class_name RogueFamiliar
extends Node3D
## 패밀리어(따라다니는 동료):
##  shield  궤도 방패 — 몸 둘레를 돌며 적 탄을 지우고 닿은 적에게 피해
##  fly     파리 — 작은 궤도, 적 탄 흡수
##  turret  꼬마 포탑 — 뒤를 따라오며 가까운 적에게 탄
##  hunter  사냥 파리 — 적을 쫓아가 물어뜯는다 (poison 이면 중독)
##  sat     레이저 위성 — 넓은 궤도, 가까운 적에게 레이저
##  minion  부하 드론 — 일시 소환, 적 둘레를 돌며 쏜다

static var _ball: SphereMesh
static var _box: BoxMesh

var kind := "shield"
var build: RogueBuild
var slot := 0.0              # 같은 종류 안에서의 위상 (0~1)
var temp := 0.0              # > 0 이면 일시 소환 (남은 초)
var poison := false
var t := 0.0
var cd := 0.0
var vel := Vector3.ZERO
var body: MeshInstance3D


static func make(k: String, b: RogueBuild) -> RogueFamiliar:
	var fm := RogueFamiliar.new()
	fm.kind = k
	fm.build = b
	return fm


func _ready() -> void:
	if _ball == null:
		_ball = SphereMesh.new()
		_ball.radius = 0.5
		_ball.height = 1.0
		_ball.radial_segments = 10
		_ball.rings = 5
		_box = BoxMesh.new()
	add_to_group("rogue_familiars")
	match kind:
		"shield":
			body = Pal.flat_mesh(_box, Color("a0e0ff"), 1.8)
			body.scale = Vector3(0.45, 0.45, 0.45)
		"fly":
			body = Pal.flat_mesh(_ball, Color("3a3a2a"), 1.0)
			body.scale = Vector3.ONE * 0.28
			var wing := Pal.flat_mesh(_box, Color("e0e8ff"), 1.6)
			wing.scale = Vector3(2.4, 0.15, 0.7)
			wing.position.y = 0.4
			body.add_child(wing)
		"turret", "minion":
			body = Pal.flat_mesh(_box, Color("ffd060") if kind == "turret" else Color("ff9ad0"), 1.4)
			body.scale = Vector3(0.5, 0.4, 0.5)
			var barrel := Pal.flat_mesh(_box, Color("404050"), 1.0)
			barrel.scale = Vector3(0.3, 0.3, 1.2)
			barrel.position = Vector3(0, 0.1, -0.6)
			body.add_child(barrel)
		"hunter":
			body = Pal.flat_mesh(_ball, Color("6a8a30") if poison else Color("5a3020"), 1.2)
			body.scale = Vector3.ONE * 0.36
		"sat":
			body = Pal.flat_mesh(_ball, Color("60f0ff"), 2.0)
			body.scale = Vector3.ONE * 0.4
	add_child(body)


func _physics_process(dt: float) -> void:
	t += dt
	cd -= dt
	if temp > 0.0:
		temp -= dt
		if temp <= 0.0:
			FX.flash(global_position, Color.WHITE, 0.4, 0.08)
			queue_free()
			return
	if not is_instance_valid(build) or not is_instance_valid(build.player):
		return
	var p := build.player
	var c := p.global_position + Vector3(0, 1.0, 0)
	match kind:
		"shield", "fly", "sat":
			var r: float = {"shield": 1.5, "fly": 1.05, "sat": 2.4}[kind]
			var w: float = {"shield": 2.6, "fly": 4.0, "sat": 1.2}[kind]
			var a: float = t * w + slot * TAU
			global_position = c + Vector3(cos(a) * r, sin(t * 6.0) * 0.12, sin(a) * r)
			body.rotate_y(dt * 4.0)
			if kind != "sat":
				_block_bullets(0.55 if kind == "shield" else 0.4)
				_contact(0.7, build.cur_dmg() * (0.8 if kind == "shield" else 0.4), 0.3)
			elif cd <= 0.0:
				var e := _nearest(9.0)
				if e:
					cd = 1.1
					var o := global_position
					RogueEffects.beam(build, o, (e.global_position - o) * Vector3(1, 0, 1), 10.0, 0.2, build.cur_dmg() * 0.9, RogueEffects.C_SHOCK)
		"turret":
			var behind := c - p.aim_dir * 1.3 + Vector3(-p.aim_dir.z, 0, p.aim_dir.x) * (slot - 0.25) * 2.0
			global_position = global_position.lerp(behind, minf(1.0, dt * 5.0))
			var e := _nearest(10.0)
			if e:
				look_at(Vector3(e.global_position.x, global_position.y, e.global_position.z), Vector3.UP)
				if cd <= 0.0:
					cd = 0.55
					RogueEffects.bullet(build, global_position, -global_basis.z, build.cur_dmg() * 0.55, {"plain": true, "size_k": 0.7})
		"minion":
			var e := _nearest(14.0)
			var goal := c + Vector3(cos(t + slot * TAU), 0, sin(t + slot * TAU)) * 2.0
			if e:
				goal = e.global_position + Vector3(0, 1.4, 0) + Vector3(cos(t * 2.0 + slot * TAU), 0, sin(t * 2.0 + slot * TAU)) * 3.0
				look_at(Vector3(e.global_position.x, global_position.y, e.global_position.z), Vector3.UP)
				if cd <= 0.0:
					cd = 0.4
					RogueEffects.bullet(build, global_position, -global_basis.z, build.cur_dmg() * 0.6, {"plain": true, "size_k": 0.7})
			global_position = global_position.lerp(goal, minf(1.0, dt * 3.0))
		"hunter":
			var e := _nearest(12.0)
			var goal := c + Vector3(cos(t * 3.0 + slot * TAU), 0, sin(t * 3.0 + slot * TAU)) * 1.4
			if e:
				goal = e.global_position + Vector3(0, 0.9, 0)
			var to := goal - global_position
			vel = vel.move_toward(to.normalized() * 9.0, 40.0 * dt)
			global_position += vel * dt
			global_position.y = lerpf(global_position.y, goal.y + sin(t * 20.0) * 0.1, minf(1.0, dt * 8.0))
			_contact(0.6, build.cur_dmg() * 0.5, 0.25)


func _nearest(r: float) -> Enemy:
	var best: Enemy = null
	var bd := r
	for e in Enemy.live(get_tree()):
		var en := e as Enemy
		if not en.alive or not en.landed or en.prop:
			continue
		var d := en.global_position.distance_to(global_position)
		if d < bd:
			bd = d
			best = en
	return best


func _block_bullets(r: float) -> void:
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Node3D
		if Vector2(bl.global_position.x - global_position.x, bl.global_position.z - global_position.z).length() < r:
			FX.flash(bl.global_position, Color("c0f0ff"), 0.35, 0.06)
			bl.queue_free()


func _contact(r: float, dmg: float, every: float) -> void:
	if cd > 0.0:
		return
	for e in Enemy.live(get_tree()):
		var en := e as Enemy
		if not en.alive or not en.landed or en.prop:
			continue
		if Vector2(en.global_position.x - global_position.x, en.global_position.z - global_position.z).length() < r + en.radius:
			cd = every
			build.deal(en, dmg, (en.global_position - global_position).normalized(), global_position, 0.2)
			if poison:
				build.apply_status(en, "poison", 3.0)
			return
