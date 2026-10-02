class_name BugPill
extends BugEnemy
## 공벌레 (PILL BUG). 크림색 등딱지의 큰 쥐며느리.
##  · 평소: 다리 6쌍을 물결치듯 놀리며 느릿느릿 다가오고, 가끔 멈춰 더듬이로 바닥을 톡톡 두드리며 냄새를 맡는다
##  · 굴리기: 등을 한 번 뒤로 젖혔다(반동) 몸을 공처럼 말아 플레이어에게 굴러 박는다. 벽에 두 번까지 튕긴다.
##    공 상태 동안은 등딱지가 총알을 튕겨 낸다 (광선검·레이저·미사일은 들어간다)
##  · 멈추면 몸을 펴며 기지개 → 잠깐 어질어질 (이때가 노릴 틈)
## 애니메이션은 PillRig. 이 파일은 상태·이동·판정만.

enum P { CRAWL, SNIFF, CURL, ROLL, BRAKE, UNCURL, DAZED }

const MODEL := "res://assets/models/bug_pillbug.glb"
const CRAWL_SPEED := 1.5
const CURL_T := 0.62
const ROLL_SPEED := 12.5
const ROLL_MAX_T := 2.4
const HOMING := 1.1            ## 굴러가며 플레이어 쪽으로 꺾는 정도 (rad/s)
const BRAKE_T := 0.45
const UNCURL_T := 0.42
const DAZED_T := 0.8
const ROLL_RANGE := 11.0
const CONTACT_SPEED := 5.0

var rig: PillRig
var roller: Node3D
var state := P.CRAWL
var st_t := 0.0
var st_len := 2.0
var vel := Vector3.ZERO
var roll_dir := Vector3.FORWARD
var bounces := 2
var roll_cd := 1.5
var cur_speed := 0.0
var turn_rate := 0.0
var weave := 0.0
var _hit_cd := 0.0
var _dust_t := 0.0
var uncurl_from := 1.0


func _model_path() -> String:
	return MODEL


func _attach_model(p: Node3D, m: Node3D) -> void:
	roller = Node3D.new()
	roller.name = "roller"
	p.add_child(roller)
	roller.add_child(m)


func _ready() -> void:
	super._ready()
	hp = 6
	radius = 0.72
	hp_bar_y = 1.45
	hp_bar_w = 1.1
	slice_size = Vector3(1.0, 0.6, 1.6)
	slice_color = Color("ece2cc")
	weave = randf() * TAU
	roll_cd = randf_range(1.2, 2.5)
	st_len = randf_range(1.5, 3.0)


func _make_rig() -> void:
	rig = PillRig.new().setup(model, roller)


func _set_emerge(k: float) -> void:
	if rig:
		rig.emerge_k = k


func _goo_height() -> float:
	return 0.4


func _flip_height() -> float:
	return 0.66


func _sever_node() -> Node3D:
	return rig.n.seg_2 as Node3D


## 공 상태: 등딱지가 총알을 튕겨 낸다
func armored() -> bool:
	return rig != null and rig.curl > 0.65 and alive


func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	if armored() and source == "bullet":
		var c := (j.body as Node3D).global_position + Vector3(0, rig.lift_at(rig.curl) + 0.3, 0)
		var at := c.lerp(pos, 0.7) if pos != Vector3.ZERO else c
		FX.sparks(at, 5, [Color.WHITE, Color("ffe8a0")], 6.0, 0.18, -12.0, 0.05)
		knock += Vector3(dir.x, 0, dir.z) * 0.6
		punch = maxf(punch, 0.25)
		if _hit_cd <= 0.0:
			_hit_cd = 0.08
			Sfx.play("clank", 0.2, -14.0)
		return
	super.take_hit(dmg, dir, pos, source)


func _rig_update(dt: float) -> void:
	rig.speed = cur_speed if state == P.CRAWL else 0.0
	rig.turn = turn_rate
	rig.update(dt)


func _rig_dead(dt: float, k: float) -> void:
	rig.dead_k = k
	rig.speed = 0.0
	rig.sniff = 0.0
	# 죽은 공벌레: 펼쳐졌다가 다리를 버둥대며 서서히 반쯤 말린다
	rig.curl = lerpf(rig.curl, clampf((death_t - 0.5) / 0.8, 0.0, 0.45), 1.0 - exp(-6.0 * dt))
	rig.roll = lerp_angle(rig.roll, 0.0, 1.0 - exp(-10.0 * dt))
	rig.stretch = 0.0
	rig.update(dt)


func _ai(dt: float) -> void:
	var player := Main.inst.player
	var to_p := _to_player()
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)
	var cm: StandardMaterial3D = j.core_mat
	st_t += dt
	roll_cd -= dt
	_hit_cd -= dt
	var active := player.alive and not player.hidden and Main.inst.state == Main.State.PLAY
	match state:
		P.CRAWL:
			# 느릿느릿, 좌우로 살짝 휘청이며 다가온다
			weave += dt * 1.3
			var goal := dir.rotated(Vector3.UP, sin(weave) * 0.45)
			if dist < 2.2:
				goal = Vector3(-dir.z, 0, dir.x)
			turn_rate = _face(goal, dt, 3.0)
			cur_speed = move_toward(cur_speed, CRAWL_SPEED, dt * 3.0)
			var fwd := -global_basis.z
			global_position += Vector3(fwd.x, 0, fwd.z).normalized() * cur_speed * dt
			if active and roll_cd <= 0.0 and dist < ROLL_RANGE and dist > 2.0:
				_go(P.CURL, CURL_T)
				Sfx.play("bug_chitter", 0.1, -6.0)
				Sfx.play("charge", 0.1, -14.0)
			elif st_t >= st_len:
				_go(P.SNIFF, randf_range(0.6, 1.1))
				if near_player(9.0):
					Sfx.play("bug_click", 0.3, -14.0)
		P.SNIFF:
			cur_speed = move_toward(cur_speed, 0.0, dt * 6.0)
			turn_rate = _face(dir, dt, 2.0)
			rig.sniff = minf(1.0, rig.sniff + dt * 5.0)
			if st_t >= st_len:
				_go(P.CRAWL, randf_range(1.6, 3.2))
		P.CURL:
			cur_speed = 0.0
			turn_rate = _face(dir, dt, 7.0)
			var k := st_t / CURL_T
			# 반동: 먼저 등을 뒤로 젖혀 머리를 들었다가(0~35%) 단숨에 말아 버린다 · 다 말리면 부르르 떤다
			rig.stretch = -sin(clampf(k / 0.35, 0.0, 1.0) * PI) * 0.9
			rig.curl = _ease_in(clampf((k - 0.3) / 0.55, 0.0, 1.0))
			cm.emission_energy_multiplier = 3.0 * k
			if k > 0.85:
				(j.body as Node3D).position.x = sin(st_t * 80.0) * 0.03
			if st_t >= CURL_T:
				(j.body as Node3D).position.x = 0.0
				roll_dir = dir
				vel = roll_dir * ROLL_SPEED
				bounces = 2
				rig.curl = 1.0
				rig.stretch = 0.0
				cm.emission_energy_multiplier = 0.0
				_go(P.ROLL, ROLL_MAX_T)
				FX.land_dust(global_position)
				Sfx.play("roll", 0.1, -4.0)
		P.ROLL:
			# 살짝 휘어 따라간다 (세게 꺾지는 않는다)
			if active:
				var cur := vel.normalized()
				var ang := cur.signed_angle_to(dir, Vector3.UP)
				vel = cur.rotated(Vector3.UP, clampf(ang, -HOMING * dt, HOMING * dt)) * vel.length()
			_move_ball(dt)
			_contact(player)
			_face(vel, dt, 20.0)
			rig.roll -= vel.length() / PillRig.BALL_R * dt
			_dust_t -= dt
			if _dust_t <= 0.0:
				_dust_t = 0.05
				FX.puffs(global_position + Vector3(0, 0.08, 0), 1, DIRT, 0.25, 0.3, 0.45)
			if st_t >= st_len or bounces < 0:
				_go(P.BRAKE, BRAKE_T)
		P.BRAKE:
			vel = vel.move_toward(Vector3.ZERO, ROLL_SPEED / BRAKE_T * dt)
			_move_ball(dt)
			_contact(player)
			rig.roll -= vel.length() / PillRig.BALL_R * dt
			# 멈추며 굴림을 바로 세운다 (가까운 쪽 한 바퀴로)
			var k := st_t / BRAKE_T
			if k > 0.5:
				rig.roll = lerp_angle(rig.roll, 0.0, 1.0 - exp(-14.0 * dt))
			if st_t >= BRAKE_T:
				vel = Vector3.ZERO
				rig.roll = 0.0
				uncurl_from = 1.0
				_go(P.UNCURL, UNCURL_T)
				Sfx.play("land", 0.15, -6.0)
		P.UNCURL:
			var k := st_t / UNCURL_T
			# 툭 펴지며 등을 쭉 젖혔다(기지개) 돌아온다
			rig.curl = uncurl_from * (1.0 - _ease_out(k))
			rig.stretch = -sin(clampf(k, 0.0, 1.0) * PI) * 0.7
			turn_rate = _face(dir, dt, 4.0)
			if st_t >= UNCURL_T:
				rig.curl = 0.0
				rig.stretch = 0.0
				rig.alarm = 1.0
				_go(P.DAZED, DAZED_T)
		P.DAZED:
			cur_speed = 0.0
			(j.body as Node3D).rotation.z = sin(st_t * 9.0) * 0.06 * (1.0 - st_t / DAZED_T)
			if st_t >= DAZED_T:
				(j.body as Node3D).rotation.z = 0.0
				roll_cd = randf_range(2.2, 3.6)
				_go(P.CRAWL, randf_range(1.0, 2.0))
	if state != P.SNIFF:
		rig.sniff = maxf(0.0, rig.sniff - dt * 3.0)
	if state != P.ROLL and state != P.BRAKE:
		global_position += (_separation(1.9) * 2.0 + knock) * dt
		knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
		global_position = Main.inst.push_out(global_position, radius)


## 공 굴리기 이동: 잘게 나눠 밀어내기 · 벽에 부딪히면 반사 (튕길 수 있는 횟수를 깎는다)
func _move_ball(dt: float) -> void:
	var total := (vel + knock) * dt
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	var steps := maxi(1, int(ceil(total.length() / 0.12)))
	for i in steps:
		global_position += total / steps
		var p := Main.inst.push_out(global_position, PillRig.BALL_R)
		var push := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
		global_position = p
		if push.length() > 0.0005:
			var nrm := push.normalized()
			if vel.dot(nrm) < -0.5:
				vel = (vel - 2.0 * vel.dot(nrm) * nrm) * 0.85
				bounces -= 1
				punch = 0.8
				var at := global_position - nrm * PillRig.BALL_R + Vector3(0, 0.5, 0)
				FX.sparks(at, 10, [Color.WHITE, Color("ffe8a0"), Color("c8b898")], 7.0, 0.3, -12.0, 0.06)
				FX.shockwave(at, Color("e8dcc0"), 1.6, 0.18, 0.05)
				Sfx.play("clank", 0.12, -6.0)
				if global_position.distance_to(Main.inst.player.global_position) < 11.0:
					Main.inst.shake(0.12)
				break


## 몸통 박치기: 빠르게 구르는 공에 닿으면 피해 + 튕겨 나감
func _contact(player: Player) -> void:
	if vel.length() < CONTACT_SPEED or not player.alive:
		return
	var rel := player.global_position - global_position
	rel.y = 0
	if rel.length() > PillRig.BALL_R + player.hit_radius + 0.1:
		return
	var nrm := rel.normalized() if rel.length() > 0.01 else vel.normalized()
	if not player.take_hit(global_position):
		return
	player.velocity += nrm * 9.0
	if vel.dot(nrm) > 0.0:
		vel = (vel - 2.0 * vel.dot(nrm) * nrm) * 0.6
	punch = 1.0
	FX.sparks(global_position + nrm * PillRig.BALL_R + Vector3(0, 0.6, 0), 14, [Color.WHITE, Color("ffd060")], 8.0, 0.3, -12.0, 0.06)
	Sfx.play("clank", 0.05, 0.0)
	Main.inst.shake(0.25)


func _can_hurt() -> bool:
	return state != P.ROLL and state != P.BRAKE


func _go(s: int, dur: float) -> void:
	state = s
	st_t = 0.0
	st_len = dur


func _on_stagger() -> void:
	(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 0.0
	(j.body as Node3D).position.x = 0.0
	if rig:
		rig.alarm = 1.0
		rig.stretch = 0.0
	if state == P.CURL or state == P.ROLL or state == P.BRAKE:
		vel = Vector3.ZERO
		rig.roll = 0.0
		uncurl_from = rig.curl
		_go(P.UNCURL, UNCURL_T)
	elif state != P.UNCURL:
		_go(P.CRAWL, randf_range(0.8, 1.6))
	cur_speed = 0.0


static func _ease_in(x: float) -> float:
	return x * x * x


static func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)
