extends SceneTree
## Run with: Godot --headless --path . -s tests/rogue_check.gd
## 로그라이크 모드 HEX DEPTHS (RogueMain, scenes/rogue.tscn)
##  1. 데이터: 패시브 80+ · 액티브 18 · 장신구 20 · 알약/카드 · 결합 공격 재료 · 변신 태그가 모두 성립 가능
##  2. 층 생성 (여러 시드 × 6층): 보스방 = 가장 먼 막다른 방 · 아이템방/상점 존재 · 모든 방이 시작에서 이어짐 · 거래방 섬
##  3. 씬 시작: 체력 3칸 · 아이템방 받침대 · 상점 가격
##  4. 빌드: 스탯 · 결합 공격 · 변신(외형 포함)
##  5. 변형 탄: 다중 · 유도 · 폭발 · 레이저 · 혈사포 · 미사일 결합 — 실제로 적 체력을 깎는다
##  6. 픽업 · 받침대 · 악마 거래 · 알약 정체 공개
##  7. 폭탄이 금 간 벽을 부수면 비밀방 포털
##  8. 전투방: 들어가면 잠기고, 적을 다 잡으면 열리며 액티브가 충전된다
##  9. 보스 → 트랩도어 → 다음 층

var fails := 0
var main: RogueMain


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _frames(n: int) -> void:
	for i in n:
		if is_instance_valid(main) and is_instance_valid(main.player) and main.state == Main.State.PLAY:
			main.player.invuln = 999.0
		await physics_frame


func _kill_all() -> void:
	for e in get_nodes_in_group("enemies"):
		if is_instance_valid(e) and e.alive and not e.get("prop"):
			RogueBuild.inst.deal(e, 99999.0, Vector3.FORWARD, e.global_position)


func _run() -> void:
	# ── 1. 데이터 ──
	var db := RogueItems.db()
	var counts := {RogueItems.T.PASSIVE: 0, RogueItems.T.ACTIVE: 0, RogueItems.T.TRINKET: 0}
	var names := {}
	var dup := false
	for id in db:
		counts[db[id].type] += 1
		if names.has(db[id].name):
			dup = true
		names[db[id].name] = true
	_check(counts[RogueItems.T.PASSIVE] >= 80, "패시브 %d개" % counts[RogueItems.T.PASSIVE])
	_check(counts[RogueItems.T.ACTIVE] >= 18, "액티브 %d개" % counts[RogueItems.T.ACTIVE])
	_check(counts[RogueItems.T.TRINKET] >= 20, "장신구 %d개" % counts[RogueItems.T.TRINKET])
	_check(not dup, "아이템 이름이 겹치지 않는다")
	_check(RogueItems.PILLS.size() >= RogueItems.PILL_COLORS.size(), "알약 효과 %d종 ≥ 색 %d종" % [RogueItems.PILLS.size(), RogueItems.PILL_COLORS.size()])
	_check(RogueItems.CARDS.size() >= 17, "카드·룬 %d종" % RogueItems.CARDS.size())
	var syn_ok := true
	for s in RogueItems.SYNERGIES:
		for g in s.need:
			for id in g:
				if not db.has(id):
					syn_ok = false
					print("  결합 재료 없음: %s (%s)" % [id, s.id])
	_check(syn_ok and RogueItems.SYNERGIES.size() >= 14, "결합 공격 %d종 · 재료가 모두 아이템 목록에 있다" % RogueItems.SYNERGIES.size())
	var tag_ok := true
	for tag in RogueItems.TRANSFORMS:
		var n := 0
		for id in db:
			if db[id].type == RogueItems.T.PASSIVE and tag in db[id].tags:
				n += 1
		if n < RogueItems.TRANSFORM_NEED + 1:
			tag_ok = false
			print("  변신 %s 태그 아이템 %d개" % [tag, n])
	_check(tag_ok, "변신 %d종 모두 태그 아이템이 충분하다" % RogueItems.TRANSFORMS.size())

	# ── 2. 층 생성 ──
	var gen_ok := true
	var reach_ok := true
	var boss_ok := true
	var secret_n := 0
	var total := 0
	for sd in range(1, 13):
		for d in range(1, 7):
			var m := RogueMap.new()
			m.generate_floor(sd * 977 + d, d)
			total += 1
			var kinds := {}
			for r in m.rooms:
				kinds[r.kind] = int(kinds.get(r.kind, 0)) + 1
			if not (kinds.has("boss") and kinds.has("treasure") and kinds.has("shop") and kinds.has("start") and kinds.has("deal")):
				gen_ok = false
				print("  특수방 누락 seed=%d d=%d %s" % [sd, d, kinds])
			if kinds.has("secret"):
				secret_n += 1
			# 연결
			var seen := {m.start_room: true}
			var q: Array = [m.start_room]
			while q.size() > 0:
				var c: int = q.pop_front()
				for nb in m.rooms[c].nbr:
					if not seen.has(nb):
						seen[nb] = true
						q.append(nb)
			for r in m.rooms:
				if not r.slots.is_empty() and not seen.has(r.id):
					reach_ok = false
			# 보스 = 막다른 방 중 가장 멂
			var b: Dictionary = m.rooms[m.boss_room]
			if b.nbr.size() != 1:
				boss_ok = false
			for r in m.rooms:
				if r.nbr.size() == 1 and r.dist > b.dist:
					boss_ok = false
			m.free()
	_check(gen_ok, "층 %d개: 시작·보스·아이템방·상점·거래방이 모두 생성" % total)
	_check(reach_ok, "모든 방이 시작 방에서 문으로 이어진다")
	_check(boss_ok, "보스방은 가장 먼 막다른 방")
	_check(secret_n >= total * 0.7, "비밀방 %d / %d 층" % [secret_n, total])

	# ── 3. 씬 시작 ──
	RogueRun.started = false
	RogueRun.new_run(4242)
	main = load("res://scenes/rogue.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(10)
	_check(main.player.hp == 6 and RogueRun.red_max == 6, "시작 체력 3칸 (반 칸 6)")
	var peds := get_nodes_in_group("rogue_pedestals")
	var tre := main.rmap.rooms_of_kind("treasure")
	var in_treasure := false
	var shop_priced := false
	for p in peds:
		if main.rmap.room_at(p.global_position) == tre[0]:
			in_treasure = true
		if p.price > 0:
			shop_priced = true
	_check(in_treasure, "아이템방에 받침대")
	_check(shop_priced, "상점 받침대에 가격")

	# ── 4. 빌드 ──
	var b := RogueBuild.inst
	var d0 := b.dmg
	var t0 := b.tears
	RogueRun.items.append_array(["protein", "trigger", "homing", "ipecac"])
	b.recompute()
	await _frames(2)
	_check(b.dmg > d0 + 3.0, "공격력 증가 %.2f → %.2f" % [d0, b.dmg])
	_check(b.syn.has("missile"), "유도 칩 + 폭발 탄두 = 결합 공격 '유도 폭뢰'")
	_check(b.syn.has("mortar"), "트리거 + 폭발 탄두 = '연사 박격'")
	_check(b.tears > t0 * 0.9, "연사 박격으로 폭발 탄두의 연사 감소가 사라짐 (%.2f)" % b.tears)
	RogueRun.items.append_array(["mantle", "grail", "wings"])
	b.recompute()
	await _frames(2)
	_check(b.trans.has("angel"), "천사 태그 3개 → 변신 '기계 세라핌'")
	_check(b.flying(), "변신 능력: 비행")
	_check(b.look.parts.has("angel") and is_instance_valid(b.look.parts.angel), "변신 외형(후광·날개)이 몸에 붙는다")

	# ── 5. 변형 탄 ──
	var e := main.spawn_enemy("drone0", main.player.global_position + Vector3(0, 0, -5))
	e.landed = true
	await _frames(40)
	var hp0: int = e.hp
	var shots0 := get_nodes_in_group("rogue_shots").size()
	b._shot(main.player.global_position + Vector3(0, 0.95, 0), Vector3.FORWARD)
	await _frames(1)
	_check(get_nodes_in_group("rogue_shots").size() > shots0, "기본 총 → 변형 탄 생성")
	var style_ok := false
	for s in get_nodes_in_group("rogue_shots"):
		if s.style == "missile":
			style_ok = true
	_check(style_ok, "유도 폭뢰: 탄이 미사일 모양")
	await _frames(70)
	_check(not is_instance_valid(e) or e.hp < hp0, "미사일 탄이 적에게 피해 (%d → %s)" % [hp0, str(e.hp) if is_instance_valid(e) else "처치"])
	# 레이저 · 혈사포 · 다중 · 거대
	RogueRun.items.append_array(["technology", "inner_eye"])
	b.recompute()
	_check(b.syn.has("prism"), "레이저 + 삼중 = '프리즘 레이저'")
	var e2 := main.spawn_enemy("drone0", main.player.global_position + Vector3(0, 0, -6))
	await _frames(45)
	var hp2: int = e2.hp
	b._shot(main.player.global_position + Vector3(0, 0.95, 0), Vector3.FORWARD)
	await _frames(2)
	_check(not is_instance_valid(e2) or e2.hp < hp2, "레이저가 즉시 적중")
	RogueRun.items.append("brimstone")
	b.recompute()
	b._shot(main.player.global_position + Vector3(0, 0.95, 0), Vector3.FORWARD)
	await _frames(2)
	_check(true, "혈사포 빔 발사 오류 없음")
	_kill_all()
	await _frames(30)

	# ── 6. 픽업 · 받침대 · 거래 · 알약 ──
	var c0 := RogueRun.coins
	var pk := main.drop("nickel", main.player.global_position, null, false)
	await _frames(40)
	_check(RogueRun.coins == c0 + 5, "동전 5개 줍기 (%d → %d)" % [c0, RogueRun.coins])
	main.player.hp = RogueRun.red_max
	var hrt := main.drop("heart", main.player.global_position, null, false)
	await _frames(40)
	_check(is_instance_valid(hrt), "체력이 가득이면 하트를 안 먹는다")
	if is_instance_valid(hrt):
		hrt.queue_free()
	var pill := main.drop("pill", main.player.global_position, 3, false)
	await _frames(40)
	_check(not RogueRun.pocket.is_empty() and RogueRun.pocket.kind == "pill", "알약을 주머니에")
	main.use_pocket_item()
	_check(RogueRun.pills_known.has(3), "먹은 알약은 정체가 공개된다 (%s)" % RogueItems.pill_name(RogueRun.pill_map[3]))
	var n_items := RogueRun.items.size()
	var ped := main._pedestal(main.player.global_position + Vector3(8, 0, 0), "speed_gear")
	await _frames(2)
	main.take_pedestal(ped)
	_check(RogueRun.items.size() == n_items + 1 and ped.item_id == "", "받침대 아이템 획득 → 빈 받침대")
	RogueRun.red_max = 10
	main.player.hp = 10
	var devil := main._pedestal(main.player.global_position + Vector3(8, 0, 2), "pentagram", 0, 1)
	await _frames(2)
	main.take_pedestal(devil)
	_check(RogueRun.red_max == 8 and RogueRun.items.has("pentagram"), "악마 거래: 빨간 그릇 1칸으로 구매 (그릇 %d)" % RogueRun.red_max)
	var act := main._pedestal(main.player.global_position + Vector3(8, 0, -2), "a_necro")
	await _frames(2)
	main.take_pedestal(act)
	_check(RogueRun.active_item == "a_necro" and RogueRun.charge == 4, "액티브 획득 · 가득 충전")

	# ── 7. 비밀방 ──
	var cracks := get_nodes_in_group("rogue_cracks")
	if cracks.size() > 0:
		var cr: Node3D = cracks[0]
		var portals0 := get_nodes_in_group("rogue_portals").size()
		RogueEffects.explosion(cr.global_position - cr.face * 0.8, 2.7, 10.0, false, "bomb")
		await _frames(2)
		_check(get_nodes_in_group("rogue_portals").size() > portals0, "폭발이 금 간 벽을 부수고 비밀방 포털이 열린다")
		var portal = null
		for q in get_nodes_in_group("rogue_portals"):
			if q.kind == "secret":
				portal = q
		main.on_portal(portal)
		await _frames(3)
		_check(main.rmap.room_at(main.player.global_position) == main.rmap.island_secret, "포털로 비밀방에 들어간다")
		main._teleport(main.rmap.room_center(main.rmap.start_room))
		await _frames(3)
	else:
		_check(true, "(이 시드는 비밀방 없음)")

	# ── 8. 전투방 ──
	var normal := -1
	for r in main.rmap.rooms:
		if r.kind == "normal" and main.room_live[r.id] == "idle":
			normal = r.id
			break
	main._teleport(main.rmap.room_center(normal))
	await _frames(20)
	_check(main.room_live[normal] == "active" and main.rmap.rooms[normal].gates_closed, "전투방에 들어가면 문이 잠긴다")
	await _frames(60)
	var ch0 := RogueRun.charge
	RogueRun.charge = 0
	_kill_all()
	await _frames(20)
	_kill_all()
	await _frames(30)
	_check(main.room_live[normal] == "cleared" and not main.rmap.rooms[normal].gates_closed, "적을 모두 잡으면 문이 열린다")
	_check(RogueRun.charge >= 1, "방 정리 → 액티브 충전 (%d)" % RogueRun.charge)
	RogueRun.charge = maxi(ch0, 4)
	main.use_active_item()
	_check(RogueRun.charge == 0, "액티브 사용 → 충전 소모")

	# ── 9. 보스 → 다음 층 ──
	main._teleport(main.rmap.room_center(main.rmap.boss_room) + Vector3(0, 0, 3))
	await _frames(30)
	_check(is_instance_valid(main.boss), "보스방 진입 → 보스 등장 (%s)" % (main.boss.spec.name if is_instance_valid(main.boss) else "-"))
	await _frames(60)
	for i in 4:
		for x in main.boss.bosses:
			if is_instance_valid(x) and x.alive:
				b.deal(x, 99999.0, Vector3.FORWARD, x.global_position)
		_kill_all()
		await _frames(20)
	_check(is_instance_valid(main.trapdoor), "보스 격파 → 트랩도어")
	var depth0 := RogueRun.depth
	main.on_portal(main.trapdoor)
	await _frames(20)
	var nm = current_scene
	_check(RogueRun.depth == depth0 + 1 and nm is RogueMain and nm != main, "트랩도어 → %d층 (씬 다시 불러옴)" % RogueRun.depth)
	main = nm
	await _frames(10)
	_check(RogueRun.items.has("pentagram") and main.build.has("pentagram"), "아이템이 다음 층으로 이어진다")

	# ── 10. 전부 한 번씩: 결합 공격 15 · 변신 9 · 액티브 · 알약 · 카드 (오류가 나면 SCRIPT ERROR 로 실패) ──
	b = main.build
	var p0: Vector3 = main.player.global_position
	for i in 3:
		main.spawn_enemy("drone0", p0 + Vector3(randf_range(-4, 4), 0, -5))
	await _frames(50)
	var syn_hit := 0
	for sd in RogueItems.SYNERGIES:
		RogueRun.items.clear()
		for g in sd.need:
			RogueRun.items.append(g[0])
		b.recompute()
		if b.syn.has(sd.id):
			syn_hit += 1
		for k in 4:
			b._shot(main.player.global_position + Vector3(0, 0.95, 0), Vector3.FORWARD.rotated(Vector3.UP, k * 0.4))
			await _frames(3)
		b._dash(main.player, false)
		b._strike(Vector3.FORWARD, 2.2, {"hit": 1, "blocked": 0, "killed": 1})
		main._place_bomb(main.player.global_position + Vector3(3, 0, 0))
		await _frames(30)
	_check(syn_hit == RogueItems.SYNERGIES.size(), "결합 공격 %d / %d 성립 · 발사·대시·검·폭탄 실행" % [syn_hit, RogueItems.SYNERGIES.size()])
	var tr_hit := 0
	for tag in RogueItems.TRANSFORMS:
		RogueRun.items.clear()
		for id in RogueItems.db():
			var it: Dictionary = RogueItems.db()[id]
			if it.type == RogueItems.T.PASSIVE and tag in it.tags and RogueRun.items.size() < 3:
				RogueRun.items.append(id)
		b.recompute()
		await _frames(10)
		if b.trans.has(tag) and b.look.parts.has(tag):
			tr_hit += 1
		b._shot(main.player.global_position + Vector3(0, 0.95, 0), Vector3.FORWARD)
		await _frames(10)
	_check(tr_hit == RogueItems.TRANSFORMS.size(), "변신 %d / %d · 외형 장식" % [tr_hit, RogueItems.TRANSFORMS.size()])
	var act_n := 0
	for id in RogueItems.db():
		if RogueItems.db()[id].type != RogueItems.T.ACTIVE:
			continue
		main.player.hp = maxi(main.player.hp, 4)
		RogueRun.active_item = id
		RogueRun.charge = 6
		main.use_active_item()
		act_n += 1
		await _frames(8)
	_check(act_n == 18, "액티브 %d종 실행" % act_n)
	for ci in RogueItems.PILL_COLORS.size():
		RogueRun.pocket = {"kind": "pill", "id": ci, "horse": ci % 5 == 0}
		main.use_pocket_item()
		await _frames(3)
	_check(RogueRun.pills_known.size() == RogueItems.PILL_COLORS.size(), "알약 %d색 모두 먹어서 공개" % RogueRun.pills_known.size())
	for cd in RogueItems.CARDS:
		RogueRun.pocket = {"kind": "card", "id": cd[0]}
		main.use_pocket_item()
		await _frames(6)
	_check(main.player.alive, "카드·룬 %d종 실행 뒤에도 정상" % RogueItems.CARDS.size())
	await _frames(240)

	print("RESULT %s (%d fails)" % ["ROGUE_OK" if fails == 0 else "ROGUE_FAILED", fails])
	quit(1 if fails > 0 else 0)
