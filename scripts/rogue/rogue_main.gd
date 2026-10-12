class_name RogueMain
extends Main
## 로그라이크 모드 「HEX DEPTHS」 — 아이작의 번제식 층·방 구조 위에 기존 전투 코어(대시·검 콤보·총·레이저·미사일)만 남긴 새 모드.
## 기획: docs/roguelike-isaac-mode.md
##  - 층마다 RogueMap 이 방 그리드를 새로 만든다. 방에 들어가면 문이 잠기고 적을 모두 잡으면 열린다.
##  - 특수방: 아이템 · 상점 · 보스 · 비밀(폭탄으로 금 간 벽) · 저주 · 희생 · 도전 · 서재 · 악마/천사 거래
##  - 아이템: RogueItems / RogueBuild. 액티브 Q · 폭탄 X · 알약/카드 Z · 정보 Tab
##  - 보스를 잡으면 트랩도어로 다음 층 (씬을 다시 불러온다, 런 상태는 RogueRun 이 들고 간다)
## 실행 인자: --seed=N · --rogue-depth=N(시작 층) · --rogue-items=a,b(시작 아이템) · --godmode · --bot --seconds=N

const SCENE := "res://scenes/rogue.tscn"
const SHOP_PRICE := 15
const DROP_CHANCE := 0.6

var rmap: RogueMap
var build: RogueBuild
var rhud: RogueHud
var boss: RogueBoss
var rng := RandomNumberGenerator.new()
var cur_room := -1
var pending_room := -1
var room_live: Dictionary = {}     # 방 id → "idle" · "active" · "cleared"
var curse := ""
var reveal_all := false
var reveal_special := false
var reveal_secret := false
var reveal_boss := false
var sac_count := 0
var challenge_wave := 0
var return_pos := Vector3.ZERO
var deal_kind := ""
var trapdoor: Node3D
var godmode := false
var quit_at := -1.0
var _lock_msg_t := 0.0
var _bot_use_t := 0.0
var _bot_stuck_t := 0.0
var _bot_goal := Vector3.INF
var _bot_last_pos := Vector3.ZERO
var _bot_ban := {}
var _dark_light: OmniLight3D


func _ready() -> void:
	inst = self
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	randomize()
	_parse_args()
	var start_depth := 0
	var start_items: Array = []
	var run_seed := -1
	for a in cmd_args:
		if a == "--godmode":
			godmode = true
		elif a.begins_with("--rogue-depth="):
			start_depth = clampi(int(a.substr(14)), 1, RogueRun.FLOORS)
		elif a.begins_with("--rogue-items="):
			start_items = a.substr(14).split(",", false)
		elif a.begins_with("--seed="):
			run_seed = int(a.substr(7))
		elif a.begins_with("--seconds=") and capture_mode and capture_dir == "":
			quit_at = float(a.substr(10))
	if not RogueRun.started:
		RogueRun.new_run(run_seed)
		if start_depth > 0:
			RogueRun.depth = start_depth
		for id in start_items:
			if RogueItems.get_item(id).is_empty():
				continue
			if RogueItems.get_item(id).type == RogueItems.T.ACTIVE:
				RogueRun.active_item = id
				RogueRun.charge = 6
			else:
				RogueRun.items.append(id)
			RogueRun.seen[id] = true
	rng.seed = hash([RogueRun.run_seed, RogueRun.depth])
	seed(rng.seed)
	_setup_input()
	_setup_rogue_input()
	world = Node3D.new()
	add_child(world)
	FX.setup(world)
	add_child(Sfx.new())
	_build_environment()
	BrawlLook.attach(self, env, sun)
	_floor_mood()
	rmap = RogueMap.new()
	map = rmap
	world.add_child(rmap)
	rmap.terrain = false
	rmap.generate_floor(rng.seed, RogueRun.depth)
	rmap.build()
	bullets = Node3D.new()
	add_child(bullets)
	player = Player.new()
	player.bot = capture_mode
	add_child(player)
	player.global_position = rmap.room_center(rmap.start_room)
	player.hp = RogueRun.red
	camera = CameraRig.new()
	add_child(camera)
	camera.current = true
	camera.snap(player.global_position)
	debris = Debris.new()
	world.add_child(debris)
	world.add_child(GunFX.new())
	world.add_child(Parry.new())
	add_child(ParryFX.new())
	hud = Hud.new()
	add_child(hud)
	if is_instance_valid(hud.combo_meter):
		# 로그 모드는 타격 콤보 점수를 쓰지 않는다 (왼쪽 HUD 를 덮지 않게 그리기·갱신을 끈다)
		hud.combo_meter.process_mode = Node.PROCESS_MODE_DISABLED
		hud.combo_meter.visible = false
	build = RogueBuild.new()
	add_child(build)
	build.attach(self, player)
	rhud = RogueHud.new()
	add_child(rhud)
	var impact := ImpactFrame.new()
	impact.enabled = not cmd_args.has("--noimpact")
	add_child(impact)
	FxWarm.attach(self)
	_roll_curse()
	for r in rmap.rooms:
		room_live[r.id] = "idle"
		_populate(r)
	room_live[rmap.start_room] = "cleared"
	_door_signs()
	for r in rmap.rooms:
		if r.locked:
			rmap.close_gates(r.id)
			_tint_gates(r.id, Color("ffd040") if r.kind != "challenge" else Color("c0c8ff"))
	var b := build
	reveal_all = b.f("map_all") > 0
	reveal_special = b.f("map_special") > 0
	reveal_secret = b.f("map_secret") > 0
	reveal_boss = b.f("map_boss") > 0
	if not capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var sub := "아이템을 모아 빌드를 완성하고 보스를 쓰러뜨려라"
	if curse != "":
		sub = {"darkness": "어둠의 저주", "lost": "길 잃음의 저주 — 지도가 없다", "unknown": "미지의 저주 — 체력이 보이지 않는다", "blind": "장님의 저주 — 아이템 이름이 보이지 않는다"}[curse]
	hud.banner("%d층 · %s" % [RogueRun.depth, RogueRun.floor_name()], Color(0.75, 0.9, 1.0), sub)
	print("ROGUE_FLOOR depth=%d rooms=%d seed=%d tries=%d curse=%s items=%d" % [RogueRun.depth, rmap.rooms.size(), rng.seed, rmap.gen_tries, curse, RogueRun.items.size()])
	_enter_room(rmap.start_room)


func _exit_tree() -> void:
	Enemy.dmg_hook = Callable()
	super()


func _setup_rogue_input() -> void:
	var keys := {"rogue_active": KEY_Q, "rogue_bomb": KEY_X, "rogue_pocket": KEY_Z, "rogue_info": KEY_TAB}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var ev := InputEventKey.new()
			ev.physical_keycode = keys[action]
			InputMap.action_add_event(action, ev)


func _hide_base_hud() -> void:
	if hud == null:
		return
	for n in [hud.presets, hud.legacy_left, hud.wave_label, hud.count_label, hud.minimap, hud.combo_box, hud.energy_icons, hud.missile_icons, hud.hint]:
		if is_instance_valid(n):
			n.visible = false


## 층마다 조금씩 다른 색
func _floor_mood() -> void:
	var tints := [Color(0.02, 0.02, 0.05), Color(0.01, 0.03, 0.05), Color(0.05, 0.025, 0.02), Color(0.02, 0.01, 0.04), Color(0.03, 0.01, 0.02), Color(0.04, 0.0, 0.03)]
	env.background_color = tints[clampi(RogueRun.depth - 1, 0, 5)]
	var amb := [Color(0.55, 0.55, 0.85), Color(0.45, 0.65, 0.8), Color(0.85, 0.6, 0.5), Color(0.6, 0.45, 0.8), Color(0.8, 0.45, 0.55), Color(0.85, 0.35, 0.6)]
	env.ambient_light_color = env.ambient_light_color.lerp(amb[clampi(RogueRun.depth - 1, 0, 5)], 0.4)


func _roll_curse() -> void:
	if RogueRun.depth < 2 or rng.randf() > 0.35:
		return
	curse = ["darkness", "lost", "unknown", "blind"][rng.randi_range(0, 3)]
	if curse == "darkness":
		sun.light_energy *= 0.22
		env.ambient_light_energy *= 0.35
		_dark_light = OmniLight3D.new()
		_dark_light.omni_range = 9.0
		_dark_light.light_energy = 1.6
		_dark_light.light_color = Color(1.0, 0.92, 0.8)
		_dark_light.position = Vector3(0, 3.0, 0)
		player.add_child(_dark_light)


func _tint_gates(id: int, c: Color) -> void:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(c.r, c.g, c.b, 0.6)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	for mi in rmap.rooms[id].gate_nodes:
		(mi as MeshInstance3D).material_override = m


# ── 방 채우기 ───────────────────────────────────────────

func _populate(r: Dictionary) -> void:
	var c: Vector3 = rmap.room_center(r.id)
	match r.kind:
		"start":
			if RogueRun.depth == 1:
				_floor_text(c + Vector3(0, 0.05, 3.2), "WASD 이동 · 우클릭 사격 · 좌클릭 검 · Space 대시\nQ 액티브 · X 폭탄 · Z 알약/카드 · Tab 정보")
		"normal":
			for i in rng.randi_range(0, 3):
				_spawn_crate(rmap.random_spot(r.id, c, 0.0), rng.randf() < 0.12)
			if RogueRun.depth >= 2 and rng.randf() < 0.3:
				_spawn_hearth(rmap.random_spot(r.id, c, 0.0))
		"treasure":
			var n := 2 if build.f("options") > 0 else 1
			for i in n:
				_pedestal(c + Vector3((i - (n - 1) * 0.5) * 3.0, 0, 0), _roll_item("treasure"), 0, 0, 1 if n > 1 else -1)
		"shop":
			var price := SHOP_PRICE / (2 if build.f("discount") > 0 else 1)
			for i in 2:
				_pedestal(c + Vector3(-4.5 + i * 3.0, 0, -1.5), _roll_item("shop"), price)
			var goods := [["heart", 3], ["bomb", 5], ["key", 5], ["pill", 4], ["card", 5], ["battery", 8], ["soul", 6]]
			goods.shuffle()
			for i in 3:
				var g: Array = goods[i]
				drop(g[0], c + Vector3(1.5 + i * 2.0, 0, -1.5), null, false, maxi(1, int(g[1]) / (2 if build.f("discount") > 0 else 1)))
			_floor_text(c + Vector3(0, 0.05, 2.6), "상점 — 동전으로 산다")
		"secret":
			if rng.randf() < 0.45:
				_pedestal(c, _roll_item("secret"))
			else:
				for i in rng.randi_range(4, 7):
					drop(["coin", "coin", "nickel", "bomb", "key", "soul"][rng.randi_range(0, 5)], c + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-2, 2)))
		"curse":
			if rng.randf() < 0.5:
				_pedestal(c, _roll_item("devil"))
			else:
				drop("chest", c)
				drop("black", c + Vector3(2, 0, 0))
			_floor_text(c + Vector3(0, 0.05, 2.8), "저주방 — 들어올 때마다 피해")
		"sacrifice":
			var sp := RogueProps.Spikes.new()
			sp.sacrifice = true
			sp.size = Vector2(2.0, 2.0)
			world.add_child(sp)
			sp.global_position = c
			_floor_text(c + Vector3(0, 0.05, 2.8), "희생방 — 가시를 밟을수록 보상")
		"library":
			for i in 2:
				_pedestal(c + Vector3((i - 0.5) * 3.0, 0, 0), _roll_item("library", RogueItems.T.ACTIVE), 0, 0, 2)
			_floor_text(c + Vector3(0, 0.05, 2.6), "서재 — 하나만 가질 수 있다")
		"challenge":
			_floor_text(c + Vector3(0, 0.05, 2.8), "도전방 — 웨이브를 버티면 보상")
	# 금 간 벽
	if r.kind == "secret" and r.has("secret_wall"):
		var sw: Dictionary = r.secret_wall
		var cr := RogueProps.Crack.new()
		cr.face = Vector3(sw.face.x, 0, sw.face.y)
		world.add_child(cr)
		cr.global_position = rmap.world_of(sw.cell)
		cr.set_meta("room", sw.room)


## 특수방 문 위 표지판 (아이작의 문 장식처럼 옆 방에서도 방 종류가 보이게)
func _door_signs() -> void:
	var cols := {"boss": Color("ff4a5a"), "treasure": Color("ffd040"), "shop": Color("7cf090"), "curse": Color("c070ff"), "sacrifice": Color("ff6a7a"), "challenge": Color("ffb040"), "library": Color("8ad8ff")}
	for r in rmap.rooms:
		if not cols.has(r.kind):
			continue
		var done := {}
		for door in r.doors:
			var c: Vector2i = door[0]
			var sl := (c - Vector2i(RogueMap.OX, RogueMap.OY)) / Vector2i(RogueMap.PX, RogueMap.PY)
			var k := Vector4i(sl.x, sl.y, door[1].x, door[1].y)
			if done.has(k):
				continue
			done[k] = true
			var l := Label3D.new()
			l.text = "%s %s" % [RogueHud.ROOM_ICONS.get(r.kind, ""), RogueHud.KIND_NAMES.get(r.kind, "")]
			l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			l.font_size = 44
			l.outline_size = 12
			l.pixel_size = 0.01
			l.modulate = cols[r.kind]
			world.add_child(l)
			var d: Vector2i = door[1]
			l.global_position = rmap.world_of(c) - Vector3(d.x, 0, d.y) * 2.0 + Vector3(0, 2.3, 0)


func _floor_text(pos: Vector3, text: String) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.008
	l.outline_size = 10
	l.modulate = Color(0.85, 0.9, 1.0, 0.75)
	l.rotation_degrees.x = -90.0
	world.add_child(l)
	l.global_position = pos


func _roll_item(pool: String, type := -1) -> String:
	var id := RogueItems.roll(pool, rng, RogueRun.seen, type)
	if id == "":
		id = RogueItems.roll("treasure", rng, RogueRun.seen, type)
	if id == "":
		id = "protein"
	RogueRun.seen[id] = true
	return id


func _pedestal(pos: Vector3, id: String, price := 0, heart_price := 0, group := -1) -> RoguePedestal:
	var p := RoguePedestal.new()
	p.item_id = id
	p.price = price
	p.heart_price = heart_price
	p.group = group
	p.blind = curse == "blind" and price == 0 and heart_price == 0
	world.add_child(p)
	p.global_position = Vector3(pos.x, 0, pos.z)
	return p


func _spawn_crate(pos: Vector3, tinted := false) -> void:
	var c := RogueProps.Crate.new()
	c.tinted = tinted
	world.add_child(c)
	c.global_position = pos


func _spawn_hearth(pos: Vector3) -> void:
	var h := RogueProps.Hearth.new()
	world.add_child(h)
	h.global_position = pos


# ── 진행 ────────────────────────────────────────────────

func _physics_process(dt: float) -> void:
	time += dt
	RogueRun.time += dt
	_hide_base_hud()
	if combo > 0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 0
	if godmode and is_instance_valid(player):
		player.invuln = maxf(player.invuln, 0.5)
	if not is_instance_valid(player):
		return
	RogueRun.red = player.hp if player.alive else 0
	if state == State.PLAY and player.alive:
		var rid := rmap.room_at(player.global_position)
		if rid >= 0 and rid != cur_room:
			_enter_room(rid)
		if pending_room >= 0 and rid == pending_room and _inside(rid):
			_start_combat(pending_room)
			pending_room = -1
		_check_clear()
		_check_locks(dt)
		_rogue_input()
	if quit_at > 0.0 and time >= quit_at:
		print("ROGUE_END t=%.1f depth=%d rooms=%d kills=%d items=%d hp=%d" % [time, RogueRun.depth, RogueRun.rooms, RogueRun.kills, RogueRun.items.size(), player.hp])
		get_tree().quit()


func _inside(rid: int) -> bool:
	for door in rmap.rooms[rid].doors:
		if rmap.world_of(door[0]).distance_to(player.global_position) < 2.0:
			return false
	return true


func _enter_room(rid: int) -> void:
	cur_room = rid
	var r: Dictionary = rmap.rooms[rid]
	var first: bool = not r.visited
	r.visited = true
	build.on_room_enter()
	if build.f("room_soul") > 0 and build.roll(build.f("room_soul")):
		RogueRun.soul += 1
		hud.popup("+소울", Color("8aa8ff"), player.global_position + Vector3(0, 2.2, 0))
	match r.kind:
		"normal", "boss", "challenge":
			if room_live[rid] == "idle":
				pending_room = rid
		"curse":
			if not build.flying():
				player.take_hit(player.global_position + Vector3(0, 0, 0.5))
		"treasure", "shop", "library", "secret", "deal":
			if first:
				Sfx.play("ready", 0.0, -4.0)


func _start_combat(rid: int) -> void:
	var r: Dictionary = rmap.rooms[rid]
	room_live[rid] = "active"
	rmap.close_gates(rid)
	shake(0.2)
	Sfx.play("spawn", 0.0, 0.0)
	match r.kind:
		"boss":
			boss = RogueBoss.new()
			add_child(boss)
			boss.start(self, rid, RogueRun.depth)
		"challenge":
			challenge_wave = 1
			_spawn_wave(rid, 1.3)
			hud.banner("CHALLENGE", Color("ffb040"), "웨이브 1 / 2")
		_:
			_spawn_wave(rid, 1.0)


func _spawn_wave(rid: int, k: float) -> void:
	var r: Dictionary = rmap.rooms[rid]
	var big: bool = r.slots.size() > 1
	var n := roundi(clampi(3 + RogueRun.depth + rng.randi_range(0, 2), 3, 10) * (1.6 if big else 1.0) * k)
	for i in n:
		var pos := rmap.random_spot(rid, player.global_position, 4.5)
		_queue_spawn(_pick_type(), pos, i * 0.08)


func _pick_type() -> String:
	var d := RogueRun.depth
	var w := {"grub": 3.0, "chomper": 2.0, "drone0": 3.0, "ant": 1.0 if d >= 1 else 0.0}
	if d >= 2:
		w["striker"] = 1.5
		w["pill"] = 1.2
		w["drone1"] = 2.0
	if d >= 3:
		w["crawler"] = 1.0
		w["turret"] = 1.0
		w["drone2"] = 1.5
		w["ant"] = 2.0
	if d >= 5:
		w["striker"] = 2.5
		w["crawler"] = 1.6
	var total := 0.0
	for k in w:
		total += w[k]
	var roll := rng.randf() * total
	for k in w:
		roll -= w[k]
		if roll <= 0.0:
			return k
	return "drone0"


func _queue_spawn(type: String, pos: Vector3, delay := 0.0) -> void:
	pending_spawns += 1
	FX.spawn_marker(pos, 0.7 + delay)
	get_tree().create_timer(0.7 + delay, false).timeout.connect(func():
		pending_spawns -= 1
		if state == State.LOSE:
			return
		spawn_enemy(type, pos))


func hp_k() -> float:
	return 2.0 * (1.0 + 0.28 * (RogueRun.depth - 1))


## 적 하나 (보스 부하 · 웨이브 공용). 챔피언 확률 포함
func spawn_enemy(type: String, pos: Vector3) -> Enemy:
	var e: Enemy
	match type:
		"grub": e = BugGrub.new()
		"chomper": e = BugChomper.new()
		"ant": e = BugAnt.new()
		"pill": e = BugPill.new()
		"striker": e = Striker.new()
		"crawler": e = Crawler.new()
		"turret": e = Turret.new()
		"drone1":
			e = Enemy.new()
			e.pattern = 1
		"drone2":
			e = Enemy.new()
			e.pattern = 2
		_:
			e = Enemy.new()
			e.pattern = 0
	e.hp_mul = hp_k()
	var champ := rng.randf() < 0.12 + 0.03 * RogueRun.depth and type != "turret"
	if champ:
		e.hp_mul *= 2.0
		e.set_meta("champion", true)
	world.add_child(e)
	e.global_position = pos
	if e is BugEnemy or e is Turret:
		e.rotation.y = atan2(-(player.global_position.x - pos.x), -(player.global_position.z - pos.z))
	if champ:
		e.scale = Vector3.ONE * 1.2
		e.radius *= 1.2
		var ring := Pal.flat_mesh(_champ_ring(), [Color("ff4a5a"), Color("ffd040"), Color("60f0ff"), Color("b070ff"), Color("70ff60")][rng.randi_range(0, 4)], 2.2)
		ring.position.y = 0.08
		e.add_child(ring)
	return e


static var _ring_mesh: TorusMesh
static func _champ_ring() -> TorusMesh:
	if _ring_mesh == null:
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.75
		_ring_mesh.outer_radius = 0.9
		_ring_mesh.rings = 24
	return _ring_mesh


func _room_enemies() -> int:
	var n := 0
	for e in Enemy.live(get_tree()):
		if not e.get("prop"):
			n += 1
	return n


func _check_clear() -> void:
	if cur_room < 0 or room_live.get(cur_room, "") != "active":
		return
	var r: Dictionary = rmap.rooms[cur_room]
	if r.kind == "boss":
		return
	if pending_spawns > 0 or _room_enemies() > 0:
		return
	if r.kind == "challenge" and challenge_wave == 1:
		challenge_wave = 2
		_spawn_wave(cur_room, 1.5)
		hud.banner("CHALLENGE", Color("ffb040"), "웨이브 2 / 2")
		return
	_clear_rogue_room(cur_room)


func _clear_rogue_room(rid: int) -> void:
	var r: Dictionary = rmap.rooms[rid]
	room_live[rid] = "cleared"
	rmap.open_gates(rid)
	rooms_cleared += 1
	RogueRun.rooms += 1
	print("ROGUE_CLEAR id=%d kind=%s t=%.1f hp=%d soul=%d items=%d" % [rid, r.kind, time, player.hp, RogueRun.soul, RogueRun.items.size()])
	_charge_active(1 + build.f("battery") + (1 if build.f("cell") > 0 and randf() * 100 < build.f("cell") else 0))
	if build.f("regen") > 0 and build.roll(build.f("regen")):
		heal_red(1, true)
	Sfx.play("charged", 0.0, -2.0)
	FX.shockwave(player.global_position, Pal.CYAN, 3.0, 0.4)
	var c: Vector3 = rmap.room_center(rid)
	if r.kind == "challenge":
		_pedestal(c, _roll_item("boss"))
		hud.banner("CHALLENGE CLEAR", Color("ffd040"), "보상 아이템")
		return
	if rng.randf() < DROP_CHANCE + build.luck * 0.05:
		drop(_room_reward(), c)


func _room_reward() -> String:
	var w := {"coin": 28.0, "nickel": 3.0, "heart": 13.0, "half_heart": 7.0, "key": 10.0, "bomb": 10.0, "soul": 4.0, "pill": 6.0, "card": 5.0, "battery": 3.0, "chest": 4.0, "trinket": 2.0, "missile": 4.0}
	if build.f("drop_coin") > 0:
		w.coin += 25.0
	if build.f("drop_key") > 0:
		w.key += 15.0
	if build.f("drop_bomb") > 0:
		w.bomb += 15.0
	var total := 0.0
	for k in w:
		total += w[k]
	var roll := rng.randf() * total
	for k in w:
		roll -= w[k]
		if roll <= 0.0:
			return k
	return "coin"


func _charge_active(n: int) -> void:
	if RogueRun.active_item == "":
		return
	var need := int(RogueItems.get_item(RogueRun.active_item).get("charge", 1))
	var was := RogueRun.charge
	RogueRun.charge = mini(need, RogueRun.charge + n)
	if was < need and RogueRun.charge >= need:
		hud.popup("액티브 준비", Color("ffe070"), player.global_position + Vector3(0, 2.4, 0))


func _check_locks(dt: float) -> void:
	_lock_msg_t -= dt
	for r in rmap.rooms:
		if not r.locked:
			continue
		var near := false
		for door in r.doors:
			if rmap.world_of(door[0]).distance_to(player.global_position) < 1.7:
				near = true
		if not near:
			continue
		if r.kind == "challenge":
			if player.hp >= RogueRun.red_max:
				_unlock(r.id)
			elif _lock_msg_t <= 0.0:
				_lock_msg_t = 1.5
				hud.popup("체력이 가득해야 열린다", Color("c0c8ff"), player.global_position + Vector3(0, 2.4, 0))
		elif RogueRun.keys > 0:
			RogueRun.keys -= 1
			_unlock(r.id)
		elif _lock_msg_t <= 0.0:
			_lock_msg_t = 1.5
			hud.popup("열쇠가 필요하다", Color("ffd040"), player.global_position + Vector3(0, 2.4, 0))


func _unlock(id: int) -> void:
	rmap.rooms[id].locked = false
	rmap.open_gates(id)
	Sfx.play("unfold", 0.0, -2.0)
	FX.sparks(player.global_position + Vector3(0, 1, 0), 12, [Color("ffd040"), Color.WHITE], 6.0, 0.4, -8.0, 0.07)


# ── 보스 · 포털 ─────────────────────────────────────────

func on_boss_dead(ctrl: RogueBoss) -> void:
	var rid := ctrl.room
	room_live[rid] = "cleared"
	rmap.open_gates(rid)
	RogueRun.rooms += 1
	_charge_active(1)
	var c: Vector3 = rmap.room_center(rid)
	print("ROGUE_BOSS_DEAD depth=%d t=%.1f" % [RogueRun.depth, time])
	FX.victory(player.global_position)
	Sfx.play("win", 0.0, -2.0)
	if RogueRun.depth >= RogueRun.FLOORS:
		_victory()
		return
	_pedestal(c + Vector3(-2.5, 0, 0), _roll_item("boss"))
	drop("heart", c + Vector3(2.5, 0, 1.0))
	trapdoor = _portal("trapdoor", c + Vector3(0, 0, 3.0))
	hud.banner("BOSS DOWN", Color("ffd040"), "트랩도어로 다음 층")
	# 악마 / 천사 거래
	if RogueRun.depth >= 1:
		var devil := 0.3 + build.f("devil_up") * 0.15 + (1.0 if build.f("goat") > 0 else 0.0)
		if RogueRun.depth == 1:
			devil *= 0.5
		if rng.randf() < devil:
			deal_kind = "angel" if (build.f("angel_up") > 0 or (RogueRun.deals_taken == 0 and rng.randf() < 0.4)) and build.f("goat") == 0 else "devil"
			_portal(deal_kind, c + Vector3(0, 0, -3.5))
			hud.popup("거래의 문이 열렸다", Color("ff6a4a") if deal_kind == "devil" else Color("fff0a0"), c + Vector3(0, 2.0, -3.5))


func _portal(kind: String, pos: Vector3) -> RogueProps.Portal:
	var p := RogueProps.Portal.new()
	p.kind = kind
	world.add_child(p)
	p.global_position = Vector3(pos.x, 0, pos.z)
	return p


func on_portal(p: RogueProps.Portal) -> void:
	match p.kind:
		"trapdoor":
			_next_floor()
		"secret":
			return_pos = p.global_position
			var here := rmap.room_at(p.global_position)
			if here >= 0:
				return_pos += (rmap.room_center(here) - p.global_position).normalized() * 1.6
			var sc: Vector3 = rmap.room_center(rmap.island_secret)
			if get_tree().get_nodes_in_group("rogue_portals").filter(func(q): return q.kind == "back").is_empty():
				_portal("back", sc + Vector3(0, 0, 4.5))
			_teleport(sc)
			hud.banner("비밀방", Color("c890ff"), "숨겨진 방을 찾았다")
		"back", "deal_back":
			_teleport(return_pos)
		"devil", "angel":
			return_pos = p.global_position + Vector3(0, 0, 2.0)
			_open_deal(p.kind)
			_teleport(rmap.room_center(rmap.island_deal) + Vector3(0, 0, 3.0))


func _open_deal(kind: String) -> void:
	var r: Dictionary = rmap.rooms[rmap.island_deal]
	if r.get("filled", false):
		return
	r.filled = true
	var c: Vector3 = rmap.room_center(rmap.island_deal)
	if kind == "devil":
		for i in 2:
			var id := _roll_item("devil")
			var q: int = RogueItems.get_item(id).q
			_pedestal(c + Vector3((i - 0.5) * 4.0, 0, -1.0), id, 0, 2 if q >= 3 else 1)
		_floor_text(c + Vector3(0, 0.05, 1.8), "악마의 거래 — 빨간 그릇으로 산다")
	else:
		for i in 2:
			_pedestal(c + Vector3((i - 0.5) * 4.0, 0, -1.0), _roll_item("angel"), 0, 0, 7)
		_floor_text(c + Vector3(0, 0.05, 1.8), "천사의 방 — 하나만 가질 수 있다")
	_portal("deal_back", c + Vector3(0, 0, 4.5))


func _teleport(pos: Vector3) -> void:
	player.global_position = Vector3(pos.x, Main.gy(pos), pos.z)
	player.velocity = Vector3.ZERO
	camera.snap(player.global_position)
	FX.ring(player.global_position + Vector3(0, 0.3, 0), 3.5, [Color("c0e8ff"), Color.WHITE, Color("c0e8ff")], 0.4)
	Sfx.play("dash", 0.0, -2.0)


func _next_floor() -> void:
	RogueRun.red = player.hp
	RogueRun.depth += 1
	print("ROGUE_NEXT depth=%d t=%.1f" % [RogueRun.depth, time])
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file.call_deferred(SCENE)


func _victory() -> void:
	state = State.WIN
	RogueRun.won = true
	RogueRun.started = false
	print("ROGUE_WIN t=%.1f items=%d kills=%d" % [RogueRun.time, RogueRun.items.size(), RogueRun.kills])
	player.celebrate()
	hud.message("HEX HEART 격파", "6층 정복 · 아이템 %d개 · 처치 %d · %.0f초 · R 새 런" % [RogueRun.items.size(), RogueRun.kills, RogueRun.time], Color("ffd040"))


func on_blast(pos: Vector3, radius: float, _source := "") -> void:
	for cr in get_tree().get_nodes_in_group("rogue_cracks"):
		var c := cr as RogueProps.Crack
		if c.opened:
			continue
		if Vector2(c.global_position.x - pos.x, c.global_position.z - pos.z).length() < radius + 1.2:
			c.opened = true
			var at := c.global_position - c.face * 1.4
			_portal("secret", at)
			FX.sparks(c.global_position + Vector3(0, 0.6, 0), 20, [Color("c890ff"), Color.WHITE], 7.0, 0.5, -10.0, 0.1)
			hud.popup("비밀 통로!", Color("c890ff"), c.global_position + Vector3(0, 2.0, 0))
			reveal_secret = true


func on_sacrifice(_sp) -> void:
	sac_count += 1
	var c: Vector3 = rmap.room_center(cur_room)
	match sac_count:
		1, 2:
			if rng.randf() < 0.6:
				drop("coin", c + Vector3(0, 0, 2.2))
		3:
			_pedestal(c + Vector3(0, 0, 2.8), _roll_item("angel"))
		4:
			drop("chest", c + Vector3(0, 0, 2.2))
		5:
			drop("soul", c + Vector3(0, 0, 2.2))
			drop("soul", c + Vector3(1, 0, 2.2))
		7:
			_pedestal(c + Vector3(0, 0, 2.8), _roll_item("devil"))
		_:
			if rng.randf() < 0.4:
				drop(_room_reward(), c + Vector3(0, 0, 2.2))
	hud.popup("희생 ×%d" % sac_count, Color("ff6a7a"), player.global_position + Vector3(0, 2.4, 0))


func on_crate_broken(c: Node) -> void:
	var at: Vector3 = (c as Node3D).global_position
	if c is RogueProps.Crate and c.tinted:
		for i in rng.randi_range(1, 2):
			drop(["soul", "bomb", "key", "nickel"][rng.randi_range(0, 3)], at)
	elif rng.randf() < 0.3:
		drop(["coin", "coin", "coin", "heart", "bomb", "key", "pill"][rng.randi_range(0, 6)], at)


# ── 처치 · 피격 ─────────────────────────────────────────

func on_enemy_killed(e: Enemy) -> void:
	kills += 1
	RogueRun.kills += 1
	combo += 1
	combo_t = COMBO_TIME
	best_combo = maxi(best_combo, combo)
	var pts := 100 * combo
	score += pts
	hud.combo_pop(pts, e.kill_source)
	ComboMeter.kill()
	if is_instance_valid(player):
		player.gain_boost()
	hitstop(0.06)
	shake(0.3)
	camera.kill_punch(e.global_position)
	var at := e.global_position
	if build.f("vamp") > 0 and (build.syn.has("vampire") or build.roll(build.f("vamp"))):
		heal_red(1, true)
	if build.f("kill_explode") > 0:
		RogueEffects.explosion(at, 2.2, build.cur_dmg() * 1.5, false)
	if build.f("kill_soul") > 0 and build.roll(build.f("kill_soul")):
		RogueRun.soul += 1
		hud.popup("+소울", Color("8aa8ff"), at + Vector3(0, 2.0, 0))
	if build.f("fly_queen") > 0 and build.roll(build.f("fly_queen")):
		build.spawn_temp_familiar("hunter", 8.0)
	if build.f("spore") > 0:
		RogueEffects.poison_cloud(at, 1.8, 3.0, build.cur_dmg() * 0.3)
	if e.has_meta("champion"):
		drop(_room_reward(), at)
	elif rng.randf() < 0.07:
		drop(["coin", "coin", "missile", "half_heart"][rng.randi_range(0, 3)], at)


func on_player_hurt() -> void:
	super()
	if is_instance_valid(player):
		RogueRun.red = player.hp


func on_player_died() -> void:
	super()
	RogueRun.red = 0
	RogueRun.started = false
	print("ROGUE_DEAD depth=%d t=%.1f items=%d kills=%d" % [RogueRun.depth, RogueRun.time, RogueRun.items.size(), RogueRun.kills])
	hud.message("DESTROYED", "%d층에서 쓰러졌다 · 아이템 %d개 · 처치 %d · R 새 런" % [RogueRun.depth, RogueRun.items.size(), RogueRun.kills], Color("ff4a8a"))


func heal_red(n: int, pop := false) -> void:
	if not is_instance_valid(player) or not player.alive:
		return
	var before := player.hp
	player.hp = mini(RogueRun.red_max, player.hp + n)
	RogueRun.red = player.hp
	if pop and player.hp > before:
		hud.popup("+♥", Color("ff6a7a"), player.global_position + Vector3(0, 2.3, 0))


# ── 픽업 · 받침대 ───────────────────────────────────────

func drop(kind: String, pos: Vector3, value = null, pop := true, price := 0) -> RoguePickup:
	if value == null:
		match kind:
			"pill":
				value = rng.randi_range(0, RogueItems.PILL_COLORS.size() - 1)
			"card":
				value = RogueItems.CARDS[rng.randi_range(0, RogueItems.CARDS.size() - 1)][0]
			"trinket":
				value = _roll_item("treasure", RogueItems.T.TRINKET)
	var p := RoguePickup.make(kind, value)
	p.price = price
	if kind == "pill" and rng.randf() < 0.1:
		p.horse = true
	world.add_child(p)
	pos.y = Main.gy(pos) + 0.8
	p.global_position = pos
	if pop:
		p.pop()
	return p


func collect(p: RoguePickup) -> bool:
	if not player.alive:
		return false
	if p.price > 0:
		if RogueRun.coins < p.price:
			hud.popup("동전 %d개 필요" % p.price, Color("ffd040"), p.global_position + Vector3(0, 1.6, 0))
			return false
	var at := p.global_position + Vector3(0, 1.2, 0)
	match p.kind:
		"coin", "nickel", "dime":
			var v := {"coin": 1, "nickel": 5, "dime": 10}[p.kind] as int
			RogueRun.coins = mini(99, RogueRun.coins + v)
			Sfx.play("tink", 0.1, -6.0)
			hud.popup("+%d¢" % v, Color("ffd040"), at)
		"key":
			RogueRun.keys = mini(99, RogueRun.keys + 1)
			Sfx.play("lock", 0.1, -4.0)
			hud.popup("+열쇠", Color("ffe080"), at)
		"bomb":
			RogueRun.bombs = mini(99, RogueRun.bombs + 1)
			Sfx.play("clank", 0.1, -6.0)
			hud.popup("+폭탄", Color("c0c0d0"), at)
		"heart", "half_heart":
			if player.hp >= RogueRun.red_max:
				return false
			heal_red(2 if p.kind == "heart" else 1)
			Sfx.play("charged", 0.1, -6.0)
			hud.popup("+♥", Color("ff6a7a"), at)
		"soul", "black":
			if RogueRun.hearts_total() >= RogueRun.RED_CAP:
				return false
			if p.kind == "soul":
				RogueRun.soul += 2
			else:
				RogueRun.black += 2
			Sfx.play("charged", 0.1, -6.0)
			hud.popup("+소울" if p.kind == "soul" else "+블랙", Color("8aa8ff") if p.kind == "soul" else Color("b070ff"), at)
		"battery":
			if RogueRun.active_item == "":
				return false
			_charge_active(99)
			Sfx.play("charged", 0.0, -3.0)
		"missile":
			if player.missiles >= Player.MISSILE_MAX:
				return false
			player.missiles += 1
			hud.popup("+미사일", Color("ffb070"), at)
		"pill", "card":
			if not RogueRun.pocket.is_empty():
				var old: Dictionary = RogueRun.pocket
				var back := drop(old.kind, p.global_position + Vector3(1.0, 0, 0), old.id)
				back.horse = old.get("horse", false)
			RogueRun.pocket = {"kind": p.kind, "id": p.value, "horse": p.horse}
			Sfx.play("lock", 0.1, -4.0)
			if p.kind == "card":
				var cd := RogueItems.card(str(p.value))
				hud.banner(cd[1], Color("ff9ad0"), cd[2] + "  ·  Z 로 사용")
			else:
				var ci := int(p.value)
				var known := RogueRun.pills_known.has(ci)
				hud.banner(("큰 " if p.horse else "") + (RogueItems.pill_name(RogueRun.pill_map[ci]) if known else "알약 · %s" % RogueItems.PILL_COLORS[ci][0]), Color("ff9ad0"), "Z 로 먹는다" + ("" if known else " · 먹어 봐야 효과를 안다"))
		"trinket":
			if RogueRun.trinket != "":
				drop("trinket", p.global_position + Vector3(1.0, 0, 0), RogueRun.trinket)
			RogueRun.trinket = str(p.value)
			var it := RogueItems.get_item(RogueRun.trinket)
			hud.banner(it.name, Color("d0c0ff"), "장신구 · " + it.desc)
			build.recompute()
			reveal_boss = reveal_boss or build.f("map_boss") > 0
		"chest":
			Sfx.play("unfold", 0.0, -2.0)
			for i in rng.randi_range(2, 4):
				drop(_room_reward(), p.global_position)
			if rng.randf() < 0.15:
				drop("trinket", p.global_position)
	if p.price > 0:
		RogueRun.coins -= p.price
	return true


func take_pedestal(ped: RoguePedestal) -> void:
	if ped.taken or ped.item_id == "" or not player.alive:
		return
	var id := ped.item_id
	var it := RogueItems.get_item(id)
	if ped.price > 0:
		if RogueRun.coins < ped.price:
			hud.popup("동전 %d개 필요" % ped.price, Color("ffd040"), ped.global_position + Vector3(0, 2.4, 0))
			return
		RogueRun.coins -= ped.price
	if ped.heart_price > 0:
		var cost := ped.heart_price * 2
		if RogueRun.red_max >= cost + 2:
			RogueRun.red_max -= cost
			player.hp = mini(player.hp, RogueRun.red_max)
		elif RogueRun.soul >= 6:
			RogueRun.soul -= 6
		else:
			hud.popup("체력 그릇이 모자라다", Color("ff4a5a"), ped.global_position + Vector3(0, 2.4, 0))
			return
		RogueRun.deals_taken += 1
		Sfx.play("powerdown", 0.0, -2.0)
	RogueRun.seen[id] = true
	var swapped := ""
	match it.type:
		RogueItems.T.ACTIVE:
			swapped = RogueRun.active_item
			RogueRun.active_item = id
			RogueRun.charge = int(it.get("charge", 1))
		RogueItems.T.TRINKET:
			swapped = RogueRun.trinket
			RogueRun.trinket = id
		_:
			RogueRun.items.append(id)
			_grant_once(it)
	ped.price = 0
	ped.heart_price = 0
	ped.blind = false
	ped.set_item(swapped)
	if ped.group >= 0:
		for other in get_tree().get_nodes_in_group("rogue_pedestals"):
			if other != ped and other.group == ped.group and not other.taken:
				FX.flash(other.global_position + Vector3(0, 1.3, 0), Color.WHITE, 0.8, 0.12)
				other.set_item("")
	print("ROGUE_ITEM %s (%s) t=%.1f" % [id, it.name, time])
	build.recompute()
	var c := RogueItems.color_of(id)
	hud.banner(it.name, c.lerp(Color.WHITE, 0.3), it.desc + ("  ·  Q 로 사용" if it.type == RogueItems.T.ACTIVE else ""))
	player.celebrate()
	FX.ring(player.global_position + Vector3(0, 0.3, 0), 4.0, [c, Color.WHITE, c], 0.5)
	Sfx.play("charged", 0.0, 0.0)


## 아이템을 얻는 순간 한 번만 주는 것: 체력 그릇 · 회복 · 소울 · 블랙 · 자원
func _grant_once(it: Dictionary) -> void:
	var s: Dictionary = it.stats
	if s.has("hearts"):
		RogueRun.red_max = mini(RogueRun.RED_CAP, RogueRun.red_max + int(s.hearts) * 2)
	if s.has("heal"):
		heal_red(int(s.heal))
	if s.has("soul"):
		RogueRun.soul += int(s.soul)
	if s.has("black"):
		RogueRun.black += int(s.black)
	var fl: Dictionary = it.flags
	if fl.has("coins"):
		RogueRun.coins = mini(99, RogueRun.coins + int(fl.coins))
	if fl.has("keys"):
		RogueRun.keys = mini(99, RogueRun.keys + int(fl.keys))
	if fl.has("bombs"):
		RogueRun.bombs = mini(99, RogueRun.bombs + int(fl.bombs))
	if fl.has("map_all"):
		reveal_all = true
	if fl.has("map_special"):
		reveal_special = true
	if fl.has("map_secret"):
		reveal_secret = true


func announce_synergy(sid: String) -> void:
	for s in RogueItems.SYNERGIES:
		if s.id == sid:
			print("ROGUE_SYNERGY %s" % sid)
			get_tree().create_timer(1.3, false).timeout.connect(func():
				hud.banner("결합 공격 · " + s.name, Color("ff9af0"), s.desc))
			FX.shockwave(player.global_position, Color("ff9af0"), 5.0, 0.5)


func announce_transform(tag: String) -> void:
	var tr: Dictionary = RogueItems.TRANSFORMS[tag]
	print("ROGUE_TRANSFORM %s" % tag)
	match tag:
		"angel": RogueRun.soul += 4
		"demon": RogueRun.black += 4
		"mushroom":
			RogueRun.red_max = mini(RogueRun.RED_CAP, RogueRun.red_max + 2)
			heal_red(2)
		"bomb": RogueRun.bombs = mini(99, RogueRun.bombs + 5)
	get_tree().create_timer(2.6, false).timeout.connect(func():
		hud.banner("변신 · " + tr.name, RogueItems.TAG_COLORS[tag], tr.desc))
	FX.victory(player.global_position)
	hitstop(0.15)
	shake(0.5)


# ── 액티브 · 폭탄 · 알약/카드 ───────────────────────────

func _rogue_input() -> void:
	var use_active := Input.is_action_just_pressed("rogue_active")
	var use_bomb := Input.is_action_just_pressed("rogue_bomb")
	var use_pocket := Input.is_action_just_pressed("rogue_pocket")
	if player.bot:
		use_active = false
		use_bomb = false
		use_pocket = false
		_bot_use_t -= get_physics_process_delta_time()
		if _bot_use_t <= 0.0:
			_bot_use_t = 1.0
			var fighting := _room_enemies() > 0
			if fighting and RogueRun.active_item != "" and RogueRun.charge >= int(RogueItems.get_item(RogueRun.active_item).get("charge", 1)) and RogueRun.active_item not in ["a_teleport", "a_d6", "a_chaos", "a_razor"]:
				use_active = true
			elif not RogueRun.pocket.is_empty() and (fighting or randf() < 0.2):
				use_pocket = true
			elif fighting and RogueRun.bombs > 2 and randf() < 0.15:
				use_bomb = true
	if use_active:
		use_active_item()
	if use_bomb:
		if RogueRun.bombs > 0:
			RogueRun.bombs -= 1
			_place_bomb(player.global_position)
		else:
			hud.popup("폭탄 없음", Color(0.8, 0.8, 0.9), player.global_position + Vector3(0, 2.2, 0))
	if use_pocket:
		use_pocket_item()


func _place_bomb(pos: Vector3) -> void:
	RogueBomb.spawn(self, pos)
	if build.syn.has("powder"):
		for i in 3:
			var a := TAU * i / 3.0
			RogueBomb.spawn(self, pos, false, Vector3(cos(a), 0, sin(a)) * 7.0)


func use_active_item() -> void:
	var id := RogueRun.active_item
	if id == "":
		return
	var need := int(RogueItems.get_item(id).get("charge", 1))
	if RogueRun.charge < need:
		hud.popup("충전 부족", Color(0.8, 0.8, 0.9), player.global_position + Vector3(0, 2.2, 0))
		return
	if not _do_active(id):
		return
	RogueRun.charge = 0
	print("ROGUE_ACTIVE %s" % id)
	hud.popup(RogueItems.get_item(id).name, Color("8ad8ff"), player.global_position + Vector3(0, 2.4, 0))
	Sfx.play("charged", 0.0, -2.0)


func _aim_point() -> Vector3:
	var a := player.aim_point
	a.y = 0
	return a


func _do_active(id: String) -> bool:
	var p := player.global_position
	match id:
		"a_bomb":
			_place_bomb(p)
		"a_ring":
			for i in 16:
				var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 16.0)
				RogueEffects.bullet(build, p + Vector3(0, 0.95, 0), d, build.cur_dmg())
		"a_d6":
			var n := 0
			for ped in get_tree().get_nodes_in_group("rogue_pedestals"):
				if ped.item_id != "" and not ped.taken and rmap.room_at(ped.global_position) == cur_room:
					var pool: String = {"shop": "shop", "secret": "secret", "deal": "devil", "library": "library"}.get(rmap.room_kind(cur_room), "treasure")
					ped.set_item(_roll_item(pool))
					FX.flash(ped.global_position + Vector3(0, 1.3, 0), Color.WHITE, 1.0, 0.12)
					n += 1
			if n == 0:
				return false
		"a_d20":
			for pk in get_tree().get_nodes_in_group("rogue_pickups"):
				if pk.price == 0 and rmap.room_at(pk.global_position) == cur_room:
					drop(_room_reward(), pk.global_position)
					pk.queue_free()
		"a_watch":
			RogueEffects.time_stop(3.0)
		"a_shadows":
			player.invuln = 8.0
			build.look.mantle_show(true)
			get_tree().create_timer(8.0, false).timeout.connect(func():
				if is_instance_valid(build) and is_instance_valid(build.look):
					build.look.mantle_show(build.shield_ready))
		"a_belial":
			build.room_dmg += 2.0
			RogueRun.black += 1
		"a_razor":
			if player.hp <= 1:
				return false
			player.hp -= 1
			RogueRun.red = player.hp
			build.room_dmg += 1.2
			FX.player_hurt(p + Vector3(0, 0.9, 0))
		"a_necro":
			RogueEffects.room_damage(40.0)
		"a_teleport":
			_teleport_random()
		"a_crystal":
			reveal_all = true
			reveal_secret = true
			reveal_special = true
		"a_nickel":
			if rng.randf() < 0.5:
				drop("coin", p)
		"a_hole":
			RogueEffects.black_hole(build, _aim_point(), 6.0, build.cur_dmg() * 1.5, 1.3)
		"a_sat":
			build.spawn_temp_familiar("sat", 8.0)
		"a_berserk":
			build.berserk_until = build.time + 6.0
			hud.screen_flash(Color("ff3a4a"), 0.3)
		"a_supply":
			for i in rng.randi_range(4, 6):
				drop(_room_reward(), p)
		"a_minions":
			for i in 2:
				var fm := build.spawn_temp_familiar("minion", 999.0)
				fm.kind = "minion"
		"a_chaos":
			var n := RogueRun.items.size()
			for old in RogueRun.items:
				RogueRun.seen[old] = true
			RogueRun.items.clear()
			for i in n:
				RogueRun.items.append(_roll_item("treasure", RogueItems.T.PASSIVE))
			build.recompute()
			hud.screen_flash(Color("ff9af0"), 0.4)
	build.recompute()
	return true


func _teleport_random() -> void:
	var cands: Array = []
	for r in rmap.rooms:
		if not r.slots.is_empty() and r.id != cur_room:
			cands.append(r.id)
	if cands.is_empty():
		return
	_teleport(rmap.room_center(cands[rng.randi_range(0, cands.size() - 1)]))


func _teleport_kind(kind: String) -> bool:
	var ids := rmap.rooms_of_kind(kind)
	if ids.is_empty():
		return false
	_teleport(rmap.room_center(ids[0]) + Vector3(0, 0, 2.5))
	return true


func use_pocket_item() -> void:
	if RogueRun.pocket.is_empty():
		return
	var pk: Dictionary = RogueRun.pocket
	RogueRun.pocket = {}
	if pk.kind == "pill":
		var ci := int(pk.id)
		var eff: String = RogueRun.pill_map[ci]
		RogueRun.pills_known[ci] = true
		var k := 2.0 if pk.get("horse", false) else 1.0
		_pill(eff, k)
		hud.banner(("큰 " if k > 1.0 else "") + RogueItems.pill_name(eff), Color("ff9ad0"), "알약 · " + RogueItems.PILL_COLORS[ci][0])
		print("ROGUE_PILL %s" % eff)
	else:
		var cid := str(pk.id)
		_card(cid)
		var cd := RogueItems.card(cid)
		hud.banner(cd[1], Color("ff9ad0"), cd[2])
		print("ROGUE_CARD %s" % cid)
	build.recompute()
	Sfx.play("charged", 0.0, -3.0)


func _pill(eff: String, k: float) -> void:
	match eff:
		"full_health": heal_red(24)
		"health_up":
			RogueRun.red_max = mini(RogueRun.RED_CAP, RogueRun.red_max + 2 * int(k))
			heal_red(2 * int(k))
		"health_down":
			RogueRun.red_max = maxi(2, RogueRun.red_max - 2)
			player.hp = mini(player.hp, RogueRun.red_max)
		"dmg_up": RogueRun.add_stat("dmg", 0.6 * k)
		"dmg_down": RogueRun.add_stat("dmg", -0.4 * k)
		"tears_up": RogueRun.add_stat("tears", 0.5 * k)
		"tears_down": RogueRun.add_stat("tears", -0.35 * k)
		"speed_up": RogueRun.add_stat("speed", 0.15 * k)
		"speed_down": RogueRun.add_stat("speed", -0.1 * k)
		"range_up": RogueRun.add_stat("range", 2.0 * k)
		"range_down": RogueRun.add_stat("range", -1.5 * k)
		"luck_up": RogueRun.add_stat("luck", 1.0 * k)
		"luck_down": RogueRun.add_stat("luck", -1.0 * k)
		"bombs": RogueRun.bombs = mini(99, RogueRun.bombs + 2 * int(k))
		"keys": RogueRun.keys = mini(99, RogueRun.keys + 2 * int(k))
		"coins":
			for i in 5 * int(k):
				drop("coin", player.global_position)
		"power":
			player.invuln = 6.0 * k
			build.room_dmg += 1.0
		"energy": _charge_active(99)
		"tele": _teleport_random()
		"vision":
			reveal_all = true
			reveal_special = true
		"blast":
			RogueEffects.explosion(player.global_position, 2.5, build.cur_dmg() * 2.0, false)


func _card(cid: String) -> void:
	var p := player.global_position
	match cid:
		"fool": _teleport(rmap.room_center(rmap.start_room))
		"magician": build.room_homing = true
		"emperor":
			if rmap.boss_room >= 0:
				_teleport(rmap.room_center(rmap.boss_room) + Vector3(0, 0, 4.0))
		"lovers":
			drop("heart", p)
			drop("heart", p)
		"chariot": player.invuln = 6.0
		"hermit":
			if not _teleport_kind("shop"):
				_teleport_random()
		"strength":
			build.room_dmg += 1.5
		"star":
			if not _teleport_kind("treasure"):
				_teleport_random()
		"moon":
			if rmap.island_secret >= 0:
				return_pos = p
				if get_tree().get_nodes_in_group("rogue_portals").filter(func(q): return q.kind == "back").is_empty():
					_portal("back", rmap.room_center(rmap.island_secret) + Vector3(0, 0, 4.5))
				_teleport(rmap.room_center(rmap.island_secret))
				reveal_secret = true
			else:
				_teleport_random()
		"sun":
			heal_red(24)
			reveal_all = true
			reveal_special = true
			RogueEffects.room_damage(30.0)
		"world":
			reveal_all = true
			reveal_special = true
		"justice":
			drop("coin", p)
			drop("bomb", p)
			drop("key", p)
		"death": RogueEffects.room_damage(40.0)
		"tower":
			for i in 6:
				var a := TAU * i / 6.0
				RogueBomb.spawn(self, p + Vector3(cos(a), 0, sin(a)) * 3.2)
		"hagalaz":
			for c in get_tree().get_nodes_in_group("rogue_crates") + get_tree().get_nodes_in_group("rogue_hearths"):
				if rmap.room_at(c.global_position) == cur_room:
					c.die()
		"berkano":
			for i in 3:
				build.spawn_temp_familiar("hunter", 20.0)
		"algiz":
			player.invuln = 10.0
			RogueRun.soul += 1


# ── 미니맵 정보 ─────────────────────────────────────────

## 0 모름 · 1 윤곽만(가 본 방 옆) · 2 보임 · 3 아이콘까지
func room_known(id: int) -> int:
	var r: Dictionary = rmap.rooms[id]
	if r.visited:
		return 3
	if reveal_all:
		return 3 if reveal_special else 2
	if reveal_special and r.kind not in ["normal", "start"]:
		return 3
	if reveal_boss and r.kind == "boss":
		return 3
	for n in r.nbr:
		if rmap.rooms[n].visited:
			return 1 if r.kind in ["normal", "start"] else 3
	return 0


func combat_rooms() -> int:
	return rmap.rooms.size() if rmap else 0


func enemies_left() -> int:
	return _room_enemies()


# ── 입력 ────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	var f5 := event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F5 and event.is_pressed()
	if f5 or (event.is_action_pressed("restart") and state != State.PLAY):
		Engine.time_scale = 1.0
		RogueRun.started = false
		get_tree().reload_current_scene()
	elif event.is_action_pressed("pause"):
		RogueRun.started = false
		Lobby.back(get_tree())
	elif event.is_action_pressed("rogue_info"):
		rhud.info_open = not rhud.info_open
	elif event.is_action_pressed("mute"):
		Sfx.inst.muted = not Sfx.inst.muted
	elif event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).physical_keycode == KEY_J:
		hud.banner("DAMAGE LOG  %s" % DamageLog.PRESET_NAMES[DamageLog.use()], Color(1, 0.9, 0.55), "J 키로 전환")


# ── 자동 플레이 (검증) ──────────────────────────────────

func _bot_explore(p: Player, out: Dictionary) -> Vector3:
	var dt := get_physics_process_delta_time()
	bot_path_t -= dt
	# 제자리걸음 감지: 4초 동안 1m 도 못 움직이면 그 목표를 포기한다
	_bot_stuck_t += dt
	if p.global_position.distance_to(_bot_last_pos) > 1.0:
		_bot_last_pos = p.global_position
		_bot_stuck_t = 0.0
	if bot_path_t <= 0.0 or bot_path.is_empty():
		bot_path_t = 0.5
		var goal := _bot_pick_goal(p)
		if goal == Vector3.INF and not _bot_ban.is_empty():
			_bot_ban.clear()
			goal = _bot_pick_goal(p)
		_bot_goal = goal
		bot_path.clear()
		if goal != Vector3.INF:
			bot_path = rmap.find_path(p.global_position, goal)
			if bot_path.is_empty() or _bot_stuck_t > 4.0:
				_bot_ban[_key(goal)] = true
				_bot_stuck_t = 0.0
	while bot_path.size() > 1 and bot_path[0].distance_to(p.global_position) < 1.1:
		bot_path.pop_front()
	if cmd_args.has("--dbg") and fmod(time, 2.0) < 0.017:
		print("DBG t=%.1f pos=%s room=%d live=%s goal=%s path=%d enemies=%d pend=%d/%d" % [time, p.global_position, cur_room, room_live.get(cur_room, "-"), _bot_goal, bot_path.size(), _room_enemies(), pending_spawns, pending_room])
	if bot_path.is_empty():
		return Vector3.ZERO
	var wp: Vector3 = bot_path[mini(1, bot_path.size() - 1)]
	var d := wp - p.global_position
	d.y = 0
	out.aim = p.global_position + d.normalized() * 4.0 + Vector3(0, 0.95, 0)
	return d.normalized()


func _key(v: Vector3) -> String:
	return "%d,%d" % [roundi(v.x), roundi(v.z)]


func _bot_pick_goal(p: Player) -> Vector3:
	if room_live.get(cur_room, "") == "active" or pending_room >= 0 and pending_room == cur_room:
		return rmap.room_center(cur_room) if pending_room == cur_room else Vector3.INF
	var best := Vector3.INF
	var bd := 1e9
	# 1. 지금 방의 무료 아이템 · 집을 수 있는 픽업
	for ped in get_tree().get_nodes_in_group("rogue_pedestals"):
		if ped.item_id == "" or ped.taken or ped.price > 0 or ped.heart_price > 0 or _bot_ban.has(_key(ped.global_position)):
			continue
		if rmap.room_at(ped.global_position) != cur_room:
			continue
		var d: float = ped.global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = ped.global_position
	if best != Vector3.INF:
		return best
	for pk in get_tree().get_nodes_in_group("rogue_pickups"):
		if pk.price > 0 or _bot_ban.has(_key(pk.global_position)) or rmap.room_at(pk.global_position) != cur_room:
			continue
		if (pk.kind == "heart" or pk.kind == "half_heart") and p.hp >= RogueRun.red_max:
			continue
		var d: float = pk.global_position.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = pk.global_position
	if best != Vector3.INF:
		return best
	# 2. 거래방 · 비밀방에서는 나가는 포털로
	var here := rmap.room_kind(rmap.room_at(p.global_position))
	if here == "deal" or here == "secret":
		for q in get_tree().get_nodes_in_group("rogue_portals"):
			if q.kind == "back" or q.kind == "deal_back":
				return q.global_position
	# 3. 안 가 본 방 (잠긴 방은 열쇠가 있을 때 문 앞으로)
	for r in rmap.rooms:
		if r.visited or r.slots.is_empty():
			continue
		var goal: Vector3 = rmap.room_center(r.id)
		if r.locked:
			if r.kind == "challenge" and p.hp < RogueRun.red_max:
				continue
			if r.kind != "challenge" and RogueRun.keys <= 0:
				continue
			if r.doors.is_empty():
				continue
			goal = rmap.world_of(r.doors[0][0] - r.doors[0][1])
		if r.kind == "boss" and _unvisited_normals() > 0 and time < 150.0:
			continue
		if _bot_ban.has(_key(goal)):
			continue
		var d := goal.distance_to(p.global_position)
		if d < bd:
			bd = d
			best = goal
	if best != Vector3.INF:
		return best
	# 4. 트랩도어
	if is_instance_valid(trapdoor):
		return trapdoor.global_position
	return Vector3.INF


func _unvisited_normals() -> int:
	var n := 0
	for r in rmap.rooms:
		if not r.visited and not r.slots.is_empty() and r.kind == "normal" and not _bot_ban.has(_key(rmap.room_center(r.id))):
			n += 1
	return n
