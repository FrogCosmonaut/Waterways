# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
@tool
class_name WaterwaysGradientInspector
extends HBoxContainer

@onready var _color_1: ColorPickerButton = %Color1
@onready var _gradient: ColorRect = %Gradient
@onready var _color_2: ColorPickerButton = %Color2


func set_value(new_gradient : Projection):
	_color_1.color = Color(new_gradient[0].x, new_gradient[0].y, new_gradient[0].z)
	_color_2.color = Color(new_gradient[1].x, new_gradient[1].y, new_gradient[1].z)
	_gradient.material.set_shader_parameter("color1", _color_1.color)
	_gradient.material.set_shader_parameter("color2", _color_2.color)


func get_value() -> Projection:
	var _gradient := Projection()
	_gradient[0] = Vector3(_color_1.color.r, _color_1.color.g, _color_1.color.b)
	_gradient[1] = Vector3(_color_2.color.r, _color_2.color.g, _color_2.color.b)
	return _gradient
