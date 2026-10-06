extends Main
## 거미 보스 전용 테스트 씬 · SHAFT 07 — SHIPWRIGHT (본편과 따로 실행, 나중에 이식할 수 있게 scripts/spider/ 에 모두 모았다)
## 높은 벽으로 밀폐된 넓은 갱도. 보스는 벽과 구멍, 끝없이 솟은 기둥 사이를 오가며 공격한다.
##  - 거미줄: 바닥에 떨어진 거미줄 판 위는 느려지고(감속 지대), 직격하면 칭칭 감겨 크게 느려진다. 대시(Space)로 끊는다.
##  - 새끼 거미: 산란 · 굴에서 몰려나온다. 처치하면 가끔 미사일 · 에너지를 떨어뜨린다.
## 실행: launchers/scenes/spider_boss.cmd · 인자 --phase2 (2페이즈부터) · --godmode · --show (공격 없이 돌아다니는 모습만 관찰) · --bot

const Stage := preload("res://scripts/spider/spider_stage.gd")
const Boss := preload("res://scripts/spider/spider_boss.gd")
const SCam := preload("res://scripts/spider/spider_camera.gd")
const BossBar := preload("res://scripts/boss_bar.gd")

const WEB_SLOW := 0.5          # 거미줄 판 위 속도 배율
const WRAP_SLOW := 0.28        # 직격으로 감겼을 때
const WRAP_TIME := 2.4

var stage: Stage
var boss: Boss
var bar: BossBar
var player_light: OmniLight3D
var alarm_lights: Array = []
var shaft_lights: Array = []
var web_t := 0.0               # 감김 남은 시간
var web_k := 0.0               # 지금 감속 정도 (0~1, 연출용)
var wrap: Node3D               # 플레이어를 감은 거미줄 고리
var web_label: Label
var _was_dashing := false
var _dbg_f := 0
var bot_orbit := 1.0
var _arg_godmode := false      # 실행 인자는 _ready 에서 한 번만 읽는다
var _arg_dbg := false
var _arg_perflog := false


func _ready() -> void:
	inst = self
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	randomize()
	_parse_args()
	var user_args := OS.get_cmdline_user_args()
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
	_shaft_lighting()
	stage = Stage.new()
	world.add_child(stage)
	bullets = Node3D.new()
	add_child(bullets)

	player = Player.new()
	player.bot = capture_mode
	add_child(player)
	player.global_position = Vector3(0, 0, 12.0)
	player_light = OmniLight3D.new()
	player_light.light_color = Color(0.75, 0.85, 1.0)
	player_light.light_energy = 1.1
	player_light.omni_range = 8.0
	player_light.omni_attenuation = 1.4
	world.add_child(player_light)

	camera = SCam.new()
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
	hud.wave_label.visible = false
	hud.count_label.visible = false
	hud.minimap.visible = false
	var impact := ImpactFrame.new()
	impact.enabled = not OS.get_cmdline_user_args().has("--noimpact")
	add_child(impact)
	bar = BossBar.new()
	add_child(bar)
	bar.root.visible = false
	_build_web_ui()
	if not capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_spawn_boss()
	hud.banner("SHAFT 07", Color("6ad8ff"), "버려진 건조 갱도 — 벽 속에서 무언가가 기어 다닌다")
	Sfx.play("twind", 0.0, -6.0)


## 갱도 조명: 어둡고 차가운 바탕 · 위에서 떨어지는 빛기둥 · 벽등 · 볼류메트릭 안개 (보스의 탐조등이 안개를 가른다)
func _shaft_lighting() -> void:
	env.background_color = Color(0.004, 0.006, 0.011)
	env.ambient_light_color = Color(0.42, 0.52, 0.66)
	env.ambient_light_energy = 0.16
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.15
	env.tonemap_white = 6.0
	env.glow_intensity = 0.8
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.set_glow_level(0, true)
	env.set_glow_level(2, true)
	env.set_glow_level(4, true)
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.03, 0.045)
	env.fog_light_energy = 1.0
	env.fog_density = 0.009
	env.fog_sky_affect = 1.0
	env.volumetric_fog_enabled = not OS.get_cmdline_user_args().has("--novol")
	env.volumetric_fog_density = 0.014
	env.volumetric_fog_albedo = Color(0.62, 0.7, 0.8)
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_length = 70.0
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = 0.0
	# 안개 격자 크기는 전역 값이라 앞 씬(심연 성소의 촘촘한 격자)이 남긴 값을 프로젝트 기본값으로 맞춘다
	RenderingServer.environment_set_volumetric_fog_volume_size(
		ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_size", 64),
		ProjectSettings.get_setting("rendering/environment/volumetric_fog/volume_depth", 64))
	env.ssao_intensity = 2.0
	env.ssr_enabled = true
	env.ssr_max_steps = 40
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.05
	sun.light_color = Color(0.62, 0.74, 0.92)
	sun.light_energy = 0.32
	sun.rotation_degrees = Vector3(-68, 22, 0)
	sun.light_volumetric_fog_energy = 0.3
	sun.directional_shadow_max_distance = 70.0
	# 천장 틈으로 떨어지는 빛기둥 (기둥 사이 바닥을 둥글게 밝힌다)
	for spec in [[Vector3(-8, 70, -6), Vector3(-8, 0, -4), 11.0, 26.0], [Vector3(9, 70, 2), Vector3(9, 0, 3), 9.0, 22.0], [Vector3(-2, 70, 9), Vector3(-1, 0, 10), 8.0, 16.0], [Vector3(20, 70, -16), Vector3(19, 0, -15), 7.0, 18.0]]:
		var s := SpotLight3D.new()
		s.light_color = Color(0.72, 0.84, 1.0)
		s.light_energy = spec[3]
		s.spot_range = 90.0
		s.spot_angle = spec[2]
		s.spot_angle_attenuation = 1.5
		s.spot_attenuation = 0.4
		s.light_volumetric_fog_energy = 1.4
		s.shadow_enabled = shaft_lights.size() < 2
		s.shadow_bias = 0.1
		add_child(s)
		s.position = spec[0]
		s.look_at(spec[1], Vector3.FORWARD)
		shaft_lights.append(s)
	# 벽등: 나트륨빛 작은 등이 벽 아래쪽을 군데군데 비춘다
	var lamp_m := StandardMaterial3D.new()
	lamp_m.albedo_color = Color(1.0, 0.62, 0.28)
	lamp_m.emission_enabled = true
	lamp_m.emission = Color(1.0, 0.6, 0.25)
	lamp_m.emission_energy_multiplier = 4.0
	var lamp_b := BoxMesh.new()
	lamp_b.size = Vector3(0.7, 0.3, 0.3)
	for w in ["N", "E", "W"]:
		var half := Stage.wall_half(w)
		var u := -half + 6.0
		while u < half - 4.0:
			var skip := false
			for i in Stage.HOLES.size():
				if Stage.in_opening(i, w, u, 5.0, -2.5):
					skip = true
			if not skip:
				var n := Stage.wall_n(w)
				var lp := Stage.wall_point(w, u, 5.2) + n * 0.2
				var mi := MeshInstance3D.new()
				mi.mesh = lamp_b
				mi.material_override = lamp_m
				world.add_child(mi)
				mi.global_position = lp
				mi.look_at(lp + n, Vector3.UP)
				var ol := OmniLight3D.new()
				ol.light_color = Color(1.0, 0.62, 0.32)
				ol.light_energy = 1.4
				ol.omni_range = 9.0
				ol.omni_attenuation = 1.3
				world.add_child(ol)
				ol.global_position = lp + n * 1.0 - Vector3(0, 0.5, 0)
			u += 11.0
	# 2페이즈 경보등 (평소 꺼짐): 벽 위쪽에서 도는 붉은 회전등
	for spec in [Vector3(-Stage.HX + 1.0, 14.0, -8.0), Vector3(Stage.HX - 1.0, 14.0, 4.0), Vector3(6.0, 16.0, -Stage.HZ + 1.0), Vector3(-14.0, 16.0, -Stage.HZ + 1.0)]:
		var s := SpotLight3D.new()
		s.light_color = Color(1.0, 0.12, 0.08)
		s.light_energy = 0.0
		s.spot_range = 50.0
		s.spot_angle = 22.0
		s.light_volumetric_fog_energy = 2.0
		s.shadow_enabled = false
		add_child(s)
		s.position = spec
		alarm_lights.append(s)


func _build_web_ui() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 5
	add_child(cl)
	web_label = Label.new()
	web_label.text = "거미줄에 묶였다 — SPACE 대시로 끊어라"
	web_label.add_theme_font_size_override("font_size", 22)
	web_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	web_label.add_theme_color_override("font_outline_color", Color(0, 0.05, 0.1))
	web_label.add_theme_constant_override("outline_size", 6)
	web_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	web_label.position = Vector2(-220, -150)
	web_label.size = Vector2(440, 40)
	web_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	web_label.visible = false
	cl.add_child(web_label)
	# 감긴 거미줄 고리 (플레이어를 따라다닌다)
	wrap = Node3D.new()
	world.add_child(wrap)
	var silk := StandardMaterial3D.new()
	silk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	silk.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	silk.albedo_color = Color(0.9, 0.96, 1.0, 0.7)
	silk.emission_enabled = true
	silk.emission = Color(0.8, 0.95, 1.0)
	silk.emission_energy_multiplier = 0.6
	for k in 6:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.42 + k * 0.03
		tm.outer_radius = tm.inner_radius + 0.035
		tm.rings = 18
		tm.ring_segments = 4
		var mi := MeshInstance3D.new()
		mi.mesh = tm
		mi.material_override = silk
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wrap.add_child(mi)
		mi.position = Vector3(0, 0.35 + k * 0.2, 0)
		mi.rotation = Vector3(randf_range(-0.5, 0.5), randf() * TAU, randf_range(-0.5, 0.5))
	wrap.visible = false


func _spawn_boss() -> void:
	boss = Boss.new()
	boss.stage = stage
	boss.bar = bar
	world.add_child(boss)
	(camera as SCam).boss = boss
	bar.name_label.text = "SHIPWRIGHT  ·  수선공 거미"
	bar.root.visible = true
	bar.appear()
	boss.phase_changed.connect(_on_boss_phase)
	boss.defeated.connect(_on_boss_defeated)
	boss.revealed.connect(func(at: Vector3, kind: String): (camera as SCam).reveal(at, kind))
	var args := OS.get_cmdline_user_args()
	if args.has("--phase2"):
		boss.skip_to_phase2 = true
	if args.has("--show"):
		boss.show_mode = true
		player.invuln = 999.0


func _on_boss_phase(p: int) -> void:
	if p != 2:
		return
	print("SPIDER_PHASE2 t=%.1f hp=%d" % [time, player.hp])
	var tw := create_tween().set_parallel(true)
	tw.tween_property(stage, "alarm", 1.0, 1.2)
	for s in alarm_lights:
		tw.tween_property(s, "light_energy", 9.0, 1.0)
	tw.tween_property(env, "ambient_light_color", Color(0.6, 0.4, 0.42), 1.5)


func _on_boss_defeated() -> void:
	print("SPIDER_DOWN t=%.1f hp=%d" % [time, player.hp])
	stage.clear_webs()
	for e in get_tree().get_nodes_in_group("enemies"):
		if (e as Enemy).alive:
			(e as Enemy).take_hit(99, Vector3.FORWARD, (e as Node3D).global_position, "bullet")
	get_tree().create_timer(1.6, false).timeout.connect(_win)


# ── 판정 보조 ───────────────────────────────────────────

func is_blocked(p: Vector3) -> bool:
	return stage.is_blocked(p)


func push_out(p: Vector3, radius: float) -> Vector3:
	return stage.push_out(p, radius)


func floor_at(_p: Vector3) -> float:
	return 0.0


func combat_rooms() -> int:
	return 1


func enemies_left() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


## 거미줄 직격: 플레이어가 감긴다
func web_player(strength := 1.0) -> void:
	if not player.alive or player.dash_t > 0.0:
		return
	var was := web_t > 0.0
	web_t = maxf(web_t, WRAP_TIME * strength)
	if not was:
		hud.popup("WEBBED", Color(0.8, 0.95, 1.0), player.global_position + Vector3(0, 2.3, 0))
		Sfx.play("powerdown", 0.1, -8.0)
		print("PLAYER_WEBBED t=%.1f" % time)


func web_patch(at: Vector3, r: float) -> void:
	stage.add_web(at, r)


# ── 매 프레임 ───────────────────────────────────────────

func _physics_process(dt: float) -> void:
	time += dt
	if combo > 0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 0
	if _arg_godmode:
		player.invuln = 999.0
	if boss and boss.alive:
		boss_loot(boss, boss.boss_hp / Boss.MAX_HP)
	_update_web(dt)
	if player.alive:
		player.global_position = stage.push_out(player.global_position, 0.4)
	player_light.global_position = player.global_position + Vector3(0, 2.8, 0.8)
	# 2페이즈 경보등이 돈다
	for i in alarm_lights.size():
		var s := alarm_lights[i] as SpotLight3D
		if s.light_energy > 0.01:
			var a := time * 2.4 + i * 1.6
			s.look_at(s.global_position + Vector3(cos(a), -0.8, sin(a)), Vector3.UP)
	_dbg_f += 1
	if _arg_dbg and _dbg_f % 120 == 0:
		print("DBG t=%.1f st=%d pat=%s loc=%s c=%s hidden=%s landed=%s hp=%.0f route=%d enemies=%d webs=%d slow=%.2f" % [time, boss.st, boss.pat, boss.loc.get("s", "?"), str(boss.cur_c.snapped(Vector3.ONE * 0.1)), boss.hidden, boss.landed, boss.boss_hp, boss.route.size(), enemies_left(), stage.webs.size(), player.slow_mul])
	if _arg_perflog and fmod(time, 5.0) < dt:
		print("PERF t=%.0f fps=%d nodes=%d draw=%d" % [time, Performance.get_monitor(Performance.TIME_FPS), Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


## 거미줄 감속: 감김(직격) · 바닥 판. 대시하면 감김이 크게 줄고, 거미줄 판을 검으로 베면 끊어진다.
func _update_web(dt: float) -> void:
	var dashing := player.dash_t > 0.0
	if dashing and not _was_dashing and web_t > 0.0:
		web_t *= 0.4
		FX.sparks(player.global_position + Vector3(0, 0.9, 0), 14, [Color.WHITE, Color(0.8, 0.95, 1.0)], 6.0, 0.4, -8.0, 0.05)
		hud.popup("BREAK", Color(0.8, 1.0, 1.0), player.global_position + Vector3(0, 2.2, 0))
		Sfx.play("slash", 0.2, -10.0)
	_was_dashing = dashing
	if player.slash_anim > 0.0 and stage.webs.size() > 0:
		var fwd := Vector3(player.aim_dir.x, 0, player.aim_dir.z)
		if stage.cut_webs(player.global_position + fwd * 1.2, 1.6) > 0:
			FX.sparks(player.global_position + fwd * 1.4 + Vector3(0, 0.3, 0), 6, [Color.WHITE, Color(0.8, 0.95, 1.0)], 4.0, 0.3, -8.0, 0.04)
	web_t = maxf(0.0, web_t - dt)
	var mul := 1.0
	var floor_k := stage.web_at(player.global_position) if not player.airborne else 0.0
	if floor_k > 0.0:
		mul = lerpf(1.0, WEB_SLOW, clampf(floor_k * 1.4, 0.0, 1.0))
	if web_t > 0.0:
		mul = minf(mul, lerpf(WRAP_SLOW, 0.75, 1.0 - clampf(web_t / 1.2, 0.0, 1.0)))
	if not player.alive:
		mul = 1.0
	player.slow_mul = mul
	web_k = lerpf(web_k, 1.0 - mul, 1.0 - exp(-10.0 * dt))
	wrap.visible = web_t > 0.0 and player.alive
	if wrap.visible:
		wrap.global_position = player.global_position
		wrap.rotate_y(dt * 0.6)
		wrap.scale = Vector3.ONE * (0.85 + 0.15 * clampf(web_t / WRAP_TIME, 0.0, 1.0))
	web_label.visible = web_t > 0.0 and player.alive
	if web_label.visible:
		web_label.modulate.a = 0.7 + 0.3 * sin(time * 8.0)


func _process(dt: float) -> void:
	super._process(dt)
	if stage:
		stage.update(dt, camera, player.global_position)


func _drop_loot(e: Enemy) -> void:
	if e.is_boss:
		return
	if randf() < 0.22:
		drop_pickup("missile", e.global_position)
	if randf() < 0.14:
		drop_pickup("energy", e.global_position)


func on_player_died() -> void:
	super.on_player_died()
	web_t = 0.0


func _win() -> void:
	state = State.WIN
	print("WIN t=%.1f score=%d" % [time, score])
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		b.queue_free()
	bar.hide_bar()
	FX.victory(player.global_position)
	player.celebrate()
	Sfx.play("win", 0.0)
	var tw := create_tween()
	tw.tween_property(stage, "alarm", 0.0, 1.5)
	for s in alarm_lights:
		tw.parallel().tween_property(s, "light_energy", 0.0, 1.5)
	hud.message("SHIPWRIGHT DOWN", "%.1f초 · 점수 %d · 최대 %d 콤보 · R 키로 다시 도전" % [time, score, best_combo], Color("7ad8ff"))


# ── 자동 플레이 (검증용) ─────────────────────────────────

func bot_input(p: Player) -> Dictionary:
	var out := {"move": Vector3.ZERO, "aim": p.global_position - Vector3(0, 0, 3), "fire": false, "slash": false, "dash": false, "charge": false, "boost": false, "jump": false, "ult": false}
	var pp := Vector3(p.global_position.x, 0, p.global_position.z)
	var dt := get_physics_process_delta_time()
	bot_dash_cd -= dt
	if boss and boss.show_mode:
		# 확인 모드: 가운데 근처에서 천천히 돌며 보스를 바라본다
		var a := time * 0.25
		out.move = (Vector3(cos(a) * 6.0, 0, 6.0 + sin(a) * 4.0) - pp).limit_length(1.0) * 0.5
		out.aim = boss.focus_point()
		return out
	var best: Enemy = null
	var bd := 1e9
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.landed or not en.alive:
			continue
		var d := en.global_position.distance_to(pp)
		if en.is_boss:
			d += 5.0
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
		var want := 5.0 if not best.is_boss else 9.0
		if bd > want + 1.5:
			move += n * 0.8
		elif bd < want - 1.5:
			move -= n * 0.9
		out.slash = bd < 2.6 and fmod(time, 0.3) < 0.03
		if fmod(time, 6.0) > 4.9 and p.energy > 0:
			out.charge = true
			out.fire = false
		out.ult = p.missiles >= 3 and fmod(time, 9.0) < 0.05
	else:
		move += (Vector3(0, 0, 8) - pp).limit_length(1.0) * 0.4
	# 벽 · 기둥 피하기
	for i in Stage.PILLARS.size():
		var c := Stage.pillar_pos(i)
		var rel := pp - c
		if rel.length() < Stage.pillar_r(i) + 1.6:
			move += rel.normalized() * 0.8
	if absf(pp.x) > Stage.HX - 3.0:
		move.x -= signf(pp.x) * 0.8
	if absf(pp.z) > Stage.HZ - 3.0:
		move.z -= signf(pp.z) * 0.8
	# 거미줄 판에서 벗어난다
	for w in stage.webs:
		var rel: Vector3 = pp - (w.pos as Vector3)
		if rel.length() < float(w.r) + 0.6:
			move += (rel.normalized() if rel.length() > 0.1 else Vector3.BACK) * 1.2
	if web_t > 0.3 and bot_dash_cd <= 0.0:
		out.dash = true
		bot_dash_cd = 0.6
	# 보스 위험
	if boss and boss.alive:
		for th in boss.get_threats():
			match th.type:
				"circle":
					var rel: Vector3 = pp - Vector3(th.pos.x, 0, th.pos.z)
					if rel.length() < float(th.r) + 1.2:
						move += (rel.normalized() if rel.length() > 0.1 else Vector3.BACK) * 2.6
						if rel.length() < float(th.r) and bot_dash_cd <= 0.0:
							out.dash = true
							out.move = rel.normalized() if rel.length() > 0.1 else Vector3.BACK
							bot_dash_cd = 0.8
							return out
				"beam":
					var o: Vector3 = th.origin
					var a: float = th.a
					var d := Vector3(cos(a), 0, sin(a))
					var rel := pp - Vector3(o.x, 0, o.z)
					var along := clampf(rel.dot(d), 0.0, float(th.len))
					var off := rel - d * along
					if off.length() < float(th.half) + 1.6:
						var side := off.normalized() if off.length() > 0.05 else Vector3(-d.z, 0, d.x)
						move += side * 3.0
						if bot_dash_cd <= 0.0:
							out.dash = true
							out.move = side
							bot_dash_cd = 0.8
							return out
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
	if Parry.inst and Parry.inst.best_threat() != null:
		out.dash = true
	out.move = move.limit_length(1.0)
	return out
