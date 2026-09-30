class_name Pickup
extends Node3D
## 바닥에 떨어진 재화 아이템 (미사일 · 에너지). 적이 죽은 자리에 튀어나와 떠 있다가
## 플레이어가 직접 닿아야 먹힌다. 이미 가득 차 있으면 먹히지 않고 그대로 남는다.

const RADIUS := 1.05          # 이 거리 안에 들어오면 먹는다
const MAGNET := 1.9           # 이 안에서는 살짝 끌려온다 (닿기 직전 보정)
const LIFE := 18.0            # 이 시간이 지나면 사라진다 (마지막 4초는 깜빡인다)
const COLORS := {"missile": Color("ffa040"), "energy": Color("5af0ff")}

static var _box: BoxMesh
static var _ball: SphereMesh
static var _ring: TorusMesh

var kind := "missile"
var amount := 1
var age := 0.0
var vel := Vector3.ZERO
var floor_y := 0.0
var settled := false
var core: Node3D
var ring: MeshInstance3D
var _full_hint_t := 0.0


func _ready() -> void:
	add_to_group("pickups")
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
		_ball = SphereMesh.new()
		_ball.radius = 0.5
		_ball.height = 1.0
		_ring = TorusMesh.new()
		_ring.inner_radius = 0.42
		_ring.outer_radius = 0.5
	var c: Color = COLORS[kind]
	core = Node3D.new()
	add_child(core)
	if kind == "missile":
		# 작은 미사일 한 발: 흰 몸통 + 주황 탄두 + 꼬리 날개
		var b := MeshInstance3D.new()
		b.mesh = _box
		b.scale = Vector3(0.16, 0.16, 0.56)
		b.material_override = Pal.lit(Color("eeeaf4"), 0.25)
		core.add_child(b)
		var nose := Pal.flat_mesh(_ball, c, 1.8)
		nose.scale = Vector3(0.17, 0.17, 0.26)
		nose.position = Vector3(0, 0, -0.3)
		core.add_child(nose)
		for s in [-1.0, 1.0]:
			var fin := MeshInstance3D.new()
			fin.mesh = _box
			fin.scale = Vector3(0.36, 0.04, 0.12)
			fin.position = Vector3(0, 0, 0.24)
			fin.rotation.z = PI * 0.5 * (0.0 if s < 0 else 1.0)
			fin.material_override = Pal.lit(c, 0.6)
			core.add_child(fin)
		core.rotation = Vector3(0.5, 0, 0.35)
	else:
		# 에너지 셀: 빛나는 팔면체 결정
		var g := Pal.flat_mesh(_box, c, 2.4)
		g.scale = Vector3.ONE * 0.3
		g.rotation = Vector3(PI * 0.25, 0, PI * 0.25)
		core.add_child(g)
		var inner := Pal.flat_mesh(_ball, Color.WHITE, 3.0)
		inner.scale = Vector3.ONE * 0.16
		core.add_child(inner)
	# 바닥 표시 고리 (멀리서도 떨어진 자리가 보이게)
	ring = Pal.flat_mesh(_ring, c, 1.6)
	ring.scale = Vector3(1.4, 1.0, 1.4)
	add_child(ring)
	floor_y = Main.gy(global_position)
	# 튀어 오르며 떨어진다
	var a := randf() * TAU
	vel = Vector3(cos(a) * randf_range(1.0, 2.6), randf_range(5.0, 7.0), sin(a) * randf_range(1.0, 2.6))


func _physics_process(dt: float) -> void:
	age += dt
	var m := Main.inst
	if not settled:
		vel.y -= 22.0 * dt
		var np := global_position + vel * dt
		if m.is_blocked(Vector3(np.x, global_position.y, np.z)):
			vel.x = -vel.x * 0.4
			vel.z = -vel.z * 0.4
			np = global_position + Vector3(0, vel.y * dt, 0)
		floor_y = Main.gy(np)
		if np.y <= floor_y + 0.55 and vel.y < 0.0:
			np.y = floor_y + 0.55
			if absf(vel.y) > 3.0:
				vel.y = -vel.y * 0.35
				vel.x *= 0.5
				vel.z *= 0.5
			else:
				settled = true
				vel = Vector3.ZERO
		global_position = np
	else:
		var bob := sin(age * 3.2) * 0.12
		global_position.y = floor_y + 0.6 + bob
	core.rotation.y += dt * 2.4
	ring.global_position = Vector3(global_position.x, floor_y + 0.04, global_position.z)
	var pulse := 1.0 + sin(age * 6.0) * 0.08
	ring.scale = Vector3(1.4 * pulse, 1.0, 1.4 * pulse)

	# 수명 끝자락: 깜빡이다 사라진다
	if age > LIFE - 4.0:
		visible = fmod(age, 0.25 if age > LIFE - 1.5 else 0.4) < 0.18
	if age >= LIFE:
		queue_free()
		return

	var p := m.player
	if p == null or not p.alive or age < 0.35:
		return
	var d := p.global_position - global_position
	d.y = 0.0
	var dist := d.length()
	if p.is_full(kind):
		# 가득 찼으면 먹지 않는다. 밟고 있으면 가끔 알려준다.
		_full_hint_t -= dt
		if dist < RADIUS and _full_hint_t <= 0.0:
			_full_hint_t = 1.5
			m.hud.popup("FULL", Color(0.8, 0.8, 0.9), global_position + Vector3(0, 1.2, 0))
		return
	if dist < MAGNET and settled:
		global_position += d.normalized() * minf(dist, dt * 6.0)
	if dist < RADIUS:
		_collect(p)


func _collect(p: Player) -> void:
	var got := p.gain(kind, amount)
	if got <= 0:
		return
	var c: Color = COLORS[kind]
	var m := Main.inst
	FX.flash(global_position, c, 0.9, 0.08)
	FX.sparks(global_position, 10, [c, Color.WHITE], 4.5, 0.35, -8.0, 0.06)
	var ping := Sfx.play("ready", 0.0, -3.0)
	if ping:
		ping.pitch_scale = 1.5 if kind == "energy" else 1.15
	m.hud.popup(("+%d MISSILE" if kind == "missile" else "+%d ENERGY") % got, c, global_position + Vector3(0, 1.3, 0))
	amount -= got
	if amount <= 0:
		queue_free()
