@tool
extends SubViewportContainer
## The workspace's 3D view.
##
## Hosts its own World3D in a SubViewport and instances the region scene into
## it, so the workspace renders terrain without borrowing the engine's 3D
## editor viewport. That independence is what lets the same UI run in a
## standalone build later.
##
## Navigation follows the convention every 3D tool shares, Noggit included:
## hold RMB to look, WASD/QE to fly, wheel to change speed, MMB to pan.

signal camera_moved(position: Vector3)
signal region_ready(region: Node)
signal cursor_moved(world: Vector3, valid: bool)
signal edit_applied(op_count: int)
signal brush_changed(radius: float, strength: float)
## A water body placed or moved its own surface, so the panel has to follow.
signal water_changed()

const Sculpt := preload("res://addons/animosis_terrain/sculpt.gd")
const ScaleRef := preload("res://addons/animosis_terrain/scale_ref.gd")
const Grid := preload("res://addons/animosis_terrain/grid.gd")
const AreaLayer := preload("res://addons/animosis_terrain/area.gd")
const PassabilityLayer := preload("res://addons/animosis_terrain/passability.gd")
const WaterLayer := preload("res://addons/animosis_terrain/water.gd")

const REGION_SCENE := "res://Main.tscn"

const LOOK_SENSITIVITY := 0.22
const PITCH_LIMIT := 89.0
const SPEED_MIN := 2.0
const SPEED_MAX := 4000.0
const SPEED_STEP := 1.15
const BOOST := 4.0
const CREEP := 0.2

var region: Node3D
var camera: Camera3D
var terrain: Node          ## Terrain3D, kept untyped so this file loads without the addon

var _speed: float = 120.0
var _looking := false
var _panning := false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _last_emit := Vector3.INF

var sculpt
var _cursor := Vector3.INF
var _painting := false
var _lowering := false
var _refs: Dictionary = {}     ## Kind -> ScaleRef instance
var _armed_ref: int = -1       ## which reference a plain click moves, -1 = none
var grid
var area
var passability
var water
## The layer being painted into while LMB is held, and the value being written,
## or null / -1 when not painting. Both layers chunk their meshes the same way,
## so they share one write-and-throttled-flush path rather than each having one.
var _layer_node
var _layer_paint: int = -1
var _layer_next_flush := 0.0
## Fill or Brush for the water tool. Fill is the default because a lake is a
## basin, not a shape somebody draws.
var water_fill_mode := true
var _pending_mouse := Vector2.INF   ## latest cursor position awaiting a raycast
var _last_applied := Vector3.INF    ## where the last deposit landed

## Continuous mode applies on a FIXED tick, not per rendered frame, so a 144 Hz
## machine deposits the same material as a 60 Hz one. Frame-rate-dependent
## deposition would also make the operation log unreproducible.
## Share of wall time sculpting may consume. operate() blocks the main thread,
## so at radius 200 (61.7 ms per call) an unthrottled stroke simply stops the
## editor. Holding it to a fraction keeps the UI responsive at any brush size.
const OPERATE_DUTY := 0.30
const OP_INTERVAL_MIN := 0.016   ## never more than once a frame
const OP_INTERVAL_MAX := 0.400   ## never less often than 2.5 Hz
## Layers get a tighter ceiling than sculpting. A deferred sculpt stroke is
## material that has not been deposited yet; a deferred layer flush is data that
## is already written and merely not drawn, so a long gap reads as the tool
## having missed the input rather than as it working.
const LAYER_FLUSH_INTERVAL_MAX := 0.180

var _next_op_at := 0.0


## Interval derived from the MEASURED cost, so it self-tunes to the brush size
## and to the machine instead of trusting a formula.
func _operate_interval() -> float:
	if sculpt == null:
		return OP_INTERVAL_MIN
	return clampf((sculpt.last_op_ms / 1000.0) / OPERATE_DUTY, OP_INTERVAL_MIN, OP_INTERVAL_MAX)


func _init() -> void:
	stretch = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP

	var vp := SubViewport.new()
	vp.name = "View"
	vp.handle_input_locally = false          # input is driven from here instead
	# WHEN_VISIBLE, not ALWAYS: the workspace is an overlay that spends most of
	# its life hidden behind the engine's own screens, and ALWAYS would keep
	# rendering 4 km of terrain the whole time.
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vp.msaa_3d = Viewport.MSAA_2X
	vp.own_world_3d = true
	# Wireframes must be generated up front; switching this on after meshes
	# exist leaves them without wireframe data. Cheap to leave enabled.
	RenderingServer.set_debug_generate_wireframes(true)
	add_child(vp)


func _ready() -> void:
	_load_region()
	set_process(true)


func _view() -> SubViewport:
	return get_node_or_null("View") as SubViewport


## Instances the region scene. Kept tolerant: a missing scene leaves an empty
## world rather than breaking the workspace.
func _load_region() -> void:
	var vp := _view()
	if vp == null:
		return

	if not ResourceLoader.exists(REGION_SCENE):
		push_warning("Animosis Terrain: %s not found; viewport will be empty." % REGION_SCENE)
		_ensure_camera(vp)
		return

	var packed := load(REGION_SCENE) as PackedScene
	if packed == null:
		_ensure_camera(vp)
		return

	region = packed.instantiate() as Node3D
	vp.add_child(region)

	terrain = region.get_node_or_null("Terrain3D")
	camera = region.get_node_or_null("Camera3D") as Camera3D
	_ensure_camera(vp)
	_adopt_camera_rotation()

	sculpt = Sculpt.new()
	if terrain and sculpt.attach(terrain, region):
		pass

	area = AreaLayer.new()
	region.add_child(area)

	passability = PassabilityLayer.new()
	region.add_child(passability)

	water = WaterLayer.new()
	region.add_child(water)

	grid = Grid.new()
	region.add_child(grid)
	var extent: float = float(region.get("extent_m")) if "extent_m" in region else 4096.0
	grid.configure(terrain, extent)
	area.configure(terrain, extent)
	passability.configure(terrain, extent)
	water.configure(terrain, extent)

	for k in [ScaleRef.Kind.PERSON, ScaleRef.Kind.BUILDING, ScaleRef.Kind.DRAGON]:
		var r = ScaleRef.new(k)
		region.add_child(r)
		_refs[k] = r

	region_ready.emit(region)


func _ensure_camera(vp: SubViewport) -> void:
	if camera != null:
		camera.current = true
		return
	camera = Camera3D.new()
	camera.far = 8000.0
	camera.position = Vector3(420, 320, 420)
	vp.add_child(camera)
	camera.current = true
	_adopt_camera_rotation()


## Seed yaw/pitch from wherever the camera already points, so the first RMB
## drag does not snap the view.
func _adopt_camera_rotation() -> void:
	if camera == null:
		return
	var e := camera.global_transform.basis.get_euler()
	_yaw = e.y
	_pitch = e.x


## Rebuilds the terrain. The region scene owns generation; the viewport only
## asks for it.
func generate() -> void:
	if region and region.has_method("build"):
		region.call("build")
	else:
		push_warning("Animosis Terrain: region has no build() method.")


func clear_region() -> void:
	if region and region.has_method("_clear"):
		region.call("_clear")


func frame_region() -> void:
	if camera == null:
		return
	var extent: float = 4096.0
	if region and "extent_m" in region:
		extent = float(region.get("extent_m"))
	camera.position = Vector3(extent * 0.12, extent * 0.10, extent * 0.12)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	_adopt_camera_rotation()


func height_under(world_xz: Vector3) -> float:
	if terrain == null:
		return NAN
	var data = terrain.get("data")
	if data == null:
		return NAN
	return data.get_height(world_xz)


# ------------------------------------------------------------------ input --

func _sculpt_modifier() -> int:
	# 0 = none, 1 = raise (Shift), -1 = lower (Ctrl)
	if Input.is_key_pressed(KEY_SHIFT):
		return 1
	if Input.is_key_pressed(KEY_CTRL):
		return -1
	return 0


func _gui_input(event: InputEvent) -> void:
	# Sculpting claims LMB before navigation sees it, but only while a modifier
	# is held -- an unmodified click must never deform the world by accident.
	if sculpt and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mod := _sculpt_modifier()
		if event.pressed and mod != 0 and _cursor.is_finite():
			if sculpt.tool == sculpt.Tool.AREA:
				# Areas are a stamp, not a stroke: one click assigns, and the
				# overlay rebuild makes per-motion painting far too expensive.
				area.paint(_cursor, sculpt.radius,
					0 if mod < 0 else area.selected_id)
				accept_event()
				return
			if sculpt.tool == sculpt.Tool.WATER and water_fill_mode:
				# A fill is one operation, not a stroke: it claims the whole
				# basin at once, so there is nothing to drag.
				if mod < 0:
					water.clear_body(water.selected_id)
				else:
					var n: int = water.fill(_cursor, water.selected_id)
					_set_fill_report(n)
				water_changed.emit()
				accept_event()
				return
			if sculpt.tool == sculpt.Tool.PASSABILITY or sculpt.tool == sculpt.Tool.WATER:
				if sculpt.tool == sculpt.Tool.WATER:
					_layer_node = water
					_layer_paint = 0 if mod < 0 else water.selected_id
				else:
					_layer_node = passability
					_layer_paint = int(PassabilityLayer.State.DERIVED if mod < 0
						else passability.paint_state)
				# A single click shows at once; only a drag defers the meshing.
				_layer_node.paint(_cursor, sculpt.radius, _layer_paint)
				_last_applied = _cursor
				_layer_next_flush = 0.0
				if sculpt.tool == sculpt.Tool.WATER:
					water_changed.emit()
				accept_event()
				return
			_painting = true
			_lowering = mod < 0
			_next_op_at = 0.0
			_last_applied = Vector3.INF
			sculpt.begin(_cursor, _lowering)
			_apply_stroke()
			edit_applied.emit(sculpt.operation_count())
			accept_event()
			return
		elif not event.pressed and (_painting or _layer_node != null):
			if _painting:
				# Spec §4.4: terrain moved, so every basin resolves again. Done
				# on release rather than per stroke tick -- the shoreline only
				# has to be right once you stop, and resolving mid-stroke would
				# pay for water sitting on ground still being shaped.
				resolve_water()
			_painting = false
			if _layer_node != null:
				# Whatever the timer had not got to yet has to land now, or the
				# tail of the stroke is written but never drawn.
				_layer_node.flush_pending()
			_layer_node = null
			_layer_paint = -1
			sculpt.end()
			accept_event()
			return

	if (_armed_ref != -1 and event is InputEventMouseButton
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed
			and _sculpt_modifier() == 0 and _cursor.is_finite()):
		_refs[_armed_ref].place_at(_cursor)
		accept_event()
		return

	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_looking = event.pressed
				_set_capture(_looking)
				if _looking:
					grab_focus()
				accept_event()
			MOUSE_BUTTON_MIDDLE:
				_panning = event.pressed
				accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				if _sculpt_modifier() != 0:
					set_brush_radius(brush_radius() * 1.12)
					_update_cursor(event.position)
				else:
					_speed = clampf(_speed * SPEED_STEP, SPEED_MIN, SPEED_MAX)
				accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if _sculpt_modifier() != 0:
					set_brush_radius(brush_radius() / 1.12)
					_update_cursor(event.position)
				else:
					_speed = clampf(_speed / SPEED_STEP, SPEED_MIN, SPEED_MAX)
				accept_event()

	elif event is InputEventMouseMotion:
		if not _looking:
			# Queue it. Mouse motion can fire several times per frame and a
			# raycast per event is wasted work; _process resolves it once.
			_pending_mouse = event.position
		if _painting or _layer_node != null:
			# Application happens in _process, rate-limited. Doing it here meant
			# one operate() per motion event -- at 125 Hz mouse polling and
			# 61.7 ms a call, that is a frozen editor.
			accept_event()
			return
		if _looking:
			_yaw -= deg_to_rad(event.relative.x * LOOK_SENSITIVITY)
			_pitch = clampf(
				_pitch - deg_to_rad(event.relative.y * LOOK_SENSITIVITY),
				deg_to_rad(-PITCH_LIMIT), deg_to_rad(PITCH_LIMIT)
			)
			_apply_rotation()
			accept_event()
		elif _panning and camera:
			var b := camera.global_transform.basis
			var scale := _speed * 0.004
			camera.global_position += (-b.x * event.relative.x + b.y * event.relative.y) * scale
			accept_event()

	elif event is InputEventKey and event.pressed and event.keycode == KEY_F:
		frame_region()
		accept_event()


## Projects the pointer onto the terrain and moves the brush ring there.
func _update_cursor(screen_pos: Vector2) -> void:
	if sculpt == null or camera == null:
		return
	var hit: Vector3 = sculpt.raycast(camera, screen_pos)
	var mod := _sculpt_modifier()

	# Rebuilding the ring costs a height query per segment, so skip it when the
	# cursor has barely moved relative to the brush size. Always rebuild while
	# painting, since the ground under it is changing.
	var moved_enough := true
	if not _painting and hit.is_finite() and _cursor.is_finite():
		moved_enough = hit.distance_to(_cursor) > maxf(0.25, sculpt.radius * 0.02)

	_cursor = hit
	if _cursor.is_finite():
		if moved_enough:
			sculpt.show_cursor_at(_cursor, mod < 0)
	else:
		sculpt.hide_cursor()
	if grid:
		grid.update_cells(_cursor)
	cursor_moved.emit(_cursor, _cursor.is_finite())


## Turning a reference on shows it AND makes it the click target, so the most
## recently enabled one is what a plain click moves. Earlier ones stay visible,
## which is the whole point -- a person beside a building beside a dragon is the
## comparison you actually want.
##
## Placing is not an edit, so it responds to an UNMODIFIED click. The modifier
## rule exists to protect terrain; this touches nothing.
func set_scale_ref(kind: int, on: bool) -> void:
	var r = _refs.get(kind)
	if r == null:
		return
	if on:
		var at := _cursor if _cursor.is_finite() else Vector3.ZERO
		if not _cursor.is_finite() and terrain:
			var data = terrain.get("data")
			if data:
				var h: float = data.get_height(at)
				at.y = 0.0 if is_nan(h) else h
		r.place_at(at)
		_armed_ref = kind
	else:
		r.visible = false
		if _armed_ref == kind:
			_armed_ref = -1


func scale_ref_label(kind: int) -> String:
	var r = _refs.get(kind)
	return r.label() if r else ""


func scale_ref_height(kind: int) -> float:
	var r = _refs.get(kind)
	return r.height() if r else 0.0


func set_area_overlay(on: bool) -> void:
	if area:
		area.set_visible_overlay(on)


func set_area_selection(id: int) -> void:
	if area:
		area.selected_id = id


func area_registry() -> Dictionary:
	return area.registry if area else {}


func area_at(world: Vector3) -> int:
	return area.at(world) if area else 0


func area_path(id: int) -> String:
	return area.path_of(id) if area else ""


func set_passability_overlay(on: bool) -> void:
	if passability:
		passability.set_visible_overlay(on)


func set_passability_paint(state: int) -> void:
	if passability:
		passability.paint_state = state


func passability_label(world: Vector3) -> String:
	return passability.label_at(world) if passability else ""


func set_water_overlay(on: bool) -> void:
	if water:
		water.set_visible_overlay(on)


func set_water_selection(id: int) -> void:
	if water:
		water.selected_id = id


func water_bodies() -> Dictionary:
	return water.bodies if water else {}


func water_level(id: int) -> float:
	var b = water.bodies.get(id) if water else null
	return b.level if b else 0.0


func water_levelled(id: int) -> bool:
	var b = water.bodies.get(id) if water else null
	return b.levelled if b else false


func set_water_level(id: int, y: float) -> void:
	if water:
		water.set_level(id, y)


## Places the surface exactly at the ground under the cursor, which is how you
## state "the shoreline goes here" rather than guessing a number.
func sample_water_level(id: int) -> float:
	if water == null or not _cursor.is_finite():
		return NAN
	water.set_level(id, _cursor.y)
	return _cursor.y


func add_water_body() -> int:
	return water.add_body() if water else 0


## Real relief of the region, so the Level slider spans the ground rather than
## an arbitrary range. A slider whose middle sits a hundred metres above every
## hilltop turns one stray click into a flood.
func terrain_height_range() -> Vector2:
	if terrain == null:
		return Vector2(-50.0, 300.0)
	var data = terrain.get("data")
	if data == null or not data.has_method("get_height_range"):
		return Vector2(-50.0, 300.0)
	var r: Vector2 = data.get_height_range()
	if is_equal_approx(r.x, r.y):
		return Vector2(-50.0, 300.0)
	return r


## Cells are 2 m square, so the count converts straight to an area.
func _set_fill_report(cells: int) -> void:
	last_fill_cells = cells


var last_fill_cells: int = 0


func refill_water(id: int) -> void:
	if water:
		last_fill_cells = water.refill(id)
		water_changed.emit()


func water_label(world: Vector3) -> String:
	return water.label_at(world) if water else ""


## Spec §4.4: a terrain change resolves the water level for affected basins.
## The level does not move; what it reaches does.
func resolve_water() -> void:
	if water:
		water.resolve_levels()


func set_wireframe(on: bool) -> void:
	var vp := _view()
	if vp:
		vp.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if on else Viewport.DEBUG_DRAW_DISABLED


func set_grid_level(level: int, on: bool) -> void:
	if grid:
		grid.set_level(level, on)


## Terrain moved under the grid, so anything visible has to be redrawn.
func refresh_grid() -> void:
	if grid:
		grid.refresh()


func set_tool(t: int) -> void:
	if sculpt:
		sculpt.tool = t


func set_sculpt_mode(m: int) -> void:
	if sculpt:
		sculpt.mode = m


func sculpt_mode() -> int:
	return sculpt.mode if sculpt else 0


func set_brush_shape(shape_key: String) -> void:
	if sculpt:
		sculpt.shape = shape_key


func brush_radius() -> float:
	return sculpt.radius if sculpt else 0.0


func set_brush_radius(v: float) -> void:
	if sculpt == null:
		return
	sculpt.radius = clampf(v, 2.0, 200.0)
	brush_changed.emit(sculpt.radius, sculpt.strength)


func brush_strength() -> float:
	return sculpt.strength if sculpt else 0.0


func set_brush_strength(v: float) -> void:
	if sculpt == null:
		return
	sculpt.strength = clampf(v, 1.0, 100.0)
	brush_changed.emit(sculpt.radius, sculpt.strength)


func _apply_stroke() -> void:
	sculpt.stroke(_cursor, camera.global_rotation.y if camera else 0.0)
	_last_applied = _cursor


func _set_capture(on: bool) -> void:
	# Captured mouse gives unbounded look without the pointer leaving the
	# window. Always restore it, or the editor is left with a hidden cursor.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE)


func _apply_rotation() -> void:
	if camera:
		camera.global_rotation = Vector3(_pitch, _yaw, 0.0)


func _notification(what: int) -> void:
	# Losing focus mid-drag would otherwise strand the captured cursor.
	if what == NOTIFICATION_FOCUS_EXIT or what == NOTIFICATION_EXIT_TREE:
		if _looking:
			_looking = false
			_set_capture(false)


func _process(delta: float) -> void:
	if camera == null:
		return

	if _looking:
		var dir := Vector3.ZERO
		if Input.is_key_pressed(KEY_W): dir -= camera.global_transform.basis.z
		if Input.is_key_pressed(KEY_S): dir += camera.global_transform.basis.z
		if Input.is_key_pressed(KEY_A): dir -= camera.global_transform.basis.x
		if Input.is_key_pressed(KEY_D): dir += camera.global_transform.basis.x
		if Input.is_key_pressed(KEY_E): dir += Vector3.UP
		if Input.is_key_pressed(KEY_Q): dir -= Vector3.UP

		if dir != Vector3.ZERO:
			var mult := 1.0
			if Input.is_key_pressed(KEY_SHIFT): mult = BOOST
			elif Input.is_key_pressed(KEY_ALT): mult = CREEP
			camera.global_position += dir.normalized() * _speed * mult * delta

	if _pending_mouse.is_finite():
		var at := _pending_mouse
		_pending_mouse = Vector2.INF
		_update_cursor(at)

	# Writes follow the cursor; meshing follows a measured clock. A third of the
	# brush between writes leaves no gaps at any speed a hand moves, and because
	# the write is the cheap half, none of the stroke is ever lost to throttling
	# -- only the moment it becomes visible is deferred.
	if _layer_node != null and _cursor.is_finite():
		if (not _last_applied.is_finite()
				or _cursor.distance_to(_last_applied) > sculpt.radius * 0.33):
			_layer_node.paint(_cursor, sculpt.radius, _layer_paint, false)
			_last_applied = _cursor
			if _layer_node == water:
				water_changed.emit()
		var now := Time.get_ticks_msec() / 1000.0
		if now >= _layer_next_flush and _layer_node.has_pending():
			_layer_node.flush_pending()
			_layer_next_flush = now + clampf(
				(_layer_node.last_op_ms / 1000.0) / OPERATE_DUTY,
				OP_INTERVAL_MIN, LAYER_FLUSH_INTERVAL_MAX)

	if _painting and sculpt and _cursor.is_finite():
		var now := Time.get_ticks_msec() / 1000.0
		if now >= _next_op_at:
			# Stroke only deposits where the cursor has actually travelled;
			# Continuous deposits wherever it is held.
			var moved: bool = not _last_applied.is_finite() 				or _cursor.distance_to(_last_applied) > sculpt.radius * 0.12
			if sculpt.mode == sculpt.Mode.CONTINUOUS or moved:
				_apply_stroke()
				_next_op_at = now + _operate_interval()

	if camera.global_position.distance_to(_last_emit) > 0.5:
		_last_emit = camera.global_position
		camera_moved.emit(_last_emit)


func fly_speed() -> float:
	return _speed
