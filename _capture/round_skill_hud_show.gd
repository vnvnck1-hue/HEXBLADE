extends SceneTree
## 현재 개발 배경 위에서 실제 장비 HUD와 여러 상태를 캡처한다.
const OUT := "res://output/round-skill-hud-20261004/"

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _shot(name_: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT + name_ + ".png")

func _run() -> void:
	HudPresets.current = HudPresets.STRIKER
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(120)
	var main := current_scene as Main
	main.player.invuln = 9999.0
	main.player.aim_point = main.player.global_position + Vector3(3, 0, -2)
	main.player.process_mode = Node.PROCESS_MODE_DISABLED
	for e in get_nodes_in_group("enemies"):
		e.process_mode = Node.PROCESS_MODE_DISABLED
	main.hud.hint.modulate.a = 0.0
	main.player.mag = 26
	main.player.missiles = 4
	await _shot("applied")
	main.player.mag = 0
	main.player.reload_t = Player.RELOAD_TIME * 0.5
	main.player.dash_cd = Player.DASH_CD * 0.65
	main.player.overheated = true
	main.player.boost = 0.18
	main.player.energy = 0
	main.player.missiles = 0
	await _shot("reloading_cooldown")
	main.player.reload_t = 0.0
	main.player.mag = 3
	main.player.overheated = false
	main.player.energy = 2
	main.player.charging = true
	main.player.charge = 0.65
	main.player.charge_stage = 1
	main.player.missiles = 0
	main.player.ult_queue = 4
	await _shot("charging_queue")
	print("ROUND_SKILL_HUD_CAPTURE_OK")
	quit()
