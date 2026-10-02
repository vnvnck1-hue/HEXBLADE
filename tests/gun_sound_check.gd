extends SceneTree
## Run with: Godot --headless --path . -s tests/gun_sound_check.gd
## 플레이어 기관총 발사음(GunSound)을 확인한다.
##  1. 변형 8개, 각 0.38초(44.1kHz), 정점 약 -1dBFS, 무음 아님.
##  2. 짜임: 시작 10ms 가 바로 크고(파열음), 저역(<150Hz)이 60~160ms 에 가장 세다(늦은 쿵).
##  3. 변형끼리 실제로 다르다 (같은 소리 반복 아님).
##  4. Sfx 의 "shoot" 은 변형 배열이고, 재생할 때마다 그중 하나를 고른다.

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _rms_db(x: PackedFloat32Array, a: float, b: float) -> float:
	var i0 := int(a * GunSound.RATE)
	var i1 := mini(int(b * GunSound.RATE), x.size())
	var s := 0.0
	for i in range(i0, i1):
		s += x[i] * x[i]
	return 10.0 * log(s / maxf(1, i1 - i0) + 1e-12) / log(10.0)


## 150Hz 이하 성분만 남긴 RMS (2차 저역 필터 두 번)
func _low_db(x: PackedFloat32Array, a: float, b: float) -> float:
	var y := GunSound._biquad(GunSound._biquad(x, "lp", 150.0, 0.707), "lp", 150.0, 0.707)
	return _rms_db(y, a, b)


func _run() -> void:
	var t0 := Time.get_ticks_msec()
	var xs := GunSound.build()
	print("  build %d ms" % (Time.get_ticks_msec() - t0))
	_check(xs.size() == GunSound.VARIANTS, "변형 %d개" % xs.size())
	var ok_len := true
	var ok_peak := true
	var ok_crack := true
	var ok_boom := true
	for x in xs:
		ok_len = ok_len and x.size() == int(GunSound.DUR * GunSound.RATE)
		var peak := 0.0
		for v in x:
			peak = maxf(peak, absf(v))
		ok_peak = ok_peak and absf(peak - 0.89) < 0.01
		ok_crack = ok_crack and _rms_db(x, 0.0, 0.01) > -24.0
		var early := _low_db(x, 0.0, 0.05)
		var late := _low_db(x, 0.06, 0.16)
		ok_boom = ok_boom and late > early + 3.0
	_check(ok_len, "길이 0.38초")
	_check(ok_peak, "정점 0.89")
	_check(ok_crack, "시작 10ms RMS > -24dBFS (파열음)")
	_check(ok_boom, "저역이 0~50ms 보다 60~160ms 에서 3dB 이상 셈 (늦은 쿵)")
	var diff := 0.0
	for i in xs[0].size():
		diff += absf(xs[0][i] - xs[1][i])
	_check(diff / xs[0].size() > 0.01, "변형끼리 다름 (평균 차 %.3f)" % (diff / xs[0].size()))

	var sfx := Sfx.new()
	root.add_child(sfx)
	await process_frame
	var shots = sfx.streams.get("shoot")
	_check(shots is Array and shots.size() == GunSound.VARIANTS, "Sfx.shoot 은 변형 배열")
	_check(shots is Array and shots[0] is AudioStreamWAV and shots[0].mix_rate == GunSound.RATE, "44.1kHz 스트림")
	var picked := {}
	for i in 24:
		var p := Sfx.play("shoot")
		if p:
			if i == 0:
				_check(p.stream in shots, "재생 스트림이 변형 중 하나")
			picked[p.stream] = true
	_check(picked.size() >= 3, "여러 번 재생하면 여러 변형이 나옴 (%d종)" % picked.size())
	sfx.queue_free()
	await process_frame
	print("RESULT gun_sound_check fails=%d" % fails)
	quit(1 if fails > 0 else 0)
