@tool
extends EditorPlugin
## Registers the Animosis materials workspace.
##
## A separate plugin rather than another screen on the terrain one: an
## EditorPlugin may declare only a single main screen, and these are genuinely
## separate tools that happen to share a host.
##
## Same overlay approach as the terrain workspace -- parented to the editor's
## base control so it covers the whole window, with its own exit affordance.

const Workspace := preload("res://addons/animosis_library/library_workspace.gd")

const FALLBACK_SCREEN := "3D"

var _workspace: Control


func _enter_tree() -> void:
	_workspace = Workspace.new()
	_workspace.name = "AnimosisLibraryWorkspace"
	_workspace.exit_requested.connect(_on_exit_requested)

	var base := EditorInterface.get_base_control()
	base.add_child(_workspace)
	_workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_workspace.mouse_filter = Control.MOUSE_FILTER_STOP
	_workspace.hide()


func _exit_tree() -> void:
	if is_instance_valid(_workspace):
		_workspace.queue_free()
	_workspace = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if not is_instance_valid(_workspace):
		return
	_workspace.visible = visible
	if visible:
		_workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var base := EditorInterface.get_base_control()
		base.move_child(_workspace, base.get_child_count() - 1)
		_workspace.grab_focus()


func _on_exit_requested() -> void:
	EditorInterface.set_main_screen_editor(FALLBACK_SCREEN)


func _get_plugin_name() -> String:
	return "Library"


func _get_plugin_icon() -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	for candidate in ["StandardMaterial3D", "Material", "Node3D"]:
		if theme.has_icon(candidate, "EditorIcons"):
			return theme.get_icon(candidate, "EditorIcons")
	return null
