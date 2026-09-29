class_name RunMain
extends Main
## 섹터 런의 방 하나 (Main 상속). 통로 없는 단일 방을 만들고, 칸 종류에 따라
## 전투(정리하면 포탈) · 정예(강화 전투) · 정비(수리 발판) · 출발(바로 포탈) 을 진행한다.
## 포탈은 방 위쪽(화면 안쪽)에, 입장 지점은 아래쪽에 둔다. 다음 칸 순서(지도 위→아래)는 포탈 왼쪽→오른쪽.

const G := preload("res://scripts/sector_graph.gd")
const PORTAL_GAP := 3.4
const HOLD_TIME := 1.1       # 워프 직후 전투 시작까지의 여유
const REST_HEAL := 3

var nd: Dictionary
var portals: Array[SectorPortal] = []
var portals_open := false
var rest_pad: Node3D
var rest_used := false
var entry := Vector3.ZERO
var bot_pick := -1
var marks: Control


func _ready() -> void:
	var run := _run()
	if not run.active or run.over:
		# 이 씬으로 바로 시작했을 때: 새 런을 연다
		_parse_args()
		run.begin(map_seed if map_seed >= 0 else randi())
	nd = run.node()
	process_priority = 100   # HUD 보다 뒤에 돌아 상단 문구를 덮어쓴다
	super._ready()
	if capture_dir != "":
		# 검증 캡처: 칸마다 하위 폴더에 따로 저장 (씬이 바뀌면 프레임 번호가 처음부터 다시 시작하므로)
		capture_dir = "%s/s%d_%02d" % [capture_dir, run.sector, run.path.size()]
		DirAccess.make_dir_recursive_absolute(capture_dir)
	player.hp = run.hp
	var r: Dictionary = map.rooms[map.start_room]
	r.difficulty = nd.difficulty
	if nd.kind in [G.Kind.COMBAT, G.Kind.ELITE]:
		r.state = "hold"
	entry = _entry_spot()
	player.global_position = entry
	camera.snap(player.global_position)
	# 방 미니맵 자리에 섹터 지도를 그린다
	hud.minimap.draw.disconnect(hud._draw_minimap)
	hud.minimap.draw.connect(_draw_sector_mini)
	hud.minimap.custom_minimum_size = Vector2(228, 150)
	_build_portals()
	marks = Control.new()
	marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.draw.connect(_draw_portal_marks)
	hud.root.add_child(marks)
	if OS.get_cmdline_user_args().has("--showmap"):
		run.map_view.want = true
	match nd.kind:
		G.Kind.START:
			hud.banner("SECTOR %d" % (run.sector + 1), Color(0.7, 0.95, 1.0), "%s  ·  포탈을 골라 %s 까지 돌파하라  ·  Tab 섹터 지도" % [run.sector_name(), run.boss_name()])
			_open_portals(1.0)
			if run.sector == 0 and not capture_mode:
				run.map_view.want = true
		G.Kind.REST:
			hud.banner("정비 구역", G.KIND_COLORS[G.Kind.REST], "수리 발판에 올라서면 장갑 +%d" % REST_HEAL)
			_build_rest_pad()
			_open_portals(1.2)
		G.Kind.ELITE:
			hud.banner("정예 구역", G.KIND_COLORS[G.Kind.ELITE], "강적 출현 · 단계 %d" % nd.level)
		_:
			hud.banner("전투 구역", G.KIND_COLORS[G.Kind.COMBAT], "%s · 단계 %d" % [ArenaMap.SHAPE_NAMES[r.shape], nd.level])


func _run() -> Node:
	return get_node("/root/Run")


func _build_arena() -> void:
	map = ArenaMap.new()
	world.add_child(map)
	var combat: bool = nd.kind in [G.Kind.COMBAT, G.Kind.ELITE]
	# 출발·정비 구역은 엄폐물 없는 넓은 홀로 고정
	if combat:
		map.generate_single(nd.seed, nd.shape, true)
	else:
		map.generate_single(nd.seed, ArenaMap.Shape.RECT, false, Vector2i(17, 12))
	map.build()


func combat_rooms() -> int:
	return 1


func _activate_room(id: int) -> void:
	super._activate_room(id)
	var title: String = "정예 구역" if nd.kind == G.Kind.ELITE else ArenaMap.SHAPE_NAMES[map.rooms[id].shape]
	hud.banner(title, G.KIND_COLORS[nd.kind], "적 %d기 · 모두 격파하면 출구 포탈이 열립니다" % room_total)


## 방 정리: 기본 규칙(방마다 체력 +1)은 쓰지 않는다. 회복은 정비 칸에서.
func _clear_room() -> void:
	var id := active_room
	map.rooms[id].state = "cleared"
	active_room = -1
	rooms_cleared += 1
	var run := _run()
	run.coins += nd.coins
	print("ROOM_CLEAR node=%d level=%d t=%.1f hp=%d coins=%d" % [nd.id, nd.level, time, player.hp, run.coins])
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		FX.flash(b.position, Pal.E_BULLETS[2], 0.4, 0.1)
		b.queue_free()
	Sfx.play("charged", 0.0, 0.0)
	FX.shockwave(player.global_position, Pal.CYAN, 4.0, 0.5)
	hud.banner("AREA CLEAR", Color(0.6, 0.95, 1.0), "코인 +%d  ·  출구 포탈이 열립니다" % nd.coins)
	_open_portals(0.9)


func _physics_process(dt: float) -> void:
	if map.rooms[map.start_room].state == "hold" and time >= HOLD_TIME:
		map.rooms[map.start_room].state = "idle"
	super._physics_process(dt)
	if rest_pad and not rest_used and player.alive:
		var d := player.global_position - rest_pad.global_position
		d.y = 0
		if d.length() < 1.3:
			_use_rest()


func _process(dt: float) -> void:
	super._process(dt)
	var run := _run()
	hud.wave_label.text = "SECTOR %d  ·  단계 %d / %d" % [run.sector + 1, nd.level, G.LEVELS + 1]
	if active_room >= 0:
		hud.count_label.text = "ENEMIES  %d" % enemies_left()
	elif portals_open:
		hud.count_label.text = "포탈을 골라 들어가세요"
	else:
		hud.count_label.text = "코인 %d" % run.coins
	marks.queue_redraw()


## 화면 밖의 열린 포탈 방향을 가장자리 화살표로 알려 준다
func _draw_portal_marks() -> void:
	var sz := marks.size
	var margin := 46.0
	for p in portals:
		if not p.is_open:
			continue
		var wp := p.global_position + Vector3(0, SectorPortal.CENTER_Y, 0)
		var sp := camera.unproject_position(wp)
		var behind := camera.is_position_behind(wp)
		var inside := not behind and sp.x > margin and sp.y > margin and sp.x < sz.x - margin and sp.y < sz.y - margin
		if inside:
			continue
		var c := sz * 0.5
		var d := (sp - c) * (-1.0 if behind else 1.0)
		if d.length() < 1.0:
			continue
		d = d.normalized()
		# 화면 테두리와 만나는 점
		var k := minf((sz.x * 0.5 - margin) / maxf(absf(d.x), 0.001), (sz.y * 0.5 - margin) / maxf(absf(d.y), 0.001))
		var at := c + d * k
		var n := Vector2(-d.y, d.x)
		var pulse := 1.0 + 0.15 * sin(time * 8.0)
		var tip := at + d * 16.0 * pulse
		marks.draw_colored_polygon(PackedVector2Array([tip, at - d * 6.0 + n * 13.0, at - d * 6.0 - n * 13.0]), p.color)
		var hs := G.hex_points(at - d * 26.0, 13.0)
		marks.draw_colored_polygon(hs, Color(0.03, 0.03, 0.08, 0.8))
		hs.append(hs[0])
		marks.draw_polyline(hs, p.color, 2.0, true)
		SectorMapView._icon(marks, at - d * 26.0, 5.5, p.kind, p.color)


func _draw_sector_mini() -> void:
	var c := hud.minimap
	var sz := c.size
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.03, 0.08, 0.72))
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.4, 0.4, 0.7, 0.5), false, 1.0)
	SectorMapView.paint(c, Rect2(Vector2(6, 6), sz - Vector2(12, 22)), _run(), time, hud.font, false)
	c.draw_string(hud.font, Vector2(8, sz.y - 5), "Tab  섹터 지도", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.65, 0.9))


# ── 포탈 ────────────────────────────────────────────────

## 입장 지점: 방 아래쪽(+Z) 가운데 근처의 빈 칸
func _entry_spot() -> Vector3:
	var spots := map.open_spots(map.start_room)
	var zmax := -1e9
	for p in spots:
		zmax = maxf(zmax, p.z)
	var cx := map.room_center_world(map.start_room).x
	var best := map.room_center_world(map.start_room)
	var bs := 1e9
	for p in spots:
		if p.z < zmax - 3.5:
			continue
		var s := absf(p.x - cx) + (zmax - p.z) * 0.3
		if s < bs:
			bs = s
			best = p
	return best


## 포탈 자리: 방 위쪽(-Z)부터 서로 PORTAL_GAP 이상 떨어진 칸을 고른 뒤 왼쪽→오른쪽으로 정렬
func _portal_spots(k: int) -> Array[Vector3]:
	var spots := map.open_spots(map.start_room)
	spots.sort_custom(func(a, b): return a.z < b.z)
	var out: Array[Vector3] = []
	var gap := PORTAL_GAP
	while out.size() < k and gap > 1.6:
		out.clear()
		for p in spots:
			if p.distance_to(entry) < 5.0:
				continue
			var ok := true
			for q in out:
				if q.distance_to(p) < gap:
					ok = false
					break
			if ok:
				out.append(p)
				if out.size() >= k:
					break
		gap -= 0.4
	out.sort_custom(func(a, b): return a.x < b.x)
	return out


func _build_portals() -> void:
	var run := _run()
	var nexts: Array = run.next_nodes()
	var spots := _portal_spots(nexts.size())
	for i in mini(nexts.size(), spots.size()):
		var nx: Dictionary = nexts[i]
		var desc: Array = run.describe(nx)
		var p := SectorPortal.new()
		p.setup(nx.id, nx.kind, desc[0], desc[1])
		world.add_child(p)
		p.global_position = spots[i]
		p.entered.connect(_on_portal_entered)
		portals.append(p)


func _open_portals(delay: float) -> void:
	if portals_open:
		return
	portals_open = true
	for i in portals.size():
		portals[i].open(delay + i * 0.18)


func _on_portal_entered(p: SectorPortal) -> void:
	for q in portals:
		if q != p:
			q.close()
	player.invuln = 999.0
	FX.shockwave(p.global_position + Vector3(0, 0.2, 0), p.color, 3.5, 0.4)
	FX.vortex(p.global_position + Vector3(0, SectorPortal.CENTER_Y, 0), Basis(), p.color)
	shake(0.3)
	_run().enter_node(p.node_id)


# ── 정비 ────────────────────────────────────────────────

func _build_rest_pad() -> void:
	rest_pad = Node3D.new()
	world.add_child(rest_pad)
	rest_pad.global_position = map.room_center_world(map.start_room)
	var cm := CylinderMesh.new()
	cm.radial_segments = 6
	cm.top_radius = 1.1
	cm.bottom_radius = 1.2
	cm.height = 0.1
	var base := MeshInstance3D.new()
	base.mesh = cm
	base.material_override = Pal.lit(Color(0.12, 0.2, 0.18))
	base.position.y = 0.05
	rest_pad.add_child(base)
	var t := TorusMesh.new()
	t.inner_radius = 0.85
	t.outer_radius = 0.98
	t.ring_segments = 6
	t.rings = 6
	var ring := Pal.flat_mesh(t, G.KIND_COLORS[G.Kind.REST], 1.8)
	ring.name = "Ring"
	ring.position.y = 0.12
	ring.scale = Vector3(1, 0.3, 1)
	rest_pad.add_child(ring)
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.22, 0.22)
	for k in 2:
		var bar := Pal.flat_mesh(bm, G.KIND_COLORS[G.Kind.REST], 2.0)
		bar.position.y = 1.3
		bar.rotation.z = PI / 2.0 * k
		bar.name = "Cross%d" % k
		rest_pad.add_child(bar)
	var tw := rest_pad.create_tween().set_loops()
	tw.tween_property(rest_pad, "rotation:y", TAU, 4.0).from(0.0)
	var l := OmniLight3D.new()
	l.light_color = G.KIND_COLORS[G.Kind.REST]
	l.light_energy = 1.6
	l.omni_range = 4.5
	l.position.y = 1.2
	rest_pad.add_child(l)


func _use_rest() -> void:
	rest_used = true
	var before := player.hp
	player.hp = mini(Player.MAX_HP, player.hp + REST_HEAL)
	FX.shockwave(rest_pad.global_position + Vector3(0, 0.15, 0), G.KIND_COLORS[G.Kind.REST], 3.0, 0.5)
	FX.sparks(player.global_position + Vector3(0, 0.8, 0), 18, [G.KIND_COLORS[G.Kind.REST], Color.WHITE], 5.0, 0.6, -6.0, 0.07)
	Sfx.play("charged", 0.0, 0.0)
	hud.banner("REPAIRED", G.KIND_COLORS[G.Kind.REST], "장갑 %d → %d" % [before, player.hp])
	# 쓴 발판은 불이 꺼진다
	for c in rest_pad.get_children():
		if String(c.name) == "Ring" or String(c.name).begins_with("Cross"):
			(c as MeshInstance3D).set_instance_shader_parameter("energy", 0.25)
		elif c is OmniLight3D:
			(c as OmniLight3D).light_energy = 0.2


# ── 자동 플레이 (검증용) ─────────────────────────────────

func bot_input(p: Player) -> Dictionary:
	var out := super.bot_input(p)
	if active_room >= 0:
		return out
	var target := Vector3.INF
	if rest_pad and not rest_used:
		target = rest_pad.global_position
	elif portals_open and portals.size() > 0 and portals[0].is_open:
		if bot_pick < 0:
			var arg_pick := -1
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--pick="):
					arg_pick = int(a.substr(7))
			bot_pick = (arg_pick if arg_pick >= 0 else randi()) % portals.size()
		target = portals[bot_pick].global_position
	if target == Vector3.INF:
		return out
	# 엄폐물을 돌아가도록 격자 경로의 다음 경유점을 따라간다
	bot_path_t -= get_physics_process_delta_time()
	if bot_path_t <= 0.0 or bot_path.is_empty():
		bot_path_t = 0.5
		bot_path = map.find_path(p.global_position, target)
	while bot_path.size() > 1 and bot_path[0].distance_to(p.global_position) < 1.1:
		bot_path.pop_front()
	var wp: Vector3 = bot_path[mini(1, bot_path.size() - 1)] if bot_path.size() > 1 else target
	var d := wp - p.global_position
	d.y = 0
	out.move = d.normalized() if d.length() > 0.3 else Vector3.ZERO
	out.aim = p.global_position + d.normalized() * 4.0 + Vector3(0, 0.95, 0)
	out.fire = false
	out.boost = false
	out.dash = false
	return out
