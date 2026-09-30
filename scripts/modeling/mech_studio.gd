extends Node3D

const Model = preload("res://scripts/modeling/reference_mech.gd")
var model: Node3D
var camera: Camera3D
var ui: CanvasLayer
var yaw := -0.52
var pitch := 0.19
var zoom := 5.6
var spinning := false
var dragging := false
var clay := false
var saved_materials: Dictionary = {}
var stats: Label
var status: Label
var capturing := false

func _ready() -> void:
	DisplayServer.window_set_title("Reference Mech — 3D Model Studio")
	var builder = Model.new()
	model = builder.build()
	add_child(model)
	# Ground the asymmetric bevelled soles using the actual mesh bounds.
	var bounds := _bounds(model)
	model.position.y -= bounds.position.y
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("b9c3c1")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e2e7e4")
	env.ambient_light_energy = 0.52
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 0.22
	env.ssao_intensity = 1.7
	env.ssao_detail = 0.6
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	_light(Vector3(-43,-145,0),1.20,Color("fff3db"),true)
	_light(Vector3(-23,35,0),0.55,Color("dce8f0"),false)
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(200,200)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("a2afac")
	floor_mat.roughness = 1
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = floor_mat
	floor_node.position.y = -0.008
	add_child(floor_node)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = 0.05
	camera.far = 100
	add_child(camera)
	camera.current = true
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_ui()
	_update_camera()
	if OS.get_cmdline_user_args().has("--capture"):
		capturing = true
		_capture.call_deferred()
	elif OS.get_cmdline_user_args().has("--export-model"):
		_export()
	elif OS.get_cmdline_user_args().has("--studio-snapshot"):
		_save_studio.call_deferred()

func _save_studio() -> void:
	for k in 20:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://output/reference-mech/studio.png")

func _light(rot: Vector3, energy: float, color: Color, shadows: bool) -> void:
	var l := DirectionalLight3D.new()
	l.rotation_degrees = rot
	l.light_energy = energy
	l.light_color = color
	l.shadow_enabled = shadows
	l.light_angular_distance = 1.2
	l.directional_shadow_max_distance = 25
	l.shadow_bias = 0.035
	add_child(l)

func _bounds(n: Node3D) -> AABB:
	var found := false
	var result := AABB()
	for part in n.find_children("*","MeshInstance3D",true,false):
		var b: AABB = part.global_transform * part.mesh.get_aabb()
		result = result.merge(b) if found else b
		found = true
	return result

func _update_camera() -> void:
	var target := Vector3(0,2.30,0)
	camera.size = zoom
	camera.position = target + Vector3(sin(yaw)*cos(pitch),sin(pitch),-cos(yaw)*cos(pitch))*12
	camera.look_at(target)

func _process(dt: float) -> void:
	if spinning:
		yaw += dt*0.30
		_update_camera()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			dragging = e.pressed
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = maxf(2.4,zoom-0.3)
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = minf(9,zoom+0.3)
		_update_camera()
	elif e is InputEventMouseMotion and dragging:
		spinning = false
		yaw -= e.relative.x*0.008
		pitch = clampf(pitch+e.relative.y*0.006,-0.25,1.15)
		_update_camera()
	elif e is InputEventKey and e.pressed:
		match e.keycode:
			KEY_1: _view(0,0)
			KEY_2: _view(-PI/2,0)
			KEY_3: _view(PI,0)
			KEY_4: _view(-.52,.19)
			KEY_SPACE: spinning = not spinning
			KEY_C: _clay()
			KEY_ESCAPE: get_tree().quit()

func _view(y: float, p: float) -> void:
	spinning = false
	yaw = y
	pitch = p
	zoom = 5.6
	_update_camera()

func _clay() -> void:
	clay = not clay
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("bdbdb7")
	mat.roughness = .8
	for part in model.find_children("*","MeshInstance3D",true,false):
		if clay:
			saved_materials[part] = part.material_override
			part.material_override = mat
		else:
			part.material_override = saved_materials[part]

func _ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var heading := Label.new()
	heading.text = "REFERENCE / 01\nIVORY MECH"
	heading.position = Vector2(36,26)
	heading.add_theme_font_size_override("font_size",26)
	heading.add_theme_color_override("font_color",Color("263732"))
	ui.add_child(heading)
	stats = Label.new()
	stats.position = Vector2(38,100)
	stats.text = "CONCEPT RECONSTRUCTION\n%d mesh parts · %s triangles\nPBR / separate mechanical parts" % [model.get_meta("mesh_count"),str(model.get_meta("triangle_count"))]
	stats.add_theme_font_size_override("font_size",14)
	stats.add_theme_color_override("font_color",Color("4b6058"))
	ui.add_child(stats)
	var bar := VBoxContainer.new()
	bar.position = Vector2(36,182)
	bar.custom_minimum_size.x = 216
	bar.add_theme_constant_override("separation",7)
	ui.add_child(bar)
	for spec in [["01 Front",0.0,0.0],["02 Side",-PI/2,0.0],["03 Back",PI,0.0],["04 Perspective",-.52,.19]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(_view.bind(spec[1],spec[2]))
		bar.add_child(b)
	var clay_button := Button.new()
	clay_button.text = "Clay / C"
	clay_button.pressed.connect(_clay)
	bar.add_child(clay_button)
	var spin_button := Button.new()
	spin_button.text = "Turntable / SPACE"
	spin_button.pressed.connect(func(): spinning = not spinning)
	bar.add_child(spin_button)
	status = Label.new()
	status.position = Vector2(36,440)
	status.text = "DRAG     Orbit\nSCROLL   Zoom\nSPACE    Turntable\n1–4      View presets\nC        Clay material\n\nRear surfaces and hidden\nmount details are inferred."
	status.add_theme_font_size_override("font_size",14)
	status.add_theme_color_override("font_color",Color("3e534b"))
	ui.add_child(status)

func _own(n: Node, scene_root: Node) -> void:
	for c in n.get_children():
		c.owner = scene_root
		_own(c,scene_root)

func _export() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://output/reference-mech"))
	_own(model,model)
	var scene := PackedScene.new()
	var pack_result := scene.pack(model)
	var save_result := ResourceSaver.save(scene,"res://output/reference-mech/reference-mech.tscn") if pack_result == OK else pack_result
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var append_result := doc.append_from_scene(model,state)
	var glb_result := doc.write_to_filesystem(state,"res://output/reference-mech/reference-mech.glb") if append_result == OK else append_result
	var b := _bounds(model)
	var data := {"mesh_parts":model.get_meta("mesh_count"),"triangles":model.get_meta("triangle_count"),"bounds_min":[b.position.x,b.position.y,b.position.z],"bounds_size":[b.size.x,b.size.y,b.size.z],"scene_save":save_result,"gltf_export":glb_result,"front_axis":"-Z","up_axis":"+Y","rear_surfaces":"inferred"}
	var f := FileAccess.open("res://output/reference-mech/model-audit.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(data,"  "))
	print("MODEL_EXPORT ",JSON.stringify(data))

func _capture() -> void:
	_export()
	ui.visible = false
	var views := [["hero",-.52,.19],["front",0.0,0.0],["right",-PI/2,0.0],["back",PI,0.0],["back-three-quarter",2.55,.20],["game-angle",-.65,.64]]
	for spec in views:
		_view(spec[1],spec[2])
		for k in 12:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var err := get_viewport().get_texture().get_image().save_png("res://output/reference-mech/"+spec[0]+".png")
		print("MODEL_CAPTURE ",spec[0]," ",err)
	get_tree().quit()
