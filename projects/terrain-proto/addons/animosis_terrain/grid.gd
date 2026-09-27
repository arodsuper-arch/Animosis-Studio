@tool
extends Node3D
## Grid overlay showing where data actually lives.
##
## Four independent levels, because they answer different questions:
##
##   Region        where this authored unit ends
##   Render chunk  what re-uploads when you sculpt
##   Layer chunk   what ticks, and what a network delta names
##   Cells         one per terrain vertex, for reading individual values
##
## Lines follow the surface rather than floating on a plane, so the grid reads
## correctly on slopes. That costs a height query per sample, so meshes are
## built ONCE per toggle rather than per frame, and the cell grid is confined to
## a small window around the cursor -- a whole region of 2 m cells is four
## million lines and would never be legible anyway.

const Coords := preload("res://addons/animosis_terrain/coords.gd")

const RENDER_CHUNK_M_REF := 512.0
const LAYER_CHUNK_M_REF := 128.0

enum Level { REGION, RENDER_CHUNK, LAYER_CHUNK, CELL, CONTOUR }

const COLOURS := {
	Level.REGION:       Color("#E5484D"),
	Level.RENDER_CHUNK: Color("#6FA8DC"),
	Level.LAYER_CHUNK:  Color("#7FD69A"),
	Level.CELL:         Color(1, 1, 1, 0.22),
	Level.CONTOUR:      Color("#E3BC5C"),
}

## Contours every 10 m of elevation, sampled on a 16 m lattice. Finer sampling
## buys detail nobody reads at this scale and costs a height query per point
## across the whole region.
const CONTOUR_INTERVAL := 10.0
const CONTOUR_SAMPLE := 16.0

## Spacing of the next level up. A line that coincides with a coarser grid is
## skipped, so every line belongs to exactly one level -- otherwise the finer
## grid draws over all the coarser ones (4096, 512, 128 and 2 all divide) and
## they look like they replace each other instead of nesting.
const COARSER := {
	Level.RENDER_CHUNK: 0.0,                   ## region extent, filled at runtime
	Level.LAYER_CHUNK:  RENDER_CHUNK_M_REF,
	Level.CELL:         LAYER_CHUNK_M_REF,
}

## Metres between height samples along a line. Fine enough to hug terrain,
## coarse enough that a full region stays affordable.
const SAMPLE_STEP := 8.0
const LIFT := 0.5

## Half-width of the cell window around the cursor, in cells.
const CELL_WINDOW := 24

var _terrain
var _extent: float = 4096.0
var _layers: Dictionary = {}       ## Level -> MeshInstance3D
var _enabled: Dictionary = {}
var _cell_anchor := Vector2i(999999, 999999)


func _init() -> void:
	name = "GridOverlay"
	for level in Level.values():
		var mi := MeshInstance3D.new()
		mi.mesh = ImmediateMesh.new()
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = COLOURS[level]
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.disable_receive_shadows = true
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		_layers[level] = mi
		_enabled[level] = false


func configure(terrain, extent_m: float) -> void:
	_terrain = terrain
	_extent = extent_m
	_apply_bounds()
	# The region border is context you always want, not a decision. It costs two
	# lines per axis and answers "where does this authored unit end", which is
	# never not worth knowing.
	set_level(Level.REGION, true)


## An ImmediateMesh built at runtime reports no useful AABB, so the renderer
## frustum-culls it as soon as the camera looks away from its origin -- which
## for a 4 km grid is almost always. A custom AABB spanning the region fixes it.
## The brush ring escapes this only because it is small and always under the
## cursor.
func _apply_bounds() -> void:
	var half := _extent * 0.5
	var box := AABB(Vector3(-half, -2000.0, -half), Vector3(_extent, 4000.0, _extent))
	for level in _layers:
		var mi: MeshInstance3D = _layers[level]
		mi.custom_aabb = box


func is_enabled(level: int) -> bool:
	return _enabled.get(level, false)


func set_level(level: int, on: bool) -> void:
	_enabled[level] = on
	var mi: MeshInstance3D = _layers[level]
	mi.visible = on
	if not on:
		return
	if level == Level.CONTOUR:
		_rebuild_contours()
	elif level != Level.CELL:
		_rebuild(level)


## Terrain changed under us; anything visible has to be redrawn.
func refresh() -> void:
	for level in _layers:
		if not _enabled.get(level, false):
			continue
		if level == Level.CONTOUR:
			_rebuild_contours()
		elif level != Level.CELL:
			_rebuild(level)
	_cell_anchor = Vector2i(999999, 999999)


func _height(x: float, z: float) -> float:
	if _terrain == null:
		return 0.0
	var data = _terrain.get("data")
	if data == null:
		return 0.0
	var h: float = data.get_height(Vector3(x, 0.0, z))
	return 0.0 if is_nan(h) else h


## Contours need the truth about missing data. _height() substitutes 0 for NaN,
## which is harmless for a grid line but invents a cliff from 0 up to real
## terrain and fabricates every contour level in between.
func _height_raw(x: float, z: float) -> float:
	if _terrain == null:
		return NAN
	var data = _terrain.get("data")
	if data == null:
		return NAN
	return data.get_height(Vector3(x, 0.0, z))


func _spacing(level: int) -> float:
	match level:
		Level.REGION: return _extent
		Level.RENDER_CHUNK: return Coords.RENDER_CHUNK_M
		Level.LAYER_CHUNK: return Coords.LAYER_CHUNK_M
		_: return Coords.LAYER_CELL_M


func _rebuild(level: int) -> void:
	var mi: MeshInstance3D = _layers[level]
	var mesh: ImmediateMesh = mi.mesh
	mesh.clear_surfaces()

	var step := _spacing(level)
	var half := _extent * 0.5
	var lines := int(_extent / step) + 1
	if lines < 2 or lines > 200:
		return

	var coarser: float = COARSER.get(level, 0.0)
	if level == Level.RENDER_CHUNK:
		coarser = _extent

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var drawn := 0
	for i in lines:
		var at := -half + float(i) * step
		if coarser > 0.0 and is_zero_approx(fmod(at + half, coarser)):
			continue   # belongs to a coarser level
		_strip(mesh, Vector2(at, -half), Vector2(at, half))
		_strip(mesh, Vector2(-half, at), Vector2(half, at))
		drawn += 1
	mesh.surface_end()
	print("[grid] level %d: %d lines at %.0f m spacing" % [level, drawn * 2, step])


## A line segment, sampled along its length so it hugs the surface.
func _strip(mesh: ImmediateMesh, from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	var steps := maxi(1, int(length / SAMPLE_STEP))
	var prev := Vector3.INF
	for i in steps + 1:
		var t := float(i) / float(steps)
		var p := from.lerp(to, t)
		var v := Vector3(p.x, _height(p.x, p.y) + LIFT, p.y)
		if prev.is_finite():
			mesh.surface_add_vertex(prev)
			mesh.surface_add_vertex(v)
		prev = v


## Topographic contours by marching squares over a sampled height lattice.
##
## Built across frames rather than in one call. The first version looped every
## contour level over every cell -- 256x256 cells x ~14 levels, near a million
## GDScript iterations -- and froze the editor for seconds. Two fixes:
##
##   * cells outer, levels inner, bounded by the cell's own min/max. A 16 m cell
##     spans a few metres of height, so it can cross at most one contour. This
##     removes ~95% of the work rather than making it faster.
##   * yield periodically, so a long build never blocks input.
##
## A generation counter cancels an in-flight build if the toggle flips again.
var _contour_gen: int = 0

func _rebuild_contours() -> void:
	_contour_gen += 1
	_build_contours(_contour_gen)


func _build_contours(gen: int) -> void:
	var mi: MeshInstance3D = _layers[Level.CONTOUR]
	var mesh: ImmediateMesh = mi.mesh
	mesh.clear_surfaces()
	if _terrain == null:
		return

	var t0 := Time.get_ticks_msec()
	var half := _extent * 0.5
	var n := int(_extent / CONTOUR_SAMPLE)
	if n < 2 or n > 512:
		return

	# --- sample the lattice once ---
	var h := PackedFloat32Array()
	h.resize((n + 1) * (n + 1))
	var lo := INF
	var hi := -INF
	for j in n + 1:
		for i in n + 1:
			var v: float = _height_raw(-half + i * CONTOUR_SAMPLE, -half + j * CONTOUR_SAMPLE)
			h[j * (n + 1) + i] = v
			if not is_nan(v):
				lo = minf(lo, v)
				hi = maxf(hi, v)
		if j % 32 == 0:
			await Engine.get_main_loop().process_frame
			if gen != _contour_gen or not _enabled.get(Level.CONTOUR, false):
				return

	if not is_finite(lo) or hi - lo < CONTOUR_INTERVAL:
		return

	# --- march, visiting each cell once ---
	var verts := PackedVector3Array()
	var w := n + 1
	for j in n:
		for i in n:
			var a: float = h[j * w + i]
			var b: float = h[j * w + i + 1]
			var c: float = h[(j + 1) * w + i + 1]
			var d: float = h[(j + 1) * w + i]

			# A cell touching missing data has no honest contour through it.
			if is_nan(a) or is_nan(b) or is_nan(c) or is_nan(d):
				continue

			var cell_lo: float = minf(minf(a, b), minf(c, d))
			var cell_hi: float = maxf(maxf(a, b), maxf(c, d))

			# Only the levels this cell can actually cross.
			var first := ceilf(cell_lo / CONTOUR_INTERVAL) * CONTOUR_INTERVAL
			var level_h := first
			while level_h <= cell_hi:
				_cell_contour(verts, a, b, c, d, i, j, half, level_h)
				level_h += CONTOUR_INTERVAL
		if j % 32 == 0:
			await Engine.get_main_loop().process_frame
			if gen != _contour_gen or not _enabled.get(Level.CONTOUR, false):
				return

	if verts.is_empty():
		return

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for v in verts:
		mesh.surface_add_vertex(v)
	mesh.surface_end()

	print("[grid] contours: %d segments, %.0f-%.0f m every %.0f m -- %d ms" % [
		verts.size() / 2, lo, hi, CONTOUR_INTERVAL, Time.get_ticks_msec() - t0])


## One marching-squares cell. Finds where the contour crosses each edge and
## joins the crossings. Two crossings is the common case; four is a saddle,
## where either pairing is defensible and we take them in order.
func _cell_contour(verts: PackedVector3Array, a: float, b: float, c: float, d: float,
		i: int, j: int, half: float, level_h: float) -> void:
	# Written without temporary arrays on purpose. Allocating two typed Arrays
	# per cell, across tens of thousands of cells, cost more than the maths did.
	var cx := 0
	var x0 := 0.0
	var y0 := 0.0
	var x1 := 0.0
	var y1 := 0.0
	var x2 := 0.0
	var y2 := 0.0
	var x3 := 0.0
	var y3 := 0.0

	# top: (i,j) -> (i+1,j)
	if (a < level_h) != (b < level_h):
		var t: float = (level_h - a) / (b - a)
		x0 = i + t; y0 = j; cx += 1
	# right: (i+1,j) -> (i+1,j+1)
	if (b < level_h) != (c < level_h):
		var t: float = (level_h - b) / (c - b)
		if cx == 0: x0 = i + 1; y0 = j + t
		else: x1 = i + 1; y1 = j + t
		cx += 1
	# bottom: (i+1,j+1) -> (i,j+1)
	if (c < level_h) != (d < level_h):
		var t: float = (level_h - c) / (d - c)
		if cx == 0: x0 = i + 1 - t; y0 = j + 1
		elif cx == 1: x1 = i + 1 - t; y1 = j + 1
		else: x2 = i + 1 - t; y2 = j + 1
		cx += 1
	# left: (i,j+1) -> (i,j)
	if (d < level_h) != (a < level_h):
		var t: float = (level_h - d) / (a - d)
		if cx == 0: x0 = i; y0 = j + 1 - t
		elif cx == 1: x1 = i; y1 = j + 1 - t
		elif cx == 2: x2 = i; y2 = j + 1 - t
		else: x3 = i; y3 = j + 1 - t
		cx += 1

	if cx < 2:
		return

	verts.append(Vector3(-half + x0 * CONTOUR_SAMPLE, level_h + LIFT, -half + y0 * CONTOUR_SAMPLE))
	verts.append(Vector3(-half + x1 * CONTOUR_SAMPLE, level_h + LIFT, -half + y1 * CONTOUR_SAMPLE))

	# Four crossings is a saddle; either pairing is defensible, take them in order.
	if cx == 4:
		verts.append(Vector3(-half + x2 * CONTOUR_SAMPLE, level_h + LIFT, -half + y2 * CONTOUR_SAMPLE))
		verts.append(Vector3(-half + x3 * CONTOUR_SAMPLE, level_h + LIFT, -half + y3 * CONTOUR_SAMPLE))


## The cell grid tracks the cursor. Rebuilt only when the cursor crosses into a
## new cell, not every frame.
func update_cells(world: Vector3) -> void:
	if not _enabled.get(Level.CELL, false) or not world.is_finite():
		return

	var cell := Vector2i(
		int(floorf(world.x / Coords.LAYER_CELL_M)),
		int(floorf(world.z / Coords.LAYER_CELL_M))
	)
	if cell == _cell_anchor:
		return
	_cell_anchor = cell

	var mi: MeshInstance3D = _layers[Level.CELL]
	var mesh: ImmediateMesh = mi.mesh
	mesh.clear_surfaces()

	var c := Coords.LAYER_CELL_M
	var lo := Vector2((cell.x - CELL_WINDOW) * c, (cell.y - CELL_WINDOW) * c)
	var hi := Vector2((cell.x + CELL_WINDOW) * c, (cell.y + CELL_WINDOW) * c)

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in CELL_WINDOW * 2 + 1:
		var at := lo.x + float(i) * c
		if not is_zero_approx(fmod(at, Coords.LAYER_CHUNK_M)):
			_strip(mesh, Vector2(at, lo.y), Vector2(at, hi.y))
		var az := lo.y + float(i) * c
		if not is_zero_approx(fmod(az, Coords.LAYER_CHUNK_M)):
			_strip(mesh, Vector2(lo.x, az), Vector2(hi.x, az))
	mesh.surface_end()
