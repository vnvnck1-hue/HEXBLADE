extends SceneTree
## Run with: Godot --headless --path . -s tests/ground_break_check.gd
## 바닥 파괴 연출 (GroundBreak) 확인. 전투 테스트장(training.tscn)에서:
##  1. 스타일 목록 · = 키 전환 · use_id
##  2. 스타일마다 조각이 생기고, 판은 들리고 / 기둥은 솟고 / 찌그러짐은 둔덕이 생기고 / 덩어리는 튀었다 바닥에 멈춘다
##  3. 수명이 지나면 조각·데칼이 모두 사라진다. OFF 면 아무것도 안 생긴다
##  4. 조각 재질은 그 자리 바닥 재질을 복제해 밝힌 것 (안 들린 판은 바닥 재질 그대로)
##  5. 상한: 한꺼번에 많이 불러도 조각 수 · 연출 수가 넘지 않는다
##  6. E 도약 내려찍기 착지에서 연출이 나온다

var fails := 0
var main: TrainingMain
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


func _secs(s: float) -> void:
	await _frames(int(ceil(s * 60.0)))


func _gb() -> GroundBreak:
	return GroundBreak.inst


func _clear() -> void:
	if is_instance_valid(_gb()):
		for b in _gb().bursts:
			_gb()._free_burst(b)
		_gb().bursts.clear()
		_gb()._budget = GroundBreak.BUDGET


func _run() -> void:
	var scene: PackedScene = load("res://scenes/training.tscn")
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	player = main.player
	main.god = true
	for d in main.dummies:
		if is_instance_valid(d):
			d.queue_free()
	main.dummies.clear()
	var at := main.center + Vector3(0, 0, -1.0)
	var gy := Main.gy(at)

	# 1. 스타일
	var ids := GroundBreak.STYLES.map(func(s): return s.id)
	_check(ids == ["crumble", "slab", "spike", "buckle", "scatter", "mix", "off"], "스타일 7종 (깨짐 튐 기본 · 판 들림 · 암석 솟음 · 찌그러짐 · 파편 튐 · 대파괴 · 끔)")
	GroundBreak.style = 0
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_EQUAL
	ev.pressed = true
	main._unhandled_input(ev)
	_check(GroundBreak.style == 1, "= 키로 다음 스타일 (%d)" % GroundBreak.style)
	ev.shift_pressed = true
	main._unhandled_input(ev)
	_check(GroundBreak.style == 0, "Shift+= 로 이전 스타일")
	GroundBreak.use_id("buckle")
	_check(GroundBreak.current().id == "buckle", "use_id")
	await _frames(2)
	_clear()

	# 2·3. 스타일마다
	for id in ["crumble", "slab", "spike", "buckle", "scatter", "mix"]:
		_clear()
		GroundBreak.burst(at, 1.0, Vector3.RIGHT, id)
		var gb := _gb()
		_check(is_instance_valid(gb) and gb.bursts.size() == 1, "%s: 연출 하나 생김" % id)
		if not is_instance_valid(gb) or gb.bursts.is_empty():
			continue
		var b: GroundBreak.Burst = gb.bursts[0]
		await _secs(0.35)
		match id:
			"slab", "mix":
				var top := 0.0
				var tilted := 0
				for pc in b.pieces:
					if pc.kind == GroundBreak.SLAB:
						top = maxf(top, pc.node.global_transform.basis.y.angle_to(Vector3.UP))
						if pc.node.global_transform.basis.y.angle_to(Vector3.UP) > deg_to_rad(15.0):
							tilted += 1
				_check(top > deg_to_rad(45.0) and tilted >= 6, "%s: 판이 들림 (최대 %.0f° · 15° 넘는 판 %d개)" % [id, rad_to_deg(top), tilted])
			"spike":
				var hi := -9.0
				for pc in b.pieces:
					if pc.kind == GroundBreak.SPIKE:
						var tip: Vector3 = pc.node.global_transform * Vector3(0, pc.lift, 0)
						hi = maxf(hi, tip.y - gy)
				_check(hi > 0.8, "spike: 기둥이 바닥 위로 솟음 (끝 높이 %.2fm)" % hi)
			"buckle":
				var mx := 0.0
				for ri in GroundBreak.BK_RINGS + 1:
					var r := b.R * float(ri) / GroundBreak.BK_RINGS
					mx = maxf(mx, gb._buckle_h(b, r, 0.3, ri * GroundBreak.BK_SEGS))
				_check(mx > 0.25, "buckle: 둔덕 고리 높이 %.2fm" % mx)
				_check(b.buckle.material_override is ShaderMaterial and (b.buckle.material_override as ShaderMaterial).shader.code.contains("COLOR.rgb"), "buckle: 정점 색 주름 명암 재질")
			"crumble":
				var spikes := 0
				var slabs := 0
				var air := 0
				for pc in b.pieces:
					match pc.kind:
						GroundBreak.SPIKE: spikes += 1
						GroundBreak.SLAB: slabs += 1
						GroundBreak.CHUNK:
							if pc.node.global_position.y > gy + 0.4:
								air += 1
				_check(spikes == 0 and slabs >= 10 and air >= 5, "crumble: 솟는 암석 없음 · 가장자리 판 %d · 튄 파편 %d" % [slabs, air])
			"scatter":
				var air := 0
				for pc in b.pieces:
					if pc.kind == GroundBreak.CHUNK and pc.node.global_position.y > gy + 0.4:
						air += 1
				_check(air >= 5, "scatter: 덩어리가 튀어 오름 (공중 %d개)" % air)
		if id == "scatter":
			await _secs(1.6)
			var rest := 0
			var below := 0
			var chunks := 0
			for pc in b.pieces:
				if pc.kind == GroundBreak.CHUNK:
					chunks += 1
					if pc.rest:
						rest += 1
					if pc.node.global_position.y < gy - 0.02:
						below += 1
			_check(rest > chunks * 0.6 and below == 0, "scatter: 바닥에 멈춤 (%d/%d, 바닥 아래 %d)" % [rest, chunks, below])
		await _secs(b.life + 0.2)
		_check(gb.bursts.is_empty(), "%s: 수명이 지나면 연출이 끝남" % id)
		await _frames(2)
		var left := 0
		for c in gb.get_children():
			if not c.is_queued_for_deletion():
				left += 1
		_check(left == 0, "%s: 남은 조각 · 데칼 노드 없음 (%d)" % [id, left])

	# OFF
	_clear()
	GroundBreak.burst(at, 1.0, Vector3.ZERO, "off")
	_check(_gb().bursts.is_empty(), "off: 아무것도 안 생김")

	# 4. 재질
	_clear()
	GroundBreak.burst(at, 1.0, Vector3.ZERO, "slab")
	var b2: GroundBreak.Burst = _gb().bursts[0]
	# 바깥 판이 모두 들리는 유효한 무작위 결과도 있다. 두 재질 분기가
	# 함께 존재하는 표본을 제한된 횟수로 확보해 재질 계약을 검사한다.
	for retry in 8:
		if b2.pieces.any(func(pc): return pc.kind == GroundBreak.SLAB and pc.ang <= 0.05):
			break
		_clear()
		GroundBreak.burst(at, 1.0, Vector3.ZERO, "slab")
		b2 = _gb().bursts[0]
	var fm := b2.fmat as ShaderMaterial
	_check(fm != null and fm.shader != null and fm.shader.code.contains("floor_base"), "그 자리 바닥 재질을 찾음")
	var lifted := 0
	var flat_floor := 0
	var brighter := true
	var brightness_key := "lift" if fm and fm.get_shader_parameter("handpaint") == true else "floor_value"
	for pc in b2.pieces:
		if pc.kind != GroundBreak.SLAB:
			continue
		var m := pc.node.material_override as ShaderMaterial
		if pc.ang > 0.05:
			lifted += 1
			if m == fm or m == null or float(m.get_shader_parameter(brightness_key)) <= float(fm.get_shader_parameter(brightness_key)):
				brighter = false
		elif m == fm:
			flat_floor += 1
	_check(lifted > 0 and brighter, "들린 판은 바닥보다 밝은 복제 재질 (%d개)" % lifted)
	_check(flat_floor > 0, "안 들린 판은 바닥 재질 그대로 (%d개)" % flat_floor)

	# 5. 상한
	_clear()
	for i in 30:
		_gb()._budget = GroundBreak.BUDGET
		GroundBreak.burst(at + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), 1.0, Vector3.ZERO, "mix")
	_check(_gb().bursts.size() <= GroundBreak.MAX_BURSTS and GroundBreak.piece_count() <= GroundBreak.MAX_PIECES + 140, "상한: 연출 %d개 · 조각 %d개" % [_gb().bursts.size(), GroundBreak.piece_count()])
	_clear()
	var made := 0
	for i in 20:
		var n0 := _gb().bursts.size()
		GroundBreak.burst(at, 0.3, Vector3.ZERO, "slab")
		if _gb().bursts.size() > n0:
			made += 1
	_check(made <= int(GroundBreak.BUDGET), "한 프레임에 많이 불러도 %d개만 (미사일 일제 사격)" % made)

	# 7. 지나간 자리 흔적: 대시 중 일격참
	_clear()
	GroundBreak.style = 0
	await _secs(0.3)
	player.global_position = main.center + Vector3(-6, 0, 3)
	player.velocity = Vector3.ZERO
	player.aim_override = player.global_position + Vector3(12, 0.95, 0)
	await _frames(4)
	Input.action_press("move_right")
	Input.action_press("dash")
	await _frames(2)
	Input.action_release("dash")
	Input.action_release("move_right")
	await _frames(3)
	Input.action_press("slash")
	await _frames(2)
	Input.action_release("slash")
	await _secs(0.5)
	var trails: Array = _gb().bursts.filter(func(x): return x.trail)
	_check(trails.size() >= 3, "돌진 일격참이 지나간 자리에 흔적 %d개" % trails.size())
	var spread := 0.0
	for tb in trails:
		spread = maxf(spread, (tb.center - trails[0].center).length())
	_check(spread > 2.0, "흔적이 길을 따라 이어짐 (%.1fm)" % spread)
	var small := true
	for tb in trails:
		if tb.R > 1.3 or tb.pieces.size() > 8:
			small = false
	_check(small, "흔적은 작다 (찌그러짐 반경 · 파편 수)")
	var hop := 0.0
	await _secs(0.1)
	for tb in trails:
		for pc in tb.pieces:
			hop = maxf(hop, pc.node.global_position.y - gy)
	_check(hop > 0.05 and hop < 1.6, "파편이 살짝 튐 (최고 %.2fm)" % hop)
	player.aim_override = Vector3.INF
	await _secs(GroundBreak.TRAIL_LIFE + 0.3)
	_check(_gb().bursts.filter(func(x): return x.trail).is_empty(), "흔적도 수명이 지나면 사라짐")

	# 8. Q 합체 휠윈드
	_clear()
	var dr := PartnerDrone.inst
	if is_instance_valid(dr):
		main.infinite = true
		for i in 600:
			if dr.state == PartnerDrone.St.FOLLOW and dr.link_cd <= 0.0 and dr.whirl_t < 0.0:
				break
			await physics_frame
		dr.whirl_link()
		var spun := false
		for i in 300:
			await physics_frame
			if dr.whirl_t >= 0.0:
				spun = true
				break
		Input.action_press("move_left")
		var made_q := 0
		var seen := {}
		for i in 900:
			await physics_frame
			for tb in _gb().bursts:
				if tb.trail and not seen.has(tb):
					seen[tb] = true
					made_q += 1
			if dr.whirl_t < 0.0:
				break
		Input.action_release("move_left")
		_check(spun and made_q >= 6, "Q 휠윈드가 지나간 자리에 흔적 %d개" % made_q)
		await _secs(GroundBreak.TRAIL_LIFE + 0.3)
	else:
		_check(false, "드론 없음")
	GroundBreak.style = GroundBreak.STYLES.size() - 1
	_clear()
	player.lunge_t = 0.5
	for i in 20:
		player.global_position += Vector3(0.3, 0, 0)
		GroundBreak.follow(player, 1.0 / 60.0)
	player.lunge_t = 0.0
	_check(_gb().bursts.is_empty(), "OFF 면 흔적도 없음")
	GroundBreak.style = 0

	# 6. 도약 내려찍기
	_clear()
	GroundBreak.style = 0
	await _secs(0.3)
	player.global_position = main.center + Vector3(0, 0, 4.5)
	player.velocity = Vector3.ZERO
	player.leap.cd = 0.0
	player.aim_override = main.center + Vector3(0, 0.95, 0)
	await _frames(2)
	Input.action_press("rush_skill")
	await _frames(10)
	Input.action_release("rush_skill")
	var landed := false
	for i in 120:
		await physics_frame
		if is_instance_valid(_gb()) and not _gb().bursts.is_empty():
			landed = true
			break
	_check(landed, "E 도약 내려찍기 착지에서 바닥이 깨짐")
	if landed:
		var c: Vector3 = _gb().bursts[0].center
		_check(Vector2(c.x - main.center.x, c.z - main.center.z).length() < 1.5, "착지점에서 깨짐 (%.2fm)" % Vector2(c.x - main.center.x, c.z - main.center.z).length())
	player.aim_override = Vector3.INF

	print("RESULT ground_break_check: %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
