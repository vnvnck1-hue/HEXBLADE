class_name RoguePickup
extends Node3D
## 로그 모드 픽업: 동전(1·5·10) · 열쇠 · 폭탄 · 하트(반·한 칸) · 소울 · 블랙 · 배터리 · 알약 · 카드/룬 · 장신구 · 상자 · 미사일.
## 튀어나왔다가 내려앉고, 플레이어가 닿으면 RogueMain.collect() 가 받는다 (하트가 가득이면 안 먹는다).
## price > 0 이면 상점 진열품: 동전이 모자라면 집을 수 없다.

const KINDS := ["coin", "nickel", "dime", "key", "bomb", "heart", "half_heart", "soul", "black", "battery", "pill", "card", "trinket", "chest", "missile"]

static var _disc: CylinderMesh
static var _ball: SphereMesh
static var _box: BoxMesh
static var _ring: TorusMesh
static var _cap: CapsuleMesh

var kind := "coin"
var value = null                 # 알약 색 번호 · 카드 id · 장신구 id
var price := 0
var horse := false               # 큰 알약
var vel := Vector3.ZERO
var age := 0.0
var settled := false
var gy := 0.0
var body: Node3D
var label: Label3D
var _deny_t := 0.0


static func _m() -> void:
	if _disc:
		return
	_disc = CylinderMesh.new()
	_disc.top_radius = 0.5
	_disc.bottom_radius = 0.5
	_disc.height = 0.12
	_disc.radial_segments = 14
	_ball = SphereMesh.new()
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 12
	_ball.rings = 6
	_box = BoxMesh.new()
	_ring = TorusMesh.new()
	_ring.inner_radius = 0.32
	_ring.outer_radius = 0.5
	_cap = CapsuleMesh.new()
	_cap.radius = 0.2
	_cap.height = 0.8


static func make(kind_: String, value_ = null) -> RoguePickup:
	var p := RoguePickup.new()
	p.kind = kind_
	p.value = value_
	return p


func _ready() -> void:
	_m()
	add_to_group("rogue_pickups")
	body = Node3D.new()
	add_child(body)
	_build()
	FX.blob_shadow(self, 0.9, 0.5)
	gy = Main.gy(global_position)
	if price > 0:
		label = Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 54
		label.outline_size = 14
		label.pixel_size = 0.01
		label.modulate = Color("ffe070")
		label.text = "%d¢" % price
		label.position = Vector3(0, 1.3, 0)
		label.no_depth_test = true
		add_child(label)
		settled = true


func _part(mesh: Mesh, c: Color, pos: Vector3, s: Vector3, e := 1.2) -> MeshInstance3D:
	var mi := Pal.flat_mesh(mesh, c, e)
	mi.position = pos
	mi.scale = s
	body.add_child(mi)
	return mi


func _heart(c: Color, s := 1.0) -> void:
	_part(_ball, c, Vector3(-0.13, 0.12, 0) * s, Vector3.ONE * 0.32 * s, 1.5)
	_part(_ball, c, Vector3(0.13, 0.12, 0) * s, Vector3.ONE * 0.32 * s, 1.5)
	var tip := _part(_box, c, Vector3(0, -0.02, 0) * s, Vector3(0.3, 0.3, 0.2) * s, 1.5)
	tip.rotation_degrees.z = 45.0


func _build() -> void:
	match kind:
		"coin", "nickel", "dime":
			var c: Color = {"coin": Color("ffd040"), "nickel": Color("d8e0f0"), "dime": Color("80d0ff")}[kind]
			var s: float = {"coin": 0.42, "nickel": 0.5, "dime": 0.55}[kind]
			var d := _part(_disc, c, Vector3.ZERO, Vector3(s, 1, s), 1.6)
			d.rotation_degrees.x = 90.0
			_part(_disc, Color.WHITE, Vector3(0, 0, 0.05), Vector3(s * 0.4, 0.6, s * 0.4), 1.8).rotation_degrees.x = 90.0
		"key":
			_part(_ring, Color("ffd040"), Vector3(0, 0.15, 0), Vector3(0.35, 0.35, 0.35), 1.5).rotation_degrees.x = 90.0
			_part(_box, Color("ffd040"), Vector3(0, -0.15, 0), Vector3(0.07, 0.4, 0.07), 1.5)
			_part(_box, Color("ffd040"), Vector3(0.08, -0.3, 0), Vector3(0.12, 0.06, 0.06), 1.5)
		"bomb":
			_part(_ball, Color("2a2a38"), Vector3.ZERO, Vector3.ONE * 0.5, 1.0)
			_part(_box, Color("a08060"), Vector3(0, 0.3, 0), Vector3(0.05, 0.14, 0.05), 1.0)
			_part(_ball, Color("ffb040"), Vector3(0, 0.39, 0), Vector3.ONE * 0.09, 2.6)
		"heart":
			_heart(Color("ff3a4a"))
		"half_heart":
			_heart(Color("ff3a4a"), 0.7)
		"soul":
			_heart(Color("6a8aff"))
		"black":
			_heart(Color("3a2050"))
		"battery":
			_part(_box, Color("40c060"), Vector3.ZERO, Vector3(0.25, 0.45, 0.25), 1.2)
			_part(_box, Color("e0f0e0"), Vector3(0, 0.26, 0), Vector3(0.1, 0.07, 0.1), 1.4)
			_part(_box, Color("ffe040"), Vector3(0, 0.0, -0.13), Vector3(0.06, 0.22, 0.01), 2.0)
		"pill":
			var cols: Array = RogueItems.PILL_COLORS[int(value) % RogueItems.PILL_COLORS.size()]
			var s := 1.5 if horse else 1.0
			_part(_ball, cols[1], Vector3(-0.1, 0, 0) * s, Vector3(0.36, 0.3, 0.3) * s, 1.4)
			_part(_ball, cols[2], Vector3(0.1, 0, 0) * s, Vector3(0.36, 0.3, 0.3) * s, 1.4)
		"card":
			var rune := str(value) in ["hagalaz", "berkano", "algiz"]
			_part(_box, Color("909aa8") if rune else Color("f4f0e8"), Vector3.ZERO, Vector3(0.36, 0.5, 0.05), 1.2)
			_part(_box, Color("6060ff") if rune else Color("e03a4a"), Vector3(0, 0, -0.03), Vector3(0.14, 0.14, 0.02), 2.0).rotation_degrees.z = 45.0
		"trinket":
			_part(_ring, Color("d0c0ff"), Vector3.ZERO, Vector3(0.4, 0.4, 0.4), 1.6).rotation_degrees.x = 90.0
			_part(_ball, Color("ff8ad0"), Vector3(0, 0.2, 0), Vector3.ONE * 0.14, 2.2)
		"chest":
			_part(_box, Color("a06a30"), Vector3.ZERO, Vector3(0.7, 0.45, 0.5), 1.0)
			_part(_box, Color("ffd040"), Vector3(0, 0.05, 0), Vector3(0.72, 0.07, 0.52), 1.4)
			_part(_box, Color("ffd040"), Vector3(0, 0.0, -0.26), Vector3(0.12, 0.14, 0.04), 1.8)
		"missile":
			_part(_box, Color("e8e8f0"), Vector3.ZERO, Vector3(0.14, 0.14, 0.5), 1.2)
			_part(_ball, Color("ff7a30"), Vector3(0, 0, 0.27), Vector3.ONE * 0.16, 2.4)


func _physics_process(dt: float) -> void:
	age += dt
	_deny_t -= dt
	var main := Main.inst
	if main == null or not is_instance_valid(main.player):
		return
	if not settled:
		vel.y -= 26.0 * dt
		var np := global_position + vel * dt
		if main.is_blocked(Vector3(np.x, global_position.y, global_position.z)):
			vel.x = -vel.x * 0.5
			np.x = global_position.x
		if main.is_blocked(Vector3(np.x, global_position.y, np.z)):
			vel.z = -vel.z * 0.5
			np.z = global_position.z
		if np.y <= gy + 0.45:
			np.y = gy + 0.45
			if absf(vel.y) < 2.5:
				settled = true
				vel = Vector3.ZERO
			else:
				vel.y = -vel.y * 0.45
				vel.x *= 0.6
				vel.z *= 0.6
		global_position = np
	body.rotation.y += dt * (2.2 if kind in ["coin", "nickel", "dime", "key", "trinket", "card"] else 0.6)
	body.position.y = sin(age * 3.0) * 0.07
	var p := main.player
	var to := p.global_position - global_position
	to.y = 0
	var b := RogueBuild.inst
	if price == 0 and settled and b and b.f("magnet") > 0 and to.length() < 6.0 and kind != "chest":
		var np2 := global_position + to.normalized() * minf(to.length(), 7.0 * dt)
		if not main.is_blocked(np2):
			global_position = np2
	if age > 0.35 and to.length() < 0.95 and _deny_t <= 0.0:
		if main.has_method("collect") and main.collect(self):
			queue_free()
		else:
			_deny_t = 0.8


## 상점·상자에서 튀어나오게
func pop(dir := Vector3.ZERO) -> void:
	settled = false
	if dir == Vector3.ZERO:
		dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	vel = dir * randf_range(2.0, 4.0) + Vector3(0, randf_range(6.0, 8.0), 0)
