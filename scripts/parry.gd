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
## 모든 패링 공격은 과장된 준비동작 → 십자 별빛 알림 → 알림 후 정확히 TRAVEL 초 뒤에 닿는다 (타이밍이 매번 같다).
## 성공 연출은 전투 속도를 끊지 않게 짧다: 2프레임 정지 + 몇 프레임 슬로우, 적당한 줌인, 글자 없음.
## 시간 연출(정지 → 슬로우 → 복귀)은 실제 시간(ms)으로 진행한다.

static var inst: Parry

const EARLY := 0.26           # 닿기 전 이만큼(게임 초)부터 패링된다
const LATE := 0.07            # 닿은 뒤 이만큼까지 봐준다 (입력 지연 보정)
const EARLY_LOCK := 0.4       # 창이 열리기 전 이만큼 안에 누르면 헛패링: 잠시 패링 불가
const LOCKOUT := 0.32
const TRAVEL := 0.5           # 알림이 뜬 뒤 공격이 플레이어에게 닿기까지 (게임 초). 모든 패링 공격 공통
# 시간 연출 (실제 초): 단 몇 프레임
const FREEZE := 0.034         # 2프레임 정지
const SLOW := 0.3
const SLOW_HOLD := 0.05       # 슬로우 유지 (약 3프레임)
const SLOW_END := 0.11        # 이때 정상 속도로 완전히 복귀

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
	ParryFX.burst(contact, dir, kind)
	if ParryFX.inst:
		ParryFX.inst.play(contact, kind)
	if ImpactFrame.inst:
		ImpactFrame.inst.parry(contact, dir)
	var main := Main.inst
	main.camera.parry_cine(p, src, foe)
	main.shake(0.45)
	main.kick(-dir * 0.5)
	Sfx.play("parry", 0.03, 3.0)
	print("PARRY %s t=%.2f n=%d f=%d" % [kind, main.time, count, main.capture_frame])
	# 시간: 2프레임 멈췄다가 몇 프레임 슬로우, 곧바로 정상 속도
	_seq_start = Parry.now_ms()
	main.set_slowmo(SLOW)
	main.hitstop(FREEZE)


func sequence_active() -> bool:
	return _seq_start >= 0


func _process(_dt: float) -> void:
	if _seq_start < 0:
		return
	var main := Main.inst
	var e := (Parry.now_ms() - _seq_start) * 0.001
	if main.player.ult_busy() or main.state == Main.State.LOSE:
		# 궁극기 락온이 시간을 넘겨받는다
		_seq_start = -1
		return
	if e >= SLOW_END:
		_seq_start = -1
		main.set_slowmo(1.0)
		return
	var s := SLOW
	if e > SLOW_HOLD:
		var k := smoothstep(SLOW_HOLD, SLOW_END, e)
		s = lerpf(SLOW, 1.0, k * k)
	main.set_slowmo(s)
