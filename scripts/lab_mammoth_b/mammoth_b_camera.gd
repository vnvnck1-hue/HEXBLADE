extends Camera3D
## B안 죽음 연출 카메라. 전투 카메라(BossCamera)는 그대로 두고, 연출 중에만 이 카메라가 current 가 된다.
## 연출 감독이 매 프레임 눈 위치·시선·FOV·기울기를 넘기면, 흔들림(상한 적용)과 FOV 펀치를 더해 적용한다.
## 모든 값은 연출 시간(실제 시간 기반)으로 계산해 프레임률과 무관하게 같은 결과가 나온다.

const WALL_X := 11.3               # 양옆 구조물 안쪽으로 눈이 들어가지 않게

var noise := FastNoiseLite.new()
var shake_k := 1.0                 # 접근성 옵션 (0 / 0.5 / 1)
## [시작 시각, 이동 m, 회전 도, 감쇠 s]
var _shakes: Array = []
## [시작 시각, FOV 변화 도]
var _punches: Array = []
var rumble := 0.0                  # 지속 진동 (m)


func _ready() -> void:
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.05
	near = 0.1
	far = 200.0


func add_shake(t0: float, move_m: float, rot_deg: float, decay: float) -> void:
	_shakes.append([t0, move_m, rot_deg, decay])


func add_punch(t0: float, deg: float) -> void:
	_punches.append([t0, deg])


## eye/look 는 월드 좌표. T 는 연출 시간
func frame(T: float, eye: Vector3, look: Vector3, fov_deg: float, roll_deg: float) -> void:
	# 구조물 가림 보정: 옆벽 안쪽으로 밀어 넣고 그만큼 높이·뒤로 물러난다
	var over := absf(eye.x) - WALL_X
	if over > 0.0:
		eye.x = signf(eye.x) * WALL_X
		eye.y += over * 0.8
		eye.z += over * 0.6
	eye.y = maxf(eye.y, 0.8)
	var mv := 0.0
	var rot := 0.0
	for s in _shakes:
		var e: float = T - s[0]
		if e < 0.0:
			continue
		var k := exp(-e / maxf(s[3], 0.01) * 2.3)
		mv = maxf(mv, s[1] * k)
		rot = maxf(rot, s[2] * k)
	mv = maxf(mv, rumble)
	mv *= shake_k
	rot *= shake_k
	var fov_add := 0.0
	for p in _punches:
		var e: float = T - p[0]
		if e >= 0.0 and e < 0.6:
			fov_add += p[1] * exp(-e * 9.0) * cos(e * 22.0)
	fov = clampf(fov_deg + fov_add * shake_k, 20.0, 80.0)
	var n := T * 55.0
	global_position = eye
	if eye.distance_to(look) > 0.01:
		look_at(look, Vector3.UP)
	global_position += global_basis.x * noise.get_noise_2d(n, 3.0) * mv * 1.6 + global_basis.y * noise.get_noise_2d(7.0, n) * mv * 1.6
	rotate_object_local(Vector3.FORWARD, deg_to_rad(roll_deg * shake_k + noise.get_noise_2d(n, 11.0) * rot * 1.6))
