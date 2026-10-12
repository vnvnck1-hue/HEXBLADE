class_name RogueLook
extends Node
## 변신 외형: 플레이어 몸(visual)에 장식을 붙인다.
##  angel 후광 + 빛 날개 · demon 뿔 + 붉은 바닥 오라 · fly 검은 파리 구름 · poison 초록 오라 · mushroom 몸 1.3배
##  tech 청록 회로 고리 + 안테나 · blade 떠도는 검 3자루 · bomb 도화선 불꽃 · gun 어깨 보조 포신
## 성스러운 망토가 준비되면 옅은 방패 막.

static var _box: BoxMesh
static var _ball: SphereMesh
static var _ring: TorusMesh
static var _cone: CylinderMesh

var build: RogueBuild
var root: Node3D
var ground: Node3D
var parts := {}              # 태그 → Node3D
var mantle: MeshInstance3D
var t := 0.0
var _scale := 1.0


static func _m() -> void:
	if _box:
		return
	_box = BoxMesh.new()
	_ball = SphereMesh.new()
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 10
	_ball.rings = 5
	_ring = TorusMesh.new()
	_ring.inner_radius = 0.44
	_ring.outer_radius = 0.5
	_ring.rings = 28
	_cone = CylinderMesh.new()
	_cone.top_radius = 0.0
	_cone.bottom_radius = 0.5
	_cone.height = 1.0
	_cone.radial_segments = 8


func refresh(b: RogueBuild) -> void:
	build = b
	_m()
	var p := b.player
	if not is_instance_valid(p) or p.visual == null:
		return
	if root == null:
		root = Node3D.new()
		root.name = "RogueLook"
		p.visual.add_child(root)
		ground = Node3D.new()
		ground.name = "RogueAura"
		p.add_child(ground)
		mantle = Pal.flat_mesh(_ring, Color("fff4c0"), 2.2)
		mantle.scale = Vector3(1.5, 1.0, 1.5)
		mantle.position.y = 0.1
		mantle.visible = false
		root.add_child(mantle)
	for tag in RogueItems.TRANSFORMS:
		var want: bool = b.trans.has(tag)
		if want and not parts.has(tag):
			parts[tag] = _make(tag)
		elif not want and parts.has(tag):
			parts[tag].queue_free()
			parts.erase(tag)
	_scale = 1.0
	if b.f("grow") > 0:
		_scale *= 1.0 + 0.15 * mini(b.f("grow"), 2)
	if b.f("shrink") > 0:
		_scale *= 0.85
	p.visual.scale = Vector3.ONE * _scale


func _part(parent: Node3D, mesh: Mesh, c: Color, pos: Vector3, s: Vector3, e := 1.6) -> MeshInstance3D:
	var mi := Pal.flat_mesh(mesh, c, e)
	mi.position = pos
	mi.scale = s
	parent.add_child(mi)
	return mi


func _make(tag: String) -> Node3D:
	var n := Node3D.new()
	n.name = "T_" + tag
	var on_ground := tag in ["demon", "poison", "tech"]
	(ground if on_ground else root).add_child(n)
	match tag:
		"angel":
			_part(n, _ring, Color("fff0a0"), Vector3(0, 1.25, 0), Vector3(0.55, 0.6, 0.55), 2.6)
			for s in [-1.0, 1.0]:
				var w := _part(n, _box, Color("fffbe8"), Vector3(s * 0.55, 0.55, 0.35), Vector3(0.9, 0.06, 0.45), 2.0)
				w.rotation_degrees = Vector3(0, s * -25.0, s * 30.0)
		"demon":
			var aura := _part(n, _ring, Color("ff2a3a"), Vector3(0, 0.05, 0), Vector3(1.4, 0.4, 1.4), 2.2)
			aura.name = "Aura"
			for s in [-1.0, 1.0]:
				var h := _part(n, _cone, Color("401018"), Vector3(s * 0.16, 1.8, -0.05), Vector3(0.12, 0.32, 0.12), 1.0)
				h.rotation_degrees.z = s * -25.0
		"fly":
			for i in 6:
				var f := _part(n, _ball, Color("1a1a12"), Vector3.ZERO, Vector3.ONE * 0.12, 1.0)
				f.name = "Fly%d" % i
		"poison":
			_part(n, _ring, Color("70ff60"), Vector3(0, 0.05, 0), Vector3(1.3, 0.4, 1.3), 2.0).name = "Aura"
		"mushroom":
			_part(n, _ball, Color("e05040"), Vector3(0, 1.0, 0), Vector3(0.7, 0.3, 0.7), 1.4)
			for i in 4:
				_part(n, _ball, Color("fff0e0"), Vector3(cos(i * 1.6) * 0.22, 1.1, sin(i * 1.6) * 0.22), Vector3.ONE * 0.09, 1.6)
		"tech":
			_part(n, _ring, Color("40e8ff"), Vector3(0, 0.06, 0), Vector3(1.2, 0.3, 1.2), 2.4).name = "Aura"
			_part(n, _ring, Color("40e8ff"), Vector3(0, 0.06, 0), Vector3(0.9, 0.3, 0.9), 1.6).name = "Aura2"
			_part(n, _box, Color("40e8ff"), Vector3(0.12, 1.95, 0), Vector3(0.03, 0.4, 0.03), 2.0)
		"blade":
			for i in 3:
				var sw := Node3D.new()
				sw.name = "Sword%d" % i
				n.add_child(sw)
				_part(sw, _box, Color("ff7ac8"), Vector3(0, 0, 0), Vector3(0.06, 0.06, 0.8), 2.6)
				_part(sw, _box, Color("ffe0f4"), Vector3(0, 0, 0.42), Vector3(0.2, 0.05, 0.05), 1.6)
		"bomb":
			_part(n, _ball, Color("2a2a38"), Vector3(-0.3, 0.1, 0.25), Vector3.ONE * 0.2, 1.0)
			_part(n, _ball, Color("2a2a38"), Vector3(0.3, 0.1, 0.25), Vector3.ONE * 0.2, 1.0)
			_part(n, _ball, Color("ffd060"), Vector3(0, 0.9, 0.25), Vector3.ONE * 0.1, 2.8).name = "Fuse"
		"gun":
			for s in [-1.0, 1.0]:
				var pod := _part(n, _box, Color("ffb040"), Vector3(s * 0.55, 0.55, 0.05), Vector3(0.14, 0.14, 0.5), 1.4)
				pod.name = "Pod"
	var tc: Color = RogueItems.TAG_COLORS.get(tag, Color.WHITE)
	FX.ring(build.player.global_position + Vector3(0, 0.3, 0), 4.5, [tc, Color.WHITE, tc], 0.6)
	return n


func mantle_show(on: bool) -> void:
	if mantle:
		mantle.visible = on


func mantle_pop() -> void:
	if mantle == null:
		return
	mantle.visible = false
	FX.sparks(mantle.global_position, 18, [Color("fff4c0"), Color.WHITE], 7.0, 0.4, -6.0, 0.08)


var _dt_last := 0.0


func _process(dt: float) -> void:
	t += dt
	_dt_last = dt
	if mantle and mantle.visible:
		mantle.scale = Vector3(1.5, 1.0, 1.5) * (1.0 + sin(t * 5.0) * 0.05)
		mantle.rotate_y(_dt_last * 1.2)
	for tag in parts:
		var n: Node3D = parts[tag]
		if not is_instance_valid(n):
			continue
		match tag:
			"fly":
				var i := 0
				for f in n.get_children():
					var a := t * (3.0 + i * 0.4) + i * 1.3
					(f as Node3D).position = Vector3(cos(a) * (0.8 + sin(t * 7.0 + i) * 0.2), 0.6 + sin(t * 9.0 + i * 2.0) * 0.4, sin(a) * 0.8)
					i += 1
			"blade":
				var i := 0
				for sw in n.get_children():
					var a := t * 1.8 + TAU * i / 3.0
					var s3 := sw as Node3D
					s3.position = Vector3(cos(a) * 1.1, 0.3 + sin(t * 2.0 + i) * 0.15, sin(a) * 1.1)
					s3.rotation = Vector3(0, -a, 0)
					i += 1
			"demon", "poison", "tech":
				for c in n.get_children():
					if str(c.name).begins_with("Aura"):
						(c as Node3D).rotate_y(dt * (1.5 if c.name == "Aura" else -2.5))
			"bomb":
				var fz := n.get_node_or_null("Fuse")
				if fz:
					fz.visible = fmod(t * 14.0, 1.0) < 0.6
