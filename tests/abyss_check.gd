extends SceneTree
## Run with: Godot --headless --path . -s tests/abyss_check.gd
## LAYER 01 심연 성소 확인:
##  1. 판 배치 7종이 15×15 이고, 걸을 수 있는 판이 한 덩어리로 이어지며, 가장자리 등장 자리가 있다
##  2. push_out 은 어떤 점이든 걸을 수 있는 판 위로 돌려놓는다
##  3. 장면을 띄워 적을 계속 처치하면 페이즈 1~4 가 차례로 정리되고, 판 배치가 바뀌며, 중간보스가 나온다
##  4. 보스 체력 50% 에서 2페이즈(십자 배치)로 바뀌고, 쓰러뜨리면 레이어 클리어(WIN)
##  5. 갑각 참회자의 정면 갑각은 탄을 튕긴다 · 파열이 주변 허스크를 함께 터뜨린다

const Stage := preload("res://scripts/abyss/abyss_stage.gd")
const Husk := preload("res://scripts/abyss/husk.gd")
const Penitent := preload("res://scripts/abyss/penitent.gd")
const Warden := preload("res://scripts/abyss/warden.gd")

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _kill_all(main: Node) -> void:
	for e in main.get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en.alive and en.landed and en.is_inside_tree() and not en.is_boss:
			en.take_hit(9999, Vector3.FORWARD, en.global_position, "bullet")


func _run() -> void:
	# ── 1. 판 배치 ──
	for name in Stage.LAYOUTS:
		var rows: Array = Stage.LAYOUTS[name]
		var ok_shape := rows.size() == Stage.N
		for r in rows:
			ok_shape = ok_shape and (r as String).length() == Stage.N
		var walk := {}
		for j in Stage.N:
			for i in Stage.N:
				var ch := (rows[j] as String)[i]
				if ch == "#" or ch == "v":
					walk[Vector2i(i, j)] = true
		# 한 덩어리로 이어지는가 (넘쳐 채우기)
		var seen := {}
		var stack: Array = [walk.keys()[0]]
		while not stack.is_empty():
			var c: Vector2i = stack.pop_back()
			if seen.has(c) or not walk.has(c):
				continue
			seen[c] = true
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				stack.append(c + d)
		_check(ok_shape and seen.size() == walk.size(), "배치 %s: 15×15 · 바닥 %d칸이 한 덩어리" % [name, walk.size()])

	# ── 2~3. 장면 ──
	var scene: PackedScene = load("res://scenes/abyss.tscn")
	var main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(20)
	var player: Player = main.player
	var stage: Stage = main.stage
	_check(stage.layout == "descent" and stage.on_floor(player.global_position), "시작: 강림 배치 · 플레이어가 바닥 위")
	_check(stage.edge_spots().size() > 8, "가장자리 등장 자리 %d곳" % stage.edge_spots().size())
	var far := stage.push_out(Vector3(40, 0, -33), 0.4)
	_check(stage.on_floor(far), "push_out: 먼 점도 바닥 위로 돌아온다 → (%.1f, %.1f)" % [far.x, far.z])

	# 참회자 정면 갑각: 앞에서 쏜 탄을 튕긴다
	await _frames(100)
	var pen: Enemy = Penitent.new()
	pen.position = Vector3(0, 0, -4)
	main.world.add_child(pen)
	await _frames(45)
	pen.rotation.y = 0.0                         # 정면(-Z)이 북쪽
	var b := Bullet.new()
	b.vel = Vector3(0, 0, 30.0)
	_check(pen.landed and pen.call("deflect_bullet", b, Vector3(0, 0.95, -5), Vector3(0, 0, 1)), "참회자: 정면에서 온 탄을 튕긴다")
	_check(not pen.call("deflect_bullet", b, Vector3(0, 0.95, -3), Vector3(0, 0, -1)), "참회자: 등 뒤에서 온 탄은 맞는다")
	b.free()
	# 파열이 주변 허스크를 함께 터뜨린다
	var hk: Enemy = Husk.new()
	hk.position = pen.global_position + Vector3(1.5, 0, 0)
	main.world.add_child(hk)
	await _frames(5)
	pen.take_hit(9999, Vector3.FORWARD, pen.global_position, "bullet")
	await _frames(70)
	_check(not is_instance_valid(hk) or not hk.alive, "참회자 파열: 옆 허스크도 터진다")

	var seen_layouts := {}
	var guard := 0
	while main.phase_state != "boss" and guard < 60 * 240:
		guard += 1
		player.hp = Player.MAX_HP
		player.invuln = 9999.0
		seen_layouts[stage.layout] = true
		if guard % 6 == 0:
			_kill_all(main)
		await physics_frame
	_check(main.phase_state == "boss" and main.phase == 4, "페이즈 1~4 를 정리하면 보스 페이즈 (phase=%d, %.0f초)" % [main.phase, main.time])
	_check(seen_layouts.has("descent") and seen_layouts.has("wings") and seen_layouts.has("ring") and seen_layouts.has("colonnade"), "판 배치가 바뀌었다 %s" % [seen_layouts.keys()])
	_check(is_instance_valid(main.boss), "후광의 파수자 등장")

	# ── 4. 보스 ──
	var boss: Warden = main.boss
	var saw_p2 := false
	guard = 0
	while main.state == Main.State.PLAY and guard < 60 * 200:
		guard += 1
		player.hp = Player.MAX_HP
		player.invuln = 9999.0
		if boss.st == Warden.St.FIGHT and guard % 3 == 0:
			boss.take_hit(20, Vector3.FORWARD, boss.global_position, "bullet")
		if boss.phase == 2 and stage.layout == "cross":
			saw_p2 = true
		if guard % 10 == 0:
			_kill_all(main)
		await physics_frame
	_check(saw_p2, "보스 50%: 2페이즈 · 십자 배치")
	_check(main.state == Main.State.WIN, "보스 격파 → 레이어 클리어 (%.0f초)" % main.time)
	await _frames(30)
	print("RESULT %s (%d fail)" % ["OK" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
