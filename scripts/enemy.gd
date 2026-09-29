class_name Enemy
extends Node3D
## 흰색 몸체·붉은 코어 적. 낙하 등장 → 거리 유지하며 선회 → 코어가 부풀면 발사.

enum Pattern { AIMED_BURST, FAN, RING }
## 죽음 연출: 즉시 폭발 / 과부하 팽창 후 폭발 / 튕겨 날아가 추락 폭발 / 전원 차단 후 쓰러져 붕괴
enum Death { BURST, OVERLOAD, SPINOUT, SHUTDOWN, SLICED }

var hp := 4
var alive := true
var landed := false
var radius := 0.62
var pattern := Pattern.AIMED_BURST
var j: Dictionary
var t := 0.0
var drop_t := 0.0
var fire_timer := 2.0
var burst_left := 0
var burst_timer := 0.0
var strafe := 1.0
var strafe_timer := 2.0
var desired := 7.0
var knock := Vector3.ZERO
var flash_t := 0.0
var punch := 0.0
var shadow: MeshInstance3D
var wob := Vector2.ZERO
var wob_v := Vector2.ZERO
var dying := false
var death := Death.BURST
var death_t := 0.0
var death_dir := Vector3.ZERO
var d_vel := Vector3.ZERO
var d_spin := Vector3.ZERO
var fx_t := 0.0
var forced_death := -1
var slash_yaw := 0.0
var halves: Array = []        # [node, vel, spin, glow_mesh]
var cut_frame: Basis
var visual: Node3D
var locked := false
var kill_source := ""
## 광선검 절단 조각의 크기(폭, 높이, 깊이)와 색. 몸체가 다른 기체는 덮어쓴다.
var slice_size := Vector3(0.78, 0.74, 0.78)
var slice_color := Pal.E_WHITE

const DROP_TIME := 0.45
const TELEGRAPH := 0.5


func _ready() -> void:
	add_to_group("enemies")
	visual = Node3D.new()
	add_child(visual)
	j = _build(visual)
	shadow = FX.blob_shadow(self, 2.1, 0.7)
	t = randf() * 10.0
	strafe = 1.0 if randf() < 0.5 else -1.0
	fire_timer = randf_range(1.2, 2.0)
	match pattern:
		Pattern.AIMED_BURST: desired = 6.0
		Pattern.FAN: desired = 5.0
		Pattern.RING: desired = 4.2
	j.body.position.y = 7.0


func _physics_process(dt: float) -> void:
	if dying:
		_update_death(dt)
		return
	if not alive:
		return
	t += dt
	var body: Node3D = j.body
	if not landed:
		_update_entry(dt)
		return
	_ai(dt)
	# 피격 반응
	punch = move_toward(punch, 0.0, dt * 6.0)
	body.scale = Vector3(1.0 + punch * 0.22, 1.0 - punch * 0.16, 1.0 + punch * 0.22)
	if flash_t > 0.0:
		flash_t -= dt
		if flash_t <= 0.0:
			_set_flash(false)


## 등장 연출: 기본은 하늘에서 떨어져 착지한다. 끝나면 landed 를 켠다 (그 전에는 맞지 않는다).
func _update_entry(dt: float) -> void:
	var body: Node3D = j.body
	drop_t += dt
	var k: float = clamp(drop_t / DROP_TIME, 0.0, 1.0)
	body.position.y = lerp(7.0, 1.0, k * k)
	shadow.scale = Vector3.ONE * lerp(0.4, 1.0, k)
	if k >= 1.0:
		landed = true
		punch = 1.0
		FX.land_dust(global_position)
		Main.inst.shake(0.12)


## 몸체 메시 조립. 하위 기체는 body / core / core_mat / cube 를 가진 딕셔너리를 돌려준다.
func _build(v: Node3D) -> Dictionary:
	return Build.drone(v)


## 착지 후 매 프레임 이동·조준·공격
func _ai(dt: float) -> void:
	var body: Node3D = j.body
	var player := Main.inst.player
	var to_p := player.global_position - global_position
	to_p.y = 0
	var dist := to_p.length()
	var dir := to_p / maxf(dist, 0.001)

	# 이동: 거리 유지 + 선회 + 서로 밀어내기
	strafe_timer -= dt
	if strafe_timer <= 0.0:
		strafe_timer = randf_range(1.5, 3.0)
		strafe = -strafe
	var move := Vector3.ZERO
	if dist > desired + 0.8:
		move += dir
	elif dist < desired - 0.8:
		move -= dir
	move += Vector3(-dir.z, 0, dir.x) * strafe * 0.6
	for o in get_tree().get_nodes_in_group("enemies"):
		if o == self:
			continue
		var d: Vector3 = global_position - (o as Node3D).global_position
		d.y = 0
		var l := d.length()
		if l < 2.2 and l > 0.001:
			move += d / l * (2.2 - l)
	var speed := 2.0 if burst_left == 0 and fire_timer > TELEGRAPH else 0.6
	global_position += (move.limit_length(1.0) * speed + knock) * dt
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	global_position = Main.inst.push_out(global_position, radius)

	# 방향: 플레이어를 바라본다
	if player.alive:
		var target_yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-6.0 * dt))

	# 공중 부유
	body.position.y = 1.0 + sin(t * 2.4) * 0.1
	wob_v += (-wob * 220.0 - wob_v * 11.0) * dt
	wob += wob_v * dt

	# 발사 예고: 코어 팽창·밝아짐
	var core: MeshInstance3D = j.core
	var cm: StandardMaterial3D = j.core_mat
	if player.alive and Main.inst.state == Main.State.PLAY:
		fire_timer -= dt
	var tele: float = clamp(1.0 - fire_timer / TELEGRAPH, 0.0, 1.0)
	core.scale = Vector3.ONE * (1.0 + tele * 0.6 + sin(t * 40.0) * 0.06 * tele)
	# 예고 중에는 뒤로 젖혀 힘을 모은다
	body.rotation.x = wob.x + tele * 0.22
	body.rotation.z = sin(t * 1.7) * 0.06 + wob.y + sin(t * 45.0) * 0.03 * tele
	cm.emission_energy_multiplier = 0.6 + tele * 3.0
	if fire_timer <= 0.0:
		_begin_attack()
	if burst_left > 0:
		burst_timer -= dt
		if burst_timer <= 0.0:
			burst_timer = 0.13
			burst_left -= 1
			_shoot([0.0], 7.5)


func _begin_attack() -> void:
	fire_timer = randf_range(1.9, 2.8)
	match pattern:
		Pattern.AIMED_BURST:
			burst_left = 3
			burst_timer = 0.0
		Pattern.FAN:
			_shoot([-0.5, -0.25, 0.0, 0.25, 0.5], 6.0)
		Pattern.RING:
			var a: Array[float] = []
			var off := randf() * 0.3
			for i in 12:
				a.append(TAU * i / 12.0 + off)
			_shoot(a, 5.0, true)


func _shoot(angles: Array, speed: float, big := false) -> void:
	var core: MeshInstance3D = j.core
	var origin := core.global_position
	origin.y = 0.95
	var fwd := -global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	for a in angles:
		var d := fwd.rotated(Vector3.UP, a)
		Main.inst.add_bullet(Bullet.make_enemy(origin + d * 0.2, d, speed, big))
	FX.flash(origin, Color("ff8a40"), 0.55, 0.07)
	wob_v.x -= 7.0
	Sfx.play("eshot", 0.08, -4.0)
	punch = 0.5


func take_hit(dmg: int, dir: Vector3, _pos: Vector3, source := "bullet") -> void:
	if not alive:
		return
	hp -= dmg
	knock += Vector3(dir.x, 0, dir.z) * (3.0 + dmg)
	var l := global_basis.inverse() * Vector3(dir.x, 0, dir.z)
	wob_v += Vector2(l.z, -l.x) * (8.0 + dmg * 2.0)
	punch = 1.0
	flash_t = 0.06
	_set_flash(true)
	Sfx.play("hit", 0.15, -6.0)
	if hp <= 0:
		die(dir, source)


func die(dir := Vector3.ZERO, source := "bullet") -> void:
	if not alive:
		return
	alive = false
	dying = true
	death_t = 0.0
	remove_from_group("enemies")
	death_dir = Vector3(dir.x, 0, dir.z)
	if death_dir.length() < 0.01:
		death_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	death_dir = death_dir.normalized()
	kill_source = source
	locked = false
	death = _pick_death(source) if (forced_death < 0 or source == "slash" or source == "phantom") else forced_death
	_set_flash(false)
	Main.inst.on_enemy_killed(self)
	var body: Node3D = j.body
	match death:
		Death.BURST:
			_explode(1.0, 7.0, 6.0, death_dir * 3.0)
		Death.OVERLOAD:
			Sfx.play("overload", 0.05, -2.0)
			FX.flash(body.global_position, Color.WHITE, 1.2, 0.08)
		Death.SPINOUT:
			d_vel = death_dir * 7.5 + Vector3(0, 8.0, 0)
			d_spin = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(14.0, 22.0)
			FX.flash(body.global_position, Color.WHITE, 1.0, 0.08)
			FX.sparks(body.global_position, 12, [Color.WHITE, Color("ff9a40")], 7.0, 0.35, -10.0, 0.08)
			Sfx.play("roll", 0.1, -2.0)
		Death.SLICED:
			_begin_slice()
		Death.SHUTDOWN:
			var cm: StandardMaterial3D = j.core_mat
			cm.emission_energy_multiplier = 0.0
			cm.albedo_color = Color(0.22, 0.18, 0.24)
			d_vel = death_dir * 2.0
			FX.sparks(body.global_position, 10, [Color("fff0a0"), Color("ffffff")], 5.0, 0.3, -12.0, 0.06)
			Sfx.play("powerdown", 0.05, -2.0)


func _pick_death(source: String) -> int:
	var r := randf()
	match source:
		"laser":
			return Death.OVERLOAD if r < 0.55 else (Death.BURST if r < 0.8 else Death.SHUTDOWN)
		"slash", "phantom":
			return Death.SLICED
	return [Death.BURST, Death.OVERLOAD, Death.SPINOUT, Death.SHUTDOWN][randi() % 4]


func _update_death(dt: float) -> void:
	death_t += dt
	var body: Node3D = j.body
	var core: MeshInstance3D = j.core
	var cm: StandardMaterial3D = j.core_mat
	fx_t -= dt
	match death:
		Death.SLICED:
			_update_slice(dt)
		Death.OVERLOAD:
			# 부들부들 떨며 부풀고 코어가 폭주하듯 깜빡인 뒤 크게 터진다
			var k := clampf(death_t / 0.5, 0.0, 1.0)
			var jit := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.09 * k
			body.position = Vector3(0, 1.0 + k * 0.35, 0) + jit
			body.rotation = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.08 * k
			body.scale = Vector3.ONE * (1.0 + 0.45 * k * k)
			core.scale = Vector3.ONE * (1.0 + 1.2 * k)
			cm.emission_energy_multiplier = 2.0 + 12.0 * k
			_set_flash(k > 0.25 and fmod(death_t, 0.09) < 0.045)
			if fx_t <= 0.0:
				fx_t = 0.05
				FX.sparks(core.global_position, 3, [Color.WHITE, Pal.E_RED], 6.0, 0.25, -6.0, 0.06)
			if k >= 1.0:
				_set_flash(false)
				Main.inst.shake(0.45)
				Main.inst.hitstop(0.04)
				_explode(1.7, 11.0, 8.0, Vector3.ZERO)
		Death.SPINOUT:
			# 맞은 방향으로 튕겨 날아가 빙글빙글 돌며 연기를 뿜다 바닥에 처박힌다
			d_vel.y -= 24.0 * dt
			global_position += Vector3(d_vel.x, 0, d_vel.z) * dt
			global_position = Main.inst.push_out(global_position, 0.4)
			body.position.y += d_vel.y * dt
			if d_spin.length() > 0.01:
				body.rotate(d_spin.normalized(), d_spin.length() * dt)
			shadow.scale = Vector3.ONE * clampf(1.4 - body.position.y * 0.25, 0.3, 1.0)
			if fx_t <= 0.0:
				fx_t = 0.035
				FX.smoke(body.global_position)
			if (body.position.y <= 0.45 and d_vel.y < 0.0) or death_t > 1.6:
				Main.inst.shake(0.35)
				FX.shockwave(global_position, Color("ff8a50"), 2.6, 0.3)
				_explode(1.15, 8.0, 5.0, Vector3(d_vel.x, 0, d_vel.z) * 0.5)
		Death.SHUTDOWN:
			# 전원이 꺼져 툭 떨어지고, 한 번 튕긴 뒤 옆으로 쓰러져 지직거리다 무너진다
			d_vel.y -= 26.0 * dt
			body.position.y += d_vel.y * dt
			global_position += Vector3(d_vel.x, 0, d_vel.z) * dt
			d_vel.x *= 0.92
			d_vel.z *= 0.92
			if body.position.y < 0.37:
				body.position.y = 0.37
				if d_vel.y < -2.0:
					d_vel.y = -d_vel.y * 0.3
					FX.land_dust(global_position)
					Sfx.play("land", 0.1, -4.0)
				else:
					d_vel.y = 0.0
			body.rotation.z = lerpf(body.rotation.z, 0.42 * signf(death_dir.x + 0.01), 1.0 - exp(-6.0 * dt))
			body.rotation.x = lerpf(body.rotation.x, 0.25, 1.0 - exp(-6.0 * dt))
			shadow.scale = Vector3.ONE * 0.9
			if fx_t <= 0.0:
				fx_t = randf_range(0.08, 0.2)
				FX.sparks(core.global_position, 4, [Color("fff0a0"), Color.WHITE], 4.0, 0.2, -12.0, 0.05)
				cm.emission_energy_multiplier = 2.0 if randf() < 0.3 else 0.0
			if death_t > 1.05:
				FX.puffs(body.global_position, 5, [Color("6a6680"), Color("8a88a0"), Color("403c50"), Color("2c2a3a")], 0.6, 0.6, 0.6)
				FX.shockwave(global_position, Color("8a88a0"), 1.8, 0.25, 0.05)
				Sfx.play("boom", 0.2, -8.0)
				Debris.burst(body, body.global_position + Vector3(0, 0.25, 0), 2.2, 3.0)
				dying = false
				queue_free()


## 광선검 절단: 몸체를 비스듬한 절단면으로 두 조각 낸다
func _begin_slice() -> void:
	var body: Node3D = j.body
	var center := body.global_position
	# 절단면: 휘두른 방향(수평 호)을 따라 약간 기울어진 평면
	var tilt := randf_range(-0.35, 0.35)
	cut_frame = Basis(Vector3.UP, slash_yaw) * Basis(Vector3.FORWARD, tilt)
	var cube_w := slice_size.x
	var cube_d := slice_size.z
	var half_h := slice_size.y * 0.5
	var hot := Color(1.0, 0.97, 0.85)
	for side in [1, -1]:
		var piece := Node3D.new()
		FX.root.add_child(piece)
		piece.global_transform = Transform3D(cut_frame, center)
		var bm := BoxMesh.new()
		bm.size = Vector3(cube_w, half_h, cube_d)
		var box := MeshInstance3D.new()
		box.mesh = bm
		box.material_override = Pal.lit(slice_color)
		box.position = Vector3(0, half_h * 0.5 * side, 0)
		piece.add_child(box)
		# 달아오른 절단면
		var gm := BoxMesh.new()
		gm.size = Vector3(cube_w * 0.96, 0.025, cube_d * 0.96)
		var glow := Pal.flat_mesh(gm, hot, 2.4)
		glow.position = Vector3(0, 0.012 * side, 0)
		piece.add_child(glow)
		if side < 0:
			# 코어는 아래쪽 조각에 붙어 있다
			var core := MeshInstance3D.new()
			core.mesh = (j.core as MeshInstance3D).mesh
			core.material_override = Pal.lit(Color("7a1a30"))
			piece.add_child(core)
			core.global_transform = (j.core as MeshInstance3D).global_transform
		var tangent := cut_frame.x * (1.0 if randf() < 0.5 else -1.0)
		var v := Vector3.ZERO
		var spin := Vector3.ZERO
		if side > 0:
			# 윗조각: 절단면을 따라 미끄러져 떨어진다
			v = tangent * 2.2 + death_dir * 1.6 + Vector3(0, 2.0, 0)
			spin = cut_frame.z * randf_range(2.5, 4.0) * signf(tangent.dot(cut_frame.x))
		else:
			v = -tangent * 0.4 + death_dir * 0.4
			spin = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.8
		halves.append([piece, v, spin, glow, side])
	body.visible = false
	# 절단 순간: 가로로 긋는 섬광 + 불꽃
	var slash_line := BoxMesh.new()
	slash_line.size = Vector3(2.6, 0.04, 0.1)
	var sl := Pal.flat_mesh(slash_line, Color(0.9, 1.0, 0.7), 3.0)
	FX.root.add_child(sl)
	sl.global_transform = Transform3D(cut_frame * Basis(Vector3.UP, PI * 0.5), center)
	var tw := sl.create_tween()
	tw.tween_property(sl, "scale", Vector3(1.4, 0.2, 0.2), 0.12).set_ease(Tween.EASE_OUT)
	tw.tween_callback(sl.queue_free)
	FX.flash(center, Color(0.85, 1.0, 0.6), 1.3, 0.08)
	FX.sparks(center, 22, [Color.WHITE, Color("ffd060"), Color("ff7a30")], 9.0, 0.45, -14.0, 0.07)
	FX.sparks(center, 10, [Pal.BLADE, Color.WHITE], 6.0, 0.3, -6.0, 0.06)
	Sfx.play("slash", 0.0, 2.0)
	Sfx.play("hit", 0.1, 0.0)


func _update_slice(dt: float) -> void:
	var cool := clampf(death_t / 1.0, 0.0, 1.0)
	var glow_c := Color(1.0, 0.97, 0.85).lerp(Color(1.0, 0.45, 0.1), smoothstep(0.0, 0.35, cool)).lerp(Color(0.35, 0.05, 0.05), smoothstep(0.35, 1.0, cool))
	for h in halves:
		var piece := h[0] as Node3D
		var v: Vector3 = h[1]
		var spin: Vector3 = h[2]
		var glow := h[3] as MeshInstance3D
		var side: int = h[4]
		# 처음 0.08초는 잘린 채 그대로 멈춰 있다가 떨어진다 (베인 느낌)
		if death_t > 0.08:
			v.y -= 20.0 * dt
			var pos := piece.global_position + v * dt
			var floor_y := 0.19 if side > 0 else 0.2
			if pos.y < floor_y:
				pos.y = floor_y
				if v.y < -2.0:
					v.y = -v.y * 0.25
					FX.land_dust(pos)
				else:
					v.y = 0.0
				v.x *= 0.8
				v.z *= 0.8
				spin *= 0.85
			piece.global_position = pos
			if spin.length() > 0.01:
				piece.rotate(spin.normalized(), spin.length() * dt)
			h[1] = v
			h[2] = spin
		glow.set_instance_shader_parameter("tint", glow_c)
		glow.set_instance_shader_parameter("energy", lerpf(2.6, 1.0, cool))
	# 절단면에서 불똥이 떨어지고 연기가 난다
	if fx_t <= 0.0:
		fx_t = 0.05
		var h0: Array = halves[randi() % halves.size()]
		var pp := (h0[0] as Node3D).global_position
		FX.sparks(pp, 3, [Color("ffd060"), Color("ff6a20")], 2.5, 0.4, -9.0, 0.05)
		if randf() < 0.4:
			FX.smoke(pp + Vector3(0, 0.2, 0))
	if death_t > 1.25:
		for h in halves:
			var piece := h[0] as Node3D
			Debris.burst(piece, piece.global_position + Vector3(0, -0.3, 0), 1.4, 2.0)
			FX.puffs(piece.global_position, 2, [Color("6a6680"), Color("8a88a0"), Color("403c50"), Color("2c2a3a")], 0.3, 0.4, 0.4)
			piece.queue_free()
		halves.clear()
		dying = false
		queue_free()


func _explode(scale_k: float, power: float, lift: float, push: Vector3) -> void:
	var body: Node3D = j.body
	var p := body.global_position
	FX.enemy_explosion(p, scale_k)
	Debris.burst(body, p - Vector3(0, 0.35, 0), power, lift, push)
	Sfx.play("boom", 0.1)
	dying = false
	queue_free()


func _set_flash(on: bool) -> void:
	var rest: Material = Pal.lock_hatch() if locked else null
	for mi in (j.body as Node3D).find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = Pal.flash() if on else rest


## 궁극기 락온: 몸체 전체에 붉은 빗금을 덮는다
func set_locked(on: bool) -> void:
	if locked == on or not is_instance_valid(j.body):
		return
	locked = on
	_set_flash(flash_t > 0.0)
	if on:
		punch = 0.6
		FX.flash((j.body as Node3D).global_position, Color(1, 0.2, 0.25), 1.1, 0.1)
