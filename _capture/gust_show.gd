extends SceneTree
## 기체 VFX(GustFX) 확인용: 실제 런 아레나에서 대시 · 부스터 · 광선검을 입력으로 흉내 내며 캡처.
## godot --path . --fixed-fps 60 -s res://_capture/gust_show.gd
var game: Node
var shots := 0

func _initialize() -> void:
	_run.call_deferred()

func _press(a: String, on: bool) -> void:
	if on:
		Input.action_press(a)
	else:
		Input.action_release(a)

func _run() -> void:
	game = load("res://scenes/run.tscn").instantiate()
	root.add_child(game)
	await process_frame
	get_root().get_node("Run").map_view.want = false
	await create_timer(2.2).timeout
	get_root().get_node("Run").map_view.visible = false
	var p: Player = game.player
	p.hp = 999
	# 대시
	_press("move_right", true)
	await create_timer(0.2).timeout
	_press("dash", true)
	await physics_frame
	_press("dash", false)
	for i in 4:
		for f in 3:
			await physics_frame
		await _save("gust_dash_%d" % i)
	await create_timer(0.3).timeout
	await _save("gust_dash_after")
	# 부스터
	_press("move_right", false)
	_press("move_up", true)
	_press("boost", true)
	for f in 4:
		await physics_frame
	await _save("gust_boost_0")
	for i in range(1, 3):
		await create_timer(0.25).timeout
		await _save("gust_boost_%d" % i)
	_press("boost", false)
	_press("move_up", false)
	await create_timer(0.8).timeout
	# 광선검
	for i in 4:
		_press("slash", true)
		await physics_frame
		_press("slash", false)
		for f in 4:
			await physics_frame
		await _save("gust_slash_%d" % i)
		await create_timer(0.12).timeout
	print("GUST_COUNT ", GustFX.count())
	quit()

func _save(title: String) -> void:
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png("res://_capture/gust/%s.png" % title)
	print("GUST_CAPTURE ", title, " ", err, " n=", GustFX.count())
