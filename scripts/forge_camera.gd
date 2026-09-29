extends CameraRig
## 용광로 보스전 카메라: 팔각 발판 전체와 북쪽의 거신을 한 화면에 담는 높은 쿼터뷰.
## 전장 중심 쪽에 무게를 두고 플레이어를 조금만 따라간다. 흔들림·반동·FOV 펀치는 CameraRig 것을 쓴다.

const OFFSET := Vector3(0, 40.0, 33.6)
const FOV := 40.0
const CENTER := Vector3(0, 0, -5.0)
const FOLLOW := 0.18

var boss: Node3D


func _ready() -> void:
	super._ready()
	cur_offset = OFFSET
	cur_fov = FOV


func snap(target: Vector3) -> void:
	focus = CENTER.lerp(target, FOLLOW)
	cur_offset = OFFSET
	cur_fov = FOV
	_apply(Vector3.ZERO)


func update(dt: float, player: Player) -> void:
	t += dt
	var target := CENTER.lerp(Vector3(player.global_position.x, 0, player.global_position.z), FOLLOW)
	if player.alive:
		var look := player.aim_point - player.global_position
		look.y = 0
		target += look.limit_length(6.0) * 0.06
	if pull_t > 0.0:
		pull_t -= dt
	var pull_k := clampf(pull_t / 0.35, 0.0, 1.0)
	target += pull * pull_k * pull_k * 0.5
	focus = focus.lerp(target, 1.0 - exp(-4.0 * dt))

	ult_k = move_toward(ult_k, 1.0 if ult_on else 0.0, dt * (5.0 if ult_on else 3.0))
	var zoom_target := lerpf(1.0, 1.18, ult_k)
	if beam_on:
		zoom_target = 1.08
	zoom_v += ((zoom_target - zoom) * 40.0 - zoom_v * 9.0) * dt
	zoom += zoom_v * dt
	zoom = clampf(zoom, 0.88, 1.4)

	fov_v += (-fov_add * 160.0 - fov_v * 14.0) * dt
	fov_add += fov_v * dt
	kick_v += (-kick_pos * 180.0 - kick_v * 18.0) * dt
	kick_pos += kick_v * dt
	roll = lerpf(roll, -player.velocity.x * 0.0015, 1.0 - exp(-4.0 * dt))

	trauma = maxf(0.0, trauma - dt * 1.8)
	if beam_on:
		trauma = maxf(trauma, 0.25)
	shake_time += dt
	var s := trauma * trauma * 0.6
	cur_offset = OFFSET
	cur_fov = FOV
	_apply(Vector3(noise.get_noise_2d(shake_time * 260.0, 0.0), noise.get_noise_2d(0.0, shake_time * 260.0), 0.0) * s)
