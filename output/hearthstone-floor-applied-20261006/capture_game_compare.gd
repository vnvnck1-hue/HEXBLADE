extends SceneTree
const PAINT := preload("res://scripts/claude_background/blue_handpaint.gd")
const OUT := "res://output/hearthstone-floor-applied-20261006/"
var scene: Main
var floors: Array[ShaderMaterial] = []
var saved: Array[Dictionary] = []
var old_mean: Vector3

func _initialize() -> void:
	_run.call_deferred()

func _snap(name_: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(OUT + name_ + ".png")
	print("FLOOR_GAME_COMPARE ", name_, " save=", err, " player=", scene.player.global_position)
	assert(err == OK)

func _pair(frame: int) -> void:
	paused = true
	floors.clear()
	saved.clear()
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi.material_override as ShaderMaterial
		if m == null or m.shader != BrawlLook._shaders.get("floor") or floors.has(m):
			continue
		floors.append(m)
		saved.append({"paint_tex": m.get_shader_parameter("paint_tex"), "paint_mean": m.get_shader_parameter("paint_mean"), "floor_direct": m.get_shader_parameter("floor_direct"), "lift": m.get_shader_parameter("lift")})
	assert(not floors.is_empty())
	await _snap("game_%04d_after" % frame)
	for m in floors:
		m.set_shader_parameter("paint_tex", PAINT.PREVIOUS_FLOOR_TEXTURE)
		m.set_shader_parameter("paint_mean", old_mean)
		m.set_shader_parameter("floor_direct", false)
		m.set_shader_parameter("lift", 0.82)
	await _snap("game_%04d_before" % frame)
	for i in floors.size():
		for key in saved[i]:
			floors[i].set_shader_parameter(key, saved[i][key])
	var original_shader := floors[0].shader
	var mask_shader := Shader.new()
	mask_shader.code = original_shader.code.replace("render_mode cull_disabled;", "render_mode unshaded, cull_disabled;").replace("ALBEDO = clamp(col, 0.0, 1.0);", "ALBEDO = vec3(1.0, 0.0, 1.0);")
	for m in floors:
		m.shader = mask_shader
	await _snap("game_%04d_floor_mask" % frame)
	for m in floors:
		m.shader = original_shader
	paused = false

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	seed(4)
	PAINT.direct_floor = false
	old_mean = PAINT.mean_for(false)
	PAINT.direct_floor = true
	scene = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	scene.map_seed = 4
	root.add_child(scene)
	current_scene = scene
	assert(scene.player.bot)
	for frame in 1800:
		await physics_frame
		if frame in [120, 480]:
			await process_frame
			await _pair(frame)
	print("FLOOR_GAME_COMPARE_COMPLETE bot=", scene.player.bot, " game_time=", scene.time, " seed=4")
	quit()
