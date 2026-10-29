extends SceneTree
## 무한 비행 모드 실시간 녹화용. 화면은 바깥 ffmpeg ddagrab 이 주 모니터의 창 영역을 잡는다.
## Movie Maker(--write-movie)는 실시간보다 느리게 그려 실제 시계로 재는 히트스탑·슬로모션·컷인이 압축되므로 쓰지 않는다.
##  1) 테두리 없는 창을 주 모니터에 놓고 맨 위로, 창 좌표를 STREAMVID_WIN 으로 찍는다 (바깥 녹화가 이 좌표를 쓴다)
##  2) 0.2초 흰 화면 = 영상 동기 표식 → 1초 뒤가 clip0 (영상에서 흰 프레임을 찾아 맞춘다)
##  3) 게임 시작과 함께 clip0, 각본 봇이 기술을 쓴다. 소리는 AudioEffectRecord 로 따로 녹음
##  4) CLIP 초 + 여유 뒤 events.json · session_audio.wav 를 남기고 끝낸다
const CLIP := 30.0
const WIN := Vector2i(1600, 1000)
var out := "res://output/stream-play-video-20261029"
var rec := AudioEffectRecord.new()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	DisplayServer.window_set_title("HEXBLADE_REC")
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_size(WIN)
	# Godot 좌표는 모든 화면을 감싼 상자의 왼쪽 위가 원점 → 주 모니터 기준으로 놓고, 바깥 녹화에는 주 모니터 기준 좌표를 넘긴다
	var ps := DisplayServer.get_primary_screen()
	var sp := DisplayServer.screen_get_position(ps)
	var ss := DisplayServer.screen_get_size(ps)
	DisplayServer.window_set_position(sp + Vector2i(maxi(0, (ss.x - WIN.x) / 2), maxi(0, (ss.y - WIN.y) / 2)))
	# 흰 화면 (동기 표식)
	var layer := CanvasLayer.new()
	layer.layer = 128
	var white := ColorRect.new()
	white.color = Color.BLACK
	white.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(white)
	root.add_child(layer)
	for i in 30:
		await process_frame
	var wp := DisplayServer.window_get_position() - sp
	var ws := DisplayServer.window_get_size()
	print("STREAMVID_WIN %d %d %d %d screen=%dx%d scale=%.2f" % [wp.x, wp.y, ws.x, ws.y, ss.x, ss.y, DisplayServer.screen_get_scale(ps)])
	# 바깥 녹화가 붙을 시간
	var t_wait := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_wait < 4000:
		await process_frame
	AudioServer.add_bus_effect(0, rec)
	rec.set_recording_active(true)
	var audio_start := Time.get_unix_time_from_system()
	white.color = Color.WHITE
	var flash_unix := Time.get_unix_time_from_system()
	var tf := Time.get_ticks_msec()
	while Time.get_ticks_msec() - tf < 200:
		await process_frame
	white.color = Color.BLACK
	var game: Node = load("res://scenes/stream.tscn").instantiate()
	game.set_script(load("res://_capture/stream_play_main.gd"))
	# 흰 화면 1초 뒤 = 게임 시작 = clip0
	while Time.get_unix_time_from_system() < flash_unix + 1.0:
		await process_frame
	layer.queue_free()
	root.add_child(game)
	current_scene = game
	var clip_unix := Time.get_unix_time_from_system()
	game.clip0 = Time.get_ticks_msec()
	game.clip_on = true
	game.mark("clip_start")
	while is_instance_valid(game) and game.ct() < CLIP + 1.5:
		await process_frame
		var p = game.player
		if is_instance_valid(p) and not p.alive:
			game.mark("player_died")
			break
	game.mark("clip_end", {"kills": game.kills, "score": game.score, "sector": game.sector, "distance": int(game.distance)})
	rec.set_recording_active(false)
	var wav := rec.get_recording()
	if wav:
		wav.save_to_wav(ProjectSettings.globalize_path(out + "/session_audio.wav"))
	var f := FileAccess.open(out + "/events.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"audio_start_unix": audio_start, "flash_unix": flash_unix, "clip_unix": clip_unix,
		"clip_seconds": CLIP, "window": [wp.x, wp.y, ws.x, ws.y], "events": game.log_rows}, "  "))
	f.close()
	print("STREAMVID_DONE")
	quit()
