class_name _WaterwaysConfluenceMethods
extends RefCounted
## Edge matching for T/Y confluences, where a tributary river desembocates into
## the side of a main river.


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
			var w := clampf(1.0 - dist_from_edge / _WaterwaysConstants.EDGE_MATCH_FEATHER, 0.0, 1.0)
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
			var w := clampf(1.0 - dist_from_edge / _WaterwaysConstants.EDGE_MATCH_FEATHER, 0.0, 1.0)
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
