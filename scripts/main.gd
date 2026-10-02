class_name Main
extends Node3D
## 방·통로 맵 · 카메라 · 방 전투 진행 · 승패 · 타격 정지 · 화면 흔들림.

enum State { PLAY, WIN, LOSE }

## 방 난이도별 적 패턴 풀 (0 조준 3연발, 1 부채꼴, 2 원형탄)
const POOLS := [[0], [0, 0, 1], [0, 1, 1, 2], [0, 1, 2, 2]]
const MAX_ALIVE := 4
## 웨이브 방(가장 큰 방): 웨이브별 적 수 · 웨이브 사이 숨 돌릴 시간
const WAVE_SIZES := [5, 6, 7, 8, 10]
const WAVE_GAP := 2.4
## 고속 요격기(Striker) 비율. 방마다 반올림 오차를 이월해 전체 적의 20%를 맞춘다.
const STRIKER := -1
const STRIKER_RATIO := 0.2
## 고정 포탑(Turret) 비율. 요격기와 같은 방식으로 이월해 전체 적의 15%를 맞춘다.
const TURRET := -2
const TURRET_RATIO := 0.15
## 중력 크롤러(Crawler) 비율. 같은 방식으로 이월해 전체 적의 12%를 맞춘다.
const CRAWLER := -3
const CRAWLER_RATIO := 0.12
## 벌레형 괴생명체: 붉은 개미 척후병 / 아이보리 굼벵이. 기존 드론 몫 일부를 쓴다.
const INSECT_ANT := -4
const INSECT_GRUB := -5
const INSECT_ANT_RATIO := 0.12
const INSECT_GRUB_RATIO := 0.10
## 연속 처치 콤보: 이 시간 안에 다음 적을 처치하면 이어진다
const COMBO_TIME := 3.0
# 재화 드롭: 적이 죽을 때 가끔 그 자리에 떨어뜨린다 (플레이어가 직접 주워야 한다)
const DROP_MISSILE := 0.3
const DROP_ENERGY := 0.18
const BOSS_LOOT_STEP := 0.1      # 보스 체력이 이만큼 깎일 때마다 미사일 하나를 흘린다

static var inst: Main

var state := State.PLAY
var player: Player
var camera: CameraRig
var debris: Debris
var cam_preset_arg := -1
var hud: Hud
var world: Node3D
var bullets: Node3D
var map: ArenaMap
var map_seed := -1
var active_room := -1
var room_total := 0
var room_kills := 0
var rooms_cleared := 0
var spawn_queue: Array = []
## 웨이브 방 진행: 현재 웨이브 번호 (웨이브 방이 아니면 0)
var wave := 0
var spawn_timer := 0.0
var pending_spawns := 0
var striker_carry := 0.0
var turret_carry := 0.0
var crawler_carry := 0.0
var ant_carry := 0.0
var grub_carry := 0.0
## 이번 방에서 포탑 해치를 쓴 자리 (겹치지 않게)
var turret_spots: Array = []
var combo := 0
var combo_t := 0.0
var best_combo := 0
var score := 0
var slowmo := 1.0
var _cam_us := 0
var bot_lock_t := 0.0
var kills := 0
var time := 0.0
var hitstop_until := 0
var end_timer := 0.0
var env: Environment
var sun: DirectionalLight3D
var _dark_tw: Tween
var bot_path: Array[Vector3] = []
var bot_path_t := 0.0

# 검증용 자동 플레이 / 프레임 캡처
var capture_mode := false
var capture_dir := ""
var capture_every := 6
var capture_seconds := 20.0
var capture_frame := 0
var bot_dash_cd := 0.0
## 연출 확인용: 정해진 시각에 참격·폭발·피격·승리 연출을 재생
var showcase := false
## 포탑 확인용: 플레이어 옆에 포탑 둘을 세우고 피격 무시 상태로 관찰한 뒤 한 기는 베고 한 기는 쏜다
var turret_show := false
## 패링 확인용: 시작 방에 패링 탄 드론과 돌진 요격기를 세우고 자동으로 패링한다
var parry_show := false
## 크롤러 확인용: 시작 방에 크롤러를 떨어뜨리고 피격 무시 상태로 쏘며 구르기·반사·도탄·변신·공격·처치를 본다
var crawler_show := false
## 검술 콤보 확인용: 적이 내려앉기 전 허공을 베어 헛침 경직을 보인 뒤, 튼튼한 드론과 일반 드론을 연타로 잇는다
var combo_show := false
var act_show := false            # 사격·재장전·레이저·미사일 동작 확인
## 돌진 연출 확인용: 옆 대시 → 먼 적에게 긴 돌진 베기 → 다시 먼 적 → 관통 일격
var rush_show := false
## 확인 모드: 거리 벌리기 (다른 확인 모드에서는 결과가 흔들리지 않게 거리 벌리기를 끈다)
var evade_show := false
## 굴곡 확인용: 출발 방의 둔덕·오목한 자리를 차례로 걸어 지나간 뒤 출발점으로 돌아온다
var terrain_show := false
var _tshow_goals: Array[Vector3] = []
var _tshow_wait := 0.0
var _show_crawler: Crawler
var _show_room := -1
var _show_step := 0
var _show_aim := Vector3(2.2, 0.95, 0.4)


func _ready() -> void:
	inst = self
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	randomize()
	_parse_args()
	_setup_input()
	world = Node3D.new()
	add_child(world)
	FX.setup(world)
	add_child(Sfx.new())
	_build_environment()
	PaintedLook.attach(self, env, sun)
	_build_arena()
	bullets = Node3D.new()
	add_child(bullets)

	player = Player.new()
	player.bot = capture_mode
	add_child(player)
	player.global_position = map.room_center_world(map.start_room)

	camera = CameraRig.new()
	add_child(camera)
	camera.current = true
	if cam_preset_arg >= 0:
		camera.set_preset(cam_preset_arg)
	camera.snap(player.global_position)
	debris = Debris.new()
	world.add_child(debris)
	world.add_child(GunFX.new())
	world.add_child(Parry.new())
	add_child(ParryFX.new())

	hud = Hud.new()
	add_child(hud)
	var impact := ImpactFrame.new()
	impact.enabled = not OS.get_cmdline_user_args().has("--noimpact")
	add_child(impact)
	if not capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	if showcase:
		return
	FX.victory(player.global_position)
	hud.banner("EXPLORE", Color(0.7, 0.95, 1.0), "전투방 %d곳을 모두 정리하세요" % combat_rooms())


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture="):
			capture_mode = true
			capture_dir = a.substr(10)
		elif a.begins_with("--every="):
			capture_every = int(a.substr(8))
		elif a.begins_with("--seconds="):
			capture_seconds = float(a.substr(10))
		elif a == "--bot":
			capture_mode = true
		elif a.begins_with("--campreset="):
			cam_preset_arg = int(a.substr(12))
		elif a.begins_with("--seed="):
			map_seed = int(a.substr(7))
		elif a == "--showcase":
			showcase = true
		elif a == "--turretshow":
			showcase = true
			turret_show = true
		elif a == "--parryshow":
			showcase = true
			parry_show = true
		elif a == "--crawlershow":
			showcase = true
			crawler_show = true
		elif a == "--comboshow":
			showcase = true
			combo_show = true
		elif a == "--actshow":
			showcase = true
			act_show = true
		elif a == "--rushshow":
			showcase = true
			rush_show = true
		elif a == "--evadeshow":
			showcase = true
			evade_show = true
		elif a == "--terrainshow":
			showcase = true
			terrain_show = true


func _setup_input() -> void:
	var keys := {
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
		"dash": [KEY_SPACE], "boost": [KEY_SHIFT], "slash": [KEY_E, KEY_F], "restart": [KEY_R, KEY_F5], "ult": [KEY_R, KEY_Q], "reload": [KEY_T], "camera": [KEY_C], "cam_preset": [KEY_V],
		"pause": [KEY_ESCAPE], "mute": [KEY_M], "impact": [KEY_I], "toon": [KEY_O], "lens": [KEY_L],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	# 마우스: 좌클릭 검 · 우클릭 사격 · 좌우 동시 유지 충전 (동시 판정은 Player 가 한다)
	var mouse := {"slash_mouse": MOUSE_BUTTON_LEFT, "fire_mouse": MOUSE_BUTTON_RIGHT}
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mb := InputEventMouseButton.new()
		mb.button_index = mouse[action]
		InputMap.action_add_event(action, mb)


# ── 월드 구성 ───────────────────────────────────────────

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.85)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 28, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.97, 1.0)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)


func _build_arena() -> void:
	map = ArenaMap.new()
	world.add_child(map)
	# 방 탐색 아레나는 바닥에 완만한 굴곡이 있다. --flat 이면 예전처럼 평지.
	map.terrain = not OS.get_cmdline_user_args().has("--flat")
	map.generate(map_seed if map_seed >= 0 else randi())
	map.build()


# ── 판정 보조 ───────────────────────────────────────────

func is_blocked(p: Vector3) -> bool:
	return map.is_blocked(p)


func push_out(p: Vector3, radius: float) -> Vector3:
	return map.push_out(p, radius)


## 지면 높이 (지형이 없는 장면은 0)
func floor_at(p: Vector3) -> float:
	return map.height_at(p) if map else 0.0


## 어느 장면에서든 쓰는 지면 높이 조회 (이펙트·파편이 바닥에 붙을 때)
static func gy(p: Vector3) -> float:
	return inst.floor_at(p) if is_instance_valid(inst) else 0.0


## 플레이어용: 높이는 그대로 두고 feet 보다 climb 넘게 높은 지형을 벽처럼 밀어낸다
func push_out_feet(p: Vector3, radius: float, feet: float, climb: float) -> Vector3:
	return map.push_out_feet(p, radius, feet, climb) if map and map.terrain else p


func add_bullet(b: Bullet) -> void:
	if not b.from_player:
		b.add_to_group("enemy_bullets")
	bullets.add_child(b)


func mouse_ground(h: float) -> Vector3:
	return screen_ground(get_viewport().get_mouse_position(), h)


## 보이는 화면 좌표 sp 를 지나는 시선이 높이 h 평면과 만나는 점
func screen_ground(sp: Vector2, h: float) -> Vector3:
	var mp := camera.render_pos(sp)
	var o := camera.project_ray_origin(mp)
	var d := camera.project_ray_normal(mp)
	if abs(d.y) < 0.0001:
		return player.global_position
	var t := (h - o.y) / d.y
	return o + d * t


func combat_rooms() -> int:
	return ArenaMap.COMBAT_ROOMS if map.rooms.size() > ArenaMap.COMBAT_ROOMS else map.rooms.size() - 1


## 현재 전투방에 남은 적 수
func enemies_left() -> int:
	return room_total - room_kills if active_room >= 0 else 0


# ── 방 진행 ─────────────────────────────────────────────

func _activate_room(id: int) -> void:
	var r: Dictionary = map.rooms[id]
	r.state = "active"
	r.visited = true
	active_room = id
	map.close_gates(id)
	print("ROOM_ENTER id=%d shape=%d scale=%.1f wave=%s t=%.1f" % [id, r.shape, r.scale, r.wave, time])
	var d: int = clampi(r.difficulty, 1, 6)
	turret_spots.clear()
	shake(0.25)
	Sfx.play("spawn", 0.0, 0.0)
	if r.wave:
		wave = 1
		_fill_queue(WAVE_SIZES[0], d)
		spawn_timer = 0.6
		hud.banner("WAVE 1 / %d" % ArenaMap.WAVES, Color("ff7a9a"), "대형 %s · 웨이브 %d번을 모두 버티세요 · 적 %d기" % [ArenaMap.SHAPE_NAMES[r.shape], ArenaMap.WAVES, room_total])
		return
	wave = 0
	# 넓은 방은 크기만큼 적이 더 나온다 (2배 방 ×1.5, 3배 방 ×2)
	_fill_queue(roundi(clampi(3 + d, 4, 9) * (1.0 + (r.scale - 1.0) * 0.5)), d)
	spawn_timer = 0.6
	var title: String = ArenaMap.SHAPE_NAMES[r.shape] if r.scale <= 1.0 else "대형 " + ArenaMap.SHAPE_NAMES[r.shape]
	hud.banner(title, Color("ff7a9a"), "차단막이 닫혔습니다 · 적 %d기" % room_total)


## 적 count 기를 소환 대기열에 채운다 (요격기·포탑·크롤러 비율은 방마다 이월해 맞춘다)
func _fill_queue(count: int, d: int) -> void:
	room_total = count
	room_kills = 0
	spawn_queue.clear()
	var pool: Array = POOLS[mini(d - 1, POOLS.size() - 1)]
	striker_carry += room_total * STRIKER_RATIO
	var strikers := mini(int(striker_carry + 0.001), room_total)
	striker_carry -= strikers
	turret_carry += room_total * TURRET_RATIO
	var turrets := mini(int(turret_carry + 0.001), room_total - strikers)
	turret_carry -= turrets
	crawler_carry += room_total * CRAWLER_RATIO
	var crawlers := mini(int(crawler_carry + 0.001), room_total - strikers - turrets)
	crawler_carry -= crawlers
	ant_carry += room_total * INSECT_ANT_RATIO
	var ants := mini(int(ant_carry + 0.001), room_total - strikers - turrets - crawlers)
	ant_carry -= ants
	grub_carry += room_total * INSECT_GRUB_RATIO
	var grubs := mini(int(grub_carry + 0.001), room_total - strikers - turrets - crawlers - ants)
	grub_carry -= grubs
	for i in room_total:
		if i < strikers:
			spawn_queue.append(STRIKER)
		elif i < strikers + turrets:
			spawn_queue.append(TURRET)
		elif i < strikers + turrets + crawlers:
			spawn_queue.append(CRAWLER)
		elif i < strikers + turrets + crawlers + ants:
			spawn_queue.append(INSECT_ANT)
		elif i < strikers + turrets + crawlers + ants + grubs:
			spawn_queue.append(INSECT_GRUB)
		else:
			spawn_queue.append(pool[randi() % pool.size()])
	spawn_queue.shuffle()


## 웨이브 방: 한 웨이브를 정리하면 잠깐 쉬었다가 다음 웨이브가 몰려온다 (웨이브마다 난이도 +1)
func _next_wave() -> void:
	wave += 1
	var r: Dictionary = map.rooms[active_room]
	var d: int = clampi(r.difficulty + wave - 1, 1, 6)
	_fill_queue(WAVE_SIZES[mini(wave - 1, WAVE_SIZES.size() - 1)], d)
	spawn_timer = WAVE_GAP
	print("WAVE %d/%d t=%.1f hp=%d" % [wave, ArenaMap.WAVES, time, player.hp])
	Sfx.play("charged", 0.0, 0.0)
	FX.shockwave(player.global_position, Color("ff7a9a"), 4.0, 0.5)
	var last := wave == ArenaMap.WAVES
	hud.banner("FINAL WAVE" if last else "WAVE %d / %d" % [wave, ArenaMap.WAVES], Color("ff5a7a") if last else Color("ff9ab0"), "웨이브 정리 · 다음 적 %d기" % room_total)


## 한 방에서 동시에 살아 있을 수 있는 적 수: 넓은 방일수록 많다
func max_alive() -> int:
	if active_room < 0:
		return MAX_ALIVE
	var r: Dictionary = map.rooms[active_room]
	return MAX_ALIVE + roundi((r.scale - 1.0) * 1.5) + (1 if r.wave else 0)


func _clear_room() -> void:
	var id := active_room
	map.rooms[id].state = "cleared"
	map.open_gates(id)
	active_room = -1
	wave = 0
	rooms_cleared += 1
	print("ROOM_CLEAR %d/%d t=%.1f hp=%d id=%d" % [rooms_cleared, combat_rooms(), time, player.hp, get_instance_id()])
	if player.hp < Player.MAX_HP:
		player.hp += 1
	if rooms_cleared >= combat_rooms():
		_win()
	else:
		Sfx.play("charged", 0.0, 0.0)
		FX.shockwave(player.global_position, Pal.CYAN, 4.0, 0.5)
		hud.banner("ROOM CLEAR", Color(0.6, 0.95, 1.0), "%d / %d  ·  차단막 해제 · 체력 +1" % [rooms_cleared, combat_rooms()])


func _spawn_show(p: Vector3, off: Vector3, hp := 3) -> Enemy:
	var e := Enemy.new()
	e.pattern = Enemy.Pattern.AIMED_BURST
	e.hp = hp
	world.add_child(e)
	e.global_position = map.push_out(p + off, 1.0)
	e.desired = 2.2
	return e


func _run_turret_show() -> void:
	if _show_step == 1 and time >= 5.5:
		# 광선검 절단 연출 확인: 첫 포탑을 벤 것으로 처리한다
		_show_step = 2
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy
			en.slash_yaw = randf() * TAU
			en.take_hit(999, en.global_position - player.global_position, en.global_position, "slash")
			break
	if _show_step > 0 or time < 0.2:
		return
	_show_step = 1
	player.invuln = 999.0
	# 시작 방의 벽가·구석 해치에서 둘을 올린다. 첫 해치 앞으로 플레이어를 옮겨 화면에 담는다.
	turret_spots.clear()
	var first := _spawn_turret(map.start_room, 2.5)
	var fwd := Vector3(-sin(first.face_yaw), 0, -cos(first.face_yaw))
	player.global_position = map.push_out(first.global_position + fwd * 4.5, 0.5)
	camera.snap(player.global_position)
	_spawn_turret(map.start_room, 2.5)


func _run_crawler_show() -> void:
	if _show_step == 0 and time >= 0.2:
		_show_step = 1
		player.invuln = 999.0
		# 가장 가까운 전투방으로 옮기고 출입구를 닫는다 (실제 전투처럼 구체가 통로로 빠져나가지 않게)
		_show_room = map.start_room
		var bd := 1e9
		for r in map.rooms:
			var d: float = map.room_center_world(r.id).distance_to(player.global_position)
			if r.combat and d < bd:
				bd = d
				_show_room = r.id
		map.rooms[_show_room].state = "active"
		map.close_gates(_show_room)
		player.global_position = map.room_center_world(_show_room)
		camera.snap(player.global_position)
		var e := Crawler.new()
		world.add_child(e)
		e.global_position = map.random_spot(_show_room, player.global_position, 5.0)
		e.hp = 9999
		_show_crawler = e
	elif _show_step == 1 and time >= 13.0 and is_instance_valid(_show_crawler):
		# 충분히 본 뒤에는 약점 상태에서 처치되도록 체력을 낮춘다
		_show_step = 2
		_show_crawler.hp = 6
		print("CRAWLER %.3f HP_LOW" % time)


func _run_combo_show() -> void:
	if _show_step == 0 and time >= 0.2:
		_show_step = 1
		player.invuln = 999.0
		var p := player.global_position
		var tank := _spawn_show(p, Vector3(0.3, 0, -3.4), 40)
		tank.desired = 1.6
		_spawn_show(p, Vector3(3.6, 0, -5.0), 3)
		_spawn_show(p, Vector3(-3.8, 0, -4.2), 3)
		_show_aim = p + Vector3(5.0, 0.95, 1.5)


func _run_act_show() -> void:
	if _show_step == 0 and time >= 0.2:
		_show_step = 1
		player.invuln = 999.0
		var p := player.global_position
		# 왼쪽(화면 왼편)을 겨눠 사격 팔(왼팔)이 카메라 쪽을 보게 한다
		var e := _spawn_show(p, Vector3(-6.5, 0, 0.8), 999)
		e.desired = 6.5
		_spawn_show(p, Vector3(-5.5, 0, -2.5), 999).desired = 6.5
		_show_aim = e.global_position + Vector3(0, 0.95, 0)
	elif _show_step == 1 and time >= 5.6:
		_show_step = 2
		player.energy = Player.ENERGY_MAX
		player.missiles = Player.MISSILE_MAX


## 드론 둘 · 요격기 · 크롤러를 띄우고, 봇이 가까운 적에게 붙어 광선검을 연타한다
func _run_evade_show() -> void:
	if _show_step == 0 and time >= 0.2:
		_show_step = 1
		player.invuln = 999.0
		# 가까운 전투방에 가두고 싸운다 (구체 크롤러가 통로로 빠져나가지 않게)
		_show_room = map.start_room
		var bd := 1e9
		for r in map.rooms:
			var d: float = map.room_center_world(r.id).distance_to(player.global_position)
			if r.combat and d < bd:
				bd = d
				_show_room = r.id
		map.rooms[_show_room].state = "active"
		map.close_gates(_show_room)
		player.global_position = map.room_center_world(_show_room)
		camera.snap(player.global_position)
		var p := player.global_position
		var foes: Array[Enemy] = []
		for i in 2:
			var e := Enemy.new()
			e.pattern = Enemy.Pattern.AIMED_BURST
			foes.append(e)
		foes.append(Striker.new())
		foes.append(Crawler.new())
		for e in foes:
			world.add_child(e)
			e.global_position = map.random_spot(_show_room, p, 3.5)
			e.hp = 9999


func _run_rush_show() -> void:
	# 방 가운데 기준으로 세운다 (대시로 벽가에 붙어도 적이 방 밖으로 밀려나지 않게)
	var p := map.room_center_world(map.start_room)
	var steps := [0.2, 1.6, 2.6, 3.7]
	if _show_step >= steps.size() or time < steps[_show_step]:
		return
	match _show_step:
		0:
			player.invuln = 999.0
			_show_aim = p + Vector3(-3.0, 0.95, 0.5)
		1:
			player.global_position = p + Vector3(-2.5, 0, 1.0)
			camera.snap(player.global_position)
			_show_aim = _spawn_show(p, Vector3(3.5, 0, -1.5), 40).global_position + Vector3(0, 0.95, 0)
		2:
			_show_aim = _spawn_show(p, Vector3(-3.5, 0, 1.5), 40).global_position + Vector3(0, 0.95, 0)
		3:
			_show_aim = _spawn_show(p, Vector3(2.5, 0, 3.5), 40).global_position + Vector3(0, 0.95, 0)
			player._arm_phantom()
	_show_step += 1


func _run_parry_show() -> void:
	if _show_step == 0 and time >= 0.2:
		_show_step = 1
		player.invuln = 0.0
		player.hp = 999
		var p := player.global_position
		var e := _spawn_show(p, Vector3(1.5, 0, -6.5), 999)
		e.orb_only = true
		e.orb_cd = 0.0
		e.desired = 6.5
	elif _show_step == 1 and time >= 5.5:
		_show_step = 2
		var s := Striker.new()
		s.lunge_only = true
		s.lunge_cd = 1.2
		world.add_child(s)
		s.global_position = map.push_out(player.global_position + Vector3(-4.5, 0, -2.5), 1.0)
		s.hp = 999


func _run_showcase() -> void:
	if terrain_show:
		if _tshow_goals.is_empty() and _show_step == 0:
			_show_step = 1
			player.invuln = 999.0
			_tshow_goals = _terrain_goals()
		if fmod(time, 0.25) < get_physics_process_delta_time():
			print("TSHOW t=%.2f pos=(%.1f,%.2f,%.1f) gy=%.2f air=%s goals=%d" % [time, player.global_position.x, player.global_position.y, player.global_position.z, player.gy, player.airborne, _tshow_goals.size()])
		return
	if parry_show:
		_run_parry_show()
		return
	if turret_show:
		_run_turret_show()
		return
	if crawler_show:
		_run_crawler_show()
		return
	if combo_show:
		_run_combo_show()
		return
	if act_show:
		_run_act_show()
		return
	if rush_show:
		_run_rush_show()
		return
	if evade_show:
		_run_evade_show()
		return
	var p := player.global_position
	var steps := [0.2, 3.6, 4.2, 5.2]
	if _show_step >= steps.size() or time < steps[_show_step]:
		return
	match _show_step:
		0:
			player.invuln = 999.0
			for i in 4:
				var a := deg_to_rad(-60.0 + i * 40.0)
				_spawn_show(p, Vector3(sin(a), 0, -cos(a)) * 6.5)
			_show_aim = p + Vector3(0, 0.95, -6.0)
		1:
			var e := _spawn_show(p, Vector3(2.8, 0, -2.4))
			_show_aim = e.global_position + Vector3(0, 0.95, 0)
		2:
			var e := _spawn_show(p, Vector3(-3.0, 0, -1.2))
			_show_aim = e.global_position + Vector3(0, 0.95, 0)
		3:
			for i in 7:
				var a := TAU * i / 7.0
				_spawn_show(p, Vector3(cos(a), 0, sin(a)) * randf_range(4.5, 7.0), 4)
			player.missiles = Player.MISSILE_MAX
	_show_step += 1


func _physics_process(dt: float) -> void:
	time += dt
	if combo > 0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 0
	if showcase:
		_run_showcase()
	map.update_discovery(player.global_position, dt)
	if state == State.PLAY and active_room < 0 and not showcase and player.alive:
		var rid := map.room_at(player.global_position)
		if rid >= 0 and map.rooms[rid].combat and map.rooms[rid].state == "idle":
			# 출입구에서 한 칸 이상 안쪽으로 들어왔을 때 닫는다
			var inside := true
			for door in map.rooms[rid].doors:
				if map.world_of(door[0]).distance_to(player.global_position) < 1.8:
					inside = false
					break
			if inside:
				_activate_room(rid)
		elif rid >= 0:
			map.rooms[rid].visited = true
	if state == State.PLAY and active_room >= 0 and spawn_queue.size() > 0:
		spawn_timer -= dt
		var alive := get_tree().get_nodes_in_group("enemies").size() + pending_spawns
		if spawn_timer <= 0.0 and alive < max_alive():
			spawn_timer = 0.5
			_spawn(spawn_queue.pop_front())


func _spawn(pattern: int) -> void:
	if pattern == TURRET:
		_spawn_turret(active_room, 6.0)
		return
	# 넓은 방에서는 플레이어 둘레 16m 안에 나온다 (화면 밖 먼 구석에서 나오지 않게)
	var far := INF if map.rooms[active_room].scale <= 1.0 else 16.0
	var pos := map.random_spot(active_room, player.global_position, 5.5, far)
	pending_spawns += 1
	FX.spawn_marker(pos, 0.7)
	Sfx.play("spawn", 0.1, -6.0)
	get_tree().create_timer(0.7, false).timeout.connect(func():
		pending_spawns -= 1
		if state == State.LOSE:
			return
		var e: Enemy
		match pattern:
			STRIKER: e = Striker.new()
			CRAWLER: e = Crawler.new()
			INSECT_ANT: e = InsectEnemy.new()
			INSECT_GRUB:
				e = InsectEnemy.new()
				(e as InsectEnemy).kind = InsectEnemy.Kind.GRUB
			_: e = Enemy.new()
		if pattern >= 0:
			e.pattern = pattern
		world.add_child(e)
		e.global_position = pos)


## 포탑은 벽가·구석의 바닥 해치에서 솟아오른다 (해치 연출이 예고를 대신하므로 소환 표식은 쓰지 않는다)
func _spawn_turret(room: int, min_dist: float) -> Turret:
	var spot := map.wall_spot(room, player.global_position, min_dist, turret_spots)
	if spot.is_empty():
		spot = {"pos": map.random_spot(room, player.global_position, 7.5), "yaw": randf() * TAU}
	turret_spots.append(spot.pos)
	var e := Turret.new()
	e.face_yaw = spot.yaw
	world.add_child(e)
	e.global_position = spot.pos
	return e


func on_enemy_killed(_e: Enemy) -> void:
	kills += 1
	# 콤보 점수: 콤보가 길수록, 검·관통 일격으로 벨수록 크게 오른다
	combo += 1
	combo_t = COMBO_TIME
	best_combo = maxi(best_combo, combo)
	var mult := {"slash": 2, "phantom": 3, "parry": 3}.get(_e.kill_source, 1) as int
	var pts := 100 * combo * mult
	score += pts
	hud.combo_pop(pts, _e.kill_source)
	_drop_loot(_e)
	if is_instance_valid(player):
		player.gain_boost()
	hitstop(0.07)
	shake(0.35)
	camera.kill_punch(_e.global_position)
	if active_room >= 0 and state == State.PLAY:
		room_kills += 1
		if room_kills >= room_total:
			if wave > 0 and wave < ArenaMap.WAVES:
				_next_wave()
			else:
				_clear_room()


func _drop_loot(e: Enemy) -> void:
	var pos := e.global_position
	if randf() < DROP_MISSILE:
		drop_pickup("missile", pos)
	if randf() < DROP_ENERGY:
		drop_pickup("energy", pos)


func drop_pickup(kind: String, pos: Vector3, amount := 1) -> Pickup:
	var pk := Pickup.new()
	pk.kind = kind
	pk.amount = amount
	pos.y = maxf(pos.y, gy(pos)) + 0.8
	pk.position = pos
	world.add_child(pk)
	return pk


var _boss_loot_given := 0
## 보스전은 잡몹이 없으므로, 보스 체력이 BOSS_LOOT_STEP 깎일 때마다 보스 앞에 미사일을 흘린다
func boss_loot(boss_node: Enemy, hp_frac: float) -> void:
	var due := int((1.0 - hp_frac) / BOSS_LOOT_STEP)
	while _boss_loot_given < due:
		_boss_loot_given += 1
		var pos := boss_node.global_position.lerp(player.global_position, 0.55)
		if is_blocked(pos):
			pos = player.global_position
		drop_pickup("missile", pos)
		if _boss_loot_given % 2 == 0:
			drop_pickup("energy", pos)


var _p2_at := -1.0
## 검증용 `--fastkill=초`: 2페이즈에 들어가고 이 초가 지나면 보스 체력을 한 방 남기고 깎는다 (격파 쇼타임 확인용)
func _fast_kill(boss_node: Node, in_p2: bool) -> void:
	if boss_node == null or not in_p2:
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fastkill="):
			if _p2_at < 0.0:
				_p2_at = time
			if time - _p2_at >= float(a.substr(11)):
				boss_node.set("boss_hp", minf(float(boss_node.get("boss_hp")), 2.0))


func on_player_hurt() -> void:
	hud.hurt_flash()
	if combo > 1:
		hud.combo_break()
	combo = 0


func on_player_died() -> void:
	state = State.LOSE
	print("LOSE t=%.1f" % time)
	shake(0.8)
	Sfx.play("lose", 0.0)
	hud.message("DESTROYED", "R 키로 다시 시작", Color("ff4a8a"))
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		b.queue_free()
	for b in get_tree().get_nodes_in_group("parry_orbs"):
		b.queue_free()


func _win() -> void:
	state = State.WIN
	print("WIN t=%.1f" % time)
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		FX.flash(b.position, Pal.E_BULLETS[2], 0.4, 0.1)
		b.queue_free()
	for b in get_tree().get_nodes_in_group("parry_orbs"):
		b.queue_free()
	FX.victory(player.global_position)
	player.celebrate()
	Sfx.play("win", 0.0)
	hud.message("ALL ROOMS CLEAR", "방 %d곳 · 적 %d기 격파 · %.1f초 · 점수 %d · 최대 %d 콤보 · R 키로 다시 시작" % [rooms_cleared, kills, time, score, best_combo], Color("7cf5ff"))


func _unhandled_input(event: InputEvent) -> void:
	# R: 전투 중에는 궁극기, 결과 화면에서는 재시작 (F5 는 언제나 재시작)
	var restart_now := event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F5 and event.is_pressed()
	if restart_now or (event.is_action_pressed("restart") and state != State.PLAY):
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()
	elif event.is_action_pressed("pause"):
		# Esc: 로비로 (섹터 런 중이면 런은 중단된다)
		Lobby.back(get_tree())
	elif event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).physical_keycode == KEY_B:
		# B: 방 탐색 → 추격 보스전 → 용광로 보스전 → 방 탐색 순환
		Engine.time_scale = 1.0
		Engine.physics_ticks_per_second = 60
		var scenes := ["res://scenes/main.tscn", "res://scenes/boss.tscn", "res://scenes/forge.tscn"]
		get_tree().change_scene_to_file(scenes[(scenes.find(scene_file_path) + 1) % scenes.size()])
	elif event.is_action_pressed("camera"):
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL if camera.projection == Camera3D.PROJECTION_PERSPECTIVE else Camera3D.PROJECTION_PERSPECTIVE
	elif event.is_action_pressed("cam_preset"):
		camera.set_preset(camera.preset_index + 1)
		hud.banner("CAMERA  %s" % camera.p.name, Color(0.8, 0.9, 1.0), camera.p.desc)
	elif event.is_action_pressed("lens") and camera.has_method("cycle_lens"):
		var lv: Array = camera.call("cycle_lens")
		hud.banner("LENS  %s" % lv[0], Color(0.8, 0.9, 1.0), lv[1])
	elif event.is_action_pressed("mute"):
		Sfx.inst.muted = not Sfx.inst.muted
	elif event.is_action_pressed("impact"):
		ImpactFrame.inst.enabled = not ImpactFrame.inst.enabled
		hud.banner("IMPACT FRAME  %s" % ("ON" if ImpactFrame.inst.enabled else "OFF"), Color(1, 1, 1), "강한 레이저 발사 순간의 흑백 프레임")
	elif event.is_action_pressed("toon"):
		Pal.set_toon(not Pal.toon_on)
		hud.banner("CARTOON  %s" % ("ON" if Pal.toon_on else "OFF"), Color(1, 1, 1), "셀 음영 + 외곽선")
	elif event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).physical_keycode == KEY_K:
		# K: 하스스톤 식 핸드 페인팅 질감 켜기/끄기 (PaintedLook)
		hud.banner("PAINTED  %s" % PaintedLook.toggle(), Color(1, 0.9, 0.7), "하스스톤 식 핸드 페인팅 질감")


# ── 카메라 · 타격감 ─────────────────────────────────────

func shake(amount: float) -> void:
	camera.shake(amount)


## 카메라를 한 방향으로 밀었다가 스프링으로 복귀 (레이저 반동 등)
func kick(v: Vector3) -> void:
	camera.kick(v)


## 최대 레이저 연출: 주변을 급격히 어둡게 해 빔 광원을 돋보이게 한다
func dramatic(on: bool) -> void:
	if _dark_tw:
		_dark_tw.kill()
	_dark_tw = create_tween().set_parallel(true)
	var d := 0.1 if on else 0.6
	_dark_tw.tween_property(sun, "light_energy", 0.08 if on else 1.25, d)
	_dark_tw.tween_property(env, "ambient_light_energy", 0.05 if on else 0.5, d)
	_dark_tw.tween_property(env, "background_color", Color(0.0, 0.0, 0.01) if on else Color(0.02, 0.02, 0.05), d)
	_dark_tw.tween_property(env, "glow_intensity", 1.1 if on else 0.5, d)
	_dark_tw.tween_property(env, "glow_hdr_threshold", 0.85 if on else 1.1, d)
	if on:
		# 임팩트 프레임이 재생 중이면 끝난 뒤 섬광을 낸다 (흑백 대비를 덮지 않게)
		ImpactFrame.inst.after(hud.screen_flash.bind(Color(0.85, 1.0, 1.0), 0.55))


func hitstop(sec: float) -> void:
	Engine.time_scale = minf(0.06, slowmo * 0.5)
	hitstop_until = max(hitstop_until, Time.get_ticks_msec() + int(sec * 1000.0))


## 기본 시간 배율 (궁극기 락온 중 슬로우모션). 물리 틱을 함께 올려 느린 화면에서도 움직임이 끊기지 않게 한다.
func set_slowmo(s: float) -> void:
	slowmo = s
	Engine.physics_ticks_per_second = int(round(60.0 / s))
	if Time.get_ticks_msec() >= hitstop_until:
		Engine.time_scale = s


func _process(dt: float) -> void:
	# dt 는 time_scale 이 반영된 게임 시간. 히트스탑 동안 카메라도 함께 멈춰야 튀지 않는다.
	_update_camera(dt)
	if Engine.time_scale != slowmo and Time.get_ticks_msec() >= hitstop_until:
		Engine.time_scale = slowmo
	if capture_mode:
		_capture()


func _update_camera(dt: float) -> void:
	if camera == null:
		return
	if OS.get_cmdline_user_args().has("--overview"):
		# 검증용: 맵 전체를 위에서 비스듬히 내려다본다
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 118.0
		camera.global_position = Vector3(0, 90, 55)
		camera.look_at(Vector3.ZERO, Vector3.UP)
		return
	# 락온 중에는 실제 시간으로 움직인다. 시간 배율이 바뀐 바로 그 프레임에 (프레임 시간 ÷ 배율)로 재면
	# 수백 ms 가 한 번에 들어가 줌이 순간이동하므로 실제 시계로 잰다.
	var now := Time.get_ticks_usec()
	var real_dt := clampf((now - _cam_us) / 1000000.0, 0.0, 0.05)
	_cam_us = now
	if player.ult_busy():
		dt = real_dt
	camera.update(dt, player)


func _capture() -> void:
	capture_frame += 1
	if OS.get_cmdline_user_args().has("--camlog"):
		print("CAM %.4f %.4f %.4f %.3f" % [camera.global_position.x, camera.global_position.y, camera.global_position.z, Engine.time_scale])
	if capture_dir != "" and capture_frame % capture_every == 0 and time > 0.3:
		if crawler_show and is_instance_valid(_show_crawler):
			var sp := camera.unproject_position(_show_crawler.global_position + Vector3(0, 0.8, 0))
			print("CPOS %d %.0f %.0f %.3f" % [capture_frame / capture_every, sp.x, sp.y, time])
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/f_%04d.png" % [capture_dir, capture_frame / capture_every])
	if time > capture_seconds:
		get_tree().quit()


## 출발 방의 굴곡 견학 순서: 둔덕·오목한 자리 가운데를 차례로 · 출발점
func _terrain_goals() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var home := map.room_center_world(map.start_room)
	for f in map.feats:
		if f.k == "mound" and map.room_at(Vector3(f.c.x, 0, f.c.y)) == map.start_room:
			out.append(Vector3(f.c.x, f.h, f.c.y))
	out.append(home)
	return out


## 굴곡 견학 봇: 경로를 따라 걸어 굴곡을 지나간다
func _terrain_bot(p: Player, out: Dictionary) -> Dictionary:
	if _tshow_goals.is_empty():
		return out
	var goal: Vector3 = _tshow_goals[0]
	var flat := Vector2(goal.x - p.global_position.x, goal.z - p.global_position.z)
	if flat.length() < 0.7:
		_tshow_wait += get_physics_process_delta_time()
		if _tshow_wait > 0.8:
			_tshow_wait = 0.0
			_tshow_goals.pop_front()
			bot_path.clear()
		return out
	bot_path_t -= get_physics_process_delta_time()
	if bot_path.is_empty() or bot_path_t <= 0.0:
		bot_path_t = 0.5
		bot_path = map.find_path(p.global_position, goal)
	while bot_path.size() > 1 and Vector2(bot_path[0].x - p.global_position.x, bot_path[0].z - p.global_position.z).length() < 0.6:
		bot_path.pop_front()
	if bot_path.is_empty():
		return out
	var wp: Vector3 = bot_path[0]
	var d := Vector3(wp.x - p.global_position.x, 0, wp.z - p.global_position.z)
	out.move = d.normalized()
	out.aim = p.global_position + d.normalized() * 4.0 + Vector3(0, 0.95, 0)
	return out


## 자동 플레이: 가까운 적 주위를 돌며 사격, 가까운 적탄은 회피
func bot_input(p: Player) -> Dictionary:
	var out := {"move": Vector3.ZERO, "aim": p.global_position - Vector3(0, 0, 3), "fire": false, "slash": false, "dash": false, "charge": false, "boost": false, "jump": false}
	if terrain_show:
		return _terrain_bot(p, out)
	if turret_show:
		# 천천히 원을 그리며 포탑이 따라오는지 보고, 5.5초에 한 기를 베어 절단 연출을 본 뒤 남은 포탑을 쏜다
		var a := time * 0.5
		out.move = Vector3(cos(a), 0, sin(a)) * 0.12 if time < 5.5 else Vector3.ZERO
		for e in get_tree().get_nodes_in_group("enemies"):
			out.aim = (e as Node3D).global_position + Vector3(0, 0.95, 0)
			break
		out.fire = time > 6.6
		return out
	if parry_show:
		# 제자리에서 가까운 적을 조준하고, 패링 창이 열리면 대시를 누른다
		var bd2 := 1e9
		for e in get_tree().get_nodes_in_group("enemies"):
			var dd := (e as Node3D).global_position.distance_to(p.global_position)
			if dd < bd2:
				bd2 = dd
				out.aim = (e as Node3D).global_position + Vector3(0, 0.95, 0)
		var th := Parry.inst.best_threat()
		out.dash = th != null and th.parry_eta() < Parry.EARLY * 0.5
		return out
	if rush_show:
		out.aim = _show_aim
		var tt := time
		if tt > 1.1 and tt < 1.12:
			out.move = Vector3(1, 0, 0.2)
			out.dash = true
		out.slash = (tt > 2.3 and tt < 2.317) or (tt > 3.3 and tt < 3.317) or (tt > 4.3 and tt < 4.317)
		return out
	if evade_show:
		# 가장 가까운 적에게 다가가 붙으면 0.15초마다 검을 휘두른다
		var bd4 := 1e9
		var tgt: Enemy = null
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy
			var dd := en.global_position.distance_to(p.global_position)
			if en.landed and dd < bd4:
				bd4 = dd
				tgt = en
		if tgt:
			out.aim = tgt.global_position + Vector3(0, 0.95, 0)
			var to := tgt.global_position - p.global_position
			to.y = 0
			out.move = to.normalized() if bd4 > 2.2 else Vector3.ZERO
			out.slash = bd4 < 3.2 and fmod(time, 0.15) < 0.017
		return out
	if act_show:
		# 연사 30발 → 자동 재장전 → 3단 레이저 → 지속 레이저 → 미사일 일제 사격
		out.aim = _show_aim
		var ta := time
		out.fire = ta > 0.3 and ta < 3.4
		out.charge = (ta > 4.6 and ta < 5.35) or (ta > 5.9 and ta < 7.0)
		out.ult = ta > 9.4 and ta < 9.45
		return out
	if combo_show:
		# 0.5초: 적이 아직 내려앉기 전 허공을 벤다 (헛침 → 경직 중 연타는 무시된다)
		# 1.3초~: 가까운 적을 조준하고 0.1초마다 연타 → 적중할 때마다 다음 단으로 이어진다
		# 3.9초~4.5초: 손을 떼 링크가 끊기는 것을 보이고(4초에 대시) 다시 연타
		out.aim = _show_aim
		var tt := time
		# 대시 확인: 시작 직후 옆으로 한 번, 링크를 끊은 사이에 한 번
		if (tt > 0.25 and tt < 0.27) or (tt > 4.0 and tt < 4.02):
			out.move = Vector3(-1, 0, 0.3) if tt < 1.0 else Vector3(1, 0, -0.2)
			out.dash = true
		if tt < 1.2:
			out.slash = (tt > 0.5 and tt < 0.52) or (fmod(tt, 0.1) < 0.017 and tt > 0.6 and tt < 0.95)
			return out
		var bd3 := 1e9
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy
			if not en.landed:
				continue
			var dd := en.global_position.distance_to(p.global_position)
			if dd < bd3:
				bd3 = dd
				out.aim = en.global_position + Vector3(0, 0.95, 0)
		out.slash = fmod(tt, 0.1) < 0.017 and not (tt > 3.9 and tt < 4.5)
		return out
	if crawler_show:
		# 크롤러와 6m 안팎을 유지하며 옆으로 돌고 계속 쏜다: 구체일 때는 도탄, 거미일 때는 약점 피격
		if is_instance_valid(_show_crawler) and _show_crawler.alive:
			# 방 가운데를 지키며 조준만 따라간다 (벽에 막히지 않게)
			var home := map.room_center_world(_show_room) - p.global_position
			home.y = 0
			out.move = (home * 0.5).limit_length(1.0) if home.length() > 0.4 else Vector3.ZERO
			out.aim = _show_crawler.global_position + Vector3(0, 0.95, 0)
			out.fire = _show_crawler.landed
		return out
	if showcase:
		# 연출 확인 순서: 충전하며 대시 → 최대 레이저로 빠르게 쓸기 → 돌진 베기 ×2 → 미사일 궁극기
		out.aim = _show_aim
		out.charge = time > 0.3 and time < 1.45
		if time > 0.75 and time < 0.8:
			out.move = Vector3(1, 0, 0.2)
			out.dash = true
		if time > 1.5 and time < 3.5:
			var a := sin((time - 1.5) * 4.0) * deg_to_rad(75.0)
			out.aim = p.global_position + Vector3(sin(a), 0, -cos(a)) * 6.0
		if (time > 4.2 and time < 4.24) or (time > 4.8 and time < 4.84) or (time > 5.3 and time < 5.34) or (time > 5.6 and time < 5.64):
			out.slash = true
		if time > 5.9 and time < 5.95:
			out.ult = true
		return out
	var best: Enemy = null
	var bd := 1e9
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.landed:
			continue
		var d := en.global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = en
	var move := Vector3.ZERO
	if best:
		out.aim = best.global_position + Vector3(0, 0.95, 0)
		out.fire = true
		var to := best.global_position - p.global_position
		to.y = 0
		var n := to.normalized()
		move += Vector3(-n.z, 0, n.x) * (1.0 if sin(time * 0.4) > 0 else -1.0)
		if bd > 7.0:
			move += n * 0.8
		elif bd < 4.5:
			move -= n * 0.8
		out.slash = bd < 2.8 and fmod(time, 1.0) < 0.05
		# 주기적으로 레이저 충전 → 발사, 멀면 부스터로 접근
		var cyc := fmod(time, 5.0)
		if cyc > 3.6:
			out.charge = true
			out.fire = false
		out.boost = bd > 8.5 and p.boost > 0.4
		out.ult = get_tree().get_nodes_in_group("enemies").size() >= 3
		# 관통 일격이 준비되면 먼 적에게도 바로 벤다
		if p.phantom_ready and bd < Player.PHANTOM_RANGE - 1.0:
			out.slash = true
	# 패링: 창이 열리면 대시를 눌러 받아친다
	if Parry.inst and Parry.inst.best_threat() != null:
		out.dash = true
		out.move = move.limit_length(1.0)
		return out
	# 탄 회피
	bot_dash_cd -= get_physics_process_delta_time()
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		var rel := p.global_position - bl.position
		rel.y = 0
		var l := rel.length()
		if l < 2.4 and bl.vel.dot(rel) > 0:
			var side := Vector3(-bl.vel.z, 0, bl.vel.x).normalized()
			if side.dot(rel) < 0:
				side = -side
			move += side * (2.4 - l)
			if l < 1.3 and bot_dash_cd <= 0.0 and randf() < 0.5:
				out.dash = true
				bot_dash_cd = 1.0
	# 차지 레이저 예고 범위에서 옆으로 빠진다
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Striker:
			var th: Dictionary = (e as Striker).beam_threat()
			if th.is_empty():
				continue
			var rel: Vector3 = p.global_position - th.origin
			rel.y = 0
			var along := clampf(rel.dot(th.dir), 0.0, th.length)
			var off: Vector3 = rel - th.dir * along
			if off.length() < th.width * 0.5 + 1.2:
				var side: Vector3 = off.normalized() if off.length() > 0.05 else Vector3(-th.dir.z, 0, th.dir.x)
				move += side * 2.5
	# 전투 중 주기적으로 대시하고, 끝나는 순간 다시 눌러 2단 대시
	if best and bot_dash_cd <= 0.0 and fmod(time, 3.0) < 0.03:
		out.dash = true
		bot_dash_cd = 1.0
	# 대시가 끝나는 순간 다시 눌러 2단 대시
	if p.dash_t > 0.0 and p.dash_t < Player.CHAIN_WINDOW * 0.8 and not p.rainbow and p.chain_ok:
		out.dash = true
	if best == null:
		move += _bot_explore(p, out)
	out.move = move.limit_length(1.0)
	return out


## 자동 플레이 락온: 포인터가 아직 락온하지 않은 가까운 적 쪽으로 빠르게 쓸고 지나간다 (실제 시간 기준)
func bot_ult_pointer(p: Player, ptr: Vector2) -> Vector2:
	var best := Vector2.INF
	var bd := 1e9
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed or p.locks.has(en):
			continue
		var sp := camera.screen_pos(en.global_position + Vector3(0, 1.0, 0))
		var d := sp.distance_to(ptr)
		if d < bd:
			bd = d
			best = sp
	if best == Vector2.INF:
		return ptr
	var rdt := get_process_delta_time() / maxf(Engine.time_scale, 0.01)
	return ptr.move_toward(best, 2600.0 * rdt)


func bot_ult_release(p: Player) -> bool:
	var left := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e as Enemy).landed and not p.locks.has(e):
			left += 1
	return (left == 0 and p.ult_aim_left() < 1.6) or p.ult_aim_left() < 0.5


func _bot_explore(p: Player, out: Dictionary) -> Vector3:
	bot_path_t -= get_physics_process_delta_time()
	if bot_path_t <= 0.0 or bot_path.is_empty():
		bot_path_t = 0.6
		var target := -1
		var bd := 1e9
		for r in map.rooms:
			if r.combat and r.state == "idle":
				var d: float = map.room_center_world(r.id).distance_to(p.global_position)
				if d < bd:
					bd = d
					target = r.id
		bot_path.clear()
		if target >= 0:
			bot_path = map.find_path(p.global_position, map.room_center_world(target))
	if OS.get_cmdline_user_args().has("--dbg") and fmod(time, 1.0) < 0.02:
		var rr := map.room_at(p.global_position)
		print("DBG t=%.1f pos=%s path=%d room=%d state=%s act=%d gs=%d" % [time, p.global_position, bot_path.size(), rr, map.rooms[rr].state if rr >= 0 else "-", active_room, state])
	# 가까운 경유점은 건너뛴다
	while bot_path.size() > 1 and bot_path[0].distance_to(p.global_position) < 1.1:
		bot_path.pop_front()
	if bot_path.is_empty():
		return Vector3.ZERO
	var wp: Vector3 = bot_path[mini(1, bot_path.size() - 1)]
	var d := wp - p.global_position
	d.y = 0
	out.aim = p.global_position + d.normalized() * 4.0 + Vector3(0, 0.95, 0)
	out.boost = bot_path.size() > 12 and p.boost > 0.5
	return d.normalized()
