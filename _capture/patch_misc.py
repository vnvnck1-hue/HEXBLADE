import io, os
os.chdir(os.path.join(os.path.dirname(__file__), "..", "scripts"))


def edit(p, pairs):
    s = io.open(p, encoding="utf-8").read()
    for a, b in pairs:
        assert a in s, (p, a[:80])
        s = s.replace(a, b)
    io.open(p, "w", encoding="utf-8", newline="\n").write(s)


# ── fx.gd: 몇 프레임 만에 끝나는 검광 ──
edit("fx.gd", [
    ('''	tw.tween_property(mat, "shader_parameter/progress", 1.0, 0.3)''',
     '''	# 0.05초 만에 호가 완성되고, 짧게 잔광이 남았다 사라진다
	tw.tween_property(mat, "shader_parameter/progress", 0.72, 0.05)
	tw.tween_property(mat, "shader_parameter/progress", 1.0, 0.14).set_ease(Tween.EASE_IN)'''),
    ('''	tw2.tween_property(gm, "albedo_color:a", 0.0, 0.3)''', '''	tw2.tween_property(gm, "albedo_color:a", 0.0, 0.2)'''),
])

# ── main.gd ──
edit("main.gd", [
    ('''var bot_path: Array[Vector3] = []''', '''var env: Environment
var sun: DirectionalLight3D
var _dark_tw: Tween
var bot_path: Array[Vector3] = []'''),
    ('''	var env := Environment.new()''', '''	env = Environment.new()'''),
    ('''	var sun := DirectionalLight3D.new()''', '''	sun = DirectionalLight3D.new()'''),
    ('''"restart": [KEY_R],''', '''"restart": [KEY_R, KEY_F5], "ult": [KEY_R, KEY_Q],'''),
    ('''	if event.is_action_pressed("restart"):
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()''', '''	# R: 전투 중에는 궁극기, 결과 화면에서는 재시작 (F5 는 언제나 재시작)
	var restart_now := event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F5 and event.is_pressed()
	if restart_now or (event.is_action_pressed("restart") and state != State.PLAY):
		Engine.time_scale = 1.0
		get_tree().reload_current_scene()'''),
    ('''	kills += 1
	hitstop(0.07)''', '''	kills += 1
	player.ult = minf(1.0, player.ult + Player.ULT_PER_KILL)
	hitstop(0.07)'''),
    ('''func hitstop(sec: float) -> void:''', '''## 최대 레이저 연출: 주변을 급격히 어둡게 해 빔 광원을 돋보이게 한다
func dramatic(on: bool) -> void:
	if _dark_tw:
		_dark_tw.kill()
	_dark_tw = create_tween().set_parallel(true)
	var d := 0.1 if on else 0.6
	_dark_tw.tween_property(sun, "light_energy", 0.08 if on else 1.25, d)
	_dark_tw.tween_property(env, "ambient_light_energy", 0.05 if on else 0.5, d)
	_dark_tw.tween_property(env, "background_color", Color(0.0, 0.0, 0.01) if on else Color(0.02, 0.02, 0.05), d)
	_dark_tw.tween_property(env, "glow_intensity", 1.1 if on else 0.5, d)
	_dark_tw.tween_property(env, "glow_hdr_threshold", 0.85 if on else 1.1, d)
	if on:
		hud.screen_flash(Color(0.85, 1.0, 1.0), 0.55)


func hitstop(sec: float) -> void:'''),
    # 자동 플레이: 궁극기 사용
    ('''		out.boost = bd > 8.5 and p.boost > 0.4''', '''		out.boost = bd > 8.5 and p.boost > 0.4
		out.ult = get_tree().get_nodes_in_group("enemies").size() >= 3'''),
])

# ── hud.gd: 궁 게이지, 충전 단계 색, 화면 섬광 ──
edit("hud.gd", [
    ('''var laser_bar: ProgressBar
''', '''var laser_bar: ProgressBar
var ult_bar: ProgressBar
var ult_label: Label
var flash_rect: ColorRect
'''),
    ('''	laser_bar = _bar(Color.WHITE)
	left.add_child(laser_bar)
''', '''	laser_bar = _bar(Color.WHITE)
	left.add_child(laser_bar)
	ult_label = _label("MISSILE  [R]", 13, Color(0.7, 0.68, 0.95))
	left.add_child(ult_label)
	ult_bar = _bar(Color("ffb040"))
	left.add_child(ult_bar)
'''),
    ('''	vignette = ColorRect.new()''', '''	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)
	vignette = ColorRect.new()'''),
    ('''	(laser_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = (Color.WHITE if p.charge >= 1.0 else Pal.CYAN) if p.charging else Color(0.4, 0.5, 0.8)''',
     '''	var stage_c: Color = ChargeFX.STAGE_COLORS[mini(p.charge_stage, 3)]
	(laser_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = stage_c if p.charging else Color(0.4, 0.5, 0.8)
	ult_bar.value = p.ult
	var uf := ult_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if p.ult >= 1.0:
		uf.bg_color = Color("ffe070") if fmod(m.time, 0.4) < 0.2 else Color("ff9a30")
		ult_label.text = "MISSILE  READY [R]"
	else:
		uf.bg_color = Color("a06a30")
		ult_label.text = "MISSILE  [R]"'''),
    ('''func hurt_flash() -> void:''', '''func screen_flash(c: Color, a: float) -> void:
	flash_rect.color = Color(c.r, c.g, c.b, a)
	var tw := flash_rect.create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, 0.25)


func hurt_flash() -> void:'''),
    ('''우클릭 유지 충전 레이저   Space 드릴 회피   Shift 부스터   E 검   V 카메라   R 재시작''', '''우클릭 유지 충전 레이저   Space 드릴 회피   Shift 부스터   E 검   R 미사일   V 카메라   F5 재시작'''),
])
print("ok")
