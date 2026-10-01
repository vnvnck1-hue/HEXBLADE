class_name CutIn
extends CanvasLayer
## 연출 전용: 큰 순간에만 화면을 가로지르는 2D 컷인 타이포 (젠레스 존 제로식 그래픽 레이어).
## - 비스듬한 띠가 옆에서 쓸려 들어오고, 굵은 기울임 글자가 크게 박혔다가 제자리를 찾은 뒤 옆으로 빠져나간다
## - 띠 안에는 만화 속도선이 흐르고, 글자 뒤에는 강조색 그림자 글자가 한 박자 늦게 따라온다
## - 흑백 임팩트 프레임이 도는 중이면 끝난 뒤에 시작한다 (흑백 대비를 덮지 않게)
## 드문 순간(관통 일격 다중 적중 · 최대 레이저 · 보스 페이즈 전환 · 보스 격파)에만 부른다. 패링은 글자 없이 둔다.
## 시간은 연출용 실제 시간(Parry.now_ms)으로 재서 히트스탑·슬로우 중에도 길이가 같다. 판정과 무관.
## 실행 인자 `--nocutin` 으로 끌 수 있다.

static var inst: CutIn

const DARK := Color(0.035, 0.025, 0.07)
const TILT := -0.12                 # 띠 기울기 (rad)
const IN_T := 0.09                  # 띠가 쓸려 들어오는 시간
const SLAM_T := 0.1                 # 글자가 박히는 시간
const OUT_T := 0.16                 # 빠져나가는 시간

var enabled := true
var rig: Node2D
var band: Polygon2D
var edge_a: Polygon2D
var edge_b: Polygon2D
var streaks: Array[Polygon2D] = []
var title: Label
var shadow: Label
var sub: Label
var _start := -1
var _hold := 0.35
var _big := false
var _accent := Color.WHITE
var _y := 0.66                      # 띠 중심의 화면 높이 비율


func _exit_tree() -> void:
	if inst == self:
		inst = null


## 없으면 현재 전투 씬(Main)에 붙여서 돌려준다
static func ensure() -> CutIn:
	if inst == null and Main.inst:
		var c := CutIn.new()
		c.enabled = not OS.get_cmdline_user_args().has("--nocutin")
		Main.inst.add_child(c)
	return inst


## 짧은 컷인 (약 0.6초). accent 는 띠 테두리 · 그림자 글자 색
static func slam(text: String, small := "", accent := Color(1.0, 0.3, 0.35), hold := 0.34) -> void:
	var c := ensure()
	if c == null or not c.enabled:
		return
	c._queue(text, small, accent, hold, false, 0.66)


## 보스 격파용 큰 컷인: 화면 가운데를 굵게 가르고 더 오래 머문다
static func showtime(text: String, small: String, accent: Color, hold := 0.78) -> void:
	var c := ensure()
	if c == null or not c.enabled:
		return
	c._queue(text, small, accent, hold, true, 0.56)


static func active() -> bool:
	return inst != null and inst._start >= 0


func _ready() -> void:
	inst = self
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	rig = Node2D.new()
	root.add_child(rig)
	band = _poly(Color(DARK, 0.92))
	edge_a = _poly(Color.WHITE)
	edge_b = _poly(Color.WHITE)
	for i in 9:
		streaks.append(_poly(Color(1, 1, 1, 0.16)))
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Arial Black", "Impact", "Malgun Gothic", "맑은 고딕", "sans-serif"])
	f.font_weight = 900
	f.font_italic = true
	var fs := SystemFont.new()
	fs.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Apple SD Gothic Neo", "Noto Sans CJK KR", "sans-serif"])
	fs.font_weight = 700
	shadow = _text(f, 96)
	title = _text(f, 96)
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_color_override("font_outline_color", DARK)
	sub = _text(fs, 22)
	sub.add_theme_constant_override("outline_size", 8)
	sub.add_theme_color_override("font_outline_color", DARK)
	visible = false


func _poly(c: Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.color = c
	rig.add_child(p)
	return p


func _text(f: Font, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", f)
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rig.add_child(l)
	return l


func _queue(text: String, small: String, accent: Color, hold: float, big: bool, y: float) -> void:
	var go := func() -> void:
		_begin(text, small, accent, hold, big, y)
	if ImpactFrame.inst and ImpactFrame.inst.active():
		ImpactFrame.inst.after(go)
	else:
		go.call()


func _begin(text: String, small: String, accent: Color, hold: float, big: bool, y: float) -> void:
	_start = Parry.now_ms()
	_hold = hold
	_big = big
	_accent = accent
	_y = y
	var fsz := 132 if big else 88
	title.text = text
	title.add_theme_font_size_override("font_size", fsz)
	title.reset_size()
	# 긴 글자는 화면 폭의 70% 안에 들어오게 줄인다
	var max_w := get_viewport().get_visible_rect().size.x * 0.7
	if title.size.x > max_w:
		fsz = int(fsz * max_w / title.size.x)
	for l in [title, shadow]:
		(l as Label).text = text
		(l as Label).add_theme_font_size_override("font_size", fsz)
		(l as Label).size = Vector2.ZERO
		(l as Label).reset_size()
	title.add_theme_color_override("font_color", Color(1.0, 0.99, 0.95))
	shadow.add_theme_color_override("font_color", accent)
	sub.text = small
	sub.add_theme_font_size_override("font_size", 26 if big else 21)
	sub.add_theme_color_override("font_color", Color(1.0, 0.97, 0.92))
	sub.reset_size()
	edge_a.color = accent
	edge_b.color = accent.lerp(Color.WHITE, 0.4)
	visible = true
	print("CUTIN %s" % text)
	_process(0.0)


func _hide() -> void:
	visible = false
	_start = -1


func _process(_dt: float) -> void:
	if _start < 0:
		return
	var e := (Parry.now_ms() - _start) * 0.001
	var total := IN_T + _hold + OUT_T
	if e >= total:
		_hide()
		return
	var vs := get_viewport().get_visible_rect().size
	rig.position = Vector2(vs.x * 0.5, vs.y * _y)
	rig.rotation = TILT
	var half_w := vs.length() * 0.62
	var bh := (vs.y * (0.2 if _big else 0.13))
	# 들어옴: 띠가 오른쪽에서 쓸려 오며 두께가 붙는다 / 나감: 두께가 얇아지며 왼쪽으로 빠진다
	var k_in := 1.0 - pow(1.0 - clampf(e / IN_T, 0.0, 1.0), 4.0)
	var out_e := clampf((e - IN_T - _hold) / OUT_T, 0.0, 1.0)
	var k_out := out_e * out_e
	var sweep := (1.0 - k_in) * vs.x * 1.1 - k_out * vs.x * 0.35
	var thick := bh * (0.35 + 0.65 * k_in) * (1.0 - k_out)
	var drift := -e * (40.0 if _big else 60.0)
	_quad(band, sweep, half_w, thick * 0.5, 0.0)
	_quad(edge_a, sweep + 40.0, half_w, 3.0 + 3.0 * k_in, -thick * 0.5 - 5.0)
	_quad(edge_b, sweep - 40.0, half_w, 2.0 + 2.0 * k_in, thick * 0.5 + 4.0)
	# 띠 안 속도선: 오른쪽 → 왼쪽으로 빠르게 흐른다 (프레임마다 조금씩 흔들림)
	for i in streaks.size():
		var s := streaks[i]
		var row := (float(i) / (streaks.size() - 1) - 0.5) * thick * 0.86
		var speed := 2600.0 + 700.0 * fmod(i * 0.37, 1.0)
		var ln := 140.0 + 160.0 * fmod(i * 0.61, 1.0)
		var x := fposmod(-e * speed + i * 397.0, half_w * 2.0) - half_w
		s.polygon = PackedVector2Array([Vector2(x + sweep, row - 1.2), Vector2(x + sweep + ln, row - 0.6),
			Vector2(x + sweep + ln, row + 0.6), Vector2(x + sweep, row + 1.2)])
		s.visible = thick > 6.0
	# 글자: 크게(2.4배) 박혔다가 살짝 넘쳐 제자리 → 천천히 흐름 → 옆으로 빠지며 사라짐
	var ts := clampf((e - 0.03) / SLAM_T, 0.0, 1.0)
	var sc := lerpf(2.4, 1.0, 1.0 - pow(1.0 - ts, 5.0))
	if ts >= 1.0:
		sc = 1.0 + 0.04 * exp(-(e - 0.03 - SLAM_T) * 18.0) * sin((e - 0.03 - SLAM_T) * 40.0)
	var a := clampf(ts * 3.0, 0.0, 1.0) * (1.0 - k_out)
	var tx := sweep * 0.25 + drift - k_out * 220.0
	_place(title, sc, Vector2(tx, 0.0), a)
	var lag := clampf((e - 0.07) / SLAM_T, 0.0, 1.0)
	var sh_off := Vector2(10.0, 8.0) * (1.0 + (1.0 - lag) * 3.0)
	_place(shadow, sc * lerpf(1.25, 1.0, lag), Vector2(tx, 0.0) + sh_off, a * lag)
	# 부제는 띠 아래 테두리 밖, 제목 왼쪽 끝에 맞춘다 (제목과 겹치지 않게)
	sub.position = Vector2(tx - title.size.x * 0.5 + 24.0, thick * 0.5 + 12.0 + (1.0 - k_in) * 20.0)
	sub.modulate.a = clampf((e - 0.1) / 0.08, 0.0, 1.0) * (1.0 - k_out)


func _quad(p: Polygon2D, x: float, half_w: float, half_h: float, y: float) -> void:
	# 양 끝을 비스듬히 자른 평행사변형
	var sk := half_h * 1.4
	p.polygon = PackedVector2Array([Vector2(x - half_w + sk, y - half_h), Vector2(x + half_w + sk, y - half_h),
		Vector2(x + half_w - sk, y + half_h), Vector2(x - half_w - sk, y + half_h)])


func _place(l: Label, s: float, at: Vector2, a: float) -> void:
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2.ONE * s
	l.position = at - l.size * 0.5
	l.modulate.a = a
