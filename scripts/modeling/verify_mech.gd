extends SceneTree

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file("res://output/reference-mech/reference-mech.glb",state)
	assert(err == OK,"GLB must load")
	var model := doc.generate_scene(state)
	assert(model != null,"GLB must instantiate")
	root.add_child(model)
	var count := 0
	var vertices := 0
	var bad := 0
	var materials: Dictionary = {}
	for part in model.find_children("*","MeshInstance3D",true,false):
		count += 1
		for i in part.mesh.get_surface_count():
			var arrays: Array = part.mesh.surface_get_arrays(i)
			for v in arrays[Mesh.ARRAY_VERTEX]:
				vertices += 1
				if not v.is_finite(): bad += 1
			for n in arrays[Mesh.ARRAY_NORMAL]:
				if not n.is_finite() or n.length() < 0.9: bad += 1
			var mat = part.mesh.surface_get_material(i)
			assert(mat != null,"Every surface must have a material")
			materials[mat.resource_name] = true
	assert(count >= 230,"All modeled parts must survive export")
	assert(bad == 0,"Geometry and normals must be finite")
	assert(materials.size() == 7,"All seven PBR materials must survive export")
	var studio = load("res://scenes/reference_mech_studio.tscn").instantiate()
	root.add_child(studio)
	await process_frame
	studio._view(0,0)
	assert(studio.camera.position.z < 0)
	studio._view(-PI/2,0)
	assert(studio.camera.position.x < 0)
	studio._view(PI,0)
	assert(studio.camera.position.z > 0)
	studio._clay()
	assert(studio.clay)
	studio._clay()
	assert(not studio.clay)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	studio._unhandled_input(press)
	var old_yaw: float = studio.yaw
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(30,10)
	studio._unhandled_input(motion)
	assert(studio.yaw != old_yaw,"Dragging must orbit the model")
	var old_zoom: float = studio.zoom
	press.button_index = MOUSE_BUTTON_WHEEL_UP
	studio._unhandled_input(press)
	assert(studio.zoom < old_zoom,"Wheel must zoom")
	var result := {"glb_roundtrip":"passed","mesh_parts":count,"vertices":vertices,"invalid_geometry_values":bad,"materials":materials.keys(),"view_presets":"passed","clay_toggle":"passed","orbit_and_zoom":"passed"}
	var f := FileAccess.open("res://output/reference-mech/verification.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result,"  "))
	print("MECH_VERIFIED ",JSON.stringify(result))
	quit()
