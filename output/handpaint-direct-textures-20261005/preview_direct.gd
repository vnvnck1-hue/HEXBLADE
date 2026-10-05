extends SceneTree
## Approval studio only. Original GLB geometry + direct color textures.
## No BrawlLook, palette replacement, brush blending or procedural wear.
const OUT := "res://output/handpaint-direct-textures-20261005/"
var world: Node3D
var materials: Array[StandardMaterial3D] = []
var floor_mat: ShaderMaterial

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _texture(name_: String) -> ImageTexture:
	var img := Image.load_from_file(OUT + name_ + ".png")
	return ImageTexture.create_from_image(img)

func _paint_model(path: String, texture_: Texture2D, at: Vector3) -> Node3D:
	var model := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(model)
	model.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture_
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	materials.append(mat)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
	return model

func _shot(name_: String) -> void:
	await _frames(8)
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(OUT + name_ + ".png")
	print("DIRECT_TEXTURE_CAPTURE ", name_, " error=", error)

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color("141926")
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = Color.WHITE
	we.environment.ambient_light_energy = 0.72
	we.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 0.6
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.2
	world.add_child(camera)
	camera.position = Vector3(7.6, 7.8, 10.5)
	camera.look_at(Vector3(0, 0.9, 0.0))
	camera.current = true
	var tall_tex := _texture("02_tall_wall_albedo")
	var low_tex := _texture("03_low_wall_albedo")
	_paint_model("res://assets/models/bg_claude_w01.glb", tall_tex, Vector3(-2.2, 0, -2.0))
	_paint_model("res://assets/models/bg_claude_w01.glb", tall_tex, Vector3(-0.2, 0, -2.0))
	for x in [1.2, 2.2]:
		_paint_model("res://assets/models/bg_claude_block_wall.glb", low_tex, Vector3(x, 0, -1.5))
	floor_mat = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded; uniform sampler2D tex : source_color, filter_linear, repeat_enable; varying vec3 wp; void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;} void fragment(){ALBEDO=texture(tex,wp.xz/4.0+vec2(0.5)).rgb;}"
	floor_mat.shader = shader
	floor_mat.set_shader_parameter("tex", _texture("01_floor_albedo"))
	for x in [-2.0, 0.0, 2.0]:
		for z in [-2.0, 0.0, 2.0]:
			var n := (load("res://assets/models/bg_claude_f01.glb") as PackedScene).instantiate() as Node3D
			world.add_child(n)
			n.position = Vector3(x - 1.0, 0, z - 1.0)
			for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
				mi.material_override = floor_mat
	await _shot("04_direct_uv_preview")
	for mat in materials:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	shader.code = shader.code.replace("render_mode unshaded; ", "")
	await _shot("05_neutral_light_preview")
	print("DIRECT_PREVIEW_COMPLETE")
	quit()
