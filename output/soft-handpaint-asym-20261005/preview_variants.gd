extends SceneTree
## Separate approval studio. Original GLB + each generated albedo, direct sampling.
const OUT := "res://output/soft-handpaint-asym-20261005/"
var studio: Node3D
var mats: Array[StandardMaterial3D] = []
var floor_mat: ShaderMaterial

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _texture(file: String) -> ImageTexture:
	var img := Image.load_from_file(OUT + file + ".png")
	return ImageTexture.create_from_image(img)

func _capture(name_: String) -> void:
	await _frames(8)
	await RenderingServer.frame_post_draw
	var image_ := root.get_texture().get_image()
	var result := image_.save_png(OUT + name_ + ".png")
	print("SOFT_CAPTURE ", name_, " size=", image_.get_size(), " error=", result)

func _wall(at: Vector3, tex: Texture2D) -> void:
	var n := (load("res://assets/models/bg_claude_w01.glb") as PackedScene).instantiate() as Node3D
	studio.add_child(n)
	# W01 front is -Z. Match the game's rear-wall placement facing +Z.
	n.rotation.y = PI
	n.position = at + Vector3(2.0, 0, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mats.append(mat)
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat

func _variant(key: String) -> void:
	studio = Node3D.new()
	root.add_child(studio)
	current_scene = studio
	mats.clear()
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color("171b2a")
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color.WHITE
	we.environment.ambient_light_energy = 0.72
	we.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	studio.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.light_energy = 0.6
	light.shadow_enabled = true
	studio.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.7
	studio.add_child(camera)
	camera.position = Vector3(7.6, 7.8, 10.5)
	camera.look_at(Vector3(0, 0.8, 0.0))
	camera.current = true
	var tex := _texture(key + "_wall")
	_wall(Vector3(-2.0, 0, -2.0), tex)
	_wall(Vector3(0.0, 0, -2.0), tex)
	floor_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded; uniform sampler2D tex : source_color, filter_linear, repeat_enable; varying vec3 wp; void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;} void fragment(){ALBEDO=texture(tex,wp.xz/4.0+vec2(0.5)).rgb;}"
	floor_mat.shader = shader
	floor_mat.set_shader_parameter("tex", _texture(key + "_floor"))
	for x in [-2.0, 0.0, 2.0]:
		for z in [-2.0, 0.0, 2.0]:
			var n := (load("res://assets/models/bg_claude_f01.glb") as PackedScene).instantiate() as Node3D
			studio.add_child(n)
			n.position = Vector3(x - 1.0, 0, z - 1.0)
			for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
				mi.material_override = floor_mat
	await _capture(key + "_model_direct")
	for mat in mats:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	shader.code = shader.code.replace("render_mode unshaded; ", "")
	await _capture(key + "_model_lit")
	studio.queue_free()
	await _frames(5)

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	for key in ["A", "B", "C"]:
		await _variant(key)
	print("SOFT_VARIANTS_COMPLETE")
	quit()
