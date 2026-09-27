@tool
extends Control
## Vector tool icons, drawn rather than loaded.
##
## Keeping them as code means no import step, no .gdignore surprises, and they
## recolour with the UI state for free. Each icon is authored on a 24x24 grid
## and scaled to whatever size the slot asks for.

const GRID := 24.0

@export var icon: String = "sculpt"
@export var colour: Color = Color("#C4C4C4"):
	set(v):
		colour = v
		queue_redraw()


func _init(p_icon: String = "sculpt", p_size: float = 20.0) -> void:
	icon = p_icon
	custom_minimum_size = Vector2(p_size, p_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s: float = minf(size.x, size.y) / GRID
	if s <= 0.0:
		return
	var w: float = maxf(1.4, 1.7 * s)

	match icon:
		"sculpt":
			_sculpt(s, w)
		"paint":
			_paint(s, w)
		"holes":
			_holes(s, w)
		"flatten":
			_flatten(s, w)
		"grid":
			_grid(s, w)
		"area":
			_area(s, w)
		"passability":
			_passability(s, w)
		"water":
			_water(s, w)
		"wireframe":
			_wireframe(s, w)
		"contour":
			_contour(s, w)
		"material":
			_material(s, w)
		"model":
			_model(s, w)
		"person":
			_person(s, w)
		"building":
			_building(s, w)
		"dragon":
			_dragon(s, w)
		_:
			_unknown(s, w)


func _p(pts: Array, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.push_back(Vector2(p[0], p[1]) * s)
	return out


## A ridge line under paired arrows, up and down: the tool does both, and the
## icon should say so rather than implying raise only.
func _sculpt(s: float, w: float) -> void:
	# Ridge, kept low so the arrows have clear air above it.
	draw_polyline(_p([[2, 22], [8, 18], [12, 20], [17, 16], [22, 22]], s), colour, w, true)

	# Up arrow, left.
	draw_polyline(_p([[8, 13], [8, 3]], s), colour, w, true)
	draw_polyline(_p([[4.5, 6.5], [8, 3], [11.5, 6.5]], s), colour, w, true)

	# Down arrow, right.
	draw_polyline(_p([[16, 3], [16, 13]], s), colour, w, true)
	draw_polyline(_p([[12.5, 9.5], [16, 13], [19.5, 9.5]], s), colour, w, true)


## Two arrows pressing down onto a level line: bring terrain to a height.
func _flatten(s: float, w: float) -> void:
	draw_polyline(_p([[3, 18], [21, 18]], s), colour, w * 1.3, true)
	for x in [8.0, 16.0]:
		draw_polyline(_p([[x, 4], [x, 13]], s), colour, w, true)
		draw_polyline(_p([[x - 3, 10], [x, 13], [x + 3, 10]], s), colour, w, true)


func _paint(s: float, w: float) -> void:
	draw_polyline(_p([[4, 20], [4, 12], [20, 12], [20, 20], [4, 20]], s), colour, w, true)
	draw_polyline(_p([[12, 12], [12, 4]], s), colour, w, true)


func _holes(s: float, w: float) -> void:
	draw_arc(Vector2(12, 12) * s, 7.5 * s, 0.0, TAU, 32, colour, w, true)
	draw_polyline(_p([[7, 17], [17, 7]], s), colour, w, true)


## Standing figure with a ground line: human-scale reference.
func _person(s: float, w: float) -> void:
	draw_arc(Vector2(12, 5) * s, 2.6 * s, 0.0, TAU, 20, colour, w, true)
	draw_polyline(_p([[12, 8], [12, 15]], s), colour, w, true)      # torso
	draw_polyline(_p([[7.5, 11], [16.5, 11]], s), colour, w, true)  # arms
	draw_polyline(_p([[12, 15], [8.5, 20]], s), colour, w, true)    # legs
	draw_polyline(_p([[12, 15], [15.5, 20]], s), colour, w, true)
	draw_polyline(_p([[3, 22], [21, 22]], s), colour, w, true)      # ground


## Pitched-roof structure with storey lines.
func _building(s: float, w: float) -> void:
	draw_polyline(_p([[4, 21], [4, 10], [12, 4], [20, 10], [20, 21], [4, 21]], s), colour, w, true)
	draw_polyline(_p([[4, 14], [20, 14]], s), colour, w, true)
	draw_polyline(_p([[10, 21], [10, 17], [14, 17], [14, 21]], s), colour, w, true)


## Winged creature in profile: swept wing over an arched body and tail.
func _dragon(s: float, w: float) -> void:
	draw_polyline(_p([[3, 19], [8, 20], [13, 17], [18, 18]], s), colour, w, true)   # body + tail
	draw_polyline(_p([[18, 18], [20, 14], [18, 11]], s), colour, w, true)           # neck
	draw_polyline(_p([[18, 11], [21, 9]], s), colour, w, true)                      # head
	draw_polyline(_p([[9, 18], [6, 8], [14, 11], [13, 17]], s), colour, w, true)    # wing


## Sphere with a highlight: a surface material.
## A lattice: the data grid overlay.
func _grid(s: float, w: float) -> void:
	for i in 4:
		var at: float = 3.0 + float(i) * 6.0
		draw_polyline(_p([[at, 3], [at, 21]], s), colour, w, true)
		draw_polyline(_p([[3, at], [21, at]], s), colour, w, true)


## Triangulated quad: the mesh itself.
## Irregular partitioned patches: zones on a map.
func _area(s: float, w: float) -> void:
	draw_polyline(_p([[3, 4], [21, 4], [21, 20], [3, 20], [3, 4]], s), colour, w, true)
	draw_polyline(_p([[3, 11], [10, 11], [10, 20]], s), colour, w, true)
	draw_polyline(_p([[10, 11], [15, 7], [21, 9]], s), colour, w, true)


## A striped barrier on posts: movement stops here. Deliberately not a crossed
## circle -- the holes icon already owns that shape, and a barrier reads as
## "cannot pass" rather than "does not exist".
func _passability(s: float, w: float) -> void:
	draw_polyline(_p([[3, 8], [21, 8], [21, 14], [3, 14], [3, 8]], s), colour, w, true)
	draw_polyline(_p([[7, 14], [11, 8]], s), colour, w, true)
	draw_polyline(_p([[13, 14], [17, 8]], s), colour, w, true)
	draw_polyline(_p([[7, 14], [7, 21]], s), colour, w, true)
	draw_polyline(_p([[17, 14], [17, 21]], s), colour, w, true)


## A droplet over a waterline. The line matters: this tool is about a SURFACE
## at a height, not about a quantity of liquid.
func _water(s: float, w: float) -> void:
	draw_polyline(_p([[12, 3], [17, 10], [17, 13.5], [12, 17], [7, 13.5], [7, 10], [12, 3]],
		s), colour, w, true)
	draw_polyline(_p([[3, 20], [7, 20]], s), colour, w, true)
	draw_polyline(_p([[10, 20], [14, 20]], s), colour, w, true)
	draw_polyline(_p([[17, 20], [21, 20]], s), colour, w, true)


func _wireframe(s: float, w: float) -> void:
	draw_polyline(_p([[3, 5], [21, 5], [21, 19], [3, 19], [3, 5]], s), colour, w, true)
	draw_polyline(_p([[3, 12], [21, 12]], s), colour, w, true)
	draw_polyline(_p([[3, 5], [21, 12]], s), colour, w, true)
	draw_polyline(_p([[3, 12], [21, 19]], s), colour, w, true)


## Nested closed curves: a topographic map.
func _contour(s: float, w: float) -> void:
	draw_polyline(_p([[3, 18], [7, 13], [12, 16], [17, 10], [21, 14]], s), colour, w, true)
	draw_polyline(_p([[5, 13], [9, 9], [13, 12], [17, 6]], s), colour, w, true)
	draw_polyline(_p([[8, 8], [11, 5], [14, 7]], s), colour, w, true)


func _material(s: float, w: float) -> void:
	draw_arc(Vector2(12, 12) * s, 8.0 * s, 0.0, TAU, 36, colour, w, true)
	draw_arc(Vector2(12, 12) * s, 8.0 * s, deg_to_rad(200), deg_to_rad(250), 12, colour, w * 1.6, true)


## Cube in three-quarter view: a mesh asset.
func _model(s: float, w: float) -> void:
	draw_polyline(_p([[12, 3], [21, 8], [21, 17], [12, 22], [3, 17], [3, 8], [12, 3]], s), colour, w, true)
	draw_polyline(_p([[3, 8], [12, 13], [21, 8]], s), colour, w, true)
	draw_polyline(_p([[12, 13], [12, 22]], s), colour, w, true)


func _unknown(s: float, w: float) -> void:
	draw_polyline(_p([[6, 6], [18, 6], [18, 18], [6, 18], [6, 6]], s), colour, w, true)
