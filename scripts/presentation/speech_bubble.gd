class_name SpeechBubble
extends Control
## 필드 위 만화 말풍선 — 캐릭터 대사 · 감정표현(!! ?) · 의성어(끼릭! 싹싹)
##
## 흰 바탕 + 짙은 남색 굵은 테두리 + 오른쪽 아래로 밀린 남색 그림자 + 꼬리.
##   SAY   : 대사. 남색 글자, 넓은 말풍선, 꼬리가 말하는 쪽을 가리킨다.
##   EMOTE : 감정 기호. 빨간 굵은 글자, 작은 정사각 말풍선.
##   SFX   : 의성어. 톱니 모양 터짐 말풍선, 꼬리 없음, 크게 기울어진다.
## 등장은 "띠용!"(0.2초 안): 꼬리 끝을 축으로 0 에서 튀어나와 가로·세로가 서로 다른 스프링으로 출렁이고
## (젤리처럼 늘었다 눌림), 기울기도 스프링으로 흔들리다 멈춘다. 퇴장은 옆으로 눌리며 뿅 줄어든다.
## 시간은 실제 시계 (슬로모션 · 히트스탑 중에도 똑같이 튄다). HUD 층 아래라 F2(UI 숨김)를 따른다.
##
## 사용:
##   SpeechBubble.say(드론, "다녀올게요!", SpeechBubble.SAY, {"offset": Vector3(0, 0.6, 0)})
##   SpeechBubble.at(위치, "끼릭!", SpeechBubble.SFX)

enum { SAY, EMOTE, SFX }

const INK := Color("262a44")          ## 테두리 · 그림자 · 대사 글자
const RED := Color("ff3a5c")          ## 감정 기호 · 의성어 글자
const PAPER := Color(1, 1, 1)
const OUTLINE := 3.6
const SHADOW := Vector2(3.5, 4.5)
const LIFE := {SAY: 1.9, EMOTE: 1.15, SFX: 0.7}
const FONT_SIZE := {SAY: 20, EMOTE: 34, SFX: 26}

static var _layer: Control            ## 말풍선을 모아 두는 화면 층 (HUD root 아래)
static var _font: Font
static var fixed_dt := 0.0            ## 0 보다 크면 실제 시계 대신 이 간격 (캡처 · 검사용)

var kind := SAY
var text := ""
var anchor: Node3D                     ## 따라갈 대상 (없으면 world 고정)
var world := Vector3.ZERO
var offset := Vector3.ZERO
var key := 0                           ## 같은 키의 새 말풍선이 오면 이전 것은 비킨다
var col := INK
var fsize := 20
var life := 1.9
var delay := 0.0
var drift := 0.0                       ## 위로 떠오르는 속도 (px/s, 의성어)

var t := -1.0                          ## 등장 후 경과 (delay 동안은 음수)
var leaving := -1.0                    ## 퇴장 경과 (-1 = 아직)
var sx := 0.0                          ## 가로 · 세로 스케일 스프링
var sy := 0.0
var vx := 0.0
var vy := 0.0
var rot := 0.0
var vr := 0.0
var tilt := 0.0                        ## 멈춘 뒤 기울기
var rise := 0.0
var flip := false                      ## 꼬리를 오른쪽에 둘까
var tail_tip := Vector2.ZERO           ## 그리기 좌표에서 꼬리 끝 (= 회전·크기 축)
var _body := PackedVector2Array()
var _ink := PackedVector2Array()
var _txt_pos := Vector2.ZERO
var _last_us := 0
var _rdt := 0.0


# ═══════════════════════════════════════════════════
#  정적 진입점
# ═══════════════════════════════════════════════════
static func say(who: Node3D, msg: String, k := SAY, opts := {}) -> SpeechBubble:
	if who == null or not is_instance_valid(who):
		return null
	var o := opts.duplicate()
	o["anchor"] = who
	if not o.has("key"):
		o["key"] = who.get_instance_id() * 4 + k
	return _spawn(msg, k, who.global_position, o)


static func at(pos: Vector3, msg: String, k := SFX, opts := {}) -> SpeechBubble:
	return _spawn(msg, k, pos, opts)


## 지금 화면에 떠 있는 말풍선 (확인용)
static func live() -> Array:
	var out := []
	if is_instance_valid(_layer):
		for c in _layer.get_children():
			if c is SpeechBubble and not (c as SpeechBubble).is_queued_for_deletion():
				out.append(c)
	return out


static func _spawn(msg: String, k: int, pos: Vector3, o: Dictionary) -> SpeechBubble:
	var layer := _get_layer()
	if layer == null:
		return null
	var b := SpeechBubble.new()
	b.kind = k
	b.text = msg
	b.world = pos
	b.anchor = o.get("anchor", null)
	b.offset = o.get("offset", Vector3(0, 2.2, 0) if b.anchor else Vector3.ZERO)
	b.key = int(o.get("key", 0))
	b.col = o.get("color", INK if k == SAY else RED)
	b.fsize = int(o.get("size", FONT_SIZE[k]))
	b.life = float(o.get("life", LIFE[k]))
	b.delay = float(o.get("delay", 0.0))
	b.drift = float(o.get("drift", 46.0 if k == SFX else 0.0))
	b.flip = bool(o.get("flip", randf() < 0.3))
	if b.key != 0:
		for c in layer.get_children():
			var old := c as SpeechBubble
			if old and old.key == b.key and old.leaving < 0.0:
				old.dismiss()
	layer.add_child(b)
	return b


static func _get_layer() -> Control:
	if is_instance_valid(_layer):
		return _layer
	var m := Main.inst
	if m == null or m.hud == null or not is_instance_valid(m.hud.root):
		return null
	_font = m.hud.font
	_layer = Control.new()
	_layer.name = "SpeechBubbles"
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.hud.root.add_child(_layer)
	return _layer


# ═══════════════════════════════════════════════════
#  말풍선 하나
# ═══════════════════════════════════════════════════
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 40 if kind == SAY else 41
	_build_shape()
	t = -delay
	tilt = randf_range(-0.07, 0.07) if kind != SFX else randf_range(-0.22, 0.22)
	# 띠용: 처음 기울기를 크게 비틀어 두고 스프링으로 되돌린다
	rot = tilt + (randf_range(0.25, 0.4) * (1.0 if randf() < 0.5 else -1.0))
	vy = 26.0                           # 세로가 먼저 솟고 가로가 따라온다
	visible = false
	_last_us = Time.get_ticks_usec()
	_place()


func dismiss() -> void:
	if leaving < 0.0:
		leaving = 0.0


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := minf((now - _last_us) / 1000000.0, 0.05) if fixed_dt <= 0.0 else fixed_dt
	_last_us = now
	_rdt = dt
	if get_tree().paused:
		return
	if anchor != null and not is_instance_valid(anchor):
		anchor = null
		dismiss()
	t += dt
	if t < 0.0:
		return
	if t - dt < 0.0:
		_pop_lines_start()
	if leaving < 0.0 and t >= life:
		dismiss()
	if leaving >= 0.0:
		leaving += dt
		var k := clampf(leaving / 0.09, 0.0, 1.0)
		var e := k * k
		sx = lerpf(sx, (1.0 + 0.35 * k) * (1.0 - e), 0.6)
		sy = lerpf(sy, (1.0 - k) * (1.0 - e), 0.6)
		if k >= 1.0:
			queue_free()
			return
	else:
		# 띠용 스프링: 단단하고 빨리 멈춘다 (약 50ms 에 1.3배 → 0.2초 안 정착). 가로·세로 진동수를 달리해 젤리처럼
		var steps := ceili(dt / (1.0 / 240.0))
		var h := dt / steps
		for i in steps:
			vx += ((1.0 - sx) * 1500.0 - vx * 36.0) * h
			vy += ((1.0 - sy) * 2000.0 - vy * 40.0) * h
			vr += ((tilt - rot) * 1300.0 - vr * 34.0) * h
			sx += vx * h
			sy += vy * h
			rot += vr * h
	rise += drift * dt
	_place()
	# 모양은 한 번 만들어 두고 크기·기울기는 Control 변환이 맡는다. 스프링이 멈추고 효과선도 끝나면 다시 그리지 않는다
	# (말풍선마다 오목한 다각형 3개를 매 프레임 삼각형으로 다시 쪼개던 것)
	var moving := leaving >= 0.0 or absf(vx) + absf(vy) + absf(vr) > 0.02 			or absf(1.0 - sx) + absf(1.0 - sy) > 0.002 or (_lines_t >= 0.0 and _lines_t < 0.12)
	if moving or not _still_drawn:
		queue_redraw()
		_still_drawn = not moving


func _place() -> void:
	var m := Main.inst
	var wp := (anchor.global_position if anchor else world) + offset
	if m == null or m.camera == null or m.camera.is_position_behind(wp) or t < 0.0:
		visible = false
		return
	var sp: Vector2 = m.camera.screen_pos(wp) if m.camera.has_method("screen_pos") else m.camera.unproject_position(wp)
	var vs := get_viewport_rect().size
	var k := clampf(vs.y / 800.0, 0.75, 1.6)   # 창 높이에 맞춘 크기
	visible = true
	# 꼬리 끝이 기준점에 오도록 놓고, 꼬리 끝을 축으로 키우고 돌린다
	position = sp - tail_tip + Vector2(0, -rise)
	pivot_offset = tail_tip
	scale = Vector2(maxf(sx, 0.0), maxf(sy, 0.0)) * k
	rotation = rot
	# 화면 밖으로 나가지 않게 (위쪽 · 좌우)
	var top := sp.y - rise - tail_tip.y * k
	if top < 6.0:
		position.y += 6.0 - top
	var w := size.x * k
	if sp.x - tail_tip.x * k < 8.0:
		position.x += 8.0 - (sp.x - tail_tip.x * k)
	elif sp.x - tail_tip.x * k + w > vs.x - 8.0:
		position.x -= (sp.x - tail_tip.x * k + w) - (vs.x - 8.0)


# ── 모양 ───────────────────────────────────────────
func _build_shape() -> void:
	var f := _font if _font else ThemeDB.fallback_font
	var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	var asc := f.get_ascent(fsize)
	var poly := PackedVector2Array()
	var pad := Vector2(16, 9) if kind == SAY else Vector2(12, 7)
	if kind == SFX:
		pad = Vector2(20, 16)
	var w := ts.x + pad.x * 2.0
	var hh := ts.y + pad.y * 2.0
	if kind == EMOTE:
		w = maxf(w, hh * 0.95)
	var j := func(): return Vector2(randf_range(-2.5, 2.5), randf_range(-2.0, 2.0))
	if kind == SFX:
		# 톱니 터짐: 타원 둘레에 뾰족한 가시를 번갈아 낸다
		var n := 14 + int(ts.x / 26.0)
		var c := Vector2(w, hh) * 0.5
		for i in n * 2:
			var a := TAU * i / (n * 2) + randf_range(-0.06, 0.06)
			var r := 1.0 if i % 2 == 0 else 0.8
			r *= randf_range(0.94, 1.08) if i % 2 == 0 else 1.0
			poly.append(c + Vector2(cos(a) * c.x * r * 1.06, sin(a) * c.y * r * 1.12))
		tail_tip = c + Vector2(0, c.y * 1.1)
	else:
		# 살짝 비뚤어진 사각형 (만화 말풍선처럼 모서리마다 조금씩 어긋남) → 둥근 모서리로 부풀린다
		var r := 5.0
		var q := PackedVector2Array([Vector2(r, r) + j.call(), Vector2(w - r, r + 2) + j.call(),
				Vector2(w - r, hh - r) + j.call(), Vector2(r, hh - r - 1) + j.call()])
		var rounded := Geometry2D.offset_polygon(q, r, Geometry2D.JOIN_ROUND)
		poly = rounded[0] if rounded.size() > 0 else q
		# 꼬리: 아래 변 왼쪽(또는 오른쪽)에서 아래 바깥쪽으로 뾰족하게
		var tw := clampf(w * 0.22, 12.0, 20.0)
		var th := 13.0 if kind == SAY else 11.0
		var bx := clampf(w * 0.28, 12.0, 34.0)
		var tail: PackedVector2Array
		if not flip:
			tail = PackedVector2Array([Vector2(bx, hh - 6), Vector2(bx + tw, hh - 6), Vector2(bx - 5, hh + th)])
			tail_tip = Vector2(bx - 5, hh + th)
		else:
			tail = PackedVector2Array([Vector2(w - bx - tw, hh - 6), Vector2(w - bx, hh - 6), Vector2(w - bx + 5, hh + th)])
			tail_tip = Vector2(w - bx + 5, hh + th)
		var merged := Geometry2D.merge_polygons(poly, tail)
		for mp in merged:
			if not Geometry2D.is_polygon_clockwise(mp) or merged.size() == 1:
				poly = mp
				break
	_body = poly
	var outl := Geometry2D.offset_polygon(_body, OUTLINE, Geometry2D.JOIN_ROUND)
	_ink = outl[0] if outl.size() > 0 else _body
	_txt_pos = Vector2((w - ts.x) * 0.5, (hh - ts.y) * 0.5 + asc)
	size = Vector2(w, hh)


var _lines_t := -1.0
var _still_drawn := false
var _lines := []


## 튀어나올 때 바깥으로 튀는 짧은 효과선 (만화의 "뿅" 선)
func _pop_lines_start() -> void:
	_lines_t = 0.0
	_lines.clear()
	var c := size * 0.5
	var n := 5 if kind != SAY else 4
	for i in n:
		var a := -PI * 0.5 + randf_range(-1.25, 1.25) + (i - n * 0.5) * 0.35
		_lines.append([a, randf_range(0.85, 1.15)])
	_lines.sort_custom(func(x, y): return x[0] < y[0])


func _draw() -> void:
	if _body.is_empty():
		return
	# 그림자 → 테두리 → 바탕 → 글자 (그림자는 회전과 상관없이 오른쪽 아래로 보이게 되돌려 민다)
	var sh := SHADOW.rotated(-rotation)
	draw_colored_polygon(_shift(_ink, sh), Color(INK, 0.95))
	draw_colored_polygon(_ink, INK)
	draw_colored_polygon(_body, PAPER)
	var f := _font if _font else ThemeDB.fallback_font
	draw_string(f, _txt_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
	if kind != SAY:
		# 굵은 감정 기호 · 의성어는 한 번 더 겹쳐 찍어 두껍게
		draw_string(f, _txt_pos + Vector2(0.8, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)
	# 효과선
	if _lines_t >= 0.0:
		_lines_t += _rdt
		var k := _lines_t / 0.12
		if k < 1.0:
			var c := size * 0.5
			var rad := maxf(size.x, size.y) * 0.5
			for l in _lines:
				var d := Vector2(cos(l[0]), sin(l[0]))
				var r0: float = rad * (1.05 + 0.5 * k) * l[1]
				var r1: float = r0 + 12.0 * (1.0 - k)
				draw_line(c + d * r0, c + d * r1, Color(INK, 1.0 - k), 3.0 * (1.0 - k * 0.6))


static func _shift(p: PackedVector2Array, d: Vector2) -> PackedVector2Array:
	var o := PackedVector2Array()
	o.resize(p.size())
	for i in p.size():
		o[i] = p[i] + d
	return o
