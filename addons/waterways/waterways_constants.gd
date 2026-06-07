class_name WaterwaysConstants
extends RefCounted

enum BakeResolution {
	_128 = 128,  ## 128x128px
	_256 = 256,  ## 256x256px
	_512 = 512,  ## 512x512px
	_1024 = 1024,  ## 1024x1024px
	_2048 = 2048,  ## 2048x2048px
}

enum FilterShader {
	DILATE_PASS1,
	DILATE_PASS2,
	DILATE_PASS3,
	NORMAL_MAP_PASS,
	NORMAL_TO_FLOW_PASS,
	BLUR_PASS1,
	BLUR_PASS2,
	FOAM_PASS,
	COMBINE_PASS,
	DOTPRODUCT_PASS,
	FLOW_PRESSURE_PASS,
}

enum RenderShader {
	HEIGHT_SHADER,
	FLOW_SHADER,
	ALPHA_SHADER,
}

const _FILTER_SHADER_DIR: String = "res://addons/waterways/shaders/filters"
const _FILTER_SHADER_MAP: Dictionary[FilterShader, String] = {
	FilterShader.DILATE_PASS1: "dilate_filter_pass1.gdshader",
	FilterShader.DILATE_PASS2: "dilate_filter_pass2.gdshader",
	FilterShader.DILATE_PASS3: "dilate_filter_pass3.gdshader",
	FilterShader.NORMAL_MAP_PASS: "normal_map_pass.gdshader",
	FilterShader.NORMAL_TO_FLOW_PASS: "normal_to_flow_filter.gdshader",
	FilterShader.BLUR_PASS1: "blur_pass1.gdshader",
	FilterShader.BLUR_PASS2: "blur_pass2.gdshader",
	FilterShader.FOAM_PASS: "foam_pass.gdshader",
	FilterShader.COMBINE_PASS: "combine_pass.gdshader",
	FilterShader.DOTPRODUCT_PASS: "dotproduct.gdshader",
	FilterShader.FLOW_PRESSURE_PASS: "flow_pressure_pass.gdshader",
}

const _RENDER_SHADER_DIR: String = "res://addons/waterways/shaders/system_renders"
const _RENDER_SHADER_MAP: Dictionary[RenderShader, String] = {
	RenderShader.HEIGHT_SHADER: "system_height.gdshader",
	RenderShader.FLOW_SHADER: "system_flow.gdshader",
	RenderShader.ALPHA_SHADER: "alpha.gdshader",
}

const FLOW_OFFSET_NOISE_TEXTURE_PATH: String = "res://addons/waterways/textures/flow_offset_noise.png"
const FOAM_NOISE_PATH: String = "res://addons/waterways/textures/foam_noise.png"

const DEFAULT_SYSTEM_GROUP_NAME: StringName = &"waterways_system"
const RIVER_MESH_NAME: StringName = &"RiverMeshInstance"
const WATERFALL_MESH_NAME: StringName = &"WaterfallMeshInstance"


## Cached filepath: Shader
static var _cached_shaders: Dictionary[String, Shader] = {}
## Cached filepath: Texture2D
static var _cached_images: Dictionary[String, Texture2D] = {}


static func _load_shader(file: String) -> Shader:
	if file not in _cached_shaders:
		if not FileAccess.file_exists(file):
			push_error("Shader '%s' doesn't exist." % file)
			return null
		_cached_shaders[file] = load(file)
	return _cached_shaders[file]


static func _load_image(file: String) -> Texture2D:
	if file not in _cached_images:
		if not FileAccess.file_exists(file):
			push_error("Image '%s' doesn't exist." % file)
			return null
		_cached_images[file] = load(file)
	return _cached_images[file]


static func get_filter_shader(shader: FilterShader) -> Shader:
	return _load_shader(_FILTER_SHADER_DIR.path_join(_FILTER_SHADER_MAP[shader]))


static func get_render_shader(shader: RenderShader) -> Shader:
	return _load_shader(_RENDER_SHADER_DIR.path_join(_RENDER_SHADER_MAP[shader]))


static func get_flow_noise_texture() -> Texture2D:
	return _load_image(FLOW_OFFSET_NOISE_TEXTURE_PATH)


static func get_foam_noise_texture() -> Texture2D:
	return _load_image(FOAM_NOISE_PATH)
