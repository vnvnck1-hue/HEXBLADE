class_name SectorMapView
extends Control
## 섹터 지도 그리기. 전체 화면(Tab)과 HUD 미니맵 자리 양쪽에서 같은 paint() 를 쓴다.
## 지나온 칸 = 청록 테두리, 현재 칸 = 맥동 링, 갈 수 있는 칸 = 깜빡이는 밝은 테두리, 지나친 칸 = 어둡게.

const G := preload("res://scripts/sector_graph.gd")

var font: Font
var shown := 0.0      # 전체 화면 표시 정도 (0~1)
var want := false
var t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = make_font()
	modulate.a = 0.0


static func make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Apple SD Gothic Neo", "Noto Sans CJK KR", "sans-serif"])
	f.font_weight = 700
	return f


func _process(dt: float) -> void:
	t += dt
	var rdt := dt / maxf(Engine.time_scale, 0.01)
	shown = move_toward(shown, 1.0 if want else 0.0, rdt * 6.0)
	modulate.a = shown
	visible = shown > 0.001
	if visible:
		size = get_viewport_rect().size
		queue_redraw()


func _draw() -> void:
	var run := get_node_or_null("/root/Run")
	if run == null or run.nodes.is_empty():
		return
	var sz := size
	draw_rect(Rect2(Vector2.ZERO, sz), Color(0.01, 0.01, 0.04, 0.72))
	var panel := Rect2(sz * 0.5 - Vector2(560, 300), Vector2(1120, 600))
	draw_rect(panel, Color(0.04, 0.04, 0.1, 0.9))
	draw_rect(panel, Color(0.4, 0.5, 0.9, 0.6), false, 2.0)
	var title := "SECTOR %d  ·  %s" % [run.sector + 1, run.sector_name()]
	draw_string(font, panel.position + Vector2(28, 44), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0.8, 0.95, 1.0))
	var stat := "단계 %d / %d    체력 %d    코인 %d    점수 %d" % [run.cur_level(), G.LEVELS + 1, run.hp, run.coins, run.score]
	_rstring(Vector2(panel.end.x - 28, panel.position.y + 44), stat, 18, Color(0.75, 0.75, 0.95))
	paint(self, Rect2(panel.position + Vector2(40, 80), panel.size - Vector2(80, 150)), run, t, font, true)
	# 범례
	var lx := panel.position.x + 40
	var ly := panel.position.y + panel.size.y - 30
	for k in [G.Kind.COMBAT, G.Kind.ELITE, G.Kind.REST, G.Kind.BOSS]:
		var c := lx + 12
		_icon(self, Vector2(c, ly - 6), 9.0, k, G.KIND_COLORS[k])
		draw_string(font, Vector2(c + 16, ly), G.KIND_NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.8, 0.95))
		lx += 110
	_rstring(Vector2(panel.end.x - 28, ly), "방을 정리하면 출구에 포탈이 열립니다  ·  Tab 지도 닫기", 16, Color(0.6, 0.65, 0.85))


func _rstring(right: Vector2, text: String, fs: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, right - Vector2(w, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## rect 안에 섹터 지도 전체를 맞춰 그린다. detailed 면 칸 아래에 이름을 쓴다.
static func paint(ci: CanvasItem, rect: Rect2, run: Node, t: float, font: Font, detailed: bool) -> void:
	var nodes: Array = run.nodes
	# 격자 범위
	var lv_max := G.LEVELS + 1
	var span := Vector2(lv_max * 1.5 + 2.0, (G.ROW_MAX - G.ROW_MIN + 1.5) * sqrt(3.0))
	var R := minf(rect.size.x / span.x, rect.size.y / span.y)
	var origin := rect.position + Vector2((rect.size.x - (lv_max * 1.5) * R) * 0.5, rect.size.y * 0.5 - 0.25 * sqrt(3.0) * R)
	var at := func(lv: int, row: int) -> Vector2: return origin + G.hex_center(lv, row, R)
	# 배경 빈 헥스
	for lv in range(0, lv_max + 1):
		for row in range(G.ROW_MIN, G.ROW_MAX + 1):
			var pts := G.hex_points(at.call(lv, row), R * 0.94)
			pts.append(pts[0])
			ci.draw_polyline(pts, Color(0.3, 0.32, 0.6, 0.16), 1.0)
	var cur: Dictionary = nodes[run.cur]
	var path: Array = run.path
	# 연결선
	for nd in nodes:
		for to in nd.links:
			var b: Dictionary = nodes[to]
			var pa: Vector2 = at.call(nd.level, nd.row)
			var pb: Vector2 = at.call(b.level, b.row)
			var col := Color(0.35, 0.38, 0.7, 0.35)
			var w := 1.5
			var walked := path.has(nd.id) and path.has(to) and path.find(to) == path.find(nd.id) + 1
			if walked:
				col = Color(0.35, 0.95, 1.0, 0.95)
				w = 3.0
			elif nd.id == run.cur:
				col = Color(1, 1, 1, 0.55 + 0.35 * sin(t * 6.0))
				w = 2.5
			elif nd.level < cur.level:
				col.a = 0.15
			ci.draw_line(pa, pb, col, w * (1.0 if detailed else 0.7), true)
	# 칸
	for nd in nodes:
		var c: Vector2 = at.call(nd.level, nd.row)
		var kc: Color = G.KIND_COLORS[nd.kind]
		var visited: bool = path.has(nd.id)
		var reachable: bool = cur.links.has(nd.id)
		var passed: bool = nd.level <= cur.level and not visited
		var fill := Color(kc.r, kc.g, kc.b, 0.16)
		var edge := Color(kc.r, kc.g, kc.b, 0.55)
		if visited:
			fill = Color(0.1, 0.3, 0.4, 0.85)
			edge = Color(0.4, 0.95, 1.0, 1.0)
		elif passed:
			fill = Color(0.1, 0.1, 0.16, 0.6)
			edge = Color(0.3, 0.3, 0.4, 0.4)
			kc = Color(0.4, 0.4, 0.5)
		elif reachable:
			fill = Color(kc.r, kc.g, kc.b, 0.3 + 0.12 * sin(t * 6.0))
			edge = Color(1, 1, 1, 0.75 + 0.25 * sin(t * 6.0))
		var hr := R * (1.08 if nd.kind == G.Kind.BOSS else 0.8)
		var pts := G.hex_points(c, hr)
		ci.draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		ci.draw_polyline(pts, edge, 2.5 if detailed else 1.5, true)
		# 자세히 보기에서는 아이콘을 위로 올리고 이름을 칸 안 아래쪽에 쓴다
		var show_label := detailed and not passed
		var ic := c - Vector2(0, hr * 0.2) if show_label else c
		_icon(ci, ic, hr * (0.3 if show_label else 0.42), nd.kind, kc if not visited else Color(0.75, 1.0, 1.0))
		if nd.id == run.cur:
			var pr := hr * (1.12 + 0.08 * sin(t * 5.0))
			var rp := G.hex_points(c, pr)
			rp.append(rp[0])
			ci.draw_polyline(rp, Color(0.4, 1.0, 1.0, 0.9), 2.0 if detailed else 1.5, true)
		if show_label:
			var label: String = G.KIND_NAMES[nd.kind]
			if nd.kind == G.Kind.BOSS:
				label = run.boss_name()
			var nc := Color(0.9, 0.9, 1.0, 0.95) if not visited else Color(0.6, 0.95, 1.0)
			var fs := int(clampf(hr * 0.36, 11.0, 16.0))
			ci.draw_string(font, c + Vector2(-hr, hr * 0.62), label, HORIZONTAL_ALIGNMENT_CENTER, hr * 2.0, fs, nc)


## 칸 종류 아이콘 (벡터): 전투 = X 두 자루, 정예 = 겹마름모, 정비 = 십자, 보스 = 뿔 달린 원, 출발 = 점
static func _icon(ci: CanvasItem, c: Vector2, s: float, kind: int, col: Color) -> void:
	var w := maxf(1.5, s * 0.22)
	match kind:
		G.Kind.COMBAT:
			ci.draw_line(c + Vector2(-s, -s), c + Vector2(s, s), col, w, true)
			ci.draw_line(c + Vector2(s, -s), c + Vector2(-s, s), col, w, true)
		G.Kind.ELITE:
			for k in [1.0, 0.55]:
				var r: float = s * k
				var d := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0), c + Vector2(0, -r)])
				ci.draw_polyline(d, col, w, true)
		G.Kind.REST:
			ci.draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), col, w * 1.4, true)
			ci.draw_line(c + Vector2(0, -s), c + Vector2(0, s), col, w * 1.4, true)
		G.Kind.BOSS:
			ci.draw_arc(c + Vector2(0, s * 0.15), s * 0.8, 0, TAU, 20, col, w, true)
			ci.draw_line(c + Vector2(-s * 0.55, -s * 0.45), c + Vector2(-s * 0.9, -s * 1.1), col, w, true)
			ci.draw_line(c + Vector2(s * 0.55, -s * 0.45), c + Vector2(s * 0.9, -s * 1.1), col, w, true)
			ci.draw_circle(c + Vector2(0, s * 0.15), s * 0.25, col)
		_:
			ci.draw_circle(c, s * 0.45, col)
