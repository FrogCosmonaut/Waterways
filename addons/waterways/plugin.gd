# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
@tool
extends EditorPlugin

const RIVER_CONTROLS_SCENE: PackedScene = preload("./gui/river_controls.tscn")
const WATER_SYSTEM_CONTROLS_SCENE: PackedScene = preload("./gui/water_system_controls.tscn")
const PROGRESS_WINDOW_SCENE: PackedScene = preload("./gui/progress_window.tscn")

var river_gizmo: WaterwaysRiverGizmo = WaterwaysRiverGizmo.new()
var waterfall_gizmo: WaterwaysWaterfallGizmo = WaterwaysWaterfallGizmo.new()
var gradient_inspector: WaterwaysInspectorPlugin = WaterwaysInspectorPlugin.new()

var _river_controls = RIVER_CONTROLS_SCENE.instantiate()
var _water_system_controls = WATER_SYSTEM_CONTROLS_SCENE.instantiate()
var _edited_node = null
var _progress_window = null
var _editor_selection : EditorSelection = null
var _heightmap_renderer = null
var _mode := WaterwaysRiverControls.Mode.SELECT
var constraint: int = WaterwaysRiverControls.CONSTRAINTS.NONE
var local_editing := false
var selection_locked := false


func _enter_tree() -> void:
	add_node_3d_gizmo_plugin(river_gizmo)
	add_node_3d_gizmo_plugin(waterfall_gizmo)
	add_inspector_plugin(gradient_inspector)
	river_gizmo.editor_plugin = self
	waterfall_gizmo.editor_plugin = self
	_river_controls.mode_changed.connect(_on_river_controls_mode_changed)
	_river_controls.options_changed.connect(_on_river_controls_options_changed)
	_progress_window = PROGRESS_WINDOW_SCENE.instantiate()
	_river_controls.add_child(_progress_window)
	_editor_selection = EditorInterface.get_selection()
	_editor_selection.selection_changed.connect(_on_selection_change)
	scene_changed.connect(_on_scene_changed)
	scene_closed.connect(_on_scene_closed)


func _on_generate_flowmap_pressed() -> void:
	_edited_node.bake_texture()


func _on_generate_mesh_pressed() -> void:
	_edited_node.spawn_mesh()


func _on_debug_view_changed(index : int) -> void:
	_edited_node.set_debug_view(index)


func _on_generate_system_maps_pressed() -> void:
	_edited_node.generate_system_maps()


func _exit_tree() -> void:
	remove_node_3d_gizmo_plugin(river_gizmo)
	remove_node_3d_gizmo_plugin(waterfall_gizmo)
	remove_inspector_plugin(gradient_inspector)
	_river_controls.mode_changed.disconnect(_on_river_controls_mode_changed)
	_river_controls.options.disconnect(_on_river_controls_options_changed)
	_editor_selection.selection_changed.disconnect(_on_selection_change)
	scene_changed.disconnect(_on_scene_changed)
	scene_closed.disconnect(_on_scene_closed)
	_hide_river_control_panel()
	_hide_water_system_control_panel()


func _handles(node):
	return node is WaterwaysRiver or node is WaterwaysWaterfall or node is WaterwaysSystemManager


# TODO - I think this was commented out for 4.0 conversion and isn't needed anymore
#func _edit(node):
#	print("edit(), node is: ", node)
#	if node is WaterwaysRiver:
#		_show_river_control_panel()
#		_edited_node = node as WaterwaysRiver
#	if node is WaterwaysSystemManager:
#		_show_water_system_control_panel()
#		_edited_node = node as WaterwaysSystemManager


func _on_selection_change() -> void:
	_editor_selection = EditorInterface.get_selection()
	var selected = _editor_selection.get_selected_nodes()

	# If selection is locked to a river, revert any selection change
	if selection_locked and _edited_node is WaterwaysRiver:
		if len(selected) == 0 or selected[0] != _edited_node:
			_editor_selection.clear()
			_editor_selection.add_node(_edited_node)
			_show_river_control_panel()
			_edited_node = selected[0] as WaterwaysRiver
			_river_controls.menu.debug_view_menu_selected = _edited_node.debug_view
			if not _edited_node.progress_notified.is_connected(_river_progress_notified):
				_edited_node.progress_notified.connect(_river_progress_notified)
			return

	_hide_water_system_control_panel()
	_hide_river_control_panel()

	if len(selected) == 0:
		return
	if selected[0] is WaterwaysRiver:
		_show_river_control_panel()
		_edited_node = selected[0] as WaterwaysRiver
		_river_controls.menu.debug_view_menu_selected = _edited_node.debug_view
		if not _edited_node.progress_notified.is_connected(_river_progress_notified):
			_edited_node.progress_notified.connect(_river_progress_notified)
	elif selected[0] is WaterwaysWaterfall:
		_edited_node = selected[0] as WaterwaysWaterfall
	elif selected[0] is WaterwaysSystemManager:
		_show_water_system_control_panel()
		_edited_node = selected[0] as WaterwaysSystemManager
	else:
		_edited_node = null


func _on_scene_changed(scene_root) -> void:
	_hide_river_control_panel()
	_hide_water_system_control_panel()


func _on_scene_closed(_value) -> void:
	_hide_river_control_panel()
	_hide_water_system_control_panel()


func _on_river_controls_mode_changed(new_mode: WaterwaysRiverControls.Mode) -> void:
	_mode = new_mode


func _on_river_controls_options_changed(option: WaterwaysRiverControls.Option, value) -> void:
	if option == WaterwaysRiverControls.Option.CONSTRAINT:
		constraint = value  # TODO: here is receiving either a bool or an int, check how to solve this.
		if constraint == WaterwaysRiverControls.CONSTRAINTS.COLLIDERS:
			# WaterwaysHelperMethods.reset_all_colliders(_edited_node.get_tree().root)
			# TODO - figure out if this is needed any more
			pass
	elif option == WaterwaysRiverControls.Option.LOCAL_MODE:
		local_editing = value
	elif option == WaterwaysRiverControls.Option.LOCK_SELECTION:
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
		if _mode == WaterwaysRiverControls.Mode.SELECT:
			if not event.pressed:
				river_gizmo.reset()
			return AFTER_GUI_INPUT_PASS
		if _mode == WaterwaysRiverControls.Mode.ADD and not event.pressed:
			# if we don't have a point on the line, we'll calculate a point
			# based of a plane of the last point of the curve
			if closest_segment == -1:
				var end_pos = _edited_node.curve.get_point_position(_edited_node.curve.get_point_count() - 1)
				var end_pos_global : Vector3 = _edited_node.to_global(end_pos)

				var z : Vector3 = _edited_node.curve.get_point_out(_edited_node.curve.get_point_count() - 1).normalized()
				var x := z.cross(Vector3.DOWN).normalized()
				var y := z.cross(x).normalized()
				var _handle_base_transform = Transform3D(
					Basis(x, y, z) * global_transform.basis,
					end_pos_global
				)

				var plane := Plane(end_pos_global, end_pos_global + camera.transform.basis.x, end_pos_global + camera.transform.basis.y)
				var new_pos
				if constraint == WaterwaysRiverControls.CONSTRAINTS.COLLIDERS:
					var space_state = _edited_node.get_world_3d().direct_space_state
					var ray_params = PhysicsRayQueryParameters3D.create(ray_from, ray_from + ray_dir * 4096)
					var result = space_state.intersect_ray(ray_params)
					if result:
						new_pos = result.position
					else:
						return AFTER_GUI_INPUT_PASS
				elif constraint == WaterwaysRiverControls.CONSTRAINTS.NONE:
					new_pos = plane.intersects_ray(ray_from, ray_from + ray_dir * 4096)

				elif constraint in WaterwaysRiverGizmo.AXIS_MAPPING:
					var axis: Vector3 = WaterwaysRiverGizmo.AXIS_MAPPING[constraint]
					if local_editing:
						axis = _handle_base_transform.basis * (axis)
					var axis_from = end_pos_global + (axis * WaterwaysRiverGizmo.AXIS_CONSTRAINT_LENGTH)
					var axis_to = end_pos_global - (axis * WaterwaysRiverGizmo.AXIS_CONSTRAINT_LENGTH)
					var ray_to = ray_from + (ray_dir * WaterwaysRiverGizmo.AXIS_CONSTRAINT_LENGTH)
					var result = Geometry3D.get_closest_points_between_segments(axis_from, axis_to, ray_from, ray_to)
					new_pos = result[0]

				elif constraint in WaterwaysRiverGizmo.PLANE_MAPPING:
					var normal: Vector3 = WaterwaysRiverGizmo.PLANE_MAPPING[constraint]
					if local_editing:
						normal = _handle_base_transform.basis * (normal)
					var projected : Vector3 = end_pos_global.project(normal)
					var direction : float = signf(projected.dot(normal))
					var distance : float = direction * projected.length()
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
		if _mode == WaterwaysRiverControls.Mode.REMOVE and not event.pressed:
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


func _river_progress_notified(progress: float, message: String) -> void:
	if not _progress_window.visible:
		_progress_window.popup_centered()

	_progress_window.show_progress(message, progress)

	if progress >= 100.0:
		# Keep the finished 100% state on screen briefly so it's actually seen,
		# instead of closing the instant we reach 100%.
		await get_tree().create_timer(0.5).timeout
		_progress_window.hide()



func _show_river_control_panel() -> void:
	if not _river_controls.get_parent():
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _river_controls)
		_river_controls.menu.generate_flowmap.connect(_on_generate_flowmap_pressed)
		_river_controls.menu.generate_mesh.connect(_on_generate_mesh_pressed)
		_river_controls.menu.debug_view_changed.connect(_on_debug_view_changed)


func _hide_river_control_panel() -> void:
	if _river_controls.get_parent():
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _river_controls)
		_river_controls.menu.generate_flowmap.disconnect(_on_generate_flowmap_pressed)
		_river_controls.menu.generate_mesh.disconnect(_on_generate_mesh_pressed)
		_river_controls.menu.debug_view_changed.disconnect(_on_debug_view_changed)

		if _river_controls.lock_selection:
			_river_controls.lock_selection.button_pressed = false

		if selection_locked:
			selection_locked = false


func _show_water_system_control_panel() -> void:
	if not _water_system_controls.get_parent():
		add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _water_system_controls)
		_water_system_controls.menu.generate_system_maps.connect(_on_generate_system_maps_pressed)


func _hide_water_system_control_panel() -> void:
	if _water_system_controls.get_parent():
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _water_system_controls)
		_water_system_controls.menu.generate_system_maps.disconnect(_on_generate_system_maps_pressed)
