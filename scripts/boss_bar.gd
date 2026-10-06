extends CanvasLayer
## 화면 상단 보스 체력바. 등장 시 차오르고, 깎인 만큼 흰 잔량이 뒤따라 줄어든다.
## 40% 지점에 페이즈 경계 눈금, 페이즈 2 에 들어서면 붉게 바뀌고 깜빡인다.

const W := 720.0
const H := 30.0

var root: Control
var frame: Control
var name_label: Label
var phase_label: Label
var pattern_label: Label
var hp := 1.0          # 실제 비율
var shown := 0.0       # 채워진 막대
var trail := 0.0       # 뒤따르는 흰 잔량
var fill_in := 0.0     # 등장 연출 진행
var phase := 1
var threshold := 0.4
var shake := 0.0
var flash := 0.0
var weak := false
var t := 0.0
var font: SystemFont
var _hide_tw: Tween


func _ready() -> void:
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "sans-serif"])
	font.font_weight = 800
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	frame = Control.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.draw.connect(_draw_bar)
	root.add_child(frame)
	name_label = _label("MAMMOTH  ·  강철 거수 중전차", 22, Color(1, 0.92, 0.95))
	phase_label = _label("PHASE 1", 16, Color("ffb0c0"))
	pattern_label = _label("", 18, Color(1, 0.85, 0.6))
	root.visible = false


func _label(text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


func appear() -> void:
	if _hide_tw:
		_hide_tw.kill()
		_hide_tw = null
	root.visible = true
	fill_in = 0.0
	root.modulate.a = 0.0
	var tw := root.create_tween()
	tw.tween_property(root, "modulate:a", 1.0, 0.3)


## 서서히 사라진 뒤 root 를 숨긴다 (숨긴 동안에는 _process · 다시 그리기를 하지 않는다). appear() 가 다시 보인다
func hide_bar() -> void:
	if _hide_tw:
		_hide_tw.kill()
	_hide_tw = root.create_tween()
	_hide_tw.tween_interval(1.2)
	_hide_tw.tween_property(root, "modulate:a", 0.0, 0.6)
	_hide_tw.tween_callback(root.hide)


func set_hp(k: float, big := false) -> void:
	if k < hp:
		shake = maxf(shake, 0.35 if big else 0.12)
		flash = 1.0
	hp = clampf(k, 0.0, 1.0)


func set_phase(p: int) -> void:
	phase = p
	phase_label.text = "PHASE %d" % p
	phase_label.add_theme_color_override("font_color", Color("ff5a70") if p >= 2 else Color("ffb0c0"))
	shake = 1.0


func set_pattern(text: String) -> void:
	pattern_label.text = text
	pattern_label.modulate.a = 1.0


func _process(dt: float) -> void:
	if not root.visible:
		return
	t += dt
	fill_in = minf(1.0, fill_in + dt / 1.6)
	var target := hp * smoothstep(0.0, 1.0, fill_in)
	shown = lerpf(shown, target, 1.0 - exp(-18.0 * dt)) if fill_in >= 1.0 else target
	if trail < shown or fill_in < 1.0:
		trail = shown
	else:
		trail = move_toward(trail, shown, dt * 0.35)
	shake = maxf(0.0, shake - dt * 2.5)
	flash = maxf(0.0, flash - dt * 6.0)
	var vs := root.size
	var x0 := (vs.x - W) * 0.5
	var jit := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 6.0
	frame.position = Vector2(x0, 44) + jit
	frame.size = Vector2(W, H)
	name_label.position = Vector2(x0, 12) + jit
	phase_label.reset_size()
	phase_label.position = Vector2(x0 + W - phase_label.size.x, 16) + jit
	pattern_label.reset_size()
	pattern_label.position = Vector2((vs.x - pattern_label.size.x) * 0.5, 100) + jit
	frame.queue_redraw()


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, Vector2(W, H))
	# 외곽 틀
	frame.draw_rect(r.grow(4), Color(0, 0, 0, 0.75))
	frame.draw_rect(r.grow(3), Color(1, 0.35, 0.45, 0.9), false, 2.0)
	frame.draw_rect(r, Color(0.12, 0.03, 0.07, 0.95))
	# 흰 잔량 → 본 막대
	frame.draw_rect(Rect2(0, 0, W * trail, H), Color(1, 0.95, 0.85, 0.9))
	var c := Color("ff2a4a") if phase == 1 else Color("ff1030").lerp(Color("ffb020"), 0.5 + 0.5 * sin(t * 10.0))
	if weak:
		c = Color("ffe060") if fmod(t, 0.2) < 0.1 else Color("ff8a20")
	frame.draw_rect(Rect2(0, 0, W * shown, H), c)
	# 윗단 광택 + 피격 섬광
	frame.draw_rect(Rect2(0, 0, W * shown, H * 0.35), Color(1, 1, 1, 0.22 + flash * 0.4))
	# 10칸 눈금
	for i in range(1, 10):
		var x := W * i / 10.0
		frame.draw_line(Vector2(x, H * 0.55), Vector2(x, H), Color(0, 0, 0, 0.35), 2.0)
	# 페이즈 경계 (40%)
	var px := W * threshold
	frame.draw_line(Vector2(px, -8), Vector2(px, H + 8), Color(1, 0.95, 0.6) if phase == 1 else Color(1, 1, 1, 0.3), 3.0)
	frame.draw_string(font, Vector2(px - 14, H + 22), "%d%%" % roundi(threshold * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.7, 0.9 if phase == 1 else 0.3))
	frame.draw_string(font, Vector2(W - 64, H + 22), "%d%%" % int(ceil(hp * 100.0)), HORIZONTAL_ALIGNMENT_RIGHT, 64, 15, Color(1, 1, 1, 0.95))
