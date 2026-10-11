extends SceneTree
## 전체 대화 캐스트/표정의 실제 아이들링, 남주 제외, 교차 전환/반전/M키/유한 캐시.
var fails := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		fails += 1

func _run() -> void:
	root.size = Vector2i(1280, 800)
	await process_frame
	var unique_paths := {}
	var motions := {}
	for id in DialogueCast.CAST:
		if id == "me":
			continue
		_check(DialogueIdleMotion.supports(id), id + " 아이들링 등록")
		var p := DialoguePortrait.new()
		p.setup(id, "left", "", Vector2(1280, 800))
		root.add_child(p)
		p.set_process(false)
		p.paired = true
		p.solo_bottom = 224.0
		p.active = true
		p._x = p._target_x()
		p._alpha = 1.0
		p._light = 1.0
		for expr in DialogueCast.CAST[id].expr:
			p.set_expr(expr, false)
			var tex := DialogueCast.texture(id, expr)
			unique_paths[tex.resource_path] = true
			var mat := p.current_image.material as ShaderMaterial
			var mask := mat.get_shader_parameter("hair_mask") as Texture2D
			var image := mask.get_image()
			var hair_pixels := 0
			var cloth_pixels := 0
			for y in image.get_height():
				for x in image.get_width():
					var pixel := image.get_pixel(x, y)
					hair_pixels += int(pixel.r > 0.15)
					cloth_pixels += int(pixel.g + pixel.b > 0.05)
			_check(mat.shader == DialogueIdleMotion.SHADER and mat.get_shader_parameter("clip_enabled") == 0.0
				and mat.get_shader_parameter("bust") == 0.0 and hair_pixels > 150 and cloth_pixels > 100,
				id + "/" + expr + " 합체 셰이더 재사용 + 원화별 머리/옷 마스크")
			var initial := p.idle_motion.hair
			for i in 120:
				p._process(1.0 / 60.0)
			_check(p._tex == tex and p.idle_motion.hair.distance_to(initial) > 0.0001
				and p.idle_motion.hair.length() < 0.03 and is_finite(p.rotation), id + "/" + expr + " 실제 움직임/안정 변위")
		var origin := p.idle_motion.body_offset
		p.active = false
		for i in 90:
			p._process(1.0 / 60.0)
		_check(p.idle_motion.body_offset.distance_to(origin) > 0.1 and p.idle_motion.amount == 1.0,
			id + " 듣는 동안에도 아이들링 유지")
		motions[id] = p.idle_motion.body_offset
		var poses: Array = DialogueCast.CAST[id].expr.keys()
		if poses.size() > 1:
			var before := p._tex
			p.set_expr(poses[0], false)
			before = p._tex
			p.set_expr(poses[1], true)
			_check(p.old_image.visible and p._old == before
				and p.old_image.material.get_shader_parameter("hair_mask") == DialogueIdleMotion.mask_for(id, before), id + " 이전 표정도 자기 마스크로 교차 전환")
			for i in 15:
				p._process(1.0 / 60.0)
			_check(not p.old_image.visible and p.old_image.texture == null, id + " 전환 뒤 이전 원화 참조 정리")
		p.place("right")
		p._process(1.0 / 60.0)
		_check(p.current_image.flip_h == p._flip and p.shadow_image.flip_h == p._flip, id + " 자리 반전과 그림자 변형 일치")
		DialogueView.reduce_motion = true
		for i in 25:
			p._process(1.0 / 60.0)
		_check(p.idle_motion.amount == 0.0 and p.idle_motion.body_offset == Vector2.ZERO and p.rotation == 0.0
			and p.current_image.material.get_shader_parameter("hair_wave") == 0.0
			and p.current_image.material.get_shader_parameter("hair_off") == Vector2.ZERO, id + " 움직임 줄이기면 몸/머리/옷 모두 정지")
		DialogueView.reduce_motion = false
		for i in 25:
			p._process(1.0 / 60.0)
		p._process(1.2)
		_check(p.idle_motion.amount == 1.0 and p.idle_motion.hair.length() < 0.03 and is_finite(p.idle_motion.body_roll), id + " 복귀와 큰 프레임 간격에서 안정")
		_check(p.idle_motion.materials.size() == 3, id + " 표정 반복에도 재질 3개 고정")
		p.queue_free()
		await process_frame
	_check(motions.size() == 3 and motions.owner != motions.worker and motions.partner != motions.worker, "세 여성 모두 적용, 인물별 속도/위상 구별")
	var cached := DialogueIdleMotion._masks.size()
	for round in 3:
		for id in DialogueCast.CAST:
			if id == "me":
				continue
			for expr in DialogueCast.CAST[id].expr:
				DialogueIdleMotion.mask_for(id, DialogueCast.texture(id, expr))
	_check(cached == unique_paths.size() and DialogueIdleMotion._masks.size() == cached, "재진입/표정 반복 마스크 캐시 %d장으로 고정" % cached)
	var main: DialogueMain = load("res://scenes/partner_dialogue.tscn").instantiate()
	root.add_child(main)
	_check(not DialogueIdleMotion.supports("me") and main.view.speaker_portrait.material == null,
		"남주 대사창 원화는 아이들링 셰이더/모션 제외")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_M
	key.keycode = KEY_M
	key.pressed = true
	root.push_input(key)
	await process_frame
	_check(DialogueView.reduce_motion, "실제 M키 설정으로 아이들링 줄이기")
	DialogueView.reduce_motion = false
	main.queue_free()
	await process_frame
	print("RESULT dialogue_idle_check: %s (%d fails)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)
