class_name DashWhirl
extends RefCounted
## 2단 대시 성공 → 휠윈드 장전 (충전식). Player 가 소유하고 arm → start → update → pose 순으로 부른다.
##
## 2단 대시를 제때 누르면 무지개 2단 대시가 나가며 ARM_WINDOW 초 동안 칼날이 불타오른다(장전).
## 그 안에 검을 누르면 광선검을 옆으로 펼친 채 드론 합체 휠윈드와 같은 빠르기(초당 TURN_RATE 바퀴)로 TURNS 바퀴 회전한다.
## 도는 동안 대시처럼 TRAVEL m(대시 한 번 거리)를 미끄러져 나가며(처음 빠르고 끝에서 감속) 한 바퀴마다 둘레 R 안 적을 벤다. 무적.
## 방향은 이동키 쪽(없으면 조준 쪽)이고, 도는 중에도 이동키로 STEER rad/s 만큼 꺾을 수 있다.
## 공격 · 사격 · 충전은 막히고, 대시로 끊을 수 있다.

const TURNS := 5                # 회전 수 (= 적 한 마리가 맞는 최대 횟수)
const TURN_RATE := 12.0         # 초당 바퀴 수 — 드론 합체 휠윈드(PartnerDrone.WHIRL_TURNS)와 같다
const TIME := TURNS / TURN_RATE # 전체 시간 (약 0.42초)
const ARM_WINDOW := 3.0         # 2단 대시 성공 후 휠윈드를 쓸 수 있는 시간
const R := 2.7                  # 칼날 반경
const DMG := 3
# 이동: 대시(Player.DASH_SPEED · DASH_TIME, 속도 1.25 → 0.55 배 감속)와 같은 거리 · 같은 감속 모양
const TRAVEL := Player.DASH_SPEED * Player.DASH_TIME * 0.9    # 약 4.6m
const STEER := 6.0             # 도는 중 이동키로 진행 방향을 꺾는 빠르기 (rad/s)
const LIFE := 0.24              # 회전 중 광선검 리본 수명 · 폭 (드론 휠윈드와 같은 원반)
const REACH := 1.25
const COL := Color("ff8ad0")

var p: Player
var t := -1.0                   # 경과 (-1 = 아님)
var ang := 0.0
var turns_done := 0
var whirls := 0                 # 확인용: 시작 횟수 · 마지막 휠윈드의 총 적중 수
var hits := 0
var _prev := 0.0
var _keep: Array = []
var _fx := 0.0
var _ghost := 0
var _a0 := 0.0
var armed_t := 0.0             # 장전 남은 시간 (0 이면 장전 안 됨)
var dir := Vector3.FORWARD     # 진행 방향


func _init(owner: Player) -> void:
	p = owner


func active() -> bool:
	return t >= 0.0


func armed() -> bool:
	return armed_t > 0.0


## 2단 대시 성공: 장전 (칼날이 불타오른다)
func arm() -> void:
	armed_t = ARM_WINDOW
	p.blade_fx.ignite()


## 장전을 쓰지 않고 끝낸다
func disarm() -> void:
	if armed_t <= 0.0:
		return
	armed_t = 0.0
	if not p.phantom_ready:
		p.blade_fx.douse()


func start() -> void:
	if active():
		stop(false)
	armed_t = 0.0
	p.blade_fx.release()
	var md := p.move_dir
	md.y = 0
	dir = md.normalized() if md.length() > 0.1 else p.aim_dir
	t = 0.0
	turns_done = 0
	hits = 0
	whirls += 1
	ang = atan2(-p.aim_dir.x, -p.aim_dir.z)
	_prev = ang
	_a0 = ang
	_keep = [p.trail.life, p.trail.reach, p.trail.bright]
	p.trail.life = LIFE
	p.trail.reach = REACH
	p.trail.bright = 1.0
	p.trail.boost = 1.0
	p.invuln = maxf(p.invuln, TIME + 0.05)
	var main := Main.inst
	var c := p.global_position + Vector3(0, 0.95, 0)
	FX.flash(c, Color(1.0, 0.85, 0.95), 2.0, 0.1)
	FX.shockwave(p.global_position, COL, 4.2, 0.35, 0.1)
	FX.shockwave(p.global_position, Color.WHITE, 2.6, 0.22)
	FX.sparks(c, 20, [Color.WHITE, COL, Pal.BLADE], 9.0, 0.4, -6.0, 0.07)
	Distortion.burst(c, 2.6, 0.28, 1.1)
	Sfx.play("roll", 0.0, 0.0)
	main.camera.fov_punch(7.0)
	main.shake(0.3)


## 끝 · 끊김. finish 면 마무리 참격
func stop(finish := true) -> void:
	if not active():
		return
	t = -1.0
	if _keep.size() == 3:
		p.trail.life = _keep[0]
		p.trail.reach = _keep[1]
		p.trail.bright = _keep[2]
	_keep = []
	p.trail.boost = 0.0
	p.visual.basis = Basis.IDENTITY
	var yaw := atan2(-p.aim_dir.x, -p.aim_dir.z)
	(p.j.upper as Node3D).rotation.y = yaw
	(p.j.legs as Node3D).rotation.y = yaw
	if finish:
		FX.slash(p, ang, 3)
		FX.shockwave(p.global_position, COL, 3.4, 0.3)
		Main.inst.camera.fov_punch(4.0)
		p.squash_v -= 6.0


## 이번 틱 이동 속도: 대시처럼 처음 빠르고 끝에서 감속하며 TIME 동안 TRAVEL 만큼 간다
func velocity(dt: float) -> Vector3:
	var md := p.move_dir
	md.y = 0
	if md.length() > 0.1:
		var want := md.normalized()
		var ang_to := dir.signed_angle_to(want, Vector3.UP)
		dir = dir.rotated(Vector3.UP, clampf(ang_to, -STEER * dt, STEER * dt)).normalized()
	var k := clampf(t / TIME, 0.0, 1.0)
	return dir * (TRAVEL / TIME) * lerpf(1.25, 0.55, k) / 0.9 * p.slow_mul


func update(dt: float) -> void:
	if armed_t > 0.0:
		armed_t -= dt
		if armed_t <= 0.0:
			armed_t = 0.01
			disarm()
	if not active():
		return
	t += dt
	var main := Main.inst
	var k := clampf(t / TIME, 0.0, 1.0)
	# 처음엔 빠르게 감겨 들어가고 끝에서 살짝 풀린다: 회전 각은 정확히 TURNS 바퀴
	var e := k * (2.0 - k) * 0.35 + k * 0.65
	ang = _a0 + e * TAU * TURNS
	# 한 바퀴마다 둘레를 벤다
	var now_turn := int(e * TURNS + 0.001)
	while turns_done < mini(now_turn, TURNS):
		turns_done += 1
		_cut()
	_fx -= dt
	if _fx <= 0.0:
		_fx = 0.06
		var c := p.global_position + Vector3(0, randf_range(0.5, 1.3), 0)
		FX.vortex(c, Basis(Vector3.UP, ang) * Basis.from_scale(Vector3.ONE * randf_range(1.5, 2.1)), COL if randf() < 0.5 else Pal.BLADE)
		FX.puffs(Vector3(p.global_position.x, Main.gy(p.global_position) + 0.05, p.global_position.z), 1,
			[Color(0.55, 0.6, 0.75), Color(0.45, 0.5, 0.65), Color(0.2, 0.22, 0.32), Color(0.16, 0.18, 0.28)], 1.0, 0.35, 0.45)
		main.shake(0.04)
	_ghost -= 1
	if _ghost <= 0:
		_ghost = 3
		FX.afterimage(p.visual, Color(1.0, 0.6, 0.85, 0.28), 0.12)
	if k >= 1.0:
		stop(true)


func _cut() -> void:
	var main := Main.inst
	FX.slash(p, ang + PI * 0.5, 3 if turns_done == TURNS else 0)
	var sl := Sfx.play("slash", 0.12, -3.0)
	if sl:
		sl.pitch_scale = 1.0 + turns_done * 0.08
	var any := false
	for e in Enemy.live(p.get_tree()):
		var en := e as Enemy
		if not is_instance_valid(en) or not en.alive or not en.landed:
			continue
		var out := en.global_position - p.global_position
		if absf(out.y) > 1.8:
			continue
		out.y = 0
		if out.length() > R + en.radius:
			continue
		var d := out.normalized() if out.length() > 0.1 else p.aim_dir
		en.slash_yaw = ang + PI * 0.5
		var k0 := en.knock
		en.take_hit(DMG, d, en.global_position, "slash")
		en.knock = k0 + (en.knock - k0) * 0.15      # 회오리에 붙잡혀 계속 맞는다
		FX.sparks(en.global_position + Vector3(0, 0.9, 0), 5, [Color.WHITE, Pal.BLADE, COL], 6.0, 0.25, -10.0, 0.05)
		hits += 1
		any = true
	for b in p.get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		var d := bl.position - p.global_position
		d.y = 0
		if not bl.unslashable and d.length() < R + 0.3:
			FX.flash(bl.position, Pal.BLADE, 0.4, 0.06)
			bl.queue_free()
	if any:
		main.hitstop(0.025)


## 자세 (Player._animate 끝): 몸을 세운 축으로 돌리고 양팔을 펼쳐 칼끝이 원반을 그린다.
## 한 틱에 크게 도는 칼이 매끈한 원을 남기도록 사이 각도를 잘게 샘플해 리본에 넘긴다.
func pose(dt: float) -> void:
	var j := p.j
	var arm: Node3D = j.arm_r
	var blade: Node3D = j.blade
	(j.upper as Node3D).rotation.y = 0.0
	(j.legs as Node3D).rotation.y = 0.0
	(j.torso as Node3D).rotation = Vector3.ZERO
	arm.rotation = Vector3(-0.1, 0.0, 1.45)
	blade.rotation_degrees = Vector3(-90, 0, 0)
	blade.scale = Vector3(0.95, 0.95, 1.25)
	(j.arm_l as Node3D).rotation.z = -1.1
	for h in [j.hip_l, j.hip_r]:
		(h as Node3D).rotation.x = -0.3
	for kn in [j.knee_l, j.knee_r]:
		(kn as Node3D).rotation.x = -0.45
	var mv := p.velocity
	mv.y = 0
	var tilt := Basis.IDENTITY
	if mv.length() > 0.5:
		tilt = Basis(mv.normalized().cross(Vector3.DOWN).normalized(), clampf(mv.length() * 0.04, 0.0, 0.2))
	var samples: Array = []
	var n := clampi(int(ceil(absf(ang - _prev) / 0.3)), 1, 14)
	for i in range(1, n + 1):
		p.visual.basis = tilt * Basis(Vector3.UP, lerpf(_prev, ang, float(i) / n))
		if i < n:
			samples.append(p.trail.sample_now())
	_prev = ang
	p.visual.position.y = Player.PIVOT_Y + p.hover + 0.1
	p.trail.boost = 1.0
	p.trail.feed(dt, samples)
