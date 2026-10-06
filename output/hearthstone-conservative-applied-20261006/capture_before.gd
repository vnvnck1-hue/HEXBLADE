extends SceneTree

const OUT := "res://output/hearthstone-conservative-applied-20261006/before_effective.png"
var viewport: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(2048, 2048)
	viewport.own_world_3d = true
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.current = true
	camera.position = Vector3(0, 0, 10)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.BLACK
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	viewport.add_child(environment)
	var current := BrawlLook._floor_for(ClaudeBgDress.floor_material())
	assert(current.get_shader_parameter("handpaint") == true)
	var material := current.duplicate() as ShaderMaterial
	var shader := Shader.new()
	var code := current.shader.code
	code = code.replace("render_mode cull_disabled;", "render_mode unshaded, cull_disabled, depth_test_disabled;")
	assert(code.contains("wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;"))
	code = code.replace("wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;", "wpos = vec3(UV.x * 4.0, 0.0, UV.y * 4.0); POSITION = vec4(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0, 0.5, 1.0);")
	code = code.replace("wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);", "wn = vec3(0.0, 1.0, 0.0);")
	shader.code = code
	material.shader = shader
	material.set_shader_parameter("pool_use", 0.0)
	var quad := MeshInstance3D.new()
	quad.mesh = QuadMesh.new()
	quad.material_override = material
	viewport.add_child(quad)
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image().save_png(OUT)
	print("FLOOR_COMPARE_CURRENT save=", result, " paint=", current.get_shader_parameter("paint_tex").resource_path, " lift=", current.get_shader_parameter("lift"), " period=", current.get_shader_parameter("period"))
	assert(result == OK)
	quit()
