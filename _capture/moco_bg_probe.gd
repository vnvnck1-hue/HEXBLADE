extends SceneTree
## mo.co 무드 배경 조정(docs/moco-bg-claude.md) 비교 캡처·측정.
## 같은 seed·카메라에서 전투 없는 화면을 찍고, 조용한 작은 영역(5×5 px)의 화면 sRGB 휘도 근사
## Y = 0.2126R + 0.7152G + 0.0722B (선형 물리 휘도 아님) 를 역할별로 잰다:
##   floor = 통로 바닥 · wall_top = 낮은 벽 블록 윗면 · service = 벽 밖 설비 바닥 · char = 플레이어·적(켜고 끈 차이 픽셀)
## 결과: <tag>.png(화면) · <tag>_marks.png(표본 위치) · <tag>.json (값) · 콘솔 요약.
## powershell -File tools\godot.ps1 wait --resolution 1280x800 -s res://_capture/moco_bg_probe.gd -- --seed=4 --tag=after [--classic] [--bgtone=old] [--dark] [--wide]
##   --dark: 강력 레이저 암전(Main.dramatic(true)) 상태도 찍고 다시 복귀(false) 후 값이 기준과 같은지 확인
const OUT := "res://output/moco-bg-20261004/"


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _grab() -> Image:
	await _frames(6)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	return img


static func _y(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


static func _patch(img: Image, p: Vector2i) -> float:
	var s := 0.0
	var n := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var q := p + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < img.get_width() and q.y < img.get_height():
				s += _y(img.get_pixelv(q))
				n += 1
	return s / maxf(n, 1)


func _run() -> void:
	var tag := "probe"
	var dark := false
	var wide := false
	for a in OS.get_cmdline_user_args():
		if a == "--classic":
			BrawlLook.on = false
		elif a == "--dark":
			dark = true
		elif a == "--wide":
			wide = true
		elif a.begins_with("--tag="):
			tag = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(40)
	var main := current_scene as Main
	main.player.invuln = 9999.0
	main.hud.visible = false
	var c := _frame_spot(main.map, main.player.global_position)
	main.player.global_position = c
	main.camera.snap(c)
	var made: Array[Node3D] = [main.player]
	var spots := [Vector3(-3.2, 0, -1.6), Vector3(3.0, 0, -2.2), Vector3(-2.6, 0, 2.2)]
	var kinds := [Crawler, Turret, TrainingDummy]
	for i in spots.size():
		var e: Enemy = kinds[i].new()
		var pos: Vector3 = main.map.push_out(c + spots[i], 1.0)
		if e is TrainingDummy:
			(e as TrainingDummy).anchor = pos
		main.world.add_child(e)
		e.global_position = pos
		made.append(e)
	await _frames(90)
	for e in made:
		e.process_mode = Node.PROCESS_MODE_DISABLED
	main.process_mode = Node.PROCESS_MODE_DISABLED
	if wide:
		# 넓게: 카메라 거리만 늘린다 (같은 각도·화각)
		var cp: Dictionary = main.camera.p.duplicate()
		cp.offset = (cp.offset as Vector3) * 1.8
		main.camera.p = cp
		main.camera.cur_offset = cp.offset
	main.camera.snap(c)
	var img := await _grab()
	img.save_png(OUT + tag + ".png")
	for id in BrawlLook._pool_mats:
		var pm := (BrawlLook._pool_mats[id] as WeakRef).get_ref() as ShaderMaterial
		if pm:
			var cm := main.camera.get_viewport().get_camera_3d()
			var pp := main.player.global_position
			for off in [Vector3(0,0,0), Vector3(-4,0,0), Vector3(-8,0,0), Vector3(-12,0,0), Vector3(4,0,0), Vector3(8,0,0), Vector3(0,0,-4), Vector3(0,0,-8), Vector3(0,0,-12), Vector3(0,0,3)]:
				var w: Vector3 = pp + off
				var sp := Vector2i(cm.unproject_position(w))
				if Rect2i(Vector2i.ZERO, img.get_size()).has_point(sp):
					print("POOL sample off=", off, " cell=", main.map.cell_type(main.map.cell_of(w)), " Y=", snappedf(_patch(img, sp), 0.001))
			print("POOL dbg player=", main.player.global_position, " pool_pos=", pm.get_shader_parameter("pool_pos"), " on=", pm.get_shader_parameter("pool_on"), " n=", BrawlLook._pool_mats.size())
			break
	for n in made:
		n.visible = false
	var bare := await _grab()
	# 벽 블록·설비 프랍을 숨긴 화면: 설비 바닥 표본이 무언가에 가려졌는지 가린다
	var hid: Array[Node3D] = []
	for gi: GeometryInstance3D in main.map.find_children("*", "GeometryInstance3D", true, false):
		if gi.visible and gi.name != "ServiceFloor" and (gi is MultiMeshInstance3D or gi.get_parent() != main.map):
			gi.visible = false
			hid.append(gi)
	var open_img := await _grab()
	for n in hid:
		n.visible = true
	for n in made:
		n.visible = true
	var cam := main.camera.get_viewport().get_camera_3d()
	var vp := Rect2(Vector2.ZERO, Vector2(img.get_size()))
	var map := main.map
	var samples := {"floor": [], "wall_top": [], "service": []}
	var marks := img.duplicate() as Image
	# 통로 바닥: 플레이어 둘레 칸 중 바닥·평지
	var pc := map.cell_of(c)
	for dy in range(-7, 8):
		for dx in range(-11, 12):
			var cc := pc + Vector2i(dx, dy)
			if map.cell_type(cc) != ArenaMap.FLOOR or absf(map.cell_h(cc)) > 0.01:
				continue
			if map.cell_type(cc + Vector2i(0, 1)) != ArenaMap.FLOOR:   # 카메라 쪽 벽이 가림
				continue
			_try(samples.floor, cam, vp, img, bare, map.world_of(cc) + Vector3(0, 0.0, 0))
	# 벽 윗면 / 설비 바닥: 화면 안의 벽 블록 · 설비 바닥 칸
	var d := ClaudeServiceDress.distances(map)
	for y in ArenaMap.H:
		for x in ArenaMap.W:
			var cc := Vector2i(x, y)
			var i := y * ArenaMap.W + x
			var tall: Dictionary = map.get_meta("claude_tall", {})
			var occd: Dictionary = map.get_meta("claude_occupied", {})
			if map.grid[i] == ArenaMap.VOID and d[i] == 1 and map._near_floor(cc) and not tall.has(cc) and not occd.has(cc):
				var base := map.hgt[i] if not map.hgt.is_empty() else 0.0
				_try(samples.wall_top, cam, vp, img, bare, map.world_of(cc) + Vector3(0, base + _wall_h(map), 0))
			elif map.grid[i] == ArenaMap.VOID and d[i] >= 2 and d[i] <= 4:
				# 벽·프랍을 숨긴 화면과 같은 픽셀 = 아무것도 가리지 않은 설비 바닥 (프랍 그림자도 같이 사라지므로 그늘 진 곳도 빠진다)
				_try(samples.service, cam, vp, img, open_img, map.world_of(cc) + Vector3(0, ClaudeServiceDress.FLOOR_Y, 0))
	# 캐릭터: 켜고 끈 차이가 큰 픽셀
	var ch := 0.0
	var chn := 0
	var edge := 0.0
	var edn := 0
	for py in range(0, img.get_height(), 2):
		for px in range(0, img.get_width(), 2):
			var a := img.get_pixel(px, py)
			var b := bare.get_pixel(px, py)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.12:
				ch += _y(a)
				chn += 1
				edge += absf(_y(a) - _y(b))
				edn += 1
	var res := {"tag": tag, "brawl": BrawlLook.active()}
	for k in samples:
		var arr: Array = samples[k]
		var s := 0.0
		for v in arr:
			s += v[0]
			marks.fill_rect(Rect2i(v[1] - Vector2i(3, 3), Vector2i(7, 7)), {"floor": Color.YELLOW, "wall_top": Color.CYAN, "service": Color.MAGENTA}[k])
		res[k] = s / maxf(arr.size(), 1)
		res[k + "_n"] = arr.size()
	if OS.get_cmdline_user_args().has("--dbgwall"):
		for v in samples.wall_top:
			print("WALL sx=", v[1].x, " Y=", snappedf(v[0], 0.001))
	res.char = ch / maxf(chn, 1)
	res.char_vs_bg = edge / maxf(edn, 1)     # 캐릭터 픽셀이 그 자리 배경과 다른 평균 밝기 차
	res.wall_minus_floor = res.wall_top - res.floor
	res.service_over_floor = res.service / maxf(res.floor, 0.001)
	marks.save_png(OUT + tag + "_marks.png")
	if dark:
		main.process_mode = Node.PROCESS_MODE_INHERIT
		main.dramatic(true)
		await create_timer(0.4).timeout
		var di := await _grab()
		di.save_png(OUT + tag + "_dark.png")
		res.dark_floor = _avg(di, samples.floor)
		main.dramatic(false)
		await create_timer(1.0).timeout
		main.process_mode = Node.PROCESS_MODE_DISABLED
		var ri := await _grab()
		ri.save_png(OUT + tag + "_restored.png")
		res.restored_floor = _avg(ri, samples.floor)
		res.env_glow = main.env.glow_intensity
		res.env_amb = main.env.ambient_light_energy
		res.sun_e = main.sun.light_energy
	var f := FileAccess.open(OUT + tag + ".json", FileAccess.WRITE)
	f.store_string(JSON.stringify(res, "  "))
	f.close()
	print("MOCO BG PROBE ", JSON.stringify(res))
	quit()


static func _avg(img: Image, arr: Array) -> float:
	var s := 0.0
	for v in arr:
		s += _patch(img, v[1])
	return s / maxf(arr.size(), 1)


## 바닥·낮은 벽·설비 바닥이 한 화면에 고르게 보이는 평지 칸 (시작 방에서 가까운 것부터)
static func _frame_spot(map: ArenaMap, near: Vector3) -> Vector3:
	var d := ClaudeServiceDress.distances(map)
	var tall: Dictionary = map.get_meta("claude_tall", {})
	var best := near
	var best_s := -1.0
	var pc := map.cell_of(near)
	for dy in range(-40, 41, 2):
		for dx in range(-40, 41, 2):
			var t := pc + Vector2i(dx, dy)
			if map.cell_type(t) != ArenaMap.FLOOR or absf(map.cell_h(t)) > 0.01:
				continue
			var fl := 0
			var wl := 0
			var sv := 0
			for oy in range(-6, 7):
				for ox in range(-10, 11):
					var q := t + Vector2i(ox, oy)
					if q.x < 0 or q.y < 0 or q.x >= ArenaMap.W or q.y >= ArenaMap.H:
						continue
					var i := q.y * ArenaMap.W + q.x
					if map.grid[i] == ArenaMap.FLOOR:
						fl += 1
					elif d[i] == 1 and not tall.has(q):
						wl += 1
					elif d[i] >= 2 and d[i] <= 5:
						sv += 1
			var s := minf(fl, 120) + minf(wl, 30) * 2.0 + minf(sv, 60) * 1.5 - Vector2(dx, dy).length() * 0.5
			if s > best_s:
				best_s = s
				best = map.world_of(t)
	return best


## 낮은 벽 블록 윗면 높이 (블록 메시 AABB 꼭대기)
static func _wall_h(_map: ArenaMap) -> float:
	var m := ClaudeBgDress.block_mesh("wall")
	var bb := m.get_aabb()
	return bb.end.y - 0.02


func _try(list: Array, cam: Camera3D, vp: Rect2, img: Image, bare: Image, w: Vector3) -> void:
	if cam.is_position_behind(w):
		return
	var sp := cam.unproject_position(w)
	if not vp.grow(-12).has_point(sp):
		return
	var p := Vector2i(sp)
	# 캐릭터가 덮은 곳 제외
	var a := img.get_pixelv(p)
	var b := bare.get_pixelv(p)
	if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.05:
		return
	list.append([_patch(img, p), p])
