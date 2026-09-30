extends Node
## MAMMOTH 죽음 연출 B안 "궤도 파손과 전복" 감독 — 강화판 (연출 테스트 씬 전용, 본선 미적용).
## 기획: docs/mammoth-death/맘모스_죽음연출_기능명세서.md 5장 · storyboard-B.png
## 피드백 반영: 고속 주행의 관성으로 차체가 크게 돌며(스핀 아웃) 뒤집히고, 강철이 도로에 갈리며 불꽃이 쏟아진다.
##
##  B01 0.00-0.30 궤도 파손     0.09초 정지 → 파손측 궤도로 급접근. 궤도가 뜯겨 나가며 차체가 튀어 오른다
##  B02 0.30-1.50 관성 스핀     한쪽 궤도를 잃은 차체가 관성으로 크게 돌며 모서리로 도로를 긁는다 (불꽃 폭포)
##  B03 1.50-2.30 공중 전복     모서리가 걸려 차체가 떠오르며 뒤집힌다. 정점에서 잠깐 느려지고 포탑이 뜯겨 나간다
##  B04 2.30-3.35 뒤집힌 채 마찰  지붕으로 떨어져 튀어 오른 뒤, 계속 돌면서 도로에 갈린다 (최대 불꽃)
##  B05 3.35-4.00 연쇄 폭발     멈추는 순간 큰 폭발 1회 + 양 끝 연쇄 폭발. 넓게 풀백
##  B06 4.00-5.70 잔해 통과     높은 쿼터뷰 복귀. 불타는 잔해가 도로와 함께 멀어지고 플레이어는 반대 차선
##
## 차체 자세: 요(스핀)와 롤(전복)을 무게중심에 적용한 뒤, 차체 외곽 표본점 중 가장 낮은 점이 도로에 닿도록 높이를 푼다.
## 그래서 어떤 자세에서도 도로를 뚫지 않고, 도로에 닿은 표본점이 곧 불꽃이 튀는 접촉점이 된다.
## 시간: 실제 시간 × rate(관찰 속도) × warp(전복 정점의 짧은 속도 램프). warp 동안에는 월드도 같은 배율로 늦춘다.

signal finished(reason: String)

const Dummy := preload("res://scripts/lab_mammoth_b/mammoth_b_dummy.gd")
const Stage := preload("res://scripts/boss_stage.gd")
const DeathFX := preload("res://scripts/lab_mammoth_b/mammoth_b_fx.gd")
const Overlay := preload("res://scripts/lab_mammoth_b/mammoth_b_overlay.gd")
const Audio := preload("res://scripts/lab_mammoth_b/mammoth_b_audio.gd")
const CineCam := preload("res://scripts/lab_mammoth_b/mammoth_b_camera.gd")
const BT := preload("res://scripts/boss_tank.gd")

const DURATION := 5.70
const ENTRY_HOLD := 0.09
const SKIP_AFTER := 0.50
const SPIN := 0.30
const FLIP := 1.50
const TEAR := 2.02                 # 롤 약 105도: 포탑이 도로에 걸려 뜯겨 나간다
const IMPACT := 2.30               # 지붕으로 떨어지는 순간
const FREEZE := 0.08
const BLAST := 3.35
const HANDOFF := 4.00
const CAM_DONE := 4.90
const COM := Vector3(0, 1.8, 0)    # 무게중심 (차체 로컬)

const CUTS := [
	[0.00, "B01", "궤도 파손"], [SPIN, "B02", "관성 스핀"], [FLIP, "B03", "공중 전복"],
	[IMPACT, "B04", "뒤집힌 채 마찰"], [BLAST, "B05", "연쇄 폭발"], [HANDOFF, "B06", "잔해 통과"],
]

## 카메라 구간: [시작, 끝, 출발 포즈, 도착 포즈, 곡선]
const SHOTS := [
	[0.00, 0.09, "entry", "entry", "hold"],
	[0.09, 0.26, "entry", "hit", "whip"],
	[0.26, 0.46, "hit", "chase_a", "inout"],
	[0.46, 1.50, "chase_a", "chase_b", "sine"],
	[1.50, 1.78, "chase_b", "flip", "inout"],
	[1.78, 2.30, "flip", "flip_b", "sine"],
	[2.30, 2.50, "flip_b", "grind", "out"],
	[2.50, 3.35, "grind", "grind_b", "sine"],
	[3.35, 3.55, "grind_b", "blast", "out"],
	[3.55, 4.00, "blast", "blast_b", "sine"],
	[4.00, CAM_DONE, "blast_b", "return", "inout"],
]

# ── 외부에서 넣는 값 ──
var main: Main
var dummy: Dummy
var stage: Stage
var boss_cam: Camera3D
var bar: CanvasLayer
var speed_fx: CanvasLayer
var side := 1.0
var rate := 1.0
var flash_k := 1.0
var shake_k := 1.0
var low := false

# ── 상태 ──
var T := 0.0
var active := false
var done := false
var fx: DeathFX
var overlay: Overlay
var audio: Audio
var cam: CineCam
var light: OmniLight3D
var B0 := Vector3.ZERO
var entry_xf: Transform3D
var entry_fov := 50.0
var v0 := 42.0
var safe_pos := Vector3.ZERO
var slide_max := 4.2
var wreck_z := 0.0
var wreck_v := 0.0
var warp := 1.0
var _last_us := 0
var _cues: Array = []
var _cue_i := 0
var _spark_acc := 0.0
var _dust_cd := 0.0
var _fire_cd := 0.0
var _trail_cd := 0.0
var _chunk_cd := 0.0
var _marks := {}                   # 표본점 번호 → 이전 도로 좌표
var _samples: Array = []           # [visual 로컬 점, 포탑 소속]
var _turret: Node3D
var _turret_gone := false
var _tread_i := 0
var _impacts: Array = []           # [시각, 블러, 색수차, 월드 지점]
var _flashes: Array = []           # [시각, 색, 알파, 감쇠]
var _cam_handed := false
var _rig := Transform3D.IDENTITY
var _contacts: Array = []          # 이번 프레임 도로에 닿은 [표본 번호, 월드 점]
var _com_w := Vector3.ZERO


## ctx: main, dummy, stage, boss_cam, bar, speed_fx, side, rate, flash, shake, low
func begin(ctx: Dictionary) -> void:
	if active or done:
		return
	main = ctx.main
	dummy = ctx.dummy
	stage = ctx.stage
	boss_cam = ctx.boss_cam
	bar = ctx.bar
	speed_fx = ctx.speed_fx
	side = ctx.side
	rate = ctx.get("rate", 1.0)
	flash_k = ctx.get("flash", 1.0)
	shake_k = ctx.get("shake", 1.0)
	low = ctx.get("low", false)
	active = true
	T = 0.0
	_last_us = Time.get_ticks_usec()
	B0 = dummy.global_position
	entry_xf = boss_cam.global_transform
	entry_fov = boss_cam.fov
	v0 = stage.speed
	_tread_i = 0 if side > 0.0 else 1          # 모델이 180도 돌아 있어 로컬 -X 궤도가 월드 +X 쪽
	_turret = dummy.tank.turret
	dummy.driving = false
	# 뒤집힌 차체(반경 약 4.5m)가 도로 반폭 10 안에 남도록 횡이동량을 정한다
	slide_max = clampf(5.3 - side * B0.x, -1.5, 4.2)
	safe_pos = Vector3(clampf(B0.x + side * (slide_max - 7.5), -8.8, 8.8), 0, 3.4)
	_build_samples()

	fx = DeathFX.new()
	fx.stage = stage
	fx.budget = 0.5 if low else 1.0
	main.world.add_child(fx)
	light = fx.make_light(Color(1.0, 0.6, 0.25), 9.0)
	overlay = Overlay.new()
	add_child(overlay)
	audio = Audio.new()
	add_child(audio)
	cam = CineCam.new()
	cam.shake_k = shake_k
	main.add_child(cam)
	cam.global_transform = entry_xf
	cam.fov = entry_fov
	cam.current = true

	main.hud.visible = false
	bar.call("set_hp", 0.0, true)
	var br: Control = bar.get("root")
	var tw := br.create_tween().set_ignore_time_scale(true)
	tw.tween_interval(0.18 / rate)
	tw.tween_property(br, "modulate:a", 0.0, 0.2 / rate)

	_cues = [
		[0.00, "hit"], [ENTRY_HOLD, "tread"], [0.36, "lurch"], [0.62, "unravel"], [0.95, "unravel"],
		[1.20, "groan"], [FLIP, "catch"], [1.80, "slowin"], [TEAR, "tear"], [IMPACT, "impact"],
		[2.75, "grind_hit"], [3.05, "grind_hit"], [BLAST, "blast"], [3.47, "blast2"], [3.60, "blast3"],
		[3.75, "debris"], [HANDOFF, "handoff"], [CAM_DONE, "cam_return"],
	]
	_cue_i = 0
	print("DEATH_BEGIN variant=B+ side=%d rate=%.2f frame=%d" % [int(side), rate, main.capture_frame])


## 차체 외곽 표본점 (모델 로컬 → visual 로컬). 모서리가 둥글어 조금 안쪽으로 잡는다
func _build_samples() -> void:
	var pts := []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			pts.append([Vector3(3.45 * sx, 0.15, 2.5 * sz), false])
			pts.append([Vector3(3.45 * sx, 1.0, 3.25 * sz), false])
			pts.append([Vector3(3.3 * sx, 2.45, 2.4 * sz), false])
			pts.append([Vector3(1.85 * sx, 2.95, 2.7 * sz), false])
			pts.append([Vector3(1.8 * sx, 1.25, 3.6 * sz), false])
		pts.append([Vector3(1.8 * sx, 3.85, 2.3), false])        # 미사일 포드
		pts.append([Vector3(1.75 * sx, 3.55, -2.25), false])     # 보조 포탑
		pts.append([Vector3(0.7 * sx, 3.7, 2.95), false])        # 배기통
		pts.append([Vector3(2.2 * sx, 3.45, 0.25), true])        # 포탑 허리
		pts.append([Vector3(2.9 * sx, 3.8, -0.2), true])         # 귀 포드
		pts.append([Vector3(0.95 * sx, 3.65, -4.6), true])       # 포구
	pts.append([Vector3(0, 5.05, 0.25), true])
	pts.append([Vector3(0, 3.5, 2.45), true])
	pts.append([Vector3(0, 3.6, -2.3), true])
	_samples.clear()
	var mt := dummy.model.transform
	for p in pts:
		_samples.append([mt * (p[0] as Vector3), p[1]])


## Enter: 0.5초 이후에만. 끝 상태를 적용하고 정상 완료와 같은 경로로 끝낸다
func skip() -> void:
	if not active or T < SKIP_AFTER:
		return
	_detach_turret(false)
	_cue_i = _cues.size()
	T = DURATION
	wreck_z = 30.0
	_apply_body()
	stage.speed = 10.0
	_finish("skipped")


func _process(_dt: float) -> void:
	if not active and not done:
		return
	var now := Time.get_ticks_usec()
	var real := minf((now - _last_us) / 1000000.0, 0.25)
	_last_us = now
	if main.capture_mode:
		# 프레임 캡처는 저장 때문에 느려지므로 한 프레임 = 1/60초로 고정해 컷을 빠짐없이 남긴다
		real = 1.0 / 60.0
	if active:
		warp = _warp(T)
		var dT := real * rate * warp
		T += dT
		main.set_slowmo(rate * warp)
		while _cue_i < _cues.size() and T >= float(_cues[_cue_i][0]):
			_cue(_cues[_cue_i][1])
			_cue_i += 1
		_apply_body()
		_update_contact(dT)
		_update_stage()
		_update_camera()
		_update_overlay()
		if T >= DURATION:
			_finish("normal")
		_update_wreck(dT)
	else:
		_update_wreck(real * rate)


## 전복 정점의 속도 램프: 1.84초부터 0.3배로 늘어졌다가 떨어지기 직전 한 번에 원래 속도로
func _warp(t: float) -> float:
	if t < 1.84 or t > 2.22:
		return 1.0
	if t < 1.92:
		return lerpf(1.0, 0.3, smoothstep(1.84, 1.92, t))
	if t < 2.14:
		return 0.3
	return lerpf(0.3, 1.0, smoothstep(2.14, 2.22, t))


# ── 차체 곡선 ───────────────────────────────────────────

func _tb(t: float) -> float:
	return t if t < IMPACT else maxf(IMPACT, t - FREEZE)


## 스핀: 궤도가 끊긴 쪽이 끌리며 처음부터 빠르게 돌고 점점 느려진다 (총 250도)
func _yaw(tb: float) -> float:
	var u := clampf((tb - ENTRY_HOLD) / 3.3, 0.0, 1.0)
	return 250.0 * (1.0 - pow(1.0 - u, 1.7))


func _roll(tb: float) -> float:
	if tb < ENTRY_HOLD:
		return 0.0
	if tb < 0.4:
		return 14.0 * (1.0 - pow(1.0 - (tb - ENTRY_HOLD) / 0.31, 3.0))
	if tb < FLIP:
		var u := (tb - 0.4) / 1.1
		return 14.0 + 28.0 * smoothstep(0.0, 1.0, u) + sin(tb * 37.0) * 3.0 * sin(PI * u)
	if tb < IMPACT:
		return 42.0 + 138.0 * pow((tb - FLIP) / (IMPACT - FLIP), 1.8)
	var e := tb - IMPACT
	if e < 0.3:
		return 180.0 - 12.0 * sin(PI * e / 0.3)
	if e < 0.5:
		return 180.0 - 3.5 * sin(PI * (e - 0.3) / 0.2)
	return 180.0


## 도로 위로 뜨는 높이 (궤도가 끊기며 튀어 오름 · 전복 중 떠오름 · 지붕으로 떨어진 뒤 튐)
func _air(tb: float) -> float:
	if tb > 0.1 and tb < 0.38:
		return 0.55 * sin(PI * (tb - 0.1) / 0.28)
	if tb > 1.6 and tb < IMPACT:
		return 1.6 * pow(sin(PI * (tb - 1.6) / (IMPACT - 1.6)), 0.8)
	var e := tb - IMPACT
	if e > 0.0 and e < 0.32:
		return 0.9 * sin(PI * e / 0.32)
	if e >= 0.32 and e < 0.5:
		return 0.25 * sin(PI * (e - 0.32) / 0.18)
	return 0.0


func _slide(tb: float) -> float:
	var u := clampf((tb - 0.2) / 2.4, 0.0, 1.0)
	return slide_max * (1.0 - (1.0 - u) * (1.0 - u)) + 0.6 * smoothstep(IMPACT, BLAST, tb) * signf(slide_max)


## 속도를 잃고 플레이어 쪽으로 밀려온다
func _zoff(tb: float) -> float:
	return 5.0 * smoothstep(0.2, BLAST, tb)


func _base(tb: float) -> Vector3:
	return Vector3(side * _slide(tb), 0, _zoff(tb) + wreck_z)


## 차체 루트 기준 변환. 요·롤을 무게중심에 걸고, 가장 낮은 표본점이 도로 + air 에 오도록 높이를 푼다
func _solve(tb: float) -> Transform3D:
	var b := Basis(Vector3.UP, deg_to_rad(_yaw(tb)) * side) * Basis(Vector3.BACK, -side * deg_to_rad(_roll(tb)))
	var o := _base(tb) + COM - b * COM
	var y_all := 1e9
	var y_hull := 1e9
	for s in _samples:
		var y := (b * (s[0] as Vector3) + o).y
		y_all = minf(y_all, y)
		if not s[1]:
			y_hull = minf(y_hull, y)
	# 포탑이 뜯겨 나간 뒤에는 차체 표본만으로 서서히 넘겨 한 프레임에 툭 떨어지지 않게 한다
	var k := smoothstep(TEAR, TEAR + 0.2, tb) if _turret_gone else 0.0
	o.y += _air(tb) - lerpf(y_all, y_hull, k)
	return Transform3D(b, o)


func _apply_body() -> void:
	var tb := _tb(T)
	_rig = _solve(tb)
	dummy.visual.transform = _rig
	_com_w = dummy.to_global(_rig * COM)
	# 도로에 닿은 표본점 = 불꽃이 튀는 곳
	_contacts.clear()
	if _air(tb) < 0.12:
		for i in _samples.size():
			if _samples[i][1] and _turret_gone:
				continue
			var w := dummy.to_global(_rig * (_samples[i][0] as Vector3))
			if w.y < 0.3:
				_contacts.append([i, w])
	if not _turret_gone and is_instance_valid(_turret):
		# 포탑이 차체보다 늦게 따라와 비틀린다
		var lag := _roll(tb) - _roll(maxf(0.0, tb - 0.12))
		_turret.rotation = Vector3(0, 0, -side * deg_to_rad(lag) * 0.6)
		for i in 2:
			var g: Node3D = dummy.tank.cannons[i].pivot
			g.rotation.x = -0.15 * smoothstep(0.2, 1.2, tb) + sin(tb * 13.0 + i * 1.7) * 0.07
		var core := dummy.tank.core as MeshInstance3D
		if T < ENTRY_HOLD + 0.06:
			core.set_instance_shader_parameter("tint", Color.WHITE)
			core.set_instance_shader_parameter("energy", 4.0)
		else:
			core.set_instance_shader_parameter("tint", Pal.E_RED.lerp(Color("fff0b0"), randf() * 0.4))
			core.set_instance_shader_parameter("energy", 1.0 + randf() * 2.4)
	dummy.shadow.global_position = Vector3(_com_w.x, 0.015, _com_w.z)
	dummy.shadow.global_rotation = Vector3.ZERO


## 요 회전 각속도 (rad/s, 월드 Y)
func _yaw_rate(tb: float) -> float:
	return deg_to_rad(_yaw(tb + 0.01) - _yaw(tb)) / 0.01 * side


# ── 마찰 불꽃 · 먼지 · 긁힘 ─────────────────────────────

func _update_contact(dT: float) -> void:
	var tb := _tb(T)
	var grinding := T >= IMPACT and T < BLAST + 0.1
	var scraping := T >= 0.12 and T < FLIP + 0.1
	var rate_k := 0.0
	if scraping:
		rate_k = 420.0
	elif grinding:
		rate_k = lerpf(900.0, 380.0, smoothstep(IMPACT, BLAST, T))
	var has := _contacts.size() > 0
	var loud := (1.0 if has else 0.25) * (0.8 if scraping else (1.0 if grinding else 0.0))
	audio.scrape_vol = loud
	audio.scrape_pitch = lerpf(0.85, 1.45, clampf(T / 3.0, 0.0, 1.0)) * (0.6 + 0.4 * warp)
	cam.rumble = (0.035 if scraping else (0.06 if grinding else 0.0)) * (1.0 if has else 0.3)
	if has:
		var mid: Vector3 = _contacts[randi() % _contacts.size()][1]
		light.global_position = mid + Vector3(0, 0.5, 0)
		light.light_energy = (1.6 + randf() * 2.2) * (1.4 if grinding else 1.0)
	elif T >= FLIP and T < IMPACT:
		# 공중 전복: 도로에 남은 불꽃빛이 아랫면을 비추고, 뜯긴 궤도에서 불똥과 연기가 샌다
		light.global_position = Vector3(_com_w.x, 0.6, _com_w.z)
		light.light_energy = 3.0
		for k in 3:
			var ep := dummy.model.to_global(Vector3(-side * randf_range(1.8, 3.4), randf_range(0.2, 1.8), randf_range(-3.0, 3.0)))
			fx.spark(ep, Vector3(randf_range(-4, 4), randf_range(-2, 4), stage.speed * randf_range(0.2, 0.6)), randf_range(0.3, 0.7), 1.0, 0.4)
		_dust_cd -= dT
		if _dust_cd <= 0.0:
			_dust_cd = 0.03
			stage.puff(dummy.model.to_global(Vector3(-side * 2.6, 1.0, -3.2)), Color(0.12, 0.1, 0.13, 0.7), randf_range(1.6, 2.4), 0.6, 0.35)
			stage.puff(dummy.model.to_global(Vector3(-side * 2.6, 1.0, -3.2)), Color(1.0, 0.5, 0.15, 0.85), 1.2, 0.25, 0.35, true)
		for k in _marks.keys():
			_marks.erase(k)
		return
	else:
		light.light_energy = maxf(0.0, light.light_energy - dT * 10.0)
		for k in _marks.keys():
			_marks.erase(k)
		return
	var road := stage.speed
	var w_up := _yaw_rate(tb)
	_spark_acc += dT * rate_k
	var n := int(_spark_acc)
	_spark_acc -= n
	for i in n:
		# 닿은 점 두 개 사이 어딘가에서 튄다 (모서리를 따라 선으로 긁히는 느낌)
		var a: Vector3 = _contacts[randi() % _contacts.size()][1]
		var b: Vector3 = _contacts[randi() % _contacts.size()][1]
		var p := a.lerp(b, randf())
		p.y = 0.05
		# 스핀 때문에 접촉점이 도로를 쓸고 가는 속도가 불꽃에 실린다
		var r := p - Vector3(_com_w.x, 0.05, _com_w.z)
		var tang := Vector3(0, w_up, 0).cross(r)
		var v := tang * randf_range(0.5, 1.1) + Vector3(randf_range(-3.0, 3.0), randf_range(1.5, 9.0), road * randf_range(0.55, 1.1))
		fx.spark(p, v, randf_range(0.18, 0.55), randf_range(0.9, 1.5), 1.0 if randf() < 0.6 else 0.3)
	_dust_cd -= dT
	if _dust_cd <= 0.0:
		_dust_cd = 0.03
		var q: Vector3 = _contacts[randi() % _contacts.size()][1] + Vector3(0, 0.3, 0)
		stage.puff(q, Color(0.4, 0.38, 0.46, 0.55), randf_range(1.4, 2.6), 0.5, 0.85)
		if randf() < 0.4:
			stage.puff(q, Color(1.0, 0.55, 0.2, 0.7), randf_range(0.8, 1.4), 0.18, 0.9, true)
	_chunk_cd -= dT
	if _chunk_cd <= 0.0:
		_chunk_cd = 0.16
		var q: Vector3 = _contacts[randi() % _contacts.size()][1] + Vector3(0, 0.4, 0)
		fx.chunk(q, Vector3(randf_range(-6, 6), randf_range(4, 9), road * randf_range(0.3, 0.7)))
	# 도로 긁힘: 닿은 표본점마다 도로 좌표로 이전 점을 기억해 흐르는 자국을 잇는다
	var seen := {}
	for c in _contacts:
		var id: int = c[0]
		var w: Vector3 = c[1]
		w.y = 0.03
		seen[id] = true
		var road_p := Vector3(w.x, 0, w.z - stage.scroll)
		if _marks.has(id):
			var prev: Vector3 = _marks[id] + Vector3(0, 0, stage.scroll)
			if prev.distance_to(w) > 0.3:
				if prev.distance_to(w) < 8.0:
					fx.scratch(prev, w, randf_range(0.2, 0.34), 0.7)
				_marks[id] = road_p
		else:
			_marks[id] = road_p
	for k in _marks.keys():
		if not seen.has(k):
			_marks.erase(k)


# ── cue ─────────────────────────────────────────────────

func _cue(id: String) -> void:
	print("DEATH_CUE %s t=%.3f" % [id, T])
	var joint := dummy.model.to_global(Vector3(-side * 2.6, 1.0, -3.0))    # 파손측 궤도 앞 접합부
	var road := stage.speed
	match id:
		"hit":
			main.hitstop(ENTRY_HOLD / rate)
			FX.flash(joint, Color.WHITE, 1.8, 0.14)
			fx.spark_burst(joint, 90, 16.0, road)
			_flash(Color(1, 0.95, 0.9), 0.35, 0.12)
			_impact(0.45, 0.6, joint)
			cam.add_shake(T, 0.1, 0.8, 0.22)
			cam.add_punch(T, -4.0)
			Audio.sfx("hit", 3.0, 0.7)
			Audio.sfx("clank", 0.0, 0.8)
			audio.play("snap", 0.0)
		"tread":
			var xf := Transform3D(dummy.model.global_basis, joint + Vector3(0, 0.2, 0.6))
			fx.tread_chunk(xf, Vector3(side * 1.0, 15.0, -9.0))
			for k in 10:
				fx.cleat(joint + Vector3(randf_range(-0.5, 0.5), randf_range(0, 0.8), randf_range(-0.5, 0.5)), Vector3(side * randf_range(2, 10), randf_range(6, 13), randf_range(-2, 16)))
			FX.enemy_explosion(joint, 1.2)
			fx.spark_fan(joint, 70, Vector3(side, 0, 0), road, 1.2)
			var tread: Node3D = dummy.tank.treads[_tread_i]
			BT.glow(tread, Vector3(1.9, 0.5, 0.3), Vector3(0, 1.0, -3.25), Color("ff6a20"), 2.6)
			Audio.sfx("launch", -1.0, 0.75)
			Audio.sfx("roll", -4.0, 0.7)
		"lurch":
			# 튀어 올랐던 차체가 모서리로 떨어지며 처음 도로를 찍는다
			for c in _contacts:
				fx.spark_fan(c[1], 14, Vector3(side, 0, 0), road, 1.0)
			cam.add_shake(T, 0.09, 0.8, 0.2)
			cam.add_punch(T, -2.5)
			_impact(0.3, 0.4, _com_w)
			Audio.sfx("land", 0.0, 0.6)
			Audio.sfx("clank", -2.0, 0.7)
		"unravel":
			# 끊긴 궤도 벨트가 풀려 채찍처럼 날아간다
			var p := dummy.model.to_global(Vector3(-side * 2.6, 1.2, randf_range(-2.0, 2.0)))
			fx.tread_chunk(Transform3D(dummy.model.global_basis, p), Vector3(randf_range(-8, 8), 11.0, randf_range(4, 14)))
			for k in 5:
				fx.cleat(p, Vector3(randf_range(-9, 9), randf_range(5, 11), randf_range(0, 16)))
			fx.spark_burst(p, 40, 12.0, road)
			FX.enemy_explosion(p, 0.8)
			cam.add_shake(T, 0.05, 0.5, 0.15)
			Audio.sfx("clank", -3.0, randf_range(0.6, 0.8))
		"groan":
			audio.play("groan", 0.0, 1.0)
			FX.enemy_explosion(dummy.model.to_global(Vector3(0.7 * side, 3.6, 2.95)), 0.9)
		"catch":
			# 모서리가 도로에 걸려 차체가 들린다
			for c in _contacts:
				fx.spark_fan(c[1], 30, Vector3(side, 0, 0), road, 1.5, 1.3)
			cam.add_shake(T, 0.12, 1.2, 0.25)
			cam.add_punch(T, 5.0)
			_impact(0.5, 0.5, _com_w)
			audio.play("groan", -2.0, 1.3)
			Audio.sfx("land", 2.0, 0.5)
			Audio.sfx("dash", 0.0, 0.5)
		"slowin":
			Audio.sfx("slowin", -2.0, 0.8)
		"tear":
			var tp := _turret.global_position if is_instance_valid(_turret) else _com_w
			fx.spark_burst(tp, 160, 18.0, road)
			FX.enemy_explosion(tp, 1.6)
			FX.flash(tp, Color.WHITE, 2.4, 0.12)
			_detach_turret(true)
			_flash(Color(1, 0.9, 0.7), 0.25, 0.1)
			_impact(0.4, 0.8, tp)
			cam.add_shake(T, 0.1, 1.0, 0.25)
			Audio.sfx("clank", 3.0, 0.5)
			audio.play("snap", 2.0, 0.7)
		"impact":
			for c in _contacts:
				fx.spark_fan(c[1], 26, Vector3(randf_range(-1, 1), 0, 0).normalized(), road, 1.8, 2.0)
			for k in 22:
				var q := _com_w + Vector3(randf_range(-5, 5), 0.4 - _com_w.y, randf_range(-4, 4))
				stage.puff(q, Color(0.36, 0.34, 0.42, 0.65), randf_range(2.8, 4.8), randf_range(0.8, 1.3), 0.55)
			FX.shockwave(Vector3(_com_w.x, 0.1, _com_w.z), Color("ffd9a0"), 8.0, 0.45, 0.14)
			FX.ring(Vector3(_com_w.x, 0.2, _com_w.z), 16.0, Pal.RING_ORANGE, 0.5)
			for k in 10:
				fx.chunk(_com_w + Vector3(randf_range(-2, 2), 0, randf_range(-3, 3)), Vector3(randf_range(-10, 10), randf_range(8, 15), randf_range(0, 16)), k < 3)
			_flash(Color(1.0, 0.92, 0.8), 0.4, 0.14)
			_impact(1.3, 1.2, _com_w)
			if flash_k > 0.5 and ImpactFrame.inst:
				ImpactFrame.inst.call("_play", _com_w, Vector3(side, 0, 0), [[34, 0.0, 1.3], [50, 1.0, 1.8]])
			cam.add_shake(T, 0.26, 2.0, 0.4)
			cam.add_punch(T, -8.0)
			light.light_energy = 6.0
			audio.play("thump", 3.0)
			Audio.sfx("boom", 4.0, 0.55)
			Audio.sfx("land", 2.0, 0.45)
			Audio.sfx("clank", 2.0, 0.5)
		"grind_hit":
			# 뒤집힌 채 돌다가 이음매에 걸려 한 번 더 크게 튄다
			for c in _contacts:
				fx.spark_fan(c[1], 20, Vector3(randf_range(-1, 1), 0, 0).normalized(), road, 1.3, 1.5)
			cam.add_shake(T, 0.08, 0.7, 0.18)
			_impact(0.35, 0.5, _com_w)
			Audio.sfx("clank", 0.0, randf_range(0.5, 0.7))
		"blast":
			var c := _com_w + Vector3(0, 0.5, 0)
			FX.fire_explosion(c, 3.2)
			FX.ring(Vector3(c.x, 0.25, c.z), 20.0, Pal.RING_ORANGE, 0.65)
			FX.shockwave(Vector3(c.x, 0.2, c.z), Color("ffd060"), 12.0, 0.55, 0.2)
			fx.spark_burst(c, 220, 24.0, road * 0.4)
			for k in (6 if low else 14):
				fx.chunk(c + Vector3(randf_range(-2, 2), randf_range(0, 1.5), randf_range(-2, 2)), Vector3(randf_range(-10, 10), randf_range(8, 20), randf_range(-2, 16)), k < 4)
			_flash(Color(1.0, 0.95, 0.75), 0.5, 0.22)
			_impact(1.0, 1.0, c)
			if flash_k > 0.5 and ImpactFrame.inst:
				ImpactFrame.inst.call("_play", c, Vector3.UP, [[34, 0.0, 1.0]])
			cam.add_shake(T, 0.2, 1.6, 0.45)
			cam.add_punch(T, 6.0)
			light.light_energy = 9.0
			Audio.sfx("boom", 6.0, 0.8)
			Audio.sfx("boom", 3.0, 0.55)
			Audio.sfx("launch", 0.0, 0.6)
		"blast2", "blast3":
			var e := dummy.model.to_global(Vector3(randf_range(-1.5, 1.5), 2.0, 3.0 if id == "blast2" else -3.0))
			FX.fire_explosion(e, 1.8)
			fx.spark_burst(e, 80, 16.0, road * 0.4)
			FX.shockwave(Vector3(e.x, 0.2, e.z), Color("ffb040"), 6.0, 0.4, 0.12)
			_flash(Color(1.0, 0.85, 0.6), 0.22, 0.12)
			_impact(0.5, 0.5, e)
			cam.add_shake(T, 0.12, 0.9, 0.3)
			Audio.sfx("boom", 3.0, 0.7 if id == "blast2" else 0.9)
		"debris":
			audio.play("debris", -2.0)
		"handoff":
			boss_cam.set("boss", null)
		"cam_return":
			_hand_camera()


func _detach_turret(fly: bool) -> void:
	if _turret_gone or not is_instance_valid(_turret):
		return
	_turret_gone = true
	var gt := _turret.global_transform
	_turret.get_parent().remove_child(_turret)
	stage.add_child(_turret)
	_turret.global_transform = gt
	if fly:
		# 뒤집히는 방향으로 크게 내던져진다 (옆 공간이 좁으면 도로 안쪽으로)
		# 카메라(전복측 앞쪽) 반대로 날려 렌즈를 가리지 않게 한다
		var dir := Vector3(-side, 0, -0.5).normalized()
		if absf(_com_w.x + dir.x * 8.0) > 9.0:
			dir.x = -dir.x
		stage.drift(_turret, dir * 7.0 + Vector3(0, 15.0, 4.0), Vector3(randf_range(-1, 1), 0.4, randf_range(-1, 1)).normalized() * 7.0, true, 5.0)
	else:
		_turret.queue_free()


# ── 도로 · 잔해 ─────────────────────────────────────────

func _update_stage() -> void:
	if T < 0.35:
		# 급접근 순간 화면이 앞으로 쏠리는 속도감
		stage.speed = v0 * (1.0 + 0.18 * sin(PI * clampf((T - ENTRY_HOLD) / 0.26, 0.0, 1.0)))
	elif T < BLAST:
		stage.speed = v0 * lerpf(1.0, 0.88, smoothstep(0.35, BLAST, T))
	else:
		var u := clampf((T - BLAST) / 1.5, 0.0, 1.0)
		stage.speed = lerpf(v0 * 0.88, 10.0, 1.0 - pow(1.0 - u, 2.0))
	var sfx_i := 1.9
	if T < ENTRY_HOLD:
		sfx_i = 1.2
	elif warp < 0.9:
		sfx_i = 0.7
	elif T >= BLAST:
		sfx_i = lerpf(0.9, 0.3, smoothstep(BLAST, HANDOFF, T))
	speed_fx.set("target_intensity", sfx_i)


func _update_wreck(dT: float) -> void:
	if not is_instance_valid(dummy):
		return
	if T >= HANDOFF:
		wreck_v = move_toward(wreck_v, stage.speed, 22.0 * dT)
		wreck_z += wreck_v * dT
		if not active:
			_apply_body()
		if dummy.visual.visible and dummy.global_position.z + wreck_z > Stage.NEAR_Z + 8.0:
			dummy.visual.visible = false
			dummy.shadow.visible = false
	if not dummy.visual.visible:
		return
	# 불타는 잔해와 검은 연기 기둥 (포탑이 뜯긴 뒤부터)
	if T >= TEAR:
		_fire_cd -= dT
		if _fire_cd <= 0.0:
			_fire_cd = 0.05 if low else 0.03
			var rel := 0.25 if T < HANDOFF else 0.85
			var top := _com_w + Vector3(0, 2.0, 0)
			stage.puff(top + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-2.5, 2.5)), Color(0.13, 0.11, 0.14, 0.78), randf_range(3.2, 4.8), 1.5, rel)
			for k in 2:
				var fp := dummy.model.to_global(Vector3(randf_range(-1.8, 1.8), randf_range(1.2, 3.2), randf_range(-2.8, 2.8)))
				stage.puff(fp, Color(1.0, 0.48 + randf() * 0.2, 0.12, 0.9), randf_range(1.8, 3.0), 0.45, rel * 0.9, true)
				if randf() < 0.2:
					fx.spark_burst(fp, 4, 7.0, stage.speed * 0.3)
	# 날아가는 포탑이 불꼬리를 끈다
	_trail_cd -= dT
	if _trail_cd <= 0.0 and is_instance_valid(_turret) and _turret_gone and T < TEAR + 1.8:
		_trail_cd = 0.025
		var tp := _turret.global_position + Vector3(0, 0.8, 0)
		stage.puff(tp, Color(1.0, 0.55, 0.2, 0.9), 1.8, 0.3, 0.2, true)
		stage.puff(tp, Color(0.1, 0.08, 0.1, 0.6), 2.0, 0.6, 0.3)
		fx.spark(tp, Vector3(randf_range(-3, 3), randf_range(0, 4), randf_range(-3, 3)), 0.3, 0.8, 0.5)


# ── 카메라 ──────────────────────────────────────────────

func _cam_center() -> Vector3:
	var tb := _tb(T)
	return B0 + Vector3(side * _slide(tb), 0, _zoff(tb))


## [눈, 시선, FOV]
func _pose(id: String) -> Array:
	var C := _cam_center()
	var H := _com_w - Vector3(0, 0, wreck_z)
	var L := Vector3(side, 0, 0)
	match id:
		"entry":
			return [entry_xf.origin, entry_xf.origin - entry_xf.basis.z * 20.0, entry_fov]
		"hit":
			return [C + L * 9.0 + Vector3(0, 5.0, 10.5), dummy.model.to_global(Vector3(-side * 2.6, 1.0, -2.6)), 48.0]
		"chase_a":
			return [C + L * 10.0 + Vector3(0, 3.0, 10.5), H - Vector3(0, 0.6, 0), 52.0]
		"chase_b":
			# 스핀하는 차체를 따라 옆으로 크게 돌아 들어간다
			return [C + Basis(Vector3.UP, -side * deg_to_rad(32.0)) * (L * 10.5 + Vector3(0, 2.6, 11.0)), H - Vector3(0, 0.4, 0), 52.0]
		"flip":
			# 낮게 깔려 머리 위로 넘어가는 차체를 올려다본다
			return [C + L * 10.5 + Vector3(0, 1.3, 9.5), H + Vector3(0, 1.4, 0), 60.0]
		"flip_b":
			return [C + L * 9.5 + Vector3(0, 1.1, 8.5), H + Vector3(0, 0.8, 0), 62.0]
		"grind":
			# 불꽃이 쏟아져 오는 쪽(+Z)에서 낮게 받는다
			return [C + L * 5.0 + Vector3(0, 1.7, 13.0), H - Vector3(0, 0.5, 0), 58.0]
		"grind_b":
			return [C + L * 4.0 + Vector3(0, 2.2, 15.5), H - Vector3(0, 0.3, 0), 55.0]
		"blast":
			return [C + L * 8.0 + Vector3(0, 13.0, 22.0), C + Vector3(0, 2.5, 0), 58.0]
		"blast_b":
			return [C + L * 9.0 + Vector3(0, 14.0, 24.5), C + Vector3(0, 2.0, 1.0), 57.0]
		_:
			var xf := boss_cam.global_transform
			return [xf.origin, xf.origin - xf.basis.z * 20.0, boss_cam.fov]


func _update_camera() -> void:
	if _cam_handed:
		return
	var shot: Array = SHOTS[SHOTS.size() - 1]
	for s in SHOTS:
		if T < float(s[1]):
			shot = s
			break
	var a := _pose(shot[2])
	var b := _pose(shot[3])
	var u := clampf((T - float(shot[0])) / maxf(float(shot[1]) - float(shot[0]), 0.001), 0.0, 1.0)
	var e := _ease(shot[4], u)
	var eye: Vector3 = (a[0] as Vector3).lerp(b[0], e)
	var look: Vector3 = (a[1] as Vector3).lerp(b[1], e)
	var fv: float = lerpf(a[2], b[2], e)
	# 더치 앵글: 스핀 중 기울고, 전복 때 크게 따라 기울었다가, 마찰 때 반대로
	var roll := -side * 6.0 * smoothstep(0.3, 0.8, T) * (1.0 - smoothstep(1.4, 1.7, T))
	roll += -side * 12.0 * smoothstep(1.6, 2.2, T) * (1.0 - smoothstep(2.3, 2.6, T))
	roll += side * 6.0 * smoothstep(2.4, 2.8, T) * (1.0 - smoothstep(3.3, 3.6, T))
	cam.frame(T, eye, look, fv, roll)


func _hand_camera() -> void:
	if _cam_handed:
		return
	_cam_handed = true
	boss_cam.current = true
	main.hud.visible = true


# ── 화면 효과 ───────────────────────────────────────────

func _flash(c: Color, a: float, decay: float) -> void:
	_flashes.append([T, c, a * flash_k, decay])


func _impact(blur: float, aberr: float, world: Vector3) -> void:
	_impacts.append([T, blur, aberr, world])


func _update_overlay() -> void:
	var bars := 1.0
	if T < 0.16:
		bars = smoothstep(0.0, 0.16, T)
	elif T > 4.1:
		bars = 1.0 - smoothstep(4.1, 4.7, T)
	overlay.bars = bars
	overlay.vignette = (0.35 + (0.2 if warp < 0.9 else 0.0)) * bars
	# 달리는 동안 가장자리 방사 블러와 색수차를 계속 깐다
	var base := 0.0
	if T > ENTRY_HOLD and T < BLAST:
		base = 0.2 if (T > IMPACT or T < FLIP) else 0.1
	var bl := base
	var ab := base * 1.2
	overlay.aim(cam if cam.current else boss_cam, _com_w)
	for im in _impacts:
		var e: float = T - im[0]
		if e < 0.0 or e > 0.5:
			continue
		var k := exp(-e * 10.0)
		if k * float(im[1]) > bl:
			bl = k * float(im[1])
			overlay.aim(cam if cam.current else boss_cam, im[3])
		ab = maxf(ab, k * float(im[2]))
	if T > ENTRY_HOLD and T < 0.3:
		bl = maxf(bl, 0.6 * sin(PI * (T - ENTRY_HOLD) / 0.21))
	overlay.blur = bl * (0.3 + 0.7 * shake_k)
	overlay.aberr = ab
	var fl := Color(1, 1, 1, 0)
	for f in _flashes:
		var e: float = T - f[0]
		if e < 0.0:
			continue
		var a: float = float(f[2]) * exp(-e / maxf(float(f[3]), 0.01) * 2.3)
		if a > fl.a:
			fl = Color(f[1].r, f[1].g, f[1].b, a)
	overlay.flash = fl


func _finish(reason: String) -> void:
	if not active:
		return
	active = false
	done = true
	warp = 1.0
	main.set_slowmo(rate)
	_hand_camera()
	overlay.bars = 0.0
	overlay.blur = 0.0
	overlay.aberr = 0.0
	overlay.vignette = 0.0
	overlay.flash = Color(1, 1, 1, 0)
	audio.scrape_vol = 0.0
	light.light_energy = 0.0
	if is_instance_valid(cam):
		cam.queue_free()
	print("DEATH_FINISH variant=B+ reason=%s sparks=%d" % [reason, fx.spark_count()])
	finished.emit(reason)


## 테스트 씬 표시용: 현재 컷
func cut_info() -> Array:
	var c: Array = CUTS[0]
	for k in CUTS:
		if T >= float(k[0]):
			c = k
	return c


# ── 곡선 ────────────────────────────────────────────────

func _ease(kind: String, u: float) -> float:
	match kind:
		"hold":
			return 0.0
		"whip":
			return 1.0 - pow(1.0 - u, 4.0)
		"out":
			return 1.0 - pow(1.0 - u, 3.0)
		"sine":
			return 0.5 - 0.5 * cos(PI * u)
		_:
			return 4.0 * u * u * u if u < 0.5 else 1.0 - pow(-2.0 * u + 2.0, 3.0) * 0.5
