class_name StreamMain
extends Main
## 무한 비행 모드 (종 스크롤 슈팅). 추격 보스전의 흐르는 도로(boss_stage.gd) 위를 부스터로 끝없이 날아가며,
## 화면 위(-Z)에서 편대로 날아 들어오는 적을 격추한다. 끝이 없고, 시간이 지날수록 섹터가 올라 적이 많고 단단해진다.
##
##  - 좌표: 플레이어는 원점 근처에 머물고 공간(바닥·구조물·연출)이 +Z 로 흐른다 (WorldFlow).
##    적 탄·전투기는 이 좌표에서 움직이므로 화면 기준으로 날아다닌다.
##  - 편대: StreamFighter(경로 비행 · 지나가면 놓침) · StreamDrone(앞쪽에 버티다 이탈) · Striker · Crawler(정예)
##  - 섹터: SECTOR_TIME 마다 1 올라간다. 도로가 빨라지고, 편대 간격이 줄고, 적 체력·동시 수가 는다.
##    ELITE_EVERY 섹터마다 정예(Crawler) 편대가 경고와 함께 나온다.
##  - 편대 보너스: 한 편대를 하나도 놓치지 않고 모두 격추하면 점수와 재화를 준다.
##  - 기록: 최고 비행 거리 · 점수 · 섹터를 user://stream_best.cfg 에 남긴다.

const Stage := preload("res://scripts/boss_stage.gd")
const SpeedFX := preload("res://scripts/speed_fx.gd")
const BossCamera := preload("res://scripts/boss_camera.gd")

const SPEED_START := 24.0     # 도로 속도 (m/s) — 거리 계산과 배경 흐름
const SPEED_MAX := 44.0
const SPEED_STEP := 2.2       # 섹터마다 빨라지는 양
const SECTOR_TIME := 30.0
const ELITE_EVERY := 4
const PLAYER_Z_MIN := -9.0
const PLAYER_Z_MAX := 6.0
const LOOK_AHEAD := 11.0      # 카메라가 플레이어보다 앞(-Z)을 더 보게 하는 거리
const FLOW_FAR_Z := 30.0
const VIEW_K := 1.6
const PICKUP_DRIFT := 3.5     # 떨어진 재화가 화면 아래로 흘러가는 속도
const BEST_PATH := "user://stream_best.cfg"
const WAVE_BONUS := 500

var stage: Stage
var speed_fx: SpeedFX
var anchor: Node3D            # 카메라 시선 당김용 (BossCamera 의 boss 자리에 둔다)
var info: Label
var info_layer: CanvasLayer

var sector := 1
var distance := 0.0
var escaped := 0
var wave_count := 0
var wave_timer := 1.6
var schedule: Array = []      # [{at, fn}] 편대 안 개별 소환 예약
var waves: Dictionary = {}    # wave_id → {left, lost, pos}
var elite_alive := false
var best := {"distance": 0.0, "score": 0, "sector": 0}
var new_best := false
var save_records := true      # 기록 파일에 남길까 (자동 플레이·테스트는 끈다)
var jet_t := 0.0
var bot_side := 1.0
var arg_godmode := false
var arg_sector := 0
var quit_at := -1.0
var _wave_seq := 0


func _ready() -> void:
	inst = self
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	randomize()
	_parse_args()
	for a in cmd_args:
		if a == "--godmode":
			arg_godmode = true
		elif a.begins_with("--sector="):
			arg_sector = maxi(1, int(a.substr(9)))
		elif a.begins_with("--seconds=") and capture_mode and capture_dir == "":
			quit_at = float(a.substr(10))
	if map_seed >= 0:
		seed(map_seed)
	_setup_input()
	world = Node3D.new()
	add_child(world)
	FX.setup(world)
	add_child(Sfx.new())
	_build_environment()
	env.ssao_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.04, 0.05, 0.13)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	sun.directional_shadow_max_distance = 70.0
	stage = Stage.new()
	stage.speed = SPEED_START
	world.add_child(stage)
	WorldFlow.attach(world, stage, FLOW_FAR_Z)
	bullets = Node3D.new()
	add_child(bullets)

	player = Player.new()
	player.bot = capture_mode
	player.infinite_boost = true
	add_child(player)
	player.global_position = Vector3(0, 0, 3.0)

	anchor = Node3D.new()
	add_child(anchor)
	camera = BossCamera.new()
	add_child(camera)
	camera.current = true
	(camera as BossCamera).boss = anchor
	_place_anchor()
	camera.snap(player.global_position)
	debris = Debris.new()
	world.add_child(debris)
	world.add_child(GunFX.new())
	world.add_child(Parry.new())       # 패링: 요격기 돌진 베기 · 드론 금빛 탄을 대시로 받아친다
	add_child(ParryFX.new())
	ToonGunFX.inst.view_k = VIEW_K

	hud = Hud.new()
	add_child(hud)
	hud.wave_label.visible = false
	hud.count_label.visible = false
	hud.minimap.visible = false
	var impact := ImpactFrame.new()
	impact.enabled = not cmd_args.has("--noimpact")
	add_child(impact)
	PartnerDrone.attach(self)      # 파트너 청소 드론 (끄기: --drone=off)
	speed_fx = SpeedFX.new()
	add_child(speed_fx)
	_build_info()
	_load_best()
	if not capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if arg_sector > 1:
		_set_sector(arg_sector, false)
	hud.banner("ENDLESS FLIGHT", Color(0.7, 0.95, 1.0), "끝없이 날아가며 몰려오는 편대를 격추하라")


func _exit_tree() -> void:
	_save_best()
	super()


# ── 판정 보조 (방·벽 대신 좌우 차선만 막는다) ─────────────

func is_blocked(p: Vector3) -> bool:
	return absf(p.x) > Stage.HALF_W + 4.0 or p.z > 18.0 or p.z < -60.0


func push_out(p: Vector3, radius: float) -> Vector3:
	p.x = clampf(p.x, -Stage.HALF_W + radius, Stage.HALF_W - radius)
	return p


func combat_rooms() -> int:
	return 1


func enemies_left() -> int:
	return _alive_count()


func _alive_count() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.get("prop"):
			n += 1
	return n


# ── 섹터 · 난이도 ───────────────────────────────────────

## 동시에 화면에 있어도 되는 적 수
func max_alive() -> int:
	var n := mini(5 + sector * 2, 22)
	return mini(n, 7) if elite_alive else n


func wave_gap() -> float:
	return maxf(0.9, 3.0 - sector * 0.18)


func hp_scale() -> float:
	return 1.0 + (sector - 1) * 0.14


func _set_sector(n: int, announce := true) -> void:
	sector = n
	var sp := minf(SPEED_START + (sector - 1) * SPEED_STEP, SPEED_MAX)
	create_tween().tween_property(stage, "speed", sp, 1.6).set_trans(Tween.TRANS_QUAD)
	if not announce:
		stage.speed = sp
		return
	var elite := sector % ELITE_EVERY == 0
	if elite:
		hud.banner("WARNING", Color("ff3a4a"), "SECTOR %d · 정예 기체 접근" % sector)
		Sfx.play("twind", 0.0, -2.0)
		_queue_elite()
	else:
		hud.banner("SECTOR %d" % sector, Color(0.6, 1.0, 0.85), "속도 상승 · 적 증가")
		Sfx.play("spawn", 0.0, -2.0)
	shake(0.25)


# ── 진행 ────────────────────────────────────────────────

func _physics_process(dt: float) -> void:
	time += dt
	if combo > 0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 0
	if arg_godmode:
		player.invuln = 999.0
	if state == State.PLAY:
		distance += stage.speed * dt
		var due := 1 + int(time / SECTOR_TIME) + maxi(arg_sector - 1, 0)
		if due > sector:
			_set_sector(due)
		_run_schedule()
		wave_timer -= dt
		if wave_timer <= 0.0 and schedule.is_empty() and _alive_count() < max_alive():
			_launch_wave()
			wave_timer = wave_gap() * randf_range(0.85, 1.2)
	_flow_pickups(dt)
	_clamp_player(dt)
	(camera as BossCamera).speed_k = stage.speed / 42.0
	speed_fx.target_intensity = clampf(stage.speed / 36.0, 0.3, 1.3) if state == State.PLAY else 0.15
	var cur := get_viewport().get_camera_3d()
	if cur:
		speed_fx.track(cur, Vector3(cur.global_position.x * 0.3, 0.0, -60.0))
	_place_anchor()
	_update_info()
	if quit_at > 0.0 and time >= quit_at:
		print("STREAM t=%.1f sector=%d dist=%d kills=%d escaped=%d waves=%d score=%d alive=%s" % [time, sector, int(distance), kills, escaped, wave_count, score, str(player.alive)])
		quit_at = -1.0
		get_tree().quit()


func _place_anchor() -> void:
	if anchor and player:
		anchor.global_position = Vector3(player.global_position.x, 0, player.global_position.z - LOOK_AHEAD)


func _clamp_player(dt: float) -> void:
	if not player.alive:
		return
	var p := player.global_position
	p.x = clampf(p.x, -Stage.HALF_W + 0.4, Stage.HALF_W - 0.4)
	p.z = clampf(p.z, PLAYER_Z_MIN, PLAYER_Z_MAX)
	player.global_position = p
	jet_t -= dt
	if jet_t <= 0.0:
		jet_t = 0.04
		var back := player.global_position + Vector3(randf_range(-0.2, 0.2), 1.1, 0.45)
		stage.puff(back, Color(0.2, 0.9, 1.0, 0.9) if randf() < 0.6 else Color(0.6, 0.5, 1.0, 0.9), 0.4, 0.2, 0.9, true)


## 떨어진 재화는 공간과 함께 천천히 화면 아래로 흘러간다 (놓치면 사라진다)
func _flow_pickups(dt: float) -> void:
	for pk in get_tree().get_nodes_in_group("pickups"):
		var n := pk as Node3D
		n.position.z += PICKUP_DRIFT * dt
		if n.position.z > StreamFighter.BOTTOM_Z:
			n.queue_free()


func _run_schedule() -> void:
	var i := 0
	while i < schedule.size():
		var it: Dictionary = schedule[i]
		if time >= float(it.at):
			schedule.remove_at(i)
			(it.fn as Callable).call()
		else:
			i += 1


func _later(delay: float, fn: Callable) -> void:
	schedule.append({"at": time + delay, "fn": fn})


# ── 편대 ────────────────────────────────────────────────

## 섹터에 따라 나올 수 있는 편대와 가중치
func _wave_pool() -> Array:
	var pool := [["line", 3.0], ["vee", 3.0], ["snake", 2.5]]
	if sector >= 2:
		pool += [["swoop", 2.5], ["hook", 2.0], ["gunship", 1.6]]
	if sector >= 3:
		pool += [["dive", 2.0], ["pincer", 1.6]]
	if sector >= 4:
		pool += [["striker", 1.2], ["bomber", 1.6]]
	if sector >= 6:
		pool += [["storm", 1.4]]
	return pool


func _launch_wave() -> void:
	var pool := _wave_pool()
	var total := 0.0
	for p in pool:
		total += float(p[1])
	var r := randf() * total
	var pick := "line"
	for p in pool:
		r -= float(p[1])
		if r <= 0.0:
			pick = p[0]
			break
	launch(pick)


## 편대 하나를 띄운다 (테스트에서도 부른다)
func launch(kind: String) -> int:
	wave_count += 1
	_wave_seq += 1
	var id := _wave_seq
	waves[id] = {"left": 0, "lost": 0, "pos": Vector3.ZERO}
	var x := randf_range(-5.0, 5.0)
	var sd := 1.0 if randf() < 0.5 else -1.0
	var sp := 7.0 + sector * 0.25
	match kind:
		"line":
			# 가로 한 줄이 함께 내려온다
			var n := 4 + mini(sector / 3, 2)
			for i in n:
				var xi := lerpf(-7.0, 7.0, float(i) / float(n - 1))
				_fighter(id, StreamFighter.Path.STRAIGHT, StreamFighter.Kind.DART, xi, sp, 0.0)
		"vee":
			# V 자 편대: 가운데가 앞장선다
			for i in 5:
				var k := i - 2
				_fighter(id, StreamFighter.Path.STRAIGHT, StreamFighter.Kind.DART, x + k * 1.8, sp, absf(k) * 0.28)
		"snake":
			# 한 줄로 늘어서 좌우로 꿈틀대며 내려온다
			for i in 6:
				_fighter(id, StreamFighter.Path.SINE, StreamFighter.Kind.DART, x * 0.5, sp * 0.9, i * 0.32, {"side": sd, "amp": 4.0})
		"swoop":
			# 위 한쪽 구석에서 차례로 들어와 반대편으로 휘어 나간다
			for i in 5:
				_fighter(id, StreamFighter.Path.SWOOP, StreamFighter.Kind.DART, 0.0, 12.0 + sector * 0.3, i * 0.3, {"side": sd})
		"hook":
			# 큰 폭격기가 내려와 멈춰 쏜 뒤 돌아 나간다
			for i in 3:
				_fighter(id, StreamFighter.Path.HOOK, StreamFighter.Kind.WING, lerpf(-6.0, 6.0, i / 2.0), sp, i * 0.4, {"side": -1.0 if i < 1 else 1.0, "stop": -10.0 + randf_range(-1.5, 1.5)})
		"dive":
			# 내려와 연사하다가 플레이어 쪽으로 급강하해 지나간다
			for i in 2 + mini(sector / 4, 2):
				_fighter(id, StreamFighter.Path.DIVE, StreamFighter.Kind.DART, randf_range(-7.0, 7.0), sp, i * 0.55, {"stop": randf_range(-12.0, -8.0)})
		"pincer":
			# 양쪽 구석에서 동시에 들어와 엇갈린다
			for i in 3:
				_fighter(id, StreamFighter.Path.SWOOP, StreamFighter.Kind.DART, 0.0, 12.0, i * 0.3, {"side": 1.0})
				_fighter(id, StreamFighter.Path.SWOOP, StreamFighter.Kind.DART, 0.0, 12.0, i * 0.3 + 0.15, {"side": -1.0})
		"bomber":
			# 폭격기 둘 + 호위 요격기 줄
			_fighter(id, StreamFighter.Path.STRAIGHT, StreamFighter.Kind.WING, -4.0, sp * 0.75, 0.0)
			_fighter(id, StreamFighter.Path.STRAIGHT, StreamFighter.Kind.WING, 4.0, sp * 0.75, 0.0)
			for i in 4:
				_fighter(id, StreamFighter.Path.SINE, StreamFighter.Kind.DART, 0.0, sp, 0.6 + i * 0.3, {"side": sd, "amp": 6.0})
		"gunship":
			# 앞쪽에 버티는 포격 드론
			for i in 2 + mini(sector / 5, 1):
				_drone(id, Vector3(lerpf(-5.0, 5.0, randf()), 0, randf_range(-13.0, -9.0)), i * 0.5)
		"striker":
			for i in 1 + mini(sector / 6, 1):
				_ground_enemy(id, Striker.new(), Vector3(randf_range(-6.0, 6.0), 0, randf_range(-10.0, -6.0)), i * 0.6)
			for i in 3:
				_fighter(id, StreamFighter.Path.STRAIGHT, StreamFighter.Kind.DART, randf_range(-7.0, 7.0), sp, 0.8 + i * 0.4)
		"storm":
			# 혼합 대편대
			for i in 4:
				_fighter(id, StreamFighter.Path.SWOOP, StreamFighter.Kind.DART, 0.0, 13.0, i * 0.25, {"side": sd})
			_fighter(id, StreamFighter.Path.HOOK, StreamFighter.Kind.WING, 0.0, sp, 0.6, {"side": -sd, "stop": -11.0})
			_drone(id, Vector3(-sd * 5.0, 0, -11.0), 1.0)
		_:
			push_warning("unknown wave %s" % kind)
	return id


func _fighter(id: int, path: int, kind: int, x: float, sp: float, delay: float, opts := {}) -> void:
	waves[id].left += 1    # 예약분도 편대 크기에 넣는다 (먼저 나온 기체를 다 잡았다고 편대가 끝나지 않게)
	_later(delay, func():
		if state == State.LOSE:
			waves[id].left -= 1
			return
		var f := StreamFighter.new()
		f.path = path
		f.kind = kind
		f.x0 = x
		f.speed = sp
		f.wave_id = id
		f.side = float(opts.get("side", 1.0))
		f.amp = float(opts.get("amp", 3.0))
		f.stop_z = float(opts.get("stop", -9.0))
		f.phase = randf() * TAU
		f.hp_mul = hp_scale()
		f.set_meta("stream_wave", id)
		world.add_child(f))


func _drone(id: int, pos: Vector3, delay: float) -> void:
	waves[id].left += 1
	_later(delay, func():
		if state == State.LOSE:
			waves[id].left -= 1
			return
		var d := StreamDrone.new()
		d.pattern = [Enemy.Pattern.AIMED_BURST, Enemy.Pattern.FAN, Enemy.Pattern.RING][randi() % (1 + mini(sector / 2, 2))]
		d.wave_id = id
		d.stay = 11.0 + randf() * 4.0
		d.hp_mul = hp_scale()
		d.set_meta("stream_wave", id)
		world.add_child(d)
		d.global_position = pos
		FX.spawn_marker(pos, 0.5))


func _ground_enemy(id: int, e: Enemy, pos: Vector3, delay: float) -> void:
	waves[id].left += 1
	_later(delay, func():
		if state == State.LOSE:
			waves[id].left -= 1
			e.free()
			return
		e.hp_mul = hp_scale()
		e.set_meta("stream_wave", id)
		world.add_child(e)
		e.global_position = pos
		FX.spawn_marker(pos, 0.5))


## 정예 편대: 큰 크롤러 하나 + 호위. 크롤러가 있는 동안은 새 편대를 가볍게 줄인다
func _queue_elite() -> void:
	wave_count += 1
	_wave_seq += 1
	var id := _wave_seq
	waves[id] = {"left": 0, "lost": 0, "pos": Vector3.ZERO}
	elite_alive = true
	var c := Crawler.new()
	c.set_meta("stream_elite", true)
	_ground_enemy(id, c, Vector3(0, 0, -9.0), 1.2)
	for i in 4:
		_fighter(id, StreamFighter.Path.SWOOP, StreamFighter.Kind.DART, 0.0, 12.0, 2.0 + i * 0.3, {"side": 1.0 if i % 2 == 0 else -1.0})


# ── 처치 · 놓침 ─────────────────────────────────────────

func on_enemy_killed(e: Enemy) -> void:
	super(e)
	if e.has_meta("stream_elite"):
		elite_alive = false
		hud.banner("ELITE DOWN", Color("ffd166"), "+%d" % (2000 * sector))
		score += 2000 * sector
		drop_pickup("missile", e.global_position, 2)
		drop_pickup("energy", e.global_position)
	_wave_member_done(e, false)


func on_enemy_escaped(e: Enemy) -> void:
	escaped += 1
	_wave_member_done(e, true)


func _wave_member_done(e: Enemy, lost: bool) -> void:
	if not e.has_meta("stream_wave"):
		return
	var id: int = e.get_meta("stream_wave")
	if not waves.has(id):
		return
	var w: Dictionary = waves[id]
	w.left -= 1
	if lost:
		w.lost += 1
	else:
		w.pos = e.global_position
	if w.left <= 0:
		waves.erase(id)
		if w.lost == 0 and state == State.PLAY:
			# 편대를 하나도 놓치지 않고 전멸시켰다
			var pts := WAVE_BONUS * sector
			score += pts
			hud.popup("PERFECT +%d" % pts, Color("7cf5ff"), w.pos + Vector3(0, 1.8, 0))
			drop_pickup("missile" if randf() < 0.55 else "energy", w.pos)


# ── 끝 · 기록 ───────────────────────────────────────────

func on_player_died() -> void:
	state = State.LOSE
	print("LOSE t=%.1f dist=%d" % [time, int(distance)])
	shake(0.8)
	Sfx.play("lose", 0.0)
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		b.queue_free()
	for b in get_tree().get_nodes_in_group("parry_orbs"):
		b.queue_free()
	schedule.clear()
	create_tween().tween_property(stage, "speed", 4.0, 2.5).set_ease(Tween.EASE_OUT)
	new_best = distance > float(best.distance)
	if new_best:
		best = {"distance": distance, "score": score, "sector": sector}
	elif score > int(best.score):
		best.score = score
	_save_best()
	var head := "NEW RECORD!" if new_best else "DESTROYED"
	hud.message(head, "비행 %s m · SECTOR %d · 격추 %d · 놓침 %d · 점수 %d · 최고 %s m · R 키로 다시 출격" % [_fmt(distance), sector, kills, escaped, score, _fmt(float(best.distance))], Color("7cf5ff") if new_best else Color("ff4a8a"))


func _load_best() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(BEST_PATH) == OK:
		best.distance = float(cfg.get_value("best", "distance", 0.0))
		best.score = int(cfg.get_value("best", "score", 0))
		best.sector = int(cfg.get_value("best", "sector", 0))


func _save_best() -> void:
	if capture_mode or not save_records:
		return     # 자동 플레이·테스트 기록은 남기지 않는다
	var cfg := ConfigFile.new()
	cfg.set_value("best", "distance", best.distance)
	cfg.set_value("best", "score", best.score)
	cfg.set_value("best", "sector", best.sector)
	cfg.save(BEST_PATH)


static func _fmt(m: float) -> String:
	var s := str(int(m))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out


# ── 정보 표시 (상단 가운데) ──────────────────────────────

func _build_info() -> void:
	info_layer = CanvasLayer.new()
	info_layer.layer = 5
	add_child(info_layer)
	# 오른쪽 위 점수 칸 바로 아래 (가운데 위는 궁극기 LOCK 표시 자리)
	info = Label.new()
	info.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	info.offset_left = -560
	info.offset_right = -18
	info.offset_top = 62
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info.add_theme_font_size_override("font_size", 19)
	info.add_theme_color_override("font_color", Color(0.85, 0.97, 1.0))
	info.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.12))
	info.add_theme_constant_override("outline_size", 7)
	info_layer.add_child(info)


func _update_info() -> void:
	if info == null:
		return
	info_layer.visible = not ui_hidden
	var b := maxf(float(best.distance), distance)
	info.text = "SECTOR %d   ·   %s m\n격추 %d   ·   BEST %s m" % [sector, _fmt(distance), kills, _fmt(b)]


# ── 자동 플레이 (검증용) ─────────────────────────────────

func bot_input(p: Player) -> Dictionary:
	var out := {"move": Vector3.ZERO, "aim": p.global_position - Vector3(0, 0, 8), "fire": false, "slash": false, "dash": false, "charge": false, "boost": true}
	if not p.alive:
		return out
	# 가장 가까운 앞쪽 적을 노린다
	var target: Node3D = null
	var best_d := INF
	var count := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null or not en.alive or not en.landed:
			continue
		count += 1
		var d := en.global_position.distance_to(p.global_position)
		if d < best_d:
			best_d = d
			target = en
	if fmod(time, 6.0) < 0.02:
		bot_side = -bot_side
	var want := Vector3(bot_side * 4.0, 0, 3.0)
	if target:
		out.aim = target.global_position + Vector3(0, 0.95, 0)
		out.fire = true
		want.x = clampf(target.global_position.x * 0.7 + bot_side * 1.5, -8.5, 8.5)
		if best_d < 3.2:
			out.slash = true
		out.ult = p.missiles > 0 and count >= 4
		if fmod(time, 9.0) > 7.6:
			out.charge = true
			out.fire = false
	var move := want - p.global_position
	move.y = 0
	move = move.limit_length(1.0) * 0.8
	bot_dash_cd -= get_physics_process_delta_time()
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		var rel := p.global_position - bl.position
		rel.y = 0
		var l := rel.length()
		if l < 2.6 and bl.vel.dot(rel) > 0:
			var side := Vector3(-bl.vel.z, 0, bl.vel.x).normalized()
			if side.dot(rel) < 0:
				side = -side
			move += side * (2.6 - l) * 1.3
			if l < 1.2 and bot_dash_cd <= 0.0 and randf() < 0.4:
				out.dash = true
				bot_dash_cd = 0.9
	out.move = move.limit_length(1.0)
	return out
