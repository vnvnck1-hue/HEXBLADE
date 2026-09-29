class_name Bullet
extends Node3D
## 플레이어탄 / 적탄. 판정은 수평 거리로 단순화한다.

static var _p_mesh: CylinderMesh
static var _e_mesh: SphereMesh
static var _e_core: SphereMesh

var vel := Vector3.ZERO
var life := 2.0
var from_player := true
var radius := 0.15
var age := 0.0
var mesh: MeshInstance3D
var color_phase := 0
var streak: Node3D
var origin := Vector3.ZERO

const STREAK_LEN := 1.5


## 플레이어탄: 머리(현재 위치)에서 뒤로 길게 뻗는 레이저형 광선. 발사 직후에는 총구에서 자라난다.
static func make_player(pos: Vector3, dir: Vector3, speed: float) -> Bullet:
	if _p_mesh == null:
		_p_mesh = CylinderMesh.new()
		_p_mesh.top_radius = 1.0
		_p_mesh.bottom_radius = 0.25
		_p_mesh.height = 1.0
		_p_mesh.radial_segments = 8
		_p_mesh.rings = 1
	var b := Bullet.new()
	b.from_player = true
	b.vel = dir * speed
	b.radius = 0.16
	b.life = 0.48
	b.streak = Node3D.new()
	b.add_child(b.streak)
	b.streak.basis = Basis.looking_at(dir, Vector3.UP)
	# 예광탄: 바깥 주황 광채 · 안쪽 흰 노랑 심 · 머리의 밝은 점
	for L in [[Pal.TRACER_GLOW, 1.6, 0.06, 1.0], [Pal.TRACER_CORE, 2.6, 0.028, 0.75]]:
		var mi := Pal.flat_mesh(_p_mesh, L[0], L[1])
		# 원기둥 +Y → -Z(진행 방향): 굵은 쪽이 머리, 가는 쪽이 꼬리(+Z)
		mi.rotation_degrees.x = -90.0
		mi.position = Vector3(0, 0, 0.5 * L[3])
		mi.scale = Vector3(L[2], L[3], L[2])
		b.streak.add_child(mi)
		if b.mesh == null:
			b.mesh = mi
	var head := SphereMesh.new()
	head.radius = 0.055
	head.height = 0.11
	head.radial_segments = 8
	head.rings = 4
	b.add_child(Pal.flat_mesh(head, Pal.TRACER_CORE, 3.0))
	b.streak.scale = Vector3(1, 1, 0.05)
	b.position = pos
	b.origin = pos
	return b


static func make_enemy(pos: Vector3, dir: Vector3, speed: float, big := false) -> Bullet:
	if _e_mesh == null:
		_e_mesh = SphereMesh.new()
		_e_mesh.radius = 0.5
		_e_mesh.height = 1.0
		_e_mesh.radial_segments = 14
		_e_mesh.rings = 7
	var b := Bullet.new()
	b.from_player = false
	b.vel = dir * speed
	b.radius = 0.2 if big else 0.15
	b.life = 5.0
	b.mesh = Pal.flat_mesh(_e_mesh, Pal.E_BULLETS[0], 1.15)
	b.mesh.scale = Vector3.ONE * (b.radius * 2.2)
	b.add_child(b.mesh)
	b.position = pos
	return b


func _physics_process(dt: float) -> void:
	age += dt
	life -= dt
	var prev := position
	position += vel * dt
	if life <= 0.0:
		queue_free()
		return
	var main := Main.inst
	if from_player:
		# 빠른 탄이라 이번 프레임에 지나간 선분 전체로 판정한다 (벽·적 관통 방지)
		var step := vel * dt
		var travel := step.length()
		var fwd := step / maxf(travel, 0.0001)
		var n := int(ceil(travel / 0.3))
		for i in n:
			var q := prev + step * (float(i + 1) / n)
			if main.is_blocked(q):
				position = q
				GunFX.impact_wall(q - fwd * 0.15, _wall_normal(q, fwd), fwd)
				queue_free()
				return
		var best: Enemy = null
		var best_t := 1e9
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy
			if not en.alive or not en.landed:
				continue
			var rel := Vector3(en.global_position.x - prev.x, 0, en.global_position.z - prev.z)
			var along := clampf(rel.dot(fwd), 0.0, travel)
			if (rel - fwd * along).length() < en.radius + radius and along < best_t:
				best_t = along
				best = en
		if best:
			position = prev + fwd * best_t
			best.take_hit(1, fwd, position)
			GunFX.impact_body(position, fwd, best.slice_color)
			queue_free()
			return
		# 광선 길이: 총구에서 자라나 최대 길이까지, 속도가 빠를수록 길다
		var shown := minf(STREAK_LEN, Vector2(position.x - origin.x, position.z - origin.z).length())
		streak.scale.z = maxf(shown, 0.05)
		return
	if main.is_blocked(position):
		var f := vel.normalized()
		FX.bullet_hit(position - f * 0.1, Pal.E_BULLETS[1])
		GunFX.impact_wall(position - f * 0.1, _wall_normal(position, f), f, 0.5)
		queue_free()
		return
	# 적탄: 빨강 → 주황 → 노랑 으로 반짝이며 변색
	var idx := int(age * 7.0) % 4
	if idx != color_phase:
		color_phase = idx
		mesh.set_instance_shader_parameter("tint", Pal.E_BULLETS[[0, 1, 2, 1][idx] + (1 if age > 0.8 else 0)])
	var p := main.player
	if p.alive and _flat_dist(p.global_position) < p.hit_radius + radius:
		if p.take_hit(position):
			queue_free()


## 막힌 칸에 들어간 점 p 에서 진행 방향 fwd 로 들어온 면의 법선 (격자 벽이라 X 또는 Z 축)
static func _wall_normal(p: Vector3, fwd: Vector3) -> Vector3:
	var back := p - fwd * 0.3
	if not Main.inst.is_blocked(Vector3(back.x, 0, p.z)):
		return Vector3(-signf(fwd.x), 0, 0)
	return Vector3(0, 0, -signf(fwd.z))


func _flat_dist(o: Vector3) -> float:
	return Vector2(position.x - o.x, position.z - o.z).length()
