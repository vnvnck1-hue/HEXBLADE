import io, os
os.chdir(os.path.join(os.path.dirname(__file__), "..", "scripts"))
p = "player.gd"
s = io.open(p, encoding="utf-8").read()


def rep(a, b, n=1):
    global s
    assert a in s, a[:90]
    s = s.replace(a, b, n)


# ── 상수 ──
rep("const MEGA_TURN_MAX := 1.7      # 최대 회전 속도 (rad/s) → 조준이 묵직하게 따라감\nconst MEGA_TURN_GAIN := 3.5",
    "const MEGA_TURN_MAX := 16.0     # 최대 회전 속도 (rad/s) → 거의 즉시 따라옴\nconst MEGA_TURN_GAIN := 24.0")
rep("const LUNGE_TIME := 0.12", "const LUNGE_TIME := 0.07")
rep("const LUNGE_STOP := 1.45\n", """const LUNGE_STOP := 1.45
const SLASH_TIME := 0.16         # 휘두르기 전체 (앞 0.05초에 스윙 완료)
const SLASH_SWING := 0.05
# 궁극기: 미사일 난사
const ULT_TIME := 14.0           # 자연 충전 시간
const ULT_PER_KILL := 0.1
const ULT_MISSILES := 18
const CHARGE_STAGES := [0.34, 0.67, 1.0]
""")
rep("var lunge_dir := Vector3.ZERO\n", """var lunge_dir := Vector3.ZERO
var ult := 0.6
var ult_queue := 0
var ult_t := 0.0
var charge_stage := 0
""")

# ── 입력: 궁극기 ──
rep("""		boost_held = b.get("boost", false)
	else:""", """		boost_held = b.get("boost", false)
		if b.get("ult", false) and ult >= 1.0 and playing:
			_fire_ult()
	else:""")
rep("""		boost_held = Input.is_action_pressed("boost")
	if mega_t > 0.0:""", """		boost_held = Input.is_action_pressed("boost")
		if Input.is_action_just_pressed("ult") and ult >= 1.0 and playing:
			_fire_ult()
	if mega_t > 0.0:""")

# ── 충전: 대시 중에도 유지 ──
rep("""	if charge_held and laser_cd <= 0.0 and dash_t <= 0.0:
		if not charging:
			charging = true
			charge = 0.0
			charge_fx.begin()
			charge_snd = Sfx.play("charge", 0.0, -6.0)
		var before := charge
		charge = minf(1.0, charge + dt / CHARGE_TIME)
		if before < 1.0 and charge >= 1.0:
			charge_fx.flash_full()
			Sfx.play("charged", 0.0, -2.0)
			Main.inst.shake(0.12)
		charge_fx.set_charge(charge, dt)""", """	if charge_held and laser_cd <= 0.0:
		if not charging:
			charging = true
			charge = 0.0
			charge_stage = 0
			charge_fx.begin()
			charge_snd = Sfx.play("charge", 0.0, -6.0)
		charge = minf(1.0, charge + dt / CHARGE_TIME)
		# 단계가 오를 때마다 색이 바뀌며 번쩍
		var st := 0
		for th in CHARGE_STAGES:
			if charge >= th:
				st += 1
		if st > charge_stage:
			charge_stage = st
			charge_fx.stage_up(st)
			if st >= 3:
				Sfx.play("charged", 0.0, -1.0)
				Main.inst.shake(0.15)
				Main.inst.camera.fov_punch(2.0)
			else:
				var ping := Sfx.play("ready", 0.0, -4.0)
				if ping:
					ping.pitch_scale = 0.8 + st * 0.35
		charge_fx.set_charge(charge, dt)""")
rep("""		if charge >= 1.0 and dash_t <= 0.0:
			_start_mega()
		elif charge >= CHARGE_MIN and dash_t <= 0.0:
			_fire_laser(charge)""", """		if charge >= 1.0:
			_start_mega()
		elif charge >= CHARGE_MIN:
			_fire_laser(charge)""")
rep("""	Main.inst.camera.fov_punch(7.0)
	if charging:
		charging = false
		charge_fx.end()
		if charge_snd and charge_snd.playing:
			charge_snd.stop()
		charge = 0.0
""", """	Main.inst.camera.fov_punch(7.0)
""")

# ── 사격 흔들림 ──
rep("""	Sfx.play("shoot", 0.08, -8.0)
	recoil = 1.0
	tilt_v -= d * 0.9""", """	Sfx.play("shoot", 0.08, -8.0)
	recoil = 1.0
	tilt_v -= d * 0.9
	var main := Main.inst
	main.kick(-d * 0.09)
	main.shake(0.05)""")

# ── 검: 몇 프레임 만에 끝나는 스윙, 무조건 한 방 ──
rep("""func _slash_hit() -> void:
	slash_anim = 0.28""", """func _slash_hit() -> void:
	slash_anim = SLASH_TIME""")
rep("""			en.take_hit(3, d.normalized(), en.global_position, "slash")
			hit_any = true""", """			en.slash_yaw = atan2(-aim_dir.x, -aim_dir.z)
			en.take_hit(999, d.normalized(), en.global_position, "slash")
			hit_any = true""")
rep("""	if hit_any:
		main.hitstop(0.05)
		main.shake(0.18)
		main.camera.fov_punch(-3.0)""", """	# 휘두르기만 해도 짧은 흔들림, 베면 강하게
	main.shake(0.2)
	main.kick(aim_dir * 0.35)
	if hit_any:
		main.hitstop(0.09)
		main.shake(0.4)
		main.camera.fov_punch(-4.0)""")
rep("""	elif slash_anim > 0.0:
		slash_anim -= dt
		var k := 1.0 - slash_anim / 0.28
		arm_r.rotation.y = lerpf(-1.3, 1.8, ease(k, 0.3))
		arm_r.rotation.x = -0.4
		blade.rotation_degrees = Vector3(8, -70, 0)
		torso.rotation.y = lerpf(-0.7, 0.8, ease(k, 0.3))""", """	elif slash_anim > 0.0:
		slash_anim -= dt
		# 앞 SLASH_SWING 초에 스윙이 끝나고, 나머지는 휘두른 자세로 멈췄다 복귀
		var el := SLASH_TIME - slash_anim
		var k := clampf(el / SLASH_SWING, 0.0, 1.0)
		arm_r.rotation.y = lerpf(-1.4, 1.9, k)
		arm_r.rotation.x = -0.4
		blade.rotation_degrees = Vector3(8, -70, 0)
		torso.rotation.y = lerpf(-0.8, 0.85, k)""")

# ── 지속 레이저: 극적 조명 켜고 끄기 ──
rep("""	mega_node = MegaBeam.new()
	FX.root.add_child(mega_node)
	var main := Main.inst""", """	mega_node = MegaBeam.new()
	FX.root.add_child(mega_node)
	var main := Main.inst
	main.dramatic(true)""")
rep("""	Main.inst.camera.set_beam(false)
	laser_cd = 0.9""", """	Main.inst.camera.set_beam(false)
	Main.inst.dramatic(false)
	laser_cd = 0.9""")


# ── 궁극기 ──
rep("""# ── 최대 충전 지속 레이저 ────────────────────────────────""", """# ── 궁극기: 백팩 미사일 난사 ─────────────────────────────

func _fire_ult() -> void:
	ult = 0.0
	ult_queue = ULT_MISSILES
	ult_t = 0.0
	var main := Main.inst
	main.shake(0.35)
	main.camera.fov_punch(5.0)
	main.kick(aim_dir * -0.4)
	squash_v -= 9.0
	hover_v += 4.0
	FX.shockwave(global_position, Color("ffb050"), 3.5, 0.35)
	FX.ring(Vector3(global_position.x, 0.3, global_position.z), 3.5, [Color("ffd060"), Color("ff7a30"), Color.WHITE], 0.35)
	Sfx.play("overload", 0.0, -2.0)


func _update_ult(dt: float) -> void:
	if ult < 1.0 and ult_queue == 0:
		var before := ult
		ult = minf(1.0, ult + dt / ULT_TIME)
		if before < 1.0 and ult >= 1.0:
			Sfx.play("charged", 0.0, -6.0)
	if ult_queue > 0:
		ult_t -= dt
		while ult_t <= 0.0 and ult_queue > 0:
			ult_t += 0.03
			_launch_missile(ULT_MISSILES - ult_queue)
			ult_queue -= 1


func _launch_missile(i: int) -> void:
	var jet: Node3D = j.jet_l if i % 2 == 0 else j.jet_r
	var origin := jet.global_position + Vector3(0, 0.2, 0)
	var targets := Missile.pick_targets(global_position, 16.0)
	var m := Missile.new()
	if targets.size() > 0:
		m.target = targets[i % targets.size()]
	else:
		var a := randf() * TAU
		m.target_pos = global_position + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 7.0)
		m.target_pos.y = 0.3
	# 흩날리듯 사방으로 퍼져 올라간다
	var a2 := TAU * float(i) / ULT_MISSILES + randf_range(-0.2, 0.2)
	var out := Vector3(cos(a2), 0, sin(a2))
	m.vel = out * randf_range(5.0, 9.0) + Vector3(0, randf_range(6.0, 10.0), 0) - aim_dir * 1.5
	FX.root.add_child(m)
	m.global_position = origin
	FX.flash(origin, Color("ffd080"), 0.35, 0.05)
	if i % 3 == 0:
		Sfx.play("eshot", 0.2, -8.0)
	recoil = 0.6


# ── 최대 충전 지속 레이저 ────────────────────────────────""")
rep("""	invuln = max(0.0, invuln - dt)
	hurt_t = max(0.0, hurt_t - dt)
	_animate(dt)""", """	invuln = max(0.0, invuln - dt)
	hurt_t = max(0.0, hurt_t - dt)
	_update_ult(dt)
	_animate(dt)""")

io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("ok")
