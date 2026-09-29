import io, os
os.chdir(os.path.join(os.path.dirname(__file__), "..", "scripts"))
p = "main.gd"
s = io.open(p, encoding="utf-8").read()

a = s[s.index("func _run_showcase() -> void:"):s.index("func _physics_process(dt: float) -> void:")]
b = '''func _spawn_show(p: Vector3, off: Vector3, hp := 3) -> Enemy:
	var e := Enemy.new()
	e.pattern = Enemy.Pattern.AIMED_BURST
	e.hp = hp
	world.add_child(e)
	e.global_position = map.push_out(p + off, 1.0)
	return e


func _run_showcase() -> void:
	var p := player.global_position
	var steps := [0.2, 3.7, 4.35, 5.2]
	if _show_step >= steps.size() or time < steps[_show_step]:
		return
	match _show_step:
		0:
			player.invuln = 999.0
			for i in 4:
				var a := deg_to_rad(-60.0 + i * 40.0)
				_spawn_show(p, Vector3(sin(a), 0, -cos(a)) * 6.5)
			_show_aim = p + Vector3(0, 0.95, -6.0)
		1:
			var e := _spawn_show(p, Vector3(2.8, 0, -2.4))
			_show_aim = e.global_position + Vector3(0, 0.95, 0)
		2:
			var e := _spawn_show(p, Vector3(-3.0, 0, -1.2))
			_show_aim = e.global_position + Vector3(0, 0.95, 0)
		3:
			for i in 7:
				var a := TAU * i / 7.0
				_spawn_show(p, Vector3(cos(a), 0, sin(a)) * randf_range(4.5, 7.0), 4)
			player.ult = 1.0
	_show_step += 1


'''
s = s.replace(a, b)

i = s.index("	if showcase:\n		# 연출 확인 순서")
j = s.index("		return out\n", i) + len("		return out\n")
b = '''	if showcase:
		# 연출 확인 순서: 충전하며 대시 → 최대 레이저로 빠르게 쓸기 → 돌진 베기 ×2 → 미사일 궁극기
		out.aim = _show_aim
		out.charge = time > 0.3 and time < 1.45
		if time > 0.75 and time < 0.8:
			out.move = Vector3(1, 0, 0.2)
			out.dash = true
		if time > 1.5 and time < 3.5:
			var a := sin((time - 1.5) * 4.0) * deg_to_rad(75.0)
			out.aim = p.global_position + Vector3(sin(a), 0, -cos(a)) * 6.0
		if (time > 4.0 and time < 4.04) or (time > 4.6 and time < 4.64):
			out.slash = true
		if time > 5.9 and time < 5.95:
			out.ult = true
		return out
'''
s = s[:i] + b + s[j:]
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("ok")
