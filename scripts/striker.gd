class_name Striker
extends Enemy
## 고속 요격기. 플레이어처럼 빠르게 선회·대시하며 짧은 속사를 퍼붓고,
## 가끔 멈춰 서서 차지 레이저를 쏜다. 발사 전에는 바닥에 붉은 띠로 공격 범위를 예고한다.

enum S { MOVE, CHARGE, RECOVER, LUNGE_TELE, LUNGE }

const SPEED := 6.4
const ACCEL := 30.0
const DASH_SPEED := 15.5
const DASH_TIME := 0.2
const TURN := 14.0
const BURST_SHOTS := 4
const BURST_GAP := 0.07
const BURST_SPEED := 12.5
const BURST_TELE := 0.22
const BEAM_TRACK := 0.65        # 이 시간 동안 조준을 따라온다
const BEAM_LOCK := 0.4          # 이후 방향 고정 → 발사 (예고가 가장 강해지는 구간)
const BEAM_W := 0.9
const BEAM_RANGE := 22.0
const BEAM_HIT_WINDOW := 0.1
const RECOVER_TIME := 0.45
# 근접 돌진 베기 (패링 공격): 금빛 예고 → 뒤로 젖혀 힘을 모았다가 → 플레이어에게 고속 돌진
const LUNGE_TRIGGER := 8.0      # 이 거리 안이면 돌진을 노린다
const LUNGE_TELE := 0.6
const LUNGE_TRACK := 0.45       # 예고 중 이 시간까지 조준을 따라온다
const LUNGE_SPEED := 24.0
const LUNGE_MAX := 0.5
const LUNGE_REACH := 1.1
const STAGGER_TIME := 2.2

var state := S.MOVE
var vel := Vector3.ZERO
var dash_t := 0.0
var dash_dir := Vector3.ZERO
var dash_cd := 1.2
var ghost_t := 0.0
var shot_cd := 1.0
var beam_cd := 3.5
var charge_t := 0.0
var beam_dir := Vector3.FORWARD
var beam_len := 10.0
var beam_origin := Vector3.ZERO
var beam_hit_t := 0.0
var recover_t := 0.0
var warning: LaserWarning
var charge_snd: AudioStreamPlayer
var lunge_cd := 3.0
var lunge_t := 0.0
var lunge_dir := Vector3.FORWARD
var lunge_hit := false
var lunge_marker: MeshInstance3D
## 확인 모드: 거리와 무관하게 돌진만 한다
var lunge_only := false


func _ready() -> void:
	super()
	hp = 5
	radius = 0.6
	desired = 6.5
	shot_cd = randf_range(0.9, 1.4)
	beam_cd = randf_range(3.0, 4.5)
	dash_cd = randf_range(0.6, 1.4)
	lunge_cd = randf_range(2.5, 4.5)


func _build(v: Node3D) -> Dictionary:
	return Build.striker(v)


## 레이저 예고 중인지와 범위 (자동 플레이 회피용)
func beam_threat() -> Dictionary:
	if state != S.CHARGE:
		return {}
	return {"origin": beam_origin, "dir": beam_dir, "length": beam_len, "width": BEAM_W}


func _ai(dt: float) -> void:
	var body: Node3D = j.body
	var player := Main.inst.player
	var to_p := player.global_position - global_position
	to_p.y = 0
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)
	var active := player.alive and Main.inst.state == Main.State.PLAY

	match state:
		S.MOVE:
			_move(dt, dir, dist)
			if active:
				shot_cd -= dt
				beam_cd -= dt
				lunge_cd -= dt
				if lunge_cd <= 0.0 and dist < LUNGE_TRIGGER and dash_t <= 0.0 and burst_left == 0:
					_begin_lunge(dir)
				elif lunge_only:
					pass
				elif beam_cd <= 0.0 and dist < BEAM_RANGE - 2.0 and dash_t <= 0.0 and burst_left == 0:
					_begin_charge()
				elif shot_cd <= 0.0 and burst_left == 0:
					shot_cd = randf_range(1.0, 1.6)
					burst_left = BURST_SHOTS
					burst_timer = BURST_TELE
			_face(dir, dt, TURN)
		S.CHARGE:
			vel = vel.move_toward(Vector3.ZERO, 40.0 * dt)
			charge_t += dt
			if charge_t < BEAM_TRACK:
				beam_dir = beam_dir.slerp(dir, 1.0 - exp(-10.0 * dt)).normalized()
			_face(beam_dir, dt, 30.0)
			_update_beam_pose()
			var k := clampf(charge_t / (BEAM_TRACK + BEAM_LOCK), 0.0, 1.0)
			warning.set_progress(k)
			_charge_look(k)
			if not active:
				_cancel_charge()
			elif charge_t >= BEAM_TRACK + BEAM_LOCK:
				_fire_beam()
		S.LUNGE_TELE:
			_lunge_tele(dt, dir, dist, active)
		S.LUNGE:
			_lunge(dt, player)
		S.RECOVER:
			vel = vel.move_toward(Vector3.ZERO, 30.0 * dt)
			recover_t -= dt
			if beam_hit_t > 0.0:
				beam_hit_t -= dt
				_beam_hit_check()
			if recover_t <= 0.0:
				state = S.MOVE

	global_position += (vel + knock) * dt
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	global_position = Main.inst.push_out(global_position, radius)

	# 속사: 짧은 예고 뒤 빠른 탄 연사 (조금 앞을 노린다)
	if burst_left > 0 and state == S.MOVE:
		burst_timer -= dt
		var tele := clampf(1.0 - burst_timer / BURST_TELE, 0.0, 1.0) if burst_left == BURST_SHOTS else 1.0
		(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 0.8 + tele * 2.5
		if burst_timer <= 0.0 and active:
			burst_timer = BURST_GAP
			burst_left -= 1
			var lead := player.velocity * clampf(dist / BURST_SPEED, 0.0, 0.6) * 0.5
			var aim := (player.global_position + lead - global_position)
			aim.y = 0
			var fwd := -global_basis.z
			fwd.y = 0
			var off := fwd.normalized().signed_angle_to(aim.normalized(), Vector3.UP)
			_shoot([clampf(off, -0.35, 0.35) + randf_range(-0.04, 0.04)], BURST_SPEED)
		elif not active:
			burst_left = 0
	elif state == S.MOVE:
		(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 0.8

	# 기울기: 옆으로 움직이면 날개를 기울이고, 앞으로 가속하면 기수를 숙인다
	var local_v := global_basis.inverse() * vel
	wob_v += (-wob * 220.0 - wob_v * 11.0) * dt
	wob += wob_v * dt
	body.position.y = 1.0 + sin(t * 3.1) * 0.06
	body.rotation.z = lerpf(body.rotation.z, clampf(local_v.x * 0.07, -0.6, 0.6), 1.0 - exp(-10.0 * dt)) + wob.y * 0.3
	body.rotation.x = lerpf(body.rotation.x, clampf(local_v.z * 0.03, -0.25, 0.25), 1.0 - exp(-10.0 * dt)) + wob.x * 0.3
	_animate_jets(dt)


func _move(dt: float, dir: Vector3, dist: float) -> void:
	strafe_timer -= dt
	if strafe_timer <= 0.0:
		strafe_timer = randf_range(0.8, 1.8)
		strafe = -strafe
	dash_cd -= dt
	if dash_t > 0.0:
		dash_t -= dt
		vel = dash_dir * DASH_SPEED
		ghost_t -= dt
		if ghost_t <= 0.0:
			ghost_t = 0.035
			FX.afterimage(visual)
		if dash_t <= 0.0:
			vel = dash_dir * SPEED
		return
	var want := Vector3(-dir.z, 0, dir.x) * strafe
	if dist > desired + 1.0:
		want += dir * 1.2
	elif dist < desired - 1.0:
		want -= dir * 1.2
	for o in get_tree().get_nodes_in_group("enemies"):
		if o == self:
			continue
		var d: Vector3 = global_position - (o as Node3D).global_position
		d.y = 0
		var l := d.length()
		if l < 2.4 and l > 0.001:
			want += d / l * (2.4 - l)
	var speed := SPEED * (0.55 if burst_left > 0 else 1.0)
	vel = vel.move_toward(want.limit_length(1.0) * speed, ACCEL * dt)
	# 대시: 옆으로 순간 이탈 (가까우면 뒤로 빠지며)
	if dash_cd <= 0.0 and burst_left == 0:
		dash_cd = randf_range(1.1, 2.2)
		dash_t = DASH_TIME
		strafe = 1.0 if randf() < 0.5 else -1.0
		var back := -0.6 if dist < desired else (0.4 if dist > desired + 2.0 else 0.0)
		dash_dir = (Vector3(-dir.z, 0, dir.x) * strafe + dir * back).normalized()
		ghost_t = 0.0
		Sfx.play("dash", 0.12, -9.0)
		FX.shockwave(global_position, Color("ff7a8a"), 1.2, 0.2, 0.05)


func _face(dir: Vector3, dt: float, rate: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-rate * dt))


func _animate_jets(dt: float) -> void:
	var flame := 0.35
	if dash_t > 0.0 or state == S.LUNGE:
		flame = 1.6
	elif state == S.CHARGE:
		flame = 0.12
	else:
		flame = 0.3 + vel.length() / SPEED * 0.3
	for jet in j.jets:
		var n := jet as Node3D
		var y := lerpf(n.scale.y, flame * randf_range(0.85, 1.1), 1.0 - exp(-20.0 * dt))
		n.scale = Vector3(1, y, 1)


# ── 차지 레이저 ──────────────────────────────────────────

func _begin_charge() -> void:
	state = S.CHARGE
	charge_t = 0.0
	burst_left = 0
	var p := Main.inst.player.global_position - global_position
	p.y = 0
	beam_dir = p.normalized() if p.length() > 0.01 else -global_basis.z
	warning = LaserWarning.new()
	FX.root.add_child(warning)
	_update_beam_pose()
	warning.set_progress(0.0)
	charge_snd = Sfx.play("echarge", 0.03, -3.0)


func _update_beam_pose() -> void:
	var core: MeshInstance3D = j.core
	beam_origin = core.global_position
	beam_origin.y = 0.95
	var main := Main.inst
	beam_len = 0.0
	while beam_len < BEAM_RANGE:
		beam_len += 0.25
		if main.is_blocked(beam_origin + beam_dir * beam_len):
			break
	warning.set_pose(beam_origin, beam_dir, beam_len, BEAM_W)


## 충전 중 기체: 코어가 부풀며 달아오르고, 뒤로 젖혀 떨며 붉은 불꽃을 빨아들인다
func _charge_look(k: float) -> void:
	var core: MeshInstance3D = j.core
	var cm: StandardMaterial3D = j.core_mat
	core.scale = Vector3.ONE * (1.0 + k * 1.1 + sin(t * 50.0) * 0.08 * k)
	cm.emission_energy_multiplier = 1.0 + k * 6.0
	wob_v.x += 18.0 * k * get_physics_process_delta_time()
	fx_t -= get_physics_process_delta_time()
	if fx_t <= 0.0:
		fx_t = lerpf(0.09, 0.03, k)
		var off := Vector3(randf_range(-1, 1), randf_range(-0.4, 0.6), randf_range(-1, 1)).normalized() * randf_range(0.6, 1.1)
		FX.flash(core.global_position + off * (1.0 - k * 0.4), Pal.E_RED if randf() < 0.6 else Color("ffae10"), 0.14, 0.12)
	if k > 0.8 and fmod(t, 0.1) < 0.05:
		FX.flash(core.global_position, Color(1, 0.9, 0.9), 0.35 + k * 0.2, 0.04)


func _fire_beam() -> void:
	_update_beam_pose()
	_clear_warning()
	state = S.RECOVER
	recover_t = RECOVER_TIME
	beam_cd = randf_range(5.5, 8.0)
	shot_cd = randf_range(0.8, 1.3)
	beam_hit_t = BEAM_HIT_WINDOW
	FX.enemy_laser(beam_origin, beam_dir, beam_len, BEAM_W)
	Sfx.play("elaser", 0.04, -1.0)
	var core: MeshInstance3D = j.core
	core.scale = Vector3.ONE
	(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 0.8
	vel = -beam_dir * 9.0
	wob_v.x -= 16.0
	punch = 1.0
	Main.inst.shake(0.3)
	_beam_hit_check()


func _beam_hit_check() -> void:
	var p := Main.inst.player
	if not p.alive:
		return
	var rel := Vector3(p.global_position.x - beam_origin.x, 0, p.global_position.z - beam_origin.z)
	var along := clampf(rel.dot(beam_dir), 0.0, beam_len)
	if (rel - beam_dir * along).length() < BEAM_W * 0.5 + p.hit_radius:
		var hit_at := beam_origin + beam_dir * along
		if p.take_hit(Vector3(hit_at.x, p.global_position.y, hit_at.z)):
			beam_hit_t = 0.0


func _cancel_charge() -> void:
	_clear_warning()
	state = S.MOVE
	beam_cd = randf_range(2.0, 3.0)
	(j.core as MeshInstance3D).scale = Vector3.ONE


func _clear_warning() -> void:
	if is_instance_valid(warning):
		warning.queue_free()
	warning = null
	if charge_snd and Sfx.inst and charge_snd.playing and charge_snd.stream == Sfx.inst.streams.get("echarge"):
		charge_snd.stop()
	charge_snd = null


# ── 근접 돌진 베기 (패링 공격) ──────────────────────────

func _begin_lunge(dir: Vector3) -> void:
	state = S.LUNGE_TELE
	charge_t = 0.0
	lunge_dir = dir
	lunge_hit = false
	burst_left = 0
	lunge_marker = ParryFX.lunge_marker()
	_warn(_nose(), "melee")
	Parry.inst.register(self)
	Sfx.play("rev", 0.05, -4.0)


func _nose() -> Vector3:
	return global_position + Vector3(0, 1.0, 0) - global_basis.z * 0.8


## 예고: 조준을 따라오며 몸을 뒤로 젖혀 힘을 모은다. 바닥에 돌진 경로가 금빛으로 깔린다.
func _lunge_tele(dt: float, dir: Vector3, dist: float, active: bool) -> void:
	charge_t += dt
	var k := clampf(charge_t / LUNGE_TELE, 0.0, 1.0)
	if charge_t < LUNGE_TRACK:
		lunge_dir = lunge_dir.slerp(dir, 1.0 - exp(-12.0 * dt)).normalized()
	_face(lunge_dir, dt, 30.0)
	# 살짝 물러서며 웅크린다
	vel = vel.move_toward(-lunge_dir * 2.2 * (1.0 - k), 40.0 * dt)
	wob_v.x += 14.0 * k * dt
	var cm: StandardMaterial3D = j.core_mat
	cm.emission_energy_multiplier = 1.0 + k * 5.0
	ParryFX.set_lunge_marker(lunge_marker, global_position, lunge_dir, minf(dist + 1.5, LUNGE_SPEED * LUNGE_MAX), 1.1, k)
	fx_t -= dt
	if fx_t <= 0.0:
		fx_t = lerpf(0.08, 0.03, k)
		FX.flash(_nose() + Vector3(randf_range(-0.5, 0.5), randf_range(-0.2, 0.3), randf_range(-0.5, 0.5)), ParryFX.GOLD, 0.16, 0.1)
	if not active:
		_end_lunge()
		state = S.MOVE
	elif charge_t >= LUNGE_TELE:
		state = S.LUNGE
		lunge_t = 0.0
		vel = lunge_dir * LUNGE_SPEED
		ghost_t = 0.0
		Sfx.play("launch", 0.05, -2.0)
		FX.shockwave(global_position, ParryFX.GOLD, 2.2, 0.22, 0.06)
		punch = 0.8


func _lunge(dt: float, player: Player) -> void:
	lunge_t += dt
	vel = lunge_dir * LUNGE_SPEED
	ghost_t -= dt
	if ghost_t <= 0.0:
		ghost_t = 0.02
		FX.afterimage(visual, Color(1.0, 0.75, 0.25, 0.35))
	if lunge_marker:
		ParryFX.set_lunge_marker(lunge_marker, global_position, lunge_dir, 2.0, 1.1, 1.0)
	var to := player.global_position - global_position
	to.y = 0
	if not lunge_hit and player.alive and to.length() < LUNGE_REACH + player.hit_radius:
		lunge_hit = true
		# 날개 끝으로 베고 지나간다 (대시 무적이면 그냥 스쳐 간다)
		if player.take_hit(global_position):
			FX.flash(player.global_position + Vector3(0, 0.9, 0), Color(1, 0.6, 0.3), 1.0, 0.08)
	var ahead := global_position + lunge_dir * (radius + 0.3)
	if lunge_t >= LUNGE_MAX or Main.inst.is_blocked(ahead):
		_end_lunge()
		state = S.RECOVER
		recover_t = RECOVER_TIME
		vel = lunge_dir * 5.0


func _end_lunge() -> void:
	lunge_cd = randf_range(3.5, 5.5) if not lunge_only else randf_range(1.6, 2.2)
	shot_cd = maxf(shot_cd, 0.8)
	if is_instance_valid(lunge_marker):
		lunge_marker.queue_free()
	lunge_marker = null
	_end_warn()
	if Parry.inst:
		Parry.inst.unregister(self)


func parry_eta() -> float:
	var p := Main.inst.player
	if not p.alive or not alive or stagger_t > 0.0:
		return INF
	var to := p.global_position - global_position
	to.y = 0
	var gap := maxf(0.0, to.length() - LUNGE_REACH - p.hit_radius)
	match state:
		S.LUNGE_TELE:
			if gap > LUNGE_SPEED * LUNGE_MAX:
				return INF
			return (LUNGE_TELE - charge_t) + gap / LUNGE_SPEED
		S.LUNGE:
			if lunge_hit or to.dot(lunge_dir) < -0.3:
				return INF
			return gap / LUNGE_SPEED
	return INF


func parry_kind() -> String:
	return "melee"


func parry_point() -> Vector3:
	var p := Main.inst.player.global_position + Vector3(0, 0.95, 0)
	return p.lerp(_nose(), 0.5)


func parry_source() -> Node3D:
	return self


func parry_window_open() -> void:
	ParryFX.cue(_nose())


## 패링당함: 크게 튕겨 나가 경직된다
func parry_hit(p: Player) -> void:
	var d := global_position - p.global_position
	d.y = 0
	_end_lunge()
	state = S.RECOVER
	recover_t = 0.0
	vel = Vector3.ZERO
	stagger(d.normalized(), STAGGER_TIME)
	take_hit(1, d.normalized(), global_position, "parry")


func _on_stagger() -> void:
	_clear_warning()
	_end_lunge()
	state = S.MOVE
	vel = Vector3.ZERO
	dash_t = 0.0
	(j.core as MeshInstance3D).scale = Vector3.ONE


func die(dir := Vector3.ZERO, source := "bullet") -> void:
	if alive:
		_clear_warning()
		_end_lunge()
		state = S.MOVE
	super(dir, source)


func _exit_tree() -> void:
	_clear_warning()
	if is_instance_valid(lunge_marker):
		lunge_marker.queue_free()
	if Parry.inst:
		Parry.inst.unregister(self)
