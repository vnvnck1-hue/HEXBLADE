extends SceneTree
## 브롤 룩 흰 얼룩 찾기: 얼룩 화면 지점의 밝기를 재며 노드를 하나씩 숨겨, 숨겼을 때 밝기가 떨어지는 노드를 출력한다.
## powershell -File tools\godot.ps1 wait --resolution 1280x720 -s res://_capture/brawl_haze_find.gd -- --seed=4

const SPOT := Vector2(200, 560)
const CLEAN := Vector2(1000, 600)


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _lum(img: Image, p: Vector2) -> float:
	var s := 0.0
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var c := img.get_pixelv(Vector2i(p) + Vector2i(dx, dy))
			s += c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	return s / 81.0


func _measure_at(p: Vector2) -> float:
	await _frames(3)
	await RenderingServer.frame_post_draw
	return _lum(root.get_texture().get_image(), p)


func _measure() -> float:
	await _frames(3)
	await RenderingServer.frame_post_draw
	return _lum(root.get_texture().get_image(), SPOT)


func _run() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(30)
	var main := current_scene as Main
	main.player.invuln = 9999.0
	main.hud.visible = false
	main.process_mode = Node.PROCESS_MODE_DISABLED   # 모두 멈춘다 (화면만)
	main.camera.snap(main.player.global_position)
	await _frames(5)
	var base := await _measure()
	print("HAZE base=%.3f" % base)
	# 깨끗해 보이는 지점의 밝기: 해 그림자를 끄면 얼마나 밝아지나 (밝아지면 그 지점은 무언가의 그림자 속)
	var clean0 := await _measure_at(CLEAN)
	main.sun.shadow_enabled = false
	var clean1 := await _measure_at(CLEAN)
	var spot1 := await _measure()
	main.sun.shadow_enabled = true
	print("HAZE clean=%.3f clean_noshadow=%.3f spot_noshadow=%.3f" % [clean0, clean1, spot1])
	# 실험: 해를 숨김 / 해를 예전 방향으로 / 바닥 셀 단계 없앰
	main.sun.visible = false
	print("HAZE nosun clean=%.3f spot=%.3f" % [await _measure_at(CLEAN), await _measure()])
	main.sun.visible = true
	var rot := main.sun.rotation_degrees
	main.sun.rotation_degrees = Vector3(-62, 28, 0)
	print("HAZE oldsun clean=%.3f spot=%.3f" % [await _measure_at(CLEAN), await _measure()])
	main.sun.rotation_degrees = Vector3(-90, 0, 0)
	print("HAZE topsun clean=%.3f spot=%.3f" % [await _measure_at(CLEAN), await _measure()])
	main.sun.rotation_degrees = rot
	var fm: ShaderMaterial = null
	for mi: MeshInstance3D in main.map.find_children("*", "MeshInstance3D", true, false):
		var sm := mi.material_override as ShaderMaterial
		if sm and sm.shader == BrawlLook._shaders.get("floor"):
			fm = sm
	if fm:
		fm.set_shader_parameter("shade_floor", 1.0)
		fm.set_shader_parameter("shade_tint", Color(1, 1, 1))
		print("HAZE nocel clean=%.3f spot=%.3f" % [await _measure_at(CLEAN), await _measure()])
	if clean1 - clean0 > 0.05:
		# 그림자를 드리우는 노드 찾기: 숨겼을 때 깨끗한 지점이 밝아지는 것
		for n in main.find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			if not g.is_visible_in_tree() or g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				continue
			var keep := g.cast_shadow
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var v := await _measure_at(CLEAN)
			g.cast_shadow = keep
			if v - clean0 > 0.05:
				var aabb := g.get_aabb()
				print("CASTER +%.3f  %s (%s) aabb=%s pos=%s  %s" % [v - clean0, main.get_path_to(g), g.get_class(), aabb, g.global_position, _mat_info(g)])
		print("HAZE done")
		quit()
		return
	# 넓게: 3단계 깊이까지 Node3D 를 하나씩 숨겨 본다
	var cands: Array[Node] = []
	for n in main.find_children("*", "Node3D", true, false):
		var depth := 0
		var p := n.get_parent()
		while p != main and p != null:
			depth += 1
			p = p.get_parent()
		if depth <= 3:
			cands.append(n)
	for n in cands:
		var n3 := n as Node3D
		if not n3.visible or n3 is Camera3D:
			continue
		n3.visible = false
		var v := await _measure()
		n3.visible = true
		if base - v > 0.03:
			print("HAZE drop %.3f  %s  (%s)  mat=%s" % [base - v, main.get_path_to(n), n.get_class(), _mat_info(n)])
	print("HAZE done")
	quit()


func _mat_info(n: Node) -> String:
	var gi := n as GeometryInstance3D
	if gi == null:
		return "-"
	var s := "override=%s" % gi.material_override
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		s += " mesh=%s" % (n as MeshInstance3D).mesh.get_class()
	if n is MultiMeshInstance3D:
		s += " multimesh"
	return s
