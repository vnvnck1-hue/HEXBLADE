class_name InsectMotion
extends RefCounted
## Named Blender pivots → procedural insect animation. Owns poses, never damage/AI.
## Walk: world-space stance anchors + two-link IK. Ant alternates tripods;
## grub uses a delayed contraction wave. Animation preview uses this same driver.

const MODES := ["idle", "walk", "windup", "attack", "recover", "hurt", "stagger", "death", "emerge"]
var actor: Node3D
var model: Node3D
var body: Node3D
var head: Node3D
var thorax: Node3D
var ant := true
var joints: Dictionary = {}
var rest: Dictionary = {}
var legs: Array[Dictionary] = []
var clock := 0.0
var gait := 0.0
var prev := Vector3.ZERO
var mode := "idle"
var turn_lag := 0.0
var last_yaw := 0.0


func setup(owner_node: Node3D, asset: Node3D, is_ant: bool) -> void:
	actor = owner_node
	model = asset
	ant = is_ant
	body = asset.find_child("body", true, false) as Node3D
	head = asset.find_child("head", true, false) as Node3D
	thorax = asset.find_child("thorax", true, false) as Node3D
	_collect(body)
	for row in 3:
		for side in ["l", "r"]:
			var id: String = side + str(row)
			var h: Node3D = joints["leg_" + id + "_hip"]
			var kn: Node3D = joints["leg_" + id + "_knee"]
			var f: Node3D = joints["leg_" + id + "_foot"]
			var tip := asset.find_child("pt_foot_" + id, true, false) as Node3D
			var origin := actor.to_local(tip.global_position)
			var u := actor.global_basis.inverse() * (kn.global_position - h.global_position)
			var v := actor.global_basis.inverse() * (f.global_position - kn.global_position)
			legs.append({"hip": h, "knee": kn, "foot": f, "tip": tip, "origin": origin,
				"upper": u, "lower": v, "a": u.length(), "b": v.length(),
				"hip_basis": actor.global_basis.inverse() * h.global_basis,
				"knee_basis": actor.global_basis.inverse() * kn.global_basis,
				"foot_basis": actor.global_basis.inverse() * f.global_basis,
				"offset": tip.position, "anchor": tip.global_position,
				"from": tip.global_position, "swing": false,
				"phase": (float((row + (1 if side == "r" else 0)) % 2) * 0.5) if ant else row * 0.19 + (0.5 if side == "r" else 0.0),
				"side": -1.0 if side == "l" else 1.0})
	prev = actor.global_position
	last_yaw = actor.rotation.y


func _collect(n: Node3D) -> void:
	if not n is MeshInstance3D:
		joints[n.name] = n
		rest[n.name] = n.transform
	for c in n.get_children():
		if c is Node3D:
			_collect(c)


func reset_feet() -> void:
	for l in legs:
		l.anchor = actor.to_global(l.origin)
		l.anchor.y = Main.gy(l.anchor)
		l.from = l.anchor
		l.swing = false
	prev = actor.global_position


func pose(next_mode: String, progress: float, speed: float, dt: float) -> void:
	var changed := mode != next_mode
	mode = next_mode
	clock += dt
	var distance := Vector2(actor.global_position.x - prev.x, actor.global_position.z - prev.z).length()
	if distance > 2.0:
		reset_feet()
	prev = actor.global_position
	var stride := 0.62 if ant else 0.32
	if speed > 0.03 and mode == "walk":
		# Preview can walk in place; live cycles follow actual travelled distance.
		gait += maxf(distance, speed * dt * 0.35) / stride
	var yaw_delta := wrapf(actor.rotation.y - last_yaw, -PI, PI)
	last_yaw = actor.rotation.y
	turn_lag = lerpf(turn_lag, clampf(-yaw_delta / maxf(dt, 0.001) * 0.10, -0.35, 0.35), 1.0 - exp(-8.0 * dt))
	for key: String in rest:
		(joints[key] as Node3D).transform = rest[key]
	var k := clampf(progress, 0.0, 1.0)
	var activity := clampf(speed / (3.6 if ant else 1.6), 0.0, 1.0) if mode == "walk" else 0.0
	thorax.position.y += sin(clock * 3.0) * (0.012 if ant else 0.019)
	if ant:
		thorax.position.y += sin(gait * TAU * 2.0) * 0.025 * activity
		thorax.rotation.z += sin(gait * TAU) * 0.065 * activity
		head.rotation.y += sin(clock * 1.9) * 0.085 + turn_lag * 0.7
		for i in range(1, 5):
			var ab: Node3D = joints["abdomen_" + str(i)]
			ab.rotation.y += sin(clock * 3.2 - i * 0.65) * 0.035 + turn_lag * float(i) * 0.22
			ab.position.y += sin(gait * TAU - i * 0.6) * 0.018 * activity
	else:
		for i in 6:
			var ab: Node3D = joints["abdomen_" + str(i)]
			var wave := sin(gait * TAU - i * 0.82)
			ab.position.y += wave * 0.06 * activity
			ab.position.z += cos(gait * TAU - i * 0.82) * 0.065 * activity
			ab.rotation.x += wave * 0.11 * activity
			ab.rotation.y += turn_lag * i * 0.11
		head.rotation.x += sin(gait * TAU + 0.5) * 0.065 * activity
	# Autonomous searching and delayed tips, even at rest.
	for side in ["l", "r"]:
		var sign_side := -1.0 if side == "l" else 1.0
		for i in 3:
			var feeler: Node3D = joints["antenna_%s_%d" % [side, i]]
			feeler.rotation.x += sin(clock * 4.0 - i * 0.6 + sign_side) * 0.10
			feeler.rotation.y += sign_side * (sin(clock * 2.8 - i * 0.8 + sign_side) * 0.13 + turn_lag)
			if mode == "walk":
				feeler.rotation.x += sin(gait * TAU - i * 0.7) * 0.13 * activity
	var jaw_open := 0.06 + sin(clock * 2.6) * 0.035
	match mode:
		"windup":
			thorax.position.y -= k * (0.14 if ant else 0.11)
			thorax.rotation.x -= k * (0.22 if ant else 0.32)
			head.rotation.x -= k * 0.2
			jaw_open += k * 0.8
			for side in ["l", "r"]:
				(joints["antenna_" + side + "_0"] as Node3D).rotation.x -= k * 0.4
		"attack":
			var snap := sin(k * PI)
			thorax.position.z -= snap * (0.17 if ant else 0.13)
			thorax.rotation.x += snap * 0.3
			head.rotation.x += snap * 0.25
			jaw_open += (1.0 - smoothstep(0.12, 0.35, k)) * 0.9
		"recover":
			thorax.rotation.x += (1.0-k) * 0.2
			jaw_open += (1.0-k) * 0.2
		"hurt", "stagger":
			var recoil := exp(-k * 4.5) * sin(k * PI * 3.0)
			thorax.rotation.x -= recoil * 0.40
			head.rotation.z += recoil * 0.18
			jaw_open += absf(recoil) * 0.3
		"emerge":
			body.position.y -= (1.0-smoothstep(0.0, 1.0, k)) * (1.85 if ant else 1.3)
			body.rotation.x -= sin(k * PI) * 0.25
		"death":
			var fall := smoothstep(0.06, 0.55, k)
			body.rotation.z = fall * (1.4 if ant else 1.15)
			body.position.y += fall * (0.32 if ant else 0.22)
			body.position.z += fall * 0.25
			jaw_open = 0.45
			for l in legs:
				(l.hip as Node3D).rotation.z += l.side * (0.7 * fall + sin(clock * 28.0) * 0.06 * (1.0-k))
				(l.knee as Node3D).rotation.x += 0.6 * fall
	for side in ["l", "r"]:
		(joints["jaw_" + side] as Node3D).rotation.y += jaw_open * (-1.0 if side == "l" else 1.0)
	if mode != "death" and mode != "emerge":
		_feet(activity, speed, changed)


func _feet(activity: float, speed: float, changed: bool) -> void:
	var stride := (0.62 if ant else 0.32) * maxf(activity, 0.25)
	var forward := -actor.global_basis.z.normalized()
	for l in legs:
		var ph := fposmod(gait + float(l.phase), 1.0)
		var swinging := mode == "walk" and speed > 0.03 and ph > 0.60
		var nominal: Vector3 = actor.to_global(l.origin)
		nominal.y = Main.gy(nominal)
		if changed and mode != "walk":
			l.anchor = nominal
		if swinging and not l.swing:
			l.from = l.anchor
		if not swinging and l.swing:
			l.anchor = nominal + forward * stride * 0.45
			l.anchor.y = Main.gy(l.anchor)
		l.swing = swinging
		var goal: Vector3 = l.anchor
		if swinging:
			var k := (ph-0.60)/0.40
			var ahead := nominal + forward * stride * 0.45
			ahead.y = Main.gy(ahead)
			goal = (l.from as Vector3).lerp(ahead, smoothstep(0.0,1.0,k))
			goal.y += sin(k * PI) * (0.15 if ant else 0.07) * maxf(activity, 0.3)
		# Teleports / tight turns: recover an unreachable planted foot.
		# Reach is measured to the ankle, not the claw tip projecting past it.
		var ankle_goal := goal - actor.global_basis * (l.foot_basis as Basis) * (l.offset as Vector3)
		if ankle_goal.distance_to((l.hip as Node3D).global_position) > (l.a + l.b) * 0.997:
			goal = nominal
			l.anchor = goal
		_solve(l, goal)


func _solve(l: Dictionary, tip_goal: Vector3) -> void:
	var hip: Node3D = l.hip
	var knee: Node3D = l.knee
	var foot: Node3D = l.foot
	# Foot stays level; IK targets its pivot while its claw marker touches terrain.
	var foot_basis: Basis = actor.global_basis * l.foot_basis
	var target := tip_goal - foot_basis * (l.offset as Vector3)
	var from := hip.global_position
	var d := target - from
	var length := clampf(d.length(), absf(l.a-l.b)+0.001, l.a+l.b-0.001)
	var axis := d.normalized() if d.length() > 0.001 else Vector3.DOWN
	var pole := actor.global_basis * Vector3(l.side, 0.18, 0.05)
	pole = (pole - axis * pole.dot(axis)).normalized()
	var along: float = (l.a*l.a + length*length - l.b*l.b) / (2.0*length)
	var bend := from + axis * along + pole * sqrt(maxf(0.0, l.a*l.a-along*along))
	var u: Vector3 = actor.global_basis * (l.upper as Vector3)
	var v: Vector3 = actor.global_basis * (l.lower as Vector3)
	hip.global_basis = Basis(Quaternion(u.normalized(), (bend-from).normalized())) * actor.global_basis * (l.hip_basis as Basis)
	knee.global_basis = Basis(Quaternion(v.normalized(), (target-bend).normalized())) * actor.global_basis * (l.knee_basis as Basis)
	foot.global_basis = foot_basis
