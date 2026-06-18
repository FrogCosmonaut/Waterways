# Copyright © 2023 Kasper Arnklit Frandsen - MIT License
# See `LICENSE.md` included in the source distribution for details.
class_name _WaterwaysHelperMethods
extends RefCounted


static func cart2bary(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var denom := d00 * d11 - d01 * d01
	var v = (d11 * d20 - d01 * d21) / denom
	var w = (d00 * d21 - d01 * d20) / denom
	var u = 1.0 - v - w
	return Vector3(u, v, w)


static func bary2cart(a: Vector3, b: Vector3, c: Vector3, barycentric: Vector3) -> Vector3:
	return barycentric.x * a + barycentric.y * b + barycentric.z * c


static func point_in_bariatric(v: Vector3) -> bool:
	return 0 <= v.x and v.x <= 1 and 0 <= v.y and v.y <= 1 and 0 <= v.z and v.z <= 1;


static func sum_array(array: Array[float]) -> float:
	var sum := 0.0
	for element in array:
			sum += element
	return sum


static func calculate_side(steps: int) -> int:
	var side_float: float = sqrt(steps)
	if fmod(side_float, 1.0) != 0.0:
		side_float += 1.0
	return int(side_float)


static func get_endpoint_flow_direction(curve: Curve3D, point_index: int) -> Vector3:
	if point_index == 0:
		return curve.get_point_out(point_index).normalized()
	return (-curve.get_point_in(point_index)).normalized()


static func get_curve_forward(curve: Curve3D, offset: float) -> Vector3:
	var length := curve.get_baked_length()
	var eps := maxf(length * 0.001, 0.01)
	var ahead := curve.sample_baked(clampf(offset + eps, 0.0, length))
	var behind := curve.sample_baked(clampf(offset - eps, 0.0, length))
	return (ahead - behind).normalized()


static func get_curve_surface_normal(curve: Curve3D, offset: float) -> Vector3:
	var forward := get_curve_forward(curve, offset)
	var right := forward.cross(Vector3.UP).normalized()
	return right.cross(forward).normalized()


static func width_at_offset(curve: Curve3D, widths: Array, offset: float) -> float:
	var count := curve.get_point_count()
	if count == 0 or widths.is_empty():
		return 0.0
	if count == 1:
		return float(widths[0])
	for i in count - 1:
		var o1 := curve.get_closest_offset(curve.get_point_position(i + 1))
		if offset <= o1 or i == count - 2:
			var o0 := curve.get_closest_offset(curve.get_point_position(i))
			var seg := maxf(o1 - o0, 0.0001)
			var t := clampf((offset - o0) / seg, 0.0, 1.0)
			return lerpf(float(widths[mini(i, widths.size() - 1)]), float(widths[mini(i + 1, widths.size() - 1)]), t)
	return float(widths[widths.size() - 1])


static func generate_river_width_values(curve: Curve3D, steps: int, step_length_divs: int, step_width_divs: int, widths: Array[float]) -> Array[float]:
	var river_width_values: Array[float]
	var length := curve.get_baked_length()
	for step in steps * step_length_divs + 1:
		var target_pos := curve.sample_baked((float(step) / float(steps * step_length_divs + 1)) * curve.get_baked_length())
		var closest_dist := 4096.0
		var closest_interpolate: float
		var closest_point: int
		for c_point in curve.get_point_count() - 1:
			for i in 100:
				var interpolate := float(i) / 100.0
				var pos := curve.sample(c_point, interpolate)
				var dist = pos.distance_to(target_pos)
				if dist < closest_dist:
					closest_dist = dist
					closest_interpolate = interpolate
					closest_point = c_point
		river_width_values.append( lerp(widths[closest_point], widths[closest_point + 1], closest_interpolate) )
	
	return river_width_values


static func generate_river_mesh(
	curve: Curve3D, steps: int, step_length_divs: int, step_width_divs: int,
	smoothness: float, river_width_values: Array[float], uv_length_offset: float = 0.0
) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curve_length := curve.get_baked_length()
	var last_step := steps * step_length_divs
	st.set_smooth_group(0)

	# Curve-frame surface normals at the two ends.
	var normal_start := Vector3.UP
	var normal_end := Vector3.UP

	# Generating the verts
	for step in last_step + 1:
		var position := curve.sample_baked(float(step) / float(last_step) * curve_length, false)
		var forward_vector: Vector3
		if step == 0:
			forward_vector = curve.get_point_out(0)
		elif step == last_step:
			forward_vector = -curve.get_point_in(curve.get_point_count() - 1)
		if forward_vector.is_zero_approx():
			var backward_pos := curve.sample_baked((float(step) - smoothness) / float(last_step) * curve_length, false)
			var forward_pos := curve.sample_baked((float(step) + smoothness) / float(last_step) * curve_length, false)
			forward_vector = forward_pos - backward_pos
		var right_vector := forward_vector.cross(Vector3.UP).normalized()
		if step == 0:
			normal_start = right_vector.cross(forward_vector).normalized()
		elif step == last_step:
			normal_end = right_vector.cross(forward_vector).normalized()

		var width_lerp: float = river_width_values[step]

		for w_sub in step_width_divs + 1:
			st.set_uv(
				Vector2(
					float(w_sub) / (float(step_width_divs)),
					uv_length_offset + float(step) / float(step_length_divs),
				)
			)
			st.add_vertex(position + right_vector * width_lerp - 2.0 * right_vector * width_lerp * float(w_sub) / (float(step_width_divs)))
	
	# Defining the tris
	for step in steps * step_length_divs:
		for w_sub in step_width_divs:
			st.add_index( (step * (step_width_divs + 1)) + w_sub)
			st.add_index( (step * (step_width_divs + 1)) + w_sub + 1)
			st.add_index( (step * (step_width_divs + 1)) + w_sub + 2 + step_width_divs - 1)
			
			st.add_index( (step * (step_width_divs + 1)) + w_sub + 1)
			st.add_index( (step * (step_width_divs + 1)) + w_sub + 3 + step_width_divs - 1)
			st.add_index( (step * (step_width_divs + 1)) + w_sub + 2 + step_width_divs - 1)
		
	st.generate_normals()
	st.generate_tangents()
	st.deindex()

	var mesh := ArrayMesh.new()
	var mesh2 :=  ArrayMesh.new()
	var mesh3 := ArrayMesh.new()
	mesh = st.commit()

	var mdt := MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)

	# Generate UV2
	# Decide on grid size
	var grid_side := calculate_side(steps)
	var grid_side_length := 1.0 / float(grid_side)
	var x_grid_sub_length := grid_side_length / float(step_width_divs)
	var y_grid_sub_length := grid_side_length / float(step_length_divs)
	var grid_size := pow(grid_side, 2)
	var index := 0
	var UVs := steps * step_width_divs * step_length_divs * 6
	var x_offset := 0.0
	for x in grid_side:
		var y_offset := 0.0
		for y in grid_side:
		
			if index < UVs:
				var sub_y_offset := 0.0
				for sub_y in step_length_divs:
					var sub_x_offset := 0.0
					for sub_x in step_width_divs:
						var x_comb_offset := x_offset + sub_x_offset
						var y_comb_offset := y_offset + sub_y_offset
						mdt.set_vertex_uv2(index, Vector2(x_comb_offset, y_comb_offset))
						mdt.set_vertex_uv2(index + 1, Vector2(x_comb_offset + x_grid_sub_length, y_comb_offset))
						mdt.set_vertex_uv2(index + 2, Vector2(x_comb_offset, y_comb_offset + y_grid_sub_length))
						
						mdt.set_vertex_uv2(index + 3, Vector2(x_comb_offset + x_grid_sub_length, y_comb_offset))
						mdt.set_vertex_uv2(index + 4, Vector2(x_comb_offset + x_grid_sub_length, y_comb_offset + y_grid_sub_length))
						mdt.set_vertex_uv2(index + 5, Vector2(x_comb_offset, y_comb_offset + y_grid_sub_length))
						index += 6
						sub_x_offset += grid_side_length / float(step_width_divs)
					sub_y_offset += grid_side_length / float(step_length_divs)
			
			y_offset += grid_side_length
		x_offset += grid_side_length
	
	for i in mdt.get_vertex_count():
		var uvy := mdt.get_vertex_uv(i).y
		if is_equal_approx(uvy, uv_length_offset):
			mdt.set_vertex_normal(i, normal_start)
		elif is_equal_approx(uvy, uv_length_offset + float(steps)):
			mdt.set_vertex_normal(i, normal_end)

	mdt.commit_to_surface(mesh2)
	st.clear()
	st.create_from(mesh2, 0)
	st.index()
	mesh3 = st.commit()
	return mesh3


static func generate_collision_positions(
	global_trans: Transform3D,
	mesh_arrays: Array,
	steps: int,
	step_length_divs: int,
	step_width_divs: int,
	img_width: int,
	img_height: int,
	progress: _WaterwaysProgressReporter,
) -> Array:  # Arraty of [Vector2i pixel, Vector3 world_pos]
	const FINAL_PROGRESS: float = 45.0
	const PROGRESS_FREQ: int = 30

	var uv2: PackedVector2Array = mesh_arrays[5]
	var verts: PackedVector3Array = mesh_arrays[0]

	# move the verts into world space once, read-only for the workers
	var world_verts := PackedVector3Array()
	world_verts.resize(verts.size())
	for v in verts.size():
		world_verts[v] = global_trans * verts[v]

	var tris_in_step_quad := step_length_divs * step_width_divs * 2
	var side := calculate_side(steps)
	# how many pixels wide each UV2 tile is (constant for the whole map)
	var pixels_per_tile := img_width / side

	var column_results: Array = []
	column_results.resize(img_width)
	var mutex := Mutex.new()
	var counter := [0]  # boxed so the workers share one count

	var process_column := func(x: int) -> void:
		var local: Array = []
		var column := x / pixels_per_tile
		for y in img_height:
			var row := y / pixels_per_tile
			var step_quad := column * side + row
			if step_quad >= steps:
				break  # empty part of UV2, move to the next column

			var uv_coordinate := Vector2(
				(0.5 + float(x)) / float(img_width),
				(0.5 + float(y)) / float(img_height),
			)
			var correct_triangle := Vector3i(-1, -1, -1)
			var baryatric_coords := Vector3.ZERO
			for tris in tris_in_step_quad:
				var offset_tris: int = (tris_in_step_quad * step_quad) + tris
				var p := Vector3(uv_coordinate.x, uv_coordinate.y, 0.0)
				var a := Vector3(uv2[offset_tris * 3].x, uv2[offset_tris * 3].y, 0.0)
				var b := Vector3(uv2[offset_tris * 3 + 1].x, uv2[offset_tris * 3 + 1].y, 0.0)
				var c := Vector3(uv2[offset_tris * 3 + 2].x, uv2[offset_tris * 3 + 2].y, 0.0)
				baryatric_coords = _WaterwaysHelperMethods.cart2bary(p, a, b, c)
				if _WaterwaysHelperMethods.point_in_bariatric(baryatric_coords):
					correct_triangle = Vector3i(offset_tris * 3, offset_tris * 3 + 1, offset_tris * 3 + 2)
					break # we have the correct triangle so we break out of loop

			if correct_triangle.x != -1:
				var vert0: Vector3 = world_verts[correct_triangle.x]
				var vert1: Vector3 = world_verts[correct_triangle.y]
				var vert2: Vector3 = world_verts[correct_triangle.z]
				local.append([Vector2i(x, y), _WaterwaysHelperMethods.bary2cart(vert0, vert1, vert2, baryatric_coords)])

		mutex.lock()
		column_results[x] = local
		counter[0] += 1
		var done: int = counter[0]
		mutex.unlock()
		if done % PROGRESS_FREQ == 0 or done == img_width:
			progress.report_deferred(
				FINAL_PROGRESS * float(done) / float(img_width),
				"Calculating Collisions (%sx%s)" % [img_width, img_height]
			)

	progress.report_deferred(
		0.0, "Calculating Collisions (%sx%s)" % [img_width, img_height]
	)
	var task_id := WorkerThreadPool.add_group_task(process_column, img_width, -1, false, "Waterways collision positions")
	WorkerThreadPool.wait_for_group_task_completion(task_id)

	# add everything to one list, order is irrelevant for raycasting
	var positions: Array = []
	for col in column_results:
		positions.append_array(col)
	return positions


#region Confluence edge matching

# Feather width across the joined tile.
# 1.0 = blend across the whole tile, 0.5 = blend across half of it.
# I noticed that 0.5 works best here... Maybe this should be exported somewhere.
const EDGE_MATCH_FEATHER := 0.5


static func _sample_joined_edge(img: Image, res: int, side: int, steps: int, at_start: bool, t: float) -> Color:
	var margin := float(res) / float(side)
	var step_quad := 0 if at_start else steps - 1
	var col := step_quad / side
	var row := step_quad % side

	var u_x := (float(col) + clampf(t, 0.0, 1.0)) / float(side)
	var u_y := float(row + (0 if at_start else 1)) / float(side)

	var x := clampi(roundi(margin + u_x * res), 0, img.get_width() - 1)
	var y := clampi(roundi(margin + u_y * res), 0, img.get_height() - 1)
	return img.get_pixel(x, y)


static func copy_joined_edge(
		dst: Image, dst_res: int, dst_side: int, dst_steps: int, dst_at_start: bool,
		src: Image, src_res: int, src_side: int, src_steps: int, src_at_start: bool,
		debug_mask: Image = null
	) -> void:
	var margin := float(dst_res) / float(dst_side)
	var step_quad := 0 if dst_at_start else dst_steps - 1
	var col := step_quad / dst_side
	var row := step_quad % dst_side

	var x0 := roundi(margin + float(col) * margin)
	var x1 := roundi(margin + float(col + 1) * margin)
	var y0 := roundi(margin + float(row) * margin)
	var y1 := roundi(margin + float(row + 1) * margin)

	var w_img := dst.get_width()
	var h_img := dst.get_height()

	for x in range(x0, x1):
		var t := (float(x - x0) + 0.5) / float(maxi(x1 - x0, 1))
		var src_color := _sample_joined_edge(src, src_res, src_side, src_steps, src_at_start, t)

		for y in range(y0, y1):
			if x < 0 or y < 0 or x >= w_img or y >= h_img:
				continue

			var f := (float(y - y0) + 0.5) / float(maxi(y1 - y0, 1))
			var dist_from_edge := f if dst_at_start else (1.0 - f)
			var w := clampf(1.0 - dist_from_edge / EDGE_MATCH_FEATHER, 0.0, 1.0)

			if w <= 0.0:
				continue

			var orig := dst.get_pixel(x, y)
			dst.set_pixel(x, y, orig.lerp(src_color, w))

			if debug_mask != null:
				debug_mask.set_pixel(x, y, Color(w, w, w, 1.0))


static func _sample_river_slice(img: Image, res: int, side: int, steps: int, length_frac: float, t: float) -> Color:
	var margin := float(res) / float(side)
	var step_pos := clampf(length_frac, 0.0, 1.0) * float(steps)
	var step_quad := clampi(int(floor(step_pos)), 0, steps - 1)
	var local_y := clampf(step_pos - float(step_quad), 0.0, 1.0)
	var col := step_quad / side
	var row := step_quad % side

	var u_x := (float(col) + clampf(t, 0.0, 1.0)) / float(side)
	var u_y := (float(row) + local_y) / float(side)

	var x := clampi(roundi(margin + u_x * res), 0, img.get_width() - 1)
	var y := clampi(roundi(margin + u_y * res), 0, img.get_height() - 1)
	return img.get_pixel(x, y)


static func _blend_mouth_tile(
		dst: Image, dst_res: int, dst_side: int, dst_steps: int, dst_at_start: bool, target: Color
	) -> void:
	var margin := float(dst_res) / float(dst_side)
	var step_quad := 0 if dst_at_start else dst_steps - 1
	var col := step_quad / dst_side
	var row := step_quad % dst_side

	var x0 := roundi(margin + float(col) * margin)
	var x1 := roundi(margin + float(col + 1) * margin)
	var y0 := roundi(margin + float(row) * margin)
	var y1 := roundi(margin + float(row + 1) * margin)

	var w_img := dst.get_width()
	var h_img := dst.get_height()

	for x in range(x0, x1):
		for y in range(y0, y1):
			if x < 0 or y < 0 or x >= w_img or y >= h_img:
				continue
			var f := (float(y - y0) + 0.5) / float(maxi(y1 - y0, 1))
			var dist_from_edge := f if dst_at_start else (1.0 - f)
			var w := clampf(1.0 - dist_from_edge / EDGE_MATCH_FEATHER, 0.0, 1.0)
			if w <= 0.0:
				continue
			var orig := dst.get_pixel(x, y)
			dst.set_pixel(x, y, orig.lerp(target, w))


static func blend_confluence_mouth(
		dst: Image, dst_res: int, dst_side: int, dst_steps: int, dst_at_start: bool,
		flow_dir_uv: Vector2,
		src: Image, src_res: int, src_side: int, src_steps: int, src_frac: float, src_t: float = 0.5
	) -> void:
	var src_color := _sample_river_slice(src, src_res, src_side, src_steps, src_frac, src_t)
	var main_flow := Vector2((src_color.r - 0.5) * 2.0, (src_color.g - 0.5) * 2.0)
	var main_mag := main_flow.length()
	var dir := flow_dir_uv.normalized() if flow_dir_uv.length() > 0.0001 else Vector2.ZERO

	var margin := float(dst_res) / float(dst_side)
	var step_quad := 0 if dst_at_start else dst_steps - 1
	var col := step_quad / dst_side
	var row := step_quad % dst_side
	var x0 := roundi(margin + float(col) * margin)
	var x1 := roundi(margin + float(col + 1) * margin)
	var y0 := roundi(margin + float(row) * margin)
	var y1 := roundi(margin + float(row + 1) * margin)
	var w_img := dst.get_width()
	var h_img := dst.get_height()

	for x in range(x0, x1):
		for y in range(y0, y1):
			if x < 0 or y < 0 or x >= w_img or y >= h_img:
				continue
			var f := (float(y - y0) + 0.5) / float(maxi(y1 - y0, 1))
			var dist_from_edge := f if dst_at_start else (1.0 - f)
			var w := clampf(1.0 - dist_from_edge / EDGE_MATCH_FEATHER, 0.0, 1.0)
			if w <= 0.0:
				continue
			var orig := dst.get_pixel(x, y)
			var orig_flow := Vector2((orig.r - 0.5) * 2.0, (orig.g - 0.5) * 2.0)
			# rotate the mouth flow toward the main's downstream
			var target_flow := dir * maxf(orig_flow.length(), main_mag)
			var new_flow := orig_flow.lerp(target_flow, w)
			var new_foam := lerpf(orig.b, src_color.b, w)
			var new_phase := lerpf(orig.a, src_color.a, w)
			dst.set_pixel(x, y, Color(
				clampf(new_flow.x * 0.5 + 0.5, 0.0, 1.0),
				clampf(new_flow.y * 0.5 + 0.5, 0.0, 1.0),
				new_foam,
				new_phase))


## Side merge for a scalar map
static func blend_confluence_mouth_scalar(
		dst: Image, dst_res: int, dst_side: int, dst_steps: int, dst_at_start: bool,
		src: Image, src_res: int, src_side: int, src_steps: int, src_frac: float, src_t: float = 0.5
	) -> void:
	var src_color := _sample_river_slice(src, src_res, src_side, src_steps, src_frac, src_t)
	_blend_mouth_tile(dst, dst_res, dst_side, dst_steps, dst_at_start, src_color)


## Suppresses the foam channel (.b) of a river's own flow_foam map over the region
## where a tributary desembocates
static func suppress_mouth_foam(
		img: Image, res: int, side: int, steps: int,
		frac_lo: float, frac_hi: float, t_lo: float, t_hi: float
	) -> void:
	var margin := float(res) / float(side)
	var s_lo := clampi(int(floor(clampf(frac_lo, 0.0, 1.0) * float(steps))), 0, steps - 1)
	var s_hi := clampi(int(floor(clampf(frac_hi, 0.0, 1.0) * float(steps))), 0, steps - 1)
	var tl := clampf(minf(t_lo, t_hi), 0.0, 1.0)
	var th := clampf(maxf(t_lo, t_hi), 0.0, 1.0)
	for step_quad in range(mini(s_lo, s_hi), maxi(s_lo, s_hi) + 1):
		var col := step_quad / side
		var row := step_quad % side
		var x0 := roundi(margin + (float(col) + tl) * margin)
		var x1 := roundi(margin + (float(col) + th) * margin)
		var y0 := roundi(margin + float(row) * margin)
		var y1 := roundi(margin + float(row + 1) * margin)
		for x in range(mini(x0, x1), maxi(x0, x1)):
			# Fade the suppression out toward the inner edge of the band.
			var span := float(maxi(absi(x1 - x0), 1))
			var dist_in := (float(x - mini(x0, x1)) + 0.5) / span
			var fade: float = (1.0 - dist_in) if tl <= 0.001 else dist_in
			for y in range(y0, y1):
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				var c := img.get_pixel(x, y)
				c.b = c.b * (1.0 - clampf(fade, 0.0, 1.0))
				img.set_pixel(x, y, c)

#endregion


# Adds offset margins so filters will correctly extend across UV edges
static func add_margins(image: Image, resolution: int, margin: int) -> Image:
	var with_margins_size := resolution + 2 * margin
	
	var image_with_margins := Image.create(with_margins_size, with_margins_size, true, Image.FORMAT_RGB8)
	image_with_margins.blend_rect(image, Rect2i(0, resolution - margin, resolution, margin), Vector2i(margin + margin, 0))
	image_with_margins.blend_rect(image, Rect2i(0, 0, resolution, resolution), Vector2i(margin, margin))
	image_with_margins.blend_rect(image, Rect2i(0, 0, resolution, margin), Vector2i(0, resolution + margin))

	return image_with_margins


#region Textures folder methods

## Saves a baked map next to the current scene as a compressed .res file and
## returns a reference, so the texture lives on the disk instead of embedded in the .tscn
static func save_baked_texture(texture: Texture2D, node: Node, suffix: String) -> Texture2D:
	var scene_root := node.get_tree().get_edited_scene_root()
	if scene_root == null or scene_root.scene_file_path.is_empty():
		push_warning("Waterways: save the scene before baking so the '%s' map is stored on disk." % suffix)
		return texture

	var dir := scene_root.scene_file_path.get_basename() + _WaterwaysConstants.TEXTURES_FOLDER_SUFFIX
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var node_id := node.name if node == scene_root else String(scene_root.get_path_to(node)).replace("/", "_")
	var path := dir.path_join("%s_%s.res" % [node_id, suffix])

	var err := ResourceSaver.save(texture, path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		push_warning("Waterways: could not save the '%s' map to %s (error %d). Embedding it in the scene instead." % [suffix, path, err])
		return texture

	texture.take_over_path(path)
	return texture


static func _collect_baked_node_ids(scene_root: Node) -> Dictionary:
	var ids := {}
	var stack: Array[Node] = [scene_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is WaterwaysRiver or node is WaterwaysSystem:
			var node_id := node.name if node == scene_root else String(scene_root.get_path_to(node)).replace("/", "_")
			ids[node_id] = true
		stack.append_array(node.get_children())
	return ids


static func _node_id_from_baked_filename(file_name: String) -> String:
	var base := file_name.get_basename()
	for suffix in _WaterwaysConstants.BAKED_TEXTURE_SUFFIXES_MAP.values():
		if base.ends_with("_" + suffix):
			return base.substr(0, base.length() - suffix.length() - 1)
	return ""


## Scans the `_waterways` folder and returns the paths of baked `.res` files
## that dont belong to any WaterwaysRiver or WaterwaysSystem currently in the scene.
static func find_orphaned_baked_textures(scene_root: Node) -> PackedStringArray:
	var orphans: PackedStringArray = []
	if scene_root == null or scene_root.scene_file_path.is_empty():
		return orphans

	var dir_path := scene_root.scene_file_path.get_basename() + _WaterwaysConstants.TEXTURES_FOLDER_SUFFIX
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return orphans

	var known_ids := _collect_baked_node_ids(scene_root)

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension() == "res":
			var node_id := _node_id_from_baked_filename(file_name)
			if not node_id.is_empty() and not known_ids.has(node_id):
				orphans.append(dir_path.path_join(file_name))
		file_name = dir.get_next()
	dir.list_dir_end()

	return orphans


static func delete_baked_textures(paths: PackedStringArray) -> void:
	for path in paths:
		var err := DirAccess.remove_absolute(path)
		if err != OK:
			push_warning("Waterways: could not delete '%s' (error %d)." % [path, err])
	if Engine.is_editor_hint() and not paths.is_empty():
		EditorInterface.get_resource_filesystem().scan()

#endregion
