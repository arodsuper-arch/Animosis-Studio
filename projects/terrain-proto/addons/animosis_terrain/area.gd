@tool
extends Node3D
## Area IDs: the first layer.
##
## Per-cell data at the layer resolution from coords.gd, painted with the same
## brush spine as everything else, and drawn as tinted quads over the ground.
##
## Drawn rather than shaded on purpose. Tinting terrain by area properly means
## sampling a layer texture inside Terrain3D's own shader; an overlay mesh gets
## the same read at a fraction of the risk, and the blockiness is honest -- it
## shows the actual cell grid the data lives on rather than a smooth lie.
##
## Storage is deliberately general. Temperature, moisture, fertility and
## corruption are the same shape: one byte per cell, per region, dirty-tracked
## by layer chunk. Area is simply the first one with a tool.

const Coords := preload("res://addons/animosis_terrain/coords.gd")

## Area cells are COARSER than the base layer cell (2 m) on purpose.
##
## A zone boundary is a decision about hundreds of metres of ground; 2 m
## precision is detail nothing ever displays, since the overlay draws at this
## same 8 m. Storing it finer cost 16x the paint time for resolution no one
## could see -- seeding five zones took 2.4 seconds at 2 m.
##
## Layers may each pick their own cell size; the only rule is that it divides
## the 128 m layer chunk evenly. 8 m gives 16 x 16 cells per chunk.
## Temperature and moisture will likely want the full 2 m.
const CELL_M := 8.0
const DRAW_STEP := CELL_M

const UNASSIGNED := 0

## How far each zone colour is pulled toward white before multiplying. Lower
## tints harder and hides more ground; higher shows more ground and separates
## the zones less.
const TINT_TOWARD_WHITE := 0.20


## One entry in the area tree. A cell stores only the leaf id -- ancestors come
## from `parent`, so a two-byte cell carries a full path.
class AreaDef:
	extends RefCounted
	var id: int
	var name: String
	var parent: int
	var colour: Color

	func _init(p_id: int, p_name: String, p_parent: int, p_colour: Color) -> void:
		id = p_id
		name = p_name
		parent = p_parent
		colour = p_colour


var registry: Dictionary = {}          ## id -> AreaDef
var selected_id: int = 1

var _extent: float = 4096.0
var _cells: int = 0
var _data: PackedByteArray            ## one byte per cell, row-major
var _terrain
var _overlay: MeshInstance3D
var _painted := false                  ## nothing drawn until something is
var _suppress_rebuild := false         ## batch a run of stamps into one rebuild


func _init() -> void:
	name = "AreaLayer"
	_seed_registry()

	_overlay = MeshInstance3D.new()
	_overlay.name = "AreaOverlay"
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	# Multiply, not alpha blend. Alpha paints a flat colour ON TOP of the ground
	# and hides its lighting and texture; multiply TINTS what is already there,
	# so every contour, shadow and material detail still reads through the zone
	# colour. It is how map overlays have always been done.
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	# No depth test. A quad is a flat patch between four sampled corners, but
	# the terrain between them is often higher, so it pierces the overlay --
	# visible as speckles of ground inside a zone. Lifting the quads stops them
	# hugging, and subdividing costs geometry for a problem that is really
	# about draw order. Drawing on top solves it outright and keeps the mesh
	# perfectly conformal. The trade is that a zone behind a hill still shows,
	# which is acceptable for an overlay that is only visible while its own
	# tool is selected.
	mat.no_depth_test = true
	mat.render_priority = 1
	_overlay.material_override = mat
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay.visible = false
	add_child(_overlay)


## Placeholder tree so there is something to paint with. Colours are chosen to
## stay distinguishable against grass and rock rather than to be pretty.
func _seed_registry() -> void:
	var defs := [
		[1, "Northern Reach", 0, Color("#7FD69A")],
		[2, "The Lowlands", 0, Color("#6FA8DC")],
		[3, "Ashfall Range", 0, Color("#E3BC5C")],
		[4, "Crossroads", 2, Color("#E5484D")],
		[5, "Quarry", 3, Color("#C77DD6")],
	]
	for d in defs:
		registry[int(d[0])] = AreaDef.new(int(d[0]), String(d[1]), int(d[2]), d[3])


func configure(terrain, extent_m: float) -> void:
	_terrain = terrain
	_extent = extent_m
	_cells = int(extent_m / CELL_M)
	_data = PackedByteArray()
	_data.resize(_cells * _cells)
	_data.fill(UNASSIGNED)
	_painted = false

	var half := extent_m * 0.5
	_overlay.custom_aabb = AABB(
		Vector3(-half, -2000.0, -half), Vector3(extent_m, 4000.0, extent_m))

	_seed_zones()


## Paints a starting arrangement so the tool shows something real on first use
## rather than an empty region that looks broken. Two of the five are nested
## inside their parents, which is the part worth being able to see.
func _seed_zones() -> void:
	var t0 := Time.get_ticks_msec()
	var e := _extent
	_suppress_rebuild = true

	# [id, centre x, centre z, radius] as fractions of the region extent.
	var stamps := [
		[1, -0.24, -0.22, 0.20],   # Northern Reach
		[2,  0.08,  0.24, 0.22],   # The Lowlands
		[3,  0.28, -0.26, 0.16],   # Ashfall Range
		[4,  0.10,  0.26, 0.06],   # Crossroads, inside the Lowlands
		[5,  0.30, -0.28, 0.05],   # Quarry, inside Ashfall
	]
	for st in stamps:
		paint(Vector3(float(st[1]) * e, 0.0, float(st[2]) * e), float(st[3]) * e, int(st[0]))

	_suppress_rebuild = false
	print("[area] seeded %d zones in %d ms" % [stamps.size(), Time.get_ticks_msec() - t0])


func path_of(id: int) -> String:
	if not registry.has(id):
		return "unassigned"
	var parts: Array[String] = []
	var cur := id
	var guard := 0
	while registry.has(cur) and guard < 8:
		parts.push_front(registry[cur].name)
		cur = registry[cur].parent
		guard += 1
	return " / ".join(parts)


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
	return _data[i] if i >= 0 else UNASSIGNED


## Circular stamp. Hard-edged by design: an area boundary is a decision, not a
## gradient, and a feathered one would store partial ids that mean nothing.
func paint(world: Vector3, radius: float, id: int) -> int:
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
		# Solve the circle per row instead of testing every cell in the square:
		# no distance test in the inner loop, and the ~21% of the square that
		# falls outside the circle is never visited.
		var span := int(sqrt(maxf(0.0, r2 - float(dz * dz))))
		var x0 := maxi(0, cx - span)
		var x1 := mini(_cells - 1, cx + span)
		var row := z * _cells
		for x in range(x0, x1 + 1):
			var i := row + x
			if _data[i] != id:
				_data[i] = id
				touched += 1

	if touched > 0:
		_painted = _painted or id != UNASSIGNED
		if not _suppress_rebuild:
			_rebuild_overlay()
	return touched


# ---------------------------------------------------------------- overlay --

func set_visible_overlay(on: bool) -> void:
	_overlay.visible = on
	if on:
		_rebuild_overlay()


func overlay_visible() -> bool:
	return _overlay.visible


func _height(x: float, z: float) -> float:
	if _terrain == null:
		return 0.0
	var data = _terrain.get("data")
	if data == null:
		return 0.0
	var h: float = data.get_height(Vector3(x, 0.0, z))
	return 0.0 if is_nan(h) else h


func _cached(lattice: PackedFloat32Array, n: int, i: int, j: int,
		half: float, step: float) -> float:
	var idx := j * (n + 1) + i
	var v := lattice[idx]
	if is_nan(v):
		v = _height(-half + i * step, -half + j * step)
		lattice[idx] = v
	return v


## Sparse: only cells with an assigned area produce geometry, so an untouched
## region costs nothing and the mesh grows with what has actually been painted.
func _rebuild_overlay() -> void:
	if not _overlay.visible or _cells <= 0:
		return

	var t0 := Time.get_ticks_msec()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var half := _extent * 0.5
	var step := DRAW_STEP
	var n := int(_extent / step)
	var lift := 0.05   # hairline, only to avoid coplanar artefacts

	# Every interior corner is shared by four quads, so sampling per quad asks
	# the same question four times. Cached on first use; NAN marks unsampled.
	var lattice := PackedFloat32Array()
	lattice.resize((n + 1) * (n + 1))
	lattice.fill(NAN)
	var queries := 0

	for j in n:
		for i in n:
			var wx := -half + i * step
			var wz := -half + j * step
			var id := at(Vector3(wx + step * 0.5, 0.0, wz + step * 0.5))
			if id == UNASSIGNED or not registry.has(id):
				continue

			# Multiply darkens by however far the colour sits from white, so the
			# swatch colour is pulled toward white to tint rather than dim. The
			# list keeps the true colour, which stays the more readable of the
			# two at swatch size.
			var col: Color = registry[id].colour.lerp(Color.WHITE, TINT_TOWARD_WHITE)
			col.a = 1.0

			var y00 := _cached(lattice, n, i, j, half, step)
			var y10 := _cached(lattice, n, i + 1, j, half, step)
			var y11 := _cached(lattice, n, i + 1, j + 1, half, step)
			var y01 := _cached(lattice, n, i, j + 1, half, step)

			var p00 := Vector3(wx, y00 + lift, wz)
			var p10 := Vector3(wx + step, y10 + lift, wz)
			var p11 := Vector3(wx + step, y11 + lift, wz + step)
			var p01 := Vector3(wx, y01 + lift, wz + step)

			for v in [p00, p10, p11, p00, p11, p01]:
				verts.append(v)
				cols.append(col)

	print("[area] overlay: %d quads, %d ms" % [verts.size() / 6, Time.get_ticks_msec() - t0])

	var mesh := ArrayMesh.new()
	if not verts.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_COLOR] = cols
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_overlay.mesh = mesh
