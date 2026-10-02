extends SceneTree
## Run with: Godot --headless --path . -s tests/painted_look_check.gd
## 하스스톤 식 핸드 페인팅 룩 (scripts/presentation/painted_look.gd) 을 확인한다.
##  1. 기본은 꺼짐이고, K 키로 켜면 플레이어 파츠의 셀 머티리얼이 칠 머티리얼로 바뀌고 경계 상자가 들어간다.
##  2. 발광 파츠(눈·코어)와 Pal.flat 은 그대로 둔다.
##  3. 켠 뒤 새로 생긴 적도 자동으로 바뀐다.
##  4. 맵 벽은 표면 덮어쓰기, 바닥은 바탕색만 따뜻해지고, 끄면 모두 원래대로 돌아온다(조명 포함).
##  5. 켠 상태는 씬을 다시 불러도 유지된다.

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


func _press_k() -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_K
	ev.keycode = KEY_K
	ev.pressed = true
	root.push_input(ev)
	await _frames(1)
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	root.push_input(up)
	await _frames(2)


func _meshes(n: Node) -> Array:
	return n.find_children("*", "MeshInstance3D", true, false)


func _count_painted(n: Node) -> int:
	var c := 0
	for mi in _meshes(n):
		if mi.material_override is ShaderMaterial and mi.has_meta("pl_orig"):
			c += 1
	return c


func _run() -> void:
	PaintedLook.game_preset = PaintedLook.NONE
	# 칠 머티리얼은 코드로 만든 단색 파츠용이다. 새 메카(텍스처 원본)는 바꾸지 않으므로 예전 로봇으로 확인한다
	MechPlayer._choice = "robot"
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	main.player.invuln = 999.0
	var sun_c := main.sun.light_color
	var amb := main.env.ambient_light_color

	# ── 1. 기본 꺼짐 → K 로 켬 ──
	_check(PaintedLook.game_preset == PaintedLook.NONE and _count_painted(main.player) == 0, "기본은 꺼짐")
	await _press_k()
	_check(PaintedLook.game_preset == PaintedLook.HEARTH, "K 로 HEARTH 켜짐")
	var painted := _count_painted(main.player)
	_check(painted > 10, "플레이어 파츠가 칠 머티리얼로 바뀜 (%d개)" % painted)
	var boxed := 0
	for mi in _meshes(main.player):
		if mi.has_meta("pl_orig") and mi.get_instance_shader_parameter("aabb_hi") != null:
			boxed += 1
	_check(boxed == painted, "바뀐 파츠마다 경계 상자 전달 (%d/%d)" % [boxed, painted])

	# ── 2. 발광·flat 은 그대로 ──
	var bad := 0
	for mi in _meshes(main):
		var m: Material = mi.get_meta("pl_orig") if mi.has_meta("pl_orig") else null
		if m is StandardMaterial3D and (m as StandardMaterial3D).emission_enabled:
			bad += 1
		if mi.material_override == Pal.flat() and mi.has_meta("pl_orig"):
			bad += 1
	_check(bad == 0, "발광·flat 머티리얼은 바꾸지 않음")

	# ── 3. 나중에 생긴 적 ──
	var e := Crawler.new()
	main.world.add_child(e)
	e.global_position = main.player.global_position + Vector3(6, 0, 6)
	await _frames(3)
	_check(_count_painted(e) > 5, "켠 뒤 생긴 적도 바뀜 (%d개)" % _count_painted(e))
	e.queue_free()

	# ── 4. 지형 · 끄면 복원 ──
	var walls := 0
	var floor_warm := false
	for mi in _meshes(main.map):
		if mi.material_override == null and mi.mesh and mi.mesh.get_surface_count() > 0 and mi.get_surface_override_material(0) is ShaderMaterial:
			walls += 1
		if mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).has_meta("pl_base"):
			var sm := mi.material_override as ShaderMaterial
			floor_warm = floor_warm or sm.get_shader_parameter("base") != sm.get_meta("pl_base")
	_check(walls > 0, "맵 벽 표면이 칠 머티리얼로 덮임")
	_check(floor_warm, "맵 바닥 바탕색이 따뜻해짐")
	_check(main.sun.light_color != sun_c, "주광이 따뜻해짐")
	await _press_k()
	_check(PaintedLook.game_preset == PaintedLook.NONE and _count_painted(main.player) == 0, "K 로 다시 끄면 플레이어 원래대로")
	var left := 0
	for mi in _meshes(main.map):
		if mi.material_override == null and mi.mesh and mi.mesh.get_surface_count() > 0 and mi.get_surface_override_material(0) != null:
			left += 1
		if mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).has_meta("pl_base"):
			var sm := mi.material_override as ShaderMaterial
			if sm.get_shader_parameter("base") != sm.get_meta("pl_base"):
				left += 1
	_check(left == 0, "끄면 벽·바닥도 원래대로")
	_check(main.sun.light_color == sun_c and main.env.ambient_light_color == amb, "끄면 조명도 원래대로")

	# ── 5. 씬을 다시 불러도 유지 ──
	await _press_k()
	main.queue_free()
	await _frames(2)
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(30)
	_check(PaintedLook.game_preset == PaintedLook.HEARTH and _count_painted(main.player) > 10, "다시 불러도 켜진 상태 유지")

	PaintedLook.game_preset = PaintedLook.NONE
	print("RESULT  %s  (%d fail)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
