extends Main
## 용광로 보스전 진행: 용암 위 팔각 발판 · 거신 등장/페이즈/격파 · 좁아지는 전장 경계 · 자동 플레이.
## 방·통로 맵 대신 forge_stage.gd 가 발판과 주변 설비를 만든다. 나머지(플레이어·탄·HUD·연출)는 Main 과 같다.

const Stage := preload("res://scripts/forge_stage.gd")
const ForgeBoss := preload("res://scripts/forge_boss.gd")
const BossBar := preload("res://scripts/boss_bar.gd")
const ForgeCamera := preload("res://scripts/forge_camera.gd")

const BOSS_DELAY := 0.8
const EDGE := 0.45                # 발판 가장자리에서 플레이어 중심까지 최소 거리
## 이 전장의 기본 조명 (dramatic() 이 어두워졌다 되돌아올 값)
const SUN_E := 0.95
const AMB_E := 0.42
const BG := Color(0.07, 0.02, 0.015)

var stage: Stage
var boss: ForgeBoss
var bar: BossBar
var boss_spawned := false
var bot_orbit := 1.0


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
	_forge_lighting()
	stage = Stage.new()
	world.add_child(stage)
	bullets = Node3D.new()
	add_child(bullets)

	player = Player.new()
	player.bot = capture_mode
	add_child(player)
	player.global_position = Vector3(0, 0, 7.5)

	camera = ForgeCamera.new()
	add_child(camera)
	camera.current = true
	camera.snap(player.global_position)
	debris = Debris.new()
	world.add_child(debris)
	world.add_child(GunFX.new())

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
	bar.name_label.text = "VULCAN  ·  용광로 거신"
	if not capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	hud.banner("FORGE", Color("ffb060"), "용광로 심장부 — 좁은 발판 위에서 거신을 쓰러뜨려라")


## 용광로 조명: 붉은 배경 · 따뜻한 주변광 · 낮게 깔린 주황 안개 · 강한 발광
func _forge_lighting() -> void:
	env.background_color = BG
	env.ambient_light_color = Color(0.66, 0.56, 0.78)
	env.ambient_light_energy = AMB_E
	env.fog_enabled = true
	env.fog_light_color = Color(0.32, 0.09, 0.04)
	env.fog_density = 0.0028
	env.fog_sky_affect = 0.0
	env.glow_intensity = 0.62
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	sun.light_color = Color(1.0, 0.78, 0.62)
	sun.light_energy = SUN_E
	sun.rotation_degrees = Vector3(-60, 24, 0)
	sun.directional_shadow_max_distance = 80.0


func _spawn_boss() -> void:
	boss_spawned = true
	boss = ForgeBoss.new()
	boss.stage = stage
	boss.bar = bar
	world.add_child(boss)
	(camera as ForgeCamera).boss = boss
	bar.appear()
	boss.phase_changed.connect(_on_phase)
	boss.defeated.connect(_on_boss_defeated)
	hud.banner("WARNING", Color("ff3a4a"), "용광로 거신 VULCAN 기동!")
	Sfx.play("twind", 0.0, 0.0)
	shake(0.3)


func _on_phase(_p: int) -> void:
	pass


func _on_boss_defeated() -> void:
	get_tree().create_timer(1.6, false).timeout.connect(_win)


# ── 판정 보조 ───────────────────────────────────────────

## 벽이 없는 전장: 탄은 멀리 날아가 수명으로 사라지고, 파편만 먼 경계에서 막힌다
func is_blocked(p: Vector3) -> bool:
	return Vector2(p.x, p.z + 4.0).length() > 46.0


func push_out(p: Vector3, radius: float) -> Vector3:
	return Stage.clamp_inside(p, stage.radius - radius)


func combat_rooms() -> int:
	return 1


func enemies_left() -> int:
	return 1 if boss and boss.alive else 0


func dramatic(on: bool) -> void:
	if _dark_tw:
		_dark_tw.kill()
	_dark_tw = create_tween().set_parallel(true)
	var d := 0.1 if on else 0.6
	_dark_tw.tween_property(sun, "light_energy", 0.08 if on else SUN_E, d)
	_dark_tw.tween_property(env, "ambient_light_energy", 0.05 if on else AMB_E, d)
	_dark_tw.tween_property(env, "background_color", Color(0.01, 0.0, 0.0) if on else BG, d)
	_dark_tw.tween_property(env, "glow_intensity", 1.1 if on else 0.62, d)
	_dark_tw.tween_property(env, "glow_hdr_threshold", 0.85 if on else 1.0, d)
	if on:
		ImpactFrame.inst.after(hud.screen_flash.bind(Color(1.0, 0.9, 0.8), 0.5))


# ── 진행 ────────────────────────────────────────────────

func _physics_process(dt: float) -> void:
	time += dt
	if combo > 0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 0
	if not boss_spawned and time >= BOSS_DELAY:
		_spawn_boss()
	if OS.get_cmdline_user_args().has("--godmode"):
		player.invuln = 999.0
	if OS.get_cmdline_user_args().has("--fastp2") and boss and boss.phase == 1 and boss.st == ForgeBoss.St.FIGHT and time > 6.0:
		boss.take_hit(20, Vector3.FORWARD, boss.global_position, "missile")
		boss.boss_hp = minf(boss.boss_hp, ForgeBoss.MAX_HP * ForgeBoss.PHASE2_AT + 1.0)
	# 전장 경계: 지금 남은 팔각 발판 안
	if player.alive:
		player.global_position = Stage.clamp_inside(player.global_position, stage.radius - EDGE)


func _win() -> void:
	state = State.WIN
	print("WIN t=%.1f" % time)
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		FX.flash(b.position, Pal.E_BULLETS[2], 0.4, 0.1)
		b.queue_free()
	bar.hide_bar()
	var tw := create_tween()
	tw.tween_property(stage, "heat", 0.0, 3.0)
	FX.victory(player.global_position)
	player.celebrate()
	Sfx.play("win", 0.0)
	hud.message("VULCAN DESTROYED", "%.1f초 · 점수 %d · 최대 %d 콤보 · R 키로 다시 도전" % [time, score, best_combo], Color("ffc070"))


# ── 자동 플레이 (검증용) ─────────────────────────────────

func bot_input(p: Player) -> Dictionary:
	var out := {"move": Vector3.ZERO, "aim": p.global_position - Vector3(0, 0, 6), "fire": false, "slash": false, "dash": false, "charge": false, "boost": false}
	if boss == null:
		return out
	var pp := Vector3(p.global_position.x, 0, p.global_position.z)
	var target := Vector3(boss.global_position.x, 0.95, boss.global_position.z + 5.0)
	# 박힌 팔이 가까우면 그쪽을 노리고 벤다
	var near_fist: Enemy = null
	for a in boss.arms:
		var fv = (a as Dictionary).fist
		if not is_instance_valid(fv):
			continue
		var f := fv as Enemy
		if f.landed and f.global_position.distance_to(pp) < 7.0:
			near_fist = f
	if near_fist:
		target = near_fist.global_position + Vector3(0, 0.95, 0)
		out.slash = fmod(time, 0.4) < 0.03
	out.aim = target
	out.fire = boss.alive and boss.landed
	var cyc := fmod(time, 6.0)
	if cyc > 4.6 and boss.alive:
		out.charge = true
		out.fire = false
	out.ult = p.ult >= 1.0 and boss.alive and boss.landed
	if OS.get_cmdline_user_args().has("--pacifist"):
		# 패턴 확인용: 공격하지 않고 피하기만 한다
		out.fire = false
		out.charge = false
		out.slash = false
		out.ult = false
	# 기본 위치: 발판 중앙보다 조금 남쪽에서 천천히 원을 그린다
	if fmod(time, 4.0) < 0.02:
		bot_orbit = -bot_orbit
	var r := minf(stage.radius * 0.55, 5.5)
	var a0 := time * 0.45 * bot_orbit
	var want := Vector3(sin(a0) * r, 0, 2.0 + cos(a0) * r * 0.6)
	var move := want - pp
	move = move.limit_length(1.0) * 0.6
	var dt := get_physics_process_delta_time()
	bot_dash_cd -= dt
	for th in boss.get_threats():
		match th.type:
			"circle":
				var rel: Vector3 = pp - th.pos
				rel.y = 0
				if rel.length() < float(th.r) + 1.0:
					move += (rel.normalized() if rel.length() > 0.1 else Vector3.BACK) * 2.2
			"fan":
				var rel: Vector3 = pp - th.apex
				rel.y = 0
				var d: Vector3 = th.dir
				var ang := absf(angle_difference(atan2(rel.x, rel.z), atan2(d.x, d.z)))
				if rel.length() < float(th.r) + 1.0 and ang < float(th.half) + 0.25:
					var side := Vector3(-d.z, 0, d.x)
					if side.dot(rel) < 0.0:
						side = -side
					move += side * 2.5
			"beam":
				var rel: Vector3 = pp - th.origin
				rel.y = 0
				var d: Vector3 = th.dir
				var along: float = clampf(rel.dot(d), 0.0, th.len)
				var off: Vector3 = rel - d * along
				if th.get("sweep", false):
					# 쓸고 오는 빔: 가까워지면 빔 쪽으로 대시해 뚫고 지나간다
					var pa := atan2(rel.x, rel.z)
					var ba: float = th.a
					var ahead := signf(float(th.a1) - ba)
					var gap := (pa - ba) * ahead
					if gap > 0.0 and gap < 0.2 and bot_dash_cd <= 0.0:
						out.dash = true
						out.move = Vector3(-d.z, 0, d.x) * -ahead
						bot_dash_cd = 0.8
						return out
				elif off.length() < float(th.half) + 1.5:
					move += (off.normalized() if off.length() > 0.1 else Vector3(-d.z, 0, d.x)) * 3.0
			"wedges":
				var rr := pp.length()
				var idx := posmod(int(round(atan2(pp.x, pp.z) / (PI / 4.0))), 8)
				if rr < float(th.r_in) + 0.8 or (th.hit as Array).has(idx):
					# 가장 가까운 안전 조각 가운데로
					for k in 8:
						if not (th.hit as Array).has(k):
							var a := k * PI / 4.0 + PI / 8.0
							var goal := Vector3(sin(a), 0, cos(a)) * float(th.r_out) * 0.6
							move += (goal - pp).limit_length(1.0) * 3.0
							break
	# 탄 회피
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		var rel := pp - Vector3(bl.position.x, 0, bl.position.z)
		var l := rel.length()
		if l < 2.2 and bl.vel.dot(rel) > 0:
			var side := Vector3(-bl.vel.z, 0, bl.vel.x).normalized()
			if side.dot(rel) < 0:
				side = -side
			move += side * (2.2 - l) * 1.2
			if l < 1.1 and bot_dash_cd <= 0.0 and randf() < 0.4:
				out.dash = true
				bot_dash_cd = 0.9
	out.move = move.limit_length(1.0)
	return out
