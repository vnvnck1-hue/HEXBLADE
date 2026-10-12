class_name PlayerEntrance
extends RefCounted
## 플레이어 등장 연출 (모든 전투 씬 공통): 화면 아래 밖에서 고속으로 날아 들어와
## 브레이크 턴(몸을 뒤로 홱 돌려 등 부스터를 진행 방향으로 뿜어 제동)하고 쿵 착지한다.
##
## 판정 위치(Player.global_position)는 처음부터 착지 자리에 두고 몸(visual)만 오프셋으로 날린다.
## → 카메라 · 적 · 충돌 · 맵 배치는 그대로, 연출만 얹힌다. 동안은 조작 잠금(cine_lock) + 무적.
## 끄기: --entrance=off 또는 PlayerEntrance.enabled = false.
## 테스트(-s 스크립트)와 쇼케이스 모드에선 저절로 꺼진다 (--entrance=on 이면 강제로 켬).

static var enabled := true
static var force := false     # 검사용: 테스트(-s)에서도 켠다

const ARRIVE := 0.8        # 착지까지 (게임 시간, 초)
const TURN_A := 0.36       # 브레이크 턴 시작
const TURN_B := 0.68       # 브레이크 턴 끝 (몸이 반 바퀴 돈다)
const TOTAL := 1.1         # 착지 뒤 자세를 추스르고 조작을 돌려준다
const HEIGHT := 2.6        # 날아 들어오는 높이 (m)
const SIDE := 0.3          # 옆으로 비껴 들어오는 비율 (거리 대비)
const MARGIN := 2.5        # 화면 밖 판정 뒤 더 물러서는 거리 (m)

var p: Player
var t := -1.0              # -1 = 아직 시작 전
var done := false
var side := 1.0
var start := Vector3.ZERO  # 착지 자리 기준 시작 오프셋 (월드 방향)
var off := Vector3.ZERO
var vel := Vector3.ZERO
var vdir := Vector3.FORWARD
var heading := 0.0
var turn_from := 0.0
var turn_sign := 1.0
var _ghost_t := 0.0
var _prev_w := Vector3.ZERO
var _braked := false
var _landed := false
var _lock_before := false


static func wanted() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--entrance=off"):
		return false
	if args.has("--entrance=on") or force:
		return true
	if not enabled:
		return false
	var raw := OS.get_cmdline_args()
	if raw.has("-s") or raw.has("--script"):
		return false
	if Main.inst and Main.inst.get("showcase"):
		return false
	return true


## Player._ready 끝에서 부른다. 연출을 안 하면 null.
static func make(player: Player) -> PlayerEntrance:
	if not wanted():
		return null
	var e := PlayerEntrance.new()
	e.p = player
	e._lock_before = player.cine_lock
	player.cine_lock = true
	player.visual.visible = false       # 첫 물리 틱 전 화면에 착지 자리의 몸이 비치지 않게
	return e


func active() -> bool:
	return not done


## 부스터 불꽃 세기 (Player._animate_jets 에 넘긴다). 브레이크 턴 때 가장 크게 뿜는다.
func jet() -> float:
	if done or t < 0.0:
		return 1.0 if not done else 0.0
	if t < TURN_A:
		return 1.0
	if t < ARRIVE:
		var k := (t - TURN_A) / (ARRIVE - TURN_A)
		return 1.0 + 1.3 * sin(PI * minf(k * 1.3, 1.0))
	return maxf(0.0, 1.0 - (t - ARRIVE) / 0.15)


## Player._animate 끝 (자세 덮어쓰기 차례)에서 매 틱 부른다
func pose(dt: float) -> void:
	if done:
		return
	if t < 0.0:
		_begin()
		t = 0.0
	else:
		t += dt
	var u := clampf(t / ARRIVE, 0.0, 1.0)
	var a := 1.0 - u
	# 화면 아래 성분은 빠르게(a³), 옆 성분은 천천히(a²) 줄어 비스듬히 휘어 들어온다
	off = _offset_at(a)
	vel = -_split_vel(a) / ARRIVE        # 해석 미분 (진행 속도)
	p.invuln = maxf(p.invuln, 0.2)
	var vh := Vector3(vel.x, 0, vel.z)
	if vh.length() > 1.0:
		vdir = vh.normalized()

	# ── 몸 방향 (yaw) ──
	if t < TURN_A:
		heading = atan2(-vdir.x, -vdir.z)
		turn_from = heading
	elif t < TURN_B:
		var k := (t - TURN_A) / (TURN_B - TURN_A)
		var e := 4.0 * k * k * k if k < 0.5 else 1.0 - pow(-2.0 * k + 2.0, 3.0) * 0.5
		heading = turn_from + turn_sign * PI * e
	else:
		heading = turn_from + turn_sign * PI
	if t >= TURN_A and not _braked:
		_braked = true
		_brake_fx()

	# ── 기울기: 날 땐 진행 방향으로 숙이고, 턴부터는 진행 반대로 버티며 크게 옆으로 눕는다 ──
	var back := smoothstep(TURN_A - 0.04, TURN_A + 0.1, t)
	var settle := 1.0 - smoothstep(ARRIVE - 0.06, TOTAL, t)
	var lean := lerpf(0.55, -0.7, back) * settle
	var tk := clampf((t - TURN_A) / (TURN_B - TURN_A), 0.0, 1.0)
	var roll := turn_sign * 0.95 * sin(PI * tk)
	var right := Basis(Vector3.UP, heading) * Vector3.RIGHT
	var tilt := vdir * lean + right * roll
	var n := (Vector3.UP + tilt).normalized()
	var axis := Vector3.UP.cross(n)
	p.visual.basis = Basis(axis.normalized(), Vector3.UP.angle_to(n)) if axis.length() > 0.0001 else Basis.IDENTITY
	p.lean.basis = Basis.IDENTITY

	# ── 위치: 판정은 그대로, 몸만 날린다 ──
	var crouch := 0.0
	if t > ARRIVE:
		crouch = sin(PI * clampf((t - ARRIVE) / (TOTAL - ARRIVE), 0.0, 1.0)) * 0.22
	p.visual.position = Vector3(off.x, Player.PIVOT_Y + p.hover + off.y - crouch, off.z)
	p.shadow.position.x = off.x
	p.shadow.position.z = off.z
	p.dodge_ring.visible = false

	# ── 팔다리 ──
	var j := p.j
	var hand := 1.0 - smoothstep(ARRIVE, TOTAL, t)
	var aim_yaw := atan2(-p.aim_dir.x, -p.aim_dir.z)
	var turn_to := smoothstep(ARRIVE, TOTAL, t)
	(j.legs as Node3D).rotation.y = lerp_angle(heading, aim_yaw, turn_to * 0.5)
	(j.upper as Node3D).rotation.y = lerp_angle(heading + turn_sign * 0.35 * sin(PI * tk), aim_yaw, turn_to)
	var fly := 1.0 - smoothstep(ARRIVE - 0.12, ARRIVE, t)
	var land_k := sin(PI * clampf((t - ARRIVE) / (TOTAL - ARRIVE), 0.0, 1.0))
	var hl := j.hip_l as Node3D
	var hr := j.hip_r as Node3D
	var kl := j.knee_l as Node3D
	var kr := j.knee_r as Node3D
	var dangle := sin(t * 30.0) * 0.08
	hl.rotation.x = lerpf(0.0, 0.7 + dangle, fly) + land_k * 0.75
	hr.rotation.x = lerpf(0.0, 0.5 - dangle, fly) + land_k * 0.55
	kl.rotation.x = lerpf(0.0, -1.15, fly) - land_k * 1.25
	kr.rotation.x = lerpf(0.0, -1.3, fly) - land_k * 1.0
	# 검을 뒤로 끌어 당긴 돌진 자세 → 착지하며 풀린다
	var arm_r := j.arm_r as Node3D
	arm_r.rotation.y = -1.4 * hand
	arm_r.rotation.x = -0.5 * hand
	(j.torso as Node3D).rotation.y = -0.6 * hand
	(j.torso as Node3D).rotation.x = lerpf(-0.25, 0.2, back) * hand

	_trail_fx(dt)
	if t >= ARRIVE and not _landed:
		_landed = true
		_land_fx()
	if t >= TOTAL:
		_finish()


# ── 내부 ─────────────────────────────────────────────

## 카메라에서 본 화면 아래 방향 (수평). 카메라가 없으면 +Z.
func _down_dir() -> Vector3:
	var cam := p.get_viewport().get_camera_3d() if p.is_inside_tree() else null
	if cam == null:
		return Vector3.BACK
	var f := -cam.global_basis.z
	f.y = 0.0
	return -f.normalized() if f.length() > 0.01 else Vector3.BACK


## 시작 오프셋을 "화면 아래 성분 · 옆 성분 · 높이"로 나눠 각자 다른 속도로 줄인다
var _down := Vector3.BACK
var _side := Vector3.RIGHT
var _d_amt := 16.0
var _s_amt := 0.0


func _split_vel(a: float) -> Vector3:
	return _down * (_d_amt * 3.0 * a * a) + _side * (_s_amt * 2.0 * a) + Vector3.UP * (HEIGHT * 2.0 * a)


func _offset_at(a: float) -> Vector3:
	return _down * (_d_amt * a * a * a) + _side * (_s_amt * a * a) + Vector3.UP * (HEIGHT * a * a)


func _begin() -> void:
	side = -1.0 if randf() < 0.5 else 1.0
	turn_sign = side
	_down = _down_dir()
	_side = Vector3.UP.cross(_down).normalized()
	_d_amt = _offscreen_distance()
	_s_amt = side * _d_amt * SIDE
	start = _offset_at(1.0)
	_prev_w = p.global_position + start
	var sp := Sfx.play("dash", 0.0, -2.0)
	if sp:
		sp.pitch_scale = 0.7
	if not Sfx.inst.muted:
		p.boost_snd.stream = Sfx.inst.streams.boost
		p.boost_snd.play()
		p.boost_snd.volume_db = -9.0


## 몸 전체(발끝~머리)가 화면 아래 밖에 있게 되는 최소 거리 + 여유
func _offscreen_distance() -> float:
	var cam := p.get_viewport().get_camera_3d()
	if cam == null:
		return 16.0
	var vp := p.get_viewport().get_visible_rect().size
	var base := p.global_position
	for i in 90:
		var d := 4.0 + i * 0.5
		var o := _down * d + _side * (side * d * SIDE) + Vector3.UP * HEIGHT
		var ok := true
		for h in [-0.3, 0.9, 2.2]:
			if not _offscreen(cam, base + o + Vector3(0, h, 0), vp):
				ok = false
				break
		if ok:
			return d + MARGIN
	return 4.0 + 90 * 0.5


static func _offscreen(cam: Camera3D, w: Vector3, vp: Vector2) -> bool:
	if cam.is_position_behind(w):
		return true
	var s := cam.unproject_position(w)
	return s.y > vp.y + 24.0 or s.x < -24.0 or s.x > vp.x + 24.0


func _trail_fx(dt: float) -> void:
	var w := p.visual.global_position
	if t < ARRIVE - 0.05:
		_ghost_t -= dt
		if _ghost_t <= 0.0:
			_ghost_t = 0.06
			FX.afterimage(p.visual, Color(0.55, 0.85, 1.0, 0.26), 0.09)
		GustFX.dash_trail(_prev_w, w, Pal.CYAN, 1.3)
	if t >= TURN_A and t < ARRIVE:
		# 제동 분사: 등 부스터가 진행 방향으로 불꽃을 뿜는다
		for jet: Node3D in [p.j.jet_l, p.j.jet_r]:
			if randf() < 0.6:
				FX.sparks(jet.global_position, 2, [Pal.JET_CORE, Pal.JET], 7.0, 0.22, -6.0, 0.06)
	_prev_w = w


func _brake_fx() -> void:
	var w := p.visual.global_position
	Sfx.play("dash", 0.05, -1.0)
	FX.flash(w, Color(1.0, 0.8, 0.5), 1.0, 0.07)
	FX.sparks(w, 16, [Pal.JET_CORE, Pal.JET, Color.WHITE], 9.0, 0.35, -8.0, 0.08)
	GustFX.boost_burst(Vector3(w.x, p.global_position.y, w.z), vdir)
	if Main.inst and Main.inst.camera:
		Main.inst.camera.fov_punch(2.0)


func _land_fx() -> void:
	var gp := p.global_position
	var ground := Vector3(gp.x, p.gy, gp.z)
	p.jump_fx.land(ground, 11.0)
	FX.shockwave(ground, Pal.CYAN, 3.4, 0.4)
	FX.sparks(ground + Vector3(0, 0.1, 0), 12, [Color("ff9a60"), Pal.JET, Color.WHITE], 6.0, 0.4, -12.0, 0.07)
	RushFX.brake(gp, vdir)
	Sfx.play("land", 0.0, -1.0)
	p.squash_v -= 13.0
	if Main.inst:
		Main.inst.shake(0.2)
		if Main.inst.camera:
			Main.inst.camera.fov_punch(3.0)


func _finish() -> void:
	done = true
	p.cine_lock = _lock_before
	p.visual.position.x = 0.0
	p.visual.position.z = 0.0
	p.shadow.position.x = 0.0
	p.shadow.position.z = 0.0
	p.dodge_ring.visible = true
	p.invuln = maxf(p.invuln, 0.3)
