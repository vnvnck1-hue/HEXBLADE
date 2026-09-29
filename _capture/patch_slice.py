import io, os
os.chdir(os.path.join(os.path.dirname(__file__), "..", "scripts"))
p = "enemy.gd"
s = io.open(p, encoding="utf-8").read()


def rep(a, b):
    global s
    assert a in s, a[:90]
    s = s.replace(a, b)


rep("enum Death { BURST, OVERLOAD, SPINOUT, SHUTDOWN }", "enum Death { BURST, OVERLOAD, SPINOUT, SHUTDOWN, SLICED }")
rep("var forced_death := -1\n", """var forced_death := -1
var slash_yaw := 0.0
var halves: Array = []        # [node, vel, spin, glow_mesh]
var cut_frame: Basis
""")
rep('''		"slash":
			return Death.SPINOUT if r < 0.6 else (Death.SHUTDOWN if r < 0.8 else Death.BURST)''', '''		"slash":
			return Death.SLICED''')
rep('''	death = _pick_death(source) if forced_death < 0 else forced_death''', '''	death = _pick_death(source) if (forced_death < 0 or source == "slash") else forced_death''')
rep('''		Death.SHUTDOWN:
			var cm: StandardMaterial3D = j.core_mat
			cm.emission_energy_multiplier = 0.0
			cm.albedo_color = Color(0.22, 0.18, 0.24)
			d_vel = death_dir * 2.0''', '''		Death.SLICED:
			_begin_slice()
		Death.SHUTDOWN:
			var cm: StandardMaterial3D = j.core_mat
			cm.emission_energy_multiplier = 0.0
			cm.albedo_color = Color(0.22, 0.18, 0.24)
			d_vel = death_dir * 2.0''')

rep('''func _explode(scale_k: float''', '''## 광선검 절단: 몸체를 비스듬한 절단면으로 두 조각 낸다
func _begin_slice() -> void:
	var body: Node3D = j.body
	var center := body.global_position
	# 절단면: 휘두른 방향(수평 호)을 따라 약간 기울어진 평면
	var tilt := randf_range(-0.35, 0.35)
	cut_frame = Basis(Vector3.UP, slash_yaw) * Basis(Vector3.FORWARD, tilt)
	var cube_w := 0.78
	var half_h := 0.37
	var hot := Color(1.0, 0.97, 0.85)
	for side in [1, -1]:
		var piece := Node3D.new()
		FX.root.add_child(piece)
		piece.global_transform = Transform3D(cut_frame, center)
		var bm := BoxMesh.new()
		bm.size = Vector3(cube_w, half_h, cube_w)
		var box := MeshInstance3D.new()
		box.mesh = bm
		box.material_override = Pal.lit(Pal.E_WHITE)
		box.position = Vector3(0, half_h * 0.5 * side, 0)
		piece.add_child(box)
		# 달아오른 절단면
		var gm := BoxMesh.new()
		gm.size = Vector3(cube_w * 0.96, 0.025, cube_w * 0.96)
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


func _explode(scale_k: float''')
rep('''	fx_t -= dt
	match death:''', '''	fx_t -= dt
	match death:
		Death.SLICED:
			_update_slice(dt)''')
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("ok")
