extends SceneTree
## Run with: Godot --headless --path . -s tests/claude_service_check.gd
## 1번 설비실 프랍 5종(Claude, docs/service-machinery-claude.md)과 본편 적용(ClaudeServiceDress)을 확인한다.
##  1. GLB 5종: 메시 하나가 모델 원점에 변환 없이, 크기·피벗·정면(-Z)이 설계 계약대로, 구운 텍스처 · 상태등 발광 마스크(S01·S02·S05).
##  2. 배관 접속: S03 끝단(±1.0, 축 X) · S04 끝단(A -X · B +Z, 모서리점에서 0.75) · S02 포트(정면 0.80) 가 같은 높이 0.30 의 축에 맞물린다.
##  3. 본편(main.tscn seed 3): 설비 바닥 · 5종 모두 놓임 · 모든 프랍이 벽 밖 설비 칸(거리 DMIN~DMAX)의 FLOOR_Y 위,
##     프랍 윗면이 벽 윗면(0.8)보다 낮음 · 프랍끼리(벽면 라인 제외) 같은 칸을 겹쳐 쓰지 않음 · 상태등 재질 노랑/민트.
##  4. 판정 불변: 설비실을 꺼도 충돌 상자 수 · 막힌 칸이 같다. 끄면(--service=off) ServiceRoom 없음.

const EPS := 0.01
const HEIGHT := {"vent": 1.0, "tank": 1.65, "pipe": 0.6, "elbow": 0.6, "column": 1.6}

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _near(a: Vector3, b: Vector3, eps := EPS) -> bool:
	return (a - b).abs().x < eps and (a - b).abs().y < eps and (a - b).abs().z < eps


func _pt(scene: Node, name: String) -> Vector3:
	var n := scene.find_child(name, true, false) as Node3D
	return n.position if n else Vector3(INF, INF, INF)


func _run() -> void:
	BrawlLook.on = false
	# ── 1. GLB 5종
	var spec := {
		"vent": [Vector3(-0.75, 0, -0.75), Vector3(0.75, 1.0, 0.75)],
		"tank": [Vector3(-0.6, 0, -0.812), Vector3(0.6, 1.65, 0.6)],
		"pipe": [Vector3(-1.003, 0, -0.3), Vector3(1.003, 0.6, 0.3)],
		"elbow": [Vector3(-0.753, 0, -0.3), Vector3(0.3, 0.6, 0.753)],
		"column": [Vector3(-0.251, 0, -0.251), Vector3(0.251, 1.6, 0.251)],
	}
	var scenes := {}
	for kind in spec:
		var ps := load(ClaudeServiceDress.GLB[kind]) as PackedScene
		_check(ps != null, "%s GLB 불러오기" % kind)
		if ps == null:
			continue
		var n := ps.instantiate() as Node3D
		scenes[kind] = n
		var mis := n.find_children("*", "MeshInstance3D", true, false)
		_check(mis.size() == 1, "%s 메시 하나 (%d)" % [kind, mis.size()])
		var mi := mis[0] as MeshInstance3D
		_check(mi.transform.is_equal_approx(Transform3D.IDENTITY), "%s 메시 노드에 회전·이동 없음 (MultiMesh 가 메시만 쓴다)" % kind)
		var bb := mi.get_aabb()
		var want: Array = spec[kind]
		_check(_near(bb.position, want[0], 0.02) and _near(bb.end, want[1], 0.02), "%s 크기·피벗 %s ~ %s (원하는 값 %s ~ %s)" % [kind, bb.position, bb.end, want[0], want[1]])
		var m := mi.mesh.surface_get_material(0) as StandardMaterial3D
		_check(m != null and m.albedo_texture != null and m.metallic < 0.01, "%s 구운 베이스컬러 텍스처 · 비금속" % kind)
		if kind in ["vent", "tank", "column"]:
			_check(m != null and m.emission_texture != null, "%s 상태등 발광 마스크 텍스처" % kind)
			var lm := ClaudeServiceDress.lamp_material(kind, true) as StandardMaterial3D
			_check(lm.emission_enabled and lm.emission.is_equal_approx(ClaudeServiceDress.LAMP_MINT) and lm != ClaudeServiceDress.lamp_material(kind, false),
					"%s 상태등 재질 변형 노랑/민트" % kind)
	# ── 2. 배관 접속
	if scenes.size() == 5:
		var pa := _pt(scenes.pipe, "pt_end_a")
		var pb := _pt(scenes.pipe, "pt_end_b")
		_check(_near(pa, Vector3(-1, 0.3, 0)) and _near(pb, Vector3(1, 0.3, 0)), "S03 끝단 (±1.0, 0.30, 0) %s %s" % [pa, pb])
		var ea := _pt(scenes.elbow, "pt_end_a")
		var eb := _pt(scenes.elbow, "pt_end_b")
		_check(_near(ea, Vector3(-0.75, 0.3, 0)) and _near(eb, Vector3(0, 0.3, 0.75)), "S04 끝단 A (-0.75, 0.3, 0) · B (0, 0.3, 0.75) %s %s" % [ea, eb])
		# S03 오른쪽 끝에 S04 를 모서리점 x=1.75 로 놓으면 끝단이 정확히 겹친다
		_check(_near(pb, ea + Vector3(1.75, 0, 0)), "S03 끝단 B = S04 끝단 A (모서리점을 0.75 앞에)")
		var tp := _pt(scenes.tank, "pt_port")
		_check(_near(tp, Vector3(0, 0.3, -0.8)), "S02 포트 정면(-Z) 0.80 · 높이 0.30 %s" % tp)
		# 0.25배 라인: 지름 0.125
		_check(absf(0.6 * 0.25 - 0.15) < 1e-6, "벽면 라인 = S03 0.25배 균일 축소 (밴드 외경 0.15)")
	for n in scenes.values():
		n.free()
	# ── 3·4. 본편
	var on := await _main_game(true)
	var off := await _main_game(false)
	_check(on.shapes == off.shapes and on.blocked == off.blocked, "설비실 켜고 끄기에 충돌 상자 %d/%d · 막힌 칸 %d/%d 같음" % [on.shapes, off.shapes, on.blocked, off.blocked])
	print("RESULT claude_service_check fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _main_game(enabled: bool) -> Dictionary:
	ClaudeServiceDress.enabled = enabled
	var g := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	g.map_seed = 3
	root.add_child(g)
	await _frames(3)
	var map := g.map
	var out := {"shapes": map.find_children("*", "CollisionShape3D", true, false).size(), "blocked": 0}
	for y in ArenaMap.H:
		for x in ArenaMap.W:
			if map.is_blocked_cell(Vector2i(x, y)):
				out.blocked += 1
	var svc := map.find_child("ServiceRoom", true, false) as Node3D
	if not enabled:
		_check(svc == null, "끄면(--service=off) 설비실 없음")
		g.queue_free()
		await _frames(2)
		ClaudeServiceDress.enabled = true
		return out
	_check(svc != null, "본편에 ServiceRoom (seed 3)")
	if svc == null:
		g.queue_free()
		return out
	var d := ClaudeServiceDress.distances(map)
	var fl := svc.get_node("ServiceFloor") as MeshInstance3D
	_check(fl.mesh != null and int(fl.get_meta("cells")) > 500 and absf((fl.global_transform * fl.get_aabb()).position.y - ClaudeServiceDress.FLOOR_Y) < 0.001,
			"설비 바닥 %d칸 · 높이 %.1f" % [int(fl.get_meta("cells")), ClaudeServiceDress.FLOOR_Y])
	var count := {}
	var in_band := true
	var on_floor := true
	var below_wall := true
	var bad := ""
	var cells := {}
	var overlap := 0
	for mmi in svc.get_children():
		if not mmi is MultiMeshInstance3D:
			continue
		var key: String = mmi.get_meta("claude_service")
		var kind := key.get_slice(":", 0)
		var line := key == "pipe:line"
		count[key] = count.get(key, 0) + (mmi.get_meta("claude_spots") as Array).size()
		for xf: Transform3D in mmi.get_meta("claude_spots"):
			var c := map.cell_of(xf.origin)
			var dv := d[c.y * ArenaMap.W + c.x]
			if dv < ClaudeServiceDress.DMIN or dv > ClaudeServiceDress.DMAX:
				in_band = false
				bad = "%s %s 거리 %d" % [key, xf.origin, dv]
			if not line and absf(xf.origin.y - ClaudeServiceDress.FLOOR_Y) > 0.001:
				on_floor = false
			var top: float = xf.origin.y + HEIGHT[kind] * xf.basis.get_scale().y
			if top > ArenaMap.WALL_H - 0.1:
				below_wall = false
				bad = "%s 윗면 %.2f" % [key, top]
			if not line and kind != "pipe" and kind != "elbow":
				if cells.has(c):
					overlap += 1
				cells[c] = true
	_check(in_band, "모든 프랍이 벽 밖 설비 칸 (거리 %d~%d) %s" % [ClaudeServiceDress.DMIN, ClaudeServiceDress.DMAX, bad])
	_check(on_floor, "프랍 피벗이 설비 바닥 높이")
	_check(below_wall, "프랍 윗면이 벽 윗면 %.1f 보다 0.1 이상 낮음 (플레이어를 가리지 않게) %s" % [ArenaMap.WALL_H, bad])
	_check(overlap == 0, "환기 장치·탱크·기둥이 같은 칸을 겹쳐 쓰지 않음 (%d)" % overlap)
	for k in ["vent", "tank", "pipe", "column", "column:mint", "pipe:line"]:
		_check(count.get(k, 0) > 0, "%s %d개" % [k, count.get(k, 0)])
	var placed: Array = svc.get_meta("placed")
	var names := {}
	for p in placed:
		names[p[0]] = true
	_check(names.size() >= 4, "조립 틀 %d곳 · 종류 %s" % [placed.size(), names.keys()])
	g.queue_free()
	await _frames(2)
	return out
