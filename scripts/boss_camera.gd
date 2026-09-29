extends CameraRig
## 추격 보스전 카메라: 플레이어와 보스를 함께 담는 높은 쿼터뷰.
## 흔들림·반동·FOV 펀치는 CameraRig 것을 그대로 쓰고, 초점과 속도 진동만 따로 계산한다.

const OFFSET := Vector3(0, 19.0, 11.0)
const FOV := 50.0

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
	focus = focus.lerp(target, 1.0 - exp(-5.0 * dt))

	ult_k = move_toward(ult_k, 1.0 if ult_on else 0.0, dt * (5.0 if ult_on else 3.0))
	var zoom_target := lerpf(1.0, 1.25, ult_k)
	if beam_on:
		zoom_target = 1.12
	zoom_v += ((zoom_target - zoom) * 40.0 - zoom_v * 9.0) * dt
	zoom += zoom_v * dt
	zoom = clampf(zoom, 0.85, 1.5)

	fov_v += (-fov_add * 160.0 - fov_v * 14.0) * dt
	fov_add += fov_v * dt
	kick_v += (-kick_pos * 180.0 - kick_v * 18.0) * dt
	kick_pos += kick_v * dt
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
