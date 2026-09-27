@tool
extends Node3D
## Still water, as volumes rather than as painted pixels.
##
## You paint where water is ALLOWED to be; the ground decides where it actually
## is. A cell holds water where its footprint names a body and the ground under
## it sits below that body's level, so painting up a bank simply stops at the
## shoreline. Nothing crops it, because nothing ever claimed water was there.
##
## That follows the spec rather than the tool this copies: §7 authors "Water
## volumes", §2.3 places them with "level and flow direction", and §4.4 resolves
## "water level for affected basins" whenever terrain moves. Noggit stores a
## per-chunk water mask instead, which is why it needs Crop Water, Auto Opacity
## and Regen ADT Opacity -- three controls and a maintenance step that exist
## only to re-sync data that was never derived in the first place. Here:
##
##   crop          -> ground < level, evaluated at mesh time
##   auto opacity  -> alpha from depth, per vertex
##   angled mode   -> a level profile along a course (stage two, rivers)
##   liquid layers -> two bodies can overlap; each owns its own level
##
## The level being ONE NUMBER per body is the whole point. A lake has to stay
## level. Store a height per cell and raising it means repainting every cell and
## watching them drift; store it on the body and rain, drought and season are an
## assignment.

const Coords := preload("res://addons/animosis_terrain/coords.gd")

## The footprint is COARSER than the surface it produces, and that split is
## what makes a lake affordable.
##
## The footprint answers one question -- which body owns this ground -- and the
## shoreline is not its job: that comes from `ground < level` evaluated per mesh
## cell. So the footprint can be coarse while the water's edge stays exact.
##
## It has to be, too. At 2 m a one square kilometre lake is 250,000 cells to
## flood, which measured at nearly a second; the same lake is 15,000 cells at
## 8 m. Sixteen times less work for a boundary nobody can see, because the mesh
## resolves inside it.
const FOOT_M := 8.0                      ## footprint cell -- which body
const MESH_M := Coords.LAYER_CELL_M      ## 2 m surface cell -- where the edge is
const CHUNK_M := Coords.LAYER_CHUNK_M    ## 128 m -- the meshing and dirty unit

const FOOT_PER_CHUNK := 16               ## 128 / 8
const MESH_PER_CHUNK := 64               ## 128 / 2
const MESH_PER_FOOT := 4                 ## 8 / 2

const NONE := 0

## Depth over which the surface fades from clear to full. This is the shoreline,
## and it does a second job: it hides the 2 m stair-stepping at the water's edge
## that a hard boundary would show. Noggit authors this per tile and regenerates
## it; it is a subtraction here.
const FADE_DEPTH_M := 2.6
const MAX_ALPHA := 0.80

## Hairline, only to stop the surface z-fighting the ground it meets at the
## shore, where depth is zero by definition.
const LIFT := 0.02

## A run of cells merges into one quad while the surface alpha holds within
## this. Deep water is uniformly opaque, so a whole row collapses to a single
## quad regardless of how rough the bed beneath it is -- the surface is flat, so
## unlike the passability overlay there is no geometric reason to break a run.
## Only the shallows subdivide, which is exactly where the gradient needs it.
const RUN_ALPHA_TOL := 0.10

## First-click depth. Clicking sets the shoreline at the point clicked, but on
## flat ground that produces a surface exactly level with the bed and therefore
## no water at all, which reads as the tool having done nothing. Starting a body
## slightly above the click gives something to see; Sample sets it exactly.
const INITIAL_DEPTH_M := 2.0

## Ceiling on one fill, in footprint cells. A level above every ridge would
## otherwise flood the whole region; stopping and saying so beats locking the
## editor while it happens. 120,000 cells is 7.7 km2 -- half a 4 km region.
const FILL_CELL_BUDGET := 120000


## One water volume. `level` is the surface height in world metres, and it is
## the only thing that decides where this body's water reaches.
class WaterBody:
	extends RefCounted
	var id: int
	var name: String
	var level: float
	var colour: Color
	var levelled: bool    ## false until anything has placed the surface
	## While true the level follows the lowest ground the brush has passed over,
	## so dragging across a valley settles the water into the valley instead of
	## flooding to the height of wherever the first click happened to land.
	## Touching the Level slider or Sample ends it -- once a person has stated a
	## level, nothing should move it behind their back.
	var auto_level: bool
	var lowest: float
	## Where a fill started. Kept so the basin can be found again when the level
	## moves: the shoreline of a lake is a consequence of its level, so it has to
	## be recomputed rather than dragged.
	var seed_at: Vector3
	var seeded: bool

	func _init(p_id: int, p_name: String, p_colour: Color) -> void:
		id = p_id
		name = p_name
		colour = p_colour
		level = 0.0
		levelled = false
		auto_level = true
		lowest = INF
		seed_at = Vector3.ZERO
		seeded = false


var bodies: Dictionary = {}       ## id -> WaterBody
var selected_id: int = 1

var _extent: float = 4096.0
var _cells: int = 0               ## footprint cells per side, whole region
var _chunks: int = 0              ## chunks per side
var _wet: PackedByteArray         ## 0 unknown, 1 wet, 2 dry -- per fill
var _data: PackedByteArray        ## body id per cell, row-major over the region
var _terrain
var _data_ref                     ## Terrain3D height store, resolved per remesh
var _material: StandardMaterial3D
var _meshes: Dictionary = {}
var _used: Dictionary = {}
var _dirty: Dictionary = {}
var _bounds: Dictionary = {}      ## chunk index -> Vector4i scan box
var _clat: PackedFloat32Array     ## coarse corner heights for the chunk being meshed
var _verts: PackedVector3Array    ## scratch, reused across chunks
var _cols: PackedColorArray
var _suppress := false

## Rolling estimate of one flush, in milliseconds. Same rate limiter as the
## passability layer: writes are cheap and must not be throttled, meshing is not
## and must be.
var last_op_ms: float = 1.0


func _init() -> void:
	name = "WaterLayer"
	visible = false
	_seed_bodies()

	_material = StandardMaterial3D.new()
	# Shaded, unlike the layer overlays. Those describe the ground; this is a
	# surface in the world, and a specular response off the sun is most of what
	# makes water read as water rather than as coloured glass.
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.roughness = 0.08
	_material.metallic = 0.25
	_material.metallic_specular = 0.9
	# Seen from underneath as well as above.
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Depth testing STAYS ON, unlike the area and passability overlays. Those are
	# diagrams that must be readable through a hill; this is a thing in the
	# world, and terrain in front of it has to hide it.
	_material.no_depth_test = false


## Three bodies to paint into, levels unset. Deliberately no footprints: unlike
## areas, one Shift-click produces visible water, so a seeded demo would only be
## in the way.
func _seed_bodies() -> void:
	var defs := [
		[1, "Lake", Color("#3E7FA8")],
		[2, "Pond", Color("#4E9E8F")],
		[3, "Sea", Color("#2E5F8F")],
	]
	for d in defs:
		bodies[int(d[0])] = WaterBody.new(int(d[0]), String(d[1]), d[2])


func configure(terrain, extent_m: float) -> void:
	_terrain = terrain
	_extent = extent_m
	_chunks = maxi(1, int(extent_m / CHUNK_M))
	_cells = _chunks * FOOT_PER_CHUNK

	_data = PackedByteArray()
	_data.resize(_cells * _cells)
	_data.fill(NONE)

	# Wetness memo for a fill, so each cell is sampled exactly once however many
	# times the flood reaches it. One byte per footprint cell: 256 kB for a 4 km
	# region, which is nothing next to the height lookups it saves.
	_wet = PackedByteArray()
	_wet.resize(_cells * _cells)

	_clat = PackedFloat32Array()
	_clat.resize((FOOT_PER_CHUNK + 1) * (FOOT_PER_CHUNK + 1))

	for m in _meshes.values():
		(m as Node).queue_free()
	_meshes.clear()
	_used.clear()
	_dirty.clear()
	_bounds.clear()


# ------------------------------------------------------------------ bodies --

func selected() -> WaterBody:
	return bodies.get(selected_id)


func add_body() -> int:
	var id := 1
	while bodies.has(id):
		id += 1
	if id > 255:
		push_warning("Animosis Terrain: water bodies exhausted (one byte per cell).")
		return 0
	# Hue spread rather than a fixed palette, so an arbitrary number of bodies
	# stay distinguishable without anyone choosing colours.
	var col := Color.from_hsv(fmod(0.55 + float(id) * 0.11, 1.0), 0.52, 0.66)
	bodies[id] = WaterBody.new(id, "Water %d" % id, col)
	return id


## Places the surface exactly at a height, which is what Sample does. Clicking
## uses the same path with a small offset so the first click shows something.
func set_level(id: int, y: float) -> void:
	var b: WaterBody = bodies.get(id)
	if b == null:
		return
	b.level = y
	b.levelled = true
	b.auto_level = false
	# Every chunk holding water is remeshed, not just this body's. Tracking
	# which chunks hold which body would save work only where several bodies
	# share a region, and a level drag is already bounded by the flush limiter.
	resolve_levels()


func depth_at(world: Vector3) -> float:
	var i := _index(world)
	if i < 0:
		return 0.0
	var b: WaterBody = bodies.get(_data[i])
	if b == null or not b.levelled:
		return 0.0
	_data_ref = _terrain.get("data") if _terrain != null else null
	return maxf(0.0, b.level - _height(world.x, world.z))


func label_at(world: Vector3) -> String:
	var i := _index(world)
	if i < 0 or _data[i] == NONE:
		return ""
	var b: WaterBody = bodies.get(_data[i])
	if b == null:
		return ""
	var d := depth_at(world)
	return "%s  %.1f m deep" % [b.name, d] if d > 0.0 else "%s  dry" % b.name


# ---------------------------------------------------------------- storage --

func _index(world: Vector3) -> int:
	if _cells <= 0:
		return -1
	var half := _extent * 0.5
	var cx := int(floorf((world.x + half) / FOOT_M))
	var cz := int(floorf((world.z + half) / FOOT_M))
	if cx < 0 or cz < 0 or cx >= _cells or cz >= _cells:
		return -1
	return cz * _cells + cx


func at(world: Vector3) -> int:
	var i := _index(world)
	return _data[i] if i >= 0 else NONE


## Paints the FOOTPRINT, not the water. Where the water actually lands inside
## this footprint is decided at mesh time against the ground.
func paint(world: Vector3, radius: float, id: int, flush := true) -> int:
	if _cells <= 0 or not world.is_finite():
		return 0

	# The first stamp places the surface and later stamps never move it.
	# Tracking the lowest ground the brush had passed over sounded better and was
	# worse: dragging from the shore into deeper water lowered the level, so the
	# lake shrank away from the parts already painted. A level that moves while
	# you paint is a level you cannot aim.
	var level_moved := false
	if id != NONE:
		var b: WaterBody = bodies.get(id)
		if b != null and b.auto_level and not b.levelled:
			_data_ref = _terrain.get("data") if _terrain != null else null
			b.level = _height(world.x, world.z) + INITIAL_DEPTH_M
			b.levelled = true
			level_moved = true

	var half := _extent * 0.5
	var r_cells := int(ceilf(radius / FOOT_M))
	var cx := int(floorf((world.x + half) / FOOT_M))
	var cz := int(floorf((world.z + half) / FOOT_M))

	var touched := 0
	var r2 := float(r_cells * r_cells)
	for dz in range(-r_cells, r_cells + 1):
		var z := cz + dz
		if z < 0 or z >= _cells:
			continue
		var span := int(sqrt(maxf(0.0, r2 - float(dz * dz))))
		var x0 := maxi(0, cx - span)
		var x1 := mini(_cells - 1, cx + span)
		var row := z * _cells
		for x in range(x0, x1 + 1):
			var i := row + x
			if _data[i] != id:
				_data[i] = id
				touched += 1

	if touched == 0:
		return 0

	_mark_region(
		clampi(cx - r_cells, 0, _cells - 1), clampi(cz - r_cells, 0, _cells - 1),
		clampi(cx + r_cells, 0, _cells - 1), clampi(cz + r_cells, 0, _cells - 1),
		id != NONE)

	# A level change moves the shoreline everywhere, not just under the brush.
	if level_moved:
		for ci in _used:
			_dirty[ci] = true

	if flush and not _suppress:
		_flush_dirty()
	return touched


## Floods a basin from one point, which is how a lake actually gets made.
##
## Painting a large body cell by cell is the wrong gesture twice over: it is a
## lot of dragging, and the shoreline it leaves is a union of brush circles
## rather than anything the ground decided. Water already knows its own extent --
## everything connected to here that lies below the level -- so the click only
## has to say WHICH basin, and how high.
##
## Noggit cannot offer this, because its water is a stored mask: the extent has
## to be drawn by hand there, since nothing derives it.
func fill(world: Vector3, id: int) -> int:
	if _cells <= 0 or not world.is_finite() or id == NONE:
		return 0
	var b: WaterBody = bodies.get(id)
	if b == null:
		return 0

	_data_ref = _terrain.get("data") if _terrain != null else null
	if b.auto_level and not b.levelled:
		b.level = _height(world.x, world.z) + INITIAL_DEPTH_M
		b.levelled = true
	b.seed_at = world
	b.seeded = true

	var start := _index(world)
	if start < 0:
		return 0

	_clear_body(id)

	var lvl := b.level
	_wet.fill(0)

	# Span flood fill, not four-neighbour. The naive form pushes and pops four
	# entries per cell; this one claims a whole run of a row at a time and pushes
	# one seed per contiguous run in each adjacent row, which is roughly an order
	# of magnitude fewer stack operations for the same component.
	var stack := PackedInt32Array()
	stack.push_back(start)

	var gx0 := _cells
	var gx1 := -1
	var gz0 := _cells
	var gz1 := -1
	var count := 0
	var capped := false

	while stack.size() > 0 and not capped:
		var seed := stack[stack.size() - 1]
		stack.resize(stack.size() - 1)
		var z := seed / _cells
		var sx := seed % _cells
		if _data[seed] != NONE or not _is_wet(sx, z, lvl):
			continue

		var row := z * _cells
		var xl := sx
		while xl > 0 and _data[row + xl - 1] == NONE and _is_wet(xl - 1, z, lvl):
			xl -= 1
		var xr := sx
		while xr < _cells - 1 and _data[row + xr + 1] == NONE and _is_wet(xr + 1, z, lvl):
			xr += 1

		for x in range(xl, xr + 1):
			_data[row + x] = id
		count += xr - xl + 1
		gx0 = mini(gx0, xl)
		gx1 = maxi(gx1, xr)
		gz0 = mini(gz0, z)
		gz1 = maxi(gz1, z)
		if count >= FILL_CELL_BUDGET:
			capped = true

		# Claim the dry cells that stopped the run. They render as nothing --
		# the mesh clips them against the ground -- but including them means the
		# 2 m shoreline is never cut short by an 8 m footprint edge.
		if xl > 0 and _data[row + xl - 1] == NONE:
			_data[row + xl - 1] = id
		if xr < _cells - 1 and _data[row + xr + 1] == NONE:
			_data[row + xr + 1] = id

		for adj in [z - 1, z + 1]:
			var zz := int(adj)
			if zz < 0 or zz >= _cells:
				continue
			var nrow := zz * _cells
			var x := xl
			while x <= xr:
				if _data[nrow + x] == NONE and _is_wet(x, zz, lvl):
					stack.push_back(nrow + x)
					# Skip the rest of this run: one seed per run is enough, and
					# the span expansion above will claim the whole of it.
					while x <= xr and _is_wet(x, zz, lvl):
						x += 1
				x += 1

	if capped:
		push_warning("Animosis Terrain: water fill hit its budget; the level is above the ground around it.")
	if count == 0:
		return 0

	_mark_region(gx0, gz0, gx1, gz1, true)
	_flush_dirty()
	return count


## Wetness of one footprint cell, sampled at its centre and remembered. The memo
## is what keeps a span fill from re-sampling: runs get tested from the row above
## and the row below as well as along their own.
func _is_wet(x: int, z: int, lvl: float) -> bool:
	var i := z * _cells + x
	var m := _wet[i]
	if m != 0:
		return m == 1
	var half := _extent * 0.5
	var h := _height(-half + (float(x) + 0.5) * FOOT_M,
		-half + (float(z) + 0.5) * FOOT_M)
	_wet[i] = 1 if h < lvl else 2
	return h < lvl


## Re-floods from the stored seed. The level moved, so the shoreline has to be
## found again; it was never a thing anyone drew.
func refill(id: int) -> int:
	var b: WaterBody = bodies.get(id)
	if b == null or not b.seeded:
		return 0
	return fill(b.seed_at, id)


## Erases a body wherever it currently sits, bounded by the chunks it occupies
## rather than by scanning the region.
func _clear_body(id: int) -> void:
	for ci in _used.keys():
		var lim: Vector4i = _bounds.get(ci, Vector4i(0, 0, FOOT_PER_CHUNK - 1, FOOT_PER_CHUNK - 1))
		var base_x := (int(ci) % _chunks) * FOOT_PER_CHUNK
		var base_z := (int(ci) / _chunks) * FOOT_PER_CHUNK
		var hit := false
		for j in range(lim.y, lim.w + 1):
			var row := (base_z + j) * _cells + base_x
			for i in range(lim.x, lim.z + 1):
				if _data[row + i] == id:
					_data[row + i] = NONE
					hit = true
		if hit:
			_dirty[ci] = true


## Marks every chunk overlapping a cell rectangle and widens their scan boxes.
func _mark_region(gx0: int, gz0: int, gx1: int, gz1: int, occupied: bool) -> void:
	for j in range(gz0 / FOOT_PER_CHUNK, gz1 / FOOT_PER_CHUNK + 1):
		for i in range(gx0 / FOOT_PER_CHUNK, gx1 / FOOT_PER_CHUNK + 1):
			var ci := j * _chunks + i
			_dirty[ci] = true
			if not occupied:
				continue
			_used[ci] = true
			var li0 := maxi(0, gx0 - i * FOOT_PER_CHUNK)
			var li1 := mini(FOOT_PER_CHUNK - 1, gx1 - i * FOOT_PER_CHUNK)
			var lj0 := maxi(0, gz0 - j * FOOT_PER_CHUNK)
			var lj1 := mini(FOOT_PER_CHUNK - 1, gz1 - j * FOOT_PER_CHUNK)
			var b2: Vector4i = _bounds.get(ci, Vector4i(li0, lj0, li1, lj1))
			_bounds[ci] = Vector4i(
				mini(b2.x, li0), mini(b2.y, lj0), maxi(b2.z, li1), maxi(b2.w, lj1))


## Removes a body entirely.
func clear_body(id: int) -> void:
	_clear_body(id)
	var b: WaterBody = bodies.get(id)
	if b != null:
		b.seeded = false
	_flush_dirty()


# ---------------------------------------------------------------- surface --

func set_visible_overlay(on: bool) -> void:
	visible = on
	if not on:
		return
	for ci in _used:
		_dirty[ci] = true
	_flush_dirty()


## Re-resolves every basin against the ground. Called when terrain moves
## (spec §4.4) and when a level changes -- the two things that alter where the
## water reaches without altering the footprint anyone painted.
func resolve_levels() -> void:
	for ci in _used:
		_dirty[ci] = true
	_flush_dirty()


func flush_pending() -> void:
	_flush_dirty()


func has_pending() -> bool:
	return not _dirty.is_empty()


func _flush_dirty() -> void:
	if not visible or _dirty.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	for ci in _dirty:
		_rebuild_chunk(int(ci))
	_dirty.clear()
	last_op_ms = lerpf(last_op_ms, float(Time.get_ticks_usec() - t0) / 1000.0, 0.4)


func _height(x: float, z: float) -> float:
	if _data_ref == null:
		return 0.0
	var h: float = _data_ref.get_height(Vector3(x, 0.0, z))
	return 0.0 if is_nan(h) else h


## Coarse corner heights, one row at a time, in a tight loop.
func _fill_coarse_row(j: int, i0: int, i1: int, ox: float, oz: float) -> void:
	var base := j * (FOOT_PER_CHUNK + 1)
	var wz := oz + float(j) * FOOT_M
	for i in range(i0, i1 + 1):
		_clat[base + i] = _height(ox + float(i) * FOOT_M, wz)


## Subdivides one 8 m footprint cell into 2 m surface cells. Only the shoreline
## comes through here, which is the whole reason the surface can be fine without
## the lake costing what a fine surface everywhere would.
func _emit_fine(fi: int, fj: int, ox: float, oz: float, lvl: float, c: Color) -> void:
	var bx := ox + float(fi) * FOOT_M
	var bz := oz + float(fj) * FOOT_M
	var m := MESH_PER_FOOT

	# Corners of the block, (m+1) square. Sampled per block rather than cached
	# across the chunk: neighbouring blocks re-sample a shared edge, which costs
	# a handful of lookups against the bookkeeping a chunk-wide cache would need.
	var fh := PackedFloat32Array()
	fh.resize((m + 1) * (m + 1))
	for jj in m + 1:
		var wz := bz + float(jj) * MESH_M
		var base := jj * (m + 1)
		for ii in m + 1:
			fh[base + ii] = _height(bx + float(ii) * MESH_M, wz)

	for jj in m:
		var ra := jj * (m + 1)
		var rb := ra + m + 1
		var z0 := bz + float(jj) * MESH_M
		var z1 := z0 + MESH_M
		for ii in m:
			var a00 := clampf((lvl - fh[ra + ii]) / FADE_DEPTH_M, 0.0, 1.0)
			var a10 := clampf((lvl - fh[ra + ii + 1]) / FADE_DEPTH_M, 0.0, 1.0)
			var a11 := clampf((lvl - fh[rb + ii + 1]) / FADE_DEPTH_M, 0.0, 1.0)
			var a01 := clampf((lvl - fh[rb + ii]) / FADE_DEPTH_M, 0.0, 1.0)
			if a00 <= 0.0 and a10 <= 0.0 and a11 <= 0.0 and a01 <= 0.0:
				continue
			var x0 := bx + float(ii) * MESH_M
			var x1 := x0 + MESH_M
			var y := lvl + LIFT
			_quad(Vector3(x0, y, z0), Vector3(x1, y, z0),
				Vector3(x1, y, z1), Vector3(x0, y, z1),
				Color(c.r, c.g, c.b, a00 * MAX_ALPHA),
				Color(c.r, c.g, c.b, a10 * MAX_ALPHA),
				Color(c.r, c.g, c.b, a11 * MAX_ALPHA),
				Color(c.r, c.g, c.b, a01 * MAX_ALPHA))


func _quad(p00: Vector3, p10: Vector3, p11: Vector3, p01: Vector3,
		c00: Color, c10: Color, c11: Color, c01: Color) -> void:
	_verts.push_back(p00)
	_verts.push_back(p10)
	_verts.push_back(p11)
	_verts.push_back(p00)
	_verts.push_back(p11)
	_verts.push_back(p01)
	_cols.push_back(c00)
	_cols.push_back(c10)
	_cols.push_back(c11)
	_cols.push_back(c00)
	_cols.push_back(c11)
	_cols.push_back(c01)


## Meshes one 128 m chunk of surface, coarse where it can be and fine where it
## has to be.
##
## Almost all of a lake is deeper than the fade, where the surface is uniformly
## opaque and a 2 m grid buys nothing but work: those cells mesh at the 8 m
## footprint and merge into runs, so a chunk of open water is a handful of quads
## off 289 height samples. Only blocks straddling the shoreline subdivide, and
## they are the thin ring where the detail is actually visible.
##
## Meshing the whole surface at 2 m cost 4096 cell tests and 4225 height samples
## per chunk regardless of what was in it, which made a square kilometre of lake
## take seconds.
func _rebuild_chunk(ci: int) -> void:
	if _chunks <= 0:
		return
	var fn := FOOT_PER_CHUNK
	var base_fx := (ci % _chunks) * fn
	var base_fz := (ci / _chunks) * fn
	var half := _extent * 0.5
	var ox := -half + float(base_fx) * FOOT_M
	var oz := -half + float(base_fz) * FOOT_M

	var lim: Vector4i = _bounds.get(ci, Vector4i(0, 0, fn - 1, fn - 1))

	_data_ref = _terrain.get("data") if _terrain != null else null
	_verts = PackedVector3Array()
	_cols = PackedColorArray()

	var filled := PackedByteArray()
	filled.resize(fn + 1)
	filled.fill(0)

	for fj in range(lim.y, lim.w + 1):
		if filled[fj] == 0:
			_fill_coarse_row(fj, lim.x, lim.z + 1, ox, oz)
			filled[fj] = 1
		if filled[fj + 1] == 0:
			_fill_coarse_row(fj + 1, lim.x, lim.z + 1, ox, oz)
			filled[fj + 1] = 1

		var frow := (base_fz + fj) * _cells + base_fx
		var ca := fj * (fn + 1)
		var cb := ca + fn + 1
		var z0 := oz + float(fj) * FOOT_M
		var z1 := z0 + FOOT_M

		var fi := lim.x
		while fi <= lim.z:
			var sid := _data[frow + fi]
			if sid == NONE:
				fi += 1
				continue
			var body: WaterBody = bodies.get(sid)
			if body == null or not body.levelled:
				fi += 1
				continue

			var lvl := body.level
			var hi := maxf(maxf(_clat[ca + fi], _clat[ca + fi + 1]),
				maxf(_clat[cb + fi], _clat[cb + fi + 1]))
			var lo := minf(minf(_clat[ca + fi], _clat[ca + fi + 1]),
				minf(_clat[cb + fi], _clat[cb + fi + 1]))

			if lvl - lo <= 0.0:
				# Entirely above the surface: inside the footprint, on dry land.
				fi += 1
				continue

			if lvl - hi <= FADE_DEPTH_M:
				# Straddles the shoreline, so this block earns its 2 m cells.
				_emit_fine(fi, fj, ox, oz, lvl, body.colour)
				fi += 1
				continue

			# Open water. Merge every following block that is also open water of
			# the same body: alpha is saturated across all of them, so a run is
			# exact rather than approximate.
			var k := fi + 1
			while k <= lim.z and _data[frow + k] == sid:
				var khi := maxf(maxf(_clat[ca + k], _clat[ca + k + 1]),
					maxf(_clat[cb + k], _clat[cb + k + 1]))
				if lvl - khi <= FADE_DEPTH_M:
					break
				k += 1

			var c := body.colour
			var full := Color(c.r, c.g, c.b, MAX_ALPHA)
			var x0 := ox + float(fi) * FOOT_M
			var x1 := ox + float(k) * FOOT_M
			var y := lvl + LIFT
			_quad(Vector3(x0, y, z0), Vector3(x1, y, z0),
				Vector3(x1, y, z1), Vector3(x0, y, z1),
				full, full, full, full)
			fi = k

	var verts := _verts
	var cols := _cols
	if verts.is_empty():
		var spare: MeshInstance3D = _meshes.get(ci)
		if spare != null:
			spare.mesh = null
		return

	# Normals, which the surface was missing. Without them a shaded material has
	# no direction to light and the water rendered as a flat pale sheet -- most
	# of what made it read as a plate hanging over the ground rather than as a
	# surface lying in it. Every one points up, because the surface is level.
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	norms.fill(Vector3.UP)

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_chunk_node(ci).mesh = mesh
