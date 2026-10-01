extends SceneTree
## Run with: Godot --headless --path . -s tests/world_flow_check.gd
## 흐르는 공간(WorldFlow): 추격 보스전에서 바닥에 남는 · 공중에 떠 있는 연출이 도로를 따라 화면 아래(+Z)로 흘러간다.
##  1. 탄피: 바닥에 닿으면 흐르는 도로에 끌려가 화면 밖으로 흘러 나가 지워진다
##  2. 바닥 파편(벽·몸체 부스러기)과 잔해 조각도 같은 식으로 흘러간다
##  3. 공중 연출(연기 구체): 짧은 섬광은 거의 제자리, 오래 남는 연기는 도로 쪽으로 크게 끌려간다
##  4. 폭발의 바닥 그을음은 도로와 거의 같은 속도로 흐른다
##  5. 흐르지 않는 씬(방 탐색 main.tscn)에서는 탄피가 바닥에 그대로 남는다 (예전 동작 유지)

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		if Main.inst and is_instance_valid(Main.inst.player):
			Main.inst.player.invuln = 999.0
		await physics_frame


func _load(path: String) -> Main:
	if current_scene:
		current_scene.queue_free()
		await process_frame
	var m: Main = load(path).instantiate()
	root.add_child(m)
	current_scene = m
	await _frames(3)
	return m


func _run() -> void:
	var main := await _load("res://scenes/boss.tscn")
	_check(WorldFlow.active() and WorldFlow.road_v() > 40.0, "추격전: 흐르는 공간 켜짐 (도로 %.0f m/s)" % WorldFlow.road_v())
	var at := Vector3(0, 1.2, 3.0)

	# 1. 탄피
	GunFX.eject(at, Vector3.RIGHT, Vector3.FORWARD)
	var cas: Dictionary = GunFX.inst.casings.back()
	var node: Node3D = cas.node
	var z0 := node.global_position.z
	var max_z := z0
	for i in 90:
		await _frames(1)
		if not is_instance_valid(node) or not node.is_inside_tree():
			break
		max_z = node.global_position.z
	var removed := not is_instance_valid(node) or not node.is_inside_tree() or not GunFX.inst.casings.has(cas)
	_check(max_z - z0 > 15.0, "탄피가 바닥에 닿아 도로에 끌려 흘러간다 (%.1fm 이동)" % (max_z - z0))
	_check(removed, "화면 아래로 나간 탄피는 지워진다")

	# 2. 파편 · 잔해
	GunFX.inst._chip(at, Vector3(1, 2, 0), Color.GRAY, 1.0)
	var chip: Node3D = GunFX.inst.chips.back().node
	var cz := chip.global_position.z
	await _frames(60)
	_check(not is_instance_valid(chip) or chip.global_position.z - cz > 6.0, "바닥 파편이 흘러간다")
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	Debris.toss(box.mesh, null, Transform3D(Basis.IDENTITY, at), Vector3(0, 3, 0), 2.0)
	var piece: Node3D = Debris.inst.pieces.back().node
	var pz := piece.global_position.z
	await _frames(70)
	_check(not is_instance_valid(piece) or piece.global_position.z - pz > 4.0, "잔해 조각이 바닥에 닿아 흘러간다")
	box.free()

	# 3. 공중 연출: 섬광(짧음)과 연기(김)
	FX.flash(at, Color.WHITE, 0.6, 0.08)
	var flash_node: Node3D = WorldFlow.inst.get_child(WorldFlow.inst.get_child_count() - 1).get_child(0)
	var fz := flash_node.global_position.z
	await _frames(4)
	var flash_move := flash_node.global_position.z - fz if is_instance_valid(flash_node) else 0.0
	_check(flash_move < 0.6, "짧은 섬광은 거의 제자리 (%.2fm)" % flash_move)
	FX.smoke(at)
	var smoke: Node3D = WorldFlow.inst.get_child(WorldFlow.inst.get_child_count() - 1).get_child(0)
	var sz := smoke.global_position.z
	await _frames(24)
	var smoke_move := smoke.global_position.z - sz if is_instance_valid(smoke) else 99.0
	_check(smoke_move > 4.0, "연기는 도로 쪽으로 끌려 흘러간다 (0.4초에 %.1fm)" % smoke_move)

	# 4. 폭발 그을음
	var ex := StylizedExplosion.spawn(WorldFlow.holder(WorldFlow.AIR), Vector3(2, 1, -2), 1.0, 0.0)
	var gz := ex.scorch.global_position.z
	await _frames(30)
	var scorch_move := ex.scorch.global_position.z - gz
	var road_move := WorldFlow.road_v() * 0.5
	_check(scorch_move > road_move * 0.8, "바닥 그을음은 도로와 함께 흐른다 (%.1fm / 도로 %.1fm)" % [scorch_move, road_move])

	# 5. 흐르지 않는 씬
	main = await _load("res://scenes/main.tscn")
	_check(not WorldFlow.active() and WorldFlow.road_v() == 0.0, "방 탐색: 흐르는 공간 꺼짐")
	var p := main.player.global_position + Vector3(0, 1.2, 0)
	GunFX.eject(p, Vector3.RIGHT, Vector3.FORWARD)
	var c2: Dictionary = GunFX.inst.casings.back()
	await _frames(120)
	var n2: Node3D = c2.node
	_check(is_instance_valid(n2) and c2.rest and absf(n2.global_position.z - p.z) < 2.0, "방 탐색에서는 탄피가 바닥에 그대로 남는다")

	print("RESULT world_flow_check fails=%d" % fails)
	quit(1 if fails > 0 else 0)
