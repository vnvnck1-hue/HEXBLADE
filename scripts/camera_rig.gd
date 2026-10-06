class_name CameraRig
extends Camera3D
## 쿼터뷰 카메라. 프리셋별로 추적 속도·선행·기울기·줌 반응이 다르다.
## 모든 움직임은 게임 시간(dt, time_scale 반영)으로 계산해 히트스탑 때 함께 멈춘다.

const PRESETS := [
	{
		"name": "CLASSIC", "desc": "안정적인 기본 쿼터뷰",
		"offset": Vector3(0, 9.8, 7.3), "fov": 40.0, "follow": 6.0, "look": 0.18, "lead": 0.0,
		"roll": 0.0, "punch": 0.35, "speed_zoom": 0.0, "kill_pull": 0.0, "sway": 0.0,
	},
	{
		"name": "ACTION", "desc": "빠른 추적 · 이동 선행 · 강한 FOV 펀치 · 격파 줌",
		"offset": Vector3(0, 9.0, 6.6), "fov": 42.0, "follow": 9.0, "look": 0.26, "lead": 0.22,
		"roll": 0.03, "punch": 1.0, "speed_zoom": 0.16, "kill_pull": 1.0, "sway": 0.0,
	},
	{
		"name": "CINEMATIC", "desc": "낮은 각도 · 느린 추적 · 크게 기울고 흔들리는 연출",
		"offset": Vector3(0, 6.4, 8.6), "fov": 38.0, "follow": 3.2, "look": 0.2, "lead": 0.42,
		"roll": 0.06, "punch": 0.9, "speed_zoom": 0.24, "kill_pull": 1.5, "sway": 1.0,
	},
	{
		"name": "TACTICAL", "desc": "높고 넓은 시야 · 모든 전투 카메라 공통",
		# 각도(62°)는 그대로, 거리만 1.2배 (예전 (0,15,8))
		"offset": Vector3(0, 18.0, 9.6), "fov": 36.0, "follow": 7.0, "look": 0.12, "lead": 0.08,
		"roll": 0.0, "punch": 0.3, "speed_zoom": 0.08, "kill_pull": 0.3, "sway": 0.0,
	},
	# 브롤스타즈 식 망원 부감 (BrawlLook): 멀리서 화각 26° 로 50° 내려다본다. 원근이 약해 벽 앞면이 평행에 가깝고
	# 캐릭터가 정면에 가깝게 보인다. 바닥이 보이는 넓이는 예전 TACTICAL (0,15,8) 과 같게 거리를 맞췄다 (docs/brawl-look.md).
	{
		"name": "BRAWL", "desc": "망원 렌즈 50° 부감 · 브롤스타즈 식",
		"offset": Vector3(0, 15.9, 13.3), "fov": 26.0, "follow": 8.0, "look": 0.12, "lead": 0.06,
		"roll": 0.0, "punch": 0.3, "speed_zoom": 0.06, "kill_pull": 0.3, "sway": 0.0,
	},
]
const DEFAULT := 3   # TACTICAL (높고 넓은 시야 · 절제된 반응)
const BRAWL := 4
## 게임의 모든 전투 카메라는 TACTICAL 시야 하나로 통일한다 (62° 내려다봄 · 화각 36°). set_preset 은 무엇을 넘겨도 이것.
## 거대 보스 전장(추격 · 용광로 · 거미)은 같은 각도 · 화각에서 거리만 늘린다: view_offset(배율).
## 나머지 프리셋은 기록용으로 남겨 둔다. 연출 컷(격파 감독 · 쇼타임 컷인)은 잠깐 따로 잡는다.
const VIEW_FOV := 36.0


static func view_offset(dist_k := 1.0) -> Vector3:
	return (PRESETS[DEFAULT].offset as Vector3) * dist_k

var preset_index := DEFAULT
var p: Dictionary = PRESETS[DEFAULT]
var cur_offset: Vector3 = PRESETS[DEFAULT].offset
var cur_fov: float = PRESETS[DEFAULT].fov

var focus := Vector3.ZERO
var lead := Vector3.ZERO
var trauma := 0.0
var shake_time := 0.0
var kick_pos := Vector3.ZERO
var kick_v := Vector3.ZERO
var fov_add := 0.0
var fov_v := 0.0
var zoom := 1.0          # 오프셋 배율 (1보다 크면 줌아웃)
var zoom_v := 0.0
var charge_zoom := 1.0   # 광선검 기 모으기: 단계마다 계단식으로 줌아웃 (BladeTech 가 정한다)
var frame_bias := Vector3.ZERO   # 장면이 정하는 시선 이동 (보스방: 보스 쪽으로). 부드럽게 따라간다
var frame_zoom := 1.0            # 장면이 정하는 줌아웃 배율 (보스방: 큰 보스를 함께 담는다)
var _frame_bias := Vector3.ZERO
var _frame_zoom := 1.0
var roll := 0.0
var pull := Vector3.ZERO  # 격파 지점 쪽으로 잠깐 끌림
var pull_t := 0.0
var beam_on := false
var beam_dir := Vector3.ZERO
var beam_bias := Vector3.ZERO
var ult_on := false
var ult_k := 0.0          # 락온 시야 전환 정도 (0~1)
var ult_look := Vector3.ZERO
var noise := FastNoiseLite.new()
var t := 0.0
# 패링 줌: 플레이어와 적 사이로 시선을 조금 당기며 적당히 줌인했다가 곧 돌아온다 (실제 시간으로 진행)
const CINE_IN := 0.05
const CINE_HOLD := 0.16
const CINE_END := 0.45
const CINE_ZOOM := 0.87         # 오프셋 배율 (1 = 평소 거리)
const CINE_SHIFT := 0.3         # 시선을 적 쪽으로 옮기는 비율 (플레이어~적 중간까지의 거리 기준)
var cine_start := -1
var cine_player: Player
var cine_foe: Node3D
var cine_foe_pos := Vector3.ZERO
var cine_w := 0.0
# 광각 렌즈 배럴 왜곡 세기 (LensFX 가 화면을 휘고, 아래 두 함수가 화면 좌표를 같은 식으로 맞춘다)
var lens_k := 0.0


func _ready() -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	far = 200.0
	ToonOutline.attach(self)


## 월드 → 실제로 보이는 화면 좌표 (렌즈 왜곡 반영). HUD 마커 · 락온 판정용.
func screen_pos(wp: Vector3) -> Vector2:
	var r := unproject_position(wp)
	if lens_k <= 0.001:
		return r
	var vs := get_viewport().get_visible_rect().size
	var q := (r - vs * 0.5) / vs.y
	var rr := q.length()
	if rr < 0.00001:
		return r
	var n := 1.0 + lens_k * _lens_rm2(vs)
	# r (1 + k r²) / n = rr 를 뉴턴법으로 푼다
	var x := rr
	for i in 5:
		x -= (x * (1.0 + lens_k * x * x) / n - rr) / ((1.0 + 3.0 * lens_k * x * x) / n)
	return vs * 0.5 + q * (x / rr) * vs.y


## 보이는 화면 좌표 → 렌더된 화면 좌표 (마우스 조준 광선용)
func render_pos(sp: Vector2) -> Vector2:
	if lens_k <= 0.001:
		return sp
	var vs := get_viewport().get_visible_rect().size
	var q := (sp - vs * 0.5) / vs.y
	var src := q * (1.0 + lens_k * q.length_squared()) / (1.0 + lens_k * _lens_rm2(vs))
	return vs * 0.5 + src * vs.y


func _lens_rm2(vs: Vector2) -> float:
	var a := vs.x / maxf(1.0, vs.y)
	return a * a * 0.25 + 0.25


## 시야는 하나로 통일됐다: 어떤 번호를 넘겨도 TACTICAL (V 키 · --campreset 도 바꾸지 않는다)
func set_preset(_i: int) -> void:
	preset_index = DEFAULT
	p = PRESETS[preset_index]


func snap(target: Vector3) -> void:
	focus = target
	cur_offset = p.offset
	cur_fov = p.fov
	_apply(Vector3.ZERO)


# ── 이벤트 ──────────────────────────────────────────────

func shake(a: float) -> void:
	trauma = minf(1.0, trauma + a)


func kick(v: Vector3) -> void:
	kick_v += v


## 순간적으로 시야가 넓어졌다 돌아옴 (대시·발사)
func fov_punch(deg: float) -> void:
	fov_v += deg * 22.0 * p.punch


## 격파 지점으로 살짝 끌리며 줌인
func kill_punch(pos: Vector3) -> void:
	if p.kill_pull <= 0.0:
		return
	pull = (pos - focus) * 0.22 * p.kill_pull
	pull.y = 0
	pull_t = 0.35
	# 연속 격파에도 누적되지 않도록 한 번만큼만
	zoom_v = minf(zoom_v, -1.4 * float(p.kill_pull))


## 궁극기 락온 전환 속도 (초당). 켤 때는 빠르게(약 0.3초) 줌아웃해 시야를 확보하되 부드럽게 감속하며 닿는다.
const ULT_K_IN := 6.5
const ULT_K_OUT := 3.0
## 락온 중 시선이 조준점 쪽으로 옮겨 가는 비율 (1 = 조준점이 정확히 화면 가운데)과 따라가는 속도
const ULT_FOCUS := 0.88
## 시선이 플레이어에게서 벗어날 수 있는 최대 거리 (m). 아주 먼 조준점에서도 플레이어가 화면에 남는다.
const ULT_LOOK_MAX := 7.5
const ULT_FOLLOW := 7.0


## 궁극기 락온: 크게 줌아웃해 주변을 보여 주고, 포인터 쪽으로 시야를 끌어 준다
func set_ult_view(on: bool) -> void:
	ult_on = on
	if on:
		zoom_v += 6.0
		fov_v += 30.0
	else:
		zoom_v -= 9.0
		fov_v -= 60.0
		kick_v += -ult_look * 0.12


## 광선검 기 모으기 줌: 단계가 오를 때마다 한 칸씩 툭 물러난다 (단단한 스프링 + 뒤로 차는 충격)
func set_charge_zoom(z: float) -> void:
	if z > charge_zoom + 0.001:
		zoom_v += (z - charge_zoom) * 9.0
	charge_zoom = z


## 줌 스프링. 궁극기 락온 중에는 훨씬 단단하게 당겨 거의 즉시 목표 줌에 닿는다 (살짝 넘쳤다 자리 잡는다).
## 단단한 스프링은 프레임이 길게 끊기면 발산하므로 1/240초 이하로 쪼개어 적분한다.
func _zoom_spring(dt: float, zoom_target: float) -> void:
	var stepped := charge_zoom > 1.001
	var stiff := 70.0 if ult_on or stepped else 40.0
	var damp := 15.0 if ult_on else (12.0 if stepped else 9.0)
	var left := minf(dt, 0.25)
	while left > 0.0:
		var h := minf(left, 1.0 / 240.0)
		left -= h
		zoom_v += ((zoom_target - zoom) * stiff - zoom_v * damp) * h
		zoom += zoom_v * h


## 보스전 카메라용: 락온 중 시선을 조준점 쪽으로 옮길 양 (ult_k 반영). 매 프레임 한 번 부른다.
var ult_shift := Vector3.ZERO


func _ult_aim_shift(dt: float, player: Player) -> Vector3:
	var want := Vector3.ZERO
	if (ult_on or player.ult_winding()) and player.alive:
		want = player.ult_aim_w - player.global_position
		want.y = 0.0
		want = (want * ULT_FOCUS).limit_length(ULT_LOOK_MAX)
	ult_shift = ult_shift.lerp(want, 1.0 - exp(-ULT_FOLLOW * dt))
	return ult_shift * ult_k


## 락온 순간 카메라 임팩트: 적 쪽으로 툭 끌렸다 돌아오고, 살짝 줌인 펀치 + 짧은 떨림. 락온이 쌓일수록 조금씩 세진다.
func lock_impact(at: Vector3, count: int) -> void:
	var k := 1.0 + minf(count - 1, 6) * 0.08
	var d := at - focus
	d.y = 0.0
	if d.length() > 0.01:
		kick_v += d.normalized() * 2.2 * k
	zoom_v -= 1.6 * k
	fov_v -= 26.0 * k
	roll += (0.012 if count % 2 == 0 else -0.012) * k
	shake(0.16 * k)


## FOV 펀치 · 반동 스프링 (줌 스프링과 같은 이유로 쪼개어 적분한다)
func _fov_kick_springs(dt: float) -> void:
	var left := minf(dt, 0.25)
	while left > 0.0:
		var h := minf(left, 1.0 / 240.0)
		left -= h
		fov_v += (-fov_add * 160.0 - fov_v * 14.0) * h
		fov_add += fov_v * h
		kick_v += (-kick_pos * 180.0 - kick_v * 18.0) * h
		kick_pos += kick_v * h


## 패링 성공: 적당한 줌인
func parry_cine(player: Player, foe: Node3D, foe_pos: Vector3) -> void:
	cine_start = Parry.now_ms()
	cine_player = player
	cine_foe = foe
	cine_foe_pos = foe_pos
	trauma = minf(trauma, 0.3)


func set_beam(on: bool, dir := Vector3.ZERO) -> void:
	beam_on = on
	if on:
		beam_dir = dir


# ── 갱신 ────────────────────────────────────────────────

func update(dt: float, player: Player) -> void:
	t += dt
	cur_offset = cur_offset.lerp(p.offset, 1.0 - exp(-4.0 * dt))
	cur_fov = lerpf(cur_fov, p.fov, 1.0 - exp(-4.0 * dt))

	var target := player.global_position
	target.y = player.view_y           # 점프로 화면이 출렁이지 않게 지면 높이(부드럽게)를 따른다
	var hv := Vector3(player.velocity.x, 0, player.velocity.z)
	if player.alive:
		var look := player.aim_point - player.global_position
		look.y = 0
		target += look.limit_length(6.0) * float(p.look) * (0.25 if beam_on else 1.0)
		lead = lead.lerp(hv * float(p.lead) * 0.35, 1.0 - exp(-3.0 * dt))
		target += lead
	_frame_bias = _frame_bias.lerp(frame_bias, 1.0 - exp(-3.0 * dt))
	target += _frame_bias
	# 강력 레이저: 발사 방향으로 시야를 터 준다
	var bias_target := beam_dir * 2.8 if beam_on else Vector3.ZERO
	beam_bias = beam_bias.lerp(bias_target, 1.0 - exp(-(2.5 if beam_on else 3.5) * dt))
	target += beam_bias
	# 격파 끌림
	if pull_t > 0.0:
		pull_t -= dt
	var pull_k := clampf(pull_t / 0.35, 0.0, 1.0)
	target += pull * pull_k * pull_k
	# 락온 중: 줌아웃하고, 시선을 월드 조준점(player.ult_aim_w) 쪽으로 옮겨 조준점이 화면 가운데 가깝게 오게 한다.
	# 조준점은 마우스 이동량으로 움직이는 월드 좌표라 카메라가 따라가도 끌려가지 않는다.
	ult_k = move_toward(ult_k, 1.0 if ult_on else 0.0, dt * (ULT_K_IN if ult_on else ULT_K_OUT))
	var look_target := Vector3.ZERO
	var follow := float(p.follow)
	if ult_on or player.ult_winding():
		var aim := player.ult_aim_w - player.global_position
		aim.y = 0.0
		look_target = (aim * ULT_FOCUS).limit_length(ULT_LOOK_MAX)
		follow = maxf(follow, ULT_FOLLOW)
	ult_look = ult_look.lerp(look_target, 1.0 - exp(-ULT_FOLLOW * dt))
	target = target.lerp(player.global_position + lead, ult_k)
	target += ult_look * ult_k
	focus = focus.lerp(target, 1.0 - exp(-follow * dt))

	# 줌: 기본 1, 부스터 속도에 비례해 줌아웃, 강력 레이저 시 크게 줌아웃
	var zoom_target := 1.0 + clampf(hv.length() / Player.BOOST_SPEED, 0.0, 1.0) * float(p.speed_zoom) * (1.0 if player.boosting else 0.35)
	if beam_on:
		zoom_target = 1.35
	zoom_target = lerpf(zoom_target, 1.75, ult_k)
	_frame_zoom = lerpf(_frame_zoom, frame_zoom, 1.0 - exp(-2.5 * dt))
	zoom_target *= _frame_zoom
	zoom_target = maxf(zoom_target, charge_zoom)
	_zoom_spring(dt, zoom_target)
	zoom = clampf(zoom, 0.82, 1.9)

	# FOV 스프링
	# FOV · 반동 스프링
	_fov_kick_springs(dt)

	# 좌우 이동에 따른 기울기 + 시네마틱 흔들림
	var roll_target := -hv.x * float(p.roll) * 0.1
	roll = lerpf(roll, roll_target, 1.0 - exp(-5.0 * dt))

	trauma = maxf(0.0, trauma - dt * 1.8)
	if beam_on:
		trauma = maxf(trauma, 0.32)
	shake_time += dt
	var s := trauma * trauma * 0.5
	var sway := Vector3(sin(t * 0.7), sin(t * 0.53) * 0.5, cos(t * 0.61)) * 0.25 * float(p.sway)
	_apply(Vector3(noise.get_noise_2d(shake_time * 260.0, 0.0), noise.get_noise_2d(0.0, shake_time * 260.0), 0.0) * s + sway)


func _apply(shake_off: Vector3) -> void:
	var cz := _cine_update()
	var shift: Vector3 = cz[1]
	var base: Vector3 = focus + kick_pos + shift
	var z: float = zoom * lerpf(1.0, CINE_ZOOM, cz[0])
	fov = clampf(cur_fov + fov_add, 20.0, 80.0)
	size = 13.0 * z
	global_position = base + cur_offset * z
	look_at(base, Vector3.UP)
	# 흔들림은 화면 평면 기준
	global_position += global_basis.x * shake_off.x + global_basis.y * shake_off.y
	global_position.z += shake_off.z
	rotate_object_local(Vector3.FORWARD, roll)


## 패링 줌 진행: [가중치 0~1, 시선 이동량]. 들어갈 때는 급격히, 나올 때는 부드럽게.
func _cine_update() -> Array:
	if cine_start < 0:
		return [0.0, Vector3.ZERO]
	var e := (Parry.now_ms() - cine_start) * 0.001
	if e >= CINE_END or not is_instance_valid(cine_player):
		cine_start = -1
		cine_w = 0.0
		return [0.0, Vector3.ZERO]
	if e < CINE_IN:
		cine_w = 1.0 - pow(1.0 - e / CINE_IN, 3.0)
	elif e < CINE_HOLD:
		cine_w = 1.0
	else:
		cine_w = 1.0 - smoothstep(CINE_HOLD, CINE_END, e)
	if is_instance_valid(cine_foe):
		cine_foe_pos = cine_foe_pos.lerp(cine_foe.global_position, 0.25)
	var d := cine_foe_pos - cine_player.global_position
	d.y = 0
	return [cine_w, d.limit_length(8.0) * 0.5 * CINE_SHIFT * cine_w]
