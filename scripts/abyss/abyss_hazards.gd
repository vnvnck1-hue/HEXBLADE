extends Node3D
## 심연 성소의 함정 (킬 나이트처럼 레이어마다 하나씩 늘어나고, 뒤로 갈수록 겹친다).
##  - 체액 분출구: 창살 판이 끓어오르다(1.2초) 체액 기둥을 뿜는다. 위에 선 것은 플레이어든 적이든 다친다.
##  - 심판의 탑: 전장 밖 심연에서 솟은 오벨리스크가 예고선을 긋고(1.3초) 붉은 빔으로 전장을 쓸고 지나간다.
## 적도 함정에 맞는다 → 적을 끌어들여 처치할 수 있다. 판정은 여기서, 그림은 AbyssFX 로.

const Stage := preload("res://scripts/abyss/abyss_stage.gd")

const VENT_CHARGE := 1.2
const VENT_BLAST := 0.55
const VENT_R := 1.15
const BEAM_W := 0.95
const BEAM_LEN := 40.0
const TOWER_TELE := 1.3
const TOWER_FIRE := 1.9
const TOWER_SWEEP := 0.55        # 쓸고 지나가는 반각 (rad)

var stage: Stage
var vents_on := false
var towers_on := false
var vents: Dictionary = {}       # Vector2i → {t, state, hit}
var towers: Array = []           # {node, eye_mat, pos, base_a, state, t, a, a0, a1, beam, rise, hit_t}
var t := 0.0


func _ready() -> void:
	for spec in [[Vector3(-19.0, 0, -4.0), 0.0], [Vector3(19.0, 0, 4.0), PI]]:
		towers.append(_tower(spec[0], spec[1]))
	# 두 탑은 엇갈려 쏜다
	towers[0].t = 1.0
	towers[1].t = 3.6


func _tower(pos: Vector3, base_a: float) -> Dictionary:
	var n := Node3D.new()
	add_child(n)
	n.position = pos + Vector3(0, -22.0, 0)
	n.visible = false
	var rock := (stage.props as Node3D).get("rock_mat") as Material
	# 받침 + 세 단 오벨리스크 + 꼭대기 눈
	for spec in [[Vector3(2.6, 20.0, 2.6), -9.0, 1.0], [Vector3(1.9, 4.0, 1.9), 2.2, 0.85], [Vector3(1.3, 3.2, 1.3), 5.6, 0.6]]:
		var mi := MeshInstance3D.new()
		mi.mesh = Build.bevel_mesh(spec[0], 0.15, spec[2])
		mi.material_override = rock
		n.add_child(mi)
		mi.position = Vector3(0, spec[1], 0)
	var eye_m := StandardMaterial3D.new()
	eye_m.albedo_color = AbyssFX.ICHOR_HOT
	eye_m.emission_enabled = true
	eye_m.emission = AbyssFX.ICHOR_HOT
	eye_m.emission_energy_multiplier = 1.0
	var em := SphereMesh.new()
	em.radius = 0.42
	em.height = 0.84
	var eye := MeshInstance3D.new()
	eye.mesh = em
	eye.material_override = eye_m
	n.add_child(eye)
	eye.position = Vector3(0, 1.0, 0)
	# 눈을 감싼 쇠 고리 둘
	for k in 2:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.55
		tm.outer_radius = 0.68
		ring.mesh = tm
		ring.material_override = Pal.lit(Color(0.1, 0.09, 0.1))
		n.add_child(ring)
		ring.position = Vector3(0, 1.0, 0)
		ring.rotation = Vector3(PI * 0.5 * k, 0, 0.4)
	var l := OmniLight3D.new()
	l.light_color = AbyssFX.ICHOR_HOT
	l.light_energy = 0.0
	l.omni_range = 10.0
	n.add_child(l)
	l.position = Vector3(0, 1.0, 0)
	return {"node": n, "eye_mat": eye_m, "eye": eye, "light": l, "pos": pos, "base_a": base_a, "state": 0, "t": 0.0,
		"a": base_a, "a0": base_a, "a1": base_a, "beam": null, "rise": 0.0, "hit_t": 0.0, "fx_t": 0.0}


func set_towers(on: bool) -> void:
	towers_on = on
	for tw in towers:
		(tw.node as Node3D).visible = true
		if not on:
			_end_beam(tw)
			tw.state = 0


func set_vents(on: bool) -> void:
	vents_on = on
	if not on:
		for c in vents:
			_vent_param(c, 0.0)
		vents.clear()


func _vent_param(c: Vector2i, charge: float) -> void:
	var tl := stage.tile_at(c)
	if not tl.is_empty():
		(tl.mi as MeshInstance3D).set_instance_shader_parameter("vent", 1.0 + charge if tl.kind == Stage.K.VENT else 0.0)


## 자동 플레이 회피용 위험 목록
func threats() -> Array:
	var out: Array = []
	for c in vents:
		var v: Dictionary = vents[c]
		if v.state >= 1:
			out.append({"type": "circle", "pos": Stage.cell_center(c), "r": VENT_R + 0.4})
	for tw in towers:
		if tw.state == 1 or tw.state == 2:
			out.append({"type": "beam", "origin": _eye_ground(tw), "a": tw.a, "a1": tw.a1, "half": BEAM_W * 0.5, "len": BEAM_LEN, "sweep": tw.state == 2, "fire": tw.state == 2})
	return out


func _eye_ground(tw: Dictionary) -> Vector3:
	var p: Vector3 = tw.pos
	return Vector3(p.x, 0.95, p.z)


static func _dir(a: float) -> Vector3:
	return Vector3(cos(a), 0, sin(a))


func _physics_process(dt: float) -> void:
	t += dt
	_update_vents(dt)
	_update_towers(dt)


# ── 분출구 ──────────────────────────────────────────────

func _update_vents(dt: float) -> void:
	if not vents_on:
		return
	# 지금 배치의 분출구를 등록한다 (판이 바뀌면 사라진 것은 지운다)
	var live := stage.vent_cells()
	for c in live:
		if not vents.has(c):
			vents[c] = {"t": randf_range(1.5, 4.5), "state": 0, "hit": false}
	for c in vents.keys():
		if not live.has(c):
			vents.erase(c)
	for c in vents:
		var v: Dictionary = vents[c]
		v.t -= dt
		match int(v.state):
			0:
				_vent_param(c, 0.0)
				if v.t <= 0.0:
					v.state = 1
					v.t = VENT_CHARGE
					Sfx.play("hrise", 0.3, -14.0)
			1:
				var k: float = 1.0 - float(v.t) / VENT_CHARGE
				_vent_param(c, k)
				if randf() < dt * (4.0 + k * 14.0):
					stage.dust(Stage.cell_center(c) + Vector3(randf_range(-0.7, 0.7), 0.1, randf_range(-0.7, 0.7)), 0.5, Color(1.0, 0.1, 0.15, 0.5), true, Vector3(0, 1.5 + k * 3.0, 0), 0.4)
				if v.t <= 0.0:
					v.state = 2
					v.t = VENT_BLAST
					v.hit = false
					AbyssFX.geyser(Stage.cell_center(c), 1.6, stage)
					Sfx.play("launch", 0.2, -6.0)
					Main.inst.shake(0.12)
			2:
				_vent_param(c, 1.0)
				var cc := Stage.cell_center(c)
				if randf() < 0.6:
					stage.dust(cc + Vector3(randf_range(-0.4, 0.4), 0.3, randf_range(-0.4, 0.4)), randf_range(0.6, 1.0), Color(1.0, 0.08, 0.13, 0.8), true, Vector3(0, randf_range(5.0, 8.0), 0), 0.4)
				_hurt_circle(cc, VENT_R, v)
				if v.t <= 0.0:
					v.state = 0
					v.t = randf_range(3.2, 6.0)
					AbyssFX.splat(cc, 1.4, 0.8)


func _hurt_circle(c: Vector3, r: float, v: Dictionary) -> void:
	if v.hit:
		return
	var p := Main.inst.player
	if p.alive and Vector2(p.global_position.x - c.x, p.global_position.z - c.z).length() < r + p.hit_radius:
		if p.take_hit(c):
			v.hit = true
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en.alive and en.landed and not en.is_boss and Vector2(en.global_position.x - c.x, en.global_position.z - c.z).length() < r + en.radius * 0.5:
			if not en.has_meta("vent_hit_t") or t - float(en.get_meta("vent_hit_t")) > 0.5:
				en.set_meta("vent_hit_t", t)
				en.take_hit(6, Vector3.UP, en.global_position, "vent")


# ── 심판의 탑 ───────────────────────────────────────────

func _update_towers(dt: float) -> void:
	for tw in towers:
		var n := tw.node as Node3D
		# 켜지면 심연에서 솟고, 꺼지면 가라앉는다
		tw.rise = move_toward(float(tw.rise), 1.0 if towers_on else 0.0, dt * 0.45)
		var p: Vector3 = tw.pos
		n.position = p + Vector3(0, lerpf(-22.0, 0.0, smoothstep(0.0, 1.0, tw.rise)), 0)
		n.visible = tw.rise > 0.01
		var eye_m := tw.eye_mat as StandardMaterial3D
		var l := tw.light as OmniLight3D
		(tw.eye as Node3D).rotation.y += dt * 0.8
		if not towers_on or tw.rise < 0.99:
			eye_m.emission_energy_multiplier = 1.0
			l.light_energy = 0.0
			continue
		tw.t = float(tw.t) - dt
		match int(tw.state):
			0:
				eye_m.emission_energy_multiplier = 1.2 + 0.4 * sin(t * 3.0)
				l.light_energy = 0.6
				if tw.t <= 0.0:
					_begin_tele(tw)
			1:
				var k := 1.0 - float(tw.t) / TOWER_TELE
				eye_m.emission_energy_multiplier = 1.5 + k * 8.0
				l.light_energy = 1.0 + k * 5.0
				AbyssFX.set_beam(tw.beam, _eye_ground(tw), _dir(tw.a), BEAM_LEN, 0.22 + k * 0.25, 0.0, 0.6 + k * 0.6)
				if tw.t <= 0.0:
					tw.state = 2
					tw.t = TOWER_FIRE
					tw.hit_t = 0.0
					Sfx.play("elaser", 0.05, -2.0)
					Main.inst.shake(0.25)
					AbyssFX.light_flash(_eye_ground(tw), AbyssFX.ICHOR_HOT, 8.0, 14.0, 0.4)
			2:
				var k := 1.0 - float(tw.t) / TOWER_FIRE
				tw.a = lerp_angle(float(tw.a0), float(tw.a1), smoothstep(0.0, 1.0, k))
				var o := _eye_ground(tw)
				var d := _dir(tw.a)
				var w := BEAM_W * (1.0 + 0.12 * sin(t * 60.0)) * (1.0 - smoothstep(0.85, 1.0, k))
				AbyssFX.set_beam(tw.beam, o, d, BEAM_LEN, w * 1.6, 1.0, 1.0)
				eye_m.emission_energy_multiplier = 10.0
				l.light_energy = 7.0
				_beam_hits(tw, o, d, dt)
				tw.fx_t = float(tw.fx_t) - dt
				if tw.fx_t <= 0.0:
					tw.fx_t = 0.07
					# 빔이 전장 위를 긁고 가는 자리: 불꽃 · 그을음
					var along := randf_range(4.0, 34.0)
					var q := o + d * along
					if stage.on_floor(q):
						FX.sparks(Vector3(q.x, 0.15, q.z), 4, [Color.WHITE, Color(1.0, 0.5, 0.5), AbyssFX.ICHOR_HOT], 6.0, 0.3, -12.0, 0.06)
						AbyssFX.scorch(q - d * 0.6, d, 1.2, 0.5)
				if tw.t <= 0.0:
					_end_beam(tw)
					tw.state = 0
					tw.t = randf_range(3.6, 5.2)


func _begin_tele(tw: Dictionary) -> void:
	tw.state = 1
	tw.t = TOWER_TELE
	# 플레이어 쪽을 기준으로, 한쪽 끝에서 반대쪽 끝으로 쓴다
	var o := _eye_ground(tw)
	var pp := Main.inst.player.global_position
	var aim := atan2(pp.z - o.z, pp.x - o.x)
	var s := 1.0 if randf() < 0.5 else -1.0
	tw.a0 = aim - TOWER_SWEEP * s
	tw.a1 = aim + TOWER_SWEEP * s
	tw.a = tw.a0
	if tw.beam == null or not is_instance_valid(tw.beam):
		tw.beam = AbyssFX.beam(AbyssFX.ICHOR_HOT)
	Sfx.play("echarge", 0.05, -6.0)


func _end_beam(tw: Dictionary) -> void:
	if tw.beam != null and is_instance_valid(tw.beam):
		(tw.beam as Node).queue_free()
	tw.beam = null


func _beam_hits(tw: Dictionary, o: Vector3, d: Vector3, dt: float) -> void:
	tw.hit_t = float(tw.hit_t) - dt
	var p := Main.inst.player
	if p.alive and _seg(o, d, p.global_position) < BEAM_W * 0.5 + p.hit_radius:
		p.take_hit(o)
	if tw.hit_t > 0.0:
		return
	tw.hit_t = 0.2
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en.alive and en.landed and not en.is_boss and _seg(o, d, en.global_position) < BEAM_W * 0.5 + en.radius:
			en.take_hit(5, d, en.global_position, "laser")


static func _seg(o: Vector3, d: Vector3, p: Vector3) -> float:
	var rel := Vector3(p.x - o.x, 0, p.z - o.z)
	var along := clampf(rel.dot(d), 0.0, BEAM_LEN)
	return (rel - d * along).length()
