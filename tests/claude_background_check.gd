extends SceneTree
## Run with: Godot --headless --path . -s tests/claude_background_check.gd
## 배경 첫 제작 (Claude 판, docs/background-first-pass-claude.md) 을 확인한다.
##  1. GLB 4종(F01 · W01 · A01 · A02)이 열리고, 재질이 구운 베이스컬러 텍스처를 실제로 가진다 (단색 재질 아님).
##  2. 축·크기·피벗: 설계 계약(F01 X0~2 Y-0.2~0 Z0~2 · W01 X0~2 Y0~3 Z0~0.25 · A01 중심 2×1×0.75 · A02 중심 1×2×0.5).
##  3. 하위 메시: A01 body/top/drawers · A02 body/door_upper/door_lower (문 원점은 경첩 쪽 -X).
##  4. 시험 씬: 바닥 16장이 8×8m 를 빈틈·겹침 없이 덮고 윗면이 Y=0, 모든 타일이 셰이더 재질 하나를 공유한다.
##  5. ㄱ자 벽 8장: 뒤·왼쪽 벽이 서로 파고들지 않고 모서리를 빈틈없이 닫는다. 벽 정면이 방 안쪽.
##  6. 작업대·수납장: 벽에서 0.05m 띄워 방 안에 있고, 그 칸은 이동·총알 판정에서 막힌다.
##  7. 본편 적용(ClaudeBgDress): main.tscn 의 바닥이 모두 Claude 바닥 셰이더, 막힌 칸이 낮은 W01 블록·3m 벽·벽감으로 빈틈없이 덮이고,
##     3m 벽 뒤에는 바닥이 없으며, 벽감 작업대·수납장은 벽 칸(막힘)에 선다. 끄면(--bg=old) 예전 그대로.

const EPS := 0.006

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


## 노드 아래 모든 메시의 월드 AABB
func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
		var b := mi.global_transform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _near(a: Vector3, b: Vector3) -> bool:
	return (a - b).abs().x < EPS and (a - b).abs().y < EPS and (a - b).abs().z < EPS


func _run() -> void:
	# 배경 재질 자체를 본다 — 브롤 룩(기본 켜짐, 재질을 바꿔 끼움)은 끈다
	BrawlLook.on = false
	var spec := {
		"f01": [Vector3(0, -0.2, 0), Vector3(2, 0, 2)],
		"w01": [Vector3(0, 0, 0), Vector3(2, 3, 0.25)],
		"a01": [Vector3(-1, 0, -0.375), Vector3(1, 1, 0.375)],
		"a02": [Vector3(-0.5, 0, -0.25), Vector3(0.5, 2, 0.25)],
	}
	for key in spec:
		var ps := load(ClaudeBgMain.GLB[key]) as PackedScene
		_check(ps != null, "%s GLB 불러오기" % key)
		if ps == null:
			continue
		var n := ps.instantiate() as Node3D
		root.add_child(n)
		await _frames(1)
		var b := _aabb(n)
		_check(_near(b.position, spec[key][0]) and _near(b.end, spec[key][1]), "%s 크기·피벗 %s ~ %s" % [key, b.position, b.end])
		var tex_ok := true
		var tex_px := 0
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			for s in mi.mesh.get_surface_count():
				var m := mi.mesh.surface_get_material(s) as BaseMaterial3D
				if m == null or m.albedo_texture == null:
					tex_ok = false
				else:
					tex_px = maxi(tex_px, m.albedo_texture.get_width())
					tex_ok = tex_ok and m.metallic < 0.05 and m.roughness > 0.7
		_check(tex_ok and tex_px >= 1024, "%s 재질 = 구운 베이스컬러 텍스처 %dpx · 비금속 · 거친 면" % [key, tex_px])
		if key == "a01":
			_check(n.get_node_or_null("body/top") != null and n.get_node_or_null("body/drawers") != null, "A01 하위 메시 body/top · body/drawers")
		if key == "a02":
			var up := n.get_node_or_null("body/door_upper") as Node3D
			var lo := n.get_node_or_null("body/door_lower") as Node3D
			_check(up != null and lo != null, "A02 하위 메시 body/door_upper · body/door_lower")
			if up and lo:
				_check(up.global_position.x < -0.35 and up.global_position.y > lo.global_position.y and up.global_position.z < -0.2,
					"A02 문 원점 = 왼쪽 경첩 · 정면(-Z) 쪽 %s" % up.global_position)
		n.queue_free()

	# ── 시험 씬
	var main := (load("res://scenes/claude_background_first_pass.tscn") as PackedScene).instantiate() as ClaudeBgMain
	root.add_child(main)
	await _frames(4)
	var floors: Array[Node3D] = []
	var walls: Array[Node3D] = []
	for c in main.bg.get_children():
		if c.name.begins_with("F01"):
			floors.append(c)
		elif c.name.begins_with("W01"):
			walls.append(c)
	_check(floors.size() == 16, "바닥 F01 16장 (%d)" % floors.size())
	var area := 0.0
	var overlap := 0.0
	var shared := true
	var top_ok := true
	for i in floors.size():
		var a := _aabb(floors[i])
		area += a.size.x * a.size.z
		top_ok = top_ok and absf(a.end.y) < EPS
		for j in range(i + 1, floors.size()):
			var b := _aabb(floors[j])
			var ix := minf(a.end.x, b.end.x) - maxf(a.position.x, b.position.x)
			var iz := minf(a.end.z, b.end.z) - maxf(a.position.z, b.position.z)
			if ix > EPS and iz > EPS:
				overlap += ix * iz
		for mi: MeshInstance3D in floors[i].find_children("*", "MeshInstance3D", true, false):
			shared = shared and mi.material_override == main.floor_mat and main.floor_mat != null
	var fb := _aabb(main.bg.get_node("F01_0_0") as Node3D)
	for f in floors:
		fb = fb.merge(_aabb(f))
	_check(absf(area - 64.0) < 0.05 and overlap < 0.001, "바닥 면적 %.2fm² · 겹침 %.3fm²" % [area, overlap])
	_check(_near(fb.position, Vector3(-4, -0.2, -4)) and _near(fb.end, Vector3(4, 0, 4)), "바닥 범위 %s ~ %s" % [fb.position, fb.end])
	_check(top_ok, "바닥 윗면 Y=0")
	_check(shared and main.floor_mat.get_shader_parameter("albedo_tex") != null, "바닥 16장이 월드 위상 셰이더 재질 하나를 공유 · 텍스처 연결")

	_check(walls.size() == 8, "벽 W01 8장 (%d)" % walls.size())
	var back := AABB()
	var left := AABB()
	var bi := 0
	var li := 0
	var wall_overlap := 0.0
	for w in walls:
		var a := _aabb(w)
		if w.name.begins_with("W01_back"):
			back = a if bi == 0 else back.merge(a)
			bi += 1
		else:
			left = a if li == 0 else left.merge(a)
			li += 1
		for w2 in walls:
			if w2 == w:
				continue
			var b := _aabb(w2)
			var inter := a.intersection(b)
			if inter.size.x > EPS and inter.size.y > EPS and inter.size.z > EPS:
				wall_overlap += inter.get_volume()
	_check(_near(back.position, Vector3(-4.25, 0, -4.25)) and _near(back.end, Vector3(3.75, 3, -4)), "뒤 벽 범위 %s ~ %s (모서리 소유)" % [back.position, back.end])
	_check(_near(left.position, Vector3(-4.25, 0, -4)) and _near(left.end, Vector3(-4, 3, 4)), "왼쪽 벽 범위 %s ~ %s" % [left.position, left.end])
	_check(wall_overlap < 0.0001, "벽끼리 관통 없음 (겹침 부피 %.5f)" % wall_overlap)
	var bw := main.bg.get_node("W01_back_0") as Node3D
	var lw := main.bg.get_node("W01_left_0") as Node3D
	_check((bw.global_basis * Vector3(0, 0, -1)).dot(Vector3(0, 0, 1)) > 0.99 and (lw.global_basis * Vector3(0, 0, -1)).dot(Vector3(1, 0, 0)) > 0.99,
		"벽 정면(-Z)이 방 안쪽을 본다")

	var bench := _aabb(main.bg.get_node("A01") as Node3D)
	var locker := _aabb(main.bg.get_node("A02") as Node3D)
	_check(absf(bench.position.z - (-4.0 + 0.05)) < EPS and absf(locker.position.z - (-4.0 + 0.05)) < EPS, "프랍 뒷면이 벽에서 0.05m (작업대 %.3f · 수납장 %.3f)" % [bench.position.z, locker.position.z])
	_check(bench.position.x > -4.0 and bench.end.x < 4.0 and locker.position.x > -4.0 and locker.end.x < 4.0 and absf(bench.position.y) < EPS and absf(locker.position.y) < EPS,
		"프랍이 방 안 · 바닥 접지")
	_check(bench.intersection(locker).get_volume() < 0.0001, "작업대와 수납장이 겹치지 않음")
	_check(main.is_blocked(bench.get_center()) and main.is_blocked(locker.get_center()) and not main.is_blocked(Vector3(0, 0, 0)), "프랍 칸은 막힘 · 방 가운데는 열림")
	var pb := main.player.global_position
	_check(absf(pb.x) < 4.0 and absf(pb.z) < 4.0 and not main.is_blocked(pb), "플레이어가 방 안 빈 칸에서 시작 %s" % pb)

	main.queue_free()
	await _frames(2)

	# ── 본편 적용
	await _main_game(true)
	await _main_game(false)
	ClaudeBgDress.enabled = true
	print("RESULT  %s  (%d fail)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)


func _main_game(on: bool) -> void:
	ClaudeBgDress.enabled = on
	var g := (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
	g.map_seed = 3
	root.add_child(g)
	await _frames(3)
	var map := g.map
	var floors := 0
	var claude_floors := 0
	var old_walls_hidden := true
	var seams_ok := true
	for ch in map.get_children():
		var mi := ch as MeshInstance3D
		if mi == null:
			continue
		var sm := mi.material_override as ShaderMaterial
		if sm and (sm.shader == map._floor_shader or sm.shader == ClaudeBgDress.FLOOR_SHADER):
			floors += 1
			if sm.shader == ClaudeBgDress.FLOOR_SHADER:
				claude_floors += 1
				var off: Vector2 = sm.get_shader_parameter("offset")
				var bb := mi.global_transform * mi.get_aabb()
				seams_ok = seams_ok and posmod(roundi(bb.position.x - off.x), 2) == 0 and posmod(roundi(bb.position.z - off.y), 2) == 0
		if mi.material_override == null and mi.mesh is ArrayMesh and mi.mesh.get_surface_count() == 2:
			old_walls_hidden = old_walls_hidden and not mi.visible
	var kit := map.get_node_or_null("ClaudeBg")
	if not on:
		_check(claude_floors == 0 and floors > 0 and kit == null and not old_walls_hidden, "끄면(--bg=old) 예전 바닥 셰이더 %d개 · 예전 벽 상자 · 배경 모델 없음" % floors)
		g.queue_free()
		await _frames(2)
		return
	_check(floors > 0 and claude_floors == floors, "본편 바닥 %d개 모두 Claude 바닥 셰이더 (seed 3)" % floors)
	_check(seams_ok, "방마다 2m 줄눈이 방의 왼쪽·뒤 벽에서 시작 (offset)")
	var by := {}
	for n in kit.get_children():
		if n.has_meta("claude_bg"):
			var k: String = n.get_meta("claude_bg")
			by[k] = by.get(k, []) + [n]
	var blocks := 0
	for k in ["blocks_wall", "blocks_cover", "blocks_pillar"]:
		for mmi: MultiMeshInstance3D in by.get(k, []):
			blocks += mmi.multimesh.instance_count
	_check(old_walls_hidden and by.has("blocks_wall") and blocks > 100, "예전 벽 상자 숨김 · 낮은 W01 블록 %d칸 (벽 %d · 엄폐 %d · 기둥 %d)" % [blocks,
		(by.blocks_wall[0] as MultiMeshInstance3D).multimesh.instance_count if by.has("blocks_wall") else 0,
		(by.blocks_cover[0] as MultiMeshInstance3D).multimesh.instance_count if by.has("blocks_cover") else 0,
		(by.blocks_pillar[0] as MultiMeshInstance3D).multimesh.instance_count if by.has("blocks_pillar") else 0])
	# 막힌 칸마다 블록 · 3m 벽 · 벽감 · WallProps 중 하나가 덮는다 (빈 구멍 없음)
	var tall: Dictionary = map.get_meta("claude_tall")
	var occ: Dictionary = map.get_meta("claude_occupied")
	var covered := {}
	for k in ["blocks_wall", "blocks_cover", "blocks_pillar"]:
		for mmi: MultiMeshInstance3D in by.get(k, []):
			for o: Vector3 in mmi.get_meta("claude_spots"):
				covered[map.cell_of(o)] = true
	var holes := 0
	for y in ArenaMap.H:
		for x in ArenaMap.W:
			var c := Vector2i(x, y)
			var t := map.cell_type(c)
			var need := t == ArenaMap.PILLAR or t == ArenaMap.LOW or (t == ArenaMap.VOID and map._near_floor(c))
			if need and not (covered.has(c) or tall.has(c) or occ.has(c)):
				holes += 1
	_check(holes == 0, "벽·기둥·엄폐물 칸이 모두 덮임 (빈칸 %d)" % holes)
	# 3m 벽: 앞면이 바닥 경계, 뒤 3칸에 바닥 없음 (다른 방을 가리지 않음)
	var walls: Array = by.get("w01", []) + by.get("half", [])
	var tall_ok := walls.size() > 0
	for c: Vector2i in tall:
		for k in range(1, ClaudeBgDress.BEHIND + 1):
			tall_ok = tall_ok and map.cell_type(c - Vector2i(0, k)) != ArenaMap.FLOOR
		tall_ok = tall_ok and map.cell_type(c + Vector2i(0, 1)) == ArenaMap.FLOOR
	_check(tall_ok, "3m 뒤 벽 W01 %d · 반쪽 %d — 앞은 바닥, 뒤 %d칸에 바닥 없음" % [by.get("w01", []).size(), by.get("half", []).size(), ClaudeBgDress.BEHIND])
	var props: Array = by.get("bench", []) + by.get("locker", [])
	_check(by.get("bench", []).size() > 0 and by.get("locker", []).size() > 0, "벽감 프랍: 작업대 %d · 수납장 %d · 옆판 %d" % [by.get("bench", []).size(), by.get("locker", []).size(), by.get("jamb", []).size()])
	var in_wall := true
	for p: Node3D in props:
		var c := map.cell_of(p.global_position)
		in_wall = in_wall and map.cell_type(c) == ArenaMap.VOID and map.cell_type(c + Vector2i(0, 1)) == ArenaMap.FLOOR and map.is_blocked(p.global_position)
	_check(in_wall, "프랍은 모두 벽 칸(막힘)에 서고 바로 앞(+Z)이 바닥 칸 — 전투 바닥을 줄이지 않음")
	g.queue_free()
	await _frames(2)
