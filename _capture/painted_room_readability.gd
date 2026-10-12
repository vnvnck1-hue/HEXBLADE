extends "res://_capture/painted_room_show.gd"
## A stationary real mech and simple ground marks, not a gameplay simulation.

func _run() -> void:
	studio = SCENE.instantiate()
	root.add_child(studio)
	await process_frame
	root.size = Vector2i(1600, 1000)
	studio.ui.visible = false
	studio.set_view(0)
	studio.set_light(1)
	var body := Node3D.new()
	body.position = Vector3(-0.5, 0.02, 0.1)
	body.rotation_degrees.y = 155
	studio.add_child(body)
	var actors: Array[Node3D] = [body]
	var mech: Node3D = load(MechPlayer.GLB).instantiate()
	mech.position = MechPlayer.SHIFT
	body.add_child(mech)
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		for s in mi.mesh.get_surface_count():
			var source := mi.get_active_material(s)
			if source is BaseMaterial3D and BrawlLook.convertible(source):
				var copied: BaseMaterial3D = source.duplicate()
				for key in copied.get_meta_list():
					if str(key).begins_with("bl_"):
						copied.remove_meta(key)
				mi.set_surface_override_material(s, BrawlLook.material_for(copied, BrawlLook.R_BODY))
	for row in [[Vector3(-0.5, 0.025, 0.1), Color("75e4de"), 0.6], [Vector3(1.2, 0.025, -0.35), Color("ff7555"), 0.8]]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = row[2] - 0.025
		torus.outer_radius = row[2] + 0.025
		torus.rings = 48
		torus.ring_segments = 8
		ring.mesh = torus
		ring.position = row[0]
		ring.scale.y = 0.1
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = row[1]
		torus.material = material
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		studio.add_child(ring)
		actors.append(ring)
	await shot("13_static_mech_markers")
	studio.set_palette(1.0, 1.0)
	await shot("16_previous_bright_mech_markers")
	studio.set_palette(studio.MUTED_SATURATION, studio.MUTED_BRIGHTNESS)
	studio.toggle_reference()
	await shot("14_static_mech_original")
	studio.toggle_reference()
	for row in [["energy", Vector3(1.35, 0.6, -1.0)], ["missile", Vector3(1.7, 0.6, 0.75)]]:
		var pickup := Pickup.new()
		pickup.kind = row[0]
		pickup.position = row[1]
		studio.add_child(pickup)
		# Use the real ready-built pickup meshes/materials, frozen for matching shots.
		# No Main/player simulation or collection behavior is run in this study.
		pickup.set_physics_process(false)
		pickup.ring.global_position = Vector3(pickup.position.x, 0.04, pickup.position.z)
		actors.append(pickup)
	await shot("17_static_mech_real_pickups")
	studio.set_palette(1.0, 1.0)
	await shot("18_previous_bright_real_pickups")
	print("PAINTED_ROOM_READABILITY_OK stationary_model_only")
	for actor in actors:
		actor.queue_free()
	for i in 10:
		await process_frame
	quit()
