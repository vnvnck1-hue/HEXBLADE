extends SceneTree
## 캡처: 거미 보스 SHIPWRIGHT 모델 · 걸음 · 카메라 확인.
##  orbit  보스 둘레를 도는 근접 카메라 (모델 · 다리 IK 확인)
##  game   실제 게임 카메라
## 실행: tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/spider_show.gd -- --bot --show --out=output/폴더 [--mode=orbit|game|both] [--secs=20] [--every=10] [--pat=이름]
##  --pat 을 주면 확인 모드 대신 그 패턴을 되풀이한다 (web · ambush · stalk · brood · drop · gatling · skitter · web_net)

var out := "output/spider-boss-20261001/cap"
var mode := "both"
var secs := 20.0
var every := 10
var pat := ""
var f := 0
var t := 0.0
var main: Node
var cam: Camera3D
var ang := 0.0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--mode="):
			mode = a.substr(7)
		elif a.begins_with("--secs="):
			secs = float(a.substr(7))
		elif a.begins_with("--every="):
			every = int(a.substr(8))
		elif a.begins_with("--pat="):
			pat = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out))
	main = load("res://scenes/spider.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	cam = Camera3D.new()
	cam.fov = 40.0
	cam.far = 400.0
	root.add_child(cam)


func _save(tag: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://%s/%s_%04d.png" % [out, tag, f])


func _process(dt: float) -> bool:
	t += dt
	f += 1
	var boss = main.get("boss")
	if boss == null:
		return false
	if pat != "" and boss.st == 1 and boss.pat == "" and boss.rest > 0.3:
		boss.order = [pat]
		boss.pat_i = -1
		boss.rest = 0.2
	var orbit := mode == "orbit" or (mode == "both" and fmod(t, 16.0) < 8.0)
	if orbit and t > 1.0:
		ang += dt * 0.35
		var c: Vector3 = boss.focus_point()
		cam.current = true
		cam.global_position = c + Vector3(cos(ang) * 17.0, 7.5, sin(ang) * 17.0)
		cam.look_at(c + Vector3(0, -0.5, 0), Vector3.UP)
	else:
		(main.get("camera") as Camera3D).current = true
	if t > 1.0 and f % every == 0:
		_save("orbit" if orbit else "game")
	return t > secs
