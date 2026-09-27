@tool
extends Control
## Animosis terrain workspace — layout pass.
##
## Chrome only. The rails, toolbar and panels are laid out to match the Noggit
## arrangement (menu bar / left tool rail / floating toolbar over the viewport /
## right properties column / status bar) but nothing is wired to a tool yet.
##
## Deliberately free of EditorInterface: this is a plain Control, so the same
## scene can later be hosted in a standalone AnimosisTerrain.exe rather than an
## editor tab, without touching the UI.

## Emitted when the user dismisses the workspace. The host decides what that
## means -- the editor plugin hands the main screen back to 3D; a standalone
## build would quit.
signal exit_requested

const Viewport3D := preload("res://addons/animosis_terrain/viewport_3d.gd")
const Coords := preload("res://addons/animosis_terrain/coords.gd")
const Icons := preload("res://addons/animosis_terrain/icons.gd")
const ScaleRef := preload("res://addons/animosis_terrain/scale_ref.gd")
const Sculpt := preload("res://addons/animosis_terrain/sculpt.gd")
const Grid := preload("res://addons/animosis_terrain/grid.gd")
const Passability := preload("res://addons/animosis_terrain/passability.gd")
const Water := preload("res://addons/animosis_terrain/water.gd")

# design/tokens.css
const SURFACE_RAIL    := Color("#0F0F0F")
const SURFACE_SUNKEN  := Color("#111111")
const SURFACE_BASE    := Color("#1A1A1A")
const SURFACE_RAISED  := Color("#262626")
const SURFACE_HOVER   := Color("#303030")
const BORDER_SUBTLE   := Color("#262626")
const BORDER_DEFAULT  := Color("#3A3A3A")
const TEXT_PRIMARY    := Color("#EDEDED")
const TEXT_SECONDARY  := Color("#C4C4C4")
const TEXT_MUTED      := Color("#9A9A9A")
const TEXT_DISABLED   := Color("#6E6E6E")
const RED_PRIMARY     := Color("#E5484D")

const RAIL_WIDTH      := 52
const RAIL_SLOTS      := 13   # Noggit's left column
const TOOLBAR_SLOTS   := 20   # Noggit's floating row
const PANEL_WIDTH     := 268
const MENU_HEIGHT     := 30
const STATUS_HEIGHT   := 26

var _viewport_host: Control
var _view: SubViewportContainer
var _status: Dictionary = {}
var _radius_slider: HSlider
var _strength_slider: HSlider
var _syncing := false
var _areas_section: Control
var _pass_section: Control
var _mode_section: Control
var _shape_section: Control
var _current_tool: int = 0
var _water_section: Control
var _water_notes: Control
var _water_rows: VBoxContainer
var _level_slider: HSlider
var _level_group: ButtonGroup
var _tool_sections: Array[Control] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	_build()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		exit_requested.emit()
		accept_event()


# ---------------------------------------------------------------- styling --

static func _sb(bg: Color, border := Color.TRANSPARENT, widths := Vector4i.ZERO, radius := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = widths.x
	s.border_width_top = widths.y
	s.border_width_right = widths.z
	s.border_width_bottom = widths.w
	if radius > 0:
		s.set_corner_radius_all(radius)
	return s


static func _panel(bg: Color, border := Color.TRANSPARENT, widths := Vector4i.ZERO, radius := 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _sb(bg, border, widths, radius))
	return p


static func _label(text: String, size: int, colour: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	if bold:
		l.add_theme_constant_override("outline_size", 0)
	return l


## A selectable tool. Toggles within a ButtonGroup so exactly one is active,
## and carries a red bar plus a tinted icon while selected -- the active tool
## has to be readable at a glance, not inferred.
static func _tool_slot(px: int, icon_name: String, label: String, group: ButtonGroup, active: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(px, px)
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = active
	b.tooltip_text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _sb(Color.TRANSPARENT, Color.TRANSPARENT, Vector4i.ZERO, 5))
	b.add_theme_stylebox_override("hover", _sb(SURFACE_HOVER, Color.TRANSPARENT, Vector4i.ZERO, 5))
	b.add_theme_stylebox_override("pressed", _sb(Color("#2A1116"), RED_PRIMARY, Vector4i(2, 0, 0, 0), 5))
	b.add_theme_stylebox_override("hover_pressed", _sb(Color("#331419"), RED_PRIMARY, Vector4i(2, 0, 0, 0), 5))

	var glyph := Icons.new(icon_name, float(px) * 0.52)
	glyph.colour = RED_PRIMARY if active else TEXT_SECONDARY

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(glyph)
	b.add_child(centre)

	b.toggled.connect(func(on: bool) -> void:
		glyph.colour = RED_PRIMARY if on else TEXT_SECONDARY)
	return b


static func _toolbar_divider() -> Control:
	var sep := Panel.new()
	sep.custom_minimum_size = Vector2(1, 22)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sep.add_theme_stylebox_override("panel", _sb(BORDER_DEFAULT))
	return sep


## A standalone toggle. Unlike a tool slot it belongs to no group, because
## things like the scale reference are overlays that coexist with whatever
## tool is selected rather than replacing it.
static func _toggle_slot(px: int, icon_name: String, label: String, on_toggled: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(px, px)
	b.toggle_mode = true
	b.tooltip_text = label
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", _sb(Color.TRANSPARENT, Color.TRANSPARENT, Vector4i.ZERO, 5))
	b.add_theme_stylebox_override("hover", _sb(SURFACE_HOVER, Color.TRANSPARENT, Vector4i.ZERO, 5))
	b.add_theme_stylebox_override("pressed", _sb(Color("#2A1116"), RED_PRIMARY, Vector4i(0, 0, 0, 2), 5))
	b.add_theme_stylebox_override("hover_pressed", _sb(Color("#331419"), RED_PRIMARY, Vector4i(0, 0, 0, 2), 5))

	var glyph := Icons.new(icon_name, float(px) * 0.58)
	glyph.colour = TEXT_SECONDARY

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(glyph)
	b.add_child(centre)

	b.toggled.connect(func(on: bool) -> void:
		glyph.colour = RED_PRIMARY if on else TEXT_SECONDARY
		on_toggled.call(on))
	return b


## An empty tool slot. Real tools land here later; for now it reads as an
## affordance without pretending to do anything.
static func _slot(px: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(px, px)
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_ARROW
	b.add_theme_stylebox_override("normal", _sb(Color.TRANSPARENT, Color.TRANSPARENT, Vector4i.ZERO, 5))
	b.add_theme_stylebox_override("hover", _sb(SURFACE_HOVER, Color.TRANSPARENT, Vector4i.ZERO, 5))
	b.add_theme_stylebox_override("pressed", _sb(SURFACE_RAISED, Color.TRANSPARENT, Vector4i.ZERO, 5))

	var glyph := Panel.new()
	glyph.custom_minimum_size = Vector2(16, 16)
	glyph.set_anchors_preset(Control.PRESET_CENTER)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.add_theme_stylebox_override("panel", _sb(Color("#3A3A3A"), Color.TRANSPARENT, Vector4i.ZERO, 3))

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.add_child(glyph)
	b.add_child(centre)
	return b


# ------------------------------------------------------------------ build --

func _build() -> void:
	# Opaque: this overlay hides the entire editor behind it.
	var bg := ColorRect.new()
	bg.color = SURFACE_BASE
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_menu_bar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	root.add_child(body)

	body.add_child(_tool_rail())
	body.add_child(_viewport_area())
	body.add_child(_properties_panel())

	root.add_child(_status_bar())


func _menu_bar() -> Control:
	var bar := _panel(SURFACE_RAIL, BORDER_SUBTLE, Vector4i(0, 0, 0, 1))
	bar.custom_minimum_size = Vector2(0, MENU_HEIGHT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	bar.add_child(row)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(6, 0)
	row.add_child(pad)

	for title in ["Animosis", "Region", "Edit", "View", "Sites", "Assets", "Help"]:
		var m := MenuButton.new()
		m.text = title
		m.flat = true
		m.focus_mode = Control.FOCUS_NONE
		m.add_theme_font_size_override("font_size", 12)
		m.add_theme_color_override("font_color", TEXT_SECONDARY)
		m.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
		m.add_theme_stylebox_override("normal", _sb(Color.TRANSPARENT))
		m.add_theme_stylebox_override("hover", _sb(SURFACE_HOVER, Color.TRANSPARENT, Vector4i.ZERO, 4))
		# Only Region does anything yet; the rest are placeholders for layout.
		if title == "Region":
			var pm := m.get_popup()
			pm.add_item("Generate", 0)
			pm.add_item("Clear", 1)
			pm.add_separator()
			pm.add_item("Frame Region", 2)
			pm.id_pressed.connect(_on_region_menu)
		row.add_child(m)

	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spring)

	var context := _label("Animosis Terrain", 11, TEXT_DISABLED)
	row.add_child(context)

	# The overlay covers the editor's tab strip, so leaving has to be possible
	# from inside. Escape does the same thing.
	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.tooltip_text = "Return to the engine  (Esc)"
	exit_btn.flat = true
	exit_btn.focus_mode = Control.FOCUS_NONE
	exit_btn.custom_minimum_size = Vector2(60, 0)
	exit_btn.add_theme_font_size_override("font_size", 12)
	exit_btn.add_theme_color_override("font_color", TEXT_SECONDARY)
	exit_btn.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
	exit_btn.add_theme_stylebox_override("normal", _sb(Color.TRANSPARENT))
	exit_btn.add_theme_stylebox_override("hover", _sb(Color("#C1272D"), Color.TRANSPARENT, Vector4i.ZERO, 4))
	exit_btn.pressed.connect(func() -> void: exit_requested.emit())
	row.add_child(exit_btn)

	var tail := Control.new()
	tail.custom_minimum_size = Vector2(6, 0)
	row.add_child(tail)

	return bar


func _tool_rail() -> Control:
	var rail := _panel(SURFACE_RAIL, BORDER_SUBTLE, Vector4i(0, 0, 1, 0))
	rail.custom_minimum_size = Vector2(RAIL_WIDTH, 0)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	rail.add_child(col)

	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 6)
	col.add_child(top)

	var tools := ButtonGroup.new()
	var rail_tools := [
		["sculpt",  "Sculpt  —  raise and lower terrain"],
		["flatten", "Flatten  —  level to a height, or blur toward the local average"],
		["area",    "Areas  —  assign zones to the ground"],
		["passability", "Passability  —  override where movement is allowed"],
		["water",   "Water  —  place water bodies and set their level"],
	]
	for i in RAIL_SLOTS:
		var s: Button
		if i < rail_tools.size():
			var idx := i
			s = _tool_slot(RAIL_WIDTH - 12, String(rail_tools[i][0]),
				String(rail_tools[i][1]), tools, i == 0)
			s.toggled.connect(func(on: bool) -> void:
				if on:
					_on_tool_selected(idx))
		else:
			s = _slot(RAIL_WIDTH - 12)
		s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(s)
		# Noggit groups its rail; a hairline every few slots reads the same way.
		if i == 5 or i == 9:
			var sep := Panel.new()
			sep.custom_minimum_size = Vector2(RAIL_WIDTH - 20, 1)
			sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			sep.add_theme_stylebox_override("panel", _sb(BORDER_DEFAULT))
			col.add_child(sep)

	return rail


func _viewport_area() -> Control:
	var host := Control.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.clip_contents = true
	_viewport_host = host

	# Real 3D view with its own World3D -- not the engine's 3D editor viewport.
	_view = Viewport3D.new()
	_view.name = "View3D"
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(_view)
	_view.camera_moved.connect(_on_camera_moved)
	_view.cursor_moved.connect(_on_cursor_moved)
	_view.edit_applied.connect(_on_edit_applied)
	_view.brush_changed.connect(_on_brush_changed)
	_view.water_changed.connect(_sync_level_slider)

	# Floating toolbar, sitting over the viewport as Noggit's does.
	var float_bar := _panel(Color(0.06, 0.06, 0.06, 0.92), BORDER_DEFAULT, Vector4i(1, 1, 1, 1), 8)
	float_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	float_bar.position = Vector2(14, 14)
	float_bar.mouse_filter = Control.MOUSE_FILTER_STOP

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 5)
	float_bar.add_child(margin)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 1)
	margin.add_child(tools)

	# Two explicit groups with a divider between them: what things are next to
	# (scale) and how the data is drawn (view). Both are overlays, neither
	# changes what a click does -- that is the rail's job.
	var scale_refs := [
		[ScaleRef.Kind.PERSON,   "person",   "Person  —  1.8 m"],
		[ScaleRef.Kind.BUILDING, "building", "Building  —  11 m to the ridge"],
		[ScaleRef.Kind.DRAGON,   "dragon",   "Dragon  —  6.5 m tall, 20 m wingspan"],
	]
	for entry in scale_refs:
		var kind: int = entry[0]
		tools.add_child(_toggle_slot(34, String(entry[1]),
			"%s.  Click the ground to move it." % String(entry[2]),
			func(on: bool) -> void: _on_scale_ref_toggled(kind, on)))

	tools.add_child(_toolbar_divider())

	var views := [
		["grid",      Grid.Level.RENDER_CHUNK, "Render chunks  —  512 m, what re-uploads when you sculpt"],
		["grid",      Grid.Level.LAYER_CHUNK,  "Layer chunks  —  128 m, what ticks and what a delta names"],
		["grid",      Grid.Level.CELL,         "Cells  —  2 m, one per terrain vertex"],
		["wireframe", -1,                      "Wireframe  —  the terrain mesh itself"],
		["contour",   Grid.Level.CONTOUR,      "Contours  —  every 10 m of elevation"],
	]
	for entry in views:
		var icon := String(entry[0])
		var lvl: int = entry[1]
		tools.add_child(_toggle_slot(34, icon, String(entry[2]),
			func(on: bool) -> void:
				if _view == null:
					return
				if lvl < 0:
					_view.set_wireframe(on)
				else:
					_view.set_grid_level(lvl, on)))

	tools.add_child(_toolbar_divider())

	for i in 8:
		tools.add_child(_slot(34))

	host.add_child(float_bar)

	# Navigation hint, bottom left, out of the way.
	var hint := _label("RMB look  ·  WASD/QE fly  ·  Shift fast  ·  MMB pan  ·  Wheel speed  ·  F frame", 11, TEXT_DISABLED)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(14, -26)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(hint)

	return host


func _on_camera_moved(pos: Vector3) -> void:
	_set_status("pos", "cam %.0f, %.0f, %.0f" % [pos.x, pos.y, pos.z])


func _region_extent() -> float:
	if _view and _view.region and "extent_m" in _view.region:
		return float(_view.region.get("extent_m"))
	return 4096.0


func _on_cursor_moved(world: Vector3, valid: bool) -> void:
	if not valid:
		_set_status("tile", "region --  chunk --")
		_set_status("cursor", "cursor --")
		return
	var extent := _region_extent()
	var r := Coords.region_of(world, extent)
	var c := Coords.layer_chunk_of(world, extent)
	var l := Coords.local_of(world, extent)
	var rc := Coords.render_chunk_of(world, extent)
	_set_status("tile", "region %d,%d   render %d,%d   layer %d,%d" % [r.x, r.y, rc.x, rc.y, c.x, c.y])
	var aid: int = _view.area_at(world) if _view else 0
	var area_txt: String = _view.area_path(aid) if (_view and aid != 0) else "unassigned"
	# Depth replaces the zone name while the water tool is up: that is the number
	# you are working to, and the line has no room for both.
	if _view and _current_tool == Sculpt.Tool.WATER:
		var w: String = _view.water_label(world)
		area_txt = w if w != "" else "no water"
	_set_status("cursor", "local %.0f, %.0f m   h %.1f m   %s" % [l.x, l.y, world.y, area_txt])


func _on_edit_applied(count: int) -> void:
	_set_status("edits", "edits %d" % count)


func _set_status(key: String, text: String) -> void:
	if _status.has(key):
		_status[key].text = text


func _properties_panel() -> Control:
	var panel := _panel(SURFACE_BASE, BORDER_SUBTLE, Vector4i(1, 0, 0, 0))
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	scroll.add_child(col)

	# One section per tool; only the selected tool's is shown.
	_tool_sections.clear()
	_tool_sections.append(_tool_section(col, "Sculpt", [
		["Shift + LMB", "raise terrain"],
		["Ctrl + LMB", "lower terrain"],
		["Shift/Ctrl + Wheel", "brush radius"],
	]))
	_tool_sections.append(_tool_section(col, "Flatten", [
		["Shift + LMB", "flatten to the height first clicked"],
		["Ctrl + LMB", "blur toward the local average"],
		["Shift/Ctrl + Wheel", "brush radius"],
	]))
	_tool_sections.append(_tool_section(col, "Areas", [
		["Shift + LMB", "assign the selected area"],
		["Ctrl + LMB", "clear back to unassigned"],
		["Shift/Ctrl + Wheel", "brush radius"],
	]))
	_tool_sections.append(_tool_section(col, "Passability", [
		["Shift + LMB", "mark the selected override"],
		["Ctrl + LMB", "clear back to derived"],
		["Shift/Ctrl + Wheel", "brush radius"],
	], "Unmarked ground answers from its own slope, surface and depth, so it "
		+ "stays correct when you sculpt. Only exceptions are stored here."))
	for i in range(1, _tool_sections.size()):
		_tool_sections[i].visible = false

	# The area list belongs to the area tool, so it travels with it.
	_areas_section = _areas_block(col)
	_areas_section.visible = false

	# Same for the override kind. Shift still means add and Ctrl still means
	# remove; this only says what Shift adds, so the third state costs no extra
	# modifier and the default behaves exactly like a two-state tool.
	_pass_section = _pass_block(col)
	_pass_section.visible = false

	_tool_sections.append(_tool_section(col, "Water", _water_rows_for(true),
		WATER_NOTE))
	_tool_sections[Sculpt.Tool.WATER].visible = false
	_water_notes = _tool_sections[Sculpt.Tool.WATER]
	_water_section = _water_block(col)
	_water_section.visible = false

	# Noggit folds falloff shape, selection model and input source into one
	# "Type" list. They are unrelated axes, so they get their own groups here.
	#
	# Shape is a FALLOFF: how the brush fades from centre to rim. That only
	# means something where a stroke deposits by degree. A layer override is a
	# decision -- a cell is blocked or it is not -- and a feathered edge would
	# write partial states that nothing can read, so the section hides for the
	# layer tools instead of sitting there doing nothing.
	_shape_section = VBoxContainer.new()
	_shape_section.add_theme_constant_override("separation", 0)
	_shape_section.add_child(_section("Shape"))
	_shape_section.add_child(_radio_grid([
		["Smooth",  "smooth",  "S-curve. Natural hills."],
		["Linear",  "linear",  "Straight cone."],
		["Plateau", "plateau", "Flat top, sharp edge."],
		["Steep",   "steep",   "Tighter peak."],
		["Feather", "feather", "Softest. Blends invisibly."],
		["Pad",     "pad",     "Square, hard edge. Building pads."],
	], 0, 2, _on_brush_shape_changed))
	col.add_child(_shape_section)

	# Mode is a question about DEPOSITION -- how much material a held brush keeps
	# adding -- so it only means something for tools that accumulate. Painting a
	# layer writes a value, and writing the same value twice does nothing, so
	# Continuous has no meaning there and the section is hidden rather than left
	# sitting inert.
	_mode_section = VBoxContainer.new()
	_mode_section.add_theme_constant_override("separation", 0)
	_mode_section.add_child(_section("Mode"))
	_mode_section.add_child(_radio_block([
		["Stroke", "Deposits only as the cursor moves. Drag to paint terrain."],
		["Continuous", "Keeps building while held, even with the mouse still."],
	], 0, _on_sculpt_mode_changed))
	col.add_child(_mode_section)
	col.add_child(_section("Settings"))
	col.add_child(_settings_block())

	return panel


## Centred, underlined heading — the same treatment Noggit uses for Type and
## Settings.
static func _section(title: String) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 5)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 14)
	wrap.add_child(spacer)

	var l := _label(title, 13, TEXT_PRIMARY)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrap.add_child(l)

	var rule := Panel.new()
	rule.custom_minimum_size = Vector2(56, 1)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.add_theme_stylebox_override("panel", _sb(BORDER_DEFAULT))
	wrap.add_child(rule)

	return wrap


## Radio group. Godot renders CheckBox as a radio button once it belongs to a
## ButtonGroup, which is the look Noggit's Type panel uses.
func _radio_block(options: Array, selected: int, on_changed: Callable) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 4)

	var box := _panel(SURFACE_RAISED, BORDER_SUBTLE, Vector4i(1, 1, 1, 1), 7)
	m.add_child(box)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	box.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	pad.add_child(col)

	var group := ButtonGroup.new()
	for i in options.size():
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 2)

		var cb := CheckBox.new()
		cb.text = String(options[i][0])
		cb.button_group = group
		cb.button_pressed = (i == selected)
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 13)
		cb.add_theme_color_override("font_color", TEXT_SECONDARY)
		cb.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)
		cb.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
		var index := i
		cb.pressed.connect(func() -> void: on_changed.call(index))
		entry.add_child(cb)

		var desc := _label(String(options[i][1]), 11, TEXT_DISABLED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(PANEL_WIDTH - 56, 0)
		entry.add_child(desc)

		col.add_child(entry)

	return m


## Compact multi-column radio grid. Six shapes with full descriptions would run
## the panel off the screen, so the description lives in the tooltip.
func _radio_grid(options: Array, selected: int, columns: int, on_changed: Callable) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 4)

	var box := _panel(SURFACE_RAISED, BORDER_SUBTLE, Vector4i(1, 1, 1, 1), 7)
	m.add_child(box)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	box.add_child(pad)

	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 9)
	# Columns are sized to their widest label by default, which left "Plateau"
	# and "Feather" setting a different column edge from "Steep" and "Pad".
	# Expanding every cell makes the columns equal thirds of the panel instead.
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_child(grid)

	var group := ButtonGroup.new()
	for i in options.size():
		var cb := CheckBox.new()
		cb.text = String(options[i][0])
		cb.tooltip_text = String(options[i][2])
		cb.button_group = group
		cb.button_pressed = (i == selected)
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 13)
		cb.add_theme_color_override("font_color", TEXT_SECONDARY)
		cb.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)
		cb.add_theme_color_override("font_hover_color", TEXT_PRIMARY)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var key := String(options[i][1])
		cb.pressed.connect(func() -> void: on_changed.call(key))
		grid.add_child(cb)

	return m


func _on_scale_ref_toggled(kind: int, on: bool) -> void:
	if _view == null:
		return
	_view.set_scale_ref(kind, on)
	if on:
		_set_status("scale", "%s %.1f m" % [_view.scale_ref_label(kind), _view.scale_ref_height(kind)])
	else:
		_set_status("scale", "scale --")


## Label, live value and slider. Matches the arrangement of a conventional
## brush panel without the spin-button clutter, which buys nothing at these
## ranges.
func _slider_row(parent: Control, caption: String, lo: float, hi: float, step: float,
		value: float, suffix: String, on_changed: Callable, hint: String = "") -> HSlider:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	parent.add_child(wrap)

	var head := HBoxContainer.new()
	head.add_child(_label(caption, 12, TEXT_SECONDARY))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spring)
	var readout := _label("%.1f%s" % [value, suffix], 12, TEXT_PRIMARY)
	head.add_child(readout)
	wrap.add_child(head)

	var slider := HSlider.new()
	slider.tooltip_text = hint
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 16)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = "%.1f%s" % [v, suffix]
		on_changed.call(v))
	wrap.add_child(slider)

	return slider


func _settings_block() -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 4)

	var box := _panel(SURFACE_RAISED, BORDER_SUBTLE, Vector4i(1, 1, 1, 1), 7)
	m.add_child(box)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	box.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	pad.add_child(col)

	_radius_slider = _slider_row(col, "Radius", 2.0, 200.0, 1.0, 40.0, " m",
		func(v: float) -> void:
			if _view and not _syncing:
				_view.set_brush_radius(v))

	_strength_slider = _slider_row(col, "Strength", 1.0, 100.0, 1.0, 33.0, "",
		func(v: float) -> void:
			if _view and not _syncing:
				_view.set_brush_strength(v),
		"Squared response: the lower half stays fine for detail, the upper half hits hard.
10 → 3    33 → 33    50 → 76    75 → 170    100 → 303")

	return m


## Shift/Ctrl + Wheel also changes the radius, so the slider has to follow the
## viewport rather than only drive it. The guard stops the round trip.
## Header plus modifier legend for one tool, wrapped so it can be shown or
## hidden as a unit.
func _tool_section(parent: Control, title: String, rows: Array, footer: String = "") -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	wrap.add_child(_section(title))
	wrap.add_child(_note_block(rows, footer))
	parent.add_child(wrap)
	return wrap


func _on_tool_selected(index: int) -> void:
	_current_tool = index
	for i in _tool_sections.size():
		_tool_sections[i].visible = (i == index)
	if _areas_section:
		_areas_section.visible = (index == Sculpt.Tool.AREA)
	if _pass_section:
		_pass_section.visible = (index == Sculpt.Tool.PASSABILITY)
	if _water_section:
		_water_section.visible = (index == Sculpt.Tool.WATER)
		if index == Sculpt.Tool.WATER:
			_sync_level_slider()
	# Shape and Mode both describe how a brush DEPOSITS. The layer tools write a
	# value instead, so neither applies to them.
	var deposits: bool = index == Sculpt.Tool.SCULPT or index == Sculpt.Tool.FLATTEN
	if _mode_section:
		_mode_section.visible = deposits
	if _shape_section:
		_shape_section.visible = deposits
	if _view:
		_view.set_tool(index)
		# The colours ARE the tool's view. Selecting Areas without seeing them,
		# or leaving them tinting the ground while sculpting, are both wrong.
		_view.set_area_overlay(index == Sculpt.Tool.AREA)
		_view.set_passability_overlay(index == Sculpt.Tool.PASSABILITY)
		# Water is the one layer that is not a diagram -- it is a thing in the
		# world -- but it still follows the tool, so the terrain stays readable
		# while you shape the bed it will sit in.
		_view.set_water_overlay(index == Sculpt.Tool.WATER)


## The area tree, each entry keyed by its own colour so the list and the
## overlay read as the same thing.
func _areas_block(parent: Control) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	wrap.add_child(_section("Zones"))

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 4)

	var box := _panel(SURFACE_RAISED, BORDER_SUBTLE, Vector4i(1, 1, 1, 1), 7)
	m.add_child(box)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	box.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	pad.add_child(col)

	var registry: Dictionary = _view.area_registry() if _view else {}
	var group := ButtonGroup.new()
	var first := true
	for id in registry:
		var def = registry[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)

		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.add_theme_stylebox_override("panel",
			_sb(def.colour, BORDER_DEFAULT, Vector4i(1, 1, 1, 1), 3))
		row.add_child(swatch)

		var cb := CheckBox.new()
		# Indented by depth, so the tree is readable without a tree widget.
		var depth := 0
		var cur: int = def.parent
		while registry.has(cur) and depth < 8:
			depth += 1
			cur = registry[cur].parent
		cb.text = "    ".repeat(depth) + def.name
		cb.tooltip_text = "%d  ·  %s" % [def.id, _view.area_path(def.id) if _view else def.name]
		cb.button_group = group
		cb.button_pressed = first
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 12)
		cb.add_theme_color_override("font_color", TEXT_SECONDARY)
		cb.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)
		var aid: int = def.id
		cb.pressed.connect(func() -> void:
			if _view:
				_view.set_area_selection(aid))
		row.add_child(cb)

		col.add_child(row)
		first = false

	wrap.add_child(m)
	parent.add_child(wrap)
	return wrap


## Bodies, level and the two buttons that place a surface.
##
## Laid out like the zone list on purpose: same swatch, same indent, same
## selection model. These are all layer tools and they should not each invent
## their own panel.
func _water_block(parent: Control) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	wrap.add_child(_section("Bodies"))

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 4)

	var box := _panel(SURFACE_RAISED, BORDER_SUBTLE, Vector4i(1, 1, 1, 1), 7)
	m.add_child(box)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	box.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pad.add_child(col)

	# Fill or Brush. Two genuinely different gestures, not two strengths of the
	# same one: a fill states a basin and a level, a brush states a shape.
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	var mode_group := ButtonGroup.new()
	for entry in [["Fill basin", true], ["Brush", false]]:
		var mb := CheckBox.new()
		mb.text = String(entry[0])
		mb.button_group = mode_group
		mb.button_pressed = bool(entry[1])
		mb.focus_mode = Control.FOCUS_NONE
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mb.add_theme_font_size_override("font_size", 12)
		mb.add_theme_color_override("font_color", TEXT_SECONDARY)
		mb.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)
		var is_fill: bool = bool(entry[1])
		mb.pressed.connect(func() -> void:
			if _view:
				_view.water_fill_mode = is_fill
			_update_water_hint(is_fill))
		modes.add_child(mb)
	col.add_child(modes)

	_water_rows = VBoxContainer.new()
	_water_rows.add_theme_constant_override("separation", 7)
	col.add_child(_water_rows)
	_rebuild_water_rows()

	# Level is the body, in one number. Dragging it moves the shoreline across
	# the terrain in real time, which a height-per-cell layer could not do at
	# all: every cell would have to be repainted and they would drift apart.
	_level_slider = _slider_row(col, "Level", 0.0, 1.0, 0.25, 0.0, " m",
		func(v: float) -> void:
			if _view and not _syncing:
				_view.set_water_level(_selected_body(), v),
		"Surface height in world metres. Water reaches wherever the ground sits below it.")

	_level_slider.drag_ended.connect(func(changed: bool) -> void:
		# During the drag the shoreline already moves within the extent the body
		# has, so it reads live. On release the basin is found again, which is
		# the part worth paying a flood fill for.
		if changed and _view:
			_view.refill_water(_selected_body()))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)

	var sample := Button.new()
	sample.text = "Sample"
	sample.tooltip_text = "Put the surface exactly at the ground under the cursor."
	sample.focus_mode = Control.FOCUS_NONE
	sample.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sample.pressed.connect(func() -> void:
		if _view == null:
			return
		var y: float = _view.sample_water_level(_selected_body())
		if is_nan(y):
			_set_status("scale", "point at the ground first")
		else:
			_sync_level_slider())
	buttons.add_child(sample)

	var make := Button.new()
	make.text = "New"
	make.tooltip_text = "Add another body with its own level."
	make.focus_mode = Control.FOCUS_NONE
	make.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	make.pressed.connect(func() -> void:
		if _view == null:
			return
		var id: int = _view.add_water_body()
		if id != 0:
			_view.set_water_selection(id)
			_rebuild_water_rows()
			_sync_level_slider())
	buttons.add_child(make)

	col.add_child(buttons)

	wrap.add_child(m)
	parent.add_child(wrap)
	return wrap


## Shared by both modes: the sentence that explains why the shoreline is not
## something you draw.
const WATER_NOTE := ("Water reaches wherever the ground sits below the level, "
	+ "so the shoreline is found rather than drawn. Sculpt the bed and it moves.")


static func _water_rows_for(fill: bool) -> Array:
	if fill:
		return [
			["Shift + LMB", "flood the basin under the cursor"],
			["Ctrl + LMB", "remove the body"],
			["Level", "re-floods when you let go"],
		]
	return [
		["Shift + LMB", "paint the selected body"],
		["Ctrl + LMB", "erase the footprint"],
		["Shift/Ctrl + Wheel", "brush radius"],
	]


## Swaps the modifier legend when the mode changes, since the two modes do not
## share a single binding.
func _update_water_hint(fill: bool) -> void:
	if _water_notes == null:
		return
	for c in _water_notes.get_children():
		c.queue_free()
	_water_notes.add_child(_section("Water"))
	_water_notes.add_child(_note_block(_water_rows_for(fill), WATER_NOTE))


func _selected_body() -> int:
	if _level_group == null:
		return 1
	var on := _level_group.get_pressed_button()
	return int(on.get_meta("body_id")) if on else 1


## Rebuilt rather than appended to, because New has to renumber nothing and the
## list is never long enough for the difference to matter.
func _rebuild_water_rows() -> void:
	if _water_rows == null:
		return
	for c in _water_rows.get_children():
		c.queue_free()

	_level_group = ButtonGroup.new()
	var registry: Dictionary = _view.water_bodies() if _view else {}
	var first := true
	for id in registry:
		var b = registry[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)

		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.add_theme_stylebox_override("panel",
			_sb(b.colour, BORDER_DEFAULT, Vector4i(1, 1, 1, 1), 3))
		row.add_child(swatch)

		var cb := CheckBox.new()
		cb.text = String(b.name)
		cb.button_group = _level_group
		cb.button_pressed = first
		cb.focus_mode = Control.FOCUS_NONE
		cb.set_meta("body_id", int(id))
		cb.add_theme_font_size_override("font_size", 12)
		cb.add_theme_color_override("font_color", TEXT_SECONDARY)
		cb.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)
		var bid: int = int(id)
		cb.pressed.connect(func() -> void:
			if _view:
				_view.set_water_selection(bid)
			_sync_level_slider())
		row.add_child(cb)

		_water_rows.add_child(row)
		first = false


## The slider follows the selected body, and a first click on an unlevelled body
## places its surface, so the panel has to be able to catch up with the viewport
## rather than only drive it.
func _sync_level_slider() -> void:
	if _level_slider == null or _view == null:
		return
	_syncing = true
	# Ranged to the ground each time, because the region can be regenerated.
	var hr: Vector2 = _view.terrain_height_range()
	_level_slider.min_value = floorf(hr.x) - 20.0
	_level_slider.max_value = ceilf(hr.y) + 20.0
	_level_slider.value = _view.water_level(_selected_body())
	_syncing = false


## The two override kinds, drawn with the swatch-plus-label shape the zone list
## already uses so the panel reads as one family of layer tools.
func _pass_block(parent: Control) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 0)
	wrap.add_child(_section("Override"))

	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 4)

	var box := _panel(SURFACE_RAISED, BORDER_SUBTLE, Vector4i(1, 1, 1, 1), 7)
	m.add_child(box)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	box.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 9)
	pad.add_child(col)

	# Swatches are the overlay colours lifted out of dark, since the overlay is
	# additive over terrain and the raw values are nearly black on their own.
	var kinds := [
		[Passability.State.BLOCKED, "Blocked", Passability.BLOCKED_TINT,
			"Impassable whatever the ground says. Map edges, unbuilt regions."],
		[Passability.State.OPEN, "Open", Passability.OPEN_TINT,
			"Passable whatever the ground says. Stairs and bridges too steep to read as walkable."],
	]
	var group := ButtonGroup.new()
	var first := true
	for k in kinds:
		var entry := VBoxContainer.new()
		entry.add_theme_constant_override("separation", 2)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 9)

		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(14, 14)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tint: Color = k[2]
		tint = tint.lerp(Color.WHITE, 0.35)
		tint.a = 1.0
		swatch.add_theme_stylebox_override("panel",
			_sb(tint, BORDER_DEFAULT, Vector4i(1, 1, 1, 1), 3))
		row.add_child(swatch)

		var cb := CheckBox.new()
		cb.text = String(k[1])
		cb.button_group = group
		cb.button_pressed = first
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 13)
		cb.add_theme_color_override("font_color", TEXT_SECONDARY)
		cb.add_theme_color_override("font_pressed_color", TEXT_PRIMARY)
		var state: int = int(k[0])
		cb.pressed.connect(func() -> void:
			if _view:
				_view.set_passability_paint(state))
		row.add_child(cb)
		entry.add_child(row)

		var desc := _label(String(k[3]), 11, TEXT_DISABLED)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(PANEL_WIDTH - 56, 0)
		entry.add_child(desc)

		col.add_child(entry)
		first = false

	wrap.add_child(m)
	parent.add_child(wrap)
	return wrap


func _on_brush_changed(radius: float, strength: float) -> void:
	_syncing = true
	if _radius_slider:
		_radius_slider.value = radius
	if _strength_slider:
		_strength_slider.value = strength
	_syncing = false


func _on_brush_shape_changed(shape_key: String) -> void:
	if _view:
		_view.set_brush_shape(shape_key)


func _on_sculpt_mode_changed(index: int) -> void:
	if _view:
		_view.set_sculpt_mode(index)


## A small key/action table. Used while tools are discoverable-by-note rather
## than by icon; real controls replace these blocks as each tool lands.
static func _note_block(rows: Array, footer: String = "") -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 4)

	var box := _panel(SURFACE_RAISED, BORDER_SUBTLE, Vector4i(1, 1, 1, 1), 7)
	m.add_child(box)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	box.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	pad.add_child(col)

	for row in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var key := _label(String(row[0]), 12, RED_PRIMARY)
		key.custom_minimum_size = Vector2(118, 0)
		line.add_child(key)
		line.add_child(_label(String(row[1]), 12, TEXT_SECONDARY))
		col.add_child(line)

	if footer != "":
		var rule := Panel.new()
		rule.custom_minimum_size = Vector2(0, 1)
		rule.add_theme_stylebox_override("panel", _sb(BORDER_DEFAULT))
		col.add_child(rule)
		var f := _label(footer, 11, TEXT_DISABLED)
		f.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		f.custom_minimum_size = Vector2(PANEL_WIDTH - 56, 0)
		col.add_child(f)

	return m


## Empty content area. Controls go here once tools are wired; showing the
## reserved space beats filling it with settings that do nothing.
func _placeholder_block(height: int) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 4)

	var box := _panel(SURFACE_RAISED, BORDER_SUBTLE, Vector4i(1, 1, 1, 1), 7)
	box.custom_minimum_size = Vector2(0, height)
	m.add_child(box)
	return m


func _status_bar() -> Control:
	var bar := _panel(SURFACE_RAIL, BORDER_SUBTLE, Vector4i(0, 1, 0, 0))
	bar.custom_minimum_size = Vector2(0, STATUS_HEIGHT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	bar.add_child(row)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(10, 0)
	row.add_child(pad)

	for entry in [["region", "region --"], ["tile", "region --  chunk --"], ["cursor", "cursor --"]]:
		var l := _label(entry[1], 11, TEXT_DISABLED)
		_status[entry[0]] = l
		row.add_child(l)

	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spring)

	for entry in [["scale", "scale --"], ["pos", "cam --"], ["edits", "edits 0"], ["chunks", "chunks --"], ["fps", "fps --"]]:
		var l := _label(entry[1], 11, TEXT_DISABLED)
		_status[entry[0]] = l
		row.add_child(l)

	var tail := Control.new()
	tail.custom_minimum_size = Vector2(10, 0)
	row.add_child(tail)

	return bar


func _on_region_menu(id: int) -> void:
	if _view == null:
		return
	match id:
		0:
			_view.generate()
			_refresh_region_status()
			_view.refresh_grid()
		1:
			_view.clear_region()
			_refresh_region_status()
			_view.refresh_grid()
		2:
			_view.frame_region()


func _refresh_region_status() -> void:
	if _view == null:
		return
	var region = _view.region
	if region and "extent_m" in region:
		_set_status("region", "region %d m  seed %d" % [region.get("extent_m"), region.get("seed")])
	var terrain = _view.terrain
	if terrain:
		var data = terrain.get("data")
		if data:
			_set_status("chunks", "chunks %d" % data.get_region_count())


func _process(_delta: float) -> void:
	# Cheap, and it makes the bar feel like a tool rather than a mock-up.
	_set_status("fps", "fps %d" % Engine.get_frames_per_second())
