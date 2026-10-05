class_name Hud
extends CanvasLayer
## 체력 · 웨이브 · 회피 게이지 · 조준점 · 결과 메시지 · 콤보 점수 · 궁극기 락온 표시.

var root: Control
var hp_box: HBoxContainer
var wave_label: Label
var count_label: Label
var dash_bar: ProgressBar
var boost_bar: ProgressBar
var boost_label: Label
var laser_bar: ProgressBar
var energy_icons: AmmoIcons
var missile_icons: AmmoIcons
var ult_label: Label
var ammo_label: Label
var ammo_bar: ProgressBar
var flash_rect: ColorRect
var center: Label
var sub: Label
var hint: Label
var vignette: ColorRect
var cross: Control
var hp_shown := -1
var minimap: Control
var font: Font
var combo_box: VBoxContainer
var combo_label: Label
var combo_sub: Label
var combo_bar: ProgressBar
var score_label: Label
var gain_label: Label
var ult_overlay: ColorRect
var ult_header: Label
var ult_timer: ProgressBar
var ult_k := 0.0
var ult_on := false
var lock_flash_t := 0.0
var legacy_left: VBoxContainer
var energy_slot: Control       # LEGACY 배치에서 에너지 아이콘 줄이 놓일 자리
var missile_slot: Control
var presets: HudPresets
var combo_meter: ComboMeter
const HINT_FULL := "WASD 이동   좌클릭 검   우클릭 사격   T 재장전   좌+우클릭 유지 충전 레이저   Space 회피(끝날 때 다시: 2단)   Shift 부스터   R 유지 락온 미사일   V 카메라   F5 재시작   H HUD"
## 프리셋은 버튼마다 키를 붙여 두므로 안내 줄에는 나머지만 남긴다
const HINT_SHORT := "WASD 이동   Space 중 검: 일격참 · 끝날 때 다시 → 검: 휠윈드 · 누른 채 이동: 청소   E 도약 내려찍기   V 카메라   F5 재시작   H HUD 프리셋"


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var th := Theme.new()
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Apple SD Gothic Neo", "Noto Sans CJK KR", "sans-serif"])
	f.font_weight = 700
	th.default_font = f
	font = f
	th.default_font_size = 18
	root.theme = th
	add_child(root)

	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)
	vignette = ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.color = Color(1, 0.1, 0.3, 0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vignette)

	var top := MarginContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	for s in ["left", "right", "top"]:
		top.add_theme_constant_override("margin_" + s, 22)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	row.add_child(left)
	legacy_left = left
	left.add_child(_label("ARMOR", 13, Color(0.7, 0.68, 0.95)))
	hp_box = HBoxContainer.new()
	hp_box.add_theme_constant_override("separation", 5)
	left.add_child(hp_box)
	left.add_child(_label("DODGE  [Space]", 13, Color(0.7, 0.68, 0.95)))
	dash_bar = ProgressBar.new()
	dash_bar.custom_minimum_size = Vector2(150, 8)
	dash_bar.show_percentage = false
	dash_bar.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.2, 0.8)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Pal.CYAN
	dash_bar.add_theme_stylebox_override("background", bg)
	dash_bar.add_theme_stylebox_override("fill", fg)
	left.add_child(dash_bar)
	boost_label = _label("BOOST  [Shift]", 13, Color(0.7, 0.68, 0.95))
	left.add_child(boost_label)
	boost_bar = _bar(Color("ffb040"))
	left.add_child(boost_bar)
	# 기본 총기 탄창: 30발마다 재장전 (T, 비면 자동)
	ammo_label = _label("AMMO  30 / 30  [T]", 13, Color(0.7, 0.68, 0.95))
	left.add_child(ammo_label)
	ammo_bar = _bar(Color("ffe070"))
	left.add_child(ammo_bar)
	left.add_child(_label("LASER  [좌+우클릭 유지]", 13, Color(0.7, 0.68, 0.95)))
	laser_bar = _bar(Color.WHITE)
	left.add_child(laser_bar)
	# 한정 재화: 최대치만큼 칸이 반투명하게 늘 보이고, 가진 만큼 불투명하게 켜진다
	energy_icons = AmmoIcons.new()
	energy_icons.setup("energy", Player.ENERGY_MAX, Color("5af0ff"), Vector2(18, 26))
	energy_slot = Control.new()
	energy_slot.custom_minimum_size = energy_icons.custom_minimum_size
	left.add_child(energy_slot)
	ult_label = _label("MISSILE  [R]", 13, Color(0.7, 0.68, 0.95))
	left.add_child(ult_label)
	missile_icons = AmmoIcons.new()
	missile_icons.setup("missile", Player.MISSILE_MAX, Color("ffa040"), Vector2(14, 26))
	missile_slot = Control.new()
	missile_slot.custom_minimum_size = missile_icons.custom_minimum_size
	left.add_child(missile_slot)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var right := VBoxContainer.new()
	right.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_child(right)
	wave_label = _label("WAVE 1", 22, Color.WHITE)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(wave_label)
	count_label = _label("", 15, Color(1, 0.55, 0.65))
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(count_label)
	minimap = Control.new()
	minimap.custom_minimum_size = Vector2(228, 228)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	right.add_child(minimap)

	# 콤보 · 점수 (미니맵 아래)
	combo_box = VBoxContainer.new()
	combo_box.add_theme_constant_override("separation", 0)
	combo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(combo_box)
	score_label = _label("SCORE  0", 17, Color(0.85, 0.9, 1.0))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combo_box.add_child(score_label)
	combo_label = _label("", 52, Color.WHITE)
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combo_label.add_theme_constant_override("outline_size", 8)
	combo_label.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.18))
	combo_box.add_child(combo_label)
	combo_sub = _label("", 15, Color(1, 0.85, 0.5))
	combo_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combo_box.add_child(combo_sub)
	combo_bar = _bar(Color("ffd060"))
	combo_bar.custom_minimum_size = Vector2(228, 5)
	combo_box.add_child(combo_bar)
	gain_label = _label("", 16, Color(1, 0.95, 0.7))
	gain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combo_box.add_child(gain_label)

	# 궁극기 락온 화면: 어두운 가장자리 + 주사선 + 상단 안내와 남은 시간
	ult_overlay = ColorRect.new()
	ult_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ult_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var osh := Shader.new()
	osh.code = """
shader_type canvas_item;
uniform float k = 0.0;
void fragment() {
	vec2 uv = UV - 0.5;
	float v = smoothstep(0.3, 0.8, length(uv * vec2(1.0, 1.25)));
	float scan = 0.5 + 0.5 * sin(FRAGCOORD.y * 1.7 + TIME * 24.0);
	vec3 c = mix(vec3(0.0, 0.02, 0.07), vec3(0.4, 0.0, 0.06), v);
	COLOR = vec4(c, k * (0.16 + v * 0.55 + scan * 0.05));
}
"""
	var om := ShaderMaterial.new()
	om.shader = osh
	ult_overlay.material = om
	ult_overlay.visible = false
	root.add_child(ult_overlay)
	root.move_child(ult_overlay, 2)
	ult_header = _label("LOCK-ON  ·  포인터로 적을 훑고 R 을 떼면 발사", 22, Color("ff6a5a"))
	ult_header.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ult_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ult_header.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ult_header.position.y = 70
	ult_header.add_theme_constant_override("outline_size", 6)
	ult_header.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.03))
	ult_header.visible = false
	root.add_child(ult_header)
	ult_timer = _bar(Color("ff5a4a"))
	ult_timer.custom_minimum_size = Vector2(360, 6)
	ult_timer.set_anchors_preset(Control.PRESET_CENTER_TOP)
	ult_timer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ult_timer.position = Vector2(-180, 104)
	ult_timer.size = Vector2(360, 6)
	ult_timer.visible = false
	root.add_child(ult_timer)

	center = _label("", 54, Color.WHITE)
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BOTH
	center.position.y -= 60
	center.add_theme_constant_override("outline_size", 10)
	center.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.18))
	root.add_child(center)
	sub = _label("", 20, Color(0.85, 0.85, 1.0))
	sub.set_anchors_preset(Control.PRESET_CENTER)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.position.y += 10
	sub.add_theme_constant_override("outline_size", 6)
	sub.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.18))
	root.add_child(sub)

	hint = _label(HINT_FULL, 14, Color(0.75, 0.75, 0.95, 0.85))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -44
	hint.offset_bottom = -18
	root.add_child(hint)

	# 플레이어 상태 프리셋 (H). 아이콘 줄은 프리셋이 정한 자리로 매 프레임 옮긴다
	presets = HudPresets.new(self)
	root.add_child(presets)
	root.add_child(energy_icons)
	root.add_child(missile_icons)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hud="):
			var v := a.substr(6).to_upper()
			var i := HudPresets.NAMES.find(v)
			HudPresets.current = i if i >= 0 else clampi(int(v), 0, HudPresets.NAMES.size() - 1)
	_apply_preset()

	cross = Control.new()
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.draw.connect(_draw_cross)
	root.add_child(cross)
	# 타격 콤보 점수 (화면 왼쪽). 예전 처치 콤보 숫자는 이것으로 대신한다
	combo_meter = ComboMeter.new()
	root.add_child(combo_meter)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.physical_keycode == KEY_H:
		var n := HudPresets.NAMES.size()
		HudPresets.current = (HudPresets.current + (n - 1 if k.shift_pressed else 1)) % n
		_apply_preset()
		banner("HUD  %d · %s" % [HudPresets.current + 1, HudPresets.NAMES[HudPresets.current]], Color(0.8, 0.95, 1.0), HudPresets.DESCS[HudPresets.current] + "   (H 다음 · Shift+H 이전)")
		get_viewport().set_input_as_handled()


func _apply_preset() -> void:
	var legacy := HudPresets.current == HudPresets.LEGACY
	legacy_left.modulate.a = 1.0 if legacy else 0.0
	hint.text = HINT_FULL if legacy else HINT_SHORT
	var icons := legacy or HudPresets.current in [HudPresets.CORNERS, HudPresets.TACTICAL]
	energy_icons.visible = icons
	missile_icons.visible = icons
	var art := CalmHud.active()
	for node in [wave_label, count_label, minimap, combo_box]:
		node.visible = not art


## 아이콘 줄 위치: LEGACY 는 세로 나열 속 빈 자리, 나머지는 프리셋이 정한 곳
func _place_icons() -> void:
	if not energy_icons.visible:
		return
	if HudPresets.current == HudPresets.LEGACY:
		energy_icons.scale = Vector2.ONE
		missile_icons.scale = Vector2.ONE
		energy_icons.position = energy_slot.get_global_rect().position - root.get_global_rect().position
		missile_icons.position = missile_slot.get_global_rect().position - root.get_global_rect().position
		return
	var sl := presets.icon_slots()
	if sl.is_empty():
		return
	energy_icons.scale = Vector2.ONE * float(sl.escale)
	missile_icons.scale = Vector2.ONE * float(sl.mscale)
	energy_icons.position = sl.energy
	missile_icons.position = sl.missile


func _bar(c: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(150, 8)
	b.show_percentage = false
	b.max_value = 1.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.2, 0.8)
	var fg := StyleBoxFlat.new()
	fg.bg_color = c
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


func _label(text: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _draw_cross() -> void:
	var m := Main.inst
	if m == null or m.player == null or not m.player.alive:
		return
	var pl := m.player
	var now := Time.get_ticks_msec()
	# 락온한 적: 붉은 괄호가 크게 나타났다 조여 들고, 회전하는 마름모와 LOCK 표시
	for en in pl.locks:
		if not is_instance_valid(en) or not (en as Enemy).alive:
			continue
		var wp: Vector3 = (en as Enemy).global_position + Vector3(0, 1.0, 0)
		if m.camera.is_position_behind(wp):
			continue
		var sp := m.camera.screen_pos(wp)
		var age: float = (now - int(pl.lock_times.get((en as Enemy).get_instance_id(), now))) / 1000.0
		var k := clampf(age / 0.14, 0.0, 1.0)
		var big := clampf((en as Enemy).radius / 0.62, 1.0, 3.0)
		var half := lerpf(90.0, 34.0, ease(k, 0.4)) * big * (1.0 + sin(age * 12.0) * 0.05)
		var lc := Color(1, 0.18, 0.2).lerp(Color.WHITE, (1.0 - k) * 0.8)
		# 어두운 바탕선을 먼저 깔아 밝은 배경에서도 또렷하게
		_brackets(sp, half, 14.0, Color(0.05, 0, 0.02, 0.75), 8.0)
		_brackets(sp, half, 14.0, lc, 4.0)
		var rot := age * 3.0
		var dia := PackedVector2Array()
		for i in 5:
			dia.append(sp + Vector2(cos(rot + i * PI * 0.5), sin(rot + i * PI * 0.5)) * 15.0)
		cross.draw_polyline(dia, Color(0.05, 0, 0.02, 0.7), 6.0, true)
		cross.draw_polyline(dia, lc, 3.0, true)
		cross.draw_circle(sp, 4.0, lc)
		# 머리 위 순번 표 (락온 순서 = 미사일 순서)
		var idx := pl.locks.find(en) + 1
		var tag := sp + Vector2(0, -half - 22)
		var tri := PackedVector2Array([tag + Vector2(-11, -6), tag + Vector2(11, -6), tag + Vector2(0, 8)])
		cross.draw_colored_polygon(tri, lc)
		cross.draw_string(font, tag + Vector2(-30, -12), "LOCK %d" % idx, HORIZONTAL_ALIGNMENT_CENTER, 60, 16, lc)
		if k < 1.0:
			cross.draw_circle(sp, lerpf(10.0, 70.0, k) * big, Color(1, 0.35, 0.3, (1.0 - k) * 0.7), false, 4.0)
	if pl.ult_aiming:
		# 자석 조준: 실제 마우스 자리에서 달라붙은 조준점까지 가는 끈
		if pl.ult_raw.distance_to(pl.ult_ptr) > 6.0:
			cross.draw_dashed_line(pl.ult_raw, pl.ult_ptr, Color(1, 0.55, 0.5, 0.75), 2.0, 7.0, true)
			cross.draw_arc(pl.ult_raw, 6.0, 0, TAU, 16, Color(1, 0.8, 0.75, 0.8), 2.0, true)
		_draw_lock_reticle(pl.ult_ptr, pl.locks.size())
		return
	var p := cross.get_local_mouse_position()
	if m.capture_mode:
		p = m.camera.screen_pos(m.player.aim_point)
	var c := Color(0.55, 1.0, 1.0, 0.9)
	cross.draw_arc(p, 11, 0, TAU, 24, c, 2.0, true)
	cross.draw_circle(p, 2.0, c)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		cross.draw_line(p + d * 15, p + d * 21, c, 2.0, true)
	# 탄창: 조준점 오른쪽 아래 남은 탄 수 · 재장전 중에는 조준 원 둘레로 진행 호
	if pl.reload_t > 0.0:
		cross.draw_arc(p, 26, -PI * 0.5, -PI * 0.5 + TAU * pl.reload_k(), 40, Color("ffd070"), 3.0, true)
		cross.draw_string(font, p + Vector2(18, 34), "RELOAD", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("ffd070"))
	else:
		var ac := Color("ff6a6a") if pl.mag <= 5 else Color(0.85, 1.0, 1.0, 0.85)
		cross.draw_string(font, p + Vector2(18, 30), str(pl.mag), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ac)


func _brackets(c: Vector2, half: float, ln: float, col: Color, w: float) -> void:
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner := c + Vector2(sx, sy) * half
			cross.draw_line(corner, corner - Vector2(sx, 0) * ln, col, w, true)
			cross.draw_line(corner, corner - Vector2(0, sy) * ln, col, w, true)


## 락온 크로스헤어: 회전하는 바깥 괄호 · 조준 원 · 락온 수
func _draw_lock_reticle(p: Vector2, count: int) -> void:
	var h := cross.size.y
	var r := Player.LOCK_PX * h / 800.0
	var t := Time.get_ticks_msec() / 1000.0
	var pulse := lock_flash_t / 0.15
	var c := Color(1, 0.3, 0.25).lerp(Color.WHITE, pulse)
	cross.draw_arc(p, r, 0, TAU, 48, Color(c.r, c.g, c.b, 0.9), 2.5, true)
	cross.draw_arc(p, r * 0.35, 0, TAU, 24, c, 2.0, true)
	cross.draw_circle(p, 2.5, Color.WHITE)
	# 회전하는 네 방향 눈금
	for i in 4:
		var a := t * 2.2 + i * PI * 0.5
		var d := Vector2(cos(a), sin(a))
		cross.draw_line(p + d * (r + 4), p + d * (r + 16), c, 3.0, true)
		cross.draw_arc(p, r + 9, a + 0.25, a + 0.75, 8, Color(c.r, c.g, c.b, 0.6), 2.0, true)
	for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		cross.draw_line(p + d * r * 0.5, p + d * r * 0.8, c, 2.0, true)
	var size := r * (1.25 + pulse * 0.3)
	_brackets(p, size, 12.0, c, 2.5)
	cross.draw_string(font, p + Vector2(size + 8, 6), "%d" % count, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, c)
	cross.draw_string(font, p + Vector2(size + 8, 22), "LOCK", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)


func _draw_minimap() -> void:
	var sz := minimap.size
	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.03, 0.03, 0.08, 0.72))
	minimap.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.4, 0.4, 0.7, 0.5), false, 1.0)
	draw_map(minimap, Rect2(Vector2.ZERO, sz))

func draw_map(canvas: Control, area: Rect2) -> void:
	var m := Main.inst
	if m == null or m.map == null or m.map.minimap_tex == null:
		return
	var sz := area.size
	var map := m.map
	var k := Vector2(sz.x / ArenaMap.W, sz.y / ArenaMap.H)
	canvas.draw_texture_rect(map.minimap_tex, area, false)
	var to_map := func(p: Vector3) -> Vector2:
		var c := Vector2(p.x / ArenaMap.CELL + ArenaMap.W * 0.5, p.z / ArenaMap.CELL + ArenaMap.H * 0.5)
		return area.position + c * k
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.get("prop"):
			canvas.draw_circle(to_map.call((e as Node3D).global_position), 1.6, Color(1, 0.65, 0.2))
		else:
			canvas.draw_circle(to_map.call((e as Node3D).global_position), 2.2, Color(1, 0.35, 0.45))
	if m.player:
		var pp: Vector2 = to_map.call(m.player.global_position)
		var ad := Vector2(m.player.aim_dir.x, m.player.aim_dir.z)
		canvas.draw_line(pp, pp + ad * 7.0, Color(0.6, 1, 1, 0.9), 1.5)
		canvas.draw_circle(pp, 3.2, Color(0.4, 1, 1))
	# 방 상태 표식
	for r in map.rooms:
		if not r.combat:
			continue
		var c: Vector3 = map.world_of(r.center)
		var cp: Vector2 = to_map.call(c)
		var seen: bool = map.discovered[map._idx(r.center)] == 1 or r.visited
		if not seen:
			continue
		match r.state:
			"idle": canvas.draw_circle(cp, 3.0, Color(1, 0.6, 0.8, 0.8), false, 1.2)
			"active": canvas.draw_circle(cp, 4.0 + sin(m.time * 8.0), Color(1, 0.3, 0.4), false, 1.6)
			"cleared": canvas.draw_circle(cp, 2.5, Color(0.5, 0.85, 1.0))


func _process(_dt: float) -> void:
	var m := Main.inst
	if m == null or m.player == null:
		return
	var p := m.player
	# 기존 세로 나열은 LEGACY 에서만 보인다 (다른 프리셋에서는 투명이라 갱신하지 않는다. 돌아오면 그 프레임에 바로 채운다)
	if HudPresets.current == HudPresets.LEGACY:
		if hp_shown != p.hp:
			hp_shown = p.hp
			for c in hp_box.get_children():
				c.queue_free()
			for i in Player.MAX_HP:
				var r := ColorRect.new()
				r.custom_minimum_size = Vector2(26, 12)
				r.color = Pal.P_LIGHT if i < p.hp else Color(0.18, 0.16, 0.3)
				hp_box.add_child(r)
		dash_bar.value = 1.0 - p.dash_cd / Player.DASH_CD
		_fill(dash_bar, Pal.CYAN if p.dash_cd <= 0.0 else Color(0.3, 0.45, 0.7))
		boost_bar.value = p.boost
		if p.overheated:
			_fill(boost_bar, Color("ff3a5a") if fmod(m.time, 0.3) < 0.15 else Color("802040"))
			boost_label.text = "BOOST  OVERHEAT"
		else:
			_fill(boost_bar, Color("ffd060") if p.boosting else Color("ffb040"))
			boost_label.text = "BOOST  [Shift]"
		if p.reload_t > 0.0:
			ammo_bar.value = p.reload_k()
			ammo_label.text = "AMMO  RELOADING…"
			ammo_label.modulate = Color("ffd070") if fmod(m.time, 0.3) < 0.15 else Color.WHITE
		else:
			ammo_bar.value = float(p.mag) / Player.MAG_SIZE
			ammo_label.text = "AMMO  %d / %d  [T]" % [p.mag, Player.MAG_SIZE]
			ammo_label.modulate = Color("ff8a8a") if p.mag <= 5 else Color.WHITE
		_fill(ammo_bar, Color("ffa040") if p.reload_t > 0.0 else Color("ffe070"))
		laser_bar.value = p.charge if p.charging else (0.0 if p.laser_cd > 0.0 else 1.0)
		var stage_c: Color = ChargeFX.STAGE_COLORS[mini(p.charge_stage, 3)]
		_fill(laser_bar, stage_c if p.charging else Color(0.4, 0.5, 0.8))
		ult_label.text = ("MISSILE  %d / %d  [R]" % [p.missiles, Player.MISSILE_MAX]) if p.missiles > 0 else "MISSILE  — 적이 떨어뜨린 탄을 주우세요"
		ult_label.modulate = Color("ffd070") if p.missiles > 0 and fmod(m.time, 0.8) < 0.4 else Color.WHITE
	energy_icons.set_count(p.energy)
	energy_icons.pending = Player.laser_cost(p.charge) if p.charging and p.charge >= Player.CHARGE_MIN else 0
	energy_icons.regen = p.energy_regen_k()
	missile_icons.set_count(_shown(p, "missile"))
	missile_icons.pending = p.ult_shot_count() if p.ult_aiming else 0
	wave_label.text = "ROOMS  %d / %d" % [m.rooms_cleared, m.combat_rooms()]
	if m.wave > 0:
		count_label.text = "WAVE %d / %d  ·  ENEMIES  %d" % [m.wave, ArenaMap.WAVES, m.enemies_left()]
	else:
		count_label.text = ("ENEMIES  %d" % m.enemies_left()) if m.active_room >= 0 else "탐색 중"
	_place_icons()
	cross.queue_redraw()
	minimap.queue_redraw()
	_update_combo(m)
	_update_ult(p)
	if CalmHud.active():
		ult_header.visible = false
		ult_timer.visible = false
	if m.time > 8.0 and m.state == Main.State.PLAY:
		# 프리셋은 버튼마다 키가 붙어 있으므로 안내 줄을 끝까지 걷어 낸다
		var hint_a := 0.35 if HudPresets.current == HudPresets.LEGACY else 0.0
		hint.modulate.a = move_toward(hint.modulate.a, hint_a, _dt)


## 막대 채움 색: 바뀔 때만 넣는다 (StyleBox 는 같은 값이어도 changed 를 내 다시 그린다)
func _fill(bar: ProgressBar, c: Color) -> void:
	var sb := bar.get_theme_stylebox("fill") as StyleBoxFlat
	if sb.bg_color != c:
		sb.bg_color = c


var _ctw: Tween


func message(big: String, small := "", col := Color.WHITE) -> Tween:
	if _ctw:
		_ctw.kill()
	center.text = big
	sub.text = small
	center.add_theme_color_override("font_color", col)
	center.reset_size()
	center.position = (root.size - center.size) * 0.5 + Vector2(0, -60)
	center.pivot_offset = center.size * 0.5
	sub.reset_size()
	sub.position = (root.size - sub.size) * 0.5 + Vector2(0, 20)
	center.modulate.a = 1.0
	sub.modulate.a = 1.0
	center.scale = Vector2(1.4, 1.4)
	_ctw = center.create_tween()
	_ctw.tween_property(center, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return _ctw


func banner(text: String, col: Color, small := "") -> void:
	var tw := message(text, small, col)
	tw.tween_interval(1.0)
	tw.tween_property(center, "modulate:a", 0.0, 0.4)
	tw.parallel().tween_property(sub, "modulate:a", 0.0, 0.4)


func screen_flash(c: Color, a: float) -> void:
	flash_rect.color = Color(c.r, c.g, c.b, a)
	var tw := flash_rect.create_tween().set_ignore_time_scale(true)
	tw.tween_property(flash_rect, "color:a", 0.0, 0.25)


func hurt_flash() -> void:
	vignette.color.a = 0.28
	var tw := vignette.create_tween()
	tw.tween_property(vignette, "color:a", 0.0, 0.35)


# ── 콤보 · 점수 ─────────────────────────────────────────

func _update_combo(m: Main) -> void:
	score_label.text = "SCORE  %d" % m.score
	if false and m.combo >= 2:   # 처치 콤보 숫자는 왼쪽 ComboMeter 로 옮겼다
		combo_label.text = "%d" % m.combo
		combo_sub.text = "COMBO  ·  BEST %d" % m.best_combo
		combo_bar.value = m.combo_t / Main.COMBO_TIME
		combo_box.modulate.a = 1.0
		var tier := clampf((m.combo - 2) / 18.0, 0.0, 1.0)
		combo_label.add_theme_color_override("font_color", Color(1, 1, 1).lerp(Color("ffb040"), tier * 0.7).lerp(Color("ff4a6a"), maxf(0.0, tier - 0.5)))
	else:
		combo_label.text = ""
		combo_sub.text = ""
		combo_bar.value = 0.0


func combo_pop(pts: int, source: String) -> void:
	var tag := ""
	match source:
		"slash": tag = "  검 x2"
		"phantom": tag = "  일격 x3"
	gain_label.text = "+%d%s" % [pts, tag]
	gain_label.modulate.a = 1.0
	var tw := gain_label.create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.6)
	tw.tween_property(gain_label, "modulate:a", 0.0, 0.4)
	combo_label.pivot_offset = combo_label.size * Vector2(1.0, 0.5)
	combo_label.scale = Vector2(1.45, 1.45)
	var ctw := combo_label.create_tween().set_ignore_time_scale(true)
	ctw.tween_property(combo_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func combo_break() -> void:
	gain_label.text = "COMBO BREAK"
	gain_label.modulate = Color(1, 0.4, 0.5, 1)
	var tw := gain_label.create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.6)
	tw.tween_property(gain_label, "modulate", Color(1, 1, 1, 0), 0.4)


## 월드 위치에 떠오르는 짧은 문구 (PERFECT · PIERCE 등)
func popup(text: String, col: Color, world_pos: Vector3) -> void:
	var m := Main.inst
	if m == null or m.camera == null or m.camera.is_position_behind(world_pos):
		return
	var l := _label(text, 30, col)
	l.add_theme_constant_override("outline_size", 7)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.04, 0.14))
	root.add_child(l)
	l.reset_size()
	var sp := m.camera.screen_pos(world_pos)
	l.position = sp - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(1.6, 1.6)
	var tw := l.create_tween().set_ignore_time_scale(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(l, "position:y", l.position.y - 46, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)


# ── 궁극기 락온 ─────────────────────────────────────────

func ult_mode(on: bool) -> void:
	ult_on = on
	if on:
		ult_overlay.visible = true
		ult_header.visible = true
		ult_timer.visible = true
		screen_flash(Color(1, 0.35, 0.3), 0.25)
	else:
		ult_header.visible = false
		ult_timer.visible = false
		screen_flash(Color(1, 0.9, 0.7), 0.3)


# ── 한정 재화 아이콘 ────────────────────────────────────

func _icons(kind: String) -> AmmoIcons:
	return energy_icons if kind == "energy" else missile_icons


## 아이콘에 보이는 개수 (궁극기 발사 중에는 아직 안 나간 미사일도 켜 두고 한 발씩 끈다)
func _shown(p: Player, kind: String) -> int:
	return p.energy if kind == "energy" else p.missiles + p.ult_queue


func ammo_gained(kind: String, n: int) -> void:
	var p := Main.inst.player
	var ic := _icons(kind)
	ic.set_count(_shown(p, kind))
	ic.gained(n)


func ammo_spent(kind: String, n: int) -> void:
	var p := Main.inst.player
	var ic := _icons(kind)
	ic.set_count(_shown(p, kind))
	ic.spent(n)


func ammo_denied(kind: String) -> void:
	_icons(kind).denied()


func lock_flash() -> void:
	lock_flash_t = 0.15
	screen_flash(Color(1, 0.2, 0.2), 0.08)


func _update_ult(p: Player) -> void:
	var rdt := get_process_delta_time() / maxf(Engine.time_scale, 0.01)
	lock_flash_t = maxf(0.0, lock_flash_t - rdt)
	ult_k = move_toward(ult_k, 1.0 if ult_on else 0.0, rdt * (8.0 if ult_on else 4.0))
	(ult_overlay.material as ShaderMaterial).set_shader_parameter("k", ult_k)
	if ult_k <= 0.0:
		ult_overlay.visible = false
	if ult_on:
		var left := p.ult_aim_left()
		ult_timer.value = left / Player.ULT_AIM_MAX
		ult_header.modulate.a = 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.02)
		ult_header.text = "LOCK-ON  %d  ·  포인터로 적을 훑고 R 을 떼면 발사" % p.locks.size()
		ult_header.reset_size()
		ult_header.position.x = (root.size.x - ult_header.size.x) * 0.5
