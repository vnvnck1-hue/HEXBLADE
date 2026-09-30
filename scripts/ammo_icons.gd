class_name AmmoIcons
extends Control
## 재화 아이콘 줄. 가질 수 있는 최대 개수만큼 칸을 항상 반투명하게 그려 두고,
## 가진 개수만큼은 불투명하게 채운다. 얻으면 튀어 오르며 켜지고, 쓰면 번쩍이며 꺼진다.

const EMPTY_A := 0.2

var kind := "energy"          # "energy" | "missile"
var max_count := 3
var count := 0
var color := Color.WHITE
var icon_size := Vector2(18, 26)
var gap := 5.0
var pending := 0              # 쓰려고 모으는 중인 칸 수 (충전 레이저 미리보기)
var regen := 0.0              # 다음 칸 재충전 진행도 (0~1)

var _pop: PackedFloat32Array  # 칸마다 획득 연출 남은 시간
var _burn: PackedFloat32Array # 칸마다 소모 연출 남은 시간
var _deny_t := 0.0


func setup(k: String, n: int, c: Color, sz: Vector2) -> void:
	kind = k
	max_count = n
	color = c
	icon_size = sz
	_pop.resize(n)
	_burn.resize(n)
	custom_minimum_size = Vector2(n * sz.x + (n - 1) * gap, sz.y + 6.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_count(n: int) -> void:
	count = clampi(n, 0, max_count)


## 새로 채워진 칸들: count 가 이미 늘어난 뒤 불린다
func gained(n: int) -> void:
	for i in range(maxi(0, count - n), count):
		_pop[i] = 0.35


## 비워진 칸들: count 가 이미 줄어든 뒤 불린다
func spent(n: int) -> void:
	for i in range(count, mini(max_count, count + n)):
		_burn[i] = 0.4


func denied() -> void:
	_deny_t = 0.35


func _process(_dt: float) -> void:
	# 궁극기 슬로우 중에도 같은 속도로 움직이게 실제 시간으로 흐른다
	var rdt := get_process_delta_time() / maxf(Engine.time_scale, 0.01)
	for i in max_count:
		_pop[i] = maxf(0.0, _pop[i] - rdt)
		_burn[i] = maxf(0.0, _burn[i] - rdt)
	_deny_t = maxf(0.0, _deny_t - rdt)
	queue_redraw()


func _draw() -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var shake := sin(t * 90.0) * 4.0 * (_deny_t / 0.35)
	# 옅은 받침: 복잡한 바닥 위에서도 빈 칸 윤곽이 읽히게
	draw_rect(Rect2(Vector2(-4, -1), size + Vector2(8, 2)), Color(0.02, 0.02, 0.08, 0.45))
	for i in max_count:
		var base := Vector2(i * (icon_size.x + gap) + shake, 3.0)
		var filled := i < count
		var c := color
		var sc := 1.0
		if filled:
			var pk := _pop[i] / 0.35
			sc = 1.0 + 0.55 * pk * pk
			c = color.lerp(Color.WHITE, pk * 0.8)
			# 곧 쓰일 칸은 깜빡인다
			if i >= count - pending:
				c = c.lerp(Color.WHITE, 0.35 + 0.35 * sin(t * 24.0))
		else:
			c.a = EMPTY_A
			if _deny_t > 0.0:
				c = Color(1, 0.3, 0.35, EMPTY_A + 0.4 * (_deny_t / 0.35))
		var center := base + icon_size * 0.5
		draw_set_transform(center, 0.0, Vector2.ONE * sc)
		_draw_icon(-icon_size * 0.5, c, filled)
		draw_set_transform(Vector2.ZERO)
		# 소모: 하얗게 번쩍이며 커지다 사라지는 윤곽
		if _burn[i] > 0.0:
			var bk := _burn[i] / 0.4
			draw_set_transform(center, 0.0, Vector2.ONE * (1.0 + (1.0 - bk) * 0.7))
			_draw_icon(-icon_size * 0.5, Color(1, 1, 1, bk * 0.9), true)
			draw_set_transform(Vector2.ZERO)
		# 재충전 진행도: 다음에 찰 칸 아래 얇은 줄
		if i == count and regen > 0.0:
			draw_rect(Rect2(base + Vector2(0, icon_size.y + 1.5), Vector2(icon_size.x * regen, 2.0)), Color(color, 0.8))


func _draw_icon(o: Vector2, c: Color, filled: bool) -> void:
	var w := icon_size.x
	var h := icon_size.y
	if kind == "energy":
		# 셀 테두리 + 번개
		var r := Rect2(o, Vector2(w, h))
		if filled:
			draw_rect(r, Color(c, c.a * 0.25))
		draw_rect(r, c, false, 2.0)
		draw_rect(Rect2(o + Vector2(w * 0.3, -3.0), Vector2(w * 0.4, 3.0)), c)
		var bolt := PackedVector2Array([
			o + Vector2(w * 0.62, h * 0.12), o + Vector2(w * 0.22, h * 0.56), o + Vector2(w * 0.48, h * 0.56),
			o + Vector2(w * 0.36, h * 0.9), o + Vector2(w * 0.8, h * 0.42), o + Vector2(w * 0.54, h * 0.42),
		])
		draw_colored_polygon(bolt, c)
	else:
		# 세워진 미사일: 탄두 · 몸통 · 꼬리 날개 · (채워졌을 때) 불꽃
		var cx := o.x + w * 0.5
		var bw := w * 0.36
		var nose := PackedVector2Array([Vector2(cx, o.y), Vector2(cx + bw * 0.5, o.y + h * 0.26), Vector2(cx - bw * 0.5, o.y + h * 0.26)])
		draw_colored_polygon(nose, c)
		draw_rect(Rect2(Vector2(cx - bw * 0.5, o.y + h * 0.28), Vector2(bw, h * 0.5)), c)
		var fin_l := PackedVector2Array([Vector2(cx - bw * 0.5, o.y + h * 0.55), Vector2(cx - bw * 0.5, o.y + h * 0.82), Vector2(o.x, o.y + h * 0.86)])
		var fin_r := PackedVector2Array([Vector2(cx + bw * 0.5, o.y + h * 0.55), Vector2(o.x + w, o.y + h * 0.86), Vector2(cx + bw * 0.5, o.y + h * 0.82)])
		draw_colored_polygon(fin_l, c)
		draw_colored_polygon(fin_r, c)
		if filled:
			var fl := PackedVector2Array([Vector2(cx - bw * 0.35, o.y + h * 0.8), Vector2(cx + bw * 0.35, o.y + h * 0.8), Vector2(cx, o.y + h)])
			draw_colored_polygon(fl, Color(1.0, 0.85, 0.4, c.a))
