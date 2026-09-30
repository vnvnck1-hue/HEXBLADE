class_name Crawler
extends Enemy
## 중력 크롤러 (HEAVY-GRAVITY CRAWLER MK.IV).
## 평소에는 노란 장갑 구체로 당구공처럼 벽을 튕기며 초고속으로 굴러다닌다. 구체 상태는 무적이라
## 총알·검·레이저·미사일을 모두 튕겨 낸다 (총알은 도탄이 되어 주변으로 흩어진다).
## 빠르게 구르는 몸통은 공격 판정이 있어 부딪히면 피해를 입는다 (대시 무적으로 뚫고 지나갈 수 있다).
## 멈춰 서서 거미처럼 다리를 펼치면 뚜껑이 열려 약점 코어가 드러나고, 이때만 피해가 들어간다.
## 거미 상태: 삼안 3연사 → 도약 내려찍기(원형탄) → 다시 구체로 접혀 굴러 나간다.
##
## 모든 동작은 "느린 준비(ease-in) → 2~3프레임 임팩트(expo) → 탄성 복귀(elastic)" 로 강약을 준다.
## 자세 값(unfold · lift · crouch · pitch · lean · sq_a · sq_b)은 Tween 으로 움직이고 _pose() 가 매 프레임 적용한다.

enum S { IDLE, WINDUP, ROLL, BRAKE, UNFOLD, SPIDER, FOLD }
enum SP { SETTLE, VOLLEY_WIND, VOLLEY, WALK, HOP_WIND, HOP, LAND }

const R := 0.6                   # 구체 반지름 (Build.CR_R)
const BALL_Y := R                # 구체 중심 높이
const L1 := 0.5                  # 허벅지 길이 (Build.CR_L1)
const L2 := 0.86                 # 정강이 길이 (Build.CR_L2)
const SPIDER_LIFT := 0.34        # 거미 자세에서 몸통이 구체보다 솟는 높이
const SPIDER_R := 0.9            # 거미 상태 피격 반지름 (다리 포함)
const CAP_OPEN := 1.95           # 뚜껑 열림 각도 (뒤로 젖혀 코어·눈을 가리지 않는다)
# 구체
const ROLL_SPEED := 19.0
const ROLL_MIN := 14.0
const ROLL_DECEL := 1.4
const HURT_SPEED := 7.0          # 이 속도 이상으로 구르면 몸통 박치기 판정
const HOMING := 0.4              # 벽에 튕길 때 플레이어 쪽으로 꺾는 비율
const ROLL_MAX_T := 3.4
# 준비 동작 (느리게)
const WINDUP_T := 0.62
const BRAKE_T := 0.42
const UNFOLD_T := 0.5
const FOLD_T := 0.42
const VOLLEY_WIND_T := 0.7
const HOP_WIND_T := 0.55
# 임팩트 (몇 프레임)
const SNAP := 0.05               # 3프레임
const HIT := 0.033               # 2프레임
const DENT := 0.017              # 1프레임
# 거미 공격
const VOLLEY_SHOTS := 3
const VOLLEY_GAP := 0.13
const VOLLEY_SPEED := 10.0
const HOP_T := 0.34
const HOP_H := 1.5
const HOP_MAX := 5.0
const RING_SHOTS := 10
const WALK_SPEED := 1.8

const DUST: Array[Color] = [Color("8a88a0"), Color("6a6680"), Color("403c50"), Color("2c2a3a")]
const SPARK: Array[Color] = [Color.WHITE, Color("ffe080"), Color("ff9a30")]
const GHOST_TINT := Color(1.0, 0.72, 0.25, 0.32)

var state := S.IDLE
var st_t := 0.0
var sp := SP.SETTLE
var sp_t := 0.0
var armored := true
var vel := Vector3.ZERO
var roll_dir := Vector3.FORWARD
var bounces_left := 0
var ghost_t := 0.0
var volley_left := 0
var volley_t := 0.0
var hop_from := Vector3.ZERO
var hop_to := Vector3.ZERO
var hop_y := 0.0
var air_tuck := 0.0
var walk_ph := 0.0
var walk_amt := 0.0
var tremble := 0.0
var eye_k := 0.4
var core_hit := 0.0
var drop_y := 6.4
var lean_dir := Vector3.FORWARD
var _snd_t := 0.0
var _last_bounce := -1.0
var _hint_t := 0.0
var _tws := {}
# 트윈으로 움직이는 자세 값
var unfold := 0.0                # 다리 펼침 0(구체) ~ 1(거미). 임팩트에서 1 을 살짝 넘겼다가 돌아온다
var lift := 0.0                  # 몸통 추가 높이
var crouch := 0.0                # 웅크림 (+ 낮게 / - 다리를 뻗어 높게)
var pitch := 0.0                 # 앞뒤 젖힘 (+ 앞을 들어 올림)
var lean := 0.0                  # lean_dir 쪽으로 몸통을 미는 양
var sq_a := 0.0                  # sq_axis 방향 늘임(+)/눌림(-)
var sq_b := 0.0                  # 세로 늘임(+)/눌림(-)
var sq_axis := Vector3.FORWARD   # 자기 좌표 수평 방향
var cap_k := 0.0                 # 뚜껑 열림 0 ~ 1
var twist := 0.0                 # 몸통 비틀기 (변신 준비)
var _last_flash := -1.0


func _ready() -> void:
	super()
	hp = 14
	hp_bar_w = 1.4
	radius = R
	desired = 5.5
	slice_size = Vector3(1.05, 1.0, 1.05)
	slice_color = Pal.CR_YELLOW
	shadow.scale = Vector3.ONE * 0.4
	_pose(0.0)
	# 거미 상태(약점 노출)에서만: 뒷걸음질과 이탈 대시 반반, 광선검은 가끔 피한다
	evade.chance = 0.45
	evade.back_w = 0.55
	evade.dodge = 0.3


func _build(v: Node3D) -> Dictionary:
	return Build.crawler(v)


func is_armored() -> bool:
	return alive and armored


# ── 거리 벌리기 (Evade 가 부른다) ───────────────────────

## 다리를 펴고 걷거나 자리 잡는 중에만 (구체·도약·연사 준비 중에는 하지 않는다)
func _can_evade() -> bool:
	return state == S.SPIDER and (sp == SP.SETTLE or sp == SP.WALK)


## 이탈 대시 뒤 무작위 공격: 삼안 3연사 · 도약 내려찍기 중 하나
func _evade_attack() -> void:
	if state != S.SPIDER:
		return
	_sp(SP.VOLLEY_WIND if randf() < 0.5 else SP.HOP_WIND)


## 순간이동 반격: 준비 없이 곧바로 삼안 3연사
func _counter_attack() -> void:
	if state != S.SPIDER:
		return
	_sp(SP.VOLLEY)


# ── 등장: 구체로 떨어져 튕긴다 ─────────────────────────

func _update_entry(dt: float) -> void:
	drop_t += dt
	var k := clampf(drop_t / DROP_TIME, 0.0, 1.0)
	drop_y = lerpf(6.4, 0.0, k * k)
	shadow.scale = Vector3.ONE * lerpf(0.4, 0.85, k)
	(j.shell as Node3D).rotate_x(-dt * 9.0)
	if k >= 1.0:
		landed = true
		state = S.IDLE
		st_t = -0.25
		_thud(1.0)
	_pose(dt)


## 바닥에 떨어진 충격: 1프레임 만에 납작하게 눌렸다가 탄성으로 튀어 오른다
func _thud(k: float) -> void:
	_snap("sq_b", -0.36 * k, DENT, 0.0, 0.4)
	FX.land_dust(global_position)
	FX.shockwave(global_position, Color("ffc040"), 1.8 * k, 0.2, 0.05)
	Sfx.play("clank", 0.08, -6.0)
	Sfx.play("land", 0.05, -3.0)
	Main.inst.shake(0.15 * k)


# ── AI ──────────────────────────────────────────────────

func _ai(dt: float) -> void:
	st_t += dt
	_snd_t -= dt
	_hint_t -= dt
	core_hit = maxf(0.0, core_hit - dt)
	var player := Main.inst.player
	var to_p := player.global_position - global_position
	to_p.y = 0
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)
	var active := player.alive and Main.inst.state == Main.State.PLAY
	match state:
		S.IDLE:
			vel = vel.move_toward(Vector3.ZERO, 30.0 * dt)
			_move_ball(dt)
			if st_t > 0.35:
				_begin_windup(dist)
		S.WINDUP:
			_windup(dt)
		S.ROLL:
			_roll(dt, player)
		S.BRAKE:
			_brake(dt, dir, player)
		S.UNFOLD:
			_unfold_wind(dt, dir)
		S.SPIDER:
			_spider(dt, dir, dist, active)
		S.FOLD:
			_fold_wind(dt, dir)
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	wob_v += (-wob * 220.0 - wob_v * 11.0) * dt
	wob += wob_v * dt
	_pose(dt)


# ── 구체: 발진 준비 → 발진 → 당구공 반사 → 제동 ─────────

## 검증용 (--crawlershow): 상태 전환 시각을 로그로 남겨 캡처 프레임과 맞춘다
func _log(s: String) -> void:
	if Main.inst.crawler_show:
		print("CRAWLER %.3f %s" % [Main.inst.time, s])


func _begin_windup(dist: float) -> void:
	state = S.WINDUP
	st_t = 0.0
	_log("WINDUP")
	var p := Main.inst.player
	var lead := p.velocity * clampf(dist / ROLL_SPEED, 0.0, 0.5)
	var aim := p.global_position + lead - global_position
	aim.y = 0
	roll_dir = aim.normalized() if aim.length() > 0.5 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	roll_dir = roll_dir.rotated(Vector3.UP, randf_range(-0.3, 0.3))
	# 준비: 굴러갈 반대쪽으로 몸을 젖히며 천천히(점점 빠르게) 납작하게 웅크린다
	lean_dir = -roll_dir
	_ease("sq_b", -0.24, WINDUP_T)
	_ease("lean", 0.14, WINDUP_T)
	Sfx.play("rev", 0.05, -4.0)


func _windup(dt: float) -> void:
	var k := clampf(st_t / WINDUP_T, 0.0, 1.0)
	# 제자리에서 헛돌며 힘을 모은다: 회전이 점점 빨라지고 바닥에서 불꽃·먼지가 튄다
	_roll_shell(roll_dir, lerpf(0.0, 24.0, k * k), dt)
	tremble = k * k * 0.03
	eye_k = 0.4 + k * 1.4
	fx_t -= dt
	if fx_t <= 0.0:
		fx_t = lerpf(0.12, 0.025, k)
		var back := global_position - roll_dir * R * 0.8 + Vector3(0, 0.06, 0)
		FX.sparks(back, 2 + int(k * 4), SPARK, 3.0 + 6.0 * k, 0.25, -12.0, 0.05)
		if randf() < 0.4:
			FX.puffs(back, 1, DUST, 0.2, 0.25, 0.4)
	if st_t >= WINDUP_T:
		_launch()


func _launch() -> void:
	state = S.ROLL
	st_t = 0.0
	_log("LAUNCH")
	vel = roll_dir * ROLL_SPEED
	bounces_left = randi_range(3, 5)
	_last_bounce = -1.0
	tremble = 0.0
	ghost_t = 0.0
	# 임팩트: 2프레임 만에 진행 방향으로 쭉 늘어나며 튀어 나가고, 탄성으로 제 모양을 찾는다
	sq_axis = _local(roll_dir)
	_snap("sq_a", 0.45, HIT, 0.0, 0.34)
	_snap("sq_b", 0.0, HIT)
	_snap("lean", -0.12, HIT, 0.0, 0.26)
	var c := _center()
	FX.flash(c, Color(1.0, 0.95, 0.75), 1.0, 0.06)
	FX.shockwave(global_position, Color("ffb040"), 2.6, 0.22, 0.06)
	FX.puffs(global_position - roll_dir * 0.6, 4, DUST, 0.4, 0.4, 0.5)
	FX.sparks(global_position - roll_dir * 0.5 + Vector3(0, 0.1, 0), 14, SPARK, 9.0, 0.3, -12.0, 0.06)
	Sfx.play("launch", 0.06, 0.0)
	Main.inst.shake(0.2)


func _roll(dt: float, player: Player) -> void:
	var speed := move_toward(vel.length(), ROLL_MIN, ROLL_DECEL * dt)
	vel = vel.normalized() * speed
	_move_ball(dt)
	_bump_enemies()
	speed = vel.length()
	_roll_shell(vel / maxf(speed, 0.001), speed, dt)
	# 초고속 잔상 + 바닥을 긁는 불꽃
	ghost_t -= dt
	if ghost_t <= 0.0:
		ghost_t = 0.03
		FX.afterimage(visual, GHOST_TINT, 0.14)
	fx_t -= dt
	if fx_t <= 0.0:
		fx_t = 0.05
		FX.sparks(global_position + Vector3(0, 0.05, 0), 2, SPARK, 3.0, 0.2, -12.0, 0.04)
	_contact(player)
	if bounces_left <= 0 or st_t > ROLL_MAX_T:
		_begin_brake()


## 벽을 뚫지 않도록 잘게 나눠 움직이고, 벽에 밀려나면 그 법선으로 반사한다
func _move_ball(dt: float) -> void:
	var total := (vel + knock) * dt
	var n := maxi(1, int(ceil(total.length() / 0.12)))
	for i in n:
		global_position += (vel + knock) * dt / n
		var p := Main.inst.push_out(global_position, R)
		var push := Vector3(p.x - global_position.x, 0, p.z - global_position.z)
		global_position = p
		if push.length() > 0.0005:
			var nrm := push.normalized()
			if vel.dot(nrm) < -0.5:
				_bounce(nrm)


## 당구공 반사. n = 부딪힌 면에서 바깥을 향하는 법선
func _bounce(n: Vector3) -> void:
	_log("BOUNCE")
	var speed := vel.length()
	var d := (vel - 2.0 * vel.dot(n) * n).normalized()
	var player := Main.inst.player
	if state == S.ROLL:
		var to_p := player.global_position - global_position
		to_p.y = 0
		if player.alive and to_p.length() > 1.5 and to_p.normalized().dot(n) > 0.1:
			d = d.slerp(to_p.normalized(), HOMING).normalized()
		# 좁은 통로에서 연달아 튕기는 것은 한 번으로 친다
		if st_t - _last_bounce > 0.25:
			bounces_left -= 1
		_last_bounce = st_t
		speed = maxf(ROLL_MIN, speed * 0.97)
	else:
		speed *= 0.5
	vel = d * speed
	var k := clampf(speed / ROLL_SPEED, 0.15, 1.0)
	var contact := _center() - n * R
	# 임팩트: 1프레임 만에 벽에 납작하게 눌렸다가 탄성으로 튀어 나간다
	sq_axis = _local(n)
	_snap("sq_a", -0.42 * k, DENT, 0.0, 0.32)
	FX.flash(contact, Color(1.0, 0.95, 0.7), 0.8 * k, 0.05)
	FX.sparks(contact, int(8 + 10 * k), SPARK, 9.0 * k, 0.3, -12.0, 0.06)
	FX.shockwave(contact, Color("ffc040"), 1.6 * k, 0.18, 0.05)
	Sfx.play("clank", 0.12, lerpf(-12.0, -2.0, k))
	if global_position.distance_to(player.global_position) < 11.0:
		Main.inst.shake(0.16 * k)
		if k > 0.6:
			Main.inst.hitstop(0.025)


## 몸통 박치기: 빠르게 구르는 동안 플레이어에게 닿으면 피해를 주고 튕겨 나간다
func _contact(player: Player) -> void:
	if vel.length() < HURT_SPEED or not player.alive:
		return
	var rel := player.global_position - global_position
	rel.y = 0
	if rel.length() > R + player.hit_radius + 0.08:
		return
	var n := rel.normalized() if rel.length() > 0.01 else vel.normalized()
	if not player.take_hit(global_position):
		return   # 대시 무적 등 → 그대로 지나간다
	player.velocity += n * 9.0
	if vel.dot(n) > 0.0:
		vel -= 2.0 * vel.dot(n) * n
	sq_axis = _local(n)
	_snap("sq_a", -0.3, DENT, 0.0, 0.3)
	FX.sparks(_center() + n * R, 16, SPARK, 9.0, 0.3, -12.0, 0.06)
	FX.shockwave(global_position + n * R, Color.WHITE, 2.0, 0.16, 0.05)
	Sfx.play("clank", 0.05, 0.0)


## 다른 적과도 당구공처럼 부딪힌다 (상대는 밀려난다)
func _bump_enemies() -> void:
	for o in get_tree().get_nodes_in_group("enemies"):
		var en := o as Enemy
		if en == self or not en.landed:
			continue
		var d := global_position - en.global_position
		d.y = 0
		var l := d.length()
		var min_d := R + en.radius
		if l < min_d and l > 0.001:
			var n := d / l
			global_position += n * (min_d - l)
			if vel.dot(n) < 0.0:
				en.knock -= n * vel.length() * 0.5
				en.wob_v += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 10.0
				_bounce(n)


func _begin_brake() -> void:
	state = S.BRAKE
	st_t = 0.0
	_log("BRAKE")
	Sfx.play("roll", 0.1, -4.0)
	# 급제동: 앞으로 쏠렸다가 버틴다
	lean_dir = vel.normalized() if vel.length() > 0.1 else lean_dir
	_snap("lean", 0.12, 0.06, 0.0, 0.45)


func _brake(dt: float, dir: Vector3, player: Player) -> void:
	var k := clampf(st_t / BRAKE_T, 0.0, 1.0)
	vel *= exp(-7.5 * dt)
	_move_ball(dt)
	var speed := vel.length()
	if speed > 0.05:
		_roll_shell(vel / speed, speed, dt)
	# 구르면서 서서히 똑바로 서고 플레이어 쪽으로 눈을 돌린다
	_upright(dt, lerpf(0.0, 9.0, k))
	_turn(dir, dt, 3.0 * k, true)
	fx_t -= dt
	if fx_t <= 0.0 and speed > 2.0:
		fx_t = 0.03
		FX.sparks(global_position - vel / speed * 0.3 + Vector3(0, 0.04, 0), 3, SPARK, 4.0, 0.22, -14.0, 0.05)
	_contact(player)
	if st_t >= BRAKE_T:
		_begin_unfold()


# ── 변신: 구체 → 거미 ───────────────────────────────────

func _begin_unfold() -> void:
	state = S.UNFOLD
	st_t = 0.0
	_log("UNFOLD_WIND")
	vel = Vector3.ZERO
	# 준비: 천천히 웅크리고 몸을 비틀며, 뚜껑 틈으로 붉은 빛이 새고 다리 끝이 살짝 비어져 나온다
	_ease("sq_b", -0.2, UNFOLD_T)
	_ease("unfold", 0.1, UNFOLD_T)
	_ease("twist", -0.55, UNFOLD_T)
	_ease("cap_k", 0.12, UNFOLD_T)
	Sfx.play("twind", 0.05, -6.0)


func _unfold_wind(dt: float, dir: Vector3) -> void:
	var k := clampf(st_t / UNFOLD_T, 0.0, 1.0)
	_upright(dt, 14.0)
	_turn(dir, dt, 8.0, true)
	tremble = k * k * 0.06
	# 이음새에서 불똥이 새고 눈이 깜빡이며 달아오른다
	eye_k = 0.4 + (1.8 if fmod(st_t, 0.1) < 0.05 else 0.3) * k
	fx_t -= dt
	if fx_t <= 0.0:
		fx_t = lerpf(0.1, 0.035, k)
		var a := randf() * TAU
		FX.sparks(_center() + Vector3(cos(a), -0.35, sin(a)) * R, 2, SPARK, 2.5, 0.25, -10.0, 0.04)
	if st_t >= UNFOLD_T:
		_unfold_snap()


func _unfold_snap() -> void:
	state = S.SPIDER
	armored = false
	radius = SPIDER_R
	tremble = 0.0
	eye_k = 1.8
	(j.shell as Node3D).basis = Basis.IDENTITY
	# 임팩트: 3프레임 만에 다리가 튀어나오고 몸통이 솟는다 → 살짝 넘쳤다가 탄성으로 자리 잡는다
	_snap("unfold", 1.15, SNAP, 1.0, 0.4)
	_snap("lift", SPIDER_LIFT + 0.16, SNAP, SPIDER_LIFT, 0.45)
	_snap("sq_b", 0.26, HIT, 0.0, 0.35)
	_snap("twist", 0.18, HIT, 0.0, 0.4)
	_snap("cap_k", 1.08, SNAP, 1.0, 0.4)
	var gp := global_position
	FX.flash(_center() + Vector3(0, 0.3, 0), Color(1.0, 0.6, 0.55), 1.3, 0.07)
	FX.shockwave(gp, Color("ffb040"), 3.0, 0.24, 0.07)
	FX.shockwave(gp, Pal.CR_EYE, 2.0, 0.16, 0.04)
	FX.puffs(gp, 6, DUST, 1.0, 0.4, 0.55)
	FX.sparks(_center(), 18, SPARK, 8.0, 0.35, -12.0, 0.06)
	Sfx.play("unfold", 0.04, 0.0)
	Sfx.play("land", 0.05, -2.0)
	Main.inst.shake(0.28)
	Main.inst.hitstop(0.05)
	Main.inst.hud.popup("WEAK POINT", Color("ff6a7a"), gp + Vector3(0, 2.4, 0))
	_sp(SP.SETTLE)


# ── 거미: 약점 노출 · 삼안 연사 · 도약 내려찍기 ─────────

func _sp(next: int) -> void:
	sp = next
	sp_t = 0.0
	_log("SP %s" % SP.keys()[next])
	match sp:
		SP.VOLLEY_WIND:
			# 준비: 앞을 천천히 들어 올리며 뒤로 웅크리고 세 눈이 달아오른다
			_ease("pitch", 0.3, VOLLEY_WIND_T)
			_ease("crouch", 0.22, VOLLEY_WIND_T)
			Sfx.play("twind", 0.05, -5.0)
		SP.VOLLEY:
			volley_left = VOLLEY_SHOTS
			volley_t = 0.0
		SP.HOP_WIND:
			# 준비: 깊이 웅크리며 떨고, 내려찍을 자리를 바닥에 예고한다
			_ease("crouch", 0.46, HOP_WIND_T)
			_ease("pitch", -0.12, HOP_WIND_T)
			hop_to = _hop_target()
			FX.spawn_marker(hop_to, HOP_WIND_T + HOP_T)
			Sfx.play("twind", 0.08, -6.0)
		SP.HOP:
			hop_from = global_position
			tremble = 0.0
			# 임팩트: 2프레임 만에 다리를 쭉 뻗으며 튀어 오르고, 공중에서 다리를 접는다
			var tw := _tween("crouch")
			tw.tween_property(self, "crouch", -0.3, HIT).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "crouch", 0.1, HOP_T * 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_snap("pitch", 0.15, HIT, 0.0, HOP_T)
			_snap("sq_b", 0.3, HIT, 0.0, 0.3)
			FX.puffs(global_position, 5, DUST, 0.7, 0.35, 0.45)
			FX.shockwave(global_position, Color("ffc040"), 1.8, 0.16, 0.05)
			Sfx.play("launch", 0.1, -6.0)


func _spider(dt: float, dir: Vector3, dist: float, active: bool) -> void:
	sp_t += dt
	_turn(dir, dt, 7.0 if sp != SP.HOP else 0.0, false)
	var move := Vector3.ZERO
	match sp:
		SP.SETTLE:
			move = _walk_move(dt, dir, dist) * 0.5
			if sp_t > 0.3:
				_sp(SP.VOLLEY_WIND)
		SP.VOLLEY_WIND:
			var k := clampf(sp_t / VOLLEY_WIND_T, 0.0, 1.0)
			eye_k = 1.4 + k * k * 4.5 + sin(t * 60.0) * 0.6 * k
			fx_t -= dt
			if fx_t <= 0.0:
				# 빛 조각이 눈으로 빨려 든다
				fx_t = lerpf(0.08, 0.03, k)
				var e := (j.eyes as Array)[randi() % 3] as Node3D
				var off := Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)).normalized() * (1.0 - k * 0.6) * 0.6
				FX.flash(e.global_position + off, Pal.CR_EYE if randf() < 0.7 else Color.WHITE, 0.12, 0.1)
			if sp_t >= VOLLEY_WIND_T:
				_sp(SP.VOLLEY)
		SP.VOLLEY:
			volley_t -= dt
			if volley_t <= 0.0 and volley_left > 0:
				volley_t = VOLLEY_GAP
				volley_left -= 1
				_volley_shot(active, volley_left == 0)
			eye_k = move_toward(eye_k, 1.8, dt * 20.0)
			if volley_left == 0 and sp_t > VOLLEY_GAP * VOLLEY_SHOTS + 0.25:
				_sp(SP.WALK)
		SP.WALK:
			move = _walk_move(dt, dir, dist)
			if sp_t > 0.7:
				_sp(SP.HOP_WIND)
		SP.HOP_WIND:
			var k := clampf(sp_t / HOP_WIND_T, 0.0, 1.0)
			tremble = k * k * 0.03
			if sp_t >= HOP_WIND_T:
				_sp(SP.HOP)
		SP.HOP:
			var k := clampf(sp_t / HOP_T, 0.0, 1.0)
			# 앞 몇 프레임에 대부분의 거리를 날고, 꼭대기에서 잠깐 멈췄다가 내리꽂힌다
			var kh := 1.0 - pow(1.0 - k, 2.2)
			global_position = Main.inst.push_out(hop_from.lerp(hop_to, kh), R)
			hop_y = HOP_H * (1.0 - pow(absf(2.0 * k - 1.0), 3.0))
			air_tuck = sin(PI * k) * 0.28
			if k >= 1.0:
				_land(active)
		SP.LAND:
			if sp_t > 0.45:
				_begin_fold()
	if sp != SP.HOP:
		global_position += (move + knock) * dt
		global_position = Main.inst.push_out(global_position, R)
	walk_amt = move_toward(walk_amt, clampf(move.length() / WALK_SPEED, 0.0, 1.0), dt * 6.0)
	core_mat_pulse()


func _walk_move(dt: float, dir: Vector3, dist: float) -> Vector3:
	strafe_timer -= dt
	if strafe_timer <= 0.0:
		strafe_timer = randf_range(1.2, 2.2)
		strafe = -strafe
	var m := Vector3(-dir.z, 0, dir.x) * strafe * 0.7
	if dist > desired + 0.8:
		m += dir
	elif dist < desired - 0.8:
		m -= dir
	return m.limit_length(1.0) * WALK_SPEED


## 임팩트: 2프레임 만에 앞으로 고개를 튕기며 세 눈에서 동시에 쏜다
func _volley_shot(active: bool, last: bool) -> void:
	var tw := _tween("pitch")
	tw.tween_property(self, "pitch", -0.22, HIT).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if last:
		tw.tween_property(self, "pitch", 0.0, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		_snap("crouch", 0.0, 0.1, 0.0, 0.01)
	else:
		tw.tween_property(self, "pitch", 0.2, VOLLEY_GAP - HIT).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	eye_k = 7.0
	wob_v.x -= 6.0
	punch = maxf(punch, 0.4)
	var fan := [0.0, 0.14, -0.14]
	var eyes: Array = j.eyes
	for i in eyes.size():
		var e := eyes[i] as Node3D
		var origin := e.global_position
		FX.flash(origin, Color(0.7, 0.9, 1.0), 0.35, 0.05)
		if not active:
			continue
		origin.y = global_position.y + 0.95
		var aim := Main.inst.player.global_position - origin
		aim.y = 0
		var d := aim.normalized().rotated(Vector3.UP, fan[i])
		Main.inst.add_bullet(Bullet.make_enemy(origin + d * 0.2, d, VOLLEY_SPEED))
	Sfx.play("eshot", 0.08, -3.0)


func _hop_target() -> Vector3:
	var p := Main.inst.player
	var aim := p.global_position + p.velocity * 0.25 - global_position
	aim.y = 0
	var l := minf(aim.length(), HOP_MAX)
	var d := aim.normalized() if aim.length() > 0.01 else -global_basis.z
	# 벽 앞에서 멈춘다
	var free := 0.0
	while free < l:
		if Main.inst.is_blocked(global_position + d * (free + 0.25 + R)):
			break
		free += 0.25
	return Main.inst.push_out(global_position + d * free, R)


## 착지 임팩트: 1~2프레임에 깊게 눌리며 원형탄과 충격파를 뿜는다
func _land(active: bool) -> void:
	_sp(SP.LAND)
	hop_y = 0.0
	air_tuck = 0.0
	_snap("crouch", 0.5, HIT, 0.0, 0.5)
	_snap("sq_b", -0.3, DENT, 0.0, 0.4)
	var gp := global_position
	FX.shockwave(gp, Color("ffb040"), 3.4, 0.3, 0.08)
	FX.shockwave(gp, Color.WHITE, 2.0, 0.14, 0.04)
	FX.puffs(gp, 8, DUST, 1.0, 0.45, 0.6)
	FX.sparks(gp + Vector3(0, 0.1, 0), 16, SPARK, 8.0, 0.35, -12.0, 0.06)
	Sfx.play("boom", 0.1, -6.0)
	Sfx.play("clank", 0.1, -4.0)
	var p := Main.inst.player
	var near := gp.distance_to(p.global_position)
	Main.inst.shake(0.35 if near < 10.0 else 0.15)
	if near < 10.0:
		Main.inst.hitstop(0.05)
	if not active:
		return
	var off := randf() * TAU
	for i in RING_SHOTS:
		var d := Vector3.FORWARD.rotated(Vector3.UP, off + TAU * i / RING_SHOTS)
		Main.inst.add_bullet(Bullet.make_enemy(Vector3(gp.x, Main.gy(gp) + 0.95, gp.z) + d * 0.9, d, 6.5))
	if near < SPIDER_R + p.hit_radius + 0.4:
		p.take_hit(gp)


# ── 변신: 거미 → 구체 ───────────────────────────────────

func _begin_fold() -> void:
	state = S.FOLD
	st_t = 0.0
	_log("FOLD_WIND")
	# 준비: 다리를 곧게 뻗어 몸통을 천천히 들어 올리며 떨린다 (여전히 약점 노출)
	_ease("lift", SPIDER_LIFT + 0.18, FOLD_T)
	_ease("unfold", 0.82, FOLD_T)
	_ease("crouch", -0.1, FOLD_T)
	_ease("pitch", 0.0, FOLD_T * 0.5)
	_ease("cap_k", 0.75, FOLD_T)
	_ease("twist", 0.4, FOLD_T)
	Sfx.play("twind", 0.05, -6.0)


func _fold_wind(dt: float, dir: Vector3) -> void:
	var k := clampf(st_t / FOLD_T, 0.0, 1.0)
	tremble = k * k * 0.035
	eye_k = lerpf(1.6, 0.3, k) * (1.0 if fmod(st_t, 0.08) < 0.05 else 0.4)
	_turn(dir, dt, 4.0, false)
	core_mat_pulse()
	if st_t >= FOLD_T:
		_fold_snap()


func _fold_snap() -> void:
	_log("FOLD_SNAP")
	armored = true
	radius = R
	tremble = 0.0
	eye_k = 0.4
	# 임팩트: 3프레임 만에 다리가 빨려 들어가고 구체로 떨어진다 → 바닥에 눌렸다 튀어 오름
	var tu := _tween("unfold")
	tu.tween_property(self, "unfold", 0.0, SNAP).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	var tl := _tween("lift")
	tl.tween_property(self, "lift", 0.0, SNAP).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_snap("crouch", 0.0, SNAP)
	_snap("pitch", 0.0, SNAP)
	_snap("twist", 0.0, SNAP)
	var tc := _tween("cap_k")
	tc.tween_property(self, "cap_k", 0.0, SNAP).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	var tb := _tween("sq_b")
	tb.tween_interval(SNAP)
	tb.tween_property(self, "sq_b", -0.32, DENT).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tb.tween_property(self, "sq_b", 0.0, 0.38).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	FX.flash(_center(), Color(1.0, 0.95, 0.8), 0.9, 0.05)
	FX.sparks(_center(), 14, SPARK, 6.0, 0.3, -12.0, 0.05)
	FX.shockwave(global_position, Color("ffc040"), 2.0, 0.18, 0.05)
	Sfx.play("unfold", 0.04, -2.0)
	Sfx.play("clank", 0.06, -3.0)
	Main.inst.shake(0.18)
	state = S.IDLE
	st_t = 0.2


# ── 피격: 구체일 때는 전부 튕겨 낸다 ────────────────────

func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	if not alive:
		return
	if armored:
		_deflect(dir, pos, source)
		return
	core_hit = 0.12
	# 연사를 받아도 흰 번쩍임이 거미 모습을 덮지 않도록 간격을 둔다
	var allow := t - _last_flash > 0.2
	var k0 := knock
	super(dmg, dir, pos, source)
	if not alive:
		return
	# 무거운 기체: 연사에 밀려 약점 구간을 벗어나지 않도록 넉백을 작게 제한한다
	knock = (k0 + (knock - k0) * 0.2).limit_length(2.5)
	if allow:
		_last_flash = t
		flash_t = 0.025   # 1~2프레임만 번쩍
	else:
		flash_t = 0.0
		_set_flash(false)


## 플레이어탄이 장갑에 맞으면 도탄으로 바꿔 튕겨 보낸다 (Bullet 이 부른다)
func deflect_bullet(b: Bullet, pos: Vector3, fwd: Vector3) -> bool:
	if not is_armored():
		return false
	var fl := Vector3(fwd.x, 0, fwd.z).normalized()
	var n := _normal_at(pos, fl)
	var hit := global_position + n * R
	hit.y = clampf(pos.y, 0.25, _center().y + 0.4)
	var d := _ricochet_dir(fl, n)
	b.ricochet(hit + n * 0.08, d, b.vel.length() * randf_range(0.5, 0.75))
	_ping(hit, n, 0.45)
	return true


func _deflect(dir: Vector3, pos: Vector3, source: String) -> void:
	var fl := Vector3(dir.x, 0, dir.z)
	fl = fl.normalized() if fl.length() > 0.01 else Vector3.FORWARD
	var n := _normal_at(pos, fl)
	var hit := _center() + n * R
	match source:
		"slash", "phantom":
			# 검이 장갑에 막힌다: 큰 금속음 + 불꽃 + 도탄 파편, 플레이어가 튕겨 나간다
			_ping(hit, n, 1.0)
			for i in 5:
				_spawn_ricochet(hit, n, fl, 34.0)
			Sfx.play("clank", 0.05, 2.0)
			var p := Main.inst.player
			var away := p.global_position - global_position
			away.y = 0
			if away.length() > 0.01:
				p.velocity += away.normalized() * 11.0
			FX.shockwave(hit, Color.WHITE, 1.8, 0.14, 0.05)
			Main.inst.hitstop(0.06)
			Main.inst.shake(0.3)
			Main.inst.hud.popup("GUARD", Color("ffd060"), hit + Vector3(0, 1.5, 0))
			_hint_t = 1.4
		"laser":
			_ping(hit, n, 0.7)
			for i in 2:
				_spawn_ricochet(hit, n, fl, 30.0)
		"missile":
			_ping(hit, n, 0.9)
			for i in 3:
				_spawn_ricochet(hit, n, fl, 30.0)
			Sfx.play("clank", 0.1, -2.0)
		_:
			_ping(hit, n, 0.5)
			_spawn_ricochet(hit, n, fl, 40.0)


## 튕겨 낸 순간: 흰 섬광 · 불꽃 · 번쩍임 · 도탄음. 가끔 DEFLECT 문구로 무적임을 알린다.
func _ping(hit: Vector3, n: Vector3, k: float) -> void:
	FX.flash(hit, Color(1.0, 0.97, 0.8), 0.12 + 0.5 * k, 0.04)
	FX.sparks(hit + n * 0.05, int(4 + 10 * k), SPARK, 7.0 + 5.0 * k, 0.22, -10.0, 0.05)
	# 흰 번쩍임은 무거운 공격에만 (연사를 받아도 노란 장갑이 읽히도록)
	if k >= 0.7:
		flash_t = 0.035
		_set_flash(true)
	punch = maxf(punch, 0.08 + 0.3 * k)
	if _snd_t <= 0.0:
		_snd_t = 0.05
		Sfx.play("ricochet" if randf() < 0.65 else "tink", 0.2, -8.0 + 4.0 * k)
	if _hint_t <= 0.0:
		_hint_t = 1.4
		Main.inst.hud.popup("DEFLECT", Color("ffd060"), hit + Vector3(0, 1.4, 0))


func _spawn_ricochet(hit: Vector3, n: Vector3, fl: Vector3, speed: float) -> void:
	var d := _ricochet_dir(fl, n, 1.0)
	var b := Bullet.make_player(hit + n * 0.1, d, speed)
	b.ricochet(hit + n * 0.1, d, speed * randf_range(0.7, 1.0))
	Main.inst.add_bullet(b)


## 반사 방향 + 흩어짐. 항상 장갑 바깥쪽을 향하고, 조금 위로 튄다.
func _ricochet_dir(fl: Vector3, n: Vector3, spread := 0.6) -> Vector3:
	var r := (fl - 2.0 * fl.dot(n) * n).normalized().rotated(Vector3.UP, randf_range(-spread, spread))
	if r.dot(n) < 0.15:
		r = (r + n * 1.2).normalized()
	return Vector3(r.x, randf_range(0.04, 0.4), r.z).normalized()


func _normal_at(pos: Vector3, fl: Vector3) -> Vector3:
	var n := Vector3(pos.x - global_position.x, 0, pos.z - global_position.z)
	return n.normalized() if n.length() > 0.05 else -fl


func die(dir := Vector3.ZERO, source := "bullet") -> void:
	if alive:
		for key in _tws:
			if (_tws[key] as Tween).is_valid():
				(_tws[key] as Tween).kill()
		_tws.clear()
		tremble = 0.0
	super(dir, source)


# ── 트윈 ───────────────────────────────────────────────

func _tween(prop: String) -> Tween:
	if _tws.has(prop) and (_tws[prop] as Tween).is_valid():
		(_tws[prop] as Tween).kill()
	var tw := create_tween()
	_tws[prop] = tw
	return tw


## 준비 동작: 느리게 시작해 점점 빨라진다 (ease-in)
func _ease(prop: String, to: float, dur: float) -> void:
	_tween(prop).tween_property(self, prop, to, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## 임팩트: hit_t(몇 프레임) 만에 hit 까지 → rest 가 있으면 탄성으로 rest 에 자리 잡는다
func _snap(prop: String, hit: float, hit_t: float, rest = null, rest_t := 0.3) -> void:
	var tw := _tween(prop)
	tw.tween_property(self, prop, hit, hit_t).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	if rest != null:
		tw.tween_property(self, prop, float(rest), rest_t).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# ── 자세 적용 ───────────────────────────────────────────

func _center() -> Vector3:
	return (j.body as Node3D).global_position


func _local(v: Vector3) -> Vector3:
	var l := global_basis.inverse() * v
	l.y = 0
	return l.normalized() if l.length() > 0.001 else Vector3.FORWARD


## 구르는 회전: 접지점이 미끄러지지 않도록 속도 / 반지름 만큼 돈다
func _roll_shell(d: Vector3, speed: float, dt: float) -> void:
	var axis := Vector3.UP.cross(d)
	if axis.length() < 0.01 or speed <= 0.0:
		return
	var la := (global_basis.inverse() * axis).normalized()
	var shell: Node3D = j.shell
	shell.basis = (Basis(la, speed / R * dt) * shell.basis).orthonormalized()


func _upright(dt: float, rate: float) -> void:
	var shell: Node3D = j.shell
	var q := shell.basis.get_rotation_quaternion()
	shell.basis = Basis(q.slerp(Quaternion.IDENTITY, 1.0 - exp(-rate * dt)))


## 몸을 돌린다. keep_shell 이면 구체의 월드 방향은 그대로 두고 받침만 돈다.
func _turn(dir: Vector3, dt: float, rate: float, keep_shell: bool) -> void:
	if rate <= 0.0 or not Main.inst.player.alive:
		return
	var ny := lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-rate * dt))
	var dy := wrapf(ny - rotation.y, -PI, PI)
	rotation.y = ny
	if keep_shell:
		var shell: Node3D = j.shell
		shell.basis = Basis(Vector3.UP, -dy) * shell.basis


func core_mat_pulse() -> void:
	var cm: StandardMaterial3D = j.core_mat
	cm.emission_energy_multiplier = (1.4 + sin(t * 10.0) * 0.6) + core_hit * 30.0


func _pose(dt: float) -> void:
	var body: Node3D = j.body
	var squash: Node3D = j.squash
	var uc := clampf(unfold, 0.0, 1.0)
	walk_ph += dt * (3.0 + walk_amt * 9.0)
	var bob := sin(t * 5.0) * 0.015 * uc if state == S.SPIDER else 0.0
	# 찌그러짐: 진행/법선 방향(sq_a)과 세로(sq_b). 부피를 대략 보존한다.
	var side := Vector3.UP.cross(sq_axis).normalized()
	var f := Basis(sq_axis, Vector3.UP, side)
	var s := Vector3(1.0 + sq_a - sq_b * 0.5, 1.0 + sq_b - sq_a * 0.5, 1.0 - (sq_a + sq_b) * 0.5)
	squash.basis = f * Basis.from_scale(s) * f.transposed()
	# 눌려도 바닥·벽에 붙어 있도록 중심을 옮긴다
	var base_h := BALL_Y + lift - crouch * 0.28 + bob
	var h := base_h + drop_y + hop_y + (s.y - 1.0) * R * (1.0 - uc)
	var off := -sq_axis * (1.0 - s.x) * R * (1.0 - uc)
	if lean != 0.0:
		var ld := global_basis.inverse() * lean_dir
		ld.y = 0
		off += ld * lean
	if tremble > 0.0:
		off += Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * tremble
	body.position = Vector3(off.x, h + off.y, off.z)
	body.rotation = Vector3(pitch + wob.x * 0.3, twist, wob.y * 0.3)
	# 뚜껑 경첩과 약점 코어. 뚜껑이 조금만 들려도 이음새로 붉은 빛이 샌다.
	var ck := clampf(cap_k, 0.0, 1.1)
	(j.cap as Node3D).rotation.x = CAP_OPEN * cap_k
	var seam: MeshInstance3D = j.seam
	seam.visible = ck > 0.01 and ck < 0.9
	seam.set_instance_shader_parameter("energy", clampf(ck * 25.0, 0.0, 3.0) * (0.8 + 0.2 * sin(t * 40.0)))
	var core: MeshInstance3D = j.core
	core.scale = Vector3.ONE * maxf(0.001, clampf(ck * 1.1 - 0.1, 0.0, 1.2))
	core.position.y = lerpf(0.36, 0.6, clampf(ck, 0.0, 1.0))
	if armored:
		(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 0.6
	(j.eye_mat as StandardMaterial3D).emission_energy_multiplier = eye_k
	# 다리: 2관절 IK 로 발을 바닥에 둔다. 접힌 자세(구체 안)와 섞는다.
	var show := uc > 0.02
	var hip_h := base_h - 0.2
	var legs: Array = j.legs
	for i in legs.size():
		var L: Dictionary = legs[i]
		var hip: Node3D = L.hip
		hip.visible = show
		if not show:
			continue
		hip.position = (L.out as Vector3) * lerpf(0.1, 0.42, uc) + Vector3(0, -0.2, 0)
		hip.scale = Vector3.ONE * lerpf(0.3, 1.0, uc)
		var ph := walk_ph + (PI if i % 2 == 1 else 0.0)
		var foot_up := maxf(0.0, sin(ph)) * 0.16 * walk_amt + air_tuck
		var reach := 0.74 + cos(ph) * 0.08 * walk_amt - crouch * 0.05
		var ik := _ik(reach, -(hip_h - 0.085) + foot_up)
		(L.thigh as Node3D).rotation.z = lerpf(1.9, ik.x, unfold)
		(L.knee as Node3D).rotation.z = lerpf(-2.7, ik.y, unfold)
	shadow.scale = Vector3.ONE * lerpf(0.85, 1.3, uc) * clampf(1.0 - hop_y * 0.3, 0.4, 1.0) if landed else shadow.scale


## 2관절 IK: 엉덩이 기준 (tx, ty) 에 발을 둔다. 무릎은 위로 꺾인다. (허벅지 각, 무릎 각)
static func _ik(tx: float, ty: float) -> Vector2:
	var d := clampf(sqrt(tx * tx + ty * ty), 0.2, L1 + L2 - 0.001)
	var c := clampf((d * d - L1 * L1 - L2 * L2) / (2.0 * L1 * L2), -1.0, 1.0)
	var a2 := -acos(c)
	var a1 := atan2(ty, tx) - atan2(L2 * sin(a2), L1 + L2 * cos(a2))
	return Vector2(a1, a2)
