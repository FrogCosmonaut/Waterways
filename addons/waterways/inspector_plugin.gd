# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
class_name WaterwaysInspectorPlugin
extends EditorInspectorPlugin

var _editor = load("res://addons/waterways/editor_property.gd")


func _can_handle(object) -> bool:
	return object is WaterwaysRiver


func _parse_property(object: Object, type: Variant.Type, name: String, hint_type: PropertyHint, hint_string: String, usage_flags, wide: bool) -> bool:
	if type == TYPE_PROJECTION and "color" in name:
		var editor_property = _editor.new()
		add_property_editor(name, editor_property)
		return true
	return false
