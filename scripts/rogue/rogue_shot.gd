class_name RogueShot
extends Node3D
## 로그 모드의 변형 탄. 궤적(직선·유도·사인파·부메랑·공전·튕김)과 명중 효과(관통·분열·폭발·화상·중독·냉각·번개·치명타)를 축마다 따로 켜서 합성한다.
## style 은 겉모습과 몇 가지 결합 공격 동작: tear(기본) · missile(유도 폭뢰) · saw(회전 톱날) · flare(태양 플레어) · blade(검기) · star(유성우)

const HEIGHT := 0.95

static var _sphere: SphereMesh
static var _disc: CylinderMesh
static var _box: BoxMesh

var build: RogueBuild
var vel := Vector3.ZERO
var speed := 24.0
var dmg := 3.5
var life := 0.4
var age := 0.0
var size := 1.0
var col := Color("ffd060")
var homing := 0.0
var pierce := false
var bounces := 0
var split := false
var explode := 0.0
var burn := 0
var poison := 0
var freeze := 0
var chain := 0
var knock := 0.6
var crit := 0
var boomer := false
var wave := 0.0
var orbit := false
var style := "tear"
var mirror := false
var child := false
var hit_any := false
var hit_cd := {}
var _base := Vector3.ZERO
var _perp := Vector3.ZERO
var _orbit_a := 0.0
var _returning := false
var _smoke_t := 0.0
var core: MeshInstance3D
var glow: MeshInstance3D


static func _meshes() -> void:
	if _sphere:
		return
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 12
	_sphere.rings = 6
	_disc = CylinderMesh.new()
	_disc.top_radius = 0.5
	_disc.bottom_radius = 0.5
	_disc.height = 0.08
	_disc.radial_segments = 10
	_box = BoxMesh.new()


func _ready() -> void:
	_meshes()
	add_to_group("rogue_shots")
	_base = global_position
	_perp = Vector3(-vel.z, 0, vel.x).normalized()
	if vel.length() > 0.01:
		speed = vel.length()
	match style:
		"saw":
			core = Pal.flat_mesh(_disc, Color("e8f0ff"), 1.6)
			core.scale = Vector3(0.9, 1, 0.9) * size
			glow = Pal.flat_mesh(_disc, col, 1.2)
			glow.scale = Vector3(1.15, 0.5, 1.15) * size
		"missile":
			core = Pal.flat_mesh(_box, Color("f0f0f0"), 1.2)
			core.scale = Vector3(0.16, 0.16, 0.55) * size
			glow = Pal.flat_mesh(_sphere, col, 2.2)
			glow.scale = Vector3.ONE * 0.28 * size
			glow.position = Vector3(0, 0, 0.3)
		"blade":
			core = Pal.flat_mesh(_sphere, Color("ffe0f4"), 2.0)
			core.scale = Vector3(1.6, 0.12, 0.35) * size
			glow = Pal.flat_mesh(_sphere, col, 1.4)
			glow.scale = Vector3(2.1, 0.08, 0.55) * size
		_:
			core = Pal.flat_mesh(_sphere, Color(1, 1, 1).lerp(col, 0.35), 2.2)
			core.scale = Vector3.ONE * 0.24 * size
			glow = Pal.flat_mesh(_sphere, col, 1.3)
			glow.scale = Vector3.ONE * 0.4 * size
	add_child(glow)
	add_child(core)
	_face()


func _face() -> void:
	if vel.length() < 0.01:
		return
	var d := vel.normalized()
	if style == "missile" or style == "blade":
		look_at(global_position + d, Vector3.UP)
	elif style == "tear" or style == "star" or style == "flare":
		# 빠를수록 진행 방향으로 늘어난다
		look_at(global_position + d, Vector3.UP)
		var k := clampf(speed / 30.0, 0.6, 1.6)
		core.scale = Vector3(0.24, 0.24, 0.24 * (1.0 + k)) * size
		glow.scale = Vector3(0.4, 0.4, 0.4 * (1.0 + k * 0.7)) * size


func _physics_process(dt: float) -> void:
	age += dt
	life -= dt
	if life <= 0.0:
		_expire(false)
		return
	var main := Main.inst
	if main == null or not is_instance_valid(main.player):
		queue_free()
		return
	var p := main.player
	var prev := global_position
	# 공전: 처음 0.7초는 몸 둘레를 돌다가 바깥으로 풀려난다
	if orbit and age < 0.7:
		_orbit_a += dt * 9.0
		var r := 1.2 + age * 2.2
		var c := p.global_position
		var tang := Vector3(-sin(_orbit_a), 0, cos(_orbit_a))
		_base = Vector3(c.x + cos(_orbit_a) * r, 0, c.z + sin(_orbit_a) * r)
		vel = (tang * 0.6 + Vector3(cos(_orbit_a), 0, sin(_orbit_a))).normalized() * speed
	else:
		if style == "missile":
			speed = minf(speed + 70.0 * dt, 38.0)
			_smoke_t -= dt
			if _smoke_t <= 0.0:
				_smoke_t = 0.045
				FX.puffs(global_position - vel.normalized() * 0.3, 1, [Color("c8d0ff"), Color("6070b0"), Color("6070b0"), Color("6070b0")], 0.12, 0.3, 0.35)
		if boomer:
			if not _returning and age > 0.45 * (age + life):
				_returning = true
			if _returning:
				var to := p.global_position - global_position
				to.y = 0
				if to.length() < 0.9:
					queue_free()
					return
				vel = vel.move_toward(to.normalized() * speed * 1.3, speed * 6.0 * dt)
		if homing > 0.0 and not _returning:
			var t := _target()
			if t:
				var to: Vector3 = t.global_position - global_position
				to.y = 0
				var want := to.normalized() * speed
				vel = vel.move_toward(want, speed * homing * 5.0 * dt)
		vel = vel.normalized() * speed
		_base += vel * dt
	var pos := _base
	if wave > 0.0:
		_perp = Vector3(-vel.z, 0, vel.x).normalized()
		pos += _perp * sin(age * 17.0) * 0.7 * wave
	pos.y = Main.gy(pos) + HEIGHT
	global_position = pos
	if style == "saw":
		core.rotate_y(dt * 30.0)
	else:
		_face()
	# 벽
	if main.is_blocked(pos) and not (orbit and age < 0.7):
		if bounces > 0:
			bounces -= 1
			var fwd := vel.normalized()
			var n := Bullet._wall_normal(pos, fwd)
			vel = (fwd - 2.0 * fwd.dot(n) * n)
			vel.y = 0
			vel = vel.normalized() * speed
			_base = prev
			_base.y = 0
			global_position = prev
			if mirror:
				dmg *= 1.5
			FX.flash(prev, col, 0.35, 0.06)
			return
		_expire(true)
		return
	# 적
	var step := pos - prev
	var travel := step.length()
	var fwd2 := step / maxf(travel, 0.0001)
	for e in Enemy.live(get_tree()):
		var en := e as Enemy
		if not is_instance_valid(en) or not en.alive or not en.landed:
			continue
		var k := en.get_instance_id()
		if hit_cd.has(k) and float(hit_cd[k]) > age:
			continue
		var rel := Vector3(en.global_position.x - prev.x, 0, en.global_position.z - prev.z)
		var along := clampf(rel.dot(fwd2), 0.0, travel)
		var r := en.radius + 0.22 * size + (0.25 if style == "saw" else 0.0)
		if (rel - fwd2 * along).length() < r:
			_hit(en, prev + fwd2 * along, fwd2 if travel > 0.001 else vel.normalized())
			if not pierce:
				_expire(false, true)
				return
			hit_cd[k] = age + (0.15 if style == "saw" else 999.0)


func _target() -> Node3D:
	var best: Node3D = null
	var bd := 10.0
	for e in Enemy.live(get_tree()):
		var en := e as Enemy
		if not en.alive or not en.landed or en.prop:
			continue
		if hit_cd.has(en.get_instance_id()):
			continue
		var d := en.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = en
	return best


func _hit(en: Enemy, at: Vector3, fwd: Vector3) -> void:
	hit_any = true
	var d := dmg
	if crit > 0 and build.roll(crit):
		d *= 3.0
		Main.inst.hud.popup("CRIT!", Color("ffe040"), at + Vector3(0, 1.4, 0))
	var is_prop := en.prop
	build.deal(en, d, fwd, at, knock * (2.2 if build.f("knock") > 0 else 1.0))
	if not is_prop:
		build.on_shot_hit()
	GunFX.impact_body(at, fwd, en.slice_color, 0.7 * size)
	if not is_instance_valid(en):
		return
	if burn > 0 and build.roll(burn):
		build.apply_status(en, "burn", 3.0)
	if poison > 0 and build.roll(poison):
		build.apply_status(en, "poison", 3.5)
	if freeze > 0 and en.alive and not en.is_boss and not is_prop and randf() < 0.3:
		en.stagger(fwd, 0.55)
		FX.sparks(at, 6, [Color("e0f8ff"), Color("60c0ff")], 4.0, 0.3, -6.0, 0.06)
	if (chain > 0 or (build.f("antenna") > 0 and build.roll(build.f("antenna")))) and not is_prop:
		RogueEffects.lightning(build, en, dmg * 0.6, 3)
	if build.f("holy") > 0 and build.roll(build.f("holy")):
		RogueEffects.holy_pillar(build, en.global_position, dmg * 1.5)
	if split and not child:
		for s in [-1.0, 1.0]:
			var c := RogueEffects.bullet(build, at - fwd * 0.3, fwd.rotated(Vector3.UP, s * 1.0), dmg * 0.5, {"child": true, "size_k": 0.6, "life_k": 0.45})
			c.hit_cd[en.get_instance_id()] = 999.0
	if explode > 0.0:
		RogueEffects.explosion(at, explode, dmg * 1.2, false)
	if style == "flare":
		RogueEffects.flame(at, dmg * 0.4, 3.0, false)


func _expire(wall: bool, hit := false) -> void:
	if not hit and not hit_any and is_instance_valid(build):
		build.on_shot_miss()
	var at := global_position
	if explode > 0.0 and not hit:
		RogueEffects.explosion(at, explode, dmg * 1.2, false)
	elif style == "flare" and not hit:
		RogueEffects.flame(at, dmg * 0.4, 3.0, false)
	elif wall:
		FX.flash(at, col, 0.4 * size, 0.07)
	else:
		FX.flash(at, col.lerp(Color.WHITE, 0.4), 0.3 * size, 0.06)
	queue_free()
