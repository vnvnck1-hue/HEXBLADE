import io, os
os.chdir(os.path.join(os.path.dirname(__file__), "..", "scripts"))


def load(p):
    return io.open(p, encoding="utf-8").read()


def save(p, s):
    io.open(p, "w", encoding="utf-8", newline="\n").write(s)


def rep(s, a, b):
    assert a in s, a[:70]
    return s.replace(a, b)


# ── enemy.gd ──
p = "enemy.gd"
s = load(p)
s = rep(s, "enum Pattern { AIMED_BURST, FAN, RING }\n", """enum Pattern { AIMED_BURST, FAN, RING }
## 죽음 연출: 즉시 폭발 / 과부하 팽창 후 폭발 / 튕겨 날아가 추락 폭발 / 전원 차단 후 쓰러져 붕괴
enum Death { BURST, OVERLOAD, SPINOUT, SHUTDOWN }
""")
s = rep(s, "var wob_v := Vector2.ZERO\n", """var wob_v := Vector2.ZERO
var dying := false
var death := Death.BURST
var death_t := 0.0
var death_dir := Vector3.ZERO
var d_vel := Vector3.ZERO
var d_spin := Vector3.ZERO
var fx_t := 0.0
var forced_death := -1
""")
s = rep(s, """func _physics_process(dt: float) -> void:
	if not alive:
		return""", """func _physics_process(dt: float) -> void:
	if dying:
		_update_death(dt)
		return
	if not alive:
		return""")
a = s[s.index("func take_hit(dmg: int"):s.index("func _set_flash(on: bool)")]
b = '''func take_hit(dmg: int, dir: Vector3, _pos: Vector3, source := "bullet") -> void:
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
	death = _pick_death(source) if forced_death < 0 else forced_death
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
		"slash":
			return Death.SPINOUT if r < 0.6 else (Death.SHUTDOWN if r < 0.8 else Death.BURST)
	return [Death.BURST, Death.OVERLOAD, Death.SPINOUT, Death.SHUTDOWN][randi() % 4]


func _update_death(dt: float) -> void:
	death_t += dt
	var body: Node3D = j.body
	var core: MeshInstance3D = j.core
	var cm: StandardMaterial3D = j.core_mat
	fx_t -= dt
	match death:
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


func _explode(scale_k: float, power: float, lift: float, push: Vector3) -> void:
	var body: Node3D = j.body
	var p := body.global_position
	FX.enemy_explosion(p, scale_k)
	Debris.burst(body, p - Vector3(0, 0.35, 0), power, lift, push)
	Sfx.play("boom", 0.1)
	dying = false
	queue_free()


'''
s = s.replace(a, b)
save(p, s)

# ── fx.gd ──
p = "fx.gd"
s = load(p)
s = rep(s, '''static func enemy_explosion(pos: Vector3) -> void:
	var ground := Vector3(pos.x, 0.25, pos.z)
	ring(ground, 3.8, Pal.RING_ORANGE, 0.45)
	flash(pos, Color(1, 1, 0.8), 1.4, 0.1)
	puffs(pos + Vector3(0, -0.5, 0), 9, Pal.PUFF_RED, 0.9, 1.0, 0.75)
	sparks(pos, 18, [Color("ffd0e8"), Color("ff4aa0"), Color("7040c0")], 9.0, 0.6, -12.0, 0.1)
	sparks(pos, 8, [Pal.E_WHITE, Pal.E_GREY], 7.0, 0.8, -18.0, 0.16)''', '''static func enemy_explosion(pos: Vector3, k := 1.0) -> void:
	var ground := Vector3(pos.x, 0.25, pos.z)
	ring(ground, 3.8 * k, Pal.RING_ORANGE, 0.45 * sqrt(k))
	flash(pos, Color(1, 1, 0.8), 1.4 * k, 0.1)
	puffs(pos + Vector3(0, -0.5, 0), int(9 * k), Pal.PUFF_RED, 0.9 * k, 1.0 * sqrt(k), 0.75)
	sparks(pos, int(18 * k), [Color("ffd0e8"), Color("ff4aa0"), Color("7040c0")], 9.0 * sqrt(k), 0.6, -12.0, 0.1)


## 추락하는 적이 뿜는 연기
static func smoke(pos: Vector3) -> void:
	var c := Color("5a2a50") if randf() < 0.5 else Color("ff5a3a")
	var mi := Pal.flat_mesh(_sphere, c)
	_add(mi, pos + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1)))
	mi.scale = Vector3.ONE * randf_range(0.25, 0.45)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.45).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(v: Color): mi.set_instance_shader_parameter("tint", v), c, Color("2a1a30"), 0.3)
	tw.parallel().tween_property(mi, "position", mi.position + Vector3(0, 0.5, 0), 0.45)
	tw.tween_callback(mi.queue_free)''')
save(p, s)

# ── sfx.gd ──
p = "sfx.gd"
s = load(p)
s = rep(s, "	streams.win = _notes", '''	streams.overload = _synth(0.5, func(t, k): return (_sq(lerp(300.0, 1400.0, k), t) * 0.25 + sin(TAU * lerp(600.0, 2400.0, k) * t) * 0.2) * (0.4 + 0.6 * k) * (0.6 + 0.4 * sin(TAU * 30.0 * t)))
	streams.powerdown = _synth(0.55, func(t, k): return (sin(TAU * lerp(700.0, 60.0, pow(k, 0.5)) * t) * 0.35 + _saw(lerp(350.0, 30.0, k), t) * 0.12) * (1.0 - k))
	streams.beam = _looped(func(t, k): return (randf() * 2.0 - 1.0) * 0.25 + _saw(55.0, t) * 0.35 + sin(TAU * 220.0 * t) * 0.15 * sin(TAU * 6.0 * t))
	streams.win = _notes''')
s = rep(s, "func _notes(freqs", '''func _looped(f: Callable) -> AudioStreamWAV:
	var w := _synth_filtered(1.0, 0.35, f)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = RATE
	return w


func _notes(freqs''')
save(p, s)
print("ok")
