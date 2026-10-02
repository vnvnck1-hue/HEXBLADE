extends "res://scripts/abyss/abyss_foe.gd"
## 허스크 (껍질벌레): 무리로 심연 가장자리를 기어올라 오는 근접 잡몹.
## 뼈빛 갑각 판 세 장 · 흑철 다리 넷 · 붉은 겹눈. 약하고 빠르다.
## 행동: 추격 → (가까우면) 몸을 낮추고 붉게 번쩍이는 예고 0.38초 → 도약 물기 → 착지 후 잠깐 멈칫.
## 등장: 가장자리 바깥 벽면을 기어 올라와 바닥 위로 넘어온다 (spawn_info.cell / out).

const Stage := preload("res://scripts/abyss/abyss_stage.gd")

enum S { CHASE, TELE, LEAP, RECOVER }

const SPEED := 4.4
const LEAP_RANGE := 3.6
const TELE_T := 0.38
const LEAP_T := 0.34
const LEAP_DIST := 4.6
const RECOVER_T := 0.6
const CLIMB_T := 0.55
const HOP_T := 0.24

var leap_cd := 0.6
var leap_from := Vector3.ZERO
var leap_to := Vector3.ZERO
var bit := false
var gait := 0.0
var weave := 0.0
var _edge := Vector3.ZERO
var _out := Vector3.FORWARD
var _snd := 0.0


func _ready() -> void:
	hp = 1
	radius = 0.5
	slice_size = Vector3(0.55, 0.35, 0.85)
	slice_color = BONE
	hp_bar_y = 1.1
	hp_bar_w = 0.7
	super._ready()
	weave = randf() * TAU
	leap_cd = randf_range(0.3, 1.0)
	var body := j.body as Node3D
	visual.scale = Vector3.ONE * 1.3
	body.position.y = 0.42
	shadow.scale = Vector3.ONE * 0.6
	if spawn_info.has("cell"):
		_edge = Stage.cell_center(spawn_info.cell)
		_out = spawn_info.out
		global_position = _edge + _out * 1.15
		rotation.y = atan2(_out.x, _out.z)          # 머리(-Z)가 안쪽을 본다
		body.position.y = -2.4
	else:
		landed = true


func _build(v: Node3D) -> Dictionary:
	var body := Build.pivot(v, Vector3(0, 0.42, 0), "Body")
	# 배: 짙은 살덩이
	Build.bevel(body, Vector3(0.42, 0.18, 0.72), Vector3(0, -0.06, 0.02), FLESH, 0.05)
	# 등 갑각 세 장 (앞으로 갈수록 높게 겹친다)
	Build.bevel(body, Vector3(0.58, 0.16, 0.36), Vector3(0, 0.1, 0.24), BONE_DARK, 0.06, Vector3(-8, 0, 0), 0.8)
	Build.bevel(body, Vector3(0.62, 0.18, 0.38), Vector3(0, 0.15, -0.02), BONE, 0.06, Vector3(-6, 0, 0), 0.8)
	Build.bevel(body, Vector3(0.54, 0.16, 0.32), Vector3(0, 0.17, -0.27), BONE, 0.06, Vector3(4, 0, 0), 0.8)
	# 꼬리 가시
	Build.bevel(body, Vector3(0.14, 0.1, 0.3), Vector3(0, 0.08, 0.5), BONE_DARK, 0.03, Vector3(-18, 0, 0), 0.5)
	# 머리 · 턱
	var head := Build.pivot(body, Vector3(0, 0.06, -0.5), "Head")
	Build.bevel(head, Vector3(0.34, 0.2, 0.26), Vector3(0, 0, 0), IRON_LIGHT, 0.05, Vector3.ZERO, 0.85)
	for s in [-1.0, 1.0]:
		Build.bevel(head, Vector3(0.05, 0.05, 0.26), Vector3(s * 0.12, -0.07, -0.2), BONE, 0.015, Vector3(0, s * 20.0, 0))
	# 겹눈: 개체마다 따로 밝기를 바꾸는 붉은 발광
	var em := glow_mat(EYE, 2.2)
	var eye_mesh := BoxMesh.new()
	eye_mesh.size = Vector3(0.07, 0.05, 0.05)
	var core := MeshInstance3D.new()
	core.mesh = eye_mesh
	core.material_override = em
	head.add_child(core)
	core.position = Vector3(0, 0.05, -0.135)
	for s in [-1.0, 1.0]:
		var e2 := MeshInstance3D.new()
		e2.mesh = eye_mesh
		e2.material_override = em
		head.add_child(e2)
		e2.position = Vector3(s * 0.09, 0.04, -0.125)
		e2.scale = Vector3(0.7, 0.8, 1)
	# 다리 넷: 엉덩이 → 위다리(바깥 위로) → 아래다리(땅으로)
	var legs: Array = []
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		var zz := -0.2 if i < 2 else 0.22
		var hip := Build.pivot(body, Vector3(side * 0.26, 0.0, zz), "Hip%d" % i)
		var up := Build.pivot(hip, Vector3.ZERO, "Up")
		Build.bevel(up, Vector3(0.07, 0.07, 0.36), Vector3(side * 0.16, 0.08, 0), IRON, 0.02, Vector3(0, side * 90.0, side * 25.0))
		var knee := Build.pivot(up, Vector3(side * 0.32, 0.15, 0), "Knee")
		Build.bevel(knee, Vector3(0.06, 0.5, 0.06), Vector3(side * 0.03, -0.25, 0), BONE_DARK, 0.02, Vector3(0, 0, side * 6.0), 0.5)
		legs.append({"hip": hip, "knee": knee, "side": side, "ph": (0.0 if i == 0 or i == 3 else PI)})
	return {"body": body, "core": core, "core_mat": em, "head": head, "legs": legs}


# ── 등장: 가장자리 벽면을 기어오른다 ─────────────────────

func _update_entry(dt: float) -> void:
	drop_t += dt
	var body := j.body as Node3D
	if not spawn_info.has("cell"):
		landed = true
		return
	var inward := -_out
	if drop_t < CLIMB_T:
		# 벽면에 붙어 머리를 위로 하고 올라온다
		var k := drop_t / CLIMB_T
		body.position.y = lerpf(-2.4, -0.15, 1.0 - pow(1.0 - k, 2.0))
		body.rotation.x = deg_to_rad(80.0)
		global_position = _edge + _out * 1.15
		gait += dt * 16.0
		_legs(1.0)
		shadow.visible = false
		if randf() < dt * 5.0:
			FX.sparks(global_position + Vector3(0, -0.2, 0), 2, [Color(0.4, 0.38, 0.4), Color(0.2, 0.18, 0.2)], 2.0, 0.3, -10.0, 0.05)
	else:
		var k := clampf((drop_t - CLIMB_T) / HOP_T, 0.0, 1.0)
		body.rotation.x = deg_to_rad(80.0) * (1.0 - k)
		body.position.y = lerpf(-0.15, 0.42, k) + sin(k * PI) * 0.35
		global_position = (_edge + _out * 1.15).lerp(_edge + _out * 0.35, k)
		shadow.visible = k > 0.4
		if k >= 1.0:
			landed = true
			body.rotation = Vector3.ZERO
			FX.land_dust(global_position)
			if _snd <= 0.0:
				Sfx.play("land", 0.25, -12.0)


# ── 행동 ────────────────────────────────────────────────

func _ai(dt: float) -> void:
	var body := j.body as Node3D
	var tp := to_player()
	var dir: Vector3 = tp[0]
	var dist: float = tp[1]
	var em := j.core_mat as StandardMaterial3D
	leap_cd -= dt
	_snd -= dt
	match st:
		S.CHASE:
			set_tele(false)
			weave += dt * 2.2
			var side := Vector3(-dir.z, 0, dir.x) * sin(weave) * 0.45
			var move := (dir + side + separation(1.2) * 0.8).limit_length(1.0)
			if not active():
				move = Vector3(-dir.z, 0, dir.x) * 0.3
			global_position += (move * SPEED + knock) * dt
			face(move if move.length() > 0.1 else dir, dt, 10.0)
			gait += dt * 15.0
			_legs(1.0)
			body.position.y = 0.42 + absf(sin(gait)) * 0.04
			body.rotation.z = sin(gait) * 0.06
			em.emission_energy_multiplier = 2.2
			if active() and dist < LEAP_RANGE and leap_cd <= 0.0:
				go(S.TELE)
				set_tele(true)
				Sfx.play("pcue", 0.2, -14.0)
		S.TELE:
			# 몸을 낮추고 뒤로 당겨 힘을 모은다
			var k := clampf(st_t / TELE_T, 0.0, 1.0)
			face(dir, dt, 14.0)
			body.position.y = lerpf(0.42, 0.28, k)
			body.rotation.x = -0.25 * k
			body.position.x = randf_range(-1, 1) * 0.02 * k
			em.emission_energy_multiplier = 2.2 + 6.0 * k
			_legs(0.2)
			if st_t >= TELE_T:
				leap_from = global_position
				var tgt := Main.inst.player.global_position + Main.inst.player.velocity * 0.12
				var d := tgt - global_position
				d.y = 0
				leap_to = global_position + d.limit_length(LEAP_DIST)
				bit = false
				body.position.x = 0
				go(S.LEAP)
				Sfx.play("dash", 0.2, -10.0)
		S.LEAP:
			var k := clampf(st_t / LEAP_T, 0.0, 1.0)
			global_position = leap_from.lerp(leap_to, 1.0 - pow(1.0 - k, 1.6))
			body.position.y = 0.42 + sin(k * PI) * 0.9
			body.rotation.x = lerpf(0.35, -0.3, k)
			_legs(0.0)
			var p := Main.inst.player
			if not bit and p.alive and Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length() < 0.8:
				bit = true
				p.take_hit(global_position)
			if k >= 1.0:
				set_tele(false)
				FX.land_dust(global_position)
				AbyssFX.splat(global_position, 0.6)
				go(S.RECOVER)
		S.RECOVER:
			var k := clampf(st_t / RECOVER_T, 0.0, 1.0)
			body.rotation.x = lerpf(-0.3, 0.0, k)
			body.position.y = 0.42
			em.emission_energy_multiplier = 1.0 + k * 1.2
			global_position += knock * dt
			if st_t >= RECOVER_T:
				leap_cd = randf_range(0.9, 1.8)
				go(S.CHASE)
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	global_position = Main.inst.push_out(global_position, radius)


## 다리 걸음: amp 0 이면 다리를 모은다
func _legs(amp: float) -> void:
	for l in j.legs:
		var hip := l.hip as Node3D
		var knee := l.knee as Node3D
		var s: float = l.side
		var ph: float = l.ph
		var sw := sin(gait + ph) * amp
		hip.rotation = Vector3(0, sw * 0.45 * s, 0)
		knee.rotation = Vector3(0, 0, (maxf(0.0, cos(gait + ph)) * 0.4 * amp - 0.1 + (1.0 - amp) * 0.35) * s)


func _on_stagger() -> void:
	super._on_stagger()
	if st == S.TELE or st == S.LEAP:
		go(S.RECOVER)


func _can_hurt() -> bool:
	return st != S.LEAP


func _begin_death() -> void:
	Sfx.play("hit", 0.2, -2.0)
	super._begin_death()
