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
const BOOST_KILL := 0.12        # 적 처치 1회당 게이지 회복 (비행 중에도 찬다)
const HOVER := 0.75
const DASH_SPEED := 17.0
const DASH_TIME := 0.3
const DASH_CD := 0.8
const FIRE_INTERVAL := 0.085
const MAG_SIZE := 30              # 기본 총기 탄창: 30발마다 재장전
const RELOAD_TIME := 1.25         # 재장전 시간 (T 키, 또는 탄창이 비면 자동)
const BULLET_SPEED := 60.0
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
# 궁극기: 미사일 난사
# ── 한정 재화 ──
# 에너지: 충전 레이저 탄창. 최소 발사 단계부터 1칸, 2단 2칸, 최대(지속 레이저) 3칸을 쓴다.
const ENERGY_MAX := 3
const ENERGY_REGEN := 9.0        # 이 시간(초)마다 에너지 1칸이 저절로 찬다
# 미사일: 궁극기 탄. 가진 개수만큼만 쏜다. 적이 죽을 때 가끔 떨어뜨리는 아이템을 직접 주워야 는다.
const MISSILE_MAX := 12
const MISSILE_START := 4
const CHARGE_STAGES := [0.34, 0.67, 1.0]
# 2단 대시: 대시 마지막 CHAIN_WINDOW 초 ~ 끝난 뒤 CHAIN_GRACE 초 안에 다시 누르면 성공
const CHAIN_WINDOW := 0.1
const CHAIN_GRACE := 0.06
# 관통 일격 (2단 대시 성공 후 첫 검)
const PHANTOM_RANGE := 9.0
const PHANTOM_TIME := 0.05       # 3프레임
const PHANTOM_BEHIND := 2.2      # 적 뒤로 빠져나가는 거리
const PHANTOM_WIDTH := 0.9
const PHANTOM_DMG := 20
const PHANTOM_WINDOW := 3.0      # 2단 대시(또는 패링) 성공 후 관통 일격을 쓸 수 있는 시간
# 검 휘두르기 4종: 가로 베기 / 역베기 / 내려찍기 / 회전 베기
const SLASH_TIMES := [0.16, 0.16, 0.2, 0.24]
const SLASH_SWINGS := [0.05, 0.05, 0.06, 0.1]
# 궁극기 락온
const ULT_SLOW := 0.06
const ULT_AIM_MAX := 2.0         # 실제 시간 (초)
const LOCK_PX := 54.0            # 화면 800px 높이 기준 락온 반경
const MAGNET_PX := 128.0         # 이 반경 안의 아직 락온하지 않은 적에게 조준점이 자석처럼 달라붙는다
const ULT_REACH := 40.0          # 락온 조준점의 안전 상한 거리 (m). 실제 한계는 화면 가장자리 (ULT_EDGE_PX)
const ULT_EDGE_PX := 18.0        # 조준점이 화면 가장자리에서 이만큼 안쪽까지 갈 수 있다 → 화면에 보이는 적은 모두 조준 가능
const ULT_WINDUP := 0.42         # R 을 뗀 뒤 발사 직전 준비동작 (실제 시간, 초). 슬로우모션도 이때 함께 끝난다
const LOCK_MAX := 10

# 점프: Shift 를 누른 채 Space 를 JUMP_HOLD 초 이상 누르고 있으면 뛴다 (짧게 떼면 평소 대시)
const JUMP_HOLD := 0.18
const JUMP_V := 8.8              # 정점 약 1.5m
const GRAVITY := 25.0
const FALL_SNAP := 0.35          # 이보다 급히 꺼지는 지면은 걸어 내려가지 않고 떨어진다

## 추격 보스전: 부스터 무한 비행 · 전장 안에서 좌우로 움직이는 속도
var infinite_boost := false
const CHASE_SPEED := 9.5
## 외부 감속 배율 (거미 보스의 거미줄 등 장면이 정한다). 1 이면 평소 속도
var slow_mul := 1.0
## 필드 기믹 훅 (scripts/gimmicks/gimmicks.gd 가 매 틱 정한다)
var no_attack := false            # 공격 불가: 연기 속 · 레버 돌리는 중 (이동기는 쓸 수 있다)
var hidden := false               # 연기 속에 숨어 적이 보지 못한다
var rooted := false               # 제자리 고정 (레버 돌리는 중)
var carry := Vector3.ZERO         # 레일이 실어 나르는 속도 (이동에 더해진다)
var interact_ok := false          # 레버 범위: F 는 검 대신 레버로 간다
var gimmick_pose: Callable        # 자세 덮어쓰기 (레버 돌리기), 인자 (player, dt)

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
# 높이 상태 (global_position.y 가 발 높이)
var gy := 0.0                     # 발밑 지면 높이
var vy := 0.0                     # 수직 속도
var airborne := false
var view_y := 0.0                 # 카메라·조준 기준 높이: 지면 높이를 부드럽게 따라간다 (점프로 흔들리지 않게)
var jump_wait := false            # Shift+Space 를 누른 채 점프 충전 중
var jump_hold := 0.0
var jump_fx: JumpFX
var shadow: MeshInstance3D
var gust_from := Vector3.ZERO    # 대시 기류: 지난 틱 위치

# 전투 상태
var fire_cd := 0.0
var mag := MAG_SIZE                # 탄창에 남은 탄
var reload_t := 0.0               # 재장전 남은 시간 (0 이면 재장전 중 아님)
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
## 사격 팔 반동 스프링: 쏘는 순간 뒤로 튕겼다가 앞으로 살짝 넘쳐 되돌아온다 (연출 전용)
var gun_kick := 0.0
var gun_kick_v := 0.0
var _arm_l_rest := Vector3.INF
var _sh_l_rest := Vector3.INF
const KICK_STIFF := 1400.0        # 스프링 강도 (클수록 빠르게 되돌아온다)
const KICK_DAMP := 26.0           # 감쇠 (작을수록 앞뒤로 더 출렁인다)
const KICK_IMPULSE := 34.0        # 한 발당 뒤로 차는 속도
var mega_t := 0.0
var mega_yaw := 0.0
var mega_tick := 0.0
var mega_node: MegaBeam
var mega_len := 0.0
var mega_impact: BeamImpact
var lunge_t := 0.0
var lunge_vel := Vector3.ZERO
var lunge_dir := Vector3.ZERO
var energy := ENERGY_MAX
var energy_regen_t := 0.0
var missiles := MISSILE_START
var ult_count := 0               # 이번 궁극기에 쏘는 미사일 수
var ult_queue := 0
var ult_t := 0.0
var charge_stage := 0
var chain_ok := true
var chain_grace := 0.0
var rainbow := false             # 지금 대시가 2단 대시인가
var dash_skip_in := false
var phantom_ready := false
var phantom_t := 0.0             # 관통 일격 남은 시간 (0 이 되면 칼날 불꽃이 꺼진다)
var lunge_phantom := false
var phantom_from := Vector3.ZERO
var slash_style := 0
var slash_total: float = SLASH_TIMES[0]
var slash_swing: float = SLASH_SWINGS[0]
var ult_aiming := false
var ult_aim_start := 0
var ult_ptr := Vector2.ZERO      # 조준점 (자석 보정 후)
var ult_raw := Vector2.ZERO      # 실제 마우스 위치
var ult_snap: Enemy = null       # 조준점이 달라붙은 적
var ult_windup_start := -1       # 준비동작 시작 시각 (ms), -1 = 아님
var _ult_ms := 0
## 락온 조준점(월드). 조준 중에는 마우스를 붙잡아 두고 이동량만큼 이 점을 옮긴다.
## 카메라가 이 점을 화면 가운데 가깝게 따라가므로 화면 좌표를 그대로 쓰면 시야가 끝없이 끌려간다.
var ult_aim_w := Vector3.ZERO
var _ult_mouse_d := Vector2.ZERO
var _ult_prev_mouse := Input.MOUSE_MODE_HIDDEN
var locks: Array = []
var lock_times := {}
var ult_targets: Array = []
var ult_plan: Array = []         # 이번 궁극기의 미사일별 목표 (null = 바닥에 흩뿌림)
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
var trail: SaberTrail     # 광선검 잔상 리본
var combo: SwordCombo     # 6단 검술 콤보
var motion: PlayerMotion  # 사격·재장전·레이저·미사일 동작 연출
var tech: BladeTech       # 좌클릭 길게 기 모으기 돌진 · 콤보 중 좌+우 회피 레이저
var body_trails: Array[SaberTrail] = []   # 팔·다리 리본 (대시 회전·돌진 중에만 보임)
var rush_feet: Array = []                 # 돌진 중 발 아래 바닥의 지난 위치 [왼, 오]
var rushing := false
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
	j = MechPlayer.build(body) if MechPlayer.active() else Build.robot(body)
	motion = PlayerMotion.new(self)
	motion.rig()
	tech = BladeTech.new(self)
	shadow = FX.blob_shadow(self, 2.6, 0.75)
	jump_fx = JumpFX.new()
	add_child(jump_fx)
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
	trail = SaberTrail.new()
	trail.blade = j.blade
	trail.anchor = self
	trail.gust = true
	add_child(trail)
	combo = SwordCombo.new(self)
	combo.trail = trail
	# 몸 리본: 어깨→손끝, 무릎 위→발끝. 드릴 회전하면 나선으로 감기고, 돌진하면 뒤로 곧게 끌린다.
	var lt: Array = j.leg_trail
	for spec in [[j.arm_l, j.arm_base, j.arm_tip_l, 0.0], [j.arm_r, j.arm_base, j.arm_tip_r, 0.3],
			[j.knee_l, lt[0], lt[1], 0.6], [j.knee_r, lt[0], lt[1], 0.9]]:
		var bt := SaberTrail.body(spec[0], spec[1], spec[2], spec[3])
		add_child(bt)
		body_trails.append(bt)
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
	var reload_pressed := false
	var slash_pressed := false
	var dash_pressed := false
	var charge_held := false
	var boost_held := false
	var bot_jump := false
	var lmb_held := false
	var rmb_held := false
	var dual := false
	var skill_held := false
	if bot:
		var b := main.bot_input(self)
		move_dir = b.move
		aim_point = b.aim
		fire = b.fire
		reload_pressed = b.get("reload", false)
		slash_pressed = b.slash
		dash_pressed = b.dash
		charge_held = b.get("charge", false)
		boost_held = b.get("boost", false)
		bot_jump = b.get("jump", false)
		lmb_held = b.get("hold", false)
		dual = b.get("dual", false)
		skill_held = b.get("skill", false)
		if b.get("ult", false) and missiles > 0 and playing and not no_attack and not ult_busy() and ult_queue == 0 and mega_t <= 0.0:
			_begin_ult_aim()
	else:
		var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		move_dir = Vector3(v.x, 0, v.y)
		aim_point = main.mouse_ground(view_y + 0.95)
		# 좌클릭 검 · 우클릭 사격 · 좌우 동시 유지 충전
		var lmb := Input.is_action_pressed("slash_mouse")
		var rmb := Input.is_action_pressed("fire_mouse")
		charge_held = lmb and rmb
		fire = rmb and not lmb
		reload_pressed = InputMap.has_action("reload") and Input.is_action_just_pressed("reload")
		# 좌클릭 검은 BladeTech 가 짧게 눌렀는지(검) 길게 눌렀는지(기 모으기) 가려서 낸다. F 는 바로 벤다. E 는 돌진 스킬.
		slash_pressed = Input.is_action_just_pressed("slash") and not (interact_ok and Input.is_action_just_pressed("interact"))
		lmb_held = lmb
		rmb_held = rmb
		dual = lmb and rmb and (Input.is_action_just_pressed("slash_mouse") or Input.is_action_just_pressed("fire_mouse"))
		skill_held = InputMap.has_action("rush_skill") and Input.is_action_pressed("rush_skill")
		dash_pressed = Input.is_action_just_pressed("dash")
		boost_held = Input.is_action_pressed("boost")
		if Input.is_action_just_pressed("ult") and playing and not no_attack and not ult_busy() and ult_queue == 0 and mega_t <= 0.0:
			if missiles > 0:
				_begin_ult_aim()
			else:
				_deny("NO MISSILE", "missile")
	if mega_t > 0.0:
		# 지속 레이저 중에는 대시만 받는다 (대시로 레이저를 끊는다)
		fire = false
		slash_pressed = false
		charge_held = false
		boost_held = false
	if ult_busy():
		fire = false
		slash_pressed = false
		dash_pressed = false
		charge_held = false
	if ult_winding():
		move_dir = Vector3.ZERO
	if not playing:
		fire = false
		slash_pressed = false
		dash_pressed = false
		charge_held = false
		boost_held = false
		move_dir = Vector3.ZERO
	if no_attack:
		# 연기 속 · 레버 돌리는 중: 이동기(이동·대시·부스터·점프)만 받는다. 모으던 충전은 레이저 없이 흩어진다
		fire = false
		slash_pressed = false
		charge_held = false
		lmb_held = false
		rmb_held = false
		dual = false
		if charging:
			charge = 0.0
		if mega_t > 0.0:
			_end_mega()
		if ult_aiming:
			_end_ult_aim(false)
	if rooted:
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

	# ── 광선검 특수기: 좌클릭 길게 → 기 모으기 돌진 · 콤보 중 좌+우 동시 → 회피 레이저 ──
	var tech_ok := playing and not no_attack and stun_t <= 0.0 and not ult_busy() and mega_t <= 0.0 and dash_t <= 0.0 and lunge_t <= 0.0
	if dual and tech_ok and tech.try_backstep():
		charge_held = false
	# E 누르고 조준 → 떼면 돌진 스킬 (기 모으기 1단계 짧은 돌진)
	if tech.skill_feed(skill_held, tech_ok and not charging):
		charge_held = false
	if tech.feed(lmb_held, rmb_held, tech_ok, dt):
		slash_pressed = true
	if tech.busy():
		fire = false
		charge_held = false
		slash_pressed = false
		if not tech.charging():
			dash_pressed = false

	var to_aim := aim_point - global_position
	to_aim.y = 0
	if to_aim.length() > 0.3 and lunge_t <= 0.0 and not combo.committed() and not tech.rushing() and not tech.backstepping():
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
	# ── 점프: Shift 를 누른 채 Space 를 살짝 길게 누르고 있어야 뛴다. 짧게 떼면 평소처럼 대시. ──
	if bot:
		if bot_jump and _can_jump():
			_jump_start()
	else:
		var shift_held := Input.is_action_pressed("boost")
		var space_held := Input.is_action_pressed("dash")
		if dash_pressed and shift_held and _can_jump():
			jump_wait = true
			jump_hold = 0.0
			dash_pressed = false
		elif jump_wait:
			if not _can_jump():
				jump_wait = false
				jump_fx.stop_charge()
			elif not space_held or not shift_held:
				# 단타: 점프 대신 대시가 나간다
				jump_wait = false
				jump_fx.stop_charge()
				dash_pressed = playing and stun_t <= 0.0 and not ult_busy()
			else:
				jump_hold += dt
				jump_fx.charge(jump_hold / JUMP_HOLD)
				squash_v -= 26.0 * dt         # 뛰기 전에 무릎을 굽혀 웅크린다
				if jump_hold >= JUMP_HOLD:
					jump_wait = false
					_jump_start()
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
	combo.update(dt)
	tech.update(dt)
	if lunge_t > 0.0:
		lunge_t -= dt
		velocity = lunge_vel
		ghost_t -= dt
		if ghost_t <= 0.0:
			ghost_t = 0.0
			FX.afterimage(visual, _ghost_color(0.5), 0.0)
		if lunge_t <= 0.0:
			lunge_phantom = false
			velocity = lunge_dir * 3.0
			_phantom_hit()
	elif dash_t > 0.0:
		dash_t -= dt
		var k := 1.0 - dash_t / DASH_TIME
		# 초반에 가장 빠르고 끝에서 감속
		velocity = dash_dir * DASH_SPEED * lerpf(1.25, 0.55, k) * lerpf(1.0, slow_mul, 0.5)
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
	elif tech.busy():
		velocity = tech.vel
	elif combo.committed():
		velocity = combo.vel
		if combo.ph == SwordCombo.Ph.LUNGE:
			FX.afterimage(visual, FX.GHOST, 0.18)
	else:
		var target_speed := BOOST_SPEED if boosting else SPEED
		if infinite_boost:
			target_speed = CHASE_SPEED
		if charging:
			target_speed *= 0.55
		if mega_t > 0.0:
			target_speed *= MEGA_MOVE
		target_speed *= slow_mul
		var dir := move_dir.limit_length(1.0)
		if boosting and dir.length() < 0.1 and not infinite_boost:
			dir = aim_dir
		var accel := BOOST_ACCEL if boosting and not infinite_boost else ACCEL
		velocity = velocity.move_toward(dir * target_speed, accel * dt)
	_move_body(dt)
	_update_rush()
	if dash_t > 0.0:
		GustFX.dash_trail(gust_from, global_position, _gust_tint(), 1.25 if rainbow else 1.0)
	gust_from = global_position

	if mega_t > 0.0:
		_update_mega(dt)

	# ── 사격 ──
	fire_cd -= dt
	laser_cd -= dt
	if reload_t > 0.0:
		reload_t -= dt
		if reload_t <= 0.0:
			_finish_reload()
	elif playing and ((reload_pressed and mag < MAG_SIZE) or (fire and mag <= 0)):
		_begin_reload()
	if fire and reload_t <= 0.0 and mag > 0 and fire_cd <= 0.0 and slash_anim <= 0.0 and not charging and laser_recoil <= 0.0 and not combo.committed():
		fire_cd = FIRE_INTERVAL
		mag -= 1
		_fire()
		if mag <= 0:
			_begin_reload()      # 탄창이 비면 곧바로 재장전

	# ── 충전 레이저 ──
	if charge_held and laser_cd <= 0.0 and not combo.committed() and (charging or energy > 0):
		if not charging:
			charging = true
			charge = 0.0
			charge_stage = 0
			charge_fx.begin()
			charge_snd = Sfx.play("charge", 0.0, -6.0)
		# 가진 에너지로 쏠 수 있는 단계까지만 모인다 (1칸: 1단, 2칸: 2단, 3칸: 최대)
		charge = minf(charge_cap(), charge + dt / CHARGE_TIME)
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
			motion.stage_pulse()
		charge_fx.set_charge(charge, dt)
	elif charging:
		charging = false
		charge_fx.end()
		if charge_snd and charge_snd.playing and Sfx.inst and charge_snd.stream == Sfx.inst.streams.get("charge"):
			charge_snd.stop()
		if charge >= 1.0:
			_spend_energy(laser_cost(charge))
			_start_mega()
		elif charge >= CHARGE_MIN:
			_spend_energy(laser_cost(charge))
			_fire_laser(charge)
		else:
			FX.fizzle((j.muzzle as Node3D).global_position)
		charge = 0.0
	elif charge_held and laser_cd <= 0.0 and energy <= 0 and not combo.committed():
		_deny("NO ENERGY", "energy")
	_regen_energy(dt)

	# ── 검 ──
	slash_cd -= dt
	if slash_pressed and not charging and lunge_t <= 0.0:
		_slash()

	invuln = max(0.0, invuln - dt)
	hurt_t = max(0.0, hurt_t - dt)
	if phantom_ready:
		phantom_t -= dt
		if phantom_t <= 0.0:
			phantom_ready = false
			blade_fx.douse()
	_update_ult(dt)
	_animate(dt)


## 수평 이동(벽 충돌) 뒤 바닥 굴곡 높이를 따른다. 점프 중에는 중력으로 떨어져 바닥에 내려앉는다.
func _move_body(dt: float) -> void:
	var main := Main.inst
	var feet := global_position.y
	velocity.y = 0
	velocity += carry             # 레일: 띠 속도만큼 실려 간다 (자기 속도는 그대로 남긴다)
	move_and_slide()
	velocity -= carry
	var p := main.push_out_feet(global_position, 0.42, feet, 0.1 if airborne else ArenaMap.STEP)
	gy = main.floor_at(p)
	if airborne:
		vy -= GRAVITY * dt
		feet += vy * dt
		if feet <= gy and vy <= 0.0:
			_land(-vy)
			feet = gy
		elif feet < gy:
			feet = gy                    # 모서리를 넘어서는 순간 살짝 올려 세운다
	elif gy < feet - FALL_SNAP:
		# 낭떠러지: 걸어 내려가지 않고 떨어진다
		airborne = true
		vy = 0.0
	else:
		feet = gy
	p.y = feet
	global_position = p
	view_y = lerpf(view_y, gy, 1.0 - exp(-7.0 * dt))
	# 그림자·회피 링은 지면에 남는다
	shadow.position.y = gy - feet + 0.015
	dodge_ring.position.y = gy - feet + 0.03
	jump_fx.follow(p, gy)


func _can_jump() -> bool:
	return alive and not airborne and Main.inst.state == Main.State.PLAY and stun_t <= 0.0 and lunge_t <= 0.0 		and dash_t <= 0.0 and mega_t <= 0.0 and not ult_busy() and celebrate_t < 0.0


func _jump_start() -> void:
	_combo_break()
	airborne = true
	vy = JUMP_V
	squash_v += 14.0                 # 쭉 늘어나며 튀어 오른다
	tilt_v += -move_dir.limit_length(1.0) * 3.0
	jump_fx.launch(Vector3(global_position.x, gy, global_position.z))
	Main.inst.camera.fov_punch(2.0)


func _land(fall: float) -> void:
	airborne = false
	vy = 0.0
	squash_v -= clampf(fall * 1.1, 4.0, 14.0)
	jump_fx.land(Vector3(global_position.x, gy, global_position.z), fall)
	if fall > 9.0:
		Main.inst.shake(0.12)


## 락온 조준은 실제 시간 기준으로 매 화면 프레임 갱신한다 (슬로우모션 중 물리 틱과 무관하게 부드럽게)
func _process(dt: float) -> void:
	if ult_aiming:
		_update_ult_aim()
	elif ult_winding():
		_update_ult_windup()
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
	FX.shockwave(global_position, Pal.JET, 2.2, 0.3)
	FX.sparks(global_position + Vector3(0, 0.1, 0), 10, [Color("ff9a60"), Pal.JET], 5.0, 0.35, -3.0, 0.08)
	GustFX.boost_burst(global_position, move_dir if move_dir.length() > 0.1 else aim_dir)
	Sfx.play("dash", 0.05, -4.0)
	hover_v += 5.0
	squash_v -= 6.0
	if not Sfx.inst.muted:
		boost_snd.stream = Sfx.inst.streams.boost
		boost_snd.play()


## 적을 처치하면 부스터 게이지가 조금 찬다 (과열 해제는 게이지 갱신에서 BOOST_RESUME 기준으로 처리)
func gain_boost(amount := BOOST_KILL) -> void:
	if not alive:
		return
	boost =minf(1.0, boost + amount)


func _boost_end() -> void:
	# 착지: 살짝 눌리며 먼지
	squash_v += 8.0
	FX.shockwave(global_position, Color("7a7ac0"), 1.6, 0.25, 0.05)
	Sfx.play("land", 0.1, -8.0)


func _dash_start(chained := false) -> void:
	_combo_break()
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
	FX.afterimage(visual, Color(0.55, 0.85, 1.0, 0.5), 0.22)
	FX.sparks(global_position + Vector3(0, 0.15, 0), 12, [Color("9a9ad8"), Pal.CYAN], 6.0, 0.3, -5.0, 0.08)
	GustFX.dash_burst(global_position, dash_dir, _gust_tint())
	gust_from = global_position
	Sfx.play("roll", 0.08)
	Sfx.play("dash", 0.05, -6.0)
	Main.inst.kick(dash_dir * 0.8)
	Main.inst.camera.fov_punch(7.0)
	if chained:
		# 2단 대시 성공: 3초 안의 다음 검은 관통 일격 (칼날이 불타오른다)
		_arm_phantom()
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
	_combo_break()
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
	_arm_phantom()
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
	GustFX.dash_stop(global_position, dash_dir)


## 대시 기류가 머금는 빛: 평소 청록, 2단 대시는 무지개
func _gust_tint() -> Color:
	return _rainbow(0.45) if rainbow else Color("8ad8ff")


func _fire() -> void:
	var muzzle: Node3D = j.muzzle
	var origin := muzzle.global_position
	origin.y = global_position.y + 0.95
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
	Sfx.play("shoot", 0.08, -12.0)
	recoil = 1.0
	# 이전 반동이 남아 있어도 매 발 새로 세게 걷어찬다
	gun_kick = maxf(gun_kick, 0.25)
	gun_kick_v = maxf(gun_kick_v, 0.0) + KICK_IMPULSE * randf_range(0.9, 1.1)
	tilt_v -= d * 0.9
	motion.on_shot()
	var main := Main.inst
	main.kick(-d * 0.09)
	main.shake(0.05)


## 콤보 중 공중 사격 (탄창을 쓰지 않는다). last 면 마지막 발이라 더 세게 튕긴다.
func combo_shot(d: Vector3, last := false) -> void:
	var muzzle: Node3D = j.muzzle
	var origin := muzzle.global_position
	origin.y = global_position.y + 0.95 + minf(combo.lift(), 0.35)
	d = d.normalized().rotated(Vector3.UP, randf_range(-0.02, 0.02))
	Main.inst.add_bullet(Bullet.make_player(origin, d, BULLET_SPEED * 1.2))
	GunFX.muzzle(origin, d, 1.3)
	var out := Vector3.UP.cross(d).normalized()
	GunFX.eject(origin - d * 0.45 + out * 0.08, (out - d * 0.2).normalized(), d)
	var s := Sfx.play("shoot", 0.06, -8.0)
	if s:
		s.pitch_scale = randf_range(0.85, 0.95)
	recoil = 1.0
	gun_kick = maxf(gun_kick, 0.35)
	gun_kick_v = maxf(gun_kick_v, 0.0) + KICK_IMPULSE * 1.4
	tilt_v -= d * (3.0 if last else 1.5)
	Main.inst.kick(-d * 0.18)
	Main.inst.shake(0.1 if last else 0.06)
	if last:
		FX.shockwave(origin, Color("ffd070"), 1.2, 0.15, 0.04)


## 재장전 시작: 빈 탄창을 뽑는 소리와 함께 사격 팔을 내린다
func _begin_reload() -> void:
	if reload_t > 0.0 or mag >= MAG_SIZE:
		return
	reload_t = RELOAD_TIME
	motion.reload_begin()
	if Main.inst and Main.inst.capture_mode:
		print("RELOAD begin t=%.3f f=%d" % [Main.inst.time, Main.inst.capture_frame])
	var hud = Main.inst.hud if Main.inst else null
	if hud and mag <= 0:
		hud.popup("RELOAD", Color("ffd070"), global_position + Vector3(0, 2.2, 0))


func _finish_reload() -> void:
	reload_t = 0.0
	mag = MAG_SIZE
	Sfx.play("clank", 0.05, -9.0)
	Sfx.play("ready", 0.0, -6.0)


## 재장전 진행도 0~1 (재장전 중이 아니면 1)
func reload_k() -> float:
	return 1.0 - reload_t / RELOAD_TIME if reload_t > 0.0 else 1.0


func _fire_laser(k: float) -> void:
	var main := Main.inst
	var muzzle: Node3D = j.muzzle
	var origin := muzzle.global_position
	origin.y = global_position.y + 0.95
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
	motion.laser(k)
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


## 검 버튼: 관통 일격이 준비돼 있으면 그것을, 아니면 콤보를 잇는다 (SwordCombo 가 적중 여부로 연결을 판단)
func _slash() -> void:
	if phantom_ready and slash_cd <= 0.0 and not combo.committed():
		_combo_break()
		_phantom_start()
		return
	combo.press()


## 콤보를 즉시 끊는다: 떠 있던 높이는 부유 스프링이 이어받아 부드럽게 떨어진다
func _combo_break() -> void:
	var lf := combo.lift()
	if lf > 0.05:
		hover = maxf(hover, lf)
	combo.cancel(true)
	if tech:
		tech.abort()


## 콤보 한 타의 판정. dir 방향 부채꼴(cone 은 반각°) 안의 적을 베고 적탄을 지운다.
## 반환: hit 유효 적중 수 · blocked 장갑에 막힌 수 · killed 처치 수
func combo_strike(dir: Vector3, reach: float, cone_deg: float, dmg: int, kb: float, slam := false) -> Dictionary:
	var cone := deg_to_rad(cone_deg)
	var hit := 0
	var blocked := 0
	var killed := 0
	var yaw := atan2(-dir.x, -dir.z)
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var d := en.global_position - global_position
		if absf(d.y) > 1.6:
			continue                  # 높이가 크게 다른 적은 베지 못한다
		d.y = 0
		var l := d.length()
		if l < reach + en.radius and (l < 0.9 or dir.angle_to(d / maxf(l, 0.001)) <= cone):
			en.slash_yaw = yaw
			# 장갑 상태(구체 크롤러)에 막힌 검은 적중으로 치지 않는다 → 콤보가 끊긴다
			var guarded: bool = en.has_method("is_armored") and en.is_armored()
			var push := d.normalized() if slam and l > 0.2 else dir
			var k0 := en.knock
			en.take_hit(dmg, push, en.global_position, "slash")
			en.knock = k0 + (en.knock - k0) * kb
			if guarded:
				blocked += 1
				continue
			hit += 1
			if not en.alive:
				killed += 1
			else:
				# 베었지만 버틴 적: 칼날 불꽃이 튄다
				var hp_ := en.global_position + Vector3(0, 1.0, 0) - d.normalized() * en.radius * 0.6
				FX.sparks(hp_, 10, [Color.WHITE, Color(1.0, 0.5, 0.8), Pal.BLADE], 7.0, 0.25, -10.0, 0.06)
				FX.flash(hp_, Color(1.0, 0.75, 0.9), 0.45, 0.04)
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		if bl.unslashable:
			continue
		var d := bl.position - global_position
		d.y = 0
		if d.length() < reach + 0.3 and (d.length() < 0.8 or dir.angle_to(d.normalized()) <= cone):
			FX.flash(bl.position, Pal.BLADE, 0.45, 0.08)
			bl.queue_free()
	return {"hit": hit, "blocked": blocked, "killed": killed}


## 관통 일격 준비: PHANTOM_WINDOW 초 동안 칼날이 불타오르고, 그 안에 휘두르면 관통 일격이 나간다
func _arm_phantom() -> void:
	phantom_t = PHANTOM_WINDOW
	phantom_ready = true
	blade_fx.ignite()


## 관통 일격: 3프레임 만에 적을 꿰뚫고 뒤로 빠져나간 뒤 경로 위의 적을 한꺼번에 벤다
func _phantom_start() -> void:
	phantom_ready = false
	phantom_t = 0.0
	blade_fx.release()
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
	FX.flash(global_position + Vector3(0, 0.9, 0), Color(1.0, 0.8, 0.7), 1.2, 0.08)
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
				(en as Enemy).take_hit(PHANTOM_DMG, dir, (en as Enemy).global_position, "phantom")
		Main.inst.hitstop(0.12)
		Main.inst.shake(0.6)
		Main.inst.hud.screen_flash(Color(1.0, 0.8, 0.75), 0.35)
		if marked.size() > 1:
			# 여러 기를 한 번에 꿰뚫은 드문 순간만 컷인 타이포로 크게
			CutIn.slam("PIERCE ×%d" % marked.size(), "관통 일격", Color(1.0, 0.45, 0.35))
		else:
			Main.inst.hud.popup("PIERCE", Color(1.0, 0.55, 0.45), to + Vector3(0, 2.2, 0))
		Sfx.play("hit", 0.0, 2.0))


# ── 궁극기: 백팩 미사일 난사 ─────────────────────────────

## R 누름: 슬로우모션 + 줌아웃 + 락온 조준 시작
func _begin_ult_aim() -> void:
	_combo_break()
	ult_aiming = true
	ult_aim_start = Time.get_ticks_msec()
	_clear_locks()
	var main := Main.inst
	ult_ptr = main.get_viewport().get_mouse_position()
	if bot:
		ult_ptr = main.camera.screen_pos(global_position)
	ult_aim_w = _clamp_reach(main.screen_ground(ult_ptr, _ult_plane()))
	_ult_mouse_d = Vector2.ZERO
	if not bot:
		_ult_prev_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ult_raw = ult_ptr
	ult_snap = null
	_ult_ms = Time.get_ticks_msec()
	main.set_slowmo(ULT_SLOW)
	main.camera.set_ult_view(true)
	main.hud.ult_mode(true)
	FX.shockwave(global_position, Color("ff5a4a"), 5.0, 0.12, 0.05)
	Sfx.play("slowin", 0.0, -2.0)


func _input(event: InputEvent) -> void:
	if ult_aiming and event is InputEventMouseMotion:
		_ult_mouse_d += (event as InputEventMouseMotion).relative


## 락온 조준점이 놓이는 높이 (적 몸통 높이)
func _ult_plane() -> float:
	return view_y + 1.0


func _clamp_reach(p: Vector3) -> Vector3:
	var d := p - global_position
	d.y = 0.0
	if d.length() > ULT_REACH:
		d = d.normalized() * ULT_REACH
	return Vector3(global_position.x + d.x, _ult_plane(), global_position.z + d.z)


## 조준이 끝나면 마우스를 풀고, 커서를 조준점이 보이던 자리에 둔다
func _release_ult_mouse() -> void:
	if bot or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	Input.mouse_mode = _ult_prev_mouse
	Input.warp_mouse(ult_ptr)


## 궁극기 조준 또는 발사 준비동작 중 (다른 행동을 받지 않는다)
func ult_busy() -> bool:
	return ult_aiming or ult_winding()


func ult_winding() -> bool:
	return ult_windup_start >= 0


## 준비동작 진행도 0~1 (실제 시간)
func ult_windup_k() -> float:
	if ult_windup_start < 0:
		return 0.0
	return clampf((Time.get_ticks_msec() - ult_windup_start) / 1000.0 / ULT_WINDUP, 0.0, 1.0)


func ult_aim_left() -> float:
	return maxf(0.0, ULT_AIM_MAX - (Time.get_ticks_msec() - ult_aim_start) / 1000.0)


func _update_ult_aim() -> void:
	var main := Main.inst
	if not alive or main.state != Main.State.PLAY:
		_end_ult_aim(false)
		return
	var cam := main.camera
	var h := main.get_viewport().get_visible_rect().size.y
	var now := Time.get_ticks_msec()
	var rdt := clampf((now - _ult_ms) / 1000.0, 0.0, 0.1)
	_ult_ms = now
	if bot:
		ult_raw = main.bot_ult_pointer(self, ult_raw)
		ult_aim_w = _clamp_reach(main.screen_ground(ult_raw, _ult_plane()))
	else:
		# 마우스 이동량을 지금 화면에서의 조준점 위치에 더해 월드 조준점을 옮긴다
		var sp := cam.screen_pos(ult_aim_w) + _ult_mouse_d
		_ult_mouse_d = Vector2.ZERO
		# 거리로 묶지 않고 화면 안으로만 묶는다 (줌아웃으로 멀리 보이는 적까지 닿게)
		var vs := main.get_viewport().get_visible_rect().size
		var e := ULT_EDGE_PX * vs.y / 800.0
		sp = sp.clamp(Vector2(e, e), vs - Vector2(e, e))
		ult_aim_w = _clamp_reach(main.screen_ground(sp, _ult_plane()))
	ult_raw = cam.screen_pos(ult_aim_w)
	# 자석 조준: 마우스 근처(MAGNET_PX)의 아직 락온하지 않은 적 중 가장 가까운 적에게 조준점이 딱 달라붙는다.
	# 락온되면 다음 적으로 넘어가고, 근처에 남은 적이 없으면 조준점은 마우스로 돌아온다.
	var r := LOCK_PX * h / 800.0
	var mr := MAGNET_PX * h / 800.0
	var snap: Enemy = null
	var snap_sp := ult_raw
	var bd := mr
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed or locks.has(en) or locks.size() >= LOCK_MAX:
			continue
		var wp := en.global_position + Vector3(0, 1.0, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.screen_pos(wp)
		var d := sp.distance_to(ult_raw)
		if d < bd:
			bd = d
			snap = en
			snap_sp = sp
	if snap != ult_snap and snap != null:
		var tick := Sfx.play("tink", 0.0, -12.0)
		if tick:
			tick.pitch_scale = 2.2
	ult_snap = snap
	ult_ptr = ult_ptr.lerp(snap_sp, 1.0 - exp(-(48.0 if snap else 30.0) * rdt))
	# 조준점(또는 마우스)이 스치는 적을 락온
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed or locks.has(en) or locks.size() >= LOCK_MAX:
			continue
		var wp := en.global_position + Vector3(0, 1.0, 0)
		if cam.is_position_behind(wp):
			continue
		var sp := cam.screen_pos(wp)
		if sp.distance_to(ult_ptr) < r or sp.distance_to(ult_raw) < r:
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
	Main.inst.camera.lock_impact(en.global_position, locks.size())


func _clear_locks() -> void:
	for en in locks:
		if is_instance_valid(en):
			(en as Enemy).set_locked(false)
	locks.clear()
	lock_times.clear()
	ult_targets.clear()


## R 놓음(또는 2초 경과): 조준을 닫고 발사 준비동작에 들어간다. 슬로우모션·줌아웃은 준비동작이 끝날 때 함께 풀린다.
func _end_ult_aim(fire: bool) -> void:
	ult_aiming = false
	ult_snap = null
	_release_ult_mouse()
	var main := Main.inst
	main.hud.ult_mode(false)
	if not fire:
		main.set_slowmo(1.0)
		main.camera.set_ult_view(false)
		_clear_locks()
		return
	ult_targets = locks.duplicate()
	ult_windup_start = Time.get_ticks_msec()
	motion.windup()


## 준비동작: 끝으로 갈수록 슬로우모션을 풀어 준비동작이 끝나는 순간 정상 속도가 되고, 그때 발사한다
func _update_ult_windup() -> void:
	if not alive or Main.inst.state != Main.State.PLAY:
		_cancel_ult_windup()
		return
	var k := ult_windup_k()
	var main := Main.inst
	if k >= 1.0:
		ult_windup_start = -1
		main.set_slowmo(1.0)
		main.camera.set_ult_view(false)
		lock_clear_t = 1.2
		_fire_ult()
		return
	var u := clampf((k - 0.72) / 0.28, 0.0, 1.0)
	main.set_slowmo(lerpf(ULT_SLOW, 1.0, u * u))


func _cancel_ult_windup() -> void:
	ult_windup_start = -1
	Main.inst.set_slowmo(1.0)
	Main.inst.camera.set_ult_view(false)
	_clear_locks()


## 미사일 분배: 락온한 적마다 한 발씩(락온 순서대로, 가진 만큼만). 보스를 락온했으면 남은 미사일을 모두 보스에게 나눠 쏜다.
## 보스가 없으면 남은 미사일은 쏘지 않고 남긴다. 락온이 하나도 없으면 가진 미사일을 모두 주변 바닥에 흩뿌린다.
static func plan_ult(targets: Array, have: int) -> Array:
	var alive_t := []
	for en in targets:
		if is_instance_valid(en) and (en as Enemy).alive:
			alive_t.append(en)
	var plan := []
	if alive_t.is_empty():
		plan.resize(have)
		return plan
	var bosses := []
	for en in alive_t:
		if plan.size() >= have:
			break
		plan.append(en)
		if (en as Enemy).is_boss:
			bosses.append(en)
	var k := 0
	while not bosses.is_empty() and plan.size() < have:
		plan.append(bosses[k % bosses.size()])
		k += 1
	return plan


## 지금 R 을 놓으면 쏠 미사일 수 (HUD 미리보기)
func ult_shot_count() -> int:
	return plan_ult(locks, missiles).size()


func _fire_ult() -> void:
	ult_plan = plan_ult(ult_targets, missiles)
	ult_count = ult_plan.size()
	missiles -= ult_count
	ult_queue = ult_count
	ult_t = 0.0
	var main := Main.inst
	if not ult_targets.is_empty():
		main.hud.banner("LOCK x%d" % ult_targets.size(), Color("ff6a5a"), "")
	main.shake(0.45)
	main.hud.screen_flash(Color(1, 0.92, 0.8), 0.4)
	main.camera.fov_punch(7.0)
	main.kick(aim_dir * -0.4)
	squash_v += 12.0
	motion.salvo()
	FX.shockwave(global_position, Color("ffb050"), 3.5, 0.35)
	FX.ring(Vector3(global_position.x, Main.gy(global_position) + 0.3, global_position.z), 3.5, [Color("ffd060"), Color("ff7a30"), Color.WHITE], 0.35)
	Sfx.play("overload", 0.0, -2.0)


func _update_ult(dt: float) -> void:
	if ult_queue > 0:
		ult_t -= dt
		while ult_t <= 0.0 and ult_queue > 0:
			ult_t += 0.035
			_launch_missile(ult_count - ult_queue)
			ult_queue -= 1
			Main.inst.hud.ammo_spent("missile", 1)


func _launch_missile(i: int) -> void:
	var jet: Node3D = j.jet_l if i % 2 == 0 else j.jet_r
	var origin := jet.global_position + Vector3(0, 0.2, 0)
	# 분배 계획(plan_ult)대로 유도한다. 목표가 없으면 자동 조준 없이 주변 바닥에 흩뿌려진다.
	var m := Missile.new()
	var en: Variant = ult_plan[i] if i < ult_plan.size() else null
	if is_instance_valid(en) and (en as Enemy).alive:
		m.target = en as Enemy
	else:
		m.target_pos = _stray_spot()
	# 흩날리듯 사방으로 퍼져 올라간다
	var a2 := TAU * float(i) / maxi(ult_count, 1) + randf_range(-0.2, 0.2)
	var out := Vector3(cos(a2), 0, sin(a2))
	m.vel = out * randf_range(5.0, 9.0) + Vector3(0, randf_range(6.0, 10.0), 0) - aim_dir * 1.5
	FX.root.add_child(m)
	m.global_position = origin
	FX.flash(origin, Color("ffd080"), 0.35, 0.05)
	if i % 3 == 0:
		Sfx.play("eshot", 0.2, -8.0)
	recoil = 0.6
	motion.salvo_kick()
	tilt_v += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 2.5


## 조준하지 못한 미사일이 떨어질 주변 바닥 지점 (벽 안은 피한다)
func _stray_spot() -> Vector3:
	var p := global_position
	for _k in 6:
		var a := randf() * TAU
		p = global_position + Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 9.0)
		p.y = global_position.y
		if not Main.inst.is_blocked(p):
			break
	p.y = Main.gy(p)
	return p


# ── 한정 재화: 에너지 · 미사일 ───────────────────────────

## 지금 에너지로 모을 수 있는 최대 충전량. 다음 단계 문턱 바로 아래에서 멈춘다.
func charge_cap() -> float:
	if energy >= 3:
		return 1.0
	if energy <= 0:
		return 0.0
	return CHARGE_STAGES[energy] - 0.001


## 이 충전량으로 쏘는 레이저의 에너지 비용 (최소 발사 단계 1칸 ~ 최대 3칸)
static func laser_cost(k: float) -> int:
	var st := 0
	for th in CHARGE_STAGES:
		if k >= th:
			st += 1
	return clampi(st, 1, 3)


func _spend_energy(n: int) -> void:
	n = mini(n, energy)
	if n <= 0:
		return
	energy -= n
	Main.inst.hud.ammo_spent("energy", n)


func _regen_energy(dt: float) -> void:
	if energy >= ENERGY_MAX:
		energy_regen_t = 0.0
		return
	energy_regen_t += dt
	if energy_regen_t >= ENERGY_REGEN:
		energy_regen_t = 0.0
		gain("energy", 1)


## 에너지 재충전까지 진행도 (HUD 표시용, 0~1)
func energy_regen_k() -> float:
	return 0.0 if energy >= ENERGY_MAX else energy_regen_t / ENERGY_REGEN


## 재화 획득. 실제로 늘어난 개수를 돌려준다 (가득 차 있으면 0).
func gain(kind: String, n: int) -> int:
	var got := 0
	match kind:
		"energy":
			got = mini(n, ENERGY_MAX - energy)
			energy += got
		"missile":
			got = mini(n, MISSILE_MAX - missiles)
			missiles += got
	if got > 0:
		Main.inst.hud.ammo_gained(kind, got)
	return got


func is_full(kind: String) -> bool:
	return energy >= ENERGY_MAX if kind == "energy" else missiles >= MISSILE_MAX


var _deny_t := 0
## 재화가 없어 못 쓸 때: 짧은 경고 (연타해도 한 번씩만)
func _deny(text: String, kind: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _deny_t < 700:
		return
	_deny_t = now
	FX.fizzle((j.muzzle as Node3D).global_position)
	var ping := Sfx.play("tink", 0.0, -4.0)
	if ping:
		ping.pitch_scale = 0.6
	Main.inst.hud.ammo_denied(kind)
	Main.inst.hud.popup(text, Color("ff5a6a"), global_position + Vector3(0, 2.2, 0))


# ── 최대 충전 지속 레이저 ────────────────────────────────

func _start_mega() -> void:
	_combo_break()
	mega_t = MEGA_TIME
	mega_yaw = atan2(-aim_dir.x, -aim_dir.z)
	mega_tick = 0.0
	mega_node = MegaBeam.new()
	FX.root.add_child(mega_node)
	var main := Main.inst
	var origin: Vector3 = (j.muzzle as Node3D).global_position
	origin.y = global_position.y + 0.95
	ImpactFrame.inst.mega(origin, aim_dir)
	main.dramatic(true)
	main.shake(0.6)
	main.hitstop(ImpactFrame.inst.duration("mega") + 0.05)
	main.camera.fov_punch(9.0)
	FX.shockwave(global_position, Pal.CYAN, 4.0, 0.4)
	FX.ring(Vector3(global_position.x, Main.gy(global_position) + 0.3, global_position.z), 5.0, Pal.RING_CYAN, 0.45)
	Sfx.play("laser", 0.0, 2.0)
	squash_v -= 8.0
	# 컷인 타이포는 흑백 임팩트 프레임이 끝난 뒤에 들어온다 (CutIn 이 알아서 미룬다)
	CutIn.slam("FULL BURST", "최대 출력 지속 레이저", Pal.CYAN)
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
	origin.y = global_position.y + 0.95
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
	_combo_break()
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
	_combo_break()
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
	_combo_break()
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
	if ult_winding():
		_cancel_ult_windup()
	if mega_t > 0.0:
		_end_mega()
	charge_fx.end()
	boost_snd.stop()
	blade_fx.visible = false
	combo.cancel(true)
	tech.abort()
	trail.visible = false
	for bt in body_trails:
		bt.visible = false
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
	var m: Material = Pal.flash() if on else null
	for mi: MeshInstance3D in FX.mesh_parts(visual):
		mi.material_overlay = m


# ── 애니메이션 ──────────────────────────────────────────

func _animate(dt: float) -> void:
	var legs: Node3D = j.legs
	var upper: Node3D = j.upper
	var torso: Node3D = j.torso
	var hv := Vector3(velocity.x, 0, velocity.z)
	var spd := hv.length()
	var aim_yaw := mega_yaw if mega_t > 0.0 else atan2(-aim_dir.x, -aim_dir.z)
	var t := Time.get_ticks_msec() * 0.001
	motion.pre()                   # 지난 틱에 덧입힌 동작 연출 오프셋을 걷어 낸다

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
	var mech: bool = j.get("mech", false)
	if not mech:
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
		# 초고속 회피: 첫 2프레임은 몸이 사라지고 출발 자리 잔상만 남는다 (순간이동처럼 보인다)
		visual.visible = dash_t < DASH_TIME - 2.0 / 60.0
		trail.feed(dt, [])
		_feed_body_trails(dt)
		return
	else:
		# 회피 직후: 기울였던 자세를 빠르게 되돌림
		visual.basis = visual.basis.orthonormalized().slerp(Basis.IDENTITY, 1.0 - exp(-25.0 * dt))
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
	elif airborne:
		# 점프: 오를 때는 무릎을 당겨 몸을 웅크리고, 떨어질 때는 다리를 뻗어 착지를 준비한다
		var up := clampf(vy / JUMP_V, -1.0, 1.0)
		var tuck := clampf(up, 0.0, 1.0)
		hl.rotation.x = lerpf(hl.rotation.x, lerpf(0.25, 0.9, tuck), 0.3)
		hr.rotation.x = lerpf(hr.rotation.x, lerpf(-0.1, 0.35, tuck), 0.3)
		kl.rotation.x = lerpf(kl.rotation.x, lerpf(-0.35, -1.3, tuck), 0.3)
		kr.rotation.x = lerpf(kr.rotation.x, lerpf(-0.2, -0.8, tuck), 0.3)
		upper.position.y = 0.74 + tuck * 0.04
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
	if mech:
		# 새 메카는 원형 부피를 지키려고 비균일 찌그러짐 대신 상체가 골반 위로 눌렸다 튀어 오른다
		upper.position.y += sq * 0.3

	# 사격 팔 반동 · 충전 자세
	recoil = move_toward(recoil, 0.0, dt * 10.0)
	laser_recoil = maxf(0.0, laser_recoil - dt)
	var arm_l: Node3D = j.arm_l
	var shake_arm := sin(t * 70.0) * 0.03 * charge if charging else 0.0
	# 반동 스프링 (반암시적 오일러: 빠른 스프링도 안정적)
	gun_kick_v += (-KICK_STIFF * gun_kick - KICK_DAMP * gun_kick_v) * dt
	gun_kick += gun_kick_v * dt
	gun_kick = clampf(gun_kick, -0.45, 1.3)
	var kick_back := maxf(gun_kick, 0.0)
	if _arm_l_rest == Vector3.INF:
		_arm_l_rest = arm_l.position
	arm_l.position = _arm_l_rest + Vector3(0, kick_back * 0.05, recoil * 0.06 + gun_kick * 0.2)
	arm_l.rotation.x = recoil * 0.08 + kick_back * 0.42 + minf(gun_kick, 0.0) * 0.15 + shake_arm
	arm_l.rotation.y = shake_arm
	# 재장전 동작은 PlayerMotion 이 덧입힌다
	# 어깨 반동: 팔이 달린 어깨 장갑도 함께 뒤로 밀리며 들렸다가 스프링으로 돌아온다
	var sh_l = j.get("shoulder_l")
	if sh_l:
		var shn := sh_l as Node3D
		if _sh_l_rest == Vector3.INF:
			_sh_l_rest = shn.position
		shn.position = _sh_l_rest + Vector3(kick_back * 0.025, kick_back * 0.045, recoil * 0.05 + gun_kick * 0.13)
		shn.rotation.x = kick_back * 0.22 + minf(gun_kick, 0.0) * 0.08
		shn.rotation.y = -kick_back * 0.18
		shn.rotation.z = -kick_back * 0.12
	var torso_pitch := -0.1 * clampf(spd / SPEED, 0.0, 1.0)
	if charging:
		torso_pitch = 0.12 * charge   # 뒤로 버티는 자세
	if mega_t > 0.0:
		torso_pitch = 0.2 + sin(t * 60.0) * 0.03
		arm_l.rotation.x = sin(t * 80.0) * 0.05
	torso_pitch += recoil * 0.06 + gun_kick * 0.08
	torso.rotation.x = lerpf(torso.rotation.x, torso_pitch, 0.25)

	# 검 휘두르기: 오른쪽 → 왼쪽
	var blade: Node3D = j.blade
	var arm_r: Node3D = j.arm_r
	var combo_pose := combo.posing() and lunge_t <= 0.0 and slash_anim <= 0.0
	if combo_pose:
		pass                      # 콤보 자세는 아래에서 마지막에 덮어쓴다
	elif lunge_t > 0.0:
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
		blade.scale = blade.scale.lerp(Vector3.ONE, 0.3)
		torso.rotation.y = lerpf(torso.rotation.y, 0.0, 0.25)

	_animate_jets(dt, maxf(1.0 if boosting else 0.0, tech.jet_k()))
	motion.post(dt)
	# 검술 콤보: 관절·높이·몸 기울기를 콤보 자세로 덮고, 스윙 사이 칼 위치를 잔상에 넘긴다
	trail.tint = blade_fx.flame_k
	if combo_pose:
		combo.pose(dt)
	elif tech.posing():
		tech.pose(dt)          # 기 모으기 · 돌진 자세 (광선검 잔상도 여기서 먹인다)
	else:
		trail.boost = 1.0 if slash_anim > 0.0 or lunge_t > 0.0 else 0.0
		trail.feed(dt, [])
	if gimmick_pose.is_valid():
		gimmick_pose.call(self, dt)    # 기믹 자세 (레버 돌리기)
	if mech:
		MechPlayer.settle(j)
	_feed_body_trails(dt)

	# 피격 무적 깜빡임 (회피 무적은 잔상으로 표현)
	visual.visible = not (hurt_t > 0.0 and fmod(hurt_t, 0.12) < 0.05)
	if combo.blur():
		# 회전 베기: 눈에 보이지 않는 속도 — 몸은 한 틱 걸러 사라지고 잔상만 남는다
		visual.visible = Engine.get_physics_frames() % 2 == 0
	_animate_ring(dt)


## 팔·다리 리본: 대시(드릴 회전) 중이거나 돌진 중일 때만 보인다
func _feed_body_trails(dt: float) -> void:
	var on := dash_t > 0.0 or rushing or lunge_t > 0.0 or combo.ph == SwordCombo.Ph.LUNGE or tech.rushing()
	# 대시 회전·돌진은 몸 톤 리본만: 광선검의 분홍 초승달은 끈다 (자세를 잡는 칼이 궤적을 어지럽히지 않게)
	trail.active = (not on or tech.whirl()) and not tech.charging()     # 최대 돌진은 광선검 회오리 잔상을 남긴다
	for bt in body_trails:
		bt.active = on
		bt.feed(dt, [])


## 돌진(콤보 파고들기·관통 일격) 중 강철 발이 바닥을 긁는다: 마찰 불꽃 + 달아오른 쇳자국. 멈추면 제동 불꽃.
func _update_rush() -> void:
	var now := (lunge_t > 0.0 or combo.ph == SwordCombo.Ph.LUNGE or motion.sliding() or (tech.rushing() and not tech.whirl())) and not airborne
	var feet := []
	for ft in [j.foot_l, j.foot_r]:
		var f := (ft as Node3D).to_global(Vector3(0, -0.12, -0.05))
		feet.append(Vector3(f.x, Main.gy(f), f.z))
	if now and not rushing:
		rush_feet = feet
		FX.flash(global_position + Vector3(0, 0.1, 0), Color(1.0, 0.75, 0.4), 0.4, 0.04)
	elif now:
		var k := 1.4 if lunge_phantom else 1.0
		for i in 2:
			RushFX.scrape(rush_feet[i], feet[i], k)
			RushFX.heat(rush_feet[i], feet[i])
		rush_feet = feet
	elif rushing:
		for i in 2:
			RushFX.heat(rush_feet[i], feet[i])
		var d := velocity if velocity.length() > 0.1 else aim_dir
		RushFX.brake(global_position, d)
	rushing = now


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
				GustFX.boost_wash(n.global_position, velocity)
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
