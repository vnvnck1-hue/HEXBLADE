class_name LobbyArt
extends Control
## 1920×1080 로비 전용 캔버스. 게임 진입은 Lobby가 담당한다.

const DESIGN := Vector2(1920, 1080)
const CREAM := Color("f5eedb")
const INK := Color("102019")
const SECONDARY := Color("a7b8d5")
const LIME := Color("82ff43")
const KEYART := preload("res://assets/ui/lobby/keyart.png")
const NORMAL := preload("res://assets/ui/lobby/02_menu_normal.svg")
const FOCUS := preload("res://assets/ui/lobby/03_menu_focus.svg")
const PRESSED := preload("res://assets/ui/lobby/04_menu_pressed.svg")
const ARROW := preload("res://assets/ui/lobby/07_arrow_cream.svg")
const HOT_ARROW := preload("res://assets/ui/lobby/08_arrow_ink.svg")

var canvas: Control
var menus: Array[Button] = []
var rows: Array[Button] = []
var drawer: Control
var scroll: ScrollContainer
var list: VBoxContainer
var close_button: Button
var last_row := 0
var font: Font
var italic_font: Font


class ArtMenuButton extends Button:
	var title_label: Label
	var subtitle_label: Label

	func _ready() -> void:
		mouse_entered.connect(grab_focus)
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		button_down.connect(queue_redraw)
		button_up.connect(queue_redraw)

	func _draw() -> void:
		var hot := has_focus() and not disabled
		var skin: Texture2D = PRESSED if is_pressed() else (FOCUS if hot else NORMAL)
		draw_texture_rect(skin, Rect2(Vector2.ZERO, size), false)
		draw_texture_rect(HOT_ARROW if hot else ARROW, Rect2(size.x - 107, 39, 48, 48), false)
		if title_label:
			title_label.modulate = INK if hot else CREAM
		if subtitle_label:
			subtitle_label.modulate = INK if hot else SECONDARY


func build(scenes: Array, text_font: Font) -> void:
	font = text_font
	# 한글 시스템 글꼴에 이탤릭 면이 없어도 사선 메뉴의 글자 기울기를 유지한다.
	var italic := FontVariation.new()
	italic.base_font = text_font
	italic.variation_transform = Transform2D(Vector2(1, 0.22), Vector2(0, 1), Vector2.ZERO)
	italic_font = italic
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var backdrop := ColorRect.new()
	backdrop.color = Color("100f1b")
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	canvas = Control.new()
	canvas.size = DESIGN
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	_texture(KEYART, Rect2(0, 0, 1920, 1080), canvas)
	_texture(preload("res://assets/ui/lobby/01_logo_mark.svg"), Rect2(170, 74, 192, 192), canvas)
	_texture(preload("res://assets/ui/lobby/17_title_wordmark.svg"), Rect2(375, 132, 726, 86), canvas)
	_texture(preload("res://assets/ui/lobby/10_logo_underline.svg"), Rect2(375, 242, 336, 18), canvas)
	_text("쿼터뷰 3D 액션 로그라이트", 27, Rect2(372, 282, 670, 36), canvas, SECONDARY)
	var titles := ["섹터 런", "연출 테스트", "테스트 씬", "종료"]
	var subtitles := ["HEX SECTOR RUN", "MAMMOTH B", "", ""]
	for i in 4:
		var b := ArtMenuButton.new()
		b.name = ["SectorRun", "DeathTest", "TestScenes", "Quit"][i]
		# 접근성/기존 도구는 Button.text를 읽고, 실제 글자는 아래 별도 Label로 배치한다.
		b.text = titles[i]
		for color_name in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color"]:
			b.add_theme_color_override(color_name, Color.TRANSPARENT)
		b.position = Vector2(157, 344 + 140 * i)
		b.size = Vector2(540 if i == 3 else 624, 125)
		b.tooltip_text = titles[i]
		b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
		canvas.add_child(b)
		b.title_label = _text(titles[i], 49, Rect2(57, 20 if subtitles[i] else 38, 460, 64), b, CREAM, true)
		if subtitles[i]:
			b.subtitle_label = _text(subtitles[i], 25, Rect2(57, 78, 460, 35), b, SECONDARY, true)
		menus.append(b)
		b.focus_entered.connect(func(): Sfx.play("tink", 0.02, -10.0))
	_cycle(menus)
	_texture(preload("res://assets/ui/lobby/11_hint_plate.svg"), Rect2(161, 933, 600, 66), canvas)
	_text("↑↓ 선택   ENTER 결정", 25, Rect2(210, 943, 550, 48), canvas, SECONDARY)
	_text("게임 중 ESC 로비   ·   F11 전체 화면", 18, Rect2(169, 1013, 760, 34), canvas, SECONDARY)
	_build_drawer(scenes)
	resized.connect(fit)
	fit()


func fit() -> void:
	var s := minf(size.x / DESIGN.x, size.y / DESIGN.y)
	canvas.scale = Vector2(s, s)
	canvas.position = (size - DESIGN * s) * 0.5


func _build_drawer(scenes: Array) -> void:
	drawer = Control.new()
	drawer.name = "TestDrawer"
	drawer.size = DESIGN
	drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer.visible = false
	canvas.add_child(drawer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.22)
	dim.size = DESIGN
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer.add_child(dim)
	var panel := Control.new()
	panel.position = Vector2(166, 334)
	panel.size = Vector2(760, 650)
	drawer.add_child(panel)
	_texture(preload("res://assets/ui/lobby/12_drawer_panel.svg"), Rect2(0, 0, 760, 650), panel)
	_text("테스트 씬", 32, Rect2(34, 25, 420, 48), panel, CREAM)
	close_button = Button.new()
	close_button.text = "ESC 닫기"
	close_button.position = Vector2(540, 26)
	close_button.size = Vector2(180, 48)
	_style_row(close_button)
	panel.add_child(close_button)
	close_button.pressed.connect(set_drawer.bind(false))
	scroll = ScrollContainer.new()
	scroll.position = Vector2(28, 92)
	scroll.size = Vector2(704, 526)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	panel.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for i in scenes.size():
		var entry: Dictionary = scenes[i]
		var b := Button.new()
		b.name = "Scene%d" % i
		b.tooltip_text = entry.title + "\n" + entry.desc
		b.custom_minimum_size = Vector2(0, 130)
		_style_row(b)
		list.add_child(b)
		var content := VBoxContainer.new()
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 20
		content.offset_right = -20
		content.offset_top = 14
		content.offset_bottom = -14
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 6)
		b.add_child(content)
		for field in ["title", "desc"]:
			var label := Label.new()
			label.text = entry[field]
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_override("font", font)
			label.add_theme_font_size_override("font_size", 26 if field == "title" else 20)
			label.add_theme_color_override("font_color", CREAM if field == "title" else SECONDARY)
			content.add_child(label)
		content.minimum_size_changed.connect(func(): b.custom_minimum_size.y = maxf(130, content.get_combined_minimum_size().y + 28))
		b.mouse_entered.connect(b.grab_focus)
		b.focus_entered.connect(_row_focus.bind(i))
		rows.append(b)
	var bottom_space := Control.new()
	bottom_space.custom_minimum_size.y = 8
	bottom_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(bottom_space)
	var controls: Array[Button] = rows.duplicate()
	controls.append(close_button)
	_cycle(controls)


func _row_focus(index: int) -> void:
	last_row = index
	_ensure_row.call_deferred(index)
	Sfx.play("tink", 0.02, -10.0)


func _ensure_row(index: int) -> void:
	scroll.ensure_control_visible(rows[index])
	# ScrollContainer는 정수 스크롤을 쓰므로 축소 배율에서 끝 1px이 잘릴 수 있다.
	var bounds := scroll.get_global_rect()
	var row := rows[index].get_global_rect()
	if row.end.y > bounds.end.y:
		scroll.scroll_vertical += ceili((row.end.y - bounds.end.y) / canvas.scale.y) + 1
	elif row.position.y < bounds.position.y:
		scroll.scroll_vertical -= ceili((bounds.position.y - row.position.y) / canvas.scale.y) + 1


func set_drawer(open: bool) -> void:
	drawer.visible = open
	for b in menus:
		b.disabled = open
		b.focus_mode = Control.FOCUS_NONE if open else Control.FOCUS_ALL
	if open and not rows.is_empty():
		rows[last_row].grab_focus()
		_ensure_row.call_deferred(last_row)
	else:
		menus[2].grab_focus()


func _cycle(buttons: Array[Button]) -> void:
	for i in buttons.size():
		var b := buttons[i]
		var prev := b.get_path_to(buttons[posmod(i - 1, buttons.size())])
		var next := b.get_path_to(buttons[(i + 1) % buttons.size()])
		b.focus_neighbor_top = prev
		b.focus_neighbor_bottom = next
		b.focus_previous = prev
		b.focus_next = next
		b.focus_neighbor_left = prev
		b.focus_neighbor_right = next


func _style_row(b: Button) -> void:
	for state in ["normal", "hover", "focus", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("303049") if state == "normal" else Color("425b42")
		box.border_color = Color("676379") if state == "normal" else LIME
		box.set_border_width_all(1 if state == "normal" else 2)
		box.content_margin_left = 16
		box.content_margin_right = 16
		b.add_theme_stylebox_override(state, box)
		b.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), CREAM)
		b.add_theme_font_size_override("font_size", 22)


func _texture(tex: Texture2D, rect: Rect2, parent: Control) -> TextureRect:
	var node := TextureRect.new()
	node.texture = tex
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_SCALE
	node.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	node.position = rect.position
	node.size = rect.size
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node


func _text(text: String, px: int, rect: Rect2, parent: Control, color: Color, italic := false) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", italic_font if italic else font)
	label.add_theme_font_size_override("font_size", px)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
