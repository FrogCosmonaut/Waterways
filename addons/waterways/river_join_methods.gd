class_name _WaterwaysRiverJoinMethods
extends RefCounted
## Edge matching for endpoint (start/end) joins between two rivers.


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
			var w := clampf(1.0 - dist_from_edge / _WaterwaysConstants.EDGE_MATCH_FEATHER, 0.0, 1.0)

			if w <= 0.0:
				continue

			var orig := dst.get_pixel(x, y)
			dst.set_pixel(x, y, orig.lerp(src_color, w))

			if debug_mask != null:
				debug_mask.set_pixel(x, y, Color(w, w, w, 1.0))
