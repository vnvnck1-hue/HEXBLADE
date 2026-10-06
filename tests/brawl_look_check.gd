extends SceneTree
## Run with: Godot --headless --path . -s tests/brawl_look_check.gd
## 브롤스타즈 식 화면 (scripts/presentation/brawl_look.gd, docs/brawl-look.md) 을 확인한다.
##  1. 기본 켜짐: 카메라는 통일 시야 TACTICAL(62° 부감 · FOV 36°) 그대로, 조명·환경광, 외곽선 브롤 규칙
##  2. 플레이어·맵 머티리얼이 브롤 셰이더로 바뀜 (Pal.flat · 투명은 그대로)
##  3. 새로 생긴 적도 바뀌고 발밑 그림자(붉은 원)가 붙음
##  4. N 으로 끄면 카메라·조명·머티리얼 모두 원래대로, 발밑 그림자 숨김
##  5. 다시 켜면 같은 머티리얼을 다시 쓴다 (원본 메타에 붙어 있어 늘지 않음), 씬을 다시 불러도 상태 유지
##  6. K(칠 질감)를 켜면 브롤 룩이 꺼진다

var fails := 0
var main: Main


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _press(key: Key) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = true
	root.push_input(ev)
	await _frames(1)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	root.push_input(up)
	await _frames(3)


func _is_brawl(m: Material) -> bool:
	var sm := m as ShaderMaterial
	return sm != null and sm.shader != null and (sm.shader == BrawlLook._shaders.get("body") or sm.shader == BrawlLook._shaders.get("body_nocull"))


## 하이라이트 세기. 따로 넣지 않은 파라미터는 null(셰이더 기본값 0)
func _spec(m: Material) -> float:
	var v: Variant = (m as ShaderMaterial).get_shader_parameter("spec_k")
	return float(v) if v != null else 0.0


func _count(n: Node) -> int:
	var c := 0
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		if _is_brawl(mi.material_override):
			c += 1
			continue
		if mi.mesh:
			for s in mi.mesh.get_surface_count():
				if _is_brawl(mi.get_surface_override_material(s)):
					c += 1
					break
	return c


## mo.co 무드 배경 (docs/moco-bg-claude.md): 바닥·벽·벽 밖 설비를 역할별로 칠하고, 월드 외곽선 계약(러프니스 0.5·림 0)은 그대로
func _moco_checks() -> void:
	if not BrawlLook.moco:
		return
	var floor_base := false
	for mi: MeshInstance3D in main.map.find_children("*", "MeshInstance3D", true, false):
		var sm := mi.material_override as ShaderMaterial
		if sm and sm.shader == BrawlLook._shaders.get("floor") and sm.get_shader_parameter("use_base") == true:
			floor_base = true
	_check(floor_base, "통로 바닥: 역할 재질 연결 (청보라 붓질 / 예전 기본색)")
	var walls := 0
	var services := 0
	var bad_contract := 0
	var shared := 0
	for mmi: MultiMeshInstance3D in main.map.find_children("*", "MultiMeshInstance3D", true, false):
		var sm := mmi.material_override as ShaderMaterial
		if not _is_brawl(sm):
			continue
		if str(mmi.get_meta("claude_bg", "")).begins_with("blocks_"):
			if float(sm.get_shader_parameter("role_mix")) > 0.0:
				walls += 1
		elif mmi.has_meta("claude_service"):
			if is_equal_approx(float(sm.get_shader_parameter("value_k")), BrawlLook.SERVICE_VALUE):
				services += 1
		if not is_equal_approx(float(sm.get_shader_parameter("out_rough")), 0.5) or float(sm.get_shader_parameter("rim")) > 0.0:
			bad_contract += 1
	_check(walls >= 1, "낮은 벽 블록 = 벽 역할 (윗면/옆면 기본색) (%d)" % walls)
	_check(services >= 1, "벽 밖 설비 프랍 = 설비 역할 (명도 %.2f) (%d)" % [BrawlLook.SERVICE_VALUE, services])
	_check(bad_contract == 0, "벽·설비도 월드 외곽선 계약 유지 (러프니스 0.5 · 림 0)")
	# 3m W01 (일반 메시): 벽 역할
	for n: Node in main.map.find_children("*", "Node3D", true, false):
		if str(n.get_meta("claude_bg", "")) == "w01":
			for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
				var m := mi.get_surface_override_material(0) as ShaderMaterial
				if m and float(m.get_shader_parameter("role_mix")) > 0.0:
					shared += 1
			break
	_check(shared >= 1, "3m W01 벽도 벽 역할")
	_check(is_equal_approx(main.env.ssao_intensity, 0.45) and is_equal_approx(main.env.glow_intensity, 0.25), "SSAO 0.45 · glow 0.25")
	var bl: Dictionary = BrawlLook.base_light(main)
	_check(is_equal_approx(float(bl.glow), main.env.glow_intensity), "레이저 암전 복귀 glow = 평상시 glow")
	# 플레이어 조명 풀: 배경 재질만 플레이어 위치를 받아 어두워지고, 캐릭터 재질은 받지 않는다
	if BrawlLook.pool:
		var pp := main.player.global_position
		var bg_ok := 0
		var bg_n := 0
		for id in BrawlLook._pool_mats:
			var pm := (BrawlLook._pool_mats[id] as WeakRef).get_ref() as ShaderMaterial
			if pm == null:
				continue
			bg_n += 1
			var ps := BrawlLook.pool_state()
			if float(pm.get_shader_parameter("pool_use")) > 0.5 and ps.w > 0.5 and Vector3(ps.x, ps.y, ps.z).distance_to(pp) < 0.5:
				bg_ok += 1
		_check(bg_n > 0 and bg_ok == bg_n, "조명 풀: 배경 재질이 플레이어 위치를 받음 (%d/%d)" % [bg_ok, bg_n])
		var char_tracked := 0
		for mi: MeshInstance3D in main.player.find_children("*", "MeshInstance3D", true, false):
			var m := mi.material_override as ShaderMaterial
			if m and BrawlLook._pool_mats.has(m.get_instance_id()):
				char_tracked += 1
		_check(char_tracked == 0, "캐릭터 재질은 조명 풀에서 빠짐 (어둠 속에서도 밝게)")


func _run() -> void:
	PaintedLook.game_preset = PaintedLook.NONE
	BrawlLook.on = true
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	main.player.invuln = 999.0

	# ── 1. 기본 켜짐 ──
	var cam := main.camera
	# 카메라 시야는 모든 씬이 TACTICAL 하나로 통일됐다 (브롤 룩도 바꾸지 않는다)
	_check(cam.preset_index == CameraRig.DEFAULT, "카메라는 통일 시야 TACTICAL")
	var off: Vector3 = cam.p.offset
	var pitch := rad_to_deg(atan2(off.y, off.z))
	_check(absf(pitch - 62.0) < 1.0 and absf(cam.p.fov - CameraRig.VIEW_FOV) < 0.01, "62° 부감 · FOV 36° (%.1f°)" % pitch)
	_check(absf(cam.cur_fov - CameraRig.VIEW_FOV) < 0.5, "씬 시작부터 통일 화각")
	_check(main.env.ambient_light_color == BrawlLook.AMBIENT and is_equal_approx(main.sun.shadow_opacity, BrawlLook.SHADOW_OPACITY), "밝은 환경광 · 옅은 그림자")
	_check(is_instance_valid(ToonOutline.inst) and ToonOutline.inst.visible and float(ToonOutline.inst.mat.get_shader_parameter("brawl")) > 0.5, "외곽선 브롤 규칙 (캐릭터 실루엣만)")

	# ── 2. 머티리얼 ──
	var pc := _count(main.player)
	_check(pc > 3, "플레이어 머티리얼이 브롤 셰이더로 (%d개)" % pc)
	var floor_ok := false
	for mi: MeshInstance3D in main.map.find_children("*", "MeshInstance3D", true, false):
		var sm := mi.material_override as ShaderMaterial
		if sm and sm.shader == BrawlLook._shaders.get("floor"):
			floor_ok = true
	_check(floor_ok, "맵 바닥이 브롤 바닥 셰이더로")
	var blocks := main.map.find_children("*", "MultiMeshInstance3D", true, false)
	var blocks_ok := 0
	for mmi: MultiMeshInstance3D in blocks:
		if _is_brawl(mmi.material_override):
			blocks_ok += 1
	_check(blocks_ok == blocks.size(), "배경 블록(MultiMesh)도 브롤 셰이더로 (%d/%d)" % [blocks_ok, blocks.size()])
	var bad := 0
	for mi: MeshInstance3D in main.find_children("*", "MeshInstance3D", true, false):
		if mi.has_meta("bl_orig"):
			var o: Material = mi.get_meta("bl_orig")
			if o == Pal.flat() or (o is BaseMaterial3D and (o as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
				bad += 1
	_check(bad == 0, "발광 단색·투명 머티리얼은 그대로")
	var world_rim := 0
	for mi: MeshInstance3D in main.map.find_children("*", "MeshInstance3D", true, false):
		if _is_brawl(mi.material_override) and float((mi.material_override as ShaderMaterial).get_shader_parameter("rim")) > 0.0:
			world_rim += 1
	_check(world_rim == 0, "맵(월드) 파츠는 림라이트·외곽선 없음")
	# 바닥·월드는 무광: 하이라이트를 켜면 지형 굴곡을 따라 넓은 흰 반사 얼룩이 번진다 (2026-10-04 사용자 보고)
	var glossy := 0
	var floor_spec := -1.0
	for mi: MeshInstance3D in main.map.find_children("*", "MeshInstance3D", true, false):
		var sm := mi.material_override as ShaderMaterial
		if sm == null:
			continue
		if sm.shader == BrawlLook._shaders.get("floor"):
			floor_spec = _spec(sm)
		elif _is_brawl(sm) and _spec(sm) > 0.0:
			glossy += 1
	for mmi: MultiMeshInstance3D in main.map.find_children("*", "MultiMeshInstance3D", true, false):
		if _is_brawl(mmi.material_override) and _spec(mmi.material_override) > 0.0:
			glossy += 1
	_check(is_zero_approx(floor_spec) and glossy == 0, "바닥·월드 파츠 무광 (하이라이트 0)")
	_moco_checks()

	# ── 3. 새로 생긴 적 ──
	var e := Crawler.new()
	main.world.add_child(e)
	e.global_position = main.player.global_position + Vector3(6, 0, 6)
	await _frames(4)
	_check(_count(e) > 3, "켠 뒤 생긴 적도 바뀜 (%d개)" % _count(e))
	var blob := e.get_node_or_null("BrawlBlob") as MeshInstance3D
	_check(blob != null and blob.visible and (blob.get_instance_shader_parameter("ring_col") as Color).r > 0.9, "적 발밑 그림자 + 붉은 원")
	_check(main.player.get_node_or_null("BrawlBlob") != null, "플레이어 발밑 그림자")
	var mat_before: Material = null
	for mi: MeshInstance3D in main.player.find_children("*", "MeshInstance3D", true, false):
		if _is_brawl(mi.material_override):
			mat_before = mi.material_override
			break

	# ── 4. N 으로 끔 ──
	await _press(KEY_N)
	_check(not BrawlLook.on and _count(main.player) == 0 and _count(e) == 0, "N 으로 끄면 머티리얼 원래대로")
	_check(cam.preset_index == CameraRig.DEFAULT, "카메라는 그대로 TACTICAL")
	_check(main.env.ambient_light_color != BrawlLook.AMBIENT and main.sun.shadow_opacity != BrawlLook.SHADOW_OPACITY, "조명 원래대로")
	_check(not blob.visible, "발밑 그림자 숨김")
	var floor_back := true
	for mi: MeshInstance3D in main.map.find_children("*", "MeshInstance3D", true, false):
		var sm := mi.material_override as ShaderMaterial
		if sm and sm.shader == BrawlLook._shaders.get("floor"):
			floor_back = false
	for mmi: MultiMeshInstance3D in main.map.find_children("*", "MultiMeshInstance3D", true, false):
		if _is_brawl(mmi.material_override):
			floor_back = false
	_check(floor_back, "맵 바닥·블록 원래대로")

	# ── 5. 다시 켬 · 다시 불러오기 ──
	await _press(KEY_N)
	var mat_after: Material = null
	for mi: MeshInstance3D in main.player.find_children("*", "MeshInstance3D", true, false):
		if _is_brawl(mi.material_override):
			mat_after = mi.material_override
			break
	_check(BrawlLook.on and mat_after != null and mat_after == mat_before, "다시 켜면 같은 머티리얼 재사용")
	e.queue_free()
	main.queue_free()
	await _frames(2)
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	_check(main.camera.preset_index == CameraRig.DEFAULT and _count(main.player) > 3, "다시 불러도 켜진 상태 유지 (카메라는 TACTICAL)")

	# ── 6. K 를 켜면 브롤 룩은 꺼짐 ──
	await _press(KEY_K)
	_check(PaintedLook.game_preset == PaintedLook.HEARTH and not BrawlLook.on and main.camera.preset_index == CameraRig.DEFAULT, "K(칠 질감)를 켜면 브롤 룩 꺼짐")
	await _press(KEY_N)
	_check(BrawlLook.on and PaintedLook.game_preset == PaintedLook.NONE, "N 으로 다시 켜면 칠 질감 꺼짐")

	PaintedLook.game_preset = PaintedLook.NONE
	print("RESULT  %s  (%d fail)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
