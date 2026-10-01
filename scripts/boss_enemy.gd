extends Enemy
## 추격 보스 "맘모스". 뒤로 달아나며(후진) 플레이어를 향해 싸운다.
## 1페이즈 패턴 4개 → 체력 40% 에서 파츠가 떨어져 나가며 2페이즈 → 패턴 3개 (강력 예고 공격 포함).
## 판정·진행은 이 파일, 흐르는 배경·연기 이동은 boss_stage.gd 가 맡는다.

const BossTank := preload("res://scripts/boss_tank.gd")
const Stage := preload("res://scripts/boss_stage.gd")
const Bar := preload("res://scripts/boss_bar.gd")
const HitLift := preload("res://scripts/presentation/mammoth_hit_lift.gd")
const DeathDirector := preload("res://scripts/lab_mammoth_b/mammoth_b_director.gd")

signal phase_changed(phase: int)
signal defeated

enum St { ENTER, FIGHT, TRANSITION, DYING, DEAD }

const MAX_HP := 800.0
const PHASE2_AT := 0.4
const BASE_Z := -10.5
const ENTER_TIME := 3.2
const PLANE_Y := 1.0              # 탄이 날아가는 높이 (판정은 수평 거리)

## 근접 견제: 붙어서 검만 휘두르는 플레이 방지
const NEAR_R := 7.5               # 보스 중심에서 이 거리 안이면 '붙어 있다' (검 사거리 2.9 + 보스 반경 3.3 포함)
const SHOCK_R := 9.0              # 밀쳐내기 충격파 반경
const SHOCK_TELE := 0.55          # 충격파 예고 시간
const SHOCK_CHANCE := 0.35        # 0.6초마다 굴리는 기본 확률 (붙어 있을수록 +최대 0.3)
const SHOCK_CD := 3.2
const SHOCK_PUSH := 26.0
const STUN_TIME := 0.7            # 푸른 경직탄에 맞았을 때 경직 시간

const PATTERNS_1 := ["volley", "gatling", "missiles", "gapring"]
const PATTERNS_2 := ["spiral", "lanes", "mega"]
const NAMES := {
	"volley": "쌍포 조준 연사", "gatling": "개틀링 교차 소사", "missiles": "추적 미사일 폭격", "gapring": "틈새 원형탄",
	"spiral": "이중 나선 탄막", "lanes": "레인 포격", "mega": "!! 거수포 — 강력 예고 공격 !!",
}

var stage: Stage
## 강력 레이저가 관통하지 못하고 표면에서 막힌다 (beam_impact.gd 가 읽음)
var blocks_beam := true
## 보스: 검술 콤보 마무리(5타) 뒤 숨 고르기가 길어진다 (sword_combo.gd 가 읽음, 붙어서 무한 연타 방지)
var no_slash_reset := true
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
var near_t := 0.0                 # 플레이어가 붙어 있은 시간
var shock_roll := 0.0
var shock_cd := 1.5
var shock_t := -1.0               # 0 이상이면 충격파 예고 중
var shock_ring: MeshInstance3D
var guard_cd := 0.0
## 연출: 강력 레이저에 맞은 쪽이 들리며 떨린다 (mammoth_hit_lift.gd)
var lift := HitLift.new()
var _grind_cd := 0.0
## 연출: 격파 시네마틱 (B안 궤도 파손과 전복). 시작되면 visual 의 변환은 감독이 소유한다
var death_fx: DeathDirector


func _ready() -> void:
	add_to_group("enemies")
	is_boss = true
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
	_update_close(dt, player)
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
	_update_lift(dt)
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
	elif pat != "mega" and shock_t < 0.0:
		core.set_instance_shader_parameter("tint", Pal.E_RED)
		core.set_instance_shader_parameter("energy", 1.6 + sin(t * (4.0 if phase == 1 else 9.0)) * 0.5)
		core.scale = core.scale.lerp(Vector3.ONE, 1.0 - exp(-6.0 * dt))


# ── 발사 도우미 ─────────────────────────────────────────

func _shot(from: Vector3, dir: Vector3, speed: float, big := false) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	Main.inst.add_bullet(Bullet.make_enemy(Vector3(from.x, PLANE_Y, from.z), d, speed, big))


## 푸른 경직탄: 검으로 지울 수 없고, 맞으면 체력 1칸 + 0.7초 경직
func _blue(from: Vector3, dir: Vector3, speed: float, life := 5.0) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	Main.inst.add_bullet(Bullet.make_blue(Vector3(from.x, PLANE_Y, from.z), d, speed, STUN_TIME, life))


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
				# 파동마다 몇 발은 검으로 못 지우는 푸른 탄 → 베면서 뚫고 들어가면 맞는다
				if i % 6 == (n * 2) % 6:
					_blue(c, _dir_from_angle(a), 5.4)
				else:
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
					if k % 4 == 0:
						_blue(c, _dir_from_angle(a), 4.2)
					else:
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
		if pt >= CHARGE - Parry.TRAVEL and not ps.get("danger", false):
			# 발사 0.4초 전: 패링 불가 공격의 붉은 섬광 (패링 공격과 같은 리듬)
			ps.danger = true
			DangerFX.warn(core.global_position)
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
				if i % 3 == 0:
					_blue(c, _dir_from_angle(off2 + TAU * i / 14.0), 3.6)
				else:
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
			var in_beam := (rel - dir * along).length() < WIDTH * 0.5 + player.hit_radius
			if in_beam and player.invuln > 0.0:
				DangerFX.evaded(player, origin + dir * along)
			if in_beam and player.invuln <= 0.0:
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
	var mi := _ring_mesh(r)
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


## 바닥 원형 경고 메시 (반지름 r). progress 로 안쪽이 차오르고, 3/4 이후 깜빡인다
func _ring_mesh(r: float, col := Color(1.0, 0.12, 0.1)) -> MeshInstance3D:
	if _marker_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never, blend_add;
instance uniform float progress = 0.0;
instance uniform vec4 col : source_color = vec4(1.0, 0.12, 0.1, 1.0);
void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float ring = smoothstep(0.9, 0.95, r) * (1.0 - smoothstep(0.98, 1.0, r));
	float fill = step(r, progress) * 0.35 * (1.0 - step(1.0, r));
	float cross = (step(abs(UV.x - 0.5), 0.012) + step(abs(UV.y - 0.5), 0.012)) * step(r, 0.35);
	float blink = mix(1.0, step(0.5, fract(TIME * 14.0)), step(0.75, progress));
	float i = (ring * 1.6 + fill + cross * 0.8 + 0.08 * (1.0 - step(1.0, r))) * blink;
	ALBEDO = col.rgb * i;
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
	mi.set_instance_shader_parameter("col", col)
	return mi


# ── 근접 견제 ───────────────────────────────────────────
# 붙어서 검만 휘두르면: ① 몸체에서 푸른 경직탄이 흩뿌려지고 ② 확률적으로 충격파가 밀어낸다.
# 패턴과 별개로 돌며, 거수포 충전 중에는 충격파를 쓰지 않는다.

func _update_close(dt: float, player: Player) -> void:
	var rel := player.global_position - global_position
	rel.y = 0
	var near := rel.length() < NEAR_R
	near_t = near_t + dt if near else maxf(0.0, near_t - dt * 2.0)
	shock_cd -= dt
	if shock_t >= 0.0:
		_update_shock(dt, player)
	elif near_t > 0.5 and shock_cd <= 0.0 and pat != "mega":
		shock_roll -= dt
		if shock_roll <= 0.0:
			shock_roll = 0.6
			# 오래 붙어 있을수록 확률이 오른다
			if randf() < SHOCK_CHANCE + minf((near_t - 0.5) * 0.15, 0.3):
				_begin_shock()
	guard_cd -= dt
	if near and near_t > 0.25 and guard_cd <= 0.0:
		guard_cd = 1.2 if phase == 1 else 0.85
		_guard_burst(player)


## 장갑 틈에서 푸른 경직탄이 흩뿌려진다: 0.25초 예고(푸른 섬광) 뒤 플레이어 쪽 부채꼴로 느리게 퍼진다
func _guard_burst(player: Player) -> void:
	var to := _aim_from(global_position, player.global_position)
	var side := Vector3(-to.z, 0, to.x)
	var count := 5 if phase == 1 else 7
	var spots: Array = []
	for i in count:
		var u := (i - (count - 1) * 0.5) / maxf(count - 1, 1) * 2.0       # -1 ~ 1
		var p := global_position + to * 2.9 + side * u * 2.6
		p.y = PLANE_Y
		spots.append(p)
		FX.flash(p, Color("8ad8ff"), 0.7, 0.25)
	Sfx.play("echarge", 0.1, -10.0)
	get_tree().create_timer(0.25, false).timeout.connect(func():
		if not is_instance_valid(self) or st != St.FIGHT:
			return
		for i in spots.size():
			var p: Vector3 = spots[i]
			var d := to.rotated(Vector3.UP, randf_range(-0.55, 0.55) + (i - (spots.size() - 1) * 0.5) * 0.12)
			_blue(p, d, randf_range(4.6, 6.0), 1.9)
			FX.sparks(p, 3, [Color.WHITE, Color("3aa8ff")], 4.0, 0.2, -4.0, 0.05)
		Sfx.play("eshot", 0.1, -6.0))


func _begin_shock() -> void:
	shock_t = 0.0
	shock_ring = _ring_mesh(SHOCK_R, Color(0.35, 0.75, 1.0))
	stage.add_child(shock_ring)
	shock_ring.global_position = Vector3(global_position.x, 0.06, global_position.z)
	Main.inst.hud.popup("!", Color("8ad8ff"), _core_pos() + Vector3(0, 2.5, 0))
	Sfx.play("echarge", 0.0, -2.0)
	print("BOSS_SHOCK near=%.1f" % near_t)


func _update_shock(dt: float, player: Player) -> void:
	shock_t += dt
	var k := clampf(shock_t / SHOCK_TELE, 0.0, 1.0)
	if is_instance_valid(shock_ring):
		shock_ring.global_position = Vector3(global_position.x, 0.06, global_position.z)
		shock_ring.set_instance_shader_parameter("progress", k)
	# 몸을 웅크리며 코어가 푸르게 달아오른다
	var core := tank.core as MeshInstance3D
	core.set_instance_shader_parameter("tint", Color("3aa8ff").lerp(Color.WHITE, k))
	core.set_instance_shader_parameter("energy", 2.0 + k * 3.0)
	punch = maxf(punch, k * 0.6)
	threats.append({"type": "circle", "pos": global_position, "r": SHOCK_R})
	if shock_t >= SHOCK_TELE:
		_fire_shock(player)


## 충격파: 반경 안의 플레이어를 앞(+Z)으로 크게 밀어내고, 앞쪽 반원으로 푸른 경직탄 고리를 퍼뜨린다
func _fire_shock(player: Player) -> void:
	_cancel_shock()
	shock_cd = SHOCK_CD
	near_t = 0.0
	var c := global_position
	FX.shockwave(Vector3(c.x, 0.3, c.z), Color("8ad8ff"), SHOCK_R * 2.0, 0.35, 0.14)
	FX.shockwave(Vector3(c.x, 0.5, c.z), Color.WHITE, SHOCK_R * 1.3, 0.25, 0.08)
	FX.flash(_core_pos(), Color("bfe8ff"), 2.6, 0.12)
	Sfx.play("boom", 0.05, 1.0)
	Main.inst.shake(0.6)
	Main.inst.hitstop(0.05)
	punch = 1.0
	var rel := player.global_position - c
	rel.y = 0
	# 대시(무적 구르기)로는 흘려 낼 수 있다
	if player.alive and player.dash_t <= 0.0 and rel.length() < SHOCK_R + player.hit_radius:
		var d := rel.normalized() if rel.length() > 0.1 else Vector3.BACK
		player.shove((d + Vector3.BACK * 0.6).normalized(), SHOCK_PUSH)
		Main.inst.kick(d * 0.8)
	var cp := _core_pos()
	var off := randf_range(-0.12, 0.12)
	for i in 11:
		var a := off + (i - 5) * 0.34
		_blue(cp, _dir_from_angle(a), 5.2, 3.0)


func _cancel_shock() -> void:
	shock_t = -1.0
	if is_instance_valid(shock_ring):
		shock_ring.queue_free()
	shock_ring = null


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
	if source == "laser":
		_laser_lift(dmg, dir)
	HitSpark.spawn(fx_point(pos, dir), dir, clampf(1.0 + amount * 0.06, 1.0, 2.4), self)
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
	_cancel_shock()
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
				# 큰 글자는 컷인 타이포가 맡고, 가운데 배너는 안내 문구만 남긴다
				CutIn.slam("PHASE 2", "MAMMOTH 장갑 파괴 · 폭주", Color("ff4a5a"), 0.5)
				Main.inst.hud.banner("", Color("ff4a5a"), "장갑이 뜯겨 나간 맘모스가 폭주합니다!")
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
	# 판정 기준 격파는 여기서 끝난다. 남은 화면은 죽음 연출(B안 궤도 파손과 전복) 감독이 소유하고,
	# 감독이 끝나면 defeated 를 보낸다. 예전 연쇄 폭발(_update_dying · _final_blast)은 쓰지 않는다.
	st = St.DEAD
	st_t = 0.0
	alive = false
	remove_from_group("enemies")
	_set_flash(false)
	lift = HitLift.new()
	Main.inst.on_enemy_killed(self)
	print("BOSS_DOWN t=%.1f" % Main.inst.time)
	var m := Main.inst
	var pl := m.player
	var px := pl.global_position.x if is_instance_valid(pl) else 0.0
	death_fx = DeathDirector.new()
	m.add_child(death_fx)
	death_fx.finished.connect(func(_reason: String): defeated.emit())
	death_fx.begin({
		"main": m, "dummy": self, "stage": stage, "boss_cam": m.camera, "bar": bar, "speed_fx": m.get("speed_fx"),
		"side": DeathDirector.pick_side(global_position.x, px),
	})
	# 격파 쇼타임(Showtime)은 쓰지 않는다: 죽음 연출 감독이 시간 · 카메라 · HUD 를 쥐므로 컷인 타이포만 얹는다
	CutIn.slam("MAMMOTH DOWN", "거대 중전차 MAMMOTH 격파", Color("ff3a4a"))


## 죽음 연출이 시작됐는가 (진행 중이거나 끝남). boss_main.gd 가 입력 잠금 · 전장 경계에 쓴다
func death_started() -> bool:
	return death_fx != null and is_instance_valid(death_fx) and (death_fx.active or death_fx.done)


## 예전 격파 연출 (연쇄 폭발 3초 → 대폭발). 죽음 연출 감독으로 바뀌어 지금은 쓰지 않는다
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


# ── 연출: 착탄 위치 · 레이저 피격 들림 ─────────────────

## 탄 판정은 반지름 3.3 원기둥이라 착탄점이 차체(반폭 3.45 · 반길이 3.6) 안쪽 낮은 곳에 묻혀 가려진다.
## 연출용 위치만 맞은 방향 반대로 거슬러 차체 겉면까지 꺼내고, 카메라 쪽으로 조금 띄운다.
func fx_point(pos: Vector3, fwd: Vector3) -> Vector3:
	var lo := Vector3(-3.55, -0.2, -3.75)
	var hi := Vector3(3.55, 3.0, 3.75)
	var p := to_local(pos)
	var d := -(global_basis.inverse() * fwd)
	d.y = 0.0
	if d.length() < 0.01:
		return pos
	d = d.normalized()
	# 상자 안에서 출발해 빠져나가는 거리 (슬랩 방식)
	var t_out := 1e9
	for i in 3:
		if absf(d[i]) > 0.0001:
			var bound: float = hi[i] if d[i] > 0.0 else lo[i]
			t_out = minf(t_out, (bound - p[i]) / d[i])
	if t_out < 0.0 or t_out > 6.0:
		return pos
	var w := to_global(p + d * (t_out + 0.08))
	w.y = maxf(w.y, 1.2)
	var cam := get_viewport().get_camera_3d()
	if cam:
		w += (cam.global_position - w).normalized() * 0.35
	return w


## 강력 레이저: 빔이 차체에 닿은 지점을 구해 그쪽을 들어 올린다
func _laser_lift(dmg: int, dir: Vector3) -> void:
	var pl := Main.inst.player
	if not is_instance_valid(pl):
		return
	var f := Vector3(dir.x, 0, dir.z)
	if f.length() < 0.01:
		return
	f = f.normalized()
	var rel := global_position - pl.global_position
	rel.y = 0
	var along := rel.dot(f)
	var perp := rel - f * along                      # 빔에서 보스 중심까지 옆 거리
	var pd := minf(perp.length(), radius)
	var hit := -perp.normalized() * pd if perp.length() > 0.01 else Vector3.ZERO
	hit -= f * sqrt(maxf(0.0, radius * radius - pd * pd))   # 빔이 처음 닿는 겉면
	var local := global_basis.inverse() * hit
	# 지속 레이저 틱(2)은 약하게 계속, 충전 레이저(3~10)는 한 번에 크게
	var k := 0.32 if dmg <= 2 else lerpf(0.5, 1.35, clampf((dmg - 3.0) / 7.0, 0.0, 1.0))
	lift.kick(Vector2(local.x, local.z), k)
	if dmg > 2:
		var at := global_position + hit + Vector3(0, 1.4, 0)
		FX.sparks(at, int(10 + 14 * k), [Color.WHITE, Color("9ff8ff"), Color("ffd060")], 9.0, 0.35, -12.0, 0.08)
		Main.inst.shake(0.25 + 0.35 * k)
		Sfx.play("clank", 0.1, -4.0 + 4.0 * k)


func _update_lift(dt: float) -> void:
	var landed: Variant = lift.step(dt)
	visual.transform = lift.compose() * visual.transform
	if landed != null and stage:
		# 들렸던 모서리가 도로를 다시 찍는다
		var e: Vector2 = landed
		var p := to_global(Vector3(e.x, 0.15, e.y))
		FX.sparks(p, 16, [Color.WHITE, Color("ffd060"), Color("ff7a30")], 9.0, 0.3, -14.0, 0.08)
		for i in 3:
			stage.puff(p + Vector3(randf_range(-1.2, 1.2), 0.2, randf_range(-1.2, 1.2)), Color(0.5, 0.46, 0.55, 0.5), randf_range(1.4, 2.2), 0.4, 0.9)
		Main.inst.shake(0.3)
		Sfx.play("land", 0.15, -2.0)
	# 들려 있는 동안 축이 된 반대쪽 궤도 모서리가 도로에 갈린다
	_grind_cd -= dt
	if lift.lifted() > 0.1 and _grind_cd <= 0.0:
		_grind_cd = 0.04
		var u := lift.tilt.normalized()
		var edge := to_global(Vector3(-u.x, 0, -u.y) * HitLift.HALF + Vector3(randf_range(-1.5, 1.5) * u.y, 0.1, randf_range(-1.5, 1.5) * u.x))
		FX.sparks(edge, 5, [Color.WHITE, Color("ffd060"), Color("ff7a30")], 7.0, 0.25, -12.0, 0.06)
		if stage and randf() < 0.5:
			stage.puff(edge + Vector3(0, 0.2, 0), Color(0.5, 0.46, 0.55, 0.4), 1.2, 0.3, 0.9)
