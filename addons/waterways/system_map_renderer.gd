# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
@tool
class_name _WaterwaysSystemMapRenderer
extends SubViewport

@onready var _camera: Camera3D = $Camera3D
@onready var _container: Node3D = $Container


func _setup_viewport(resolution: float) -> void:
	size = Vector2(resolution, resolution)


func _get_camera_pos(aabb: AABB, axis: int) -> Vector3:
	var offset := Vector3.ZERO
	match axis:
		Vector3.AXIS_X:
			offset = Vector3(aabb.size.x / 2.0, aabb.size.y + 1.0, aabb.size.x / 2.0)
		Vector3.AXIS_Y:
			push_error("AABB Y-axis as longest axis is not supported")
			return aabb.position
		Vector3.AXIS_Z:
			offset = Vector3(aabb.size.z / 2.0, aabb.size.y + 1.0, aabb.size.z / 2.0)
	return aabb.position + offset


func _position_camera_for_aabb(aabb: AABB) -> void:
	var longest_axis := aabb.get_longest_axis_index()
	_camera.position = _get_camera_pos(aabb, longest_axis)
	_camera.size = aabb.get_longest_axis_size()
	_camera.far = aabb.size.y + 2.0


func _render_and_wait() -> void:
	render_target_clear_mode = CLEAR_MODE_ALWAYS
	render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw


func _capture_render() -> ImageTexture:
	var img: Image = get_texture().get_image()
	return ImageTexture.create_from_image(img)


func _cleanup_container() -> void:
	for child in _container.get_children():
		_container.remove_child(child)

func grab_height(water_objects: Array[WaterwaysRiver], aabb: AABB, resolution: float) -> ImageTexture:
	_setup_viewport(resolution)

	var height_mat := ShaderMaterial.new()
	height_mat.shader = _WaterwaysConstants.get_render_shader(_WaterwaysConstants.RenderShader.HEIGHT_SHADER)

	height_mat.set_shader_parameter("lower_bounds", aabb.position.y)
	height_mat.set_shader_parameter("upper_bounds", aabb.end.y)

	for object in water_objects:
		var water_mesh_copy := object.mesh_instance.duplicate(true)
		_container.add_child(water_mesh_copy)
		water_mesh_copy.global_transform = object.global_transform
		water_mesh_copy.material_override = height_mat

	_position_camera_for_aabb(aabb)
	await _render_and_wait()
	var height_result := _capture_render()
	_cleanup_container()

	return height_result


func grab_alpha(water_objects: Array[WaterwaysRiver], aabb: AABB, resolution: float) -> ImageTexture:
	_setup_viewport(resolution)

	var alpha_mat := ShaderMaterial.new()
	alpha_mat.shader = _WaterwaysConstants.get_render_shader(_WaterwaysConstants.RenderShader.FLOW_SHADER)

	for object in water_objects:
		var water_mesh_copy = object.mesh_instance.duplicate(true)
		_container.add_child(water_mesh_copy)
		water_mesh_copy.global_transform = object.global_transform
		water_mesh_copy.material_override = alpha_mat

	_position_camera_for_aabb(aabb)
	await _render_and_wait()
	var alpha_result := _capture_render()
	_cleanup_container()

	return alpha_result


func grab_flow(water_objects: Array[WaterwaysRiver], aabb: AABB, resolution: float) -> ImageTexture:
	_setup_viewport(resolution)

	var flow_mat := ShaderMaterial.new()
	flow_mat.shader = _WaterwaysConstants.get_render_shader(_WaterwaysConstants.RenderShader.FLOW_SHADER)

	for i in water_objects.size():
		flow_mat.set_shader_parameter("flowmap", water_objects[i].flow_foam_noise)
		flow_mat.set_shader_parameter("distmap", water_objects[i].dist_pressure)
		flow_mat.set_shader_parameter("flow_base", water_objects[i].get_shader_parameter("flow_base"))
		flow_mat.set_shader_parameter("flow_steepness", water_objects[i].get_shader_parameter("flow_steepness"))
		flow_mat.set_shader_parameter("flow_distance", water_objects[i].get_shader_parameter("flow_distance"))
		flow_mat.set_shader_parameter("flow_pressure", water_objects[i].get_shader_parameter("flow_pressure"))
		flow_mat.set_shader_parameter("flow_max", water_objects[i].get_shader_parameter("flow_max"))
		flow_mat.set_shader_parameter("valid_flowmap", water_objects[i].get_shader_parameter("i_valid_flowmap"))
		flow_mat.set_shader_parameter("uv2_sides", water_objects[i].get_shader_parameter("i_uv2_sides"))

		var water_mesh_copy := water_objects[i].mesh_instance.duplicate(true)
		_container.add_child(water_mesh_copy)
		water_mesh_copy.global_transform = water_objects[i].global_transform
		water_mesh_copy.material_override = flow_mat

	_position_camera_for_aabb(aabb)
	await _render_and_wait()
	var flow_result := _capture_render()
	_cleanup_container()

	return flow_result
