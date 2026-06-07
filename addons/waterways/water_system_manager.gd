# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
@tool
@icon("./icons/system.svg")
class_name WaterwaysSystem
extends Node3D

const SYSTEM_MAP_RENDERER_SCENE: PackedScene = preload("./system_map_renderer.tscn")
const FILTER_RENDERER_SCENE: PackedScene = preload("./filter_renderer.tscn")

## The baked system maps texture.
@export var system_map: ImageTexture = null: set = set_system_map
## The resolution of the system maps.
@export var system_bake_resolution := WaterwaysConstants.BakeResolution._512
## This group name is assigned at runtime, it is used by the [WaterwaysBuoyant] node to find the [WaterwaysSystem].
## If you only have one [WaterwaysSystem], you can just leave this be.
@export var system_group_name: StringName = WaterwaysConstants.DEFAULT_SYSTEM_GROUP_NAME
## This is the value returned when an object queries the [WaterwaysSystem] heightmap,
## but hits outside the baked height data.
@export var minimum_water_level: float = 0.0

@export_group("Auto assign texture & coordinates on generate")
## This name will be used to find any [MeshInstance3D]s that should have the maps assigned
@export var wet_group_name: StringName = &"waterways_wet"
## The surface index the material you want to send the maps to is set on the [MeshInstance3D], -1 means disabled.
@export var surface_index: int = -1
## If the material is instead set as a [code]Material Override[/code], check this box for the maps to be assigned there.
@export var material_override: bool = false

@export_storage var _system_aabb: AABB:
	set(value):
		_system_aabb = value
		# Avoid get_longest_axis_size() twice every physics frame per Buoyant.
		if value.size != Vector3.ZERO:
			_system_aabb_longest_axis_size = value.get_longest_axis_size()

var _system_img: Image:
	set(value):
		_system_img = value
		if value:
			_system_img_size = value.get_width()

var _first_enter_tree: bool = true

# Cached longest_axis_size. Updated only when _system_aab is changed.
var _system_aabb_longest_axis_size: float
# Cached _system_img size. Updated only when _system_image is changed.
var _system_img_size: int


func _enter_tree() -> void:
	if Engine.is_editor_hint() and _first_enter_tree:
		_first_enter_tree = false
	add_to_group(system_group_name)


func _exit_tree() -> void:
	remove_from_group(system_group_name)


func _ready() -> void:
	child_order_changed.connect(update_configuration_warnings)
	if system_map != null:
		_system_img = system_map.get_image()
	else:
		push_warning("No WaterwaysSystem map!")


func _get_configuration_warnings() -> PackedStringArray:
	var warnings: PackedStringArray = []
	if system_map == null:
		warnings.append("No System Map is set. Select WaterwaysSystem -> Generate System Map to generate and assign one.")
	if get_child_count() == 0:
		warnings.append("This Node needs at least one WaterwaysRiver to work.")
	for child in get_children():
		if child is not WaterwaysRiver:
			warnings.append("Node '%s' is not a WaterwaysRiver." % child.name)
	return warnings


func _sample_system_map(query_pos: Vector3) -> Color:
	if _system_img == null:
		return Color.BLACK
	var position_in_aabb := query_pos - _system_aabb.position
	var pos_2d := Vector2(position_in_aabb.x, position_in_aabb.z)
	pos_2d = pos_2d / _system_aabb_longest_axis_size
	if pos_2d.x > 1.0 or pos_2d.x < 0.0 or pos_2d.y > 1.0 or pos_2d.y < 0.0:
		# We are outside the aabb of the Water System
		return Color.BLACK
	var point := Vector2i(pos_2d * _system_img_size)
	return _system_img.get_pixelv(point)


func generate_system_maps() -> void:
	var rivers: Array[WaterwaysRiver]

	for child in get_children():
		if child is WaterwaysRiver:
			rivers.append(child)

	if rivers.is_empty():  # TODO: Maybe a Popup here could be neat.
		push_warning("Cannot bake WaterwaysSystem map without rivers.")
		return

	# We need to make the aabb out of the first river, so we don't include 0,0
	_system_aabb = rivers[0].get_transformed_aabb()
	for river in rivers.slice(1):
		var river_aabb = river.get_transformed_aabb()
		_system_aabb = _system_aabb.merge(river_aabb)

	var renderer: WaterwaysSystemMapRenderer = SYSTEM_MAP_RENDERER_SCENE.instantiate()
	add_child(renderer)
	var flow_map: ImageTexture = await renderer.grab_flow(rivers, _system_aabb, system_bake_resolution)
	var height_map: ImageTexture = await renderer.grab_height(rivers, _system_aabb, system_bake_resolution)

	# TODO: not used, check why.
	#var alpha_map: ImageTexture = await renderer.grab_alpha(rivers, _system_aabb, system_bake_resolution)

	remove_child(renderer)

	var filter_renderer: WaterwaysFilterRenderer = FILTER_RENDERER_SCENE.instantiate()
	add_child(filter_renderer)

	system_map = await filter_renderer.apply_combine(flow_map, flow_map, height_map) as ImageTexture
	system_map = WaterwaysHelperMethods.save_baked_texture(system_map, self, "system_map") as ImageTexture

	remove_child(filter_renderer)

	# give the map and coordinates to all nodes in the wet_group
	var wet_nodes := get_tree().get_nodes_in_group(wet_group_name)
	for node in wet_nodes:
		if node is not MeshInstance3D:
			continue

		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		var material: Material = null
		if surface_index != -1:
			if mesh_instance.get_surface_override_material_count() > surface_index:
				material = mesh_instance.get_surface_override_material(surface_index)
		if material_override:
			material = mesh_instance.material_override

		if material != null:
			material.set_shader_parameter("water_systemmap", system_map)
			material.set_shader_parameter("water_systemmap_coords", get_system_map_coordinates())


## Returns the vertical distance to the water, positive values above water level,
## negative numbers below the water.
func get_water_altitude(query_pos: Vector3) -> float:
	var color: Color = _sample_system_map(query_pos)
	if color == Color.BLACK:
		# We hit the empty part of the System Map
		return min(query_pos.y, minimum_water_level)

	# Throw a warning if the map is not baked
	var height: float = color.b * _system_aabb.size.y + _system_aabb.position.y
	return height - query_pos.y


## Returns the flow vector from the system flowmap.
func get_water_flow(query_pos: Vector3) -> Vector3:
	var color: Color = _sample_system_map(query_pos)
	if color == Color.BLACK:
		# We hit the empty part of the System Map
		return Vector3.ZERO

	var flow = Vector3(color.r, 0.5, color.g) * 2.0 - Vector3(1.0, 1.0, 1.0)
	return flow


func get_system_map() -> ImageTexture:
	return system_map


func get_system_map_coordinates() -> Transform3D:
	# storing the AABB info in a transform, seems dodgy
	var offset = Transform3D(_system_aabb.position, _system_aabb.size, _system_aabb.end, Vector3())
	return offset


func set_system_map(texture: ImageTexture) -> void:
	system_map = texture
	if _first_enter_tree:
		return
	notify_property_list_changed()
	update_configuration_warnings()
