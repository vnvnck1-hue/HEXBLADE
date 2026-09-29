class_name Player
extends CharacterBody3D
## 보라색 로봇.
## WASD 이동 · 마우스 조준 · 좌클릭 연사 · 우클릭 유지→놓기 충전 레이저
## Space 드릴 회피 (끝나는 순간 다시 누르면 2단 대시) · Shift 백팩 부스터 비행 · E 검
## R 유지: 슬로우모션 락온 → 놓으면 미사일

const BeamImpact := preload("res://scripts/beam_impact.gd")
const SPEED := 6.8
const ACCEL := 70.0
const BOOST_SPEED := 13.5
const BOOST_ACCEL := 40.0
const BOOST_DRAIN := 0.5        # 초당 게이지 소모 (가득 → 2초 비행)
const BOOST_REGEN := 0.42
const BOOST_DELAY := 0.4        # 비행 종료 후 회복 시작까지
const BOOST_RESUME := 0.3       # 과열 시 이만큼 차야 재사용
const HOVER := 0.75
const DASH_SPEED := 17.0
const DASH_TIME := 0.3
const DASH_CD := 0.8
const FIRE_INTERVAL := 0.085
const BULLET_SPEED := 60.0
const SLASH_CD := 0.5
const SLASH_RANGE := 2.9
const CHARGE_TIME := 1.0
const CHARGE_MIN := 0.25
const IMPACT_MIN_CHARGE := 0.67  # 이 이상 충전(3단)해 쏘면 임팩트 프레임
const LASER_CD := 0.45
const LASER_RANGE := 24.0
const MAX_HP := 5
# 최대 충전 지속 레이저 (벨코즈 궁 스타일)
const MEGA_TIME := 2.0
const MEGA_TURN_MAX := 1.4      # 최대 회전 속도 (rad/s, 약 80°/s) → 무겁게 천천히 돈다
const MEGA_TURN_GAIN := 2.5
const MEGA_TICK := 0.1
const MEGA_DMG := 2
const MEGA_WIDTH := 1.2
const MEGA_MOVE := 0.3
# 검 돌진
const LUNGE_RANGE := 8.0         # 이 거리 안의 적에게 파고든다
const LUNGE_SPEED := 62.0        # 돌진 속도 (m/s)
const LUNGE_MIN_TIME := 0.035
const LUNGE_STOP := 1.45
const LUNGE_FREE := 2.8          # 대상이 없을 때 앞으로 내딛는 거리
# 궁극기: 미사일 난사
const ULT_TIME := 14.0           # 자연 충전 시간
const ULT_PER_KILL := 0.1
const ULT_MISSILES := 18
const CHARGE_STAGES := [0.34, 0.67, 1.0]
# 2단 대시: 대시 마지막 CHAIN_WINDOW 초 ~ 끝난 뒤 CHAIN_GRACE 초 안에 다시 누르면 성공
const CHAIN_WINDOW := 0.1
const CHAIN_GRACE := 0.06
# 관통 일격 (2단 대시 성공 후 첫 검)
const PHANTOM_RANGE := 9.0
const PHANTOM_TIME := 0.05       # 3프레임
const PHANTOM_BEHIND := 2.2      # 적 뒤로 빠져나가는 거리
const PHANTOM_WIDTH := 0.9
# 검 휘두르기 4종: 가로 베기 / 역베기 / 내려찍기 / 회전 베기
const SLASH_TIMES := [0.16, 0.16, 0.2, 0.24]
const SLASH_SWINGS := [0.05, 0.05, 0.06, 0.1]
# 궁극기 락온
const ULT_SLOW := 0.06
const ULT_AIM_MAX := 2.0         # 실제 시간 (초)
const LOCK_PX := 54.0            # 화면 800px 높이 기준 락온 반경
const LOCK_MAX := 10

## 추격 보스전: 부스터 무한 비행 · 전장 안에서 좌우로 움직이는 속도
var infinite_boost := false
const CHASE_SPEED := 9.5

var hp := MAX_HP
var alive := true
var hit_radius := 0.38
var aim_dir := Vector3.FORWARD
var aim_point := Vector3.ZERO
var move_dir := Vector3.ZERO
var bot := false
var j: Dictionary

# 이동 상태
var dash_t := 0.0
var dash_cd := 0.0
var dash_dir := Vector3.ZERO
var dash_roll_sign := 1.0
var ghost_t := 0.0
var boost := 1.0
var boosting := false
var overheated := false
var boost_idle := 0.0
var hover := 0.0
var hover_v := 0.0
var puff_t := 0.0

# 전투 상태
var fire_cd := 0.0
var slash_cd := 0.0
var slash_anim := 0.0
var charge := 0.0
var charging := false
var laser_cd := 0.0
var laser_recoil := 0.0
var invuln := 0.0
var hurt_t := 0.0
var stun_t := 0.0                 # 경직: 이동·사격·검·대시·충전이 막힌다
var recoil := 0.0
var mega_t := 0.0
var mega_yaw := 0.0
var mega_tick := 0.0
var mega_node: MegaBeam
var mega_len := 0.0
var mega_impact: BeamImpact
var lunge_t := 0.0
var lunge_vel := Vector3.ZERO
var lunge_dir := Vector3.ZERO
var ult := 0.6
var ult_queue := 0
var ult_t := 0.0
var charge_stage := 0
var chain_ok := true
var chain_grace := 0.0
var rainbow := false             # 지금 대시가 2단 대시인가
var dash_skip_in := false
var phantom_ready := false
var lunge_phantom := false
var phantom_from := Vector3.ZERO
var slash_style := 0
var slash_total: float = SLASH_TIMES[0]
var slash_swing: float = SLASH_SWINGS[0]
var ult_aiming := false
var ult_aim_start := 0
var ult_ptr := Vector2.ZERO
var locks: Array = []
var lock_times := {}
var ult_targets: Array = []
var lock_clear_t := 0.0

# 연출 상태
var visual: Node3D        # 드릴 회전 기준점 (몸 중심)
var lean: Node3D          # 스프링 기울기
var body: Node3D          # 로봇 파츠 루트
var tilt := Vector3.ZERO
var tilt_v := Vector3.ZERO
var squash := 0.0
var squash_v := 0.0
var walk := 0.0
var drill := 0.0
var dodge_ring: MeshInstance3D
var ready_ping := 0.0
var charge_fx: ChargeFX
var blade_fx: BladeFX
var charge_snd: AudioStreamPlayer
var boost_snd: AudioStreamPlayer
var celebrate_t := -1.0

const PIVOT_Y := 0.85


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.4
	cs.shape = cap
	cs.position.y = 0.7
	add_child(cs)
	visual = Node3D.new()
	visual.position.y = PIVOT_Y
	add_child(visual)
	lean = Node3D.new()
	visual.add_child(lean)
	body = Node3D.new()
	body.position.y = -PIVOT_Y
	lean.add_child(body)
	j = Build.robot(body)
	FX.blob_shadow(self, 2.6, 0.75)
	var tor := TorusMesh.new()
	tor.inner_radius = 0.82
	tor.outer_radius = 0.87
	tor.rings = 40
	tor.ring_segments = 4
	dodge_ring = Pal.flat_mesh(tor, Pal.CYAN, 1.0)
	dodge_ring.scale = Vector3(1, 0.05, 1)
	dodge_ring.position.y = 0.03
	add_child(dodge_ring)
	charge_fx = ChargeFX.new()
	(j.muzzle as Node3D).add_child(charge_fx)
	charge_fx.position = Vector3(0, 0, -0.25)
	blade_fx = BladeFX.new()
	blade_fx.player = self
	(j.blade as Node3D).add_child(blade_fx)
	boost_snd = AudioStreamPlayer.new()
	add_child(boost_snd)
	boost_snd.volume_db = -80.0


func _physics_process(dt: float) -> void:
	if not alive:
		return
	var main := Main.inst
	var playing := main.state == Main.State.PLAY

	# ── 입력 ──
	var fire := false
	var slash_pressed := false
	var dash_pressed := false
	var charge_held := false
	var boost_held := false
	if bot:
		var b := main.bot_input(self)
		move_dir = b.move
		aim_point = b.aim
		fire = b.fire
		slash_pressed = b.slash
		dash_pressed = b.dash
		charge_held = b.get("charge", false)
		boost_held = b.get("boost", false)
		if b.get("ult", false) and ult >= 1.0 and playing and not ult_aiming and ult_queue == 0 and mega_t <= 0.0:
			_begin_ult_aim()
	else:
		var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		move_dir = Vector3(v.x, 0, v.y)
		aim_point = main.mouse_ground(0.95)
		# 좌클릭 검 · 우클릭 사격 · 좌우 동시 유지 충전
		var lmb := Input.is_action_pressed("slash_mouse")
		var rmb := Input.is_action_pressed("fire_mouse")
		charge_held = lmb and rmb
		fire = rmb and not lmb
		slash_pressed = Input.is_action_just_pressed("slash") or (Input.is_action_just_pressed("slash_mouse") and not rmb)
		dash_pressed = Input.is_action_just_pressed("dash")
		boost_held = Input.is_action_pressed("boost")
		if Input.is_action_just_pressed("ult") and ult >= 1.0 and playing and not ult_aiming and ult_queue == 0 and mega_t <= 0.0:
			_begin_ult_aim()
	if mega_t > 0.0:
		# 지속 레이저 중에는 대시만 받는다 (대시로 레이저를 끊는다)
		fire = false
		slash_pressed = false
		charge_held = false
		boost_held = false
	if ult_aiming:
		fire = false
		slash_pressed = false
		dash_pressed = false
		charge_held = false
	if not playing:
		fire = false
		slash_pressed = false
		dash_pressed = false
		charge_held = false
		boost_held = false
		move_dir = Vector3.ZERO
	stun_t = maxf(0.0, stun_t - dt)
	if stun_t > 0.0:
		fire = false
		slash_pressed = false
		dash_pressed = false
		charge_held = false
		charge = 0.0            # 모으던 충전은 레이저 없이 흩어진다
		move_dir = Vector3.ZERO
		if mega_t > 0.0:
			_end_mega()
		if randf() < 0.35:
			FX.sparks(global_position + Vector3(randf_range(-0.3, 0.3), randf_range(0.4, 1.4), randf_range(-0.3, 0.3)), 2, [Color.WHITE, Color("8ad8ff")], 3.0, 0.15, 0.0, 0.05)
			tilt_v += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 3.0

	var to_aim := aim_point - global_position
	to_aim.y = 0
	if to_aim.length() > 0.3 and lunge_t <= 0.0:
		aim_dir = to_aim.normalized()

	# ── 부스터 게이지 ──
	var want_boost := boost_held and not overheated and dash_t <= 0.0
	if infinite_boost:
		# 추격 보스전: 부스터가 꺼지지 않고 게이지도 줄지 않는다
		want_boost = true
		boost = 1.0
		overheated = false
	if want_boost and boost > 0.0:
		if not boosting:
			_boost_start()
		boost = maxf(0.0, boost - BOOST_DRAIN * dt)
		boost_idle = 0.0
		if boost <= 0.0:
			overheated = true
			Sfx.play("hurt", 0.0, -10.0)
	else:
		if boosting:
			_boost_end()
		boost_idle += dt
		if boost_idle > BOOST_DELAY:
			boost = minf(1.0, boost + BOOST_REGEN * dt)
		if overheated and boost >= BOOST_RESUME:
			overheated = false
	boosting = want_boost and boost > 0.0

	# ── 회피 (드릴 회전) ──
	dash_cd = max(0.0, dash_cd - dt)
	chain_grace = maxf(0.0, chain_grace - dt)
	# 패링: 패링 공격이 닿기 직전이면 대시 대신 반격이 나간다 (대시 쿨다운과 무관)
	if dash_pressed and lunge_t <= 0.0 and Parry.inst and Parry.inst.try_parry(self):
		dash_pressed = false
	if dash_pressed and lunge_t <= 0.0:
		if mega_t > 0.0:
			# 레이저 끊기
			_end_mega()
			FX.flash((j.muzzle as Node3D).global_position, Pal.CYAN, 0.8, 0.08)
			_dash_start(false)
		elif dash_t > 0.0:
			if not rainbow and chain_ok and dash_t <= CHAIN_WINDOW:
				_dash_start(true)
			else:
				chain_ok = false        # 너무 일찍 누르면 이번 대시는 연결 불가
		elif chain_grace > 0.0:
			_dash_start(true)
		elif dash_cd <= 0.0:
			_dash_start(false)
	if lunge_t > 0.0:
		lunge_t -= dt
		velocity = lunge_vel
		ghost_t -= dt
		if ghost_t <= 0.0:
			ghost_t = 0.0 if lunge_phantom else 0.012
			FX.afterimage(visual, _ghost_color(0.5) if lunge_phantom else FX.GHOST, 0.0 if lunge_phantom else 0.32)
		if lunge_t <= 0.0:
			if lunge_phantom:
				velocity = lunge_dir * 3.0
				_phantom_hit()
			else:
				velocity = lunge_dir * 2.5
				_slash_hit()
	elif dash_t > 0.0:
		dash_t -= dt
		var k := 1.0 - dash_t / DASH_TIME
		# 초반에 가장 빠르고 끝에서 감속
		velocity = dash_dir * DASH_SPEED * lerpf(1.25, 0.55, k)
		ghost_t -= dt
		if ghost_t <= 0.0:
			ghost_t = 0.04 if rainbow else 0.06
			FX.afterimage(visual, _ghost_color(0.34) if rainbow else FX.GHOST)
			var ay := atan2(-aim_dir.x, -aim_dir.z)
			var vc := Pal.CYAN if randf() < 0.5 else Color("b0a0ff")
			if rainbow:
				vc = _rainbow(0.45)
			FX.vortex(visual.global_position, Basis(Vector3.UP, ay) * Basis(Vector3.RIGHT, -PI * 0.5), vc)
		if dash_t <= 0.0:
			_dash_end()
	else:
		var target_speed := BOOST_SPEED if boosting else SPEED
		if infinite_boost:
			target_speed = CHASE_SPEED
		if charging:
			target_speed *= 0.55
		if mega_t > 0.0:
			target_speed *= MEGA_MOVE
		var dir := move_dir.limit_length(1.0)
		if boosting and dir.length() < 0.1 and not infinite_boost:
			dir = aim_dir
		var accel := BOOST_ACCEL if boosting and not infinite_boost else ACCEL
		velocity = velocity.move_toward(dir * target_speed, accel * dt)
	velocity.y = 0
	move_and_slide()
	global_position.y = 0

	if mega_t > 0.0:
		_update_mega(dt)

	# ── 사격 ──
	fire_cd -= dt
	laser_cd -= dt
	if fire and fire_cd <= 0.0 and slash_anim <= 0.0 and not charging and laser_recoil <= 0.0:
		fire_cd = FIRE_INTERVAL
		_fire()

	# ── 충전 레이저 ──
	if charge_held and laser_cd <= 0.0:
		if not charging:
			charging = true
			charge = 0.0
			charge_stage = 0
			charge_fx.begin()
			charge_snd = Sfx.play("charge", 0.0, -6.0)
		charge = minf(1.0, charge + dt / CHARGE_TIME)
		# 단계가 오를 때마다 색이 바뀌며 번쩍
		var st := 0
		for th in CHARGE_STAGES:
			if charge >= th:
				st += 1
		if st > charge_stage:
			charge_stage = st
			charge_fx.stage_up(st)
			if st >= 3:
				Sfx.play("charged", 0.0, -1.0)
				Main.inst.shake(0.15)
				Main.inst.camera.fov_punch(2.0)
			else:
				var ping := Sfx.play("ready", 0.0, -4.0)
				if ping:
					ping.pitch_scale = 0.8 + st * 0.35
		charge_fx.set_charge(charge, dt)
	elif charging:
		charging = false
		charge_fx.end()
		if charge_snd and charge_snd.playing:
			charge_snd.stop()
		if charge >= 1.0:
			_start_mega()
		elif charge >= CHARGE_MIN:
			_fire_laser(charge)
		else:
			FX.fizzle((j.muzzle as Node3D).global_position)
		charge = 0.0

	# ── 검 ──
	slash_cd -= dt
	if slash_pressed and slash_cd <= 0.0 and not charging and lunge_t <= 0.0:
		slash_cd = SLASH_CD
		_slash()

	invuln = max(0.0, invuln - dt)
	hurt_t = max(0.0, hurt_t - dt)
	_update_ult(dt)
	_animate(dt)


## 락온 조준은 실제 시간 기준으로 매 화면 프레임 갱신한다 (슬로우모션 중 물리 틱과 무관하게 부드럽게)
func _process(dt: float) -> void:
	if ult_aiming:
		_update_ult_aim()
	elif lock_clear_t > 0.0 and ult_queue == 0:
		lock_clear_t -= dt
		if lock_clear_t <= 0.0:
			_clear_locks()


func _rainbow(sat := 0.45, off := 0.0) -> Color:
	return Color.from_hsv(fmod(Time.get_ticks_msec() * 0.0025 + off + randf() * 0.15, 1.0), sat, 1.0)


func _ghost_color(a: float) -> Color:
	var c := _rainbow(0.5)
	c.a = a
	return c


# ── 행동 ────────────────────────────────────────────────

func _boost_start() -> void:
	FX.shockwave(global_position, Pal.CYAN, 2.2, 0.3)
	FX.sparks(global_position + Vector3(0, 0.1, 0), 10, [Color("8a8ac8"), Pal.CYAN], 5.0, 0.35, -3.0, 0.08)
	Sfx.play("dash", 0.05, -4.0)
	hover_v += 5.0
	squash_v -= 6.0
	if not Sfx.inst.muted:
		boost_snd.stream = Sfx.inst.streams.boost
		boost_snd.play()


func _boost_end() -> void:
	# 착지: 살짝 눌리며 먼지
	squash_v += 8.0
	FX.shockwave(global_position, Color("7a7ac0"), 1.6, 0.25, 0.05)
	Sfx.play("land", 0.1, -8.0)


func _dash_start(chained := false) -> void:
	dash_skip_in = chained and dash_t > 0.0
	rainbow = chained
	chain_ok = true
	chain_grace = 0.0
	dash_dir = move_dir.normalized() if move_dir.length() > 0.1 else aim_dir
	dash_t = DASH_TIME
	dash_cd = DASH_CD
	invuln = max(invuln, DASH_TIME + 0.06)
	ghost_t = 0.0
	# 조준 방향을 기준으로 옆으로 피하면 그쪽으로 구른다
	var side := aim_dir.cross(dash_dir).y
	dash_roll_sign = -1.0 if side > 0.0 else 1.0
	drill = 0.0
	FX.shockwave(global_position, Pal.CYAN, 2.4, 0.28)
	FX.sparks(global_position + Vector3(0, 0.15, 0), 12, [Color("9a9ad8"), Pal.CYAN], 6.0, 0.3, -5.0, 0.08)
	Sfx.play("roll", 0.08)
	Sfx.play("dash", 0.05, -6.0)
	Main.inst.kick(dash_dir * 0.8)
	Main.inst.camera.fov_punch(7.0)
	if chained:
		# 2단 대시 성공: 무지개빛 충격파 + 다음 검은 관통 일격
		phantom_ready = true
		for i in 3:
			FX.shockwave(global_position, _rainbow(0.5, i * 0.33), 2.0 + i * 0.7, 0.3 + i * 0.05)
		FX.sparks(global_position + Vector3(0, 0.5, 0), 18, [_rainbow(0.5, 0.0), _rainbow(0.5, 0.33), _rainbow(0.5, 0.66), Color.WHITE], 8.0, 0.4, -6.0, 0.08)
		Sfx.play("charged", 0.0, -3.0)
		Main.inst.hitstop(0.03)
		Main.inst.camera.fov_punch(4.0)
		Main.inst.hud.popup("PERFECT", _rainbow(0.35), global_position + Vector3(0, 2.2, 0))


## 패링 반격: 공격해 온 적을 향해 검을 휘둘러 받아친다. 대시가 곧바로 다시 차고, 다음 검은 관통 일격이 된다.
func parry_counter(foe: Vector3, kind: String) -> void:
	if mega_t > 0.0:
		_end_mega()
	if dash_t > 0.0:
		dash_t = 0.0
		_dash_end()
	rainbow = false
	chain_grace = 0.0
	var d := foe - global_position
	d.y = 0
	if d.length() > 0.01:
		aim_dir = d.normalized()
	var aim_yaw := atan2(-aim_dir.x, -aim_dir.z)
	visual.basis = Basis.IDENTITY
	(j.upper as Node3D).rotation.y = aim_yaw
	(j.legs as Node3D).rotation.y = aim_yaw
	# 받아친 반동: 근접은 뒤로 밀리고, 원거리는 앞으로 내딛는다
	velocity = aim_dir * (3.0 if kind == "ranged" else -5.0)
	invuln = maxf(invuln, 0.7)
	dash_cd = 0.0
	slash_cd = 0.0
	phantom_ready = true
	slash_style = 1 if slash_style == 0 else 0
	slash_total = SLASH_TIMES[slash_style]
	slash_swing = SLASH_SWINGS[slash_style]
	slash_anim = slash_total
	FX.slash(self, aim_yaw, slash_style)
	Sfx.play("slash", 0.05, 2.0)
	tilt_v += -aim_dir * 9.0
	squash_v -= 8.0
	_set_flash(true)
	get_tree().create_timer(0.05, true, false, true).timeout.connect(_set_flash.bind(false))
	FX.afterimage(visual, Color(1.0, 0.85, 0.4, 0.5), 0.3)


func _dash_end() -> void:
	if not rainbow and chain_ok:
		chain_grace = CHAIN_GRACE
	rainbow = false
	# 회전 기준을 몸 전체(visual) → 상·하체 파츠로 되돌린다. 끝 시점엔 visual 이 조준 yaw 만 갖고 있다.
	var aim_yaw := atan2(-aim_dir.x, -aim_dir.z)
	visual.basis = Basis.IDENTITY
	(j.upper as Node3D).rotation.y = aim_yaw
	(j.legs as Node3D).rotation.y = aim_yaw
	velocity = dash_dir * SPEED
	squash_v += 7.0
	tilt_v += dash_dir * 5.0
	FX.shockwave(global_position, Color("8a7ae0"), 1.4, 0.22, 0.05)


func _fire() -> void:
	var muzzle: Node3D = j.muzzle
	var origin := muzzle.global_position
	origin.y = 0.95
	var d := aim_point - origin
	d.y = 0
	if d.length() < 1.2:
		d = aim_dir
	d = d.normalized().rotated(Vector3.UP, randf_range(-0.03, 0.03))
	Main.inst.add_bullet(Bullet.make_player(origin, d, BULLET_SPEED))
	GunFX.muzzle(origin, d)
	# 탄피는 사격 팔(왼쪽) 바깥으로 튄다
	var out := Vector3.UP.cross(d).normalized()
	GunFX.eject(origin - d * 0.45 + out * 0.08, (out - d * 0.2).normalized(), d)
	Sfx.play("shoot", 0.08, -8.0)
	recoil = 1.0
	tilt_v -= d * 0.9
	var main := Main.inst
	main.kick(-d * 0.09)
	main.shake(0.05)


func _fire_laser(k: float) -> void:
	var main := Main.inst
	var muzzle: Node3D = j.muzzle
	var origin := muzzle.global_position
	origin.y = 0.95
	var dir := aim_point - origin
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.5 else aim_dir
	var length := 0.0
	while length < LASER_RANGE:
		length += 0.2
		if main.is_blocked(origin + dir * length):
			break
	var w := lerpf(0.45, 1.25, k)
	var contact := BeamImpact.find_contact(get_tree(), origin, dir, length, w)
	if not contact.is_empty() and contact.blocks:
		length = contact.dist
	var dmg := int(round(lerpf(3.0, 10.0, k)))
	var hit_any := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		if _seg_dist(origin, dir, length, en.global_position) < en.radius + w * 0.5:
			en.take_hit(dmg, dir, en.global_position, "laser")
			hit_any = true
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		if _seg_dist(origin, dir, length, bl.position) < w * 0.6 + 0.2:
			FX.flash(bl.position, Pal.CYAN, 0.4, 0.08)
			bl.queue_free()
	FX.laser(origin, dir, length, w, k)
	if not contact.is_empty():
		BeamImpact.burst(contact.pos, dir, k, contact.size)
	Sfx.play("laser", 0.04, lerpf(-6.0, 1.0, k))
	var impact := k >= IMPACT_MIN_CHARGE
	if impact:
		ImpactFrame.inst.laser(origin, dir)
	# 반동: 뒤로 밀리고 상체가 젖혀진다
	velocity = -dir * lerpf(5.0, 14.0, k)
	tilt_v -= dir * lerpf(4.0, 10.0, k)
	squash_v -= 5.0 * k
	laser_recoil = 0.3
	laser_cd = LASER_CD
	recoil = 1.5
	main.shake(lerpf(0.3, 0.75, k))
	main.kick(-dir * lerpf(0.4, 1.1, k))
	main.camera.fov_punch(lerpf(2.0, 6.0, k))
	if impact:
		main.hitstop(ImpactFrame.inst.duration("laser") + (0.06 if hit_any else 0.02))
	elif hit_any:
		main.hitstop(0.06)


func _seg_dist(o: Vector3, d: Vector3, length: float, p: Vector3) -> float:
	var rel := Vector3(p.x - o.x, 0, p.z - o.z)
	var t := clampf(rel.dot(d), 0.0, length)
	return (rel - d * t).length()


## 전방(또는 아주 가까운) 적 중 가장 가까운 대상
func _lunge_target() -> Enemy:
	var best: Enemy = null
	var bd := LUNGE_RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var d := en.global_position - global_position
		d.y = 0
		var l := d.length()
		if l < bd and (l < 2.0 or aim_dir.angle_to(d / maxf(l, 0.001)) < deg_to_rad(70)):
			bd = l
			best = en
	return best


func _slash() -> void:
	if phantom_ready:
		_phantom_start()
		return
	var target := _lunge_target()
	var gap := LUNGE_FREE
	if target:
		var to := target.global_position - global_position
		to.y = 0
		aim_dir = to.normalized()
		gap = to.length() - LUNGE_STOP
	if gap > 0.25:
		# 적에게 파고들며 (대상이 없으면 앞으로 크게 내딛으며) 베기
		lunge_dir = aim_dir
		lunge_t = maxf(gap / LUNGE_SPEED, LUNGE_MIN_TIME)
		lunge_vel = lunge_dir * (gap / lunge_t)
		invuln = maxf(invuln, lunge_t + 0.05)
		ghost_t = 0.0
		slash_anim = 0.0
		tilt_v += lunge_dir * 8.0
		FX.shockwave(global_position, Pal.BLADE, 1.8, 0.22, 0.05)
		Sfx.play("dash", 0.08, -5.0)
		Main.inst.camera.fov_punch(3.0)
		return
	_slash_hit()


func _slash_hit() -> void:
	# 매번 다른 모션이 나오도록 직전 모션은 제외하고 고른다
	var st := randi() % 3
	slash_style = st if st < slash_style else st + 1
	slash_total = SLASH_TIMES[slash_style]
	slash_swing = SLASH_SWINGS[slash_style]
	slash_anim = slash_total
	var yaw := atan2(-aim_dir.x, -aim_dir.z)
	FX.slash(self, yaw, slash_style)
	Sfx.play("slash", 0.08)
	var reach := SLASH_RANGE + (0.8 if slash_style == 2 else 0.0)
	var cone := deg_to_rad([80.0, 80.0, 40.0, 180.0][slash_style])
	velocity += aim_dir * 6.0
	tilt_v += aim_dir * 5.0
	var main := Main.inst
	var hit_any := false
	var keep_cd := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var d := en.global_position - global_position
		d.y = 0
		if d.length() < reach + en.radius and aim_dir.angle_to(d.normalized()) <= cone:
			en.slash_yaw = atan2(-aim_dir.x, -aim_dir.z)
			# 장갑 상태(구체 크롤러)에 막힌 검은 콤보 쿨다운을 초기화하지 않는다
			var guarded: bool = en.has_method("is_armored") and en.is_armored()
			# 맘모스처럼 검 한 방에 죽지 않는 보스는 맞혀도 쿨다운을 초기화하지 않는다 (붙어서 연타 방지)
			keep_cd = keep_cd or en.get("no_slash_reset") == true
			en.take_hit(999, d.normalized(), en.global_position, "slash")
			hit_any = hit_any or not guarded
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		var d := bl.position - global_position
		d.y = 0
		if bl.unslashable:
			continue
		if d.length() < reach + 0.3 and (d.length() < 0.8 or aim_dir.angle_to(d.normalized()) <= cone):
			FX.flash(bl.position, Pal.BLADE, 0.45, 0.08)
			bl.queue_free()
	# 휘두르기만 해도 짧은 흔들림, 베면 강하게
	main.shake(0.2)
	main.kick(aim_dir * 0.35)
	if hit_any:
		main.hitstop(0.09)
		main.shake(0.4)
		main.camera.fov_punch(-4.0)
		# 검으로 처치하면 즉시 다시 휘두를 수 있다 (콤보)
		if not keep_cd:
			slash_cd = 0.0


## 관통 일격: 3프레임 만에 적을 꿰뚫고 뒤로 빠져나간 뒤 경로 위의 적을 한꺼번에 벤다
func _phantom_start() -> void:
	phantom_ready = false
	var main := Main.inst
	var best: Enemy = null
	var bd := PHANTOM_RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var d := en.global_position - global_position
		d.y = 0
		var l := d.length()
		if l < bd and (l < 2.0 or aim_dir.angle_to(d / maxf(l, 0.001)) < deg_to_rad(60)):
			bd = l
			best = en
	var dir := aim_dir
	var dist := 5.5
	if best:
		var to := best.global_position - global_position
		to.y = 0
		dir = to.normalized()
		dist = to.length() + PHANTOM_BEHIND
	# 벽 앞에서 멈춘다
	var free := 0.0
	while free < dist:
		if main.is_blocked(global_position + dir * (free + 0.25 + 0.45)):
			break
		free += 0.25
	dist = maxf(free, 0.5)
	aim_dir = dir
	phantom_from = global_position
	lunge_dir = dir
	lunge_phantom = true
	lunge_t = PHANTOM_TIME
	lunge_vel = dir * (dist / PHANTOM_TIME)
	invuln = maxf(invuln, PHANTOM_TIME + 0.3)
	ghost_t = 0.0
	slash_anim = 0.0
	tilt_v += dir * 10.0
	FX.flash(global_position + Vector3(0, 0.9, 0), Color(0.9, 1.0, 0.8), 1.2, 0.08)
	FX.shockwave(global_position, _rainbow(0.4), 2.6, 0.25, 0.06)
	Sfx.play("dash", 0.0, -2.0)
	Sfx.play("roll", 0.05, -4.0)
	main.camera.fov_punch(8.0)
	main.kick(dir * 0.9)


func _phantom_hit() -> void:
	lunge_phantom = false
	var main := Main.inst
	var to := global_position
	var path := to - phantom_from
	path.y = 0
	var length := path.length()
	var dir := path / maxf(length, 0.001) if length > 0.01 else lunge_dir
	var yaw := atan2(-dir.x, -dir.z)
	var marked: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		if _seg_dist(phantom_from, dir, length, en.global_position) < en.radius + PHANTOM_WIDTH:
			marked.append(en)
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		if not bl.unslashable and _seg_dist(phantom_from, dir, length, bl.position) < PHANTOM_WIDTH + 0.3:
			bl.queue_free()
	# 빠져나간 뒤 뒤돌아 베는 자세: 역베기 모션 + 경로를 가르는 일섬
	slash_style = 1
	slash_total = SLASH_TIMES[1]
	slash_swing = SLASH_SWINGS[1]
	slash_anim = slash_total
	FX.phantom_cut(phantom_from, to, _rainbow(0.35))
	FX.slash(self, yaw + PI, 1)
	Sfx.play("slash", 0.0, 3.0)
	main.shake(0.3)
	main.camera.fov_punch(-5.0)
	if marked.is_empty():
		return
	slash_cd = 0.0
	# 한 박자 늦게 경로 위의 적이 한꺼번에 갈라진다
	get_tree().create_timer(0.08, false).timeout.connect(func():
		for en in marked:
			if is_instance_valid(en) and (en as Enemy).alive:
				(en as Enemy).slash_yaw = yaw
				(en as Enemy).take_hit(999, dir, (en as Enemy).global_position, "phantom")
		Main.inst.hitstop(0.12)
		Main.inst.shake(0.6)
		Main.inst.hud.screen_flash(Color(0.85, 1.0, 0.8), 0.35)
		Main.inst.hud.popup("PIERCE x%d" % marked.size() if marked.size() > 1 else "PIERCE", Color(0.8, 1.0, 0.6), to + Vector3(0, 2.2, 0))
		Sfx.play("hit", 0.0, 2.0))


# ── 궁극기: 백팩 미사일 난사 ─────────────────────────────

## R 누름: 슬로우모션 + 줌아웃 + 락온 조준 시작
func _begin_ult_aim() -> void:
	ult_aiming = true
	ult_aim_start = Time.get_ticks_msec()
	_clear_locks()
	var main := Main.inst
	ult_ptr = main.get_viewport().get_mouse_position()
	if bot:
		ult_ptr = main.camera.unproject_position(global_position)
	main.set_slowmo(ULT_SLOW)
	main.camera.set_ult_view(true)
	main.hud.ult_mode(true)
	FX.shockwave(global_position, Color("ff5a4a"), 5.0, 0.12, 0.05)
	Sfx.play("slowin", 0.0, -2.0)


func ult_aim_left() -> float:
	return maxf(0.0, ULT_AIM_MAX - (Time.get_ticks_msec() - ult_aim_start) / 1000.0)


func _update_ult_aim() -> void:
	var main := Main.inst
	if not alive or main.state != Main.State.PLAY:
		_end_ult_aim(false)
		return
	var cam := main.camera
	var h := main.get_viewport().get_visible_rect().size.y
	if bot:
		ult_ptr = main.bot_ult_pointer(self, ult_ptr)
	else:
		ult_ptr = main.get_viewport().get_mouse_position()
	# 포인터가 스치는 적을 락온
	var r := LOCK_PX * h / 800.0
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed or locks.has(en) or locks.size() >= LOCK_MAX:
			continue
		var wp := en.global_position + Vector3(0, 1.0, 0)
		if cam.is_position_behind(wp):
			continue
		if cam.unproject_position(wp).distance_to(ult_ptr) < r:
			_lock(en)
	var released := not Input.is_action_pressed("ult")
	if bot:
		released = main.bot_ult_release(self)
	if released or ult_aim_left() <= 0.0:
		_end_ult_aim(true)


func _lock(en: Enemy) -> void:
	locks.append(en)
	lock_times[en.get_instance_id()] = Time.get_ticks_msec()
	en.set_locked(true)
	var ping := Sfx.play("lock", 0.0, -3.0)
	if ping:
		ping.pitch_scale = 1.0 + locks.size() * 0.07
	Main.inst.hud.lock_flash()
	Main.inst.camera.shake(0.08)


func _clear_locks() -> void:
	for en in locks:
		if is_instance_valid(en):
			(en as Enemy).set_locked(false)
	locks.clear()
	lock_times.clear()
	ult_targets.clear()


## R 놓음(또는 2초 경과): 슬로우 해제 후 락온한 적에게 미사일 발사
func _end_ult_aim(fire: bool) -> void:
	ult_aiming = false
	var main := Main.inst
	main.set_slowmo(1.0)
	main.camera.set_ult_view(false)
	main.hud.ult_mode(false)
	if not fire:
		_clear_locks()
		return
	ult_targets = locks.duplicate()
	lock_clear_t = 1.2
	_fire_ult()


func _fire_ult() -> void:
	ult = 0.0
	ult_queue = ULT_MISSILES
	ult_t = 0.0
	var main := Main.inst
	if not ult_targets.is_empty():
		main.hud.banner("LOCK x%d" % ult_targets.size(), Color("ff6a5a"), "")
	main.shake(0.35)
	main.camera.fov_punch(5.0)
	main.kick(aim_dir * -0.4)
	squash_v -= 9.0
	hover_v += 4.0
	FX.shockwave(global_position, Color("ffb050"), 3.5, 0.35)
	FX.ring(Vector3(global_position.x, 0.3, global_position.z), 3.5, [Color("ffd060"), Color("ff7a30"), Color.WHITE], 0.35)
	Sfx.play("overload", 0.0, -2.0)


func _update_ult(dt: float) -> void:
	if ult < 1.0 and ult_queue == 0:
		var before := ult
		ult = minf(1.0, ult + dt / ULT_TIME)
		if before < 1.0 and ult >= 1.0:
			Sfx.play("charged", 0.0, -6.0)
	if ult_queue > 0:
		ult_t -= dt
		while ult_t <= 0.0 and ult_queue > 0:
			ult_t += 0.03
			_launch_missile(ULT_MISSILES - ult_queue)
			ult_queue -= 1


func _launch_missile(i: int) -> void:
	var jet: Node3D = j.jet_l if i % 2 == 0 else j.jet_r
	var origin := jet.global_position + Vector3(0, 0.2, 0)
	# 락온한 적에게 고르게 나눠 쏘고, 락온이 없으면 가까운 적을 자동 조준
	var targets := ult_targets.filter(func(en): return is_instance_valid(en) and (en as Enemy).alive)
	if targets.is_empty():
		targets = Missile.pick_targets(global_position, 16.0)
	var m := Missile.new()
	if targets.size() > 0:
		m.target = targets[i % targets.size()]
	else:
		var a := randf() * TAU
		m.target_pos = global_position + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 7.0)
		m.target_pos.y = 0.3
	# 흩날리듯 사방으로 퍼져 올라간다
	var a2 := TAU * float(i) / ULT_MISSILES + randf_range(-0.2, 0.2)
	var out := Vector3(cos(a2), 0, sin(a2))
	m.vel = out * randf_range(5.0, 9.0) + Vector3(0, randf_range(6.0, 10.0), 0) - aim_dir * 1.5
	FX.root.add_child(m)
	m.global_position = origin
	FX.flash(origin, Color("ffd080"), 0.35, 0.05)
	if i % 3 == 0:
		Sfx.play("eshot", 0.2, -8.0)
	recoil = 0.6


# ── 최대 충전 지속 레이저 ────────────────────────────────

func _start_mega() -> void:
	mega_t = MEGA_TIME
	mega_yaw = atan2(-aim_dir.x, -aim_dir.z)
	mega_tick = 0.0
	mega_node = MegaBeam.new()
	FX.root.add_child(mega_node)
	var main := Main.inst
	var origin: Vector3 = (j.muzzle as Node3D).global_position
	origin.y = 0.95
	ImpactFrame.inst.mega(origin, aim_dir)
	main.dramatic(true)
	main.shake(0.6)
	main.hitstop(ImpactFrame.inst.duration("mega") + 0.05)
	main.camera.fov_punch(9.0)
	FX.shockwave(global_position, Pal.CYAN, 4.0, 0.4)
	FX.ring(Vector3(global_position.x, 0.3, global_position.z), 5.0, Pal.RING_CYAN, 0.45)
	Sfx.play("laser", 0.0, 2.0)
	squash_v -= 8.0
	_update_mega(0.0)


func _mega_dir() -> Vector3:
	return Vector3(-sin(mega_yaw), 0, -cos(mega_yaw))


func _update_mega(dt: float) -> void:
	var main := Main.inst
	# 조준을 묵직하게 따라감: 차이에 비례하되 최대 회전 속도 제한
	var target_yaw := atan2(-aim_dir.x, -aim_dir.z)
	var diff := angle_difference(mega_yaw, target_yaw)
	mega_yaw += clampf(diff * MEGA_TURN_GAIN, -MEGA_TURN_MAX, MEGA_TURN_MAX) * dt
	var dir := _mega_dir()
	var muzzle: Node3D = j.muzzle
	var origin := muzzle.global_position
	origin.y = 0.95
	var length := 0.0
	while length < LASER_RANGE:
		length += 0.25
		if main.is_blocked(origin + dir * length):
			break
	# 피격 지점: 처음 닿는 적 표면에 피격 연출. 보스처럼 막는 적은 빔이 거기서 멈춘다
	var contact := BeamImpact.find_contact(get_tree(), origin, dir, length, MEGA_WIDTH)
	if contact.is_empty():
		if mega_impact:
			mega_impact.active_t = 0.0
	else:
		if contact.blocks:
			length = contact.dist
		if mega_impact == null or not is_instance_valid(mega_impact):
			mega_impact = BeamImpact.new()
			FX.root.add_child(mega_impact)
		mega_impact.touch(contact.pos, dir, contact.size)
	mega_len = length
	if mega_node:
		mega_node.set_beam(origin, dir, length)
	main.camera.set_beam(true, dir)
	# 반동: 뒤로 계속 밀리고 몸이 젖혀짐
	velocity -= dir * 9.0 * dt
	tilt_v -= dir * 2.5 * dt * 10.0
	mega_tick -= dt
	if mega_tick <= 0.0:
		mega_tick = MEGA_TICK
		var hit_any := false
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy
			if not en.alive or not en.landed:
				continue
			if _seg_dist(origin, dir, length, en.global_position) < en.radius + MEGA_WIDTH * 0.5:
				en.take_hit(MEGA_DMG, dir, en.global_position, "laser")
				hit_any = true
		for b in get_tree().get_nodes_in_group("enemy_bullets"):
			var bl := b as Bullet
			if _seg_dist(origin, dir, length, bl.position) < MEGA_WIDTH * 0.6 + 0.2:
				FX.flash(bl.position, Pal.CYAN, 0.4, 0.08)
				bl.queue_free()
		if hit_any:
			main.shake(0.1)
		main.kick(-dir * 0.12)
	mega_t -= dt
	if mega_t <= 0.0:
		_end_mega()


func _end_mega() -> void:
	mega_t = 0.0
	if mega_node:
		mega_node.finish()
		mega_node = null
	if mega_impact and is_instance_valid(mega_impact):
		mega_impact.finish()
	mega_impact = null
	Main.inst.camera.set_beam(false)
	Main.inst.dramatic(false)
	laser_cd = 0.9
	squash_v += 6.0
	FX.shockwave(global_position, Pal.CYAN, 2.5, 0.3)


func take_hit(from: Vector3) -> bool:
	if not alive or invuln > 0.0 or Main.inst.state != Main.State.PLAY:
		return false
	hp -= 1
	invuln = 1.1
	hurt_t = 1.1
	var d := global_position - from
	d.y = 0
	d = d.normalized()
	velocity += d * 6.0
	tilt_v += d * 12.0
	squash_v -= 6.0
	FX.player_hurt(global_position + Vector3(0, 0.9, 0))
	_set_flash(true)
	get_tree().create_timer(0.07).timeout.connect(_set_flash.bind(false))
	Sfx.play("hurt", 0.05)
	var main := Main.inst
	main.shake(0.3)
	main.kick(d * 0.5)
	main.hitstop(0.08)
	main.on_player_hurt()
	if hp <= 0:
		die(d)
	return true


## 경직: t 초 동안 조작이 막히고 몸이 푸른 전류에 감긴 채 떤다
func stagger(t: float) -> void:
	if not alive:
		return
	stun_t = maxf(stun_t, t)
	print("PLAYER_STUN %.2fs hp=%d" % [t, hp])
	if lunge_t > 0.0:
		lunge_t = 0.0
		lunge_phantom = false
	if dash_t > 0.0:
		dash_t = 0.0
		_dash_end()
	velocity *= 0.3
	var c := global_position + Vector3(0, 0.9, 0)
	FX.sparks(c, 16, [Color.WHITE, Color("8ad8ff"), Color("2a6cff")], 7.0, 0.35, -6.0, 0.07)
	FX.shockwave(global_position, Color("3aa8ff"), 2.2, 0.25)
	Main.inst.hud.popup("STUN", Color("8ad8ff"), global_position + Vector3(0, 2.2, 0))
	Sfx.play("powerdown", 0.1, -4.0)


## 충격파에 밀려난다: 돌진·대시를 끊고 dir 쪽으로 speed 만큼 튕겨 나간다 (피해는 없음)
func shove(dir: Vector3, speed: float) -> void:
	if not alive:
		return
	if lunge_t > 0.0:
		lunge_t = 0.0
		lunge_phantom = false
	if dash_t > 0.0:
		dash_t = 0.0
		_dash_end()
	dir.y = 0
	dir = dir.normalized()
	velocity = dir * speed
	tilt_v += dir * 14.0
	squash_v -= 7.0
	slash_cd = maxf(slash_cd, 0.35)


func die(push := Vector3.ZERO) -> void:
	alive = false
	if ult_aiming:
		_end_ult_aim(false)
	if mega_t > 0.0:
		_end_mega()
	charge_fx.end()
	boost_snd.stop()
	blade_fx.visible = false
	FX.shatter(visual, push)
	visual.visible = false
	dodge_ring.visible = false
	FX.player_death(global_position + Vector3(0, 0.8, 0))
	Sfx.play("boom", 0.0, 3.0)
	Main.inst.on_player_died()


## 승리 포즈: 뛰어올라 한 바퀴
func celebrate() -> void:
	celebrate_t = 0.0
	charge_fx.end()


func _set_flash(on: bool) -> void:
	for mi in visual.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = Pal.flash() if on else null


# ── 애니메이션 ──────────────────────────────────────────

func _animate(dt: float) -> void:
	var legs: Node3D = j.legs
	var upper: Node3D = j.upper
	var torso: Node3D = j.torso
	var hv := Vector3(velocity.x, 0, velocity.z)
	var spd := hv.length()
	var aim_yaw := mega_yaw if mega_t > 0.0 else atan2(-aim_dir.x, -aim_dir.z)
	var t := Time.get_ticks_msec() * 0.001

	# 스프링 기울기: 이동 방향으로 숙이고, 충격은 tilt_v 로 들어온다
	var lean_target := hv * (0.045 if boosting else 0.018)
	if charging:
		lean_target += -aim_dir * 0.12 * charge
	if mega_t > 0.0:
		lean_target += -_mega_dir() * 0.28
	tilt_v += ((lean_target - tilt) * 120.0 - tilt_v * 13.0) * dt
	tilt += tilt_v * dt
	tilt = tilt.limit_length(0.9)
	var n := (Vector3.UP + Vector3(tilt.x, 0, tilt.z)).normalized()
	var axis := Vector3.UP.cross(n)
	lean.basis = Basis(axis.normalized(), Vector3.UP.angle_to(n)) if axis.length() > 0.0001 else Basis.IDENTITY

	# 찌그러짐 스프링
	squash_v += (-squash * 260.0 - squash_v * 16.0) * dt
	squash += squash_v * dt
	var sq := clampf(squash * 0.06, -0.3, 0.3)
	body.scale = Vector3(1.0 - sq * 0.5, 1.0 + sq, 1.0 - sq * 0.5)

	# 부유 높이
	var hover_target := HOVER + sin(t * 6.0) * 0.06 if boosting else 0.0
	hover_v += ((hover_target - hover) * 90.0 - hover_v * 12.0) * dt
	hover += hover_v * dt
	hover = maxf(hover, -0.05)
	visual.position.y = PIVOT_Y + hover

	# ── 드릴 회피: 조준 방향으로 머리를 두고 몸을 눕혀 축 회전 ──
	if dash_t > 0.0:
		var k := 1.0 - dash_t / DASH_TIME
		var lay := (1.0 if dash_skip_in else smoothstep(0.0, 0.18, k)) * (1.0 - smoothstep(0.82, 1.0, k))
		drill = dash_roll_sign * TAU * ease(k, -1.8)
		var upright := Basis(Vector3.UP, aim_yaw)
		var flat := upright * Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, drill)
		visual.basis = upright.slerp(flat, lay) if lay < 0.999 else flat
		lean.basis = Basis.IDENTITY
		tilt = Vector3.ZERO
		# 파츠는 몸 정면 기준으로 정렬, 팔다리는 몸통에 붙인다
		upper.rotation.y = 0.0
		legs.rotation.y = 0.0
		for h in [j.hip_l, j.hip_r]:
			(h as Node3D).rotation.x = lerpf((h as Node3D).rotation.x, 0.25, 0.5)
		for kn in [j.knee_l, j.knee_r]:
			(kn as Node3D).rotation.x = lerpf((kn as Node3D).rotation.x, -0.2, 0.5)
		(j.arm_l as Node3D).rotation.z = lerpf((j.arm_l as Node3D).rotation.z, -0.3, 0.5)
		(j.arm_r as Node3D).rotation.z = lerpf((j.arm_r as Node3D).rotation.z, 0.3, 0.5)
		_animate_jets(dt, 0.0)
		_animate_ring(dt)
		visual.visible = true
		return
	else:
		# 회피 직후: 기울였던 자세를 빠르게 되돌림
		visual.basis = visual.basis.slerp(Basis.IDENTITY, 1.0 - exp(-25.0 * dt))
		(j.arm_l as Node3D).rotation.z = lerpf((j.arm_l as Node3D).rotation.z, 0.0, 0.3)
		(j.arm_r as Node3D).rotation.z = lerpf((j.arm_r as Node3D).rotation.z, 0.0, 0.3)

	# 승리 포즈
	if celebrate_t >= 0.0:
		celebrate_t += dt
		var ck := clampf(celebrate_t / 0.7, 0.0, 1.0)
		visual.position.y = PIVOT_Y + sin(ck * PI) * 1.4
		visual.rotation.y = ease(ck, -2.0) * TAU
		if ck >= 1.0:
			celebrate_t = -1.0
			visual.rotation.y = 0.0
			squash_v += 9.0
			FX.shockwave(global_position, Pal.CYAN, 3.0, 0.4)

	# 하체는 이동 방향, 상체는 조준 방향
	upper.rotation.y = lerp_angle(upper.rotation.y, aim_yaw, 1.0 - exp(-30.0 * dt))
	if spd > 0.5:
		var mv := hv / spd
		var move_yaw := atan2(-mv.x, -mv.z)
		if abs(angle_difference(move_yaw, aim_yaw)) > PI * 0.5:
			move_yaw = move_yaw + PI
		legs.rotation.y = lerp_angle(legs.rotation.y, move_yaw, 1.0 - exp(-14.0 * dt))
	else:
		legs.rotation.y = lerp_angle(legs.rotation.y, aim_yaw, 1.0 - exp(-8.0 * dt))

	var hl: Node3D = j.hip_l
	var hr: Node3D = j.hip_r
	var kl: Node3D = j.knee_l
	var kr: Node3D = j.knee_r
	if boosting or hover > 0.15:
		# 비행: 다리를 뒤로 모으고 살랑거림
		var dangle := sin(t * 7.0) * 0.12
		hl.rotation.x = lerpf(hl.rotation.x, 0.55 + dangle, 0.2)
		hr.rotation.x = lerpf(hr.rotation.x, 0.4 - dangle, 0.2)
		kl.rotation.x = lerpf(kl.rotation.x, -0.9, 0.2)
		kr.rotation.x = lerpf(kr.rotation.x, -1.1, 0.2)
		upper.position.y = 0.74
	else:
		var moving: float = clampf(spd / SPEED, 0.0, 1.0)
		walk += dt * (4.0 + spd * 1.6)
		var sw := sin(walk) * 0.75 * moving
		var fwd_sign := 1.0
		if spd > 0.5:
			var lf := -legs.global_basis.z
			fwd_sign = 1.0 if lf.dot(hv) >= 0.0 else -1.0
		hl.rotation.x = sw * fwd_sign
		hr.rotation.x = -sw * fwd_sign
		kl.rotation.x = max(0.0, -sin(walk)) * -0.9 * moving
		kr.rotation.x = max(0.0, sin(walk)) * -0.9 * moving
		var bob := absf(cos(walk)) * 0.06 * moving
		# 서 있을 때 숨쉬기
		var breathe := sin(t * 2.4) * 0.015 * (1.0 - moving)
		upper.position.y = 0.74 + bob + breathe
		torso.rotation.z = sin(walk) * 0.05 * moving

	# 사격 팔 반동 · 충전 자세
	recoil = move_toward(recoil, 0.0, dt * 10.0)
	laser_recoil = maxf(0.0, laser_recoil - dt)
	var arm_l: Node3D = j.arm_l
	var shake_arm := sin(t * 70.0) * 0.03 * charge if charging else 0.0
	arm_l.position.z = recoil * 0.1
	arm_l.rotation.x = recoil * 0.14 + shake_arm
	arm_l.rotation.y = shake_arm
	var torso_pitch := -0.1 * clampf(spd / SPEED, 0.0, 1.0)
	if charging:
		torso_pitch = 0.12 * charge   # 뒤로 버티는 자세
	if mega_t > 0.0:
		torso_pitch = 0.2 + sin(t * 60.0) * 0.03
		arm_l.rotation.x = sin(t * 80.0) * 0.05
	torso_pitch += recoil * 0.06
	torso.rotation.x = lerpf(torso.rotation.x, torso_pitch, 0.25)

	# 검 휘두르기: 오른쪽 → 왼쪽
	var blade: Node3D = j.blade
	var arm_r: Node3D = j.arm_r
	if lunge_t > 0.0:
		# 돌진 중: 검을 뒤로 당긴 준비 자세
		arm_r.rotation.y = lerpf(arm_r.rotation.y, -1.4, 0.5)
		arm_r.rotation.x = -0.5
		blade.rotation_degrees = Vector3(8, -70, 0)
		torso.rotation.y = lerpf(torso.rotation.y, -0.8, 0.5)
	elif slash_anim > 0.0:
		slash_anim -= dt
		# 앞 slash_swing 초에 스윙이 끝나고, 나머지는 휘두른 자세로 멈췄다 복귀
		var el := slash_total - slash_anim
		var k := clampf(el / slash_swing, 0.0, 1.0)
		match slash_style:
			0:
				# 가로 베기: 오른쪽 → 왼쪽
				arm_r.rotation.y = lerpf(-1.4, 1.9, k)
				arm_r.rotation.x = -0.4
				blade.rotation_degrees = Vector3(8, -70, 0)
				torso.rotation.y = lerpf(-0.8, 0.85, k)
			1:
				# 역베기: 왼쪽 → 오른쪽으로 되받아 친다
				arm_r.rotation.y = lerpf(1.9, -1.5, k)
				arm_r.rotation.x = -0.35
				blade.rotation_degrees = Vector3(8, -30, 0)
				torso.rotation.y = lerpf(0.9, -0.85, k)
			2:
				# 내려찍기: 머리 위로 치켜든 검을 앞바닥까지 내려친다
				arm_r.rotation.y = 0.0
				arm_r.rotation.x = lerpf(2.8, 0.85, ease(k, 0.6))
				blade.rotation_degrees = Vector3(-90, 0, 0)
				torso.rotation.y = lerpf(0.35, -0.1, k)
				torso.rotation.x = lerpf(0.3, -0.38, k)
			3:
				# 회전 베기: 팔을 옆으로 뻗고 상체가 한 바퀴 돈다
				arm_r.rotation.y = 0.0
				arm_r.rotation.x = -0.15
				arm_r.rotation.z = 1.35
				blade.rotation_degrees = Vector3(-90, 0, 0)
				torso.rotation.y = 0.0
				upper.rotation.y = aim_yaw + ease(k, 0.7) * TAU
	else:
		arm_r.rotation.y = lerp_angle(arm_r.rotation.y, 0.0, 0.25)
		arm_r.rotation.x = lerpf(arm_r.rotation.x, 0.0, 0.25)
		blade.rotation_degrees = blade.rotation_degrees.lerp(Vector3(38, -18, 0), 0.25)
		torso.rotation.y = lerpf(torso.rotation.y, 0.0, 0.25)

	_animate_jets(dt, 1.0 if boosting else 0.0)

	# 피격 무적 깜빡임 (회피 무적은 잔상으로 표현)
	visual.visible = not (hurt_t > 0.0 and fmod(hurt_t, 0.12) < 0.05)
	_animate_ring(dt)


func _animate_jets(dt: float, on: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for jet in [j.jet_l, j.jet_r]:
		var n := jet as Node3D
		var target := on * (0.75 + sin(t * 60.0 + n.position.x * 20.0) * 0.2 + randf() * 0.15)
		var s := lerpf(n.scale.y, target, 0.5)
		n.scale = Vector3(0.7 + on * 0.5, maxf(s, 0.001), 0.7 + on * 0.5)
		n.visible = s > 0.02
	if on > 0.0:
		puff_t -= dt
		if puff_t <= 0.0:
			puff_t = 0.025
			for jet in [j.jet_l, j.jet_r]:
				var n := jet as Node3D
				var p := n.global_position - n.global_basis.y.normalized() * 0.6
				FX.boost_puff(p, -velocity * 0.3 + Vector3(0, -1.5, 0))
		if not Sfx.inst.muted:
			boost_snd.volume_db = lerpf(boost_snd.volume_db, -9.0, 0.2)
			boost_snd.pitch_scale = 0.9 + velocity.length() / BOOST_SPEED * 0.4
	else:
		boost_snd.volume_db = lerpf(boost_snd.volume_db, -60.0, 0.15)
		if boost_snd.playing and boost_snd.volume_db < -55.0:
			boost_snd.stop()


func _animate_ring(dt: float) -> void:
	var ready_k := 1.0 - dash_cd / DASH_CD
	if dash_cd <= 0.0 and ready_ping < 0.0:
		ready_ping = 0.25
		Sfx.play("ready", 0.0, -14.0)
	if dash_cd > 0.0:
		ready_ping = -1.0
	var ring_c := Color(0.2, 0.17, 0.4).lerp(Color(0.25, 0.7, 0.85), 1.0 if dash_cd <= 0.0 else ready_k * 0.3)
	dodge_ring.set_instance_shader_parameter("tint", ring_c)
	var pulse := 0.0
	if ready_ping > 0.0:
		ready_ping = max(0.0, ready_ping - dt)
		pulse = ready_ping * 1.2
	dodge_ring.scale = Vector3(1.0 + pulse, 0.05, 1.0 + pulse)
