extends "res://scripts/abyss/abyss_foe.gd"
## 애가꽃 (LAMENT): 바닥에 뿌리내린 생체 포대. 흑철 줄기 끝의 꽃봉오리(뼈빛 꽃잎 여섯 장)가
## 열리면 안쪽의 진홍 심장이 드러나며 초승달 탄막을 뿌린다.
## 탄막 셋: 나선(세 갈래가 돌며 흩뿌림) · 장벽(가로 한 줄 초승달을 세 번 겨눠 밀어냄) · 이중 고리(엇갈린 두 겹 원형탄).
## 세 번 쏘면 바닥 아래로 가라앉아 다른 자리에서 다시 피어난다. 등장은 바닥 소환 문양에서 솟아오른다.

enum S { RISE, IDLE, OPEN, FIRE, CLOSE, SINK }

const Shot := preload("res://scripts/abyss/abyss_shot.gd")
const PINK := Color(1.0, 0.12, 0.42)
const CRIMSON := Color(1.0, 0.07, 0.15)
const RISE_T := 1.1
const OPEN_T := 0.5
const CLOSE_T := 0.4

var pattern_k := 0
var fired := 0
var fire_t := 0.0
var shots := 0
var spin_dir := 1.0
var open_k := 0.0
var _home := Vector3.ZERO


func _ready() -> void:
	hp = 6
	radius = 0.75
	slice_size = Vector3(0.9, 1.0, 0.9)
	slice_color = BONE
	hp_bar_y = 2.7
	hp_bar_w = 1.0
	super._ready()
	visual.scale = Vector3.ONE * 1.3
	pattern_k = randi() % 3
	spin_dir = 1.0 if randf() < 0.5 else -1.0
	(j.body as Node3D).position.y = -2.6
	shadow.scale = Vector3.ONE * 0.8
	go(S.RISE)
	AbyssFX.sigil(global_position, 1.3, RISE_T * 0.8, PINK)


func _build(v: Node3D) -> Dictionary:
	var body := Build.pivot(v, Vector3.ZERO, "Body")
	# 바닥에 퍼진 뿌리
	for i in 6:
		var a := TAU * i / 6.0 + 0.3
		var root := Build.cyl(body, 0.09, 1.1, Vector3(cos(a) * 0.5, 0.06, sin(a) * 0.5), FLESH, Vector3(0, 0, 0), 0.03, 6)
		root.rotation = Vector3(0, -a, deg_to_rad(80.0))
	Build.cyl(body, 0.42, 0.3, Vector3(0, 0.15, 0), IRON, Vector3.ZERO, 0.3, 8)
	# 줄기: 마디 셋
	var stalk := Build.pivot(body, Vector3(0, 0.3, 0), "Stalk")
	var seg_a := Build.pivot(stalk, Vector3.ZERO, "A")
	Build.cyl(seg_a, 0.17, 0.6, Vector3(0, 0.3, 0), IRON_LIGHT, Vector3.ZERO, 0.13, 8)
	Build.cyl(seg_a, 0.21, 0.08, Vector3(0, 0.6, 0), BONE_DARK, Vector3.ZERO, -1.0, 8)
	var seg_b := Build.pivot(seg_a, Vector3(0, 0.62, 0), "B")
	Build.cyl(seg_b, 0.13, 0.55, Vector3(0, 0.27, 0), FLESH, Vector3.ZERO, 0.11, 8)
	# 꽃봉오리: 심장 + 꽃잎 여섯
	var head := Build.pivot(seg_b, Vector3(0, 0.6, 0), "Head")
	var core_m := glow_mat(CRIMSON, 1.2)
	var sm := SphereMesh.new()
	sm.radius = 0.28
	sm.height = 0.5
	var core := MeshInstance3D.new()
	core.mesh = sm
	core.material_override = core_m
	head.add_child(core)
	core.position = Vector3(0, 0.32, 0)
	Build.cyl(head, 0.2, 0.18, Vector3(0, 0.05, 0), IRON, Vector3.ZERO, 0.32, 8)
	var petals: Array = []
	for i in 6:
		var a := TAU * i / 6.0
		var pv := Build.pivot(head, Vector3(cos(a) * 0.2, 0.12, sin(a) * 0.2), "Petal%d" % i)
		pv.rotation.y = -a + PI * 0.5
		var leaf := Build.bevel(pv, Vector3(0.3, 0.62, 0.07), Vector3(0, 0.3, 0), BONE if i % 2 == 0 else Color("c4b6a0"), 0.03, Vector3.ZERO, 0.45)
		leaf.name = "Leaf"
		# 꽃잎 안쪽의 붉은 맥
		var vein := Build.glow_box(pv, Vector3(0.04, 0.42, 0.01), Vector3(0, 0.3, -0.04), PINK, 1.8)
		vein.name = "Vein"
		petals.append(pv)
	return {"body": body, "core": core, "core_mat": core_m, "head": head, "stalk": stalk, "a": seg_a, "b": seg_b, "petals": petals}


func _punch_scale() -> void:
	var h := j.head as Node3D
	h.scale = Vector3.ONE * (1.0 + punch * 0.2)


func _update_entry(dt: float) -> void:
	st_t += dt
	var body := j.body as Node3D
	var k := clampf(st_t / RISE_T, 0.0, 1.0)
	body.position.y = lerpf(-2.6, 0.0, smoothstep(0.35, 1.0, k))
	_bloom(0.0)
	if k > 0.35 and randf() < 0.5:
		FX.sparks(global_position + Vector3(randf_range(-0.6, 0.6), 0.1, randf_range(-0.6, 0.6)), 2, [PINK, CRIMSON], 3.0, 0.3, -6.0, 0.05)
	if k >= 1.0:
		landed = true
		_home = global_position
		go(S.IDLE)
		fire_t = randf_range(0.8, 1.6)
		FX.land_dust(global_position)


func _ai(dt: float) -> void:
	var tp := to_player()
	var dir: Vector3 = tp[0]
	var stalk := j.stalk as Node3D
	var em := j.core_mat as StandardMaterial3D
	# 줄기가 플레이어 쪽으로 천천히 고개를 돌리며 흔들린다
	face(dir, dt, 2.5)
	stalk.rotation = Vector3(sin(t * 1.3) * 0.06 - open_k * 0.12, 0, sin(t * 0.9) * 0.08)
	(j.b as Node3D).rotation = Vector3(sin(t * 1.7 + 1.0) * 0.08 + open_k * 0.2, 0, 0)
	knock = knock.move_toward(Vector3.ZERO, 40.0 * dt)
	global_position += knock * dt * 0.2
	match st:
		S.IDLE:
			open_k = move_toward(open_k, 0.0, dt * 3.0)
			em.emission_energy_multiplier = 1.0 + sin(t * 3.0) * 0.3
			fire_t -= dt
			if fire_t <= 0.0 and active():
				if fired >= 3:
					go(S.SINK)
					AbyssFX.sigil(global_position, 1.2, 0.7, PINK)
					Sfx.play("hrise", 0.2, -10.0)
				else:
					go(S.OPEN)
					set_tele(true)
					Sfx.play("twind", 0.2, -12.0)
		S.OPEN:
			open_k = clampf(st_t / OPEN_T, 0.0, 1.0)
			em.emission_energy_multiplier = 1.0 + open_k * 5.0
			if st_t >= OPEN_T:
				set_tele(false)
				go(S.FIRE)
				shots = 0
				fire_t = 0.0
		S.FIRE:
			open_k = 1.0
			em.emission_energy_multiplier = 5.0 + sin(t * 30.0) * 1.5
			if _fire(dt):
				fired += 1
				pattern_k = (pattern_k + 1) % 3
				go(S.CLOSE)
		S.CLOSE:
			open_k = 1.0 - clampf(st_t / CLOSE_T, 0.0, 1.0)
			em.emission_energy_multiplier = 1.0 + open_k * 4.0
			if st_t >= CLOSE_T:
				go(S.IDLE)
				fire_t = randf_range(1.5, 2.4)
		S.SINK:
			var k := clampf(st_t / 0.7, 0.0, 1.0)
			(j.body as Node3D).position.y = lerpf(0.0, -2.6, k * k)
			if k >= 1.0:
				_relocate()
	_bloom(open_k)


## 꽃잎을 연다 (0 닫힘 ~ 1 활짝)
func _bloom(k: float) -> void:
	var e := 1.0 - pow(1.0 - k, 3.0)
	for pv in j.petals:
		(pv as Node3D).rotation.x = lerpf(-0.18, 1.15, e)
	(j.core as Node3D).scale = Vector3.ONE * (0.75 + e * 0.45)


## 탄막 하나를 진행한다. 끝나면 true
func _fire(dt: float) -> bool:
	fire_t -= dt
	var origin := (j.core as Node3D).global_position
	origin.y = 0.95
	match pattern_k:
		0:
			# 나선: 세 갈래가 돌며 0.08초마다 흩뿌린다 (2.2초)
			if fire_t <= 0.0:
				fire_t = 0.085
				var base := st_t * 2.1 * spin_dir
				for i in 3:
					var a := base + TAU * i / 3.0
					var d := Vector3(sin(a), 0, cos(a))
					Main.inst.add_bullet(Shot.make(origin + d * 0.4, d, 5.2, PINK, 0.55))
				if shots % 3 == 0:
					Sfx.play("eshot", 0.1, -12.0)
				shots += 1
			return st_t > 2.2
		1:
			# 장벽: 가로 한 줄(초승달 7개)을 플레이어 쪽으로 세 번
			if fire_t <= 0.0 and shots < 3:
				fire_t = 0.5
				var tp := to_player()
				var fwd: Vector3 = tp[0]
				var side := Vector3(-fwd.z, 0, fwd.x)
				for i in 7:
					var off := (i - 3) * 0.62
					var b := Shot.make(origin + side * off + fwd * 0.5, fwd, 4.4 + absf(i - 3) * 0.12, CRIMSON, 0.7) as Bullet
					b.set("accel", 1.4)
					Main.inst.add_bullet(b)
				FX.flash(origin, Color(1.0, 0.6, 0.7), 0.7, 0.06)
				Sfx.play("eshot", 0.05, -6.0)
				shots += 1
			return shots >= 3 and fire_t <= 0.0
		_:
			# 이중 고리: 16발 원형 → 0.3초 뒤 반 칸 엇갈려 한 번 더
			if fire_t <= 0.0 and shots < 2:
				fire_t = 0.3
				var off := randf() * 0.4 + (PI / 16.0 if shots == 1 else 0.0)
				for i in 16:
					var a := TAU * i / 16.0 + off
					var d := Vector3(sin(a), 0, cos(a))
					var b := Shot.make(origin + d * 0.5, d, 4.0 if shots == 0 else 3.2, PINK, 0.6) as Bullet
					Main.inst.add_bullet(b)
				FX.flash(origin, Color(1.0, 0.7, 0.8), 0.9, 0.07)
				AbyssFX.light_flash(origin, PINK, 3.0, 5.0, 0.2)
				Sfx.play("eshot", 0.05, -4.0)
				shots += 1
			return shots >= 2 and fire_t <= 0.0


## 가라앉았다가 다른 자리에서 피어난다
func _relocate() -> void:
	var m = Main.inst
	if m.has_method("random_floor_spot"):
		global_position = m.call("random_floor_spot", 5.5)
	fired = 0
	landed = false
	go(S.RISE)
	AbyssFX.sigil(global_position, 1.3, RISE_T * 0.8, PINK)


func _on_stagger() -> void:
	super._on_stagger()
	if st == S.OPEN or st == S.FIRE:
		go(S.CLOSE)


func _begin_death() -> void:
	var c := (j.core as Node3D).global_position
	# 꽃잎이 흩어지고 심장이 터진다
	for pv in j.petals:
		var leaf := (pv as Node3D).get_node("Leaf") as MeshInstance3D
		Debris.toss(leaf.mesh, leaf.material_override, leaf.global_transform, (leaf.global_position - c).normalized() * 6.0 + Vector3(0, 4.0, 0), 1.4)
	FX.flash(c, Color(1.0, 0.8, 0.9), 1.2, 0.08)
	FX.sparks(c, 24, [Color.WHITE, PINK, CRIMSON], 9.0, 0.5, -10.0, 0.09)
	AbyssFX.light_flash(c, PINK, 5.0, 7.0, 0.35)
	super._begin_death()
