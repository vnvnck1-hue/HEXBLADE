extends SceneTree
## 로그 모드 장면별 캡처 (화면 있음): 시작 방 HUD · 상점 · 아이템방 · 결합 공격 전투 · Tab 패널 · 변신 · 보스
## 실행: tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/rogue_show.gd
## 결과: output/rogue-20261012/shots/*.png

const OUT := "res://output/rogue-20261012/shots/"
var main: RogueMain


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		if is_instance_valid(main) and is_instance_valid(main.player):
			main.player.invuln = 999.0
		await process_frame


func _shot(name: String) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("SHOT " + name)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	PlayerEntrance.enabled = false
	RogueRun.started = false
	RogueRun.new_run(20261012)
	for id in ["twin", "homing", "ipecac", "orb_shield", "buddy"]:
		RogueRun.items.append(id)
		RogueRun.seen[id] = true
	RogueRun.active_item = "a_hole"
	RogueRun.charge = 4
	RogueRun.coins = 23
	RogueRun.bombs = 3
	RogueRun.keys = 2
	RogueRun.soul = 3
	RogueRun.pocket = {"kind": "card", "id": "sun"}
	RogueRun.trinket = "t_foot"
	main = load("res://scenes/rogue.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(40)
	await _shot("01_start")
	# 상점
	var shop: int = main.rmap.rooms_of_kind("shop")[0]
	main.rmap.rooms[shop].locked = false
	main.rmap.open_gates(shop)
	main._teleport(main.rmap.room_center(shop) + Vector3(0, 0, 2.5))
	await _frames(50)
	await _shot("02_shop")
	# 아이템방
	var tre: int = main.rmap.rooms_of_kind("treasure")[0]
	main._teleport(main.rmap.room_center(tre) + Vector3(0, 0, 3.0))
	await _frames(50)
	await _shot("03_treasure")
	# 전투방: 결합 공격 '유도 폭뢰' 로 자동 전투
	var normal := -1
	for r in main.rmap.rooms:
		if r.kind == "normal":
			normal = r.id
			break
	main.player.bot = true
	main._teleport(main.rmap.room_center(normal))
	await _frames(150)
	await _shot("04_combat_missile_synergy")
	await _frames(40)
	await _shot("05_combat_b")
	# 변신 (천사) + 패널
	for id in ["mantle", "grail", "wings", "sword_wave", "long_blade", "whetstone"]:
		RogueRun.items.append(id)
	main.build.recompute()
	await _frames(120)
	await _shot("06_transform_angel_blade")
	main.rhud.info_open = true
	await _frames(5)
	await _shot("07_info_panel")
	main.rhud.info_open = false
	# 보스
	main._teleport(main.rmap.room_center(main.rmap.boss_room) + Vector3(0, 0, 4.0))
	await _frames(200)
	await _shot("08_boss")
	await _frames(120)
	await _shot("09_boss_b")
	quit()
