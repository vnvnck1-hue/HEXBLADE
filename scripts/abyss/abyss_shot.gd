extends Bullet
## 심연 성소의 적탄: 진행 방향으로 볼록한 초승달. 판정·피격·검으로 지우기는 Bullet 과 같다.
## 덧붙인 움직임: accel(속도 변화) · turn(초당 회전각, 나선탄) · delay(잠깐 멈췄다가 출발).

var accel := 0.0
var turn := 0.0
var delay := 0.0
var max_speed := 14.0
var min_speed := 1.5
var visual: MeshInstance3D
var _dir := Vector3.FORWARD
var _speed := 0.0
var _base_scale := 0.6


static func make(pos: Vector3, dir: Vector3, speed: float, c := Color(1.0, 0.1, 0.25), size := 0.62) -> Bullet:
	var b = load("res://scripts/abyss/abyss_shot.gd").new()
	b.from_player = false
	var d := Vector3(dir.x, 0, dir.z).normalized()
	b.vel = d * speed
	b._dir = d
	b._speed = speed
	b.radius = 0.17 + size * 0.06
	b.life = 6.0
	# Bullet 의 변색 연출은 쓰지 않는다 (보이지 않는 빈 메시)
	b.mesh = MeshInstance3D.new()
	b.add_child(b.mesh)
	b._base_scale = size
	b.visual = AbyssFX.crescent_mesh(c, size)
	b.add_child(b.visual)
	b.position = pos
	return b


func _physics_process(dt: float) -> void:
	if delay > 0.0:
		delay -= dt
		vel = Vector3.ZERO
		age += dt
		if delay <= 0.0:
			vel = _dir * _speed
		_orient(_base_scale * (0.7 + 0.3 * sin(age * 30.0)))
		# 정지 중에도 판정은 남긴다 (Bullet 이 처리)
		super._physics_process(0.0)
		return
	if turn != 0.0 or accel != 0.0:
		_speed = clampf(_speed + accel * dt, min_speed, max_speed)
		if turn != 0.0:
			_dir = _dir.rotated(Vector3.UP, turn * dt)
		vel = _dir * _speed
	super._physics_process(dt)
	if is_instance_valid(visual):
		# 사라지기 직전 줄어든다
		_orient(_base_scale * (0.35 + 0.65 * clampf(life / 0.3, 0.0, 1.0)))


func _orient(s: float) -> void:
	var d := _dir if vel.length() < 0.01 else vel.normalized()
	d.y = 0
	if d.length() > 0.01:
		visual.basis = Basis.looking_at(d.normalized(), Vector3.UP).scaled(Vector3(s, 1.0, s))
