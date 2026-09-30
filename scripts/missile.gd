class_name Missile
extends Node3D
## 궁극기 미사일. 발사 직후 사방으로 흩날리다가(SCATTER) 방향을 틀어 목표로 급가속 유도한다.
## 목표(락온한 적)가 없으면 target_pos 바닥 지점에 떨어진다. 다른 적을 스스로 찾아 조준하지 않는다.

const SCATTER := 0.3
const MAX_SPEED := 36.0
const DAMAGE := 6
const SPLASH := 1.6

static var _body_mesh: BoxMesh
static var _tip_mesh: SphereMesh

var vel := Vector3.ZERO
var target: Enemy = null
var target_pos := Vector3.ZERO
var age := 0.0
var trail_t := 0.0
var flame: MeshInstance3D
var wobble := Vector3.ZERO


func _ready() -> void:
	if _body_mesh == null:
		_body_mesh = BoxMesh.new()
		_body_mesh.size = Vector3(0.1, 0.1, 0.38)
		_tip_mesh = SphereMesh.new()
		_tip_mesh.radius = 0.5
		_tip_mesh.height = 1.0
	var b := MeshInstance3D.new()
	b.mesh = _body_mesh
	b.material_override = Pal.lit(Color("e8e6f0"))
	add_child(b)
	var nose := Pal.flat_mesh(_tip_mesh, Color("ff6a3a"), 1.6)
	nose.scale = Vector3.ONE * 0.12
	nose.position = Vector3(0, 0, -0.2)
	add_child(nose)
	flame = Pal.flat_mesh(_tip_mesh, Color("ffd070"), 2.2)
	flame.position = Vector3(0, 0, 0.26)
	add_child(flame)
	wobble = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))


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
	if age < SCATTER:
		# 흩날림: 감속하며 살짝 흔들린다
		vel *= exp(-3.0 * dt)
		vel.y -= 6.0 * dt
		vel += wobble * 8.0 * dt
	else:
		var speed := minf(MAX_SPEED, 10.0 + (age - SCATTER) * 70.0)
		var want := (goal - global_position).normalized() * speed
		vel = vel.lerp(want, 1.0 - exp(-(6.0 + age * 10.0) * dt))
	global_position += vel * dt
	if vel.length() > 0.1:
		look_at(global_position + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.RIGHT)
	flame.scale = Vector3(0.1, 0.1, 0.25) * (1.0 + randf() * 0.6)
	# 연기 궤적
	trail_t -= dt
	if trail_t <= 0.0:
		trail_t = 0.018
		_trail()
	var hit_r := 0.9 if target != null else 0.6
	if global_position.distance_to(goal) < hit_r or global_position.y < Main.gy(global_position) + 0.15 or age > 3.0:
		_explode()


func _trail() -> void:
	var c := Color("ffffff") if randf() < 0.5 else Color("c8c0e8")
	var mi := Pal.flat_mesh(_tip_mesh, c, 1.0)
	FX.root.add_child(mi)
	mi.global_position = global_position - vel.normalized() * 0.25
	mi.scale = Vector3.ONE * randf_range(0.12, 0.2)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.35).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(v: Color): mi.set_instance_shader_parameter("tint", v), c, Color("3a2a60"), 0.35)
	tw.tween_callback(mi.queue_free)


func _explode() -> void:
	var p := global_position
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en.alive and en.landed and (en.global_position + Vector3(0, 1, 0)).distance_to(p) < SPLASH:
			var d := en.global_position - p
			d.y = 0
			en.take_hit(DAMAGE, d.normalized() if d.length() > 0.01 else Vector3.FORWARD, p, "missile")
	FX.fire_explosion(p, 0.38)
	FX.sparks(p, 8, [Color.WHITE, Color("ffb040"), Color("ff5a3a")], 7.0, 0.35, -10.0, 0.08)
	Sfx.play("boom", 0.25, -9.0)
	Main.inst.shake(0.08)
	queue_free()
