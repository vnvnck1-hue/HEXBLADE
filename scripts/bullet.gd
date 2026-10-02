class_name Bullet
extends Node3D
## 플레이어탄 / 적탄. 판정은 수평 거리로 단순화한다.

## 고저차: 탄은 지면에서 HUG 이상 떠서 날고, 높이 차가 HIT_DY 넘는 대상(다른 층)은 맞히지 않는다
const HUG := 0.45
const HIT_DY := 1.35

static var _e_mesh: SphereMesh

var vel := Vector3.ZERO
var life := 2.0
var from_player := true
var radius := 0.15
var age := 0.0
var mesh: MeshInstance3D
var color_phase := 0
var tracer: ToonGunFX.Tracer
var origin := Vector3.ZERO
## 장갑에 튕겨 나간 도탄: 적을 맞히지 않고, 벽에 한 번 더 튕긴 뒤 사라진다
var deflected := false
var bounces := 0
## 푸른 경직탄: 검(베기·관통 일격)으로 지워지지 않고, 맞으면 stun 초 동안 플레이어가 굳는다
var unslashable := false
var stun := 0.0

const BLUE: Array[Color] = [Color("2a6cff"), Color("3aa8ff"), Color("8ad8ff"), Color("3aa8ff")]


## 플레이어탄: 보이는 모습은 ToonGunFX 예광 연출(깜빡이는 머리 · 궤적 위 잔광 · 옅은 연기 선)이 맡는다.
static func make_player(pos: Vector3, dir: Vector3, speed: float) -> Bullet:
	var b := Bullet.new()
	b.from_player = true
	b.vel = dir * speed
	b.radius = 0.16
	b.life = 0.48
	b.tracer = ToonGunFX.tracer().setup(dir)
	b.add_child(b.tracer)
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


## 푸른 경직탄: 적탄보다 크고 느리며, 흰 심 위로 푸른 광채가 맥동한다
static func make_blue(pos: Vector3, dir: Vector3, speed: float, stun_time := 0.7, life_time := 5.0) -> Bullet:
	var b := make_enemy(pos, dir, speed, true)
	b.unslashable = true
	b.stun = stun_time
	b.life = life_time
	b.radius = 0.3
	b.mesh.scale = Vector3.ONE * (b.radius * 2.2)
	b.mesh.set_instance_shader_parameter("tint", BLUE[0])
	b.mesh.set_instance_shader_parameter("energy", 1.8)
	var core := Pal.flat_mesh(_e_mesh, Color("e8f6ff"), 2.6)
	core.scale = Vector3.ONE * 0.32
	b.add_child(core)
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
	# 바닥 굴곡: 탄은 둔덕을 타고 넘는다
	var fy := Main.gy(position) + HUG
	if fy > position.y and fy - position.y < ArenaMap.STEP + HUG and not deflected:
		position.y = fy
	if from_player:
		# 빠른 탄이라 이번 프레임에 지나간 선분 전체로 판정한다 (벽·적 관통 방지)
		var step := vel * dt
		var travel := step.length()
		var fwd := step / maxf(travel, 0.0001)
		var n := int(ceil(travel / 0.3))
		for i in n:
			var q := prev + step * (float(i + 1) / n)
			if main.is_blocked(q):
				var wn := _wall_normal(q, fwd)
				if deflected and bounces > 0:
					# 도탄이 벽에 한 번 더 튕긴다
					bounces -= 1
					var fl := Vector3(fwd.x, 0, fwd.z)
					var r := (fl - 2.0 * fl.dot(wn) * wn).normalized().rotated(Vector3.UP, randf_range(-0.3, 0.3))
					GunFX.impact_wall(q - fwd * 0.15, wn, fwd, 0.4)
					ricochet(q - fwd * 0.2, Vector3(r.x, randf_range(0.05, 0.3), r.z).normalized(), vel.length() * 0.8, life)
					return
				position = q
				GunFX.impact_wall(q - fwd * 0.15, wn, fwd, 0.5 if deflected else 1.0)
				queue_free()
				return
		if deflected:
			_update_streak()
			return
		var best: Enemy = null
		var best_t := 1e9
		for e in Enemy.live(get_tree()):
			if not is_instance_valid(e):
				continue
			var en := e as Enemy
			if not en.alive or not en.landed:
				continue
			if absf(en.global_position.y + 1.0 - position.y) > HIT_DY:
				continue                 # 다른 층의 적
			var rel := Vector3(en.global_position.x - prev.x, 0, en.global_position.z - prev.z)
			var along := clampf(rel.dot(fwd), 0.0, travel)
			if (rel - fwd * along).length() < en.radius + radius and along < best_t:
				best_t = along
				best = en
		if best:
			position = prev + fwd * best_t
			# 장갑 상태의 적은 탄을 튕겨 낸다 (탄이 도탄이 되어 계속 날아간다)
			if best.has_method("deflect_bullet") and best.deflect_bullet(self, position, fwd):
				return
			best.take_hit(1, fwd, position)
			# 큰 기체(맘모스)는 판정점이 차체 안에 묻히므로 연출 위치만 겉면으로 꺼낸다
			var fx_at: Vector3 = best.call("fx_point", position, fwd) if best.has_method("fx_point") else position
			GunFX.impact_body(fx_at, fwd, best.slice_color)
			queue_free()
			return
		_update_streak()
		return
	if main.is_blocked(position):
		var f := vel.normalized()
		FX.bullet_hit(position - f * 0.1, Pal.E_BULLETS[1])
		GunFX.impact_wall(position - f * 0.1, _wall_normal(position, f), f, 0.5)
		queue_free()
		return
	var idx := int(age * 7.0) % 4
	if unslashable:
		# 푸른 경직탄: 푸른빛으로 맥동하고, 사라지기 직전 줄어든다
		mesh.scale = Vector3.ONE * (radius * 2.2 * (1.0 + sin(age * 18.0) * 0.12) * clampf(life / 0.25, 0.2, 1.0))
		if idx != color_phase:
			color_phase = idx
			mesh.set_instance_shader_parameter("tint", BLUE[idx])
	elif idx != color_phase:
		# 적탄: 빨강 → 주황 → 노랑 으로 반짝이며 변색
		color_phase = idx
		mesh.set_instance_shader_parameter("tint", Pal.E_BULLETS[[0, 1, 2, 1][idx] + (1 if age > 0.8 else 0)])
	var p := main.player
	if p.alive and _flat_dist(p.global_position) < p.hit_radius + radius and absf(p.global_position.y + 0.95 - position.y) < HIT_DY:
		if p.take_hit(position):
			if stun > 0.0:
				p.stagger(stun)
			queue_free()


## 도탄은 사라지기 직전 가늘어진다
func _update_streak() -> void:
	if deflected and tracer:
		tracer.thin = clampf(life / 0.12, 0.15, 1.0)


## 튕겨 나가는 도탄으로 바꾼다: pos 에서 dir 방향으로 다시 날아간다
func ricochet(pos: Vector3, dir: Vector3, speed: float, new_life := -1.0) -> void:
	if not deflected:
		bounces = 1
	deflected = true
	position = pos
	origin = pos
	vel = dir * speed
	life = new_life if new_life > 0.0 else randf_range(0.2, 0.36)
	if tracer:
		tracer.redirect(pos, dir)


## 막힌 칸에 들어간 점 p 에서 진행 방향 fwd 로 들어온 면의 법선 (격자 벽이라 X 또는 Z 축)
static func _wall_normal(p: Vector3, fwd: Vector3) -> Vector3:
	var back := p - fwd * 0.3
	if not Main.inst.is_blocked(Vector3(back.x, p.y, p.z)):
		return Vector3(-signf(fwd.x), 0, 0)
	return Vector3(0, 0, -signf(fwd.z))


func _flat_dist(o: Vector3) -> float:
	return Vector2(position.x - o.x, position.z - o.z).length()
