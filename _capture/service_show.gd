extends SceneTree
## 1번 설비실(ClaudeServiceDress) 본편 캡처: 방 탐색(main.tscn) 실제 게임 카메라로, 조립 틀마다 가장 가까운 바닥에 플레이어를 세워 찍는다.
##  - svc_<틀>_<n>.png : 설비실 켬
##  - svc_off_<틀>.png : 같은 자리, 설비실 끔 (예전 검은 공간) — 첫 자리만
##  - svc_pair.png     : 첫 자리 끔(좌) · 켬(우)
## powershell -File tools\godot.ps1 wait --resolution 1600x900 -s res://_capture/service_show.gd -- [--seed=3] [--n=6]
const OUT := "res://output/service-machinery-claude/"

var seed_v := 3
var n_shots := 6


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed_v = int(a.substr(7))
		elif a.begins_with("--n="):
			n_shots = int(a.substr(4))
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> Image:
	await _frames(4)
	await RenderingServer.frame_post_draw
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	print("FRAME %s prims=%d draws=%d fps=%.0f" % [name, prims, draws, Engine.get_frames_per_second()])
	var img := root.get_texture().get_image()
	img.save_png(OUT + name)
	return img


func _load(on: bool) -> Main:
	ClaudeServiceDress.enabled = on
	var g := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	g.map_seed = seed_v
	root.add_child(g)
	current_scene = g
	await _frames(20)
	g.player.invuln = 99999.0
	return g


func _freeze(g: Main) -> void:
	for e in get_nodes_in_group("enemies"):
		(e as Node).process_mode = Node.PROCESS_MODE_DISABLED


## 틀 중심에서 가장 가까운 열린 바닥 칸
func _stand(g: Main, at: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var bd := INF
	var c0 := g.map.cell_of(at)
	for dy in range(-12, 13):
		for dx in range(-12, 13):
			var c := c0 + Vector2i(dx, dy)
			if g.map.cell_type(c) != ArenaMap.FLOOR or g.map.is_blocked_cell(c):
				continue
			var p := g.map.world_of(c)
			var dd := p.distance_to(at)
			if dd < bd:
				bd = dd
				best = p
	return best


func _go(g: Main, p: Vector3) -> void:
	g.player.global_position = p + Vector3(0, g.map.height_at(p), 0)
	g.player.velocity = Vector3.ZERO
	g.player.aim_point = p + Vector3(2, 0, -1)
	g.camera.snap(p)
	await _frames(30)
	g.camera.snap(g.player.global_position)
	await _frames(20)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var g := await _load(true)
	_freeze(g)
	var svc := g.map.find_child("ServiceRoom", true, false) as Node3D
	var placed: Array = svc.get_meta("placed") if svc else []
	print("SERVICE placed=%d" % placed.size())
	# 틀 종류마다 하나씩, 그다음 나머지
	var order: Array = []
	var seen := {}
	for p in placed:
		if not seen.has(p[0]):
			seen[p[0]] = true
			order.append(p)
	for p in placed:
		if order.size() >= n_shots:
			break
		if not order.has(p):
			order.append(p)
	var first_pos := Vector3.ZERO
	var on_img: Image
	for i in mini(order.size(), n_shots):
		var at := _stand(g, order[i][1])
		if i == 0:
			first_pos = at
		await _go(g, at)
		var img := await _shot("svc_%s_%d.png" % [order[i][0], i])
		if i == 0:
			on_img = img
		print("SHOT %s at %s (stand %s)" % [order[i][0], order[i][1], at])
	g.queue_free()
	await _frames(5)
	var g2 := await _load(false)
	_freeze(g2)
	await _go(g2, first_pos)
	var off := await _shot("svc_off_%s.png" % (order[0][0] if order.size() > 0 else "none"))
	if on_img:
		var w := off.get_width()
		var h := off.get_height()
		var pair := Image.create(w, h / 2, false, Image.FORMAT_RGBA8)
		var a := off.duplicate() as Image
		var b := on_img.duplicate() as Image
		a.resize(w / 2, h / 2)
		b.resize(w / 2, h / 2)
		a.convert(Image.FORMAT_RGBA8)
		b.convert(Image.FORMAT_RGBA8)
		pair.blit_rect(a, Rect2i(0, 0, w / 2, h / 2), Vector2i.ZERO)
		pair.blit_rect(b, Rect2i(0, 0, w / 2, h / 2), Vector2i(w / 2, 0))
		pair.save_png(OUT + "svc_pair.png")
	ClaudeServiceDress.enabled = true
	print("SERVICE SHOW saved")
	quit()
