class_name SweepGear
extends Node3D
## 청소 질주 장비 (PartnerDrone 소유) — 자세와 장비 모델만 맡는다 (청소 판정 · 흡입 효과는 PartnerDrone._sweep).
## Space 를 누른 채 다니는 동안:
##  1. 꺼내기 DRAW_T: 칼 팔을 어깨 너머 등 뒤로 뻗어 → 등에 청소 탱크가 튀어나오고 → 흡입 막대를 뽑아 앞바닥으로 내려 꽂는다.
##  2. 쓸기 루프: 상체를 숙이고 막대 끝 노즐을 앞바닥에서 좌우로 쓸며 문지른다 (가만히 서 있으면 무릎도 굽힌다).
##  3. 집어넣기 STOW_T: 막대를 다시 등 뒤로 넘기고 탱크가 쪼그라들어 사라진다.
## 막대는 칼 팔의 손(j.blade 자리)에서 바닥의 노즐 목표점을 향해 겨누므로 리그와 상관없이 노즐이 바닥에 닿는다.
## 탱크 · 호스 · 막대는 모두 top_level (메카 리그의 거울 노드 밑에 두지 않는다).

enum St { OFF, DRAW, LOOP, STOW }

const DRAW_T := 0.21
const GRAB_T := 0.085           ## 꺼내기 중 손이 등 뒤에 닿는 순간 (탱크가 튀어나온다)
const STOW_T := 0.13
const NOZZLE_AHEAD := 1.35      ## 노즐이 닿는 앞바닥 거리
const SWING := 0.55             ## 노즐 좌우 쓸기 폭 (m)
const SWEEP_HZ := 3.4
const MINT := Color(0.35, 1.0, 0.82)
const TANK_COL := Color(0.93, 0.89, 0.78)
const TANK_DARK := Color(0.23, 0.21, 0.32)
const HOSE_COL := Color(0.2, 0.19, 0.27)
const HOSE_SEG := 10

static var _box: BoxMesh
static var _cyl: CylinderMesh
static var _ball: SphereMesh

var player: Player
var st := St.OFF
var t := 0.0
var phase := 0.0
var k := 0.0                     ## 쓸기 세기 0~1 (루프에서 1, 탱크 창이 차오른다)
var from := {}                   ## 상태 시작 때 관절 값
var aim := Vector3.FORWARD
var tip := Vector3.ZERO          ## 노즐 끝 (월드)

var tank: Node3D
var tank_fill: MeshInstance3D
var wand: Node3D
var head: Node3D
var hose: Array[MeshInstance3D] = []
var _tank_s := 0.0               ## 탱크 크기 (튀어나옴 스프링)
var _tank_v := 0.0
var _blade_hidden := false


func setup(p: Player) -> SweepGear:
	player = p
	_meshes()
	_build_tank()
	_build_wand()
	_build_hose()
	_show(false)
	return self


static func _meshes() -> void:
	if _box:
		return
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	_cyl = CylinderMesh.new()
	_cyl.top_radius = 0.5
	_cyl.bottom_radius = 0.5
	_cyl.height = 1.0
	_cyl.radial_segments = 14
	_cyl.rings = 1
	_ball = SphereMesh.new()
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 14
	_ball.rings = 7


func _part(parent: Node3D, mesh: Mesh, col: Color, pos: Vector3, size: Vector3, emission := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = Pal.lit(col, emission)
	mi.position = pos
	mi.scale = size
	parent.add_child(mi)
	return mi


## 등 탱크: 크림색 원통 + 짙은 뚜껑 · 바닥 + 출렁이는 민트 창 + 띠 + 배기구
func _build_tank() -> void:
	tank = Node3D.new()
	tank.top_level = true
	add_child(tank)
	_part(tank, _cyl, TANK_COL, Vector3.ZERO, Vector3(0.36, 0.62, 0.36))
	_part(tank, _ball, TANK_COL, Vector3(0, 0.31, 0), Vector3(0.36, 0.2, 0.36))
	_part(tank, _cyl, TANK_DARK, Vector3(0, 0.36, 0), Vector3(0.2, 0.08, 0.2))
	_part(tank, _cyl, TANK_DARK, Vector3(0, -0.31, 0), Vector3(0.38, 0.07, 0.38))
	for y in [-0.16, 0.16]:
		_part(tank, _cyl, TANK_DARK, Vector3(0, y, 0), Vector3(0.375, 0.04, 0.375))
	# 앞(바깥, +Z)으로 난 창: 빨아들인 만큼 차오르는 민트 액체
	_part(tank, _box, Color(0.08, 0.12, 0.16), Vector3(0, 0.0, 0.17), Vector3(0.12, 0.42, 0.04))
	tank_fill = _part(tank, _box, MINT, Vector3(0, -0.1, 0.19), Vector3(0.09, 0.2, 0.03), 1.4)
	# 배기구 두 개 (위쪽)
	for x in [-0.08, 0.08]:
		_part(tank, _cyl, TANK_DARK, Vector3(x, 0.44, -0.05), Vector3(0.05, 0.12, 0.05))


## 흡입 막대: 손잡이 + 관 + 넓적한 노즐 머리(민트 입술) · 노즐 끝 점
func _build_wand() -> void:
	wand = Node3D.new()
	wand.top_level = true
	add_child(wand)
	# 막대 길이는 매 틱 늘였다 줄인다 (자식 "tube" 의 z 크기). 막대 축 = -Z
	var tube := _part(wand, _cyl, Color(0.75, 0.78, 0.86), Vector3.ZERO, Vector3(0.05, 1.0, 0.05))
	tube.name = "tube"
	tube.rotation.x = PI * 0.5
	_part(wand, _cyl, TANK_DARK, Vector3(0, 0, -0.05), Vector3(0.075, 0.18, 0.075)).rotation.x = PI * 0.5
	head = Node3D.new()
	head.top_level = true
	add_child(head)
	_part(head, _box, TANK_DARK, Vector3(0, 0.06, 0), Vector3(0.62, 0.09, 0.2))
	_part(head, _box, TANK_COL, Vector3(0, 0.12, 0.02), Vector3(0.4, 0.06, 0.14))
	_part(head, _box, MINT, Vector3(0, 0.025, -0.06), Vector3(0.6, 0.03, 0.06), 2.2)    # 빨아들이는 입
	_part(head, _cyl, TANK_DARK, Vector3(0, 0.18, 0.04), Vector3(0.07, 0.14, 0.07))


func _build_hose() -> void:
	for i in HOSE_SEG:
		var mi := MeshInstance3D.new()
		mi.mesh = _cyl
		mi.material_override = Pal.lit(MINT.darkened(0.25) if i % 3 == 1 else HOSE_COL)
		mi.top_level = true
		add_child(mi)
		hose.append(mi)


func _show(on: bool) -> void:
	tank.visible = on
	wand.visible = on
	head.visible = on
	for h in hose:
		h.visible = on


func active() -> bool:
	return st != St.OFF


## 흡입이 켜져 있다 (쓸기 루프)
func sucking() -> bool:
	return st == St.LOOP


# ── 매 물리 틱 (PartnerDrone._sweep 이 부른다) ──────────────

func update(dt: float, want: bool) -> void:
	if player.dash_t > 0.0 or not player.alive:
		# 대시 중에는 몸이 누워 돈다: 장비는 바로 거둔다 (대시가 끝나도 누르고 있으면 다시 꺼낸다)
		if st != St.OFF:
			_off()
		return
	var a := player.aim_dir
	a.y = 0
	if a.length() > 0.1:
		aim = aim.slerp(a.normalized(), 1.0 - exp(-18.0 * dt)).normalized()
	t += dt
	match st:
		St.OFF:
			if want:
				_enter(St.DRAW)
		St.DRAW:
			if not want:
				_enter(St.STOW)
			elif t >= DRAW_T:
				_enter(St.LOOP)
				_plant_fx()
		St.LOOP:
			phase += dt * TAU * SWEEP_HZ
			if not want:
				_enter(St.STOW)
		St.STOW:
			if want:
				_enter(St.DRAW)
			elif t >= STOW_T:
				_off()
				return
	k = move_toward(k, 1.0 if st == St.LOOP else 0.0, dt * (5.0 if st == St.LOOP else 7.0))


func _enter(s: St) -> void:
	var was := st
	st = s
	t = 0.0
	from = _read_joints()
	if s == St.DRAW:
		player.gear_pose = _pose
		if was == St.OFF:
			phase = 0.0
	elif s == St.STOW:
		var snd := Sfx.play("dash", 0.04, -10.0)
		if snd:
			snd.pitch_scale = 1.5


func _off() -> void:
	st = St.OFF
	k = 0.0
	_show(false)
	_tank_s = 0.0
	_tank_v = 0.0
	if player.gear_pose.is_valid() and player.gear_pose.get_object() == self:
		player.gear_pose = Callable()
	if _blade_hidden and player.j.has("blade"):
		(player.j.blade as Node3D).visible = true
	_blade_hidden = false


func release() -> void:
	if st != St.OFF:
		_off()


## 노즐이 처음 바닥에 닿는 순간: 쿵 · 먼지 · 민트 섬광
func _plant_fx() -> void:
	FX.land_dust(Vector3(tip.x, Main.gy(tip) + 0.05, tip.z))
	FX.flash(tip + Vector3(0, 0.15, 0), MINT, 0.6, 0.05)
	player.squash_v -= 4.0
	var snd := Sfx.play("land", 0.05, -9.0)
	if snd:
		snd.pitch_scale = 1.25


func _read_joints() -> Dictionary:
	var j := player.j
	var ar: Node3D = j.arm_r
	var al: Node3D = j.arm_l
	var to: Node3D = j.torso
	return {"arm_r": ar.rotation, "arm_l": al.rotation, "torso": to.rotation, "crouch": k}


# ── 자세 (Player._animate 끝에서 gear_pose 로 불린다) ─────────

func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


func _back_out(x: float) -> float:
	var s := 1.7
	var q := clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + q * q * ((s + 1.0) * q + s)


## 쓸기 루프 자세: 칼 팔을 앞아래로 내려 몸 앞을 좌우로 쓸며 문지르고 · 상체를 숙여 따라 비튼다.
## (메카 리그 실측: 팔 x 0 = 손이 앞 0.76m · 높이 1.0m, x 를 올리면 머리 위 → 등 뒤로. y + 는 손이 몸 가운데로)
func _loop_pose() -> Dictionary:
	var s := sin(phase)
	var scrub := sin(phase * 2.0)
	return {
		"arm_r": Vector3(-0.3 + scrub * 0.08, 0.35 + s * 0.45, 0.1),
		"arm_l": Vector3(0.1 + scrub * 0.05, -0.2 + s * 0.15, 0.25),
		"torso": Vector3(-0.22 + scrub * 0.03, s * 0.22, s * 0.05),
		"crouch": 1.0,
	}


## 등 뒤로 손을 뻗은 자세 (꺼내기 · 집어넣기의 반환점: 손이 어깨 너머 뒤 · 높이 약 1.5m)
func _reach_pose() -> Dictionary:
	return {
		"arm_r": Vector3(2.9, 0.25, 0.2),
		"arm_l": Vector3(0.1, -0.2, 0.15),
		"torso": Vector3(0.14, 0.42, -0.06),
		"crouch": 0.0,
	}


func _mix(a: Dictionary, b: Dictionary, x: float) -> Dictionary:
	return {
		"arm_r": (a.arm_r as Vector3).lerp(b.arm_r, x),
		"arm_l": (a.arm_l as Vector3).lerp(b.arm_l, x),
		"torso": (a.torso as Vector3).lerp(b.torso, x),
		"crouch": lerpf(float(a.crouch), float(b.crouch), x),
	}


func _pose(p: Player, dt: float) -> void:
	if st == St.OFF:
		return
	var j := p.j
	var pose: Dictionary
	var wand_k := 0.0            # 0 = 막대가 등 뒤 위를 향함 · 1 = 앞바닥 노즐 목표점을 향함
	var grabbed := true
	match st:
		St.DRAW:
			if t < GRAB_T:
				pose = _mix(from, _reach_pose(), _ease_out(t / GRAB_T))
				grabbed = false
			else:
				var x := (t - GRAB_T) / (DRAW_T - GRAB_T)
				pose = _mix(_reach_pose(), _loop_pose(), _back_out(x))
				wand_k = _ease_out(x * 1.15)
		St.LOOP:
			pose = _loop_pose()
			wand_k = 1.0
		St.STOW:
			var x := t / STOW_T
			pose = _mix(from, _reach_pose(), _ease_out(x * 1.4))
			wand_k = 1.0 - _ease_out(x * 1.6)
			grabbed = x < 0.75
	(j.arm_r as Node3D).rotation = pose.arm_r
	(j.arm_l as Node3D).rotation = pose.arm_l
	(j.torso as Node3D).rotation = pose.torso
	var cr := float(pose.crouch)
	var moving := Vector2(p.velocity.x, p.velocity.z).length() > 0.6
	if not moving and cr > 0.0:
		# 가만히 쓸 때는 무릎을 굽혀 자세를 낮춘다 (걸을 때는 걸음 그대로)
		for h in [j.hip_l, j.hip_r]:
			(h as Node3D).rotation.x = lerpf((h as Node3D).rotation.x, 0.32 * cr, 0.5)
		for kn in [j.knee_l, j.knee_r]:
			(kn as Node3D).rotation.x = lerpf((kn as Node3D).rotation.x, -0.55 * cr, 0.5)
		p.visual.position.y -= 0.07 * cr
	# 칼은 숨기고 그 자리(손)에 막대를 쥔다
	var blade: Node3D = j.blade
	if blade.visible:
		blade.visible = false
		_blade_hidden = true
	_place_gear(p, dt, grabbed, wand_k)


## 탱크 · 막대 · 노즐 머리 · 호스를 지금 자세에 맞춰 놓는다
func _place_gear(p: Player, dt: float, grabbed: bool, wand_k: float) -> void:
	var j := p.j
	var torso: Node3D = j.torso
	var yaw := (j.upper as Node3D).global_rotation.y
	var body := Basis(Vector3.UP, yaw)
	var back := body * Vector3(0, 0, 1)
	# 탱크: 꺼내는 손이 등에 닿는 순간 튀어나오고, 집어넣으면 쪼그라든다
	var want_s := 0.0
	if st == St.LOOP or (st == St.DRAW and t >= GRAB_T * 0.85) or (st == St.STOW and t < STOW_T * 0.8):
		want_s = 1.0
	if want_s > 0.5 and _tank_s < 0.05 and not tank.visible:
		_tank_pop()
	_tank_v += ((want_s - _tank_s) * 380.0 - _tank_v * 17.0) * dt
	_tank_s = maxf(0.0, _tank_s + _tank_v * dt)
	tank.visible = _tank_s > 0.02
	var lean := float(torso.rotation.x)
	var tb := body * Basis(Vector3.RIGHT, lean * 0.8) * Basis(Vector3.RIGHT, -0.12)
	var tp := torso.global_position + back * 0.46 + Vector3(0, 0.12, 0)
	tank.global_transform = Transform3D(tb.scaled(Vector3.ONE * maxf(_tank_s, 0.001)), tp)
	var fill := 0.25 + 0.6 * k + sin(Time.get_ticks_msec() * 0.012) * 0.04 * k
	tank_fill.scale.y = 0.42 * clampf(fill, 0.05, 1.0)
	tank_fill.position.y = -0.21 + tank_fill.scale.y * 0.5
	# 막대: 손 → (등 뒤 위 · 앞바닥 노즐 목표점) 사이로 겨눈다
	var grip := (j.blade as Node3D).global_position
	var side := aim.cross(Vector3.UP).normalized()
	var goal := p.global_position + aim * NOZZLE_AHEAD + side * sin(phase) * SWING * (1.0 if st == St.LOOP else 0.4)
	goal.y = Main.gy(goal) + 0.05
	var up_back := grip + (back * 0.55 + Vector3.UP * 0.95)
	var aim_pt := up_back.lerp(goal, wand_k)
	var d := aim_pt - grip
	var length := clampf(d.length(), 0.6, 1.9)
	var dir := d.normalized() if d.length() > 0.01 else aim
	var show_wand := grabbed and tank.visible
	wand.visible = show_wand
	head.visible = show_wand
	if show_wand:
		var wb := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else back)
		wand.global_transform = Transform3D(wb, grip)
		var tube: Node3D = wand.get_node("tube")
		tube.scale = Vector3(0.05, length, 0.05)
		tube.position = Vector3(0, 0, -length * 0.5)
		tip = grip + dir * length
		# 노즐 머리: 바닥에 붙을수록 납작하게 눕는다
		var flat := Basis(Vector3.UP, atan2(-aim.x, -aim.z))
		var hb := Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.98 else back).slerp(flat, wand_k)
		head.global_transform = Transform3D(hb, tip - Vector3(0, 0.05 * wand_k, 0))
	else:
		tip = grip
	# 호스: 탱크 아래 옆 출구 → 손잡이, 아래로 처지는 곡선
	var outlet := tank.to_global(Vector3(0.14, -0.26, 0.05)) if tank.visible else tp
	var c1 := outlet + Vector3(0, -0.45, 0) + back * 0.1
	var c2 := grip - dir * 0.35 + Vector3(0, -0.35, 0)
	var show_hose := tank.visible and show_wand
	var prev := outlet
	for i in hose.size():
		var mi := hose[i]
		mi.visible = show_hose
		if not show_hose:
			continue
		var u := float(i + 1) / hose.size()
		var q := _bezier(outlet, c1, c2, grip, u)
		var seg := q - prev
		var l := seg.length()
		if l > 0.001:
			var y := seg / l
			var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
			var z := x.cross(y)
			mi.global_transform = Transform3D(Basis(x * 0.07, y * (l + 0.02), z * 0.07), (prev + q) * 0.5)
		prev = q


func _bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, u: float) -> Vector3:
	var v := 1.0 - u
	return a * v * v * v + b * 3.0 * v * v * u + c * 3.0 * v * u * u + d * u * u * u


func _tank_pop() -> void:
	_tank_v = 9.0
	var at := tank.global_position
	FX.sparks(at, 10, [Color.WHITE, MINT, TANK_COL], 4.5, 0.3, -6.0, 0.05)
	FX.flash(at, MINT, 0.7, 0.05)
	var snd := Sfx.play("tink", 0.0, -6.0)
	if snd:
		snd.pitch_scale = 1.6
