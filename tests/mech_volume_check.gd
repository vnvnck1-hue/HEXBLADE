extends SceneTree
## Verify exported rigid hierarchy and textured original shells in Godot.
var fails := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		print("FAIL " + message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var packed := load("res://assets/models/mech_volume_preserved.glb") as PackedScene
	check(packed != null, "GLB imports")
	if not packed:
		quit(1)
		return
	var model := packed.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	var links := {
		"body": "pelvis", "head": "body",
		"hand": "arm_hand_fore", "gun_mount": "arm_gun_fore",
		"pt_grip": "hand", "pt_muzzle": "gun_mount",
		"face_original": "head", "gun_original": "gun_mount",
	}
	for side in ["hand", "gun"]:
		links["shoulder_" + side] = "body"
		links["arm_" + side + "_upper"] = "shoulder_" + side
		links["arm_" + side + "_fore"] = "arm_" + side + "_upper"
		links["hip_" + side] = "pelvis"
		links["knee_" + side] = "hip_" + side
		links["ankle_" + side] = "knee_" + side
		links["foot_" + side + "_original"] = "ankle_" + side
		links["pt_foot_" + side] = "ankle_" + side
	for child: String in links:
		var node := model.find_child(child, true, false)
		check(node != null and node.get_parent().name == links[child], "hierarchy " + child)
	for pair in [["arm_hand_fore", "pt_grip"], ["arm_gun_fore", "pt_muzzle"],
			["knee_hand", "pt_foot_hand"], ["knee_gun", "pt_foot_gun"]]:
		var joint := model.find_child(pair[0], true, false) as Node3D
		var tip := model.find_child(pair[1], true, false) as Node3D
		if not joint or not tip:
			continue
		var before := tip.global_position
		var original := joint.transform
		joint.rotate_x(0.5)
		check(before.distance_to(tip.global_position) > 0.04, "joint moves its endpoint: " + str(pair[0]))
		joint.transform = original
	var textured := 0
	var top := -INF
	var bottom := INF
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		check(part.scale.is_equal_approx(Vector3.ONE), "mesh has no local shrinking: " + part.name)
		var has_paint := false
		for s in part.mesh.get_surface_count():
			var mat := part.mesh.surface_get_material(s) as BaseMaterial3D
			if mat and mat.albedo_texture:
				has_paint = true
			for v: Vector3 in part.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
				var p := part.to_global(v)
				top = maxf(top, p.y)
				bottom = minf(bottom, p.y)
		if has_paint:
			textured += 1
	check(textured >= 25, "original textured shells survive export")
	check(top > 1.75 and top < 1.82 and absf(bottom) < 0.01, "tall ornaments removed, original body bounds retained")
	model.free()
	print("RESULT mech_volume_check fails=%d" % fails)
	quit(1 if fails else 0)
