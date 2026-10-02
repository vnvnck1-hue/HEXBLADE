class_name GimmickLab
extends Main
## 기믹 시험장 (Main 상속): 넓은 평지 홀 하나에 연기 구역 · 레일 · 가스통 · 수리키트 해치를 모두 두고
## 위쪽에서 사격 드론이 계속 내려온다. 플레이어 체력은 1 아래로 내려가지 않는다 (해치 회복을 시험할 수 있게 2 로 시작).
## 1 키: 가스통·해치 다시 놓기.  봇(--bot): 연기에 숨기 → 빠져나오기 → 레일 위 기 모으기 → 가스통 사격 → 레버 돌리기 를 반복한다.

const ROOM_SIZE := Vector2i(34, 24)
const DRONES := 3
const DRONE_GAP := 3.5
const PHASES := ["smoke", "exit", "belt", "barrels", "hatch", "collect"]

var center := Vector3.ZERO
var g: Gimmicks
var smoke: SmokeZone
var belt: RailBelt
var barrel_spots: Array[Vector3] = []
var hatch_spot := Vector3.ZERO
var drones: Array[Enemy] = []
var _drone_t := 1.0
var panel: Label
var phase := 0
var ph_t := 0.0
var cycles := 0
var closeup := 1.0
var _rode := false
var _side := false
var log_hidden_t := 0.0
var stats := {"hidden_s": 0.0, "belt_carry": 0.0}


func _ready() -> void:
	process_priority = 100
	super._ready()
	center = map.room_center_world(map.start_room)
	player.global_position = center + Vector3(0, 0, 3.0)
	player.hp = 2
	camera.snap(player.global_position)
	panel = Label.new()
	panel.add_theme_font_size_override("font_size", 14)
	panel.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	panel.add_theme_constant_override("outline_size", 5)
	panel.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.1))
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(22, -200)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.text = "\n".join([
		"[ 기믹 시험장 ]",
		"연기 구역   들어가면 적이 못 봄 · 이동기만 가능 · 공격 불가",
		"레일         올라타면 띠 속도만큼 빨라짐 (기 모으기 중에도)",
		"가스통       맞히면 폭발 · 주변 모두 피해 · 연쇄",
		"수리 해치    레버 옆에서 F 연타 → 열리면 키트를 주워 체력 +2",
		"1  가스통 · 해치 다시 놓기",
	])
	hud.root.add_child(panel)
	# 확인용: --phase=N 이면 봇이 그 단계부터, --closeup=0.5 면 카메라를 그만큼 당긴다
	for a in Main.cmd_args:
		if a.begins_with("--phase="):
			phase = clampi(int(a.substr(8)), 0, PHASES.size() - 1)
		elif a.begins_with("--closeup="):
			closeup = float(a.substr(10))
	if closeup < 1.0:
		camera.p = camera.p.duplicate()
		camera.p.offset = camera.p.offset * closeup
	FX.victory(player.global_position)
	hud.banner("GIMMICK LAB", Color(0.7, 0.95, 1.0), "연기 · 레일 · 가스통 · 수리키트 해치 · Esc 로비")


func _build_arena() -> void:
	map = ArenaMap.new()
	world.add_child(map)
	map.terrain = false
	map.generate_single(map_seed if map_seed >= 0 else 11, ArenaMap.Shape.RECT, false, ROOM_SIZE)
	map.build()


func combat_rooms() -> int:
	return 0


## Gimmicks 가 자동 배치 대신 부른다
func gimmick_layout(gm: Gimmicks) -> void:
	g = gm
	g.auto = false
	var c := map.room_center_world(map.start_room)
	smoke = g.add_smoke(c + Vector3(-9.0, 0, -1.0), 2.8)
	belt = g.add_belt(c + Vector3(1.0, 0, 5.5), Vector3.RIGHT, 12.0)
	barrel_spots = [c + Vector3(5.0, 0, -3.0), c + Vector3(6.4, 0, -3.6), c + Vector3(5.6, 0, -2.0), c + Vector3(-2.0, 0, -6.5)]
	hatch_spot = c + Vector3(10.5, 0, 2.0)
	_place_props()


func _place_props() -> void:
	for e in get_tree().get_nodes_in_group("gas_canisters"):
		if is_instance_valid(e) and (e as GasCanister).alive:
			e.queue_free()
	for b in barrel_spots:
		g.add_barrel(b)
	for h in g.hatches:
		if is_instance_valid(h):
			h.queue_free()
	g.hatches.clear()
	g.add_hatch(hatch_spot, PI, true)


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	if player.alive:
		if player.hp <= 1:
			player.invuln = maxf(player.invuln, 0.2)
		player.energy = Player.ENERGY_MAX
		player.missiles = maxi(player.missiles, 2)
		if player.hidden:
			stats.hidden_s += dt
		if player.carry != Vector3.ZERO:
			stats.belt_carry += dt
	# 사격 드론: 위쪽에서 계속 내려온다
	for i in range(drones.size() - 1, -1, -1):
		if not is_instance_valid(drones[i]) or not drones[i].alive:
			drones.remove_at(i)
	_drone_t -= dt
	if drones.size() < DRONES and _drone_t <= 0.0:
		_drone_t = DRONE_GAP
		var e := Enemy.new()
		e.pattern = Enemy.Pattern.AIMED_BURST
		world.add_child(e)
		e.global_position = center + Vector3(randf_range(-7.0, 7.0), 0, randf_range(-9.0, -7.0))
		drones.append(e)
	if player.bot:
		_bot_step(dt)



func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo() and (event as InputEventKey).physical_keycode == KEY_1:
		_place_props()
		hud.banner("RESET", Color(0.8, 0.9, 1.0), "가스통과 해치를 다시 놓았습니다")
		get_viewport().set_input_as_handled()
		return
	super._unhandled_input(event)


func _process(dt: float) -> void:
	super._process(dt)
	hud.wave_label.text = "GIMMICK LAB"
	var tags := []
	if player.hidden:
		tags.append("은신")
	elif player.no_attack:
		tags.append("공격 불가")
	if player.carry != Vector3.ZERO:
		tags.append("레일 %.1fm/s" % player.carry.length())
	if player.rooted:
		tags.append("레버")
	hud.count_label.text = "HP %d / %d  ·  %s" % [player.hp, Player.MAX_HP, " · ".join(tags) if tags.size() > 0 else "-"]


# ── 자동 플레이 ─────────────────────────────────────────

func _bot_step(dt: float) -> void:
	if g == null:
		return
	ph_t += dt
	var ph_name: String = PHASES[phase]
	var next := false
	match ph_name:
		"smoke": next = ph_t > 7.0
		"exit": next = ph_t > 1.6
		"belt": next = _rode and player.carry == Vector3.ZERO or ph_t > 9.0
		"barrels": next = get_tree().get_nodes_in_group("gas_canisters").is_empty() or ph_t > 7.0
		"hatch": next = _hatch_done() or ph_t > 9.0
		"collect": next = ph_t > 2.5
	if next:
		print("LAB_PHASE %s done t=%.1f hp=%d hidden_s=%.1f belt=%.1f" % [ph_name, time, player.hp, stats.hidden_s, stats.belt_carry])
		phase = (phase + 1) % PHASES.size()
		ph_t = 0.0
		_rode = false
		_side = false
		if phase == 0:
			cycles += 1
			player.hp = 2
			_place_props()


func _hatch_done() -> bool:
	for h in g.hatches:
		if is_instance_valid(h) and h.done:
			return true
	return false


func _hatch() -> RepairHatch:
	for h in g.hatches:
		if is_instance_valid(h):
			return h
	return null


func _go(p: Player, to: Vector3, stop := 0.4) -> Vector3:
	var d := to - p.global_position
	d.y = 0
	return d.normalized() if d.length() > stop else Vector3.ZERO


func bot_input(p: Player) -> Dictionary:
	var out := {"move": Vector3.ZERO, "aim": p.global_position + Vector3(0, 0.95, -3), "fire": false, "slash": false, "dash": false, "charge": false, "boost": false, "jump": false}
	if g == null:
		return out
	var ph_name: String = PHASES[phase]
	match ph_name:
		"smoke":
			out.move = _go(p, smoke.global_position, 0.5)
			# 숨은 채로 쏘려 해 본다 (막혀야 한다)
			out.fire = fmod(ph_t, 1.0) < 0.3
			if drones.size() > 0 and is_instance_valid(drones[0]):
				out.aim = drones[0].global_position + Vector3(0, 0.95, 0)
		"exit":
			out.move = Vector3(1, 0, 0.35).normalized()
			out.boost = ph_t > 0.3
		"belt":
			var start := belt.global_position - belt.dir * (belt.length * 0.5 - 0.6)
			# 한 번 올라타면 끝까지 실려 가며 기를 모은다 (내리면 놓아 레이저)
			# 레일 옆으로 돌아 출발점에 선다 (흐름을 거슬러 걷지 않게)
			var side := start - belt.dir * 0.8 + belt.dir.cross(Vector3.UP) * (RailBelt.WIDTH * 0.5 + 1.0)
			if Vector2(p.global_position.x - side.x, p.global_position.z - side.z).length() < 0.6:
				_side = true
			var to_start := start - p.global_position
			to_start.y = 0
			if to_start.length() < 0.6:
				_rode = true
			if not _rode:
				out.move = _go(p, start if _side else side, 0.3)
			else:
				out.charge = p.carry != Vector3.ZERO
			out.aim = p.global_position + Vector3(0, 0.95, -6)
		"barrels":
			var best: Node3D = null
			var bd := 1e9
			for e in get_tree().get_nodes_in_group("gas_canisters"):
				var l := (e as Node3D).global_position.distance_to(p.global_position)
				if l < bd:
					bd = l
					best = e
			if best:
				out.aim = best.global_position + Vector3(0, 0.95, 0)
				var to := best.global_position - p.global_position
				to.y = 0
				out.move = to.normalized() if bd > 8.0 else (-to.normalized() if bd < 5.5 else Vector3.ZERO)
				out.fire = bd < 9.0
		"hatch":
			var h := _hatch()
			if h:
				out.move = _go(p, h.lever_pos(), 1.0)
		"collect":
			var h := _hatch()
			if h:
				out.move = _go(p, h.global_position, 0.3)
	return out
