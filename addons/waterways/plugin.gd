# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
@tool
extends EditorPlugin

const RIVER_CONTROLS_SCENE: PackedScene = preload("./gui/river_controls.tscn")
const WATER_SYSTEM_CONTROLS_SCENE: PackedScene = preload("./gui/water_system_controls.tscn")
const PROGRESS_WINDOW_SCENE: PackedScene = preload("./gui/progress_window.tscn")
## Maximum world-space distance at which a dragged river endpoint automatically
## joins an endpoint of another river when dropped.
const ENDPOINT_JOIN_DISTANCE := 0.5

var river_gizmo := _WaterwaysRiverGizmo.new()
var waterfall_gizmo := _WaterwaysWaterfallGizmo.new()
var gradient_inspector := _WaterwaysInspectorPlugin.new()

var _river_controls = RIVER_CONTROLS_SCENE.instantiate()
var _water_system_controls = WATER_SYSTEM_CONTROLS_SCENE.instantiate()
var _edited_node = null
var _progress_window: _WaterwaysProgressWindow = null
var _progress_reporter: _WaterwaysProgressReporter = null
var _editor_selection: EditorSelection = null
var _mode := _WaterwaysRiverControls.Mode.SELECT
var constraint := _WaterwaysRiverControls.Constraint.NONE
var local_editing := false
var selection_locked := false


func _enter_tree() -> void:
	add_node_3d_gizmo_plugin(river_gizmo)
	add_node_3d_gizmo_plugin(waterfall_gizmo)
	add_inspector_plugin(gradient_inspector)
	river_gizmo.editor_plugin = self
	waterfall_gizmo.editor_plugin = self
	_river_controls.constraint_selected.connect(_on_river_controls_constraint_selected)
	_river_controls.mode_changed.connect(_on_river_controls_mode_changed)
	_river_controls.options_changed.connect(_on_river_controls_options_changed)
	_progress_window = PROGRESS_WINDOW_SCENE.instantiate()
	add_child(_progress_window)
	_editor_selection = EditorInterface.get_selection()
	_editor_selection.selection_changed.connect(_on_selection_change)
	scene_changed.connect(_on_scene_changed)
	scene_closed.connect(_on_scene_closed)


func _on_generate_flowmap_requested() -> void:
	_edited_node.bake_texture()


func _on_generate_mesh_requested() -> void:
	_edited_node.spawn_mesh()


func _on_debug_view_changed(index: int) -> void:
	_edited_node.set_debug_view(index)


func _on_generate_system_maps_requested() -> void:
	_edited_node.generate_system_maps()


func _on_bake_children_requested() -> void:
	_edited_node.bake_all_children()


func _exit_tree() -> void:
	remove_node_3d_gizmo_plugin(river_gizmo)
	remove_node_3d_gizmo_plugin(waterfall_gizmo)
	remove_inspector_plugin(gradient_inspector)
	_river_controls.constraint_selected.disconnect(_on_river_controls_constraint_selected)
	_river_controls.mode_changed.disconnect(_on_river_controls_mode_changed)
	_river_controls.options_changed.disconnect(_on_river_controls_options_changed)
	_editor_selection.selection_changed.disconnect(_on_selection_change)
	scene_changed.disconnect(_on_scene_changed)
	scene_closed.disconnect(_on_scene_closed)
	_hide_river_control_panel()
	_hide_water_system_control_panel()


func _handles(node):
	return node is WaterwaysRiver or node is WaterwaysWaterfall or node is WaterwaysSystem


# TODO - I think this was commented out for 4.0 conversion and isn't needed anymore
#func _edit(node):
#	print("edit(), node is: ", node)
#	if node is WaterwaysRiver:
#		_show_river_control_panel()
#		_edited_node = node as WaterwaysRiver
#	if node is WaterwaysSystem:
#		_show_water_system_control_panel()
#		_edited_node = node as WaterwaysSystem


func _on_selection_change() -> void:
	_editor_selection = EditorInterface.get_selection()
	var selected = _editor_selection.get_selected_nodes()

	# If selection is locked to a river, revert any selection change
	if selection_locked and _edited_node is WaterwaysRiver:
		if selected.is_empty() or selected[0] != _edited_node:
			_editor_selection.clear()
			_editor_selection.add_node(_edited_node)
		return

	_hide_water_system_control_panel()
	_hide_river_control_panel()

	if selected.is_empty():
		return

	var reporter := selected[0].get("progress") as _WaterwaysProgressReporter
	if reporter and reporter != _progress_reporter:
		if is_instance_valid(_progress_reporter) and _progress_reporter.progress_notified.is_connected(_progress_notified):
			_progress_reporter.progress_notified.disconnect(_progress_notified)
		reporter.progress_notified.connect(_progress_notified)
		_progress_reporter = reporter

	if selected[0] is WaterwaysRiver:
		_show_river_control_panel()
		_edited_node = selected[0] as WaterwaysRiver
		_river_controls.debug_view_menu_selected = _edited_node.debug_view
	elif selected[0] is WaterwaysWaterfall:
		_edited_node = selected[0] as WaterwaysWaterfall
	elif selected[0] is WaterwaysSystem:
		_show_water_system_control_panel()
		_edited_node = selected[0] as WaterwaysSystem
	else:
		_edited_node = null


func _on_scene_changed(scene_root) -> void:
	_hide_river_control_panel()
	_hide_water_system_control_panel()
	# propagate the selection, e.g. when changing tabs with a river node selected
	_on_selection_change()


func _on_scene_closed(_value) -> void:
	_hide_river_control_panel()
	_hide_water_system_control_panel()


func _on_river_controls_constraint_selected(value: _WaterwaysRiverControls.Constraint) -> void:
	constraint = value


func _on_river_controls_mode_changed(new_mode: _WaterwaysRiverControls.Mode) -> void:
	_mode = new_mode


func _on_river_controls_options_changed(option: _WaterwaysRiverControls.Option, value: bool) -> void:
	match option:
		_WaterwaysRiverControls.Option.LOCAL_MODE:
			local_editing = value
		_WaterwaysRiverControls.Option.LOCK_SELECTION:
			selection_locked = value


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _edited_node:
		return AFTER_GUI_INPUT_PASS

	if _edited_node is WaterwaysRiver:
		return _forward_3d_gui_input_river(camera, event)
	elif _edited_node is WaterwaysWaterfall:
		return AFTER_GUI_INPUT_PASS

	return AFTER_GUI_INPUT_PASS


func _forward_3d_gui_input_river(camera: Camera3D, event: InputEvent) -> int:
	var global_transform: Transform3D = _edited_node.transform
	if _edited_node.is_inside_tree():
		global_transform = _edited_node.get_global_transform()
	var global_inverse: Transform3D = global_transform.affine_inverse()

	if (event is InputEventMouseButton) and (event.button_index == MOUSE_BUTTON_LEFT):
		var ray_from = camera.project_ray_origin(event.position)
		var ray_dir = camera.project_ray_normal(event.position)
		var g1 = global_inverse * (ray_from)
		var g2 = global_inverse * (ray_from + ray_dir * 4096)


		# Iterate through points to find closest segment
		var curve_points = _edited_node.get_curve_points()
		var closest_distance = 4096.0
		var closest_segment = -1

		for point in curve_points.size() -1:
			var p1 = curve_points[point]
			var p2 = curve_points[point + 1]
			var result  = Geometry3D.get_closest_points_between_segments(p1, p2, g1, g2)
			var dist = result[0].distance_to(result[1])
			if dist < closest_distance:
				closest_distance = dist
				closest_segment = point

		# Iterate through baked points to find the closest position on the
		# curved path
		var baked_curve_points = _edited_node.curve.get_baked_points()
		var baked_closest_distance = 4096.0
		var baked_closest_point = Vector3()
		var baked_point_found = false

		for baked_point in baked_curve_points.size() - 1:
			var p1 = baked_curve_points[baked_point]
			var p2 = baked_curve_points[baked_point + 1]
			var result  = Geometry3D.get_closest_points_between_segments(p1, p2, g1, g2)
			var dist = result[0].distance_to(result[1])
			if dist < 0.1 and dist < baked_closest_distance:
				baked_closest_distance = dist
				baked_closest_point = result[0]
				baked_point_found = true

		# In case we were close enough to a line segment to find a segment,
		# but not close enough to the curved line
		if not baked_point_found:
			closest_segment = -1

		# We'll use this closest point to add a point in between if on the line
		# and to remove if close to a point
		if _mode == _WaterwaysRiverControls.Mode.SELECT:
			if not event.pressed:
				river_gizmo.reset()
			return AFTER_GUI_INPUT_PASS
		if _mode == _WaterwaysRiverControls.Mode.ADD and not event.pressed:
			# if we don't have a point on the line, we'll calculate a point
			# based of a plane of the last point of the curve
			if closest_segment == -1:
				var end_pos = _edited_node.curve.get_point_position(_edited_node.curve.get_point_count() - 1)
				var end_pos_global: Vector3 = _edited_node.to_global(end_pos)

				var z: Vector3 = _edited_node.curve.get_point_out(_edited_node.curve.get_point_count() - 1).normalized()
				var x := z.cross(Vector3.DOWN).normalized()
				var y := z.cross(x).normalized()
				var _handle_base_transform = Transform3D(
					Basis(x, y, z) * global_transform.basis,
					end_pos_global
				)

				var plane := Plane(end_pos_global, end_pos_global + camera.transform.basis.x, end_pos_global + camera.transform.basis.y)
				var new_pos
				if constraint == _WaterwaysRiverControls.Constraint.COLLIDERS:
					var space_state = _edited_node.get_world_3d().direct_space_state
					var ray_params = PhysicsRayQueryParameters3D.create(ray_from, ray_from + ray_dir * 4096)
					var result = space_state.intersect_ray(ray_params)
					if result:
						new_pos = result.position
					else:
						return AFTER_GUI_INPUT_PASS
				elif constraint == _WaterwaysRiverControls.Constraint.NONE:
					new_pos = plane.intersects_ray(ray_from, ray_from + ray_dir * 4096)

				elif constraint in _WaterwaysRiverGizmo.AXIS_MAPPING:
					var axis: Vector3 = _WaterwaysRiverGizmo.AXIS_MAPPING[constraint]
					if local_editing:
						axis = _handle_base_transform.basis * (axis)
					var axis_from = end_pos_global + (axis * _WaterwaysRiverGizmo.AXIS_CONSTRAINT_LENGTH)
					var axis_to = end_pos_global - (axis * _WaterwaysRiverGizmo.AXIS_CONSTRAINT_LENGTH)
					var ray_to = ray_from + (ray_dir * _WaterwaysRiverGizmo.AXIS_CONSTRAINT_LENGTH)
					var result = Geometry3D.get_closest_points_between_segments(axis_from, axis_to, ray_from, ray_to)
					new_pos = result[0]

				elif constraint in _WaterwaysRiverGizmo.PLANE_MAPPING:
					var normal: Vector3 = _WaterwaysRiverGizmo.PLANE_MAPPING[constraint]
					if local_editing:
						normal = _handle_base_transform.basis * (normal)
					var projected: Vector3 = end_pos_global.project(normal)
					var direction: float = signf(projected.dot(normal))
					var distance: float = direction * projected.length()
					plane = Plane(normal, distance)
					new_pos = plane.intersects_ray(ray_from, ray_dir)

				baked_closest_point = _edited_node.to_local(new_pos)

			var ur := get_undo_redo()
			ur.create_action("Add River point")
			ur.add_do_method(_edited_node, "add_point", baked_closest_point, closest_segment)
			ur.add_do_method(_edited_node, "properties_changed")
			ur.add_do_method(_edited_node, "set_materials", "i_valid_flowmap", false)
			ur.add_do_property(_edited_node, "valid_flowmap", false)
			ur.add_do_method(_edited_node, "update_configuration_warnings")
			if closest_segment == -1:
				ur.add_undo_method(_edited_node, "remove_point", _edited_node.curve.get_point_count()) # remove last
			else:
				ur.add_undo_method(_edited_node, "remove_point", closest_segment + 1)
			ur.add_undo_method(_edited_node, "properties_changed")
			ur.add_undo_method(_edited_node, "set_materials", "i_valid_flowmap", _edited_node.valid_flowmap)
			ur.add_undo_property(_edited_node, "valid_flowmap", _edited_node.valid_flowmap)
			ur.add_undo_method(_edited_node, "update_configuration_warnings")
			ur.commit_action()
		if _mode == _WaterwaysRiverControls.Mode.REMOVE and not event.pressed:
			# A closest_segment of -1 means we didn't press close enough to a
			# point for it to be removed
			if not closest_segment == -1:
				var closest_index = _edited_node.get_closest_point_to(baked_closest_point)
				#_edited_node.remove_point(closest_index)
				var ur = get_undo_redo()
				ur.create_action("Remove River point")
				ur.add_do_method(_edited_node, "remove_point", closest_index)
				ur.add_do_method(_edited_node, "properties_changed")
				ur.add_do_method(_edited_node, "set_materials", "i_valid_flowmap", false)
				ur.add_do_property(_edited_node, "valid_flowmap", false)
				ur.add_do_method(_edited_node, "update_configuration_warnings")
				if closest_index == _edited_node.curve.get_point_count() - 1:
					ur.add_undo_method(_edited_node, "add_point", _edited_node.curve.get_point_position(closest_index), -1)
				else:
					ur.add_undo_method(_edited_node, "add_point", _edited_node.curve.get_point_position(closest_index), closest_index - 1, _edited_node.curve.get_point_out(closest_index), _edited_node.widths[closest_index])
				ur.add_undo_method(_edited_node, "properties_changed")
				ur.add_undo_method(_edited_node, "set_materials", "i_valid_flowmap", _edited_node.valid_flowmap)
				ur.add_undo_property(_edited_node, "valid_flowmap", _edited_node.valid_flowmap)
				ur.add_undo_method(_edited_node, "update_configuration_warnings")
				ur.commit_action()
		return AFTER_GUI_INPUT_STOP

	elif _edited_node is WaterwaysRiver:
		# Forward input to river controls. This is cleaner than handling
		# the keybindings here as the keybindings need to interact with
		# the buttons. Handling it here would expose more private details
		# of the controls than needed, instead only the spatial_gui_input()
		# method needs to be exposed.
		# TODO - so this was returning a bool before? Check this
		return _river_controls.spatial_gui_input(event)
	return AFTER_GUI_INPUT_PASS


## Called by the river gizmo when the user finishes dragging a curve point.
func try_join_dragged_endpoint(river: WaterwaysRiver, point_index: int, restore_position: Vector3) -> bool:
	var point_count: int = river.curve.get_point_count()
	if point_index != 0 and point_index != point_count - 1:
		return false

	var source_is_start := point_index == 0
	var dropped_position: Vector3 = river.to_global(river.curve.get_point_position(point_index))
	var picked := _find_nearby_river_endpoint(_get_other_rivers(river), dropped_position, source_is_start)
	if picked.is_empty():
		return false

	_join_river_endpoint(river, point_index, restore_position, picked.river, picked.point)
	return true


func _find_nearby_river_endpoint(rivers: Array, global_position: Vector3, source_is_start: bool) -> Dictionary:
	var closest_dist := ENDPOINT_JOIN_DISTANCE
	var result := {}
	for river in rivers:
		var point_count: int = river.curve.get_point_count()
		var target_point: int = (point_count - 1) if source_is_start else 0
		var pos: Vector3 = river.to_global(river.curve.get_point_position(target_point))
		var dist := pos.distance_to(global_position)
		if dist < closest_dist:
			closest_dist = dist
			result = {river = river, point = target_point}
	return result


func _get_other_rivers(exclude: WaterwaysRiver) -> Array:
	var rivers: Array = []
	var scene_root := get_tree().get_edited_scene_root()
	if scene_root == null:
		return rivers
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is WaterwaysRiver and node != exclude:
			rivers.append(node)
		stack.append_array(node.get_children())
	return rivers


func _join_river_endpoint(source_river: WaterwaysRiver, source_point: int, restore_position: Vector3, target_river: WaterwaysRiver, target_point: int) -> void:
	var old_in := source_river.curve.get_point_in(source_point)
	var old_out := source_river.curve.get_point_out(source_point)
	var old_widths := source_river.widths.duplicate()
	var old_uv_offset: float = source_river._uv_length_offset

	var ur := get_undo_redo()
	ur.create_action("Join River Endpoint")
	ur.add_do_method(source_river, "snap_endpoint_to", source_point, target_river, target_point)
	ur.add_do_method(source_river, "properties_changed")
	ur.add_do_method(source_river, "set_materials", "i_valid_flowmap", false)
	ur.add_do_property(source_river, "valid_flowmap", false)
	ur.add_do_method(source_river, "update_configuration_warnings")

	ur.add_undo_method(source_river, "set_curve_point_position", source_point, restore_position)
	ur.add_undo_method(source_river, "set_curve_point_in", source_point, old_in)
	ur.add_undo_method(source_river, "set_curve_point_out", source_point, old_out)
	ur.add_undo_method(source_river, "set_widths", old_widths)
	ur.add_undo_method(source_river, "set_uv_length_offset", old_uv_offset)
	ur.add_undo_method(source_river, "properties_changed")
	ur.add_undo_method(source_river, "set_materials", "i_valid_flowmap", source_river.valid_flowmap)
	ur.add_undo_property(source_river, "valid_flowmap", source_river.valid_flowmap)
	ur.add_undo_method(source_river, "update_configuration_warnings")
	ur.commit_action()

	target_river.regenerate()


func _progress_notified(progress: float, message: String) -> void:
	if not _progress_window.visible:
		_popup_progress_centered()

	_progress_window.show_progress(message, progress)

	if progress >= 100.0:
		# Keep the finished 100% state on screen briefly so it's actually seen,
		# instead of closing the instant we reach 100%.
		await get_tree().create_timer(0.5).timeout
		_progress_window.hide()


func _popup_progress_centered() -> void:
	var editor_window := EditorInterface.get_base_control().get_window()
	var popup_size := _progress_window.size
	if _progress_window.is_embedded():
		_progress_window.position = (editor_window.size - popup_size) / 2
	else:
		# Native OS window: position is in absolute screen coordinates.
		_progress_window.position = editor_window.position + (editor_window.size - popup_size) / 2
	_progress_window.popup()


func _show_river_control_panel() -> void:
	if not _river_controls.get_parent():
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _river_controls)
		_river_controls.generate_flowmap_requested.connect(_on_generate_flowmap_requested)
		_river_controls.generate_mesh_requested.connect(_on_generate_mesh_requested)
		_river_controls.debug_view_changed.connect(_on_debug_view_changed)


func _hide_river_control_panel() -> void:
	if _river_controls.get_parent():
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _river_controls)
		_river_controls.generate_flowmap_requested.disconnect(_on_generate_flowmap_requested)
		_river_controls.generate_mesh_requested.disconnect(_on_generate_mesh_requested)
		_river_controls.debug_view_changed.disconnect(_on_debug_view_changed)
		_river_controls.on_hide()

		if selection_locked:
			selection_locked = false


func _show_water_system_control_panel() -> void:
	if not _water_system_controls.get_parent():
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _water_system_controls)
		_water_system_controls.generate_system_maps_requested.connect(_on_generate_system_maps_requested)
		_water_system_controls.bake_children_requested.connect(_on_bake_children_requested)


func _hide_water_system_control_panel() -> void:
	if _water_system_controls.get_parent():
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _water_system_controls)
		_water_system_controls.generate_system_maps_requested.disconnect(_on_generate_system_maps_requested)
		_water_system_controls.bake_children_requested.disconnect(_on_bake_children_requested)
