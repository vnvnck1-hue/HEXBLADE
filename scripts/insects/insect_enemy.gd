class_name InsectEnemy
extends Enemy
## Ground insects, same Enemy hit/lock/parry/kill contract as the other enemies.
## Ant: quick chase + telegraphed bite dash. Grub: slow inching + body lunge.

enum Kind { ANT, GRUB }
enum Act { CHASE, WINDUP, ATTACK, RECOVER }
const ANT_MODEL := preload("res://assets/models/insect_ant.glb")
const GRUB_MODEL := preload("res://assets/models/insect_grub.glb")
@export var kind: Kind = Kind.ANT
var motion := InsectMotion.new()
var asset: Node3D
var act := Act.CHASE
var act_t := 0.0
var cooldown := 1.0
var attack_dir := Vector3.FORWARD
var bite_done := false
var passive := false
var log_actions := false
var preview_mode := ""
var preview_k := 0.0
var _prev_pos := Vector3.ZERO
var attack_count := 0
var mouth_point: Node3D
var _target_has_hidden := false


func _ready() -> void:
	for prop in Main.inst.player.get_property_list():
		if prop.name == "hidden":
			_target_has_hidden = true
	add_to_group("enemies")
	visual = Node3D.new()
	add_child(visual)
	asset = (ANT_MODEL if kind == Kind.ANT else GRUB_MODEL).instantiate() as Node3D
	asset.scale = Vector3.ONE * (0.78 if kind == Kind.ANT else 0.90)
	visual.add_child(asset)
	motion.setup(self, asset, kind == Kind.ANT)
	mouth_point = asset.find_child("pt_mouth",true,false) as Node3D
	j = {"body": motion.body}
	hp = 4 if kind == Kind.ANT else 8
	radius = 0.56 if kind == Kind.ANT else 0.76
	hp_bar_y = 2.1 if kind == Kind.ANT else 1.65
	hp_bar_w = 1.15 if kind == Kind.ANT else 1.35
	slice_color = Color("b44a27") if kind == Kind.ANT else Color("ead6af")
	slice_size = Vector3(0.8, 1.3, 1.7) if kind == Kind.ANT else Vector3(1.2, 0.95, 2.2)
	shadow = FX.blob_shadow(self, 1.8 if kind == Kind.ANT else 2.5, 0.45)
	evade.e = self
	evade.chance = 0.0
	cooldown = randf_range(0.8, 1.5)
	_prev_pos = global_position


func _physics_process(dt: float) -> void:
	if not preview_mode.is_empty():
		motion.pose(preview_mode, preview_k, 3.6 if kind == Kind.ANT else 1.5, dt)
		return
	if dying:
		_update_death(dt)
		return
	if not alive:
		return
	if max_hp == 0:
		_init_hp()
	t += dt
	_update_hp_bar(dt)
	if not landed:
		drop_t += dt
		motion.pose("emerge", drop_t / 0.65, 0.0, dt)
		global_position.y = Main.gy(global_position)
		if drop_t >= 0.65:
			landed = true
			motion.reset_feet()
			FX.land_dust(global_position)
		return
	var mode_name := "idle"
	var progress := 0.0
	if stagger_t > 0.0:
		stagger_t = maxf(0.0, stagger_t-dt)
		mode_name = "stagger"
		progress = 1.0-stagger_t/maxf(stagger_total,0.01)
		_move(knock,dt)
		if stagger_t <= 0.0 and is_instance_valid(stun_halo):
			stun_halo.queue_free()
	elif hurt_t > 0.0:
		hurt_t = maxf(0.0, hurt_t-dt)
		hurt_age += dt
		mode_name = "hurt"
		progress = hurt_age / HURT_TIME
		_move(knock,dt)
	else:
		_ai(dt)
		match act:
			Act.CHASE: mode_name = "walk" if not passive and Main.inst.player.alive and not _target_hidden() else "idle"
			Act.WINDUP:
				mode_name = "windup"
				progress = act_t / _wind_time()
			Act.ATTACK:
				mode_name = "attack"
				progress = act_t / _attack_time()
			Act.RECOVER:
				mode_name = "recover"
				progress = act_t / 0.65
	knock = knock.move_toward(Vector3.ZERO, 22.0*dt)
	var distance := Vector2(global_position.x-_prev_pos.x,global_position.z-_prev_pos.z).length()
	var speed := distance/maxf(dt,0.001)
	_prev_pos = global_position
	motion.pose(mode_name, progress, speed, dt)
	flash_t = maxf(0.0,flash_t-dt)
	glow_t = maxf(0.0,glow_t-dt)
	_set_flash(flash_t > 0.0)


func _wind_time() -> float:
	return 0.58 if kind == Kind.ANT else 0.85


func _attack_time() -> float:
	return 0.28 if kind == Kind.ANT else 0.42


func _go(next: Act) -> void:
	act = next
	act_t = 0.0
	if log_actions:
		print("INSECT %s %s t=%.2f" % ["ANT" if kind == Kind.ANT else "GRUB", Act.keys()[act], t])


func _ai(dt: float) -> void:
	var p := Main.inst.player
	var d := p.global_position-global_position
	d.y = 0.0
	var distance := d.length()
	var dir := d.normalized() if distance > 0.001 else -global_basis.z
	var active := p.alive and not _target_hidden() and Main.inst.state == Main.State.PLAY and not passive
	# No new attack / continuing lunge when the target dies or becomes hidden.
	if not active:
		if act != Act.CHASE:
			_cancel_attack()
		_move(knock,dt)
		return
	act_t += dt
	cooldown -= dt
	match act:
		Act.CHASE:
			rotation.y = lerp_angle(rotation.y,atan2(-dir.x,-dir.z),1.0-exp(-8.0*dt))
			var move := dir * (3.6 if kind == Kind.ANT else 1.45)
			for o in get_tree().get_nodes_in_group("enemies"):
				if not is_instance_valid(o) or o == self:
					continue
				var separation: Vector3 = global_position-o.global_position
				separation.y = 0.0
				var l := separation.length()
				if l > 0.01 and l < radius+o.radius+0.25:
					move += separation/l * 2.1
			_move(move+knock,dt)
			if cooldown <= 0.0 and distance < (3.2 if kind == Kind.ANT else 2.5):
				attack_dir = dir
				_go(Act.WINDUP)
				warn_glow = true
				if is_instance_valid(Parry.inst):
					Parry.inst.register(self)
				ParryFX.warn(mouth_point.global_position,"melee")
				Sfx.play("pcue",0.12,-13.0)
		Act.WINDUP:
			_move(knock,dt)
			# Direction committed after the first half; sidestepping remains useful.
			if act_t < _wind_time()*0.5:
				attack_dir = dir
				rotation.y = atan2(-dir.x,-dir.z)
			if act_t >= _wind_time():
				bite_done = false
				attack_count += 1
				_go(Act.ATTACK)
				parry_flash()
		Act.ATTACK:
			var speed := 9.0 if kind == Kind.ANT else 5.5
			_move(attack_dir * speed + knock,dt)
			var mouth := mouth_point.global_position
			var flat := Vector2(mouth.x-p.global_position.x,mouth.z-p.global_position.z).length()
			if not bite_done and flat < p.hit_radius+0.52 and absf(p.global_position.y-global_position.y) < 1.05:
				bite_done = true
				p.take_hit(mouth)
			if act_t >= _attack_time():
				if is_instance_valid(Parry.inst):
					Parry.inst.unregister(self)
				_end_warn()
				_go(Act.RECOVER)
		Act.RECOVER:
			_move(knock,dt)
			if act_t >= 0.65:
				cooldown = 0.9 if kind == Kind.ANT else 1.4
				_go(Act.CHASE)


func _move(velocity_in: Vector3, dt: float) -> void:
	# Use the terrain step barrier so ground insects cannot drift through tall ledges.
	var pos := Main.inst.push_out_feet(global_position+velocity_in*dt,radius,global_position.y,0.5)
	pos.y = Main.gy(pos)
	global_position = pos


func _target_hidden() -> bool:
	var p := Main.inst.player
	return bool(p.get("hidden")) if _target_has_hidden else bool(p.get_meta("insect_hidden",false))


func _cancel_attack() -> void:
	if is_instance_valid(Parry.inst):
		Parry.inst.unregister(self)
	_end_warn()
	_go(Act.RECOVER)
	cooldown = 0.8


func _interrupt() -> void:
	_cancel_attack()


func _on_stagger() -> void:
	_cancel_attack()


func stagger(dir: Vector3, duration: float) -> void:
	# Keep Enemy's doubled-damage stagger contract with our grounded pose.
	if not alive:
		return
	stagger_t = duration
	stagger_total = duration
	knock = Vector3(dir.x,0,dir.z).normalized()*9.0
	_cancel_attack()
	flash_t = 0.1
	if not is_instance_valid(stun_halo):
		stun_halo = ParryFX.stun_halo(visual)
		stun_halo.position.y = hp_bar_y-0.2
	Sfx.play("clank",0.08,-6.0)


func die(dir := Vector3.ZERO, source := "bullet") -> void:
	if not alive:
		return
	alive = false
	dying = true
	death_t = 0.0
	kill_source = source
	death_dir = Vector3(dir.x,0,dir.z).normalized()
	if is_instance_valid(Parry.inst):
		Parry.inst.unregister(self)
	remove_from_group("enemies")
	locked = false
	warn_glow = false
	glow_t = 0.0
	flash_t = 0.0
	_set_flash(false)
	if is_instance_valid(hp_bar):
		hp_bar.queue_free()
	if is_instance_valid(lock_marker):
		lock_marker.queue_free()
	if is_instance_valid(stun_halo):
		stun_halo.queue_free()
	Main.inst.on_enemy_killed(self)
	Sfx.play("hit",0.12,-7.0)


func _update_death(dt: float) -> void:
	death_t += dt
	motion.pose("death",death_t/1.15,0.0,dt)
	if death_t >= 1.15:
		# Organic crumple, then shrink away; no mechanical explosion.
		visual.scale = Vector3.ONE * maxf(0.0,1.0-(death_t-1.15)/0.35)
	if death_t >= 1.5:
		queue_free()


func _exit_tree() -> void:
	if is_instance_valid(Parry.inst):
		Parry.inst.unregister(self)


func parry_eta() -> float:
	if not alive or not is_instance_valid(Main.inst) or act not in [Act.WINDUP, Act.ATTACK]:
		return INF
	var p := Main.inst.player
	if not p.alive or _target_hidden() or absf(p.global_position.y-global_position.y) > 1.05:
		return INF
	var mouth := mouth_point.global_position
	var d := p.global_position-mouth
	d.y = 0.0
	var along := d.dot(attack_dir)
	var lateral := (d-attack_dir*along).length()
	if lateral > p.hit_radius+0.6:
		return INF
	var travel := (along-p.hit_radius-0.52)/(9.0 if kind == Kind.ANT else 5.5)
	if act == Act.WINDUP:
		return maxf(0.0,_wind_time()-act_t)+maxf(0.0,travel)
	return travel


func parry_kind() -> String:
	return "melee"


func parry_point() -> Vector3:
	return mouth_point.global_position


func parry_source() -> Node3D:
	return self


func parry_window_open() -> void:
	parry_flash()


func parry_hit(p: Player) -> void:
	stagger(global_position-p.global_position,1.4)
