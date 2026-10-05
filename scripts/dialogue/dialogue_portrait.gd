class_name DialoguePortrait
extends Control
## 대화 화면의 인물 그림 한 장. 자리 이동 · 말하는 사람 강조(밝기·크기·앞으로) · 표정 교차 전환 ·
## 표정이 바뀔 때 통통 튀기 · 감정 흔들기 · 말할 때 살짝 들썩임 · 등장/퇴장 미끄러짐을 맡는다.

const SLOT_X := {"left2": 0.07, "left": 0.28, "center": 0.5, "right": 0.72, "right2": 0.93}
const BACK_SLOTS := ["left2", "right2"]
const DIM := Color(0.38, 0.4, 0.52)
const XFADE := 0.14

var who := ""
var expr := ""
var slot := "left"
var active := false
var leaving := false
## 단독 상담은 중앙에 세우고 그림의 허리 끝을 하단 창 뒤에 살짝 넣는다.
var solo := false
## 좌우 두 인물은 몸 방향만 안쪽으로, 시선은 원화대로 플레이어 쪽으로 유지한다.
var paired := false
var solo_bottom := 266.0

var _tex: Texture2D
var _old: Texture2D
var _fade := 1.0
var _x := 0.0
var _alpha := 0.0
var _light := 0.0
var _hop := 0.0
var _hop_v := 0.0
var _shake := 0.0
var _bob := 0.0
var _flip := false
var _t := 0.0
var _screen := Vector2(1280, 800)


func setup(id: String, at: String, e: String, screen: Vector2) -> void:
	who = id
	_screen = screen
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_expr(e if e != "" else DialogueCast.CAST[id].default, false)
	place(at)
	# 화면 밖 가까운 쪽에서 미끄러져 들어온다
	_x = _target_x() + (-1.0 if _target_x() < screen.x * 0.5 else 1.0) * screen.x * 0.18
	_alpha = 0.0
	_layout()


func place(at: String) -> void:
	slot = at
	_orient()


func body_direction() -> int:
	var c: Dictionary = DialogueCast.CAST[who]
	var direction := int(c.get("faces", {}).get(expr, c.face))
	return -direction if _flip else direction


func _orient() -> void:
	var c: Dictionary = DialogueCast.CAST[who]
	var want := 1 if SLOT_X[slot] <= 0.5 else -1
	var raw_direction := int(c.get("faces", {}).get(expr, c.face))
	var can_flip: bool = c.flip_ok or expr in c.get("flip_expr", [])
	_flip = can_flip and raw_direction != want


func set_expr(e: String, animate := true) -> void:
	if e == expr and _tex != null:
		return
	var t := DialogueCast.texture(who, e)
	if animate and _tex != null:
		_old = _tex
		_fade = 0.0
		hop(0.6)
	expr = e
	_tex = t
	_orient()


func leave() -> void:
	leaving = true


func hop(power := 1.0) -> void:
	_hop_v = -520.0 * power


func shake(power := 1.0) -> void:
	_shake = maxf(_shake, 0.35 * power)


## 글자 소리와 맞춰 살짝 들썩인다
func bob() -> void:
	_bob = 1.0


func resize_screen(screen: Vector2) -> void:
	_screen = screen
	_layout()


func _side() -> float:
	return h_size() * 0.5


func h_size() -> float:
	if solo or paired:
		return minf(_screen.y - solo_bottom - 92.0, _screen.x * 0.5 - 40.0)
	return _screen.y * (0.76 if slot in BACK_SLOTS else 0.88)


func _target_x() -> float:
	if solo:
		return _screen.x * 0.5
	if paired:
		return _screen.x * (0.25 if slot in ["left", "left2"] else 0.75)
	return _screen.x * SLOT_X[slot]


func _layout() -> void:
	var s := h_size()
	size = Vector2(s, s)
	pivot_offset = Vector2(s * 0.5, s)


func gone() -> bool:
	return leaving and _alpha < 0.02


func _process(dt: float) -> void:
	_t += dt
	var tx := _target_x()
	if leaving:
		tx += (-1.0 if tx < _screen.x * 0.5 else 1.0) * _screen.x * 0.18
	_x = lerpf(_x, tx, 1.0 - exp(-dt * 11.0))
	_alpha = move_toward(_alpha, 0.0 if leaving else 1.0, dt * 5.0)
	_light = lerpf(_light, 1.0 if active else 0.0, 1.0 - exp(-dt * 12.0))
	_fade = minf(1.0, _fade + dt / XFADE)
	# 통통: 위로 튀었다가 스프링으로 돌아온다
	_hop_v += (-_hop * 260.0 - _hop_v * 18.0) * dt
	_hop += _hop_v * dt * 0.06
	_shake = maxf(0.0, _shake - dt)
	_bob = maxf(0.0, _bob - dt * 9.0)
	_layout()
	var s := size.x
	var breathe := sin(_t * 1.6 + float(who.hash() % 7)) * 0.004 * _light
	var sc := lerpf(0.94, 1.0, _light) + breathe
	scale = Vector2(sc, sc)
	var sx := 0.0
	if _shake > 0.0:
		sx = sin(_t * 70.0) * 14.0 * _shake / 0.35
	var y := _screen.y - s + s * 0.06 + lerpf(14.0, 0.0, _light) + _hop * 40.0 - _bob * 4.0
	if solo or paired:
		# 큰 프레임 간격 뒤 스프링이 아래로 넘쳐도 그림의 허리/손을 화면 안에 유지한다.
		y = _screen.y - solo_bottom - s + clampf(_hop * 40.0 - _bob * 4.0, -12.0, 0.0)
	position = Vector2(_x - s * 0.5 + sx, y)
	var listener := Color(0.70, 0.70, 0.78) if paired else DIM
	modulate = Color(listener.lerp(Color.WHITE, _light), _alpha)
	queue_redraw()


func _draw() -> void:
	var s := size.x
	if _flip:
		draw_set_transform(Vector2(s, 0), 0.0, Vector2(-1, 1))
	var r := Rect2(Vector2.ZERO, Vector2(s, s))
	# 뒤 배경과 떨어져 보이게 옅은 그림자
	if _tex:
		draw_texture_rect(_tex, Rect2(Vector2(s * 0.012, s * 0.006), r.size), false, Color(0, 0, 0, 0.35))
	if _old and _fade < 1.0:
		draw_texture_rect(_old, r, false, Color(1, 1, 1, 1.0 - _fade))
	if _tex:
		draw_texture_rect(_tex, r, false, Color(1, 1, 1, _fade if _old else 1.0))
	if _fade >= 1.0:
		_old = null
