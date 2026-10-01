class_name Lobby
extends Control
## 게임 시작 화면. 메인 게임(헥스 섹터 런)과 테스트 씬(방 탐색 아레나 · 보스전 단독)을 고른다.
## 게임 중 Esc 로 언제든 이 화면으로 돌아온다 (Lobby.back()).

const SCENE := "res://scenes/lobby.tscn"
const RUN_SCENE := "res://scenes/run.tscn"
const DEATH_TEST_SCENE := "res://scenes/mammoth_death_lab.tscn"
const TEST_SCENES := [
	{"title": "방 탐색 아레나", "desc": "전투방 9곳을 통로로 이은 기존 절차 생성 맵", "scene": "res://scenes/main.tscn"},
	{"title": "전투 테스트 · 허수아비", "desc": "넓은 홀에서 허수아비로 콤보·무기·패링을 자유롭게 시험 · 피해 숫자·DPS 표시", "scene": "res://scenes/training.tscn"},
	{"title": "MAMMOTH 추격전", "desc": "도로 위 전차 보스 단독 실행", "scene": "res://scenes/boss.tscn"},
	{"title": "VULCAN 용광로", "desc": "좁아지는 용암 아레나 보스 단독 실행", "scene": "res://scenes/forge.tscn"},
	{"title": "LAYER 01 · 심연 성소", "desc": "어두운 부유 아레나 · 페이즈마다 땅이 솟고 꺼짐 · 함정 · 중간보스 HALO WARDEN", "scene": "res://scenes/abyss.tscn"},
	{"title": "SHAFT 07 · 거미 보스 SHIPWRIGHT", "desc": "높은 벽의 갱도 · 벽과 구멍을 오가는 다관절 거미 · 거미줄 감속 · 새끼 소환 · 끝없는 기둥", "scene": "res://scenes/spider.tscn"},
	{"title": "캐릭터 대화", "desc": "격납고 브리핑 · 표정 포트레이트 · 선택지 분기 · 자동 · 넘기기 · 기록", "scene": "res://scenes/dialogue.tscn"},
	{"title": "MAMMOTH 죽음 연출 · B안", "desc": "궤도 파손과 전복 컷씬 반복 확인 (본선 격파에 적용됨)", "scene": "res://scenes/lab_mammoth_b.tscn"},
]
const CYAN := Color("7cf5ff")
const PINK := Color("ff4a8a")
const GOLD := Color("ffd166")

var font: SystemFont
var bg: Control
var t := 0.0
var main_btn: Button
var test_box: VBoxContainer
var test_btns: Array[Button] = []
var _leaving := false


## 게임 씬에서 로비로 돌아온다
static func back(tree: SceneTree) -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	tree.change_scene_to_file(SCENE)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(Sfx.new())
	if _route_cmdline():
		return
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Apple SD Gothic Neo", "Noto Sans CJK KR", "sans-serif"])
	font.font_weight = 700
	var th := Theme.new()
	th.default_font = font
	th.default_font_size = 18
	theme = th

	bg = Control.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(_draw_bg)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size = Vector2(520, 0)
	center.add_child(col)

	var title := _label("HEX BLADE", 76, Color.WHITE)
	title.add_theme_color_override("font_shadow_color", CYAN * Color(1, 1, 1, 0.55))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", 18)
	col.add_child(title)
	col.add_child(_label("쿼터뷰 3D 액션 로그라이트", 18, Color(0.7, 0.8, 0.95)))
	col.add_child(_spacer(26))

	main_btn = _button("메인 게임  ·  HEX SECTOR RUN", "포탈로 경로를 골라 섹터를 돌파하고 MAMMOTH · VULCAN 을 격파", CYAN, 21)
	main_btn.pressed.connect(_start_run)
	col.add_child(main_btn)

	var death_btn := _button("연출 테스트  ·  MAMMOTH B안", "궤도 파손과 전복 · 재생 / 일시정지 / 컷별 미리보기", PINK, 20)
	death_btn.pressed.connect(_go.bind(DEATH_TEST_SCENE))
	col.add_child(death_btn)

	var test_btn := _button("테스트 씬", "기존 방 조합 게임과 보스전을 따로 실행", GOLD, 20)
	test_btn.pressed.connect(_toggle_tests)
	col.add_child(test_btn)

	test_box = VBoxContainer.new()
	test_box.add_theme_constant_override("separation", 8)
	test_box.visible = false
	col.add_child(test_box)
	for s in TEST_SCENES:
		var b := _button("    ▸  " + s.title, "        " + s.desc, GOLD.lerp(Color.WHITE, 0.35), 17)
		b.pressed.connect(_go.bind(s.scene))
		test_box.add_child(b)
		test_btns.append(b)

	var quit_btn := _button("종료", "", Color(0.75, 0.75, 0.85), 18)
	quit_btn.pressed.connect(func(): get_tree().quit())
	col.add_child(quit_btn)

	col.add_child(_spacer(18))
	col.add_child(_label("↑↓ 선택 · Enter 결정 · 게임 중 Esc 로비 · F11 전체 화면", 14, Color(0.55, 0.6, 0.75)))
	main_btn.grab_focus.call_deferred()


## 자동 플레이 · 캡처 실행 인자로 켰을 때는 로비를 건너뛴다 (--test 는 방 탐색 아레나, 그 밖은 섹터 런)
func _route_cmdline() -> bool:
	var args := OS.get_cmdline_user_args()
	var skip := false
	for a in args:
		if a not in ["--toon", "--notoon", "--noimpact"]:
			skip = true
	if not skip:
		return false
	var target: String = TEST_SCENES[0].scene if args.has("--test") else RUN_SCENE
	get_tree().change_scene_to_file.call_deferred(target)
	return true


func _start_run() -> void:
	if _leaving:
		return
	_leaving = true
	Sfx.play("charged", 0.0)
	get_node("/root/Run").new_run()


func _go(scene: String) -> void:
	if _leaving:
		return
	_leaving = true
	Sfx.play("ready", 0.0)
	get_tree().change_scene_to_file(scene)


func _toggle_tests() -> void:
	test_box.visible = not test_box.visible
	Sfx.play("lock", 0.0, -4.0)
	if test_box.visible:
		test_btns[0].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE and test_box.visible:
			test_box.visible = false
			main_btn.grab_focus()
			get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	t += dt
	if bg:
		bg.queue_redraw()


# ── 모양 ────────────────────────────────────────────────

func _label(text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	return l


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _button(title: String, desc: String, accent: Color, size: int) -> Button:
	var b := Button.new()
	b.text = title + ("\n" + desc if desc != "" else "")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(0, 50 + (26 if desc != "" else 0))
	b.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", accent)
	var normal := _box(Color(0.06, 0.07, 0.14, 0.82), accent * Color(1, 1, 1, 0.35), 2)
	var hot := _box(Color(accent.r, accent.g, accent.b, 0.16), accent, 3)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hot)
	b.add_theme_stylebox_override("focus", hot)
	b.add_theme_stylebox_override("pressed", _box(Color(accent.r, accent.g, accent.b, 0.3), Color.WHITE, 3))
	b.mouse_entered.connect(func(): b.grab_focus())
	b.focus_entered.connect(func(): Sfx.play("tink", 0.02, -10.0))
	return b


func _box(fill: Color, border: Color, w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(w)
	s.border_width_left = w + 4
	s.set_corner_radius_all(4)
	s.content_margin_left = 22
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


## 배경: 천천히 흐르는 육각 격자와 가운데로 모이는 빛
func _draw_bg() -> void:
	var sz := bg.size
	bg.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.03, 0.08))
	var r := 34.0
	var w := r * sqrt(3.0)
	var h := r * 1.5
	var off := Vector2(fmod(t * 9.0, w), fmod(t * 6.0, h * 2.0))
	var mid := sz * 0.5
	var y := -h * 2.0
	var row := 0
	while y < sz.y + h * 2.0:
		var x := -w + (w * 0.5 if row % 2 == 1 else 0.0)
		while x < sz.x + w:
			var c := Vector2(x, y) + off
			var d := c.distance_to(mid) / sz.length()
			var pulse := 0.5 + 0.5 * sin(t * 1.3 - d * 14.0)
			var col := CYAN.lerp(PINK, clampf(c.x / sz.x, 0.0, 1.0)) * Color(1, 1, 1, (0.05 + 0.1 * pulse) * (1.0 - d * 1.2))
			var pts := PackedVector2Array()
			for i in 7:
				var a := PI / 6.0 + TAU * i / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * (r - 3.0))
			bg.draw_polyline(pts, col, 1.5, true)
			x += w
		y += h
		row += 1
	# 위아래 어둡게
	for i in 12:
		var k := i / 12.0
		bg.draw_rect(Rect2(0, k * sz.y * 0.18, sz.x, sz.y * 0.018), Color(0, 0, 0, 0.35 * (1.0 - k)))
		bg.draw_rect(Rect2(0, sz.y - (k + 0.1) * sz.y * 0.18, sz.x, sz.y * 0.018), Color(0, 0, 0, 0.35 * (1.0 - k)))
