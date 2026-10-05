class_name DroneHud
extends Control
## 파트너 드론 패널: 이름 · 상태 · 지원 게이지(두 칸 = 스킬 2회) · 청소 수 · 키 안내.
## 값이 바뀔 때만 다시 그린다.

const W := 330.0
const H := 134.0
const MINT := DroneFX.MINT
const DIM := Color(0.62, 0.72, 0.78)

var drone: PartnerDrone
var _snap := ""
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	offset_left = -W - 20.0
	offset_right = -20.0
	# 스킬 버튼 묶음(오른쪽 아래) 위 · 미니맵 아래
	offset_top = -H - 236.0
	offset_bottom = -236.0
	_place()


func _place() -> void:
	if HudPresets.current == HudPresets.STRIKER:
		var view := get_viewport_rect().size
		var rect := RoundSkillDock.support_rect(view, Vector2(W, H))
		offset_left = rect.position.x - view.x
		offset_right = rect.end.x - view.x
		offset_top = rect.position.y - view.y
		offset_bottom = rect.end.y - view.y
	else:
		offset_left = -W - 20.0
		offset_right = -20.0
		offset_top = -H - 236.0
		offset_bottom = -236.0


func _process(dt: float) -> void:
	_place()
	if not is_instance_valid(drone):
		visible = false
		return
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
