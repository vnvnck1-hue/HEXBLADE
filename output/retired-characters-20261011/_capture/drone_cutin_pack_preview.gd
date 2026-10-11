extends SceneTree
## Resource-only renderer/validator. Does not attach to Main or mutate gameplay.
const PACK := "res://assets/vfx/drone_cutin/"
const OUT := "res://output/drone-cutin-resources-20261004/"
var background: Texture2D
var layer_root: Control
var dock_at := Vector2.ZERO
var strand_from := Vector2.ZERO
var issues := 0
var report := {}

func _initialize() -> void:
	call_deferred("_run")

func _tex(name: String) -> Texture2D:
	var tex := load(PACK + name) as Texture2D
	if tex == null:
		issues += 1
		push_error("PACK_TEXTURE_MISSING " + name)
	return tex

func _image_tex(path: String) -> Texture2D:
	var img := Image.load_from_file(path)
	if img == null:
		issues += 1
		push_error("PACK_IMAGE_MISSING " + path)
		return null
	return ImageTexture.create_from_image(img)

func _rect(parent: Node, tex: Texture2D, pos: Vector2, sz: Vector2) -> TextureRect:
	var n := TextureRect.new()
	n.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	n.texture = tex
	n.position = pos
	n.size = sz
	n.stretch_mode = TextureRect.STRETCH_SCALE
	n.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(n)
	if n.size.distance_to(sz) > 0.1:
		issues += 1
		push_error("PACK_RECT_SIZE " + str(n.size) + " expected " + str(sz))
	return n

func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	background = _image_tex(OUT + "gameplay_reference.png")
	var plate := _tex("cockpit_plate.png")
	if plate == null:
		quit(1)
		return
	report["source_size"] = [plate.get_width(), plate.get_height()]
	var svg_names := ["panel_mask.svg","panel_frame.svg","panel_glow.svg","lock_ring.svg","dock_flash.svg","triangle_shard.svg","sync_streak.svg","bashful_ticks.svg"]
	for name: String in svg_names:
		var tex := _tex(name)
		if tex:
			var img := tex.get_image()
			var outside_alpha := img.get_pixel(0,0).a
			report[name] = {"size":[img.get_width(),img.get_height()],"corner_alpha":outside_alpha}
			if outside_alpha > 0.01:
				issues += 1
				push_error("PACK_SVG_OPAQUE_CORNER " + name)
	await _export_panels(plate)
	var clipped := _image_tex(PACK + "cockpit_plate_clipped.png")
	for viewport_size: Vector2i in [Vector2i(1953,805),Vector2i(1280,800),Vector2i(1280,720)]:
		root.size = viewport_size
		root.get_window().size = viewport_size
		var view := Vector2(viewport_size)
		layer_root = Control.new()
		root.add_child(layer_root)
		var bg_scale := minf(view.x / 3396.0, view.y / 1399.0)
		var bg_size := Vector2(3396,1399) * bg_scale
		var bg_pos := (view - bg_size) * 0.5
		_rect(layer_root, background, bg_pos, bg_size)
		var side := minf(view.y * 1.22, view.x * 0.51)
		var pos := Vector2(-side * 0.025, -side * 0.05)
		var size_panel := Vector2.ONE * side
		_rect(layer_root, _tex("panel_glow.svg"), pos, size_panel)
		_rect(layer_root, clipped, pos, size_panel)
		_rect(layer_root, _tex("panel_frame.svg"), pos, size_panel)
		var shard := _tex("triangle_shard.svg")
		for i in 5:
			var sp := pos + Vector2(side * (0.81 + float(i % 2) * 0.14), side * (0.16 + float(i) * 0.17))
			var n := _rect(layer_root, shard, sp, Vector2.ONE * view.y * 0.036)
			n.rotation = float(i) * 0.9
		dock_at = bg_pos + bg_size * Vector2(0.51,0.435)
		strand_from = pos + size_panel * Vector2(0.88,0.30)
		var lines := Control.new()
		lines.draw.connect(_draw_strands.bind(lines, view.y / 800.0))
		layer_root.add_child(lines)
		_rect(layer_root, _tex("lock_ring.svg"), dock_at - Vector2.ONE * view.y * 0.08, Vector2.ONE * view.y * 0.16)
		_rect(layer_root, _tex("dock_flash.svg"), dock_at - Vector2.ONE * view.y * 0.055, Vector2.ONE * view.y * 0.11)
		# Source screenshot HUD patch acts as an illustrative topmost HUD layer.
		var hud := AtlasTexture.new()
		hud.atlas = background
		hud.region = Rect2(0,0,520,156)
		_rect(layer_root,hud,bg_pos,Vector2(520,156) * bg_scale)
		for _i in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var path := OUT + "preview_%dx%d.png" % [viewport_size.x, viewport_size.y]
		var err := root.get_texture().get_image().save_png(path)
		if err != OK:
			issues += 1
			push_error("PACK_PREVIEW_SAVE " + str(err))
		layer_root.queue_free()
		await process_frame
	report["issues"] = issues
	var f := FileAccess.open(OUT + "engine_validation.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(report,"  "))
	f.close()
	print("DRONE_CUTIN_PACK_CHECK issues=%d source=%s previews=3 alpha=checked" % [issues,str(report.get("source_size"))])
	quit(1 if issues else 0)

func _export_panels(plate: Texture2D) -> void:
	var sub := SubViewport.new()
	sub.size = Vector2i(1024,1024)
	sub.transparent_bg = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(sub)
	var ctrl := Control.new()
	sub.add_child(ctrl)
	var art := _rect(ctrl,plate,Vector2.ZERO,Vector2(1024,1024))
	# Compare against the same GPU sampling without the mask material.
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var original_color := sub.get_texture().get_image()
	art.material = load(PACK + "panel_clip.tres") as ShaderMaterial
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := sub.get_texture().get_image()
	if image.save_png(PACK + "cockpit_plate_clipped.png") != OK:
		issues += 1
		push_error("PACK_CLIPPED_SAVE")
	var outside := image.get_pixel(4,4).a
	var face := image.get_pixel(500,350).a
	report["clipped"] = {"corner_alpha":outside,"face_alpha":face,"format":image.get_format(),"size":[1024,1024]}
	if outside > 0.01 or face < 0.99:
		issues += 1
		push_error("PACK_ALPHA_CLIP")
	var mask := _tex("panel_mask.svg").get_image()
	var mismatches := 0
	var color_samples := 0
	var max_rgb_error := 0.0
	for y in range(0,1024,8):
		for x in range(0,1024,8):
			if absf(image.get_pixel(x,y).a - mask.get_pixel(x,y).a) > 0.04:
				mismatches += 1
			if mask.get_pixel(x,y).a > 0.99:
				var actual := image.get_pixel(x,y)
				var expected := original_color.get_pixel(x,y)
				var error := maxf(absf(actual.r - expected.r), maxf(absf(actual.g - expected.g), absf(actual.b - expected.b)))
				max_rgb_error = maxf(max_rgb_error, error)
				color_samples += 1
	report["color_preservation"] = {"samples":color_samples,"max_rgb_error":max_rgb_error}
	if color_samples == 0 or max_rgb_error > 0.02:
		issues += 1
		push_error("PACK_COLOR_CHANGED " + str(max_rgb_error))
	report["mask_alpha_mismatches_on_8px_grid"] = mismatches
	if mismatches > 32:
		issues += 1
		push_error("PACK_MASK_ALIGNMENT " + str(mismatches))
	_rect(ctrl,_tex("panel_glow.svg"),Vector2.ZERO,Vector2(1024,1024))
	_rect(ctrl,_tex("panel_frame.svg"),Vector2.ZERO,Vector2(1024,1024))
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var ready := sub.get_texture().get_image()
	if ready.save_png(PACK + "cockpit_cutin_ready.png") != OK:
		issues += 1
		push_error("PACK_READY_SAVE")
	report["ready"] = {"corner_alpha":ready.get_pixel(4,4).a,"face_alpha":ready.get_pixel(500,350).a,"size":[1024,1024]}
	if ready.get_pixel(4,4).a > 0.01 or ready.get_pixel(500,350).a < 0.99:
		issues += 1
		push_error("PACK_READY_ALPHA")
	sub.queue_free()
	await process_frame

func _draw_strands(lines: Control, k: float) -> void:
	for i in 3:
		var pts := PackedVector2Array()
		var delta := float(i - 1) * 14.0 * k
		for j in 24:
			var t := float(j) / 23.0
			var p := strand_from.lerp(dock_at,t) + Vector2(0, sin(PI * t) * (-36.0 * k + delta))
			pts.append(p)
		lines.draw_polyline(pts,Color(0.52,1.0,0.87,0.8),3.0 * k,true)
		lines.draw_polyline(pts,Color(0.95,1.0,0.97,0.8),1.0 * k,true)
