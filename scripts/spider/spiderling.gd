extends Enemy
## 새끼 거미 (BROODLING): SHIPWRIGHT 가 뒤 몸통 해치로 낳아 던지거나 벽 굴에서 몰려나오는 작은 기계 거미.
## 다리 여덟(2관절, 4+4 교대 걸음) · 푸른 등딱지 · 청록 겹눈. 진짜 거미처럼 "확 달리다 뚝 멈추기"를 되풀이하며 다가와,
## 가까우면 몸을 낮추고 붉게 번쩍(0.35초) → 도약 물기. 약하다(3발).
## 등장: thrown = 포물선으로 날아와 착지 · tunnel = 굴 속에서 기어 나온다 (홀 안에 들어와야 맞는다).

const Stage := preload("res://scripts/spider/spider_stage.gd")

enum S { CHASE, PAUSE, TELE, LEAP, RECOVER }

const BLUE := Color("3b70c2")
const BLUE_D := Color("284f8f")
const METAL := Color("2b2f37")
const EYE := Color(0.55, 1.0, 0.97)
const SPEED := 8.5
const LEAP_RANGE := 3.4
const TELE_T := 0.36
const LEAP_T := 0.32
const LEAP_DIST := 4.2
const L1 := 0.42
const L2 := 0.55
const BODY_Y := 0.34

var st := S.CHASE
var st_t := 0.0
var spawn_mode := "thrown"         # thrown · tunnel · none
var from_p := Vector3.ZERO
var to_p := Vector3.ZERO
var fly_t := 0.7
var leap_from := Vector3.ZERO
var leap_to := Vector3.ZERO
var bit := false
var burst_t := 0.0
var pause_t := 0.0
var heading := 0.0
var legs: Array = []
var eye_mat: StandardMaterial3D
var tele_on := false
var _snd := 0.0
var _move := Vector3.ZERO
var _flash_meshes: Array = []    # 덮개를 씌울 메시 (처음 한 번만 찾는다)
var _flash_cur: Material = null
var _flash_set := false


func _ready() -> void:
	add_to_group("enemies")
	hp = 3
	radius = 0.55
	slice_size = Vector3(0.6, 0.35, 0.8)
	slice_color = BLUE
	hp_bar_y = 1.0
	hp_bar_w = 0.6
	visual = Node3D.new()
	add_child(visual)
	j = _build(visual)
	shadow = FX.blob_shadow(self, 1.5, 0.6)
	t = randf() * 10.0
	evade.e = self
	evade.chance = 0.0
	orb_chance = 0.0
	heading = randf() * TAU
	burst_t = randf_range(0.3, 0.8)
	match spawn_mode:
		"thrown":
			landed = false
			global_position = from_p
		"tunnel":
			landed = false
			global_position = from_p
		_:
			landed = true
	_place_feet()


func _build(v: Node3D) -> Dictionary:
	var body := Build.pivot(v, Vector3(0, BODY_Y, 0), "Body")
	# 머리가슴 · 등딱지 · 배
	Build.bevel(body, Vector3(0.46, 0.22, 0.5), Vector3(0, 0.02, -0.08), METAL, 0.06)
	Build.bevel(body, Vector3(0.42, 0.12, 0.44), Vector3(0, 0.15, -0.08), BLUE, 0.05, Vector3.ZERO, 0.8)
	var abd := Build.ball(body, 0.32, Vector3(0, 0.12, 0.36), BLUE_D, Vector3(1.0, 0.85, 1.25))
	abd.name = "Abd"
	Build.box(body, Vector3(0.08, 0.05, 0.5), Vector3(0, 0.37, 0.36), Color(0.15, 0.95, 0.85), Vector3(-10, 0, 0), 2.0)
	# 겹눈 (청록 둘 + 작은 넷)
	eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = EYE
	eye_mat.emission_enabled = true
	eye_mat.emission = EYE
	eye_mat.emission_energy_multiplier = 3.0
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	var core: MeshInstance3D = null
	for e in [[-0.09, 0.07, -0.34, 1.0], [0.09, 0.07, -0.34, 1.0], [-0.17, 0.1, -0.28, 0.6], [0.17, 0.1, -0.28, 0.6], [-0.05, 0.14, -0.3, 0.5], [0.05, 0.14, -0.3, 0.5]]:
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = eye_mat
		body.add_child(mi)
		mi.position = Vector3(e[0], e[1], e[2])
		mi.scale = Vector3.ONE * float(e[3])
		if core == null:
			core = mi
	# 송곳니
	for s in [-1.0, 1.0]:
		Build.bevel(body, Vector3(0.05, 0.05, 0.16), Vector3(s * 0.07, -0.06, -0.38), Color(0.8, 0.82, 0.85), 0.015, Vector3(30, 0, 0))
	# 다리 여덟: 앞 두 쌍은 앞으로, 뒤 두 쌍은 뒤로 뻗는다
	var spec := [[-0.6, -0.55], [-0.2, -0.2], [0.15, 0.2], [0.5, 0.55]]   # 엉덩이 z, 발 방향 각
	for k in 4:
		for s in [-1.0, 1.0]:
			var hz: float = spec[k][0] * 0.35
			var ang: float = spec[k][1]
			var hip := Vector3(s * 0.2, 0.0, hz)
			var rest := Vector3(s * (0.75 - absf(ang) * 0.1), -BODY_Y, hz + sin(ang) * 0.75)
			var up_n := Build.pivot(v, Vector3.ZERO, "Up")
			Build.bevel(up_n, Vector3(0.07, 0.07, L1), Vector3(0, 0, -L1 * 0.5), BLUE, 0.02)
			var lo := Build.pivot(v, Vector3.ZERO, "Lo")
			Build.bevel(lo, Vector3(0.05, 0.05, L2), Vector3(0, 0, -L2 * 0.5), METAL, 0.015, Vector3.ZERO, 0.7)
			var grp := (k + (0 if s < 0 else 1)) % 2
			legs.append({"hip": hip, "rest": rest, "up": up_n, "lo": lo, "foot": Vector3.ZERO, "from": Vector3.ZERO, "to": Vector3.ZERO, "t": -1.0, "g": grp, "side": s})
	return {"body": body, "core": core, "core_mat": eye_mat}


func _body_xf() -> Transform3D:
	return (j.body as Node3D).global_transform


func _place_feet() -> void:
	if not is_inside_tree():
		return
	var bx := _body_xf()
	for l in legs:
		var p: Vector3 = bx * (l.rest as Vector3)
		l.foot = Vector3(p.x, 0.0, p.z)
		l.t = -1.0


# ── 매 프레임 ───────────────────────────────────────────

func _physics_process(dt: float) -> void:
	if dying:
		_update_death(dt)
		return
	if not alive:
		return
	if max_hp == 0:
		_init_hp()
	t += dt
	_snd -= dt
	_update_hp_bar(dt)
	var body := j.body as Node3D
	if not landed:
		_update_entry(dt)
		_legs(dt)
		return
	if stagger_t > 0.0:
		_set_tele(false)
		_update_stagger(dt)
	elif hurt_t > 0.0:
		_update_hurt(dt)
	else:
		st_t += dt
		_ai(dt)
	punch = move_toward(punch, 0.0, dt * 6.0)
	body.scale = Vector3(1.0 + punch * 0.2, 1.0 - punch * 0.15, 1.0 + punch * 0.2)
	if flash_t > 0.0:
		flash_t -= dt
		if flash_t <= 0.0:
			_set_flash(false)
	if glow_t > 0.0:
		glow_t -= dt
		if glow_t <= 0.0:
			_set_flash(flash_t > 0.0)
	_legs(dt)


func _update_entry(dt: float) -> void:
	drop_t += dt
	var body := j.body as Node3D
	match spawn_mode:
		"thrown":
			var k := clampf(drop_t / fly_t, 0.0, 1.0)
			var p := from_p.lerp(to_p, k)
			p.y = lerpf(from_p.y, 0.0, k) + sin(k * PI) * 4.0
			global_position = Vector3(p.x, 0, p.z)
			body.position.y = BODY_Y + p.y
			body.rotation.x = k * TAU * 1.0
			shadow.scale = Vector3.ONE * lerpf(0.3, 1.0, k)
			if k >= 1.0:
				body.rotation = Vector3.ZERO
				body.position.y = BODY_Y
				landed = true
				punch = 1.0
				FX.land_dust(global_position)
				_place_feet()
				_freeze(0.25)
		"tunnel":
			# 굴 속에서 바닥 홀로 기어 나온다 (홀 안에 들어오면 맞는다)
			var d := to_p - global_position
			d.y = 0
			var step := minf(d.length(), SPEED * 0.9 * dt)
			if d.length() > 0.05:
				global_position += d.normalized() * step
				heading = atan2(-d.x, -d.z)
				rotation.y = heading
			body.position.y = BODY_Y + absf(sin(t * 22.0)) * 0.03
			if absf(global_position.x) < Stage.HX - 0.4 and absf(global_position.z) < Stage.HZ - 0.4 or d.length() < 0.1:
				landed = true
				_freeze(0.15)
		_:
			landed = true


## 뚝 멈춤 (진짜 거미의 정지)
func _freeze(sec: float) -> void:
	st = S.PAUSE
	st_t = 0.0
	pause_t = sec


func _set_tele(on: bool) -> void:
	if tele_on == on:
		return
	tele_on = on
	_set_flash(flash_t > 0.0)


func _set_flash(on: bool) -> void:
	var rest: Material = Pal.lock_hatch() if locked else (Pal.flash() if tele_on and fmod(t * 14.0, 1.0) < 0.5 else null)
	var m: Material = Pal.flash() if on else rest
	# 예고 중에는 매 프레임 불리므로 덮개가 바뀔 때만 메시를 건드린다
	if _flash_set and m == _flash_cur:
		return
	_flash_set = true
	_flash_cur = m
	if _flash_meshes.is_empty():
		_flash_meshes = visual.find_children("*", "MeshInstance3D", true, false)
	for mi in _flash_meshes:
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = m


func _ai(dt: float) -> void:
	var main := Main.inst
	var p := main.player
	var to := p.global_position - global_position
	to.y = 0
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	var body := j.body as Node3D
	var act := p.alive and main.state == Main.State.PLAY
	match st:
		S.PAUSE:
			# 멈춰서 더듬듯 앞다리를 든다
			body.position.y = BODY_Y
			body.rotation.x = lerpf(body.rotation.x, -0.15, 1.0 - exp(-10.0 * dt))
			_move = Vector3.ZERO
			if st_t > pause_t:
				st = S.CHASE
				st_t = 0.0
				burst_t = randf_range(0.5, 1.1)
		S.CHASE:
			var side := Vector3(-dir.z, 0, dir.x) * sin(t * 2.6 + float(get_instance_id() % 7)) * 0.6
			var want := (dir + side + _separation() * 0.9).limit_length(1.0) if act else Vector3(-dir.z, 0, dir.x) * 0.3
			_move = _move.lerp(want, 1.0 - exp(-12.0 * dt))
			global_position += (_move * SPEED + knock) * dt
			if _move.length() > 0.1:
				heading = lerp_angle(heading, atan2(-_move.x, -_move.z), 1.0 - exp(-14.0 * dt))
			rotation.y = heading
			body.rotation.x = lerpf(body.rotation.x, 0.08, 1.0 - exp(-10.0 * dt))
			body.position.y = BODY_Y + absf(sin(t * 26.0)) * 0.025
			if st_t > burst_t and dist > LEAP_RANGE + 1.0:
				_freeze(randf_range(0.18, 0.45))
			elif act and dist < LEAP_RANGE:
				st = S.TELE
				st_t = 0.0
				_set_tele(true)
				Sfx.play("pcue", 0.25, -16.0)
		S.TELE:
			var k := clampf(st_t / TELE_T, 0.0, 1.0)
			heading = lerp_angle(heading, atan2(-dir.x, -dir.z), 1.0 - exp(-16.0 * dt))
			rotation.y = heading
			body.position.y = lerpf(BODY_Y, BODY_Y * 0.55, k)
			body.rotation.x = -0.3 * k
			eye_mat.emission_energy_multiplier = 3.0 + 7.0 * k
			_set_flash(false)
			if st_t >= TELE_T:
				leap_from = global_position
				var tgt := p.global_position + p.velocity * 0.12
				var d := tgt - global_position
				d.y = 0
				leap_to = main.push_out(global_position + d.limit_length(LEAP_DIST), radius)
				bit = false
				st = S.LEAP
				st_t = 0.0
				Sfx.play("dash", 0.25, -12.0)
		S.LEAP:
			var k := clampf(st_t / LEAP_T, 0.0, 1.0)
			global_position = leap_from.lerp(leap_to, 1.0 - pow(1.0 - k, 1.6))
			body.position.y = BODY_Y + sin(k * PI) * 0.8
			body.rotation.x = lerpf(0.45, -0.2, k)
			if not bit and p.alive and Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length() < 0.8:
				bit = true
				p.take_hit(global_position)
			if k >= 1.0:
				_set_tele(false)
				eye_mat.emission_energy_multiplier = 3.0
				FX.land_dust(global_position)
				st = S.RECOVER
				st_t = 0.0
		S.RECOVER:
			body.rotation.x = lerpf(body.rotation.x, 0.0, 1.0 - exp(-8.0 * dt))
			body.position.y = BODY_Y
			global_position += knock * dt
			if st_t > 0.55:
				_freeze(randf_range(0.1, 0.3))
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	global_position = main.push_out(global_position, radius)


func _separation() -> Vector3:
	var out := Vector3.ZERO
	for o in get_tree().get_nodes_in_group("enemies"):
		if o == self or (o as Enemy).is_boss:
			continue
		var d: Vector3 = global_position - (o as Node3D).global_position
		d.y = 0
		var l := d.length()
		if l < 1.3 and l > 0.001:
			out += d / l * (1.3 - l)
	return out


## 여덟 다리 걸음: 몸이 움직여 발이 쉬는 자리에서 벗어나면 같은 조 넷이 함께 딛는다 (4+4 교대)
func _legs(dt: float) -> void:
	if not is_inside_tree():
		return
	var bx := _body_xf()
	var vel := (_move * SPEED) if landed else Vector3.ZERO
	var spd := vel.length()
	var stepping := [0, 0]
	for l in legs:
		if float(l.t) >= 0.0:
			stepping[int(l.g)] += 1
	var dur := clampf(0.16 - spd * 0.006, 0.07, 0.16)
	var airborne := not landed or st == S.LEAP
	for l in legs:
		var hip: Vector3 = bx * (l.hip as Vector3)
		var rest: Vector3 = bx * (l.rest as Vector3)
		rest.y = 0.0
		if airborne:
			# 공중: 다리를 몸 둘레로 웅크린다
			var tuck := bx * ((l.rest as Vector3) * Vector3(0.55, 0.3, 0.6))
			l.foot = (l.foot as Vector3).lerp(tuck, 1.0 - exp(-20.0 * dt))
			l.t = -1.0
		elif float(l.t) < 0.0:
			var err := Vector2((l.foot as Vector3).x - rest.x, (l.foot as Vector3).z - rest.z).length()
			if err > 0.32 and stepping[1 - int(l.g)] == 0:
				l.from = l.foot
				var to := rest + vel * dur * 0.7
				to.y = 0.0
				l.to = to
				l.t = 0.0
				stepping[int(l.g)] += 1
		if float(l.t) >= 0.0 and not airborne:
			l.t = float(l.t) + dt / dur
			var k := clampf(float(l.t), 0.0, 1.0)
			var f := (l.from as Vector3).lerp(l.to, k)
			f.y = sin(k * PI) * 0.22
			l.foot = f
			if float(l.t) >= 1.0:
				l.t = -1.0
				var ff: Vector3 = l.foot
				ff.y = 0.0
				l.foot = ff
		_pose(l, hip, l.foot, bx.basis)


func _pose(l: Dictionary, hip: Vector3, foot: Vector3, b: Basis) -> void:
	var d := foot - hip
	var dl := clampf(d.length(), 0.05, L1 + L2 - 0.01)
	var axis := d.normalized() if d.length() > 0.01 else -b.y
	var pole := (b.y + (foot - hip - b.y * (foot - hip).dot(b.y)).normalized() * 0.2).normalized()
	var perp := pole - axis * pole.dot(axis)
	perp = perp.normalized() if perp.length() > 0.01 else b.y
	var a := (dl * dl + L1 * L1 - L2 * L2) / (2.0 * dl)
	var h := sqrt(maxf(0.0, L1 * L1 - a * a))
	var knee := hip + axis * a + perp * h
	var end := hip + axis * dl
	(l.up as Node3D).global_transform = Transform3D(_look(knee - hip, perp), hip)
	(l.lo as Node3D).global_transform = Transform3D(_look(end - knee, perp), knee)


static func _look(v: Vector3, up_hint: Vector3) -> Basis:
	var nv := v.normalized()
	var u := up_hint - nv * up_hint.dot(nv)
	if u.length() < 0.01:
		u = Vector3.UP if absf(nv.y) < 0.95 else Vector3.FORWARD
	return Basis.looking_at(nv, u.normalized())


# ── 피격 · 처치 ─────────────────────────────────────────

func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	if not alive:
		return
	super.take_hit(dmg, dir, pos, source)
	if is_inside_tree() and alive:
		FX.sparks((j.body as Node3D).global_position, 4, [Color.WHITE, EYE, Color(0.5, 0.6, 0.7)], 5.0, 0.3, -14.0, 0.05)


func _on_stagger() -> void:
	_set_tele(false)


func _on_hurt() -> void:
	_set_tele(false)
	if st == S.TELE or st == S.LEAP:
		st = S.RECOVER
		st_t = 0.0


func _can_hurt() -> bool:
	return st != S.LEAP


func die(dir := Vector3.ZERO, source := "bullet") -> void:
	if not alive:
		return
	tele_on = false
	if source == "slash" or source == "phantom":
		super.die(dir, source)
		return
	alive = false
	remove_from_group("enemies")
	kill_source = source
	locked = false
	if is_instance_valid(hp_bar):
		hp_bar.queue_free()
	if is_instance_valid(stun_halo):
		stun_halo.queue_free()
	_set_flash(false)
	Main.inst.on_enemy_killed(self)
	var body := j.body as Node3D
	var c := body.global_position
	FX.flash(c, Color(0.8, 1.0, 1.0), 0.9, 0.07)
	FX.sparks(c, 14, [Color.WHITE, EYE, Color(1.0, 0.7, 0.3), Color(0.3, 0.32, 0.36)], 7.0, 0.45, -14.0, 0.07)
	FX.puffs(c, 4, [Color(0.25, 0.27, 0.3), Color(0.18, 0.19, 0.21), Color(0.1, 0.1, 0.12), Color(0.06, 0.06, 0.07)], 0.6, 0.5, 0.6)
	Debris.burst(body, c - Vector3(0, 0.15, 0), 5.0, 4.0, dir * 2.0)
	Sfx.play("boom", 0.2, -9.0)
	queue_free()
