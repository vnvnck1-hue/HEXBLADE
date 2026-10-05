class_name HudPresets
extends Control
## 플레이어 상태 HUD 프리셋 (H 키로 실시간 전환, 실행 인자 --hud=이름).
## 판정·수치는 건드리지 않고 Player 값을 읽어 그리기만 한다. 리서치·설계: docs/hud-presets.md
##   STRIKER  : 젠레스 존 제로식. 좌상단 기체 카드(헥스 엠블럼·사선 장갑칸) + 우하단 원형 스킬 버튼 묶음
##   CORNERS  : Returnal·Hades식 하단 분할. 왼쪽 아래 생존(장갑·회피·부스터), 오른쪽 아래 무장(탄창·에너지·미사일)
##   COCKPIT  : Armored Core·Ruiner식 디제틱. 기체 둘레 호(장갑·부스터·회피)와 조준점 둘레 호(탄창·에너지), 평소엔 옅게
##   TACTICAL : 좌상단 자리는 지키되 글자 대신 아이콘·칸으로 압축한 한 장짜리 패널
##   LEGACY   : 기존 세로 나열 (비교용)

const NAMES := ["STRIKER", "CORNERS", "COCKPIT", "TACTICAL", "LEGACY"]
const DESCS := [
	"젠레스 존 제로식 — 좌상단 기체 카드 · 우하단 원형 스킬 버튼",
	"Returnal · Hades식 — 왼쪽 아래 생존 · 오른쪽 아래 무장",
	"Armored Core · Ruiner식 — 기체와 조준점 둘레에 붙는 디제틱 호, 평소엔 옅게",
	"정돈된 좌상단 — 글자 대신 아이콘 · 칸으로 압축한 패널",
	"기존 세로 나열 (비교용)",
]
enum { STRIKER, CORNERS, COCKPIT, TACTICAL, LEGACY }

## 씬을 다시 불러도 고른 프리셋이 유지된다
static var current := STRIKER

const INK := Color(0.03, 0.03, 0.09, 0.72)       # 판 바탕
const INK_LINE := Color(0.45, 0.42, 0.85, 0.55)  # 판 테두리
const DIM := Color(0.62, 0.6, 0.86)              # 보조 글자
const HP_ON := Color("9d8cff")
const HP_LOW := Color("ff3a5a")
const BOOST_C := Color("ffb040")
const AMMO_C := Color("ffe070")
const EN_C := Color("5af0ff")
const MSL_C := Color("ffa040")

var hud: Hud
var font: Font
var t := 0.0
var s := 1.0                 # 900px 높이 기준 배율
var W := 1600.0
var H := 900.0

# 연출 상태 (실제 시간으로 흐른다)
var hp_prev := -1
var hp_trail := 0.0          # 깎인 칸이 하얗게 남았다 사라지는 잔량
var hp_hit := 0.0            # 피격 직후 흔들림
var en_prev := -1
var en_pop := 0.0
var msl_prev := -1
var msl_pop := 0.0
var mag_prev := -1
var dash_ready_pop := 0.0
var dash_was_ready := true
var skill_ready_pop := 0.0
var skill_was_ready := true
var cockpit_a := {"hp": 0.4, "boost": 0.0, "dash": 0.0, "en": 0.4}


func _init(h: Hud) -> void:
	hud = h
	font = h.font
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(dt: float) -> void:
	var rdt := dt / maxf(Engine.time_scale, 0.01)
	t += rdt
	var m := Main.inst
	if m == null or m.player == null:
		return
	var p := m.player
	if hp_prev < 0:
		hp_prev = p.hp
		hp_trail = p.hp
	if p.hp < hp_prev:
		hp_hit = 1.0
	elif p.hp > hp_prev:
		hp_trail = p.hp
	hp_prev = p.hp
	# 잔량은 잠깐 버텼다가 따라 내려간다
	if hp_hit < 0.6:
		hp_trail = move_toward(hp_trail, p.hp, rdt * 4.0)
	hp_hit = maxf(0.0, hp_hit - rdt * 2.2)
	if en_prev >= 0 and p.energy != en_prev:
		en_pop = 1.0
	en_prev = p.energy
	en_pop = maxf(0.0, en_pop - rdt * 3.0)
	var msl := p.missiles + p.ult_queue
	if msl_prev >= 0 and msl != msl_prev:
		msl_pop = 1.0
	msl_prev = msl
	msl_pop = maxf(0.0, msl_pop - rdt * 3.0)
	var ready := p.dash_cd <= 0.0
	if ready and not dash_was_ready:
		dash_ready_pop = 1.0
	dash_was_ready = ready
	dash_ready_pop = maxf(0.0, dash_ready_pop - rdt * 3.5)
	var sready := p.tech == null or p.tech.skill_ready()
	if sready and not skill_was_ready:
		skill_ready_pop = 1.0
	skill_was_ready = sready
	skill_ready_pop = maxf(0.0, skill_ready_pop - rdt * 3.5)
	_cockpit_fade(p, rdt)
	queue_redraw()


# ── 공용 그리기 ─────────────────────────────────────────

## align 은 pos 기준점 (CENTER = 가운데, RIGHT = 오른쪽 끝)
func _txt(pos: Vector2, str_: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, outline := 0, _w := -1.0) -> void:
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		pos.x -= _txt_w(str_, size) * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		pos.x -= _txt_w(str_, size)
	if outline > 0:
		draw_string_outline(font, pos, str_, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0.03, 0.02, 0.1, col.a * 0.9))
	draw_string(font, pos, str_, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _txt_w(str_: String, size: int) -> float:
	return font.get_string_size(str_, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## 사선 평행사변형 (위 변이 skew 만큼 오른쪽으로 밀린다)
func _para(o: Vector2, w: float, h: float, skew: float, c: Color, filled := true, lw := 1.5) -> void:
	var pts := PackedVector2Array([o + Vector2(skew, 0), o + Vector2(w + skew, 0), o + Vector2(w, h), o + Vector2(0, h)])
	if filled:
		draw_colored_polygon(pts, c)
	else:
		pts.append(pts[0])
		draw_polyline(pts, c, lw, true)


## 가로로 채워지는 사선 막대
func _para_bar(o: Vector2, w: float, h: float, skew: float, k: float, fg: Color, bg := Color(0.08, 0.08, 0.18, 0.85)) -> void:
	_para(o, w, h, skew, bg)
	k = clampf(k, 0.0, 1.0)
	if w * k > 1.0:
		_para(o, w * k, h, skew, fg)


func _hex(c: Vector2, r: float, col: Color, filled := true, lw := 2.0, rot := 0.0) -> void:
	var pts := PackedVector2Array()
	for i in 6:
		var a := rot + i * TAU / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	if filled:
		draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		draw_polyline(pts, col, lw, true)


## 끝이 깎인 판 (오른쪽 위 · 왼쪽 아래 모서리를 비스듬히 자른다)
func _plate(r: Rect2, cut: float, bg: Color, line: Color) -> void:
	var p := r.position
	var e := r.end
	var pts := PackedVector2Array([p, Vector2(e.x - cut, p.y), Vector2(e.x, p.y + cut), e, Vector2(p.x + cut, e.y), Vector2(p.x, e.y - cut)])
	draw_colored_polygon(pts, bg)
	pts.append(pts[0])
	draw_polyline(pts, line, 1.2, true)


func _keycap(o: Vector2, key: String, col := Color(0.85, 0.85, 1.0), size := 12) -> float:
	var w := maxf(_txt_w(key, size) + 10.0, 20.0)
	var r := Rect2(o, Vector2(w, size + 7.0))
	draw_rect(r, Color(0.02, 0.02, 0.07, 0.85))
	draw_rect(r, Color(col, 0.7), false, 1.2)
	_txt(o + Vector2(w * 0.5 - _txt_w(key, size) * 0.5, size + 2.0), key, size, col)
	return w


## 장갑 칸 (사선). 잔량 칸은 하얗게, 1칸 남으면 붉게 맥동
func _hp_cells(o: Vector2, cw: float, ch: float, skew: float, gap: float, p: Player) -> void:
	var low := p.hp <= 1
	var shake := Vector2(sin(t * 80.0), cos(t * 67.0)) * 3.0 * hp_hit * hp_hit
	for i in Player.MAX_HP:
		var x := o + shake + Vector2(i * (cw + gap), 0)
		if i < p.hp:
			var c := HP_ON
			if low:
				c = HP_LOW.lerp(Color.WHITE, 0.25 + 0.25 * sin(t * 9.0))
			_para(x, cw, ch, skew, c)
			_para(x + Vector2(skew * 0.5, 0), cw * 0.6, ch * 0.28, skew * 0.3, Color(1, 1, 1, 0.22))
		elif i < ceili(hp_trail):
			_para(x, cw, ch, skew, Color(1, 1, 1, 0.85 * clampf(hp_trail - i, 0.0, 1.0)))
		else:
			_para(x, cw, ch, skew, Color(0.12, 0.1, 0.24, 0.9))
			_para(x, cw, ch, skew, Color(0.4, 0.36, 0.7, 0.5), false, 1.0)


func _boost_col(p: Player) -> Color:
	if p.overheated:
		return Color("ff3a5a") if fmod(t, 0.3) < 0.15 else Color("802040")
	return Color("ffd060") if p.boosting else BOOST_C


## 원형 진행 (위에서 시계 방향)
func _ring(c: Vector2, r: float, k: float, col: Color, w: float, a0 := -PI * 0.5) -> void:
	k = clampf(k, 0.0, 1.0)
	if k <= 0.0:
		return
	draw_arc(c, r, a0, a0 + TAU * k, maxi(6, int(48 * k)), col, w, true)


func _pie(c: Vector2, r: float, k: float, col: Color) -> void:
	k = clampf(k, 0.0, 1.0)
	if k < 0.03:
		return
	var pts := PackedVector2Array([c])
	var n := maxi(3, int(36 * k))
	for i in n + 1:
		var a := -PI * 0.5 + TAU * k * i / n
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)


func _laser_k(p: Player) -> float:
	return p.charge if p.charging else (0.0 if p.laser_cd > 0.0 else 1.0)


func _stage_col(p: Player) -> Color:
	return ChargeFX.STAGE_COLORS[mini(p.charge_stage, 3)]


func _combo_active(p: Player) -> bool:
	return p.combo != null and (p.combo.ph != SwordCombo.Ph.IDLE or p.combo.link_t > 0.0)


func _mouse(m: Main) -> Vector2:
	if m.capture_mode:
		return m.camera.screen_pos(m.player.aim_point) / s
	return get_local_mouse_position() / s


# ── 그리기 진입점 ───────────────────────────────────────

func _draw() -> void:
	var m := Main.inst
	if m == null or m.player == null or current == LEGACY:
		return
	var p := m.player
	s = clampf(size.y / 900.0, 0.7, 2.0)
	W = size.x / s
	H = size.y / s
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	match current:
		STRIKER: _draw_striker(m, p)
		CORNERS: _draw_corners(m, p)
		COCKPIT: _draw_cockpit(m, p)
		TACTICAL: _draw_tactical(m, p)


# ── STRIKER : 젠레스 존 제로식 ──────────────────────────

func _draw_striker(m: Main, p: Player) -> void:
	# 좌상단 기체 카드: 헥스 엠블럼 · 기체명 · 사선 장갑칸 · 부스터 막대
	var o := Vector2(26, 24)
	# 폭은 720p 에서도 보스 체력바(가운데 720px)와 겹치지 않게 잡았다
	_para(o + Vector2(-8, 4), 305, 82, 14, Color(0.02, 0.02, 0.08, 0.55))
	_para(o + Vector2(-8, 4), 6, 82, 14, Pal.CYAN)
	var ec := o + Vector2(36, 45)
	_hex(ec, 27, Color(0.06, 0.05, 0.16, 0.95), true, 2.0, PI / 6.0)
	_hex(ec, 27, Pal.CYAN if p.hp > 1 else HP_LOW, false, 2.5, PI / 6.0)
	_hex(ec, 19, Color(Pal.P_LIGHT, 0.5), false, 1.5, PI / 6.0)
	# 엠블럼 안: 기체의 노란 두 눈
	for sx in [-1.0, 1.0]:
		draw_rect(Rect2(ec + Vector2(sx * 6.0 - 3.5, -3.0), Vector2(7, 5)), Pal.M_EYE)
	_txt(o + Vector2(74, 26), "HEXBLADE", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 4)
	_txt(o + Vector2(282, 25), "%d / %d" % [p.hp, Player.MAX_HP], 13, HP_LOW if p.hp <= 1 else DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	_hp_cells(o + Vector2(74, 36), 40, 17, 8, 5, p)
	var by := o.y + 62
	_para_bar(Vector2(o.x + 72, by), 222, 6, 4, p.boost, _boost_col(p))
	if p.overheated:
		_txt(Vector2(o.x + 74, by + 20), "OVERHEAT", 12, Color("ff5a6a"))
	if p.phantom_t > 0.0:
		var blink := p.phantom_t > 0.8 or fmod(t, 0.16) < 0.08
		if blink:
			_txt(Vector2(o.x + 200, by + 20), "BLADE  %.1f" % p.phantom_t, 12, Pal.BLADE, HORIZONTAL_ALIGNMENT_LEFT, 3)

	# 우하단 스킬 버튼 묶음
	var base := Vector2(W - 92, H - 92)
	# 주 공격: 검 (콤보 단계 칸이 둘레에 켜진다)
	var sw_c := base
	var hot := _combo_active(p)
	draw_circle(sw_c, 50, Color(0.03, 0.03, 0.1, 0.78))
	draw_arc(sw_c, 50, 0, TAU, 48, Color(1, 1, 1, 0.75) if hot else Color(0.6, 0.6, 0.9, 0.6), 2.5, true)
	if p.phantom_t > 0.0:
		draw_arc(sw_c, 56 + sin(t * 20.0) * 1.5, 0, TAU, 48, Color(Pal.BLADE, 0.85), 3.0, true)
	var n_steps := SwordCombo.STEPS.size()     # 템포 프리셋마다 단 수가 다르다
	for i in n_steps:
		var a := -PI * 0.5 + (i - (n_steps - 1) * 0.5) * 0.3
		var lit := hot and i <= p.combo.step
		var dp := sw_c + Vector2(cos(a), sin(a)) * 62
		draw_circle(dp, 4.0 if lit else 3.0, Pal.BLADE if lit else Color(0.4, 0.38, 0.6, 0.7))
	# 광선검 아이콘
	var bc := Pal.BLADE if p.phantom_t > 0.0 else Color(1, 0.55, 0.5)
	draw_line(sw_c + Vector2(-18, 18), sw_c + Vector2(20, -20), Color(bc, 0.35), 9.0, true)
	draw_line(sw_c + Vector2(-18, 18), sw_c + Vector2(20, -20), bc, 4.0, true)
	draw_line(sw_c + Vector2(-16, 16), sw_c + Vector2(18, -18), Color(1, 0.95, 0.9), 1.5, true)
	draw_line(sw_c + Vector2(-26, 10), sw_c + Vector2(-10, 26), Color(0.8, 0.8, 0.9), 3.5, true)
	_keycap(sw_c + Vector2(-16, 32), "LMB")

	# 회피 (쿨다운 부채꼴)
	var dc := base + Vector2(-112, 22)
	var ready := p.dash_cd <= 0.0
	draw_circle(dc, 32, Color(0.03, 0.03, 0.1, 0.78))
	if not ready:
		_pie(dc, 30, 1.0 - p.dash_cd / Player.DASH_CD, Color(Pal.CYAN, 0.28))
	draw_arc(dc, 32 + dash_ready_pop * 8.0, 0, TAU, 40, Color(Pal.CYAN, 0.9 if ready else 0.35), 2.5 + dash_ready_pop * 2.0, true)
	_dash_icon(dc, Pal.CYAN if ready else Color(0.4, 0.5, 0.7))
	_keycap(dc + Vector2(-22, 26), "Space")

	# 돌진 스킬 E (쿨다운 부채꼴 · 남은 초)
	if p.tech:
		var skc := base + Vector2(-152, -58)
		_rush_skill(skc, 28, p)
		_keycap(skc + Vector2(-8, 22), "E")

	# 충전 레이저 (에너지 칸 = 둘레 호 3조각, 충전 중이면 안쪽에 단계 색)
	var lc := base + Vector2(-70, -94)
	_skill_energy(lc, 34, p)
	_keycap(lc + Vector2(-20, 28), "L+R")

	# 미사일 (남은 수)
	var mc := base + Vector2(14, -132)
	var mk := 1.0 + msl_pop * 0.35
	draw_circle(mc, 28, Color(0.03, 0.03, 0.1, 0.78))
	var have := p.missiles > 0
	draw_arc(mc, 28, 0, TAU, 40, Color(MSL_C, 0.9 if have else 0.3), 2.5, true)
	if p.ult_aiming:
		draw_arc(mc, 34, 0, TAU, 40, Color(1, 0.3, 0.25, 0.6 + 0.4 * sin(t * 20.0)), 2.5, true)
	_missile_icon(mc + Vector2(-9, -2), 10, 22, Color(MSL_C, 1.0 if have else 0.35))
	_txt(mc + Vector2(16, 10) * mk, "%d" % (p.missiles + p.ult_queue), int(20 * mk), Color.WHITE if have else Color(0.6, 0.6, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 4, 0)
	_keycap(mc + Vector2(-8, 22), "R")

	# 기본 총: 탄창 막대 (회피 버튼 왼쪽)
	_ammo_strip(Vector2(base.x - 330, base.y + 34), 170, p, true)


func _rush_skill(c: Vector2, r: float, p: Player) -> void:
	var col := BladeTech.SKILL_COL
	var cd := p.tech.skill_cd
	var ready := cd <= 0.0
	draw_circle(c, r, Color(0.03, 0.03, 0.1, 0.78))
	if not ready:
		_pie(c, r - 2, 1.0 - cd / BladeTech.SKILL_CD, Color(col, 0.25))
	var aiming := p.tech.skill_aiming()
	draw_arc(c, r + skill_ready_pop * 8.0, 0, TAU, 40, Color(col, 0.9 if ready else 0.3), 2.5 + skill_ready_pop * 2.0, true)
	if aiming:
		draw_arc(c, r + 6, 0, TAU, 40, Color(col, 0.6 + 0.4 * sin(t * 20.0)), 2.0, true)
	# 아이콘: 앞으로 찌르는 화살 + 뒤로 끌리는 속도선
	var ic := col if ready else Color(0.35, 0.5, 0.5)
	draw_line(c + Vector2(-12, 0), c + Vector2(10, 0), ic, 4.0, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(16, 0), c + Vector2(6, -8), c + Vector2(6, 8)]), ic)
	for i in 2:
		var y := -7.0 + i * 14.0
		draw_line(c + Vector2(-16, y), c + Vector2(-6, y), Color(ic, 0.6), 2.0, true)
	if not ready:
		_txt(c + Vector2(0, 6), "%.1f" % cd, 15, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 4, 0)


func _skill_energy(c: Vector2, r: float, p: Player) -> void:
	draw_circle(c, r, Color(0.03, 0.03, 0.1, 0.78))
	var n := Player.ENERGY_MAX
	var pend := Player.laser_cost(p.charge) if p.charging and p.charge >= Player.CHARGE_MIN else 0
	for i in n:
		var a0 := -PI * 0.5 + i * TAU / n + 0.12
		var a1 := -PI * 0.5 + (i + 1) * TAU / n - 0.12
		var on := i < p.energy
		var col := EN_C if on else Color(EN_C, 0.18)
		if on and i >= p.energy - pend:
			col = col.lerp(Color.WHITE, 0.4 + 0.3 * sin(t * 24.0))
		draw_arc(c, r, a0, a1, 16, col, 4.0 + (en_pop * 2.0 if on else 0.0), true)
	# 다음 칸 재충전
	if p.energy < n:
		var i := p.energy
		var a0 := -PI * 0.5 + i * TAU / n + 0.12
		draw_arc(c, r + 6, a0, a0 + (TAU / n - 0.24) * p.energy_regen_k(), 12, Color(EN_C, 0.6), 1.5, true)
	if p.charging:
		_pie(c, r - 7, p.charge, Color(_stage_col(p), 0.45))
	# 빔 아이콘
	var ic := _stage_col(p) if p.charging else (EN_C if p.energy > 0 else Color(0.4, 0.45, 0.6))
	draw_line(c + Vector2(-14, 0), c + Vector2(14, 0), Color(ic, 0.4), 9.0, true)
	draw_line(c + Vector2(-14, 0), c + Vector2(14, 0), ic, 3.0, true)
	draw_circle(c + Vector2(-14, 0), 5.0, ic)


func _dash_icon(c: Vector2, col: Color) -> void:
	for i in 3:
		var x := -12.0 + i * 8.0
		var pts := PackedVector2Array([c + Vector2(x, -9), c + Vector2(x + 9, 0), c + Vector2(x, 9)])
		draw_polyline(pts, Color(col, 0.45 + i * 0.27), 3.0, true)


func _missile_icon(o: Vector2, w: float, h: float, c: Color) -> void:
	var cx := o.x + w * 0.5
	var bw := w * 0.5
	draw_colored_polygon(PackedVector2Array([Vector2(cx, o.y), Vector2(cx + bw * 0.5, o.y + h * 0.28), Vector2(cx - bw * 0.5, o.y + h * 0.28)]), c)
	draw_rect(Rect2(Vector2(cx - bw * 0.5, o.y + h * 0.3), Vector2(bw, h * 0.5)), c)
	draw_colored_polygon(PackedVector2Array([Vector2(cx - bw * 0.5, o.y + h * 0.55), Vector2(cx - bw * 0.5, o.y + h * 0.82), Vector2(o.x, o.y + h * 0.88)]), c)
	draw_colored_polygon(PackedVector2Array([Vector2(cx + bw * 0.5, o.y + h * 0.55), Vector2(o.x + w, o.y + h * 0.88), Vector2(cx + bw * 0.5, o.y + h * 0.82)]), c)


## 탄창: 큰 숫자 + 낱발 눈금. 재장전 중에는 눈금이 차오른다
func _ammo_strip(o: Vector2, w: float, p: Player, keys: bool) -> void:
	var rel := p.reload_t > 0.0
	var low := p.mag <= 5 and not rel
	var col := Color("ff6a6a") if low else AMMO_C
	if rel:
		var rc := Color("ffd070") if fmod(t, 0.3) < 0.15 else Color.WHITE
		_txt(o + Vector2(0, -6), "RELOAD", 20, rc, HORIZONTAL_ALIGNMENT_LEFT, 4)
	else:
		_txt(o + Vector2(0, -6), "%d" % p.mag, 30, col, HORIZONTAL_ALIGNMENT_LEFT, 4)
		_txt(o + Vector2(_txt_w("%d" % p.mag, 30) + 4, -7), "/ %d" % Player.MAG_SIZE, 14, DIM, HORIZONTAL_ALIGNMENT_LEFT, 3)
	var n := Player.MAG_SIZE
	var tw := w / n
	for i in n:
		var on: bool
		if rel:
			on = i < int(n * p.reload_k())
		else:
			on = i < p.mag
		var c := (Color("ffa040") if rel else col) if on else Color(0.2, 0.2, 0.32, 0.8)
		draw_rect(Rect2(o + Vector2(i * tw, 2), Vector2(maxf(tw - 1.5, 1.0), 9)), c)
	if keys:
		_keycap(o + Vector2(w - 54, -26), "RMB", Color(0.85, 0.85, 1.0), 11)
		_keycap(o + Vector2(w - 22, -26), "T", Color(0.85, 0.85, 1.0), 11)


# ── CORNERS : 하단 분할 ─────────────────────────────────

func _draw_corners(m: Main, p: Player) -> void:
	# 왼쪽 아래: 생존
	var o := Vector2(30, H - 128)
	_plate(Rect2(o + Vector2(-12, -14), Vector2(330, 118)), 14, INK, INK_LINE)
	_txt(o + Vector2(0, 6), "HEXBLADE", 15, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 3)
	_txt(o + Vector2(92, 6), "ARMOR", 12, HP_LOW if p.hp <= 1 else DIM)
	# 장갑 = 헥스 칸
	var shake := Vector2(sin(t * 80.0), cos(t * 67.0)) * 3.0 * hp_hit * hp_hit
	for i in Player.MAX_HP:
		var c := o + shake + Vector2(20 + i * 46, 42)
		if i < p.hp:
			var col := HP_ON
			if p.hp <= 1:
				col = HP_LOW.lerp(Color.WHITE, 0.25 + 0.25 * sin(t * 9.0))
			_hex(c, 20, col, true, 2.0, PI / 6.0)
			_hex(c, 12, Color(1, 1, 1, 0.18), true, 1.0, PI / 6.0)
		elif i < ceili(hp_trail):
			_hex(c, 20, Color(1, 1, 1, 0.85 * clampf(hp_trail - i, 0.0, 1.0)), true, 2.0, PI / 6.0)
		else:
			_hex(c, 20, Color(0.1, 0.09, 0.22, 0.9), true, 2.0, PI / 6.0)
			_hex(c, 20, Color(0.4, 0.36, 0.7, 0.6), false, 1.2, PI / 6.0)
	# 회피 마름모 + 부스터 막대
	var dy := o.y + 84
	var ready := p.dash_cd <= 0.0
	var dk := 1.0 - p.dash_cd / Player.DASH_CD
	var dcn := Vector2(o.x + 12, dy)
	var dia := PackedVector2Array([dcn + Vector2(0, -10), dcn + Vector2(10, 0), dcn + Vector2(0, 10), dcn + Vector2(-10, 0)])
	draw_colored_polygon(dia, Pal.CYAN if ready else Color(0.12, 0.16, 0.3))
	if not ready and dk > 0.05:
		var sq := dia.duplicate()
		for i in sq.size():
			sq[i] = dcn + (sq[i] - dcn) * dk
		draw_colored_polygon(sq, Color(Pal.CYAN, 0.6))
	if dash_ready_pop > 0.0:
		var big := PackedVector2Array()
		for v in dia:
			big.append(dcn + (v - dcn) * (1.0 + (1.0 - dash_ready_pop) * 0.9))
		big.append(big[0])
		draw_polyline(big, Color(Pal.CYAN, dash_ready_pop), 2.0, true)
	_keycap(Vector2(o.x + 28, dy - 10), "Space", Color(0.8, 0.95, 1.0), 11)
	var bx := o.x + 90
	_para_bar(Vector2(bx, dy - 4), 170, 8, 4, p.boost, _boost_col(p))
	_keycap(Vector2(bx + 180, dy - 10), "Shift", Color(1, 0.9, 0.75), 11)
	if p.overheated:
		_txt(Vector2(bx, dy - 10), "OVERHEAT", 11, Color("ff5a6a"))
	if p.phantom_t > 0.0 and (p.phantom_t > 0.8 or fmod(t, 0.16) < 0.08):
		_txt(Vector2(o.x + 208, o.y + 6), "BLADE %.1f" % p.phantom_t, 12, Pal.BLADE, HORIZONTAL_ALIGNMENT_LEFT, 3)

	# 오른쪽 아래: 무장
	var r0 := Vector2(W - 330, H - 128)
	_plate(Rect2(r0 + Vector2(-12, -14), Vector2(330, 118)), 14, INK, INK_LINE)
	_txt(r0 + Vector2(0, 6), "ARMS", 12, DIM)
	_ammo_strip(r0 + Vector2(0, 40), 200, p, false)
	_keycap(r0 + Vector2(214, 24), "RMB", Color(0.85, 0.85, 1.0), 11)
	_keycap(r0 + Vector2(254, 24), "T", Color(0.85, 0.85, 1.0), 11)
	# 에너지 · 미사일은 기존 아이콘 줄(획득·소모 연출 포함)을 이 자리로 옮겨 쓴다
	_txt(r0 + Vector2(0, 70), "LASER", 11, DIM)
	_keycap(r0 + Vector2(42, 58), "L+R", Color(0.8, 0.95, 1.0), 10)
	_txt(r0 + Vector2(118, 70), "MISSILE", 11, DIM)
	_keycap(r0 + Vector2(170, 58), "R", Color(1, 0.9, 0.75), 10)


## CORNERS · TACTICAL 에서 아이콘 줄 자리 (Hud 가 매 프레임 옮긴다)
func icon_slots() -> Dictionary:
	match current:
		CORNERS:
			return {"energy": Vector2(W - 328, H - 128 + 77) * s, "missile": Vector2(W - 330 + 118, H - 128 + 77) * s, "escale": 0.8 * s, "mscale": 0.8 * s}
		TACTICAL:
			return {"energy": Vector2(36, 166) * s, "missile": Vector2(104, 166) * s, "escale": 0.7 * s, "mscale": 0.62 * s}
	return {}


# ── COCKPIT : 디제틱 호 ─────────────────────────────────

func _cockpit_fade(p: Player, rdt: float) -> void:
	var want_hp := 1.0 if (hp_hit > 0.0 or p.hp <= 2) else 0.85
	var want_boost := 1.0 if (p.boosting or p.boost < 0.999 or p.overheated) else 0.0
	var want_dash := 1.0 if p.dash_cd > 0.0 or dash_ready_pop > 0.0 else 0.0
	var want_en := 1.0 if (p.charging or en_pop > 0.0 or p.energy < Player.ENERGY_MAX) else 0.45
	cockpit_a.hp = move_toward(cockpit_a.hp, want_hp, rdt * (6.0 if want_hp > cockpit_a.hp else 1.2))
	cockpit_a.boost = move_toward(cockpit_a.boost, want_boost, rdt * (8.0 if want_boost > cockpit_a.boost else 1.5))
	cockpit_a.dash = move_toward(cockpit_a.dash, want_dash, rdt * (10.0 if want_dash > cockpit_a.dash else 2.5))
	cockpit_a.en = move_toward(cockpit_a.en, want_en, rdt * (6.0 if want_en > cockpit_a.en else 1.5))


func ae_bg() -> float:
	return cockpit_a.en


func _arc_segments(c: Vector2, r: float, a0: float, a1: float, n: int, on: int, col: Color, off: Color, w: float, gap := 0.05) -> void:
	var step := (a1 - a0) / n
	for i in n:
		var b0 := a0 + i * step + gap
		var b1 := a0 + (i + 1) * step - gap
		draw_arc(c, r, b0, b1, 10, col if i < on else off, w, true)


func _draw_cockpit(m: Main, p: Player) -> void:
	if not p.alive:
		return
	var wp := p.global_position + Vector3(0, 0.9, 0)
	if m.camera.is_position_behind(wp):
		return
	var c := m.camera.screen_pos(wp) / s
	var r := 82.0
	# 장갑: 기체 왼쪽 호 (아래 → 위)
	var ah: float = cockpit_a.hp
	var hc := HP_ON
	if p.hp <= 1:
		hc = HP_LOW.lerp(Color.WHITE, 0.25 + 0.25 * sin(t * 9.0))
	var shake := Vector2(sin(t * 80.0), cos(t * 67.0)) * 4.0 * hp_hit * hp_hit
	var a_lo := PI * 0.78
	var a_hi := PI * 1.22
	# 아래(PI*0.78)에서 위(PI*1.22)로 채운다. 어두운 받침선이 기체 보라색·이펙트 위에서도 호를 떼어 보이게 한다
	draw_arc(c + shake, r, a_lo, a_hi, 24, Color(0.02, 0.02, 0.08, ah * 0.7), 12.0, true)
	_arc_segments(c + shake, r, a_lo, a_hi, Player.MAX_HP, p.hp, Color(hc, ah), Color(0.25, 0.22, 0.45, ah * 0.7), 7.0, 0.035)
	if hp_trail > p.hp:
		var step := (a_hi - a_lo) / Player.MAX_HP
		var i := p.hp
		var tk := clampf(hp_trail - i, 0.0, 1.0)
		if tk > 0.1:
			draw_arc(c + shake, r, a_lo + i * step + 0.035, a_lo + (i + tk) * step - 0.035, 8, Color(1, 1, 1, 0.9), 7.0, true)
	if ah > 0.5:
		_txt(c + Vector2(-r - 14, -r * 0.5), "%d" % p.hp, 14, Color(hc, ah), HORIZONTAL_ALIGNMENT_RIGHT, 3, 0)
	# 부스터: 기체 오른쪽 호 (아래 → 위로 차오름)
	var ab: float = cockpit_a.boost
	if ab > 0.01:
		var b_lo := PI * 0.22
		var b_hi := -PI * 0.22
		draw_arc(c, r, b_hi, b_lo, 24, Color(0.02, 0.02, 0.08, ab * 0.7), 12.0, true)
		draw_arc(c, r, b_hi, b_lo, 24, Color(0.15, 0.12, 0.25, ab * 0.7), 7.0, true)
		if p.boost > 0.02:
			draw_arc(c, r, b_lo, lerpf(b_lo, b_hi, p.boost), 24, Color(_boost_col(p), ab), 7.0, true)
		if p.overheated:
			_txt(c + Vector2(r + 10, 4), "OVERHEAT", 12, Color(1, 0.35, 0.4, ab), HORIZONTAL_ALIGNMENT_LEFT, 3)
	# 회피: 발밑 짧은 호
	var ad: float = cockpit_a.dash
	if ad > 0.01:
		var dk := 1.0 - p.dash_cd / Player.DASH_CD
		var w0 := PI * 0.5 - 0.32
		draw_arc(c, r + 4, w0, w0 + 0.64, 16, Color(0.02, 0.02, 0.08, ad * 0.7), 8.0, true)
		draw_arc(c, r + 4, w0, w0 + 0.64, 16, Color(0.15, 0.2, 0.3, ad * 0.6), 3.0, true)
		draw_arc(c, r + 4, w0, w0 + 0.64 * dk, 16, Color(Pal.CYAN, ad), 3.0 + dash_ready_pop * 3.0, true)
	if p.phantom_t > 0.0 and (p.phantom_t > 0.8 or fmod(t, 0.16) < 0.08):
		draw_arc(c, r + 10, -PI * 0.5 - 0.5, -PI * 0.5 + 0.5, 20, Color(Pal.BLADE, 0.9), 3.0, true)

	# 조준점 둘레: 탄창 호 (오른쪽 아래 사분면) · 에너지 3조각 (위) · 미사일 수
	if p.ult_aiming:
		return
	var q := _mouse(m)
	var rel := p.reload_t > 0.0
	var mk := float(p.mag) / Player.MAG_SIZE
	var ac := Color("ff6a6a") if p.mag <= 5 else Color(AMMO_C, 0.85)
	draw_arc(q, 34, PI * 0.08, PI * 0.42, 16, Color(0.02, 0.02, 0.08, 0.6), 7.0, true)
	draw_arc(q, 34, -PI * 0.5 - 0.42, -PI * 0.5 + 0.42, 16, Color(0.02, 0.02, 0.08, 0.5 * ae_bg()), 8.0, true)
	draw_arc(q, 34, PI * 0.08, PI * 0.42, 16, Color(0.2, 0.2, 0.3, 0.6), 3.0, true)
	if not rel:
		draw_arc(q, 34, PI * 0.08, PI * 0.08 + PI * 0.34 * mk, 16, ac, 3.0, true)
	var ae: float = cockpit_a.en
	var pend := Player.laser_cost(p.charge) if p.charging and p.charge >= Player.CHARGE_MIN else 0
	for i in Player.ENERGY_MAX:
		var a0 := -PI * 0.5 - 0.42 + i * 0.28 + 0.03
		var on := i < p.energy
		var col := Color(EN_C, ae) if on else Color(EN_C, 0.15 * ae)
		if on and i >= p.energy - pend:
			col = Color.WHITE
		draw_arc(q, 34, a0, a0 + 0.22, 8, col, 4.0, true)
	if p.charging:
		draw_arc(q, 40, -PI * 0.5 - 0.42, -PI * 0.5 - 0.42 + 0.84 * p.charge, 16, _stage_col(p), 2.0, true)
	var msl := p.missiles + p.ult_queue
	var mcol := Color(MSL_C, 0.9) if msl > 0 else Color(0.6, 0.6, 0.7, 0.4)
	_missile_icon(q + Vector2(-46, 18), 7, 15, mcol)
	_txt(q + Vector2(-50, 30), "%d" % msl, int(13 * (1.0 + msl_pop * 0.4)), mcol, HORIZONTAL_ALIGNMENT_RIGHT, 3, 0)

	# 좌상단: 아주 작은 상태줄 (호를 놓쳤을 때를 위한 보조)
	var o := Vector2(24, 30)
	_txt(o, "HEXBLADE", 13, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_LEFT, 3)
	for i in Player.MAX_HP:
		draw_rect(Rect2(o + Vector2(80 + i * 12, -9), Vector2(9, 9)), hc if i < p.hp else Color(0.25, 0.22, 0.45, 0.8))


# ── TACTICAL : 압축한 좌상단 패널 ───────────────────────

func _draw_tactical(m: Main, p: Player) -> void:
	var o := Vector2(22, 20)
	_plate(Rect2(o, Vector2(268, 180)), 16, INK, INK_LINE)
	draw_rect(Rect2(o + Vector2(0, 0), Vector2(4, 40)), Pal.CYAN)
	_txt(o + Vector2(14, 20), "HEXBLADE", 14, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT, 3)
	_txt(o + Vector2(236, 20), "%d/%d" % [p.hp, Player.MAX_HP], 12, HP_LOW if p.hp <= 1 else DIM, HORIZONTAL_ALIGNMENT_RIGHT, 0, 0)
	_hp_cells(o + Vector2(14, 28), 38, 12, 5, 6, p)
	# 아이콘 + 막대 + 키 3줄
	var rows := [
		["dash", 1.0 - p.dash_cd / Player.DASH_CD, Pal.CYAN if p.dash_cd <= 0.0 else Color(0.3, 0.45, 0.7), "Space"],
		["boost", p.boost, _boost_col(p), "Shift"],
		["laser", _laser_k(p), _stage_col(p) if p.charging else Color(0.45, 0.55, 0.85), "L+R"],
	]
	for i in rows.size():
		var y := o.y + 58 + i * 20
		var row: Array = rows[i]
		var full: bool = row[1] >= 0.999
		var ia := 0.55 if full else 1.0
		_row_icon(Vector2(o.x + 22, y + 4), row[0], Color(row[2], ia))
		_para_bar(Vector2(o.x + 38, y), 140, 7, 3, row[1], Color(row[2], ia))
		_keycap(Vector2(o.x + 188, y - 6), row[3], Color(0.8, 0.8, 0.95, 0.8), 10)
	# 탄창 (숫자 + 눈금 축소판)
	var ay := o.y + 122
	_txt(Vector2(o.x + 14, ay + 10), "RELOAD" if p.reload_t > 0.0 else "%02d" % p.mag, 14, Color("ffd070") if p.reload_t > 0.0 else (Color("ff6a6a") if p.mag <= 5 else AMMO_C), HORIZONTAL_ALIGNMENT_LEFT, 3)
	var n := Player.MAG_SIZE
	for i in n:
		var on := i < (int(n * p.reload_k()) if p.reload_t > 0.0 else p.mag)
		draw_rect(Rect2(Vector2(o.x + 74 + i * 3.6, ay + 1), Vector2(2.4, 9)), (AMMO_C if p.reload_t <= 0.0 else Color("ffa040")) if on else Color(0.2, 0.2, 0.32))
	_keycap(Vector2(o.x + 188, ay - 4), "T", Color(0.8, 0.8, 0.95, 0.8), 10)
	_keycap(Vector2(o.x + 240, ay + 25), "R", Color(1, 0.9, 0.75, 0.8), 10)
	if p.phantom_t > 0.0 and (p.phantom_t > 0.8 or fmod(t, 0.16) < 0.08):
		_txt(Vector2(o.x + 14, o.y + 196), "BLADE %.1f" % p.phantom_t, 12, Pal.BLADE, HORIZONTAL_ALIGNMENT_LEFT, 3)


func _row_icon(c: Vector2, kind: String, col: Color) -> void:
	match kind:
		"dash":
			for i in 2:
				var x := -7.0 + i * 6.0
				draw_polyline(PackedVector2Array([c + Vector2(x, -5), c + Vector2(x + 5, 0), c + Vector2(x, 5)]), col, 2.0, true)
		"boost":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(5, 3), c + Vector2(0, 7), c + Vector2(-5, 3)]), col)
		"laser":
			draw_line(c + Vector2(-7, 0), c + Vector2(7, 0), col, 3.0, true)
			draw_circle(c + Vector2(-7, 0), 3.0, col)
