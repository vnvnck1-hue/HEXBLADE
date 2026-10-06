class_name MisfitzHit
extends RefCounted
## MISFITZ 'ENEMY 05 · Hit' 레퍼런스의 타격 버스트 (docs/misfitz-hit-vfx.md). 판정과 무관한 연출 전용.
## MocoFX 의 ImmediateMesh 하나에 매 프레임 다시 그린다 (노드·머티리얼·정적 캐시 없음). 카메라를 향한 판.
##
## 레퍼런스 키프레임 (정점 A → 소멸 B) 을 시간표로 옮긴 것 (일반 타격, 초):
##  0.000~0.033  번쩍: 흰 3갈래 별이 0.55 → 1.12 배로 튀어나오며 흰색 → 마젠타로 물든다, 보라 광채가 켜진다
##  0.033~0.100  정점 A: 비대칭 3갈래 별 (긴 가지 둘 + 짧은 가지 하나). 흰 심지 · 연분홍 면 · 마젠타 테두리,
##               가지마다 한쪽 면은 짙은 마젠타 (베벨). 뒤로 계단처럼 밀린 잔상 2겹 (마젠타 · 보라),
##               그 뒤 큰 보라 별 덩어리 + 가는 보라 광선 4가닥, 네모 픽셀 조각
##  0.100~0.170  깨짐: 별 가지의 골이 안으로 파고들어 가는 선 같은 가지만 남는다. 보라 덩어리가
##               속 빈 윤곽 파편 3개 (ㄱ자 · 삼각형 · 사다리꼴) 로 깨져 바깥으로 흩어진다
##  0.170~0.300  소멸 B: 가는 별이 짧아지며 투명해지고, 윤곽 파편 · 픽셀 조각이 흩어지며 사라진다
## 색: 근접 = 보라(레퍼런스), 원거리(총 · 레이저 · 미사일) = 노랑 (PALETTES · RANGED).
## 강타는 크기 1.3 배 · 시간 1.25 배 · 잔상 3겹 · 픽셀 조각 더 많이.

const T_POP := 0.033
const T_A := 0.10
const T_B := 0.17
const T_END := 0.30
const HEAVY_TIME := 1.25
const HEAVY_SIZE := 1.3
const R_NORMAL := 0.4        # 별 반경 = 대상 몸체 폭 × 이 값 (레퍼런스 크기 0.8 의 절반, 사용자 요청)
const R_HEAVY := 0.4 * HEAVY_SIZE

# 레퍼런스에서 뽑은 색 (sRGB). 꼭짓점 색은 선형으로 바꿔 쓴다
const WHITE := Color("ffffff")
## 색 세트: purple = 레퍼런스 그대로 (근접 공격), yellow = 같은 명암 구조의 노랑·주황 (총 · 레이저 · 미사일 같은 원거리)
##  pale 별 안쪽 면 · edge 별 테두리 · dark 가지 그늘(베벨) · echo1/2 잔상 · back 뒤 덩어리·광선 · shard 윤곽 파편 · glow 광채 · sq 픽셀 조각
const PALETTES := {
	"purple": {
		"pale": Color("f8d2fa"), "edge": Color("ff2ee8"), "dark": Color("c214d6"),
		"echo1": Color("ff3ce6"), "echo2": Color("a43cf0"), "back": Color("9b2cf0"),
		"shard": Color("7f46dc"), "glow": Color("b43cf0"),
		"sq": [Color("8048e8"), Color("a77cff"), Color("f25ff0"), Color("e628f0")],
	},
	"yellow": {
		"pale": Color("fff4c4"), "edge": Color("ffd21e"), "dark": Color("e88a00"),
		"echo1": Color("ffbe28"), "echo2": Color("ff7a1a"), "back": Color("ff9a1e"),
		"shard": Color("e0701e"), "glow": Color("ffb020"),
		"sq": [Color("ffc83c"), Color("ffe678"), Color("ff9a28"), Color("fff0a0")],
	},
}
const RANGED := ["bullet", "laser", "missile"]    # 이 피해 원천은 노랑, 나머지(검 · 관통 일격 · 패링 …)는 보라

# 3갈래 별: [각도(rad, 별 자기 좌표), 길이(반경 배), 골 반각 비율]. 레퍼런스 정점 A 의 위 · 오른쪽 · 왼쪽 아래 가지
const ARMS := [[0.0, 1.0], [1.88, 1.0], [3.70, 0.62]]
const ARM_MID := 0.94           # 긴 두 가지의 가운데 각 → 이 방향을 표면 밖(공격이 온 쪽)으로 돌린다
const VALLEY_A := 0.25          # 정점 A 의 골 반경 (가지가 두툼)
const VALLEY_B := 0.035         # 소멸 B 의 골 반경 (가는 선)

# 속 빈 윤곽 파편 (자기 좌표, 반경 배). [점 목록, 닫힘]
const SHARDS := [
	[[Vector2(0.25, 0.45), Vector2(-0.15, 0.05), Vector2(-0.15, -0.4), Vector2(0.2, -0.4)], false],   # ㄱ자
	[[Vector2(0.0, 0.42), Vector2(0.35, -0.25), Vector2(-0.25, -0.12)], true],                          # 삼각형
	[[Vector2(-0.45, 0.05), Vector2(0.3, 0.05), Vector2(0.5, 0.3), Vector2(0.4, -0.12), Vector2(-0.3, -0.15)], true],  # 사다리꼴 + 가시
]


## MocoFX.hit 이 만드는 버스트 하나 (Dictionary, "mz" 표식)
static func make(pos: Vector3, dir: Vector3, width: float, heavy: bool, k: float, key: Object, tone := "purple") -> Dictionary:
	var pal: Dictionary = PALETTES.get(tone, PALETTES.purple)
	var sq_cols: Array = pal.sq
	var w := clampf(width, 0.8, 2.2)
	var kk := clampf((k - 1.0) / 0.8, 0.0, 1.0)
	var r := w * (R_HEAVY if heavy else R_NORMAL) * lerpf(1.0, 1.12, kk)
	# 일반 적의 판정점은 몸 안쪽 → 공격이 온 쪽 표면으로 (MocoFX 와 같은 규칙)
	var fd := Vector3(dir.x, 0, dir.z)
	if fd.length() > 0.01 and not (key is Enemy and (key as Enemy).is_boss):
		pos -= fd.normalized() * minf(width, 2.4) * MocoFX.SURFACE
	var ts := HEAVY_TIME if heavy else 1.0
	var lens: Array = []
	for a: Array in ARMS:
		lens.append(float(a[1]) * randf_range(0.88, 1.1))
	var shards: Array = []
	var base := randf() * TAU
	for i in SHARDS.size():
		shards.append({
			"a": base + TAU * i / SHARDS.size() + randf_range(-0.35, 0.35),
			"s": randf_range(0.85, 1.15), "rot": randf_range(-0.5, 0.5), "spin": randf_range(-1.6, 1.6),
		})
	var squares: Array = []
	for i in (16 if heavy else 11):
		squares.append({
			"a": randf() * TAU, "d0": randf_range(0.25, 0.95), "v": randf_range(0.6, 1.5), "up": randf_range(0.0, 0.5),
			"s": randf_range(0.035, 0.12) * (1.6 if randf() < 0.18 else 1.0),
			"t0": randf_range(0.0, 0.08) * ts, "life": randf_range(0.18, 0.3) * ts,
			"col": MocoFX.lin(sq_cols[randi() % sq_cols.size()]), "al": randf_range(0.65, 1.0),
		})
	var rays: Array = []
	for i in 4:
		rays.append([TAU * i / 4.0 + randf_range(-0.4, 0.4) + 0.4, randf_range(1.25, 1.65)])
	return {
		"mz": true, "pal": pal, "pos": pos, "dir": dir, "r": r, "age": 0.0, "heavy": heavy, "ts": ts,
		"end": T_END * ts, "spin": randf_range(-0.4, 0.4), "mirror": randf() < 0.5,
		"lens": lens, "shards": shards, "squares": squares, "rays": rays, "echoes": 3 if heavy else 2,
	}


static func _lin(c: Color, a: float) -> Color:
	var l := c.srgb_to_linear()
	l.a = clampf(a, 0.0, 1.0)
	return l


static func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x)


## 그리기 (MocoFX._draw_bursts 의 surface 안에서)
static func emit(m: MocoFX, b: Dictionary) -> void:
	var pal: Dictionary = b.pal
	var GLOW: Color = pal.glow
	var VIO: Color = pal.back
	var MAG: Color = pal.edge
	var MAG_DK: Color = pal.dark
	var PALE: Color = pal.pale
	var ts: float = b.ts
	var t: float = float(b.age) / ts          # 일반 타격 시간표로 맞춘 나이
	var r: float = b.r
	var p: Vector3 = b.pos
	var c := p + (m._cam_pos - p).normalized() * MocoFX.PULL
	# 표면 밖 방향 (화면 판 각도)
	var d: Vector3 = b.dir
	var sx := d.dot(m._cam_right)
	var sy := d.dot(m._cam_up)
	var out := (atan2(sy, sx) + PI) if absf(sx) + absf(sy) > 0.05 else PI * 0.5
	var mir := -1.0 if b.mirror else 1.0
	var rot := out + float(b.spin) - ARM_MID * mir

	# ── 시간표 ──
	var scale: float
	if t < T_POP:
		scale = lerpf(0.55, 1.12, _ease_out(t / T_POP))
	elif t < 0.06:
		scale = lerpf(1.12, 1.0, (t - T_POP) / (0.06 - T_POP))
	elif t < T_B:
		scale = lerpf(1.0, 1.06, (t - 0.06) / (T_B - 0.06))
	else:
		scale = lerpf(1.06, 0.7, (t - T_B) / (T_END - T_B))
	var valley := lerpf(VALLEY_A, VALLEY_B, smoothstep(T_A * 0.8, T_B, t))
	var star_a := 1.0 - smoothstep(0.22, T_END, t)
	var flash := 1.0 - smoothstep(0.0, T_POP, t)        # 첫 두 프레임 흰빛

	# 1) 보라 광채 (원형, 가장자리 투명)
	var glow := smoothstep(0.0, 0.04, t) * (1.0 - smoothstep(0.06, 0.2, t))
	if glow > 0.01:
		_disc(m, c, r * 1.35 * scale, _lin(GLOW, 0.55 * glow), _lin(GLOW, 0.0))
	# 2) 가는 보라 광선
	var ray_a := smoothstep(0.015, 0.035, t) * (1.0 - smoothstep(0.1, 0.16, t))
	if ray_a > 0.01:
		var col := _lin(VIO, 0.8 * ray_a)
		for ry: Array in b.rays:
			var a: float = rot + float(ry[0]) * mir
			var L: float = r * float(ry[1]) * lerpf(0.7, 1.0, _ease_out(t / 0.06))
			_spike(m, c, a, r * 0.1, L, r * 0.022, col, col)
	# 3) 뒤 보라 별 덩어리 (정점 A) → 윤곽 파편으로 깨짐
	var back_a := smoothstep(0.012, 0.03, t) * (1.0 - smoothstep(T_A - 0.01, T_A + 0.03, t))
	if back_a > 0.01:
		_star(m, c, rot + 0.28 * mir, mir, b.lens, r * scale * 1.22, r * 0.34, 1.0, _lin(VIO, 0.82 * back_a), _lin(VIO, 0.82 * back_a))
	var sh_t := t - (T_A - 0.012)
	if sh_t > 0.0:
		var fly := _ease_out(sh_t / (T_END - T_A))
		var fill_a := 0.78 * (1.0 - smoothstep(0.0, 0.05, sh_t))
		var line_a := 0.9 * (1.0 - smoothstep(T_END * 0.6, T_END, t))
		for i in SHARDS.size():
			var sd: Dictionary = b.shards[i]
			var a: float = float(sd.a)
			var dist := r * lerpf(0.62, 1.08, fly)
			var sc := r * float(sd.s) * lerpf(0.9, 1.05, fly)
			var sr: float = a + float(sd.rot) + float(sd.spin) * sh_t
			var at := Vector2(cos(a), sin(a)) * dist
			_shard(m, c, at, sr, sc, SHARDS[i], fill_a, line_a, pal)
	# 4) 네모 픽셀 조각 (화면에 똑바로 선 사각형)
	for sq: Dictionary in b.squares:
		var lt := t - float(sq.t0) / ts
		var life := float(sq.life) / ts
		if lt < 0.0 or lt > life:
			continue
		var k := lt / life
		var a: float = sq.a
		var dist := r * (float(sq.d0) + float(sq.v) * lt)
		var x := cos(a) * dist
		var y := sin(a) * dist + r * float(sq.up) * lt
		var s := r * float(sq.s) * (1.0 - 0.4 * k)
		var col: Color = sq.col
		col.a = float(sq.al) * (1.0 - smoothstep(0.6, 1.0, k))
		var p0 := m._w(c, x - s, y - s)
		var p1 := m._w(c, x + s, y - s)
		var p2 := m._w(c, x + s, y + s)
		var p3 := m._w(c, x - s, y + s)
		m._tri(p0, p1, p2, col)
		m._tri(p0, p2, p3, col)
	# 5) 잔상: 가장 긴 가로 가지 반대쪽으로 계단처럼 밀린 별 (정점 A 동안)
	var echo_a := smoothstep(0.02, 0.035, t) * (1.0 - smoothstep(0.08, 0.115, t))
	if echo_a > 0.01:
		var back := -Vector2(cos(rot), sin(rot))
		for i in range(int(b.echoes), 0, -1):
			var off := back * r * 0.14 * i
			var ec: Color = pal.echo1 if i == 1 else pal.echo2
			var col := _lin(ec, (0.72 if i == 1 else 0.55) * echo_a)
			_star(m, m._w(c, off.x, off.y), rot, mir, b.lens, r * scale * 0.97, r * valley, 1.0, col, col)
	# 6) 본체 별: 마젠타 테두리 (가지마다 한쪽 짙은 그늘) → 연분홍 면 → 흰 심지
	if star_a > 0.01:
		var mag := _lin(MAG, star_a).lerp(_lin(WHITE, star_a), flash)
		var dk := _lin(MAG_DK, star_a).lerp(_lin(WHITE, star_a), flash)
		_star(m, c, rot, mir, b.lens, r * scale, r * valley, 1.0, mag, dk)
		var pale := _lin(PALE, star_a).lerp(_lin(WHITE, star_a), flash)
		_star(m, c, rot, mir, b.lens, r * scale * 0.86, r * valley * 0.72, 1.0, pale, pale)
		var core_k := 1.0 - smoothstep(T_A, T_B, t) * 0.45
		var cw := _lin(WHITE, star_a)
		_star(m, c, rot, mir, b.lens, r * scale * 0.56 * core_k, r * valley * 0.45, 1.0, cw, cw)


## 3갈래 별 (가지마다 반쪽씩 lit/shade 색). L = 가지 길이 기준 반경, v = 골 반경
static func _star(m: MocoFX, c: Vector3, rot: float, mir: float, lens: Array, L: float, v: float, _k: float, lit: Color, shade: Color) -> void:
	var n := ARMS.size()
	for i in n:
		var a := rot + float(ARMS[i][0]) * mir
		var tip_l := L * float(lens[i])
		var a_prev := rot + float(ARMS[(i + n - 1) % n][0]) * mir
		var a_next := rot + float(ARMS[(i + 1) % n][0]) * mir
		var vp := a + _half(a, a_prev)
		var vn := a + _half(a, a_next)
		var tip := m._w(c, cos(a) * tip_l, sin(a) * tip_l)
		var p0 := m._w(c, cos(vp) * v, sin(vp) * v)
		var p1 := m._w(c, cos(vn) * v, sin(vn) * v)
		m._tri(c, p0, tip, shade)
		m._tri(c, tip, p1, lit)


## a 에서 b 쪽으로 가는 짧은 각의 절반
static func _half(a: float, b: float) -> float:
	return wrapf(b - a, -PI, PI) * 0.5


## 가는 광선 (밑동 base 부터 끝 L 까지 좁아지는 쐐기)
static func _spike(m: MocoFX, c: Vector3, a: float, base: float, L: float, hw: float, col: Color, _col2: Color) -> void:
	var ca := cos(a)
	var sa := sin(a)
	var tip := m._w(c, ca * L, sa * L)
	var l0 := m._w(c, ca * base - sa * hw, sa * base + ca * hw)
	var r0 := m._w(c, ca * base + sa * hw, sa * base - ca * hw)
	m._tri(l0, tip, r0, col)


## 원형 광채: 가운데 색 → 가장자리 색 (꼭짓점 색 보간)
static func _disc(m: MocoFX, c: Vector3, R: float, inner: Color, outer: Color) -> void:
	var seg := 18
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		m._tri3(c, m._w(c, cos(a0) * R, sin(a0) * R), m._w(c, cos(a1) * R, sin(a1) * R), inner, outer, outer)


## 윤곽 파편: 처음엔 채운 덩어리, 곧 속이 비고 선만 남는다
static func _shard(m: MocoFX, c: Vector3, at: Vector2, rot: float, sc: float, shape: Array, fill_a: float, line_a: float, pal: Dictionary) -> void:
	var pts: Array = []
	for q: Vector2 in shape[0]:
		var v := q.rotated(rot) * sc + at
		pts.append(m._w(c, v.x, v.y))
	var closed: bool = shape[1]
	if fill_a > 0.01:
		var fc := _lin(pal.back, fill_a)
		for i in range(1, pts.size() - 1):
			m._tri(pts[0], pts[i], pts[i + 1], fc)
	if line_a > 0.01:
		var lc := _lin(pal.shard, line_a)
		var hw := sc * 0.045
		var n: int = pts.size() if closed else pts.size() - 1
		for i in n:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[(i + 1) % pts.size()]
			var seg := b - a
			var side := seg.cross(m._cam_pos - a).normalized() * hw
			# 모서리가 이어 보이게 양 끝을 조금 늘인다
			var ext := seg.normalized() * hw
			m._tri(a - ext - side, b + ext - side, b + ext + side, lc)
			m._tri(a - ext - side, b + ext + side, a - ext + side, lc)
