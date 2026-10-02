class_name GunSound
## 플레이어 기관총 발사음 합성 (노이즈·사인만, 샘플 없음).
## 원본 설계는 tools/sfx/mg_synth.py, 기준 수치는 tools/sfx/mg_fit_params.json (후보 A_close).
## 파이썬판의 FFT 대역 나누기는 같은 폭의 바이쿼드 대역 필터로 바꿨다.
## 걸러 둔 노이즈 원본 몇 개를 변형마다 다른 위치에서 잘라 써서 합성 시간을 줄인다.

const RATE := 44100
const DUR := 0.38
const VARIANTS := 8
const VARY := 0.75
const OCT: Array[float] = [31.25, 62.5, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0]
const CTRL: Array[float] = [40.0, 125.0, 400.0, 1250.0, 4000.0, 12500.0]
const SOURCES := 3

## 시간 값은 초 단위
const BASE := {
	"b1_g": [-36.248, -13.472, -15.325, -18.772, -24.798, -34.391],
	"b2_g": [-37.868, -23.138, -27.535, -23.351, -21.548, -25.634],
	"b1_lv": 6.0, "b1_att": 0.01221, "b1_tau": 0.0795,
	"b2_lv": -0.279, "b2_t0": 0.0799, "b2_att": 0.03299, "b2_tau": 0.13993,
	"sw_lv": -30.732, "sw_f0": 2258.474, "sw_f1": 70.206, "sw_tf": 0.01254, "sw_t0": 0.01219,
	"sw_att": 0.00647, "sw_tau": 0.07599, "sw_drv": 3.612, "sw_h2": -21.26, "sw_jit": 20.862,
	"bm_lv": -10.326, "bm_f0": 211.893, "bm_f1": 51.409, "bm_t0": 0.07544, "bm_att": 0.0416, "bm_tau": 0.04645,
	"ck_lv": -34.795,
	"cr_lv": -22.441, "cr_f": 2201.139, "cr_tau": 0.10952, "cr_rate": 2217.609,
	"drive": 1.0,
}
const TIME_KEYS := ["b1_att", "b1_tau", "b2_t0", "b2_att", "b2_tau", "sw_tf", "sw_t0", "sw_att", "sw_tau",
	"bm_t0", "bm_att", "bm_tau", "cr_tau", "cr_rate"]
const PITCH_KEYS := ["sw_f0", "sw_f1", "bm_f0", "bm_f1", "cr_f"]
const DB_KEYS := ["b1_lv", "b2_lv", "sw_lv", "sw_h2", "bm_lv", "ck_lv", "cr_lv"]


## 변형 VARIANTS 개의 표본 (-1~1)
static func build(seed := 1) -> Array[PackedFloat32Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := int(DUR * RATE)
	# 옥타브 대역 노이즈 원본: [원본][대역] → 길이 2n (변형마다 다른 위치에서 n 만큼 자른다)
	var sources := []
	for s in SOURCES:
		var white := PackedFloat32Array()
		white.resize(n * 2)
		for i in n * 2:
			white[i] = rng.randf_range(-1.0, 1.0)
		var bands := []
		for c in OCT:
			bands.append(_biquad(white, "bp", minf(c, RATE * 0.45), 1.41))
		sources.append(bands)
	var out: Array[PackedFloat32Array] = []
	for v in VARIANTS:
		out.append(_render(_vary(BASE, rng), rng, sources, n))
	return out


static func _vary(p: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var q := p.duplicate(true)
	for k in ["b1_g", "b2_g"]:
		var g: Array = q[k]
		for i in g.size():
			g[i] += rng.randfn(0.0, 2.5 * VARY)
	for k in DB_KEYS:
		q[k] += rng.randfn(0.0, 2.5 * VARY)
	for k in PITCH_KEYS:
		q[k] *= exp(rng.randfn(0.0, 0.12 * VARY))
	for k in TIME_KEYS:
		q[k] *= exp(rng.randfn(0.0, 0.15 * VARY))
	return q


static func _render(p: Dictionary, rng: RandomNumberGenerator, sources: Array, n: int) -> PackedFloat32Array:
	var b1 := _shaped(sources[rng.randi() % SOURCES], rng.randi() % n, n, p.b1_g)
	var b2 := _shaped(sources[rng.randi() % SOURCES], rng.randi() % n, n, p.b2_g)
	var jit := _wobble(n, rng, p.sw_jit)
	var cr := _crackle(n, rng, p.cr_f, p.cr_tau, p.cr_rate)
	var b1_a := _db(p.b1_lv)
	var b2_a := _db(p.b2_lv)
	var sw_a := _db(p.sw_lv)
	var h2_a := _db(p.sw_lv + p.sw_h2)
	var bm_a := _db(p.bm_lv)
	var cr_a := _db(p.cr_lv)
	var ck_a := _db(p.ck_lv) * 4.0
	var ck_n := int(0.0006 * RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	var ph1 := 0.0
	var ph2 := 0.0
	var phb := 0.0
	var peak := 1e-9
	for i in n:
		var t := float(i) / RATE
		var v: float = b1[i] * _env(t, 0.0, p.b1_att, p.b1_tau) * b1_a + b2[i] * _env(t, p.b2_t0, p.b2_att, p.b2_tau) * b2_a
		if t >= p.sw_t0:
			var f: float = (p.sw_f1 + (p.sw_f0 - p.sw_f1) * exp(-(t - p.sw_t0) / p.sw_tf)) * (1.0 + jit[i])
			ph1 += TAU * f / RATE
			ph2 += TAU * f * 2.0 / RATE
			var e := _env(t, p.sw_t0, p.sw_att, p.sw_tau)
			v += tanh(sin(ph1) * p.sw_drv) * e * sw_a + sin(ph2) * e * h2_a
		if t >= p.bm_t0:
			var fb: float = p.bm_f1 + (p.bm_f0 - p.bm_f1) * exp(-(t - p.bm_t0) / 0.04)
			phb += TAU * fb / RATE
			v += sin(phb) * _env(t, p.bm_t0, p.bm_att, p.bm_tau) * bm_a
		v += cr[i] * cr_a
		if i < ck_n:
			v += rng.randf_range(-1.0, 1.0) * ck_a
		x[i] = v
		peak = maxf(peak, absf(v))
	var drive: float = p.drive
	var td := tanh(drive)
	var fade := int(0.005 * RATE)
	var peak2 := 1e-9
	for i in n:
		var v := tanh(x[i] / peak * drive) / td
		if i >= n - fade:
			v *= float(n - i) / fade
		x[i] = v
		peak2 = maxf(peak2, absf(v))
	for i in n:
		x[i] = x[i] / peak2 * 0.89
	return x


static func _env(t: float, start: float, att: float, tau: float) -> float:
	var d := t - start
	if d < 0.0:
		return 0.0
	return minf(1.0, d / maxf(att, 1e-5)) * exp(-d / tau)


static func _db(v: float) -> float:
	return pow(10.0, v / 20.0)


## 조절점 6개의 dB 를 옥타브 대역 10개로 보간해 섞는다 (원본의 off 위치부터 n 표본)
static func _shaped(bands: Array, off: int, n: int, ctrl_db: Array) -> PackedFloat32Array:
	var gains := PackedFloat32Array()
	for c in OCT:
		gains.append(_db(_interp_log(c, ctrl_db)))
	var y := PackedFloat32Array()
	y.resize(n)
	for b in bands.size():
		var src: PackedFloat32Array = bands[b]
		var g := gains[b]
		for i in n:
			y[i] += src[off + i] * g
	return y


static func _interp_log(f: float, ctrl_db: Array) -> float:
	var lf := log(f) / log(2.0)
	var l0 := log(CTRL[0]) / log(2.0)
	if lf <= l0:
		return ctrl_db[0]
	for i in CTRL.size() - 1:
		var a := log(CTRL[i]) / log(2.0)
		var b := log(CTRL[i + 1]) / log(2.0)
		if lf <= b:
			return lerpf(ctrl_db[i], ctrl_db[i + 1], (lf - a) / (b - a))
	return ctrl_db[CTRL.size() - 1]


## 주파수 흔들림 비율: 300Hz 이하로 걸러 낸 노이즈를 최대 amount% 로
static func _wobble(n: int, rng: RandomNumberGenerator, amount: float) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(n)
	for i in n:
		w[i] = rng.randfn(0.0, 1.0)
	w = _biquad(w, "lp", 300.0, 0.707)
	var m := 1e-9
	for v in w:
		m = maxf(m, absf(v))
	for i in n:
		w[i] = w[i] / m * amount / 100.0
	return w


## 파열 입자: 시간에 따라 줄어드는 밀도의 짧은 펄스를 fc 근처 넓은 대역으로 거름
static func _crackle(n: int, rng: RandomNumberGenerator, fc: float, tau: float, rate: float) -> PackedFloat32Array:
	var imp := PackedFloat32Array()
	imp.resize(n)
	for i in n:
		if rng.randf() < rate * exp(-float(i) / RATE / tau) / RATE:
			imp[i] = rng.randf_range(-1.0, 1.0) * (0.4 + rng.randf())
	var y := _biquad(imp, "bp", fc, 0.6)
	for i in n:
		y[i] *= 6.0
	return y


static func _biquad(x: PackedFloat32Array, kind: String, f: float, q: float) -> PackedFloat32Array:
	var w := TAU * f / RATE
	var c := cos(w)
	var a := sin(w) / (2.0 * q)
	var b0: float
	var b1: float
	var b2: float
	if kind == "bp":
		b0 = a; b1 = 0.0; b2 = -a
	else:
		b0 = (1.0 - c) / 2.0; b1 = 1.0 - c; b2 = (1.0 - c) / 2.0
	var a0 := 1.0 + a
	var a1 := -2.0 * c / a0
	var a2 := (1.0 - a) / a0
	b0 /= a0; b1 /= a0; b2 /= a0
	var y := PackedFloat32Array()
	y.resize(x.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in x.size():
		var v := x[i]
		var o := b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1; x1 = v; y2 = y1; y1 = o
		y[i] = o
	return y
