class_name DialogueVoice
extends Node
## 글자가 찍힐 때 나는 짧은 말소리(블립). 인물마다 높이와 파형이 다르다 (DialogueCast 의 voice · wave).

const RATE := 22050
const LEN := 0.055

var volume_db := -14.0
var muted := false
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func blip(who: String, pitch_jitter := 0.08) -> void:
	if muted:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _stream(who)
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = volume_db
	p.play()


func _stream(who: String) -> AudioStreamWAV:
	if _streams.has(who):
		return _streams[who]
	var c := DialogueCast.info(who)
	var f: float = c.voice
	var wave: int = c.wave
	var n := int(LEN * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var k := float(i) / n
		var ph := fmod(f * t * (1.0 + 0.15 * (1.0 - k)), 1.0)
		var s := 0.0
		match wave:
			0: s = 1.0 if ph < 0.5 else -1.0
			1: s = 4.0 * absf(ph - 0.5) - 1.0
			_: s = sin(TAU * ph)
		s *= 0.32 * minf(1.0, k * 30.0) * pow(1.0 - k, 1.6)
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = data
	_streams[who] = w
	return w
