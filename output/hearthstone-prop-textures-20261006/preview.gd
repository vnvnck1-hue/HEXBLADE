extends SceneTree
## Same original meshes, UVs, default Brawl lights. Only direct PNG base color changes.
const OUT := "res://output/hearthstone-prop-textures-20261006/"
var studio: Node3D
var camera: Camera3D
var core_materials: Array[ShaderMaterial] = []
var current_key := ""
var captures: Array = []
var models: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _texture(model: String, key: String) -> Texture2D:
	var file := "references/" + model + "_current.png"
	if key != "current":
		for record: Dictionary in models:
			if record.model == model:
				file = "png/" + key + "/" + str(record.source_texture).get_file()
	var image := Image.load_from_file(OUT + file)
	assert(image != null and not image.is_empty(), file)
	if key == "current":
		image.flip_y()
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _frames(n: int = 8) -> void:
	for i in n:
		await process_frame
	await RenderingServer.frame_post_draw

func _capture(name_: String) -> void:
	await _frames()
	var err := root.get_texture().get_image().save_png(OUT + "previews/" + name_ + ".png")
	assert(err == OK)
	captures.append(name_)
	print("PROP_PREVIEW ", name_, " save=", err)

func _world() -> void:
	studio = Node3D.new()
	root.add_child(studio)
	current_scene = studio
	core_materials.clear()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = BrawlLook.BG
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = BrawlLook.AMBIENT
	env.environment.ambient_light_energy = BrawlLook.AMBIENT_ENERGY
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	studio.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = BrawlLook.SUN_ROT
	sun.light_color = BrawlLook.SUN_COLOR
	sun.light_energy = BrawlLook.SUN_ENERGY
	sun.shadow_enabled = true
	sun.shadow_opacity = BrawlLook.SHADOW_OPACITY
	sun.shadow_blur = 2.2
	sun.directional_shadow_max_distance = 70.0
	studio.add_child(sun)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 13.8
	studio.add_child(camera)
	camera.position = Vector3(9.5, 13.0, 18.0)
	camera.look_at(Vector3(0, 0.4, 0))
	camera.current = true
	RenderingServer.global_shader_parameter_set(&"bl_pool", Vector4(0, 0, 0, 0))

func _add(model: String, at: Vector3, yaw: float = 180.0) -> Node3D:
	var n := (load("res://assets/models/" + model + ".glb") as PackedScene).instantiate() as Node3D
	studio.add_child(n)
	n.rotation_degrees.y = yaw
	var bound := AABB()
	var first := true
	var tex := _texture(model, current_key)
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.get_aabb()
		bound = b if first else bound.merge(b)
		first = false
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si) as BaseMaterial3D
			if src == null:
				continue
			var role := BrawlLook.R_SERVICE if model.contains("service") else BrawlLook.R_WORLD if model.contains("a01") or model.contains("a02") else BrawlLook.R_WALL
			var mat := BrawlLook.material_for(src, role).duplicate() as ShaderMaterial
			mat.set_shader_parameter("albedo", Color.WHITE)
			mat.set_shader_parameter("albedo_tex", tex)
			mat.set_shader_parameter("use_tex", true)
			mat.set_shader_parameter("tex_gamma", 1.0)
			mat.set_shader_parameter("sat", 1.0)
			mat.set_shader_parameter("value_k", 1.0)
			mat.set_shader_parameter("tint", Color.WHITE)
			mat.set_shader_parameter("role_mix", 0.0)
			mat.set_shader_parameter("handpaint", false)
			mat.set_shader_parameter("top_lift", 0.0)
			mat.set_shader_parameter("pool_on", 0.0)
			mat.set_shader_parameter("rim", 0.0)
			mi.set_surface_override_material(si, mat)
			core_materials.append(mat)
	n.position = at - Vector3(bound.get_center().x, bound.position.y, bound.get_center().z)
	return n

func _floor() -> void:
	var mat := BrawlLook._floor_for(ClaudeBgDress.floor_material()).duplicate() as ShaderMaterial
	mat.set_shader_parameter("albedo_tex", _texture("bg_claude_f01", current_key))
	mat.set_shader_parameter("handpaint", false)
	mat.set_shader_parameter("use_base", false)
	mat.set_shader_parameter("lift", 1.0)
	mat.set_shader_parameter("sat", 1.0)
	mat.set_shader_parameter("warm", Color.WHITE)
	mat.set_shader_parameter("pool_on", 0.0)
	core_materials.append(mat)
	for x in range(-6, 6, 2):
		for z in range(-4, 6, 2):
			var n := (load("res://assets/models/bg_claude_f01.glb") as PackedScene).instantiate() as Node3D
			studio.add_child(n)
			n.position = Vector3(x, -0.02, z)
			for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
				mi.material_override = mat

func _layout(group: String) -> void:
	_world()
	_floor()
	if group == "walls":
		_add("bg_claude_w01", Vector3(-3.7, 0, -2.7))
		_add("bg_claude_w01_half", Vector3(-1.5, 0, -2.7))
		_add("bg_claude_jamb", Vector3(-0.1, 0, -2.7))
		_add("bg_claude_a01", Vector3(2.4, 0, -2.1))
		_add("bg_claude_a02", Vector3(4.5, 0, -2.5))
		_add("bg_claude_block_wall", Vector3(-3.6, 0, 0.6), 0.0)
		_add("bg_claude_block_cover", Vector3(-1.6, 0, 0.6), 0.0)
		_add("bg_claude_block_pillar", Vector3(0.5, 0, 0.6), 0.0)
	else:
		_add("bg_claude_service_s01_vent", Vector3(-3.8, 0, -1.7))
		_add("bg_claude_service_s02_tank", Vector3(-0.7, 0, -1.7))
		_add("bg_claude_service_s05_column", Vector3(2.2, 0, -1.7))
		_add("bg_claude_service_s03_pipe", Vector3(-2.3, 0, 1.4), 0.0)
		_add("bg_claude_service_s04_elbow", Vector3(1.2, 0, 1.4), 0.0)
		camera.size = 10.3
		camera.position = Vector3(8.4, 11, 16)
		camera.look_at(Vector3(0, 0.7, 0))

func _unlit() -> void:
	for mat in core_materials:
		var code := mat.shader.code
		code = code.replace("render_mode cull_disabled;", "render_mode cull_disabled, unshaded;")
		if not code.contains("unshaded"):
			code = code.replace("shader_type spatial;", "shader_type spatial; render_mode unshaded;")
		var sh := Shader.new()
		sh.code = code
		mat.shader = sh
		mat.set_shader_parameter("emission_energy", 0.0)

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	DirAccess.make_dir_recursive_absolute(OUT + "previews")
	models.assign(JSON.parse_string(FileAccess.get_file_as_string(OUT + "models.json")))
	var keys := ["current", "A", "B", "C"]
	if OS.get_cmdline_user_args().has("--first"):
		keys = ["current", "A"]
	for key: String in keys:
		current_key = key
		for group: String in ["walls", "service"]:
			if OS.get_cmdline_user_args().has("--first") and group == "service":
				continue
			_layout(group)
			await _capture(key + "_" + group + "_lit")
			_unlit()
			await _capture(key + "_" + group + "_direct")
			studio.queue_free()
			await _frames(3)
	var file := FileAccess.open(OUT + "preview_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"captures": captures, "godot": Engine.get_version_info(), "basecolor": "direct PNG, no procedural repaint", "lights": "BrawlLook constants, pool off for equal comparison"}, "\t"))
	print("PROP_PREVIEW_COMPLETE count=", captures.size())
	quit()
