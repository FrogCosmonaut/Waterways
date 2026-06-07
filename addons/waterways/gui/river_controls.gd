# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
@tool
class_name WaterwaysRiverControls
extends HBoxContainer

signal generate_flowmap_requested
signal mode_changed(mode: Mode)
signal constraint_selected(constraint: Constraint)
signal options_changed(option: Option, value: bool)
signal generate_mesh_requested
signal debug_view_changed(id: int)

enum Mode {
	SELECT,
	ADD,
	REMOVE,
}

enum Option {
	LOCAL_MODE,
	LOCK_SELECTION,
}

enum Constraint {
	NONE,
	COLLIDERS,
	AXIS_X,
	AXIS_Y,
	AXIS_Z,
	PLANE_YZ,
	PLANE_XZ,
	PLANE_XY,
}


var debug_view_menu_selected: int = 0
var constraint := Constraint.NONE

var _mouse_down: bool
var _lock_icon_open: Texture2D
var _lock_icon_closed: Texture2D

@onready var _bake_button: Button = %BakeButton
@onready var _select_button: Button = %SelectButton
@onready var _add_button: Button = %AddButton
@onready var _remove_button: Button = %RemoveButton
@onready var _constraints_texture_rect: TextureRect = %ConstraintsTextureRect
@onready var _constraints_button: OptionButton = %ConstraintsButton
@onready var _local_mode_button: Button = %LocalModeButton
@onready var _lock_selection_button: Button = %LockSelectionButton
@onready var _mesh_button: Button = %MeshButton
@onready var _debug_button: Button = %DebugButton
@onready var _debug_popup_menu: PopupMenu = %DebugPopupMenu


func _ready() -> void:
	if not Engine.is_editor_hint():
		return

	_load_editor_icons()


func _enter_tree() -> void:
	if not is_node_ready():
		await ready


func _load_editor_icons() -> void:
	var gui := EditorInterface.get_base_control()
	_constraints_texture_rect.texture = gui.get_theme_icon("3D", "EditorIcons")
	_local_mode_button.icon = gui.get_theme_icon("Object", "EditorIcons")
	_lock_selection_button.icon = gui.get_theme_icon("Object", "EditorIcons")
	_bake_button.icon = gui.get_theme_icon("Bake", "EditorIcons")
	_select_button.icon = gui.get_theme_icon("CurveEdit", "EditorIcons")
	_add_button.icon = gui.get_theme_icon("CurveCreate", "EditorIcons")
	_remove_button.icon = gui.get_theme_icon("CurveDelete", "EditorIcons")
	_mesh_button.icon = gui.get_theme_icon("MultiMeshInstance3D", "EditorIcons")
	_debug_button.icon = gui.get_theme_icon("Debug", "EditorIcons")
	_lock_icon_open = gui.get_theme_icon("Unlock", "EditorIcons")
	_lock_icon_closed = gui.get_theme_icon("Lock", "EditorIcons")
	_on_lock_selection_toggled(_lock_selection_button.disabled)


func spatial_gui_input(event: InputEvent) -> bool:
	# This uses the forwarded spatial input in order to not react to events
	# while the spatial editor is not in focus

	# This is to avoid that the contraints are toggled while navigating 
	# the scene with WASD holding the right mouse button
	if event is InputEventMouseButton:
		_mouse_down = event.pressed

	if event is InputEventKey and event.is_pressed() and not _constraints_button.disabled:
		# Early exit if any of the modifiers (except shift) is pressed to not
		# override default shortcuts like Ctrl + Z
		if event.alt_pressed or event.ctrl_pressed or event.meta_pressed or _mouse_down:
			return false

		# Handle local mode keybinding for toggling
		if event.keycode == KEY_T:
			# Set the input as handled to prevent default actions from the keys
			_local_mode_button.button_pressed = not _local_mode_button.button_pressed
			get_viewport().set_input_as_handled()
			return true

		# Fetch the constraint that the user requested to toggle
		var requested: int
		match [event.keycode, event.shift_pressed]:
			[KEY_S, _]:
				requested = Constraint.COLLIDERS
			[KEY_X, false]:
				requested = Constraint.AXIS_X
			[KEY_Y, false]:
				requested = Constraint.AXIS_Y
			[KEY_Z, false]:
				requested = Constraint.AXIS_Z
			[KEY_X, true]:
				requested = Constraint.PLANE_YZ
			[KEY_Y, true]:
				requested = Constraint.PLANE_XZ
			[KEY_Z, true]:
				requested = Constraint.PLANE_XY
			_:
				return false

		# If the user requested the current selection, we toggle it instead to off
		if requested == _constraints_button.selected:
			requested = Constraint.NONE

		# Update the OptionsButton and call the signal callback as that is
		# only automatically called when the user clicks it
		_constraints_button.select(requested)
		_on_constraints_button_item_selected(requested)
		
		# Set the input as handled to prevent default actions from the keys
		get_viewport().set_input_as_handled()
		return true

	return false


func _on_bake_button_pressed() -> void:
	generate_flowmap_requested.emit()


func _on_select_button_pressed() -> void:
	_untoggle_points_handling_buttons()
	_disable_constraint_ui(false)
	_select_button.button_pressed = true
	mode_changed.emit(Mode.SELECT)


func _on_add_button_pressed() -> void:
	_untoggle_points_handling_buttons()
	_disable_constraint_ui(false)
	_add_button.button_pressed = true
	mode_changed.emit(Mode.ADD)


func _on_remove_button_pressed() -> void:
	_untoggle_points_handling_buttons()
	_disable_constraint_ui(true)
	_remove_button.button_pressed = true
	mode_changed.emit(Mode.REMOVE)


func _on_mesh_button_pressed() -> void:
	generate_mesh_requested.emit()


func _on_constraints_button_item_selected(index: int) -> void:
	constraint_selected.emit(index)


func _on_local_mode_toggled(toggled_on: bool) -> void:
	options_changed.emit(Option.LOCAL_MODE, toggled_on)


func _on_lock_selection_toggled(toggled_on: bool) -> void:
	_lock_selection_button.icon = _lock_icon_closed if toggled_on else _lock_icon_open
	options_changed.emit(Option.LOCK_SELECTION, toggled_on)


func _on_debug_button_toggled(toggled_on: bool) -> void:
	if toggled_on:
		var popup_pos = _debug_button.get_screen_position()
		popup_pos.y += int(_debug_button.get_size().y)
		_debug_popup_menu.position = popup_pos
		_debug_popup_menu.popup()
	else:
		_debug_popup_menu.hide()


func _on_debug_popup_menu_popup_hide() -> void:
	_debug_button.set_pressed_no_signal(false)


func _on_debug_popup_menu_id_pressed(id: int) -> void:
	# Disable the rest of the buttons. Dear Godot, why isn't this native?
	# Get the index, right now the index and id's are identical, but just in case.
	var index := _debug_popup_menu.get_item_index(id)
	for i in _debug_popup_menu.item_count:
		_debug_popup_menu.set_item_checked(i, false)

	debug_view_changed.emit(id)
	_debug_popup_menu.set_item_checked(id, true)


func _disable_constraint_ui(disable: bool) -> void:
	_constraints_button.disabled = disable
	_local_mode_button.disabled = disable


## Toggle points handling buttons
func _untoggle_points_handling_buttons() -> void:
	_select_button.button_pressed = false
	_add_button.button_pressed = false
	_remove_button.button_pressed = false


## Public method to unselect "local mode" and "lock selection" buttons
func on_hide() -> void:
	_local_mode_button.button_pressed = false
	_lock_selection_button.button_pressed = false
