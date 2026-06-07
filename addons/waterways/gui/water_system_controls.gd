# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
@tool
class_name _WaterwaysSystemControls
extends HBoxContainer

signal generate_system_maps_requested
signal bake_children_requested

@onready var _generate_system_map_button: Button = %GenerateSystemMapButton
@onready var _bake_rivers_button: Button = %BakeRiversButton


func _ready() -> void:
	if not Engine.is_editor_hint():
		return

	_load_editor_icons()


func _load_editor_icons() -> void:
	var gui := EditorInterface.get_base_control()
	_generate_system_map_button.icon = gui.get_theme_icon("GridMinimap", "EditorIcons")
	_bake_rivers_button.icon = gui.get_theme_icon("Bake", "EditorIcons")


func _on_generate_system_map_button_pressed() -> void:
	generate_system_maps_requested.emit()


func _on_bake_rivers_button_pressed() -> void:
	bake_children_requested.emit()
