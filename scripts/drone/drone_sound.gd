class_name DroneSound
extends RefCounted
## 파트너 드론 효과음 (코드 합성, 샘플 없음). Sfx 의 정적 캐시에 이름을 덧붙여 Sfx.play("drone_…") 로 쓴다.
## Sfx 본체는 건드리지 않는다 — 드론이 처음 생길 때 ensure() 가 한 번 합성한다.
##  drone_step    발끝 톡 (작은 금속 탁)           drone_chirp   탑승자 말풍선 삐빅 (두 음)
##  drone_pop     청소 끝 뽁 + 반짝 차임            drone_hop     추진기 푸슉
##  drone_dock    합체 철컥 + 올라가는 윙           drone_undock  분리 치익 + 내려가는 윙
##  drone_shield  보호막 펼침 (반짝이는 화음)        drone_break   보호막이 막고 깨짐 (유리 짤랑)
##  drone_charge  볼텍스 모으기 (빨려드는 쉬익)      drone_burst   볼텍스 터짐 (낮은 쿵 + 바람)
##  drone_hurt    피격 지직                         drone_shot    합체 중 보조 사격 (작은 퓻)
##  vacuum_loop() 흡입 소리 (끊김 없이 반복되는 바람 소리, 드론이 따로 재생기를 갖는다)

const RATE := 22050


static func ensure() -> void:
	if Sfx._cache.has("drone_pop"):
		return
	Sfx._cache.drone_step = _wav(_tick(0.07, 1900.0, 0.35))
	Sfx._cache.drone_chirp = _wav(_chirp(0.2))
	Sfx._cache.drone_pop = _wav(_pop(0.42))
	Sfx._cache.drone_hop = _wav(_puff(0.32))
	Sfx._cache.drone_dock = _wav(_dock(0.5, true))
	Sfx._cache.drone_undock = _wav(_dock(0.42, false))
	Sfx._cache.drone_shield = _wav(_shimmer(0.6))
	Sfx._cache.drone_break = _wav(_glass(0.5))
	Sfx._cache.drone_charge = _wav(_suck(0.7))
	Sfx._cache.drone_burst = _wav(_burst(0.7))
	Sfx._cache.drone_hurt = _wav(_zap(0.25))
	Sfx._cache.drone_shot = _wav(_pew(0.12))
	if Sfx.inst:
		Sfx.inst.streams = Sfx._cache


static func _wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 30000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


static func _buf(dur: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(dur * RATE))
	return s


## 작은 금속 탁: 감쇠 사인 + 짧은 노이즈
static func _tick(dur: float, hz: float, vol: float) -> PackedFloat32Array:
	var s := _buf(dur)
	for i in s.size():
		var t := float(i) / RATE
		var env := exp(-t * 90.0)
		s[i] = (sin(TAU * hz * t) * 0.6 + sin(TAU * hz * 2.7 * t) * 0.25 + randf_range(-1, 1) * 0.3 * exp(-t * 400.0)) * env * vol
	return s


## 삐빅: 짧은 두 음 (올라감)
static func _chirp(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var notes := [[0.0, 1320.0], [0.09, 1760.0]]
	for nt: Array in notes:
		var st := int(float(nt[0]) * RATE)
		for i in range(st, mini(s.size(), st + int(0.08 * RATE))):
			var t := float(i - st) / RATE
			var env := minf(1.0, t * 400.0) * exp(-t * 28.0)
			var f: float = nt[1] * (1.0 + t * 0.6)
			s[i] += (sin(TAU * f * t) + 0.3 * sign(sin(TAU * f * t))) * env * 0.22
	return s


## 뽁 + 반짝: 아래로 꺾이는 짧은 음 뒤에 높은 차임 두 개
static func _pop(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var f := 900.0 * exp(-t * 30.0) + 260.0
		ph += TAU * f / RATE
		s[i] = sin(ph) * exp(-t * 26.0) * 0.45
		for c: Array in [[0.06, 2093.0], [0.13, 3136.0]]:
			var tc := t - float(c[0])
			if tc > 0.0:
				s[i] += sin(TAU * float(c[1]) * tc) * exp(-tc * 14.0) * 0.16
	return s


## 추진기 푸슉: 걸러진 노이즈 (빠르게 붙고 천천히 빠짐)
static func _puff(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var lp := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / dur
		lp += (randf_range(-1, 1) - lp) * lerpf(0.5, 0.08, k)
		s[i] = lp * minf(1.0, t * 80.0) * pow(1.0 - k, 1.6) * 0.9
	return s


## 합체 철컥 + 윙 (붙을 땐 올라가고 떨어질 땐 내려간다)
static func _dock(dur: float, up: bool) -> PackedFloat32Array:
	var s := _buf(dur)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / dur
		var clank := 0.0
		for c in [0.0, 0.05]:
			var tc: float = t - c
			if tc >= 0.0:
				clank += (sin(TAU * 620.0 * tc) * 0.5 + sin(TAU * 1730.0 * tc) * 0.3 + randf_range(-1, 1) * 0.4) * exp(-tc * 60.0)
		var f := (lerpf(240.0, 760.0, k) if up else lerpf(700.0, 200.0, k))
		ph += TAU * f / RATE
		var whine := (sin(ph) * 0.5 + sin(ph * 2.0) * 0.2) * sin(PI * k) * 0.35
		s[i] = clank * 0.5 + whine
	return s


## 보호막: 반짝이며 펼쳐지는 화음 (빠른 트레몰로)
static func _shimmer(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	for i in s.size():
		var t := float(i) / RATE
		var env := minf(1.0, t * 30.0) * exp(-t * 4.5)
		var trem := 0.7 + 0.3 * sin(TAU * 18.0 * t)
		var v := 0.0
		for f in [880.0, 1108.7, 1318.5, 1760.0]:
			v += sin(TAU * f * t * (1.0 + t * 0.04))
		s[i] = v * 0.09 * env * trem
	return s


## 유리 짤랑: 높은 비조화 배음 여럿 + 노이즈 터짐
static func _glass(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var fs := [2310.0, 3170.0, 4420.0, 5230.0, 6810.0]
	for i in s.size():
		var t := float(i) / RATE
		var v := randf_range(-1, 1) * exp(-t * 45.0) * 0.5
		for j in fs.size():
			v += sin(TAU * fs[j] * t) * exp(-t * (9.0 + j * 4.0)) * 0.18
		s[i] = v * 0.6
	return s


## 빨려드는 쉬익: 점점 높아지고 세지는 노이즈
static func _suck(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var lp := 0.0
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		var k := t / dur
		lp += (randf_range(-1, 1) - lp) * lerpf(0.05, 0.6, k)
		ph += TAU * lerpf(110.0, 330.0, k * k) / RATE
		s[i] = (lp * 0.7 + sin(ph) * 0.3) * k * k * 0.8
	return s


## 볼텍스 터짐: 낮은 쿵 + 바람이 흩어짐
static func _burst(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var lp := 0.0
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * (40.0 + 90.0 * exp(-t * 14.0)) / RATE
		lp += (randf_range(-1, 1) - lp) * 0.25
		s[i] = sin(ph) * exp(-t * 7.0) * 0.8 + lp * exp(-t * 5.0) * 0.5
	return s


## 지직: 끊기는 사각파
static func _zap(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	for i in s.size():
		var t := float(i) / RATE
		var gate := 1.0 if fmod(t * 38.0, 1.0) < 0.6 else 0.2
		var f := 180.0 + randf_range(-30, 30)
		s[i] = sign(sin(TAU * f * t)) * gate * exp(-t * 9.0) * 0.3 + randf_range(-1, 1) * 0.15 * exp(-t * 20.0)
	return s


## 퓻: 빠르게 내려가는 짧은 음
static func _pew(dur: float) -> PackedFloat32Array:
	var s := _buf(dur)
	var ph := 0.0
	for i in s.size():
		var t := float(i) / RATE
		ph += TAU * (2400.0 * exp(-t * 28.0) + 400.0) / RATE
		s[i] = (sin(ph) * 0.6 + sign(sin(ph)) * 0.15) * exp(-t * 30.0) * 0.4
	return s


## 흡입 소리: 걸러진 노이즈 + 낮은 모터. 1초짜리를 끊김 없이 반복 (앞뒤를 겹쳐 이음매를 지운다)
static func vacuum_loop() -> AudioStreamWAV:
	if Sfx._cache.has("_drone_vac"):
		return Sfx._cache._drone_vac
	var n := RATE
	var raw := PackedFloat32Array()
	raw.resize(n + int(RATE * 0.2))
	var lp := 0.0
	var lp2 := 0.0
	for i in raw.size():
		var t := float(i) / RATE
		lp += (randf_range(-1, 1) - lp) * 0.35
		lp2 += (lp - lp2) * 0.5
		raw[i] = lp2 * 0.55 + sin(TAU * 118.0 * t) * 0.12 + sin(TAU * 236.0 * t) * 0.06
	var x := int(RATE * 0.2)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = raw[i]
		if i < x:
			var k := float(i) / x
			s[i] = raw[i] * k + raw[n + i] * (1.0 - k)
	var w := _wav(s, true)
	Sfx._cache._drone_vac = w
	return w
