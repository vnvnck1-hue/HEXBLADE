class_name RunTutorial
extends Node
## 섹터 런 기본 튜토리얼 — 첫 섹터의 출발 방(포탈 홀)에서 **청소업체 사장**이 대화 형식으로 기본 조작 8단계와
## 게임 방식을 안내한다. 끝나면(또는 건너뛰면) finished 를 쏘고 RunMain 이 포탈을 연다.
##
##  흐름: 사장 대사(타자기, Enter 로 다음 줄) → 해 보기(키 · 진행도, 실제 입력으로 완료) → 사장의 한마디(자동으로 다음) → …
##  단계: 이동 → 사격·재장전 → 광선검 콤보 → 회피 대시 → 부스터 → E 도약 내려찍기 → R 궁극기 → Tab 섹터 지도 → 게임 방식 설명 → 출격
##  사격 단계부터 무적 허수아비(TrainingDummy) 둘이 플레이어 곁에 나타나 사격·검·궁극기를 실제로 맞혀 보게 한다.
##  대사 넘기기 = Space · 대화창 클릭 · Enter (필드 클릭은 넘기지 않는다). 해 보기 중 Enter = 이 단계 건너뛰기 · Backspace = 전체 건너뛰기
##  대사 중엔 공격 입력을 막고(Player.attack_lock), Space 대시는 회피 단계를 배우기 전까지 잠근다(Player.dash_lock) — 대사 중 Space 는 늘 대사 넘기기
##  튜토리얼에서 쓴 탄창·에너지·미사일·점수는 끝날 때 런 값으로 되돌린다 (연습에 재화가 들지 않는다).
##
##  언제 뜨나: 새 런의 첫 출발 방(섹터 1). 한 번 끝내면(건너뛰어도) user://tutorial.cfg 에 기록되어 다음 런부터는
##  자동으로 뜨지 않고 출발 방에서 F1 로 다시 볼 수 있다. --tutorial=on 이면 늘, --tutorial=off 면 안 뜬다.
##  자동 플레이·캡처(--bot/--capture)에서는 --tutorial=on 이 아니면 뜨지 않는다.
##  사장 원화 · 이름 · 목소리는 DialogueCast 의 "owner" 항목(표정 welcome / briefing / encouragement + 눈 감은 프레임)을 그대로 쓴다.

signal finished

const SAVE := "user://tutorial.cfg"
static var enabled := true
static var force := false        # 검사용: 기록·캡처 모드와 상관없이 켠다
static var persist := true       # 끝난 기록을 파일에 남긴다 (검사에서는 끈다)

const WHO := "owner"
const ACCENT := Color(0.57, 0.78, 0.72)      # 사장 색 (DialogueCast)
const MINT := Color(0.45, 1.0, 0.8)
const BG := Color(0.04, 0.04, 0.12, 0.88)
const EDGE := Color(0.55, 0.62, 1.0, 0.35)
const TEXT := Color(0.93, 0.94, 1.0)
const DIM := Color(0.62, 0.66, 0.85)
const CPS := 42.0                # 타자기 속도 (글자/초)
const DASH_STEP := 3             # 이 단계의 해 보기부터 Space 대시가 풀린다
const OK_HOLD := 1.1             # 완료 대사를 다 찍고 다음 단계로 넘어가기까지
const PANEL_W := 820.0
const PANEL_Y := 150.0           # 왼쪽 위 기체 카드 · 상단 방 정보 아래
const PORTRAIT_SRC := Rect2(120, 0, 1010, 1010)   # 원화(1254²)에서 얼굴·상반신만 잘라 쓴다
const TEXT_X := 190.0            # 패널 왼쪽 끝에서 글 시작까지 (초상 자리)

enum St { WAIT, SAY, ACTION, OK, DONE }
var st := St.WAIT
var main: Main
var player: Player
var run: Node
var voice: DialogueVoice
var dummies: Array[TrainingDummy] = []
var steps: Array[Dictionary] = []
var idx := -1
var t := 0.0
var panel: Control
var _skipped := false
var _rect := Rect2()             # 대화 패널 자리 (클릭 판정)
var _res: Dictionary = {}        # 시작 때 런 자원 (끝나면 복구)

# 대사
var _lines: Array = []           # 남은 대사 [{t, e}]
var _line: Dictionary = {}       # 지금 대사
var _shown := 0.0                # 찍힌 글자 수
var _after: Callable             # 대사가 다 끝난 뒤
var _auto := false               # 마지막 대사가 끝나면 Enter 없이 저절로 넘어간다
var _hold := 0.0
var _blip_n := 0
var expr := "welcome"
var _blink_t := 3.0
var _closed := 0.0

# 단계 측정값
var _moved := 0.0
var _last_pos := Vector3.INF
var _gun_hits := 0
var _sword_hits := 0
var _dashes := 0
var _dash_was := false
var _boost_t := 0.0
var _leaps := 0
var _leap_was := false
var _ult_fired := 0
var _ult_was := false
var _ult_pending := false
var _ult_missiles := 0
var _map_opened := false
var _map_closed := false


class TutDummy extends TrainingDummy:
	signal hit(source: String)
	func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
		var was := alive
		super.take_hit(dmg, dir, pos, source)
		if was:
			hit.emit(source)


# ── 켜기 조건 · 기록 ────────────────────────────────────

static func wanted(m: Main) -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--tutorial=off"):
		return false
	if force or args.has("--tutorial=on"):
		return true
	if not enabled or m.capture_mode:
		return false
	return not done()


static func done() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return false
	return bool(cf.get_value("tutorial", "done", false))


static func mark_done() -> void:
	if not persist:
		return
	var cf := ConfigFile.new()
	cf.load(SAVE)
	cf.set_value("tutorial", "done", true)
	cf.save(SAVE)


static func attach(m: Main) -> RunTutorial:
	var tut := RunTutorial.new()
	tut.name = "RunTutorial"
	tut.main = m
	m.add_child(tut)
	return tut


# ── 구성 ────────────────────────────────────────────────

func _ready() -> void:
	player = main.player
	run = get_node_or_null("/root/Run")
	_res = {"hp": player.hp, "energy": player.energy, "missiles": player.missiles}
	voice = DialogueVoice.new()
	add_child(voice)
	_build_steps()
	panel = Control.new()
	panel.name = "TutorialPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.draw.connect(_draw_panel)
	main.hud.root.add_child(panel)
	print("TUTORIAL_BEGIN")


static func _l(text: String, e := "briefing") -> Dictionary:
	return {"t": text, "e": e}


func _build_steps() -> void:
	steps = [
		{"title": "이동", "keys": ["W", "A", "S", "D"], "goal": 6.0, "unit": "m",
		 "value": func() -> float: return _moved,
		 "intro": [_l("왔군요, 신입. 출격 전에 조작만 빠르게 짚을게요. 먼저 W A S D 로 걸어 봐요.", "welcome")],
		 "ok": [_l("좋아요, 감이 오네요.", "encouragement")]},
		{"title": "사격 · 재장전", "keys": ["우클릭", "T"], "goal": 6.0, "unit": "명중",
		 "value": func() -> float: return float(_gun_hits),
		 "intro": [_l("허수아비를 세웠어요. 마우스로 겨누고 우클릭으로 쏴 봐요. 탄창은 30발, T 로 재장전.")],
		 "ok": [_l("명중률 좋네요.", "encouragement")]},
		{"title": "광선검 콤보", "keys": ["좌클릭", "F"], "goal": 5.0, "unit": "명중",
		 "value": func() -> float: return float(_sword_hits),
		 "intro": [_l("좌클릭은 광선검. 허수아비 곁에서 연타하면 6단 콤보가 이어져요. 적중해야 다음 단으로 넘어가요.")],
		 "ok": [_l("시원하네요. 그 검이 우리 회사 간판이에요.", "encouragement")]},
		{"title": "회피 대시", "keys": ["Space"], "goal": 2.0, "unit": "회",
		 "value": func() -> float: return float(_dashes),
		 "intro": [_l("이제 Space. 드릴 회피예요, 도는 동안은 무적. 두 번 해 봐요.")],
		 "ok": [_l("대시가 끝나는 순간 또 누르면 2단 대시, 적의 금빛 별빛 공격이 닿기 직전에 누르면 패링이에요.", "encouragement")]},
		{"title": "부스터 비행", "keys": ["Shift"], "goal": 0.7, "unit": "초",
		 "value": func() -> float: return _boost_t,
		 "intro": [_l("Shift 는 부스터. 게이지가 닳고 과열되면 식혀야 해요. 잠깐 날아 봐요.")],
		 "ok": []},
		{"title": "도약 내려찍기", "keys": ["E"], "goal": 1.0, "unit": "회",
		 "value": func() -> float: return float(_leaps),
		 "intro": [_l("E 를 누른 채 착지점을 고르고 떼면 도약 내려찍기. 원 안의 적은 기절해요.")],
		 "ok": []},
		{"title": "궁극기 · 락온 미사일", "keys": ["R"], "goal": 1.0, "unit": "회",
		 "value": func() -> float: return float(_ult_fired),
		 "intro": [_l("R 을 누르고 있으면 슬로모션. 허수아비를 스쳐 락온하고 떼면 미사일을 전부 쏴요. 미사일은 보급으로만 채워요.")],
		 "ok": []},
		{"title": "섹터 지도", "keys": ["Tab"], "goal": 2.0, "unit": "",
		 "value": func() -> float: return (1.0 if _map_opened else 0.0) + (1.0 if _map_closed else 0.0),
		 "intro": [_l("조작은 끝. Tab 으로 섹터 지도를 열고 닫아 봐요.")],
		 "ok": []},
		# 마지막: 해 보기 없이 게임 방식 설명 → 출격
		{"title": "게임 방식", "keys": [], "goal": -1.0, "unit": "", "value": func() -> float: return 0.0,
		 "intro": [
			_l("의뢰는 이래요. 포탈을 골라 단계를 올라가 섹터 끝의 보스를 잡아요. 전투 구역은 다 치우면 코인과 출구 포탈, 정비 구역은 장갑 +3."),
			_l("장갑은 방을 옮겨도 이어지고 0 이면 실패. 에너지와 미사일은 보급으로만 채워요. 드론이 잔해를 치우면 지원 게이지 — Q 합체, X 보호막, Z 청소."),
			_l("준비됐죠? 포탈을 열게요. 다녀와요, 신입.", "encouragement"),
		 ],
		 "ok": []},
	]


## 허수아비 둘: 사격 단계가 시작될 때 플레이어 좌우 4.2m 옆줄에 나타난다 (화면 위 대화 패널에 가리지 않는 자리)
func _spawn_dummies() -> void:
	if not dummies.is_empty():
		return
	var base := player.global_position
	for sx in [-4.2, 4.2]:
		var d := TutDummy.new()
		var p := base + Vector3(sx, 0, 0.0)
		d.anchor = main.map.push_out(p, 1.0)
		d.immortal = true
		main.world.add_child(d)
		d.global_position = d.anchor
		d.rotation.y = atan2(-(base.x - p.x), -(base.z - p.z))
		d.hit.connect(_on_dummy_hit)
		dummies.append(d)
		FX.flash(d.anchor + Vector3(0, 1.0, 0), MINT, 1.4, 0.15)
		FX.shockwave(d.anchor + Vector3(0, 0.1, 0), MINT, 2.0, 0.35)
	Sfx.play("spawn", 0.0, -4.0)


func _on_dummy_hit(source: String) -> void:
	if source in ["bullet"]:
		_gun_hits += 1
	elif source not in ["laser", "missile", "orb"]:
		_sword_hits += 1


func _clear_dummies() -> void:
	for d in dummies:
		if is_instance_valid(d):
			FX.flash(d.global_position + Vector3(0, 1.0, 0), MINT, 1.2, 0.15)
			FX.sparks(d.global_position + Vector3(0, 1.0, 0), 14, [MINT, Color.WHITE], 4.0, 0.5, -6.0, 0.06)
			d.queue_free()
	dummies.clear()


# ── 진행 ────────────────────────────────────────────────

func active() -> bool:
	return st != St.DONE


func step_title() -> String:
	return steps[idx].title if idx >= 0 and idx < steps.size() else ""


## 지금 대사를 다 찍었나
func line_done() -> bool:
	return not _line.is_empty() and _shown >= _line.t.length()


func _physics_process(dt: float) -> void:
	if st == St.DONE or not is_instance_valid(player) or not player.alive:
		return
	t += dt
	_blink_t -= dt
	if _blink_t <= 0.0:
		_closed = 0.12
		_blink_t = randf_range(2.8, 6.0)
	_closed = maxf(0.0, _closed - dt)
	match st:
		St.WAIT:
			# 등장 연출이 끝난 뒤 시작
			if not player.entrance_busy() and t > 0.4:
				_next_step()
		St.SAY, St.OK:
			_type(dt)
		St.ACTION:
			_measure(dt)
			var s := steps[idx]
			if (s.value as Callable).call() >= s.goal:
				_step_ok()
	_apply_locks()
	if panel:
		_rect = _layout()
		panel.queue_redraw()


## 대사 중엔 공격을 막고, Space 대시는 회피 단계의 해 보기부터 푼다 (대사 중 Space 는 늘 대사 넘기기)
func _apply_locks() -> void:
	var talking := st == St.SAY or st == St.OK or st == St.WAIT
	player.attack_lock = talking
	player.dash_lock = talking or idx < DASH_STEP


func _type(dt: float) -> void:
	if _line.is_empty():
		return
	var n: int = _line.t.length()
	if _shown < n:
		var before := int(_shown)
		_shown = minf(_shown + CPS * dt, n)
		var now := int(_shown)
		if now > before:
			_blip_n += now - before
			if _blip_n >= 2:
				_blip_n = 0
				voice.blip(WHO)
		if _shown >= n:
			_hold = 0.0
	elif _auto and _lines.is_empty():
		_hold += dt
		if _hold >= OK_HOLD:
			_advance()


## 대사 묶음을 시작한다. after: 다 끝난 뒤 할 일
func _say(lines: Array, after: Callable, auto := false) -> void:
	_lines = lines.duplicate()
	_after = after
	_auto = auto
	_begin_line()


func _begin_line() -> void:
	if _lines.is_empty():
		_line = {}
		_after.call()
		return
	_line = _lines.pop_front()
	expr = _line.e
	_shown = 0.0
	_hold = 0.0
	_blip_n = 0


## Enter: 찍는 중이면 다 보여 주고, 다 보였으면 다음 대사(없으면 after)
func _advance() -> void:
	if _line.is_empty():
		return
	if _shown < _line.t.length():
		_shown = _line.t.length()
		return
	_begin_line()


func _next_step() -> void:
	idx += 1
	if idx >= steps.size():
		finish()
		return
	if idx == 1:
		_spawn_dummies()
	if steps[idx].title.begins_with("궁극기"):
		player.missiles = maxi(player.missiles, 2)     # 연습용 미사일 (끝나면 복구)
	st = St.SAY
	print("TUTORIAL_STEP %d %s" % [idx + 1, steps[idx].title])
	_say(steps[idx].intro, _begin_action)


func _begin_action() -> void:
	var s := steps[idx]
	if s.goal < 0.0:
		# 해 보기 없는 단계(게임 방식 설명): 대사가 끝나면 바로 출격
		finish()
		return
	st = St.ACTION
	_dash_was = player.dash_t > 0.0
	_leap_was = player.leap.busy()
	_ult_was = player.ult_aiming
	_ult_pending = false
	_last_pos = player.global_position
	Sfx.play("ready", 0.0, -4.0)


func _step_ok() -> void:
	st = St.OK
	Sfx.play("lock", 0.0, -2.0)
	main.hud.screen_flash(MINT, 0.12)
	var s := steps[idx]
	if (s.ok as Array).is_empty():
		_next_step()
	else:
		_say(s.ok, _next_step, true)


func _measure(dt: float) -> void:
	# 이동: 대시·도약이 아닌 보통 걸음만 센다
	if _last_pos != Vector3.INF and player.dash_t <= 0.0 and not player.leap.busy():
		var d := player.global_position - _last_pos
		d.y = 0
		_moved += minf(d.length(), 0.4)
	_last_pos = player.global_position
	var dashing := player.dash_t > 0.0
	if dashing and not _dash_was:
		_dashes += 1
	_dash_was = dashing
	if player.boosting:
		_boost_t += dt
	var leaping := player.leap.busy()
	if leaping and not _leap_was:
		_leaps += 1
	_leap_was = leaping
	# 궁극기: 조준 시작 때 미사일 수를 기억하고, 준비동작 뒤 실제로 발사되면(미사일이 줄면) 센다
	if player.ult_aiming and not _ult_was:
		_ult_missiles = player.missiles
		_ult_pending = true
	if _ult_pending and not player.ult_aiming:
		if player.ult_queue > 0 or player.missiles < _ult_missiles:
			_ult_fired += 1
			_ult_pending = false
		elif not player.ult_winding():
			_ult_pending = false      # 조준만 하고 취소
	_ult_was = player.ult_aiming
	if run and run.map_view:
		if run.map_view.want:
			_map_opened = true
		elif _map_opened:
			_map_closed = true


## Enter: 대사 중엔 다음 줄, 해 보기 중엔 이 단계 건너뛰기
func skip_step() -> void:
	match st:
		St.SAY, St.OK:
			_advance()
		St.ACTION:
			_step_ok()
		St.WAIT:
			pass


## Backspace: 전체 건너뛰기
func skip_all() -> void:
	_skipped = true
	finish()


func finish() -> void:
	if st == St.DONE:
		return
	st = St.DONE
	_line = {}
	player.attack_lock = false
	player.dash_lock = false
	_clear_dummies()
	# 연습에 쓴 재화 복구
	player.hp = _res.hp
	player.energy = _res.energy
	player.missiles = _res.missiles
	player.mag = Player.MAG_SIZE
	player.reload_t = 0.0
	player.boost = 1.0
	if run and run.map_view:
		run.map_view.want = false
	main.score = 0
	main.kills = 0
	# 콤보 창이 늦게 정산하는 점수까지 지운다
	get_tree().create_timer(ComboMeter.WINDOW + 0.5, false).timeout.connect(func():
		if is_instance_valid(main):
			main.score = 0)
	mark_done()
	if panel:
		var tw := panel.create_tween()
		tw.tween_property(panel, "modulate:a", 0.0, 0.3)
		tw.tween_callback(panel.queue_free)
		panel = null
	print("TUTORIAL_END skipped=%s" % _skipped)
	finished.emit()


## HUD 의 Control 들이 마우스 이벤트를 먹기 전에 받아야 하므로 _unhandled_input 이 아니라 _input
func _input(event: InputEvent) -> void:
	if st == St.DONE:
		return
	var talking := st == St.SAY or st == St.OK
	if event is InputEventMouseButton:
		# 대화창 클릭 = 다음 대사. 필드 클릭은 대사를 넘기지 않는다 (대사 중엔 공격도 잠겨 있다)
		var mb := event as InputEventMouseButton
		# _input 의 마우스 위치는 화면 배율을 거친 캔버스 좌표라 패널 자리와 바로 비교한다
		if talking and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and _rect.has_point(mb.position):
			get_viewport().set_input_as_handled()
			_advance()
		return
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var k := (event as InputEventKey).physical_keycode
	if k == KEY_SPACE and talking:
		get_viewport().set_input_as_handled()
		_advance()
	elif k == KEY_ENTER or k == KEY_KP_ENTER:
		get_viewport().set_input_as_handled()
		skip_step()
	elif k == KEY_BACKSPACE:
		get_viewport().set_input_as_handled()
		skip_all()


## 대화창 자리 (클릭 판정 · 검사용). 그리기와 상관없이 매 틱 계산한다 (헤드리스에서도 클릭 판정이 되게)
func rect() -> Rect2:
	return _rect


func _layout() -> Rect2:
	if idx < 0 or panel == null:
		return Rect2()
	var font: Font = main.hud.font
	var w := PANEL_W
	var x := (panel.size.x - w) * 0.5
	var body_w := w - TEXT_X - 24.0
	var full: String = _line.t if not _line.is_empty() else ""
	var lines := _wrap_lines(font, full, body_w, 16)
	var h := 76.0 + lines * 22.0 + (44.0 if st == St.ACTION else 10.0)
	return Rect2(x, PANEL_Y, w, maxf(h, 166.0))


# ── 화면: 사장 대화 패널 ─────────────────────────────────

func _draw_panel() -> void:
	if st == St.DONE or st == St.WAIT or panel == null or idx < 0:
		return
	var font: Font = main.hud.font
	var s := steps[idx]
	var action := st == St.ACTION
	var r := _layout()
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var body_w := w - TEXT_X - 24.0
	var full: String = _line.t if not _line.is_empty() else ""
	var pulse := 0.5 + 0.5 * sin(t * 4.0)
	var edge := Color(EDGE.r, EDGE.g, EDGE.b, 0.3 + 0.3 * pulse) if action else EDGE
	if st == St.OK:
		edge = MINT
	panel.draw_rect(r, BG)
	panel.draw_rect(r, edge, false, 2.0)
	# 사장 초상: 패널 왼쪽 칸에 얼굴·상반신 (표정은 대사마다, 가끔 눈 깜빡임, 숨쉬기)
	var tex := DialogueCast.texture(WHO, expr, _closed > 0.0)
	if tex:
		var ps := h - 16.0
		var bob := sin(t * 1.7) * 1.5
		panel.draw_texture_rect_region(tex, Rect2(x + 14.0, y + 8.0 + bob, ps, ps), PORTRAIT_SRC)
	# 이름표 · 단계
	var info := DialogueCast.info(WHO)
	panel.draw_string(font, Vector2(x + TEXT_X, y + 30), str(info.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ACCENT)
	var nw := font.get_string_size(str(info.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	panel.draw_string(font, Vector2(x + TEXT_X + nw + 10, y + 30), str(info.en), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	var head := "TUTORIAL  %d / %d  ·  %s" % [idx + 1, steps.size(), s.title]
	panel.draw_string(font, Vector2(x + w - 24 - font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x, y + 30), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	# 대사 (타자기)
	var shown_text := full.substr(0, int(_shown))
	panel.draw_multiline_string(font, Vector2(x + TEXT_X, y + 62), shown_text, HORIZONTAL_ALIGNMENT_LEFT, body_w, 16, -1, TEXT)
	var by := y + h - 22.0
	if action:
		# 해 보기: 키 칩 · 진행 막대
		var kx := x + TEXT_X
		for key in s.keys:
			kx = _draw_key(font, Vector2(kx, by - 14), str(key)) + 8.0
		var bw := 220.0
		var v: float = (s.value as Callable).call()
		var k := clampf(v / s.goal, 0.0, 1.0)
		var bx := kx + 12.0
		panel.draw_rect(Rect2(bx, by - 18, bw, 9), Color(1, 1, 1, 0.1))
		panel.draw_rect(Rect2(bx, by - 18, bw * k, 9), Color(0.55, 0.75, 1.0))
		panel.draw_string(font, Vector2(bx + bw + 12, by - 9), _progress_text(s, v), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, TEXT)
		var foot := "Enter 건너뛰기  ·  Backspace 전체 건너뛰기"
		panel.draw_string(font, Vector2(x + w - 24 - font.get_string_size(foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x, by + 6), foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	else:
		var foot := "Space · 클릭 ▶" if not line_done() or not _lines.is_empty() or not _auto else ""
		if line_done() and s.goal < 0.0 and _lines.is_empty():
			foot = "Space · 클릭  출격"
		if foot != "":
			var a := 0.75 + 0.25 * sin(t * 5.0) if line_done() else 0.4
			panel.draw_string(font, Vector2(x + w - 24 - font.get_string_size(foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, by + 4), foot, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, a))
		if st == St.SAY:
			var foot2 := "Backspace 전체 건너뛰기"
			panel.draw_string(font, Vector2(x + TEXT_X, by + 4), foot2, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)


func _progress_text(s: Dictionary, v: float) -> String:
	if s.unit == "m" or s.unit == "초":
		return "%.1f / %.0f %s" % [minf(v, s.goal), s.goal, s.unit]
	if s.unit == "":
		return "%s  ·  %s" % ["열기 ✓" if _map_opened else "열기", "닫기 ✓" if _map_closed else "닫기"]
	return "%d / %d %s" % [int(minf(v, s.goal)), int(s.goal), s.unit]


## 키 칩을 그리고 오른쪽 끝 x 를 돌려준다
func _draw_key(font: Font, left_center: Vector2, key: String) -> float:
	var tw := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var kw := tw + 18.0
	var r := Rect2(left_center.x, left_center.y - 11, kw, 22)
	panel.draw_rect(r, Color(1, 1, 1, 0.12))
	panel.draw_rect(r, Color(1, 1, 1, 0.3), false, 1.0)
	panel.draw_string(font, Vector2(left_center.x + 9, left_center.y + 5), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.95))
	return left_center.x + kw


func _wrap_lines(font: Font, text: String, width: float, size: int) -> int:
	if text == "":
		return 1
	var hgt := maxf(1.0, font.get_height(size))
	return maxi(1, roundi(font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, size).y / hgt))
