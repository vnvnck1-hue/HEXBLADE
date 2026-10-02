class_name BugSound
extends RefCounted
## 벌레 효과음 (코드 합성, 샘플 없음). Sfx 의 정적 캐시에 이름을 덧붙여 Sfx.play("bug_…") 로 쓴다.
## Sfx 본체는 건드리지 않는다 — 벌레가 처음 생길 때 ensure() 가 한 번 합성한다.
##  bug_click  큰턱 딸깍딸깍 (짧은 딸깍 3번)
##  bug_chitter 경계·피격 찍찍거림 (빠른 딸깍 + 높은 떨림)
##  bug_hiss   산 분사 (거친 노이즈 쉬익)
##  bug_squish 체액 터짐 (낮게 철퍽)
##  bug_skitter 다다닥 걸음 (아주 작은 발톱 소리 여러 번)
##  bug_dig    땅 파고 나옴 (흙 긁는 노이즈)

const RATE := 22050


static func ensure() -> void:
	if Sfx._cache.has("bug_click"):
		return
	Sfx._cache.bug_click = _wav(_clicks(0.22, [0.0, 0.07, 0.13], 2600.0, 0.5))
	Sfx._cache.bug_chitter = _wav(_chitter(0.32))
	Sfx._cache.bug_hiss = _wav(_noise(0.42, 0.55, func(k: float) -> float: return minf(1.0, k * 12.0) * pow(1.0 - k, 1.3)))
	Sfx._cache.bug_squish = _wav(_squish(0.38))
	Sfx._cache.bug_skitter = _wav(_clicks(0.2, [0.0, 0.04, 0.085, 0.12, 0.16], 4200.0, 0.22))
	Sfx._cache.bug_dig = _wav(_noise(0.5, 0.12, func(k: float) -> float: return sin(PI * k) * (0.6 + 0.4 * sin(k * 60.0))))
	if Sfx.inst:
		Sfx.inst.streams = Sfx._cache


static func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w


## 딸깍: 높은 감쇠 사인 + 짧은 노이즈 터짐을 at 시각마다
static func _clicks(dur: float, at: Array, hz: float, vol: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for c: float in at:
		var st := int(c * RATE)
		var f := hz * randf_range(0.85, 1.15)
		for i in range(st, mini(n, st + int(0.025 * RATE))):
			var tt := float(i - st) / RATE
			var env := exp(-tt * 260.0)
			s[i] += (sin(TAU * f * tt) * 0.7 + randf_range(-1, 1) * 0.6) * env * vol
	return s


static func _chitter(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := _clicks(dur, range(0, 9).map(func(i): return i * 0.032), 3200.0, 0.35)
	for i in n:
		var tt := float(i) / RATE
		var k := float(i) / n
		s[i] += sin(TAU * (1900.0 + 400.0 * sin(TAU * 38.0 * tt)) * tt) * 0.08 * sin(PI * k)
	return s


## 저역 필터 노이즈 (alpha 작을수록 둔탁)
static func _noise(dur: float, alpha: float, env: Callable) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	for i in n:
		y += alpha * (randf_range(-1, 1) - y)
		s[i] = y * 0.9 * float(env.call(float(i) / n))
	return s


static func _squish(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	for i in n:
		var tt := float(i) / RATE
		var k := float(i) / n
		y += 0.18 * (randf_range(-1, 1) - y)
		var body := sin(TAU * lerpf(180.0, 60.0, k) * tt) * 0.6 * pow(1.0 - k, 2.0)
		var wet := y * 1.4 * pow(1.0 - k, 1.5) * (0.6 + 0.4 * sin(tt * 170.0))
		s[i] = body + wet
	return s
