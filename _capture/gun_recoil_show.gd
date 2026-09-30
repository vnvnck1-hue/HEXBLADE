extends SceneTree
## 사격 팔 반동 · 총구 화염 · 순간 조명 확인: 실제 런 아레나에서 플레이어가 제자리 연사한다.
## godot --path . --fixed-fps 60 --resolution 1280x720 --write-movie DIR/f.png -s _capture/gun_recoil_show.gd

var game: Node
var cam: Camera3D


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	game = load("res://scenes/run.tscn").instantiate()
	root.add_child(game)
	await process_frame
	get_root().get_node("Run").map_view.want = false
	await create_timer(2.0).timeout
	game.hud.visible = false
	get_root().get_node("Run").map_view.visible = false
	var p: Node3D = game.player
	var aim := p.global_position + Vector3(6.0, 0, -3.0)
	# 옆 45° 가까운 카메라: 팔이 앞뒤로 움직이는 게 잘 보이게
	cam = Camera3D.new()
	root.add_child(cam)
	cam.fov = 40
	var c := p.global_position + Vector3(0, 1.0, 0)
	cam.look_at_from_position(c + Vector3(-1.5, 2.6, 4.6), c + Vector3(0.6, -0.2, -0.3))
	cam.current = true
	for i in 150:
		p.aim_point = aim
		p.aim_dir = (aim - p.global_position).normalized()
		if i % 5 == 0 and i < 110:
			p._fire()
		await physics_frame
	quit()
