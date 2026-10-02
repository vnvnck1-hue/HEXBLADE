class_name BugLab
extends Main
## 벌레형 괴생명체 시험장 (Main 상속). 엄폐물 없는 넓은 홀에서 개미 병정·공벌레와 싸워 보거나,
## 전시 모드에서 두 모델의 애니메이션을 하나씩 돌려 본다.
##
## 숫자 키:  1 개미 병정 소환   2 공벌레 소환   3 모두 지우기   4 전시 모드 ↔ 전투   5 플레이어 무적   6 자동 보충(3마리 유지)
## 실행 인자: --gallery (전시 모드로 시작) · --bot (자동 플레이, 자동 보충 켜짐) · --only=ant|pill

const ROOM_SIZE := Vector2i(30, 22)
## 전시 모드: [이름, 길이(초)] — 차례로 반복한다
const ANT_CLIPS := [["IDLE · 더듬이 탐색", 3.0], ["SKITTER · 후다닥 걸음", 3.0], ["ACID · 배를 말아 산 발사", 2.4],
	["BITE · 큰턱 물기", 2.0], ["ALARM · 피격 버둥", 1.8], ["DEATH · 뒤집혀 버둥", 2.6], ["EMERGE · 땅에서 기어 나옴", 1.8]]
const PILL_CLIPS := [["CRAWL · 물결 다리", 3.0], ["SNIFF · 더듬이 두드리기", 2.4], ["CURL · 몸 말기", 1.8],
	["ROLL · 굴러가기", 2.4], ["UNCURL · 펼치고 기지개", 1.8], ["DEATH · 뒤집혀 버둥", 2.6], ["EMERGE · 땅에서 기어 나옴", 1.8]]

var center := Vector3.ZERO
var god := true
var refill := false
var only := ""
var gallery: Node3D
var panel: Label
var clip_label: Label
var g_ant: AntRig
var g_pill: PillRig
var g_ant_root: Node3D
var g_pill_root: Node3D
var g_ant_pose: Node3D
var g_pill_pose: Node3D
var g_t := 0.0
var g_clip := 0
var _refill_t := 0.0


func _ready() -> void:
	process_priority = 100
	super._ready()
	center = map.room_center_world(map.start_room)
	player.global_position = center + Vector3(0, 0, 5.0)
	camera.snap(player.global_position)
	panel = _label(Vector2(22, -210), 14)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	panel.offset_left = 22
	panel.offset_top = -330
	panel.offset_bottom = -120
	panel.offset_right = 360
	clip_label = _label(Vector2(0, 0), 22)
	clip_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	clip_label.offset_left = -420
	clip_label.offset_right = 420
	clip_label.offset_top = 64
	clip_label.offset_bottom = 104
	clip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var start_gallery := false
	for a in Main.cmd_args:
		if a == "--gallery":
			start_gallery = true
		elif a == "--bot":
			refill = true
		elif a.begins_with("--only="):
			only = a.substr(7)
	if start_gallery:
		_set_gallery(true)
	else:
		_spawn_set()
		hud.banner("BUG LAB", Color(0.85, 1.0, 0.6), "벌레형 괴생명체 시험장 · 1 개미 · 2 공벌레 · 4 애니메이션 전시 · Esc 로비")
	_update_panel()


func _label(pos: Vector2, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.9, 1.0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.03))
	l.position = pos
	hud.root.add_child(l)
	return l


func _build_arena() -> void:
	map = ArenaMap.new()
	world.add_child(map)
	map.terrain = false
	map.generate_single(map_seed if map_seed >= 0 else 11, ArenaMap.Shape.RECT, false, ROOM_SIZE)
	map.build()


func combat_rooms() -> int:
	return 0


# ── 전투 ───────────────────────────────────────

func _spawn_set() -> void:
	if only != "pill":
		spawn_bug("ant", center + Vector3(-4.0, 0, -3.0))
		spawn_bug("ant", center + Vector3(3.5, 0, -4.5))
	if only != "ant":
		spawn_bug("pill", center + Vector3(0.5, 0, -6.0))
		spawn_bug("pill", center + Vector3(-7.0, 0, -6.5))


func spawn_bug(kind: String, at: Vector3) -> BugEnemy:
	var e: BugEnemy = BugAnt.new() if kind == "ant" else BugPill.new()
	world.add_child(e)
	e.global_position = map.push_out(at, 1.0)
	e.rotation.y = atan2(-(player.global_position.x - at.x), -(player.global_position.z - at.z))
	return e


func _bugs() -> Array:
	return get_tree().get_nodes_in_group("enemies").filter(func(e): return e is BugEnemy)


func _process(dt: float) -> void:
	super._process(dt)
	if god and player.alive:
		player.invuln = maxf(player.invuln, 0.2)
	if gallery:
		_gallery_update(dt)
	elif refill:
		_refill_t -= dt
		if _refill_t <= 0.0:
			_refill_t = 1.0
			var n := _bugs().size()
			if n < 3:
				var kind := only if only != "" else ("ant" if randf() < 0.5 else "pill")
				var p := map.random_spot(map.start_room, player.global_position, 5.0, 11.0)
				spawn_bug(kind, p)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var handled := true
		match (event as InputEventKey).physical_keycode:
			KEY_1:
				if not gallery:
					spawn_bug("ant", map.random_spot(map.start_room, player.global_position, 4.5, 9.0))
			KEY_2:
				if not gallery:
					spawn_bug("pill", map.random_spot(map.start_room, player.global_position, 4.5, 9.0))
			KEY_3:
				for e in _bugs():
					e.queue_free()
			KEY_4:
				_set_gallery(gallery == null)
			KEY_5:
				god = not god
				if not god:
					player.invuln = 0.0
			KEY_6:
				refill = not refill
			_:
				handled = false
		if handled:
			_update_panel()
			get_viewport().set_input_as_handled()
			return


func _update_panel() -> void:
	panel.text = "\n".join([
		"BUG LAB",
		"1  개미 병정 소환",
		"2  공벌레 소환",
		"3  모두 지우기",
		"4  %s" % ("전투로 돌아가기" if gallery else "애니메이션 전시"),
		"5  플레이어 무적   %s" % ("켜짐" if god else "꺼짐"),
		"6  자동 보충(3마리)   %s" % ("켜짐" if refill else "꺼짐"),
	])


# ── 전시 모드: 판정 없는 모델 두 개에 클립을 차례로 재생 ───────

func _set_gallery(on: bool) -> void:
	if on == (gallery != null):
		return
	if not on:
		gallery.queue_free()
		gallery = null
		clip_label.text = ""
		player.visible = true
		player.bot = refill and capture_mode
		camera.set_charge_zoom(1.0)
		_spawn_set()
		return
	for e in _bugs():
		e.queue_free()
	gallery = Node3D.new()
	world.add_child(gallery)
	# 플레이어는 숨기고 그 자리를 카메라 중심으로 쓴다. 가깝게 당겨 본다.
	player.global_position = center + Vector3(0, 0, 3.0)
	player.velocity = Vector3.ZERO
	player.visible = false
	player.bot = false
	camera.set_charge_zoom(0.5)
	var base := player.global_position + Vector3(0, 0, -0.6)
	# 개미: 왼쪽, 공벌레: 오른쪽, 둘 다 카메라 쪽을 비스듬히 본다
	g_ant_root = Node3D.new()
	gallery.add_child(g_ant_root)
	g_ant_root.global_position = base + Vector3(-1.7, 0, 0)
	g_ant_root.rotation.y = 0.5 + PI
	g_ant_pose = Node3D.new()
	g_ant_root.add_child(g_ant_pose)
	var am := (load(BugAnt.MODEL) as PackedScene).instantiate() as Node3D
	g_ant_pose.add_child(am)
	g_ant = AntRig.new().setup(am)
	g_pill_root = Node3D.new()
	gallery.add_child(g_pill_root)
	g_pill_root.global_position = base + Vector3(1.9, 0, 0.2)
	g_pill_root.rotation.y = -0.9 + PI
	g_pill_pose = Node3D.new()
	g_pill_root.add_child(g_pill_pose)
	var roller := Node3D.new()
	g_pill_pose.add_child(roller)
	var pm := (load(BugPill.MODEL) as PackedScene).instantiate() as Node3D
	roller.add_child(pm)
	g_pill = PillRig.new().setup(pm, roller)
	FX.blob_shadow(g_ant_root, 2.0, 0.6)
	FX.blob_shadow(g_pill_root, 2.4, 0.6)
	g_t = 0.0
	g_clip = 0
	camera.snap(player.global_position)


## 클립 번호 c 의 경과 시간 t, 진행도 k 로 두 리그의 입력을 정한다
func _gallery_update(dt: float) -> void:
	g_t += dt
	var dur: float = ANT_CLIPS[g_clip][1]
	if g_t >= dur:
		g_t = 0.0
		g_clip = (g_clip + 1) % ANT_CLIPS.size()
		dur = ANT_CLIPS[g_clip][1]
	var k := g_t / dur
	clip_label.text = "%d/%d   %s      |      %s" % [g_clip + 1, ANT_CLIPS.size(), ANT_CLIPS[g_clip][0], PILL_CLIPS[g_clip][0]]
	ant_clip(g_ant, g_ant_pose, g_clip, g_t, k, dur)
	pill_clip(g_pill, g_pill_pose, g_clip, g_t, k, dt)
	g_ant.update(dt)
	g_pill.update(dt)


## 전시 클립: 리그 입력과 몸 전체 자세(pose: 뒤집기·땅속 높이)를 정한다. 캡처 스크립트(_capture/bug_show.gd)도 쓴다.
static func ant_clip(r: AntRig, pose: Node3D, c: int, t: float, k: float, dur: float) -> void:
	r.speed = 0.0
	r.acid_k = 0.0
	r.bite_k = 0.0
	r.lunge_k = 0.0
	r.dead_k = 0.0
	r.emerge_k = 1.0
	r.turn = 0.0
	r.look_yaw = sin(t * 0.8) * 0.5
	pose.rotation = Vector3.ZERO
	pose.position = Vector3.ZERO
	match c:
		1:
			# 달렸다 멈췄다: 0.4초 달리기 / 0.25초 멈춤
			r.speed = 5.2 if fmod(t, 0.65) < 0.4 else 0.0
			r.turn = sin(t * 2.0) * 3.0
		2:
			r.acid_k = smoothstep(0.0, 0.45, k) * (1.0 - smoothstep(0.75, 1.0, k))
			if absf(t - dur * 0.5) < 0.017:
				r.fire_k = 1.0
		3:
			r.bite_k = smoothstep(0.0, 0.45, k) if k < 0.55 else 0.0
			r.lunge_k = 1.0 - smoothstep(0.55, 0.9, k) if k >= 0.55 else 0.0
		4:
			if t < 0.02:
				r.alarm = 1.0
		5:
			r.dead_k = smoothstep(0.0, 0.15, k)
			r.kick_power = 1.0 - k * 0.8
			BugEnemy.flip(pose, BugEnemy._ease_out_back(clampf(k / 0.18, 0.0, 1.0)), 1.32, 1.0)
		6:
			r.emerge_k = k
			pose.position.y = lerpf(-1.2, 0.0, ease(k, 0.6))


static func pill_clip(r: PillRig, pose: Node3D, c: int, t: float, k: float, dt: float) -> void:
	r.speed = 0.0
	r.sniff = 0.0
	r.dead_k = 0.0
	r.emerge_k = 1.0
	r.stretch = 0.0
	r.turn = 0.0
	pose.rotation = Vector3.ZERO
	pose.position = Vector3.ZERO
	if c != 3:
		r.roll = 0.0
	match c:
		0:
			r.speed = 1.5
			r.curl = 0.0
		1:
			r.sniff = 1.0
			r.curl = 0.0
		2:
			r.stretch = -sin(clampf(k / 0.25, 0.0, 1.0) * PI) * 0.9
			r.curl = pow(clampf((k - 0.22) / 0.4, 0.0, 1.0), 3.0)
		3:
			r.curl = 1.0
			r.roll -= 12.0 / PillRig.BALL_R * dt * (1.0 - smoothstep(0.7, 1.0, k))
		4:
			r.curl = 1.0 - (1.0 - pow(1.0 - clampf(k / 0.35, 0.0, 1.0), 3.0))
			r.stretch = -sin(clampf(k / 0.45, 0.0, 1.0) * PI) * 0.7
		5:
			r.curl = clampf((k - 0.35) / 0.5, 0.0, 0.45)
			r.dead_k = smoothstep(0.0, 0.15, k)
			BugEnemy.flip(pose, BugEnemy._ease_out_back(clampf(k / 0.18, 0.0, 1.0)), 0.66, 1.0)
		6:
			r.curl = 0.0
			r.emerge_k = k
			pose.position.y = lerpf(-1.0, 0.0, ease(k, 0.6))

