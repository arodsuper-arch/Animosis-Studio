@tool
extends Control
## Top-down view of the region, and the surface the border is edited on.
##
## A border is a decision about the whole region, and the 3D view is the wrong
## place to make it: from inside a 4 km region you cannot see the shape you are
## drawing. This is the view that shows the decision being made.
##
## The map is rendered rather than captured. Sampling the heightmap directly and
## shading it gives a readable map at a fixed cost that does not depend on what
## the camera is doing, and it works while the 3D view is showing something
## else entirely.

signal border_changed()
signal hovered(world: Vector2)

## Samples per side. 160 over a 4 km region is 26 m per pixel -- coarse for
## terrain, but a border is a decision about hundreds of metres and the map only
## has to show where the ground is high.
const SAMPLES := 160

## How close a click has to land, in PIXELS, to grab a corner or an edge. In
## pixels rather than metres because it is a question about the pointer.
const GRAB_PX := 7.0

const HANDLE_PX := 3.5

## Elevation ramp. Not a heightmap in grey: a map reads faster when low ground
## and high ground are different colours, and the border is being placed
## relative to the terrain rather than to absolute heights.
const RAMP := [
	Color("#2F4858"),   # lowest -- basins and where water will sit
	Color("#4A6B4A"),
	Color("#7A6A44"),
	Color("#9E8C6E"),
	Color("#C9C3B4"),   # highest -- ridges
]

const BORDER_COLOUR := Color("#E5484D")
const FILL_COLOUR := Color(0.90, 0.28, 0.30, 0.13)
const GRID_COLOUR := Color(1.0, 1.0, 1.0, 0.07)

var border                      ## RegionBorder
var extent: float = 4096.0

var _tex: ImageTexture
var _drag := -1
var _camera_at := Vector2.INF


func _init() -> void:
	custom_minimum_size = Vector2(0, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## The map is square whatever the panel does, so world distances stay honest in
## both directions and a circle drawn here is a circle on the ground.
func _map_rect() -> Rect2:
	var side := minf(size.x, size.y)
	return Rect2((size.x - side) * 0.5, (size.y - side) * 0.5, side, side)


func _to_screen(world: Vector2) -> Vector2:
	var r := _map_rect()
	var h := extent * 0.5
	return r.position + Vector2(
		(world.x + h) / extent * r.size.x,
		(world.y + h) / extent * r.size.y)


func _to_world(screen: Vector2) -> Vector2:
	var r := _map_rect()
	var h := extent * 0.5
	if r.size.x <= 0.0:
		return Vector2.ZERO
	return Vector2(
		(screen.x - r.position.x) / r.size.x * extent - h,
		(screen.y - r.position.y) / r.size.y * extent - h)


## World metres one pixel covers, so a pixel tolerance can be compared in world
## space without the caller knowing the panel size.
func _metres_per_px() -> float:
	var r := _map_rect()
	return extent / r.size.x if r.size.x > 0.0 else 1.0


# --------------------------------------------------------------- terrain --

## Renders the height field to a shaded image. Called on demand rather than
## continuously: the terrain only changes when somebody changes it, and a
## re-render is tens of thousands of height lookups.
func render_terrain(terrain, extent_m: float) -> void:
	extent = extent_m
	var data = terrain.get("data") if terrain != null else null
	if data == null:
		return

	var n := SAMPLES
	var cell := extent_m / float(n)
	var half := extent_m * 0.5

	var hs := PackedFloat32Array()
	hs.resize(n * n)
	var lo := INF
	var hi := -INF
	for j in n:
		var wz := -half + (float(j) + 0.5) * cell
		var row := j * n
		for i in n:
			var h: float = data.get_height(
				Vector3(-half + (float(i) + 0.5) * cell, 0.0, wz))
			if is_nan(h):
				h = 0.0
			hs[row + i] = h
			if h < lo:
				lo = h
			if h > hi:
				hi = h

	var span := maxf(1.0, hi - lo)
	var img := Image.create_empty(n, n, false, Image.FORMAT_RGB8)
	# Light from the north-west, which is the convention every relief map uses
	# and the reason hills read as hills rather than as holes.
	var light := Vector3(-0.55, 0.72, -0.42).normalized()

	for j in n:
		var row := j * n
		for i in n:
			var h := hs[row + i]
			var t := clampf((h - lo) / span, 0.0, 1.0)

			# Slope from the neighbours, clamped at the edges.
			var xl := hs[row + maxi(i - 1, 0)]
			var xr := hs[row + mini(i + 1, n - 1)]
			var zu := hs[maxi(j - 1, 0) * n + i]
			var zd := hs[mini(j + 1, n - 1) * n + i]
			var nrm := Vector3(xl - xr, 2.0 * cell, zu - zd).normalized()
			var lam := clampf(nrm.dot(light), 0.0, 1.0)

			img.set_pixel(i, j, _ramp(t) * (0.45 + 0.75 * lam))

	_tex = ImageTexture.create_from_image(img)
	queue_redraw()


static func _ramp(t: float) -> Color:
	var scaled := clampf(t, 0.0, 1.0) * float(RAMP.size() - 1)
	var i := int(scaled)
	if i >= RAMP.size() - 1:
		return RAMP[RAMP.size() - 1]
	return RAMP[i].lerp(RAMP[i + 1], scaled - float(i))


func set_camera_marker(world: Vector2) -> void:
	_camera_at = world
	queue_redraw()


# ------------------------------------------------------------------ draw --

func _draw() -> void:
	var r := _map_rect()
	if _tex != null:
		draw_texture_rect(_tex, r, false)
	else:
		draw_rect(r, Color("#151515"))
	draw_rect(r, Color("#3A3A3A"), false, 1.0)

	# Region quarters, as a reading aid for where the middle is.
	for f in [0.25, 0.5, 0.75]:
		draw_line(Vector2(r.position.x + r.size.x * f, r.position.y),
			Vector2(r.position.x + r.size.x * f, r.end.y), GRID_COLOUR, 1.0)
		draw_line(Vector2(r.position.x, r.position.y + r.size.y * f),
			Vector2(r.end.x, r.position.y + r.size.y * f), GRID_COLOUR, 1.0)

	if border == null or border.points.size() < 3:
		return

	var pts := PackedVector2Array()
	for p in border.points:
		pts.append(_to_screen(p))

	# Interior tint, so which side is inside is never a guess.
	draw_colored_polygon(pts, FILL_COLOUR)

	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, BORDER_COLOUR, 1.6, true)

	for i in pts.size():
		var filled := i == _drag
		draw_circle(pts[i], HANDLE_PX, BORDER_COLOUR if filled else Color("#1A1A1A"))
		draw_arc(pts[i], HANDLE_PX, 0.0, TAU, 12, BORDER_COLOUR, 1.4, true)

	if _camera_at.is_finite():
		var c := _to_screen(_camera_at)
		draw_arc(c, 4.0, 0.0, TAU, 14, Color("#EDEDED"), 1.3, true)


# ----------------------------------------------------------------- input --

func _gui_input(event: InputEvent) -> void:
	if border == null:
		return
	var tol := GRAB_PX * _metres_per_px()

	if event is InputEventMouseButton:
		var at := _to_world(event.position)

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_drag = border.nearest_point(at, tol)
				if _drag == -1:
					# Not on a corner: adding one where the edge was clicked is
					# what makes a border editable without a separate add mode.
					var edge: int = border.nearest_edge(at, tol)
					if edge != -1:
						_drag = border.insert_point(edge, at)
						border_changed.emit()
				accept_event()
			else:
				if _drag != -1:
					_drag = -1
					border_changed.emit()
				accept_event()
			queue_redraw()

		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			var hit: int = border.nearest_point(at, tol)
			if hit != -1:
				border.remove_point(hit)
				border_changed.emit()
				queue_redraw()
			accept_event()

	elif event is InputEventMouseMotion:
		var at := _to_world(event.position)
		hovered.emit(at)
		if _drag != -1:
			border.move_point(_drag, at)
			queue_redraw()
			accept_event()
