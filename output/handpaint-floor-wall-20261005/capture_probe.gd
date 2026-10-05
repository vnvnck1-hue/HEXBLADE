extends SceneTree
const OUT := "res://output/handpaint-floor-wall-20261005/"
var report: Dictionary = {"engine": Engine.get_version_info(), "assets": [], "captures": []}

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name_: String) -> void:
	await _frames(8)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var err := img.save_png(OUT + "sources/" + name_ + ".png")
	report.captures.append({"name": name_, "width": img.get_width(), "height": img.get_height(), "save_error": err})
	print("SOURCE_CAPTURE ", name_, " ", err)

func _inspect(key: String) -> void:
	var path: String = ClaudeBgDress.GLB[key]
	var asset := (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(asset)
	var info: Dictionary = {"key": key, "path": path, "meshes": []}
	for mi: MeshInstance3D in asset.find_children("*", "MeshInstance3D", true, false):
		var bb := asset.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		var entry: Dictionary = {"name": mi.name, "bounds_position": [bb.position.x, bb.position.y, bb.position.z], "bounds_size": [bb.size.x, bb.size.y, bb.size.z], "surfaces": []}
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			entry.surfaces.append({"vertices": arr[Mesh.ARRAY_VERTEX].size(), "indices": arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] != null else 0, "uv_count": arr[Mesh.ARRAY_TEX_UV].size() if arr[Mesh.ARRAY_TEX_UV] != null else 0, "texture": mat.albedo_texture.resource_path if mat and mat.albedo_texture else "", "texture_size": str(mat.albedo_texture.get_size()) if mat and mat.albedo_texture else ""})
		info.meshes.append(entry)
	report.assets.append(info)
	asset.free()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "sources"))
	root.get_node("Run").set("active", false)
	for key in ["f01", "w01", "half", "wall", "cover", "pillar"]:
		_inspect(key)
	seed(4)
	change_scene_to_file("res://scenes/training.tscn")
	await _frames(100)
	var game := current_scene as Main
	game.hud.visible = false
	var panel: Variant = game.get("panel")
	if panel is CanvasItem:
		panel.visible = false
	game.process_mode = Node.PROCESS_MODE_DISABLED
	await _shot("01_training_current")
	game.player.global_position = Vector3(1.5, 0, -2)
	if is_instance_valid(PartnerDrone.inst):
		PartnerDrone.inst.global_position = Vector3(3.3, 0.3, -1.5)
	game.camera.global_position = Vector3(2, 18, 5.6)
	game.camera.look_at(Vector3(2, 0, -4), Vector3.UP)
	await _shot("06_training_floor_wall")
	game.camera.global_position = Vector3(9, 11, 9)
	game.camera.look_at(Vector3(8, 0, -6), Vector3.UP)
	await _shot("02_training_wall_current")
	game.queue_free()
	await _frames(8)
	seed(4)
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(100)
	game = current_scene as Main
	game.hud.visible = false
	game.process_mode = Node.PROCESS_MODE_DISABLED
	await _shot("03_main_current")
	game.queue_free()
	await _frames(8)
	var studio := Node3D.new()
	root.add_child(studio)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("252735")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a1a9cb")
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	studio.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	studio.add_child(sun)
	var cam := Camera3D.new()
	studio.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 10.5
	cam.position = Vector3(7, 8, 11)
	cam.look_at(Vector3(0, 0.8, 0))
	cam.make_current()
	var models: Array[Node3D] = []
	for z in 2:
		for x in 3:
			var fl := (load(ClaudeBgDress.GLB.f01) as PackedScene).instantiate() as Node3D
			fl.position = Vector3(-3 + x * 2, 0, -2 + z * 2)
			studio.add_child(fl)
			for mi: MeshInstance3D in fl.find_children("*", "MeshInstance3D", true, false):
				mi.material_override = ClaudeBgDress.floor_material()
			models.append(fl)
	for x in 3:
		var wall := (load(ClaudeBgDress.GLB.w01) as PackedScene).instantiate() as Node3D
		wall.position = Vector3(-3 + x * 2, 0, -2)
		wall.rotation.y = PI
		# The asset front is -Z: rotate it to face +Z, retaining its 2m span.
		wall.position.x += 2
		studio.add_child(wall)
		models.append(wall)
	for z in 3:
		var block := (load(ClaudeBgDress.GLB.wall) as PackedScene).instantiate() as Node3D
		block.position = Vector3(-3.5, 0, -1.5 + z)
		studio.add_child(block)
		models.append(block)
	await _shot("04_actual_modules_material")
	var clay := StandardMaterial3D.new()
	clay.albedo_color = Color("9199a6")
	clay.roughness = 0.9
	for model in models:
		for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = clay
	await _shot("05_actual_modules_clay")
	var f := FileAccess.open(OUT + "geometry_report.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	studio.queue_free()
	await _frames(4)
	print("GEOMETRY_REVIEW_COMPLETE")
	quit()
