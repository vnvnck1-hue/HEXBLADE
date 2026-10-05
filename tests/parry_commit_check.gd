extends SceneTree
## Run with: Godot --headless --path . -s tests/parry_commit_check.gd
## 패링 공격 규칙을 확인한다.
##  1. 패링 공격 별빛은 위험 섬광(패링 불가)의 절반 크기다.
##  2. 패링 공격 준비동작에 들어간 적은 맞아도 피격 경직·넉백 없이 공격을 끝까지 해낸다 (드론 패링 탄 · 요격기 돌진 베기).
##     패링 공격 중이 아닐 때 맞으면 예전처럼 경직된다.
##  3. 준비동작 동안 몸 전체에 흰 발광(Pal.parry_charge)이 덮이고, 공격이 나가면 걷힌다.

var fails := 0
var main: Main
var player: Player


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _clear_enemies() -> void:
	for e in get_nodes_in_group("enemies"):
		e.queue_free()
	for o in get_nodes_in_group("parry_orbs"):
		o.queue_free()
	await _frames(2)


func _overlay(e: Enemy) -> Material:
	for mi: MeshInstance3D in FX.mesh_parts(e.j.body as Node3D):
		return mi.material_overlay
	return null


func _place(e: Enemy, off: Vector3) -> void:
	main.world.add_child(e)
	e.global_position = player.global_position + off
	e.global_position.y = Main.gy(e.global_position)
	e.hp = 99999
	e.landed = true
	(e.j.body as Node3D).position.y = 1.0


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	player = main.player
	player.hp = 999
	await _clear_enemies()

	# 1. 별빛 크기
	var star := ParryFX.warn(player.global_position + Vector3(0, 1, 0), "melee")
	var danger := ParryFX.warn(player.global_position + Vector3(0, 1, 0), "danger")
	_check(is_equal_approx(star.scale.x, ParryFX.DANGER_STAR_SIZE * 0.5), "parry star is half the danger star (%.1f)" % star.scale.x)
	_check(is_equal_approx(danger.scale.x, ParryFX.DANGER_STAR_SIZE), "danger star size unchanged (%.1f)" % danger.scale.x)

	# 2-a. 드론: 패링 탄 준비동작 중 맞아도 끊기지 않고 발사한다
	var d := Enemy.new()
	d.orb_only = true
	_place(d, Vector3(6, 0, 0))
	d.fire_timer = Enemy.ORB_WINDUP + 0.05
	await _frames(12)
	_check(d.orb_next and d.windup_k > 0.0, "drone entered orb windup")
	_check(d.parry_committed(), "drone windup counts as committed")
	_check(d.charge_on and _overlay(d) == Pal.parry_charge(), "drone glows white during windup")
	for i in 3:
		d.take_hit(1, Vector3(1, 0, 0), d.global_position)
		await _frames(3)
	_check(d.hurt_t == 0.0, "drone not staggered by hits during windup")
	_check(d.knock.length() < 0.01, "drone not knocked back during windup")
	_check(d.orb_next, "drone still winding up after hits")
	var fired := false
	for i in 90:
		await physics_frame
		if get_nodes_in_group("parry_orbs").size() > 0:
			fired = true
			break
	_check(fired, "drone fired the parry orb after being hit")
	await _frames(3)
	_check(not d.charge_on, "drone white glow cleared after firing")
	# 패링 공격 중이 아니면 예전처럼 경직된다
	d.fire_timer = 3.0
	d.take_hit(1, Vector3(1, 0, 0), d.global_position)
	_check(d.hurt_t > 0.0, "drone still staggers when not attacking")
	d.queue_free()
	await _clear_enemies()

	# 2-b. 요격기: 돌진 베기 준비동작 중 맞아도 돌진까지 간다
	var s := Striker.new()
	s.lunge_only = true
	_place(s, Vector3(0, 0, 5))
	await _frames(2)
	var dir := (player.global_position - s.global_position)
	dir.y = 0
	s._begin_lunge(dir.normalized())
	await _frames(6)
	_check(s.parry_committed(), "striker lunge windup counts as committed")
	_check(s.charge_on and _overlay(s) == Pal.parry_charge(), "striker glows white during windup")
	for i in 4:
		s.take_hit(1, -dir.normalized(), s.global_position)
		await _frames(4)
	_check(s.hurt_t == 0.0, "striker not staggered by hits during windup")
	var lunged := false
	for i in 120:
		await physics_frame
		if s.state == Striker.S.LUNGE:
			lunged = true
			break
	_check(lunged, "striker launched the lunge after being hit")
	_check(not s.charge_on, "striker white glow cleared on launch")
	s.take_hit(1, -dir.normalized(), s.global_position)
	_check(s.hurt_t == 0.0, "striker not staggered mid-lunge")
	s.queue_free()
	await _frames(2)

	print("RESULT parry_commit_check fails=%d" % fails)
	quit(1 if fails > 0 else 0)
