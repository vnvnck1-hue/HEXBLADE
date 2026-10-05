class_name CalmHud
extends Control
## 채택된 차분한 만화풍 상단 HUD. 스킬과 드론 카드는 별도 모듈에서 그린다.

const PAPER := Color("f4f4eb")
const PANEL := Color(0.045, 0.085, 0.12, 0.94)
const BORDER := Color(0.35, 0.52, 0.61, 0.55)
const MINT := Color("91e5ac")
const CORAL := Color("ee8185")
const ORANGE := Color("f6a257")
const DIM := Color("a9bbc8")

var hud: Hud
var enabled := true
var portrait: Texture2D
var title_font := SystemFont.new()
var panel_style := StyleBoxFlat.new()
var map_style := StyleBoxFlat.new()
var enemy_style := StyleBoxFlat.new()
var has_boss := false
var elapsed := 0.0


func _init(h: Hud) -> void:
	hud = h
	enabled = not OS.get_cmdline_user_args().has("--hud-art=classic")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


static func active() -> bool:
	var main := Main.inst
	return main != null and main.hud != null and main.hud.presets != null and main.hud.presets.calm != null and main.hud.presets.calm.enabled and HudPresets.current == HudPresets.STRIKER


func _ready() -> void:
	portrait = load("res://assets/ui/calm_hud/mecha_bust.png") as Texture2D
	title_font.font_names = PackedStringArray(["Arial", "Liberation Sans", "Malgun Gothic", "sans-serif"])
	title_font.font_weight = 800
	title_font.font_italic = true
	panel_style.bg_color = PANEL
	panel_style.border_color = BORDER
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.shadow_color = Color(0.015, 0.03, 0.06, 0.35)
	panel_style.shadow_size = 2
	map_style.bg_color = Color(0.025, 0.055, 0.085, 0.98)
	map_style.border_color = PAPER
	map_style.set_border_width_all(1)
	map_style.set_corner_radius_all(5)
	enemy_style.bg_color = Color("172332")
	enemy_style.border_color = Color("091521")
	enemy_style.set_border_width_all(1)
	enemy_style.set_corner_radius_all(2)


func _process(dt: float) -> void:
	visible = enabled and HudPresets.current == HudPresets.STRIKER
	if not visible:
		return
	elapsed += dt / maxf(Engine.time_scale, 0.01)
	has_boss = false
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Enemy and e.is_boss:
			has_boss = true
			break
	queue_redraw()


func ui_scale() -> float:
	return clampf(size.y / 900.0, 0.7, 1.5)


func hero_rect() -> Rect2:
	var scale_ := ui_scale()
	var width := minf(495.0, size.x / scale_ * 0.32)
	return Rect2(Vector2(18, 150 if has_boss else 22) * scale_, Vector2(width, 136) * scale_)


func status_rect() -> Rect2:
	var scale_ := ui_scale()
	var width := minf(420.0, size.x / scale_ * 0.30)
	return Rect2(Vector2((size.x - width * scale_) * 0.5, (150 if has_boss else 16) * scale_), Vector2(width, 50) * scale_)


func minimap_rect() -> Rect2:
	var scale_ := ui_scale()
	return Rect2(Vector2(size.x - 18 * scale_ - 292 * scale_, 18 * scale_), Vector2(292, 254 if has_map() else 44) * scale_)


func has_map() -> bool:
	var m := Main.inst
	return m != null and m.map != null and m.map.minimap_tex != null


func _text(pos: Vector2, value: String, px: int, col := PAPER, right := false, heading := true) -> void:
	var face: Font = title_font if heading else hud.font
	if right:
		pos.x -= face.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string_outline(face, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 2, Color(0.02, 0.04, 0.06, 0.75))
	draw_string(face, pos, value, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _center(pos: Vector2, value: String, px: int, col := PAPER) -> void:
	pos.x -= title_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x * 0.5
	_text(pos, value, px, col)


func _frame(rect: Rect2) -> void:
	draw_style_box(panel_style, rect)
	# 큰 단색 면을 유지하는 낮은 대비의 사선 음영.
	var p := rect.position
	var end := rect.end
	draw_colored_polygon(PackedVector2Array([Vector2(end.x - 58, p.y + 1), end - Vector2(1, rect.size.y - 1), end - Vector2(24, 1), Vector2(end.x - 96, end.y - 1)]), Color(0.15, 0.23, 0.28, 0.11))


func _cell(pos: Vector2, extent: Vector2, color: Color, fill := 1.0) -> void:
	var skew := 9.0
	var pts := PackedVector2Array([pos + Vector2(skew, 0), pos + Vector2(extent.x + skew, 0), pos + extent, pos + Vector2(0, extent.y)])
	draw_colored_polygon(pts, Color("203d3e"))
	if fill > 0.01:
		var width := extent.x * clampf(fill, 0, 1)
		pts = PackedVector2Array([pos + Vector2(skew, 0), pos + Vector2(width + skew, 0), pos + Vector2(width, extent.y), pos + Vector2(0, extent.y)])
		draw_colored_polygon(pts, color)
		draw_line(pos + Vector2(skew + 2, 1), pos + Vector2(width + skew - 1, 1), Color(1, 1, 1, 0.2), 1, true)


func _draw_hero(p: Player) -> void:
	var rect := hero_rect()
	var scale_ := ui_scale()
	draw_set_transform(rect.position, 0, Vector2.ONE * scale_)
	var width := rect.size.x / scale_
	_frame(Rect2(Vector2.ZERO, Vector2(width, 136)))
	if portrait:
		draw_texture_rect(portrait, Rect2(-10, -23, 172, 172), false)
	_text(Vector2(172, 34), "HEXBLADE", 25)
	var hp_width := (width - 172 - 76 - 8 * 4) / Player.MAX_HP
	var shake := Vector2(sin(elapsed * 65), cos(elapsed * 71)) * hud.presets.hp_hit * 2.0
	for i in Player.MAX_HP:
		var at := Vector2(168 + i * (hp_width + 8), 50) + shake
		var on := i < p.hp
		var color := MINT if p.hp > 1 else CORAL.lerp(PAPER, 0.16 + 0.12 * sin(elapsed * 7))
		var trail := clampf(hud.presets.hp_trail - i, 0, 1)
		_cell(at, Vector2(hp_width, 26), color if on else Color(PAPER, 0.7), 1.0 if on else trail)
	_text(Vector2(width - 19, 73), "%d / %d" % [p.hp, Player.MAX_HP], 23, CORAL if p.hp <= 1 else PAPER, true)
	_text(Vector2(168, 115), "HOT" if p.overheated else "BOOST", 18, CORAL if p.overheated else ORANGE)
	for i in 3:
		_cell(Vector2(250 + i * 25, 96), Vector2(18, 18), CORAL if p.overheated else ORANGE, clampf(p.boost * 3 - i, 0, 1))
	for i in Player.ENERGY_MAX:
		_cell(Vector2(width - 90 + i * 23, 98), Vector2(14, 16), Color("68dbb8"), 1 if i < p.energy else 0)
	if p.phantom_t > 0:
		_text(Vector2(174, 133), "PIERCE  %.1f" % p.phantom_t, 11, CORAL)


func _draw_status(m: Main, p: Player) -> void:
	var rect := status_rect()
	var scale_ := ui_scale()
	draw_set_transform(rect.position, 0, Vector2.ONE * scale_)
	var width := rect.size.x / scale_
	# 보스 전용 씬은 기존처럼 방 진행을 표시하지 않는다.
	if has_map():
		_frame(Rect2(Vector2.ZERO, Vector2(width, 50)))
		_text(Vector2(23, 34), "ROOMS  %d / %d" % [m.rooms_cleared, m.combat_rooms()], 25)
		draw_line(Vector2(width * 0.53, 12), Vector2(width * 0.53, 38), BORDER, 1, true)
		_text(Vector2(width - 22, 34), "ENEMIES  %d" % m.enemies_left(), 24, CORAL, true)
	var row := 56.0 if has_map() else 0.0
	if p.ult_aiming or p.ult_winding():
		_frame(Rect2(width * 0.5 - 75, row, 150, 38))
		_center(Vector2(width * 0.5, row + 26), "LOCK x%d" % p.locks.size(), 22, DIM)
		if p.ult_aiming:
			draw_rect(Rect2(width * 0.5 - 59, row + 33, 118 * p.ult_aim_left() / Player.ULT_AIM_MAX, 2), CORAL)
	elif m.wave > 0:
		_frame(Rect2(width * 0.5 - 75, 56, 150, 30))
		_center(Vector2(width * 0.5, 78), "WAVE %d / %d" % [m.wave, ArenaMap.WAVES], 17, DIM)


func _draw_map(m: Main) -> void:
	var rect := minimap_rect()
	var scale_ := ui_scale()
	draw_set_transform(rect.position, 0, Vector2.ONE * scale_)
	var height := rect.size.y / scale_
	_frame(Rect2(0, 0, 292, height))
	if has_map():
		var map_area := Rect2(10, 10, 272, 210)
		draw_style_box(map_style, map_area)
		hud.draw_map(self, map_area.grow(-5))
	_text(Vector2(272, height - 9), "SCORE  %d" % m.score, 23, PAPER, true)
	if false and m.combo >= 2:   # 처치 콤보 숫자는 왼쪽 ComboMeter 로 옮겼다
		var combo_rect := Rect2(86, height + 9, 206, 80)
		_frame(combo_rect)
		_text(Vector2(278, height + 45), "%d" % m.combo, 34, ORANGE, true)
		_text(Vector2(278, height + 68), "COMBO · BEST %d" % m.best_combo, 14, DIM, true)
		draw_rect(Rect2(100, height + 77, 178, 3), Color("283944"))
		draw_rect(Rect2(100, height + 77, 178 * clampf(m.combo_t / Main.COMBO_TIME, 0, 1), 3), ORANGE)
	if hud.gain_label.modulate.a > 0.05 and not hud.gain_label.text.is_empty():
		_text(Vector2(282, height + 111), hud.gain_label.text, 15, Color(PAPER, hud.gain_label.modulate.a), true, false)


func enemy_rect(e: Enemy) -> Rect2:
	var m := Main.inst
	var world := e.global_position + Vector3(0, e.hp_bar_y + 0.1, 0)
	if m.camera.is_position_behind(world):
		return Rect2()
	var at := m.camera.screen_pos(world)
	var extent := Vector2(96, 12) * ui_scale()
	return Rect2(at - extent * 0.5, extent)


func _draw_enemies() -> void:
	draw_set_transform(Vector2.ZERO)
	var protected := [hero_rect(), status_rect().grow(4), minimap_rect(), RoundSkillDock.dock_rect(size).grow(5)]
	if is_instance_valid(PartnerDrone.inst):
		protected.append(DroneHud.panel_rect(size))
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or not e.alive or not e.landed or e.is_boss or e.prop or not is_instance_valid(e.hp_bar):
			continue
		var rect := enemy_rect(e)
		if not Rect2(Vector2.ZERO, size).encloses(rect) or rect.size == Vector2.ZERO:
			continue
		var hidden := false
		for area in protected:
			if area.intersects(rect):
				hidden = true
				break
		if hidden:
			continue
		draw_style_box(enemy_style, rect)
		var inside := rect.grow(-2)
		var k := clampf(float(e.hp) / e.max_hp, 0, 1)
		draw_rect(Rect2(inside.position, Vector2(inside.size.x * e._bar_chip, inside.size.y)), Color("f2cdc1"))
		draw_rect(Rect2(inside.position, Vector2(inside.size.x * k, inside.size.y)), CORAL)
		draw_rect(Rect2(inside.position, Vector2(inside.size.x * k, 2 * ui_scale())), Color(1, 0.86, 0.85, 0.32))


func _draw() -> void:
	if not enabled or HudPresets.current != HudPresets.STRIKER or Main.inst == null or Main.inst.player == null:
		return
	var m := Main.inst
	_draw_enemies()
	_draw_hero(m.player)
	_draw_status(m, m.player)
	_draw_map(m)
