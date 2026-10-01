class_name DialogueMain
extends Control
## 대화 시스템 테스트 씬 (scenes/dialogue.tscn). 대사 파일을 골라 처음부터 돌려 본다.
##   F1 격납고 브리핑 · F2 기능 시연 · R 처음부터 · Esc 로비
## 실행 인자 (-- 뒤): --script=feature_demo  --bot(자동 진행 + 선택지 무작위, 끝나면 종료)  --seed=1
##                    --capture=폴더(res:// 기준, 미리 만들어 둠) --every=0.5  --seconds=40

const SCRIPTS := [
	{"key": KEY_F1, "id": "hangar_briefing", "title": "격납고 브리핑"},
	{"key": KEY_F2, "id": "feature_demo", "title": "기능 시연"},
]
const DIR := "res://data/dialogue/"

var view: DialogueView
var runner: DialogueRunner
var current := "hangar_briefing"
var help: Label
var bot := false
var bot_pick_t := 0.0
var capture_dir := ""
var capture_every := 0.5
var capture_t := 0.0
var capture_n := 0
var seconds := 0.0
var elapsed := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(Sfx.new())
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--script="):
			current = a.substr(9)
		elif a == "--bot":
			bot = true
		elif a.begins_with("--seed="):
			seed(int(a.substr(7)))
		elif a.begins_with("--capture="):
			capture_dir = a.substr(10)
		elif a.begins_with("--every="):
			capture_every = float(a.substr(8))
		elif a.begins_with("--seconds="):
			seconds = float(a.substr(10))
	help = Label.new()
	help.add_theme_font_size_override("font_size", 14)
	help.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9, 0.7))
	help.position = Vector2(46, 56)
	help.z_index = 55
	start(current)
	add_child(help)


func start(id: String) -> void:
	current = id
	if view:
		view.queue_free()
	var s := DialogueScript.load_file(DIR + id + ".dlg")
	for e in s.errors:
		push_error(e)
	runner = DialogueRunner.new(s)
	view = DialogueView.new()
	add_child(view)
	move_child(view, 0)
	view.finished.connect(_on_finished)
	if bot:
		view.auto = true
		DialogueView.speed_idx = 2
	var names := []
	for d in SCRIPTS:
		names.append("%s %s%s" % [OS.get_keycode_string(d.key), d.title, " ◀" if d.id == id else ""])
	help.text = "  ·  ".join(names) + "  ·  R 처음부터  ·  Esc 로비"
	view.play(runner)


func _on_finished() -> void:
	print("DIALOGUE_DONE %s flags=%s log=%d" % [current, str(runner.flags), view.log_count()])
	if bot and capture_dir == "":
		get_tree().create_timer(0.5).timeout.connect(get_tree().quit)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k: Key = event.physical_keycode
	if k == KEY_ESCAPE:
		Lobby.back(get_tree())
	elif k == KEY_R:
		start(current)
	else:
		for d in SCRIPTS:
			if d.key == k:
				start(d.id)


func _process(dt: float) -> void:
	elapsed += dt
	if bot and runner.waiting_choice:
		bot_pick_t += dt
		if bot_pick_t > 0.8:
			bot_pick_t = 0.0
			view._pick(randi() % runner.options.size())
	if capture_dir != "":
		capture_t += dt
		if capture_t >= capture_every:
			capture_t = 0.0
			get_viewport().get_texture().get_image().save_png("%s/d_%04d.png" % [capture_dir, capture_n])
			capture_n += 1
	if seconds > 0.0 and elapsed >= seconds:
		get_tree().quit()
