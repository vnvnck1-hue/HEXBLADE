class_name RogueProps
extends RefCounted
## 로그 모드 방 소품.
##  Crate      부서지는 상자 (아무 공격) — 가끔 픽업. tinted 면 폭탄으로만 부서지고 좋은 것을 준다 (아이작의 틴티드 록)
##  Hearth     화톳불 — 닿으면 반 칸 피해 (비행이면 무시), 쏘면 꺼진다
##  Spikes     가시 바닥 — 밟으면 피해 (희생방에서는 보상 카운트)
##  Portal     트랩도어 · 비밀방/거래방 출입구 · 귀환
##  Crack      금 간 벽 — 폭탄으로 부수면 비밀방 포털

static var _box: BoxMesh
static var _ball: SphereMesh
static var _disc: CylinderMesh
static var _ring: TorusMesh


static func _m() -> void:
	if _box:
		return
	_box = BoxMesh.new()
	_ball = SphereMesh.new()
	_ball.radius = 0.5
	_ball.height = 1.0
	_disc = CylinderMesh.new()
	_disc.top_radius = 0.5
	_disc.bottom_radius = 0.5
	_disc.height = 0.05
	_disc.radial_segments = 24
	_ring = TorusMesh.new()
	_ring.inner_radius = 0.42
	_ring.outer_radius = 0.5
	_ring.rings = 28


class Crate extends Enemy:
	var tinted := false

	func _ready() -> void:
		prop = true
		super._ready()
		add_to_group("rogue_crates")
		hp = 9 if tinted else 6
		max_hp = hp
		radius = 0.55
		slice_color = Color("c09060")
		landed = true
		(j.body as Node3D).position.y = 0.0
		if is_instance_valid(hp_bar):
			hp_bar.visible = false

	func _init_hp() -> void:
		max_hp = maxi(hp, 1)

	func _build(v: Node3D) -> Dictionary:
		RogueProps._m()
		var body := Build.pivot(v, Vector3.ZERO, "Body")
		var c := Color("8a6a50") if not tinted else Color("6a7aa0")
		var mi := MeshInstance3D.new()
		mi.mesh = RogueProps._box
		mi.material_override = Pal.lit(c)
		mi.scale = Vector3(0.95, 0.85, 0.95)
		mi.position.y = 0.43
		body.add_child(mi)
		for s in [-1.0, 1.0]:
			var band := MeshInstance3D.new()
			band.mesh = RogueProps._box
			band.material_override = Pal.lit(Color("4a3a30"))
			band.scale = Vector3(0.97, 0.1, 0.97)
			band.position.y = 0.43 + s * 0.28
			body.add_child(band)
		if tinted:
			# 아이작의 틴티드 록처럼 X 표식
			for a in [45.0, -45.0]:
				var x := Pal.flat_mesh(RogueProps._box, Color("a0e0ff"), 1.6)
				x.scale = Vector3(0.7, 0.08, 0.02)
				x.position = Vector3(0, 0.45, -0.49)
				x.rotation_degrees.z = a
				body.add_child(x)
		return {"body": body}

	func _physics_process(dt: float) -> void:
		if not alive:
			return
		t += dt
		punch = move_toward(punch, 0.0, dt * 6.0)
		(j.body as Node3D).scale = Vector3(1.0 + punch * 0.12, 1.0 - punch * 0.1, 1.0 + punch * 0.12)
		if flash_t > 0.0:
			flash_t -= dt
			if flash_t <= 0.0:
				_set_flash(false)

	func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
		if not alive:
			return
		var d := dmg
		if Enemy.dmg_hook.is_valid():
			d = Enemy.dmg_hook.call(self, dmg, source)
		punch = 1.0
		flash_t = 0.06
		_set_flash(true)
		if tinted and source != "bomb":
			Sfx.play("tink", 0.1, -12.0)
			return
		Sfx.play("clank", 0.15, -12.0)
		hp -= d
		if hp <= 0:
			die(dir, source)

	func stagger(_dir: Vector3, _dur: float) -> void:
		pass

	func die(_dir := Vector3.ZERO, _source := "bullet") -> void:
		if not alive:
			return
		alive = false
		remove_from_group("enemies")
		var at := global_position + Vector3(0, 0.5, 0)
		FX.sparks(at, 14, [Color("c09060"), Color("6a4a30"), Color.WHITE], 6.0, 0.5, -14.0, 0.1)
		FX.puffs(at, 4, [Color("8a7a6a"), Color("4a4040"), Color("4a4040"), Color("4a4040")], 0.6, 0.6, 0.5)
		Sfx.play("land", 0.1, -4.0)
		if Main.inst and Main.inst.has_method("on_crate_broken"):
			Main.inst.on_crate_broken(self)
		queue_free()


class Hearth extends Enemy:
	var flame: MeshInstance3D
	var _burn_cd := 0.0

	func _ready() -> void:
		prop = true
		super._ready()
		add_to_group("rogue_hearths")
		hp = 8
		max_hp = 8
		radius = 0.5
		slice_color = Color("ff9a40")
		landed = true
		(j.body as Node3D).position.y = 0.0
		if is_instance_valid(hp_bar):
			hp_bar.visible = false

	func _init_hp() -> void:
		max_hp = maxi(hp, 1)

	func _build(v: Node3D) -> Dictionary:
		RogueProps._m()
		var body := Build.pivot(v, Vector3.ZERO, "Body")
		var base := MeshInstance3D.new()
		base.mesh = RogueProps._box
		base.material_override = Pal.lit(Color("3a3440"))
		base.scale = Vector3(0.9, 0.3, 0.9)
		base.position.y = 0.15
		body.add_child(base)
		flame = Pal.flat_mesh(RogueProps._ball, Color("ff8a30"), 2.4)
		flame.position.y = 0.75
		body.add_child(flame)
		return {"body": body}

	func _physics_process(dt: float) -> void:
		if not alive:
			return
		t += dt
		_burn_cd -= dt
		var k := float(hp) / max_hp
		flame.scale = Vector3(0.7, 1.0 + sin(t * 17.0) * 0.18, 0.7) * (0.45 + 0.55 * k)
		flame.set_instance_shader_parameter("tint", Color("ffd060").lerp(Color("ff3a20"), fmod(t * 3.0, 1.0)))
		if flash_t > 0.0:
			flash_t -= dt
			if flash_t <= 0.0:
				_set_flash(false)
		var m := Main.inst
		if m and is_instance_valid(m.player) and _burn_cd <= 0.0:
			var b := RogueBuild.inst
			if (b == null or not b.flying()) and m.player.global_position.distance_to(global_position) < 0.95:
				_burn_cd = 0.5
				m.player.take_hit(global_position)

	func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
		if not alive:
			return
		flash_t = 0.05
		_set_flash(true)
		hp -= 1
		FX.sparks(pos if pos != Vector3.ZERO else global_position + Vector3(0, 0.7, 0), 3, [Color("ffd060"), Color("ff5a20")], 3.0, 0.3, 4.0, 0.05)
		if hp <= 0:
			die(dir, source)

	func stagger(_dir: Vector3, _dur: float) -> void:
		pass

	func die(_dir := Vector3.ZERO, _source := "bullet") -> void:
		if not alive:
			return
		alive = false
		remove_from_group("enemies")
		FX.puffs(global_position + Vector3(0, 0.6, 0), 6, [Color("605860"), Color("302830"), Color("302830"), Color("302830")], 0.6, 0.7, 0.8)
		Sfx.play("powerdown", 0.1, -10.0)
		if Main.inst and Main.inst.has_method("on_crate_broken"):
			Main.inst.on_crate_broken(self)
		queue_free()


class Spikes extends Node3D:
	var size := Vector2(3.0, 3.0)
	var sacrifice := false
	var _cd := 0.0

	func _ready() -> void:
		RogueProps._m()
		var base := MeshInstance3D.new()
		base.mesh = RogueProps._box
		base.material_override = Pal.lit(Color("5a3a40"))
		base.scale = Vector3(size.x, 0.08, size.y)
		base.position.y = 0.04
		add_child(base)
		for x in range(int(size.x * 2)):
			for z in range(int(size.y * 2)):
				var sp := MeshInstance3D.new()
				sp.mesh = RogueProps._box
				sp.material_override = Pal.lit(Color("d8d0e0"))
				sp.scale = Vector3(0.12, 0.35, 0.12)
				sp.position = Vector3(-size.x * 0.5 + 0.25 + x * 0.5, 0.2, -size.y * 0.5 + 0.25 + z * 0.5)
				sp.rotation_degrees.y = 45.0
				add_child(sp)

	func _physics_process(dt: float) -> void:
		_cd -= dt
		var m := Main.inst
		if m == null or not is_instance_valid(m.player) or _cd > 0.0:
			return
		var b := RogueBuild.inst
		if b and b.flying():
			return
		var rel := m.player.global_position - global_position
		if absf(rel.x) < size.x * 0.5 and absf(rel.z) < size.y * 0.5 and m.player.invuln <= 0.0:
			_cd = 0.3
			# 소울 하트가 막아도 피해를 받은 것으로 센다 (무적 시간이 새로 걸렸으면 맞은 것)
			m.player.take_hit(global_position + Vector3(0, 0, 0.01))
			if m.player.invuln > 0.0 and sacrifice and m.has_method("on_sacrifice"):
				m.on_sacrifice(self)


class Portal extends Node3D:
	var kind := "trapdoor"       # trapdoor · secret · back · devil · angel · deal_back
	var target := Vector3.ZERO
	var ring_mi: MeshInstance3D
	var disc: MeshInstance3D
	var t := 0.0
	var _cd := 0.6
	var armed := false            # 플레이어가 한 번 떨어져야 들어갈 수 있다 (생기자마자 발밑에서 빨려 들지 않게)
	var label: Label3D

	func _ready() -> void:
		RogueProps._m()
		add_to_group("rogue_portals")
		var c: Color = {"trapdoor": Color("10081a"), "secret": Color("6a40c0"), "back": Color("40a0ff"), "devil": Color("c01020"), "angel": Color("fff4d0"), "deal_back": Color("40a0ff")}.get(kind, Color.WHITE)
		var rc: Color = {"trapdoor": Color("ff5a7a"), "secret": Color("c890ff"), "back": Color("a0e8ff"), "devil": Color("ff6a4a"), "angel": Color("ffe880"), "deal_back": Color("a0e8ff")}.get(kind, Color.WHITE)
		disc = Pal.flat_mesh(RogueProps._disc, c, 1.0)
		disc.scale = Vector3(1.7, 1, 1.7)
		disc.position.y = 0.03
		add_child(disc)
		ring_mi = Pal.flat_mesh(RogueProps._ring, rc, 2.2)
		ring_mi.scale = Vector3(1.9, 1.0, 1.9)
		ring_mi.position.y = 0.06
		add_child(ring_mi)
		label = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 40
		label.outline_size = 12
		label.pixel_size = 0.01
		label.no_depth_test = true
		label.position.y = 1.6
		label.modulate = rc
		label.text = {"trapdoor": "▼ 다음 층", "secret": "비밀방", "back": "돌아가기", "devil": "악마의 방", "angel": "천사의 방", "deal_back": "돌아가기"}.get(kind, "")
		add_child(label)
		FX.ring(global_position + Vector3(0, 0.2, 0), 4.0, [rc, Color.WHITE, rc], 0.5)

	func _physics_process(dt: float) -> void:
		t += dt
		_cd -= dt
		ring_mi.rotate_y(dt * 2.0)
		ring_mi.scale = Vector3(1.9, 1.0, 1.9) * (1.0 + sin(t * 4.0) * 0.06)
		var m := Main.inst
		if m == null or not is_instance_valid(m.player) or _cd > 0.0:
			return
		var rel := m.player.global_position - global_position
		rel.y = 0
		if rel.length() > 1.6:
			armed = true
		if armed and rel.length() < 0.9 and m.has_method("on_portal"):
			_cd = 1.5
			m.on_portal(self)


class Crack extends Node3D:
	var face := Vector3.FORWARD     # 벽 쪽 방향
	var opened := false

	func _ready() -> void:
		RogueProps._m()
		add_to_group("rogue_cracks")
		# 벽면에 그은 금 (어두운 지그재그)
		for i in 5:
			var mi := Pal.flat_mesh(RogueProps._box, Color("101018"), 1.0)
			mi.scale = Vector3(0.06, 0.35, 0.04)
			mi.position = face * 0.48 + Vector3(0, 0.25 + i * 0.12, 0) + face.cross(Vector3.UP) * (0.15 if i % 2 == 0 else -0.12)
			mi.rotation_degrees = Vector3(0, rad_to_deg(atan2(face.x, face.z)), 30.0 if i % 2 == 0 else -30.0)
			add_child(mi)
		var dust := Pal.flat_mesh(RogueProps._disc, Color("2a2a38"), 1.0)
		dust.scale = Vector3(0.9, 1, 0.9)
		dust.position = face * 0.2 + Vector3(0, 0.02, 0)
		add_child(dust)
