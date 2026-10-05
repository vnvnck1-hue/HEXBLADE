extends SceneTree
## 감염 오염물 확인 캡처 (docs/infestation.md): 방 탐색 본편(main.tscn)을 띄워
##  1. 구석 무더기 몇 곳을 전체 화면 + 확대(zoom_*)로 찍고
##  2. 한 무더기를 탄으로 쏘아 터뜨리며 체액이 튀는 순간을 연속으로 찍고 (pop_*)
##  3. 다 터진 잔해 → 청소 도중 → 청소 끝을 찍는다 (clean_*).
## godot --path . -s _capture/infest_show.gd -- --seed=4 --godmode [--out=DIR] [--n=4]

const CROP := Vector2i(640, 460)

var out := "res://output/infest-20261005"
var count := 4
var main: Main
var close := false
var ccam: Camera3D


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--n="):
			count = int(a.substr(4))
		elif a == "--close":
			close = true
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _shot(name: String, focus: Vector3) -> void:
	if close:
		name = "close_" + name
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out.path_join(name + ".png"))
	var vp := root.get_visible_rect().size
	var cam: Camera3D = ccam if close else main.camera
	var c := cam.unproject_position(focus) * Vector2(img.get_size()) / vp
	var r := Rect2i(Vector2i(c) - CROP / 2, CROP)
	r.position = r.position.clamp(Vector2i.ZERO, img.get_size() - CROP)
	img.get_region(r).save_png(out.path_join("zoom_" + name + ".png"))
	print("saved ", name)


func _park(n: InfestNest) -> void:
	var p := main.player
	var to := n.global_position + Vector3(2.4, 0, 1.6)
	var q := main.push_out(to, 0.5)
	p.global_position = q
	p.velocity = Vector3.ZERO
	main.camera.snap(n.global_position)
	_aim(n.global_position)


## --close: 게임 카메라 대신 무더기 앞 비스듬히 위의 고정 카메라로 찍는다 (파일 이름 앞에 close_)
func _aim(pos: Vector3) -> void:
	if not close:
		return
	if ccam == null:
		ccam = Camera3D.new()
		ccam.fov = 38.0
		root.add_child(ccam)
	var at := pos + Vector3(0, 0.25, 0)
	ccam.global_position = at + Vector3(0.6, 2.6, 3.4)
	ccam.look_at(at, Vector3.UP)
	ccam.make_current()


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await _frames(40)
	var inf := Infestation.inst
	print("nests: ", inf.nests.size() if inf else -1)
	if inf == null or inf.nests.is_empty():
		quit(1)
		return
	main.player.invuln = 9999.0
	# 큰 무더기부터
	var list := inf.nests.duplicate()
	list.sort_custom(func(a, b): return a.cysts.size() > b.cysts.size())
	for i in mini(count, list.size()):
		var n: InfestNest = list[i]
		_park(n)
		await _frames(40)
		_shot("nest_%d" % i, n.global_position + Vector3(0, 0.3, 0))
	# 터뜨리기
	var n: InfestNest = list[0]
	_park(n)
	await _frames(30)
	var focus := n.global_position + Vector3(0, 0.3, 0)
	var dir := (n.global_position - main.player.global_position)
	dir.y = 0
	dir = dir.normalized()
	var k := 0
	var order := n.cysts.duplicate()
	order.sort_custom(func(a, b): return a.s > b.s)
	n.take_hit(1, dir, order[0].center() - dir * order[0].radius())
	await _frames(3)
	_shot("hit_0", focus)
	for c in order:
		if c.popped or c.pop_t >= 0.0:
			continue
		n._damage(c, c.hp, dir)
		if c.s > 0.9 and k < 3:
			for f in 6:
				OS.delay_msec(30)      # 히트스탑은 실제 시간 기준 — 캡처가 빨리 돌아도 멈춤이 풀리게
				await _frames(2)
				_shot("pop_%d_%d" % [k, f], focus)
			k += 1
		await _frames(4)
	await _frames(40)
	_shot("splash_after", focus)
	var rem: InfestRemains = null
	for m in main.get_tree().get_nodes_in_group(DroneMess.GROUP):
		if m is InfestRemains:
			rem = m
	print("remains: ", rem != null)
	if rem:
		_aim(rem.global_position)
		_shot("clean_0", rem.global_position)
		rem.clean(rem.work_max * 0.5, main.player.global_position + Vector3(0, 0.8, 0))
		await _frames(30)
		_shot("clean_1", rem.global_position)
		rem.clean(rem.work_max, main.player.global_position + Vector3(0, 0.8, 0))
		await _frames(40)
		_shot("clean_2", focus)
	quit()
