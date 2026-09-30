extends Node3D
## Lobby review room for the B storyboard. Not a combat or sector-run scene.

const Presentation := preload("res://scripts/presentation/mammoth_death_b.gd")
const RATES := [0.25, 0.5, 1.0, 1.5]

@onready var presentation: Presentation = $Presentation
var playing := false
var looping := true
var rate := 1.0
var warmup := 0.6
var loop_wait := 0.0
var ui: Control
var status: Label
var time_label: Label
var play_button: Button
var timeline: HSlider
var flash: ColorRect
var capture_dir := ""
var capture_every := 4
var capture_seconds := 7.0
var capture_frame := 0
var wall_time := 0.0
var capturing := false
var fixed_capture_time := -1.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_environment()
	var sound := Sfx.new()
	add_child(sound)
	presentation.effects.bind_audio(sound.streams)
	_build_ui()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lab-capture="):
			capture_dir = arg.substr(14)
		elif arg.begins_with("--lab-every="):
			capture_every = maxi(1, int(arg.substr(12)))
		elif arg.begins_with("--lab-seconds="):
			capture_seconds = float(arg.substr(14))
		elif arg.begins_with("--lab-seek="):
			fixed_capture_time = float(arg.substr(11))
	if capture_dir != "":
		DirAccess.make_dir_recursive_absolute(capture_dir)
		looping = false
		presentation.effects.sound_enabled = false
	if OS.get_cmdline_user_args().has("--lab-clean"):
		ui.visible = false
	if fixed_capture_time >= 0:
		warmup = -1.0
		presentation.seek(fixed_capture_time)
		playing = false
	presentation.finished.connect(_on_finished)
	_refresh_ui()


func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("080913")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.50, 0.52, 0.80)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.9
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_density = 0.009
	env.fog_light_color = Color("0c0d20")
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 28, 0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 65
	sun.shadow_normal_bias = 1.0
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-28, 150, 0)
	rim.light_color = Color("80dfff")
	rim.light_energy = 0.35
	add_child(rim)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	flash = ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.color = Color(1, 0.95, 0.85, 0)
	layer.add_child(flash)
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Noto Sans CJK KR", "sans-serif"])
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 16
	ui.theme = theme

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 24
	top.offset_right = -24
	top.offset_top = 18
	ui.add_child(top)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(titles)
	titles.add_child(_label("MAMMOTH  ·  죽음 연출 테스트 B안", 22, Color("e4efff")))
	titles.add_child(_label("궤도 파손과 전복  ·  본선 적용 전 미리보기", 14, Color("ffd166")))
	status = _label("01  ·  궤도 파손", 17, Color("7cf5ff"))
	titles.add_child(status)
	var back := _button("로비로  Esc")
	back.pressed.connect(_back)
	top.add_child(back)

	var bottom := PanelContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_left = 20
	bottom.offset_right = -20
	bottom.offset_top = -160
	bottom.offset_bottom = -16
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.045, 0.09, 0.90)
	panel_style.set_content_margin_all(12)
	panel_style.set_corner_radius_all(6)
	bottom.add_theme_stylebox_override("panel", panel_style)
	ui.add_child(bottom)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	bottom.add_child(column)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	play_button = _button("일시정지  Space")
	play_button.pressed.connect(_toggle_play)
	actions.add_child(play_button)
	var replay := _button("처음부터  R")
	replay.pressed.connect(_replay)
	actions.add_child(replay)
	var speed := OptionButton.new()
	for value in RATES:
		speed.add_item("%.2f배속" % value)
	speed.select(2)
	speed.item_selected.connect(func(index: int): rate = RATES[index])
	actions.add_child(speed)
	var loop_check := CheckButton.new()
	loop_check.text = "반복"
	loop_check.button_pressed = true
	loop_check.toggled.connect(func(value: bool): looping = value)
	actions.add_child(loop_check)
	var shake_check := CheckButton.new()
	shake_check.text = "흔들림"
	shake_check.button_pressed = presentation.shake_strength > 0
	shake_check.toggled.connect(func(value: bool):
		presentation.shake_strength = 1.0 if value else 0.0
		presentation.refresh_options())
	actions.add_child(shake_check)
	var flash_check := CheckButton.new()
	flash_check.text = "섬광"
	flash_check.button_pressed = presentation.flash_strength > 0
	flash_check.toggled.connect(func(value: bool):
		presentation.flash_strength = 1.0 if value else 0.0
		presentation.refresh_options())
	actions.add_child(flash_check)
	var fixed_check := CheckButton.new()
	fixed_check.text = "고정 카메라"
	fixed_check.toggled.connect(func(value: bool):
		presentation.fixed_camera = value
		presentation.refresh_options())
	actions.add_child(fixed_check)
	var sound_check := CheckButton.new()
	sound_check.text = "소리"
	sound_check.button_pressed = true
	sound_check.toggled.connect(func(value: bool): presentation.effects.sound_enabled = value)
	actions.add_child(sound_check)

	var transport := HBoxContainer.new()
	column.add_child(transport)
	timeline = HSlider.new()
	timeline.min_value = 0
	timeline.max_value = Presentation.DURATION
	timeline.step = 0.01
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.value_changed.connect(_seek)
	transport.add_child(timeline)
	time_label = _label("0.00 / 5.20초", 14, Color("ccd8ed"))
	time_label.custom_minimum_size.x = 122
	transport.add_child(time_label)
	var cuts := HBoxContainer.new()
	cuts.add_theme_constant_override("separation", 8)
	column.add_child(cuts)
	for i in Presentation.CUT_NAMES.size():
		var button := _button("%02d  %s" % [i + 1, Presentation.CUT_NAMES[i]])
		button.add_theme_font_size_override("font_size", 13)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_seek.bind(Presentation.CUT_STARTS[i] + (0.35 if i > 0 else 0.0)))
		cuts.add_child(button)


func _process(dt: float) -> void:
	wall_time += dt
	if warmup > 0:
		warmup -= dt
		if warmup <= 0:
			playing = true
	elif playing:
		presentation.advance(dt * rate)
	elif presentation.completed and looping and loop_wait >= 0:
		loop_wait += dt
		if loop_wait > 1.5:
			_replay()
	presentation.effects.update_audio(presentation.time, rate, playing)
	flash.color.a = presentation.flash_alpha if presentation.time > 0.0 else 0.0
	_refresh_ui()
	if capture_dir != "":
		capture_frame += 1
		if capture_frame % capture_every == 0 and not capturing:
			_capture.call_deferred(capture_frame)
		if wall_time >= capture_seconds and not capturing:
			print("MAMMOTH_LAB_CAPTURE_DONE frames=", capture_frame, " snapshot=", presentation.snapshot())
			get_tree().quit()


func _toggle_play() -> void:
	warmup = -1
	if presentation.completed:
		_replay()
	else:
		playing = not playing
	_refresh_ui()


func _replay() -> void:
	warmup = -1
	loop_wait = 0
	presentation.reset()
	playing = true
	_refresh_ui()


func _seek(value: float) -> void:
	warmup = -1
	loop_wait = 0
	playing = false
	presentation.seek(value)
	loop_wait = -1
	_refresh_ui()


func _on_finished() -> void:
	playing = false
	loop_wait = 0
	presentation.effects.stop_audio()


func _refresh_ui() -> void:
	if timeline == null:
		return
	var index := presentation.cut_index()
	status.text = "%02d  ·  %s%s" % [index + 1, Presentation.CUT_NAMES[index], "  ·  재생 완료" if presentation.completed else ""]
	timeline.set_value_no_signal(presentation.time)
	time_label.text = "%.2f / %.2f초" % [presentation.time, Presentation.DURATION]
	play_button.text = "일시정지  Space" if playing else ("다시 재생  Space" if presentation.completed else "재생  Space")


func _capture(index: int) -> void:
	capturing = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(capture_dir.path_join("frame_%05d.png" % index))
	capturing = false


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_ESCAPE:
		_back()
	elif key == KEY_SPACE:
		_toggle_play()
	elif key == KEY_R or key == KEY_F5:
		_replay()
	elif key == KEY_H:
		ui.visible = not ui.visible
	elif key >= KEY_1 and key <= KEY_6:
		var index := key - KEY_1
		_seek(Presentation.CUT_STARTS[index] + (0.35 if index > 0 else 0.0))
	get_viewport().set_input_as_handled()


func _back() -> void:
	presentation.effects.stop_audio()
	Lobby.back(get_tree())


func _exit_tree() -> void:
	if is_instance_valid(presentation) and is_instance_valid(presentation.effects):
		presentation.effects.stop_audio()


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 34
	button.focus_mode = Control.FOCUS_NONE
	return button
