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
		"name": "TACTICAL", "desc": "높고 넓은 시야 · 절제된 반응",
		"offset": Vector3(0, 15.0, 8.0), "fov": 36.0, "follow": 7.0, "look": 0.12, "lead": 0.08,
		"roll": 0.0, "punch": 0.3, "speed_zoom": 0.08, "kill_pull": 0.3, "sway": 0.0,
	},
]

var preset_index := 1
var p: Dictionary = PRESETS[1]
var cur_offset: Vector3 = PRESETS[1].offset
var cur_fov: float = PRESETS[1].fov

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
var roll := 0.0
var pull := Vector3.ZERO  # 격파 지점 쪽으로 잠깐 끌림
var pull_t := 0.0
var beam_on := false
var beam_dir := Vector3.ZERO
var beam_bias := Vector3.ZERO
var ult_on := false
var ult_k := 0.0          # 락온 시야 전환 정도 (0~1)
var ult_look := Vector3.ZERO
var ult_prev_ptr := Vector2.ZERO
var noise := FastNoiseLite.new()
var t := 0.0
# 패링 시네마틱: 플레이어 등 뒤 어깨 너머로 파고들어 플레이어와 적을 한 화면에 담는다 (실제 시간으로 진행)
const CINE_IN := 0.12
const CINE_HOLD := 0.8
const CINE_END := 1.25
var cine_start := -1
var cine_player: Player
var cine_foe: Node3D
var cine_foe_pos := Vector3.ZERO
var cine_side := 1.0
var cine_back := 2.6
var cine_prev_proj := -1
var cine_w := 0.0


func _ready() -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	far = 200.0
	ToonOutline.attach(self)


func set_preset(i: int) -> void:
	preset_index = posmod(i, PRESETS.size())
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


## 궁극기 락온: 크게 줌아웃해 주변을 보여 주고, 포인터 쪽으로 시야를 끌어 준다
func set_ult_view(on: bool) -> void:
	ult_on = on
	if on:
		zoom_v += 6.0
		fov_v += 40.0
	else:
		zoom_v -= 9.0
		fov_v -= 60.0
		kick_v += -ult_look * 1.5


## 패링 성공: 등 뒤 극적 구도로 전환
func parry_cine(player: Player, foe: Node3D, foe_pos: Vector3) -> void:
	cine_start = Parry.now_ms()
	cine_player = player
	cine_foe = foe
	cine_foe_pos = foe_pos
	# 지금 카메라가 있는 쪽 어깨로 돌아 들어가 휘감는 움직임이 짧고 자연스럽게
	var d := foe_pos - player.global_position
	d.y = 0
	d = d.normalized() if d.length() > 0.01 else player.aim_dir
	var side := Vector3(-d.z, 0, d.x)
	var cam_rel := global_position - player.global_position
	cine_side = 1.0 if cam_rel.dot(side) >= 0.0 else -1.0
	if projection == PROJECTION_ORTHOGONAL:
		cine_prev_proj = PROJECTION_ORTHOGONAL
		projection = PROJECTION_PERSPECTIVE
	trauma = minf(trauma, 0.3)


func cine_active() -> bool:
	return cine_start >= 0


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
	var hv := Vector3(player.velocity.x, 0, player.velocity.z)
	if player.alive:
		var look := player.aim_point - player.global_position
		look.y = 0
		target += look.limit_length(6.0) * float(p.look) * (0.25 if beam_on else 1.0)
		lead = lead.lerp(hv * float(p.lead) * 0.35, 1.0 - exp(-3.0 * dt))
		target += lead
	# 강력 레이저: 발사 방향으로 시야를 터 준다
	var bias_target := beam_dir * 2.8 if beam_on else Vector3.ZERO
	beam_bias = beam_bias.lerp(bias_target, 1.0 - exp(-(2.5 if beam_on else 3.5) * dt))
	target += beam_bias
	# 격파 끌림
	if pull_t > 0.0:
		pull_t -= dt
	var pull_k := clampf(pull_t / 0.35, 0.0, 1.0)
	target += pull * pull_k * pull_k
	# 락온 중: 줌아웃만 하고 시야는 거의 고정한다 (포인터를 따라 화면이 움직이면 조준이 어렵다).
	# 조준 방향 시야 이동도 걷어 내고, 포인터 쪽으로는 아주 살짝만 기운다.
	ult_k = move_toward(ult_k, 1.0 if ult_on else 0.0, dt * (5.0 if ult_on else 3.0))
	var look_target := Vector3.ZERO
	var roll_add := 0.0
	if ult_on:
		var vs := get_viewport().get_visible_rect().size
		var m := (player.ult_ptr - vs * 0.5) / (vs * 0.5)
		m = m.limit_length(1.0)
		look_target = Vector3(m.x, 0, m.y * 1.3) * 0.35
	ult_prev_ptr = player.ult_ptr
	ult_look = ult_look.lerp(look_target, 1.0 - exp(-3.0 * dt))
	target = target.lerp(player.global_position + lead, ult_k)
	target += ult_look
	focus = focus.lerp(target, 1.0 - exp(-float(p.follow) * dt))

	# 줌: 기본 1, 부스터 속도에 비례해 줌아웃, 강력 레이저 시 크게 줌아웃
	var zoom_target := 1.0 + clampf(hv.length() / Player.BOOST_SPEED, 0.0, 1.0) * float(p.speed_zoom) * (1.0 if player.boosting else 0.35)
	if beam_on:
		zoom_target = 1.35
	zoom_target = lerpf(zoom_target, 1.75, ult_k)
	zoom_v += ((zoom_target - zoom) * 40.0 - zoom_v * 9.0) * dt
	zoom += zoom_v * dt
	zoom = clampf(zoom, 0.82, 1.9)

	# FOV 스프링
	fov_v += (-fov_add * 160.0 - fov_v * 14.0) * dt
	fov_add += fov_v * dt

	# 반동 스프링
	kick_v += (-kick_pos * 180.0 - kick_v * 18.0) * dt
	kick_pos += kick_v * dt

	# 좌우 이동에 따른 기울기 + 시네마틱 흔들림
	var roll_target := -hv.x * float(p.roll) * 0.1
	roll = lerpf(roll, roll_target, 1.0 - exp(-5.0 * dt)) + roll_add

	trauma = maxf(0.0, trauma - dt * 1.8)
	if beam_on:
		trauma = maxf(trauma, 0.32)
	shake_time += dt
	var s := trauma * trauma * 0.5
	var sway := Vector3(sin(t * 0.7), sin(t * 0.53) * 0.5, cos(t * 0.61)) * 0.25 * float(p.sway)
	_apply(Vector3(noise.get_noise_2d(shake_time * 260.0, 0.0), noise.get_noise_2d(0.0, shake_time * 260.0), 0.0) * s + sway)


func _apply(shake_off: Vector3) -> void:
	var base := focus + kick_pos
	fov = clampf(cur_fov + fov_add, 20.0, 80.0)
	size = 13.0 * zoom
	global_position = base + cur_offset * zoom
	look_at(base, Vector3.UP)
	# 흔들림은 화면 평면 기준
	global_position += global_basis.x * shake_off.x + global_basis.y * shake_off.y
	global_position.z += shake_off.z
	rotate_object_local(Vector3.FORWARD, roll)
	_apply_cine(shake_off, base)


func _apply_cine(shake_off: Vector3, base_look: Vector3) -> void:
	if cine_start < 0:
		return
	var e := (Parry.now_ms() - cine_start) * 0.001
	if e >= CINE_END or not is_instance_valid(cine_player):
		cine_start = -1
		cine_w = 0.0
		if cine_prev_proj >= 0:
			projection = cine_prev_proj as ProjectionType
			cine_prev_proj = -1
		return
	# 들어갈 때는 급격히(지수 감속), 나올 때는 부드럽게
	if e < CINE_IN:
		cine_w = 1.0 - pow(1.0 - e / CINE_IN, 3.0)
	elif e < CINE_HOLD:
		cine_w = 1.0
	else:
		cine_w = 1.0 - smoothstep(CINE_HOLD, CINE_END, e)
	var pp := cine_player.global_position
	if is_instance_valid(cine_foe):
		cine_foe_pos = cine_foe_pos.lerp(cine_foe.global_position, 0.25)
	var d := cine_foe_pos - pp
	d.y = 0
	var dist := d.length()
	d = d / dist if dist > 0.01 else cine_player.aim_dir
	var side := Vector3(-d.z, 0, d.x) * cine_side
	# 천천히 밀고 들어가며(돌리) 어깨 쪽으로 살짝 돈다
	var push := smoothstep(0.0, CINE_HOLD, e)
	var back := lerpf(3.1, 2.2, push)
	# 근접처럼 적이 가까우면 플레이어 몸에 가리지 않도록 옆으로 더 빼고 조금 더 물러선다
	var near := clampf((4.5 - dist) / 3.0, 0.0, 1.0)
	back = lerpf(back, lerpf(1.9, 1.5, push), near)
	var lat := lerpf(lerpf(1.55, 1.2, push), lerpf(2.9, 2.5, push), near)
	var h := lerpf(1.8, 1.5, push)
	var off := -d * back + side * lat
	var cam := pp + off * _cine_clear(pp, off) + Vector3(0, h, 0)
	# 시선: 플레이어 너머 적 쪽. 적이 멀면 중간쯤을 봐서 둘 다 화면에 들어오게 한다
	# 시선을 적 쪽 어깨 반대편으로 살짝 비켜 플레이어가 화면 한쪽, 적이 반대쪽에 서게 한다
	var look := pp + d * lerpf(clampf(dist * 0.6, 1.5, 5.0), dist * 0.55 + 0.4, near) - side * 0.35 * (1.0 - near) + Vector3(0, lerpf(1.05, 0.95, push), 0)
	# 눈 위치와 시선점을 따로 보간해 전환 중에도 플레이어가 화면을 벗어나지 않게 한다
	var w := cine_w
	var eye := global_position.lerp(cam, w)
	var tgt := base_look.lerp(look, w)
	var b := Basis.looking_at(tgt - eye, Vector3.UP)
	# 더치 앵글: 어깨 쪽으로 기울인다
	b = b * Basis(Vector3.FORWARD, deg_to_rad(7.0) * cine_side * (0.6 + 0.4 * push) * w + roll * (1.0 - w))
	var sh := (b.x * shake_off.x + b.y * shake_off.y) * 0.5 * w
	global_transform = Transform3D(b, eye + sh)
	fov = lerpf(fov, lerpf(62.0, 50.0, push), cine_w)


## 플레이어 뒤쪽이 벽에 막히면 카메라를 벽 앞까지 당긴다 (오프셋에 곱할 비율)
func _cine_clear(pp: Vector3, off: Vector3) -> float:
	var main := Main.inst
	if main == null:
		return 1.0
	var n := 12
	var l := maxf(off.length(), 0.01)
	for i in range(1, n + 1):
		var k := float(i) / n
		if main.is_blocked(pp + off * k):
			return clampf(k - 0.35 / l, 0.3, 1.0)
	return 1.0
