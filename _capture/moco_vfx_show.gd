extends SceneTree
## mo.co 무드 VFX 확인 캡처 (docs/moco-vfx-claude.md). 본편 방에서 같은 seed·카메라로 효과별 시점을 찍어 시트로 묶는다.
##  normal_XXms · heavy_XXms · slash / slash_heavy · numbers · stun · shield / shield_hit · link · vortex
## powershell -File tools\godot.ps1 wait --fixed-fps 60 --resolution 1280x800 -s res://_capture/moco_vfx_show.gd -- --seed=4 [--vfx=old] [--tag=new]
## (--fixed-fps 60: 한 프레임 = 1/60초라 효과 시점을 프레임 수로 맞춘다)
const OUT := "res://output/moco-vfx-20261004/"

var main: Main
var tag := "new"
var shots: Array = []     # [이름, Image]


func _initialize() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(OUT + tag + "_" + name + ".png")
	shots.append([name, img])


func _enemy(kind, at: Vector3) -> Enemy:
	var e: Enemy = kind.new()
	var pos: Vector3 = main.map.push_out(at, 1.0)
	if e is TrainingDummy:
		(e as TrainingDummy).anchor = pos
		(e as TrainingDummy).immortal = true
	main.world.add_child(e)
	e.global_position = pos
	return e


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
	if not MocoFX.on and tag == "new":
		tag = "old"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	change_scene_to_file("res://scenes/main.tscn")
	await _frames(40)
	main = current_scene as Main
	main.player.invuln = 9999.0
	main.hud.visible = false
	var c := main.player.global_position
	var d1 := _enemy(TrainingDummy, c + Vector3(3.2, 0, -0.6))
	var d2 := _enemy(TrainingDummy, c + Vector3(-3.0, 0, -0.4))
	var cr := _enemy(Crawler, c + Vector3(0.4, 0, -3.4))
	await _frames(90)
	cr.process_mode = Node.PROCESS_MODE_DISABLED
	main.camera.snap(c)
	main.player.aim_point = c + Vector3(3, 0, -0.6)
	await _frames(10)
	# 1) 일반 타격 (총알) — 0 / 3 / 7 / 12 프레임 (0 · 50 · 117 · 200ms)
	var hp := d1.global_position + Vector3(-0.3, 1.0, 0.2)
	d1.take_hit(1, Vector3(1, 0, -0.2).normalized(), hp, "bullet")
	await _shot("normal_000ms")
	var acc := 0
	for f in [3, 4, 5]:
		await _frames(f)
		acc += f
		await _shot("normal_%03dms" % roundi(acc * 1000.0 / 60.0))
	await _frames(30)
	# 2) 강타 (검)
	d1.take_hit(3, Vector3(1, 0, -0.2).normalized(), hp, "slash")
	await _shot("heavy_000ms")
	await _frames(4)
	await _shot("heavy_067ms")
	await _frames(6)
	await _shot("heavy_167ms")
	await _frames(40)
	# 3) 검 궤적: 가로 베기 · 내려찍기(강타)
	FX.slash(main.player, _yaw(), 0)
	await _frames(3)
	await _shot("slash")
	await _frames(30)
	FX.slash(main.player, _yaw(), 2)
	await _frames(4)
	await _shot("slash_heavy")
	await _frames(30)
	# 4) 피해 숫자 연사 (합산) + 강타 숫자
	for i in 6:
		d2.take_hit(1, Vector3(-1, 0, 0), d2.global_position + Vector3(0.3, 1.0, 0), "bullet")
		await _frames(2)
	d1.take_hit(5, Vector3(1, 0, 0), hp, "slash")
	await _frames(6)
	await _shot("numbers")
	await _frames(40)
	# 5) 경직 진입 STUN!
	d2.stagger(Vector3(-1, 0, 0), 1.1)
	await _frames(8)
	await _shot("stun")
	await _frames(60)
	# 6) 보호막 + 연결
	var noz := Node3D.new()
	main.world.add_child(noz)
	noz.global_position = c + Vector3(-1.6, 1.6, 1.2)
	var sh := DroneFX.Shield.new()
	sh.life = 10.0
	main.player.add_child(sh)
	DroneFX.tether(noz, main.player, 0.35)
	await _frames(6)
	await _shot("link")
	await _frames(30)
	await _shot("shield")
	sh.hit = 1.0
	sh.pop(Vector3(-1, 0, 0.3))
	await _frames(3)
	await _shot("shield_hit")
	await _frames(30)
	# 7) 볼텍스 (실제 반지름 8m, 끌어당김 0.75초)
	DroneFX.vortex_disc(main.player, 8.0, 0.75)
	await _frames(24)
	await _shot("vortex")
	await _frames(40)
	_sheet()
	print("MOCO VFX SHOW saved ", shots.size())
	quit()


func _sheet() -> void:
	var cols := 4
	var w := 640
	var h := 400
	var rows := ceili(shots.size() / float(cols))
	var sheet := Image.create(w * cols, h * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.07, 0.13))
	for i in shots.size():
		var im: Image = (shots[i][1] as Image).duplicate()
		im.resize(w, h)
		sheet.blit_rect(im, Rect2i(0, 0, w, h), Vector2i((i % cols) * w, (i / cols) * h))
	sheet.save_png(OUT + tag + "_sheet.png")


## 플레이어 → 조준점 방향 각 (Player 의 aim_yaw 와 같은 식)
func _yaw() -> float:
	var d := main.player.aim_point - main.player.global_position
	return atan2(-d.x, -d.z)
