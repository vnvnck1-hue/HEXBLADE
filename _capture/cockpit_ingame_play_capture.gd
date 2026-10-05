extends SceneTree
## Observe real main-scene bot gameplay; never alter gauge, drone state or cutin clock.
var out := "res://_capture/cockpit_ingame_play_20261005"
var events: Array = []
var frames := 0
var seen := false
var ended_at := -1.0
var saved_before := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()

func _run() -> void:
	var game := load("res://scenes/main.tscn").instantiate() as Main
	root.add_child(game)
	current_scene = game
	var start := Time.get_ticks_msec()
	while is_instance_valid(game) and Time.get_ticks_msec() - start < 175000:
		await process_frame
		await RenderingServer.frame_post_draw
		var d := PartnerDrone.inst
		if not is_instance_valid(d):
			continue
		if not saved_before and game.time > 2.0:
			root.get_texture().get_image().save_png(out + "/before.png")
			saved_before = true
		var c = d.cutin
		if is_instance_valid(c):
			seen = true
			frames += 1
			var filename := "cutin_%03d.png" % frames
			var row := {"file":filename,"game_seconds":game.time,"real_ms":Time.get_ticks_msec()-start,"phase":c.ph,"cutin_seconds":c.t,"dock_seconds":c.dock_t,"drone_state":d.state,"gauge":d.gauge,"cleaned":d.cleaned,"alive":game.player.alive,"hp":game.player.hp}
			events.append(row)
			var err := root.get_texture().get_image().save_png(out + "/" + filename)
			if err != OK:
				push_error("GAMEPLAY_CAPTURE_SAVE " + str(err))
			print("GAMEPLAY_CUTIN " + JSON.stringify(row))
		elif seen:
			if ended_at < 0.0:
				ended_at = game.time
			if game.time - ended_at > 0.6:
				root.get_texture().get_image().save_png(out + "/after.png")
				break
		if not game.player.alive:
			print("GAMEPLAY_PLAYER_DIED before_cutin=" + str(not seen))
			break
	var f := FileAccess.open(out + "/capture.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"scene":"res://scenes/main.tscn","args":OS.get_cmdline_user_args(),"fixed_cutin_dt":CockpitCutin.fixed_dt,"captures":events}, "  "))
	f.close()
	print("GAMEPLAY_CAPTURE_RESULT cutin_frames=%d" % frames)
	quit(0 if frames > 0 else 1)
