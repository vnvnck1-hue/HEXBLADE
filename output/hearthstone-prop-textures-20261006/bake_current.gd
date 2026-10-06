extends SceneTree
## UV capture of today's effective base color, before dynamic lighting.
const OUT := "res://output/hearthstone-prop-textures-20261006/"
const SIZE := 2048
const MODELS := ["bg_claude_f01", "bg_claude_w01", "bg_claude_w01_half", "bg_claude_block_wall", "bg_claude_block_cover", "bg_claude_block_pillar", "bg_claude_jamb", "bg_claude_a01", "bg_claude_a02", "bg_claude_service_s01_vent", "bg_claude_service_s02_tank", "bg_claude_service_s03_pipe", "bg_claude_service_s04_elbow", "bg_claude_service_s05_column"]
var vp: SubViewport
var holder: Node3D
var records: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _frames() -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw

func _capture(file: String) -> void:
	await _frames()
	var err := vp.get_texture().get_image().save_png(OUT + file)
	print("UV_BAKE ", file, " save=", err)
	assert(err == OK)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT + "references")
	vp = SubViewport.new()
	vp.size = Vector2i(SIZE, SIZE)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var cam := Camera3D.new()
	vp.add_child(cam)
	cam.current = true
	cam.position = Vector3(0, 0, 10)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	vp.add_child(env)
	for key: String in MODELS:
		holder = Node3D.new()
		vp.add_child(holder)
		var model := (load("res://assets/models/" + key + ".glb") as PackedScene).instantiate() as Node3D
		holder.add_child(model)
		var source_path := ""
		var materials: Array[ShaderMaterial] = []
		if key == "bg_claude_f01":
			model.visible = false
			var q := MeshInstance3D.new()
			q.mesh = QuadMesh.new()
			holder.add_child(q)
			var original := BrawlLook._floor_for(ClaudeBgDress.floor_material())
			var sm := original.duplicate() as ShaderMaterial
			var sh := Shader.new()
			var code := original.shader.code
			code = code.replace("render_mode cull_disabled;", "render_mode unshaded, cull_disabled, depth_test_disabled;")
			code = code.replace("wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;", "wpos = vec3(UV.x * 4.0, 0.0, UV.y * 4.0); POSITION = vec4(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0, 0.5, 1.0);")
			code = code.replace("wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);", "wn = vec3(0.0, 1.0, 0.0);")
			sh.code = code
			sm.shader = sh
			q.material_override = sm
			materials.append(sm)
			source_path = "res://assets/models/bg_claude_f01_floor_4m_v3.png"
		else:
			# Match front-facing placement for the wall and service references.
			model.rotation.y = PI if key.contains("w01") or key.contains("service") else 0.0
			var role := BrawlLook.R_SERVICE if key.contains("service") else BrawlLook.R_WORLD if key.contains("a01") or key.contains("a02") else BrawlLook.R_WALL
			for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				mi.custom_aabb = AABB(Vector3(-100, -100, -100), Vector3(200, 200, 200))
				for si in mi.mesh.get_surface_count():
					var src := mi.mesh.surface_get_material(si) as BaseMaterial3D
					if src == null:
						continue
					if src.albedo_texture:
						source_path = src.albedo_texture.resource_path
					var original := BrawlLook.material_for(src, role)
					var sm := original.duplicate() as ShaderMaterial
					var sh := Shader.new()
					var code := original.shader.code
					code = code.replace("render_mode cull_disabled;", "render_mode unshaded, cull_disabled, depth_test_disabled;")
					if not code.contains("render_mode unshaded"):
						code = code.replace("shader_type spatial;", "shader_type spatial;\nrender_mode unshaded, cull_disabled, depth_test_disabled;")
					code = code.replace("wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;", "wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; POSITION = vec4(UV.x * 2.0 - 1.0, 1.0 - UV.y * 2.0, 0.5, 1.0);")
					sh.code = code
					sm.shader = sh
					sm.set_shader_parameter("emission_energy", 0.0)
					mi.set_surface_override_material(si, sm)
					materials.append(sm)
		await _capture("references/" + key + "_current.png")
		# Save exact rasterized coverage for UV area metrics and padding.
		for sm in materials:
			var sh := Shader.new()
			var code := sm.shader.code
			code = code.replace("ALBEDO = clamp(col, 0.0, 1.0);", "ALBEDO = vec3(1.0);")
			sh.code = code
			sm.shader = sh
		await _capture("references/" + key + "_coverage.png")
		records.append({"model": key, "glb": "assets/models/" + key + ".glb", "source_texture": source_path, "size": [SIZE, SIZE], "mapping": "world_xz_4m" if key.ends_with("f01") else "original_uv", "reference": "references/" + key + "_current.png"})
		holder.queue_free()
		await _frames()
	var file := FileAccess.open(OUT + "models.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	print("UV_BAKE_COMPLETE count=", records.size())
	quit()
