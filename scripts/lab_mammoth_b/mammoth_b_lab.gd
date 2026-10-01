extends Main
## 로비 테스트 씬: MAMMOTH 죽음 연출 B안 "궤도 파손과 전복" 반복 확인용. 같은 감독(mammoth_b_director.gd)을 본선 boss.tscn 격파에서도 쓴다.
## 추격 보스전과 같은 도로 · 카메라 · 플레이어 위에 공격하지 않는 맘모스 더미를 달리게 하고,
## Enter 로 격파 순간부터 복귀까지의 연출만 반복 재생한다. 점수 · 섹터 런 · 저장과 무관.
##
## Enter 재생 / 스킵(0.5초 이후) / 다시 보기   T 관찰 속도 1 · 0.5 · 0.25   G 전복 방향 자동 · 왼쪽 · 오른쪽
## H 흔들림 1 · 0.5 · 0   J 섬광 1 · 0.3 · 0   L 낮은 품질   P 진입 속도 1페이즈 · 2페이즈   U 안내 숨기기
## Esc 로비 · F5 처음부터 (옵션은 유지)

const Stage := preload("res://scripts/boss_stage.gd")
const BossBar := preload("res://scripts/boss_bar.gd")
const SpeedFX := preload("res://scripts/speed_fx.gd")
const BossCamera := preload("res://scripts/boss_camera.gd")
const Dummy := preload("res://scripts/lab_mammoth_b/mammoth_b_dummy.gd")
const Director := preload("res://scripts/lab_mammoth_b/mammoth_b_director.gd")
const LabUI := preload("res://scripts/lab_mammoth_b/mammoth_b_lab_ui.gd")

const SPEEDS := [42.0, 56.0]
const RATES := [1.0, 0.5, 0.25]
const SHAKES := [1.0, 0.5, 0.0]
const FLASHES := [1.0, 0.3, 0.0]
const MIN_GAP := 4.8
const Z_MAX := 6.0

## 씬을 다시 불러와도 유지되는 관찰 옵션
static var opt_rate := 0
static var opt_side := 0           # 0 자동, -1 왼쪽, 1 오른쪽
static var opt_shake := 0
static var opt_flash := 0
static var opt_low := false
static var opt_speed := 0
static var opt_ui := true
static var replay := false

var stage: Stage
var dummy: Dummy
var bar: BossBar
var speed_fx: SpeedFX
var director: Director
var ui: LabUI
var auto_t := 2.2
var jet_t := 0.0


func _ready() -> void:
	inst = self
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	randomize()
	_parse_args()
	for a in OS.get_cmdline_user_args():
		# 캡처 검증용: --labside=-1 / 1 로 전복 방향 고정
		if a.begins_with("--labside="):
			opt_side = clampi(int(a.substr(10)), -1, 1)
	_setup_input()
	world = Node3D.new()
	add_child(world)
	FX.setup(world)
	add_child(Sfx.new())
	_build_environment()
	env.ssao_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.05, 0.12)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	sun.directional_shadow_max_distance = 70.0
	stage = Stage.new()
	stage.speed = SPEEDS[opt_speed]
	world.add_child(stage)
	WorldFlow.attach(world, stage, 30.0)
	bullets = Node3D.new()
	add_child(bullets)

	player = Player.new()
	player.bot = capture_mode
	player.infinite_boost = true
	add_child(player)
	player.global_position = Vector3(0, 0, 3.0)

	dummy = Dummy.new()
	dummy.stage = stage
	world.add_child(dummy)
	# 자동 재생 시 매번 같은 자리에서 시작하도록 흔들림 위상을 고정한다
	dummy.t = 1.3

	camera = BossCamera.new()
	add_child(camera)
	camera.current = true
	(camera as BossCamera).boss = dummy
	camera.snap(player.global_position)
	debris = Debris.new()
	world.add_child(debris)

	hud = Hud.new()
	add_child(hud)
	hud.wave_label.visible = false
	hud.count_label.visible = false
	hud.minimap.visible = false
	var impact := ImpactFrame.new()
	impact.enabled = not OS.get_cmdline_user_args().has("--noimpact")
	add_child(impact)
	speed_fx = SpeedFX.new()
	add_child(speed_fx)
	bar = BossBar.new()
	add_child(bar)
	bar.appear()
	bar.set_hp(0.06)
	bar.set_phase(2)

	director = Director.new()
	add_child(director)
	director.finished.connect(_on_finished)
	ui = LabUI.new()
	ui.director = director
	add_child(ui)
	ui.visible = opt_ui
	if not capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	set_slowmo(RATES[opt_rate])
	auto_t = 1.0 if replay else 2.2
	if not replay:
		hud.banner("DEATH LAB  ·  B", Color("ffd166"), "MAMMOTH 죽음 연출 B안 — 궤도 파손과 전복")
	_refresh_ui()


# ── 연출 시작 · 종료 ────────────────────────────────────

func _start() -> void:
	if director.active or director.done:
		return
	var s := float(opt_side)
	if s == 0.0:
		s = Director.pick_side(dummy.global_position.x, player.global_position.x)
	player.invuln = 999.0
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		b.queue_free()
	director.begin({
		"main": self, "dummy": dummy, "stage": stage, "boss_cam": camera, "bar": bar, "speed_fx": speed_fx,
		"side": s, "rate": RATES[opt_rate], "flash": FLASHES[opt_flash], "shake": SHAKES[opt_shake], "low": opt_low,
	})
	_refresh_ui()


func _on_finished(reason: String) -> void:
	state = State.WIN
	print("WIN t=%.1f reason=%s" % [time, reason])
	FX.victory(player.global_position)
	player.celebrate()
	Sfx.play("win", 0.0)
	bar.hide_bar()
	hud.message("MAMMOTH DESTROYED", "B안 · 궤도 파손과 전복  ·  Enter 다시 보기", Color("7cf5ff"))
	_refresh_ui()


func _replay() -> void:
	replay = true
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


# ── 판정 보조 (Main 계약) ───────────────────────────────

func is_blocked(p: Vector3) -> bool:
	return absf(p.x) > Stage.HALF_W + 4.0 or p.z > 18.0 or p.z < -48.0


func push_out(p: Vector3, radius: float) -> Vector3:
	p.x = clampf(p.x, -Stage.HALF_W + radius, Stage.HALF_W - radius)
	return p


func combat_rooms() -> int:
	return 1


func enemies_left() -> int:
	return 0


# ── 진행 ────────────────────────────────────────────────

func _physics_process(dt: float) -> void:
	time += dt
	player.invuln = maxf(player.invuln, 1.0)
	if not director.active and not director.done:
		auto_t -= dt / maxf(RATES[opt_rate], 0.01)
		if auto_t <= 0.0:
			_start()
	elif director.active and director.T > 1.2 and OS.get_cmdline_user_args().has("--labskip"):
		# 캡처 검증용: Enter 스킵 경로
		director.skip()
	if player.alive:
		var p := player.global_position
		p.x = clampf(p.x, -Stage.HALF_W + 0.4, Stage.HALF_W - 0.4)
		if not director.active and not director.done:
			p.z = clampf(p.z, dummy.global_position.z + MIN_GAP, Z_MAX)
		else:
			p.z = clampf(p.z, -4.0, Z_MAX)
		player.global_position = p
		jet_t -= dt
		if jet_t <= 0.0:
			jet_t = 0.035
			var back := player.global_position + Vector3(randf_range(-0.2, 0.2), 1.1, 0.45)
			stage.puff(back, Color(0.2, 0.9, 1.0, 0.9) if randf() < 0.6 else Color(0.6, 0.5, 1.0, 0.9), 0.45, 0.22, 0.9, true)
	var k := stage.speed / SPEEDS[0]
	(camera as BossCamera).speed_k = k
	if not director.active:
		speed_fx.target_intensity = clampf(k, 0.0, 1.4) if state != State.WIN else 0.25
	var cur := get_viewport().get_camera_3d()
	if cur:
		speed_fx.track(cur, Vector3(cur.global_position.x * 0.3, 0.0, -60.0))


## 연출 중에는 입력을 잠그고 반대 차선의 안전한 자리로 부스터 비행시킨다
func bot_input(p: Player) -> Dictionary:
	var out := {"move": Vector3.ZERO, "aim": p.global_position - Vector3(0, 0, 6), "fire": false, "slash": false, "dash": false, "charge": false, "boost": true}
	if director.active or director.done:
		var to := director.safe_pos - p.global_position
		to.y = 0
		out.move = (to * 0.6).limit_length(1.0) if to.length() > 0.3 else Vector3.ZERO
		return out
	# 캡처 · 자동 확인용: 보스 앞에서 천천히 좌우로
	var want := Vector3(sin(time * 0.6) * 3.0, 0, 2.5)
	var mv := want - p.global_position
	mv.y = 0
	out.move = mv.limit_length(1.0) * 0.6
	out.aim = dummy.global_position + Vector3(0, 0.95, 0)
	return out


func _process(dt: float) -> void:
	# 연출 중 입력 잠금: 사람이 조작하던 플레이어도 자동 비행으로 바꾼다
	player.bot = capture_mode or director.active or director.done
	super._process(dt)


# ── 입력 ────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key := (event as InputEventKey).physical_keycode
		var handled := true
		match key:
			KEY_ENTER, KEY_KP_ENTER:
				if director.active:
					director.skip()
				elif director.done:
					_replay()
				else:
					_start()
			KEY_R:
				if director.done:
					_replay()
				else:
					handled = false
			KEY_T:
				opt_rate = (opt_rate + 1) % RATES.size()
				if not director.active:
					set_slowmo(RATES[opt_rate])
				hud.banner("관찰 속도  ×%.2f" % RATES[opt_rate], Color(1, 1, 1), "연출 시간과 월드를 함께 늦춰 봅니다 (본선 연출은 항상 ×1)")
			KEY_G:
				opt_side = [0, -1, 1][([0, -1, 1].find(opt_side) + 1) % 3]
				hud.banner("전복 방향  %s" % ["자동", "왼쪽", "오른쪽"][[0, -1, 1].find(opt_side)], Color(1, 1, 1), "다음 재생부터 적용")
			KEY_H:
				opt_shake = (opt_shake + 1) % SHAKES.size()
				hud.banner("화면 흔들림  %.1f" % SHAKES[opt_shake], Color(1, 1, 1), "다음 재생부터 적용")
			KEY_J:
				opt_flash = (opt_flash + 1) % FLASHES.size()
				hud.banner("섬광  %.1f" % FLASHES[opt_flash], Color(1, 1, 1), "다음 재생부터 적용")
			KEY_L:
				opt_low = not opt_low
				hud.banner("품질  %s" % ("낮음" if opt_low else "기본"), Color(1, 1, 1), "다음 재생부터 적용")
			KEY_P:
				opt_speed = (opt_speed + 1) % SPEEDS.size()
				if not director.active and not director.done:
					stage.speed = SPEEDS[opt_speed]
				hud.banner("진입 속도  %d m/s" % int(SPEEDS[opt_speed]), Color(1, 1, 1), "1페이즈 42 · 2페이즈 56")
			KEY_U:
				opt_ui = not opt_ui
				ui.visible = opt_ui
			KEY_C:
				# 연출 중 투영 전환 금지 (복귀 시 화면 크기가 튄다)
				handled = director.active
			_:
				handled = false
		if handled:
			_refresh_ui()
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


func _refresh_ui() -> void:
	if ui == null:
		return
	ui.text = "\n".join([
		"DEATH LAB  ·  MAMMOTH B안  궤도 파손과 전복",
		"Enter  재생 / 스킵 / 다시 보기",
		"T  관찰 속도   ×%.2f" % RATES[opt_rate],
		"G  전복 방향   %s" % ["자동", "왼쪽", "오른쪽"][[0, -1, 1].find(opt_side)],
		"H  흔들림   %.1f      J  섬광   %.1f" % [SHAKES[opt_shake], FLASHES[opt_flash]],
		"L  품질   %s      P  진입 속도   %d" % ["낮음" if opt_low else "기본", int(SPEEDS[opt_speed])],
		"U  안내 숨기기 · I 임팩트 프레임 · M 음소거 · Esc 로비",
	])
