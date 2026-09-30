extends CanvasLayer
## 연출 테스트 씬 안내: 조작 키 · 현재 옵션 · B안 6컷 타임라인과 현재 컷 표시. U 키로 숨긴다.

const Director := preload("res://scripts/lab_mammoth_b/mammoth_b_director.gd")

var root: Control
var info: Label
var cut_label: Label
var line: Control
var font: SystemFont
var director: Director
var text := ""


func _ready() -> void:
	layer = 30
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Apple SD Gothic Neo", "Noto Sans CJK KR", "sans-serif"])
	font.font_weight = 700
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	info = _label(15, Color(0.85, 0.9, 1.0))
	info.position = Vector2(18, 16)
	cut_label = _label(22, Color("ffd166"))
	line = Control.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(_draw_line)
	root.add_child(line)


func _label(size: int, c: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	return l


func _process(_dt: float) -> void:
	info.text = text
	var vs := root.size
	line.position = Vector2(vs.x * 0.5 - 330, vs.y - 58)
	line.size = Vector2(660, 40)
	line.queue_redraw()
	if director and (director.active or director.done):
		var c := director.cut_info()
		cut_label.text = "%s  %s   %.2fs" % [c[1], c[2], minf(director.T, Director.DURATION)]
	else:
		cut_label.text = "B안 · 궤도 파손과 전복  —  Enter 로 재생"
	cut_label.reset_size()
	cut_label.position = Vector2((vs.x - cut_label.size.x) * 0.5, vs.y - 96)


func _draw_line() -> void:
	var w := line.size.x
	var dur := Director.DURATION
	line.draw_rect(Rect2(0, 14, w, 8), Color(0.05, 0.06, 0.12, 0.8))
	var cols := [Color("7cf5ff"), Color("5ad0ff"), Color("ffd166"), Color("ff9a3a"), Color("ff4a5a"), Color("9a8aff")]
	for i in Director.CUTS.size():
		var c: Array = Director.CUTS[i]
		var t0: float = c[0]
		var t1: float = Director.CUTS[i + 1][0] if i + 1 < Director.CUTS.size() else dur
		var x0 := t0 / dur * w
		var x1 := t1 / dur * w
		line.draw_rect(Rect2(x0 + 1, 15, x1 - x0 - 2, 6), cols[i] * Color(1, 1, 1, 0.55))
		line.draw_string(font, Vector2(x0 + 3, 36), c[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.85, 1.0))
	if director and (director.active or director.done):
		var x := minf(director.T, dur) / dur * w
		line.draw_rect(Rect2(x - 1.5, 6, 3, 22), Color.WHITE)
