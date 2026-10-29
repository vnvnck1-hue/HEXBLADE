extends SceneTree
## 방 탐색 자동 플레이 실시간 녹화용 (화면은 바깥 ffmpeg gdigrab 이 창 제목 HEXBLADE_REC 로 잡는다).
## Movie Maker(--write-movie)는 실시간보다 느리게 그려 실제 시계로 재는 히트스탑·슬로모션·컷인이 압축되므로 쓰지 않는다.
## 준비: 드론 자동 조작을 끄고 게이지가 찰 때까지 플레이 → 패링이 나오면 그 1초 전을 구간 시작으로
## 구간: 2초 Q · 3.5~6초 궁극기 최대 1회 · 6초 이후 두 번째 Q · 11초에 끝. 사건은 유닉스 시각으로 남긴다.
var out := "res://output/room-play-video-20261014"
var events: Array = []
var rec := AudioEffectRecord.new()

func _initialize() -> void:
	_run.call_deferred()

func _now() -> float:
	return Time.get_unix_time_from_system()

func _log(kind: String, game: Node, extra := {}) -> void:
	var row := {"kind": kind, "unix": _now(), "game_t": game.time}
	row.merge(extra)
	events.append(row)
	print("ROOMVID " + JSON.stringify(row))

func _run() -> void:
	DisplayServer.window_set_title("HEXBLADE_REC")
	# Godot 좌표는 모든 화면을 감싼 상자의 왼쪽 위가 원점 → 주 모니터 기준으로 놓고, 바깥 녹화에는 주 모니터 기준 좌표를 넘긴다
	var sp := DisplayServer.screen_get_position(DisplayServer.get_primary_screen())
	DisplayServer.window_set_position(sp + Vector2i(40, 60))
	await process_frame
	await process_frame
	var wp := DisplayServer.window_get_position() - sp
	var ws := DisplayServer.window_get_size()
	print("ROOMVID_WIN %d %d %d %d scale=%.2f" % [wp.x, wp.y, ws.x, ws.y, DisplayServer.screen_get_scale()])
	AudioServer.add_bus_effect(0, rec)
	rec.set_recording_active(true)
	var audio_start := _now()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	game.set_script(load("res://_capture/room_play_main.gd"))
	root.add_child(game)
	current_scene = game
	DisplayServer.window_set_title("HEXBLADE_REC")
	var phase := 0            # 0 게이지 대기 · 1 패링 대기 · 2 구간
	var phase_t := 0.0
	var clip0 := 0.0
	var whirls := 0
	var q_last := 0.0
	var parry_n := 0
	var whirl_was := false
	var ult_was := false
	while is_instance_valid(game):
		await physics_frame
		var d = PartnerDrone.inst
		var p = game.player
		if not is_instance_valid(d) or not is_instance_valid(p):
			continue
		DisplayServer.window_set_title("HEXBLADE_REC")
		if not p.alive:
			_log("player_died", game)
			break
		d.bot = false
		var pc: int = Parry.inst.count if Parry.inst else 0
		var new_parry := pc > parry_n
		parry_n = pc
		if new_parry:
			_log("parry", game)
		var w: bool = d.whirl_t >= 0.0
		if w and not whirl_was:
			if phase == 2:
				whirls += 1
			_log("whirl_start", game, {"gauge": d.gauge, "n": whirls})
		whirl_was = w
		var u: bool = p.ult_winding() or p.ult_queue > 0
		if u and not ult_was:
			_log("ult", game, {"missiles": p.missiles})
		ult_was = u
		if phase == 0:
			game.close_in = true
			if game.time > 4.0 and d.gauge >= 65.0 and d.whirl_t < 0.0:
				phase = 1
				phase_t = game.time
				_log("ready", game, {"gauge": d.gauge})
			elif game.time > 160.0:
				_log("timeout_gauge", game)
				break
			continue
		if phase == 1:
			if new_parry and game.time - phase_t > 2.5:
				phase = 2
				clip0 = _now() - 1.0
				_log("clip_start", game, {"unix_clip": clip0, "gauge": d.gauge, "missiles": p.missiles})
			elif game.time - phase_t > 90.0:
				_log("timeout_parry", game)
				break
			continue
		var ct := _now() - clip0
		game.ult_allowed = ct > 3.5 and ct < 6.0
		# Q 는 드론이 받을 수 있는 상태일 때 누르고, 휠윈드가 실제로 시작될 때까지 0.5초마다 다시 누른다
		var can_q: bool = d.state in [PartnerDrone.St.FOLLOW, PartnerDrone.St.SEEK, PartnerDrone.St.CLEAN, PartnerDrone.St.HOP, PartnerDrone.St.CHEER] 			and d.whirl_t < 0.0 and d.gauge >= PartnerDrone.WHIRL_COST and not p.ult_busy()
		var q_due: bool = (whirls == 0 and ct > 2.0) or (whirls == 1 and ct > 6.3 and not w)
		if q_due and can_q and _now() - q_last > 0.5:
			d.whirl_link()
			q_last = _now()
			_log("q_press", game, {"n": whirls + 1, "gauge": d.gauge})
		if ct > 11.5:
			break
	rec.set_recording_active(false)
	var wav := rec.get_recording()
	if wav:
		wav.save_to_wav(ProjectSettings.globalize_path(out + "/session_audio.wav"))
	var f := FileAccess.open(out + "/events.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"audio_start_unix": audio_start, "events": events}, "  "))
	f.close()
	print("ROOMVID_DONE")
	quit()
