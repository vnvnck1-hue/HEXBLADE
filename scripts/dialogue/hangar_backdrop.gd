class_name HangarBackdrop
extends Control
## 대화 뒤 배경: 어두운 격납고. 코드로 그린다 (벽 패널 · 비계 · 정비 중인 기체 실루엣 · 매달린 조명 · 번호 03).
## 말하는 인물이 잘 보이도록 전체를 어둡게 눌러 둔다.

const WARM := Color(1.0, 0.78, 0.42)

var t := 0.0
var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(dt: float) -> void:
	t += dt
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 64.0 or h < 64.0:
		return
	var drift := sin(t * 0.25) * 6.0
	# 벽: 위가 더 어둡다
	for i in 24:
		var k := i / 24.0
		draw_rect(Rect2(0, k * h, w, h / 24.0 + 1.0), Color(0.07, 0.065, 0.07).lerp(Color(0.16, 0.13, 0.11), k * k))
	# 벽 패널 이음새
	var pw := w / 7.0
	for i in 8:
		var x := i * pw + drift * 0.3
		draw_line(Vector2(x, 0), Vector2(x, h * 0.78), Color(0, 0, 0, 0.45), 3.0)
		draw_rect(Rect2(x + pw * 0.08, h * 0.08, pw * 0.84, h * 0.1), Color(1, 1, 1, 0.025))
	# 큰 번호 03 · 깃발
	if font:
		draw_string(font, Vector2(w * 0.86 + drift * 0.3, h * 0.33), "03", HORIZONTAL_ALIGNMENT_CENTER, -1, int(h * 0.15), Color(0.6, 0.55, 0.48, 0.18))
	draw_rect(Rect2(w * 0.04 + drift * 0.3, h * 0.12, w * 0.07, h * 0.36), Color(0.45, 0.08, 0.1, 0.5))
	# 천장 트러스
	for i in 13:
		var x := i * w / 12.0 + drift * 0.5
		draw_line(Vector2(x, 0), Vector2(x + w / 24.0, h * 0.06), Color(0.02, 0.02, 0.02, 0.9), 4.0)
		draw_line(Vector2(x + w / 24.0, h * 0.06), Vector2(x + w / 12.0, 0), Color(0.02, 0.02, 0.02, 0.9), 4.0)
	draw_rect(Rect2(0, h * 0.06, w, 6), Color(0.02, 0.02, 0.02))
	# 기체 실루엣 (가운데, 살짝 뒤라 천천히 움직인다)
	_mech(Vector2(w * 0.5 + drift * 0.6, h * 0.72), h * 0.62)
	# 비계 · 난간
	var deck := h * 0.6
	draw_rect(Rect2(w * 0.3, deck, w * 0.4, 8), Color(0.05, 0.05, 0.05))
	for i in 11:
		var x := w * 0.3 + i * w * 0.04
		draw_line(Vector2(x, deck), Vector2(x, deck - h * 0.05), Color(0.55, 0.42, 0.15, 0.55), 2.0)
		draw_line(Vector2(x, deck), Vector2(x, h * 0.8), Color(0.04, 0.04, 0.04, 0.9), 3.0)
	draw_line(Vector2(w * 0.3, deck - h * 0.05), Vector2(w * 0.7, deck - h * 0.05), Color(0.6, 0.45, 0.15, 0.6), 2.0)
	# 바닥
	draw_rect(Rect2(0, h * 0.8, w, h * 0.2), Color(0.08, 0.075, 0.07))
	for i in 9:
		var x := (i - 4) * w * 0.18
		draw_line(Vector2(w * 0.5 + x * 0.3, h * 0.8), Vector2(w * 0.5 + x * 1.6, h), Color(1, 0.8, 0.3, 0.05), 2.0)
	# 매달린 조명 (가끔 깜빡인다)
	for i in 5:
		var x := w * (0.14 + i * 0.18) + drift * 0.5
		var flick := 1.0 if fmod(t * 0.7 + i * 1.37, 9.0) > 0.12 else 0.35
		draw_line(Vector2(x, h * 0.06), Vector2(x, h * 0.12), Color(0.02, 0.02, 0.02), 2.0)
		for g in 5:
			draw_circle(Vector2(x, h * 0.13), h * (0.13 - g * 0.022), Color(WARM, 0.035 * flick))
		draw_rect(Rect2(x - 26, h * 0.12, 52, 12), Color(WARM * flick, 1.0))
	# 전체를 눌러 인물이 앞에 보이게 + 가장자리 비네트
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.02, 0.04, 0.42))
	for i in 10:
		var k := i / 10.0
		var m := k * minf(w, h) * 0.25
		draw_rect(Rect2(m, m, w - m * 2.0, h - m * 2.0), Color(0, 0, 0, 0.045), false, minf(w, h) * 0.025)


## 머리 · 어깨 · 팔 · 다리 덩어리로 만든 기체 실루엣
func _mech(base: Vector2, s: float) -> void:
	var body := Color(0.32, 0.3, 0.27)
	var dark := Color(0.17, 0.16, 0.15)
	var hi := Color(0.45, 0.42, 0.37)
	var u := s / 10.0
	var parts := [
		[Vector2(-2.6, -6.2), Vector2(5.2, 3.0), body],   # 몸통
		[Vector2(-1.0, -7.4), Vector2(2.0, 1.4), body],   # 머리
		[Vector2(-4.6, -6.6), Vector2(2.2, 2.0), hi],     # 왼 어깨
		[Vector2(2.4, -6.6), Vector2(2.2, 2.0), hi],      # 오른 어깨
		[Vector2(-4.4, -4.6), Vector2(1.6, 3.4), dark],   # 왼팔
		[Vector2(2.8, -4.6), Vector2(1.6, 3.4), dark],
		[Vector2(-2.2, -3.2), Vector2(1.8, 3.4), dark],   # 다리
		[Vector2(0.4, -3.2), Vector2(1.8, 3.4), dark],
	]
	for p in parts:
		draw_rect(Rect2(base + p[0] * u, p[1] * u), p[2])
		draw_rect(Rect2(base + p[0] * u, p[1] * u), Color(0, 0, 0, 0.8), false, 3.0)
	draw_rect(Rect2(base + Vector2(-0.6, -7.0) * u, Vector2(1.2, 0.3) * u), Color(0.9, 0.2, 0.2, 0.7 + 0.3 * sin(t * 2.0)))
	draw_rect(Rect2(base + Vector2(-1.6, -5.8) * u, Vector2(3.2, 0.5) * u), Color(0.6, 0.12, 0.12))
