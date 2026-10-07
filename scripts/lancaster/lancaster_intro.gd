class_name LancasterIntro
extends Node
## LANCASTER 첫 등장 연출 감독. 보스방에 처음 들어오면 TrainingBossRoom 이 만든다. 보스의 연기는 LancasterBoss 의 INTRO 상태가 하고,
## 여기서는 무대 · 카메라 · 화면을 맡는다.
##  1. UI 가 각자 가까운 화면 가장자리 밖으로 미끄러져 나가고, 위아래 레터박스가 들어온다. 플레이어는 조작이 잠긴다.
##  2. 카메라가 보스 쪽으로 날아가 등 돌린 보스의 어깨 너머에 선다.
##  3. 보스 앞에서 벌레 4마리가 기어 나와 몰려들고, 보스는 개틀링으로 하나씩 쓸어 버린다. 그사이 한 마리가 발밑까지 기어 오고 → 짓밟힌다.
##  4. 보스가 흘깃 → 상체 → 하체 순으로 돌아서는 동안 카메라는 플레이어 쪽 앞에서 보스를 올려다보고,
##     재장전(철컥!) · 붉은 눈 · 경보에서 얼굴로 다가간다. 끝나면 게임 카메라로 돌아가고 UI · 레터박스가 원래대로.
## Enter = 건너뛰기. --bossintro=off 면 예전처럼 무릎 꿇은 정지 → 기동.

static var enabled := true

const BAR_H := 0.115             ## 레터박스 높이 (화면 높이 비율)
const UI_OUT := 0.55
const UI_IN := 0.6
const BUG_N := 4

var main: TrainingMain
var room: TrainingBossRoom
var boss: LancasterBoss
var t := 0.0
var cam: Camera3D
var layer: CanvasLayer
var top_bar: ColorRect
var bot_bar: ColorRect
var skip_label: Label
var ui: Array = []               ## [CanvasItem, 원래 위치, 방향(Vector2), 원래 알파, 순번]
var bar_k := 0.0
var ui_k := 0.0
var leaving := false
var leave_t := 0.0
var done := false
var shot := ""
var _look := Vector3.ZERO
var _rate := 0.0
var _fwd := Vector3.FORWARD      ## 시작 때 보스가 보던 쪽 (벌레가 있는 쪽)
var _noise := FastNoiseLite.new()
var _bar_shown := false


static func start(r: TrainingBossRoom) -> LancasterIntro:
	var d := LancasterIntro.new()
	d.room = r
	d.main = r.main
	d.boss = r.boss
	r.add_child(d)
	return d


func _ready() -> void:
	LancasterSound.ensure()
	var p := main.player
	p.cine_lock = true
	p.velocity = Vector3(p.velocity.x, p.velocity.y, p.velocity.z) * 0.3
	# 카메라: 지금 게임 카메라 자리에서 출발
	cam = Camera3D.new()
	cam.fov = main.camera.fov
	main.world.add_child(cam)
	cam.global_transform = main.camera.global_transform
	cam.make_current()
	_look = cam.global_position - cam.global_basis.z * cam.global_position.distance_to(p.global_position)
	_noise.frequency = 2.5
	_build_bars()
	_collect_ui()
	_fwd = boss._dir_of(boss.face_yaw)
	boss.intro_directed = true
	_spawn_bugs()
	shot = "over"


func _build_bars() -> void:
	layer = CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	top_bar = ColorRect.new()
	bot_bar = ColorRect.new()
	for b in [top_bar, bot_bar]:
		(b as ColorRect).color = Color(0.0, 0.0, 0.02)
		(b as ColorRect).mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(b)
	skip_label = Label.new()
	skip_label.text = "Enter  건너뛰기"
	skip_label.add_theme_font_size_override("font_size", 14)
	skip_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	layer.add_child(skip_label)
	_layout_bars()


func _layout_bars() -> void:
	var vs := get_viewport().get_visible_rect().size
	var h := vs.y * BAR_H
	var e := 1.0 - pow(1.0 - clampf(bar_k, 0.0, 1.0), 3.0)
	top_bar.position = Vector2(0, -h + h * e)
	top_bar.size = Vector2(vs.x, h)
	bot_bar.position = Vector2(0, vs.y - h * e)
	bot_bar.size = Vector2(vs.x, h)
	skip_label.position = Vector2(vs.x - 150, vs.y - h * e + h * 0.5 - 10)
	skip_label.modulate.a = e


## 화면 UI: 각자 가까운 가장자리 쪽으로 나간다 (전체 화면을 덮는 것은 방향을 알 수 없으니 정한 쪽으로)
func _collect_ui() -> void:
	var hud := main.hud
	var keep := [hud.center, hud.sub, hud.flash_rect, hud.vignette]
	var list: Array = []
	for c in hud.root.get_children():
		if c in keep or not (c is CanvasItem) or not (c as CanvasItem).visible:
			continue
		if c == hud.presets:
			for cc in c.get_children():
				list.append(cc)
			continue
		list.append(c)
	var vs := get_viewport().get_visible_rect().size
	var i := 0
	for c: CanvasItem in list:
		var dir := Vector2.ZERO
		if c is CalmHud:
			dir = Vector2.UP
		elif c is RoundSkillDock or c is DroneHud or c == hud.hint:
			dir = Vector2.DOWN
		elif c is ComboMeter or c is TrainingPanel:
			dir = Vector2.LEFT
		elif c is Control:
			var r := (c as Control).get_global_rect()
			if r.size.x > vs.x * 0.8 and r.size.y > vs.y * 0.8:
				dir = Vector2.ZERO          # 화면 전체: 흐려지기만
			else:
				var cc := r.get_center()
				var dl := cc.x
				var dr := vs.x - cc.x
				var du := cc.y
				var dd := vs.y - cc.y
				var m := minf(minf(dl, dr), minf(du, dd))
				dir = Vector2.LEFT if m == dl else (Vector2.RIGHT if m == dr else (Vector2.UP if m == du else Vector2.DOWN))
		var pos: Vector2 = (c as Control).position if c is Control else (c as Node2D).position if c is Node2D else Vector2.ZERO
		ui.append([c, pos, dir, c.modulate.a, i])
		i += 1


func _apply_ui(k: float, out: bool) -> void:
	var vs := get_viewport().get_visible_rect().size
	for u in ui:
		if not is_instance_valid(u[0]):
			continue
		var c: CanvasItem = u[0]
		# 순서대로 조금씩 늦게 (나갈 때) · 들어올 때도
		var kk := clampf(k * 1.35 - float(u[4]) * 0.05, 0.0, 1.0)
		var e := kk * kk * (2.7 * kk - 1.7) if out else 1.0 - pow(1.0 - kk, 3.0)      # 나갈 땐 살짝 당겼다가 휙
		var hid := e if out else 1.0 - e
		var dir: Vector2 = u[2]
		var off := Vector2(dir.x * vs.x, dir.y * vs.y) * 0.75 * hid
		if c is Control:
			(c as Control).position = (u[1] as Vector2) + off
		if dir == Vector2.ZERO:
			c.modulate.a = float(u[3]) * (1.0 - clampf(hid, 0.0, 1.0))


func _restore_ui() -> void:
	for u in ui:
		if not is_instance_valid(u[0]):
			continue
		var c: CanvasItem = u[0]
		if c is Control:
			(c as Control).position = u[1]
		c.modulate.a = u[3]


# ── 벌레 ────────────────────────────────────────────────

func _spawn_bugs() -> void:
	var b := boss.global_position
	var f := _fwd
	var side := Vector3(-f.z, 0, f.x)
	var r := room.rect.grow(-1.6)
	var bugs: Array = []
	var lat := [-4.2, -1.4, 1.6, 4.4]
	var far := [9.0, 10.2, 8.4, 9.6]
	for i in BUG_N:
		var at: Vector3 = b + f * float(far[i]) + side * float(lat[i])
		var e := _bug(at, r)
		e.puppet_goal = b + (f * 4.6 + side * lat[i] * 0.55).normalized() * 4.4
		e.puppet_speed = randf_range(2.4, 3.1)
		e.puppet_bite = 1.0
		bugs.append(e)
	# 짓밟힐 한 마리: 오른발 쪽 가까이에서 기어 나와 천천히 발밑으로
	var foot_side := boss.rig.at("pt_foot_r") - b
	var s := signf(foot_side.dot(side))
	if s == 0.0:
		s = 1.0
	var st := _bug(b + f * 6.2 + side * s * 2.4, r)
	st.puppet_speed = 1.5
	st.puppet_goal = st.global_position
	boss.begin_intro(bugs, st)


func _bug(at: Vector3, r: Rect2) -> BugAnt:
	var e := BugAnt.new()
	e.cine = true
	e.puppet = true
	e.hp_mul = 0.5
	e.lure = boss.global_position + Vector3(0, 0, 0)
	main.world.add_child(e)
	at.x = clampf(at.x, r.position.x, r.end.x)
	at.z = clampf(at.z, r.position.y, r.end.y)
	e.global_position = main.map.push_out(at, 0.8)
	var to := boss.global_position - e.global_position
	e.rotation.y = atan2(-to.x, -to.z)
	return e


# ── 매 프레임 ───────────────────────────────────────────

func _process(dt: float) -> void:
	if done:
		return
	var rdt := dt / maxf(Engine.time_scale, 0.01)        # 히트스톱 중에도 화면 연출은 부드럽게
	rdt = minf(rdt, 0.05)
	t += rdt
	if not is_instance_valid(boss):
		_end()
		return
	if not leaving:
		bar_k = minf(1.0, bar_k + rdt / 0.5)
		ui_k = minf(1.0, ui_k + rdt / UI_OUT)
		_apply_ui(ui_k, true)
		if boss.st != LancasterBoss.St.INTRO:
			leaving = true
			leave_t = 0.0
			ui_k = 0.0
	else:
		leave_t += rdt
		if not _bar_shown and bar_k < 0.4 and is_instance_valid(room.bar):
			_bar_shown = true
			room.bar.appear()
		if leave_t > 0.35:
			bar_k = maxf(0.0, bar_k - rdt / 0.5)
			ui_k = minf(1.0, ui_k + rdt / UI_IN)
			_apply_ui(ui_k, false)
	_layout_bars()
	# 말풍선(드론 대사 등)은 연출 동안 숨긴다
	if is_instance_valid(SpeechBubble._layer):
		SpeechBubble._layer.visible = leaving and ui_k > 0.5
	_camera(rdt)
	if leaving and leave_t > 0.35 + maxf(0.5, UI_IN + 0.3) and bar_k <= 0.0:
		_end()


func _camera(dt: float) -> void:
	var b := boss.global_position
	var p := main.player.global_position
	var u := p - b
	u.y = 0
	u = u.normalized() if u.length() > 0.1 else -_fwd
	var perp := Vector3(-u.z, 0, u.x)
	var sk := boss.size_k
	var want_pos := cam.global_position
	var want_look := _look
	var fov := 42.0
	var rate := 1.5
	if leaving:
		shot = "back"
	else:
		match boss.ip:
			"aim", "slaughter":
				shot = "over"
			"stomp", "crush":
				shot = "stomp"
			"glance", "turn_upper", "turn_lower":
				shot = "turn"
			"reload", "alarm":
				shot = "close"
	var side := Vector3(-_fwd.z, 0, _fwd.x)
	match shot:
		"over":
			# 등 돌린 보스의 어깨 너머 — 앞쪽 벌레 떼가 보인다
			want_pos = b - _fwd * 7.2 * sk + side * 3.4 * sk + Vector3.UP * 5.0 * sk
			want_look = b + _fwd * 5.0 + Vector3.UP * 0.9
			fov = 44.0
			rate = 1.1 + minf(t, 1.4) * 0.5
		"stomp":
			# 낮은 옆 구도: 들어 올린 발과 그 아래 벌레
			var foot := boss.call("_foot_r") as Vector3
			var fs := signf((foot - b).dot(side))
			if fs == 0.0:
				fs = 1.0
			want_pos = foot + side * fs * 8.8 * sk + _fwd * 1.6 * sk + Vector3.UP * 1.6 * sk
			want_look = foot + Vector3.UP * 1.6 * sk - side * fs * 0.8
			fov = 42.0
			rate = 2.6
		"turn":
			# 플레이어 쪽 앞에서 올려다본다: 처음엔 등, 돌아서면 얼굴
			want_pos = b + u * 9.0 * sk + perp * 2.6 * sk + Vector3.UP * 2.4 * sk
			want_look = b + Vector3.UP * 2.3 * sk
			fov = 40.0
			rate = 1.3
		"close":
			# 얼굴로 다가간다 (재장전 · 붉은 눈 · 경보)
			var k := clampf(boss.ip_t / 1.2, 0.0, 1.0) if boss.ip == "reload" else 1.0
			want_pos = b + u * lerpf(8.4, 6.6, k) * sk + perp * 1.4 * sk + Vector3.UP * 2.5 * sk
			want_look = b + Vector3.UP * 2.45 * sk
			fov = 36.0 if boss.ip == "reload" else 33.0
			rate = 1.6
		"back":
			want_pos = main.camera.global_position
			want_look = main.camera.global_position - main.camera.global_basis.z * main.camera.global_position.distance_to(main.player.global_position)
			fov = main.camera.fov
			rate = 1.5 + leave_t * 3.0
	_rate = rate
	var a := 1.0 - exp(-rate * dt)
	# 보스 둘레를 도는 궤도 보간 (각도 · 거리 · 높이 따로) — 컷이 바뀔 때 카메라가 보스 몸을 뚫고 지나가지 않게
	var base := cam.get_meta("base", cam.global_position) as Vector3
	var rc := base - b
	var rw := want_pos - b
	var ang := lerp_angle(atan2(rc.x, rc.z), atan2(rw.x, rw.z), a)
	var rad := maxf(lerpf(Vector2(rc.x, rc.z).length(), Vector2(rw.x, rw.z).length(), a), 4.0 * sk)
	base = b + Vector3(sin(ang) * rad, lerpf(rc.y, rw.y, a), cos(ang) * rad)
	cam.set_meta("base", base)
	_look = _look.lerp(want_look, a)
	cam.fov = lerpf(cam.fov, fov, a)
	# 흔들림: 게임 카메라의 trauma 를 그대로 받는다
	var tr := main.camera.trauma
	var amp := tr * tr * 0.55
	var off := Vector3(_noise.get_noise_2d(t * 60.0, 0.0), _noise.get_noise_2d(0.0, t * 60.0), _noise.get_noise_2d(t * 60.0, 50.0)) * amp
	cam.global_position = base + off
	if cam.global_position.distance_to(_look) > 0.1:
		cam.look_at(_look + off * 0.4, Vector3.UP)


## Enter: 건너뛰기
func _unhandled_input(ev: InputEvent) -> void:
	if done or leaving:
		return
	if ev is InputEventKey and (ev as InputEventKey).pressed and not (ev as InputEventKey).echo \
			and ((ev as InputEventKey).keycode == KEY_ENTER or (ev as InputEventKey).keycode == KEY_KP_ENTER):
		skip()
		get_viewport().set_input_as_handled()


func _finish_extras() -> void:
	if is_instance_valid(SpeechBubble._layer):
		SpeechBubble._layer.visible = true
	if not _bar_shown and is_instance_valid(room) and is_instance_valid(room.bar) and is_instance_valid(boss) and boss.alive:
		_bar_shown = true
		room.bar.appear()
	if is_instance_valid(boss):
		boss.intro_directed = false


func skip() -> void:
	if is_instance_valid(boss) and boss.st == LancasterBoss.St.INTRO:
		boss.wake()          # INTRO 중 wake = 바로 끝내고 싸움 시작


func _end() -> void:
	if done:
		return
	done = true
	_restore_ui()
	_finish_extras()
	if is_instance_valid(main) and is_instance_valid(main.player):
		main.player.cine_lock = false
	if is_instance_valid(main) and is_instance_valid(main.camera):
		main.camera.make_current()
	if is_instance_valid(cam):
		cam.queue_free()
	queue_free()


func _exit_tree() -> void:
	if not done:
		done = true
		_restore_ui()
		_finish_extras()
		if is_instance_valid(main) and is_instance_valid(main.player):
			main.player.cine_lock = false
		if is_instance_valid(main) and is_instance_valid(main.camera):
			main.camera.make_current()
		if is_instance_valid(cam):
			cam.queue_free()
