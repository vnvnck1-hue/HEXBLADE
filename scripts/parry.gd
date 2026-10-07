class_name Parry
extends Node3D
## 패링 판정과 성공 연출의 지휘.
## 적의 패링 공격(금빛 예고)이 플레이어에게 닿기 직전 EARLY ~ 닿은 뒤 LATE 초 안에 대시를 누르면 패링한다.
## - 원거리(패링 탄): 투사체를 쏜 적에게 되받아친다
## - 근접(돌진 베기): 공격한 적을 잠시 경직시킨다
## 패링 공격은 아래 함수를 가진 객체로 등록한다 (덕 타이핑):
##   parry_eta() -> float        이대로 두면 플레이어에게 닿기까지 남은 게임 시간 (해당 없으면 INF)
##   parry_kind() -> String      "ranged" / "melee"
##   parry_point() -> Vector3    공격이 부딪히는 지점 (연출 중심)
##   parry_source() -> Node3D    공격한 적 (카메라 구도용)
##   parry_hit(player)           패링당했을 때의 결과 (반사 / 경직)
##   parry_window_open()         판정 창이 열리는 순간의 신호 연출
## 모든 패링 공격은 과장된 준비동작 → 십자 별빛 알림 → 실제로 닿기 직전(EARLY 초 전부터)에만 판정 창이 열린다.
## 별빛 뒤 정해진 시간에 닿는 규칙은 없다: 근접 공격은 다가와 실제로 휘두르는 순간, 탄은 실제로 날아와 닿기 직전에 패링된다
## (parry_eta 는 언제나 '지금부터 실제로 맞기까지' 남은 시간이어야 한다).
## 성공 연출은 전투 속도를 끊지 않게 짧다: 2프레임 정지 + 몇 프레임 슬로우, 적당한 줌인, 글자 없음.
## 시간 연출(정지 → 슬로우 → 복귀)은 실제 시간(ms)으로 진행한다.

static var inst: Parry

const EARLY := 0.26           # 닿기 전 이만큼(게임 초)부터 패링된다
const LATE := 0.07            # 닿은 뒤 이만큼까지 봐준다 (입력 지연 보정)
const EARLY_LOCK := 0.4       # 창이 열리기 전 이만큼 안에 누르면 헛패링: 잠시 패링 불가
const LOCKOUT := 0.32
const TRAVEL := 0.5           # 위험(붉은) 섬광을 맞기 몇 초 전에 띄울지 (보스 돌진 등 패링 불가 공격의 예고용). 패링 판정과는 무관
# 시간 연출 (실제 초): 단 몇 프레임
const FREEZE := 0.034         # 2프레임 정지
const SLOW := 0.3
const SLOW_HOLD := 0.05       # 슬로우 유지 (약 3프레임)
const SLOW_END := 0.11        # 이때 정상 속도로 완전히 복귀
# 히트스톱 프리셋 (실제 초). light = 연속 패링의 중간 타(parry_feel() == "light"): 멈추기만 하고 슬로우 없이 곧바로 이어진다,
# heavy = 마지막 타 · 단발: 멈춘 뒤 몇 프레임 슬로우. scale = 멈춘 동안 시간 배율 (0.002 = 사실상 완전 정지).
# stutter = 한 번 멈췄다 2프레임 움직이고 이 길이만큼 다시 멈춤, shiver = 멈춘 동안 화면이 이만큼(px 비율) 부들부들 떨림.
# 허수아비 씬(홀 · 보스방) P / Shift+P 로 바꾼다 (실행 인자 --parrystop=id). 씬을 다시 불러도 유지. 기본 = HEAVY 묵직하게 길게.
const STOP_PRESETS := [
	{"id": "hard", "ko": "HARD · 딱 멈춤", "light": 0.11, "heavy": 0.16, "scale": 0.002, "stutter": 0.0, "shiver": 0.0},
	{"id": "shiver", "ko": "SHIVER · 멈춘 채 떨림", "light": 0.12, "heavy": 0.2, "scale": 0.002, "stutter": 0.0, "shiver": 1.0},
	{"id": "crunch", "ko": "CRUNCH · 두 번 끊어 멈춤", "light": 0.08, "heavy": 0.11, "scale": 0.002, "stutter": 0.07, "shiver": 0.4},
	{"id": "heavy", "ko": "HEAVY · 묵직하게 길게", "light": 0.17, "heavy": 0.28, "scale": 0.002, "stutter": 0.0, "shiver": 0.6},
	{"id": "soft", "ko": "SOFT · 예전 (가볍게)", "light": 0.07, "heavy": 0.085, "scale": 0.06, "stutter": 0.0, "shiver": 0.0},
]
static var stop_i := 3          # 기본 HEAVY
static var _stop_args_read := false

var threats: Array = []
var lock_t := 0.0
var count := 0
var _opened := {}
var _seq_start := -1


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _ready() -> void:
	inst = self


## 연출용 실제 시간(ms). 프레임 캡처(고정 fps) 중에는 프레임 수로 센다.
static func now_ms() -> int:
	if Main.inst and Main.inst.capture_mode:
		return int(Engine.get_process_frames() * 1000.0 / 60.0)
	return Time.get_ticks_msec()


func register(t: Object) -> void:
	if not threats.has(t):
		threats.append(t)


func unregister(t: Object) -> void:
	threats.erase(t)
	_opened.erase(t)


## 지금 대시를 누르면 패링되는 공격 (없으면 null)
func best_threat() -> Object:
	if lock_t > 0.0:
		return null
	var best: Object = null
	var be := INF
	for t in threats:
		if not is_instance_valid(t):
			continue
		var e: float = t.parry_eta()
		if e >= -LATE and e <= EARLY and e < be:
			be = e
			best = t
	return best


## 대시 입력 때 Player 가 부른다. 패링했으면 true (이 경우 대시 대신 반격 동작이 나간다)
func try_parry(p: Player) -> bool:
	var t := best_threat()
	if t == null:
		if lock_t <= 0.0:
			for th in threats:
				if is_instance_valid(th):
					var e: float = th.parry_eta()
					if e > EARLY and e <= EARLY + EARLY_LOCK:
						# 너무 일찍 눌렀다: 잠깐 패링을 막아 연타를 막는다
						lock_t = LOCKOUT
						break
		return false
	_success(t, p)
	return true


func _physics_process(dt: float) -> void:
	lock_t = maxf(0.0, lock_t - dt)
	for t in threats.duplicate():
		if not is_instance_valid(t):
			threats.erase(t)
			continue
		var e: float = t.parry_eta()
		# 판정 창이 열리는 순간: 적 쪽에서 섬광 신호 (한 번만)
		if e <= EARLY and e >= -LATE and not _opened.has(t):
			_opened[t] = true
			t.parry_window_open()


# ── 성공 ────────────────────────────────────────────────

func _success(t: Object, p: Player) -> void:
	var kind: String = t.parry_kind()
	var heavy: bool = not (t.has_method("parry_feel") and t.parry_feel() == "light")
	var fk := 1.0 if heavy else 0.6
	var at: Vector3 = t.parry_point()
	var src: Node3D = t.parry_source()
	unregister(t)
	count += 1
	var foe := src.global_position if is_instance_valid(src) else at
	var chest := p.global_position + Vector3(0, 0.95, 0)
	var dir := foe - p.global_position
	dir.y = 0
	dir = dir.normalized() if dir.length() > 0.01 else p.aim_dir
	# 부딪히는 지점: 플레이어 가슴 앞
	var contact := chest + dir * 0.45
	if kind == "ranged":
		contact = Vector3(at.x, Main.gy(at) + 0.95, at.z)
		if contact.distance_to(chest) > 1.4:
			contact = chest + dir * 1.0
	p.parry_counter(foe, kind)
	t.parry_hit(p)
	# 연출 (docs/parry-camera-screen-effects.md): 히트 스파크 · 임팩트 버스트 · 임팩트 프레임 · 줌 블러 · 쇼크웨이브 왜곡 ·
	# 펀치 인 + 공격 방향 카메라 킥 + 셰이크 · 히트스톱. 중간 타는 작게, 마지막 타(단발 포함)는 크게 + 줌인 · 짧은 슬로우
	ParryFX.burst(contact, dir, kind, fk)
	if ParryFX.inst:
		ParryFX.inst.play(contact, kind, fk)
	if ImpactFrame.inst:
		ImpactFrame.inst.parry(contact, dir, not heavy)
	var main := Main.inst
	main.camera.parry_impact(-dir, 1.25 if heavy else 0.75)
	if heavy:
		main.camera.parry_cine(p, src, foe)
	var s := Sfx.play("parry", 0.03, 3.0 if heavy else 1.0)
	if s and not heavy:
		s.pitch_scale *= 1.08
	print("PARRY %s t=%.2f n=%d f=%d %s" % [kind, main.time, count, main.capture_frame, "heavy" if heavy else "light"])
	# 시간: 히트스톱으로 멈췄다가 — 중간 타는 곧바로 정상 속도, 마지막 타는 몇 프레임 슬로우를 거쳐 복귀
	var pr: Dictionary = stop_preset()
	var stop: float = pr.heavy if heavy else pr.light
	var total := stop
	_stutter_at = -1
	if float(pr.stutter) > 0.0:
		# 멈춤 → 2프레임 움직임 → 다시 멈춤 (끊어 씹히는 느낌)
		_stutter_at = Time.get_ticks_msec() + int((stop + 0.034) * 1000.0)
		_stutter_len = float(pr.stutter) * (1.3 if heavy else 1.0)
		total += 0.034 + _stutter_len
	_shiver_end = Time.get_ticks_msec() + int(total * 1000.0) if float(pr.shiver) > 0.0 else -1
	_shiver_k = float(pr.shiver) * (1.4 if heavy else 1.0)
	if heavy:
		_seq_start = Parry.now_ms() + int(total * 1000.0)
		main.set_slowmo(SLOW)
	main.hitstop(stop, float(pr.scale))


var _stutter_at := -1
var _stutter_len := 0.0
var _shiver_end := -1
var _shiver_k := 0.0


static func stop_preset() -> Dictionary:
	if not _stop_args_read:
		_stop_args_read = true
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--parrystop="):
				use_stop(a.substr(12))
	return STOP_PRESETS[stop_i]


static func use_stop(id: String) -> void:
	for i in STOP_PRESETS.size():
		if STOP_PRESETS[i].id == id:
			stop_i = i


## 다음(또는 이전) 프리셋으로. 바뀐 프리셋을 돌려준다
static func cycle_stop(back := false) -> Dictionary:
	stop_preset()
	stop_i = posmod(stop_i + (-1 if back else 1), STOP_PRESETS.size())
	return STOP_PRESETS[stop_i]


func sequence_active() -> bool:
	return _seq_start >= 0


func _process(_dt: float) -> void:
	var now := Time.get_ticks_msec()
	if _stutter_at >= 0 and now >= _stutter_at:
		_stutter_at = -1
		Main.inst.hitstop(_stutter_len, float(stop_preset().scale))
	if _shiver_end >= 0:
		var cam := get_viewport().get_camera_3d()
		if now < _shiver_end and cam:
			# 멈춘 화면이 부들부들 (게임 시간이 멈춰도 실제 시간으로 흔든다)
			var a := 0.035 * _shiver_k
			cam.h_offset = randf_range(-a, a)
			cam.v_offset = randf_range(-a, a)
		else:
			_shiver_end = -1
			if cam:
				cam.h_offset = 0.0
				cam.v_offset = 0.0
	if _seq_start < 0:
		return
	var main := Main.inst
	var e := (Parry.now_ms() - _seq_start) * 0.001
	if main.player.ult_busy() or main.state == Main.State.LOSE:
		# 궁극기 락온이 시간을 넘겨받는다
		_seq_start = -1
		return
	if e < 0.0:
		return                  # 아직 히트스톱 중
	if e >= SLOW_END:
		_seq_start = -1
		main.set_slowmo(1.0)
		return
	var s := SLOW
	if e > SLOW_HOLD:
		var k := smoothstep(SLOW_HOLD, SLOW_END, e)
		s = lerpf(SLOW, 1.0, k * k)
	main.set_slowmo(s)
