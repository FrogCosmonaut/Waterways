@tool
class_name WaterwaysCleanOrphanButton
extends Button

const _MSG_EMPTY: String = "No unused baked texture files were found in the scene's _waterways folder."
const _MSG_CONFIRM: String = "The following baked texture files no longer belong to any river or system in this scene and will be permanently deleted:\n\n%s"

var _orphaned_textures: PackedStringArray = []

@onready var _confirm_dialog: ConfirmationDialog = $ConfirmationDialog


func _ready() -> void:
	if not Engine.is_editor_hint():
		return

	icon = EditorInterface.get_base_control().get_theme_icon("Clear", "EditorIcons")


func _on_pressed() -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	_orphaned_textures = WaterwaysHelperMethods.find_orphaned_baked_textures(scene_root)

	if _orphaned_textures.is_empty():
		_confirm_dialog.dialog_text = _MSG_EMPTY
		_confirm_dialog.ok_button_text = "OK"
		_confirm_dialog.get_cancel_button().visible = false
	else:
		_confirm_dialog.dialog_text = _MSG_CONFIRM % "\n".join(_orphaned_textures)
		_confirm_dialog.ok_button_text = "Delete"
		_confirm_dialog.get_cancel_button().visible = true

	_confirm_dialog.popup_centered()


func _on_confirmation_dialog_confirmed() -> void:
	if _orphaned_textures.is_empty():
		return
	WaterwaysHelperMethods.delete_baked_textures(_orphaned_textures)
	_orphaned_textures.clear()
