extends SceneTree
## 핸드 페인팅 질감 비교 씬: 플레이어 기체 · 크롤러 · 포탑을 게임과 같은 조명 아래 세우고 룩을 바꿔 본다.
## 대화형: powershell -File tools\godot.ps1 wait -s _capture/painted_look_show.gd
##   1~8 룩 전환 (7 = 하스스톤 식, 8 = 하스스톤 + 따뜻한 조명·색보정) · Space 회전 정지 · C 원경/근경
## 캡처:  ... -s _capture/painted_look_show.gd -- --shots=C:/path/dir   (룩마다 원경·근경 PNG 저장 후 종료)

const PL := preload("res://scripts/presentation/painted_look.gd")

## [이름, 프리셋, 외곽선]
const LOOKS := [
	["0_current", 0, false],
	["1_current_toon", 0, true],
	["2_stroke", 1, false],
	["3_painted", 2, true],
	["4_edge", 3, true],
	["5_oil", 4, false],
	["6_hearth", 5, false],
	["7_hearth_warm", 5, false],
]

var world: Node3D
var env: Environment
var sun: DirectionalLight3D
var spin: Node3D
var cam: Camera3D
var outline: ToonOutline
var label: Label
var look := 0
var close := false
var turning := true


func _initialize() -> void:
	world = Node3D.new()
	root.add_child(world)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.85)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.9
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 28, 0)
	sun.light_energy = 1.25
	sun.light_color = Color(1.0, 0.97, 1.0)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	world.add_child(sun)

	Build.box(world, Vector3(14, 0.2, 10), Vector3(0, -0.1, 0), Pal.FLOOR)
	Build.box(world, Vector3(1.2, 1.4, 1.2), Vector3(-4.2, 0.7, -2.2), Pal.OBSTACLE)
	Build.box(world, Vector3(2.4, 0.8, 1.0), Vector3(4.0, 0.4, -2.6), Pal.OBSTACLE)

	spin = Node3D.new()
	world.add_child(spin)
	var mech := Node3D.new()
	spin.add_child(mech)
	mech.scale = Vector3.ONE * 1.6
	mech.rotation_degrees.y = 200
	Build.robot_mech(mech)
	var cr := Node3D.new()
	world.add_child(cr)
	cr.position = Vector3(-2.8, 0, 0.6)
	cr.rotation_degrees.y = 140
	Build.crawler(cr)
	var tu := Node3D.new()
	world.add_child(tu)
	tu.position = Vector3(2.9, 0, 0.3)
	tu.rotation_degrees.y = -150
	Build.turret(tu)

	cam = Camera3D.new()
	world.add_child(cam)
	cam.current = true
	outline = ToonOutline.attach(cam)
	var ui := CanvasLayer.new()
	world.add_child(ui)
	label = Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 22)
	ui.add_child(label)
	_set_cam()
	_set_look.call_deferred(0)
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	if shots != "":
		_shoot.call_deferred(shots)


func _set_cam() -> void:
	if close:
		cam.fov = 30
		cam.look_at_from_position(Vector3(0, 4.6, 4.4), Vector3(0, 1.05, 0))
	else:
		cam.fov = 40
		cam.look_at_from_position(Vector3(0, 9.0, 7.6), Vector3(0, 0.6, -0.2))


func _set_look(i: int) -> void:
	look = i
	var l: Array = LOOKS[i]
	Pal.set_toon(l[2])
	PL.set_preset(world, cam, l[1])
	_warm(l[0] == "7_hearth_warm")
	label.text = "%d  %s   (1~8 룩 · Space 회전 · C 근경)" % [i + 1, l[0]]


## 하스스톤 식 조명: 노란 주광 · 자줏빛 환경광 · 채도 보정 (게임 조명 대비 차이를 보기 위한 시험값)
func _warm(on: bool) -> void:
	sun.light_color = Color(1.0, 0.94, 0.84) if on else Color(1.0, 0.97, 1.0)
	sun.light_energy = 1.3 if on else 1.25
	env.ambient_light_color = Color(0.58, 0.5, 0.8) if on else Color(0.5, 0.5, 0.85)
	env.adjustment_enabled = on
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.04


var _held := {}


func _pressed(k: Key) -> bool:
	var down := Input.is_physical_key_pressed(k)
	var was: bool = _held.get(k, false)
	_held[k] = down
	return down and not was


func _process(delta: float) -> bool:
	if turning:
		spin.rotation.y += delta * 0.5
	for i in LOOKS.size():
		if _pressed(KEY_1 + i):
			_set_look(i)
	if _pressed(KEY_SPACE):
		turning = not turning
	if _pressed(KEY_C):
		close = not close
		_set_cam()
	return false


func _shoot(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	turning = false
	label.visible = false
	for i in LOOKS.size():
		_set_look(i)
		for c in [false, true]:
			close = c
			_set_cam()
			for f in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.save_png("%s/%s_%s.png" % [dir, LOOKS[i][0], "close" if c else "wide"])
	quit()

