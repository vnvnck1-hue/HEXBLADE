class_name Sfx
extends Node
## 코드로 합성한 효과음과 재생 풀.
## 합성은 무거워서(약 15초 분량을 표본마다 계산) 처음 한 번만 하고, 이후 씬은 같은 소리를 그대로 쓴다.

const RATE := 22050
static var inst: Sfx
static var _cache := {}
static var _muted := false
var streams := {}
var players: Array[AudioStreamPlayer] = []
## 음소거(M 키)는 씬을 옮겨도 유지된다
var muted: bool:
	get:
		return _muted
	set(v):
		_muted = v


func _ready() -> void:
	inst = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 기관총 한 발이 0.38초라 연사 중에는 발사음만 5개쯤 겹친다
	for i in 24:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	if _cache.is_empty():
		_build()
	streams = _cache


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _build() -> void:
	# 기관총 발사음: 변형 여러 개 중 하나를 재생할 때마다 고른다 (GunSound, 44.1kHz)
	var shots: Array[AudioStreamWAV] = []
	for s in GunSound.build():
		shots.append(_wav(s, GunSound.RATE))
	_cache.shoot = shots
	_cache.eshot = _synth(0.12, func(t, k): return sin(TAU * lerp(620.0, 300.0, k) * t) * 0.28 * (1.0 - k))
	_cache.hit = _synth(0.06, func(t, k): return (randf() * 2.0 - 1.0) * 0.35 * (1.0 - k) + sin(TAU * 1800.0 * t) * 0.15 * (1.0 - k))
	_cache.boom = _synth_filtered(0.55, 0.12, func(t, k): return ((randf() * 2.0 - 1.0) * 0.9 + sin(TAU * lerp(110.0, 38.0, k) * t) * 0.8) * pow(1.0 - k, 2.2))
	_cache.hurt = _synth(0.28, func(t, k): return _saw(lerp(420.0, 110.0, k), t) * 0.3 * (1.0 - k))
	_cache.dash = _synth_filtered(0.2, 0.25, func(t, k): return (randf() * 2.0 - 1.0) * 0.45 * sin(PI * k))
	_cache.slash = _synth_filtered(0.18, 0.5, func(t, k): return (randf() * 2.0 - 1.0) * 0.5 * sin(PI * k) + sin(TAU * lerp(900.0, 1500.0, k) * t) * 0.08 * (1.0 - k))
	_cache.spawn = _synth(0.3, func(t, k): return sin(TAU * lerp(200.0, 700.0, k) * t) * 0.14 * sin(PI * k))
	_cache.ready = _synth(0.08, func(t, k): return sin(TAU * 1760.0 * t) * 0.12 * (1.0 - k))
	_cache.charge = _synth(1.0, func(t, k): return (sin(TAU * lerp(180.0, 900.0, k * k) * t) * 0.5 + _saw(lerp(90.0, 450.0, k * k), t) * 0.25) * 0.22 * minf(1.0, k * 8.0))
	_cache.charged = _synth(0.25, func(t, k): return (sin(TAU * 1320.0 * t) + sin(TAU * 1980.0 * t) * 0.5) * 0.16 * (1.0 - k))
	_cache.laser = _synth_filtered(0.75, 0.35, func(t, k): return ((randf() * 2.0 - 1.0) * 0.8 * pow(1.0 - k, 1.5) + _saw(lerp(220.0, 55.0, k), t) * 0.7 * (1.0 - k) + sin(TAU * lerp(1600.0, 200.0, k) * t) * 0.3 * pow(1.0 - k, 3.0)))
	_cache.echarge = _synth(1.05, func(t, k): return (_sq(lerp(140.0, 620.0, k * k), t) * 0.16 + sin(TAU * lerp(300.0, 1500.0, k * k) * t) * 0.22) * minf(1.0, k * 6.0) * (0.7 + 0.3 * sin(TAU * lerp(8.0, 30.0, k) * t)))
	_cache.elaser = _synth_filtered(0.6, 0.3, func(t, k): return ((randf() * 2.0 - 1.0) * 0.8 * pow(1.0 - k, 1.6) + _saw(lerp(160.0, 40.0, k), t) * 0.8 * (1.0 - k) + _sq(lerp(900.0, 120.0, k), t) * 0.15 * pow(1.0 - k, 3.0)))
	_cache.tshot = _synth_filtered(0.14, 0.35, func(t, k): return ((randf() * 2.0 - 1.0) * 0.5 + _sq(lerp(260.0, 90.0, k), t) * 0.35) * pow(1.0 - k, 2.0))
	_cache.hatch = _synth_filtered(0.32, 0.3, func(t, k): return ((randf() * 2.0 - 1.0) * 0.6 * pow(1.0 - k, 3.0) + _sq(lerp(180.0, 70.0, k), t) * 0.3 * pow(1.0 - k, 1.5) + sin(TAU * 1250.0 * t) * 0.1 * pow(1.0 - k, 4.0)))
	_cache.hrise = _synth(0.75, func(t, k): return (_saw(lerp(60.0, 190.0, k), t) * 0.16 + sin(TAU * lerp(220.0, 520.0, k) * t) * 0.1 + (randf() * 2.0 - 1.0) * 0.05) * sin(PI * minf(1.0, k * 1.1)) * (0.8 + 0.2 * sin(TAU * 18.0 * t)))
	_cache.twind = _synth(0.6, func(t, k): return (_saw(lerp(80.0, 420.0, k), t) * 0.18 + sin(TAU * lerp(400.0, 1300.0, k) * t) * 0.12) * minf(1.0, k * 5.0) * (0.75 + 0.25 * sin(TAU * lerp(12.0, 40.0, k) * t)))
	_cache.tink = _synth(0.09, func(t, k): return (sin(TAU * 3900.0 * t) * 0.5 + sin(TAU * 6100.0 * t) * 0.3 + sin(TAU * 2600.0 * t) * 0.2) * 0.3 * pow(1.0 - k, 3.0))
	_cache.lock =_synth(0.09, func(t, k): return (_sq(1650.0 if k < 0.45 else 2200.0, t) * 0.14 + sin(TAU * 3300.0 * t) * 0.08) * (1.0 - k * 0.6))
	_cache.slowin = _synth_filtered(0.7, 0.3, func(t, k): return ((randf() * 2.0 - 1.0) * 0.35 * (1.0 - k) + sin(TAU * lerp(520.0, 70.0, pow(k, 0.5)) * t) * 0.35) * sin(PI * minf(1.0, k * 4.0)) * (1.0 - k))
	_cache.roll = _synth_filtered(0.3, 0.4, func(t, k): return (randf() * 2.0 - 1.0) * 0.5 * sin(PI * k) * (0.6 + 0.4 * sin(TAU * 22.0 * t)))
	_cache.land = _synth_filtered(0.2, 0.2, func(t, k): return ((randf() * 2.0 - 1.0) * 0.6 + sin(TAU * lerp(120.0, 50.0, k) * t)) * pow(1.0 - k, 2.0))
	var loop := _synth_filtered(1.0, 0.3, func(t, k): return (randf() * 2.0 - 1.0) * 0.4 + sin(TAU * 70.0 * t) * 0.15)
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = int(1.0 * RATE)
	_cache.boost = loop
	_cache.overload = _synth(0.5, func(t, k): return (_sq(lerp(300.0, 1400.0, k), t) * 0.25 + sin(TAU * lerp(600.0, 2400.0, k) * t) * 0.2) * (0.4 + 0.6 * k) * (0.6 + 0.4 * sin(TAU * 30.0 * t)))
	_cache.powerdown = _synth(0.55, func(t, k): return (sin(TAU * lerp(700.0, 60.0, pow(k, 0.5)) * t) * 0.35 + _saw(lerp(350.0, 30.0, k), t) * 0.12) * (1.0 - k))
	_cache.beam = _looped(func(t, k): return (randf() * 2.0 - 1.0) * 0.25 + _saw(55.0, t) * 0.35 + sin(TAU * 220.0 * t) * 0.15 * sin(TAU * 6.0 * t))
	# 중력 크롤러: 금속 충돌음 · 도탄 휘파람 · 회전 가속 · 발진 · 변신 철컥
	_cache.clank = _synth_filtered(0.24, 0.6, func(t, k): return (randf() * 2.0 - 1.0) * 0.55 * pow(1.0 - k, 6.0) + (sin(TAU * 820.0 * t) * 0.34 + sin(TAU * 1310.0 * t) * 0.26 + sin(TAU * 2170.0 * t) * 0.16) * pow(1.0 - k, 2.5))
	_cache.ricochet = _synth(0.24, func(t, k): return sin(TAU * lerp(3600.0, 1700.0, k) * t + sin(TAU * 34.0 * t) * 1.5) * 0.2 * pow(1.0 - k, 1.3) * minf(1.0, k * 40.0))
	_cache.rev = _synth(0.66, func(t, k): return (_saw(lerp(70.0, 420.0, k * k), t) * 0.2 + sin(TAU * lerp(140.0, 900.0, k * k) * t) * 0.14) * minf(1.0, k * 4.0) * (0.75 + 0.25 * sin(TAU * lerp(10.0, 45.0, k) * t)))
	_cache.launch = _synth_filtered(0.32, 0.25, func(t, k): return (randf() * 2.0 - 1.0) * 0.8 * pow(1.0 - k, 3.0) + sin(TAU * lerp(160.0, 45.0, k) * t) * 0.9 * pow(1.0 - k, 1.5))
	_cache.unfold = _synth(0.34, func(t, k): return (randf() * 2.0 - 1.0) * (exp(-t * 90.0) * 0.7 + (exp(-(t - 0.07) * 90.0) * 0.6 if t > 0.07 else 0.0)) + _sq(lerp(520.0, 260.0, k), t) * 0.1 * (1.0 - k))
	# 패링: 예고 섬광음(쨍) · 판정 창 신호(핑) · 성공 금속 충돌음(깡 + 저음 충격)
	_cache.pwarn = _synth(0.42, func(t, k): return (sin(TAU * lerp(2300.0, 3150.0, sqrt(k)) * t) * 0.26 + sin(TAU * 4700.0 * t) * 0.12 * pow(1.0 - k, 2.0)) * pow(1.0 - k, 1.4) * minf(1.0, k * 80.0) + (randf() * 2.0 - 1.0) * 0.3 * pow(1.0 - k, 14.0))
	_cache.pcue = _synth(0.12, func(t, k): return (sin(TAU * 3520.0 * t) * 0.22 + sin(TAU * 5280.0 * t) * 0.1) * pow(1.0 - k, 2.0))
	_cache.parry = _synth_filtered(1.1, 0.75, func(t, k): return (randf() * 2.0 - 1.0) * 0.9 * pow(1.0 - k, 16.0) + (sin(TAU * 1180.0 * t) * 0.3 + sin(TAU * 1763.0 * t) * 0.24 + sin(TAU * 2541.0 * t) * 0.18 + sin(TAU * 3917.0 * t) * 0.1) * pow(1.0 - k, 2.4) + sin(TAU * lerp(150.0, 42.0, k) * t) * 0.75 * pow(1.0 - k, 3.5))
	_cache.win = _notes([523.0, 659.0, 784.0, 1047.0], 0.12)
	_cache.lose = _notes([392.0, 311.0, 233.0, 175.0], 0.16)


static func play(id: String, pitch_jitter := 0.06, vol_db := 0.0) -> AudioStreamPlayer:
	if inst == null or inst.muted or not inst.streams.has(id):
		return null
	for p in inst.players:
		if not p.playing:
			var s = inst.streams[id]
			p.stream = s.pick_random() if s is Array else s
			p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
			p.volume_db = vol_db
			p.play()
			return p
	return null


func _sq(f: float, t: float) -> float:
	return 1.0 if fmod(t * f, 1.0) < 0.5 else -1.0


func _saw(f: float, t: float) -> float:
	return fmod(t * f, 1.0) * 2.0 - 1.0


func _wav(samples: PackedFloat32Array, rate := RATE) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clamp(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w


func _synth(dur: float, f: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		s[i] = f.call(float(i) / RATE, float(i) / n)
	return _wav(s)


## 단극 저역 필터를 거친 합성 (노이즈 계열)
func _synth_filtered(dur: float, alpha: float, f: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	for i in n:
		y += alpha * (f.call(float(i) / RATE, float(i) / n) - y)
		s[i] = y * 1.6
	return _wav(s)


func _looped(f: Callable) -> AudioStreamWAV:
	var w := _synth_filtered(1.0, 0.35, f)
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_end = RATE
	return w


func _notes(freqs: Array, step: float) -> AudioStreamWAV:
	var n := int(step * freqs.size() * RATE + 0.3 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for ni in freqs.size():
		var start := int(ni * step * RATE)
		var len := int(0.3 * RATE)
		for i in len:
			if start + i >= n:
				break
			var t := float(i) / RATE
			var env := 1.0 - float(i) / len
			s[start + i] += (sin(TAU * freqs[ni] * t) + 0.3 * _sq(freqs[ni], t)) * 0.16 * env
	return _wav(s)
