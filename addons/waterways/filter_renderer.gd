# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
@tool
class_name _WaterwaysFilterRenderer
extends SubViewport

var _WC := _WaterwaysConstants
const _FS := _WaterwaysConstants.FilterShader

var filter_mat: ShaderMaterial
var _color_rect: ColorRect


func _enter_tree() -> void:
	filter_mat = ShaderMaterial.new()
	_color_rect = $ColorRect
	_color_rect.material = filter_mat
	_color_rect.position = Vector2.ZERO


func _execute_pass(shader: Shader, texture_size: Vector2, params: Dictionary) -> ImageTexture:
	filter_mat.shader = shader
	size = texture_size
	_color_rect.size = texture_size

	for param_name in params:
		filter_mat.set_shader_parameter(param_name, params[param_name])

	render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw

	var image: Image = get_texture().get_image()
	return ImageTexture.create_from_image(image)


func apply_combine(r_texture: Texture2D, g_texture: Texture2D, b_texture: Texture2D = null, a_texture: Texture2D = null) -> ImageTexture:
	var params: Dictionary = {
		"r_texture": r_texture,
		"g_texture": g_texture,
		"b_texture": b_texture,
		"a_texture": a_texture,
	}
	return await _execute_pass(_WC.get_filter_shader(_FS.COMBINE_PASS), r_texture.get_size(), params)


func apply_dotproduct(input_texture: Texture2D, resolution: float) -> ImageTexture:
	var params: Dictionary = {"input_texture": input_texture}
	return await _execute_pass(_WC.get_filter_shader(_FS.DOTPRODUCT_PASS), input_texture.get_size(), params)


func apply_flow_pressure(input_texture: Texture2D, resolution: float, rows: float) -> ImageTexture:
	var params: Dictionary = {
		"input_texture": input_texture,
		"size": resolution,
		"rows": rows,
	}
	return await _execute_pass(_WC.get_filter_shader(_FS.FLOW_PRESSURE_PASS), input_texture.get_size(), params)


func apply_foam(input_texture: Texture2D, distance: float, cutoff: float, resolution: float) -> ImageTexture:
	var params: Dictionary = {
		"input_texture": input_texture,
		"size": resolution,
		"offset": distance,
		"cutoff": cutoff,
	}
	return await _execute_pass(_WC.get_filter_shader(_FS.FOAM_PASS), input_texture.get_size(), params)


func apply_blur(input_texture: Texture2D, blur: float, resolution: float) -> ImageTexture:
	var params: Dictionary = {
		"input_texture": input_texture,
		"size": resolution,
		"blur": blur,
	}
	var pass1_result := await _execute_pass(_WC.get_filter_shader(_FS.BLUR_PASS1), input_texture.get_size(), params)

	# Pass 2
	params["input_texture"] = pass1_result
	return await _execute_pass(_WC.get_filter_shader(_FS.BLUR_PASS2), input_texture.get_size(), params)


func apply_vertical_blur(input_texture: Texture2D, blur: float, resolution: float) -> ImageTexture:
	var params: Dictionary = {
		"input_texture": input_texture,
		"size": resolution,
		"blur": blur,
	}
	return await _execute_pass(_WC.get_filter_shader(_FS.BLUR_PASS2), input_texture.get_size(), params)


func apply_normal_to_flow(input_texture: Texture2D, resolution: float) -> ImageTexture:
	var params: Dictionary = {
		"input_texture": input_texture,
		"size": resolution,
	}
	return await _execute_pass(_WC.get_filter_shader(_FS.NORMAL_TO_FLOW_PASS), input_texture.get_size(), params)


func apply_normal(input_texture: Texture2D, resolution: float) -> ImageTexture:
	var params: Dictionary = {
		"input_texture": input_texture,
		"size": resolution,
	}
	return await _execute_pass(_WC.get_filter_shader(_FS.NORMAL_MAP_PASS), input_texture.get_size(), params)


func apply_dilate(input_texture: Texture2D, dilation: float, fill: float, resolution: float, fill_texture: Texture2D = null) -> ImageTexture:
	var params: Dictionary = {
		"input_texture": input_texture,
		"size": resolution,
		"dilation": dilation,
	}
	var pass1_result := await _execute_pass(_WC.get_filter_shader(_FS.DILATE_PASS1), input_texture.get_size(), params)

	# Pass 2
	params["input_texture"] = pass1_result
	var pass2_result = await _execute_pass(_WC.get_filter_shader(_FS.DILATE_PASS2), input_texture.get_size(), params)

	params["distance_texture"] = pass2_result
	params["fill"] = fill
	if fill_texture:
		params["color_texture"] = fill_texture
	return await _execute_pass(_WC.get_filter_shader(_FS.DILATE_PASS3), input_texture.get_size(), params)
