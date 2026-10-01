class_name Missile
extends Node3D
## 궁극기 미사일. 비행은 세 박자로 극적으로 끊는다:
##  1. 사출(BURST): 발사 속도의 LAUNCH_BOOST 배로 사방에 튀어 나간다.
##  2. 제동(BRAKE): 공중에서 급격히 감속해 잠깐 멈칫하며, 그동안 코를 목표 쪽으로 돌린다.
##  3. 돌진(DASH): 속도를 제곱으로 끌어올려 목표에 일직선으로 꽂힌다.
## 배기 연기는 푸른 계열 3겹: 노즐 불꽃 심지 · 부풀며 퍼지는 연기 덩어리 · 튀는 불티.
## 목표(락온한 적)가 없으면 target_pos 바닥 지점에 떨어진다. 다른 적을 스스로 찾아 조준하지 않는다.

const LAUNCH_BOOST := 1.8
const BURST := 0.04            # 사출 유지 시간
const HANG := 0.13             # 제동이 끝나고 돌진을 시작하는 시각
const BRAKE := 17.0            # 제동 감속률 (클수록 멈칫이 깊다)
const DASH_START := 4.0        # 돌진 시작 속도
const DASH_ACCEL := 2200.0     # 돌진 속도 = DASH_START + DASH_ACCEL × t²
const MAX_SPEED := 78.0
const DAMAGE := 6
const SPLASH := 1.6
const SIZE := 1.8              # 모델 배율 (예전 대비)
const PUFF_GAP := 0.14         # 연기 덩어리 간격 (m) — 빨라져도 끊기지 않게 거리로 뿌린다
const SMOKE := [Color("eaf8ff"), Color("a8dcff"), Color("6ab8ff"), Color("3a8cff")]
const SMOKE_END := Color("0e2260")
const CORE := Color("dff6ff")

static var _body_mesh: CylinderMesh
static var _cone_mesh: CylinderMesh
static var _fin_mesh: BoxMesh
static var _band_mesh: CylinderMesh
static var _tip_mesh: SphereMesh

var vel := Vector3.ZERO
var target: Enemy = null
var target_pos := Vector3.ZERO
var age := 0.0
var trail_d := 0.0
var trail_t := 0.0
var flame: MeshInstance3D
var flame_core: MeshInstance3D
var wobble := Vector3.ZERO


static func _meshes() -> void:
	if _body_mesh != null:
		return
	_body_mesh = CylinderMesh.new()
	_body_mesh.top_radius = 0.055
	_body_mesh.bottom_radius = 0.055
	_body_mesh.height = 0.36
	_body_mesh.radial_segments = 8
	_body_mesh.rings = 1
	_cone_mesh = CylinderMesh.new()
	_cone_mesh.top_radius = 0.0
	_cone_mesh.bottom_radius = 0.055
	_cone_mesh.height = 0.13
	_cone_mesh.radial_segments = 8
	_cone_mesh.rings = 1
	_fin_mesh = BoxMesh.new()
	_fin_mesh.size = Vector3(0.012, 0.15, 0.1)
	_band_mesh = CylinderMesh.new()
	_band_mesh.top_radius = 0.06
	_band_mesh.bottom_radius = 0.06
	_band_mesh.height = 0.035
	_band_mesh.radial_segments = 8
	_band_mesh.rings = 1
	_tip_mesh = SphereMesh.new()
	_tip_mesh.radius = 0.5
	_tip_mesh.height = 1.0
	_tip_mesh.radial_segments = 10
	_tip_mesh.rings = 5


func _ready() -> void:
	_meshes()
	# 모델은 -Z 가 앞. 원기둥(Y축)을 눕혀 쓴다.
	var root := Node3D.new()
	root.scale = Vector3.ONE * SIZE
	add_child(root)
	var b := MeshInstance3D.new()
	b.mesh = _body_mesh
	b.material_override = Pal.lit(Color("eceaf4"))
	b.rotation.x = PI * 0.5
	root.add_child(b)
	var cone := Pal.flat_mesh(_cone_mesh, Color("ff6a3a"), 1.8)
	cone.rotation.x = -PI * 0.5
	cone.position = Vector3(0, 0, -0.245)
	root.add_child(cone)
	var band := Pal.flat_mesh(_band_mesh, Color("5ab8ff"), 2.4)
	band.rotation.x = PI * 0.5
	band.position = Vector3(0, 0, -0.09)
	root.add_child(band)
	for i in 4:
		var fin := MeshInstance3D.new()
		fin.mesh = _fin_mesh
		fin.material_override = Pal.lit(Color("ff7a4a"))
		var a := TAU * i / 4.0 + PI * 0.25
		fin.position = Vector3(cos(a), sin(a), 0) * 0.075 + Vector3(0, 0, 0.14)
		fin.rotation.z = a - PI * 0.5
		root.add_child(fin)
	flame = Pal.flat_mesh(_tip_mesh, Color("6ac4ff"), 2.4)
	flame.position = Vector3(0, 0, 0.24 * SIZE)
	add_child(flame)
	flame_core = Pal.flat_mesh(_tip_mesh, Color.WHITE, 3.0)
	flame_core.position = Vector3(0, 0, 0.2 * SIZE)
	add_child(flame_core)
	wobble = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
	vel *= LAUNCH_BOOST
	_launch_cloud.call_deferred()


## 발사구에서 뿜어지는 첫 연기 뭉치
func _launch_cloud() -> void:
	var back := -vel.normalized() if vel.length() > 0.1 else Vector3.DOWN
	for i in 6:
		_billow(global_position + back * randf_range(0.1, 0.4), back * randf_range(1.5, 4.0), 1.3)


func _physics_process(dt: float) -> void:
	age += dt
	if target != null and (not is_instance_valid(target) or not target.alive):
		# 목표가 먼저 죽으면 다른 적을 찾지 않고, 목표가 있던 자리 바닥에 떨어진다
		target = null
		target_pos.y = Main.gy(target_pos)
	var goal := target_pos
	if target != null:
		goal = target.global_position + Vector3(0, 1.0, 0)
		target_pos = target.global_position
	var prev := global_position
	var to_goal := (goal - global_position).normalized()
	if age < BURST:
		# 사출: 거의 감속 없이 튀어 나간다
		vel += wobble * 6.0 * dt
	elif age < HANG:
		# 제동: 급감속하며 멈칫, 후반엔 코를 목표로 돌린다
		vel *= exp(-BRAKE * dt)
		vel.y -= 4.0 * dt
		var turn := clampf((age - BURST) / (HANG - BURST), 0.0, 1.0)
		var sp := vel.length()
		vel = vel.normalized().slerp(to_goal, turn * turn * 0.6) * sp if sp > 0.01 else to_goal * sp
	else:
		# 돌진: 제곱 가속으로 목표에 일직선
		var u := age - HANG
		var speed := minf(MAX_SPEED, DASH_START + DASH_ACCEL * u * u)
		var dir := vel.normalized() if vel.length() > 0.01 else to_goal
		vel = dir.slerp(to_goal, 1.0 - exp(-40.0 * dt)) * speed
	global_position += vel * dt
	if vel.length() > 0.1:
		look_at(global_position + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.RIGHT)
	var sk := minf(vel.length() / MAX_SPEED, 1.0)
	var fl := 1.0 + randf() * 0.6
	flame.scale = Vector3(0.2, 0.2, 0.4 + sk * 0.9) * fl
	flame.position.z = (0.24 + sk * 0.22) * SIZE
	flame_core.scale = Vector3(0.11, 0.11, 0.2 + sk * 0.45) * fl
	# 연기 궤적: 지나온 길을 따라 일정 간격으로, 멈칫하는 동안에도 조금씩
	_smoke_along(prev, global_position, dt)
	var hit_r := 0.9 if target != null else 0.6
	if global_position.distance_to(goal) < hit_r or global_position.y < Main.gy(global_position) + 0.15 or age > 3.0:
		_explode()


func _smoke_along(from: Vector3, to: Vector3, dt: float) -> void:
	var seg := from.distance_to(to)
	var dir := vel.normalized() if vel.length() > 0.01 else Vector3.FORWARD
	var nozzle := -dir * 0.32 * SIZE
	var sk := minf(vel.length() / MAX_SPEED, 1.0)
	trail_d += seg
	trail_t -= dt
	var n := 0
	while trail_d >= PUFF_GAP and n < 14:
		trail_d -= PUFF_GAP
		var k := minf(trail_d / seg, 1.0) if seg > 0.001 else 0.0
		var p := to.lerp(from, k) + nozzle
		_billow(p, -dir * randf_range(1.0, 3.0) * (0.4 + sk), 1.0)
		if n % 2 == 0:
			_core(p)
		n += 1
	if n == 0 and trail_t <= 0.0:
		# 멈칫하는 동안에도 노즐에서 연기가 계속 뿜어진다
		trail_t = 0.016
		_billow(to + nozzle, -dir * randf_range(2.0, 4.0), 1.15)
		_core(to + nozzle)
	elif n > 0:
		trail_t = 0.016
	if randf() < 0.35:
		FX.sparks(to + nozzle, 1, [Color.WHITE, Color("8ad8ff")], 3.0, 0.22, -4.0, 0.035)


## 부풀며 흩어지는 연기 덩어리: 빠르게 커졌다가 옆으로 퍼지며 짙은 남색으로 식고 줄어든다
func _billow(p: Vector3, push: Vector3, big: float) -> void:
	var c: Color = SMOKE[randi() % SMOKE.size()]
	var mi := Pal.flat_mesh(_tip_mesh, c, 1.25)
	# 흐르는 씬(추격전)에서는 연기 꼬리가 공기처럼 뒤로 끌려 흐른다 (WorldFlow, 아니면 FX.root)
	WorldFlow.holder(WorldFlow.AIR).add_child(mi)
	mi.global_position = p + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.06
	var s0 := randf_range(0.18, 0.28) * big
	var s1 := randf_range(0.5, 0.85) * big
	var life := randf_range(0.45, 0.75)
	mi.scale = Vector3.ONE * s0
	var side := Vector3(randf_range(-1, 1), randf_range(-0.3, 1.0), randf_range(-1, 1)) * randf_range(0.6, 1.6)
	var drift := (push * 0.35 + side + Vector3(0, 0.5, 0)) * life
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * s1, life * 0.35).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mi, "position", mi.position + drift, life).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: Color): mi.set_instance_shader_parameter("tint", v), c, SMOKE_END, life).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(mi, "scale", Vector3.ONE * 0.01, life * 0.55).set_delay(life * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## 노즐 바로 뒤 밝은 불꽃 심지 (짧게 번쩍이고 사라진다)
func _core(p: Vector3) -> void:
	var mi := Pal.flat_mesh(_tip_mesh, CORE, 2.6)
	FX.root.add_child(mi)
	mi.global_position = p
	mi.scale = Vector3.ONE * randf_range(0.22, 0.32)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.16).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(v: Color): mi.set_instance_shader_parameter("tint", v), CORE, Color("3a8cff"), 0.16)
	tw.tween_callback(mi.queue_free)


func _explode() -> void:
	var p := global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en.alive and en.landed and (en.global_position + Vector3(0, 1, 0)).distance_to(p) < SPLASH:
			var d := en.global_position - p
			d.y = 0
			en.take_hit(DAMAGE, d.normalized() if d.length() > 0.01 else Vector3.FORWARD, p, "missile")
	FX.fire_explosion(p, 0.5)
	FX.sparks(p, 8, [Color.WHITE, Color("ffb040"), Color("ff5a3a")], 7.0, 0.35, -10.0, 0.08)
	Sfx.play("boom", 0.25, -9.0)
	Main.inst.shake(0.08)
	queue_free()
