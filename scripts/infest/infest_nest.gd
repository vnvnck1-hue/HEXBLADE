class_name InfestNest
extends Enemy
## 감염 오염물 한 무더기 (구석에 종양처럼 뭉친 감염 포낭 I05 여러 개 + 바닥·벽을 덮은 감염 연결막 I04).
## 판정 경로(탄·검·레이저·미사일·폭발)를 그대로 받으려고 Enemy 를 상속하지만 prop 이라 처치 수·방 진행·소환 상한·봇 표적·락온에서 빠진다.
##
##  맞으면  맞은 쪽 포낭이 출렁 눌리고(스프링) 하얗게 번쩍, 체액이 조금 튄다. 무더기 전체가 흥분해 빠르게 꿀렁인다.
##           탄 = 맞은 자리에서 가장 가까운 포낭 하나 · 검/레이저 = 플레이어 쪽 포낭 셋 · 폭발/미사일/볼텍스 = 맞은 자리 둘레 전부.
##  터짐    체력이 다한 포낭은 순간 부풀었다가 퍽 터지며 끈적한 체액을 사방으로 뿌리고(InfestSplash) 쭈그러든 껍질로 남는다.
##           곁의 작은 혹들은 덩달아 연달아 터진다.
##  다 터짐 막이 시들고 껍질·막·체액 웅덩이가 청소 대상 잔해(InfestRemains)로 넘어간다 → 드론·Z·Space 청소.
##
## 배치는 Infestation 이 정한다: plan = {"cysts": [{pos, basis, s, v, wall}], "mems": [{pos, basis, scale, v}]}
## (pos 는 무더기 원점 기준, basis 의 y 축 = 바깥 방향(바닥이면 위, 벽이면 벽 법선)).

const SWELL := 0.075             ## 터지기 직전 부푸는 시간
const CHAIN_S := 0.62            ## 이보다 작은 혹은 곁에서 터지면 덩달아 터진다
const BLAST_SOURCES := ["missile", "blast", "vortex", "rupture", "vent"]
const WIDE_SOURCES := ["slash", "phantom", "laser"]

class Cyst:
	var pivot: Node3D
	var mi: MeshInstance3D
	var s := 1.0
	var hp := 1
	var wall := false
	var up := Vector3.UP
	var base: Basis
	var popped := false
	var pop_t := -1.0
	var punch := 0.0
	var punch_v := 0.0
	var hit := 0.0
	var dead := 0.0
	var phase := 0.0
	var sent := Vector4(-1, -1, -1, -1)
	var still := false        ## 스프링이 멈춰 자세를 이미 써 둠 (다시 맞거나 부풀 때까지 건너뛴다)

	func center() -> Vector3:
		return pivot.global_position + up * 0.14 * s

	func radius() -> float:
		return 0.25 * s

var plan := {}
var cysts: Array[Cyst] = []
var mems: Array[MeshInstance3D] = []
var agit := 0.0
var _agit_sent := -1.0
var _chain: Array = []            ## [남은 시간, Cyst]
var _first_hit := true


func _ready() -> void:
	prop = true
	super._ready()
	add_to_group("infest_nests")
	InfestSound.ensure()
	(j.body as Node3D).position = Vector3.ZERO
	landed = true
	shadow.visible = false
	slice_color = InfestMesh.GOO
	radius = 0.6
	var far := 0.0
	var hp_sum := 0
	for c in cysts:
		if not c.wall:
			var l := Vector2(c.pivot.position.x, c.pivot.position.z).length() + c.radius() * 0.6
			far = maxf(far, l)
		hp_sum += c.hp
	radius = clampf(far, 0.55, 1.7)
	hp = hp_sum
	max_hp = maxi(hp_sum, 1)          # Enemy 체력바는 만들지 않는다 (_init_hp 를 건너뜀)


## 카메라에서 이보다 먼 둥지는 그리지 않는다 (그림자 포함). 화면 가장자리는 궁극기 조준으로 시야가 옮겨 가도 약 37m.
## 맵 전체 둥지(혹 약 300개 · 50만 삼각형 · 그림자 200개)가 BrawlLook 그림자 거리 70m 안에서 그림자 맵에 그려지던 것
const VIEW_RANGE := 48.0


func _build(v: Node3D) -> Dictionary:
	var body := Build.pivot(v, Vector3.ZERO, "Body")
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([plan.get("seed", 0), "nest"])
	for m: Dictionary in plan.get("mems", []):
		var mi := MeshInstance3D.new()
		mi.mesh = InfestMesh.membrane(int(m.v))
		mi.material_override = InfestMesh.membrane_mat(int(m.v))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = VIEW_RANGE
		var sc: Vector3 = m.scale
		var b: Basis = m.basis
		mi.transform = Transform3D(Basis(b.x * sc.x, b.y * sc.y, b.z * sc.z), m.pos)
		mi.set_instance_shader_parameter("phase", rng.randf() * TAU)
		body.add_child(mi)
		mems.append(mi)
	for c: Dictionary in plan.get("cysts", []):
		var cy := Cyst.new()
		cy.s = float(c.s)
		cy.wall = bool(c.get("wall", false))
		cy.hp = clampi(roundi(cy.s * 2.6), 1, 6)
		cy.base = c.basis
		cy.pivot = Node3D.new()
		cy.pivot.position = c.pos
		cy.pivot.basis = cy.base
		body.add_child(cy.pivot)
		cy.mi = MeshInstance3D.new()
		cy.mi.mesh = InfestMesh.cyst(int(c.v))
		cy.mi.material_override = InfestMesh.cyst_mat()
		cy.mi.scale = Vector3.ONE * cy.s
		cy.mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cy.s > 0.55 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cy.mi.visibility_range_end = VIEW_RANGE
		cy.phase = rng.randf() * TAU
		cy.mi.set_instance_shader_parameter("phase", cy.phase)
		cy.pivot.add_child(cy.mi)
		cy.up = cy.base.y.normalized()
		cysts.append(cy)
	return {"body": body}


func _physics_process(dt: float) -> void:
	if not alive:
		return
	t += dt
	# 플레이어가 다가오면 흥분해서 빨리 꿀렁인다
	var target := 0.0
	var p := Main.inst.player if Main.inst else null
	if p and is_instance_valid(p):
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		target = clampf(1.0 - (d - radius) / 2.6, 0.0, 1.0) * 0.35
	agit = move_toward(agit, target, dt * (0.35 if agit > target else 1.5))
	var ag := snappedf(agit, 0.02)
	var ag_changed := ag != _agit_sent
	if ag_changed:
		_agit_sent = ag
		for m in mems:
			m.set_instance_shader_parameter("agit", ag)
	var i := _chain.size() - 1
	while i >= 0:
		_chain[i][0] -= dt
		if _chain[i][0] <= 0.0:
			var c: Cyst = _chain[i][1]
			_chain.remove_at(i)
			if not c.popped and c.pop_t < 0.0:
				c.pop_t = 0.0
		i -= 1
	var any_alive := false
	for c in cysts:
		_tick_cyst(c, dt, ag, ag_changed)
		if not c.popped:
			any_alive = true
	if not any_alive and _chain.is_empty():
		_wither()


func _tick_cyst(c: Cyst, dt: float, ag: float, ag_changed: bool) -> void:
	var swell := 0.0
	if c.pop_t >= 0.0 and not c.popped:
		c.pop_t += dt
		swell = clampf(c.pop_t / SWELL, 0.0, 1.0)
		if c.pop_t >= SWELL:
			_pop(c)
			swell = 0.0
	# 젤리 스프링: 맞으면 납작하게 눌렸다가 늘어나며 출렁인다
	c.punch_v += (-c.punch * 240.0 - c.punch_v * 11.0) * dt
	c.punch += c.punch_v * dt
	c.hit = maxf(0.0, c.hit - dt * 9.0)
	# 멈춘 혹은 자세·셰이더 값을 다시 쓰지 않는다 (맵 전체 둥지의 혹 수백 개가 매 틱 변환을 쓰던 것)
	var rest := absf(c.punch) < 0.0005 and absf(c.punch_v) < 0.005 and swell == 0.0 and c.hit == 0.0 and c.sent.z == snappedf(c.dead, 0.05)
	if rest and c.still and not ag_changed:
		return
	c.still = rest
	var pk := c.punch
	var sw := 1.0 + swell * 0.22
	if c.popped:
		sw = 1.0
		pk *= 0.4
	c.pivot.basis = Basis(c.base.x * (1.0 + pk * 0.22) * sw, c.base.y * (1.0 - pk * 0.32) * sw, c.base.z * (1.0 + pk * 0.22) * sw)
	var v := Vector4(snappedf(c.hit, 0.05), snappedf(swell, 0.05), snappedf(c.dead, 0.05), 0)
	if v != c.sent:
		c.sent = v
		c.mi.set_instance_shader_parameter("hit", v.x)
		c.mi.set_instance_shader_parameter("swell", v.y)
		c.mi.set_instance_shader_parameter("dead", v.z)
	if ag_changed or swell > 0.0:
		c.mi.set_instance_shader_parameter("agit", minf(1.0, ag + swell))


# ── 판정 ────────────────────────────────────────────────

func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	if not alive:
		return
	var live: Array[Cyst] = []
	for c in cysts:
		if not c.popped and c.pop_t < 0.0:
			live.append(c)
	if live.is_empty():
		return
	var flat := Vector3(dir.x, 0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	var hits: Array[Cyst] = []
	if source in BLAST_SOURCES:
		var at := pos if pos != Vector3.ZERO and pos.distance_to(global_position) < radius + 2.0 else global_position
		for c in live:
			if c.center().distance_to(at) < 1.4 + c.radius():
				hits.append(c)
		if hits.is_empty():
			hits.append(_nearest(live, at))
	elif source in WIDE_SOURCES or pos.distance_to(global_position) < 0.05:
		# 플레이어 쪽 면 (공격이 온 쪽)
		var face := global_position - flat * radius * 0.8 + Vector3.UP * 0.2
		live.sort_custom(func(a: Cyst, b: Cyst) -> bool: return a.center().distance_to(face) < b.center().distance_to(face))
		for k in mini(3 if source in WIDE_SOURCES else 1, live.size()):
			hits.append(live[k])
	else:
		hits.append(_nearest(live, pos))
	for c in hits:
		_damage(c, dmg, flat)
	agit = maxf(agit, 0.75)
	Sfx.play("infest_hit", 0.15, -7.0)
	if _first_hit and Main.inst and Main.inst.hud:
		_first_hit = false
		Main.inst.hud.popup("감염 포낭", Color("ff8fc8"), global_position + Vector3(0, 1.4, 0))


func _nearest(list: Array[Cyst], at: Vector3) -> Cyst:
	var best: Cyst = list[0]
	var bd := INF
	for c in list:
		var d := c.center().distance_to(at) - c.radius()
		if d < bd:
			bd = d
			best = c
	return best


func _damage(c: Cyst, dmg: int, dir: Vector3) -> void:
	c.hp -= dmg
	c.hit = 1.0
	c.punch_v += 7.0 + minf(dmg, 6) * 1.6
	InfestSplash.spray(c.center() - dir * c.radius() * 0.7, -dir + c.up, c.s * 0.5)
	if c.hp <= 0 and c.pop_t < 0.0:
		c.pop_t = 0.0


## 포낭 하나 터짐
func _pop(c: Cyst) -> void:
	c.popped = true
	var k := clampf(c.s * 0.55, 0.2, 1.3)
	InfestSplash.burst(c.center() + c.up * 0.08 * c.s, c.up, k)
	var snd := Sfx.play("infest_pop", 0.12, lerpf(-12.0, -2.0, clampf(c.s / 2.0, 0.0, 1.0)))
	if snd:
		snd.pitch_scale = lerpf(1.35, 0.8, clampf(c.s / 2.0, 0.0, 1.0)) * randf_range(0.94, 1.06)
	var main := Main.inst
	if main:
		main.shake(0.06 + k * 0.14)
		if c.s > 1.2:
			main.hitstop(0.03)
		main.score += int(8.0 * c.s) + 2
	# 껍질: 쭈그러들며 주름진 가죽으로 남는다
	var tw := create_tween()
	tw.tween_method(func(v: float): c.dead = v, 0.0, 1.0, 0.22).set_ease(Tween.EASE_OUT)
	c.punch_v -= 10.0
	c.mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	agit = 1.0
	# 곁의 작은 혹은 덩달아 연달아 터진다
	for o in cysts:
		if o == c or o.popped or o.pop_t >= 0.0 or o.s > CHAIN_S:
			continue
		if o.center().distance_to(c.center()) < c.radius() + o.radius() + 0.12:
			_chain.append([randf_range(0.05, 0.16), o])


## 무더기가 다 터짐 → 막이 시들고 잔해(청소 대상)로 넘어간다
func _wither() -> void:
	alive = false
	remove_from_group("enemies")
	Sfx.play("infest_tear", 0.1, -8.0)
	var parts: Array = []
	for c in cysts:
		c.punch = 0.0
		c.pivot.basis = c.base
		c.mi.set_instance_shader_parameter("agit", 0.0)
		c.mi.set_instance_shader_parameter("dead", 1.0)
		parts.append(c.pivot)
	for m in mems:
		m.set_instance_shader_parameter("agit", 0.0)
		var mm := m
		mm.create_tween().tween_method(func(v: float):
			if is_instance_valid(mm):
				mm.set_instance_shader_parameter("dead", v), 0.0, 0.7, 0.5)
		parts.append(m)
	var main := Main.inst
	var at := Vector3(global_position.x, Main.gy(global_position), global_position.z)
	if main:
		main.score += 30
		if main.hud:
			main.hud.popup("오염 제거 · 청소!", Color("7dffd0"), at + Vector3(0, 1.6, 0))
	InfestRemains.make(main.world if main else get_parent(), at, parts, radius * 1.05)
	queue_free()


## 즉사 (확인용 전멸 키 등): 남은 포낭을 차례로 터뜨린다
func die(_dir := Vector3.ZERO, _source := "bullet") -> void:
	var d := 0.0
	for c in cysts:
		if not c.popped and c.pop_t < 0.0:
			_chain.append([d, c])
			d += 0.05


func stagger(_dir: Vector3, _dur: float) -> void:
	pass


func _set_flash(_on: bool) -> void:
	pass


func set_locked(_on: bool) -> void:
	pass


## 살아 있는 포낭 수
func alive_cysts() -> int:
	var n := 0
	for c in cysts:
		if not c.popped:
			n += 1
	return n


## 플레이어가 이 무더기 포낭 속으로 걸어 들어가지 않게 밀어낸다 (살아 있는 바닥 포낭만, 작은 혹은 밟고 지나감)
func push_out(p: Vector3, r: float) -> Vector3:
	for c in cysts:
		if c.popped or c.wall or c.s < 0.5:
			continue
		var cp := c.pivot.global_position
		var d := Vector2(p.x - cp.x, p.z - cp.z)
		var lim := c.radius() * 0.82 + r
		if d.length() < lim:
			var n := d.normalized() if d.length() > 0.001 else Vector2(1, 0)
			p.x = cp.x + n.x * lim
			p.z = cp.z + n.y * lim
	return p
