extends SceneTree
## Run with: Godot --headless --path . -s tests/training_ui_toggle_check.gd
## 허수아비 시험장 UI 숨김 키:
##  F1 = 왼쪽 설명(설정 패널 · 하단 조작 안내)만 숨김 ↔ 보임, HUD 나머지는 그대로
##  F2 = 모든 UI 숨김 ↔ 보임 (HUD 층 · 피해 숫자 층 · 드론 말풍선 · 적 머리 위 체력바), 씬을 나가면 풀림

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _key(m: Node, k: Key) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = true
	m.get_viewport().push_input(e)
	await process_frame
	var u := e.duplicate() as InputEventKey
	u.pressed = false
	m.get_viewport().push_input(u)
	await process_frame
	await process_frame


func _run() -> void:
	var m: TrainingMain = load("res://scenes/training.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	for i in 30:
		await physics_frame
	# 피해 숫자 층이 생기게 한 번 때린다
	var dm: TrainingDummy = m.dummies[0]
	dm.take_hit(1, Vector3.ZERO, dm.global_position + Vector3(0, 1, 0), "slash")
	await process_frame
	await process_frame
	_check(m.panel.visible and m.hud.hint.visible and m.hud.visible, "처음엔 설명 · HUD 모두 보임")

	await _key(m, KEY_F1)
	_check(not m.panel.visible and not m.hud.hint.visible, "F1: 왼쪽 설정 패널 · 조작 안내 숨김")
	_check(m.hud.visible, "F1: HUD 나머지는 그대로")
	await _key(m, KEY_F1)
	_check(m.panel.visible and m.hud.hint.visible, "F1 다시: 설명 보임")

	await _key(m, KEY_F2)
	_check(Main.ui_hidden and not m.hud.visible, "F2: HUD 층 전체 숨김 (상태 · 지도 · 스킬 · 드론 패널 · 설명)")
	var nums := ToonGunFX.inst.get_node_or_null("MocoFX/MocoNumbers") as CanvasLayer if ToonGunFX.inst else null
	_check(nums == null or not nums.visible, "F2: 피해 숫자 층 숨김")
	var d := PartnerDrone.inst
	var bub := SpeechBubble.at(m.player.global_position, "끼릭!")
	_check(bub != null and not bub.is_visible_in_tree(), "F2: 말풍선 숨김")
	for i in 3:
		await physics_frame
	var bars_hidden := true
	for e in m.dummies:
		if is_instance_valid(e.hp_bar) and e.hp_bar.visible:
			bars_hidden = false
	_check(bars_hidden, "F2: 적 머리 위 체력바 숨김")
	await _key(m, KEY_F2)
	_check(not Main.ui_hidden and m.hud.visible and (nums == null or nums.visible), "F2 다시: 모든 UI 보임")
	_check(bub == null or not is_instance_valid(bub) or bub.get_parent().is_visible_in_tree(), "F2 다시: 말풍선 층 보임")

	await _key(m, KEY_F2)
	m.queue_free()
	await process_frame
	await process_frame
	_check(not Main.ui_hidden, "씬을 나가면 UI 숨김이 풀린다")
	print("RESULT: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
