extends CameraRig
## 용광로 보스전 카메라.
## 0번(HIGH)은 팔각 발판 전체와 북쪽의 거신을 한 화면에 담는 높은 쿼터뷰 (기존 구도).
## 1번부터는 영화적 구도: 카메라가 주인공 뒤(남쪽) 낮은 곳에서 보스를 바라본다.
##  - 기준점(anchor) = 전장 중심과 플레이어 사이 (follow 비율)
##  - 카메라   = anchor 뒤로 back, 위로 height (orbit 이면 보스→플레이어 축 위, shoulder 만큼 옆으로)
##  - 시선     = anchor 에서 보스 쪽으로 look_k 만큼 + look_y 높이 → 주인공은 화면 아래, 보스는 위쪽에 선다
## 광각: wide 만큼 화각을 넓히며 그만큼 시선 쪽으로 당겨(돌리 보정) 구도는 두고 원근만 과장하고,
## lens 세기로 LensFX 배럴 왜곡을 건다. L 키로 끔 / 살짝 / 강하게, --lens=N 으로 시작 단계 지정.
## 흔들림·반동·FOV 펀치·패링 줌은 CameraRig 것을 쓴다. V 키로 순환, --campreset=N 으로 시작 프리셋 지정.

const OFFSET := Vector3(0, 40.0, 33.6)
const FOV := 40.0
const CENTER := Vector3(0, 0, -5.0)
const FOLLOW := 0.18
const BOSS_AT := Vector3(0, 0, -16.5)
const LensFX := preload("res://scripts/presentation/lens_fx.gd")
const LENS_LEVELS := [["OFF", "광각 끔", 0.0], ["SUBTLE", "살짝 광각 · 약한 배럴 왜곡", 1.0], ["STRONG", "강한 광각 · 뚜렷한 배럴 왜곡", 1.9]]

const SHOTS := [
	{
		"name": "HIGH", "desc": "기존 · 높은 부감 쿼터뷰 (전장 전체)",
		"legacy": true, "punch": 1.0, "kill_pull": 0.0,
	},
	{
		"name": "HERO LOW", "desc": "낮은 3/4 뒤 · 주인공 하단 1/3, 거신이 화면 위를 채운다",
		"fov": 40.0, "height": 15.0, "back": 21.0, "follow": 0.5, "look_k": 0.34, "look_y": 3.2,
		"orbit": 0.0, "shoulder": 0.0, "yaw": 0.0, "dutch": 0.0, "lag": 4.0, "sway": 0.35,
		"wide": 10.0, "lens": 0.07,
		"punch": 1.0, "kill_pull": 0.0,
	},
	{
		"name": "TITAN LOOK-UP", "desc": "지면 가까운 앙각 · 광각으로 거신을 올려다본다",
		"fov": 56.0, "height": 7.6, "back": 12.5, "follow": 0.78, "look_k": 0.3, "look_y": 4.2,
		"orbit": 0.0, "shoulder": 0.0, "yaw": 0.0, "dutch": 0.0, "lag": 3.5, "sway": 0.6,
		"wide": 8.0, "lens": 0.09,
		"punch": 1.2, "kill_pull": 0.0,
	},
	{
		"name": "OVER SHOULDER", "desc": "어깨 너머 · 보스-주인공 축을 따라 돌며 항상 정면 대치",
		"fov": 46.0, "height": 9.5, "back": 12.5, "follow": 1.0, "look_k": 0.36, "look_y": 3.6,
		"orbit": 1.0, "shoulder": 2.6, "yaw": 0.0, "dutch": 0.0, "lag": 3.0, "sway": 0.4,
		"wide": 10.0, "lens": 0.07,
		"punch": 1.0, "kill_pull": 0.0,
	},
	{
		"name": "TELEPHOTO", "desc": "망원 압축 · 멀리서 좁은 화각, 거신이 주인공 바로 뒤에 솟은 듯",
		"fov": 21.0, "height": 22.0, "back": 54.0, "follow": 0.45, "look_k": 0.4, "look_y": 4.6,
		"orbit": 0.0, "shoulder": 0.0, "yaw": 0.0, "dutch": 0.0, "lag": 3.0, "sway": 0.25,
		"wide": 0.0, "lens": 0.00,
		"punch": 0.6, "kill_pull": 0.0,
	},
	{
		"name": "DUTCH ANGLE", "desc": "사선 뒤 · 기울어진 수평선으로 긴장감",
		"fov": 44.0, "height": 11.5, "back": 17.0, "follow": 0.6, "look_k": 0.36, "look_y": 3.6,
		"orbit": 0.0, "shoulder": 0.0, "yaw": 34.0, "dutch": 11.0, "lag": 3.5, "sway": 0.5,
		"wide": 10.0, "lens": 0.08,
		"punch": 1.0, "kill_pull": 0.0,
	},
]

var boss: Node3D
var shot: Dictionary = SHOTS[0]
var shot_index := 0
var _cam_pos := Vector3.ZERO
var _look := Vector3.ZERO
var _anchor := Vector3.ZERO
var _axis := Vector3.BACK      # 보스 → 카메라 수평 방향 (orbit 용, 부드럽게 돈다)
var _started := false
var lens_level := 1
var _lens_amt := 1.0               # 단계 전환을 부드럽게


func _ready() -> void:
	super._ready()
	cur_offset = OFFSET
	cur_fov = FOV
	set_preset(0)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lens="):
			lens_level = clampi(int(a.substr(7)), 0, LENS_LEVELS.size() - 1)
	_lens_amt = LENS_LEVELS[lens_level][2]
	var lf := LensFX.new()
	lf.cam = self
	add_child(lf)


func cycle_lens() -> Array:
	lens_level = (lens_level + 1) % LENS_LEVELS.size()
	var lv: Array = LENS_LEVELS[lens_level]
	return [lv[0], lv[1]]


## CameraRig 프리셋 대신 SHOTS 를 쓴다. p 는 fov_punch 등 공용 반응 계수용.
func set_preset(i: int) -> void:
	shot_index = posmod(i, SHOTS.size())
	preset_index = shot_index
	shot = SHOTS[shot_index]
	p = {"name": shot.name, "desc": shot.desc, "punch": shot.punch, "kill_pull": shot.kill_pull}
	_started = false


func snap(target: Vector3) -> void:
	focus = CENTER.lerp(target, FOLLOW)
	cur_offset = OFFSET
	cur_fov = FOV
	_started = false
	if shot.get("legacy", false):
		_apply(Vector3.ZERO)
	else:
		_shot_update(0.0, target, Vector3.ZERO, true)


func update(dt: float, player: Player) -> void:
	t += dt
	if pull_t > 0.0:
		pull_t -= dt
	ult_k = move_toward(ult_k, 1.0 if ult_on else 0.0, dt * (ULT_K_IN if ult_on else ULT_K_OUT))
	var zoom_target := lerpf(1.0, 1.18, ult_k)
	if beam_on:
		zoom_target = 1.08
	_zoom_spring(dt, zoom_target)
	zoom = clampf(zoom, 0.88, 1.4)

	_fov_kick_springs(dt)

	trauma = maxf(0.0, trauma - dt * 1.8)
	if beam_on:
		trauma = maxf(trauma, 0.25)
	shake_time += dt
	var s := trauma * trauma * 0.6
	var shake_off := Vector3(noise.get_noise_2d(shake_time * 260.0, 0.0), noise.get_noise_2d(0.0, shake_time * 260.0), 0.0) * s

	var pp := Vector3(player.global_position.x, 0, player.global_position.z)
	var aim_shift := _ult_aim_shift(dt, player)
	if shot.get("legacy", false):
		var target := CENTER.lerp(pp, FOLLOW)
		if player.alive:
			var look := player.aim_point - player.global_position
			look.y = 0
			target += look.limit_length(6.0) * 0.06
		var pull_k := clampf(pull_t / 0.35, 0.0, 1.0)
		target += pull * pull_k * pull_k * 0.5
		target += aim_shift
		focus = focus.lerp(target, 1.0 - exp(-4.0 * dt))
		roll = lerpf(roll, -player.velocity.x * 0.0015, 1.0 - exp(-4.0 * dt))
		cur_offset = OFFSET
		cur_fov = FOV
		lens_k = 0.0
		_apply(shake_off)
		return
	_lens_amt = move_toward(_lens_amt, LENS_LEVELS[lens_level][2], dt * 3.0)
	roll = lerpf(roll, -player.velocity.x * 0.0025, 1.0 - exp(-4.0 * dt))
	_shot_update(dt, pp, shake_off, false)


func _boss_ground() -> Vector3:
	if is_instance_valid(boss):
		return Vector3(boss.global_position.x, 0, boss.global_position.z)
	return BOSS_AT


func _shot_update(dt: float, pp: Vector3, shake_off: Vector3, instant: bool) -> void:
	var bg := _boss_ground()
	var anchor := CENTER.lerp(pp, float(shot.follow))
	# 카메라가 놓일 수평 방향: 기본은 정남(+Z)에서 yaw 만큼 돌린 쪽, orbit 이면 보스→플레이어 축
	var base_dir := Vector3.BACK.rotated(Vector3.UP, deg_to_rad(float(shot.yaw)))
	var od := pp - bg
	od.y = 0
	var orbit_dir := od.normalized() if od.length() > 0.5 else Vector3.BACK
	var want_axis := base_dir.slerp(orbit_dir, float(shot.orbit)).normalized()
	var k := 1.0 if instant or not _started else 1.0 - exp(-2.2 * dt)
	_axis = _axis.slerp(want_axis, k).normalized()
	var side := Vector3.UP.cross(_axis).normalized()     # 화면 오른쪽
	var cam_target := anchor + _axis * float(shot.back) + Vector3.UP * float(shot.height) + side * float(shot.shoulder)
	var look_target := anchor.lerp(bg, float(shot.look_k)) + Vector3.UP * float(shot.look_y)
	# 궁극기 락온: 카메라와 시선을 함께 조준점 쪽으로 옮긴다
	cam_target += ult_shift * ult_k
	look_target += ult_shift * ult_k
	# 격파 끌림 · 패링 줌은 시선 쪽으로
	var pull_k := clampf(pull_t / 0.35, 0.0, 1.0)
	look_target += pull * pull_k * pull_k * 0.5
	# 호흡하듯 아주 느린 흔들림 (핸드헬드 느낌)
	var sw := float(shot.sway)
	cam_target += Vector3(sin(t * 0.47), sin(t * 0.61) * 0.6, cos(t * 0.39) * 0.5) * 0.35 * sw
	if instant or not _started:
		_cam_pos = cam_target
		_look = look_target
		_anchor = anchor
		_started = true
	else:
		var lk := 1.0 - exp(-float(shot.lag) * dt)
		_cam_pos = _cam_pos.lerp(cam_target, lk)
		_look = _look.lerp(look_target, 1.0 - exp(-float(shot.lag) * 1.4 * dt))
		_anchor = _anchor.lerp(anchor, lk)

	var cz := _cine_update()
	var shift: Vector3 = cz[1]
	var z: float = zoom * lerpf(1.0, CINE_ZOOM, cz[0])
	# 광각 돌리 보정: 화각을 넓힌 만큼 시선 쪽으로 다가가 시선 지점의 크기는 그대로 둔다
	var f0 := float(shot.fov)
	var f1 := f0 + float(shot.get("wide", 0.0)) * _lens_amt
	# 다가간 만큼 가까운 주인공이 화면 아래로 밀려나므로 시선을 주인공 쪽으로 조금 내린다
	var fix := clampf((f1 - f0) / 10.0, 0.0, 2.0) * 0.13
	var look := _look.lerp(_anchor + Vector3.UP * 1.2, fix) + shift + kick_pos
	z *= tan(deg_to_rad(f0) * 0.5) / tan(deg_to_rad(f1) * 0.5)
	lens_k = float(shot.get("lens", 0.0)) * _lens_amt
	var cp := look + (_cam_pos - _look) * z
	cp.y = maxf(cp.y, 1.2)
	fov = clampf(f1 + fov_add, 12.0, 95.0)
	size = 13.0 * z
	global_position = cp
	look_at(look, Vector3.UP)
	global_position += global_basis.x * shake_off.x + global_basis.y * shake_off.y
	rotate_object_local(Vector3.FORWARD, roll + deg_to_rad(float(shot.dutch)))
