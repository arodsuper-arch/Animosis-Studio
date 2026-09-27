@tool
extends EditorPlugin
## Registers the Animosis terrain workspace.
##
## The workspace is parented to the editor's BASE CONTROL, not the main-screen
## container, so it covers the whole editor window — menu bar, tab bar, docks
## and bottom panel included. Entering it should feel like opening a different
## application, not switching a tab inside a game engine.
##
## Because it covers the tab strip, the workspace owns its own exit affordance
## (button, or Escape) which hands the main screen back to 3D.
##
## workspace.gd itself has no EditorInterface references. Hosting the same UI in
## a standalone AnimosisTerrain.exe later is a change to THIS file only.

const Workspace := preload("res://addons/animosis_terrain/workspace.gd")

## Main screen to fall back to when the workspace is dismissed.
const FALLBACK_SCREEN := "3D"

var _workspace: Control


func _enter_tree() -> void:
	_workspace = Workspace.new()
	_workspace.name = "AnimosisTerrainWorkspace"
	_workspace.exit_requested.connect(_on_exit_requested)

	# Full-window overlay. Added last, so it draws above the editor chrome.
	var base := EditorInterface.get_base_control()
	base.add_child(_workspace)
	_workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_workspace.mouse_filter = Control.MOUSE_FILTER_STOP
	_workspace.hide()

	# Terrain is the primary workspace. Godot otherwise restores whichever main
	# screen the last session ended on, which with two registered plugins means
	# landing in the Library when you meant to check terrain.
	_focus_on_load.call_deferred()


func _focus_on_load() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	EditorInterface.set_main_screen_editor(_get_plugin_name())


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
		# Re-assert full-rect and top-most: docks reflow when screens change.
		_workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		EditorInterface.get_base_control().move_child(
			_workspace, EditorInterface.get_base_control().get_child_count() - 1
		)
		_workspace.grab_focus()


func _on_exit_requested() -> void:
	EditorInterface.set_main_screen_editor(FALLBACK_SCREEN)


func _get_plugin_name() -> String:
	return "Terrain"


func _get_plugin_icon() -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	for candidate in ["Terrain3D", "MeshInstance3D", "Node3D"]:
		if theme.has_icon(candidate, "EditorIcons"):
			return theme.get_icon(candidate, "EditorIcons")
	return null
