extends "res://scripts/abyss/abyss_foe.gd"
## 갑각 참회자 (PENITENT): 등에 거대한 성유물 갑각을 지고 앞으로 방패처럼 내민 중장 거구.
## 정면 갑각은 탄을 튕겨 낸다 → 옆·뒤로 돌거나, 검으로 베거나, 예고 뒤 빈틈을 노린다.
## 행동: 느린 전진(몸을 천천히 돌려 갑각이 플레이어를 향하게) ·
##   내려찍기 (예고 원 0.75초 → 충격 + 초승달 고리 14발) · 돌진 (예고선 0.8초 → 직선 돌진).
## 처치되면 부풀어 오르다 파열한다: 주변 적을 함께 터뜨리고, 너무 가까운 플레이어도 다친다 (킬 나이트의 갑각 폭발).
## 등장: 어둠 위에서 떨어져 묵직하게 착지한다.

enum S { WALK, SLAM_TELE, SLAM, CHARGE_TELE, CHARGE, RECOVER }

const Shot := preload("res://scripts/abyss/abyss_shot.gd")
const BRONZE := Color("5c4a3a")
const BRONZE_LIGHT := Color("8a7050")
const GOLD := Color("b8924c")
const SPEED := 1.7
const TURN := 2.2
const SLAM_R := 2.6
const SLAM_TELE_T := 0.75
const CHARGE_TELE_T := 0.8
const CHARGE_T := 0.75
const CHARGE_SPEED := 12.0
const SHIELD_HALF := 1.08          # 정면 갑각이 막는 반각 (약 62°)
const RUPTURE_T := 0.75
const RUPTURE_R := 4.2
const RUPTURE_HURT_R := 2.4
const DROP_T := 0.5

var slam_cd := 1.0
var charge_cd := 3.0
var charge_dir := Vector3.FORWARD
var hit_player := false
var warn: MeshInstance3D
var line: MeshInstance3D
var gait := 0.0
var _rupture_warn: MeshInstance3D


func _ready() -> void:
	hp = 14
	radius = 1.05
	slice_size = Vector3(1.3, 1.5, 1.2)
	slice_color = BRONZE
	hp_bar_y = 3.0
	hp_bar_w = 1.5
	super._ready()
	slam_cd = randf_range(0.8, 1.6)
	charge_cd = randf_range(2.5, 4.0)
	(j.body as Node3D).position.y = 9.0
	shadow.scale = Vector3.ONE * 1.3


func _build(v: Node3D) -> Dictionary:
	var body := Build.pivot(v, Vector3.ZERO, "Body")
	var hips := Build.pivot(body, Vector3(0, 0.95, 0), "Hips")
	Build.bevel(hips, Vector3(0.8, 0.35, 0.55), Vector3.ZERO, IRON, 0.06)
	# 다리 둘 (굵은 흑철 + 뼈 무릎)
	var legs: Array = []
	for s in [-1.0, 1.0]:
		var hip := Build.pivot(hips, Vector3(s * 0.34, -0.1, 0), "Leg")
		Build.bevel(hip, Vector3(0.3, 0.55, 0.32), Vector3(0, -0.25, 0), IRON_LIGHT, 0.05)
		var knee := Build.pivot(hip, Vector3(0, -0.5, 0), "Knee")
		Build.bevel(knee, Vector3(0.26, 0.5, 0.3), Vector3(0, -0.22, 0.05), IRON, 0.05)
		Build.bevel(knee, Vector3(0.22, 0.16, 0.22), Vector3(0, 0, -0.12), BONE, 0.04)
		Build.bevel(knee, Vector3(0.34, 0.12, 0.5), Vector3(0, -0.46, -0.06), IRON_LIGHT, 0.04)
		legs.append({"hip": hip, "knee": knee, "side": s})
	# 상체: 앞으로 숙인 몸통 + 등의 살덩이 주머니(약점처럼 맥동)
	var torso := Build.pivot(hips, Vector3(0, 0.25, 0), "Torso")
	torso.rotation.x = -0.25
	Build.bevel(torso, Vector3(0.9, 0.75, 0.6), Vector3(0, 0.4, 0.05), FLESH, 0.1, Vector3.ZERO, 0.9)
	var sack_m := glow_mat(Color(0.9, 0.08, 0.14), 0.8)
	var sm := SphereMesh.new()
	sm.radius = 0.42
	sm.height = 0.7
	var sack := MeshInstance3D.new()
	sack.mesh = sm
	sack.material_override = sack_m
	torso.add_child(sack)
	sack.position = Vector3(0, 0.55, 0.42)
	# 등 위의 성유물 갑각 (층층이 쌓인 판)
	var shell := Build.pivot(torso, Vector3(0, 0.75, 0.0), "Shell")
	Build.bevel(shell, Vector3(1.5, 0.3, 1.3), Vector3(0, 0.15, 0.05), BRONZE, 0.1, Vector3(-6, 0, 0), 0.75)
	Build.bevel(shell, Vector3(1.2, 0.26, 1.0), Vector3(0, 0.38, 0.12), BRONZE_LIGHT, 0.09, Vector3(-10, 0, 0), 0.7)
	Build.bevel(shell, Vector3(0.8, 0.22, 0.7), Vector3(0, 0.57, 0.2), BRONZE, 0.07, Vector3(-14, 0, 0), 0.6)
	Build.bevel(shell, Vector3(0.12, 0.5, 0.12), Vector3(0, 0.85, 0.25), GOLD, 0.03, Vector3(-18, 0, 0), 0.4)
	# 앞으로 내민 방패 갑각 (탄을 튕기는 면) + 붉은 십자 홈
	var shield := Build.pivot(torso, Vector3(0, 0.45, -0.5), "Shield")
	Build.bevel(shield, Vector3(1.5, 1.45, 0.22), Vector3(0, 0.1, 0), BRONZE, 0.1, Vector3(8, 0, 0), 0.82)
	Build.bevel(shield, Vector3(1.2, 1.15, 0.12), Vector3(0, 0.12, -0.12), BRONZE_LIGHT, 0.06, Vector3(8, 0, 0), 0.82)
	var cross_m := glow_mat(EYE, 1.6)
	var cv := MeshInstance3D.new()
	var cvm := BoxMesh.new()
	cvm.size = Vector3(0.08, 0.8, 0.04)
	cv.mesh = cvm
	cv.material_override = cross_m
	shield.add_child(cv)
	cv.position = Vector3(0, 0.15, -0.2)
	cv.rotation_degrees.x = 8.0
	var chm := BoxMesh.new()
	chm.size = Vector3(0.5, 0.08, 0.04)
	var ch := MeshInstance3D.new()
	ch.mesh = chm
	ch.material_override = cross_m
	shield.add_child(ch)
	ch.position = Vector3(0, 0.3, -0.21)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			Build.bevel(shield, Vector3(0.14, 0.14, 0.08), Vector3(sx * 0.55, 0.1 + sy * 0.5, -0.14), GOLD, 0.03)
	# 방패 위로 엿보는 두 눈
	var head := Build.pivot(torso, Vector3(0, 0.95, -0.38), "Head")
	Build.bevel(head, Vector3(0.36, 0.26, 0.3), Vector3.ZERO, IRON, 0.05, Vector3.ZERO, 0.8)
	var eye_m := glow_mat(EYE, 2.6)
	for s in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var em := BoxMesh.new()
		em.size = Vector3(0.08, 0.05, 0.04)
		e.mesh = em
		e.material_override = eye_m
		head.add_child(e)
		e.position = Vector3(s * 0.09, 0.03, -0.16)
	# 내려찍는 팔: 뼈 위팔 + 흑철 망치 주먹
	var arm := Build.pivot(torso, Vector3(0.62, 0.65, -0.1), "Arm")
	Build.bevel(arm, Vector3(0.26, 0.7, 0.26), Vector3(0, -0.3, 0), BONE_DARK, 0.05)
	var fore := Build.pivot(arm, Vector3(0, -0.62, 0), "Fore")
	Build.bevel(fore, Vector3(0.24, 0.6, 0.24), Vector3(0, -0.26, 0), IRON_LIGHT, 0.05)
	Build.bevel(fore, Vector3(0.48, 0.42, 0.48), Vector3(0, -0.66, 0), IRON, 0.08, Vector3.ZERO, 0.85)
	Build.bevel(fore, Vector3(0.18, 0.18, 0.18), Vector3(0, -0.92, 0), BONE, 0.04)
	return {"body": body, "core": sack, "core_mat": sack_m, "hips": hips, "torso": torso, "legs": legs, "arm": arm, "fore": fore,
		"shield": shield, "eye_mat": eye_m, "cross_mat": cross_m}


func _punch_scale() -> void:
	(j.torso as Node3D).scale = Vector3(1.0 + punch * 0.1, 1.0 - punch * 0.08, 1.0 + punch * 0.1)


# ── 등장: 위에서 떨어진다 ───────────────────────────────

func _update_entry(dt: float) -> void:
	drop_t += dt
	var body := j.body as Node3D
	var k := clampf(drop_t / DROP_T, 0.0, 1.0)
	body.position.y = lerpf(9.0, 0.0, k * k)
	shadow.scale = Vector3.ONE * lerpf(0.5, 1.3, k)
	face(to_player()[0], dt, 20.0)
	if k >= 1.0:
		landed = true
		punch = 1.0
		Main.inst.shake(0.4)
		FX.shockwave(global_position + Vector3(0, 0.1, 0), Color(1.0, 0.5, 0.5), 3.2, 0.3, 0.08)
		FX.land_dust(global_position)
		AbyssFX.splat(global_position, 2.2, 0.4)
		AbyssFX.light_flash(global_position + Vector3(0, 0.5, 0), AbyssFX.ICHOR_HOT, 3.0, 6.0, 0.3)
		Sfx.play("boom", 0.1, -6.0)


# ── 행동 ────────────────────────────────────────────────

func _ai(dt: float) -> void:
	var tp := to_player()
	var dir: Vector3 = tp[0]
	var dist: float = tp[1]
	var torso := j.torso as Node3D
	var arm := j.arm as Node3D
	var fore := j.fore as Node3D
	slam_cd -= dt
	charge_cd -= dt
	(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 0.8 + 0.5 * sin(t * 4.0)
	match st:
		S.WALK:
			face(dir, dt, TURN)
			var move := forward() * (1.0 if dist > 2.0 else 0.0) + separation(2.0) * 0.6
			if not active():
				move = Vector3.ZERO
			global_position += (move.limit_length(1.0) * SPEED + knock) * dt
			gait += dt * 5.5 * (1.0 if move.length() > 0.1 else 0.2)
			_walk_pose()
			torso.rotation.x = -0.25 + sin(gait * 2.0) * 0.03
			arm.rotation = Vector3(sin(gait) * 0.2, 0, 0.1)
			fore.rotation = Vector3(-0.3, 0, 0)
			if active():
				if dist < SLAM_R + 0.9 and slam_cd <= 0.0:
					_begin_slam()
				elif dist > 5.5 and dist < 13.0 and charge_cd <= 0.0:
					_begin_charge(dir)
		S.SLAM_TELE:
			var k := clampf(st_t / SLAM_TELE_T, 0.0, 1.0)
			# 팔을 머리 위로 크게 치켜든다
			arm.rotation = Vector3(lerpf(0.2, -2.6, smoothstep(0.0, 0.6, k)), 0, 0.15)
			fore.rotation = Vector3(lerpf(-0.3, -0.6, k), 0, 0)
			torso.rotation.x = lerpf(-0.25, 0.15, k)
			if is_instance_valid(warn):
				AbyssFX.set_warn(warn, k)
			if st_t >= SLAM_TELE_T:
				_slam_impact()
		S.SLAM:
			var k := clampf(st_t / 0.12, 0.0, 1.0)
			arm.rotation = Vector3(lerpf(-2.6, -0.9, k), 0, 0.15)
			torso.rotation.x = lerpf(0.15, -0.55, k)
			if st_t >= 0.12:
				go(S.RECOVER)
		S.CHARGE_TELE:
			var k := clampf(st_t / CHARGE_TELE_T, 0.0, 1.0)
			face(charge_dir, dt, 3.0)
			charge_dir = charge_dir.slerp(dir, dt * 1.5).normalized()
			torso.rotation.x = lerpf(-0.25, -0.65, k)
			gait += dt * 18.0 * k
			_walk_pose(0.3)
			if is_instance_valid(line):
				AbyssFX.set_beam(line, global_position + Vector3(0, 0.05, 0), charge_dir, CHARGE_SPEED * CHARGE_T, 2.0, 0.0, 0.5 + k * 0.5)
			if randf() < dt * 10.0:
				FX.sparks(global_position + Vector3(0, 0.1, 0), 3, [Color(0.5, 0.45, 0.45), Color(0.3, 0.25, 0.25)], 3.0, 0.3, -10.0, 0.06)
			if st_t >= CHARGE_TELE_T:
				set_tele(false)
				if is_instance_valid(line):
					line.queue_free()
				hit_player = false
				go(S.CHARGE)
				Sfx.play("launch", 0.1, -4.0)
		S.CHARGE:
			rotation.y = atan2(-charge_dir.x, -charge_dir.z)
			var before := global_position
			global_position += charge_dir * CHARGE_SPEED * dt
			global_position = Main.inst.push_out(global_position, radius)
			gait += dt * 22.0
			_walk_pose(1.2)
			torso.rotation.x = -0.6
			if randf() < 0.5:
				FX.sparks(global_position + Vector3(0, 0.1, 0), 2, [Color(1.0, 0.5, 0.4), AbyssFX.ICHOR_HOT], 4.0, 0.3, -10.0, 0.06)
			var p := Main.inst.player
			if not hit_player and p.alive and Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length() < radius + 0.45:
				hit_player = true
				p.take_hit(global_position)
			# 막히면(전장 끝) 멈춘다
			var moved := (global_position - before).length()
			if st_t >= CHARGE_T or moved < CHARGE_SPEED * dt * 0.4:
				Main.inst.shake(0.25)
				FX.land_dust(global_position)
				Sfx.play("clank", 0.1, -6.0)
				go(S.RECOVER)
		S.RECOVER:
			var k := clampf(st_t / 0.9, 0.0, 1.0)
			torso.rotation.x = lerpf(torso.rotation.x, -0.25, 1.0 - exp(-4.0 * dt))
			arm.rotation = arm.rotation.lerp(Vector3(0.2, 0, 0.1), 1.0 - exp(-4.0 * dt))
			global_position += knock * dt
			if k >= 1.0:
				slam_cd = randf_range(1.4, 2.4)
				go(S.WALK)
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	global_position = Main.inst.push_out(global_position, radius)


func _walk_pose(amp := 1.0) -> void:
	for l in j.legs:
		var s: float = l.side
		(l.hip as Node3D).rotation.x = sin(gait + (0.0 if s < 0 else PI)) * 0.4 * amp
		(l.knee as Node3D).rotation.x = maxf(0.0, -sin(gait + (0.0 if s < 0 else PI))) * 0.6 * amp
	(j.hips as Node3D).position.y = 0.95 + absf(sin(gait)) * 0.05 * amp


func _begin_slam() -> void:
	go(S.SLAM_TELE)
	set_tele(true)
	warn = AbyssFX.warn_disc(_slam_point(), SLAM_R)
	Sfx.play("twind", 0.1, -8.0)


func _slam_point() -> Vector3:
	return global_position + forward() * 1.1


func _slam_impact() -> void:
	set_tele(false)
	var c := _slam_point()
	if is_instance_valid(warn):
		warn.queue_free()
	go(S.SLAM)
	var p := Main.inst.player
	if p.alive and Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length() < SLAM_R:
		p.take_hit(c)
	Main.inst.shake(0.45)
	FX.shockwave(Vector3(c.x, 0.08, c.z), AbyssFX.ICHOR_HOT, SLAM_R * 2.0, 0.3, 0.1)
	FX.sparks(c + Vector3(0, 0.2, 0), 20, [Color(1.0, 0.8, 0.7), AbyssFX.ICHOR_HOT, Color(0.4, 0.35, 0.35)], 9.0, 0.5, -14.0, 0.1)
	AbyssFX.splat(c, 2.0, 0.3)
	AbyssFX.light_flash(c + Vector3(0, 0.6, 0), Color(1.0, 0.3, 0.25), 5.0, 7.0, 0.3)
	Sfx.play("boom", 0.1, -3.0)
	# 충격파를 따라 퍼지는 초승달 고리
	var off := randf() * TAU
	for i in 14:
		var a := off + TAU * i / 14.0
		var d := Vector3(sin(a), 0, cos(a))
		Main.inst.add_bullet(Shot.make(Vector3(c.x, 0.95, c.z) + d * 0.8, d, 5.4, AbyssFX.ICHOR_HOT, 0.65))


func _begin_charge(dir: Vector3) -> void:
	charge_cd = randf_range(5.0, 7.5)
	charge_dir = dir
	go(S.CHARGE_TELE)
	set_tele(true)
	line = AbyssFX.beam(AbyssFX.ICHOR_HOT)
	Sfx.play("rev", 0.1, -8.0)


## 정면 갑각: 앞에서 날아온 탄을 튕겨 낸다 (경직·회복 중에는 갑각이 내려가 맞는다)
func deflect_bullet(b: Bullet, pos: Vector3, fwd: Vector3) -> bool:
	if st == S.RECOVER or stagger_t > 0.0 or not landed:
		return false
	var incoming := -Vector3(fwd.x, 0, fwd.z).normalized()
	if incoming.angle_to(forward()) > SHIELD_HALF:
		return false
	var n := forward()
	var fl := Vector3(fwd.x, 0, fwd.z).normalized()
	var r := (fl - 2.0 * fl.dot(n) * n).normalized().rotated(Vector3.UP, randf_range(-0.4, 0.4))
	b.ricochet(pos - fl * 0.2, Vector3(r.x, randf_range(0.05, 0.25), r.z).normalized(), b.vel.length() * 0.7)
	FX.sparks(pos, 6, [Color.WHITE, Color("ffd890"), GOLD], 6.0, 0.25, -10.0, 0.05)
	FX.flash(pos, Color(1.0, 0.9, 0.7), 0.35, 0.05)
	punch = maxf(punch, 0.25)
	Sfx.play("tink", 0.2, -8.0)
	if randf() < 0.12:
		Main.inst.hud.popup("ARMOR", Color("e8c890"), global_position + Vector3(0, 2.6, 0))
	return true


func _on_stagger() -> void:
	super._on_stagger()
	if is_instance_valid(warn):
		warn.queue_free()
	if is_instance_valid(line):
		line.queue_free()
	if st != S.WALK:
		go(S.RECOVER)


## 가벼운 피격에는 경직되지 않는다 (무거운 기체)
func _hurt(dir: Vector3, dmg: int) -> void:
	if dmg >= 3:
		super._hurt(dir, dmg)


# ── 파열 ────────────────────────────────────────────────

func _begin_death() -> void:
	if is_instance_valid(warn):
		warn.queue_free()
	if is_instance_valid(line):
		line.queue_free()
	_rupture_warn = AbyssFX.warn_disc(global_position, RUPTURE_HURT_R, Color(1.0, 0.45, 0.2))
	Sfx.play("overload", 0.05, -2.0)
	FX.flash((j.core as Node3D).global_position, Color.WHITE, 1.0, 0.08)


func _death_tick(dt: float) -> void:
	var k := clampf(death_t / RUPTURE_T, 0.0, 1.0)
	var body := j.body as Node3D
	var torso := j.torso as Node3D
	torso.scale = Vector3.ONE * (1.0 + 0.35 * k * k)
	body.position = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.06 * k
	(j.core as Node3D).scale = Vector3.ONE * (1.0 + 1.4 * k)
	(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 1.0 + 10.0 * k
	_set_flash(k > 0.3 and fmod(death_t, 0.1) < 0.05)
	if is_instance_valid(_rupture_warn):
		AbyssFX.set_warn(_rupture_warn, k)
	if randf() < dt * 20.0:
		FX.sparks((j.core as Node3D).global_position, 3, [Color.WHITE, AbyssFX.ICHOR_HOT], 6.0, 0.25, -6.0, 0.06)
	if k >= 1.0:
		_rupture()


func _rupture() -> void:
	var c := global_position
	if is_instance_valid(_rupture_warn):
		_rupture_warn.queue_free()
	AbyssFX.rupture(c + Vector3(0, 1.0, 0), 2.2)
	Main.inst.shake(0.6)
	Main.inst.hitstop(0.06)
	Sfx.play("boom", 0.05, 2.0)
	var p := Main.inst.player
	if p.alive and Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length() < RUPTURE_HURT_R:
		p.take_hit(c)
	# 주변 적을 함께 터뜨린다 (연쇄 파열)
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed or en.is_boss:
			continue
		var d := en.global_position - c
		d.y = 0
		if d.length() < RUPTURE_R:
			en.take_hit(24, d.normalized(), en.global_position, "rupture")
	if Main.inst.has_method("on_rupture"):
		Main.inst.call("on_rupture", c)
	_set_flash(false)
	Debris.burst(j.body as Node3D, c + Vector3(0, 0.8, 0), 9.0, 7.0)
	dying = false
	queue_free()
