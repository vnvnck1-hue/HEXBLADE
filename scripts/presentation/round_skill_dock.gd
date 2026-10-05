class_name RoundSkillDock
extends Control
## 사용자 원형 장비 HUD. 그림만 텍스처, 테두리/키/수치/상태는 실제 Player 값으로 그린다.

const DESIGN := Vector2(366, 306)
const EDGE := 22.0
const FILL := Color(0.065, 0.055, 0.19, 0.76)
const LINE := Color("bbb2ef")
const QUIET := Color("79749d")
const TEXT := Color("f7f3ff")
const ICON_DIR := "res://assets/ui/round_skills/"
const ITEMS := {
	"sword": [Vector2(298, 221), 49.0],
	"gun": [Vector2(184, 244), 43.0],
	"dash": [Vector2(84, 249), 36.0],
	"boost": [Vector2(151, 135), 34.0],
	"energy": [Vector2(234, 151), 34.0],
	"missile": [Vector2(307, 67), 37.0],
	"rush": [Vector2(40, 159), 22.0],
}

var hud: Hud
var icons: Dictionary = {}
var clock := 0.0
var key_box := StyleBoxFlat.new()


static func ui_scale(view: Vector2) -> float:
	return clampf(view.y / 900.0, 0.7, 1.35)


static func dock_rect(view: Vector2) -> Rect2:
	var extent := DESIGN * ui_scale(view)
	return Rect2(view - extent - Vector2.ONE * EDGE, extent)


static func support_rect(view: Vector2, extent: Vector2) -> Rect2:
	# 미니맵 아래의 콤보와 공간을 다투지 않게 장비 묶음 왼쪽에 붙인다.
	var dock := dock_rect(view)
	return Rect2(Vector2(dock.position.x - extent.x - 16.0, view.y - EDGE - extent.y), extent)


static func missile_count(p: Player) -> int:
	# 예약탄은 실제 발사될 때까지 남은 수에 포함한다.
	return p.missiles + p.ult_queue


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	key_box.bg_color = Color(0.075, 0.055, 0.18, 0.94)
	key_box.border_color = LINE
	key_box.set_border_width_all(1)
	key_box.set_corner_radius_all(4)
	for name_ in ["sword", "gun", "dash", "boost", "energy", "missile"]:
		icons[name_] = load(ICON_DIR + name_ + ".png") as Texture2D


func _process(dt: float) -> void:
	visible = HudPresets.current == HudPresets.STRIKER
	if visible:
		clock += dt / maxf(Engine.time_scale, 0.01)
		queue_redraw()


func _text(at: Vector2, value: String, px: int, col := TEXT) -> void:
	var x := at.x - hud.font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x * 0.5
	draw_string_outline(hud.font, Vector2(x, at.y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 3, Color(0.04, 0.025, 0.12, 0.9))
	draw_string(hud.font, Vector2(x, at.y), value, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _key(c: Vector2, value: String) -> void:
	var width := maxf(24.0, hud.font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 12.0)
	draw_style_box(key_box, Rect2(c - Vector2(width * 0.5, 10), Vector2(width, 21)))
	_text(c + Vector2(0, 5), value, 12)


func _arc(c: Vector2, r: float, k: float, col: Color, width := 2.4) -> void:
	if k > 0.001:
		draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * clampf(k, 0, 1), 64, col, width, true)


func _sector(c: Vector2, r: float, k: float) -> void:
	if k <= 0.001:
		return
	var pts := PackedVector2Array([c])
	var count := maxi(3, int(64 * clampf(k, 0, 1)))
	for i in count + 1:
		var a := -PI * 0.5 + TAU * clampf(k, 0, 1) * i / count
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, Color(0.065, 0.055, 0.19, 0.66))


func _item(name_: String, available := true, active := false, icon_offset := Vector2.ZERO, icon_extent := 0.0) -> Vector2:
	var c: Vector2 = ITEMS[name_][0]
	var radius: float = ITEMS[name_][1]
	draw_circle(c, radius, FILL)
	if active:
		_arc(c, radius + 3.0, 1.0, Color(0.85, 0.8, 1.0, 0.24), 4.0)
	_arc(c, radius, 1.0, TEXT if active else (LINE if available else QUIET))
	var texture := icons.get(name_) as Texture2D
	if texture:
		var extent := radius * 2.0 if icon_extent <= 0.0 else icon_extent
		var shape := texture.get_size()
		shape *= extent / maxf(shape.x, shape.y)
		draw_texture_rect(texture, Rect2(c + icon_offset - shape * 0.5, shape), false, Color.WHITE if available else Color(0.54, 0.5, 0.66, 0.66))
	return c


func _draw() -> void:
	if hud == null or Main.inst == null or Main.inst.player == null or HudPresets.current != HudPresets.STRIKER:
		return
	var p := Main.inst.player
	var rect := dock_rect(size)
	draw_set_transform(rect.position, 0.0, Vector2.ONE * ui_scale(size))

	# 큰 검 · 아래쪽 사격/회피 · 위쪽 부스터/레이저/미사일.
	var hot := p.combo != null and (p.combo.ph != SwordCombo.Ph.IDLE or p.combo.link_t > 0.0)
	var c := _item("sword", not p.no_attack, hot or p.phantom_t > 0.0)
	if p.phantom_t > 0.0:
		_arc(c, 53, 1.0, Color("ff7d94"))
	if hot:
		for i in SwordCombo.STEPS.size():
			var a := -PI * 0.5 + (i - (SwordCombo.STEPS.size() - 1) * 0.5) * 0.22
			draw_circle(c + Vector2(cos(a), sin(a)) * 55, 2.5, Color("ff9aac") if i <= p.combo.step else QUIET)
	_key(c + Vector2(0, 53), "LMB")

	var reload := p.reload_t > 0.0
	c = _item("gun", not p.no_attack and p.mag > 0 and not reload, p.fire_cd > 0.0, Vector2(0, -9), 79.0)
	if reload:
		_sector(c, 41, 1.0 - p.reload_k())
		_arc(c, 43, p.reload_k(), Color("f2c76b"), 3.0)
		_text(c + Vector2(0, 29), "RELOAD", 12, Color("f2c76b"))
	else:
		var ammo_col := Color("ff7e90") if p.mag <= 5 else Color("ffe276")
		_text(c + Vector2(-13, 30), "%d" % p.mag, 19, ammo_col)
		_text(c + Vector2(22, 29), "/ %d" % Player.MAG_SIZE, 12)
	_key(c + Vector2(-17, 47), "RMB")
	_key(c + Vector2(23, 47), "T")

	var ready := p.dash_cd <= 0.0
	c = _item("dash", ready, p.dash_t > 0.0)
	if not ready:
		_sector(c, 34, p.dash_cd / Player.DASH_CD)
		_arc(c, 36, 1.0 - p.dash_cd / Player.DASH_CD, LINE, 3.0)
	_key(c + Vector2(0, 40), "SPACE")

	c = _item("boost", not p.overheated and p.boost > 0.0, p.boosting)
	if p.boost < 0.999 or p.boosting or p.overheated:
		_arc(c, 34, p.boost, Color("ff7e90") if p.overheated else Color("79d5ed"), 3.0)
	if p.overheated:
		_text(c + Vector2(0, 6), "HOT", 13, Color("ff7e90"))
	_key(c + Vector2(0, 38), "SHIFT")

	c = _item("energy", p.energy > 0 and p.laser_cd <= 0.0 and not p.no_attack, p.charging)
	var pending := Player.laser_cost(p.charge) if p.charging and p.charge >= Player.CHARGE_MIN else 0
	for i in Player.ENERGY_MAX:
		var a0 := -PI * 0.5 + i * TAU / Player.ENERGY_MAX + 0.09
		var a1 := -PI * 0.5 + (i + 1) * TAU / Player.ENERGY_MAX - 0.09
		var col := Color("9ee5b2") if i < p.energy else QUIET
		if i < p.energy and i >= p.energy - pending:
			col = col.lerp(TEXT, 0.5 + 0.25 * sin(clock * 12.0))
		draw_arc(c, 34, a0, a1, 22, col, 2.5, true)
	if p.charging:
		_arc(c, 38, p.charge, ChargeFX.STAGE_COLORS[mini(p.charge_stage, 3)], 3.0)
	elif p.energy < Player.ENERGY_MAX:
		var a0 := -PI * 0.5 + p.energy * TAU / Player.ENERGY_MAX + 0.09
		draw_arc(c, 38, a0, a0 + (TAU / Player.ENERGY_MAX - 0.18) * p.energy_regen_k(), 22, Color("9ee5b2"), 1.5, true)
	_key(c + Vector2(0, 38), "L+R")

	c = _item("missile", p.missiles > 0 and not p.no_attack, p.ult_aiming or p.ult_winding())
	var counter := c + Vector2(26, -26)
	draw_circle(counter, 14, Color(0.085, 0.065, 0.22, 0.97))
	_arc(counter, 14, 1.0, LINE, 1.8)
	_text(counter + Vector2(0, 5), "%d" % missile_count(p), 14)
	_key(c + Vector2(22, 39), "R")

	# E 도약 내려찍기: 작은 보조 버튼 (내려꽂히는 화살 + 바닥선)
	if p.leap != null:
		c = ITEMS.rush[0]
		ready = p.leap.ready()
		draw_circle(c, 22, FILL)
		_arc(c, 22, 1.0, LINE if ready else QUIET, 1.8)
		var color := Color("a4dbdb") if ready else QUIET
		draw_line(Vector2(c.x, c.y - 10), Vector2(c.x, c.y + 1), color, 2.4, true)
		draw_polyline(PackedVector2Array([Vector2(c.x - 6, c.y - 2), Vector2(c.x, c.y + 4), Vector2(c.x + 6, c.y - 2)]), color, 2.4, true)
		draw_line(Vector2(c.x - 10, c.y + 8), Vector2(c.x + 10, c.y + 8), color, 2.0, true)
		if p.leap.aiming():
			_arc(c, 26, 1.0, Color(LeapSlam.COL, 0.8), 2.0)
		if not ready:
			_sector(c, 20, p.leap.cd / LeapSlam.CD)
			_text(c + Vector2(0, 5), "%.1f" % p.leap.cd, 12)
		_key(c + Vector2(0, 26), "E")
