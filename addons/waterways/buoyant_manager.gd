# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
@tool
@icon("./icons/buoyant.svg")
class_name WaterwaysBuoyant
extends Node3D

@export var water_system_group_name : StringName = &"waterways_system"
@export var buoyancy_force: float = 5.0
@export var up_correcting_force: float = 5.0
@export var flow_force: float = 50.0
@export var water_resistance: float = 5.0

var _rigid_body: RigidBody3D
var _system: WaterwaysSystem
var _default_linear_damp: float = -1.0
var _default_angular_damp: float = -1.0


func _enter_tree() -> void:
	var parent = get_parent()
	if parent is RigidBody3D:
		_rigid_body = parent as RigidBody3D
		_default_linear_damp = _rigid_body.linear_damp
		_default_angular_damp = _rigid_body.angular_damp


func _exit_tree() -> void:
	_rigid_body = null


func _ready() -> void:
	var systems = get_tree().get_nodes_in_group(water_system_group_name)
	if systems.size() > 0:
		if systems[0] is WaterwaysSystem:
			_system = systems[0] as WaterwaysSystem


func _get_configuration_warnings() -> PackedStringArray:
	if _rigid_body == null:
		return ["Buoyant node must be a direct child of a RigidBody3D to function."]
	return []


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or _system == null or _rigid_body == null:
		return

	var depth := _system.get_water_altitude(global_transform.origin)
	if depth <= 0.0:
		# above water: use the body original damping
		_rigid_body.linear_damp = _default_linear_damp
		_rigid_body.angular_damp = _default_angular_damp
		return

	# underwater: spring buoyancy, flow direction push
	_rigid_body.apply_central_force(Vector3.UP * buoyancy_force * minf(depth, 5.0))
	# up correcting torque, and extra damping so the body settles
	_rigid_body.apply_central_force(_system.get_water_flow(global_transform.origin) * flow_force)
	# torque up: axis = body_up * world_up, magnitude = sin(tilt)
	_rigid_body.apply_torque(global_transform.basis.y.cross(Vector3.UP) * up_correcting_force)
	_rigid_body.linear_damp = water_resistance
	_rigid_body.angular_damp = water_resistance
