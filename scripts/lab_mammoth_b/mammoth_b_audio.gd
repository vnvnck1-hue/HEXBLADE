extends Node
## B안 전용 효과음: 궤도 체인 절단 · 도로 마찰 루프 · 철판 뒤틀림 · 지면 충돌 · 잔해 굴러감.
## 코드로 합성하고 자체 재생기를 써서 마찰 루프를 언제든 끊을 수 있다. 마스터 볼륨은 건드리지 않는다.

const RATE := 22050

var streams := {}
var _players: Array[AudioStreamPlayer] = []
var scrape: AudioStreamPlayer
var scrape_vol := 0.0              # 0~1
var scrape_pitch := 1.0


func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	# 체인 절단: 날카로운 금속 딸깍 + 짧게 울리는 고음
	streams.snap = _synth(0.45, func(t, k):
		var click := (randf() * 2.0 - 1.0) * exp(-t * 160.0) * 0.9
		var ring := (sin(TAU * 2310.0 * t) * 0.3 + sin(TAU * 3470.0 * t) * 0.2 + sin(TAU * 1180.0 * t) * 0.25) * exp(-t * 11.0)
		var thud := sin(TAU * lerpf(160.0, 60.0, k) * t) * exp(-t * 14.0) * 0.6
		return click + ring + thud)
	# 도로 마찰: 거친 노이즈 + 금속성 배음, 빠르게 떨리는 진폭
	var sc := _synth_filtered(1.0, 0.55, func(t, _k):
		var grit := (randf() * 2.0 - 1.0) * (0.55 + 0.45 * absf(sin(TAU * 31.0 * t)))
		var screech := sin(TAU * 1720.0 * t + sin(TAU * 7.0 * t) * 3.0) * 0.16 + sin(TAU * 2890.0 * t) * 0.08
		return grit * 0.6 + screech)
	sc.loop_mode = AudioStreamWAV.LOOP_FORWARD
	sc.loop_end = RATE
	streams.scrape = sc
	# 철판 뒤틀림: 느리게 떨어지는 저음 톱니 + 삐걱이는 중음
	streams.groan = _synth_filtered(1.2, 0.3, func(t, k):
		var low := _saw(lerpf(72.0, 34.0, k) + sin(TAU * 5.0 * t) * 3.0, t) * 0.55
		var creak := _sq(lerpf(310.0, 170.0, k * k) + sin(TAU * 13.0 * t) * 20.0, t) * 0.14 * absf(sin(TAU * 3.5 * t))
		return (low + creak) * sin(PI * minf(1.0, k * 1.2)) * (1.0 - k * 0.3))
	# 지면 충돌: 아주 낮은 충격 + 노이즈 폭발 + 금속 잔향
	streams.thump = _synth_filtered(1.1, 0.35, func(t, k):
		var body := sin(TAU * lerpf(62.0, 26.0, sqrt(k)) * t) * exp(-t * 3.2) * 1.1
		var burst := (randf() * 2.0 - 1.0) * exp(-t * 9.0) * 0.9
		var ring := (sin(TAU * 610.0 * t) * 0.14 + sin(TAU * 890.0 * t) * 0.1) * exp(-t * 4.0)
		return body + burst + ring)
	# 잔해: 무작위로 겹치는 짧은 금속 부딪힘
	var hits := []
	for i in 14:
		hits.append([randf() * 0.9, randf_range(700.0, 2600.0), randf_range(0.3, 1.0)])
	streams.debris = _synth(1.1, func(t, _k):
		var s := 0.0
		for h in hits:
			var dt: float = t - h[0]
			if dt >= 0.0 and dt < 0.12:
				s += ((randf() * 2.0 - 1.0) * 0.5 + sin(TAU * h[1] * dt) * 0.5) * exp(-dt * 45.0) * h[2]
		return s * 0.6)
	scrape = AudioStreamPlayer.new()
	scrape.stream = streams.scrape
	scrape.volume_db = -80.0
	add_child(scrape)


func play(id: String, vol_db := 0.0, pitch := 1.0) -> void:
	if _muted() or not streams.has(id):
		return
	for p in _players:
		if not p.playing:
			p.stream = streams[id]
			p.volume_db = vol_db
			p.pitch_scale = pitch
			p.play()
			return


## 기존 공용 효과음을 음높이까지 지정해 재생
static func sfx(id: String, vol_db := 0.0, pitch := 1.0) -> void:
	var p := Sfx.play(id, 0.0, vol_db)
	if p:
		p.pitch_scale = pitch


func _process(_dt: float) -> void:
	if scrape_vol > 0.001 and not _muted():
		if not scrape.playing:
			scrape.play()
		scrape.volume_db = linear_to_db(scrape_vol) - 2.0
		scrape.pitch_scale = scrape_pitch
	elif scrape.playing:
		scrape.stop()


func stop_all() -> void:
	scrape_vol = 0.0
	scrape.stop()
	for p in _players:
		p.stop()


func _muted() -> bool:
	return Sfx.inst != null and Sfx.inst.muted


func _saw(f: float, t: float) -> float:
	return fmod(t * f, 1.0) * 2.0 - 1.0


func _sq(f: float, t: float) -> float:
	return 1.0 if fmod(t * f, 1.0) < 0.5 else -1.0


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
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


func _synth_filtered(dur: float, alpha: float, f: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var y := 0.0
	for i in n:
		y += alpha * (f.call(float(i) / RATE, float(i) / n) - y)
		s[i] = y * 1.5
	return _wav(s)
