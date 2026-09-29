extends Enemy
## 추격 보스 "맘모스". 뒤로 달아나며(후진) 플레이어를 향해 싸운다.
## 1페이즈 패턴 4개 → 체력 40% 에서 파츠가 떨어져 나가며 2페이즈 → 패턴 3개 (강력 예고 공격 포함).
## 판정·진행은 이 파일, 흐르는 배경·연기 이동은 boss_stage.gd 가 맡는다.

const BossTank := preload("res://scripts/boss_tank.gd")
const Stage := preload("res://scripts/boss_stage.gd")
const Bar := preload("res://scripts/boss_bar.gd")

signal phase_changed(phase: int)
signal defeated

enum St { ENTER, FIGHT, TRANSITION, DYING, DEAD }

const MAX_HP := 800.0
const PHASE2_AT := 0.4
const BASE_Z := -10.5
const ENTER_TIME := 3.2
const PLANE_Y := 1.0              # 탄이 날아가는 높이 (판정은 수평 거리)

const PATTERNS_1 := ["volley", "gatling", "missiles", "gapring"]
const PATTERNS_2 := ["spiral", "lanes", "mega"]
const NAMES := {
	"volley": "쌍포 조준 연사", "gatling": "개틀링 교차 소사", "missiles": "추적 미사일 폭격", "gapring": "틈새 원형탄",
	"spiral": "이중 나선 탄막", "lanes": "레인 포격", "mega": "!! 거수포 — 강력 예고 공격 !!",
}

var stage: Stage
## 강력 레이저가 관통하지 못하고 표면에서 막힌다 (beam_impact.gd 가 읽음)
var blocks_beam := true
var bar: Bar
var st := St.ENTER
var st_t := 0.0
var phase := 1
var boss_hp := MAX_HP
var tank: Dictionary
var model: Node3D
var meshes: Array = []
var pat := ""
var pat_i := -1
var pt := 0.0
var ps := {}
var rest := 1.5
var weak := false
var weak_t := 0.0
var flash_cd := 0.0
var hit_snd_cd := 0.0
var turret_yaw := PI
var spons_yaw := [PI, PI]
var spons_alive := [true, true]
var muzzle_glow: Array = []
var recoil := [0.0, 0.0]
var fx_cd := 0.0
var smoke_points: Array = []
var wob2 := Vector2.ZERO
var wob2_v := Vector2.ZERO
var x_target := 0.0
var z_off := 0.0
var threats: Array = []           # 자동 플레이 회피용: 원·차선·빔
var warnings: Array = []          # 바닥 경고 노드
var _marker_mat: ShaderMaterial


func _ready() -> void:
	add_to_group("enemies")
	radius = 3.3
	slice_size = Vector3(4, 3, 4)
	visual = Node3D.new()
	add_child(visual)
	model = Node3D.new()
	model.rotation.y = PI           # 정면(포구)이 플레이어 쪽(+Z)을 향한 채 후진한다
	visual.add_child(model)
	tank = BossTank.build(model)
	j = {"body": model, "core": tank.core}
	shadow = FX.blob_shadow(self, 9.5, 0.8)
	for c in tank.cannons:
		var g := Pal.flat_mesh(_ball_mesh(0.5), Color("ff6a50"), 2.4)
		(c.muzzle as Node3D).add_child(g)
		g.scale = Vector3.ONE * 0.01
		muzzle_glow.append(g)
	_cache_meshes()
	landed = false
	global_position = Vector3(0, 0, -62.0)


func _ball_mesh(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 14
	s.rings = 7
	return s


func _cache_meshes() -> void:
	meshes = model.find_children("*", "MeshInstance3D", true, false)


# ── 매 프레임 ───────────────────────────────────────────

func _physics_process(dt: float) -> void:
	t += dt
	st_t += dt
	flash_cd -= dt
	hit_snd_cd -= dt
	threats.clear()
	if st == St.DEAD:
		return
	var player := Main.inst.player
	match st:
		St.ENTER:
			_update_enter(dt)
		St.FIGHT:
			_update_fight(dt, player)
		St.TRANSITION:
			_update_transition(dt)
		St.DYING:
			_update_dying(dt)
	_update_body(dt, player)


func _update_enter(_dt: float) -> void:
	# 멀리서 달아나던 보스를 따라잡는다 (보스가 화면 위에서 내려오듯 다가옴)
	var k := clampf(st_t / ENTER_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	global_position.z = lerpf(-62.0, BASE_Z, e)
	if k >= 1.0:
		st = St.FIGHT
		st_t = 0.0
		landed = true
		rest = 0.8
		Main.inst.shake(0.4)


func _update_fight(dt: float, player: Player) -> void:
	if weak:
		weak_t -= dt
		if weak_t <= 0.0:
			weak = false
			bar.weak = false
	if not player.alive or Main.inst.state != Main.State.PLAY:
		return
	if pat == "":
		rest -= dt
		if rest <= 0.0:
			_next_pattern()
		return
	pt += dt
	var done: bool = call("_p_" + pat, dt, player)
	if done:
		pat = ""
		rest = 1.1 if phase == 1 else 0.75
		bar.set_pattern("")


func _next_pattern() -> void:
	var list: Array = PATTERNS_1 if phase == 1 else PATTERNS_2
	pat_i = (pat_i + 1) % list.size()
	pat = list[pat_i]
	pt = 0.0
	ps = {}
	bar.set_pattern(NAMES[pat])
	print("BOSS_PATTERN %s phase=%d hp=%.0f" % [pat, phase, boss_hp])


## 이동·조준·흔들림·배기 연출
func _update_body(dt: float, player: Player) -> void:
	# 좌우로 천천히 흔들리며 달아나고, 앞뒤로 조금씩 거리를 벌렸다 좁힌다
	if st == St.FIGHT:
		var sway := sin(t * 0.33) * 4.5 + sin(t * 0.81) * 1.2
		if pat == "mega" or pat == "lanes":
			sway = move_toward(x_target, clampf(player.global_position.x * 0.5, -5.0, 5.0), 3.0 * dt) if pat == "mega" else 0.0
		x_target = sway
		var zo := sin(t * 0.55) * 1.3
		if pat == "mega":
			zo = -1.5
		z_off = lerpf(z_off, zo, 1.0 - exp(-1.5 * dt))
		var nx := move_toward(global_position.x, x_target, 4.0 * dt)
		var vx := (nx - global_position.x) / maxf(dt, 0.0001)
		global_position.x = nx
		global_position.z = BASE_Z + z_off
		wob2_v.y += -vx * 0.02
	# 무게감 있는 흔들림: 스프링 + 궤도 진동
	wob2_v += (-wob2 * 60.0 - wob2_v * 7.0) * dt
	wob2 += wob2_v * dt
	var rumble := sin(t * 37.0) * 0.012 + sin(t * 23.0) * 0.01
	visual.position.y = absf(sin(t * 18.0)) * 0.05
	visual.rotation = Vector3(wob2.x + rumble, 0, wob2.y + rumble * 0.6)
	punch = move_toward(punch, 0.0, dt * 5.0)
	model.scale = Vector3(1.0 + punch * 0.03, 1.0 - punch * 0.025, 1.0 + punch * 0.03)

	# 포탑은 기본적으로 플레이어를 노린다 (나선·차선 패턴 중에는 느리게)
	if player and player.alive and st != St.DYING:
		var to := player.global_position - global_position
		var want := atan2(-to.x, -to.z)
		var rate := 1.2 if pat in ["spiral", "lanes"] else 3.0
		if pat == "mega" and ps.get("locked", false):
			rate = 0.0
		turret_yaw = lerp_angle(turret_yaw, want, 1.0 - exp(-rate * dt))
	# 부품이 떨어져 나가는 중(격파)에는 조준·반동을 멈춘다
	if st != St.DYING:
		(tank.turret as Node3D).rotation.y = turret_yaw - PI
		for i in 2:
			if spons_alive[i]:
				(tank.sponsons[i] as Node3D).rotation.y = spons_yaw[i] - PI
				if pat != "gatling":
					spons_yaw[i] = lerp_angle(spons_yaw[i], turret_yaw, 1.0 - exp(-2.0 * dt))
		for i in 2:
			recoil[i] = move_toward(recoil[i], 0.0, dt * 2.5)
			(tank.cannons[i].pivot as Node3D).position.z = -2.25 + recoil[i] * 0.6

	# 배기 연기와 궤도 흙먼지: 도로 속도로 뒤(+Z)로 날려 속도감을 만든다
	fx_cd -= dt
	if fx_cd <= 0.0 and st != St.DEAD and stage:
		fx_cd = 0.06
		for side in [-1, 1]:
			var ex := model.to_global(Vector3(0.7 * side, 3.8, 2.95))
			stage.puff(ex, Color(0.75, 0.72, 0.85, 0.35) if phase == 1 else Color(0.25, 0.2, 0.24, 0.55), 1.3, 0.5, 0.5)
			var tr := model.to_global(Vector3(2.6 * side, 0.15, -3.2 + randf() * 0.4))
			stage.puff(tr, Color(0.55, 0.5, 0.6, 0.3), 1.2, 0.3, 0.95)
			if randf() < 0.25:
				FX.sparks(tr, 3, [Color("ffd060"), Color("ff7a30")], 4.0, 0.25, -6.0, 0.05)
		for sp in smoke_points:
			if is_instance_valid(sp):
				var fire := randf() < 0.35
				var c := Color(1.0, 0.5, 0.15, 0.8) if fire else Color(0.12, 0.1, 0.14, 0.6)
				stage.puff((sp as Node3D).global_position, c, 1.4 if fire else 1.8, 0.35 if fire else 0.7, 0.55, fire)
				if randf() < 0.15:
					FX.sparks((sp as Node3D).global_position, 4, [Color.WHITE, Color("ffb040")], 6.0, 0.3, -10.0, 0.06)
	# 코어 맥동 (약점 노출 중에는 노랗게 깜빡)
	var core := tank.core as MeshInstance3D
	if weak:
		core.set_instance_shader_parameter("tint", Color("ffe060") if fmod(t, 0.16) < 0.08 else Color("ff8a20"))
		core.set_instance_shader_parameter("energy", 3.0)
		core.scale = Vector3.ONE * (1.35 + sin(t * 30.0) * 0.08)
	elif pat != "mega":
		core.set_instance_shader_parameter("tint", Pal.E_RED)
		core.set_instance_shader_parameter("energy", 1.6 + sin(t * (4.0 if phase == 1 else 9.0)) * 0.5)
		core.scale = core.scale.lerp(Vector3.ONE, 1.0 - exp(-6.0 * dt))


# ── 발사 도우미 ─────────────────────────────────────────

func _shot(from: Vector3, dir: Vector3, speed: float, big := false) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	Main.inst.add_bullet(Bullet.make_enemy(Vector3(from.x, PLANE_Y, from.z), d, speed, big))


func _aim_from(from: Vector3, target: Vector3) -> Vector3:
	var d := target - from
	d.y = 0
	return d.normalized() if d.length() > 0.01 else Vector3.BACK


func _muzzle(i: int) -> Vector3:
	return (tank.cannons[i].muzzle as Node3D).global_position


func _core_pos() -> Vector3:
	return (tank.core as Node3D).global_position


func _spons_muzzle(i: int) -> Vector3:
	var s := tank.sponsons[i] as Node3D
	return s.global_position + (-s.global_basis.z) * 1.6 + Vector3(0, 0.3, 0)


func _fire_cannon(i: int) -> void:
	recoil[i] = 1.0
	FX.flash(_muzzle(i), Color("ffb080"), 1.1, 0.09)
	GunFX.muzzle(_muzzle(i), -(tank.cannons[i].muzzle as Node3D).global_basis.z, 2.6)
	punch = maxf(punch, 0.4)
	wob2_v.x -= 0.25


func _dir_from_angle(a: float) -> Vector3:
	# 0 = 플레이어 쪽(+Z), 양수 = 화면 왼쪽(-X)으로 돌아감
	return Vector3(-sin(a), 0, cos(a))


func _player_angle(from: Vector3, player: Player) -> float:
	var d := player.global_position - from
	return atan2(-d.x, d.z)


# ── 1페이즈 ─────────────────────────────────────────────

## 쌍포 조준 연사: 왼포는 현재 위치, 오른포는 이동 예측 위치로 좁은 부채꼴을 쏜다. 옆으로 크게 움직이면 피한다.
func _p_volley(_dt: float, player: Player) -> bool:
	var n: int = ps.get("n", 0)
	var fire_at := 0.7 + n * 1.05
	var tele := clampf(1.0 - (fire_at - pt) / 0.55, 0.0, 1.0) if n < 3 else 0.0
	for g in muzzle_glow:
		(g as Node3D).scale = Vector3.ONE * (0.01 + tele * 1.1 + sin(t * 50.0) * 0.08 * tele)
	if n < 3 and pt >= fire_at:
		ps.n = n + 1
		var ways := 7 if n == 2 else 5
		var spread := 0.11
		for i in 2:
			var m := _muzzle(i)
			var target := player.global_position
			if i == 1:
				target += player.velocity * 0.55
			var base := _aim_from(m, target)
			for w in ways:
				var a := (w - (ways - 1) * 0.5) * spread
				_shot(m, base.rotated(Vector3.UP, a), 10.5, true)
			_fire_cannon(i)
		Sfx.play("tshot", 0.05, 0.0)
		Main.inst.shake(0.18)
	return n >= 3 and pt > fire_at + 0.6


## 개틀링 교차 소사: 양쪽 보조포가 틈이 있는 탄줄을 X자로 교차하며 쓸어낸다. 탄줄의 끊긴 틈으로 빠져나간다.
func _p_gatling(dt: float, _player: Player) -> bool:
	var dur := 4.8
	var s := pt / 2.4
	var tri := 1.0 - absf(fmod(s, 2.0) - 1.0)         # 0→1→0 왕복
	var sweep := deg_to_rad(lerpf(-42.0, 42.0, tri))
	spons_yaw[0] = PI + sweep        # 왼쪽 보조포(화면 왼쪽)
	spons_yaw[1] = PI - sweep
	var cd: float = ps.get("cd", 0.3) - dt
	if cd <= 0.0:
		cd += 0.075
		var slot: int = ps.get("slot", 0)
		ps.slot = slot + 1
		if slot % 8 < 5:
			for i in 2:
				if not spons_alive[i]:
					continue
				var s_node := tank.sponsons[i] as Node3D
				var d := -s_node.global_basis.z
				var m := _spons_muzzle(i)
				_shot(m, d, 9.0)
				FX.flash(m, Color("ffa060"), 0.5, 0.05)
			if slot % 2 == 0:
				Sfx.play("eshot", 0.1, -8.0)
	ps.cd = cd
	return pt >= dur


## 추적 미사일 폭격: 포드에서 미사일이 솟구친 뒤, 플레이어가 있던 자리에 차례로 경고 원이 찍히고 1.15초 뒤 떨어진다.
func _p_missiles(_dt: float, player: Player) -> bool:
	if not ps.get("launched", false):
		ps.launched = true
		for pod in tank.missile_pods:
			if is_instance_valid(pod) and (pod as Node3D).is_inside_tree():
				for k in 4:
					_launch_visual((pod as Node3D).global_position + Vector3(randf_range(-0.4, 0.4), 1.2, randf_range(-0.4, 0.4)), k * 0.08)
		Sfx.play("tshot", 0.1, 0.0)
	var n: int = ps.get("n", 0)
	var count := 7
	if n < count and pt >= 0.8 + n * 0.32:
		ps.n = n + 1
		var p := player.global_position + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)) * (0.0 if n == 0 else 1.0)
		_marker(p, 2.1, 1.15)
		if n == 2 or n == 5:
			for k in 2:
				_marker(Vector3(randf_range(-Stage.HALF_W + 2, Stage.HALF_W - 2), 0, randf_range(-2.0, 5.0)), 2.1, 1.15)
	return n >= count and pt > 0.8 + count * 0.32 + 1.3


## 틈새 원형탄: 원형 파동에 한 군데 틈이 있고, 파동마다 틈이 플레이어 기준 좌우로 옮겨 간다.
func _p_gapring(_dt: float, player: Player) -> bool:
	var times := [0.5, 1.25, 2.0, 2.75]
	var offs := [0.38, -0.4, 0.5, -0.15]
	var n: int = ps.get("n", 0)
	if n < times.size():
		var tele := clampf(1.0 - (times[n] - pt) / 0.4, 0.0, 1.0)
		(tank.core as Node3D).scale = Vector3.ONE * (1.0 + tele * 0.7)
		if pt >= times[n]:
			ps.n = n + 1
			var c := _core_pos()
			var gap: float = _player_angle(c, player) + offs[n]
			var total := 44
			var gap_w := 0.3
			for i in total:
				var a := TAU * i / total
				if absf(angle_difference(a, gap)) < gap_w:
					continue
				_shot(c, _dir_from_angle(a), 6.2, i % 2 == 0)
			FX.flash(c, Color("ff6a80"), 1.6, 0.1)
			FX.shockwave(Vector3(c.x, 0.3, c.z), Pal.E_RED, 3.0, 0.3)
			Sfx.play("eshot", 0.05, 0.0)
			punch = maxf(punch, 0.6)
	return n >= times.size() and pt > 3.4


# ── 2페이즈 ─────────────────────────────────────────────

## 이중 나선: 빠른 4갈래 나선이 한 방향으로, 느린 큰 탄 4갈래가 반대로 돈다. 사이사이 쌍포 조준탄.
func _p_spiral(dt: float, player: Player) -> bool:
	var dur := 5.8
	var c := _core_pos()
	var cd: float = ps.get("cd", 0.0) - dt
	if cd <= 0.0:
		cd += 0.1
		var k: int = ps.get("k", 0)
		ps.k = k + 1
		var rot := pt * 1.25
		for arm in 4:
			var a := rot + TAU * arm / 4.0
			if absf(angle_difference(a, 0.0)) < 1.9:
				_shot(c, _dir_from_angle(a), 6.8)
		if k % 2 == 0:
			var rot2 := -pt * 0.85 + 0.4
			for arm in 4:
				var a := rot2 + TAU * arm / 4.0
				if absf(angle_difference(a, 0.0)) < 1.9:
					_shot(c, _dir_from_angle(a), 4.4, true)
		if k % 3 == 0:
			Sfx.play("eshot", 0.1, -7.0)
	ps.cd = cd
	var ac: float = ps.get("ac", 1.2) - dt
	if ac <= 0.0:
		ac = 1.4
		for i in 2:
			var m := _muzzle(i)
			var base := _aim_from(m, player.global_position)
			for w in 3:
				_shot(m, base.rotated(Vector3.UP, (w - 1) * 0.09), 11.5, true)
			_fire_cannon(i)
		Sfx.play("tshot", 0.05, -2.0)
	ps.ac = ac
	return pt >= dur


## 레인 포격: 전장을 5차선으로 나눠 3차선에 1초 예고 후 포격한다. 매번 안전 차선 2개가 옮겨 간다.
func _p_lanes(dt: float, player: Player) -> bool:
	const ROUNDS := 4
	const PERIOD := 1.55
	const WARN := 1.0
	var lanes := [-8.0, -4.0, 0.0, 4.0, 8.0]
	var r: int = ps.get("r", -1)
	var cur := int(pt / PERIOD)
	if cur != r and cur < ROUNDS:
		ps.r = cur
		ps.fired = false
		# 안전 차선: 서로 붙은 두 칸, 직전과 다른 자리
		var prev: int = ps.get("safe", -1)
		var s := randi() % 4
		while s == prev:
			s = randi() % 4
		ps.safe = s
		var hit: Array = []
		for i in 5:
			if i != s and i != s + 1:
				hit.append(i)
		ps.hit = hit
		_clear_warnings()
		for i in hit:
			var w := LaserWarning.new()
			stage.add_child(w)
			w.set_pose(Vector3(lanes[i], 0, global_position.z + 3.5), Vector3.BACK, 30.0, 3.7, 0.4)
			warnings.append(w)
		Sfx.play("echarge", 0.0, -8.0)
	var local := pt - cur * PERIOD
	if cur < ROUNDS:
		for w in warnings:
			(w as LaserWarning).set_progress(clampf(local / WARN, 0.0, 1.0))
		for i in ps.hit:
			threats.append({"type": "lane", "x": lanes[i], "half": 2.0})
		if local >= WARN and not ps.fired:
			ps.fired = true
			_clear_warnings()
			for i in ps.hit:
				FX.enemy_laser(Vector3(lanes[i], 0.9, global_position.z + 3.5), Vector3.BACK, 30.0, 3.2)
			Sfx.play("elaser", 0.05, 0.0)
			Main.inst.shake(0.35)
			var px := player.global_position.x
			for i in ps.hit:
				if absf(px - lanes[i]) < 2.0 + player.hit_radius * 0.5:
					player.take_hit(Vector3(lanes[i], 0, player.global_position.z - 1.0))
					break
		# 차선 사이 견제: 남은 보조포가 느린 조준탄
		var sc: float = ps.get("sc", 0.6) - dt
		if sc <= 0.0:
			sc = 0.5
			for i in 2:
				if spons_alive[i]:
					var m := _spons_muzzle(i)
					_shot(m, _aim_from(m, player.global_position), 7.0)
		ps.sc = sc
	return pt >= ROUNDS * PERIOD + 0.3


## 거수포 (강력 예고 공격): 2.6초 충전하는 동안 바닥에 넓은 붉은 띠로 사선을 예고하고,
## 1.8초 뒤 조준이 고정된다. 맞으면 체력 3칸. 발사 후 코어가 과열되어 3.5초간 약점(피해 2배)이 드러난다.
func _p_mega(dt: float, player: Player) -> bool:
	const CHARGE := 2.6
	const LOCK_AT := 1.8
	const BEAM := 0.9
	const WIDTH := 5.0
	var core := tank.core as MeshInstance3D
	var origin := (_muzzle(0) + _muzzle(1)) * 0.5
	if not ps.get("started", false):
		ps.started = true
		var w := LaserWarning.new()
		stage.add_child(w)
		warnings.append(w)
		Main.inst.dramatic(true)
		Main.inst.hud.banner("WARNING", Color("ff3a4a"), "거수포 충전 — 붉은 띠 밖으로 피하세요!")
		Sfx.play("echarge", 0.0, 0.0)
		ps.snd = 0.0
		ps.dir = _aim_from(origin, player.global_position)
	if pt < CHARGE:
		if pt < LOCK_AT:
			var want := _aim_from(origin, player.global_position)
			ps.dir = (ps.dir as Vector3).slerp(want, 1.0 - exp(-5.0 * dt)).normalized()
		elif not ps.get("locked", false):
			ps.locked = true
			Sfx.play("lock", 0.0, 0.0)
		var k := pt / CHARGE
		core.set_instance_shader_parameter("tint", Color("ff2040").lerp(Color("fff0f0"), k))
		core.set_instance_shader_parameter("energy", 2.0 + k * 5.0)
		core.scale = Vector3.ONE * (1.0 + k * 1.6 + sin(t * 60.0) * 0.1 * k)
		for g in muzzle_glow:
			(g as Node3D).scale = Vector3.ONE * (0.3 + k * 2.0)
		var w: LaserWarning = warnings[0]
		w.set_pose(origin, ps.dir, 34.0, WIDTH, 1.0)
		w.set_progress(k)
		threats.append({"type": "beam", "origin": origin, "dir": ps.dir, "half": WIDTH * 0.5, "len": 34.0})
		# 빨려 들어가는 불꽃
		var sc: float = ps.get("spk", 0.0) - dt
		if sc <= 0.0:
			sc = 0.06
			var off := Vector3(randf_range(-1, 1), randf_range(-0.5, 1), randf_range(-1, 1)).normalized() * 2.5
			FX.sparks(core.global_position + off, 3, [Color.WHITE, Color("ff5070")], 2.0, 0.2, 0.0, 0.08)
		ps.spk = sc
		ps.snd = float(ps.snd) + dt
		if ps.snd > 1.0:
			ps.snd = 0.0
			Sfx.play("echarge", 0.0, -2.0)
		# 충전 중 견제: 느리고 성긴 원형탄
		var rc: float = ps.get("rc", 0.5) - dt
		if rc <= 0.0:
			rc = 0.7
			var c := _core_pos()
			var off2 := randf() * TAU
			for i in 14:
				_shot(c, _dir_from_angle(off2 + TAU * i / 14.0), 3.8, true)
		ps.rc = rc
		Main.inst.shake(0.02 + k * 0.05)
		return false
	var bt := pt - CHARGE
	if bt < BEAM:
		var dir: Vector3 = ps.dir
		if not ps.get("fired", false):
			ps.fired = true
			_clear_warnings()
			ps.beam_cd = 0.0
			Sfx.play("elaser", 0.0, 4.0)
			Sfx.play("boom", 0.0, 2.0)
			Main.inst.hitstop(0.08)
			Main.inst.shake(1.0)
			Main.inst.kick(dir * 1.4)
			Main.inst.hud.screen_flash(Color(1, 0.6, 0.6), 0.6)
			Main.inst.camera.fov_punch(6.0)
			for i in 2:
				_fire_cannon(i)
			recoil = [1.4, 1.4]
			wob2_v.x -= 1.2
		ps.beam_cd = float(ps.beam_cd) - dt
		if ps.beam_cd <= 0.0:
			ps.beam_cd = 0.15
			FX.enemy_laser(origin, dir, 34.0, WIDTH * 0.95)
			Main.inst.shake(0.3)
		threats.append({"type": "beam", "origin": origin, "dir": dir, "half": WIDTH * 0.5, "len": 34.0})
		if not ps.get("hit", false) and player.alive:
			var rel := player.global_position - origin
			rel.y = 0
			var along := clampf(rel.dot(dir), 0.0, 34.0)
			if (rel - dir * along).length() < WIDTH * 0.5 + player.hit_radius and player.invuln <= 0.0:
				ps.hit = true
				if player.take_hit(origin):
					# 큰 피해: 기본 1칸에 2칸을 더한다
					player.hp -= 2
					Main.inst.hud.popup("-3", Color("ff4050"), player.global_position + Vector3(0, 2.4, 0))
					if player.hp <= 0 and player.alive:
						player.die(dir * 3.0)
		return false
	# 과열: 약점 노출
	if not ps.get("vent", false):
		ps.vent = true
		Main.inst.dramatic(false)
		weak = true
		weak_t = 3.5
		bar.weak = true
		for g in muzzle_glow:
			(g as Node3D).scale = Vector3.ONE * 0.01
		Main.inst.hud.popup("OVERHEAT!  약점 노출 · 피해 2배", Color("ffe060"), _core_pos() + Vector3(0, 2.0, 0))
		Sfx.play("powerdown", 0.0, 0.0)
	var vc: float = ps.get("vc", 0.0) - dt
	if vc <= 0.0:
		vc = 0.08
		for i in 2:
			stage.puff(_muzzle(i), Color(0.95, 0.92, 1.0, 0.5), 1.6, 0.5, 0.35)
	ps.vc = vc
	return bt > BEAM + 3.5


# ── 경고 표시 ───────────────────────────────────────────

func _clear_warnings() -> void:
	for w in warnings:
		if is_instance_valid(w):
			(w as Node).queue_free()
	warnings.clear()


## 바닥 원형 경고 → 미사일 낙하 폭발
func _marker(p: Vector3, r: float, fuse: float) -> void:
	p.x = clampf(p.x, -Stage.HALF_W + 0.5, Stage.HALF_W - 0.5)
	if _marker_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_add;
instance uniform float progress = 0.0;
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.9, 0.95, r) * (1.0 - smoothstep(0.98, 1.0, r));
	float fill = step(r, progress) * 0.35 * (1.0 - step(1.0, r));
	float cross = (step(abs(UV.x - 0.5), 0.012) + step(abs(UV.y - 0.5), 0.012)) * step(r, 0.35);
	float blink = mix(1.0, step(0.5, fract(TIME * 14.0)), step(0.75, progress));
	float i = (ring * 1.6 + fill + cross * 0.8 + 0.08 * (1.0 - step(1.0, r))) * blink;
	ALBEDO = vec3(1.0, 0.12, 0.1) * i;
}
"""
		_marker_mat = ShaderMaterial.new()
		_marker_mat.shader = sh
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	q.size = Vector2(r * 2.0, r * 2.0)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _marker_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(mi)
	mi.global_position = Vector3(p.x, 0.05, p.z)
	var info := {"type": "circle", "pos": mi.global_position, "r": r}
	var holder := {"node": mi, "info": info}
	_markers.append(holder)
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): mi.set_instance_shader_parameter("progress", v), 0.0, 1.0, fuse)
	# 낙하하는 미사일 줄기
	tw.tween_callback(func():
		_markers.erase(holder)
		_impact(mi.global_position, r)
		mi.queue_free())
	var drop := Pal.flat_mesh(_drop_mesh(), Color("ffb060"), 2.2)
	stage.add_child(drop)
	drop.global_position = Vector3(p.x, 9.0, p.z)
	drop.visible = false
	var dtw := drop.create_tween()
	dtw.tween_interval(fuse - 0.2)
	dtw.tween_callback(func(): drop.visible = true)
	dtw.tween_property(drop, "global_position:y", 0.6, 0.18).set_ease(Tween.EASE_IN)
	dtw.tween_callback(drop.queue_free)


var _markers: Array = []
var _drop: BoxMesh


func _drop_mesh() -> BoxMesh:
	if _drop == null:
		_drop = BoxMesh.new()
		_drop.size = Vector3(0.3, 2.4, 0.3)
	return _drop


func _impact(p: Vector3, r: float) -> void:
	FX.enemy_explosion(p + Vector3(0, 0.6, 0), 1.2)
	FX.shockwave(p, Color("ff8a40"), r * 2.2, 0.3)
	Sfx.play("boom", 0.15, -4.0)
	Main.inst.shake(0.25)
	var pl := Main.inst.player
	if pl.alive and Vector2(pl.global_position.x - p.x, pl.global_position.z - p.z).length() < r + pl.hit_radius * 0.5:
		pl.take_hit(p)


func _launch_visual(from: Vector3, delay: float) -> void:
	var m := Pal.flat_mesh(_drop_mesh(), Color("ffd080"), 2.0)
	stage.add_child(m)
	m.global_position = from
	m.scale = Vector3(0.7, 0.5, 0.7)
	var tw := m.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(m, "global_position", from + Vector3(randf_range(-2, 2), 9.0, randf_range(-4, -1)), 0.5).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(m, "scale", Vector3(0.05, 0.9, 0.05), 0.5)
	tw.tween_callback(m.queue_free)
	get_tree().create_timer(delay).timeout.connect(func():
		FX.flash(from, Color("ffc080"), 0.8, 0.08)
		FX.sparks(from, 6, [Color.WHITE, Color("ff9a40")], 5.0, 0.3, -4.0, 0.07))


func get_threats() -> Array:
	var out := threats.duplicate()
	for h in _markers:
		out.append(h.info)
	return out


# ── 피격 · 페이즈 ───────────────────────────────────────

func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	if not alive or st != St.FIGHT:
		# 등장·전환·폭발 중에는 튕겨낸다
		if randf() < 0.3:
			FX.sparks(pos, 3, [Color.WHITE, Color("a0a0c0")], 4.0, 0.2, -6.0, 0.05)
		return
	var amount := float(mini(dmg, 20))
	if source == "slash":
		amount = 12.0
	elif source == "phantom":
		amount = 22.0
	if weak:
		amount *= 2.0
	boss_hp = maxf(0.0, boss_hp - amount)
	bar.set_hp(boss_hp / MAX_HP, amount >= 5.0)
	kill_source = source
	var l := global_basis.inverse() * Vector3(dir.x, 0, dir.z)
	wob2_v += Vector2(l.z, -l.x) * minf(0.05 * amount, 0.8)
	punch = maxf(punch, minf(0.15 + amount * 0.05, 1.0))
	# 연사탄은 찌그러짐·불꽃만, 강한 공격만 흰색 섬광
	if amount >= 3.0 and flash_cd <= 0.0:
		flash_cd = 0.25
		_set_flash(true)
		get_tree().create_timer(0.04 if amount < 3.0 else 0.07).timeout.connect(func():
			if is_instance_valid(self):
				_set_flash(false))
	if hit_snd_cd <= 0.0:
		hit_snd_cd = 0.07
		Sfx.play("hit", 0.15, -8.0)
	if weak and randf() < 0.15:
		Main.inst.hud.popup("×2", Color("ffe060"), pos + Vector3(0, 1.5, 0))
	if phase == 1 and boss_hp <= MAX_HP * PHASE2_AT:
		boss_hp = MAX_HP * PHASE2_AT
		bar.set_hp(PHASE2_AT, true)
		_begin_transition()
	elif boss_hp <= 0.0:
		_begin_dying()


func _set_flash(on: bool) -> void:
	var rest_mat: Material = Pal.lock_hatch() if locked else null
	for mi in meshes:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = Pal.flash() if on else rest_mat


func _abort_pattern() -> void:
	if pat == "mega":
		Main.inst.dramatic(false)
	pat = ""
	weak = false
	bar.weak = false
	bar.set_pattern("")
	_clear_warnings()
	for g in muzzle_glow:
		(g as Node3D).scale = Vector3.ONE * 0.01


func _clear_bullets() -> void:
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		FX.flash((b as Node3D).position, Pal.E_BULLETS[2], 0.4, 0.1)
		b.queue_free()


func _begin_transition() -> void:
	_abort_pattern()
	_clear_bullets()
	st = St.TRANSITION
	st_t = 0.0
	ps = {"step": 0}
	Main.inst.hitstop(0.14)
	Main.inst.shake(0.9)
	Main.inst.hud.screen_flash(Color(1, 0.8, 0.7), 0.7)
	Sfx.play("overload", 0.0, 2.0)
	print("BOSS_PHASE2 t=%.1f" % Main.inst.time)


## 2페이즈 전환: 연쇄 폭발과 함께 보조포·미사일 포드·귀 포드·장갑 조각이 떨어져 나가고, 손상 부위에서 불꽃과 연기를 뿜는다
func _update_transition(_dt: float) -> void:
	var steps := [0.0, 0.45, 0.9, 1.3, 1.7]
	var s: int = ps.step
	if s < steps.size() and st_t >= steps[s]:
		ps.step = s + 1
		match s:
			0:
				_break_off(tank.sponsons[0], Vector3(-6, 9, 14))
				spons_alive[0] = false
				_wound(Vector3(-1.75, 2.7, -2.25))
			1:
				_break_off(tank.missile_pods[1], Vector3(5, 11, 10))
				_wound(Vector3(1.8, 2.8, 2.3))
			2:
				for n in (tank.turret as Node3D).get_children():
					if String(n.name).begins_with("EarPod") and (n as Node3D).position.x > 0.0:
						# 모델이 180도 돌아 있어 +X 귀 포드는 화면 왼쪽에 있다
						_break_off(n, Vector3(-7, 8, 12))
						_wound_on(tank.turret, Vector3(1.8, 0.95, -0.2))
						break
			3:
				for k in 6:
					_chunk()
				_scorch()
			4:
				Main.inst.hud.banner("PHASE 2", Color("ff4a5a"), "장갑이 뜯겨 나간 맘모스가 폭주합니다!")
				bar.set_phase(2)
				phase_changed.emit(2)
		# 매 단계 폭발
		var p := model.to_global(Vector3(randf_range(-2, 2), randf_range(2, 4), randf_range(-2, 2)))
		FX.enemy_explosion(p, 1.8)
		Sfx.play("boom", 0.1, 2.0)
		Main.inst.shake(0.6)
		Main.inst.hitstop(0.05)
		wob2_v += Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
		punch = 1.0
	if st_t > 2.6:
		st = St.FIGHT
		phase = 2
		pat_i = -1
		rest = 0.6
		_cache_meshes()


func _break_off(n: Node, vel: Vector3) -> void:
	if not is_instance_valid(n):
		return
	var nd := n as Node3D
	var gt := nd.global_transform
	nd.get_parent().remove_child(nd)
	stage.add_child(nd)
	nd.global_transform = gt
	# 이탈 부품은 화면 앞쪽(+Z, 뒤로 처짐)으로 날아가며 굴러 도로에 떨어진다
	stage.drift(nd, vel + Vector3(0, 0, randf_range(0, 6)), Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(5, 9), true, 4.0)
	FX.enemy_explosion(gt.origin, 1.4)
	FX.sparks(gt.origin, 24, [Color.WHITE, Color("ffd060"), Color("ff6a20")], 10.0, 0.5, -12.0, 0.09)
	_cache_meshes()


func _chunk() -> void:
	var c: Color = [BossTank.STEEL, BossTank.STEEL_MID, BossTank.STEEL_DARK][randi() % 3]
	var holder := Node3D.new()
	stage.add_child(holder)
	var sz := Vector3(randf_range(0.5, 1.3), randf_range(0.25, 0.6), randf_range(0.5, 1.3))
	BossTank.rbox(holder, sz, 0.12, Vector3.ZERO, c)
	holder.global_position = model.to_global(Vector3(randf_range(-2.2, 2.2), randf_range(2.2, 3.4), randf_range(-3, 3)))
	stage.drift(holder, Vector3(randf_range(-7, 7), randf_range(6, 12), randf_range(6, 16)), Vector3(randf(), randf(), randf()).normalized() * randf_range(6, 12), true, 3.5)


## 떨어져 나간 자리: 달아오른 소켓 + 연기 분출점
func _wound(local: Vector3) -> void:
	_wound_on(tank.hull, local)


func _wound_on(parent: Node3D, local: Vector3) -> void:
	BossTank.rbox(parent, Vector3(1.1, 0.25, 1.1), 0.1, local + Vector3(0, -0.1, 0), Color("1e1a22"))
	BossTank.glow(parent, Vector3(0.8, 0.12, 0.8), local, Color("ff6a20"), 2.0)
	var sp := Node3D.new()
	parent.add_child(sp)
	sp.position = local + Vector3(0, 0.3, 0)
	smoke_points.append(sp)


## 그을음과 갈라진 틈
func _scorch() -> void:
	var dark := Color("26222c")
	var spots := [Vector3(1.2, 2.93, 0.8), Vector3(-0.8, 2.93, 1.9), Vector3(1.5, 2.2, -3.2), Vector3(-1.4, 1.6, -3.55)]
	for p in spots:
		BossTank.rbox(tank.hull, Vector3(randf_range(0.7, 1.2), 0.08, randf_range(0.6, 1.1)), 0.04, p, dark)
		BossTank.glow(tank.hull, Vector3(randf_range(0.3, 0.6), 0.1, 0.06), p + Vector3(0, 0.04, 0), Color("ff7a30"), 2.0, Vector3(0, randf_range(0, 180), 0))
	for p in [Vector3(-1.2, 1.2, -0.6), Vector3(0.9, 1.5, 0.9)]:
		BossTank.rbox(tank.turret, Vector3(0.9, 0.5, 0.08), 0.04, p + Vector3(0, 0, -1.95), dark)


# ── 격파 ────────────────────────────────────────────────

func _begin_dying() -> void:
	_abort_pattern()
	_clear_bullets()
	st = St.DYING
	st_t = 0.0
	ps = {"cd": 0.0, "step": 0}
	alive = false
	remove_from_group("enemies")
	bar.set_hp(0.0, true)
	Main.inst.hitstop(0.2)
	Main.inst.shake(1.0)
	Main.inst.hud.screen_flash(Color.WHITE, 0.8)
	Sfx.play("overload", 0.0, 4.0)
	Main.inst.on_enemy_killed(self)
	print("BOSS_DOWN t=%.1f" % Main.inst.time)


## 연쇄 폭발 → 부품이 차례로 떨어져 나가며 뒤로 처지고 → 대폭발
func _update_dying(dt: float) -> void:
	ps.cd = float(ps.cd) - dt
	var k := clampf(st_t / 3.0, 0.0, 1.0)
	if ps.cd <= 0.0 and st_t < 3.0:
		ps.cd = lerpf(0.22, 0.06, k)
		var p := model.to_global(Vector3(randf_range(-3, 3), randf_range(0.8, 4.5), randf_range(-3.5, 3.5)))
		FX.enemy_explosion(p, randf_range(0.9, 1.6))
		Sfx.play("boom", 0.2, -2.0)
		Main.inst.shake(0.3)
		wob2_v += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 1.5
		if randf() < 0.5:
			_chunk()
	# 속도를 잃고 조금씩 뒤로 처진다 (플레이어 쪽으로 밀려옴)
	global_position.z = lerpf(global_position.z, BASE_Z + 1.5, 1.0 - exp(-0.8 * dt))
	visual.position.y -= k * 0.4 * dt
	var s: int = ps.step
	var marks := [0.8, 1.6, 2.3]
	if s < marks.size() and st_t >= marks[s]:
		ps.step = s + 1
		match s:
			0:
				if spons_alive[1]:
					_break_off(tank.sponsons[1], Vector3(6, 9, 14))
					spons_alive[1] = false
			1:
				_break_off(tank.missile_pods[0], Vector3(-5, 10, 12))
			2:
				for i in 2:
					_break_off(tank.cannons[i].pivot, Vector3(randf_range(-6, 6), 10, 16))
	if st_t >= 3.0 and st == St.DYING:
		st = St.DEAD
		_final_blast()


func _final_blast() -> void:
	var c := model.to_global(Vector3(0, 2.2, 0))
	for i in 5:
		var off := Vector3(randf_range(-2.5, 2.5), randf_range(0, 2), randf_range(-2.5, 2.5))
		FX.enemy_explosion(c + off, 3.0)
	FX.ring(Vector3(c.x, 0.3, c.z), 22.0, Pal.RING_ORANGE, 0.8)
	FX.shockwave(Vector3(c.x, 0.2, c.z), Color("ffd060"), 18.0, 0.6, 0.2)
	Main.inst.hud.screen_flash(Color.WHITE, 1.0)
	Main.inst.hitstop(0.25)
	Main.inst.shake(1.0)
	Sfx.play("boom", 0.0, 6.0)
	# 포탑과 궤도가 사방으로 튀고 나머지는 사라진다
	_break_off(tank.turret, Vector3(0, 16, 10))
	for tr in tank.treads:
		_break_off(tr, Vector3(signf((tr as Node3D).global_position.x) * 8, 7, 18))
	for i in 10:
		_chunk()
	visual.visible = false
	shadow.visible = false
	defeated.emit()
