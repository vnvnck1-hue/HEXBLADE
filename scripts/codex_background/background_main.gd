extends TrainingMain
## Live gameplay, baseline lighting, four assets only. Shared game scripts untouched.

const KIT := preload("res://scripts/codex_background/background_kit.gd")
const TEST_MAP := preload("res://scripts/codex_background/background_map.gd")
const PROBES := [
	["seam_walk", Vector3(-2.8, 0, 1.5), Vector3(2.8, 0, 1.5)],
	["seam_dash", Vector3(2.8, 0, 2.8), Vector3(2.8, 0, -1.6)],
	["west_wall", Vector3(-2.3, 0, .4), Vector3(-5, 0, .4)],
	["bench", Vector3(-1.55, 0, -1.8), Vector3(-1.55, 0, -5)],
	["locker", Vector3(1.2, 0, -1.8), Vector3(1.2, 0, -5)],
	["north_wall", Vector3(3, 0, -1.8), Vector3(3, 0, -5)],
]
var kit: CodexBackgroundKit
var view_mode := 0
var review := false
var proof := false
var probe_index := -1
var probe_results: Array = []
var minimum_clearance := 99.0
var floor_error := 0.0
var _report_done := false
var _shot := 0
var _shot_pending := false
var _neutral := false
var _output := "res://output/codex-background-first-pass"

func _ready() -> void:
	layout = 0
	review = OS.get_cmdline_user_args().has("--bg-review")
	proof = OS.get_cmdline_user_args().has("--bg-proof")
	panel_rows = false
	super._ready()
	center = Vector3.ZERO
	player.global_position = Vector3(0, 0, 2.4)
	camera.snap(player.global_position)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 22
	panel.offset_top = 135
	panel.offset_right = 450
	panel.offset_bottom = 355
	panel.grow_vertical = Control.GROW_DIRECTION_END
	panel.z_index = 60
	hud.banner("CODEX BACKGROUND", Color("ce5f54"), "F01 · W01 · A01 · A02 / 8×8m · 9 시점 · 0 기준/중립 조명 · Esc 로비")
	if review:
		counter = false
		_apply_flags()
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))

func _build_arena() -> void:
	map = TEST_MAP.new()
	world.add_child(map)
	map.terrain = false
	map.generate_single(map_seed if map_seed >= 0 else 7, ArenaMap.Shape.RECT, false, Vector2i(8, 8))
	map._build_minimap()
	kit = KIT.new()
	kit.name = "CodexBackgroundKit"
	world.add_child(kit)
	kit.build()
	map.set("kit", kit)

func _spots() -> Array[Vector3]:
	return [Vector3(.7, 0, -.5)]

func gimmick_layout(g: Gimmicks) -> void:
	g.auto = false

func is_blocked(p: Vector3) -> bool:
	return kit.blocked(p) if kit else super.is_blocked(p)

func push_out(p: Vector3, radius: float) -> Vector3:
	return kit.push_circle(p, radius) if kit else p

func push_out_feet(p: Vector3, radius: float, _feet: float, _climb: float) -> Vector3:
	return kit.push_circle(p, radius) if kit else p

func _panel_text() -> String:
	return "[ CODEX 배경 첫 제작 · 8×8m ]\nF01 바닥 16 · W01 벽 8 · A01/A02 각 1\n9  시점: 게임 → 전체 → 프랍 → 바닥 → 벽\n0  조명: %s\n1  허수아비 재배치 · 4 반격 · 7 무적\nWASD 이동 · Space 대시 · E 돌진 조준\n좌클릭 검 · 우클릭 총 · V 게임 카메라\n감염/소품 없음 · 본편 변경 없음" % ("중립 비교" if _neutral else "현재 게임 기준")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.physical_keycode == KEY_9:
			view_mode = (view_mode + 1) % 5
			if view_mode == 0:
				camera.projection = Camera3D.PROJECTION_PERSPECTIVE
				camera.snap(player.global_position)
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_0:
			set_neutral(not _neutral)
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)

func set_neutral(on: bool) -> void:
	_neutral = on
	env.ambient_light_color = Color(.7, .7, .7) if on else Color(.5, .5, .85)
	env.ambient_light_energy = .8 if on else .5
	sun.light_energy = 1.0 if on else 1.25
	sun.light_color = Color.WHITE if on else Color(1, .97, 1)
	# Scope: this scene only; current game settings can always be restored.
	sun.rotation_degrees = Vector3(-55, -30, 0) if on else Vector3(-62, 28, 0)

func _update_camera(dt: float) -> void:
	if review:
		view_mode = [1, 0, 2, 3, 4, 1][mini(_shot, 5)]
	if view_mode == 0:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		super._update_camera(dt)
		return
	var target := Vector3(0, .4, -.3)
	var offset := Vector3(8, 10, 12)
	var span := 12.0
	match view_mode:
		2:
			target = Vector3(-.5, 1, -3.5)
			offset = Vector3(3, 3.6, 6)
			span = 5.0
		3:
			target = Vector3(0, 0, .7)
			offset = Vector3(.01, 8, 2)
			span = 5.0
		4:
			target = Vector3(0, 1.5, -4)
			offset = Vector3(1, 1, 8)
			span = 6.5
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = span
	camera.global_position = target + offset
	camera.look_at(target, Vector3.UP)

func _physics_process(dt: float) -> void:
	# Intentional fixture resets only in --bg-proof; each case then uses real bot movement.
	if proof and time < 18:
		var index := mini(int(time / 3), 5)
		if index != probe_index:
			if probe_index >= 0:
				_record_probe()
			probe_index = index
			player.global_position = PROBES[index][1]
			player.velocity = Vector3.ZERO
			player.dash_t = 0.0
			player.dash_cd = 0.0
			player.chain_grace = 0.0
			player.inbuf.clear()
			# No attacking dummy during the locomotion fixture; live combat resumes below.
			for d in dummies:
				d.process_mode = Node.PROCESS_MODE_DISABLED
	super._physics_process(dt)
	if proof:
		var clear := kit.clearance(player.global_position)
		if clear < minimum_clearance and clear < .395:
			print("BG_CLEARANCE_BAD t=%.3f p=%s dash=%.3f combo=%s ult=%s" % [time, player.global_position, player.dash_t, player.combo.ph, player.ult_busy()])
		minimum_clearance = minf(minimum_clearance, clear)
		if time < 18:
			floor_error = maxf(floor_error, absf(player.global_position.y))
		if time >= 18 and probe_index < 6:
			_record_probe()
			probe_index = 6
			for d in dummies:
				d.process_mode = Node.PROCESS_MODE_INHERIT

func _record_probe() -> void:
	var p := player.global_position
	var name_str: String = PROBES[probe_index][0]
	var okay := false
	match probe_index:
		0: okay = p.x > 2.3
		1: okay = p.z < -1.1
		2: okay = absf(p.x + 3.58) < .12
		3: okay = absf(p.z + 2.78) < .12
		4: okay = absf(p.z + 3.03) < .12
		5: okay = absf(p.z + 3.58) < .12
	probe_results.append({"case": name_str, "position": [p.x, p.y, p.z], "ok": okay})
	print("BG_PROBE %s %s %s" % [name_str, "PASS" if okay else "FAIL", p])

func bot_input(p: Player) -> Dictionary:
	if review:
		return {"move": Vector3.ZERO, "aim": Vector3(.7, .95, -.5), "fire": _shot == 1, "slash": false, "dash": false, "skill": _shot == 1}
	if proof and time < 18:
		var i := mini(int(time / 3), 5)
		var target: Vector3 = PROBES[i][2]
		var dir := target - p.global_position
		dir.y = 0
		var phase_time := fmod(time, 3)
		return {"move": dir.normalized() if dir.length() > .1 else Vector3.ZERO, "aim": target + Vector3(0, .95, 0), "fire": false, "slash": false, "dash": i > 0 and phase_time > .35 and phase_time < .375}
	return super.bot_input(p)

func _capture() -> void:
	capture_frame += 1
	if review and _shot < 6 and not _shot_pending and time >= 2 + _shot * 2:
		_shot_pending = true
		_save_review.call_deferred()
	if time > capture_seconds and not _report_done:
		_report_done = true
		var ok := not proof or (probe_results.size() == 6 and minimum_clearance >= .395 and floor_error < .001 and hit_count > 0)
		for entry in probe_results:
			ok = ok and entry.ok
		var report := {"ok": ok, "probes": probe_results, "min_clearance_m": minimum_clearance, "floor_error_m": floor_error, "combat_hits": hit_count, "combat_damage": total, "time": time, "review_images": _shot}
		if proof or review:
			var filename := "bot_validation.json" if proof else "render_validation.json"
			var f := FileAccess.open(_output + "/" + filename, FileAccess.WRITE)
			f.store_string(JSON.stringify(report, "\t") + "\n")
		print("CODEX_BACKGROUND_RUN_%s %s" % ["OK" if ok else "FAILED", JSON.stringify(report)])
		get_tree().quit(0 if ok else 1)

func _save_review() -> void:
	await RenderingServer.frame_post_draw
	var labels := ["01_overview_baseline", "02_gameplay_baseline", "03_props_baseline", "04_floor_seams", "05_wall_baseline", "06_overview_neutral"]
	var im := get_viewport().get_texture().get_image()
	im.save_png(_output + "/" + labels[_shot] + ".png")
	_shot += 1
	_shot_pending = false
	if _shot == 5:
		set_neutral(true)
