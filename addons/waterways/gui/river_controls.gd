# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
@tool
class_name WaterwaysRiverControls
extends HBoxContainer

signal mode_changed(mode: Mode)
signal options_changed(option: Option)

enum Mode {
	SELECT,
	ADD,
	REMOVE,
}

enum Option {
	CONSTRAINT,
	LOCAL_MODE,
	LOCK_SELECTION,
}

enum CONSTRAINTS {
	NONE,
	COLLIDERS,
	AXIS_X,
	AXIS_Y,
	AXIS_Z,
	PLANE_YZ,
	PLANE_XZ,
	PLANE_XY,
}

var _mouse_down: bool
var _lock_icon_open: Texture2D
var _lock_icon_closed: Texture2D

@onready var menu: MenuButton = %RiverMenu
@onready var constraints: OptionButton = %Constraints
@onready var lock_selection: Button = %LockSelection
@onready var _local_mode: CheckBox = %LocalMode
@onready var _select: Button = %Select
@onready var _add: Button = %Add
@onready var _remove: Button = %Remove


func _ready() -> void:
	_load_editor_icons()


func _load_editor_icons() -> void:
	var gui := EditorInterface.get_base_control()
	_select.icon = gui.get_theme_icon("CurveEdit", "EditorIcons")
	_add.icon = gui.get_theme_icon("CurveCreate", "EditorIcons")
	_remove.icon = gui.get_theme_icon("CurveDelete", "EditorIcons")
	_lock_icon_open = gui.get_theme_icon("Unlock", "EditorIcons")
	_lock_icon_closed = gui.get_theme_icon("Lock", "EditorIcons")
	_select.text = ""  # Remove scene text placeholder
	_add.text = ""  # Remove scene text placeholder
	_remove.text = ""  # Remove scene text placeholder
	lock_selection.text = ""  # Remove scene text placeholder
	_on_lock_selection_toggled(lock_selection.disabled)


func spatial_gui_input(event: InputEvent) -> bool:
	# This uses the forwarded spatial input in order to not react to events
	# while the spatial editor is not in focus
	
	# This is to avoid that the contraints are toggled while navigating 
	# the scene with WASD holding the right mouse button
	if event is InputEventMouseButton:
		_mouse_down = event.pressed
	
	if event is InputEventKey and event.is_pressed() and not constraints.disabled:
		
		# Early exit if any of the modifiers (except shift) is pressed to not
		# override default shortcuts like Ctrl + Z
		if event.alt_pressed or event.ctrl_pressed or event.meta_pressed or _mouse_down:
			return false
		
		# Handle local mode keybinding for toggling
		if event.keycode == KEY_T:
			# Set the input as handled to prevent default actions from the keys
			_local_mode.button_pressed = not _local_mode.button_pressed
			get_viewport().set_input_as_handled()
			return true
		
		# Fetch the constraint that the user requested to toggle
		var requested: int
		match [event.keycode, event.shift_pressed]:
			[KEY_S, _]: requested = CONSTRAINTS.COLLIDERS
			[KEY_X, false]: requested = CONSTRAINTS.AXIS_X
			[KEY_Y, false]: requested = CONSTRAINTS.AXIS_Y
			[KEY_Z, false]: requested = CONSTRAINTS.AXIS_Z
			[KEY_X, true]: requested = CONSTRAINTS.PLANE_YZ
			[KEY_Y, true]: requested = CONSTRAINTS.PLANE_XZ
			[KEY_Z, true]: requested = CONSTRAINTS.PLANE_XY
			_: return false
		
		# If the user requested the current selection, we toggle it instead to off
		if requested == constraints.selected:
			requested = CONSTRAINTS.NONE
		
		# Update the OptionsButton and call the signal callback as that is
		# only automatically called when the user clicks it
		constraints.select(requested)
		_on_constraint_selected(requested)
		
		# Set the input as handled to prevent default actions from the keys
		get_viewport().set_input_as_handled()
		return true
	
	return false


func _on_select() -> void:
	_untoggle_buttons()
	_disable_constraint_ui(false)
	_select.button_pressed = true
	mode_changed.emit(Mode.SELECT)


func _on_add() -> void:
	_untoggle_buttons()
	_disable_constraint_ui(false)
	_add.button_pressed = true
	mode_changed.emit(Mode.ADD)


func _on_remove() -> void:
	_untoggle_buttons()
	_disable_constraint_ui(true)
	_remove.button_pressed = true
	mode_changed.emit(Mode.REMOVE)


func _on_constraint_selected(index: int) -> void:
	options_changed.emit(Option.CONSTRAINT, index)


func _on_local_mode_toggled(enabled: bool) -> void:
	options_changed.emit(Option.LOCAL_MODE, enabled)


func _on_lock_selection_toggled(enabled: bool) -> void:
	lock_selection.icon = _lock_icon_closed if enabled else _lock_icon_open
	options_changed.emit(Option.LOCK_SELECTION, enabled)


func _disable_constraint_ui(disable: bool) -> void:
	constraints.disabled = disable
	_local_mode.disabled = disable


func _untoggle_buttons() -> void:
	_select.button_pressed = false
	_add.button_pressed = false
	_remove.button_pressed = false
