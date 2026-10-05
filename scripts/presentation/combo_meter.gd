class_name ComboMeter
extends Control
## 타격 콤보 점수 (화면 왼쪽).
## 피해를 넣을 때마다(MocoFX.report 와 같은 확정 경로) 타수가 오르고, 콤보 점수 = 피해 × 10 × 배율 이 쌓인다.
## 창(WINDOW, 게임 시간) 안에 다음 피해가 들어오지 않으면 콤보가 끝나고 콤보 점수가 전체 점수(Main.score)로 들어간다.
## 플레이어가 맞으면 BREAK — 콤보 점수의 절반만 들어간다.
## 연출은 모두 실제 시간(히트스탑 · 슬로우모션과 무관하게 쫀득하게): 타격마다 숫자가 크게 튀어 찌그러졌다 늘어나며 자리를 잡고(감쇠 스프링),
## 흔들림 · 기울기 · 흰 섬광 · 색 어긋남 잔상 · 뒤로 흐르는 속도선, 강타는 충격 고리. 랭크가 오르면 도장 찍듯 내려꽂히는 랭크 글자.

const WINDOW := 1.2            # 다음 피해까지 허용 시간 (게임 시간 → 히트스탑 동안은 거의 안 준다)
const SHOW_FROM := 2           # 이 타수부터 화면에 보인다
const PTS := 10                # 피해 1 당 기본 점수
const KILL_PTS := 150          # 콤보 중 처치 보너스 (× 배율)
const MULT_STEP := 10          # 이 타수마다 배율 +0.5
const MULT_MAX := 4.0
const BREAK_KEEP := 0.5        # 맞아서 끊기면 남는 비율
const FINISH_T := 1.0
const BREAK_T := 0.9

const INK := Color("1a0f38")
const PAPER := Color("fff7e8")
const MAGENTA := Color("ff3cbd")
const CYAN := Color("35eed7")
const RED := Color("ff3a55")
## [타수, 이름, 색] — 마지막 랭크는 색이 무지개로 돈다
const RANKS := [
	[5, "NICE", Color("9fe8ff")],
	[15, "GOOD", Color("91e5ac")],
	[30, "GREAT", Color("ffe45a")],
	[50, "AWESOME", Color("ffa040")],
	[80, "STYLISH", Color("ff4fc8")],
	[120, "INSANE", Color("ff4a5a")],
	[180, "LEGENDARY", Color("ffffff")],
]

enum Phase { IDLE, LIVE, FINISH, BREAK }

static var inst: ComboMeter

var phase := Phase.IDLE
var hits := 0
var combo_score := 0
var best := 0
var window := 0.0
var rank := -1
var mult_shown := 1.0
var phase_t := 0.0
var banked := 0                 # 끝날 때 전체 점수로 넘어간 값 (FINISH/BREAK 표시용)
var shown_score := 0.0          # 굴러 올라가는 숫자

# 감쇠 스프링 [변위, 속도]
var _pop := [0.0, 0.0]          # 타수 숫자 크기
var _tilt := [0.0, 0.0]         # 타수 숫자 기울기
var _stamp := [0.0, 0.0]        # 랭크 도장
var _spop := [0.0, 0.0]         # 점수 줄
var _mpop := [0.0, 0.0]         # 배율 알약
var _shake := 0.0
var _flash := 0.0
var _chroma := 0.0
var _bar_flash := 0.0
var _stamp_flash := 0.0
var _streaks: Array = []        # {y, len, t, life, w}
var _rings: Array = []          # {t, life, r0, r1, col, w}
var _chips: Array = []          # {text, t, col, x}
var _shards: Array = []         # {p, v, r, vr, s, col}
var _last_us := 0
var _rng := RandomNumberGenerator.new()
var _font: Font


func _ready() -> void:
	inst = self
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = DamageLog.font()
	_last_us = Time.get_ticks_usec()


func _exit_tree() -> void:
	if inst == self:
		inst = null


# ═══════════════════════════════════════════════════
#  규칙
# ═══════════════════════════════════════════════════

## 확정된 피해 하나 (MocoFX.report 에서). 예전 연출(--vfx=old)이어도 센다
static func hit(amount: int, heavy: bool) -> void:
	if inst and amount > 0:
		inst._on_hit(amount, heavy)


## 콤보 중 처치
static func kill() -> void:
	if inst:
		inst._on_kill()


## 플레이어 피격 → 콤보 끊김
static func hurt() -> void:
	if inst:
		inst._on_hurt()


static func mult_for(n: int) -> float:
	return minf(1.0 + 0.5 * floorf(n / float(MULT_STEP)), MULT_MAX)


static func rank_for(n: int) -> int:
	var r := -1
	for i in RANKS.size():
		if n >= int(RANKS[i][0]):
			r = i
	return r


func mult() -> float:
	return mult_for(hits)


func _on_hit(amount: int, heavy: bool) -> void:
	if phase != Phase.LIVE:
		_start()
	hits += 1
	window = WINDOW
	var pts := int(round(amount * PTS * mult()))
	combo_score += pts
	if hits > best:
		best = hits
	var m := Main.inst
	if m and hits > m.best_combo:
		m.best_combo = hits
	if hits < SHOW_FROM:
		return
	# 연출: 숫자를 크게 튀긴다. 강타는 더 크게 · 더 세게 흔들고 충격 고리
	var big := heavy or amount >= 4
	_pop[0] = maxf(_pop[0], 0.85 if big else 0.55)
	_pop[1] = 0.0
	_tilt[0] = _rng.randf_range(0.11, 0.2) * (1.0 if _rng.randf() < 0.5 else -1.0) * (1.4 if big else 1.0)
	_tilt[1] = 0.0
	_shake = maxf(_shake, 16.0 if big else 9.0)
	_flash = 1.0
	_chroma = 1.0 if big else 0.6
	_bar_flash = 1.0
	_spop[0] = 0.22
	for i in (3 if big else 2):
		_streaks.append({"y": _rng.randf_range(-46, 6), "len": _rng.randf_range(90, 190), "t": 0.0, "life": _rng.randf_range(0.14, 0.22), "w": _rng.randf_range(3, 7)})
	if big:
		_rings.append({"t": 0.0, "life": 0.32, "r0": 30.0, "r1": 130.0, "col": PAPER, "w": 7.0})
	_chip("+", pts, CRIT if big else PAPER)
	var nm := mult()
	if nm > mult_shown:
		mult_shown = nm
		_mpop[0] = 0.7
		_chip("×%.1f" % nm, 0, CYAN)
	var r := rank_for(hits)
	if r > rank:
		rank = r
		_rank_up()
	if _streaks.size() > 12:
		_streaks = _streaks.slice(_streaks.size() - 12)
	if _chips.size() > 6:
		_chips = _chips.slice(_chips.size() - 6)


const CRIT := Color("ffe45a")


func _on_kill() -> void:
	if phase != Phase.LIVE or hits <= 0:
		return
	window = WINDOW
	var pts := int(round(KILL_PTS * mult()))
	combo_score += pts
	if hits < SHOW_FROM:
		return
	_pop[0] = maxf(_pop[0], 0.7)
	_shake = maxf(_shake, 14.0)
	_rings.append({"t": 0.0, "life": 0.36, "r0": 40.0, "r1": 150.0, "col": CYAN, "w": 6.0})
	_chip("KILL +", pts, CYAN)


func _on_hurt() -> void:
	if phase != Phase.LIVE or hits <= 0:
		return
	if hits < SHOW_FROM:
		_bank(combo_score)
		_reset()
		phase = Phase.IDLE
		return
	_bank(int(combo_score * BREAK_KEEP))
	phase = Phase.BREAK
	phase_t = 0.0
	_shake = 26.0
	_chroma = 1.0
	_flash = 1.0
	_stamp[0] = 1.0
	_stamp[1] = 0.0
	_stamp_flash = 1.0
	_rings.append({"t": 0.0, "life": 0.3, "r0": 30.0, "r1": 140.0, "col": RED, "w": 8.0})
	# 숫자가 깨져 흩어지는 조각
	for i in 14:
		var a := _rng.randf_range(-PI, PI)
		_shards.append({"p": Vector2(_rng.randf_range(0, 150), _rng.randf_range(-70, 0)), "v": Vector2(cos(a), sin(a) - 0.6) * _rng.randf_range(160, 420),
			"r": _rng.randf() * TAU, "vr": _rng.randf_range(-12, 12), "s": _rng.randf_range(7, 18), "col": _col() if i % 2 == 0 else PAPER})
	Sfx.play("cbreak", 0.03, -6.0)


func _start() -> void:
	_reset()
	phase = Phase.LIVE
	phase_t = 0.0


func _reset() -> void:
	hits = 0
	combo_score = 0
	rank = -1
	mult_shown = 1.0
	shown_score = 0.0
	_shards.clear()


func _finish() -> void:
	if hits < SHOW_FROM:
		_bank(combo_score)
		_reset()
		phase = Phase.IDLE
		return
	_bank(combo_score)
	shown_score = combo_score
	phase = Phase.FINISH
	phase_t = 0.0
	_stamp[0] = 0.9
	_stamp_flash = 1.0
	_rings.append({"t": 0.0, "life": 0.45, "r0": 50.0, "r1": 190.0, "col": _col(), "w": 8.0})
	var p := Sfx.play("cfinish", 0.0, -7.0)
	if p:
		p.pitch_scale = 1.0 + 0.06 * maxi(rank, 0)


func _bank(v: int) -> void:
	banked = v
	var m := Main.inst
	if m and v > 0:
		m.score += v


func _rank_up() -> void:
	_stamp[0] = 0.95
	_stamp[1] = 0.0
	_stamp_flash = 1.0
	_shake = maxf(_shake, 20.0)
	_rings.append({"t": 0.0, "life": 0.42, "r0": 40.0, "r1": 210.0, "col": _col(), "w": 9.0})
	_rings.append({"t": -0.06, "life": 0.4, "r0": 30.0, "r1": 150.0, "col": PAPER, "w": 4.0})
	var p := Sfx.play("crank", 0.0, -8.0)
	if p:
		p.pitch_scale = 1.0 + 0.08 * rank


## 점수 조각. 같은 종류가 막 생겼으면(0.25초 안) 값을 더하고 다시 톡 튀긴다 — 연사 중에 조각이 겹쳐 뭉개지지 않게
func _chip(tag: String, val: int, col: Color) -> void:
	if val > 0:
		for c: Dictionary in _chips:
			if c.tag == tag and float(c.age) < 0.25:
				c.val = int(c.val) + val
				c.t = minf(float(c.t), 0.04)
				c.col = col if col == CRIT else c.col
				return
	_chips.append({"tag": tag, "val": val, "t": 0.0, "age": 0.0, "col": col, "x": 0.0})


# ═══════════════════════════════════════════════════
#  갱신
# ═══════════════════════════════════════════════════

func _process(dt: float) -> void:
	var now := Time.get_ticks_usec()
	var rdt := clampf((now - _last_us) / 1000000.0, 0.0, 0.1)
	_last_us = now
	if phase == Phase.LIVE:
		window -= dt                    # 게임 시간 (히트스탑 · 슬로우모션 동안은 천천히 준다)
		if window <= 0.0:
			_finish()
	elif phase == Phase.FINISH or phase == Phase.BREAK:
		phase_t += rdt
		if phase_t >= (FINISH_T if phase == Phase.FINISH else BREAK_T):
			phase = Phase.IDLE
			_reset()
	# 스프링은 1/240초로 쪼개 적분 (프레임이 끊겨도 튀지 않게)
	var left := rdt
	while left > 0.0:
		var h := minf(left, 1.0 / 240.0)
		left -= h
		_spring(_pop, 520.0, 19.0, h)
		_spring(_tilt, 340.0, 15.0, h)
		_spring(_stamp, 420.0, 17.0, h)
		_spring(_spop, 600.0, 22.0, h)
		_spring(_mpop, 500.0, 18.0, h)
	_shake *= exp(-rdt * 26.0)
	_flash = maxf(0.0, _flash - rdt / 0.11)
	_chroma = maxf(0.0, _chroma - rdt / 0.14)
	_bar_flash = maxf(0.0, _bar_flash - rdt / 0.2)
	_stamp_flash = maxf(0.0, _stamp_flash - rdt / 0.16)
	if phase == Phase.LIVE:
		shown_score = move_toward(shown_score, combo_score, maxf(absf(combo_score - shown_score) * rdt * 12.0, rdt * 60.0))
	for s: Dictionary in _streaks:
		s.t = float(s.t) + rdt
	_streaks = _streaks.filter(func(s): return float(s.t) < float(s.life))
	for r: Dictionary in _rings:
		r.t = float(r.t) + rdt
	_rings = _rings.filter(func(r): return float(r.t) < float(r.life))
	for c: Dictionary in _chips:
		c.t = float(c.t) + rdt
		c.age = float(c.age) + rdt
	_chips = _chips.filter(func(c): return float(c.t) < 0.6)
	for s: Dictionary in _shards:
		s.v = (s.v as Vector2) + Vector2(0, 1100.0) * rdt
		s.p = (s.p as Vector2) + (s.v as Vector2) * rdt
		s.r = float(s.r) + float(s.vr) * rdt
	visible = not Main.ui_hidden
	queue_redraw()


func _spring(s: Array, k: float, d: float, h: float) -> void:
	s[1] += (-k * s[0] - d * s[1]) * h
	s[0] += s[1] * h


func _col() -> Color:
	if rank < 0:
		return PAPER
	if rank == RANKS.size() - 1:
		return Color.from_hsv(fmod(Time.get_ticks_msec() * 0.0006, 1.0), 0.55, 1.0)
	return RANKS[rank][2]


func ui_scale() -> float:
	return clampf(size.y / 900.0, 0.7, 1.5)


## 화면 왼쪽, 좌상단 상태 카드와 좌하단 드론 카드 사이 (기준점 = 타수 숫자의 기준선)
func anchor() -> Vector2:
	var s := ui_scale()
	return Vector2(64.0 * s, maxf(size.y * 0.43, 330.0 * s))


# ═══════════════════════════════════════════════════
#  그리기 (디자인 좌표: 기준점 = 타수 숫자 왼쪽 아래 기준선)
# ═══════════════════════════════════════════════════

const NUM_SIZE := 112
const HITS_SIZE := 32
const RANK_SIZE := 38
const SCORE_SIZE := 34
const SKEW := -0.2


func _draw() -> void:
	if phase == Phase.IDLE or (phase == Phase.LIVE and hits < SHOW_FROM):
		return
	var s := ui_scale()
	var shake := Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * _shake
	var base := Transform2D(0.0, Vector2(s, s), 0.0, anchor() + shake * s)
	var alpha := 1.0
	var shrink := 1.0
	var slide := 0.0
	if phase == Phase.FINISH:
		var k := phase_t / FINISH_T
		alpha = 1.0 - smoothstep(0.55, 1.0, k)
		slide = -60.0 * smoothstep(0.6, 1.0, k)
	elif phase == Phase.BREAK:
		var k := phase_t / BREAK_T
		alpha = 1.0 - smoothstep(0.45, 1.0, k)
		shrink = 1.0 - 0.15 * k
	base = base * Transform2D(0.0, Vector2.ONE * shrink, 0.0, Vector2(slide, 0))
	var col := _col()
	if phase == Phase.BREAK:
		col = RED
	var num := str(hits)
	var nw := _font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, NUM_SIZE).x
	var cap := NUM_SIZE * 0.7

	# ── 뒷판: 기울어진 잉크 띠 + 랭크 색 줄 (숫자와 같이 튄다)
	var kick: float = _pop[0] * 26.0
	draw_set_transform_matrix(base)
	var band_w := nw + 210.0 + kick
	_para(Vector2(-30 + kick * 0.3, -cap - 22), Vector2(band_w, cap + 44), 26.0, Color(INK, 0.6 * alpha))
	_para(Vector2(-30 + kick * 0.3, -cap - 22), Vector2(9, cap + 44), 26.0, Color(col, 0.95 * alpha))
	# 속도선 (숫자 뒤에서 왼쪽으로 흩날림)
	for st: Dictionary in _streaks:
		var k := float(st.t) / float(st.life)
		var x1 := nw * 0.6 - 420.0 * k
		var a := (1.0 - k) * alpha
		draw_line(Vector2(x1, float(st.y) - cap * 0.4), Vector2(x1 + float(st.len) * (1.0 - k * 0.5), float(st.y) - cap * 0.4), Color(col, 0.8 * a), float(st.w))

	# ── 충격 고리
	var center := Vector2(nw * 0.5, -cap * 0.5)
	for r: Dictionary in _rings:
		if float(r.t) < 0.0:
			continue
		var k := float(r.t) / float(r.life)
		var e := 1.0 - pow(1.0 - k, 3.0)
		draw_arc(center, lerpf(float(r.r0), float(r.r1), e), 0, TAU, 48, Color(r.col as Color, (1.0 - k) * 0.85 * alpha), float(r.w) * (1.0 - k * 0.7))

	# ── 타수 숫자: 피벗(숫자 가운데)에서 찌그러졌다 늘어나며 자리를 잡는다
	var p: float = _pop[0]
	var v: float = _pop[1]
	var sx := 1.0 + p * 0.75 - v * 0.0065
	var sy := 1.0 + p * 0.75 + v * 0.0105
	var drop := Vector2.ZERO
	var droll := 0.0
	if phase == Phase.BREAK:
		var k := phase_t / BREAK_T
		drop = Vector2(-20.0 * k, 260.0 * k * k)
		droll = 0.5 * k * k
	var t_num := base * Transform2D(_tilt[0] + droll, Vector2(maxf(sx, 0.4), maxf(sy, 0.4)), SKEW, center + drop)
	draw_set_transform_matrix(t_num)
	var at := Vector2(-nw * 0.5, cap * 0.5)
	_big_text(num, at, NUM_SIZE, col, alpha, 16)
	# HITS (숫자 오른쪽 아래, 숫자보다 덜 튄다)
	var t_hits := base * Transform2D(_tilt[0] * 0.4, Vector2.ONE * (1.0 + p * 0.25), SKEW, Vector2(nw + 14 + kick * 0.5, -8))
	draw_set_transform_matrix(t_hits)
	_outlined("HITS", Vector2.ZERO, HITS_SIZE, Color(PAPER, alpha), 9, alpha)

	# ── 랭크 도장 (숫자 위)
	if rank >= 0 or phase != Phase.LIVE:
		var label: String = RANKS[rank][1] if rank >= 0 else ""
		if phase == Phase.FINISH:
			label = "FINISH!"
		elif phase == Phase.BREAK:
			label = "BREAK"
		if label != "":
			var stp: float = _stamp[0]
			var lw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, RANK_SIZE).x
			var pivot := Vector2(lw * 0.5 + 6, -cap - 40)
			var breathe := 1.0 + 0.03 * sin(Time.get_ticks_msec() * 0.008)
			var t_r := base * Transform2D(-0.09 - stp * 0.18, Vector2.ONE * (1.0 + stp) * breathe, SKEW, pivot)
			draw_set_transform_matrix(t_r)
			var rc := RED if phase == Phase.BREAK else col
			_para(Vector2(-lw * 0.5 - 14, -RANK_SIZE * 0.5 - 8), Vector2(lw + 28, RANK_SIZE + 12), 10.0, Color(INK, 0.85 * alpha))
			_big_text(label, Vector2(-lw * 0.5, RANK_SIZE * 0.36), RANK_SIZE, rc.lerp(Color.WHITE, _stamp_flash), alpha, 9)

	# ── 남은 시간 막대
	draw_set_transform_matrix(base)
	var bar_w := 300.0
	var frac := clampf(window / WINDOW, 0.0, 1.0) if phase == Phase.LIVE else (1.0 if phase == Phase.FINISH else 0.0)
	var by := 22.0
	_para(Vector2(-6, by), Vector2(bar_w + 6, 12), 6.0, Color(INK, 0.75 * alpha))
	var blink := 1.0
	if phase == Phase.LIVE and frac < 0.3:
		blink = 0.45 + 0.55 * absf(sin(Time.get_ticks_msec() * 0.02))
	var fill_c := col.lerp(Color.WHITE, _bar_flash * 0.8)
	if frac > 0.0:
		_para(Vector2(-2, by + 2), Vector2(bar_w * frac, 8), 4.0, Color(fill_c, alpha * blink))
		_para(Vector2(-2 + bar_w * frac - 10, by + 2), Vector2(10, 8), 4.0, Color(Color.WHITE, alpha * blink))

	# ── 점수 줄: 배율 알약 + 굴러 올라가는 콤보 점수
	var sy0 := by + 58.0
	var mtxt := "×%.1f" % mult_for(hits)
	var mw := _font.get_string_size(mtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	var mp: float = _mpop[0]
	var t_m := base * Transform2D(0.0, Vector2.ONE * (1.0 + mp * 0.6), SKEW, Vector2(mw * 0.5 + 10, sy0 - 12))
	draw_set_transform_matrix(t_m)
	_para(Vector2(-mw * 0.5 - 12, -18), Vector2(mw + 24, 34), 8.0, Color(CYAN.lerp(Color.WHITE, clampf(mp, 0, 1)), 0.95 * alpha))
	draw_string(_font, Vector2(-mw * 0.5, 10), mtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(INK, alpha))
	var stext := _commas(int(shown_score)) if phase != Phase.BREAK else _commas(banked)
	var sp: float = _spop[0]
	var t_s := base * Transform2D(0.0, Vector2(1.0 + sp * 0.5, 1.0 + sp * 0.8), SKEW, Vector2(mw + 34, sy0 - 12))
	draw_set_transform_matrix(t_s)
	_outlined(stext, Vector2(0, SCORE_SIZE * 0.36), SCORE_SIZE, Color(PAPER, alpha), 9, alpha)
	var stw := _font.get_string_size(stext, HORIZONTAL_ALIGNMENT_LEFT, -1, SCORE_SIZE).x

	# 얻은 점수 조각 (점수 오른쪽에서 튀어 올라 사라진다)
	draw_set_transform_matrix(base)
	for ci in _chips.size():
		var c: Dictionary = _chips[_chips.size() - 1 - ci]
		var k := float(c.t) / 0.6
		var pop := 1.0 + 0.6 * pow(1.0 - minf(k * 5.0, 1.0), 2.0)
		var cpos := Vector2(mw + 34 + stw + 16 + float(c.x), sy0 - 40.0 * (1.0 - pow(1.0 - k, 2.0)) - 26.0 * ci)
		draw_set_transform_matrix(base * Transform2D(0.0, Vector2.ONE * pop, SKEW, cpos))
		var ct: String = str(c.tag) + (_commas(int(c.val)) if int(c.val) > 0 else "")
		_outlined(ct, Vector2.ZERO, 24, Color(c.col as Color, (1.0 - smoothstep(0.5, 1.0, k)) * alpha), 7, alpha)

	# FINISH: 전체 점수로 넘어간 값이 위로 떠오른다
	if phase == Phase.FINISH and banked > 0:
		var k := phase_t / FINISH_T
		var t_b := base * Transform2D(0.0, Vector2.ONE * (1.0 + 0.4 * pow(1.0 - minf(k * 4.0, 1.0), 2.0)), SKEW, Vector2(0, sy0 + 46 - 30 * k))
		draw_set_transform_matrix(t_b)
		_outlined("+%s  SCORE" % _commas(banked), Vector2.ZERO, 26, Color(CRIT, 1.0 - smoothstep(0.7, 1.0, k)), 8, 1.0)

	# BREAK 조각
	draw_set_transform_matrix(base)
	for sh: Dictionary in _shards:
		var c := sh.p as Vector2
		var rr := float(sh.r)
		var ss := float(sh.s)
		var pts := PackedVector2Array([c + Vector2(cos(rr), sin(rr)) * ss, c + Vector2(cos(rr + 2.3), sin(rr + 2.3)) * ss * 0.7, c + Vector2(cos(rr + 4.1), sin(rr + 4.1)) * ss * 0.9])
		draw_colored_polygon(pts, Color(sh.col as Color, alpha))
	draw_set_transform_matrix(Transform2D.IDENTITY)


## 큰 글자: 잉크 그림자 → 색 어긋남 잔상 → 두꺼운 잉크 외곽선 → 색 → 흰 섬광
func _big_text(t: String, at: Vector2, sz: int, col: Color, alpha: float, ol: int) -> void:
	draw_string_outline(_font, at + Vector2(6, 7), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, ol, Color(INK, 0.7 * alpha))
	draw_string(_font, at + Vector2(6, 7), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(INK, 0.7 * alpha))
	if _chroma > 0.0:
		var off := 10.0 * _chroma
		draw_string(_font, at + Vector2(-off, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(MAGENTA, 0.75 * _chroma * alpha))
		draw_string(_font, at + Vector2(off, 0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(CYAN, 0.75 * _chroma * alpha))
	draw_string_outline(_font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, ol, Color(INK, alpha))
	draw_string(_font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(col.lerp(Color.WHITE, _flash), alpha))


func _outlined(t: String, at: Vector2, sz: int, col: Color, ol: int, alpha: float) -> void:
	draw_string_outline(_font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, ol, Color(INK, alpha * col.a))
	draw_string(_font, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


## 오른쪽으로 기운 평행사변형 (pos = 왼쪽 위, lean = 윗변이 오른쪽으로 밀린 정도)
func _para(pos: Vector2, sz: Vector2, lean: float, col: Color) -> void:
	if col.a <= 0.0:
		return
	draw_colored_polygon(PackedVector2Array([
		pos + Vector2(lean, 0), pos + Vector2(sz.x + lean, 0),
		pos + Vector2(sz.x, sz.y), pos + Vector2(0, sz.y)]), col)


static func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
