extends CameraRig
## 추격 보스전 카메라: 플레이어와 보스를 함께 담는 높은 쿼터뷰.
## 흔들림·반동·FOV 펀치는 CameraRig 것을 그대로 쓰고, 초점과 속도 진동만 따로 계산한다.

## 통일 시야(TACTICAL 62° · 화각 36°). 거대한 보스와 함께 담으려고 거리만 1.55배 (예전 (0,19,11) · 화각 50° 와 보이는 넓이가 같다)
const OFFSET := Vector3(0, 18.0, 9.6) * 1.55
const FOV := CameraRig.VIEW_FOV

var boss: Node3D
var speed_k := 1.0        # 흐르는 속도 비율 (진동·FOV 에 반영)


func _ready() -> void:
	super._ready()
	cur_offset = OFFSET
	cur_fov = FOV


func update(dt: float, player: Player) -> void:
	t += dt
	var target := player.global_position
	if boss and is_instance_valid(boss):
		# 보스 쪽으로 35% 당겨서 둘 다 화면에 들어오게 한다. 좌우는 플레이어를 더 따라간다.
		var b := boss.global_position
		target = Vector3(lerpf(player.global_position.x, b.x, 0.25) * 0.8, 0, lerpf(player.global_position.z, b.z, 0.4))
	if player.alive:
		var look := player.aim_point - player.global_position
		look.y = 0
		target += look.limit_length(5.0) * 0.08
	if pull_t > 0.0:
		pull_t -= dt
	target += _ult_aim_shift(dt, player)
	focus = focus.lerp(target, 1.0 - exp(-5.0 * dt))

	ult_k = move_toward(ult_k, 1.0 if ult_on else 0.0, dt * (ULT_K_IN if ult_on else ULT_K_OUT))
	var zoom_target := lerpf(1.0, 1.25, ult_k)
	if beam_on:
		zoom_target = 1.12
	_zoom_spring(dt, zoom_target)
	zoom = clampf(zoom, 0.85, 1.5)

	_fov_kick_springs(dt)
	# 좌우 이동에 따라 살짝 기울어 비행감을 준다
	var roll_target := -player.velocity.x * 0.004
	roll = lerpf(roll, roll_target, 1.0 - exp(-4.0 * dt))

	trauma = maxf(0.0, trauma - dt * 1.8)
	if beam_on:
		trauma = maxf(trauma, 0.3)
	shake_time += dt
	var s := trauma * trauma * 0.5
	# 고속 주행 진동: 미세하고 빠른 떨림이 계속된다
	var buzz := Vector3(noise.get_noise_2d(t * 400.0, 7.0), noise.get_noise_2d(3.0, t * 400.0), 0.0) * 0.035 * speed_k
	cur_offset = OFFSET
	cur_fov = FOV + 4.0 * clampf(speed_k - 1.0, 0.0, 1.0)
	_apply(Vector3(noise.get_noise_2d(shake_time * 260.0, 0.0), noise.get_noise_2d(0.0, shake_time * 260.0), 0.0) * s + buzz)
