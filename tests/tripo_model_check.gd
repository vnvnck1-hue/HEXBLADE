extends SceneTree
## Prototype import and rigid-joint contract. Does not claim production animation readiness.
var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok:
		fails += 1

func _run() -> void:
	var scene := load("res://assets/models/tripo_mecha_proto.glb") as PackedScene
	_check(scene != null, "Tripo prototype imports")
	if scene == null:
		quit(1)
		return
	var model := scene.instantiate() as Node3D
	root.add_child(model)
	await process_frame
	var arm := model.find_child("arm_hand_upper", true, false) as Node3D
	var fore := model.find_child("arm_hand_fore", true, false) as Node3D
	var hand := model.find_child("hand", true, false) as Node3D
	var grip := model.find_child("pt_grip", true, false) as Node3D
	_check(arm != null and fore != null and hand != null and grip != null, "articulated arm and grip exist")
	if arm and fore and hand and grip:
		_check(fore.get_parent() == arm and hand.get_parent() == fore and grip.get_parent() == hand, "shoulder-elbow-wrist-grip hierarchy")
		var before := grip.global_position
		fore.rotate_x(0.5)
		_check(grip.global_position.distance_to(before) > 0.1, "elbow rotation moves grip")
		fore.rotate_x(-0.5)
	for side in ["gun", "hand"]:
		var hip := model.find_child("hip_" + side, true, false) as Node3D
		var knee := model.find_child("knee_" + side, true, false) as Node3D
		var ankle := model.find_child("ankle_" + side, true, false) as Node3D
		var foot := model.find_child("pt_foot_" + side, true, false) as Node3D
		_check(hip != null and knee != null and ankle != null and foot != null, side + " leg chain exists")
		if hip and knee and ankle and foot:
			_check(knee.get_parent() == hip and ankle.get_parent() == knee and foot.get_parent() == ankle, side + " rigid leg parenting")
			_check(absf(foot.global_position.y) < 0.001, side + " foot at Godot ground plane")
	var top := -INF
	var bottom := INF
	var textured := false
	var count := 0
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var part := n as MeshInstance3D
		count += 1
		for s in part.mesh.get_surface_count():
			var data := part.mesh.surface_get_arrays(s)
			for v: Vector3 in data[Mesh.ARRAY_VERTEX]:
				var p := part.to_global(v)
				top = maxf(top, p.y)
				bottom = minf(bottom, p.y)
			var mat := part.mesh.surface_get_material(s) as BaseMaterial3D
			if mat and mat.albedo_texture:
				textured = true
	_check(count > 12 and textured, "parts and source paint survive GLB import")
	_check(top > 1.4 and top < 1.8 and absf(bottom) < 0.01, "ornament-free body bounds: %.3f..%.3f m" % [bottom, top])
	var muzzle := model.find_child("pt_muzzle", true, false) as Node3D
	_check(muzzle != null and muzzle.global_position.z < -0.5, "muzzle faces Godot forward -Z")
	model.free()
	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
