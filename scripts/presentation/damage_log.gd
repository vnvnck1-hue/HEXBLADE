class_name DamageLog
extends Control
## 피해 숫자 (docs/damage-log.md). 땅굴크루 v7.8.1 드릴 데미지 로그(J.dmg / J.update / J.drawDmg)의 손맛 —
## 크게 튀어나오는 팝 · 세로 눌림 · 위로 튀는 포물선 · 강타 기울기 · ARCO 글꼴 — 을 바탕으로,
## 우리 화면(중간 밝기 남보라 바닥, 쿼터뷰, 적 위 체력바)에서 잘 읽히게 다시 맞췄다:
##   - 원본 0.31초 → 일반 0.95초 / 강타 1.2초. 튀어 오른 뒤 머리 위에 잠깐 떠 있다가(정점 뒤 천천히 가라앉음) 줄어들며 사라진다.
##   - 원본 반투명(.55) 얇은 갈색 외곽선 → 불투명 짙은 남보라 두꺼운 외곽선 + 아래 그림자. 밝은 피격 섬광 위에서도 글자가 끊기지 않는다.
##   - 원본 21/64 → 일반 34 / 강타 54 (1280×800 기준). 강타는 첫 0.1초 흰빛으로 번쩍였다가 노랑.
##   - 원본 169° 부채꼴 + 강한 중력(숫자가 대상 몸 위로 떨어져 섬광에 묻힘) → 위쪽 36° 부채꼴 + 짧은 정점, 몸이 아니라 머리 위에서 생긴다.
##   - 연사 숫자는 새 숫자가 나오면 같은 대상의 이전 숫자를 위로 밀어 올려 살짝 겹친 세로 기둥이 된다 (대상당 최대 6개).
##   - 연속 타격 열기: 같은 대상을 끊김 없이(0.75초 안에 다음 타격) 때릴수록 숫자가 크림 → 노랑 → 주황 → 붉은 분홍으로 달아오른다
##     (14타에서 최대). 움직임 변화(크기·팝·떨림·후광)는 색을 거드는 정도로만 작게.
## 프리셋 (J 키 / --dmglog=stack|bounce, static 이라 씬을 다시 불러도 유지):
##   BOUNCE — 위로 튀어 올랐다가 중력으로 자연스럽게 떨어지며 사라짐 (쌓지 않음, 기본)
##   STACK  — 머리 위에 떠서 새 숫자가 이전 숫자를 위로 밀어 쌓는 기둥
## 숫자는 생긴 월드 점에 남고 그 점의 화면 투영 + 오프셋에 그린다. 실제 시간 (히트스탑·슬로모션에 멈추지 않게).

# ── 크기 · 색 ──
const SIZE := 34.0
const SIZE_BIG := 54.0
const SIZE_STATUS := 34.0
const FLASH := Color("ffffff")
const INK := Color("1b0b38")          # 외곽선 (게임 INK 보다 짙게 — 배경 남보라와 분리)
const OUTLINE := 0.26                 # 외곽선 두께 = 글자 크기 × 이 값 (지름 기준)
const SHADOW := Color(0.04, 0.0, 0.10, 0.55)
const SHADOW_OFF := 0.09              # 그림자 아래 오프셋 = 글자 크기 × 이 값

# ── 시간 ──
const LIFE := 0.95
const LIFE_BIG := 1.2
const LIFE_STATUS := 1.1
const FADE_FROM := 0.68               # 수명의 이 비율부터 사라짐 (그 전까지 완전 불투명)
const POP := 1.55                     # 원본 1.41 보다 조금 크게 시작
const POP_BIG := 1.8
const POP_T := 0.13                   # 팝이 1 로 돌아오는 시간
const SQUASH := 0.45                  # 원본 dmgSquash
const SQUASH_T := 0.08
const FLASH_T := 0.1

# ── 움직임 (화면 px) ──
const RISE := 360.0                   # 처음 위로 튀는 속도
const RISE_RAND := 0.3
const ARC_SPREAD := 36.0              # 위쪽 부채꼴 (도)
const GRAVITY := 1500.0
const DRAG := 0.90                    # 60fps 기준 프레임당
const SINK := 22.0                    # 정점 뒤 가라앉는 최대 속도 (떠 있는 느낌)
const JITTER := Vector2(18, 6)
const TILT := 0.10                    # 일반 숫자 시작 기울기 (rad, ±)
const TILT_BIG := 11.0                # 강타 기울기 (도, ±)
const SPIN := 0.6                     # 회전 속도 (rad/s, ±, 감쇠)
const MAX := 24
const PER_TARGET := 6                 # 같은 대상의 숫자 기둥 최대 (넘으면 가장 오래된 것이 빨리 사라짐)
const STACK := 0.68                   # 새 숫자가 나오면 같은 대상의 이전 숫자를 (새 글자 크기 × 이 값)만큼 위로 민다 (1 미만 = 살짝 겹침)
const STACK_RATE := 22.0              # 밀려 올라가는 속도 (지수 접근, 1/s)
const EDGE := 12.0                    # 화면 가장자리 여유

# ── BOUNCE 프리셋 ──
const B_RISE := 470.0                 # 처음 위로 튀는 속도 (정점 약 70px)
const B_SPREAD := 70.0                # 위쪽 부채꼴 (도)
const B_GRAVITY := 1550.0
const B_DRAG := 0.985                 # 거의 감속 없이 포물선
const B_LIFE := 0.85
const B_LIFE_BIG := 1.0
const B_FADE_FROM := 0.55             # 떨어지기 시작할 즈음부터 사라짐
const B_SPIN := 1.2                   # 날아가는 쪽으로 기우는 회전 (rad/s)

const PRESETS := ["stack", "bounce"]
const PRESET_NAMES := {"stack": "STACK · 머리 위 기둥", "bounce": "BOUNCE · 튀었다 떨어짐"}
static var preset := "bounce"       # 기본 = BOUNCE (2026-10-06)
static var _arg_read := false

# ── 연속 타격 열기 (heat 0 → 1) ──
const CHAIN_GAP := 0.75               # 같은 대상의 다음 타격이 이 시간 안에 오면 연속
const CHAIN_FULL := 14                # 이 타수에서 열기 최대
const HEAT_RAMP := [                  # 글자 색: 크림 → 연노랑 → 노랑 → 주황 → 붉은 분홍
	Color("fffaf0"), Color("fff1a0"), Color("ffc93a"), Color("ff8a2a"), Color("ff3b5c")]
const HEAT_BIG_MIN := 0.4             # 강타는 열기가 낮아도 노랑부터
const HEAT_INK := Color("3d0717")     # 열기 최대 외곽선 (짙은 와인)
const HEAT_GLOW := Color("ff6a1e")    # 열기 후광 (외곽선 바깥)
const HEAT_SIZE := 0.1                # 크기 +10%
const HEAT_POP := 0.12                # 팝 +0.12 (POP_MAX 안에서)
const POP_MAX := 1.9                  # 팝 상한
const HEAT_SQUASH := 0.05
const HEAT_TILT := 0.3                # 기울기 ×(1 + 이 값)
const HEAT_RISE := 0.08
const HEAT_LIFE := 0.1                # 수명 +0.1초
const HEAT_SHAKE := 1.5               # 생긴 직후 0.2초 떨림 (px)
const HEAT_GLOW_A := 0.22             # 후광 최대 투명도
const HEAT_GLOW_W := 0.08             # 후광 두께 = 글자 × 이 값

static var _font: Font

var entries: Array = []         # {anchor, off, vx, vy, rot, vr, t, life, big, text, value, col, target(WeakRef), born, status, pop, lift, lift_to}
var _last_us := 0
var _chain := {}                # 대상 id → [연속 타수, 마지막 시각]


## 프리셋 고르기 (이름 또는 다음 것). 바뀐 이름을 돌려준다
static func use(name := "") -> String:
	if name == "":
		name = PRESETS[(PRESETS.find(preset) + 1) % PRESETS.size()]
	if name in PRESETS:
		preset = name
	return preset


static func _read_arg() -> void:
	if _arg_read:
		return
	_arg_read = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dmglog="):
			use(a.substr(9))


static func font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/ARCO.otf") as Font
		if _font == null:
			_font = ThemeDB.fallback_font
	return _font


func _ready() -> void:
	_read_arg()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 같은 대상 연속 타격 수를 올리고 열기(0~1)를 돌려준다
func _heat(target: Object) -> float:
	if target == null:
		return 0.0
	var now := Time.get_ticks_msec() * 0.001
	var id := target.get_instance_id()
	var c: Array = _chain.get(id, [0, -99.0])
	var n: int = (int(c[0]) + 1) if now - float(c[1]) < CHAIN_GAP else 1
	_chain[id] = [n, now]
	if _chain.size() > 64:               # 오래된 대상 정리
		for k in _chain.keys():
			if now - float(_chain[k][1]) > CHAIN_GAP:
				_chain.erase(k)
	return clampf(float(n - 1) / float(CHAIN_FULL - 1), 0.0, 1.0)


## 지금 그 대상의 연속 타수 (검사용)
func chain_of(target: Object) -> int:
	if target == null or not _chain.has(target.get_instance_id()):
		return 0
	var c: Array = _chain[target.get_instance_id()]
	return int(c[0]) if Time.get_ticks_msec() * 0.001 - float(c[1]) < CHAIN_GAP else 0


static func heat_color(h: float) -> Color:
	var x := clampf(h, 0.0, 1.0) * (HEAT_RAMP.size() - 1)
	var i := mini(int(x), HEAT_RAMP.size() - 2)
	return (HEAT_RAMP[i] as Color).lerp(HEAT_RAMP[i + 1], x - i)


## 새 숫자 하나
func spawn(anchor: Vector3, value: int, big: bool, target: Object = null) -> Dictionary:
	var h := _heat(target)
	var bounce := preset == "bounce"
	var half := deg_to_rad(B_SPREAD if bounce else ARC_SPREAD) * 0.5
	var ang := -PI * 0.5 + randf_range(-1.0, 1.0) * half
	var spd := (B_RISE if bounce else RISE) * (1.0 + randf_range(-RISE_RAND, RISE_RAND) * 0.5) * (1.12 if big else 1.0) * (1.0 + HEAT_RISE * h)
	var tilt := 1.0 + HEAT_TILT * h
	var e := {
		"anchor": anchor,
		"off": Vector2(randf_range(-0.5, 0.5) * JITTER.x, randf_range(-0.5, 0.5) * JITTER.y),
		"vx": cos(ang) * spd,
		"vy": sin(ang) * spd,
		"rot": (randf_range(-1.0, 1.0) * deg_to_rad(TILT_BIG) if big else randf_range(-TILT, TILT)) * tilt,
		"vr": (cos(ang) * B_SPIN + randf_range(-0.3, 0.3)) if bounce else randf_range(-SPIN, SPIN),
		"t": 0.0,
		"life": ((B_LIFE_BIG if big else B_LIFE) if bounce else (LIFE_BIG if big else LIFE)) + HEAT_LIFE * h,
		"mode": preset,
		"big": big,
		"value": value,
		"text": str(value),
		"col": heat_color(maxf(h, HEAT_BIG_MIN) if big else h),
		"target": weakref(target) if target else null,
		"born": Time.get_ticks_msec() * 0.001,
		"status": false,
		"pop": minf((POP_BIG if big else POP) + HEAT_POP * h, POP_MAX),
		"lift": 0.0,
		"lift_to": 0.0,
		"heat": h,
	}
	if not bounce:
		_stack(e)
	_push(e)
	return e


## 같은 대상의 이전 숫자를 위로 밀고, 기둥이 너무 길면 가장 오래된 것을 빨리 사라지게 한다
func _stack(e: Dictionary) -> void:
	if e.target == null:
		return
	var tgt: Object = e.target.get_ref()
	if tgt == null:
		return
	var push := (SIZE_BIG if e.big else SIZE) * (1.0 + HEAT_SIZE * float(e.heat)) * STACK
	var mine: Array = []
	for o: Dictionary in entries:
		if o.mode == "stack" and o.target != null and o.target.get_ref() == tgt and float(o.t) < float(o.life) * FADE_FROM:
			o.lift_to = float(o.lift_to) + push
			mine.append(o)
	var extra := mine.size() + 1 - PER_TARGET
	for i in maxi(0, extra):
		var o: Dictionary = mine[i]               # entries 는 생긴 순서라 앞쪽이 오래된 것
		o.t = maxf(float(o.t), float(o.life) * FADE_FROM)


## 합산으로 숫자가 바뀌었을 때 다시 톡 튀게
func bump(e: Dictionary) -> void:
	e.t = minf(float(e.t), 0.03)


## 상태 글자 (포물선 없이 감속하며 떠오름)
func spawn_status(anchor: Vector3, text: String, col: Color, target: Object = null) -> void:
	var top := 0.0          # 같은 대상의 숫자 기둥 위에 띄운다
	for o: Dictionary in entries:
		if not o.status and target != null and o.target != null and o.target.get_ref() == target:
			top = maxf(top, float(o.lift_to) + (SIZE_BIG if o.big else SIZE) * 0.5)
	_push({
		"anchor": anchor, "off": Vector2(0, -44.0 - top), "vx": 0.0, "vy": -90.0,
		"rot": 0.0, "vr": 0.0, "t": 0.0, "life": LIFE_STATUS, "big": false, "value": 0, "text": text, "col": col,
		"target": weakref(target) if target else null, "born": Time.get_ticks_msec() * 0.001, "status": true, "pop": POP,
		"lift": 0.0, "lift_to": 0.0, "heat": 0.0, "mode": "status",
	})


func _push(e: Dictionary) -> void:
	entries.append(e)
	if entries.size() > MAX:
		entries = entries.slice(entries.size() - MAX)


func _process(_dt: float) -> void:
	var us := Time.get_ticks_usec()
	var dt := 0.0 if _last_us == 0 else minf((us - _last_us) * 1e-6, 0.1)
	_last_us = us
	if entries.is_empty():
		return
	var drag := pow(DRAG, dt * 60.0)
	var bdrag := pow(B_DRAG, dt * 60.0)
	var keep: Array = []
	for e: Dictionary in entries:
		e.t = float(e.t) + dt
		e.lift = lerpf(float(e.lift), float(e.lift_to), 1.0 - exp(-STACK_RATE * dt))
		if e.status:
			e.off.y += float(e.vy) * dt
			e.vy = float(e.vy) * pow(0.93, dt * 60.0)
		elif e.mode == "bounce":
			e.vy = (float(e.vy) + B_GRAVITY * dt) * bdrag
			e.vx = float(e.vx) * bdrag
			e.off += Vector2(e.vx, e.vy) * dt
			e.rot = float(e.rot) + float(e.vr) * dt
		else:
			e.vy = minf((float(e.vy) + GRAVITY * dt) * drag, SINK)
			e.vx = float(e.vx) * drag
			e.off += Vector2(e.vx, e.vy) * dt
			e.vr = float(e.vr) * pow(0.95, dt * 60.0)
			e.rot = float(e.rot) + float(e.vr) * dt
		if float(e.t) < float(e.life):
			keep.append(e)
	entries = keep
	queue_redraw()


func _draw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or entries.is_empty():
		return
	var f := font()
	var vp := get_viewport_rect().size
	for e: Dictionary in entries:
		var w: Vector3 = e.anchor
		if cam.is_position_behind(w):
			continue
		var t := float(e.t)
		var k := t / float(e.life)
		var fade_from := B_FADE_FROM if e.mode == "bounce" else FADE_FROM
		var pop := 1.0 + (float(e.pop) - 1.0) * maxf(0.0, 1.0 - t / POP_T)
		var shrink := 1.0 - 0.25 * smoothstep(fade_from, 1.0, k)
		var h := float(e.heat)
		var sq_y := 1.0 + (SQUASH + HEAT_SQUASH * h) * maxf(0.0, 1.0 - t / SQUASH_T)
		var sq_x := 1.0 / maxf(0.55, sq_y)
		var base := SIZE_STATUS if e.status else (SIZE_BIG if e.big else SIZE)
		var sz := maxi(8, roundi(base * (1.0 + HEAT_SIZE * h) * pop * shrink))
		var a := 1.0 - smoothstep(fade_from, 1.0, k)
		var text: String = e.text
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var at := Vector2(-tw * 0.5, (f.get_ascent(sz) - f.get_descent(sz)) * 0.5)   # 가운데 정렬 · 세로 가운데
		var p: Vector2 = cam.unproject_position(w) + (e.off as Vector2) - Vector2(0, float(e.lift))
		if h > 0.0 and t < 0.2:          # 달아오를수록 생긴 직후 살짝 떤다
			p += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * HEAT_SHAKE * h * (1.0 - t / 0.2)
		# 화면 밖으로 나가지 않게 (가장자리의 적도 숫자는 읽힌다)
		var hw := tw * 0.5 + EDGE
		var hh := sz * 0.5 + EDGE
		if p.x < -200 or p.y < -200 or p.x > vp.x + 200 or p.y > vp.y + 200:
			continue
		p.x = clampf(p.x, hw, maxf(hw, vp.x - hw))
		p.y = clampf(p.y, hh, maxf(hh, vp.y - hh))
		var ol := maxi(4, roundi(sz * OUTLINE))
		draw_set_transform(p, float(e.rot), Vector2(sq_x, sq_y))
		# 1) 아래 그림자 (외곽선 모양 그대로 내려서)
		draw_string_outline(f, at + Vector2(0, sz * SHADOW_OFF), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, ol, Color(SHADOW, SHADOW.a * a))
		# 2) 열기 후광 (외곽선 바깥으로 번지는 주황, 생긴 직후 더 밝게)
		if h > 0.05:
			var ga := HEAT_GLOW_A * (0.6 + 0.4 * maxf(0.0, 1.0 - t / 0.25)) * h * a
			draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, ol + roundi(sz * HEAT_GLOW_W * h) + 2, Color(HEAT_GLOW, ga))
		# 3) 외곽선 · 4) 글자
		draw_string_outline(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, ol, Color(INK.lerp(HEAT_INK, h), a))
		var c: Color = e.col
		if e.big:
			c = FLASH.lerp(c, smoothstep(0.0, FLASH_T, t))
		draw_string(f, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(c, a))
	draw_set_transform(Vector2.ZERO)
