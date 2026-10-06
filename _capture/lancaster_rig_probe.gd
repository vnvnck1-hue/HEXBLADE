extends SceneTree
## LANCASTER 리그 단독 확인 (게임 없이 빈 무대): 자세별 정면 · 측면 · 3/4 시트.
## powershell -File tools\godot.ps1 wait -s res://_capture/lancaster_rig_probe.gd -- --out=DIR

var out := "res://output/lancaster-boss-20261006/rig"
var holder: Node3D
var rig: LancasterRig
var cam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _run() -> void:
	var w := Node3D.new()
	root.add_child(w)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.32, 0.34, 0.42)
	e.ambient_light_color = Color(0.7, 0.72, 0.8)
	e.ambient_light_energy = 0.8
	env.environment = e
	w.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	w.add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mi.mesh = pm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.45, 0.47, 0.55)
	floor_mi.material_override = fm
	w.add_child(floor_mi)
	holder = Node3D.new()
	w.add_child(holder)
	var vis := Node3D.new()
	holder.add_child(vis)
	rig = LancasterRig.new().setup(vis)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 5.2
	w.add_child(cam)
	cam.make_current()
	await process_frame
	rig.reset_feet()
	var poses := [
		["rest", {}, {}],
		["idle", {"crouch": 0.0}, {}],
		["brace", {"crouch": 0.5, "plant": true}, {"torso": Vector3(-0.16, 0, 0), "upperarm_r": Vector3(0.35, 0, 0.3), "forearm_r": Vector3(0.75, 0, 0)}],
		["claw_back", {"crouch": 0.6, "claw": 1.0}, {"torso": Vector3(0.05, -0.6, 0.05), "upperarm_r": Vector3(-0.55, 0, 0.6), "forearm_r": Vector3(1.1, 0, 0), "hand_r": Vector3(0.35, 0, 0)}],
		["claw_reach", {"crouch": 0.45, "claw": 1.0}, {"torso": Vector3(-0.38, 0.6, 0), "upperarm_r": Vector3(1.45, 0, 0.1), "forearm_r": Vector3(0.15, 0, 0)}],
		["spike_up", {"crouch": 0.75}, {"torso": Vector3(0.25, 0.25, 0), "upperarm_r": Vector3(2.5, 0, 0.35), "forearm_r": Vector3(1.4, 0, 0)}],
		["spike_slam", {"crouch": 1.0}, {"torso": Vector3(-0.6, 0, 0), "upperarm_r": Vector3(0.7, 0, 0.2), "forearm_r": Vector3(-0.15, 0, 0)}],
		["stomp", {"stomp": 1.0, "crouch": 0.15, "plant": true}, {"torso": Vector3(0.18, 0, 0.12), "upperarm_l": Vector3(0.25, 0, -0.55), "upperarm_r": Vector3(0.25, 0, 0.65)}],
		["roar", {"crouch": 0.1, "rage": 1.0}, {"torso": Vector3(0.5, 0, 0), "upperarm_l": Vector3(0.45, 0, -0.7), "upperarm_r": Vector3(1.0, 0, 0.85), "forearm_r": Vector3(0.9, 0, 0)}],
		["kneel", {"kneel": 1.0, "lean": 0.35, "eye_on": 0.0}, {"upperarm_l": Vector3(-0.15, 0, 0.15), "upperarm_r": Vector3(-0.1, 0, -0.15)}],
		["air", {"air": 1.0, "jet": 1.0}, {}],
	]
	for ps in poses:
		_apply(ps[1], ps[2])
		for i in 90:
			rig.update(1.0 / 60.0)
		await _views(ps[0])
	# 걷기: 옆으로 이동하며 몇 프레임
	_apply({"crouch": 0.0}, {})
	rig.gun_aim = 0.7
	rig.aim_point = Vector3(0, 1.0, -10)
	for i in 6:
		for f in 7:
			holder.position.x += 7.0 / 60.0
			rig.vel = Vector3(7.0, 0, 0)
			rig.update(1.0 / 60.0)
		await _views("walk_%d" % i, true)
	quit()


func _apply(v: Dictionary, pose: Dictionary) -> void:
	rig.crouch = v.get("crouch", 0.0)
	rig.plant = v.get("plant", false)
	rig.claw = v.get("claw", 0.0)
	rig.stomp = v.get("stomp", 0.0)
	rig.air = v.get("air", 0.0)
	rig.jet = v.get("jet", 0.0)
	rig.rage = v.get("rage", 0.0)
	rig.kneel = v.get("kneel", 0.0)
	rig.lean = v.get("lean", 0.0)
	rig.eye_on = v.get("eye_on", 1.0)
	rig.gun_aim = 0.0
	rig.vel = Vector3.ZERO
	rig.pose = pose
	holder.position = Vector3.ZERO
	rig.reset_feet()


func _views(name: String, only_q := false) -> void:
	var c := holder.position + Vector3(0, 1.8, 0)
	var dirs := {"front": Vector3(0, 0, -1), "side": Vector3(1, 0, 0), "q": Vector3(0.8, 0.55, -0.9)}
	for k in dirs:
		if only_q and k != "q":
			continue
		var d: Vector3 = dirs[k]
		cam.global_position = c + d.normalized() * 12.0
		cam.look_at(c, Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join("%s_%s.png" % [name, k]))
