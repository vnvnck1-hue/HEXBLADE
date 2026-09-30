class_name DangerFX
extends Node
## 연출 전용: 붉은 섬광 — "막을 수 없다, 피하라" 신호와 퍼펙트 회피 연출.
## 금빛 섬광(ParryFX.warn "ranged"/"melee")은 대시로 패링할 수 있는 공격이고,
## 붉은 섬광(여기)은 패링이 되지 않아 대시 무적으로 피해야 하는 강한 공격이다.
## - warn(): 공격이 닿기 약 0.4초 전(패링 공격과 같은 리듬) 공격 지점에 붉은 십자 별빛 + 한 박자 뒤 두 번째 맥동.
##   색만으로 구분하지 않도록 두 번 맥동하고 소리도 낮게 울린다.
## - evaded(): 붉은 공격의 판정 범위 안에서 대시 무적으로 피한 순간. 아주 짧은 슬로우(젠레스 존 제로의 Vital View 대응) +
##   청백 잔상 · 별 섬광 · 충격파. 보상(반격 등)은 주지 않는다. 판정 · 피해는 바꾸지 않는다.
## 시간 연출은 연출용 실제 시간(Parry.now_ms)으로 진행한다.

static var inst: DangerFX
static var _last_evade := -100000

const RED := Color(1.0, 0.08, 0.12)
const HOT := Color(1.0, 0.78, 0.74)
const EVADE := Color(0.62, 0.95, 1.0)
const PULSE_GAP := 0.09       # 두 번째 맥동까지 (게임 초)
# 퍼펙트 회피 시간 연출 (실제 초)
const SLOW := 0.25
const SLOW_HOLD := 0.12
const SLOW_END := 0.3
const EVADE_COOLDOWN := 600   # ms: 지속 빔이 여러 틱에 걸쳐 불러도 한 번만

var _seq_start := -1


func _exit_tree() -> void:
	if inst == self:
		inst = null


static func _ensure() -> DangerFX:
	if inst == null and Main.inst:
		var d := DangerFX.new()
		d.process_mode = Node.PROCESS_MODE_ALWAYS
		Main.inst.add_child(d)
		inst = d
	return inst


## 붉은 섬광 알림: 준비동작 끝, 공격이 닿기 약 0.4초 전에 부른다
static func warn(pos: Vector3, parent: Node3D = null) -> void:
	ParryFX.warn(pos, "danger", parent)
	print("DANGER_WARN t=%.2f" % (Main.inst.time if Main.inst else 0.0))
	var host: Node = parent if parent else FX.root
	host.get_tree().create_timer(PULSE_GAP, false).timeout.connect(func():
		ParryFX.glint(pos, 3.2, RED, 0.18)
		FX.flash(pos, HOT, 0.9, 0.05))


## 붉은 공격 판정 범위 안에 있는데 피해가 들어가지 않은 순간 부른다. 대시 중일 때만 퍼펙트 회피로 친다.
static func evaded(p: Player, at: Vector3) -> void:
	if p == null or not p.alive or p.dash_t <= 0.0:
		return
	var now := Parry.now_ms()
	if now - _last_evade < EVADE_COOLDOWN:
		return
	_last_evade = now
	var d := _ensure()
	if d == null:
		return
	var chest := p.global_position + Vector3(0, 0.95, 0)
	# 스쳐 간 자리에 붉은 불티, 몸에는 청백 잔상과 별 섬광
	ParryFX.glint(chest, 2.8, EVADE, 0.22)
	ParryFX.glint(chest, 1.4, Color.WHITE, 0.12)
	FX.afterimage(p.visual, Color(EVADE, 0.6), 0.45)
	FX.shockwave(p.global_position, EVADE, 3.2, 0.3, 0.06)
	FX.shockwave(p.global_position, RED, 2.0, 0.2, 0.04)
	var side := at - chest
	side.y = 0
	FX.sparks(chest + side.limit_length(0.6), 14, [Color.WHITE, HOT, RED], 9.0, 0.3, -6.0, 0.05)
	var main := Main.inst
	main.camera.fov_punch(-4.0)
	main.shake(0.15)
	if main.hud:
		main.hud.screen_flash(EVADE, 0.12)
	var snd := Sfx.play("slowin", 0.0, -3.0)
	if snd:
		snd.pitch_scale = 1.6
	print("PERFECT_EVADE t=%.2f" % main.time)
	d._seq_start = now
	main.set_slowmo(SLOW)


func _process(_dt: float) -> void:
	if _seq_start < 0:
		return
	var main := Main.inst
	if main == null or main.player.ult_aiming or main.state == Main.State.LOSE:
		_seq_start = -1
		return
	# 패링 · 쇼타임이 시간을 넘겨받으면 손을 뗀다
	if (Parry.inst and Parry.inst.sequence_active()) or Showtime.active():
		_seq_start = -1
		return
	var e := (Parry.now_ms() - _seq_start) * 0.001
	if e >= SLOW_END:
		_seq_start = -1
		main.set_slowmo(1.0)
		return
	var s := SLOW
	if e > SLOW_HOLD:
		var k := smoothstep(SLOW_HOLD, SLOW_END, e)
		s = lerpf(SLOW, 1.0, k * k)
	main.set_slowmo(s)
