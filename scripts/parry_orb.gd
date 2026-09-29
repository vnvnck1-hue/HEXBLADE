class_name ParryOrb
extends Node3D
## 패링 탄: 금빛 가시 링을 두른 큰 에너지 구체. 느리게 플레이어를 살짝 따라온다.
## 닿기 직전 대시로 패링하면 쏜 적에게 고속으로 되돌아가 크게 터진다.
## 대시 무적으로 그냥 피할 수도 있다 (피하면 그대로 지나간다).

const SPEED := 9.5
const HOMING := 1.5            # rad/s. 가까워지면 멈춘다
const HOMING_STOP := 3.2
const RADIUS := 0.32
const REFLECT_SPEED := 30.0
const REFLECT_HOMING := 12.0
const REFLECT_DMG := 12

var vel := Vector3.ZERO
var source: Enemy
var reflected := false
var life := 6.0
var age := 0.0
var core: MeshInstance3D
var shell: MeshInstance3D
var spikes: Node3D
var trail_t := 0.0
var _cued := false


static func make(pos: Vector3, dir: Vector3, from: Enemy) -> ParryOrb:
	var o := ParryOrb.new()
	o.position = pos
	o.vel = dir * SPEED
	o.source = from
	return o


func _ready() -> void:
	add_to_group("parry_orbs")
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 16
	sm.rings = 8
	shell = Pal.flat_mesh(sm, ParryFX.GOLD, 1.9)
	shell.scale = Vector3.ONE * RADIUS * 2.3
	add_child(shell)
	core = Pal.flat_mesh(sm, ParryFX.HOT, 3.2)
	core.scale = Vector3.ONE * RADIUS * 1.35
	add_child(core)
	# 금빛 가시 링: 패링 공격임을 모양으로도 구분한다
	spikes = Node3D.new()
	add_child(spikes)
	var pm := PrismMesh.new()
	pm.size = Vector3(0.12, 0.28, 0.06)
	for i in 8:
		var a := TAU * i / 8.0
		var mi := Pal.flat_mesh(pm, ParryFX.GOLD if i % 2 == 0 else ParryFX.HOT, 2.4)
		spikes.add_child(mi)
		mi.position = Vector3(cos(a), 0, sin(a)) * 0.5
		mi.basis = Basis(Vector3.UP, -a) * Basis(Vector3.FORWARD, -PI * 0.5)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.3)
	light.light_energy = 1.6
	light.omni_range = 3.2
	add_child(light)
	Parry.inst.register(self)


func _exit_tree() -> void:
	if Parry.inst:
		Parry.inst.unregister(self)


func _physics_process(dt: float) -> void:
	age += dt
	life -= dt
	if life <= 0.0:
		_pop()
		return
	var main := Main.inst
	var p := main.player
	if reflected:
		_steer_to_target(dt)
	elif p.alive:
		var to := p.global_position - position
		to.y = 0
		if to.length() > HOMING_STOP:
			var cur := Vector3(vel.x, 0, vel.z).normalized()
			var ang := cur.signed_angle_to(to.normalized(), Vector3.UP)
			vel = cur.rotated(Vector3.UP, clampf(ang, -HOMING * dt, HOMING * dt)) * SPEED
	position += vel * dt
	# 모양: 가시 링이 돌고 구체가 맥동한다. 판정 창이 열리면 하얗게 번쩍이며 부푼다.
	spikes.rotation.y += dt * (14.0 if reflected else 6.0)
	spikes.rotation.x = sin(age * 3.0) * 0.4
	var pulse := 1.0 + sin(age * 30.0) * 0.08
	var hot := _cued and not reflected
	shell.scale = Vector3.ONE * RADIUS * 2.3 * pulse * (1.35 if hot else 1.0)
	shell.set_instance_shader_parameter("tint", ParryFX.HOT if hot and fmod(age, 0.06) < 0.03 else ParryFX.GOLD)
	trail_t -= dt
	if trail_t <= 0.0:
		trail_t = 0.02 if reflected else 0.04
		FX.flash(position - vel.normalized() * 0.2, ParryFX.GOLD if not reflected else ParryFX.HOT, RADIUS * (2.4 if reflected else 1.6), 0.14)
	if main.is_blocked(position):
		_pop()
		return
	if reflected:
		_check_enemy_hit()
		return
	if p.alive and Vector2(position.x - p.global_position.x, position.z - p.global_position.z).length() < p.hit_radius + RADIUS:
		if p.take_hit(position):
			_pop()


func _pop() -> void:
	FX.flash(position, ParryFX.HOT, 0.9, 0.08)
	FX.sparks(position, 12, [Color.WHITE, ParryFX.GOLD], 6.0, 0.3, -8.0, 0.07)
	FX.shockwave(position, ParryFX.GOLD, 1.6, 0.22, 0.05)
	queue_free()


# ── 패링 인터페이스 ─────────────────────────────────────

func parry_eta() -> float:
	if reflected:
		return INF
	var p := Main.inst.player
	if not p.alive:
		return INF
	var rel := p.global_position - position
	rel.y = 0
	var fwd := Vector3(vel.x, 0, vel.z).normalized()
	var along := rel.dot(fwd)
	var lateral := (rel - fwd * along).length()
	if lateral > p.hit_radius + RADIUS + 0.7 or along < -0.6:
		return INF
	return (along - (p.hit_radius + RADIUS)) / SPEED


func parry_kind() -> String:
	return "ranged"


func parry_point() -> Vector3:
	return position


func parry_source() -> Node3D:
	return source if is_instance_valid(source) and source.alive else self


func parry_window_open() -> void:
	_cued = true
	ParryFX.cue(position)


## 되받아치기: 쏜 적(없으면 가까운 적)에게 고속으로 되돌아간다
func parry_hit(p: Player) -> void:
	reflected = true
	life = 2.5
	Parry.inst.unregister(self)
	remove_from_group("parry_orbs")
	var target := _target()
	var d: Vector3
	if target:
		d = target.global_position - position
	else:
		d = position - p.global_position
	d.y = 0
	vel = d.normalized() * REFLECT_SPEED
	position = p.global_position + Vector3(0, 0.95, 0) + d.normalized() * 0.9
	shell.set_instance_shader_parameter("tint", ParryFX.HOT)
	core.set_instance_shader_parameter("tint", Color.WHITE)
	core.set_instance_shader_parameter("energy", 4.5)


func _target() -> Enemy:
	if is_instance_valid(source) and source.alive and source.landed:
		return source
	var best: Enemy = null
	var bd := 18.0
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var l := en.global_position.distance_to(position)
		if l < bd:
			bd = l
			best = en
	return best


func _steer_to_target(dt: float) -> void:
	var target := _target()
	if target == null:
		return
	var to := target.global_position - position
	to.y = 0
	var cur := Vector3(vel.x, 0, vel.z).normalized()
	var ang := cur.signed_angle_to(to.normalized(), Vector3.UP)
	vel = cur.rotated(Vector3.UP, clampf(ang, -REFLECT_HOMING * dt, REFLECT_HOMING * dt)) * REFLECT_SPEED


func _check_enemy_hit() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var rel := Vector3(en.global_position.x - position.x, 0, en.global_position.z - position.z)
		if rel.length() < en.radius + RADIUS + 0.25:
			var dir := vel.normalized()
			var at := Vector3(en.global_position.x, 0.95, en.global_position.z)
			en.take_hit(REFLECT_DMG, dir, at, "parry")
			ParryFX.glint(at, 5.0, ParryFX.GOLD, 0.35)
			FX.fire_explosion(at, 1.2)
			FX.shockwave(at, ParryFX.GOLD, 5.0, 0.4, 0.1)
			FX.sparks(at, 30, [Color.WHITE, ParryFX.HOT, ParryFX.GOLD], 12.0, 0.5, -10.0, 0.08)
			Sfx.play("boom", 0.05, 2.0)
			Main.inst.shake(0.5)
			Main.inst.hitstop(0.06)
			queue_free()
			return
