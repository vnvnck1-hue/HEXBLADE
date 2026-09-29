class_name Sfx
extends Node
## 코드로 합성한 효과음과 재생 풀.

const RATE := 22050
static var inst: Sfx
var streams := {}
var players: Array[AudioStreamPlayer] = []
var muted := false


func _ready() -> void:
	inst = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 16:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	streams.shoot = _synth(0.07, func(t, k): return _sq(lerp(1300.0, 520.0, k), t) * 0.22 * (1.0 - k))
	streams.eshot = _synth(0.12, func(t, k): return sin(TAU * lerp(620.0, 300.0, k) * t) * 0.28 * (1.0 - k))
	streams.hit = _synth(0.06, func(t, k): return (randf() * 2.0 - 1.0) * 0.35 * (1.0 - k) + sin(TAU * 1800.0 * t) * 0.15 * (1.0 - k))
	streams.boom = _synth_filtered(0.55, 0.12, func(t, k): return ((randf() * 2.0 - 1.0) * 0.9 + sin(TAU * lerp(110.0, 38.0, k) * t) * 0.8) * pow(1.0 - k, 2.2))
	streams.hurt = _synth(0.28, func(t, k): return _saw(lerp(420.0, 110.0, k), t) * 0.3 * (1.0 - k))
	streams.dash = _synth_filtered(0.2, 0.25, func(t, k): return (randf() * 2.0 - 1.0) * 0.45 * sin(PI * k))
	streams.slash = _synth_filtered(0.18, 0.5, func(t, k): return (randf() * 2.0 - 1.0) * 0.5 * sin(PI * k) + sin(TAU * lerp(900.0, 1500.0, k) * t) * 0.08 * (1.0 - k))
	streams.spawn = _synth(0.3, func(t, k): return sin(TAU * lerp(200.0, 700.0, k) * t) * 0.14 * sin(PI * k))
	streams.ready = _synth(0.08, func(t, k): return sin(TAU * 1760.0 * t) * 0.12 * (1.0 - k))
	streams.charge = _synth(1.0, func(t, k): return (sin(TAU * lerp(180.0, 900.0, k * k) * t) * 0.5 + _saw(lerp(90.0, 450.0, k * k), t) * 0.25) * 0.22 * minf(1.0, k * 8.0))
	streams.charged = _synth(0.25, func(t, k): return (sin(TAU * 1320.0 * t) + sin(TAU * 1980.0 * t) * 0.5) * 0.16 * (1.0 - k))
	streams.laser = _synth_filtered(0.75, 0.35, func(t, k): return ((randf() * 2.0 - 1.0) * 0.8 * pow(1.0 - k, 1.5) + _saw(lerp(220.0, 55.0, k), t) * 0.7 * (1.0 - k) + sin(TAU * lerp(1600.0, 200.0, k) * t) * 0.3 * pow(1.0 - k, 3.0)))
	streams.echarge = _synth(1.05, func(t, k): return (_sq(lerp(140.0, 620.0, k * k), t) * 0.16 + sin(TAU * lerp(300.0, 1500.0, k * k) * t) * 0.22) * minf(1.0, k * 6.0) * (0.7 + 0.3 * sin(TAU * lerp(8.0, 30.0, k) * t)))
	streams.elaser = _synth_filtered(0.6, 0.3, func(t, k): return ((randf() * 2.0 - 1.0) * 0.8 * pow(1.0 - k, 1.6) + _saw(lerp(160.0, 40.0, k), t) * 0.8 * (1.0 - k) + _sq(lerp(900.0, 120.0, k), t) * 0.15 * pow(1.0 - k, 3.0)))
	streams.tshot = _synth_filtered(0.14, 0.35, func(t, k): return ((randf() * 2.0 - 1.0) * 0.5 + _sq(lerp(260.0, 90.0, k), t) * 0.35) * pow(1.0 - k, 2.0))
	streams.hatch = _synth_filtered(0.32, 0.3, func(t, k): return ((randf() * 2.0 - 1.0) * 0.6 * pow(1.0 - k, 3.0) + _sq(lerp(180.0, 70.0, k), t) * 0.3 * pow(1.0 - k, 1.5) + sin(TAU * 1250.0 * t) * 0.1 * pow(1.0 - k, 4.0)))
	streams.hrise = _synth(0.75, func(t, k): return (_saw(lerp(60.0, 190.0, k), t) * 0.16 + sin(TAU * lerp(220.0, 520.0, k) * t) * 0.1 + (randf() * 2.0 - 1.0) * 0.05) * sin(PI * minf(1.0, k * 1.1)) * (0.8 + 0.2 * sin(TAU * 18.0 * t)))
	streams.twind = _synth(0.6, func(t, k): return (_saw(lerp(80.0, 420.0, k), t) * 0.18 + sin(TAU * lerp(400.0, 1300.0, k) * t) * 0.12) * minf(1.0, k * 5.0) * (0.75 + 0.25 * sin(TAU * lerp(12.0, 40.0, k) * t)))
	streams.tink = _synth(0.09, func(t, k): return (sin(TAU * 3900.0 * t) * 0.5 + sin(TAU * 6100.0 * t) * 0.3 + sin(TAU * 2600.0 * t) * 0.2) * 0.3 * pow(1.0 - k, 3.0))
	streams.lock =_synth(0.09, func(t, k): return (_sq(1650.0 if k < 0.45 else 2200.0, t) * 0.14 + sin(TAU * 3300.0 * t) * 0.08) * (1.0 - k * 0.6))
	streams.slowin = _synth_filtered(0.7, 0.3, func(t, k): return ((randf() * 2.0 - 1.0) * 0.35 * (1.0 - k) + sin(TAU * lerp(520.0, 70.0, pow(k, 0.5)) * t) * 0.35) * sin(PI * minf(1.0, k * 4.0)) * (1.0 - k))
	streams.roll = _synth_filtered(0.3, 0.4, func(t, k): return (randf() * 2.0 - 1.0) * 0.5 * sin(PI * k) * (0.6 + 0.4 * sin(TAU * 22.0 * t)))
	streams.land = _synth_filtered(0.2, 0.2, func(t, k): return ((randf() * 2.0 - 1.0) * 0.6 + sin(TAU * lerp(120.0, 50.0, k) * t)) * pow(1.0 - k, 2.0))
	var loop := _synth_filtered(1.0, 0.3, func(t, k): return (randf() * 2.0 - 1.0) * 0.4 + sin(TAU * 70.0 * t) * 0.15)
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_end = int(1.0 * RATE)
	streams.boost = loop
	streams.overload = _synth(0.5, func(t, k): return (_sq(lerp(300.0, 1400.0, k), t) * 0.25 + sin(TAU * lerp(600.0, 2400.0, k) * t) * 0.2) * (0.4 + 0.6 * k) * (0.6 + 0.4 * sin(TAU * 30.0 * t)))
	streams.powerdown = _synth(0.55, func(t, k): return (sin(TAU * lerp(700.0, 60.0, pow(k, 0.5)) * t) * 0.35 + _saw(lerp(350.0, 30.0, k), t) * 0.12) * (1.0 - k))
	streams.beam = _looped(func(t, k): return (randf() * 2.0 - 1.0) * 0.25 + _saw(55.0, t) * 0.35 + sin(TAU * 220.0 * t) * 0.15 * sin(TAU * 6.0 * t))
	streams.win = _notes([523.0, 659.0, 784.0, 1047.0], 0.12)
	streams.lose = _notes([392.0, 311.0, 233.0, 175.0], 0.16)


static func play(id: String, pitch_jitter := 0.06, vol_db := 0.0) -> AudioStreamPlayer:
	if inst == null or inst.muted or not inst.streams.has(id):
		return null
	for p in inst.players:
		if not p.playing:
			p.stream = inst.streams[id]
			p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
			p.volume_db = vol_db
			p.play()
			return p
	return null


func _sq(f: float, t: float) -> float:
	return 1.0 if fmod(t * f, 1.0) < 0.5 else -1.0


func _saw(f: float, t: float) -> float:
	return fmod(t * f, 1.0) * 2.0 - 1.0


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clamp(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
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
