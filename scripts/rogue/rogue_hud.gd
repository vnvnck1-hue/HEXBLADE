class_name RogueHud
extends CanvasLayer
## 로그 모드 HUD: 하트(빨강·소울·블랙, 반 칸) · 동전/폭탄/열쇠 · 액티브(충전 칸) · 장신구 · 알약/카드 · 층/저주 ·
## 아이작식 방 미니맵 · 최근 아이템 줄 · 변신 진행도 · Tab 정보 패널.

const ROOM_ICONS := {"treasure": "★", "shop": "$", "boss": "☠", "secret": "?", "curse": "✕", "sacrifice": "▼", "challenge": "⚔", "library": "▣", "start": "·"}
const KIND_NAMES := {"start": "시작", "normal": "전투", "treasure": "아이템방", "shop": "상점", "boss": "보스", "secret": "비밀방", "curse": "저주방", "sacrifice": "희생방", "challenge": "도전방", "library": "서재", "deal": "거래방"}

var main
var canvas: Control
var font: SystemFont
var font_b: SystemFont
var info_open := false
var t := 0.0
var _heart_pts := PackedVector2Array()


func _ready() -> void:
	layer = 7
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "sans-serif"])
	font.font_weight = 600
	font_b = SystemFont.new()
	font_b.font_names = font.font_names
	font_b.font_weight = 800
	canvas = Control.new()
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw_all)
	add_child(canvas)
	for i in 24:
		var a := TAU * i / 24.0
		# 하트 곡선
		var x := 16.0 * pow(sin(a), 3)
		var y := -(13.0 * cos(a) - 5.0 * cos(2 * a) - 2.0 * cos(3 * a) - cos(4 * a))
		_heart_pts.append(Vector2(x, y) / 17.0)


func _process(dt: float) -> void:
	t += dt
	visible = not Main.ui_hidden
	layer = 30 if info_open else 7          # 정보 패널은 배너·컷인 위에
	canvas.queue_redraw()


func _txt(p: Vector2, s: String, size: int, c: Color, bold := false, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	var f: Font = font_b if bold else font
	canvas.draw_string_outline(f, p, s, align, w, size, 5, Color(0, 0, 0, 0.85))
	canvas.draw_string(f, p, s, align, w, size, c)


func _heart(c: Vector2, r: float, col: Color, half := false, outline := false) -> void:
	var pts := PackedVector2Array()
	for q in _heart_pts:
		var v := c + q * r
		if half and q.x > 0.0:
			v.x = c.x
		pts.append(v)
	if outline:
		canvas.draw_polyline(pts + PackedVector2Array([pts[0]]), col, 2.0, true)
	else:
		canvas.draw_colored_polygon(pts, col)


func _draw_all() -> void:
	main = Main.inst
	if main == null or not main.has_method("collect"):
		return
	var sz := canvas.size
	_draw_hearts(Vector2(26, 26))
	_draw_resources(Vector2(22, 96))
	_draw_slots(Vector2(22, 196))
	_draw_floor(sz)
	_draw_minimap(sz)
	_draw_items(sz)
	_draw_transforms(Vector2(22, 372))
	if info_open:
		_draw_info(sz)
	else:
		_txt(Vector2(22, sz.y - 14), "Tab 정보 · Q 액티브 · X 폭탄 · Z 알약/카드", 14, Color(1, 1, 1, 0.55))


func _draw_hearts(o: Vector2) -> void:
	var unknown: bool = main.curse == "unknown"
	var i := 0
	var r := 12.0
	var step := 27.0
	for k in range(0, RogueRun.red_max, 2):
		var p := o + Vector2((i % 8) * step, (i / 8) * 26.0)
		if unknown:
			_txt(p + Vector2(-6, 7), "?", 20, Color("ff6a7a"), true)
		else:
			_heart(p, r, Color(0.15, 0.06, 0.1, 0.85))
			_heart(p, r, Color("ff9aa8"), false, true)
			var fill := RogueRun.red - k
			if fill >= 2:
				_heart(p, r, Color("ff3a4a"))
			elif fill == 1:
				_heart(p, r, Color("ff3a4a"), true)
		i += 1
	for k in range(0, RogueRun.soul, 2):
		var p := o + Vector2((i % 8) * step, (i / 8) * 26.0)
		_heart(p, r, Color("6a8aff"), RogueRun.soul - k == 1)
		_heart(p, r, Color("c8d8ff"), false, true)
		i += 1
	for k in range(0, RogueRun.black, 2):
		var p := o + Vector2((i % 8) * step, (i / 8) * 26.0)
		_heart(p, r, Color("2a1838"), RogueRun.black - k == 1)
		_heart(p, r, Color("b070ff"), false, true)
		i += 1


func _draw_resources(o: Vector2) -> void:
	var rows := [["coin", RogueRun.coins, Color("ffd040")], ["bomb", RogueRun.bombs, Color("8a8aa0")], ["key", RogueRun.keys, Color("ffe080")]]
	for i in rows.size():
		var p := o + Vector2(0, i * 30.0)
		var c: Color = rows[i][2]
		match rows[i][0]:
			"coin":
				canvas.draw_circle(p + Vector2(10, 0), 9.0, c)
				canvas.draw_circle(p + Vector2(10, 0), 4.0, Color("fff4b0"))
			"bomb":
				canvas.draw_circle(p + Vector2(10, 1), 9.0, Color("2a2a38"))
				canvas.draw_line(p + Vector2(12, -8), p + Vector2(16, -12), Color("ffb040"), 2.5)
			"key":
				canvas.draw_arc(p + Vector2(6, 0), 5.0, 0, TAU, 12, c, 2.5)
				canvas.draw_line(p + Vector2(11, 0), p + Vector2(22, 0), c, 3.0)
				canvas.draw_line(p + Vector2(19, 0), p + Vector2(19, 5), c, 3.0)
		_txt(p + Vector2(30, 8), "%02d" % int(rows[i][1]), 22, Color.WHITE, true)


func _box(r: Rect2, c: Color) -> void:
	canvas.draw_rect(r, Color(0.06, 0.05, 0.12, 0.8))
	canvas.draw_rect(r, c, false, 2.0)


func _draw_slots(o: Vector2) -> void:
	# 액티브
	var ar := Rect2(o, Vector2(62, 62))
	_box(ar, Color("8ad8ff"))
	if RogueRun.active_item != "":
		var it := RogueItems.get_item(RogueRun.active_item)
		var need := int(it.get("charge", 1))
		var c := RogueItems.color_of(RogueRun.active_item)
		canvas.draw_rect(Rect2(o + Vector2(14, 14), Vector2(34, 34)), c)
		var full := RogueRun.charge >= need
		if full and fmod(t, 0.6) < 0.3:
			canvas.draw_rect(ar.grow(3), Color("ffe070"), false, 2.0)
		# 충전 막대
		var bh := 62.0
		for k in need:
			var seg := Rect2(o + Vector2(66, bh - (k + 1) * bh / need + 1), Vector2(10, bh / need - 2))
			canvas.draw_rect(seg, Color("ffe070") if k < RogueRun.charge else Color(0.2, 0.2, 0.3))
		_txt(o + Vector2(84, 22), it.name, 16, Color.WHITE, true)
		_txt(o + Vector2(84, 42), "Q  %s" % ("준비" if full else "%d/%d" % [RogueRun.charge, need]), 14, Color("ffe070") if full else Color(0.8, 0.8, 0.9))
	else:
		_txt(o + Vector2(14, 38), "Q", 20, Color(1, 1, 1, 0.3), true)
	# 장신구 · 알약/카드
	var tr := Rect2(o + Vector2(0, 70), Vector2(36, 36))
	_box(tr, Color("d0c0ff"))
	if RogueRun.trinket != "":
		canvas.draw_arc(tr.get_center(), 10.0, 0, TAU, 16, Color("d0c0ff"), 4.0)
		_txt(tr.position + Vector2(42, 23), RogueItems.get_item(RogueRun.trinket).name, 14, Color("e0d8ff"))
	var pr := Rect2(o + Vector2(0, 112), Vector2(36, 36))
	_box(pr, Color("ff9ad0"))
	if not RogueRun.pocket.is_empty():
		var text := ""
		if RogueRun.pocket.kind == "pill":
			var ci := int(RogueRun.pocket.id)
			var cols: Array = RogueItems.PILL_COLORS[ci]
			canvas.draw_circle(pr.get_center() + Vector2(-5, 0), 8.0, cols[1])
			canvas.draw_circle(pr.get_center() + Vector2(5, 0), 8.0, cols[2])
			text = ("큰 " if RogueRun.pocket.get("horse", false) else "") + (RogueItems.pill_name(RogueRun.pill_map[ci]) if RogueRun.pills_known.has(ci) else "%s 알약 (???)" % cols[0])
		else:
			var cd := RogueItems.card(str(RogueRun.pocket.id))
			canvas.draw_rect(Rect2(pr.position + Vector2(10, 6), Vector2(16, 24)), Color("f4f0e8"))
			text = "%s — %s" % [cd[1], cd[2]]
		_txt(pr.position + Vector2(42, 23), "Z  " + text, 14, Color("ffd0ec"))


func _draw_floor(sz: Vector2) -> void:
	var s := "%d층 · %s" % [RogueRun.depth, RogueRun.floor_name()]
	_txt(Vector2(0, 34), s, 22, Color("e0e8ff"), true, HORIZONTAL_ALIGNMENT_CENTER, sz.x)
	if main.curse != "":
		var cn: String = {"darkness": "어둠의 저주", "lost": "길 잃음의 저주", "unknown": "미지의 저주", "blind": "장님의 저주"}.get(main.curse, main.curse)
		_txt(Vector2(0, 58), cn, 16, Color("c070ff"), true, HORIZONTAL_ALIGNMENT_CENTER, sz.x)


func _draw_minimap(sz: Vector2) -> void:
	if main.curse == "lost":
		_txt(Vector2(sz.x - 200, 40), "지도 없음", 16, Color("c070ff"), true)
		return
	var m: RogueMap = main.rmap
	var cw := 22.0
	var ch := 15.0
	var gap := 3.0
	var o := Vector2(sz.x - 20 - RogueMap.GW * (cw + gap), 20)
	canvas.draw_rect(Rect2(o - Vector2(6, 6), Vector2(RogueMap.GW * (cw + gap) + 9, RogueMap.GH * (ch + gap) + 9)), Color(0.04, 0.03, 0.1, 0.55))
	for r in m.rooms:
		if r.slots.is_empty():
			continue
		var show: int = main.room_known(r.id)
		if show == 0:
			continue
		var lo := Vector2i(99, 99)
		var hi := Vector2i(-1, -1)
		for s in r.slots:
			lo = Vector2i(mini(lo.x, s.x), mini(lo.y, s.y))
			hi = Vector2i(maxi(hi.x, s.x), maxi(hi.y, s.y))
		var rect := Rect2(o + Vector2(lo.x * (cw + gap), lo.y * (ch + gap)), Vector2((hi.x - lo.x + 1) * (cw + gap) - gap, (hi.y - lo.y + 1) * (ch + gap) - gap))
		var col := Color(0.25, 0.25, 0.35, 0.9)
		if r.visited:
			col = Color(0.62, 0.62, 0.75, 0.95)
		if r.id == main.cur_room:
			col = Color(1, 1, 1, 1)
		if show == 1:
			canvas.draw_rect(rect, Color(0.3, 0.3, 0.42, 0.6), false, 1.5)
		else:
			canvas.draw_rect(rect, col)
		var icon: String = ROOM_ICONS.get(r.kind, "")
		if icon != "" and r.kind != "start" and (r.visited or main.reveal_special or show == 3):
			var ic: Color = {"boss": Color("ff4a5a"), "treasure": Color("ffd040"), "shop": Color("7cf090"), "curse": Color("c070ff")}.get(r.kind, Color("202030"))
			_txt(rect.position + Vector2(0, rect.size.y - 2), icon, 13, ic, true, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)
		if r.locked and show >= 2:
			canvas.draw_rect(rect, Color("ffd040"), false, 1.5)
	# 비밀방 (알려졌으면)
	if m.island_secret >= 0 and (main.reveal_secret or m.rooms[m.island_secret].visited):
		var gs: Vector2i = m.rooms[m.island_secret].get("ghost_slot", Vector2i(-1, -1))
		if gs.x >= 0:
			var rect := Rect2(o + Vector2(gs.x * (cw + gap), gs.y * (ch + gap)), Vector2(cw, ch))
			canvas.draw_rect(rect, Color(0.5, 0.35, 0.8, 0.85))
			_txt(rect.position + Vector2(0, ch - 2), "?", 13, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER, cw)


func _draw_items(sz: Vector2) -> void:
	var ids: Array = RogueRun.items
	var n := mini(ids.size(), 16)
	var o := Vector2(22, sz.y - 70)
	for i in n:
		var id: String = ids[ids.size() - n + i]
		var it := RogueItems.get_item(id)
		var p := o + Vector2(i * 34.0, 0)
		var c := RogueItems.color_of(id)
		canvas.draw_rect(Rect2(p, Vector2(30, 30)), Color(0.06, 0.05, 0.12, 0.85))
		canvas.draw_rect(Rect2(p + Vector2(3, 3), Vector2(24, 24)), c.darkened(0.25))
		_txt(p + Vector2(0, 22), str(it.name).substr(0, 1), 16, Color.WHITE, true, HORIZONTAL_ALIGNMENT_CENTER, 30)


func _draw_transforms(o: Vector2) -> void:
	var b := RogueBuild.inst
	if b == null:
		return
	var y := 0.0
	for tag in RogueItems.TAGS:
		var n := int(b.tag_count.get(tag, 0))
		if n <= 0:
			continue
		var c: Color = RogueItems.TAG_COLORS[tag]
		var done := b.trans.has(tag)
		var label: String = RogueItems.TRANSFORMS[tag].name if done else RogueItems.TAG_NAMES[tag]
		_txt(o + Vector2(0, y), label, 14, c if done else c.lerp(Color.WHITE, 0.3), done)
		for k in RogueItems.TRANSFORM_NEED:
			var cp := o + Vector2(98 + k * 14, y - 5)
			if k < n:
				canvas.draw_circle(cp, 5.0, c)
			else:
				canvas.draw_arc(cp, 5.0, 0, TAU, 10, c, 1.5)
		y += 20.0


func _draw_info(sz: Vector2) -> void:
	var b := RogueBuild.inst
	var r := Rect2(Vector2(sz.x * 0.12, sz.y * 0.1), Vector2(sz.x * 0.76, sz.y * 0.8))
	canvas.draw_rect(r, Color(0.03, 0.02, 0.08, 0.92))
	canvas.draw_rect(r, Color("8ad8ff"), false, 2.0)
	var x := r.position.x + 24
	var y := r.position.y + 40
	_txt(Vector2(x, y), "HEX DEPTHS · %d층 %s · 처치 %d · 방 %d" % [RogueRun.depth, RogueRun.floor_name(), RogueRun.kills, RogueRun.rooms], 20, Color.WHITE, true)
	y += 34
	if b:
		_txt(Vector2(x, y), "공격 %.2f   연사 %.2f/초   사거리 %.1fm   탄속 %.0f   이동 ×%.2f   행운 %+.0f" % [b.cur_dmg(), b.cur_tears(), b.range_m, b.shot_speed, b.speed, b.luck], 17, Color("ffe8a0"))
		y += 30
		if b.syn.size() > 0:
			var names: Array = []
			for s in RogueItems.SYNERGIES:
				if b.syn.has(s.id):
					names.append(s.name)
			_txt(Vector2(x, y), "결합 공격: " + " · ".join(names), 17, Color("ff9af0"), true)
			y += 26
		if b.trans.size() > 0:
			var tn: Array = []
			for tg in b.trans:
				tn.append(RogueItems.TRANSFORMS[tg].name)
			_txt(Vector2(x, y), "변신: " + " · ".join(tn), 17, Color("a0f0ff"), true)
			y += 26
	y += 8
	var col_w := (r.size.x - 48) / 2.0
	var i := 0
	var list: Array = RogueRun.items.duplicate()
	if RogueRun.active_item != "":
		list.push_front(RogueRun.active_item)
	if RogueRun.trinket != "":
		list.push_front(RogueRun.trinket)
	for id in list:
		var it := RogueItems.get_item(id)
		if it.is_empty():
			continue
		var cx := x + (i % 2) * col_w
		var cy := y + (i / 2) * 24.0
		if cy > r.end.y - 20:
			break
		var kind: String = ["", "[액티브] ", "[장신구] "][it.type]
		canvas.draw_rect(Rect2(Vector2(cx, cy - 13), Vector2(12, 12)), RogueItems.color_of(id))
		_txt(Vector2(cx + 18, cy), kind + "%s — %s" % [it.name, it.desc], 15, Color(0.92, 0.92, 1.0))
		i += 1
	if list.is_empty():
		_txt(Vector2(x, y), "아직 아이템이 없다", 16, Color(1, 1, 1, 0.5))
