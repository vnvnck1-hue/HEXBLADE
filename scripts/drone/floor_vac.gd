class_name FloorVac
extends Node3D
## 청소 질주 잡조각 흡입 (PartnerDrone 소유). Space 를 누른 채 다니는 동안 둘레 반경 안 바닥의 잡스러운 조각을 전부 빨아들인다:
##  탄피 · 벽/몸체 착탄 파편 (GunFX.casings / chips) · 적 몸체 조각 (Debris.pieces) · 벌레 체액 얼룩 (BugEnemy.SPLAT_GROUP) ·
##  촘퍼 체액 웅덩이 (BugChomper._puddles) · 심연 체액 데칼 (AbyssFX._decals).
## 원래 시스템의 목록에서 빼고(그 시스템은 더 이상 건드리지 않음) 같은 메시 · 재질의 복사본을 만들어 원본은 지운 뒤,
## 가까운 것부터 한 박자씩 엇갈려 나선을 그리며 흡입 중심으로 빨려 들게 한다. 들어갈 때마다 높아지는 톡 소리 · 작은 반짝임.
## 잡조각은 지원 게이지에 들어가지 않는다 (게이지는 DroneMess 만). 빨아들이지 않은 조각은 원래 수명대로 저절로 사라진다.

const MAX_FLY := 260                ## 동시에 날아가는 조각 상한 (넘으면 이번 틱에는 그만 집는다)
const FLY_T := Vector2(0.22, 0.38)   ## 빨려 드는 시간
const STAGGER := 0.22               ## 거리에 따라 늦게 출발 (가까운 것부터 차례로)
const LIFT := 0.5                   ## 날아가는 동안 위로 튀는 높이
const SWIRL := 0.55                 ## 나선 옆 흔들림

var fly: Array = []                 ## [node, 출발점, t(음수 = 대기), dur, 옆 방향 부호, 회전 속도, 처음 크기, decal?]
var swallowed := 0                  ## 지금까지 빨아들인 잡조각 수 (확인용)
var _tick_t := 0.0
var _streak := 0
var _streak_t := 0.0
var _count_t := 0.0
var _count := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()


## 반경 안 잡조각을 모두 넘겨받아 빨아들이기 시작한다 (매 틱 부른다)
func pull(center: Vector3, radius: float) -> void:
	var gy := Main.gy(center)
	var g := GunFX.inst
	if is_instance_valid(g):
		_take_list(g.casings, center, radius, gy)
		_take_list(g.chips, center, radius, gy)
	var db := Debris.inst
	if is_instance_valid(db):
		_take_list(db.pieces, center, radius, gy)
	for n in get_tree().get_nodes_in_group(BugEnemy.SPLAT_GROUP):
		var mi := n as MeshInstance3D
		if mi and _near(mi.global_position, center, radius, gy):
			mi.remove_from_group(BugEnemy.SPLAT_GROUP)
			_steal(mi, center, radius)
	for i in range(BugChomper._puddles.size() - 1, -1, -1):
		var p: Variant = BugChomper._puddles[i]
		if not is_instance_valid(p):
			continue
		var mi := p as MeshInstance3D
		if _near(mi.global_position, center, radius, gy):
			BugChomper._puddles.remove_at(i)
			_steal(mi, center, radius)
	for i in range(AbyssFX._decals.size() - 1, -1, -1):
		var d: Variant = AbyssFX._decals[i]
		if not is_instance_valid(d):
			continue
		var dc := d as Decal
		if _near(dc.global_position, center, radius, gy):
			AbyssFX._decals.remove_at(i)
			_take_decal(dc, center, radius)


func _near(p: Vector3, center: Vector3, radius: float, gy: float) -> bool:
	if p.y > gy + 1.6:
		return false             # 아직 높이 튀어 오른 것은 다음에
	return Vector2(p.x - center.x, p.z - center.z).length() <= radius


## GunFX · Debris 처럼 {node, ...} 사전 목록을 쓰는 시스템
func _take_list(list: Array, center: Vector3, radius: float, gy: float) -> void:
	for i in range(list.size() - 1, -1, -1):
		if fly.size() >= MAX_FLY:
			return
		var pc: Dictionary = list[i]
		var mi := pc.node as MeshInstance3D
		if not is_instance_valid(mi):
			continue
		if _near(mi.global_position, center, radius, gy):
			list.remove_at(i)
			_steal(mi, center, radius)


## 원본(트윈 · 물리가 붙어 있을 수 있다)은 지우고 같은 모양의 복사본을 날린다
func _steal(mi: MeshInstance3D, center: Vector3, radius: float) -> void:
	if not mi.is_inside_tree():
		mi.queue_free()
		return
	var c := MeshInstance3D.new()
	c.mesh = mi.mesh
	c.material_override = mi.material_override
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.top_level = true
	add_child(c)
	c.global_transform = mi.global_transform
	mi.queue_free()
	_launch(c, center, radius, false)


func _take_decal(dc: Decal, center: Vector3, radius: float) -> void:
	# 데칼은 투영 상자라 그대로 끌고 오며 줄인다 (그 자리의 다른 트윈은 없다)
	var c := dc
	c.top_level = true
	_launch(c, center, radius, true)


func _launch(n: Node3D, center: Vector3, radius: float, decal: bool) -> void:
	var d := Vector2(n.global_position.x - center.x, n.global_position.z - center.z).length()
	var delay := d / maxf(radius, 0.1) * STAGGER + rng.randf_range(0.0, 0.06)
	var s0: Vector3 = (n as Decal).size if decal else n.scale
	fly.append([n, n.global_position, -delay, rng.randf_range(FLY_T.x, FLY_T.y), 1.0 if rng.randf() < 0.5 else -1.0,
		Vector3(rng.randf_range(-14, 14), rng.randf_range(-14, 14), rng.randf_range(-14, 14)), s0, decal])


## 날아가는 조각 진행 · 들어간 소리 · 묶음 표시. core = 빨려 드는 곳 (플레이어 가슴)
func step(dt: float, core: Vector3) -> void:
	_tick_t -= dt
	_streak_t -= dt
	if _streak_t <= 0.0:
		_streak = 0
	var landed := 0
	for i in range(fly.size() - 1, -1, -1):
		var f: Array = fly[i]
		var n: Node3D = f[0]
		if not is_instance_valid(n):
			fly.remove_at(i)
			continue
		f[2] = float(f[2]) + dt
		var t := float(f[2])
		if t < 0.0:
			# 출발 전: 살짝 들썩인다
			if not f[7]:
				n.position.y = (f[1] as Vector3).y + absf(sin(t * 40.0)) * 0.03
			continue
		var x := clampf(t / float(f[3]), 0.0, 1.0)
		var e := x * x
		var from: Vector3 = f[1]
		var to := core
		var side := (to - from).cross(Vector3.UP)
		side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
		var arc := sin(x * PI)
		var p := from.lerp(to, e) + side * arc * SWIRL * float(f[4]) * (1.0 - e) + Vector3.UP * arc * LIFT
		if f[7]:
			var dc := n as Decal
			dc.global_position = Vector3(p.x, from.y, p.z)
			dc.size = (f[6] as Vector3) * (1.0 - e * 0.95)
			dc.modulate.a = 1.0 - e
		else:
			n.global_position = p
			n.rotation += (f[5] as Vector3) * dt * (0.3 + e)
			n.scale = (f[6] as Vector3) * maxf(1.0 - e * 0.9, 0.05)
		if x >= 1.0:
			n.queue_free()
			fly.remove_at(i)
			landed += 1
	if landed > 0:
		_swallow(landed, core)


func _swallow(n: int, core: Vector3) -> void:
	swallowed += n
	_streak += n
	_streak_t = 0.5
	_count += n
	# 톡 · 톡 · 톡: 연달아 들어갈수록 음이 올라간다 (너무 잦지 않게)
	if _tick_t <= 0.0:
		_tick_t = 0.035
		var snd := Sfx.play("tink", 0.02, -13.0)
		if snd:
			snd.pitch_scale = 1.3 + minf(_streak, 40) * 0.025
	if rng.randf() < 0.35:
		FX.sparks(core, 2, [Color.WHITE, DroneFX.MINT], 2.5, 0.2, -3.0, 0.03)


## 묶음 표시: 일정 간격으로 그동안 빨아들인 수를 띄운다 (게이지와 무관)
func flush_count(dt: float, at: Vector3) -> void:
	_count_t -= dt
	if _count_t > 0.0 or _count == 0:
		return
	_count_t = 0.45
	if Main.inst and Main.inst.hud:
		Main.inst.hud.popup("싹싹 ×%d" % _count, Color(0.85, 1.0, 0.95), at + Vector3(rng.randf_range(-0.4, 0.4), 2.3, 0))
	_count = 0


## 남은 조각을 모두 치운다 (드론이 사라질 때)
func clear() -> void:
	for f: Array in fly:
		if is_instance_valid(f[0]):
			(f[0] as Node).queue_free()
	fly.clear()
