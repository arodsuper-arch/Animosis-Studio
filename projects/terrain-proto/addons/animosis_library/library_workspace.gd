@tool
extends Control
## Animosis library workspace — shell.
##
## A CATALOG, not an authoring tool. Materials come from Substance; this browses
## them, carries the properties runtime systems read, and declares how each one
## appears under each runtime effect.
##
## Three panes: the catalog, a live preview under the real renderer, and the
## detail column. The preview can be driven into an effect state, so burning
## timber and burning cloth can be compared directly -- which is the point of
## declaring appearance per material instead of per effect.
##
## Reuses the terrain workspace's styling helpers rather than duplicating them,
## and like that workspace holds no EditorInterface references, so it could be
## hosted standalone later.

signal exit_requested

const UI := preload("res://addons/animosis_terrain/workspace.gd")
const MaterialDef := preload("res://addons/animosis_library/material_def.gd")

## Effect the preview is currently showing. "" = base material.
var _preview_effect: String = ""

const RAIL_WIDTH := 52
const RAIL_SLOTS := 13
const LIST_WIDTH := 200
const PANEL_WIDTH := 300
const MENU_HEIGHT := 30
const STATUS_HEIGHT := 26

var _materials: Array = []
var _selected: int = 0

var _list_column: VBoxContainer
var _asset_type: String = "material"
var _props_column: VBoxContainer
var _preview_mesh: MeshInstance3D
var _status: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	_materials = MaterialDef.defaults()
	_build()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		exit_requested.emit()
		accept_event()


# ------------------------------------------------------------------ build --

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UI.SURFACE_BASE
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

	body.add_child(_asset_rail())
	body.add_child(_list_pane())
	body.add_child(_preview_pane())
	body.add_child(_property_pane())

	root.add_child(_status_bar())
	_select(0)


func _menu_bar() -> Control:
	var bar := UI._panel(UI.SURFACE_RAIL, UI.BORDER_SUBTLE, Vector4i(0, 0, 0, 1))
	bar.custom_minimum_size = Vector2(0, MENU_HEIGHT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	bar.add_child(row)

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(6, 0)
	row.add_child(pad)

	# No menus until they do something. Empty popups read as broken.
	row.add_child(UI._label("Library", 13, UI.TEXT_PRIMARY))

	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spring)
	row.add_child(UI._label("terrain and model materials", 11, UI.TEXT_DISABLED))

	var exit_btn := Button.new()
	exit_btn.text = "Exit"
	exit_btn.tooltip_text = "Return to the engine  (Esc)"
	exit_btn.flat = true
	exit_btn.focus_mode = Control.FOCUS_NONE
	exit_btn.custom_minimum_size = Vector2(60, 0)
	exit_btn.add_theme_font_size_override("font_size", 12)
	exit_btn.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	exit_btn.add_theme_color_override("font_hover_color", UI.TEXT_PRIMARY)
	exit_btn.add_theme_stylebox_override("normal", UI._sb(Color.TRANSPARENT))
	exit_btn.add_theme_stylebox_override("hover", UI._sb(Color("#C1272D"), Color.TRANSPARENT, Vector4i.ZERO, 4))
	exit_btn.pressed.connect(func() -> void: exit_requested.emit())
	row.add_child(exit_btn)

	var tail := Control.new()
	tail.custom_minimum_size = Vector2(6, 0)
	row.add_child(tail)
	return bar


## Same rail the terrain workspace carries, so both pages read as one tool.
## There it selects the brush; here it selects which kind of asset the list
## shows. Identical affordance, identical selected state.
func _asset_rail() -> Control:
	var rail := UI._panel(UI.SURFACE_RAIL, UI.BORDER_SUBTLE, Vector4i(0, 0, 1, 0))
	rail.custom_minimum_size = Vector2(RAIL_WIDTH, 0)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_BEGIN
	rail.add_child(col)

	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 6)
	col.add_child(top)

	var group := ButtonGroup.new()
	var kinds := [
		["material", "Materials  —  surfaces imported from Substance"],
		["model",    "Models  —  meshes and props"],
	]
	for i in RAIL_SLOTS:
		var b: Button
		if i < kinds.size():
			var key := String(kinds[i][0])
			b = UI._tool_slot(RAIL_WIDTH - 12, key, String(kinds[i][1]), group, i == 0)
			b.toggled.connect(func(on: bool) -> void:
				if on:
					_asset_type = key
					_rebuild_list()
					_select(0))
		else:
			b = UI._slot(RAIL_WIDTH - 12)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(b)
		if i == 4 or i == 8:
			var sep := Panel.new()
			sep.custom_minimum_size = Vector2(RAIL_WIDTH - 20, 1)
			sep.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			sep.add_theme_stylebox_override("panel", UI._sb(UI.BORDER_DEFAULT))
			col.add_child(sep)

	return rail


func _list_pane() -> Control:
	var pane := UI._panel(UI.SURFACE_RAIL, UI.BORDER_SUBTLE, Vector4i(0, 0, 1, 0))
	pane.custom_minimum_size = Vector2(LIST_WIDTH, 0)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pane.add_child(scroll)

	_list_column = VBoxContainer.new()
	_list_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_column.add_theme_constant_override("separation", 2)
	scroll.add_child(_list_column)

	_rebuild_list()
	return pane


func _rebuild_list() -> void:
	for c in _list_column.get_children():
		c.queue_free()

	var head := UI._label("  Smart materials" if _asset_type == "material" else "  Models",
		11, UI.TEXT_DISABLED)
	head.custom_minimum_size = Vector2(0, 26)
	head.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_list_column.add_child(head)

	# Models are not imported yet. Saying so beats an empty column that looks
	# like a failure.
	if _asset_type == "model":
		var empty := UI._label("  nothing imported", 11, UI.TEXT_DISABLED)
		empty.custom_minimum_size = Vector2(0, 30)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_list_column.add_child(empty)
		return

	var group := ButtonGroup.new()
	var last_category := ""
	for i in _materials.size():
		var m = _materials[i]
		# Group by what consumes the material: terrain, structure, character.
		if m.category != last_category:
			last_category = m.category
			var heading := "Terrain" if m.category == "terrain" else "Models"
			var cat := UI._label("  %s" % heading, 10, UI.TEXT_DISABLED)
			cat.custom_minimum_size = Vector2(0, 22)
			cat.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			_list_column.add_child(cat)
		var b := Button.new()
		b.text = "  %s" % m.display_name
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = (i == _selected)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 32)
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
		b.add_theme_color_override("font_pressed_color", UI.TEXT_PRIMARY)
		b.add_theme_stylebox_override("normal", UI._sb(Color.TRANSPARENT))
		b.add_theme_stylebox_override("hover", UI._sb(UI.SURFACE_HOVER))
		b.add_theme_stylebox_override("pressed", UI._sb(Color("#2A1116"), UI.RED_PRIMARY, Vector4i(2, 0, 0, 0)))
		b.add_theme_stylebox_override("hover_pressed", UI._sb(Color("#331419"), UI.RED_PRIMARY, Vector4i(2, 0, 0, 0)))
		var idx := i
		b.pressed.connect(func() -> void: _select(idx))
		_list_column.add_child(b)


## Preview under the real renderer, for the same reason terrain is: a material
## judged in a different pipeline is a material judged wrong.
func _preview_pane() -> Control:
	var host := Control.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.clip_contents = true

	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(vpc)

	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vp.msaa_3d = Viewport.MSAA_2X
	vpc.add_child(vp)

	_preview_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	_preview_mesh.mesh = sphere
	vp.add_child(_preview_mesh)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	vp.add_child(sun)
	sun.look_at_from_position(Vector3(3, 4, 3), Vector3.ZERO, Vector3.UP)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = UI.SURFACE_SUNKEN
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.37, 0.40)
	e.ambient_light_energy = 0.7
	env.environment = e
	vp.add_child(env)

	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.1, 3.1), Vector3.ZERO, Vector3.UP)

	var hint := UI._label("preview  ·  no maps imported, standing in from properties", 11, UI.TEXT_DISABLED)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.position = Vector2(14, -26)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(hint)

	return host


func _property_pane() -> Control:
	var pane := UI._panel(UI.SURFACE_BASE, UI.BORDER_SUBTLE, Vector4i(1, 0, 0, 0))
	pane.custom_minimum_size = Vector2(PANEL_WIDTH, 0)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pane.add_child(scroll)

	_props_column = VBoxContainer.new()
	_props_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_props_column.add_theme_constant_override("separation", 0)
	scroll.add_child(_props_column)

	return pane


func _rebuild_properties() -> void:
	for c in _props_column.get_children():
		c.queue_free()
	if _materials.is_empty():
		return

	var m = _materials[_selected]

	# Source is read-only by design: reimport from Substance, never edit here.
	_props_column.add_child(UI._section("Imported from Substance"))
	var rows: Array = []
	rows.append(["substance", m.source_path if m.source_path != "" else "not imported"])
	for key in ["albedo", "normal", "roughness", "height"]:
		var path: String = m.maps.get(key, "")
		rows.append([key, path if path != "" else "—"])
	_props_column.add_child(UI._note_block(rows))

	_props_column.add_child(UI._section("Smart material"))
	_props_column.add_child(_effects_block(m))

	_props_column.add_child(UI._section("Applied to"))
	var used: Array = []
	if m.used_by.is_empty():
		used.append(["nothing", "not referenced"])
	else:
		for u in m.used_by:
			used.append([u, ""])
	_props_column.add_child(UI._note_block(used))


## Attaches itself to `parent` and hands back the inner column to fill. Walking
## back up the tree to find the outer node instead was one node short and tried
## to re-parent a node that already had one.
## The smart part of a smart material: how this surface looks in each runtime
## state. Selecting one drives the PREVIEW, so burning timber and burning cloth
## can be compared directly -- which is the whole argument for declaring
## appearance per material rather than per effect.
func _effects_block(mat) -> Control:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 4)

	var box := UI._panel(UI.SURFACE_RAISED, UI.BORDER_SUBTLE, Vector4i(1, 1, 1, 1), 7)
	m.add_child(box)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	box.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pad.add_child(col)

	var group := ButtonGroup.new()

	var base_btn := CheckBox.new()
	base_btn.text = "Base"
	base_btn.button_group = group
	base_btn.button_pressed = (_preview_effect == "")
	base_btn.focus_mode = Control.FOCUS_NONE
	base_btn.add_theme_font_size_override("font_size", 12)
	base_btn.add_theme_color_override("font_color", UI.TEXT_SECONDARY)
	base_btn.add_theme_color_override("font_pressed_color", UI.TEXT_PRIMARY)
	base_btn.pressed.connect(func() -> void:
		_preview_effect = ""
		_refresh_preview())
	col.add_child(base_btn)

	for key in MaterialDef.EFFECTS:
		var spec: Array = MaterialDef.EFFECTS[key]
		var st = mat.effect(key)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var cb := CheckBox.new()
		cb.text = String(spec[0])
		cb.button_group = group
		cb.button_pressed = (_preview_effect == key)
		cb.disabled = not st.enabled
		cb.focus_mode = Control.FOCUS_NONE
		cb.tooltip_text = "Requires capability: %s" % String(spec[1]) if st.enabled 			else "%s declares no appearance for this state" % mat.display_name
		cb.add_theme_font_size_override("font_size", 12)
		cb.add_theme_color_override("font_color", UI.TEXT_SECONDARY if st.enabled else UI.TEXT_DISABLED)
		cb.add_theme_color_override("font_pressed_color", UI.TEXT_PRIMARY)
		var k := String(key)
		cb.pressed.connect(func() -> void:
			_preview_effect = k
			_refresh_preview())
		row.add_child(cb)

		var spring := Control.new()
		spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spring)

		if st.enabled:
			var swatch := Panel.new()
			swatch.custom_minimum_size = Vector2(26, 14)
			swatch.add_theme_stylebox_override("panel", UI._sb(st.tint, UI.BORDER_DEFAULT, Vector4i(1, 1, 1, 1), 3))
			row.add_child(swatch)
		else:
			row.add_child(UI._label("not declared", 10, UI.TEXT_DISABLED))

		col.add_child(row)

	m.add_child(Control.new())
	return m


func _block(parent: Control) -> VBoxContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_right", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 4)

	var box := UI._panel(UI.SURFACE_RAISED, UI.BORDER_SUBTLE, Vector4i(1, 1, 1, 1), 7)
	m.add_child(box)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 12)
	box.add_child(pad)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pad.add_child(col)
	parent.add_child(m)
	return col


func _prop_slider(parent: VBoxContainer, mat, key: String, spec: Array) -> void:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 3)
	parent.add_child(wrap)

	var head := HBoxContainer.new()
	head.add_child(UI._label(String(spec[0]), 12, UI.TEXT_SECONDARY))
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spring)
	var readout := UI._label("%.2f%s" % [float(mat.properties[key]), String(spec[4])], 12, UI.TEXT_PRIMARY)
	head.add_child(readout)
	wrap.add_child(head)

	var slider := HSlider.new()
	slider.min_value = float(spec[1])
	slider.max_value = float(spec[2])
	slider.step = (float(spec[2]) - float(spec[1])) / 200.0
	slider.value = float(mat.properties[key])
	slider.custom_minimum_size = Vector2(0, 14)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float) -> void:
		mat.properties[key] = v
		readout.text = "%.2f%s" % [v, String(spec[4])]
		_refresh_preview())
	wrap.add_child(slider)


func _select(index: int) -> void:
	if _asset_type != "material" or _materials.is_empty():
		if _props_column:
			for c in _props_column.get_children():
				c.queue_free()
		if _status:
			_status.text = "  no models imported"
		return
	if index < 0 or index >= _materials.size():
		return
	_selected = index
	_rebuild_properties()
	_refresh_preview()
	if _status:
		var m = _materials[_selected]
		var declared := 0
		for k in m.effects:
			if m.effects[k].enabled:
				declared += 1
		_status.text = "  %s   ·   %s   ·   %d properties   ·   %d effect states   ·   used by %d" % [
			m.id, m.category, m.properties.size(), declared, m.used_by.size()]


## Until real maps are imported, the preview stands in for them using the
## simulation values, so the sphere still says something true about the
## material rather than showing a lie.
func _refresh_preview() -> void:
	if _preview_mesh == null or _materials.is_empty():
		return
	var m = _materials[_selected]
	var mat := StandardMaterial3D.new()
	var hardness: float = float(m.properties.get("hardness", 0.5))
	var flam: float = float(m.properties.get("flammability", 0.0))

	# Stand-in for the imported maps, derived from the properties so the sphere
	# still says something true rather than showing an invented surface.
	var base := Color(0.32 + flam * 0.30, 0.34 + (1.0 - flam) * 0.10, 0.30).lerp(
		Color(0.55, 0.55, 0.58), hardness * 0.55)
	var rough := clampf(1.0 - hardness * 0.55, 0.25, 1.0)

	if _preview_effect != "":
		var st = m.effect(_preview_effect)
		if st and st.enabled:
			base = base.lerp(st.tint, 0.75)
			rough = clampf(rough + st.roughness_shift, 0.05, 1.0)
			if st.emission > 0.0:
				mat.emission_enabled = true
				mat.emission = st.tint
				mat.emission_energy_multiplier = st.emission

	mat.albedo_color = base
	mat.roughness = rough
	mat.metallic = 0.0
	_preview_mesh.material_override = mat


func _status_bar() -> Control:
	var bar := UI._panel(UI.SURFACE_RAIL, UI.BORDER_SUBTLE, Vector4i(0, 1, 0, 0))
	bar.custom_minimum_size = Vector2(0, STATUS_HEIGHT)
	_status = UI._label("", 11, UI.TEXT_DISABLED)
	_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar.add_child(_status)
	return bar
