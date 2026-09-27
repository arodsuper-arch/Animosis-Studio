@tool
extends Node3D
## Passability overrides: where movement is decided by an author, not the ground.
##
## Passability is normally DERIVED -- slope from the heightmap, surface from the
## material, depth from water -- and derived data cannot go stale, because there
## is nothing stored to go stale. This layer holds only the exceptions someone
## states outright: the map boundary, the region that is not built yet, the
## stair whose geometry reads as too steep but is meant to be climbed.
##
## That default is the whole difference from the tool this copies. Noggit paints
## one `impass` bit per ~33 m chunk, hand-maintained and disconnected from the
## terrain under it, so flattening a mountain leaves its invisible wall standing
## and raising a cliff blocks nothing until somebody remembers. Here the ground
## answers by default and only deliberate exceptions are recorded, so the common
## case maintains itself.
##
## Whether a cell can be crossed is still not one answer: a goat climbs scree a
## handcart cannot. Derivation is therefore per locomotion capability. An
## override outranks it for every capability alike, which is what "the author
## said so" has to mean to be worth having.
##
## Derivation itself is not built yet. It is a full-region job -- roughly four
## million cells -- so it belongs in a yielding background pass like the contour
## builder in grid.gd, not in this file's paint path.

const Coords := preload("res://addons/animosis_terrain/coords.gd")

## Full layer resolution, unlike the area layer's 8 m. A zone boundary off by
## four metres is invisible; a wall off by four metres is a wall you clip the
## corner of. This is the layer that has to be right at body scale.
const CELL_M := Coords.LAYER_CELL_M      ## 2 m
const CHUNK_M := Coords.LAYER_CHUNK_M    ## 128 m -- the meshing and dirty unit

enum State {
	DERIVED,   ## ask the ground; the default, and almost every cell forever
	BLOCKED,   ## impassable no matter what the ground says
	OPEN,      ## passable no matter what the ground says
}

## Additive, not multiplied like the area overlay. Multiply tints by darkening,
## which cannot produce a white highlight at all -- white multiplies to nothing.
## Add brightens by the same logic in the opposite direction: the ground's own
## lighting, texture and contours still read through, they just read lighter.
const BLOCKED_TINT := Color(0.34, 0.36, 0.44)   ## cold white
const OPEN_TINT := Color(0.06, 0.30, 0.14)      ## green

const LIFT := 0.05

## A run of cells merges into one quad only while the ground under it stays flat
## within this. One quad is a plane between four corners, so merging across a
## slope would float it off the surface; merging across flat ground is free.
## Flat regions collapse to a few strips, cliffs fall back to per-cell and keep
## hugging. The tolerance is the entire trade, in one number.
const RUN_FLAT_TOL_M := 1.0


## Which override Shift paints. Ctrl always clears back to DERIVED, so the two
## modifiers keep the same add/remove meaning every other tool gives them and
## the third state costs no extra binding.
var paint_state: int = State.BLOCKED

var _extent: float = 4096.0
var _cells: int = 0            ## per side, whole region
var _chunk_cells: int = 0      ## per side, per chunk -- 64
var _chunks: int = 0           ## per side -- 32
var _data: PackedByteArray     ## one byte per cell, row-major over the region
var _terrain
var _material: StandardMaterial3D
var _meshes: Dictionary = {}   ## chunk index -> MeshInstance3D
var _used: Dictionary = {}     ## chunk index -> true, once anything is painted
var _dirty: Dictionary = {}    ## chunk index -> true, awaiting a remesh
## chunk index -> Vector4i(i0, j0, i1, j1), the cells within that chunk that
## have ever held an override. A remesh scans only this box, so a brush that
## clips one corner of a chunk does not cost a scan of all 4096 cells in it.
## It only ever grows: shrinking it on a clear would mean tracking what is left,
## and a slightly wide scan is cheaper than being exact.
var _bounds: Dictionary = {}
var _lat: PackedFloat32Array   ## scratch corner heights for the chunk being meshed
## Terrain3D's height store, resolved once per remesh. Reaching through
## _terrain.get("data") per sample cost more than the sample: a chunk asks for
## up to 4225 corners, and that was 4225 Variant property lookups on the way to
## 4225 height reads.
var _data_ref
var _suppress := false

## Rolling estimate of what one flush costs, in milliseconds. Writing cells is
## cheap and roughly free of the brush size; remeshing the chunks those writes
## touched is neither -- measured 0.9 ms per chunk at radius 20 and 7.5 ms at
## radius 200, which at a large brush is 186 ms of blocked main thread per
## stamp. The rate limiter is driven by this real number rather than a formula
## guessed from the radius, so it follows the brush and the machine.
var last_op_ms: float = 1.0


func _init() -> void:
	name = "PassabilityLayer"
	visible = false

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.disable_receive_shadows = true
	# Same reasoning as the area overlay: a quad spans four sampled corners and
	# the ground between them is often higher, so it pierces through as speckle.
	# Drawing on top is the only fix that keeps the mesh perfectly conformal.
	_material.no_depth_test = true
	_material.render_priority = 2


func configure(terrain, extent_m: float) -> void:
	_terrain = terrain
	_extent = extent_m
	_chunk_cells = int(CHUNK_M / CELL_M)
	_chunks = maxi(1, int(extent_m / CHUNK_M))
	_cells = _chunks * _chunk_cells

	_data = PackedByteArray()
	_data.resize(_cells * _cells)
	_data.fill(State.DERIVED)

	_lat = PackedFloat32Array()
	_lat.resize((_chunk_cells + 1) * (_chunk_cells + 1))

	for m in _meshes.values():
		(m as Node).queue_free()
	_meshes.clear()
	_used.clear()
	_dirty.clear()
	_bounds.clear()

	_seed_demo()


## Two small patches so the tool shows something real the first time it opens.
## Deliberately small and obviously placed: unlike areas, an override means
## "a person decided this", and seeding a plausible-looking set of them would
## be inventing decisions nobody made.
func _seed_demo() -> void:
	_suppress = true
	paint(Vector3(-_extent * 0.06, 0.0, -_extent * 0.04), 90.0, State.BLOCKED)
	paint(Vector3(_extent * 0.05, 0.0, _extent * 0.03), 55.0, State.OPEN)
	_suppress = false


# ---------------------------------------------------------------- storage --

func _index(world: Vector3) -> int:
	if _cells <= 0:
		return -1
	var half := _extent * 0.5
	var cx := int(floorf((world.x + half) / CELL_M))
	var cz := int(floorf((world.z + half) / CELL_M))
	if cx < 0 or cz < 0 or cx >= _cells or cz >= _cells:
		return -1
	return cz * _cells + cx


func at(world: Vector3) -> int:
	var i := _index(world)
	return _data[i] if i >= 0 else State.DERIVED


func label_at(world: Vector3) -> String:
	match at(world):
		State.BLOCKED:
			return "blocked"
		State.OPEN:
			return "forced open"
		_:
			return "derived"


## Circular stamp, hard-edged. A partial override is not a thing: either the
## author overrode this cell or the ground still answers for it.
##
## `flush` separates the two halves of a stamp. Writing cells costs a fraction
## of a millisecond and must happen on every cursor move or the stroke leaves
## gaps; rebuilding the meshes costs up to two hundred and only has to happen
## often enough to look live. A drag writes with `flush` false and flushes on a
## timer, which is what keeps a wide brush from dropping the frame rate without
## dropping any of the stroke.
func paint(world: Vector3, radius: float, state: int, flush := true) -> int:
	if _cells <= 0 or not world.is_finite():
		return 0
	var half := _extent * 0.5
	var r_cells := int(ceilf(radius / CELL_M))
	var cx := int(floorf((world.x + half) / CELL_M))
	var cz := int(floorf((world.z + half) / CELL_M))

	var touched := 0
	var r2 := float(r_cells * r_cells)
	for dz in range(-r_cells, r_cells + 1):
		var z := cz + dz
		if z < 0 or z >= _cells:
			continue
		# Solve the circle per row rather than testing every cell in the square.
		var span := int(sqrt(maxf(0.0, r2 - float(dz * dz))))
		var x0 := maxi(0, cx - span)
		var x1 := mini(_cells - 1, cx + span)
		var row := z * _cells
		for x in range(x0, x1 + 1):
			var i := row + x
			if _data[i] != state:
				_data[i] = state
				touched += 1

	if touched == 0:
		return 0

	# Dirty by chunk rather than by cell: one dictionary write per chunk instead
	# of one per cell, and the brush bounding box over-marks by at most a corner.
	var gx0 := clampi(cx - r_cells, 0, _cells - 1)
	var gx1 := clampi(cx + r_cells, 0, _cells - 1)
	var gz0 := clampi(cz - r_cells, 0, _cells - 1)
	var gz1 := clampi(cz + r_cells, 0, _cells - 1)
	for j in range(gz0 / _chunk_cells, gz1 / _chunk_cells + 1):
		for i in range(gx0 / _chunk_cells, gx1 / _chunk_cells + 1):
			var ci := j * _chunks + i
			_dirty[ci] = true
			if state == State.DERIVED:
				continue
			_used[ci] = true
			# Widen this chunk's scan box by the part of the brush inside it.
			var li0 := maxi(0, gx0 - i * _chunk_cells)
			var li1 := mini(_chunk_cells - 1, gx1 - i * _chunk_cells)
			var lj0 := maxi(0, gz0 - j * _chunk_cells)
			var lj1 := mini(_chunk_cells - 1, gz1 - j * _chunk_cells)
			var b: Vector4i = _bounds.get(ci, Vector4i(li0, lj0, li1, lj1))
			_bounds[ci] = Vector4i(
				mini(b.x, li0), mini(b.y, lj0), maxi(b.z, li1), maxi(b.w, lj1))

	if flush and not _suppress:
		_flush_dirty()
	return touched


# ---------------------------------------------------------------- overlay --

## Heights are resampled on every open rather than cached between them, so a
## sculpt session in another tool cannot leave the overlay floating above ground
## it no longer matches. The cost is bounded by what has actually been painted.
func set_visible_overlay(on: bool) -> void:
	visible = on
	if not on:
		return
	for ci in _used:
		_dirty[ci] = true
	_flush_dirty()


func overlay_visible() -> bool:
	return visible


## Rebuilds every chunk waiting on one. Public so a drag can hold writes and
## pay for the meshing on its own schedule.
func flush_pending() -> void:
	_flush_dirty()


func has_pending() -> bool:
	return not _dirty.is_empty()


func _flush_dirty() -> void:
	if not visible or _dirty.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	var count := _dirty.size()
	for ci in _dirty:
		_rebuild_chunk(int(ci))
	_dirty.clear()
	# Weighted toward recent samples: the radius can change mid-stroke and the
	# estimate has to follow it quickly.
	last_op_ms = lerpf(last_op_ms, float(Time.get_ticks_usec() - t0) / 1000.0, 0.4)
	# Only worth reporting for a batch; a drag remeshes one or two chunks per
	# stamp and would otherwise flood the log.
	if count > 8:
		print("[pass] %d chunks in %.0f ms"
			% [count, float(Time.get_ticks_usec() - t0) / 1000.0])


func _height(x: float, z: float) -> float:
	if _data_ref == null:
		return 0.0
	var h: float = _data_ref.get_height(Vector3(x, 0.0, z))
	return 0.0 if is_nan(h) else h


## Samples one whole row of the corner lattice in a tight loop.
##
## The previous shape asked for corners one at a time, behind a function call
## and a NAN test. That is tens of thousands of GDScript calls per remesh, and
## measuring showed the call overhead -- not the height lookup it guarded --
## was most of the cost. Filling a row at a time turns the cell loop below into
## nothing but array reads, and each corner is still sampled exactly once.
func _fill_lat_row(j: int, i0: int, i1: int, ox: float, oz: float) -> void:
	var base := j * (_chunk_cells + 1)
	var wz := oz + float(j) * CELL_M
	for i in range(i0, i1 + 1):
		_lat[base + i] = _height(ox + float(i) * CELL_M, wz)


func _chunk_node(ci: int) -> MeshInstance3D:
	var mi: MeshInstance3D = _meshes.get(ci)
	if mi != null:
		return mi
	mi = MeshInstance3D.new()
	mi.name = "PassChunk%d" % ci
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The mesh is flat in XZ but spans the full height range of the ground under
	# it, which Godot cannot infer cheaply from the vertices alone.
	var half := _extent * 0.5
	mi.custom_aabb = AABB(
		Vector3(-half + float(ci % _chunks) * CHUNK_M, -2000.0,
			-half + float(ci / _chunks) * CHUNK_M),
		Vector3(CHUNK_M, 4000.0, CHUNK_M))
	add_child(mi)
	_meshes[ci] = mi
	return mi


## Meshes one 128 m chunk. Chunking is the whole reason this layer can live at
## 2 m: a stamp touches a handful of chunks, so the cost of a stroke is set by
## the brush rather than by the size of the region. Rebuilding the whole region
## per stamp is what made the 8 m area overlay cost two seconds a click.
func _rebuild_chunk(ci: int) -> void:
	if _chunks <= 0:
		return
	var base_x := (ci % _chunks) * _chunk_cells
	var base_z := (ci / _chunks) * _chunk_cells
	var half := _extent * 0.5
	var ox := -half + float(base_x) * CELL_M
	var oz := -half + float(base_z) * CELL_M
	var n := _chunk_cells
	# Only the part of the chunk that has ever held an override is scanned.
	var lim: Vector4i = _bounds.get(ci, Vector4i(0, 0, n - 1, n - 1))

	_data_ref = _terrain.get("data") if _terrain != null else null
	var filled := PackedByteArray()
	filled.resize(n + 1)
	filled.fill(0)

	var verts := PackedVector3Array()
	var cols := PackedColorArray()

	for j in range(lim.y, lim.w + 1):
		# A cell needs the corner rows above and below it, and every row but the
		# first is already the one the previous cell row asked for.
		if filled[j] == 0:
			_fill_lat_row(j, lim.x, lim.z + 1, ox, oz)
			filled[j] = 1
		if filled[j + 1] == 0:
			_fill_lat_row(j + 1, lim.x, lim.z + 1, ox, oz)
			filled[j + 1] = 1

		var row := (base_z + j) * _cells + base_x
		var la := j * (n + 1)          # lattice row for corner j
		var lb := la + n + 1           # lattice row for corner j + 1
		var z0 := oz + float(j) * CELL_M
		var z1 := z0 + CELL_M

		var i := lim.x
		while i <= lim.z:
			var s := _data[row + i]
			if s == State.DERIVED:
				i += 1
				continue

			var y00 := _lat[la + i]
			var y01 := _lat[lb + i]
			var ra := _lat[la + i + 1]
			var rb := _lat[lb + i + 1]
			var lo := minf(minf(y00, y01), minf(ra, rb))
			var hi := maxf(maxf(y00, y01), maxf(ra, rb))

			# k is one past the end of the run. It starts at a single cell and
			# grows while the state holds and the ground stays flat enough that
			# one quad still sits on it.
			var k := i + 1
			while k <= lim.z and _data[row + k] == s:
				var a := _lat[la + k + 1]
				var b := _lat[lb + k + 1]
				if maxf(hi, maxf(a, b)) - minf(lo, minf(a, b)) > RUN_FLAT_TOL_M:
					break
				lo = minf(lo, minf(a, b))
				hi = maxf(hi, maxf(a, b))
				k += 1

			var col: Color = BLOCKED_TINT if s == State.BLOCKED else OPEN_TINT
			var x0 := ox + float(i) * CELL_M
			var x1 := ox + float(k) * CELL_M
			var p00 := Vector3(x0, y00 + LIFT, z0)
			var p10 := Vector3(x1, _lat[la + k] + LIFT, z0)
			var p11 := Vector3(x1, _lat[lb + k] + LIFT, z1)
			var p01 := Vector3(x0, y01 + LIFT, z1)
			# Written out rather than looped over a literal array. The loop form
			# allocated a six-element Array per quad, thousands of them per
			# remesh, for syntax that reads no better.
			verts.push_back(p00)
			verts.push_back(p10)
			verts.push_back(p11)
			verts.push_back(p00)
			verts.push_back(p11)
			verts.push_back(p01)
			cols.push_back(col)
			cols.push_back(col)
			cols.push_back(col)
			cols.push_back(col)
			cols.push_back(col)
			cols.push_back(col)

			i = k

	if verts.is_empty():
		var spare: MeshInstance3D = _meshes.get(ci)
		if spare != null:
			spare.mesh = null
		_used.erase(ci)
		_bounds.erase(ci)
		return

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_chunk_node(ci).mesh = mesh
