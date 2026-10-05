extends SceneTree
## Inspect every actual wall module using the production materials and lighting.
const OUT := "res://output/soft-handpaint-applied-20261005/"
var studio: Node3D

func _initialize() -> void:
	_run.call_deferred()

func _place(kind: String, pos: Vector3, yaw: float = 0.0) -> void:
	var n := (load(ClaudeBgDress.GLB[kind]) as PackedScene).instantiate() as Node3D
	studio.add_child(n)
	n.position = pos
	n.rotation.y = yaw
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if kind == "f01":
			mi.material_override = BrawlLook._floor_for(ClaudeBgDress.floor_material())
		else:
			var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
			mi.material_override = BrawlLook.material_for(src, BrawlLook.R_WALL)
			var mat := mi.material_override as ShaderMaterial
			var tex := mat.get_shader_parameter("paint_tex") as Texture2D
			print("APPROVED_PAINT_MODULE kind=%s atlas=%s texture=%s" % [kind, mat.get_shader_parameter("paint_wall_atlas"), tex.resource_path])

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	studio = Node3D.new()
	root.add_child(studio)
	current_scene = studio
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = BrawlLook.BG
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	we.environment.ambient_light_color = BrawlLook.AMBIENT
	we.environment.ambient_light_energy = BrawlLook.AMBIENT_ENERGY
	we.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	studio.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = BrawlLook.SUN_ROT
	light.light_color = BrawlLook.SUN_COLOR
	light.light_energy = BrawlLook.SUN_ENERGY
	light.shadow_enabled = true
	light.shadow_opacity = BrawlLook.SHADOW_OPACITY
	studio.add_child(light)
	var camera := Camera3D.new()
	studio.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.6
	camera.position = Vector3(7.6, 7.8, 10.5)
	camera.look_at(Vector3(0, 0.8, 0.0))
	camera.current = true
	for x in [-3.0, -1.0, 1.0, 3.0]:
		for z in [-2.0, 0.0, 2.0]:
			_place("f01", Vector3(x - 1.0, 0, z - 1.0))
	_place("w01", Vector3(0, 0, -2.0), PI)
	_place("w01", Vector3(2.0, 0, -2.0), PI)
	_place("half", Vector3(-2.0, 0, -2.0), PI)
	_place("jamb", Vector3(3.0, 0, -2.0), PI)
	_place("wall", Vector3(-2.0, 0, 1.0))
	_place("cover", Vector3(0.0, 0, 1.0))
	_place("pillar", Vector3(2.0, 0, 1.0))
	for frame in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(OUT + "modules.png")
	print("APPROVED_PAINT_MODULES_CAPTURE save=", err)
	quit(0 if err == OK else 1)
