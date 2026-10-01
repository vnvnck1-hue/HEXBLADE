extends Main
## 추격 보스전 진행: 무한 스크롤 배경 · 부스터 비행 고정 · 보스 등장/페이즈/격파 · 전장 경계 · 자동 플레이.
## 방·통로 맵 대신 boss_stage.gd 가 흐르는 도로를 만든다. 나머지(플레이어·탄·HUD·연출)는 Main 과 같다.

const Stage := preload("res://scripts/boss_stage.gd")
const BossEnemy := preload("res://scripts/boss_enemy.gd")
const BossBar := preload("res://scripts/boss_bar.gd")
const SpeedFX := preload("res://scripts/speed_fx.gd")
const BossCamera := preload("res://scripts/boss_camera.gd")

const SPEED_1 := 42.0
const SPEED_2 := 56.0
const BOSS_DELAY := 1.4
const MIN_GAP := 4.8          # 보스 중심에서 플레이어까지 최소 앞뒤 거리
const Z_MAX := 6.0
const VIEW_K := 1.6           # 총 연출 화면 크기 배율 (ToonGunFX.view_k)
const FLOW_FAR_Z := 30.0      # 흘러가던 탄피·파편이 이보다 아래(+Z)로 가면 지운다 (화면 밖)

var stage: Stage
var boss: BossEnemy
var bar: BossBar
var speed_fx: SpeedFX
var boss_spawned := false
var jet_t := 0.0
var bot_side := 1.0


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
	env.ssao_enabled = false
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.05, 0.12)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	sun.directional_shadow_max_distance = 70.0
	stage = Stage.new()
	stage.speed = SPEED_1
	world.add_child(stage)
	# 흐르는 공간: 탄피·파편·연기·폭발·바닥 흔적이 도로 속도에 맞춰 화면 아래로 흘러간다
	WorldFlow.attach(world, stage, FLOW_FAR_Z)
	bullets = Node3D.new()
	add_child(bullets)

	player = Player.new()
	player.bot = capture_mode
	player.infinite_boost = true
	add_child(player)
	player.global_position = Vector3(0, 0, 4.0)

	camera = BossCamera.new()
	add_child(camera)
	camera.current = true
	camera.snap(player.global_position)
	debris = Debris.new()
	world.add_child(debris)
	world.add_child(GunFX.new())
	# 보스전 카메라는 일반 전투보다 멀고(22m) 넓어(FOV 50) 같은 크기의 총 연출이 화면에서 약 0.54배로 보인다
	ToonGunFX.inst.view_k = VIEW_K

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
	if not capture_mode:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	hud.banner("CHASE", Color(0.7, 0.95, 1.0), "달아나는 중전차를 부스터로 추격하라")


func _spawn_boss() -> void:
	boss_spawned = true
	boss = BossEnemy.new()
	boss.stage = stage
	boss.bar = bar
	world.add_child(boss)
	(camera as BossCamera).boss = boss
	bar.appear()
	boss.phase_changed.connect(_on_phase)
	boss.defeated.connect(_on_boss_defeated)
	hud.banner("WARNING", Color("ff3a4a"), "거대 중전차 MAMMOTH 출현!")
	Sfx.play("twind", 0.0, 0.0)
	shake(0.3)


func _on_phase(p: int) -> void:
	if p == 2:
		# 2페이즈: 더 빨라진다
		var tw := create_tween()
		tw.tween_property(stage, "speed", SPEED_2, 1.5).set_trans(Tween.TRANS_QUAD)
		speed_fx.target_intensity = 1.35


## 죽음 연출이 끝나면(카메라 복귀 뒤) 바로 승리 처리한다
func _on_boss_defeated() -> void:
	_win.call_deferred()


## 죽음 연출 중: 입력을 잠그고(자동 비행) 하던 궁극기·지속 레이저를 끊는다
func _dying() -> bool:
	return boss != null and boss.death_started()


# ── 판정 보조 ───────────────────────────────────────────

func is_blocked(p: Vector3) -> bool:
	return absf(p.x) > Stage.HALF_W + 4.0 or p.z > 18.0 or p.z < -48.0


func push_out(p: Vector3, radius: float) -> Vector3:
	p.x = clampf(p.x, -Stage.HALF_W + radius, Stage.HALF_W - radius)
	return p


func combat_rooms() -> int:
	return 1


func enemies_left() -> int:
	return 1 if boss and boss.alive else 0


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
	if boss and boss.alive:
		boss_loot(boss, boss.boss_hp / BossEnemy.MAX_HP)
	# 전장 경계: 좌우 차선 안, 보스 앞쪽으로만
	if player.alive:
		var p := player.global_position
		var z_min := -4.0
		if boss and boss.visual.visible and not _dying():
			z_min = boss.global_position.z + MIN_GAP
		p.x = clampf(p.x, -Stage.HALF_W + 0.4, Stage.HALF_W - 0.4)
		p.z = clampf(p.z, z_min, Z_MAX)
		if boss and boss.visual.visible and not _dying() and absf(p.x - boss.global_position.x) < 3.6:
			p.z = maxf(p.z, z_min)
		player.global_position = p
		# 부스터 배기가 도로 속도로 뒤로 흩날린다
		jet_t -= dt
		if jet_t <= 0.0:
			jet_t = 0.035
			var back := player.global_position + Vector3(randf_range(-0.2, 0.2), 1.1, 0.45)
			stage.puff(back, Color(0.2, 0.9, 1.0, 0.9) if randf() < 0.6 else Color(0.6, 0.5, 1.0, 0.9), 0.45, 0.22, 0.9, true)
	var k := stage.speed / SPEED_1
	(camera as BossCamera).speed_k = k
	if _dying() and boss.death_fx.active:
		# 연출 중 속도선 세기는 감독이 정하고, 지금 화면을 찍는 카메라(연출 카메라)를 따라간다
		player.invuln = maxf(player.invuln, 1.0)
	else:
		speed_fx.target_intensity = clampf(k, 0.0, 1.4) if state != State.WIN else 0.25
	var cur := get_viewport().get_camera_3d()
	if cur:
		speed_fx.track(cur, Vector3(cur.global_position.x * 0.3, 0.0, -60.0))


func _process(dt: float) -> void:
	if _dying():
		if not player.bot:
			# 연출 시작: 사람이 조작하던 플레이어를 자동 비행으로 바꾸고 하던 큰 기술을 끊는다
			if player.ult_aiming:
				player._end_ult_aim(false)
			elif player.ult_winding():
				player._cancel_ult_windup()
			if player.mega_t > 0.0:
				player._end_mega()
		player.bot = true
	super._process(dt)


func _win() -> void:
	state = State.WIN
	print("WIN t=%.1f" % time)
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		FX.flash(b.position, Pal.E_BULLETS[2], 0.4, 0.1)
		b.queue_free()
	bar.hide_bar()
	var tw := create_tween()
	tw.tween_property(stage, "speed", 10.0, 2.5).set_ease(Tween.EASE_OUT)
	FX.victory(player.global_position)
	player.celebrate()
	Sfx.play("win", 0.0)
	hud.message("MAMMOTH DESTROYED", "추격 %.1f초 · 점수 %d · 최대 %d 콤보 · R 키로 다시 도전" % [time, score, best_combo], Color("7cf5ff"))


# ── 자동 플레이 (검증용) ─────────────────────────────────

func bot_input(p: Player) -> Dictionary:
	var out := {"move": Vector3.ZERO, "aim": p.global_position - Vector3(0, 0, 6), "fire": false, "slash": false, "dash": false, "charge": false, "boost": true}
	if _dying():
		# 죽음 연출 중: 넘어지는 맘모스 반대 차선의 안전한 자리로 부스터 비행
		var to := boss.death_fx.safe_pos - p.global_position
		to.y = 0
		out.move = (to * 0.6).limit_length(1.0) if to.length() > 0.3 else Vector3.ZERO
		return out
	if boss == null or not boss.visual.visible:
		return out
	var bp := boss.global_position
	out.aim = bp + Vector3(0, 0.95, 0)
	if OS.get_cmdline_user_args().has("--hug"):
		# 근접 견제 검증: 보스에 붙어서 검만 휘두른다 (회피 없음)
		var hug := Vector3(bp.x, 0, bp.z + MIN_GAP + 0.5) - p.global_position
		hug.y = 0
		out.move = hug.limit_length(1.0)
		out.slash = boss.landed and boss.alive
		return out
	out.fire = boss.landed and boss.alive
	var cyc := fmod(time, 7.0)
	if cyc > 5.6 and boss.alive:
		out.charge = true
		out.fire = false
	out.ult = p.missiles > 0 and boss.alive and boss.landed
	# 기본 위치: 보스 앞 7m, 좌우로 천천히 오간다
	if fmod(time, 5.0) < 0.02:
		bot_side = -bot_side
	var want := Vector3(clampf(bp.x + bot_side * 4.0, -8.5, 8.5), 0, bp.z + 8.0)
	var move := (want - p.global_position)
	move.y = 0
	move = move.limit_length(1.0) * 0.7
	# 예고 공격 회피
	for th in boss.get_threats():
		match th.type:
			"circle":
				var rel: Vector3 = p.global_position - th.pos
				rel.y = 0
				if rel.length() < th.r + 1.0:
					move += (rel.normalized() if rel.length() > 0.1 else Vector3.RIGHT) * 2.0
			"lane":
				var dx: float = p.global_position.x - th.x
				if absf(dx) < th.half + 0.9:
					var dirx := signf(dx) if absf(dx) > 0.2 else (1.0 if th.x < 0.0 else -1.0)
					if absf(p.global_position.x + dirx * 3.0) > Stage.HALF_W - 0.5:
						dirx = -dirx
					move += Vector3(dirx * 2.5, 0, 0)
			"beam":
				var rel: Vector3 = p.global_position - th.origin
				rel.y = 0
				var along: float = clampf(rel.dot(th.dir), 0.0, th.len)
				var off: Vector3 = rel - th.dir * along
				if off.length() < th.half + 1.5:
					var side: Vector3 = off.normalized() if off.length() > 0.1 else Vector3(-th.dir.z, 0, th.dir.x)
					move += side * 3.0
	# 탄 회피
	bot_dash_cd -= get_physics_process_delta_time()
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		var rel := p.global_position - bl.position
		rel.y = 0
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
