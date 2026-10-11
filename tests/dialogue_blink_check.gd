extends SceneTree
## 눈 이외 RGBA 보존, 모든 포즈의 닫힌 프레임, 실제 포트레이트 교체/재개/전환/캐시 검사.
var fails := 0
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	fails += int(not ok)
func _run() -> void:
	root.size = Vector2i(1280, 800)
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://output/portrait-blink-20261011/asset_validation.json"))
	check(DialogueCast.CAST.keys() == ["owner", "worker", "partner", "me"], "캐스트는 승인 여성 세 명과 유지한 남주만")
	for row in rows:
		# 원본 PNG를 비교한다. 임포트의 fix_alpha_border는 투명 픽셀 RGB를 확장한다.
		var open := Image.new()
		var shut := Image.new()
		open.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/portraits/opening_cast/" + row.id + ".png"))
		shut.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/portraits/opening_cast/" + row.id + "_closed.png"))
		check(open.get_size() == Vector2i(1254, 1254) and shut.get_size() == open.get_size(), row.id + " 동일 규격")
		open.convert(Image.FORMAT_RGBA8)
		shut.convert(Image.FORMAT_RGBA8)
		var a := open.get_data()
		var b := shut.get_data()
		var polygons: Array[PackedVector2Array] = []
		for points in row.regions:
			var polygon := PackedVector2Array()
			for point in points:
				polygon.append(Vector2(point[0], point[1]))
			polygons.append(polygon)
		var alpha_same := true
		var outside_same := true
		var changed := 0
		var outside_count := 0
		for pixel in 1254 * 1254:
			var i := pixel * 4
			alpha_same = alpha_same and a[i + 3] == b[i + 3]
			if a[i] == b[i] and a[i + 1] == b[i + 1] and a[i + 2] == b[i + 2]:
				continue
			changed += 1
			var at := Vector2(pixel % 1254 + 0.5, floori(float(pixel) / 1254.0) + 0.5)
			var in_eye := false
			for polygon in polygons:
				in_eye = in_eye or Geometry2D.is_point_in_polygon(at, polygon)
			outside_same = outside_same and in_eye
			outside_count += int(not in_eye)
		check(alpha_same and outside_same and changed > 1000, row.id + " 눈 밖 픽셀/전체 알파 원본과 완전 동일")
		print("  pixels %s changed=%d outside=%d alpha_same=%s" % [row.id, changed, outside_count, alpha_same])
	var total := 0
	for id in ["owner", "worker", "partner"]:
		var p := DialoguePortrait.new()
		p.setup(id, "left", "", Vector2(1280, 800))
		root.add_child(p)
		p.set_process(false)
		for expr in DialogueCast.CAST[id].expr:
			p.set_expr(expr, false)
			p.blink.closed = false
			p.blink.remaining = 0.001
			var mask: Texture2D = p.current_image.material.get_shader_parameter("hair_mask")
			p._process(1.0 / 60.0)
			check(p.blink.closed and p.current_image.texture == DialogueCast.texture(id, expr, true)
				and p.shadow_image.texture == p.current_image.texture, id + "/" + expr + " 실제 눈 감기/그림자 일치")
			p._process(DialogueBlink.CLOSED_TIME + 0.001)
			check(not p.blink.closed and p.current_image.texture == DialogueCast.texture(id, expr)
				and p.current_image.material.get_shader_parameter("hair_mask") == mask, id + "/" + expr + " 0.12초 뒤 원본 복귀, 마스크 유지")
		p.blink.closed = true
		p.blink.remaining = 0.1
		p.set_expr(DialogueCast.CAST[id].default, true)
		p._process(0.0)
		check(p.current_image.texture == DialogueCast.texture(id, p.expr, true), id + " 감은 상태에서 표정 전환")
		DialogueView.reduce_motion = true
		p._process(0.01)
		check(not p.blink.closed and p.current_image.texture == p._tex, id + " M 움직임 줄이기는 눈을 뜬 상태로 고정")
		DialogueView.reduce_motion = false
		p.active = false
		p.blink.remaining = 0.5
		var before := p.blink.count
		for frame in 3600:
			p._process(1.0 / 60.0)
		var n := p.blink.count - before
		total += n
		check(n >= 8 and n <= 22, id + " 듣는 동안도 불규칙하게 깜빡임 (60초 %d회)" % n)
		p.queue_free()
		await process_frame
	check(DialogueIdleMotion._masks.size() == 6, "눈 프레임 추가 후에도 아이들링 마스크는 원본 6장으로 고정")
	check(DialogueCast.texture("me", "neutral") != null and not DialogueIdleMotion.supports("me"), "남주 포트레이트 유지, 기존 제외 설정 유지")
	check(DiagonalDockingCutin.CHARACTERS.map(func(cfg): return cfg.id) == ["purple", "green", "mint"], "합체 캐릭터는 기존 세 명 유지, 대화 캐스트와 분리")
	check(CockpitCutin.PLATE.resource_path == "res://assets/vfx/drone_cutin/cockpit_plate_clipped.png", "조종석 합체 원본 유지")
	print("RESULT dialogue_blink_check: %s (%d fails), natural blinks %d" % ["PASS" if fails == 0 else "FAIL", fails, total])
	quit(int(fails > 0))
