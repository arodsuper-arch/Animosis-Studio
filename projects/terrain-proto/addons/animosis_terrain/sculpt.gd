@tool
extends RefCounted
## Raise / lower sculpting, plus the cursor ring that shows where it lands.
##
## Every stroke is recorded as an ordered operation (docs/terrain-and-sites-spec.md
## §7.1) rather than as heightfield bytes. Nothing consumes the log yet -- undo,
## save and multi-user sync all will, and recording from the first stroke is what
## keeps those cheap instead of a rewrite.

const BRUSH_DIR := "res://addons/terrain_3d/brushes/"

## Falloff shapes, measured from the actual brush images rather than guessed.
## Values are the profile from centre to rim; the names describe the RESULT,
## not the maths, because "Polynomial" tells an author nothing about what the
## ground will look like.
const SHAPES := {
	"plateau": "circle1",   # 1.00 1.00 0.99 0.76 0.02 -- flat top, sharp edge
	"linear":  "circle0",   # 1.00 0.76 0.51 0.26 0.06 -- straight cone
	"smooth":  "circle2",   # 1.00 0.97 0.75 0.23 0.00 -- S-curve, natural hills
	"steep":   "circle3",   # 1.00 0.76 0.34 0.07 0.00 -- tighter peak
	"feather": "circle4",   # 0.97 0.51 0.17 0.03 0.00 -- bell, blends invisibly
	"pad":     "square1",   # square, hard edge -- building pads and roads
}
## Ring detail scales with radius: a 10 m ring needs far fewer segments than a
## 200 m one to look round, and every segment costs a get_height() call across
## the GDScript/C++ boundary on each redraw.
const RING_SEGMENTS_MIN := 24
const RING_SEGMENTS_MAX := 64
const RING_LIFT := 0.35        ## metres above the surface, to avoid z-fighting
const RING_COLOUR := Color("#E5484D")
const RING_COLOUR_LOWER := Color("#6FA8DC")

## Which tool the modifiers drive. Each tool keeps the same two-modifier shape:
## Shift is the primary action, Ctrl the secondary.
enum Tool {
	SCULPT,    ## Shift raises, Ctrl lowers
	FLATTEN,   ## Shift flattens toward a height, Ctrl blurs toward the local average
	AREA,      ## Shift assigns the selected area, Ctrl clears it. Handled by the
	           ## area layer, not Terrain3D -- it writes our data, not heights.
	PASSABILITY, ## Shift marks the selected override, Ctrl clears back to
	             ## derived. Handled by the passability layer, same as Area.
	WATER,     ## Shift paints the selected body's footprint, Ctrl erases it.
	           ## Where the water lands inside that footprint is the ground's
	           ## decision, not the brush's.
}

var tool: Tool = Tool.SCULPT

## How a held stroke deposits material.
enum Mode {
	STROKE,      ## applies only as the cursor moves -- drag to paint terrain
	CONTINUOUS,  ## applies on a fixed tick while held, cursor stationary or not
}

var mode: Mode = Mode.STROKE
var shape: String = "smooth":
	set(v):
		if SHAPES.has(v):
			shape = v
			_brush = _load_brush(SHAPES[v])
var radius: float = 40.0

## Dial position, 1-100. What reaches Terrain3D is _effective_strength().
var strength: float = 33.0

## Terrain3D's strength is linear and NOT clamped at 100 -- measured: 10 -> 1.0 m,
## 100 -> 10.0 m, 200 -> 20.0 m of gain over ten applications. A linear 1-100
## dial therefore wastes its whole range: the useful fine-detail band sits in the
## bottom third and the top is far weaker than the engine allows.
##
## Response is squared about the default, so 33 still behaves exactly as it did
## while the upper half gains real punch:
##   10 -> 3     33 -> 33     50 -> 76     75 -> 170     100 -> 303
const STRENGTH_PIVOT := 33.0
const STRENGTH_EXPONENT := 2.0

var _terrain                    ## Terrain3D
var _editor                     ## Terrain3DEditor
var _brush: Array = []   ## [Image (FORMAT_RF), ImageTexture] -- the shape Terrain3D expects
var _ring: MeshInstance3D
var _mesh: ImmediateMesh
var _material: StandardMaterial3D

## Append-only stroke log. seq is monotonic per session for now; it becomes
## per-region and persisted once regions are saved.
var operations: Array[Dictionary] = []
var _seq: int = 0
var _stroke_open := false

## Rolling estimate of what one operate() costs, in milliseconds. Terrain3D's
## cost scales with brush AREA -- measured 0.9 ms at radius 20 and 61.7 ms at
## radius 200 -- so the only workable throttle is one driven by the real number
## on the real machine, not by a formula guessed from the radius.
var last_op_ms: float = 1.0

# Terrain3DEditor enum values, resolved from ClassDB rather than hardcoded.
# They are NOT in declaration order -- REGION is 0 and SCULPT is 1 -- so a
# guessed literal silently selects the wrong tool and edits regions instead of
# heights. Fallbacks are the values observed in Terrain3D 1.0.2.
var _TOOL_SCULPT := 1
var _TOOL_HEIGHT := 2
var _OP_ADD := 0
var _OP_SUBTRACT := 1
var _OP_AVERAGE := 3

## Target level for a flatten stroke, sampled where the stroke began so that
## "flatten" means "bring this to the height I clicked on".
var _flatten_height: float = 0.0


static func _editor_const(constant: String, fallback: int) -> int:
	if ClassDB.class_has_integer_constant("Terrain3DEditor", constant):
		return ClassDB.class_get_integer_constant("Terrain3DEditor", constant)
	push_warning("Animosis Terrain: Terrain3DEditor.%s missing; assuming %d." % [constant, fallback])
	return fallback


func attach(terrain, parent: Node3D) -> bool:
	_terrain = terrain
	if _terrain == null:
		return false

	if not ClassDB.class_exists("Terrain3DEditor"):
		push_warning("Animosis Terrain: Terrain3DEditor unavailable; sculpting disabled.")
		return false

	# Collision is pure cost while authoring: the cursor uses get_intersection(),
	# which reads the heightmap, not physics. Every sculpt stroke would otherwise
	# rebuild collision shapes for the affected area.
	_terrain.set("collision/mode", 0)   # Terrain3DCollision.DISABLED

	_editor = ClassDB.instantiate("Terrain3DEditor")
	_editor.set_terrain(_terrain)

	_TOOL_SCULPT = _editor_const("SCULPT", 1)
	_TOOL_HEIGHT = _editor_const("HEIGHT", 2)
	_OP_ADD = _editor_const("ADD", 0)
	_OP_SUBTRACT = _editor_const("SUBTRACT", 1)
	_OP_AVERAGE = _editor_const("AVERAGE", 3)

	_brush = _load_brush(SHAPES.get(shape, "circle2"))
	if _brush.is_empty():
		return false

	_build_ring(parent)
	return true


## The brushes folder carries a .gdignore, so Godot never imports these and
## load() cannot see them. They are read straight off disk exactly as the
## Terrain3D UI does, and Terrain3D expects [Image, Texture], not a texture.
## Results are cached: switching shape mid-session should not re-decode.
static var _brush_cache: Dictionary = {}

static func _load_brush(file_stem: String) -> Array:
	if _brush_cache.has(file_stem):
		return _brush_cache[file_stem]

	var path := BRUSH_DIR + file_stem + ".exr"
	var img := Image.load_from_file(path)
	if img == null:
		push_warning("Animosis Terrain: could not read %s." % path)
		return []
	img.convert(Image.FORMAT_RF)
	if img.get_width() < 1024 or img.get_height() < 1024:
		img.resize(1024, 1024, Image.INTERPOLATE_CUBIC)

	var entry := [img, ImageTexture.create_from_image(img)]
	_brush_cache[file_stem] = entry
	return entry


func _build_ring(parent: Node3D) -> void:
	_mesh = ImmediateMesh.new()

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.albedo_color = RING_COLOUR
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.disable_receive_shadows = true

	_ring = MeshInstance3D.new()
	_ring.name = "BrushCursor"
	_ring.mesh = _mesh
	_ring.material_override = _material
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	parent.add_child(_ring)


## Projects a screen position onto the terrain. Returns a Vector3 with
## `is_finite` false when the ray misses, which is how Terrain3D signals a miss.
func raycast(camera: Camera3D, screen_pos: Vector2) -> Vector3:
	if _terrain == null or camera == null:
		return Vector3.INF
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	# CPU mode, not GPU. GPU mode returns a frame-old result, is invalid on the
	# first call, and per Terrain3D's docs "cannot be used more than once per
	# frame" -- which a mouse-motion handler violates constantly. CPU mode
	# raymarches once, answers immediately, and our regions always exist.
	var hit: Vector3 = _terrain.get_intersection(origin, dir, false)
	# Terrain3D returns ~max-float or NaN on a miss rather than a bool.
	if is_nan(hit.y) or hit.z > 3.4e38:
		return Vector3.INF
	return hit


func show_cursor_at(world: Vector3, lowering: bool) -> void:
	if _ring == null:
		return
	if not world.is_finite():
		_ring.visible = false
		return

	_material.albedo_color = RING_COLOUR_LOWER if lowering else RING_COLOUR

	var data = _terrain.get("data")
	var segments := clampi(int(radius * 1.2), RING_SEGMENTS_MIN, RING_SEGMENTS_MAX)

	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		var p := Vector3(world.x + cos(a) * radius, 0.0, world.z + sin(a) * radius)
		# Follow the surface so the ring reads correctly on slopes, the way
		# Noggit's does, rather than floating as a flat disc.
		var h: float = data.get_height(p) if data else world.y
		p.y = (world.y if is_nan(h) else h) + RING_LIFT
		_mesh.surface_add_vertex(p)
	_mesh.surface_end()
	_ring.visible = true


func hide_cursor() -> void:
	if _ring:
		_ring.visible = false


func _brush_data(lowering: bool) -> Dictionary:
	return {
		# Terrain3D's "size" is a DIAMETER -- it feeds Decal.size, which in Godot
		# is full box dimensions, not half-extents. Our `radius` is a radius,
		# which is also what the cursor ring draws, so it doubles on the way in.
		# Passing radius directly made the brush work at half the visible ring.
		"size": radius * 2.0,
		"strength": _effective_strength(),
		"height": _flatten_height,
		"jitter": 0.0,
		"gamma": 1.0,
		"brush": _brush,
		"invert": lowering,
		"align_to_view": false,
		"show_cursor_while_painting": true,
		"mouse_pressure": 1.0,
		"modifier_shift": not lowering,
		"modifier_ctrl": lowering,
		"modifier_alt": false,
		"asset_id": 0,
		"enable_texture": false,
		"auto_regions": true,
	}


func _effective_strength() -> float:
	return STRENGTH_PIVOT * pow(maxf(strength, 0.1) / STRENGTH_PIVOT, STRENGTH_EXPONENT)


## `secondary` is Ctrl: lower for Sculpt, blur for Flatten.
func begin(world: Vector3, secondary: bool) -> void:
	if _editor == null or not world.is_finite():
		return

	var op_name := ""
	match tool:
		Tool.SCULPT:
			_editor.set_tool(_TOOL_SCULPT)
			_editor.set_operation(_OP_SUBTRACT if secondary else _OP_ADD)
			op_name = "lower" if secondary else "raise"
		Tool.FLATTEN:
			if secondary:
				# Blur pulls each point toward its neighbours -- an averaging
				# sculpt, not a height target.
				_editor.set_tool(_TOOL_SCULPT)
				_editor.set_operation(_OP_AVERAGE)
				op_name = "blur"
			else:
				_flatten_height = world.y
				_editor.set_tool(_TOOL_HEIGHT)
				_editor.set_operation(_OP_ADD)
				op_name = "flatten"

	_editor.set_brush_data(_brush_data(secondary))
	_editor.start_operation(world)
	_stroke_open = true

	_seq += 1
	operations.append({
		"op": op_name,
		"height": _flatten_height if tool == Tool.FLATTEN and not secondary else null,
		"at": [snappedf(world.x, 0.01), snappedf(world.z, 0.01)],
		"radius": radius,
		"strength": _effective_strength(),
		"falloff": SHAPES.get(shape, "circle2"),
		"seq": _seq,
	})


func stroke(world: Vector3, camera_yaw: float) -> void:
	if _editor == null or not _stroke_open or not world.is_finite():
		return
	var t0 := Time.get_ticks_usec()
	_editor.operate(world, camera_yaw)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	# Weighted toward recent samples: radius can change mid-session and the
	# estimate has to follow it quickly.
	last_op_ms = lerpf(last_op_ms, ms, 0.35)


func end() -> void:
	if _editor and _editor.is_operating():
		_editor.stop_operation()
	_stroke_open = false


func is_active() -> bool:
	return _stroke_open


func operation_count() -> int:
	return operations.size()
