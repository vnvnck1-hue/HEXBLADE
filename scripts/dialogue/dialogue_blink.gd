class_name DialogueBlink
extends RefCounted
## 표정 전환과 독립적인 짧은 눈 깜빡임. 게임의 전역 난수/선택지에는 영향을 주지 않는다.
const CLOSED_TIME := 0.12
const MIN_WAIT := 2.8
const MAX_WAIT := 6.2
var rng := RandomNumberGenerator.new()
var remaining := 0.0
var closed := false
var count := 0

func _init() -> void:
	rng.randomize()
	remaining = rng.randf_range(MIN_WAIT, MAX_WAIT)

func step(dt: float, reduced: bool) -> void:
	if reduced:
		closed = false
		remaining = maxf(remaining, MIN_WAIT)
		return
	remaining -= maxf(dt, 0.0)
	if remaining > 0.0:
		return
	closed = not closed
	if closed:
		count += 1
	remaining = CLOSED_TIME if closed else rng.randf_range(MIN_WAIT, MAX_WAIT)
