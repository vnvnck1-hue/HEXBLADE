class_name RogueEffects
extends RefCounted
## 로그 모드 공용 공격: 기본 총 발사 패턴(축 합성) · 빔 · 검기 · 폭발 · 불 · 독구름 · 충격파 · 번개 · 빛기둥 · 블랙홀 · 회전 빔.

const C_TEAR := Color("ffd878")
const C_FIRE := Color("ff7a30")
const C_POISON := Color("70ff60")
const C_ICE := Color("8ae0ff")
const C_SHOCK := Color("60f0ff")
const C_HOMING := Color("c890ff")
const C_BLAST := Color("ffa040")
const C_BRIM := Color("ff2a3a")
const C_BLADE := Color("ff7ac8")
const C_STAR := Color("fff070")

static var _cyl: CylinderMesh
static var _sph: SphereMesh
static var _torus: TorusMesh


static func _m() -> void:
	if _cyl:
		return
	_cyl = CylinderMesh.new()
	_cyl.top_radius = 0.5
	_cyl.bottom_radius = 0.5
	_cyl.height = 1.0
	_cyl.radial_segments = 8
	_cyl.rings = 1
	_sph = SphereMesh.new()
	_sph.radius = 0.5
	_sph.height = 1.0
	_sph.radial_segments = 10
	_sph.rings = 5
	_torus = TorusMesh.new()
	_torus.inner_radius = 0.42
	_torus.outer_radius = 0.5
	_torus.rings = 24


static func world() -> Node3D:
	return Main.inst.world


# ── 기본 총: 발사 패턴 ──────────────────────────────────

static func fire(b: RogueBuild, origin: Vector3, d: Vector3) -> void:
	var dm := b.cur_dmg()
	var n := clampi(1 + b.f("multi") + 2 * b.f("triple") + 3 * b.f("quad"), 1, 8)
	var span := minf(0.17 * (n - 1), 1.1)
	var dirs: Array = []
	for i in n:
		var a := 0.0 if n == 1 else lerpf(-span * 0.5, span * 0.5, float(i) / (n - 1))
		dirs.append(d.rotated(Vector3.UP, a))
	if b.f("back") > 0:
		dirs.append(-d)
	var sprayed := false
	if b.f("spray") > 0 and b.roll(b.f("spray")):
		sprayed = true
		for k in [1, 2, 3]:
			dirs.append(d.rotated(Vector3.UP, PI * 0.5 * k))
	# 탄 종류
	if b.f("brim") > 0:
		if b.syn.has("brim_spin"):
			spin_beam(b, 0.5, dm * 0.5)
		else:
			for dv in dirs:
				beam(b, origin, dv, 30.0, 0.9, dm, C_BRIM, false, true)
		Sfx.play("laser", 0.05, -10.0)
		return
	if b.f("laser") > 0:
		for dv in dirs:
			beam(b, origin, dv, b.range_m * 1.6, 0.22, dm, C_SHOCK, b.syn.has("prism"), false)
		return
	if b.f("tech_laser") > 0 and b.shot_count % 4 == 0:
		beam(b, origin, d, b.range_m * 1.5, 0.22, dm, C_SHOCK, false, false)
	if b.syn.has("singularity") and b.shot_count % 8 == 0:
		black_hole(b, origin + d * 5.0, 2.2, dm * 0.6, 1.0)
	for i in dirs.size():
		var opts := {}
		if sprayed and b.syn.has("meteor") and i >= dirs.size() - 3:
			opts = {"style": "star", "homing_k": 2.0}
		bullet(b, origin, dirs[i], dm, opts)


## 플래그대로 탄 하나. opts: style · child · size_k · life_k · homing_k · plain(축 효과 없이) · pierce · speed_k
static func bullet(b: RogueBuild, pos: Vector3, dir: Vector3, dmg: float, opts := {}) -> RogueShot:
	var s := RogueShot.new()
	s.build = b
	var plain: bool = opts.get("plain", false)
	var style: String = opts.get("style", "tear")
	if not plain and style == "tear":
		if b.syn.has("missile"):
			style = "missile"
		elif b.syn.has("saw"):
			style = "saw"
		elif b.syn.has("flare"):
			style = "flare"
	s.style = style
	var spd := b.shot_speed * float(opts.get("speed_k", 1.0))
	if style == "missile":
		spd *= 0.4
	if style == "blade":
		spd = 21.0
	s.vel = Vector3(dir.x, 0, dir.z).normalized() * spd
	s.dmg = dmg
	s.life = b.range_m / maxf(b.shot_speed, 1.0) * float(opts.get("life_k", 1.0))
	if style == "missile":
		s.life *= 1.9
	s.size = (1.0 + float(b.stats.get("size", 0.0))) * float(opts.get("size_k", 1.0))
	s.child = opts.get("child", false)
	s.knock = 0.6
	if not plain:
		s.homing = (1.0 if (b.f("homing") > 0 or b.room_homing) else 0.0) * float(opts.get("homing_k", 1.0))
		if style == "missile" or style == "star":
			s.homing = maxf(s.homing, 1.6)
		s.pierce = b.f("pierce") > 0 or style == "saw"
		s.bounces = b.f("bounce") + (2 if b.syn.has("mirror") else 0)
		s.mirror = b.syn.has("mirror")
		s.split = b.f("split") > 0
		s.explode = (2.0 if b.f("explode") > 0 else 0.0) + (0.8 if style == "missile" else 0.0)
		s.burn = b.f("burn") + (100 if style == "flare" else 0)
		s.poison = b.f("poison")
		s.freeze = b.f("freeze")
		s.chain = b.f("chain")
		s.crit = b.f("crit")
		s.boomer = b.f("boomerang") > 0 or style == "saw"
		s.wave = 1.0 if b.f("wave") > 0 else 0.0
		s.orbit = b.f("orbit") > 0 and not s.child and style != "missile"
		if b.f("giant") > 0 or style == "flare":
			s.size *= 1.6
	else:
		s.pierce = opts.get("pierce", false)
	if opts.has("pierce"):
		s.pierce = opts.pierce
	s.col = _shot_color(b, style, plain)
	s.position = pos          # world 는 원점에 있으므로 position = 전역 위치. _ready 가 이 자리를 기준점으로 잡는다
	world().add_child(s)
	return s


static func _shot_color(b: RogueBuild, style: String, plain: bool) -> Color:
	match style:
		"blade": return C_BLADE
		"star": return C_STAR
		"flare": return C_FIRE
		"missile": return C_BLAST
		"saw": return Color("c0d8ff")
	if plain:
		return C_TEAR
	if b.f("explode") > 0:
		return C_BLAST
	if b.f("burn") > 0:
		return C_FIRE
	if b.f("poison") > 0:
		return C_POISON
	if b.f("freeze") > 0:
		return C_ICE
	if b.f("chain") > 0:
		return C_SHOCK
	if b.f("homing") > 0:
		return C_HOMING
	return C_TEAR


# ── 빔 ──────────────────────────────────────────────────

## origin 에서 dir 로 벽까지 (최대 length) 즉발 빔. 닿는 적을 모두 꿰뚫는다.
static func beam(b: RogueBuild, origin: Vector3, dir: Vector3, length: float, width: float, dmg: float, c: Color, prism := false, heavy := false) -> void:
	var main := Main.inst
	dir = Vector3(dir.x, 0, dir.z).normalized()
	var L := 0.0
	while L < length:
		if main.is_blocked(origin + dir * (L + 0.3)):
			break
		L += 0.3
	L = maxf(L, 0.6)
	var hits: Array = []
	for e in Enemy.live(main.get_tree()):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var rel := en.global_position - origin
		rel.y = 0
		var along := rel.dot(dir)
		if along < -0.3 or along > L + en.radius:
			continue
		if (rel - dir * along).length() < width * 0.5 + en.radius:
			hits.append([along, en])
	hits.sort_custom(func(x, y): return x[0] < y[0])
	for h in hits:
		var en: Enemy = h[1]
		b.deal(en, dmg, dir, origin + dir * h[0], 0.8 if heavy else 0.3)
		if not is_instance_valid(en):
			continue
		if b.f("burn") > 0 and b.roll(b.f("burn")):
			b.apply_status(en, "burn", 3.0)
		if b.f("poison") > 0 and b.roll(b.f("poison")):
			b.apply_status(en, "poison", 3.5)
		if b.f("chain") > 0 and not en.prop:
			lightning(b, en, dmg * 0.5, 2)
	line_fx(origin, dir, L, width, c, heavy)
	if prism and hits.size() > 0:
		var at: Vector3 = origin + dir * float(hits[0][0])
		for a in [-0.5, 0.0, 0.5]:
			var d2 := dir.rotated(Vector3.UP, a)
			beam(b, at + d2 * 0.8, d2, 7.0, width * 0.8, dmg * 0.6, Color("ff9af0") if a != 0.0 else Color("a0f0ff"), false, false)
	if heavy:
		main.shake(0.12)
		FX.flash(origin, c, 0.9, 0.08, 0.0)


static func line_fx(origin: Vector3, dir: Vector3, length: float, width: float, c: Color, heavy := false) -> void:
	_m()
	var holder := Node3D.new()
	world().add_child(holder)
	holder.global_position = origin
	holder.look_at(origin + dir, Vector3.UP)
	var layers := [[c, 1.6, 1.0], [Color.WHITE, 2.4, 0.4]]
	for Ly in layers:
		var mi := Pal.flat_mesh(_cyl, Ly[0], Ly[1])
		mi.rotation_degrees.x = -90.0
		mi.position = Vector3(0, 0, -length * 0.5)
		var r: float = width * Ly[2]
		mi.scale = Vector3(r, length, r)
		holder.add_child(mi)
		var tw := mi.create_tween()
		tw.tween_property(mi, "scale", Vector3(0.001, length, 0.001), 0.2 if heavy else 0.11).set_ease(Tween.EASE_IN)
	var htw := holder.create_tween()
	htw.tween_interval(0.25)
	htw.tween_callback(holder.queue_free)
	FX.sparks(origin + dir * length, 5 if not heavy else 12, [Color.WHITE, c], 6.0, 0.25, -6.0, 0.06)


## 혈사포 + 소형 행성: 빔이 몸 둘레를 휩쓸며 한 바퀴
static func spin_beam(b: RogueBuild, dur: float, dmg: float) -> void:
	var n := SpinBeam.new()
	n.b = b
	n.dur = dur
	n.dmg = dmg
	world().add_child(n)


class SpinBeam extends Node3D:
	var b: RogueBuild
	var dur := 0.5
	var dmg := 1.0
	var t := 0.0
	var tick := 0.0
	var a0 := 0.0

	func _ready() -> void:
		if is_instance_valid(b) and is_instance_valid(b.player):
			var ad := b.player.aim_dir
			a0 = atan2(ad.z, ad.x)

	func _physics_process(dt: float) -> void:
		t += dt
		tick -= dt
		if t > dur or not is_instance_valid(b) or not is_instance_valid(b.player):
			queue_free()
			return
		if tick <= 0.0:
			tick = 0.05
			var a := a0 + t / dur * TAU
			var o := b.player.global_position + Vector3(0, 0.95, 0)
			RogueEffects.beam(b, o, Vector3(cos(a), 0, sin(a)), 14.0, 0.8, dmg, RogueEffects.C_BRIM, false, false)


# ── 검기 ────────────────────────────────────────────────

static func blade_wave(b: RogueBuild, pos: Vector3, dir: Vector3) -> void:
	bullet(b, pos, dir, b.cur_dmg() * 1.2 * (1.0 + float(b.stats.get("slash_x", 0.0))), {"style": "blade", "plain": true, "pierce": true, "life_k": 0.8})


# ── 폭발 · 불 · 독 · 충격파 ─────────────────────────────

static func explosion(pos: Vector3, radius: float, dmg: float, hurt_player: bool, source := "rogue") -> void:
	var main := Main.inst
	var b := RogueBuild.inst
	FX.fire_explosion(pos, radius / (2.0 if source == "bomb" else 2.8))
	main.shake((0.2 if source == "bomb" else 0.08) + radius * 0.04)
	Sfx.play("boom", 0.1, -6.0)
	for e in Enemy.live(main.get_tree()):
		var en := e as Enemy
		if not en.alive:
			continue
		var d := Vector2(en.global_position.x - pos.x, en.global_position.z - pos.z).length()
		if d < radius + en.radius * 0.5:
			var push := en.global_position - pos
			push.y = 0
			if b:
				b.deal(en, dmg, push.normalized(), en.global_position, 1.4, source)
	if hurt_player and is_instance_valid(main.player):
		var p := main.player
		var immune := b != null and b.f("bomb_immune") > 0
		if not immune and Vector2(p.global_position.x - pos.x, p.global_position.z - pos.z).length() < radius * 0.85:
			p.take_hit(pos)
	if main.has_method("on_blast"):
		main.on_blast(pos, radius, source)


static func flame(pos: Vector3, dps: float, sec: float, explosive: bool) -> void:
	var n := Flame.new()
	n.dps = dps
	n.life = sec
	n.explosive = explosive
	world().add_child(n)
	n.global_position = Vector3(pos.x, Main.gy(pos), pos.z)


class Flame extends Node3D:
	var dps := 2.0
	var life := 2.0
	var explosive := false
	var t := 0.0
	var tick := 0.0
	var core: MeshInstance3D

	func _ready() -> void:
		RogueEffects._m()
		core = Pal.flat_mesh(RogueEffects._sph, Color("ff8a30"), 2.2)
		core.scale = Vector3(0.7, 0.9, 0.7)
		core.position.y = 0.4
		add_child(core)

	func _physics_process(dt: float) -> void:
		t += dt
		tick -= dt
		var k := 1.0 - t / life
		core.scale = Vector3(0.6 + sin(t * 23.0) * 0.08, 0.8 + sin(t * 31.0) * 0.15, 0.6) * maxf(k, 0.1)
		core.set_instance_shader_parameter("tint", Color("ffd060").lerp(Color("ff4a20"), fmod(t * 4.0, 1.0)))
		if explosive and t > 0.45:
			RogueEffects.explosion(global_position + Vector3(0, 0.4, 0), 1.9, dps * 3.0, false)
			queue_free()
			return
		if tick <= 0.0:
			tick = 0.3
			var b := RogueBuild.inst
			for e in Enemy.live(get_tree()):
				var en := e as Enemy
				if en.alive and en.landed and en.global_position.distance_to(global_position) < 1.0 + en.radius:
					if b:
						b.deal(en, dps * 0.3, Vector3.ZERO, en.global_position, 0.0)
						b.apply_status(en, "burn", 1.5)
		if t > life:
			queue_free()


static func poison_cloud(pos: Vector3, radius: float, sec: float, dps: float) -> void:
	var n := Cloud.new()
	n.radius = radius
	n.life = sec
	n.dps = dps
	world().add_child(n)
	n.global_position = Vector3(pos.x, Main.gy(pos), pos.z)


class Cloud extends Node3D:
	var radius := 1.5
	var life := 3.0
	var dps := 1.0
	var t := 0.0
	var tick := 0.0
	var puff_t := 0.0

	func _physics_process(dt: float) -> void:
		t += dt
		tick -= dt
		puff_t -= dt
		if puff_t <= 0.0:
			puff_t = 0.25
			FX.puffs(global_position + Vector3(randf_range(-radius, radius) * 0.6, 0.4, randf_range(-radius, radius) * 0.6), 1, [Color("80ff60"), Color("2a8a3a"), Color("2a8a3a"), Color("2a8a3a")], radius * 0.5, radius * 0.9, 0.9)
		if tick <= 0.0:
			tick = 0.5
			var b := RogueBuild.inst
			for e in Enemy.live(get_tree()):
				var en := e as Enemy
				if en.alive and not en.prop and en.global_position.distance_to(global_position) < radius + en.radius and b:
					b.apply_status(en, "poison", 2.0)
		if t > life:
			queue_free()


static func shockwave(pos: Vector3, radius: float, dmg: float) -> void:
	var b := RogueBuild.inst
	FX.shockwave(pos, Color("a0f0ff"), radius * 1.4, 0.3)
	FX.ring(Vector3(pos.x, Main.gy(pos) + 0.2, pos.z), radius * 1.5, [Color("a0f0ff"), Color.WHITE, Color("a0f0ff")], 0.3)
	for e in Enemy.live(Main.inst.get_tree()):
		var en := e as Enemy
		if en.alive and en.landed and en.global_position.distance_to(pos) < radius + en.radius and b:
			var push := en.global_position - pos
			push.y = 0
			b.deal(en, dmg, push.normalized(), en.global_position, 2.0)


# ── 번개 · 빛 · 블랙홀 ──────────────────────────────────

static func lightning(b: RogueBuild, from: Node3D, dmg: float, n: int) -> void:
	if not is_instance_valid(from):
		return
	var hit := {from.get_instance_id(): true}
	var cur := from.global_position + Vector3(0, 1.0, 0)
	for i in n:
		var best: Enemy = null
		var bd := 6.0
		for e in Enemy.live(Main.inst.get_tree()):
			var en := e as Enemy
			if not en.alive or not en.landed or en.prop or hit.has(en.get_instance_id()):
				continue
			var d := en.global_position.distance_to(cur)
			if d < bd:
				bd = d
				best = en
		if best == null:
			return
		hit[best.get_instance_id()] = true
		var to := best.global_position + Vector3(0, 1.0, 0)
		zap_fx(cur, to)
		b.deal(best, dmg, (to - cur).normalized(), to, 0.2)
		if b.syn.has("storm_net"):
			for s in [-1.0, 1.0]:
				bullet(b, to, (to - cur).normalized().rotated(Vector3.UP, s * 1.2), dmg * 0.5, {"child": true, "size_k": 0.6, "life_k": 0.4})
		cur = to


static func zap_fx(a: Vector3, c: Vector3) -> void:
	_m()
	var pts: Array = [a]
	for k in 4:
		var m := a.lerp(c, (k + 1) / 5.0) + Vector3(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2), randf_range(-0.3, 0.3))
		pts.append(m)
	pts.append(c)
	for i in pts.size() - 1:
		var p: Vector3 = pts[i]
		var q: Vector3 = pts[i + 1]
		var mi := Pal.flat_mesh(_cyl, Color("c0ffff"), 2.6)
		world().add_child(mi)
		mi.global_position = (p + q) * 0.5
		if (q - p).length() > 0.01:
			mi.look_at(q, Vector3.UP if absf((q - p).normalized().y) < 0.95 else Vector3.RIGHT)
		mi.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		mi.scale = Vector3(0.06, (q - p).length(), 0.06)
		var tw := mi.create_tween()
		tw.tween_interval(0.08)
		tw.tween_callback(mi.queue_free)
	FX.flash(c, Color("c0ffff"), 0.5, 0.08)


static func holy_pillar(b: RogueBuild, pos: Vector3, dmg: float) -> void:
	_m()
	var mi := Pal.flat_mesh(_cyl, Color("fff4c0"), 2.4)
	world().add_child(mi)
	mi.global_position = Vector3(pos.x, Main.gy(pos) + 3.0, pos.z)
	mi.scale = Vector3(1.2, 6.0, 1.2)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(0.01, 6.0, 0.01), 0.3).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)
	FX.ring(Vector3(pos.x, Main.gy(pos) + 0.1, pos.z), 2.6, [Color("fff4c0"), Color.WHITE, Color("fff4c0")], 0.3)
	for e in Enemy.live(Main.inst.get_tree()):
		var en := e as Enemy
		if en.alive and en.landed and en.global_position.distance_to(pos) < 1.4 + en.radius:
			b.deal(en, dmg, Vector3.ZERO, en.global_position, 0.0)


static func black_hole(b: RogueBuild, pos: Vector3, sec: float, dps: float, size := 1.0) -> void:
	var n := Hole.new()
	n.b = b
	n.life = sec
	n.dps = dps
	n.size = size
	world().add_child(n)
	pos.y = Main.gy(pos) + 1.0
	if Main.inst.is_blocked(pos):
		pos = b.player.global_position + Vector3(0, 1.0, 0)
	n.global_position = pos


class Hole extends Node3D:
	var b: RogueBuild
	var life := 3.0
	var dps := 2.0
	var size := 1.0
	var t := 0.0
	var tick := 0.0
	var core: MeshInstance3D
	var ring_mi: MeshInstance3D

	func _ready() -> void:
		RogueEffects._m()
		core = Pal.flat_mesh(RogueEffects._sph, Color("120820"), 1.0)
		add_child(core)
		ring_mi = Pal.flat_mesh(RogueEffects._torus, Color("b070ff"), 2.4)
		add_child(ring_mi)
		Sfx.play("charge", 0.1, -10.0)

	func _physics_process(dt: float) -> void:
		t += dt
		tick -= dt
		var k := minf(t * 4.0, 1.0) * clampf((life - t) * 3.0, 0.0, 1.0)
		core.scale = Vector3.ONE * 1.1 * size * k
		ring_mi.scale = Vector3(2.4, 1.0, 2.4) * size * k * (1.0 + sin(t * 20.0) * 0.08)
		ring_mi.rotate_y(dt * 6.0)
		var r := 5.5 * size
		for e in Enemy.live(get_tree()):
			var en := e as Enemy
			if not en.alive or not en.landed or en.is_boss or en.prop:
				continue
			var to := global_position - en.global_position
			to.y = 0
			var d := to.length()
			if d < r and d > 0.6:
				var np := en.global_position + to.normalized() * minf(d - 0.5, (r - d + 2.0) * 1.2 * dt)
				en.global_position = Main.inst.push_out(np, en.radius * 0.6)
		if tick <= 0.0:
			tick = 0.25
			for e in Enemy.live(get_tree()):
				var en := e as Enemy
				if en.alive and en.landed and en.global_position.distance_to(global_position) < 1.8 * size + en.radius and is_instance_valid(b):
					b.deal(en, dps * 0.25, Vector3.ZERO, en.global_position, 0.0)
		if t > life:
			queue_free()


static func room_damage(amount: float) -> void:
	var b := RogueBuild.inst
	if b == null:
		return
	Main.inst.hud.screen_flash(Color("ff6a8a"), 0.35)
	Main.inst.shake(0.5)
	for e in Enemy.live(Main.inst.get_tree()):
		var en := e as Enemy
		if en.alive and en.landed and not en.prop:
			FX.flash(en.global_position + Vector3(0, 1, 0), Color("ff4a6a"), 1.2, 0.12)
			b.deal(en, amount, Vector3.ZERO, en.global_position, 0.0)


## 적과 적 탄을 sec 초 멈춘다 (실제 시간)
static func time_stop(sec: float) -> void:
	var tree := Main.inst.get_tree()
	var frozen: Array = []
	for e in tree.get_nodes_in_group("enemies"):
		frozen.append(e)
	for b in tree.get_nodes_in_group("enemy_bullets"):
		frozen.append(b)
	for b in tree.get_nodes_in_group("parry_orbs"):
		frozen.append(b)
	for n in frozen:
		(n as Node).process_mode = Node.PROCESS_MODE_DISABLED
	Main.inst.hud.screen_flash(Color("a0c8ff"), 0.4)
	tree.create_timer(sec, true, false, true).timeout.connect(func():
		for n in frozen:
			if is_instance_valid(n):
				(n as Node).process_mode = Node.PROCESS_MODE_INHERIT)
