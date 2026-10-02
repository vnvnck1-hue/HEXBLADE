extends Main
## LAYER 01 · 심연 성소 (킬 나이트 분석을 바탕으로 만든 별도 테스트 씬).
## 하나의 부유 아레나에서 페이즈를 이어 간다: 웨이브를 정리할 때마다 땅이 움직여(판이 솟고 가라앉아)
## 전장 모양이 바뀌고, 더 많은 적과 새 함정이 들어온다. 마지막 두 페이즈는 중간보스 후광의 파수자.
##   1 강림       — 허스크 무리 (기어오르는 근접 잡몹)
##   2 날개 회랑   — 애가꽃 등장 · 체액 분출구
##   3 무너진 고리 — 가운데가 꺼진 고리 · 심판의 탑(쓸고 가는 레이어 레이저)
##   4 참회의 열주 — 기둥 엄폐물 · 갑각 참회자(허스크 호위) · 함정 둘 다
##   5 후광의 파수자 1페이즈 / 6 2페이즈(전장이 십자로 줄어든다)
## 처치하면 공명 결정이 떨어지고, 모으면 공명 단계(점수 배율)가 오른다. 맞으면 한 단계 떨어진다.
## 실행: abyss_battle.cmd · 인자 --phase=N (1~6 에서 시작) · --godmode · --nopost (후처리 끔)

const Stage := preload("res://scripts/abyss/abyss_stage.gd")
const Hazards := preload("res://scripts/abyss/abyss_hazards.gd")
const Post := preload("res://scripts/abyss/abyss_post.gd")
const AHud := preload("res://scripts/abyss/abyss_hud.gd")
const ACam := preload("res://scripts/abyss/abyss_camera.gd")
const Husk := preload("res://scripts/abyss/husk.gd")
const Lament := preload("res://scripts/abyss/lament.gd")
const Penitent := preload("res://scripts/abyss/penitent.gd")
const Shard := preload("res://scripts/abyss/shard.gd")
const Warden := preload("res://scripts/abyss/warden.gd")
const BossBar := preload("res://scripts/boss_bar.gd")

const PHASES := [
	{"layout": "descent", "title": "PHASE 1  ·  강림", "sub": "심연 가장자리를 기어오르는 허스크 무리",
		"quota": {"husk": 16}, "vents": false, "towers": false, "alive": 8},
	{"layout": "wings", "title": "PHASE 2  ·  날개 회랑", "sub": "애가꽃이 피어난다 · 끓어오르는 분출구를 피하라",
		"quota": {"husk": 14, "lament": 3}, "vents": true, "towers": false, "alive": 9},
	{"layout": "ring", "title": "PHASE 3  ·  무너진 고리", "sub": "심판의 탑이 깨어났다 · 붉은 예고선을 넘어라",
		"quota": {"husk": 12, "lament": 2, "penitent": 1}, "vents": false, "towers": true, "alive": 9},
	{"layout": "colonnade", "title": "PHASE 4  ·  참회의 열주", "sub": "갑각 참회자 — 정면 갑각은 탄을 튕긴다 · 등 뒤를 노려라",
		"quota": {"husk": 16, "lament": 3, "penitent": 2}, "vents": true, "towers": true, "alive": 10},
	{"layout": "sanctum", "title": "PHASE 5  ·  후광의 파수자", "sub": "심연의 감시 천사가 떠오른다", "boss": true,
		"quota": {}, "vents": false, "towers": false, "alive": 6},
]
const PHASE_COUNT := 6
## 공명 단계 문턱 (모은 결정 수)
const RES_STEPS := [0, 8, 20, 36, 56, 80]
const RES_MULT := 0.25            # 단계마다 점수 배율 +0.25

## 이 전장의 조명 기본값 (dramatic() 이 어두워졌다 되돌아올 값)
const SUN_E := 0.22
const AMB_E := 0.07
const BG := Color(0.035, 0.0, 0.012)

var stage: Stage
var hazards: Hazards
var post: Post
var ahud: AHud
var bar: BossBar
var boss: Warden
var key_light: SpotLight3D
var player_light: OmniLight3D
var phase := 0
var phase_state := "intro"        # intro · fight · clear · shift · boss · done
var phase_t := 0.0
var plan: Array = []              # 남은 소환 묶음 [["husk", n], ["lament", 1], ...]
var phase_total := 0
var phase_kills := 0
var spawning := 0                 # 소환 연출 중인 수
var group_t := 0.0
var res_points := 0
var res_level := 0
var shards_got := 0
var bot_orbit := 1.0
var start_phase := 0
var _dbg_f := 0
var _arg_godmode := false         # 실행 인자는 _ready 에서 한 번만 읽는다
var _arg_dbg := false
var _arg_perflog := false
var _left_t := 0.0                # 남은 적 표시 갱신 간격


func _ready() -> void:
	inst = self
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	randomize()
	_parse_args()
	var user_args := OS.get_cmdline_user_args()
	for a in user_args:
		if a.begins_with("--phase="):
			start_phase = clampi(int(a.substr(8)) - 1, 0, PHASE_COUNT - 1)
	_arg_godmode = user_args.has("--godmode")
	_arg_dbg = user_args.has("--dbg")
	_arg_perflog = user_args.has("--perflog")
	_setup_input()
	world = Node3D.new()
	add_child(world)
	FX.setup(world)
	AbyssFX.setup()
	add_child(Sfx.new())
	_build_environment()
	_abyss_lighting()
	stage = Stage.new()
	world.add_child(stage)
	# 조명과 같은 자리에 빛기둥 메시
	stage.props.shaft(Vector3(1.5, 34.0, 1.0), Vector3(0, -1.0, -1.0), 4.6, Color(0.8, 0.84, 0.95), 0.9)
	stage.props.shaft(Vector3(-16, 24, -12), Vector3(-7, -1.0, -5), 3.2, Color(1.0, 0.25, 0.32), 1.3)
	stage.props.shaft(Vector3(15, 26, -6), Vector3(7, -1.0, 4), 2.4, Color(0.6, 0.8, 1.0), 0.7)
	hazards = Hazards.new()
	hazards.stage = stage
	world.add_child(hazards)
	bullets = Node3D.new()
	add_child(bullets)

	player = Player.new()
	player.bot = capture_mode
	add_child(player)
	player.global_position = Vector3(0, 0, 2.0)
	player_light = OmniLight3D.new()
	player_light.light_color = Color(0.72, 0.82, 1.0)
	player_light.light_energy = 0.9
	player_light.omni_range = 7.5
	player_light.omni_attenuation = 1.4
	world.add_child(player_light)

	camera = ACam.new()
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
	hud.wave_label.visible = false
	hud.count_label.visible = false
	hud.minimap.visible = false
	var impact := ImpactFrame.new()
	impact.enabled = not OS.get_cmdline_user_args().has("--noimpact")
	add_child(impact)
	post = Post.new()
	add_child(post)
	ahud = AHud.new()
	ahud.phase_count = PHASE_COUNT
	add_child(ahud)
	bar = BossBar.new()
	add_child(bar)
	bar.root.visible = false
	if not capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	# 첫 배치: 시작 페이즈의 판을 바로 놓는다
	phase = start_phase
	var lay: String = "cross" if phase >= 5 else (PHASES[phase] as Dictionary).layout
	stage.apply_layout(lay, 0.0, true)
	player.global_position = stage.nearest_floor(player.global_position)
	phase_state = "intro"
	phase_t = 0.0
	hud.banner("LAYER 01", Color("ff4a5a"), "심연 성소 — 가라앉은 성소의 마지막 파수꾼에게로 내려간다")
	Sfx.play("twind", 0.0, -4.0)


## 심연 조명: 거의 꺼진 차가운 주광 · 낮은 주변광 · 진홍 안개 · 볼류메트릭 빛기둥 · 강한 발광
func _abyss_lighting() -> void:
	env.background_color = BG
	env.ambient_light_color = Color(0.36, 0.44, 0.52)
	env.ambient_light_energy = AMB_E
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0
	env.glow_intensity = 0.85
	env.glow_strength = 1.05
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.95
	env.set_glow_level(0, true)
	env.set_glow_level(2, true)
	env.set_glow_level(4, true)
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.01, 0.035)
	env.fog_light_energy = 1.0
	env.fog_density = 0.0016
	env.fog_sky_affect = 1.0
	env.fog_height = -3.0
	env.fog_height_density = 0.08
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0
	env.volumetric_fog_albedo = Color(0.6, 0.62, 0.66)
	env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 80.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.0
	# 안개 격자를 촘촘히: 바닥 근처에서 계단 무늬가 드러나지 않게 (전역 설정이라 _exit_tree 에서 되돌린다)
	RenderingServer.environment_set_volumetric_fog_volume_size(160, 128)
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 2.0
	env.ssao_intensity = 2.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.08
	var args := OS.get_cmdline_user_args()
	if args.has("--nossr"):
		env.ssr_enabled = false
	if args.has("--novol"):
		env.volumetric_fog_enabled = false
	if args.has("--nosunshadow"):
		sun.shadow_enabled = false
	if args.has("--nossao"):
		env.ssao_enabled = false
	sun.light_color = Color(0.6, 0.74, 0.92)
	sun.light_energy = SUN_E
	sun.rotation_degrees = Vector3(-58, -34, 0)
	sun.light_volumetric_fog_energy = 0.4
	sun.directional_shadow_max_distance = 60.0
	# 머리 위 틈으로 떨어지는 차가운 빛기둥 (전장 가운데를 둥글게 밝힌다)
	key_light = SpotLight3D.new()
	key_light.light_color = Color(0.86, 0.86, 0.94)
	key_light.shadow_bias = 0.08
	key_light.shadow_normal_bias = 1.5
	key_light.light_energy = 9.0
	key_light.spot_range = 46.0
	key_light.spot_angle = 17.0
	key_light.spot_angle_attenuation = 1.6
	key_light.spot_attenuation = 0.6
	key_light.light_volumetric_fog_energy = 0.9
	key_light.shadow_enabled = not OS.get_cmdline_user_args().has("--nokeyshadow")
	add_child(key_light)
	key_light.position = Vector3(1.5, 30.0, 3.0)
	key_light.look_at(Vector3(0, 0, 0), Vector3.FORWARD)
	# 비스듬히 떨어지는 가는 빛기둥 둘 (붉은 한 줄기 · 차가운 한 줄기)
	for spec in [[Vector3(-16, 24, -12), Vector3(-7, 0, -5), Color(1.0, 0.22, 0.3), 9.0, 13.0], [Vector3(15, 26, -6), Vector3(7, 0, 4), Color(0.6, 0.8, 1.0), 7.0, 11.0]]:
		var s := SpotLight3D.new()
		s.light_color = spec[2]
		s.light_energy = spec[3]
		s.spot_range = 44.0
		s.spot_angle = spec[4]
		s.spot_attenuation = 0.6
		s.light_volumetric_fog_energy = 1.4
		s.shadow_enabled = false
		add_child(s)
		s.position = spec[0]
		s.look_at(spec[1], Vector3.UP)


# ── 판정 보조 ───────────────────────────────────────────

func _exit_tree() -> void:
	super._exit_tree()
	# 안개 격자 크기는 렌더링 서버 전역 값: 다음 씬이 이 촘촘한 격자를 물려받지 않게 프로젝트 기본값으로 되돌린다
	RenderingServer.environment_set_volumetric_fog_volume_size(
		ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_size", 64),
		ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_depth", 64))


## 탄을 막는 것: 솟은 기둥과 아주 먼 경계뿐 (심연 위로는 탄이 날아가 수명으로 사라진다)
func is_blocked(p: Vector3) -> bool:
	if Vector2(p.x, p.z).length() > 60.0:
		return true
	return p.y < Stage.PILLAR_Y + 0.2 and stage.blocked(Stage.cell_of(p))


func push_out(p: Vector3, radius: float) -> Vector3:
	return stage.push_out(p, radius)


func floor_at(_p: Vector3) -> float:
	return 0.0


func combat_rooms() -> int:
	return PHASE_COUNT


func enemies_left() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


## 플레이어에게서 min_d 이상 떨어진 아무 바닥 칸 (애가꽃이 피어날 자리 등)
func random_floor_spot(min_d := 5.0, max_d := 99.0) -> Vector3:
	var cells := stage.floor_cells()
	cells.shuffle()
	for c in cells:
		var p := Stage.cell_center(c)
		var d := p.distance_to(Vector3(player.global_position.x, 0, player.global_position.z))
		if d >= min_d and d <= max_d:
			return p + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
	return Stage.cell_center(cells[0]) if not cells.is_empty() else Vector3.ZERO


func dramatic(on: bool) -> void:
	if _dark_tw:
		_dark_tw.kill()
	_dark_tw = create_tween().set_parallel(true)
	var d := 0.1 if on else 0.6
	_dark_tw.tween_property(sun, "light_energy", 0.03 if on else SUN_E, d)
	_dark_tw.tween_property(key_light, "light_energy", 1.0 if on else 9.0, d)
	_dark_tw.tween_property(env, "ambient_light_energy", 0.03 if on else AMB_E, d)
	_dark_tw.tween_property(env, "glow_intensity", 1.2 if on else 0.85, d)
	if on:
		ImpactFrame.inst.after(hud.screen_flash.bind(Color(0.85, 1.0, 1.0), 0.5))


# ── 페이즈 진행 ─────────────────────────────────────────

func _phase_def() -> Dictionary:
	return PHASES[mini(phase, PHASES.size() - 1)]


func _begin_phase() -> void:
	var pd := _phase_def()
	phase_state = "boss" if pd.get("boss", false) else "fight"
	phase_t = 0.0
	phase_kills = 0
	plan.clear()
	phase_total = 0
	var q: Dictionary = pd.quota
	var husks: int = q.get("husk", 0)
	phase_total = husks + int(q.get("lament", 0)) + int(q.get("penitent", 0))
	# 참회자는 허스크 셋을 호위로 데리고 온다 (킬 나이트: 잡몹이 단단한 적을 에워싼다)
	for i in int(q.get("penitent", 0)):
		plan.append(["penitent", 1])
		var esc := mini(3, husks)
		if esc > 0:
			plan.append(["husk", esc, "escort"])
			husks -= esc
	for i in int(q.get("lament", 0)):
		plan.append(["lament", 1])
	while husks > 0:
		var n := mini(husks, randi_range(3, 5))
		plan.append(["husk", n])
		husks -= n
	# 호위는 섞기 전에 따로 빼 두었다가 참회자 뒤에 다시 붙인다
	var escorts: Array = plan.filter(func(g): return g.size() > 2)
	plan = plan.filter(func(g): return g.size() <= 2)
	plan.shuffle()
	# 첫 묶음은 언제나 허스크 (페이즈 시작을 바로 몰아친다)
	for i in plan.size():
		if plan[i][0] == "husk":
			var first = plan[i]
			plan.remove_at(i)
			plan.push_front(first)
			break
	# 참회자 뒤에는 호위를 바로 붙인다
	var fixed: Array = []
	for g in plan:
		fixed.append(g)
		if g[0] == "penitent" and not escorts.is_empty():
			fixed.append(escorts.pop_front())
	fixed.append_array(escorts)
	plan = fixed
	group_t = 0.4
	hazards.set_vents(pd.vents)
	hazards.set_towers(pd.towers)
	ahud.phase = phase
	ahud.phase_name = pd.title
	ahud.trap_text = _trap_text(pd)
	hud.banner(pd.title.replace("  ·  ", "\n").split("\n")[0], Color("ff4a5a"), "%s  ·  %s" % [pd.title.split("·")[1].strip_edges(), pd.sub])
	print("PHASE %d %s layout=%s total=%d t=%.1f hp=%d" % [phase + 1, phase_state, stage.layout, phase_total, time, player.hp])
	Sfx.play("charged", 0.0, -2.0)
	if phase_state == "boss":
		_spawn_boss()


## 확인 모드 (--foeshow): 플레이어 앞에 허스크 · 애가꽃 · 참회자를 세워 두고 쏘지 않고 관찰한다
func _begin_foe_show() -> void:
	phase_state = "show"
	player.invuln = 999.0
	hazards.set_vents(true)
	var p := player.global_position
	for spec in [[Husk, Vector3(-3.0, 0, -3.5)], [Lament, Vector3(0.5, 0, -5.0)], [Penitent, Vector3(3.5, 0, -3.0)], [Husk, Vector3(-1.5, 0, -6.5)]]:
		var e: Enemy = (spec[0] as GDScript).new()
		e.hp = 9999
		_spawn_enemy(e, stage.push_out(p + spec[1], 0.6))
	ahud.phase_name = "FOE SHOW · 적 확인"


func _trap_text(pd: Dictionary) -> String:
	var t: Array[String] = []
	if pd.vents:
		t.append("분출구")
	if pd.towers:
		t.append("심판의 탑")
	return " · ".join(t)


func _phase_clear() -> void:
	phase_state = "clear"
	phase_t = 0.0
	print("PHASE_CLEAR %d t=%.1f hp=%d res=%d" % [phase + 1, time, player.hp, res_level])
	hazards.set_vents(false)
	hazards.set_towers(false)
	if player.hp < Player.MAX_HP:
		player.hp += 1
	FX.shockwave(player.global_position, Color("ff4a5a"), 4.0, 0.5)
	hud.banner("PHASE CLEAR", Color(1.0, 0.75, 0.78), "땅이 움직인다 · 체력 +1")
	Sfx.play("charged", 0.0, 0.0)
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		FX.flash(b.position, AbyssFX.ICHOR_HOT, 0.3, 0.08)
		b.queue_free()


func _shift_to_next() -> void:
	phase += 1
	phase_state = "shift"
	phase_t = 0.0
	var lay: String = _phase_def().layout
	stage.apply_layout(lay, 1.4)
	Main.inst.shake(0.35)


func _update_phase(dt: float) -> void:
	phase_t += dt
	match phase_state:
		"intro":
			if OS.get_cmdline_user_args().has("--foeshow"):
				_begin_foe_show()
			elif phase_t > 1.6:
				_begin_phase()
		"show":
			pass
		"fight":
			_update_spawns(dt)
			if plan.is_empty() and spawning == 0 and phase_kills >= phase_total and enemies_left() == 0:
				_phase_clear()
		"clear":
			if phase_t > 1.8:
				_shift_to_next()
		"shift":
			(camera as ACam).reveal = 1.0
			if phase_t > 0.6 and stage.shift_t <= 0.0:
				(camera as ACam).reveal = 0.0
				_begin_phase()
		"boss":
			_update_boss_adds(dt)


func _update_spawns(dt: float) -> void:
	group_t -= dt
	if group_t > 0.0 or plan.is_empty() or state != State.PLAY:
		return
	var alive := enemies_left() + spawning
	var cap: int = _phase_def().alive
	var g: Array = plan[0]
	var n: int = g[1]
	if alive + n > cap and alive > 0:
		return
	plan.pop_front()
	group_t = randf_range(1.0, 1.8)
	spawn_group(g[0], n)


## 묶음 소환: 허스크는 한 가장자리에서 줄줄이 기어오르고, 애가꽃은 문양에서, 참회자는 위에서 떨어진다
func spawn_group(kind: String, n: int) -> void:
	match kind:
		"husk":
			var spots := stage.edge_spots()
			if spots.is_empty():
				phase_total -= n          # 못 나온 만큼 목표에서 빼야 페이즈가 끝난다
				return
			# 플레이어에게서 너무 가깝지 않은 가장자리 한 곳을 고르고, 그 이웃 가장자리에서 나온다
			spots.shuffle()
			var pick: Dictionary = spots[0]
			for s in spots:
				if Stage.cell_center(s.cell).distance_to(player.global_position) > 6.0:
					pick = s
					break
			var origin := Stage.cell_center(pick.cell)
			spots.sort_custom(func(a, b): return Stage.cell_center(a.cell).distance_to(origin) < Stage.cell_center(b.cell).distance_to(origin))
			for i in n:
				var sp: Dictionary = spots[mini(i, spots.size() - 1)]
				_delayed_husk(sp, 0.18 * i)
		"lament":
			_spawn_enemy(Lament.new(), random_floor_spot(6.0))
		"penitent":
			var p := random_floor_spot(4.5, 11.0)
			spawning += 1
			var w := AbyssFX.warn_disc(p, 1.6, Color(1.0, 0.4, 0.3))
			var tw := w.create_tween()
			tw.tween_method(func(v: float): AbyssFX.set_warn(w, v), 0.0, 1.0, 0.8)
			tw.tween_callback(func():
				w.queue_free()
				spawning -= 1
				if state != State.LOSE:
					_spawn_enemy(Penitent.new(), p))


func _delayed_husk(sp: Dictionary, delay: float) -> void:
	spawning += 1
	# 기어오르기 전 가장자리 아래에서 붉은 눈이 번뜩인다
	var edge := Stage.cell_center(sp.cell) + (sp.out as Vector3) * 1.15
	get_tree().create_timer(delay, false).timeout.connect(func():
		FX.flash(edge + Vector3(0, -1.0, 0), AbyssFX.ICHOR_HOT, 0.35, 0.25)
		FX.sparks(edge + Vector3(0, -0.4, 0), 3, [AbyssFX.ICHOR_HOT, Color(0.4, 0.3, 0.3)], 2.0, 0.3, -6.0, 0.05))
	get_tree().create_timer(delay + 0.35, false).timeout.connect(func():
		spawning -= 1
		if state == State.LOSE:
			return
		if not stage.walkable(sp.cell):
			# 그 사이 판이 가라앉았다: 이 허스크는 나오지 않으니 목표 수에서 뺀다 (안 빼면 페이즈가 끝나지 않는다)
			phase_total -= 1
			return
		var h := Husk.new()
		h.spawn_info = sp
		world.add_child(h))


func _spawn_enemy(e: Enemy, p: Vector3) -> void:
	e.position = p
	world.add_child(e)
	e.global_position = p


# ── 중간보스 ────────────────────────────────────────────

func _spawn_boss() -> void:
	boss = Warden.new()
	boss.stage = stage
	boss.bar = bar
	world.add_child(boss)
	(camera as ACam).boss = boss
	bar.name_label.text = "HALO WARDEN  ·  후광의 파수자"
	bar.root.visible = true
	bar.appear()
	ahud.top = 92.0
	boss.phase_changed.connect(_on_boss_phase)
	boss.defeated.connect(_on_boss_defeated)
	if start_phase >= 5:
		boss.skip_to_phase2 = true


func _on_boss_phase(p: int) -> void:
	if p == 2:
		ahud.phase = 5
		ahud.phase_name = "PHASE 6  ·  무너지는 성소"
		ahud.trap_text = "분출구"
		stage.apply_layout("cross", 1.2)
		hazards.set_vents(true)
		print("BOSS_PHASE2 t=%.1f hp=%d" % [time, player.hp])


func _update_boss_adds(_dt: float) -> void:
	if boss and boss.alive:
		boss_loot(boss, boss.boss_hp / Warden.MAX_HP)


func _on_boss_defeated() -> void:
	print("BOSS_DOWN t=%.1f hp=%d" % [time, player.hp])
	hazards.set_vents(false)
	hazards.set_towers(false)
	get_tree().create_timer(2.2, false).timeout.connect(_win)


# ── 처치 · 공명 ─────────────────────────────────────────

func on_enemy_killed(e: Enemy) -> void:
	super.on_enemy_killed(e)
	if e.is_boss:
		return
	phase_kills += 1
	# 공명 배율만큼 점수를 더 얹는다
	score += int(100 * combo * (res_mult() - 1.0))
	var n := 1
	if e is Lament:
		n = 3
	elif e is Penitent:
		n = 6
	for i in n:
		var s := Shard.new()
		s.position = e.global_position + Vector3(0, 0.6, 0)
		world.add_child(s)


func _drop_loot(e: Enemy) -> void:
	var pos := e.global_position
	var m := 0.1
	var en := 0.08
	if e is Lament:
		m = 0.4
		en = 0.3
	elif e is Penitent:
		m = 1.0
		en = 0.6
	if randf() < m:
		drop_pickup("missile", pos)
	if randf() < en:
		drop_pickup("energy", pos)


func res_mult() -> float:
	return 1.0 + res_level * RES_MULT


func on_shard(v: int) -> void:
	res_points += v
	shards_got += v
	var lv := 0
	for i in RES_STEPS.size():
		if res_points >= RES_STEPS[i]:
			lv = i
	if lv > res_level:
		res_level = lv
		ahud.flash_res()
		hud.popup("RESONANCE %d" % lv, Color(0.5, 1.0, 0.85), player.global_position + Vector3(0, 2.4, 0))
		FX.shockwave(player.global_position, Color(0.3, 1.0, 0.72), 2.4, 0.3, 0.05)
		Sfx.play("charged", 0.1, -6.0)
	_res_hud()


func _res_hud() -> void:
	ahud.res_level = res_level
	ahud.res_mult = res_mult()
	if res_level >= RES_STEPS.size() - 1:
		ahud.res_k = 1.0
	else:
		var a: int = RES_STEPS[res_level]
		var b: int = RES_STEPS[res_level + 1]
		ahud.res_k = clampf(float(res_points - a) / float(b - a), 0.0, 1.0)


func on_player_hurt() -> void:
	super.on_player_hurt()
	post.kick(1.0)
	# 맞으면 공명이 한 단계 떨어진다
	if res_level > 0:
		res_level -= 1
		res_points = RES_STEPS[res_level]
		hud.popup("RESONANCE ↓", Color(1.0, 0.4, 0.45), player.global_position + Vector3(0, 2.4, 0))
	else:
		res_points = 0
	_res_hud()


func on_rupture(_p: Vector3) -> void:
	post.kick(0.7)


# ── 매 프레임 ───────────────────────────────────────────

func _physics_process(dt: float) -> void:
	time += dt
	if combo > 0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 0
	if _arg_godmode:
		player.invuln = 999.0
	if state == State.PLAY:
		_update_phase(dt)
	# 남은 적 표시는 0.1초마다만 센다 (그룹 조회를 매 프레임 하지 않게)
	_left_t -= dt
	if _left_t <= 0.0:
		_left_t = 0.1
		ahud.left = enemies_left() + spawning + _plan_left() if phase_state == "fight" else 0
	if player.alive:
		player.global_position = stage.push_out(player.global_position, 0.4)
	player_light.global_position = player.global_position + Vector3(0, 2.6, 0.6)
	_dbg_f += 1
	if _arg_dbg and _dbg_f % 180 == 0:
		var names := []
		for e in get_tree().get_nodes_in_group("enemies"):
			names.append("%s@%s%s" % [(e as Node).get_script().resource_path.get_file().get_basename(), str(Vector2i((e as Node3D).global_position.x, (e as Node3D).global_position.z)), "" if (e as Enemy).landed else "(air)"])
		print("DBG t=%.1f ts=%.2f ult=%s st=%s kills=%d/%d spawning=%d plan=%d enemies=%s" % [time, Engine.time_scale, player.ult_aiming, phase_state, phase_kills, phase_total, spawning, plan.size(), names])
	if _arg_perflog and fmod(time, 10.0) < dt:
		print("PERF t=%.0f fps=%d nodes=%d objs=%d orphans=%d mem=%.1fMB bullets=%d draw=%d" % [time,
			Performance.get_monitor(Performance.TIME_FPS), Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_COUNT), Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			bullets.get_child_count(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


func _plan_left() -> int:
	var n := 0
	for g in plan:
		n += int(g[1])
	return n


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).physical_keycode == KEY_P:
		hud.banner("POST FX  %s" % ("ON" if post.toggle() else "OFF"), Color(1, 1, 1), "색수차 · 그레인 · 비네트 · 분할 톤")
		return
	super._unhandled_input(event)


func _win() -> void:
	state = State.WIN
	phase_state = "done"
	print("WIN t=%.1f score=%d res=%d" % [time, score, res_level])
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		FX.flash(b.position, AbyssFX.ICHOR_HOT, 0.4, 0.1)
		b.queue_free()
	bar.hide_bar()
	ahud.phase = PHASE_COUNT
	ahud.phase_name = "LAYER CLEAR"
	stage.apply_layout("last", 1.0)
	var tw := create_tween()
	tw.tween_property(stage, "heat", 1.5, 2.5)
	FX.victory(player.global_position)
	player.celebrate()
	Sfx.play("win", 0.0)
	hud.message("LAYER 01 CLEARED", "%.1f초 · 점수 %d · 공명 %d · 결정 %d · 최대 %d 콤보 · R 키로 다시 내려가기" % [time, score, res_level, shards_got, best_combo], Color("ff7080"))


# ── 자동 플레이 (검증용) ─────────────────────────────────

func bot_input(p: Player) -> Dictionary:
	var out := {"move": Vector3.ZERO, "aim": p.global_position - Vector3(0, 0, 3), "fire": false, "slash": false, "dash": false, "charge": false, "boost": false, "jump": false, "ult": false}
	var pp := Vector3(p.global_position.x, 0, p.global_position.z)
	var dt := get_physics_process_delta_time()
	if phase_state == "show":
		# 확인 모드: 제자리에서 천천히 원을 그리며 조준만 한다
		var a := time * 0.5
		out.move = Vector3(cos(a), 0, sin(a)) * 0.25
		out.aim = pp + Vector3(0, 0.95, -4.0)
		return out
	bot_dash_cd -= dt
	var best: Enemy = null
	var bd := 1e9
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.landed or not en.alive:
			continue
		var d := en.global_position.distance_to(pp)
		if en.is_boss:
			d += 4.0
		if d < bd:
			bd = d
			best = en
	var move := Vector3.ZERO
	if best:
		out.aim = best.global_position + Vector3(0, 0.95, 0)
		out.fire = true
		var to := best.global_position - pp
		to.y = 0
		var n := to.normalized()
		if fmod(time, 5.0) < 0.02:
			bot_orbit = -bot_orbit
		move += Vector3(-n.z, 0, n.x) * bot_orbit * 0.8
		var want := 5.5 if not best.is_boss else 9.0
		if bd > want + 1.5:
			move += n * 0.8
		elif bd < want - 1.5:
			move -= n * 0.9
		# 참회자는 옆으로 돌아 등 뒤를 노린다
		if best is Penitent:
			var f := (best as Node3D).global_basis.z * -1.0
			f.y = 0
			if f.normalized().dot(-n) > 0.3:
				move += Vector3(-n.z, 0, n.x) * bot_orbit * 1.2
		out.slash = bd < 2.6 and fmod(time, 0.3) < 0.03
		if fmod(time, 6.0) > 4.8:
			out.charge = true
			out.fire = false
		out.ult = p.missiles >= 3 and fmod(time, 9.0) < 0.05 and (get_tree().get_nodes_in_group("enemies").size() >= 5 or best.is_boss)
	else:
		move += (Vector3.ZERO - pp).limit_length(1.0) * 0.5
	# 가장자리 피하기: 둘레 칸 중 빈칸이 가까우면 안쪽으로
	for dv in [Vector3(1.4, 0, 0), Vector3(-1.4, 0, 0), Vector3(0, 0, 1.4), Vector3(0, 0, -1.4)]:
		if not stage.on_floor(pp + dv):
			move -= dv.normalized() * 0.6
	# 함정 · 보스 위험
	var threats: Array = hazards.threats()
	if boss and boss.alive:
		threats.append_array(boss.get_threats())
	for th in threats:
		match th.type:
			"circle":
				var rel: Vector3 = pp - Vector3(th.pos.x, 0, th.pos.z)
				if rel.length() < float(th.r) + 0.9:
					move += (rel.normalized() if rel.length() > 0.1 else Vector3.BACK) * 2.4
			"beam":
				var o: Vector3 = th.origin
				var a: float = th.a
				var d := Vector3(cos(a), 0, sin(a))
				var rel := pp - Vector3(o.x, 0, o.z)
				var along := clampf(rel.dot(d), 0.0, float(th.len))
				var off := rel - d * along
				var danger := float(th.half) + (2.6 if th.get("sweep", false) else 1.4)
				if off.length() < danger:
					var side := off.normalized() if off.length() > 0.05 else Vector3(-d.z, 0, d.x)
					if th.get("sweep", false):
						# 쓸고 오는 빔: 빔이 다가오는 쪽이면 대시로 뚫고 지나간다
						var a1: float = th.a1
						var pa := atan2(rel.z, rel.x)
						var ahead := signf(angle_difference(a, a1))
						var gap := angle_difference(a, pa) * ahead
						if gap > 0.0 and gap < 0.12 and bot_dash_cd <= 0.0:
							out.dash = true
							out.move = -side
							bot_dash_cd = 0.7
							return out
					move += side * 3.0
	# 탄 회피
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		var rel := pp - Vector3(bl.position.x, 0, bl.position.z)
		var l := rel.length()
		if l < 2.4 and bl.vel.dot(rel) > 0:
			var side := Vector3(-bl.vel.z, 0, bl.vel.x).normalized()
			if side.dot(rel) < 0:
				side = -side
			move += side * (2.4 - l) * 1.2
			if l < 1.2 and bot_dash_cd <= 0.0 and randf() < 0.5:
				out.dash = true
				bot_dash_cd = 0.9
	# 패링
	if Parry.inst and Parry.inst.best_threat() != null:
		out.dash = true
	out.move = move.limit_length(1.0)
	return out
