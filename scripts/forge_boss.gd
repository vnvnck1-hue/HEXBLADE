extends Enemy
## 용광로 보스 "VULCAN". 하반신이 용암에 잠긴 채 팔각 발판 북쪽에 버티고, 두 팔(도가니 포신)과 다섯 눈으로 싸운다.
## 1페이즈 패턴 4개 → 체력 40%: 가슴 장갑이 터져 노심이 드러나고, 두 팔로 발판을 내리쳐 바깥 고리가 용암에 가라앉는다
## (전장 반경 12m → 8m) → 2페이즈 패턴 4개 (강력 예고 공격 포함).
## 판정·진행은 이 파일, 발판·용암·불길 연출은 forge_stage.gd, 모델은 forge_titan.gd, 팔 피격 판정은 forge_fist.gd.

const Titan := preload("res://scripts/forge_titan.gd")
const Stage := preload("res://scripts/forge_stage.gd")
const Bar := preload("res://scripts/boss_bar.gd")
const Fist := preload("res://scripts/forge_fist.gd")
const MoltenSplash := preload("res://scripts/presentation/molten_splash.gd")

signal phase_changed(phase: int)
signal defeated

enum St { ENTER, FIGHT, TRANSITION, DYING, DEAD }

const MAX_HP := 1000.0
const PHASE2_AT := 0.4
const HOME := Vector3(0, 0, -16.5)
const ENTER_TIME := 3.8
const RISE_FROM := -15.0
const PLANE_Y := 1.0              # 탄이 날아가는 높이 (판정은 수평 거리)
const L := Titan.ARM_LEN
const REACH := 16.0               # 어깨에서 주먹이 닿는 수평 거리
const SLAM_R := 2.7
const CONE_R := 13.5
const BEAM_W := 2.6
const BEAM_LEN := 30.0
const WEDGE_IN := 1.8

const PATTERNS_1 := ["cone", "slam", "eyes", "slag"]
const PATTERNS_2 := ["breath", "double_slam", "eruption", "cone2"]
const NAMES := {
	"cone": "용광포 화염 분사", "slam": "도가니 내려찍기", "eyes": "오안 조준 사격", "slag": "슬래그 낙하",
	"breath": "!! 노심 화염 방사 — 강력 예고 공격 !!", "double_slam": "연속 내려찍기", "eruption": "용암 분출", "cone2": "쌍 용광포 교차 분사",
}
const EYE_ORDER := [1, 2, 4, 3, 0]

var stage: Stage
## 강력 레이저가 관통하지 못하고 표면에서 막힌다 (beam_impact.gd 가 읽음)
var blocks_beam := true
var bar: Bar
var st := St.ENTER
var st_t := 0.0
var phase := 1
var boss_hp := MAX_HP
var tt: Dictionary
var meshes: Array = []
var pat := ""
var pat_i := -1
var pt := 0.0
var ps := {}
var rest := 1.6
var weak := false
var weak_t := 0.0
var flash_cd := 0.0
var hit_snd_cd := 0.0
var arms: Array = []              # {i, side, upper, fore, glow, rings, m, goal, rate, busy, down, fist, charge, tip}
var puddles: Array = []           # {pos, r, t}
var threats: Array = []           # 자동 플레이 회피용
var warnings: Array = []
var _markers: Array = []
var eye_level: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
var eye_flash: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
var eye_k: Array = [0.0, 0.0, 0.0, 0.0, 0.0]
var core_k := 0.0
var core_open := false
var head_yaw := 0.0
var head_nod := 0.0
var lean := Vector2.ZERO
var lean_v := Vector2.ZERO
var fx_cd := 0.0
var smoke_points: Array = []
var beam: Node3D
var _drop_mesh: SphereMesh
var _molten: MoltenSplash


func _ready() -> void:
	add_to_group("enemies")
	is_boss = true
	radius = 6.2
	slice_size = Vector3(4, 3, 4)
	slice_color = Titan.IRON
	visual = Node3D.new()
	add_child(visual)
	var arm_root := Node3D.new()
	add_child(arm_root)
	tt = Titan.build(visual, arm_root)
	j = {"body": tt.body, "core": tt.core}
	shadow = FX.blob_shadow(self, 0.1, 0.0)
	shadow.visible = false
	for i in 2:
		var parts: Dictionary = tt.arms[i]
		var fist := Fist.new()
		fist.boss = self
		fist.arm_index = i
		fist.bind(parts.fore)
		arms.append({"i": i, "side": -1 if i == 0 else 1, "upper": parts.upper, "fore": parts.fore, "glow": parts.glow, "rings": parts.rings,
			"m": Vector3.ZERO, "goal": Vector3.ZERO, "rate": 3.0, "busy": false, "down": false, "fist": fist, "charge": 0.0, "tip": Vector3.ZERO})
	landed = false
	global_position = HOME + Vector3(0, RISE_FROM, 0)
	for a in arms:
		(a as Dictionary).m = _rest_goal(a)
		(a as Dictionary).goal = (a as Dictionary).m
	_cache_meshes()
	_add_fists.call_deferred()


func _add_fists() -> void:
	for a in arms:
		get_parent().add_child((a as Dictionary).fist)


func _cache_meshes() -> void:
	meshes = find_children("*", "MeshInstance3D", true, false)
	meshes.erase(shadow)


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
	_update_puddles(dt, player)
	_update_arms(dt, player)
	_update_body(dt, player)


func _update_enter(_dt: float) -> void:
	# 용암 속에서 천천히 솟아오른다
	var k := clampf(st_t / ENTER_TIME, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	global_position.y = lerpf(RISE_FROM, 0.0, e)
	fx_cd -= _dt
	if fx_cd <= 0.0 and k < 0.92:
		fx_cd = 0.07
		var p := HOME + Vector3(randf_range(-7, 7), Stage.LAVA_Y, randf_range(-4, 4.5))
		stage.splash(p, randf_range(0.9, 1.6))
		Main.inst.shake(0.05)
	for i in 5:
		eye_level[i] = 1.0 if k > 0.7 + EYE_ORDER.find(i) * 0.05 else 0.0
	if k >= 1.0:
		st = St.FIGHT
		st_t = 0.0
		landed = true
		rest = 1.0
		_roar()


func _roar() -> void:
	Main.inst.shake(0.8)
	Main.inst.hitstop(0.06)
	FX.shockwave(Vector3(HOME.x, 0.3, HOME.z + 5.0), Color("ff8a30"), 26.0, 0.7, 0.2)
	FX.ring(Vector3(HOME.x, 0.3, HOME.z + 4.0), 18.0, Pal.RING_ORANGE, 0.7)
	for i in 5:
		eye_flash[i] = 1.0
	var s := Sfx.play("overload", 0.0, 2.0)
	if s:
		s.pitch_scale = 0.45
	Sfx.play("boom", 0.0, 0.0)


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
		_end_pattern()
		rest = 1.2 if phase == 1 else 0.85


func _next_pattern() -> void:
	var list: Array = PATTERNS_1 if phase == 1 else PATTERNS_2
	pat_i = (pat_i + 1) % list.size()
	pat = list[pat_i]
	pt = 0.0
	ps = {}
	bar.set_pattern(NAMES[pat])
	print("BOSS_PATTERN %s phase=%d hp=%.0f" % [pat, phase, boss_hp])


func _end_pattern() -> void:
	pat = ""
	bar.set_pattern("")
	_clear_warnings()
	for a in arms:
		var ad: Dictionary = a
		ad.busy = false
		ad.down = false
		ad.charge = 0.0
	stage.tip_crucibles(false)


# ── 팔 (IK) ─────────────────────────────────────────────

func _shoulder_world(a: Dictionary) -> Vector3:
	return (tt.body as Node3D).to_global(Titan.SHOULDERS[a.i])


func _shoulder_ground(a: Dictionary) -> Vector3:
	var s := _shoulder_world(a)
	return Vector3(s.x, 0, s.z)


## 쉬는 자세: 발판 북쪽 대각선 변 바깥(용암 위)에 포신을 걸친다
func _rest_goal(a: Dictionary) -> Vector3:
	var s := _shoulder_world(a)
	var side: float = a.side
	return s + Vector3(side * 3.4, -5.6, 6.0) + Vector3(0, sin(t * 1.1 + a.i * 2.0) * 0.35, 0)


func _update_arms(dt: float, player: Player) -> void:
	for a in arms:
		var ad: Dictionary = a
		if not ad.busy:
			ad.goal = _rest_goal(ad)
			ad.rate = 3.0
		var rate: float = ad.rate
		ad.m = ad.goal if rate <= 0.0 else (ad.m as Vector3).lerp(ad.goal, 1.0 - exp(-rate * dt))
		_pose(ad)
		var fist: Enemy = ad.fist
		if is_instance_valid(fist):
			var tip: Vector3 = ad.tip
			fist.global_position = Vector3(tip.x, 0, tip.z)
			fist.landed = ad.down and st == St.FIGHT and alive
		# 박힌 주먹은 플레이어를 밀어낸다
		if ad.down and player.alive:
			var tip: Vector3 = ad.tip
			var rel := player.global_position - Vector3(tip.x, 0, tip.z)
			rel.y = 0
			if rel.length() < 1.7:
				var n := rel.normalized() if rel.length() > 0.05 else Vector3.BACK
				player.global_position += n * (1.7 - rel.length())
		# 포신 발광 (충전 · 발사)
		var charge: float = ad.charge
		var g: MeshInstance3D = ad.glow
		g.set_instance_shader_parameter("energy", 1.4 + charge * 3.2 + (sin(t * 40.0) * 0.4 * charge))
		g.scale = Vector3(1, 1, 0.35) * (1.0 + charge * 0.5)
		for r in ad.rings:
			(r as MeshInstance3D).set_instance_shader_parameter("energy", 1.6 + charge * 2.5 + (1.0 if weak else 0.0))


## 2관절 IK: 어깨 S 에서 목표 M 까지, 팔꿈치는 위·바깥쪽으로 굽는다. 두 마디 길이는 같다(L).
func _pose(a: Dictionary) -> void:
	var s := _shoulder_world(a)
	var to: Vector3 = (a.m as Vector3) - s
	var d := clampf(to.length(), 3.0, L * 2.0 - 0.05)
	var dir := to.normalized() if to.length() > 0.01 else Vector3.DOWN
	var side: float = a.side
	var pole := Vector3(side * 0.7, 1.0, 0.25)
	var pp := pole - dir * pole.dot(dir)
	if pp.length() < 0.01:
		pp = Vector3(side, 0, 0)
	pp = pp.normalized()
	var ca := clampf(d / (2.0 * L), -1.0, 1.0)
	var sa := sqrt(maxf(0.0, 1.0 - ca * ca))
	var e := s + dir * ca * L + pp * sa * L
	var m := s + dir * d
	(a.upper as Node3D).global_transform = Transform3D(_look(e - s), s)
	(a.fore as Node3D).global_transform = Transform3D(_look(m - e), e)
	a.tip = m


func _look(v: Vector3) -> Basis:
	var f := v.normalized()
	var up := Vector3.UP if absf(f.y) < 0.97 else Vector3.BACK
	return Basis.looking_at(f, up)


# ── 몸 · 눈 · 노심 연출 ─────────────────────────────────

func _update_body(dt: float, player: Player) -> void:
	var body: Node3D = tt.body
	lean_v += (-lean * 30.0 - lean_v * 6.0) * dt
	lean += lean_v * dt
	punch = move_toward(punch, 0.0, dt * 4.0)
	body.position.y = sin(t * 1.2) * 0.14 - punch * 0.25
	body.rotation = Vector3(lean.x + sin(t * 0.7) * 0.012, 0, lean.y)
	# 머리는 플레이어를 내려다본다
	var head: Node3D = tt.head
	if player and st != St.DYING:
		var hp := head.global_position
		var to := player.global_position - hp
		var want := clampf(atan2(to.x, to.z), -0.65, 0.65)
		head_yaw = lerp_angle(head_yaw, want, 1.0 - exp(-3.0 * dt))
	head.rotation = Vector3(0.2 + head_nod, head_yaw, 0)
	# 눈
	for i in 5:
		eye_flash[i] = maxf(0.0, float(eye_flash[i]) - dt * 3.0)
		eye_k[i] = lerpf(float(eye_k[i]), float(eye_level[i]), 1.0 - exp(-8.0 * dt))
		var e: MeshInstance3D = tt.eyes[i]
		var k: float = eye_k[i]
		var fl: float = eye_flash[i]
		var flicker := 1.0 + sin(t * 23.0 + i * 1.9) * 0.08
		e.set_instance_shader_parameter("energy", (0.15 + k * 2.4 + fl * 3.0) * flicker)
		e.set_instance_shader_parameter("tint", Titan.HOT.lerp(Color(1, 1, 0.9), fl))
		e.scale = Vector3(1, 1, 0.5) * (1.0 + fl * 0.5)
	(tt.face_ring as MeshInstance3D).set_instance_shader_parameter("energy", 0.4 + float(eye_k[0]) * 1.8 + core_k * 1.5)
	# 노심 (2페이즈에 드러나고, 과열 중에는 노랗게 깜빡)
	var core: MeshInstance3D = tt.core
	if weak:
		core.set_instance_shader_parameter("tint", Color("ffe060") if fmod(t, 0.16) < 0.08 else Color("ff8a20"))
		core.set_instance_shader_parameter("energy", 3.2)
		core.scale = Vector3.ONE * (1.25 + sin(t * 30.0) * 0.08)
	else:
		var base := 1.4 if not core_open else 2.0
		core.set_instance_shader_parameter("tint", Titan.MOLTEN.lerp(Color("fff4d0"), core_k))
		core.set_instance_shader_parameter("energy", base + sin(t * (3.0 if phase == 1 else 7.0)) * 0.4 + core_k * 4.5)
		core.scale = core.scale.lerp(Vector3.ONE * (1.0 + core_k * 0.45), 1.0 - exp(-8.0 * dt))
	for d in tt.drips:
		var dm := d as Node3D
		dm.scale.y = 1.0 + sin(t * 2.3 + dm.position.x * 4.0) * 0.12
	# 굴뚝 연기 · 상처 불꽃 · 몸통 둘레 용암 거품
	fx_cd -= dt
	if fx_cd <= 0.0 and st != St.ENTER:
		fx_cd = 0.08
		for sp in tt.stacks:
			var p := (sp as Node3D).global_position
			stage.fire(p, Vector3(randf_range(-0.4, 0.4), randf_range(2.5, 4.0), randf_range(-0.6, 0.0)), randf_range(1.8, 2.8), 2.2, Color(0.16, 0.12, 0.13, 0.5), false, 0.6)
			if randf() < 0.35:
				stage.fire(p, Vector3(0, 5.0, 0), 0.9, 0.4, Color(1.0, 0.5, 0.12, 0.8), true, 0.0)
		for sp in smoke_points:
			if is_instance_valid(sp):
				var fire := randf() < 0.4
				stage.fire((sp as Node3D).global_position, Vector3(randf_range(-0.5, 0.5), randf_range(1.5, 3.0), 0.5), 1.4 if fire else 2.0, 0.5 if fire else 1.4, Color(1.0, 0.45, 0.1, 0.85) if fire else Color(0.14, 0.1, 0.12, 0.55), fire, 0.8)
		if randf() < 0.25 and st != St.DEAD:
			var a := randf() * TAU
			stage.splash(global_position + Vector3(cos(a) * 6.2, Stage.LAVA_Y - global_position.y, sin(a) * 4.8), 0.45)


# ── 판정 도우미 ─────────────────────────────────────────

func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x, 0, p.z)


func _hurt(from: Vector3, extra := 0) -> void:
	var pl := Main.inst.player
	if pl.take_hit(from) and extra > 0:
		pl.hp -= extra
		Main.inst.hud.popup("-%d" % (extra + 1), Color("ff4050"), pl.global_position + Vector3(0, 2.4, 0))
		if pl.hp <= 0 and pl.alive:
			var d := pl.global_position - from
			d.y = 0
			pl.die(d.normalized() * 3.0)


func _in_circle(player: Player, c: Vector3, r: float) -> bool:
	return Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length() < r + player.hit_radius * 0.5


func _in_fan(player: Player, apex: Vector3, dir_a: float, half: float, r_out: float) -> bool:
	var rel := player.global_position - apex
	rel.y = 0
	var r := rel.length()
	if r > r_out + player.hit_radius:
		return false
	if r < 0.6:
		return true
	return absf(angle_difference(atan2(rel.x, rel.z), dir_a)) <= half + player.hit_radius / r


func _shot(from: Vector3, dir: Vector3, speed: float, big := false) -> void:
	var d := Vector3(dir.x, 0, dir.z).normalized()
	Main.inst.add_bullet(Bullet.make_enemy(Vector3(from.x, PLANE_Y, from.z), d, speed, big))


func _aim_from(from: Vector3, target: Vector3) -> Vector3:
	var d := target - from
	d.y = 0
	return d.normalized() if d.length() > 0.01 else Vector3.BACK


func _eye_pos(i: int) -> Vector3:
	return (tt.eyes[i] as Node3D).global_position


func _core_ground() -> Vector3:
	var c := (tt.core as Node3D).global_position
	return Vector3(c.x, 0, c.z + 0.6)


# ── 1페이즈 ─────────────────────────────────────────────

## 용광포 화염 분사: 한쪽 팔이 포신을 플레이어에게 겨누고 바닥에 부채꼴로 범위를 예고한 뒤 불길을 뿜는다. 좌우 번갈아 4회.
func _p_cone(dt: float, player: Player) -> bool:
	return _cone(dt, player, false)


## 쌍 용광포: 두 팔이 동시에 — 한쪽은 지금 위치, 다른 쪽은 이동 예측 위치로. 3회.
func _p_cone2(dt: float, player: Player) -> bool:
	return _cone(dt, player, true)


func _cone(_dt: float, player: Player, dual: bool) -> bool:
	const AIM := 0.95
	const LOCK := 0.7
	const BURST := 0.38
	var per := 1.75 if dual else 1.3
	var shots := 3 if dual else 4
	var half := deg_to_rad(20.0 if dual else 25.0)
	var n := int(pt / per)
	if n >= shots:
		for a in arms:
			(a as Dictionary).busy = false
			(a as Dictionary).charge = 0.0
		return pt > shots * per + 0.3
	var l := pt - n * per
	if int(ps.get("n", -1)) != n:
		ps.n = n
		ps.hit = false
		ps.fired = false
		_clear_warnings()
		for a in arms:
			(a as Dictionary).busy = false
		ps.use = [0, 1] if dual else [n % 2]
		ps.dirs = {}
		for i in ps.use:
			(arms[i] as Dictionary).busy = true
			warnings.append(stage.fan_warning(Vector3.ZERO, 0.0, half, CONE_R))
		Sfx.play("echarge", 0.05, -6.0)
	var dirs: Dictionary = ps.dirs
	var use: Array = ps.use
	for idx in use.size():
		var i: int = use[idx]
		var a: Dictionary = arms[i]
		var sh := _shoulder_ground(a)
		if l < LOCK or not dirs.has(i):
			var target := player.global_position
			if dual and i == 1:
				target += player.velocity * 0.75
			var d := target - sh
			d.y = 0
			var want := d.normalized() if d.length() > 0.5 else Vector3.BACK
			dirs[i] = want if not dirs.has(i) else (dirs[i] as Vector3).slerp(want, 0.35).normalized()
		if l >= LOCK and not ps.get("locked%d" % i, false):
			ps["locked%d" % i] = true
			Sfx.play("lock", 0.0, -4.0)
		var dv: Vector3 = dirs[i]
		var recoil := 0.0
		if l >= AIM:
			recoil = 1.6 * (1.0 - clampf((l - AIM) / 0.6, 0.0, 1.0))
		var m := sh + dv * (9.5 - recoil) + Vector3(0, 2.8 + recoil * 0.4, 0)
		a.goal = m
		a.rate = 7.0
		a.charge = clampf(l / AIM, 0.0, 1.0) if l < AIM else maxf(0.0, 1.0 - (l - AIM) * 2.5)
		var apex := sh + dv * 9.5
		var dir_a := atan2(dv.x, dv.z)
		var w: MeshInstance3D = warnings[idx]
		w.global_position = Vector3(apex.x, 0.04, apex.z)
		w.set_instance_shader_parameter("dir_a", dir_a)
		w.set_instance_shader_parameter("progress", clampf(l / AIM, 0.0, 1.0))
		w.visible = l < AIM + 0.05
		if l < AIM + BURST:
			threats.append({"type": "fan", "apex": apex, "dir": dv, "half": half, "r": CONE_R})
		if l >= AIM and l < AIM + BURST:
			var reach := CONE_R * clampf((l - AIM) / 0.14, 0.2, 1.0)
			_cone_fx(a.tip, dv, half, l - AIM < 0.02)
			if not ps.hit and player.alive and _in_fan(player, apex, dir_a, half, reach):
				ps.hit = true
				_hurt(apex)
	if l >= AIM and not ps.fired:
		ps.fired = true
		Sfx.play("elaser", 0.05, 0.0)
		Sfx.play("boom", 0.1, -3.0)
		Main.inst.shake(0.4)
		Main.inst.kick(Vector3(0, 0, 0.6))
		punch = maxf(punch, 0.5)
	return false


## 화염 분사 연출: 포구에서 부채꼴로 퍼지는 불길 + 연기 + 섬광
func _cone_fx(muzzle: Vector3, dir: Vector3, half: float, first: bool) -> void:
	if first:
		FX.flash(muzzle, Color("fff0c0"), 3.0, 0.12)
		FX.sparks(muzzle, 20, [Color.WHITE, Color("ffd060"), Color("ff6a20")], 14.0, 0.5, -8.0, 0.1)
		FX.shockwave(Vector3(muzzle.x, 0.3, muzzle.z), Color("ffa040"), 5.0, 0.3)
	for k in 7:
		var d := dir.rotated(Vector3.UP, randf_range(-half, half) * 0.92)
		var v := d * randf_range(30.0, 42.0) + Vector3(0, randf_range(-4.5, -2.5), 0)
		var hot := randf() < 0.7
		var c := Color(1.0, 0.72, 0.25, 0.9) if randf() < 0.4 else Color(1.0, 0.4, 0.08, 0.9)
		stage.fire(muzzle + d * randf_range(0.2, 1.2), v, randf_range(2.4, 3.6) if hot else 3.4, randf_range(0.45, 0.6), c if hot else Color(0.2, 0.12, 0.12, 0.45), hot, 3.0)


## 도가니 내려찍기: 포신을 플레이어 머리 위로 들어 올리고 바닥에 원으로 예고한 뒤 내려찍는다.
## 착지하면 충격파 탄환이 사방으로 퍼지고 쇳물 웅덩이가 남는다. 박힌 포신은 잠깐 맞출 수 있다(검 추가 피해).
func _p_slam(dt: float, player: Player) -> bool:
	return _slams(dt, player, 3, 1.7, 1.05, 1.5, 12, 3.0)


func _p_double_slam(dt: float, player: Player) -> bool:
	return _slams(dt, player, 6, 0.95, 0.78, 0.9, 16, 3.4)


func _slam_target(a: Dictionary, player: Player) -> Vector3:
	var sh := _shoulder_ground(a)
	var p := _flat(player.global_position) + _flat(player.velocity) * 0.25
	var rel := p - sh
	if rel.length() > REACH:
		p = sh + rel.normalized() * REACH
	return Stage.clamp_inside(p, stage.radius - 1.2)


func _slams(_dt: float, player: Player, count: int, period: float, warn: float, down_t: float, ring: int, pool_life: float) -> bool:
	var list: Array = ps.get("list", [])
	var nxt: int = ps.get("next", 0)
	if nxt < count and pt >= nxt * period:
		var a: Dictionary = arms[nxt % 2]
		ps.next = nxt + 1
		a.busy = true
		a.down = false
		var tgt := _slam_target(a, player)
		var w := stage.circle_warning(tgt, SLAM_R)
		warnings.append(w)
		list.append({"a": a, "t0": pt, "T": tgt, "hit": false, "w": w})
		Sfx.play("hrise", 0.05, -6.0)
	ps.list = list
	for s in list.duplicate():
		var sd: Dictionary = s
		var a: Dictionary = sd.a
		var l: float = pt - float(sd.t0)
		var tgt: Vector3 = sd.T
		var w: MeshInstance3D = sd.w if is_instance_valid(sd.w) else null
		if l < warn - 0.12:
			if l < warn * 0.62:
				sd.T = tgt.lerp(_slam_target(a, player), 0.2)
				tgt = sd.T
			var sh := _shoulder_ground(a)
			a.goal = tgt + (sh - tgt).normalized() * 1.2 + Vector3(0, 8.5, 0)
			a.rate = 6.0
			a.charge = l / warn
			if is_instance_valid(w):
				w.global_position = Vector3(tgt.x, 0.04, tgt.z)
				w.set_instance_shader_parameter("progress", l / warn)
			threats.append({"type": "circle", "pos": tgt, "r": SLAM_R})
		elif not sd.hit:
			a.goal = tgt + Vector3(0, 0.9, 0)
			a.rate = 32.0
			threats.append({"type": "circle", "pos": tgt, "r": SLAM_R})
			if is_instance_valid(w):
				w.set_instance_shader_parameter("progress", 1.0)
			if l >= warn:
				sd.hit = true
				if is_instance_valid(w):
					w.queue_free()
				sd.w = null
				a.down = true
				a.charge = 0.0
				_slam_impact(tgt, ring, pool_life, player)
		elif l < warn + down_t:
			# 박힌 채 떨린다
			a.goal = tgt + Vector3(randf_range(-0.04, 0.04), 0.9, randf_range(-0.04, 0.04))
			a.rate = 20.0
		else:
			a.down = false
			a.busy = false
			list.erase(s)
	return nxt >= count and list.is_empty()


func _slam_impact(p: Vector3, ring: int, pool_life: float, player: Player) -> void:
	molten().burst(p, 1.25 if phase == 1 else 1.05, p - _flat(global_position))
	FX.fire_explosion(p + Vector3(0, 0.3, 0), 0.3)
	FX.shockwave(p + Vector3(0, 0.15, 0), Color("ff9a40"), SLAM_R * 2.8, 0.35, 0.12)
	FX.ring(p + Vector3(0, 0.3, 0), 7.0, Pal.RING_ORANGE, 0.45)
	FX.sparks(p + Vector3(0, 0.3, 0), 22, [Color.WHITE, Color("ffd060"), Color("ff6a20")], 11.0, 0.55, -14.0, 0.1)
	Sfx.play("boom", 0.1, 1.0)
	Sfx.play("land", 0.1, 0.0)
	Main.inst.shake(0.55)
	Main.inst.hitstop(0.04)
	if player.alive and _in_circle(player, p, SLAM_R):
		_hurt(p)
	var off := randf() * TAU
	for i in ring:
		var a := off + TAU * i / ring
		_shot(p, Vector3(sin(a), 0, cos(a)), 6.0 if phase == 1 else 6.8, i % 2 == 0)
	_add_puddle(p, 2.0, pool_life)


## 오안 조준 사격: 다섯 눈이 차례로 달아올라 조준 3연탄을 쏜 뒤, 얼굴 전체에서 남쪽으로 반원 탄막 2파.
func _p_eyes(_dt: float, player: Player) -> bool:
	var n: int = ps.get("n", 0)
	const START := 0.45
	const GAP := 0.3
	if n < 10:
		var e: int = EYE_ORDER[n % 5]
		var fire_at := START + n * GAP
		eye_level[e] = 1.0 + clampf(1.0 - (fire_at - pt) / 0.3, 0.0, 1.0) * 0.8
		if pt >= fire_at:
			ps.n = n + 1
			eye_level[e] = 1.0
			eye_flash[e] = 1.0
			var from := _flat(_eye_pos(e))
			var base := _aim_from(from, player.global_position + player.velocity * (0.3 if n >= 5 else 0.0))
			for w in 3:
				_shot(from, base.rotated(Vector3.UP, (w - 1) * 0.13), 9.5, w == 1)
			FX.flash(_eye_pos(e), Color("fff0c0"), 1.2, 0.08)
			Sfx.play("eshot", 0.1, -4.0)
		return false
	var waves := [START + 10 * GAP + 0.6, START + 10 * GAP + 1.25]
	var wi: int = ps.get("w", 0)
	if wi < waves.size():
		var tele := clampf(1.0 - (waves[wi] - pt) / 0.45, 0.0, 1.0)
		for i in 5:
			eye_level[i] = 1.0 + tele
		if pt >= waves[wi]:
			ps.w = wi + 1
			var c := _flat((tt.head as Node3D).global_position)
			var total := 26
			var off := (0.5 if wi == 1 else 0.0) / total * PI * 1.1
			for i in total:
				var a := lerpf(-PI * 0.55, PI * 0.55, float(i) / (total - 1)) + off
				_shot(c, Vector3(sin(a), 0, cos(a)), 5.6, i % 2 == 0)
			for i in 5:
				eye_flash[i] = 1.0
				eye_level[i] = 1.0
			Main.inst.shake(0.3)
			Sfx.play("tshot", 0.05, 0.0)
			punch = maxf(punch, 0.4)
		return false
	return pt > waves[1] + 0.8


## 슬래그 낙하: 매달린 도가니들이 기울어 쇳물을 쏟는다. 발판 곳곳과 플레이어 자리에 원 경고가 찍히고 1.1초 뒤 쇳물 덩이가 떨어진다.
func _p_slag(dt: float, player: Player) -> bool:
	const COUNT := 11
	const GAP := 0.24
	const FUSE := 1.1
	if not ps.get("started", false):
		ps.started = true
		stage.tip_crucibles(true)
		Sfx.play("hatch", 0.0, 0.0)
	var n: int = ps.get("n", 0)
	if n < COUNT and pt >= 0.6 + n * GAP:
		ps.n = n + 1
		var p: Vector3
		if n % 2 == 0:
			p = _flat(player.global_position) + _flat(player.velocity) * 0.35
		else:
			var a := randf() * TAU
			p = Vector3(cos(a), 0, sin(a)) * randf_range(1.0, stage.radius - 1.5)
		_drop(Stage.clamp_inside(p, stage.radius - 0.8), 1.9, FUSE)
	# 눈에서 견제탄
	var sc: float = ps.get("sc", 0.8) - dt
	if sc <= 0.0:
		sc = 0.75
		var e: int = EYE_ORDER[randi() % 5]
		eye_flash[e] = 1.0
		var from := _flat(_eye_pos(e))
		_shot(from, _aim_from(from, player.global_position), 8.0, true)
		Sfx.play("eshot", 0.1, -8.0)
	ps.sc = sc
	return n >= COUNT and pt > 0.6 + COUNT * GAP + FUSE + 0.6


## 원 경고 → 쇳물 덩이 낙하 → 폭발 + 웅덩이
func _drop(p: Vector3, r: float, fuse: float) -> void:
	var w := stage.circle_warning(p, r, Color(1.0, 0.45, 0.08))
	var info := {"type": "circle", "pos": p, "r": r}
	var holder := {"node": w, "info": info}
	_markers.append(holder)
	var tw := w.create_tween()
	tw.tween_method(func(v: float): w.set_instance_shader_parameter("progress", v), 0.0, 1.0, fuse)
	tw.tween_callback(func():
		_markers.erase(holder)
		_slag_impact(p, r)
		w.queue_free())
	if _drop_mesh == null:
		_drop_mesh = SphereMesh.new()
		_drop_mesh.radius = 0.55
		_drop_mesh.height = 1.3
	var blob := Pal.flat_mesh(_drop_mesh, Color("ffb040"), 2.4)
	w.add_child(blob)
	blob.position = Vector3(randf_range(-2, 2), 16.0, randf_range(-3, 0))
	blob.visible = false
	var btw := blob.create_tween()
	btw.tween_interval(fuse - 0.35)
	btw.tween_callback(func(): blob.visible = true)
	btw.tween_property(blob, "position", Vector3(0, 0.4, 0), 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	btw.parallel().tween_property(blob, "scale", Vector3(0.7, 1.9, 0.7), 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _slag_impact(p: Vector3, r: float) -> void:
	molten().impact(p, 0.85)
	FX.fire_explosion(p + Vector3(0, 0.3, 0), 0.2)
	FX.sparks(p + Vector3(0, 0.3, 0), 14, [Color("fff0a0"), Color("ffa030"), Color("ff4a10")], 8.0, 0.5, -14.0, 0.09)
	Sfx.play("boom", 0.2, -5.0)
	Main.inst.shake(0.18)
	var pl := Main.inst.player
	if pl.alive and _in_circle(pl, p, r):
		_hurt(p)
	_add_puddle(p, 1.6, 2.6 if phase == 1 else 3.2)


# ── 2페이즈 ─────────────────────────────────────────────

## 노심 화염 방사 (강력 예고 공격): 드러난 가슴 노심이 1.9초 충전하는 동안 부채꼴 전체와 시작 사선을 예고하고,
## 굵은 화염 빔으로 발판을 한쪽 끝에서 반대쪽 끝까지 쓸어 간다. 맞으면 체력 2칸. 대시(무적)로 빔을 뚫고 지나가야 한다.
## 쏜 뒤 3.6초간 노심이 과열되어 약점 노출 · 피해 2배, 두 팔도 발판에 늘어져 맞출 수 있다.
func _p_breath(dt: float, player: Player) -> bool:
	const CHARGE := 1.9
	const SWEEP := 2.6
	const VENT := 3.6
	var half := deg_to_rad(72.0)
	var origin := _core_ground()
	if not ps.get("started", false):
		ps.started = true
		var px := player.global_position.x - origin.x
		ps.a0 = -half if px >= 0.0 else half
		ps.a1 = -float(ps.a0)
		warnings.append(stage.fan_warning(origin, 0.0, half + 0.04, BEAM_LEN - 4.0, 0.0, Color(1.0, 0.2, 0.08)))
		var lw := LaserWarning.new()
		stage.add_child(lw)
		warnings.append(lw)
		Main.inst.dramatic(true)
		Main.inst.hud.banner("WARNING", Color("ff3a4a"), "노심 화염 방사 — 대시(Space)로 빔을 뚫고 지나가세요!")
		Sfx.play("echarge", 0.0, 0.0)
		ps.snd = 0.0
		for a in arms:
			(a as Dictionary).busy = true
	# 두 팔은 몸을 받치듯 발판 가장자리를 짚는다
	for a in arms:
		var ad: Dictionary = a
		var sh := _shoulder_ground(ad)
		var side: float = ad.side
		ad.goal = sh + Vector3(side * 2.5, 1.2, 6.5)
		ad.rate = 4.0
	var a0: float = ps.a0
	var a1: float = ps.a1
	if pt < CHARGE:
		var k := pt / CHARGE
		core_k = k
		var d0 := Vector3(sin(a0), 0, cos(a0))
		(warnings[0] as MeshInstance3D).set_instance_shader_parameter("progress", k * 0.6)
		var lw: LaserWarning = warnings[1]
		lw.set_pose(origin, d0, BEAM_LEN, BEAM_W, 1.2)
		lw.set_progress(k)
		threats.append({"type": "beam", "origin": origin, "dir": d0, "half": BEAM_W * 0.5, "len": BEAM_LEN, "sweep": true, "a": a0, "a1": a1})
		var spk: float = ps.get("spk", 0.0) - dt
		if spk <= 0.0:
			spk = 0.05
			var c := (tt.core as Node3D).global_position
			var off := Vector3(randf_range(-1, 1), randf_range(-0.6, 1), randf_range(0.2, 1)).normalized() * 3.2
			FX.sparks(c + off, 3, [Color.WHITE, Color("ffb040")], 2.0, 0.2, 0.0, 0.08)
			stage.fire(c + off, -off * 2.2, 0.9, 0.35, Color(1.0, 0.6, 0.2, 0.8), true, 0.0)
		ps.spk = spk
		ps.snd = float(ps.snd) + dt
		if ps.snd > 0.9:
			ps.snd = 0.0
			Sfx.play("echarge", 0.0, -3.0)
		Main.inst.shake(0.02 + k * 0.05)
		return false
	var bt := pt - CHARGE
	if bt < SWEEP:
		if not ps.get("fired", false):
			ps.fired = true
			_clear_warnings()
			beam = _make_beam()
			Sfx.play("elaser", 0.0, 4.0)
			Sfx.play("boom", 0.0, 2.0)
			Main.inst.hitstop(0.07)
			Main.inst.shake(0.9)
			Main.inst.hud.screen_flash(Color(1, 0.7, 0.4), 0.5)
			Main.inst.camera.fov_punch(5.0)
			punch = 1.0
			ps.bcd = 0.0
		var s := bt / SWEEP
		var e := s * s * (3.0 - 2.0 * s)
		var a := lerpf(a0, a1, e)
		var dir := Vector3(sin(a), 0, cos(a))
		Main.inst.camera.set_beam(true, dir)
		beam.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP), origin + Vector3(0, 1.2, 0))
		var fl := 1.0 + sin(t * 70.0) * 0.08
		beam.scale = Vector3(fl, fl, 1.0)
		core_k = 1.0
		threats.append({"type": "beam", "origin": origin, "dir": dir, "half": BEAM_W * 0.5, "len": BEAM_LEN, "sweep": true, "a": a, "a1": a1})
		# 빔을 따라 불길, 끝에서 불꽃
		for k in 4:
			var dd := randf_range(2.0, BEAM_LEN - 6.0)
			stage.fire(origin + dir * dd + Vector3(0, 0.8, 0), dir * 6.0 + Vector3(randf_range(-2, 2), randf_range(2, 5), randf_range(-2, 2)), randf_range(1.6, 2.6), 0.45, Color(1.0, 0.55, 0.15, 0.85), true, 2.0)
		ps.bcd = float(ps.bcd) - dt
		if ps.bcd <= 0.0:
			ps.bcd = 0.09
			var r := stage.radius
			var end_d := minf(BEAM_LEN, _edge_along(origin, dir, r))
			FX.sparks(origin + dir * end_d + Vector3(0, 0.5, 0), 6, [Color.WHITE, Color("ffd060"), Color("ff6a20")], 9.0, 0.4, -10.0, 0.08)
			Main.inst.shake(0.12)
		if not ps.get("hit", false) and player.alive and player.invuln <= 0.0:
			var rel := player.global_position - origin
			rel.y = 0
			var along := clampf(rel.dot(dir), 0.0, BEAM_LEN)
			if (rel - dir * along).length() < BEAM_W * 0.5 + player.hit_radius:
				ps.hit = true
				_hurt(origin, 1)
		return false
	# 과열: 약점 노출, 두 팔이 발판에 늘어진다
	if not ps.get("vent", false):
		ps.vent = true
		if is_instance_valid(beam):
			beam.queue_free()
		Main.inst.camera.set_beam(false)
		Main.inst.dramatic(false)
		weak = true
		weak_t = VENT
		bar.weak = true
		core_k = 0.0
		Main.inst.hud.popup("OVERHEAT!  약점 노출 · 피해 2배", Color("ffe060"), (tt.core as Node3D).global_position + Vector3(0, 2.5, 0))
		Sfx.play("powerdown", 0.0, 0.0)
		for a in arms:
			var ad: Dictionary = a
			var sh := _shoulder_ground(ad)
			var side: float = ad.side
			ad.goal = Stage.clamp_inside(sh + Vector3(-side * 2.2, 0, 8.5), stage.radius - 1.6) + Vector3(0, 0.9, 0)
			ad.rate = 5.0
			ad.down = true
	var vc: float = ps.get("vc", 0.0) - dt
	if vc <= 0.0:
		vc = 0.07
		var c := (tt.core as Node3D).global_position
		stage.fire(c + Vector3(randf_range(-1, 1), 0, 1.2), Vector3(randf_range(-1, 1), 3.0, 2.0), 2.2, 1.1, Color(0.9, 0.88, 0.95, 0.35), false, 1.0)
		for a in arms:
			var tip: Vector3 = (a as Dictionary).tip
			if randf() < 0.4:
				stage.fire(tip + Vector3(0, 0.5, 0), Vector3(0, 2.5, 0), 1.6, 0.9, Color(0.8, 0.8, 0.85, 0.3), false, 0.8)
	ps.vc = vc
	return bt > SWEEP + VENT


## 방향 dir 로 원점에서 발판 가장자리까지의 거리
func _edge_along(origin: Vector3, dir: Vector3, r: float) -> float:
	var d := 0.5
	while d < BEAM_LEN:
		if Stage.oct_dist(origin + dir * d) > r and d > 3.0:
			return d
		d += 0.5
	return BEAM_LEN


func _make_beam() -> Node3D:
	var h := Node3D.new()
	stage.add_child(h)
	var cm := CylinderMesh.new()
	cm.top_radius = 0.5
	cm.bottom_radius = 0.5
	cm.height = 1.0
	cm.radial_segments = 16
	cm.rings = 1
	for layer in [[Color("ff4a10"), 1.8, 1.0], [Color("ffa030"), 2.4, 0.62], [Color("fff4d0"), 3.2, 0.3]]:
		var mi := Pal.flat_mesh(cm, layer[0], layer[1])
		mi.rotation_degrees.x = -90.0
		mi.position = Vector3(0, 0, -BEAM_LEN * 0.5)
		mi.scale = Vector3(BEAM_W * float(layer[2]), BEAM_LEN, BEAM_W * float(layer[2]))
		h.add_child(mi)
	return h


## 용암 분출: 남은 발판을 중심에서 8조각 부채꼴로 나눠 6조각 + 가운데 원에 1초 예고 후 용암이 솟는다.
## 붙어 있는 두 조각만 안전하고, 매번 자리가 바뀐다. 4회.
func _p_eruption(dt: float, player: Player) -> bool:
	const ROUNDS := 4
	const PERIOD := 1.5
	const WARN := 0.95
	var half := PI / 8.0
	var r_out := stage.radius
	var cur := int(pt / PERIOD)
	if int(ps.get("r", -1)) != cur and cur < ROUNDS:
		ps.r = cur
		ps.fired = false
		# 안전 조각은 직전 자리와 붙지 않게 (팔각 둘레로 2칸 이상 떨어진 곳). 첫 라운드(prev < 0)는 아무 데나.
		var prev: int = ps.get("safe", -1)
		var s := randi() % 8
		if prev >= 0:
			s = (prev + 2 + randi() % 5) % 8
		ps.safe = s
		var hit: Array = []
		for k in 8:
			if k != s and k != (s + 1) % 8:
				hit.append(k)
		ps.hit = hit
		_clear_warnings()
		for k in hit:
			warnings.append(stage.fan_warning(Vector3.ZERO, k * PI / 4.0, half - 0.015, r_out, WEDGE_IN))
		warnings.append(stage.circle_warning(Vector3.ZERO, WEDGE_IN))
		Sfx.play("echarge", 0.0, -7.0)
	if cur < ROUNDS:
		var local := pt - cur * PERIOD
		for w in warnings:
			(w as MeshInstance3D).set_instance_shader_parameter("progress", clampf(local / WARN, 0.0, 1.0))
		threats.append({"type": "wedges", "hit": ps.hit, "r_in": WEDGE_IN, "r_out": r_out})
		if local >= WARN and not ps.fired:
			ps.fired = true
			_clear_warnings()
			for k in ps.hit:
				var a := float(k) * PI / 4.0
				var d := Vector3(sin(a), 0, cos(a))
				for rr in [3.2, 6.2]:
					_geyser(d * rr)
			_geyser(Vector3.ZERO)
			Main.inst.shake(0.5)
			Sfx.play("boom", 0.1, 1.0)
			Sfx.play("elaser", 0.1, -6.0)
			if player.alive:
				var p := _flat(player.global_position)
				var hurt := p.length() < WEDGE_IN + player.hit_radius
				if not hurt:
					var idx := posmod(int(round(atan2(p.x, p.z) / (PI / 4.0))), 8)
					hurt = (ps.hit as Array).has(idx)
				if hurt:
					_hurt(p - p.normalized() * 0.5 if p.length() > 0.6 else p + Vector3(0, 0, -1))
		# 사이사이 눈에서 느린 조준탄
		var sc: float = ps.get("sc", 0.4) - dt
		if sc <= 0.0:
			sc = 0.7
			var e: int = EYE_ORDER[randi() % 5]
			eye_flash[e] = 1.0
			var from := _flat(_eye_pos(e))
			_shot(from, _aim_from(from, player.global_position), 7.0, true)
		ps.sc = sc
	return pt >= ROUNDS * PERIOD + 0.3


func _geyser(p: Vector3) -> void:
	molten().column(p, 0.9)
	for k in 5:
		stage.fire(p + Vector3(randf_range(-0.6, 0.6), 0.2, randf_range(-0.6, 0.6)), Vector3(randf_range(-1.2, 1.2), randf_range(10.0, 17.0), randf_range(-1.2, 1.2)), randf_range(1.4, 2.2), randf_range(0.55, 0.75), Color(1.0, 0.5 + randf() * 0.3, 0.1, 0.9), true, -9.0)
	stage.fire(p + Vector3(0, 1.0, 0), Vector3(0, 4.0, 0), 3.2, 1.3, Color(0.2, 0.12, 0.12, 0.45), false, 0.5)
	FX.sparks(p + Vector3(0, 0.4, 0), 12, [Color("fff0a0"), Color("ffa030"), Color("ff4a10")], 10.0, 0.7, -16.0, 0.1)
	FX.shockwave(p + Vector3(0, 0.1, 0), Color("ff8a30"), 3.4, 0.3)


# ── 쇳물 웅덩이 ─────────────────────────────────────────

## 액체 쇳물 스플래시 연출 (presentation 모듈). 발판 밖은 용암 높이에 떨어진다.
func molten() -> MoltenSplash:
	if _molten == null:
		_molten = MoltenSplash.new()
		_molten.name = "MoltenSplash"
		_molten.ground_fn = func(p: Vector3) -> float: return 0.0 if Stage.oct_dist(p) <= stage.radius else Stage.LAVA_Y
		stage.add_child(_molten)
	return _molten


func _add_puddle(p: Vector3, r: float, life: float) -> void:
	stage.pool(p, r, life)
	puddles.append({"pos": p, "r": r, "t": life})


func _update_puddles(dt: float, player: Player) -> void:
	for i in range(puddles.size() - 1, -1, -1):
		var pd: Dictionary = puddles[i]
		pd.t = float(pd.t) - dt
		if float(pd.t) <= 0.0 or Stage.oct_dist(pd.pos) > stage.radius + 0.5:
			puddles.remove_at(i)
			continue
		if float(pd.t) > 0.3 and player.alive and player.dash_t <= 0.0 and _in_circle(player, pd.pos, float(pd.r) * 0.8):
			_hurt(pd.pos)


# ── 경고 표시 ───────────────────────────────────────────

func _clear_warnings() -> void:
	for w in warnings:
		if is_instance_valid(w):
			(w as Node).queue_free()
	warnings.clear()


func get_threats() -> Array:
	var out := threats.duplicate()
	for h in _markers:
		out.append(h.info)
	for pd in puddles:
		out.append({"type": "circle", "pos": pd.pos, "r": pd.r})
	return out


# ── 피격 · 페이즈 ───────────────────────────────────────

func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	_damage(float(mini(dmg, 20)), dir, pos, source, 1.0)


## 팔 피격 (forge_fist.gd): 박힌 포신을 치면 본체보다 크게 들어간다
func part_hit(part: Enemy, dmg: int, dir: Vector3, pos: Vector3, source: String) -> void:
	if source == "slash" or source == "phantom":
		FX.sparks(part.global_position + Vector3(0, 1.0, 0), 18, [Color.WHITE, Pal.BLADE, Color("ffb040")], 9.0, 0.4, -10.0, 0.08)
		Main.inst.hud.popup("CRUSH", Color("ff8a70"), part.global_position + Vector3(0, 2.6, 0))
	_damage(float(mini(dmg, 20)), dir, pos, source, 1.35, (arms[(part as Fist).arm_index] as Dictionary).fore)


## flash_root: 피격 섬광을 덮을 부분 (없으면 몸통). 거대한 몸 전체가 하얗게 번쩍이지 않도록 맞은 부분만 칠한다.
func _damage(base: float, dir: Vector3, pos: Vector3, source: String, mult: float, flash_root: Node3D = null) -> void:
	if not alive or st != St.FIGHT:
		# 등장·전환·폭발 중에는 튕겨낸다
		if randf() < 0.3:
			FX.sparks(pos, 3, [Color.WHITE, Color("a0a0c0")], 4.0, 0.2, -6.0, 0.05)
		return
	var amount := base
	if source == "slash":
		amount = 12.0
	elif source == "phantom":
		amount = 22.0
	amount *= mult
	if weak:
		amount *= 2.0
	boss_hp = maxf(0.0, boss_hp - amount)
	bar.set_hp(boss_hp / MAX_HP, amount >= 5.0)
	kill_source = source
	HitSpark.spawn(pos, dir, clampf(1.0 + amount * 0.06, 1.0, 2.4), self)
	lean_v += Vector2(-dir.z, dir.x) * minf(0.01 * amount, 0.25)
	punch = maxf(punch, minf(0.1 + amount * 0.04, 1.0))
	if amount >= 8.0 and flash_cd <= 0.0:
		flash_cd = 0.3
		var root: Node3D = flash_root if flash_root else tt.body
		var part := root.find_children("*", "MeshInstance3D", true, false)
		if root is MeshInstance3D:
			part.append(root)
		_set_flash(true, part)
		get_tree().create_timer(0.06, true, false, true).timeout.connect(func():
			if is_instance_valid(self):
				_set_flash(false, part))
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


func _set_flash(on: bool, only: Array = []) -> void:
	var rest_mat: Material = Pal.lock_hatch() if locked else null
	for mi in (only if not only.is_empty() else meshes):
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = Pal.flash() if on else rest_mat


func _abort_pattern() -> void:
	if pat == "breath":
		Main.inst.dramatic(false)
		Main.inst.camera.set_beam(false)
	if is_instance_valid(beam):
		beam.queue_free()
	pat = ""
	weak = false
	bar.weak = false
	core_k = 0.0
	bar.set_pattern("")
	_clear_warnings()
	for h in _markers:
		if is_instance_valid(h.node):
			(h.node as Node).queue_free()
	_markers.clear()
	for a in arms:
		var ad: Dictionary = a
		ad.busy = false
		ad.down = false
		ad.charge = 0.0
	stage.tip_crucibles(false)


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
	Main.inst.hud.screen_flash(Color(1, 0.8, 0.6), 0.7)
	Sfx.play("overload", 0.0, 2.0)
	print("BOSS_PHASE2 t=%.1f" % Main.inst.time)


## 2페이즈 전환: 포효 → 가슴 장갑이 터져 노심 노출 → 두 팔로 발판을 내리쳐 바깥 고리가 차례로 용암에 가라앉는다
func _update_transition(_dt: float) -> void:
	var steps := [0.0, 0.55, 1.05, 1.4, 4.6]
	var s: int = ps.step
	if s < steps.size() and st_t >= steps[s]:
		ps.step = s + 1
		match s:
			0:
				_roar()
				for a in arms:
					var ad: Dictionary = a
					ad.busy = true
					var side: float = ad.side
					ad.goal = _shoulder_world(ad) + Vector3(side * 2.5, 4.0, 5.5)
					ad.rate = 5.0
			1:
				for pl in tt.plates:
					var side := signf((pl as Node3D).position.x)
					_break_off(pl, Vector3(side * 7.0, 9.0, 11.0))
				for g in tt.grille:
					_break_off(g, Vector3(randf_range(-5, 5), randf_range(6, 11), randf_range(8, 13)))
				core_open = true
				var c := (tt.core as Node3D).global_position
				FX.fire_explosion(c + Vector3(0, 0, 1.0), 1.1)
				Main.inst.hud.screen_flash(Color(1, 0.7, 0.4), 0.5)
				_wound(Vector3(-3.8, 6.4, 3.9))
				_wound(Vector3(3.6, 5.2, 3.9))
			2:
				for a in arms:
					var ad: Dictionary = a
					var side: float = ad.side
					ad.goal = Vector3(side * 8.6, 0.9, -8.6)
					ad.rate = 26.0
			3:
				for a in arms:
					var tip: Vector3 = (a as Dictionary).tip
					_slam_fx_only(Vector3(tip.x, 0, tip.z))
				Main.inst.shake(1.0)
				Main.inst.hitstop(0.08)
				stage.collapse([6, 5, 7, 4, 0, 3, 1, 2], 0.9, 0.22)
				Main.inst.hud.banner("COLLAPSE", Color("ff8a30"), "발판이 무너집니다 — 안쪽으로!")
			4:
				Main.inst.hud.banner("PHASE 2", Color("ff4a5a"), "노심을 드러낸 거신이 폭주합니다! 전장이 좁아졌습니다")
				bar.set_phase(2)
				phase_changed.emit(2)
		if s <= 1:
			var p := (tt.body as Node3D).to_global(Vector3(randf_range(-4, 4), randf_range(4, 8), 3.5))
			FX.enemy_explosion(p, 1.8)
			Sfx.play("boom", 0.1, 2.0)
			Main.inst.shake(0.6)
			lean_v += Vector2(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4))
			punch = 1.0
	if st_t > 5.2:
		st = St.FIGHT
		phase = 2
		pat_i = -1
		rest = 0.8
		for a in arms:
			(a as Dictionary).busy = false
		_cache_meshes()


func _slam_fx_only(p: Vector3) -> void:
	molten().burst(p, 1.3)
	FX.fire_explosion(p + Vector3(0, 0.3, 0), 0.8)
	FX.shockwave(p + Vector3(0, 0.15, 0), Color("ff9a40"), 10.0, 0.4, 0.15)
	FX.sparks(p + Vector3(0, 0.3, 0), 28, [Color.WHITE, Color("ffd060"), Color("ff6a20")], 12.0, 0.6, -14.0, 0.1)
	Sfx.play("boom", 0.05, 3.0)


func _break_off(n: Node, vel: Vector3) -> void:
	if not is_instance_valid(n):
		return
	var nd := n as Node3D
	var gt := nd.global_transform
	nd.get_parent().remove_child(nd)
	stage.add_child(nd)
	nd.global_transform = gt
	stage.fling(nd, vel, Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(4, 8), 6.0)
	FX.enemy_explosion(gt.origin, 1.2)
	FX.sparks(gt.origin, 20, [Color.WHITE, Color("ffd060"), Color("ff6a20")], 10.0, 0.5, -12.0, 0.09)
	_cache_meshes()


## 떨어져 나간 자리: 달아오른 소켓 + 연기 분출점
func _wound(local: Vector3) -> void:
	var body: Node3D = tt.body
	Titan.BT.rbox(body, Vector3(1.4, 1.4, 0.3), 0.1, local, Color("1e1a22"))
	Titan.BT.glow(body, Vector3(1.0, 1.0, 0.12), local + Vector3(0, 0, 0.12), Color("ff6a20"), 2.2)
	var sp := Node3D.new()
	body.add_child(sp)
	sp.position = local + Vector3(0, 0.3, 0.4)
	smoke_points.append(sp)


# ── 격파 ────────────────────────────────────────────────

func _begin_dying() -> void:
	_abort_pattern()
	_clear_bullets()
	st = St.DYING
	st_t = 0.0
	ps = {"cd": 0.0, "step": 0}
	alive = false
	remove_from_group("enemies")
	for a in arms:
		var ad: Dictionary = a
		ad.busy = true
		var fist: Enemy = ad.fist
		if is_instance_valid(fist):
			fist.alive = false
			fist.landed = false
			fist.remove_from_group("enemies")
	for i in 5:
		eye_flash[i] = 1.0
	bar.set_hp(0.0, true)
	Main.inst.hitstop(0.2)
	Main.inst.shake(1.0)
	Main.inst.hud.screen_flash(Color.WHITE, 0.8)
	Sfx.play("overload", 0.0, 4.0)
	Main.inst.on_enemy_killed(self)
	print("BOSS_DOWN t=%.1f" % Main.inst.time)


## 연쇄 폭발 → 눈이 하나씩 꺼지고 팔이 늘어져 용암에 잠긴다 → 대폭발 후 몸통이 용암 속으로 가라앉는다
func _update_dying(dt: float) -> void:
	const DUR := 3.6
	ps.cd = float(ps.cd) - dt
	var k := clampf(st_t / DUR, 0.0, 1.0)
	if ps.cd <= 0.0 and st_t < DUR:
		ps.cd = lerpf(0.22, 0.06, k)
		var p := (tt.body as Node3D).to_global(Vector3(randf_range(-5, 5), randf_range(2, 12), randf_range(-2, 4)))
		FX.enemy_explosion(p, randf_range(0.9, 1.6))
		Sfx.play("boom", 0.2, -2.0)
		Main.inst.shake(0.3)
		lean_v += Vector2(randf_range(-0.2, 0.2), randf_range(-0.2, 0.2))
	for i in 5:
		eye_level[i] = 0.0 if k > 0.2 + EYE_ORDER.find(i) * 0.14 else 1.0
	head_nod = lerpf(0.0, 0.45, k)
	global_position.y = lerpf(0.0, -1.6, k)
	for a in arms:
		var ad: Dictionary = a
		var side: float = ad.side
		ad.goal = _shoulder_world(ad) + Vector3(side * 4.0, -10.0, 5.0)
		ad.rate = 1.2
	if st_t >= DUR and st == St.DYING:
		st = St.DEAD
		_final_blast()


func _final_blast() -> void:
	var c := (tt.body as Node3D).to_global(Vector3(0, 6.0, 1.0))
	for i in 6:
		var off := Vector3(randf_range(-4, 4), randf_range(-2, 4), randf_range(-2, 3))
		FX.enemy_explosion(c + off, 3.0)
	FX.ring(Vector3(c.x, 0.3, -9.0), 26.0, Pal.RING_ORANGE, 0.8)
	FX.shockwave(Vector3(c.x, 0.2, -10.0), Color("ffd060"), 30.0, 0.7, 0.25)
	Main.inst.hud.screen_flash(Color.WHITE, 1.0)
	Main.inst.hitstop(0.25)
	Main.inst.shake(1.0)
	Sfx.play("boom", 0.0, 6.0)
	_break_off(tt.head, Vector3(randf_range(-3, 3), 18.0, 9.0))
	for a in arms:
		var ad: Dictionary = a
		var side: float = ad.side
		_break_off(ad.upper, Vector3(side * 9.0, 10.0, 6.0))
		_break_off(ad.fore, Vector3(side * 6.0, 7.0, 10.0))
		var fist: Node = ad.fist
		if is_instance_valid(fist):
			fist.queue_free()
	# 남은 몸통은 불길을 뿜으며 용암 속으로 가라앉는다
	var tw := create_tween()
	tw.tween_property(self, "global_position:y", -17.0, 4.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(func(): visual.visible = false)
	for i in 10:
		get_tree().create_timer(0.3 * i, false).timeout.connect(func():
			stage.splash(HOME + Vector3(randf_range(-6, 6), Stage.LAVA_Y, randf_range(-3, 5)), 2.0)
			Main.inst.shake(0.2))
	defeated.emit()
