class_name InfestSound
extends RefCounted
## 감염 오염물 효과음 (코드 합성). BugSound 처럼 Sfx 정적 캐시에 이름을 덧붙여 Sfx.play("infest_…") 로 쓴다.
##  infest_pop   포낭 터짐: 낮은 퍽 + 젖은 노이즈 터짐 + 보글거리는 꼬리
##  infest_hit   포낭 맞음: 짧고 둔한 철퍽
##  infest_drip  방울이 바닥에 떨어짐: 아주 짧은 톡
##  infest_tear  막이 찢어짐: 끈적하게 늘어나다 끊기는 소리

const RATE := 22050


static func ensure() -> void:
	if Sfx._cache.has("infest_pop"):
		return
	Sfx._cache.infest_pop = [BugSound._wav(_pop(0.5, 1.0)), BugSound._wav(_pop(0.46, 1.12)), BugSound._wav(_pop(0.55, 0.88))]
	Sfx._cache.infest_hit = [BugSound._wav(_hit(0.13, 1.0)), BugSound._wav(_hit(0.12, 1.2))]
	Sfx._cache.infest_drip = BugSound._wav(_drip(0.09))
	Sfx._cache.infest_tear = BugSound._wav(_tear(0.42))
	if Sfx.inst:
		Sfx.inst.streams = Sfx._cache


## 한 극 저역 통과 (k 작을수록 둔하다)
static func _lp(s: PackedFloat32Array, k: float) -> PackedFloat32Array:
	var y := 0.0
	for i in s.size():
		y += (s[i] - y) * k
		s[i] = y
	return s


static func _pop(dur: float, pitch: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var noise := PackedFloat32Array()
	noise.resize(n)
	for i in n:
		noise[i] = randf_range(-1, 1)
	noise = _lp(noise, 0.18)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := float(i) / n
		# 낮은 퍽 (음이 빨리 떨어진다)
		var f := lerpf(150.0, 42.0, minf(1.0, t * 9.0)) * pitch
		ph += TAU * f / RATE
		var thump := sin(ph) * exp(-t * 16.0) * 0.9
		# 젖은 터짐 (앞쪽만 거칠게)
		var burst := noise[i] * (exp(-t * 34.0) * 1.6 + exp(-t * 7.0) * 0.35)
		s[i] = thump + burst
		# 보글거림: 짧은 물방울 음들이 흩어진다
	for b in 7:
		var st := int(randf_range(0.04, dur * 0.7) * RATE)
		var f0 := randf_range(380.0, 900.0) * pitch
		for i in range(st, mini(n, st + int(0.05 * RATE))):
			var tt := float(i - st) / RATE
			s[i] += sin(TAU * f0 * (1.0 + tt * 14.0) * tt) * exp(-tt * 70.0) * 0.22
	return s


static func _hit(dur: float, pitch: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = randf_range(-1, 1)
	s = _lp(s, 0.22)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(230.0, 90.0, minf(1.0, t * 14.0)) * pitch / RATE
		s[i] = s[i] * exp(-t * 40.0) * 1.3 + sin(ph) * exp(-t * 30.0) * 0.6
	return s


static func _drip(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		ph += TAU * lerpf(520.0, 1300.0, minf(1.0, t * 30.0)) / RATE
		s[i] = sin(ph) * exp(-t * 55.0) * 0.4 + randf_range(-1, 1) * exp(-t * 300.0) * 0.25
	return s


static func _tear(dur: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = randf_range(-1, 1)
	s = _lp(s, 0.1)
	for i in n:
		var t := float(i) / RATE
		var k := float(i) / n
		# 끈적하게 늘어나는 동안 떨리다가 끝에서 툭 끊긴다
		var stretch := sin(PI * minf(1.0, k * 1.25)) * (0.7 + 0.3 * sin(TAU * lerpf(18.0, 60.0, k) * t))
		var snap := exp(-maxf(0.0, t - dur * 0.78) * 60.0) * (1.0 if t > dur * 0.78 else 0.0)
		s[i] = s[i] * (stretch * 0.9 + snap * 1.4) * (1.0 - k * 0.3)
	return s
