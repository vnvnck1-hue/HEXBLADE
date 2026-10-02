class_name DialogueView
extends Control
## 대화 화면. DialogueRunner 를 받아 배경 · 인물 · 대화창 · 선택지 · 기록 · 자동/넘기기를 그린다.
## 조작 (전투 키와 겹치지 않게):
##   좌클릭 · Space · Enter · 휠 아래  진행 (출력 중이면 문장 완성)
##   Ctrl 누르고 있기  모두 빨리 넘기기      S  읽은 대사만 넘기기      Tab  선택지까지 건너뛰고 요약 보기
##   A  자동 진행      L · 휠 위  기록      H · 우클릭  UI 숨기기      1~4  선택지
##   [ ]  글자 속도     - =  글자 크기      M  움직임 줄이기

signal finished

const BASE_CPS := [22.0, 40.0, 70.0, 100000.0]
const SPEED_NAMES := ["느림", "보통", "빠름", "즉시"]
const SIZES := [24, 28, 32, 36]
const CREAM := Color("efe6d6")
const INK := Color(0.055, 0.05, 0.06, 0.97)
const SKIP_STEP := 0.06

## 설정은 씬을 다시 불러도 유지
static var speed_idx := 1
static var size_idx := 1
static var reduce_motion := false

var runner: DialogueRunner
var voice: DialogueVoice
var font: SystemFont
var bold: SystemFont

var stage: Control
var backdrop: HangarBackdrop
var people: Control
var ui: Control
var box: Control
var text: RichTextLabel
var plate_name: Label
var plate_en: Label
var title_label: Label
var hint: Label
var toast: Label
var choice_box: VBoxContainer
var log_layer: Control
var log_list: VBoxContainer
var log_scroll: ScrollContainer
var summary_layer: Control
var summary_text: RichTextLabel
var flash_rect: ColorRect
var btn_log: Button
var btn_auto: Button
var btn_skip: Button

var portraits := {}
var line: Dictionary = {}
var accent := CREAM
var shown := 0.0
var total := 0
var pause_left := 0.0
var typing := false
var auto := false
var skip_read := false
var auto_wait := 0.0
var skip_wait := 0.0
var wait_left := -1.0
var shake_t := 0.0
var shake_pow := 0.0
var toast_t := 0.0
var t := 0.0
var _blip_n := 0
var _last_visible := 0
var _ended := false
var _mark_on: StyleBoxFlat           # 자동 · 넘기기 버튼의 켬/끔 바탕 (한 번만 만든다)
var _mark_off: StyleBoxFlat
static var _calm_rx: Array[RegEx] = []   # 기록에서 흔들림 · 물결 태그를 지우는 정규식 (한 번만 컴파일)
## 자동 실행 · 테스트용: 모든 대사를 빨리 넘긴다
var fast_forward := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Apple SD Gothic Neo", "Noto Sans CJK KR", "sans-serif"])
	font.font_weight = 700
	bold = font.duplicate()
	bold.font_weight = 900
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 18
	theme = th
	voice = DialogueVoice.new()
	add_child(voice)
	_build()


## 대사 진행기를 연결하고 시작한다
func play(r: DialogueRunner, label := "") -> void:
	runner = r
	runner.said.connect(_on_said)
	runner.asked.connect(_on_asked)
	runner.cue.connect(_on_cue)
	runner.ended.connect(_on_ended)
	runner.start(label)


# ── 구성 ────────────────────────────────────────────────

func _build() -> void:
	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	backdrop = HangarBackdrop.new()
	backdrop.font = bold
	stage.add_child(backdrop)
	people = Control.new()
	people.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	people.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(people)

	ui = Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.z_index = 50   # 인물(z 0~10) 위에
	add_child(ui)

	# 대화창 (아래 고정)
	box = Control.new()
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = 30
	box.offset_right = -30
	box.offset_top = -244
	box.offset_bottom = -38
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.draw.connect(_draw_box)
	ui.add_child(box)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 한국어 낱말 중간에서 끊지 않게
	text.scroll_active = false
	text.fit_content = false
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.offset_left = 64
	text.offset_right = -150
	text.offset_top = 46
	text.offset_bottom = -20
	text.add_theme_font_override("normal_font", font)
	text.add_theme_font_override("bold_font", bold)
	text.add_theme_color_override("default_color", CREAM)
	text.add_theme_constant_override("line_separation", 8)
	text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	text.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(text)
	plate_name = _label("", 34, Color.WHITE)
	plate_name.position = Vector2(66, -28)
	box.add_child(plate_name)
	plate_en = _label("", 16, Color(1, 1, 1, 0.7))
	box.add_child(plate_en)

	# 위: 장소 제목 · 버튼
	title_label = _label("", 22, CREAM)
	title_label.position = Vector2(46, 22)
	ui.add_child(title_label)
	var bar := HBoxContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = -560
	bar.offset_right = -24
	bar.offset_top = 18
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.add_theme_constant_override("separation", 10)
	ui.add_child(bar)
	btn_log = _top_button("≡  기록  L", bar, _open_log)
	btn_auto = _top_button("▶  자동  A", bar, _toggle_auto)
	btn_skip = _top_button("▶▶ 넘기기  S", bar, _toggle_skip)
	_top_button("◐  숨기기  H", bar, _toggle_hide)

	hint = _label("", 14, Color(0.75, 0.75, 0.8, 0.75))
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 40
	hint.offset_top = -27
	ui.add_child(hint)

	toast = _label("", 20, Color.WHITE)
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.offset_top = 70
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ui.add_child(toast)

	# 선택지 (대화창 위 가운데)
	choice_box = VBoxContainer.new()
	choice_box.anchor_left = 0.5
	choice_box.anchor_right = 0.5
	choice_box.anchor_top = 1.0
	choice_box.anchor_bottom = 1.0
	choice_box.offset_left = -330
	choice_box.offset_right = 330
	choice_box.offset_bottom = -280
	choice_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	choice_box.add_theme_constant_override("separation", 12)
	ui.add_child(choice_box)

	_build_log()
	_build_summary()
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.z_index = 70
	add_child(flash_rect)
	_apply_size()
	_refresh_hint()


func _build_log() -> void:
	log_layer = Control.new()
	log_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	log_layer.visible = false
	log_layer.z_index = 60
	add_child(log_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.9)
	log_layer.add_child(dim)
	var head := _label("대화 기록   ·   L · Esc · 우클릭 닫기   ·   휠로 넘겨 보기", 20, CREAM)
	head.position = Vector2(60, 28)
	log_layer.add_child(head)
	log_scroll = ScrollContainer.new()
	log_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	log_scroll.offset_left = 60
	log_scroll.offset_right = -60
	log_scroll.offset_top = 76
	log_scroll.offset_bottom = -30
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_layer.add_child(log_scroll)
	log_list = VBoxContainer.new()
	log_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_list.add_theme_constant_override("separation", 14)
	log_scroll.add_child(log_list)


func _build_summary() -> void:
	summary_layer = Control.new()
	summary_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	summary_layer.visible = false
	summary_layer.z_index = 60
	add_child(summary_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.02, 0.04, 0.82)
	summary_layer.add_child(dim)
	summary_text = RichTextLabel.new()
	summary_text.bbcode_enabled = true
	summary_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 한국어 낱말 중간에서 끊지 않게
	summary_text.set_anchors_preset(Control.PRESET_CENTER)
	summary_text.custom_minimum_size = Vector2(720, 320)
	summary_text.position = -Vector2(360, 160)
	summary_text.add_theme_font_override("normal_font", font)
	summary_text.add_theme_font_override("bold_font", bold)
	summary_text.add_theme_font_size_override("normal_font_size", 22)
	summary_text.add_theme_font_size_override("bold_font_size", 28)
	summary_text.add_theme_color_override("default_color", CREAM)
	summary_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card := _flat(INK, CREAM, 3)
	card.border_width_left = 10
	card.border_color = Color("c8303c")
	card.content_margin_left = 40
	card.content_margin_right = 36
	card.content_margin_top = 30
	card.content_margin_bottom = 26
	summary_text.add_theme_stylebox_override("normal", card)
	summary_layer.add_child(summary_text)


func _label(s: String, sz: int, c: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _top_button(s: String, parent: Control, cb: Callable) -> Button:
	var b := Button.new()
	b.text = s
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(124, 40)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_stylebox_override("normal", _flat(Color(0.05, 0.05, 0.06, 0.82), Color(CREAM, 0.55), 2))
	b.add_theme_stylebox_override("hover", _flat(Color(0.2, 0.06, 0.07, 0.9), CREAM, 2))
	b.add_theme_stylebox_override("pressed", _flat(Color(0.5, 0.1, 0.12, 0.9), CREAM, 2))
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _flat(fill: Color, border: Color, w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(w)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


# ── 진행기 신호 ─────────────────────────────────────────

func _on_said(l: Dictionary) -> void:
	line = l
	var who: String = l.who
	var info := DialogueCast.info(who) if who != "" else {}
	accent = info.get("color", Color(0.55, 0.55, 0.6))
	if DialogueCast.has_portrait(who):
		var p: DialoguePortrait = portraits.get(who)
		if p == null:
			p = _enter(who, _free_slot(), l.expr)
		elif l.expr != "":
			p.set_expr(l.expr, not reduce_motion)
		if l.punch and not reduce_motion:
			p.shake(1.0)
			p.hop(1.2)
	for id in portraits:
		var q: DialoguePortrait = portraits[id]
		q.active = id == who
		q.z_index = 10 if id == who else (0 if q.slot in DialoguePortrait.BACK_SLOTS else 2)
	# 이름표: 화자 없음(해설)이면 숨기고 글자를 기울여 회색으로
	plate_name.visible = who != ""
	plate_en.visible = who != ""
	plate_name.text = info.get("name", "")
	plate_en.text = info.get("en", "")
	plate_en.position = Vector2(plate_name.position.x + plate_name.get_minimum_size().x + 14, -14)
	var bb: String = l.bb
	if who == "":
		bb = "[i][color=#b4b0c0]" + bb + "[/color][/i]"
	text.text = bb
	text.visible_characters = 0
	total = text.get_total_character_count()
	if total <= 0:
		total = str(l.plain).length()
	shown = 0.0
	_last_visible = 0
	_blip_n = 0
	pause_left = 0.0
	typing = true
	auto_wait = 0.0
	box.queue_redraw()
	_log_add(info.get("name", ""), accent, bb)
	if skip_read and not l.was_seen and not Input.is_key_pressed(KEY_CTRL):
		skip_read = false
		_toast("읽지 않은 대사 — 넘기기 멈춤")
	_refresh_buttons()


func _on_asked(options: Array) -> void:
	_clear_choices()
	auto_wait = 0.0
	for i in options.size():
		var o: Dictionary = options[i]
		var b := Button.new()
		var tag: String = ("[%s]  " % o.tag) if o.tag != "" else ""
		b.text = "%d   %s%s%s" % [i + 1, tag, DialogueScript.markup(o.text).plain, "   ✓" if o.picked else ""]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 58)
		b.add_theme_font_size_override("font_size", 24)
		var fc := Color(CREAM, 0.6) if o.picked else CREAM
		b.add_theme_color_override("font_color", fc)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		b.add_theme_color_override("font_focus_color", Color.WHITE)
		b.add_theme_stylebox_override("normal", _flat(Color(0.05, 0.05, 0.06, 0.92), Color(CREAM, 0.4), 2))
		var hot := _flat(Color(0.55, 0.09, 0.12, 0.95), CREAM, 3)
		b.add_theme_stylebox_override("hover", hot)
		b.add_theme_stylebox_override("focus", hot)
		b.add_theme_stylebox_override("pressed", _flat(Color(0.8, 0.15, 0.18, 1), Color.WHITE, 3))
		b.pressed.connect(_pick.bind(i))
		b.mouse_entered.connect(b.grab_focus)
		b.focus_entered.connect(func(): Sfx.play("tink", 0.02, -12.0))
		choice_box.add_child(b)
	# 선택지는 자동 · 넘기기를 멈춘다 (빨리 넘기기 중이라도 고르게)
	skip_read = false
	_refresh_buttons()
	if choice_box.get_child_count() > 0:
		(choice_box.get_child(0) as Button).grab_focus.call_deferred()


func _on_cue(c: Dictionary) -> void:
	match c.op:
		"title":
			title_label.text = c.text
		"enter":
			if portraits.has(c.who):
				portraits[c.who].place(c.slot)
				if c.expr != "":
					portraits[c.who].set_expr(c.expr, not reduce_motion)
			else:
				_enter(c.who, c.slot, c.expr)
		"exit":
			var ids: Array = portraits.keys() if c.who in ["", "all"] else [c.who]
			for id in ids:
				if portraits.has(id):
					portraits[id].leave()
					portraits.erase(id)
		"expr":
			if portraits.has(c.who):
				portraits[c.who].set_expr(c.expr, not reduce_motion)
		"move":
			if portraits.has(c.who):
				portraits[c.who].place(c.slot)
		"shake":
			if not reduce_motion and not _fast():
				shake_t = 0.35 + c.power * 0.3
				shake_pow = c.power
				Sfx.play("land", 0.05, -8.0)
		"flash":
			if not _fast():
				flash_rect.color = Color(c.color, 0.0 if reduce_motion else 0.85)
		"wait":
			wait_left = 0.0 if _fast() else c.sec


func _on_ended() -> void:
	_ended = true
	typing = false
	auto = false
	skip_read = false
	_refresh_buttons()
	finished.emit()


# ── 진행 ────────────────────────────────────────────────

func _fast() -> bool:
	return skip_read or fast_forward or Input.is_key_pressed(KEY_CTRL)


## 진행 입력 한 번: 출력 중이면 완성, 다 나왔으면 다음 줄
func next() -> void:
	if runner == null or _ended or wait_left >= 0.0:
		return
	if summary_layer.visible:
		summary_layer.visible = false
		return
	if runner.waiting_choice:
		return
	if typing:
		_complete()
		return
	_advance()


func _complete() -> void:
	shown = total
	text.visible_characters = -1
	typing = false


func _advance() -> void:
	typing = false
	runner.advance()


func _pick(i: int) -> void:
	if runner == null or not runner.waiting_choice or i >= runner.options.size():
		return
	var o: Dictionary = runner.options[i]
	_log_add("▸ 선택", Color("7cf5ff"), DialogueScript.markup(o.text).bb)
	Sfx.play("lock", 0.0, -6.0)
	_clear_choices()
	runner.choose(i)


func _clear_choices() -> void:
	for c in choice_box.get_children():
		choice_box.remove_child(c)
		c.queue_free()


## 선택지(또는 끝)까지 조용히 건너뛰고, 지나온 줄거리 요약을 보여 준다
func jump_to_choice() -> void:
	if runner == null or _ended or runner.waiting_choice:
		return
	var before := runner.summaries.size()
	var guard := 0
	wait_left = -1.0
	while not runner.waiting_choice and not runner.done and guard < 2000:
		guard += 1
		_complete()
		runner.advance()
		wait_left = -1.0
	_complete()
	var lines := runner.summaries.slice(before)
	if lines.size() > 0:
		var s := "[b]지나온 이야기[/b]\n\n"
		for l in lines:
			s += "·  " + l + "\n"
		summary_text.text = s + "\n[color=#8a8fa3]아무 키나 눌러 계속[/color]"
		summary_layer.visible = true


func _process(dt: float) -> void:
	t += dt
	var screen := get_viewport_rect().size
	# 퇴장한 인물 정리
	for p in people.get_children():
		var q := p as DialoguePortrait
		q.resize_screen(screen)
		if q.gone():
			q.queue_free()
	# 화면 흔들림 · 섬광
	if shake_t > 0.0:
		shake_t -= dt
		var a := shake_pow * 18.0 * clampf(shake_t * 2.0, 0.0, 1.0)
		stage.position = Vector2(randf_range(-a, a), randf_range(-a, a))
	else:
		stage.position = Vector2.ZERO
	flash_rect.color.a = move_toward(flash_rect.color.a, 0.0, dt * 3.0)
	toast_t -= dt
	toast.modulate.a = clampf(toast_t * 2.0, 0.0, 1.0)

	if wait_left >= 0.0:
		wait_left -= dt
		if wait_left < 0.0:
			runner.advance()
		box.queue_redraw()
		return
	if typing:
		_type(dt)
	elif runner and not _ended and not runner.waiting_choice and not summary_layer.visible:
		if _fast():
			skip_wait += dt
			if skip_wait >= SKIP_STEP:
				skip_wait = 0.0
				_advance()
		elif auto:
			auto_wait += dt
			if auto_wait >= 1.0 + 0.045 * str(line.get("plain", "")).length() / maxf(1.0, BASE_CPS[mini(speed_idx, 2)] / 40.0):
				_advance()
	box.queue_redraw()


func _type(dt: float) -> void:
	if _fast():
		_complete()
		return
	if pause_left > 0.0:
		pause_left -= dt
		return
	var cps: float = BASE_CPS[speed_idx]
	var cur := int(shown)
	for sp in line.speeds:
		if sp[0] <= cur:
			cps = BASE_CPS[speed_idx] * sp[1]
	shown += cps * dt
	var target := mini(int(shown), total)
	# 멈춤 자리를 지나치지 않게 그 자리에서 멈춘다
	for i in range(_last_visible + 1, target + 1):
		if line.pauses.has(i) and speed_idx < 3:
			target = i
			shown = i
			pause_left = line.pauses[i]
			break
	if target > _last_visible:
		var plain: String = line.plain
		for i in range(_last_visible, target):
			var ch := plain[i] if i < plain.length() else " "
			if ch != " " and ch != "\n" and not DialogueScript.PUNCT_PAUSE.has(ch):
				_blip_n += 1
				if _blip_n % 2 == 1 and line.who != "":
					voice.blip(line.who)
					if portraits.has(line.who) and not reduce_motion:
						portraits[line.who].bob()
		_last_visible = target
		text.visible_characters = target
	if target >= total:
		_complete()


func _enter(who: String, at: String, e: String) -> DialoguePortrait:
	var p := DialoguePortrait.new()
	p.setup(who, at, e, get_viewport_rect().size)
	people.add_child(p)
	portraits[who] = p
	return p


func _free_slot() -> String:
	var used := []
	for id in portraits:
		used.append(portraits[id].slot)
	for s in ["left", "right", "left2", "right2", "center"]:
		if s not in used:
			return s
	return "center"


# ── 버튼 · 토글 ─────────────────────────────────────────

func _toggle_auto() -> void:
	auto = not auto
	auto_wait = 0.0
	_toast("자동 진행 " + ("켬" if auto else "끔"))
	_refresh_buttons()


func _toggle_skip() -> void:
	skip_read = not skip_read
	_toast("읽은 대사 넘기기 " + ("켬" if skip_read else "끔"))
	_refresh_buttons()


func _toggle_hide() -> void:
	ui.visible = not ui.visible


func _open_log() -> void:
	log_layer.visible = true
	await get_tree().process_frame
	if not is_inside_tree() or not is_instance_valid(log_scroll):
		return
	log_scroll.scroll_vertical = int(log_scroll.get_v_scroll_bar().max_value)


func _refresh_buttons() -> void:
	_mark(btn_auto, auto)
	_mark(btn_skip, skip_read)


func _mark(b: Button, on: bool) -> void:
	if _mark_on == null:
		_mark_on = _flat(Color(0.6, 0.1, 0.13, 0.92), CREAM, 2)
		_mark_off = _flat(Color(0.05, 0.05, 0.06, 0.82), Color(CREAM, 0.55), 2)
	b.add_theme_stylebox_override("normal", _mark_on if on else _mark_off)


func _toast(s: String) -> void:
	toast.text = s
	toast_t = 1.6


func _refresh_hint() -> void:
	hint.text = "글자 속도 [ ] %s   ·   글자 크기 - = %d   ·   움직임 줄이기 M %s   ·   Ctrl 빨리 넘기기 · Tab 선택지까지 건너뛰기" % [
		SPEED_NAMES[speed_idx], SIZES[size_idx], "켬" if reduce_motion else "끔"]


func _apply_size() -> void:
	var s: int = SIZES[size_idx]
	text.add_theme_font_size_override("normal_font_size", s)
	text.add_theme_font_size_override("bold_font_size", s)
	text.add_theme_font_size_override("italics_font_size", s)


func _log_add(who_name: String, c: Color, bb: String) -> void:
	var row := RichTextLabel.new()
	row.bbcode_enabled = true
	row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # 한국어 낱말 중간에서 끊지 않게
	row.fit_content = true
	row.scroll_active = false
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_font_override("normal_font", font)
	row.add_theme_font_override("bold_font", bold)
	row.add_theme_font_size_override("normal_font_size", 21)
	row.add_theme_font_size_override("bold_font_size", 21)
	row.add_theme_color_override("default_color", CREAM)
	var head := "[b][color=#%s]%s[/color][/b]\n" % [c.to_html(false), who_name] if who_name != "" else ""
	# 기록에서는 흔들림 · 물결을 뺀다
	if _calm_rx.is_empty():
		for tag in ["shake", "wave"]:
			_calm_rx.append(RegEx.create_from_string("\\[/?" + tag + "[^\\]]*\\]"))
	var calm := bb
	for rx in _calm_rx:
		calm = rx.sub(calm, "", true)
	row.text = head + calm
	log_list.add_child(row)


func log_count() -> int:
	return log_list.get_child_count()


# ── 입력 ────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if log_layer.visible:
		if (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_L, KEY_ESCAPE]) \
				or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
			log_layer.visible = false
			get_viewport().set_input_as_handled()
		return
	if not ui.visible:
		# 숨긴 상태에서는 아무 입력이나 UI 를 되돌리기만 한다
		if (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed):
			ui.visible = true
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_DOWN:
				next()
			MOUSE_BUTTON_RIGHT:
				_toggle_hide()
			MOUSE_BUTTON_WHEEL_UP:
				_open_log()
		return
	if not (event is InputEventKey) or not event.pressed:
		return
	var k: Key = event.physical_keycode
	if event.echo and k not in [KEY_SPACE, KEY_ENTER]:
		return
	if runner and runner.waiting_choice and k >= KEY_1 and k <= KEY_4:
		_pick(k - KEY_1)
		get_viewport().set_input_as_handled()
		return
	match k:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if not (runner and runner.waiting_choice):
				next()
		KEY_A:
			_toggle_auto()
		KEY_S:
			_toggle_skip()
		KEY_TAB:
			jump_to_choice()
		KEY_L:
			_open_log()
		KEY_H:
			_toggle_hide()
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			speed_idx = clampi(speed_idx + (1 if k == KEY_BRACKETRIGHT else -1), 0, BASE_CPS.size() - 1)
			_toast("글자 속도: " + SPEED_NAMES[speed_idx])
			_refresh_hint()
		KEY_MINUS, KEY_EQUAL:
			size_idx = clampi(size_idx + (1 if k == KEY_EQUAL else -1), 0, SIZES.size() - 1)
			_apply_size()
			_toast("글자 크기: %d" % SIZES[size_idx])
			_refresh_hint()
		KEY_M:
			reduce_motion = not reduce_motion
			_toast("움직임 줄이기 " + ("켬" if reduce_motion else "끔"))
			_refresh_hint()
		_:
			return
	get_viewport().set_input_as_handled()


# ── 대화창 그리기 ──────────────────────────────────────

func _draw_box() -> void:
	var w := box.size.x
	var h := box.size.y
	if w < 200.0 or h < 80.0:
		return
	var c := 26.0
	var pts := PackedVector2Array([Vector2(c, 0), Vector2(w - c * 2.0, 0), Vector2(w, c * 2.0), Vector2(w, h - c), Vector2(w - c, h), Vector2(c, h), Vector2(0, h - c), Vector2(0, c)])
	box.draw_colored_polygon(pts, INK)
	var outline := pts.duplicate()
	outline.append(pts[0])
	box.draw_polyline(outline, CREAM, 3.0, true)
	# 안쪽 가는 선
	var inner := PackedVector2Array()
	for p in outline:
		inner.append(p + (Vector2(w, h) * 0.5 - p).normalized() * 9.0)
	box.draw_polyline(inner, Color(CREAM, 0.12), 1.5, true)
	# 오른쪽 위 화자 색 모서리
	box.draw_colored_polygon(PackedVector2Array([Vector2(w - c * 2.0 - 70, 0), Vector2(w - c * 2.0, 0), Vector2(w, c * 2.0), Vector2(w, c * 2.0 + 70)]), Color(accent, 0.85))
	# 이름표: 기운 띠
	if plate_name.visible:
		var nw := plate_name.get_minimum_size().x + plate_en.get_minimum_size().x + 70
		var base := accent.darkened(0.45)
		box.draw_colored_polygon(PackedVector2Array([Vector2(34, -34), Vector2(54 + nw, -34), Vector2(34 + nw, 18), Vector2(14, 18)]), base)
		box.draw_colored_polygon(PackedVector2Array([Vector2(54 + nw, -34), Vector2(54 + nw + 26, -34), Vector2(34 + nw + 26, 18), Vector2(34 + nw, 18)]), accent)
		box.draw_line(Vector2(14, 18), Vector2(34 + nw + 26, 18), CREAM, 3.0)
	# 다음 표시 (다 나왔고 선택지가 아닐 때)
	if not typing and runner and not runner.waiting_choice and not _ended and wait_left < 0.0:
		var bobx := 0.0 if reduce_motion else sin(t * 6.0) * 5.0
		var o := Vector2(w - 116 + bobx, h - 46)
		box.draw_colored_polygon(PackedVector2Array([o, o + Vector2(18, 11), o + Vector2(0, 22)]), CREAM)
		var label := "AUTO" if auto else ("SKIP" if _fast() else "다음")
		box.draw_string(font, Vector2(w - 88, h - 28), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(CREAM, 0.8))
	elif _ended:
		box.draw_string(font, Vector2(w - 130, h - 28), "— 끝 —", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(CREAM, 0.6))
	if auto and not _ended:
		# 자동 진행 중: 오른쪽 아래 돌아가는 점
		var cc := Vector2(w - 140, h - 35)
		for i in 6:
			var a := t * 4.0 + i * TAU / 6.0
			box.draw_circle(cc + Vector2(cos(a), sin(a)) * 8.0, 2.0 + (i / 6.0) * 1.5, Color(CREAM, 0.25 + i * 0.12))
