# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
@tool
@icon("./icons/river.svg")
class_name WaterwaysRiver
extends Node3D

# river_changed used to update handles when values are changed on script side
# progress_notified used to up progress bar when baking maps
# albedo_set is needed since the gradient is a custom inspector that needs a signal to update from script side
signal river_changed
signal progress_notified
#signal albedo_set

const FILTER_RENDERER_PATH: String = "res://addons/waterways/filter_renderer.tscn"
const FLOW_OFFSET_NOISE_TEXTURE_PATH: String = "res://addons/waterways/textures/flow_offset_noise.png"
const FOAM_NOISE_PATH: String = "res://addons/waterways/textures/foam_noise.png"

const RIVER_MESH_INSTANCE_NAME: String = "RiverMeshInstance"

const MATERIAL_CATEGORIES = {
	albedo_ = "Albedo",
	emission_ = "Emission",
	transparency_ = "Transparency",
	flow_ = "Flow",
	foam_ = "Foam",
	custom_ = "Custom"
}

enum SHADER_TYPES {WATER, LAVA, CUSTOM}
const BUILTIN_SHADERS = [
	{
		name = "Water",
		shader_path = "res://addons/waterways/shaders/river.gdshader",
		texture_paths = [
			{
				name = "normal_bump_texture",
				path = "res://addons/waterways/textures/water1_normal_bump.png"
			}
		]
	},
	{
		name = "Lava",
		shader_path = "res://addons/waterways/shaders/lava.gdshader",
		texture_paths = [
			{
				name = "normal_bump_texture",
				path = "res://addons/waterways/textures/lava_normal_bump.png"
			},
			{
				name = "emission_texture",
				path = "res://addons/waterways/textures/lava_emission.png"
			}
		]
	}
]

const DEBUG_SHADER = {
	name = "Debug",
	shader_path = "res://addons/waterways/shaders/river_debug.gdshader",
	texture_paths = [
		{
			name = "debug_pattern",
			path = "res://addons/waterways/textures/debug_pattern.png"
		},
		{
			name = "debug_arrow",
			path = "res://addons/waterways/textures/debug_arrow.svg"
		}
	]
}


# Shape Properties
@export_group("Shape")
## How many subdivisions the river has per step along its length.
@export_range(1, 8) var shape_step_length_divs: int = 1: set = set_step_length_divs
## How many subdivisions the river has along its width.
@export_range(1, 8) var shape_step_width_divs: int = 1: set = set_step_width_divs
## How much the shape of the river is relaxed to even out corners.
@export_range(0.1, 5.0) var shape_smoothness: float = 0.5: set = set_smoothness

# Material properties not handled inside the shader. These stay in
# _get_property_list() because the per-shader uniforms below them are injected
# dynamically and can't be declared as @export.
@export_group("Material")
@export var mat_shader: WaterwaysRiverShader = DEFAULT_WATER_SHADER: set = set_shader

# LOD Properties
@export_group("Lod")
## Cutoff distance for whether the shader samples textures twice to create a
## fractal (FBM) effect for the waves and foam.
@export_range(5.0, 200.0) var lod_lod0_distance: float = 50.0: set = set_lod0_distance

# Bake Properties
@export_group("Baking")
## Resolution of the baked flow and foam map. It does not need to be large to
## look good, and baking time grows fast, so only increase it if you need to.
@export var baking_resolution := WaterwaysConstants.BakeResolution._256
## Raycast the collision map at half resolution and upscale it. Roughly 4x fewer
## raycasts for a small precision loss (the map is dilated and blurred anyway).
@export var baking_half_res_collision: bool = false
## Length of the raycasts used to detect colliders from the river surface.
@export_range(0.0, 100.0) var baking_raycast_distance: float = 10.0
## Physics layers used for the collision raycasts.
@export_flags_3d_physics var baking_raycast_layers: int = 1
## Amount of dilation used to convert the collision map into a distance field.
## This generally should not need adjusting.
@export_range(0.0, 1.0) var baking_dilate: float = 0.6
## How much the flowmap is blurred to clean up seams or artifacts.
@export_range(0.0, 1.0) var baking_flowmap_blur: float = 0.04
## How much of the distance field is cut off to generate the foam mask. Higher
## values make the foam mask tighter around the collisions.
@export_range(0.0, 1.0) var baking_foam_cutoff: float = 0.9
## How far the foam stretches along the flow direction.
@export_range(0.0, 1.0) var baking_foam_offset: float = 0.1
## How much the foam mask is blurred.
@export_range(0.0, 1.0) var baking_foam_blur: float = 0.02

# Public variables
@export_storage var curve: Curve3D
@export_storage var widths: Array[float] = [1.0, 1.0]: set = set_widths
@export_storage var valid_flowmap: bool = false
var debug_view: int = 0: set = set_debug_view
var mesh_instance: MeshInstance3D
@export_storage var flow_foam_noise: Texture2D
@export_storage var dist_pressure: Texture2D

# Private variables
var _steps: int = 2
var _st: SurfaceTool
var _mdt: MeshDataTool
var _debug_material: ShaderMaterial
var _first_enter_tree := true
var _filter_renderer: PackedScene
var _defaults: WaterwaysRiver

# Serialised private variables
@export_storage var _material: ShaderMaterial
@export_storage var _uv2_sides: int


# Internal Methods
func _get_property_list() -> Array:
	var props = [
		{
			name = "Material",
			type = TYPE_NIL,
			hint_string = "mat_",
			usage = PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SCRIPT_VARIABLE
		},
	]
	var mat_categories = MATERIAL_CATEGORIES.duplicate(true)

	if _material.shader != null:
		var shader_params := RenderingServer.get_shader_parameter_list(_material.shader.get_rid())
		for p in shader_params:
			if p.name.begins_with("i_"):
				continue
			var hit_category = null
			for category in mat_categories:
				if p.name.begins_with(category):
					props.append({
						name = str("Material/", mat_categories[category]),
						type = TYPE_NIL,
						hint_string = str("mat_", category),
						usage = PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SCRIPT_VARIABLE
					})
					hit_category = category
					break
			if hit_category != null:
				mat_categories.erase(hit_category)
			var cp := {}
			for k in p:
				cp[k] = p[k]
			cp.name = str("mat_", p.name)
			if "curve" in cp.name:
				cp.hint = PROPERTY_HINT_EXP_EASING
				cp.hint_string = "EASE"
			props.append(cp)

	return props


func _set(property: StringName, value) -> bool:
	if str(property).begins_with("mat_"):
		# TODO, is there a better way to do this, now that right() has changed?
		var param_name: String = str(property).replace("mat_", "")
		_material.set_shader_parameter(param_name, value)
		return true
	return false


func _get(property: StringName):
	if str(property).begins_with("mat_"):
		var param_name: String = str(property).replace("mat_", "")
		return _material.get_shader_parameter(param_name)


func _get_defaults() -> WaterwaysRiver:
	if not _defaults:
		_defaults = WaterwaysRiver.new()
	return _defaults


func _property_can_revert(property: StringName) -> bool:
	if str(property).begins_with("mat_"):
		var param_name: String = str(property).replace("mat_", "")
		return _material.property_can_revert(str("shader_parameter/", param_name))

	var defaults := _get_defaults()
	if not property in defaults:
		return false
	return get(property) != defaults.get(property)


func _property_get_revert(property: StringName):
	if str(property).begins_with("mat_"):
		var param_name: String = str(property).replace("mat_", "")
		var revert_value = _material.property_get_revert(str("shader_parameter/", param_name))
		return revert_value

	return _get_defaults().get(property)


func _init() -> void:
	_st = SurfaceTool.new()
	_mdt = MeshDataTool.new()
	_filter_renderer = load(FILTER_RENDERER_PATH)

	_debug_material = ShaderMaterial.new()
	_debug_material.shader = load(DEBUG_SHADER.shader_path) as Shader
	for texture in DEBUG_SHADER.texture_paths:
		_debug_material.set_shader_parameter(texture.name, load(texture.path) as Texture2D)

	_material = ShaderMaterial.new()
	_material.shader = load(BUILTIN_SHADERS[mat_shader_type].shader_path) as Shader
	for texture in BUILTIN_SHADERS[mat_shader_type].texture_paths:
		_material.set_shader_parameter(texture.name, load(texture.path) as Texture2D)
	# Have to manually set the color or it does not default right. Not sure how to work around this
	_material.set_shader_parameter("albedo_color", Transform3D(Vector3(0.0, 0.8, 1.0), Vector3(0.15, 0.2, 0.5), Vector3.ZERO, Vector3.ZERO))


func _enter_tree() -> void:
	if Engine.is_editor_hint() and _first_enter_tree:
		_first_enter_tree = false

	if not curve:
		curve = Curve3D.new()
		curve.bake_interval = 0.05
		curve.add_point(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -0.25), Vector3(0.0, 0.0, 0.25))
		curve.add_point(Vector3(0.0, 0.0, 1.0), Vector3(0.0, 0.0, -0.25), Vector3(0.0, 0.0, 0.25))

	mesh_instance = find_child(RIVER_MESH_INSTANCE_NAME) as MeshInstance3D
	if not mesh_instance:
		# This is what happens on creating a new river
		mesh_instance = MeshInstance3D.new()
		mesh_instance.name = RIVER_MESH_INSTANCE_NAME
		add_child(mesh_instance)
		_generate_river()
	else:
		_material = mesh_instance.mesh.surface_get_material(0) as ShaderMaterial

	set_materials("i_valid_flowmap", valid_flowmap)
	set_materials("i_uv2_sides", _uv2_sides)
	set_materials("i_distmap", dist_pressure)
	set_materials("i_flowmap", flow_foam_noise)
	set_materials("i_texture_foam_noise", load(FOAM_NOISE_PATH) as Texture2D)


func _get_configuration_warnings() -> PackedStringArray:
	if valid_flowmap:
		return []
	return ["No flowmap is set. Select River -> Generate Flow & Foam Map to generate and assign one."]


func get_transformed_aabb() -> AABB:
	return global_transform * mesh_instance.get_aabb()


# Public Methods - These should all be good to use as API from other scripts
func add_point(position: Vector3, index: int, dir: Vector3 = Vector3.ZERO, width: float = 0.0) -> void:
	if index == -1:
		var last_index: int = curve.get_point_count() - 1
		var dist: float = position.distance_to(curve.get_point_position(last_index))
		var new_dir: Vector3 = dir if dir != Vector3.ZERO else (position - curve.get_point_position(last_index) - curve.get_point_out(last_index) ).normalized() * 0.25 * dist
		curve.add_point(position, -new_dir, new_dir, -1)
		widths.append(widths[widths.size() - 1]) # If this is a new point at the end, add a width that's the same as last
	else:
		var dist = curve.get_point_position(index).distance_to(curve.get_point_position(index + 1))
		var new_dir: Vector3 = dir if dir != Vector3.ZERO else (curve.get_point_position(index + 1) - curve.get_point_position(index)).normalized() * 0.25 * dist
		curve.add_point(position, -new_dir, new_dir, index + 1)
		var new_width = width if width != 0.0 else (widths[index] + widths[index + 1]) / 2.0
		widths.insert(index + 1, new_width) # We set the width to the average of the two surrounding widths
	river_changed.emit()
	_generate_river()


func remove_point(index: int) -> void:
	# We don't allow rivers shorter than 2 points
	if curve.get_point_count() <= 2:
		return
	curve.remove_point(index)
	widths.remove_at(index)
	river_changed.emit()
	_generate_river()


func bake_texture() -> void:
	_generate_river()
	_generate_flowmap(baking_resolution)


func set_curve_point_position(index: int, position: Vector3) -> void:
	curve.set_point_position(index, position)
	_generate_river()


func set_curve_point_in(index: int, position: Vector3) -> void:
	curve.set_point_in(index, position)
	_generate_river()


func set_curve_point_out(index: int, position: Vector3) -> void:
	curve.set_point_out(index, position)
	_generate_river()


func set_widths(new_widths: Array[float]) -> void:
	widths = new_widths
	if _first_enter_tree:
		return
	_generate_river()


func set_materials(param: String, value) -> void:
	_material.set_shader_parameter(param, value)
	_debug_material.set_shader_parameter(param, value)


func set_debug_view(index: int) -> void:
	debug_view = index
	if index == 0:
		mesh_instance.material_override = null
	else:
		_debug_material.set_shader_parameter("mode", index)
		mesh_instance.material_override = _debug_material


func spawn_mesh() -> void:
	if owner == null:
		push_warning("Cannot create MeshInstance3D sibling when River is root.")
		return
	var sibling_mesh := mesh_instance.duplicate(true)
	get_parent().add_child(sibling_mesh)
	sibling_mesh.set_owner(get_tree().get_edited_scene_root())
	sibling_mesh.position = position
	sibling_mesh.material_override = null


func get_curve_points() -> PackedVector3Array:
	var points: PackedVector3Array
	for p in curve.get_point_count():
		points.append(curve.get_point_position(p))
	
	return points


func get_closest_point_to(point: Vector3) -> int:
	var closest_distance := 4096.0
	var closest_index: int = -1
	for p in curve.get_point_count():
		var dist := point.distance_to(curve.get_point_position(p))
		if dist < closest_distance:
			closest_distance = dist
			closest_index = p
	
	return closest_index


func get_shader_parameter(param: String):
	return _material.get_shader_parameter(param)


func set_step_length_divs(value : int) -> void:
	shape_step_length_divs = value
	if _first_enter_tree:
		return
	valid_flowmap = false
	set_materials("i_valid_flowmap", valid_flowmap)
	_generate_river()
	river_changed.emit()


# Parameter Setters
func set_step_length_divs(value: int) -> void:
	shape_step_width_divs = value
	if _first_enter_tree:
		return
	valid_flowmap = false
	set_materials("i_valid_flowmap", valid_flowmap)
	_generate_river()
	river_changed.emit()


func set_smoothness(value: float) -> void:
	shape_smoothness = value
	if _first_enter_tree:
		return
	valid_flowmap = false
	set_materials("i_valid_flowmap", valid_flowmap)
	_generate_river()
	river_changed.emit()


func set_shader_type(type: int):
	if type == mat_shader_type:
		return
	mat_shader_type = type
	
	if mat_shader_type == SHADER_TYPES.CUSTOM:
		_material.shader = mat_custom_shader
	else:
		_material.shader = load(BUILTIN_SHADERS[mat_shader_type].shader_path)
		for texture in BUILTIN_SHADERS[mat_shader_type].texture_paths:
			_material.set_shader_parameter(texture.name, load(texture.path) as Texture)
	
	notify_property_list_changed()


func set_custom_shader(shader : Shader) -> void:
	if mat_custom_shader == shader:
		return
	mat_custom_shader = shader
	if mat_custom_shader != null:
		_material.shader = mat_custom_shader
		
		if Engine.is_editor_hint:
			# Ability to fork default shader
			if shader.code == "":
				var selected_shader = load(BUILTIN_SHADERS[mat_shader_type].shader_path) as Shader
				shader.code = selected_shader.code

	if shader != null:
		print("shader != null - set shader type to custom")
		print(shader)
		set_shader_type(SHADER_TYPES.CUSTOM)
	else:
		set_shader_type(SHADER_TYPES.WATER)


func set_lod0_distance(value: float) -> void:
	lod_lod0_distance = value
	set_materials("i_lod0_distance", value)


#region Private Methods

## Emits the bake progress signal and yields a frame so the progressbar shows correctly.
func _notify_progress(percentage: float, message: String) -> void:
	progress_notified.emit(percentage, message)
	await get_tree().process_frame


func _generate_river() -> void:
	var average_width := WaterwaysHelperMethods.sum_array(widths) / (float(widths.size()) / 2.0)
	_steps = int( max(1.0, round(curve.get_baked_length() / average_width)) )
	
	var river_width_values := WaterwaysHelperMethods.generate_river_width_values(curve, _steps, shape_step_length_divs, shape_step_width_divs, widths)
	mesh_instance.mesh = WaterwaysHelperMethods.generate_river_mesh(curve, _steps, shape_step_length_divs, shape_step_width_divs, shape_smoothness, river_width_values)
	mesh_instance.mesh.surface_set_material(0, _material)


func _generate_flowmap(flowmap_resolution: int) -> void:
	# Progress budget: collision positions emit 0 to 45% (see generate_collision_positions),
	# raycasts continue 45 to 90, filters ssends a 90, finished at 100.
	const RAYCAST_PROGRESS_BASE: float = 45.0
	const RAYCAST_PROGRESS_END: float = 90.0
	var res := flowmap_resolution

	# Optionally raycast collisions at half resolution and upscale; the collision
	# map is dilated and blurred afterwards, so the precision loss is small.
	var collision_res := res / 2 if baking_half_res_collision else res
	var image := Image.create(collision_res, collision_res, true, Image.FORMAT_RGB8)
	image.fill(Color.BLACK)
	await _notify_progress(0.0, "Calculating Collisions (%sx%s)" % [collision_res, collision_res])

	var global_trans: Transform3D = mesh_instance.global_transform
	var mesh_arrays: Array = mesh_instance.mesh.surface_get_arrays(0)
	var physics_space: RID = mesh_instance.get_world_3d().space

	var baker_thread = Thread.new()
	baker_thread.start(
		WaterwaysHelperMethods.generate_collision_positions.bind(
			global_trans, mesh_arrays, _steps,
			shape_step_length_divs, shape_step_width_divs, collision_res, collision_res, self
		)
	)

	while baker_thread.is_alive():
		await get_tree().process_frame
	var positions: Array = baker_thread.wait_to_finish()

	var space_state := PhysicsServer3D.space_get_direct_state(physics_space)
	var total := positions.size()
	# Reuse the query params
	var down_params := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, baking_raycast_layers)
	var up_params := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, baking_raycast_layers)
	var last_yield := Time.get_ticks_msec()
	for i in total:
		if Time.get_ticks_msec() - last_yield > 16:
			await _notify_progress(
				RAYCAST_PROGRESS_BASE + (RAYCAST_PROGRESS_END - RAYCAST_PROGRESS_BASE) * float(i) / float(maxi(total, 1)),
				"Raycasting (%sx%s)" % [res, res]
			)
			last_yield = Time.get_ticks_msec()

		var px: Vector2i = positions[i][0]
		var real_pos: Vector3 = positions[i][1]
		var real_pos_up := real_pos + Vector3.UP * baking_raycast_distance

		down_params.from = real_pos_up
		down_params.to = real_pos
		var result_down := space_state.intersect_ray(down_params)
		if not result_down:
			continue

		up_params.from = real_pos
		up_params.to = real_pos_up
		var result_up := space_state.intersect_ray(up_params)
		if result_up and result_up.normal.y < 0:
			continue

		image.set_pixel(px.x, px.y, Color.WHITE)

	await _notify_progress(RAYCAST_PROGRESS_END, "Applying filters (%sx%s)" % [res, res])

	# Upscale the half-res collision map back to full resolution before filtering.
	if collision_res != res:
		image.resize(res, res, Image.INTERPOLATE_NEAREST)

	# Calculate how many columns are in UV2
	_uv2_sides = WaterwaysHelperMethods.calculate_side(_steps)
	
	var margin := res / float(_uv2_sides)
	image = WaterwaysHelperMethods.add_margins(image, res, margin)

	var collision_with_margins := ImageTexture.create_from_image(image)

	# Create correctly tiling noise for A channel
	var noise_texture := load(FLOW_OFFSET_NOISE_TEXTURE_PATH) as Texture2D
	var noise_with_margin_size := float(_uv2_sides + 2) * (float(noise_texture.get_width()) / float(_uv2_sides))
	var noise_with_tiling := Image.create(noise_with_margin_size, noise_with_margin_size, false, Image.FORMAT_RGB8)
	var slice_width := float(noise_texture.get_width()) / float(_uv2_sides)

	for x in _uv2_sides:
		noise_with_tiling.blend_rect(noise_texture.get_image(), Rect2(0.0, 0.0, slice_width, noise_texture.get_height()), Vector2(slice_width + float(x) * slice_width, slice_width - (noise_texture.get_width() / 2.0)))
		noise_with_tiling.blend_rect(noise_texture.get_image(), Rect2(0.0, 0.0, slice_width, noise_texture.get_height()), Vector2(slice_width + float(x) * slice_width, slice_width + (noise_texture.get_width() / 2.0)))
	var tiled_noise := ImageTexture.new()
	tiled_noise.create_from_image(noise_with_tiling)

	# Create renderer
	var renderer_instance = _filter_renderer.instantiate()

	self.add_child(renderer_instance)

	var flow_pressure_blur_amount = 0.04 / float(_uv2_sides) * flowmap_resolution
	var dilate_amount = baking_dilate / float(_uv2_sides) 
	var flowmap_blur_amount = baking_flowmap_blur / float(_uv2_sides) * flowmap_resolution
	var foam_offset_amount = baking_foam_offset / float(_uv2_sides)
	var foam_blur_amount = baking_foam_blur / float(_uv2_sides) * flowmap_resolution

	# TODO: do margin * 2 as (margin2 to save calculation time?)
	var flow_pressure_map = await renderer_instance.apply_flow_pressure(collision_with_margins, flowmap_resolution, _uv2_sides + 2.0)
	var blurred_flow_pressure_map = await renderer_instance.apply_vertical_blur(flow_pressure_map, flow_pressure_blur_amount, flowmap_resolution + margin * 2)
	var dilated_texture = await renderer_instance.apply_dilate(collision_with_margins, dilate_amount, 0.0, flowmap_resolution + margin * 2)
	var normal_map = await renderer_instance.apply_normal(dilated_texture, flowmap_resolution + margin * 2)
	var flow_map = await renderer_instance.apply_normal_to_flow(normal_map, flowmap_resolution + margin * 2)
	var blurred_flow_map = await renderer_instance.apply_blur(flow_map, flowmap_blur_amount, flowmap_resolution + margin * 2)
	var foam_map = await renderer_instance.apply_foam(dilated_texture, foam_offset_amount, baking_foam_cutoff, flowmap_resolution + margin * 2)
	var blurred_foam_map = await renderer_instance.apply_blur(foam_map, foam_blur_amount, flowmap_resolution + margin * 2)
	var flow_foam_noise_img = await renderer_instance.apply_combine(blurred_flow_map, blurred_flow_map, blurred_foam_map, tiled_noise)
	var dist_pressure_img = await renderer_instance.apply_combine(dilated_texture, blurred_flow_pressure_map)

	# Debug texture gen
#	flow_pressure_map.get_image().save_png("res://test_assets/baked_pressure_map.png")
#	blurred_flow_pressure_map.get_image().save_png("res://test_assets/baked_pressure_map_blurred.png")
#	dilated_texture.get_image().save_png("res://test_assets/dilated_texture.png")
#	normal_map.get_image().save_png("res://test_assets/normal_map.png")
#	flow_map.get_image().save_png("res://test_assets/flow_map.png")
#	blurred_flow_map.get_image().save_png("res://test_assets/blurred_flow_map.png")

	remove_child(renderer_instance) # cleanup

	flow_foam_noise = WaterwaysHelperMethods.save_baked_texture(flow_foam_noise_img, self, "flow_foam")
	dist_pressure = WaterwaysHelperMethods.save_baked_texture(dist_pressure_img, self, "dist_pressure")

	set_materials("i_flowmap", flow_foam_noise)
	set_materials("i_distmap", dist_pressure)
	set_materials("i_valid_flowmap", true)
	set_materials("i_uv2_sides", _uv2_sides)
	valid_flowmap = true
	await _notify_progress(100.0, "Finished")
	update_configuration_warnings()

#endregion


# Signal Methods
func properties_changed() -> void:
	river_changed.emit()
