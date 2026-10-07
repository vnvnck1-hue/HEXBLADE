class_name LancasterSound
extends RefCounted
## LANCASTER 의 육중한 기계음 (코드 합성, 샘플 없음). Sfx 의 정적 캐시에 이름을 덧붙여 Sfx.play("lan_…") 로 쓴다.
## BugSound 와 같은 방식 — 보스가 처음 생길 때 ensure() 가 한 번 합성한다.
##  lan_servo  큰 관절이 도는 유압 서보 (낮게 웅 — 끝이 살짝 내려앉는 기어 소리)
##  lan_step   육중한 발 디딤 (아주 낮은 쿵 + 철판 울림)
##  lan_crush  짓밟기 (쾅 + 껍질 우지끈 + 체액 철퍽)
##  lan_hiss   관절 · 배기 증기 (쉬익)
##  lan_clack  재장전 "철컥!" (노리쇠 뒤로 → 앞으로 박힘, 두 번의 금속 타격)
##  lan_hum    눈이 켜지는 전원 상승음 (낮게 시작해 높아지는 윙)
##  lan_alarm  보스전 시작 경보 (두 음을 오가는 사이렌 + 낮은 경적)

const RATE := 22050


static func ensure() -> void:
	if Sfx._cache.has("lan_servo"):
		return
	Sfx._cache.lan_servo = _wav(_servo(0.9))
	Sfx._cache.lan_step = _wav(_step(0.7))
	Sfx._cache.lan_crush = _wav(_crush(0.9))
	Sfx._cache.lan_hiss = _wav(_hiss(0.8))
	Sfx._cache.lan_clack = _wav(_clack(0.62))
	Sfx._cache.lan_hum = _wav(_hum(1.1))
	Sfx._cache.lan_alarm = _wav(_alarm(2.6))
	if Sfx.inst:
		Sfx.inst.streams = Sfx._cache


static func _wav(s: PackedFloat32Array) -> AudioStreamWAV:
	# 겹친 소리가 깨지지 않게 최대값을 0.92 로 맞춘다 (넘을 때만)
	var peak := 0.0
	for v in s:
		peak = maxf(peak, absf(v))
	if peak > 0.92:
		var g := 0.92 / peak
		for i in s.size():
			s[i] *= g
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	return w


static func _buf(dur: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(dur * RATE))
	return s


## 한 극 저역 통과 (노이즈 다듬기)
static func _lp(s: PackedFloat32Array, hz: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * hz / RATE)
	var y := 0.0
	for i in s.size():
		y += (s[i] - y) * a
		s[i] = y
	return s


## 철판 울림: 배수가 아닌 감쇠 사인 여러 개
static func _ring(s: PackedFloat32Array, at: float, freqs: Array, vol: float, decay: float) -> void:
	var st := int(at * RATE)
	for i in range(st, s.size()):
		var tt := float(i - st) / RATE
		var v := 0.0
		for f: float in freqs:
			v += sin(TAU * f * tt)
		s[i] += v / freqs.size() * vol * exp(-tt * decay)


## 쿵: 음이 아래로 미끄러지는 아주 낮은 사인
static func _thump(s: PackedFloat32Array, at: float, hz0: float, hz1: float, vol: float, decay: float) -> void:
	var st := int(at * RATE)
	var ph := 0.0
	for i in range(st, s.size()):
		var tt := float(i - st) / RATE
		var f := lerpf(hz1, hz0, exp(-tt * 18.0))
		ph += TAU * f / RATE
		s[i] += sin(ph) * vol * exp(-tt * decay) * minf(1.0, tt * 400.0)


## 짧은 노이즈 터짐 (저역 통과 hz)
static func _burst(s: PackedFloat32Array, at: float, dur: float, hz: float, vol: float) -> void:
	var st := int(at * RATE)
	var n := mini(s.size(), st + int(dur * RATE))
	var a := 1.0 - exp(-TAU * hz / RATE)
	var y := 0.0
	for i in range(st, n):
		var tt := float(i - st) / RATE
		y += (randf_range(-1, 1) - y) * a
		s[i] += y * vol * exp(-tt * 5.0 / dur)


static func _servo(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var ph := 0.0
	var ph2 := 0.0
	var n := s.size()
	var nz := 0.0
	for i in n:
		var k := float(i) / n
		var f := 62.0 + 26.0 * sin(PI * minf(k * 1.3, 1.0)) - 14.0 * smoothstep(0.75, 1.0, k)
		ph += TAU * f / RATE
		ph2 += TAU * f * 3.02 / RATE
		nz += (randf_range(-1, 1) - nz) * 0.08
		var env := smoothstep(0.0, 0.12, k) * (1.0 - smoothstep(0.7, 1.0, k))
		# 기어 이빨: 빠른 진폭 떨림
		var gear := 0.75 + 0.25 * sin(TAU * f * 0.5 * float(i) / RATE * 6.0)
		s[i] = (sin(ph) * 0.55 + sin(ph2) * 0.18 * gear + nz * 0.5) * env * 0.85
	_burst(s, dur * 0.82, 0.12, 900.0, 0.35)        # 끝에 멈춤 딸깍
	return s


static func _step(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	_thump(s, 0.0, 95.0, 38.0, 1.0, 7.0)
	_burst(s, 0.0, 0.09, 1400.0, 0.55)
	_ring(s, 0.005, [173.0, 241.0, 389.0, 517.0], 0.22, 9.0)
	return s


static func _crush(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	_thump(s, 0.0, 120.0, 34.0, 1.0, 5.0)
	_burst(s, 0.0, 0.12, 2200.0, 0.7)
	_ring(s, 0.004, [131.0, 207.0, 311.0, 463.0, 701.0], 0.28, 6.0)
	# 껍질 우지끈: 짧은 딱딱 여러 번
	for c in [0.02, 0.045, 0.06, 0.09, 0.115]:
		_burst(s, c, 0.025, 4500.0, 0.45)
	# 체액 철퍽: 낮게 끈적한 노이즈
	var st := int(0.05 * RATE)
	var y := 0.0
	for i in range(st, mini(s.size(), st + int(0.35 * RATE))):
		var tt := float(i - st) / RATE
		y += (randf_range(-1, 1) - y) * 0.06
		s[i] += y * 1.4 * exp(-tt * 9.0) * (0.6 + 0.4 * sin(tt * 90.0))
	return s


static func _hiss(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var n := s.size()
	var y := 0.0
	var y2 := 0.0
	for i in n:
		var k := float(i) / n
		var r := randf_range(-1, 1)
		y += (r - y) * 0.55
		y2 += (y - y2) * 0.2
		s[i] = (y - y2) * minf(1.0, k * 30.0) * pow(1.0 - k, 1.6) * 0.9
	return s


static func _clack(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	# 철: 노리쇠를 뒤로 당긴다 (긁히는 금속 + 높은 울림)
	_burst(s, 0.0, 0.05, 3800.0, 0.6)
	_ring(s, 0.0, [1180.0, 1730.0, 2410.0], 0.32, 38.0)
	# 미끄러짐
	var st := int(0.03 * RATE)
	var y := 0.0
	for i in range(st, mini(s.size(), st + int(0.14 * RATE))):
		var tt := float(i - st) / RATE
		y += (randf_range(-1, 1) - y) * 0.3
		s[i] += y * 0.18 * sin(PI * tt / 0.14)
	# 컥!: 앞으로 박힘 (무거운 쿵 + 낮은 금속 울림)
	_thump(s, 0.2, 160.0, 55.0, 0.95, 11.0)
	_burst(s, 0.2, 0.06, 2600.0, 0.85)
	_ring(s, 0.2, [430.0, 655.0, 1015.0, 1390.0], 0.42, 14.0)
	return s


static func _hum(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var n := s.size()
	var ph := 0.0
	var ph2 := 0.0
	for i in n:
		var k := float(i) / n
		var f := lerpf(90.0, 520.0, pow(k, 1.6))
		ph += TAU * f / RATE
		ph2 += TAU * f * 1.5 / RATE
		var env := smoothstep(0.0, 0.15, k) * (1.0 - smoothstep(0.85, 1.0, k))
		s[i] = (sin(ph) * 0.5 + signf(sin(ph2)) * 0.12) * env * 0.8
	return _lp(s, 2600.0)


## 경보: 두 음(낮고 높음)을 오가는 사이렌 3번 + 아래에 깔리는 낮은 경적
static func _alarm(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var n := s.size()
	var ph := 0.0
	var ph_h := 0.0
	var ph_l := 0.0
	for i in n:
		var tt := float(i) / RATE
		var k := float(i) / n
		var cyc := fmod(tt / 0.82, 1.0)
		# 위로 쭉 올라갔다 떨어지는 사이렌 (wail)
		var f := lerpf(440.0, 880.0, sin(PI * minf(cyc * 1.25, 1.0)))
		ph += TAU * f / RATE
		ph_h += TAU * f * 2.0 / RATE
		ph_l += TAU * 73.0 / RATE
		var siren := sin(ph) * 0.5 + signf(sin(ph_h)) * 0.1 + sin(ph * 3.0) * 0.08
		var horn := (signf(sin(ph_l)) * 0.35 + sin(ph_l * 2.0) * 0.25)
		var env := minf(1.0, tt * 30.0) * (1.0 - smoothstep(0.86, 1.0, k))
		s[i] = (siren * 0.8 + horn * 0.55) * env
	return _lp(s, 3800.0)
