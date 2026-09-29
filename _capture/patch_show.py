import io, os
os.chdir(os.path.join(os.path.dirname(__file__), "..", "scripts"))
p = "main.gd"
s = io.open(p, encoding="utf-8").read()

a = s[s.index("func _run_showcase() -> void:"):s.index("func _physics_process(dt: float) -> void:")]
b = '''func _run_showcase() -> void:
	var p := player.global_position
	var steps := [0.2, 4.1, 4.5]
	if _show_step >= steps.size() or time < steps[_show_step]:
		return
	match _show_step:
		0:
			player.invuln = 999.0
			# 지속 레이저가 쓸고 지나갈 부채꼴 위치 + 죽음 연출 4종 지정
			var deaths := [Enemy.Death.OVERLOAD, Enemy.Death.SPINOUT, Enemy.Death.SHUTDOWN, Enemy.Death.BURST]
			for i in 4:
				var a := deg_to_rad(-70.0 + i * 38.0)
				var e := Enemy.new()
				e.pattern = Enemy.Pattern.AIMED_BURST
				e.forced_death = deaths[i]
				e.hp = 3
				world.add_child(e)
				e.global_position = p + Vector3(sin(a), 0, -cos(a)) * 6.5
			_show_aim = p + Vector3(sin(deg_to_rad(-80.0)), 0, -cos(deg_to_rad(-80.0))) * 6.0
		1:
			var e := Enemy.new()
			e.forced_death = Enemy.Death.SPINOUT
			e.hp = 3
			world.add_child(e)
			e.global_position = p + Vector3(-1.5, 0, -4.2)
			_show_aim = e.global_position + Vector3(0, 0.95, 0)
		2:
			pass
	_show_step += 1


'''
s = s.replace(a, b)

a = s[s.index("	if showcase:\n		# 연출 확인 순서"):s.index("		return out\n", s.index("	if showcase:\n		# 연출 확인 순서")) + len("		return out\n")]
b = '''	if showcase:
		# 연출 확인 순서: 최대 충전 → 2초 지속 레이저로 부채꼴 쓸기 → 돌진 베기
		out.aim = _show_aim
		out.charge = time > 0.4 and time < 1.55
		if time > 1.6 and time < 3.6:
			var k := clampf((time - 1.6) / 1.6, 0.0, 1.0)
			var a := deg_to_rad(lerpf(-80.0, 60.0, k))
			out.aim = p.global_position + Vector3(sin(a), 0, -cos(a)) * 6.0
		if time > 4.8 and time < 4.85:
			out.slash = true
		return out
'''
s = s.replace(a, b)
io.open(p, "w", encoding="utf-8", newline="\n").write(s)
print("ok")
