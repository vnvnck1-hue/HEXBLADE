extends SceneTree
## Run with: Godot --headless --path . -s tests/terrain_jump_check.gd -- --seed=11
## 방 탐색 아레나의 바닥 굴곡과 점프 입력을 실제 키 입력(InputEventKey)으로 확인한다.
##  1. 모든 방에 굴곡이 있고, 어디에도 단차(끊긴 높이)가 없으며 굴곡은 낮고 완만하다
##  2. 굴곡을 걸어서 지나갈 때 막히거나 공중에 뜨지 않는다
##  3. Shift + Space 단타 → 대시 / Space 단독 → 대시 / Shift + Space 길게 → 점프

var fails := 0
var main: Main
var map: ArenaMap
var player: Player


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _key(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _release_all() -> void:
	for k in [KEY_SHIFT, KEY_SPACE, KEY_A, KEY_D, KEY_W, KEY_S]:
		_key(k, false)
	await _frames(2)


func _place(p: Vector3) -> void:
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.airborne = false
	player.vy = 0.0
	player.dash_t = 0.0
	player.dash_cd = 0.0
	player.chain_grace = 0.0
	await _frames(3)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(10)
	map = main.map
	player = main.player
	player.invuln = 999.0
	Sfx.inst.muted = true
	_check(map.terrain, "arena map has terrain enabled")

	# 1. 굴곡 구성
	var rooms_with := {}
	var max_h := 0.0
	for f in map.feats:
		rooms_with[map.room_at(Vector3(f.c.x, 0, f.c.y))] = true
		max_h = maxf(max_h, absf(f.h))
	_check(rooms_with.size() == map.rooms.size(), "every room has bumps (%d/%d)" % [rooms_with.size(), map.rooms.size()])
	_check(max_h <= 0.5, "bumps stay low (max %.2fm)" % max_h)
	# 이웃 칸의 공유 모서리 높이가 어디서나 이어진다 (끊긴 단차 면이 없다), 비탈도 완만하다
	var worst_gap := 0.0
	var worst_slope := 0.0
	for y in range(1, ArenaMap.H - 1):
		for x in range(1, ArenaMap.W - 1):
			var c := Vector2i(x, y)
			if map.cell_type(c) != ArenaMap.FLOOR:
				continue
			var p := map.world_of(c)
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var n: Vector2i = c + d
				if map.cell_type(n) != ArenaMap.FLOOR:
					continue
				var e := p + Vector3(d.x, 0, d.y) * 0.5
				# 경계 바로 양쪽에서 잰 높이 차 = 단차
				var a := map.height_at(e - Vector3(d.x, 0, d.y) * 0.001)
				var b := map.height_at(e + Vector3(d.x, 0, d.y) * 0.001)
				worst_gap = maxf(worst_gap, absf(a - b))
				worst_slope = maxf(worst_slope, absf(map.cell_h(n) - map.cell_h(c)))
	_check(worst_gap < 0.02, "no step edges anywhere (max edge gap %.3fm)" % worst_gap)
	_check(worst_slope < ArenaMap.STEP * 0.6, "slopes are gentle (max %.2fm per cell)" % worst_slope)

	var home := map.room_center_world(map.start_room)

	# 2. 굴곡 가로질러 걷기: 가운데를 지나는 직선이 막히지 않은 둔덕 중 가장 높은 것을 x 축으로 관통한다
	var best: Dictionary = {}
	var start := Vector3.ZERO
	var dir_key: Key = KEY_D
	for f in map.feats:
		if f.h <= 0.0 or (not best.is_empty() and f.h <= best.h):
			continue
		var c: Vector2 = f.c
		for sgn in [-1.0, 1.0]:
			var s0 := Vector3(c.x + sgn * (f.r1 + 0.8), 0.0, c.y)
			var ok := true
			var t := 0.0
			while t <= 1.0:
				var q := s0.lerp(Vector3(c.x, 0.0, c.y), t)
				for dz in [-0.45, 0.0, 0.45]:
					if map.is_blocked_cell(map.cell_of(q + Vector3(0, 0, dz))):
						ok = false
				t += 0.05
			if ok:
				best = f
				start = s0
				dir_key = KEY_D if sgn < 0.0 else KEY_A
				break
	_check(not best.is_empty(), "found a bump with a clear walking line")
	if not best.is_empty():
		await _place(start)
		_key(dir_key, true)
		var top := 0.0
		var air := false
		var stuck := 0
		var last := player.global_position
		for i in 60:
			await _frames(1)
			top = maxf(top, player.gy)
			air = air or player.airborne
			if Vector2(player.global_position.x - last.x, player.global_position.z - last.z).length() < 0.01 and i < 40:
				stuck += 1
			last = player.global_position
		await _release_all()
		_check(top > best.h * 0.8, "walked over a %.2fm bump (reached %.2f)" % [best.h, top])
		_check(not air and stuck < 5, "walking over bump stays grounded and unblocked (air=%s stuck=%d)" % [air, stuck])

	# 3. Shift + Space 단타 → 대시
	await _place(home)
	_key(KEY_SHIFT, true)
	await _frames(2)
	_key(KEY_SPACE, true)
	await _frames(3)
	_check(player.dash_t <= 0.0 and not player.airborne, "shift+space held 3 frames: still charging (no dash, no jump yet)")
	_key(KEY_SPACE, false)
	await _frames(2)
	_check(player.dash_t > 0.0 and not player.airborne, "shift+space tap -> dash, not jump")
	await _release_all()
	await _frames(40)

	# Space 단독 → 곧바로 대시
	await _place(home)
	_key(KEY_SPACE, true)
	await _frames(2)
	_check(player.dash_t > 0.0 and not player.airborne, "space alone -> immediate dash")
	await _release_all()
	await _frames(40)

	# Shift + Space 길게 → 점프
	await _place(home)
	_key(KEY_SHIFT, true)
	await _frames(2)
	_key(KEY_SPACE, true)
	var t_jump := -1
	for i in 30:
		await _frames(1)
		if player.airborne and t_jump < 0:
			t_jump = i
	_check(t_jump >= 9 and t_jump <= 14 and player.dash_t <= 0.0, "shift+space hold -> jump after ~0.18s (frame %d), no dash" % t_jump)
	var peak := 0.0
	for i in 40:
		await _frames(1)
		peak = maxf(peak, player.global_position.y - player.gy)
	await _release_all()
	await _frames(30)
	_check(not player.airborne, "landed after jump (peak %.2fm above ground)" % peak)

	print("TERRAIN_JUMP_CHECK %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails > 0 else 0)
