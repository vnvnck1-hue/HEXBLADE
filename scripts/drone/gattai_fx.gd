class_name GattaiFX
extends CanvasLayer
## 로봇 합체 만화 연출 (화면 위 2D). 드론이 메카 등에 붙는 순간 한 번 재생한다. 실제 시간으로 흐른다 (히트스탑·슬로우와 무관).
##  ① 집중선: 합체 지점(화면 좌표)으로 모이는 굵고 가는 흑백 쐐기 선이 화면 가장자리에서 꽂힌다. 처음엔 빽빽하게, 점점 바깥으로 물러나며 사라진다.
##  ② 흰 섬광 한 프레임 → 노란·하늘 톱니 폭발 말풍선 위 "합체!!" 글자가 크게 튀어나왔다가 흔들리며 줄어든다 (굵은 검은 테두리 · 비스듬히).
##  ③ 말풍선 주위로 작은 별 조각이 사방으로 튄다. 화면 위아래에 검은 띠(시네마 레터박스)가 잠깐 들어왔다 빠진다.

const LIFE := 0.95
const LINES := 64
const INK := Color(0.04, 0.03, 0.08)
const BURST := Color("ffe14a")
const BURST2 := Color("62ffc4")

var at := Vector2.ZERO           ## 합체 지점 (화면 좌표)
var text := "합체!!"
var font: Font
var t := 0.0
var canvas: Control
var rng := RandomNumberGenerator.new()
var _seeds: Array = []           ## 집중선 [각도, 굵기, 길이 비, 흑/백]
var _bits: Array = []            ## 튀는 별 조각 [방향, 속도, 크기, 회전]
var compact := false             ## 조종석 컷인(CockpitCutin)과 함께: 컷인 아래 층에서 집중선·레터박스만 (흰 섬광·말풍선·글자·별 조각 생략)


static func play(scene: Node, screen_pos: Vector2, label := "합체!!", lines_only := false) -> GattaiFX:
	var g := GattaiFX.new()
	g.at = screen_pos
	g.text = label
	g.compact = lines_only
	if Main.inst and Main.inst.hud:
		g.font = Main.inst.hud.font
	scene.add_child(g)
	return g


func _ready() -> void:
	layer = CockpitCutin.LAYER - 1 if compact else 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	for i in LINES:
		_seeds.append([TAU * (i + rng.randf_range(-0.35, 0.35)) / LINES, rng.randf_range(0.006, 0.03), rng.randf_range(0.0, 0.35), rng.randf() < 0.75])
	for i in 18:
		_bits.append([rng.randf() * TAU, rng.randf_range(420.0, 1100.0), rng.randf_range(10.0, 26.0), rng.randf() * TAU])
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(_draw_all)
	add_child(canvas)
	if font == null:
		font = ThemeDB.fallback_font


func _process(_dt: float) -> void:
	# 실제 시간: 히트스탑(time_scale ≈ 0.06)에도 만화 연출은 제 속도로
	t += get_process_delta_time() / maxf(Engine.time_scale, 0.0001)
	if t >= LIFE:
		queue_free()
		return
	canvas.queue_redraw()


func _draw_all() -> void:
	var vs := canvas.get_viewport_rect().size
	var diag := vs.length()
	var k := t / LIFE
	# 첫 두 프레임: 흰 섬광 → 반전처럼 검게 한 번
	if t < 0.035 and not compact:
		canvas.draw_rect(Rect2(Vector2.ZERO, vs), Color(1, 1, 1, 0.95))
		return
	if t < 0.07:
		canvas.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.02, 0.02, 0.05, 0.55))
	# 레터박스
	var lb := vs.y * 0.11 * (1.0 - smoothstep(0.55, 0.9, k)) * smoothstep(0.0, 0.08, k)
	canvas.draw_rect(Rect2(0, 0, vs.x, lb), INK)
	canvas.draw_rect(Rect2(0, vs.y - lb, vs.x, lb), INK)
	# ① 집중선: 안쪽 끝이 합체 지점 둘레 r_in 에서 시작해 화면 밖까지. 시간이 갈수록 r_in 이 커지고 옅어진다.
	var r_in := lerpf(vs.y * 0.16, vs.y * 0.55, ease(k, 0.6))
	var a := 1.0 - smoothstep(0.45, 1.0, k)
	for s: Array in _seeds:
		var ang: float = float(s[0]) + sin(t * 30.0 + float(s[0]) * 7.0) * 0.004
		var w: float = float(s[1])
		var inner := r_in * (1.0 + float(s[2]))
		var d := Vector2(cos(ang), sin(ang))
		var p0 := at + d * inner
		var p1 := at + Vector2(cos(ang - w), sin(ang - w)) * diag
		var p2 := at + Vector2(cos(ang + w), sin(ang + w)) * diag
		var c := (INK if s[3] else Color.WHITE)
		c.a = a * (0.85 if s[3] else 0.7)
		canvas.draw_colored_polygon(PackedVector2Array([p0, p1, p2]), c)
	if compact:
		return
	# ③ 튀는 별 조각
	for b: Array in _bits:
		var dir := Vector2(cos(float(b[0])), sin(float(b[0])))
		var p := at + dir * float(b[1]) * ease(k, 0.4) * 0.6
		var sz := float(b[2]) * (1.0 - k)
		_star(p, sz, sz * 0.45, 4, float(b[3]) + t * 9.0, Color(1, 1, 0.85, 1.0 - k), INK)
	# ② 톱니 폭발 말풍선 + 글자: 0.07초에 크게 튀어나왔다가(1.45배) 출렁이며 1배로, 끝에서 작아지며 사라진다
	var pop := 0.0
	var tk := t - 0.05
	if tk > 0.0:
		pop = 1.0 + 0.45 * exp(-tk * 9.0) * cos(tk * 34.0)
	pop *= 1.0 - smoothstep(0.78, 1.0, k)
	if pop <= 0.01:
		return
	var shake := Vector2(sin(t * 83.0), cos(t * 71.0)) * 6.0 * (1.0 - smoothstep(0.0, 0.35, k))
	var c0 := at + Vector2(0, -vs.y * 0.17) + shake
	var rad := vs.y * 0.17 * pop
	_star(c0, rad * 1.12, rad * 0.78, 14, 0.2, INK, Color(0, 0, 0, 0))            # 검은 테두리
	_star(c0, rad, rad * 0.7, 14, 0.2, BURST, Color(0, 0, 0, 0))
	_star(c0, rad * 0.62, rad * 0.45, 10, -0.3 + t * 2.0, BURST2.lightened(0.3), Color(0, 0, 0, 0))
	# 글꼴은 화면 높이로 정한 고정 크기(8px 단위)로만 굽고 팝은 변환 배율로 준다 (매 프레임 새 크기의 글리프를 굽지 않게)
	var fs := maxi(8, int(snappedf(vs.y * 0.085, 8.0)))
	var sc := vs.y * 0.085 * pop / float(fs)
	if sc * fs < 4.0 or font == null:
		return
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	canvas.draw_set_transform(c0, -0.12, Vector2.ONE * sc)
	var base := Vector2(-tw * 0.5, fs * 0.35)
	canvas.draw_string_outline(font, base + Vector2(5, 6), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.32), INK)
	canvas.draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, int(fs * 0.22), INK)
	canvas.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 톱니 별 (뾰족 n 개). outline 색이 있으면 그 색으로 가장자리를 두른다
func _star(c: Vector2, r_out: float, r_in: float, n: int, rot: float, col: Color, outline: Color) -> void:
	if r_out < 1.0:
		return
	var pts := PackedVector2Array()
	for i in n * 2:
		var r := r_out if i % 2 == 0 else r_in
		# 톱니 길이를 들쭉날쭉하게 (만화 효과 말풍선처럼)
		if i % 2 == 0:
			r *= 0.85 + 0.3 * abs(sin(float(i) * 12.9898))
		var a := rot + TAU * i / (n * 2)
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	if outline.a > 0.0:
		var o := PackedVector2Array()
		for p in pts:
			o.append(c + (p - c) * 1.18)
		canvas.draw_colored_polygon(o, outline)
	canvas.draw_colored_polygon(pts, col)
