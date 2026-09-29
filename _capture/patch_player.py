import io, os
os.chdir(os.path.join(os.path.dirname(__file__), "..", "scripts"))
p = "player.gd"
s = io.open(p, encoding="utf-8").read()


def rep(a, b, count=1):
    global s
    assert a in s, a[:80]
    s = s.replace(a, b, count)


rep("const MAX_HP := 5\n", """const MAX_HP := 5
# 최대 충전 지속 레이저 (벨코즈 궁 스타일)
const MEGA_TIME := 2.0
const MEGA_TURN_MAX := 1.7      # 최대 회전 속도 (rad/s) → 조준이 묵직하게 따라감
const MEGA_TURN_GAIN := 3.5
const MEGA_TICK := 0.1
const MEGA_DMG := 2
const MEGA_WIDTH := 1.35
const MEGA_MOVE := 0.3
# 검 돌진
const LUNGE_RANGE := 5.2
const LUNGE_TIME := 0.12
const LUNGE_STOP := 1.45
""")
rep("var recoil := 0.0\n", """var recoil := 0.0
var mega_t := 0.0
var mega_yaw := 0.0
var mega_tick := 0.0
var mega_node: MegaBeam
var mega_len := 0.0
var lunge_t := 0.0
var lunge_vel := Vector3.ZERO
var lunge_dir := Vector3.ZERO
""")

# 입력 차단: 지속 레이저 중에는 다른 행동 불가
rep("""	if not playing:
		fire = false""", """	if mega_t > 0.0:
		fire = false
		slash_pressed = false
		dash_pressed = false
		charge_held = false
		boost_held = false
	if not playing:
		fire = false""")
rep("""	if to_aim.length() > 0.3:
		aim_dir = to_aim.normalized()""", """	if to_aim.length() > 0.3 and lunge_t <= 0.0:
		aim_dir = to_aim.normalized()""")

# 이동: 돌진 / 지속 레이저
rep("""	if dash_t > 0.0:
		dash_t -= dt
		var k := 1.0 - dash_t / DASH_TIME""", """	if lunge_t > 0.0:
		lunge_t -= dt
		velocity = lunge_vel
		ghost_t -= dt
		if ghost_t <= 0.0:
			ghost_t = 0.03
			FX.afterimage(visual)
		if lunge_t <= 0.0:
			velocity = lunge_dir * 2.5
			_slash_hit()
	elif dash_t > 0.0:
		dash_t -= dt
		var k := 1.0 - dash_t / DASH_TIME""")
rep("""		if charging:
			target_speed *= 0.55""", """		if charging:
			target_speed *= 0.55
		if mega_t > 0.0:
			target_speed *= MEGA_MOVE""")
rep("""	# ── 사격 ──
	fire_cd -= dt""", """	if mega_t > 0.0:
		_update_mega(dt)

	# ── 사격 ──
	fire_cd -= dt""")
rep("""		if charge >= CHARGE_MIN and dash_t <= 0.0:
			_fire_laser(charge)""", """		if charge >= 1.0 and dash_t <= 0.0:
			_start_mega()
		elif charge >= CHARGE_MIN and dash_t <= 0.0:
			_fire_laser(charge)""")
rep("""	if slash_pressed and slash_cd <= 0.0 and not charging:""", """	if slash_pressed and slash_cd <= 0.0 and not charging and lunge_t <= 0.0:""")

# 카메라 펀치
rep("""	Main.inst.kick(dash_dir * 0.8)
	if charging:""", """	Main.inst.kick(dash_dir * 0.8)
	Main.inst.camera.fov_punch(7.0)
	if charging:""")
rep("""	main.kick(-dir * lerpf(0.4, 1.1, k))
	if hit_any:
		main.hitstop(0.06)""", """	main.kick(-dir * lerpf(0.4, 1.1, k))
	main.camera.fov_punch(lerpf(2.0, 6.0, k))
	if hit_any:
		main.hitstop(0.06)""")
rep("""			en.take_hit(dmg, dir, en.global_position)
			hit_any = true""", """			en.take_hit(dmg, dir, en.global_position, "laser")
			hit_any = true""")

# 검: 돌진 → 베기
a = s[s.index("func _slash() -> void:"):s.index("func take_hit(from: Vector3) -> bool:")]
b = '''## 전방(또는 아주 가까운) 적 중 가장 가까운 대상
func _lunge_target() -> Enemy:
	var best: Enemy = null
	var bd := LUNGE_RANGE
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var d := en.global_position - global_position
		d.y = 0
		var l := d.length()
		if l < bd and (l < 2.0 or aim_dir.angle_to(d / maxf(l, 0.001)) < deg_to_rad(70)):
			bd = l
			best = en
	return best


func _slash() -> void:
	var target := _lunge_target()
	if target:
		var to := target.global_position - global_position
		to.y = 0
		aim_dir = to.normalized()
		var gap := to.length() - LUNGE_STOP
		if gap > 0.25:
			# 가까운 적에게 파고들며 베기
			lunge_dir = aim_dir
			lunge_t = LUNGE_TIME
			lunge_vel = lunge_dir * minf(gap / LUNGE_TIME, 30.0)
			invuln = maxf(invuln, LUNGE_TIME + 0.05)
			ghost_t = 0.0
			slash_anim = 0.0
			tilt_v += lunge_dir * 8.0
			FX.shockwave(global_position, Pal.BLADE, 1.8, 0.22, 0.05)
			Sfx.play("dash", 0.08, -5.0)
			Main.inst.camera.fov_punch(3.0)
			return
	_slash_hit()


func _slash_hit() -> void:
	slash_anim = 0.28
	var yaw := atan2(-aim_dir.x, -aim_dir.z)
	FX.slash(self, yaw)
	Sfx.play("slash", 0.08)
	velocity += aim_dir * 4.0
	tilt_v += aim_dir * 5.0
	var main := Main.inst
	var hit_any := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var d := en.global_position - global_position
		d.y = 0
		if d.length() < SLASH_RANGE + en.radius and aim_dir.angle_to(d.normalized()) < deg_to_rad(80):
			en.take_hit(3, d.normalized(), en.global_position, "slash")
			hit_any = true
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		var d := bl.position - global_position
		d.y = 0
		if d.length() < SLASH_RANGE + 0.3 and (d.length() < 0.8 or aim_dir.angle_to(d.normalized()) < deg_to_rad(80)):
			FX.flash(bl.position, Pal.BLADE, 0.45, 0.08)
			bl.queue_free()
	if hit_any:
		main.hitstop(0.05)
		main.shake(0.18)
		main.camera.fov_punch(-3.0)


# ── 최대 충전 지속 레이저 ────────────────────────────────

func _start_mega() -> void:
	mega_t = MEGA_TIME
	mega_yaw = atan2(-aim_dir.x, -aim_dir.z)
	mega_tick = 0.0
	mega_node = MegaBeam.new()
	FX.root.add_child(mega_node)
	var main := Main.inst
	main.shake(0.6)
	main.hitstop(0.05)
	main.camera.fov_punch(9.0)
	FX.shockwave(global_position, Pal.CYAN, 4.0, 0.4)
	FX.ring(Vector3(global_position.x, 0.3, global_position.z), 5.0, Pal.RING_CYAN, 0.45)
	Sfx.play("laser", 0.0, 2.0)
	squash_v -= 8.0
	_update_mega(0.0)


func _mega_dir() -> Vector3:
	return Vector3(-sin(mega_yaw), 0, -cos(mega_yaw))


func _update_mega(dt: float) -> void:
	var main := Main.inst
	# 조준을 묵직하게 따라감: 차이에 비례하되 최대 회전 속도 제한
	var target_yaw := atan2(-aim_dir.x, -aim_dir.z)
	var diff := angle_difference(mega_yaw, target_yaw)
	mega_yaw += clampf(diff * MEGA_TURN_GAIN, -MEGA_TURN_MAX, MEGA_TURN_MAX) * dt
	var dir := _mega_dir()
	var muzzle: Node3D = j.muzzle
	var origin := muzzle.global_position
	origin.y = 0.95
	var length := 0.0
	while length < LASER_RANGE:
		length += 0.25
		if main.is_blocked(origin + dir * length):
			break
	mega_len = length
	if mega_node:
		mega_node.set_beam(origin, dir, length)
	main.camera.set_beam(true, dir)
	# 반동: 뒤로 계속 밀리고 몸이 젖혀짐
	velocity -= dir * 9.0 * dt
	tilt_v -= dir * 2.5 * dt * 10.0
	mega_tick -= dt
	if mega_tick <= 0.0:
		mega_tick = MEGA_TICK
		var hit_any := false
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy
			if not en.alive or not en.landed:
				continue
			if _seg_dist(origin, dir, length, en.global_position) < en.radius + MEGA_WIDTH * 0.5:
				en.take_hit(MEGA_DMG, dir, en.global_position, "laser")
				hit_any = true
		for b in get_tree().get_nodes_in_group("enemy_bullets"):
			var bl := b as Bullet
			if _seg_dist(origin, dir, length, bl.position) < MEGA_WIDTH * 0.6 + 0.2:
				FX.flash(bl.position, Pal.CYAN, 0.4, 0.08)
				bl.queue_free()
		if hit_any:
			main.shake(0.1)
		main.kick(-dir * 0.12)
	mega_t -= dt
	if mega_t <= 0.0:
		_end_mega()


func _end_mega() -> void:
	mega_t = 0.0
	if mega_node:
		mega_node.finish()
		mega_node = null
	Main.inst.camera.set_beam(false)
	laser_cd = 0.9
	squash_v += 6.0
	FX.shockwave(global_position, Pal.CYAN, 2.5, 0.3)


'''
s = s.replace(a, b)

rep("""func die(push := Vector3.ZERO) -> void:
	alive = false""", """func die(push := Vector3.ZERO) -> void:
	alive = false
	if mega_t > 0.0:
		_end_mega()""")

# 애니메이션: 지속 레이저 중에는 상체가 빔 방향을 향함, 돌진 준비 자세
rep("""	var aim_yaw := atan2(-aim_dir.x, -aim_dir.z)
	var t := Time.get_ticks_msec() * 0.001

	# 스프링 기울기""", """	var aim_yaw := mega_yaw if mega_t > 0.0 else atan2(-aim_dir.x, -aim_dir.z)
	var t := Time.get_ticks_msec() * 0.001

	# 스프링 기울기""")
rep("""	if charging:
		lean_target += -aim_dir * 0.12 * charge
	tilt_v +=""", """	if charging:
		lean_target += -aim_dir * 0.12 * charge
	if mega_t > 0.0:
		lean_target += -_mega_dir() * 0.28
	tilt_v +=""")
rep("""	if charging:
		torso_pitch = 0.12 * charge   # 뒤로 버티는 자세""", """	if charging:
		torso_pitch = 0.12 * charge   # 뒤로 버티는 자세
	if mega_t > 0.0:
		torso_pitch = 0.2 + sin(t * 60.0) * 0.03
		arm_l.rotation.x = sin(t * 80.0) * 0.05""")
rep("""	if slash_anim > 0.0:
		slash_anim -= dt""", """	if lunge_t > 0.0:
		# 돌진 중: 검을 뒤로 당긴 준비 자세
		arm_r.rotation.y = lerpf(arm_r.rotation.y, -1.4, 0.5)
		arm_r.rotation.x = -0.5
		blade.rotation_degrees = Vector3(8, -70, 0)
		torso.rotation.y = lerpf(torso.rotation.y, -0.8, 0.5)
	elif slash_anim > 0.0:
		slash_anim -= dt""")

io.open(p, "w", encoding="utf-8", newline="\n").write(s)

# bullet → source
b = io.open("bullet.gd", encoding="utf-8").read()
print("ok")
