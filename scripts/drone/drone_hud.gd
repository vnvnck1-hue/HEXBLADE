class_name DroneHud
extends Control
## 파트너 드론 패널: 이름 · 상태 · 지원 게이지(두 칸 = 스킬 2회) · 청소 수 · 키 안내.
## 값이 바뀔 때만 다시 그린다.

const W := 330.0
const H := 134.0
const MINT := DroneFX.MINT
const DIM := Color(0.62, 0.72, 0.78)
const CARD := Vector2(560, 168)
const PORTRAIT := "res://assets/ui/calm_hud/triad_portrait.png"

var portrait: Texture2D
var card_font := SystemFont.new()
var card_style := StyleBoxFlat.new()
var button_style := StyleBoxFlat.new()
var _card_mode := false

var drone: PartnerDrone
var _snap := ""
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	portrait = load(PORTRAIT) as Texture2D
	card_font.font_names = PackedStringArray(["Arial", "Liberation Sans", "Malgun Gothic", "sans-serif"])
	card_font.font_weight = 800
	card_font.font_italic = true
	card_style.bg_color = CalmHud.PANEL
	card_style.border_color = CalmHud.BORDER
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(8)
	button_style.set_corner_radius_all(4)
	button_style.set_border_width_all(1)
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -W - 20.0
	offset_right = -20.0
	# 스킬 버튼 묶음(오른쪽 아래) 위 · 미니맵 아래
	offset_top = -H - 236.0
	offset_bottom = -236.0
	_place()


static func panel_rect(view: Vector2) -> Rect2:
	if CalmHud.active():
		var s := RoundSkillDock.ui_scale(view)
		return Rect2(Vector2(18 * s, view.y - (CARD.y + 22) * s), CARD * s)
	if HudPresets.current == HudPresets.STRIKER:
		return RoundSkillDock.support_rect(view, Vector2(W, H))
	return Rect2(view - Vector2(W + 20, H + 236), Vector2(W, H))


func _place() -> void:
	var view := get_viewport_rect().size
	var rect := panel_rect(view)
	offset_left = rect.position.x - view.x
	offset_right = rect.end.x - view.x
	offset_top = rect.position.y - view.y
	offset_bottom = rect.end.y - view.y


func _process(dt: float) -> void:
	_place()
	if not is_instance_valid(drone):
		visible = false
		return
	visible = true
	var card_mode := CalmHud.active()
	if card_mode != _card_mode:
		_card_mode = card_mode
		queue_redraw()
	var ready := drone.gauge >= PartnerDrone.SKILL_COST
	if ready:
		_pulse += dt
	var s := "%s|%d|%d|%d|%s|%s|%s|%s" % [drone.status_text(), int(drone.gauge), drone.cleaned, drone.player_cleaned, drone.docked(), drone.p_cleaning, drone.auto_cleaning, drone.sweeping]
	if ready:
		s += "|%d" % int(_pulse * 4.0)
	if s != _snap:
		_snap = s
		queue_redraw()


func _draw() -> void:
	if not is_instance_valid(drone):
		return
	if CalmHud.active():
		_draw_card()
		return
	draw_set_transform(Vector2.ZERO)
	_draw_legacy()


func _draw_legacy() -> void:
	var f: Font = drone.main.hud.font if drone.main and drone.main.hud else ThemeDB.fallback_font
	var r := Rect2(Vector2.ZERO, Vector2(W, H))
	draw_rect(r, Color(0.03, 0.06, 0.09, 0.72))
	draw_rect(Rect2(0, 0, 4, H), MINT)
	# 이름 · 상태
	draw_string(f, Vector2(14, 24), PartnerDrone.NAME, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, MINT)
	draw_string(f, Vector2(82, 24), "파트너 청소 드론", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, DIM)
	var st := drone.status_text()
	var sc := Color("ffd070") if st == "휘청!" else (Color("9ad8ff") if drone.docked() else Color.WHITE)
	_right_text(f, Vector2(W - 14, 24), st, 15, sc)
	# 지원 게이지 두 칸
	var gx := 14.0
	var gy := 36.0
	var gw := W - 28.0
	var seg := (gw - 6.0) * 0.5
	var k := drone.gauge / PartnerDrone.GAUGE_MAX
	for i in 2:
		var x := gx + i * (seg + 6.0)
		draw_rect(Rect2(x, gy, seg, 14), Color(0.1, 0.16, 0.2, 0.9))
		var fill := clampf(k * 2.0 - i, 0.0, 1.0)
		var full := fill >= 1.0
		var c := MINT if full else MINT.darkened(0.35)
		if full:
			c = c.lerp(Color.WHITE, 0.25 + 0.25 * sin(_pulse * 7.0))
		draw_rect(Rect2(x, gy, seg * fill, 14), c)
		draw_rect(Rect2(x, gy, seg, 14), Color(1, 1, 1, 0.25), false, 1.0)
	draw_string(f, Vector2(gx, gy + 32), "지원 %d / %d" % [int(drone.gauge), int(PartnerDrone.GAUGE_MAX)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	_right_text(f, Vector2(W - 14, gy + 32), "청소 %d · 직접 %d" % [drone.cleaned, drone.player_cleaned], 13, DIM)
	# 키 안내 (지금 쓸 수 있는 X 스킬 이름이 바뀐다)
	var skill := "볼텍스" if drone.docked() else "보호막"
	var xc := MINT if drone.gauge >= PartnerDrone.SKILL_COST else DIM
	var y := gy + 58
	var x0 := gx
	x0 = _key(f, x0, y, "Q", "분리" if drone.docked() else "합체", Color.WHITE if drone.docked() or drone.gauge >= PartnerDrone.DOCK_MIN else DIM)
	x0 = _key(f, x0, y, "X", skill, xc)
	_key(f, x0, y, "Z", "직접 청소", MINT if drone.p_cleaning or drone.auto_cleaning else DIM)
	# Space 를 누른 채 다니면 둘레 오염을 전부 빨아들인다 (청소 질주 중이면 밝게)
	draw_string(f, Vector2(gx, y + 22), "SPACE 유지 이동: 주변 청소 · 짧게: 회피", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, MINT if drone.sweeping else Color(0.8, 0.95, 0.9, 0.8))


func _right_text(f: Font, end: Vector2, text: String, px: int, color: Color) -> void:
	var width := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string(f, end - Vector2(width, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


func _key(f: Font, x: float, y: float, key: String, label: String, c: Color) -> float:
	draw_rect(Rect2(x, y - 14, 20, 19), Color(1, 1, 1, 0.12))
	draw_rect(Rect2(x, y - 14, 20, 19), c, false, 1.0)
	draw_string(f, Vector2(x, y), key, HORIZONTAL_ALIGNMENT_CENTER, 20, 13, c)
	draw_string(f, Vector2(x + 26, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)
	return x + 26 + f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 16


func _card_text(at: Vector2, text: String, px: int, color := CalmHud.PAPER, face: Font = null, right := false) -> void:
	if face == null:
		face = card_font
	if right:
		at.x -= face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	draw_string_outline(face, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 2, Color(0.02, 0.04, 0.06, 0.7))
	draw_string(face, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, color)


func _action(rect: Rect2, key: String, label: String, ready: bool, using: bool) -> void:
	var color := CalmHud.MINT if ready else CalmHud.DIM.darkened(0.18)
	button_style.bg_color = Color(0.075, 0.15, 0.20, 0.95)
	button_style.border_color = CalmHud.BORDER
	draw_style_box(button_style, rect)
	var badge := Rect2(rect.position + Vector2(3, 3), Vector2(28, rect.size.y - 6))
	button_style.bg_color = CalmHud.MINT if ready else Color("314652")
	button_style.border_color = color
	draw_style_box(button_style, badge)
	_card_text(badge.position + Vector2(6, 20), key, 19, Color("152f38") if ready else CalmHud.PAPER)
	_card_text(rect.position + Vector2(38, 24), label, 16, color)
	if using:
		draw_line(rect.position + Vector2(38, rect.size.y - 4), rect.end - Vector2(7, 4), CalmHud.MINT, 2, true)


func _draw_card() -> void:
	var s := RoundSkillDock.ui_scale(get_viewport_rect().size)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * s)
	draw_style_box(card_style, Rect2(Vector2.ZERO, CARD))
	# 참조의 큰 드론 초상·넓은 남색 면·민트 키 배지.
	draw_colored_polygon(PackedVector2Array([Vector2(420, 1), Vector2(559, 1), Vector2(536, 167), Vector2(352, 167)]), Color(0.15, 0.23, 0.28, 0.11))
	if portrait:
		draw_texture_rect(portrait, Rect2(-6, 2, 158, 158), false)
	var f: Font = drone.main.hud.font
	_card_text(Vector2(152, 32), PartnerDrone.NAME, 27)
	var state_color := CalmHud.CORAL if drone.state == PartnerDrone.St.HURT else CalmHud.DIM
	_card_text(Vector2(545, 29), drone.status_text(), 14, state_color, f, true)
	_card_text(Vector2(152, 58), "SUPPORT", 17, CalmHud.MINT)
	_card_text(Vector2(545, 58), "%d / %d" % [int(drone.gauge), int(PartnerDrone.GAUGE_MAX)], 18, CalmHud.PAPER, null, true)
	var gauge := Rect2(153, 69, 392, 12)
	draw_rect(gauge, Color("203b46"))
	var k := clampf(drone.gauge / PartnerDrone.GAUGE_MAX, 0, 1)
	draw_rect(Rect2(gauge.position, Vector2(gauge.size.x * k, gauge.size.y)), CalmHud.MINT)
	draw_rect(gauge, CalmHud.BORDER, false, 1)
	draw_line(gauge.position + Vector2(gauge.size.x * 0.5, 1), gauge.position + Vector2(gauge.size.x * 0.5, gauge.size.y - 1), Color("0c2029"), 2)
	var available := not drone._down
	var dock_ready := available and (drone.docked() or drone.gauge >= PartnerDrone.DOCK_MIN)
	var skill_ready := available and drone.gauge >= PartnerDrone.SKILL_COST
	_action(Rect2(152, 92, 126, 36), "Q", "UNDOCK" if drone.docked() else "DOCK", dock_ready, drone.docked())
	_action(Rect2(286, 92, 128, 36), "X", "VORTEX" if drone.docked() else "SHIELD", skill_ready, false)
	_action(Rect2(422, 92, 123, 36), "Z", "CLEAN", available, drone.p_cleaning or drone.auto_cleaning)
	_card_text(Vector2(152, 149), "SPACE 유지 이동: 주변 청소 · 짧게: 회피", 11, CalmHud.MINT if drone.sweeping else CalmHud.DIM, f)
	_card_text(Vector2(545, 163), "청소 %d · 직접 %d" % [drone.cleaned, drone.player_cleaned], 10, CalmHud.DIM, f, true)
