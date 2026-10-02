@tool
extends Node3D
## The region border: which part of a region is the playable interior.
##
## A region is 4 km of ground, but the space a player is meant to occupy is a
## shape inside that, and until something states the shape nothing else can
## reason about it. Once it exists it answers several questions at once:
##
##   - where a Border Wall goes -- the polygon IS the path
##   - what is outside, which is impassable by definition
##   - how much playable ground a region actually has, in km2
##   - what an area, a site or a settlement has to fit within
##
## It is stored as a polygon in world XZ rather than as a mask, because a border
## is a decision about a handful of points and storing it per cell would be a
## million cells describing a dozen corners. Rasterising it is something a
## consumer does, not something the border does.
##
## Deliberately flat. The border says where the boundary is, not how high the
## ground there is; the terrain answers that, and it answers it again whenever
## the terrain changes.

const Coords := preload("res://addons/animosis_terrain/coords.gd")

const LINE_COLOUR := Color("#E5484D")
const LIFT := 1.5

## Edges are subdivided to this before being drawn, so the line follows the
## ground rather than cutting through a hill between two distant corners.
const DRAW_STEP_M := 24.0

## Where a fresh border sits, as a fraction of the region extent. Not the whole
## region: a border wall has to stand somewhere, and it stands outside this.
const DEFAULT_INSET := 0.80


## World XZ, implicitly closed. Order is the winding, and the tools that consume
## it treat the inside as the interior.
var points: PackedVector2Array

var _extent: float = 4096.0
var _terrain
var _line: MeshInstance3D


func _init() -> void:
	name = "RegionBorder"

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = LINE_COLOUR
	mat.no_depth_test = true
	mat.render_priority = 4

	_line = MeshInstance3D.new()
	_line.name = "BorderLine"
	_line.mesh = ImmediateMesh.new()
	_line.material_override = mat
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)


func configure(terrain, extent_m: float) -> void:
	_terrain = terrain
	_extent = extent_m
	var half := extent_m * 0.5
	_line.custom_aabb = AABB(
		Vector3(-half, -2000.0, -half), Vector3(extent_m, 4000.0, extent_m))
	if points.size() < 3:
		reset_rect(DEFAULT_INSET)
	else:
		rebuild()


# --------------------------------------------------------------- presets --

func reset_rect(inset: float) -> void:
	var h := _extent * 0.5 * inset
	points = PackedVector2Array([
		Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h),
	])
	rebuild()


## Rounder regions read as places rather than as boxes, and a wall built along
## one has no corners to get stuck in.
func reset_ellipse(inset: float, segments: int = 16) -> void:
	var h := _extent * 0.5 * inset
	points = PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / float(segments)
		points.append(Vector2(cos(a) * h, sin(a) * h * 0.86))
	rebuild()


# --------------------------------------------------------------- queries --

func inside(world: Vector3) -> bool:
	if points.size() < 3:
		return true
	return Geometry2D.is_point_in_polygon(Vector2(world.x, world.z), points)


## Shoelace. Absolute, so winding does not decide the sign of an area.
func area_km2() -> float:
	if points.size() < 3:
		return 0.0
	var sum := 0.0
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) * 0.5 / 1.0e6


func perimeter_m() -> float:
	if points.size() < 2:
		return 0.0
	var total := 0.0
	for i in points.size():
		total += points[i].distance_to(points[(i + 1) % points.size()])
	return total


func fraction_of_region() -> float:
	var whole := _extent * _extent / 1.0e6
	return area_km2() / whole if whole > 0.0 else 0.0


# ----------------------------------------------------------------- edits --

func move_point(index: int, to: Vector2) -> void:
	if index < 0 or index >= points.size():
		return
	var h := _extent * 0.5
	points[index] = Vector2(clampf(to.x, -h, h), clampf(to.y, -h, h))
	rebuild()


## Inserts after `index`, which is how clicking an edge adds a corner where the
## click was rather than at the end of the list.
func insert_point(index: int, at: Vector2) -> int:
	var i := clampi(index + 1, 0, points.size())
	points.insert(i, at)
	rebuild()
	return i


func remove_point(index: int) -> void:
	# Three is the fewest that still encloses anything.
	if points.size() <= 3 or index < 0 or index >= points.size():
		return
	points.remove_at(index)
	rebuild()


## Index of the nearest corner within `radius` world metres, or -1.
func nearest_point(at: Vector2, radius: float) -> int:
	var best := -1
	var best_d := radius
	for i in points.size():
		var d := points[i].distance_to(at)
		if d < best_d:
			best_d = d
			best = i
	return best


## Index of the corner BEFORE the nearest edge within `radius`, or -1.
func nearest_edge(at: Vector2, radius: float) -> int:
	var best := -1
	var best_d := radius
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var d := at.distance_to(Geometry2D.get_closest_point_to_segment(at, a, b))
		if d < best_d:
			best_d = d
			best = i
	return best


# ---------------------------------------------------------------- output --

func _height(x: float, z: float) -> float:
	if _terrain == null:
		return 0.0
	var data = _terrain.get("data")
	if data == null:
		return 0.0
	var h: float = data.get_height(Vector3(x, 0.0, z))
	return 0.0 if is_nan(h) else h


## The border as a closed 3D path on the ground, subdivided so it follows the
## terrain. This is what a Border Wall is built along -- the wall does not need
## its own path, because the border already is one.
func path_3d() -> PackedVector3Array:
	var out := PackedVector3Array()
	if points.size() < 3:
		return out
	for i in points.size():
		var a := points[i]
		var b := points[(i + 1) % points.size()]
		var steps := maxi(1, int(ceilf(a.distance_to(b) / DRAW_STEP_M)))
		for s in steps:
			var t := float(s) / float(steps)
			var p := a.lerp(b, t)
			out.append(Vector3(p.x, _height(p.x, p.y), p.y))
	# Closed: the last point repeats the first, so a wall has no seam.
	var f := points[0]
	out.append(Vector3(f.x, _height(f.x, f.y), f.y))
	return out


func rebuild() -> void:
	var mesh := _line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var path := path_3d()
	if path.size() < 2:
		_line.visible = false
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in path:
		mesh.surface_add_vertex(p + Vector3.UP * LIFT)
	mesh.surface_end()
	_line.visible = visible


func set_visible_overlay(on: bool) -> void:
	visible = on
	if on:
		rebuild()
