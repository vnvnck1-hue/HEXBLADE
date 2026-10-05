class_name TrainingPanel
extends PanelContainer
## 전투 테스트장 왼쪽 설정 패널. 반투명 남색 판 하나에 [키] 이름 ··· 값 행을 묶음별로 정리한다.
## 행의 값은 Callable 로 받아 매 프레임 refresh() 로 갱신 (ON 은 민트, OFF 는 흐리게).
## 아래 extra 칸에는 상속 씬(_panel_text)이 덧붙이는 자유 글자가 들어간다.

const BG := Color(0.05, 0.05, 0.13, 0.82)
const EDGE := Color(0.55, 0.62, 1.0, 0.22)
const KEY_BG := Color(1, 1, 1, 0.1)
const TITLE := Color(0.62, 0.92, 1.0)
const SECTION := Color(0.62, 0.66, 0.85)
const NAME := Color(0.88, 0.9, 1.0)
const VALUE := Color(1.0, 0.92, 0.62)
const ON := Color(0.45, 1.0, 0.8)
const OFF := Color(0.55, 0.57, 0.7)
const FOOT := Color(0.55, 0.58, 0.75)
const NAME_W := 104.0           # 이름 칸 최소 폭 (묶음이 달라도 값 칸이 같은 자리에 오게)

var _box: VBoxContainer
var _grid: GridContainer
var _rows: Array = []           # [값 Label, Callable]
var extra: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)


func title(text: String) -> void:
	_box.add_child(_label(text, 14, TITLE))


## 묶음 머리 (새 3열 표를 시작한다)
func section(text: String) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 3)
	_box.add_child(gap)
	_box.add_child(_label(text, 11, SECTION))
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 1)
	_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(_grid)


## [키] 이름 ··· 값. value 가 비어 있으면 값 칸 없음 (누르면 실행되는 동작)
func row(key: String, label: String, value := Callable()) -> void:
	if _grid == null:
		section("")
	_grid.add_child(_key_chip(key))
	var n := _label(label, 13, NAME)
	n.custom_minimum_size = Vector2(NAME_W, 0)
	_grid.add_child(n)
	var v := _label("", 13, VALUE)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_child(v)
	if value.is_valid():
		_rows.append([v, value])


func footer(text: String) -> void:
	extra = _label("", 12, NAME)
	extra.visible = false
	_box.add_child(extra)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	_box.add_child(gap)
	_box.add_child(_label(text, 11, FOOT))


func refresh(extra_text := "") -> void:
	extra_text = extra_text.strip_edges()
	for r: Array in _rows:
		var l: Label = r[0]
		var s := String((r[1] as Callable).call())
		if l.text != s:
			l.text = s
			l.add_theme_color_override("font_color", ON if s == "ON" else (OFF if s == "OFF" else VALUE))
	if extra:
		extra.visible = extra_text != ""
		if extra.text != extra_text:
			extra.text = extra_text


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _key_chip(key: String) -> Control:
	var c := PanelContainer.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = KEY_BG
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 0
	sb.content_margin_bottom = 1
	c.add_theme_stylebox_override("panel", sb)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l := _label(key, 11, Color(1, 1, 1, 0.92))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(16, 0)
	c.add_child(l)
	return c
