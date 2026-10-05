class_name CockpitCutin
extends CanvasLayer
## 드론 합체 조종석 컷인 (docs/drone-cockpit-cutin-claude-handoff.md). Q 즉시 합체(_begin_recall(fast=true))에서 begin,
## 실제로 등에 붙는 순간(_gattai_impact) notify_dock. 진입 → 정착 → [합체 완료] 잠금 효과 · 얼굴 유지 → 퇴장.
## 시간은 실제 단조 시계(Time.get_ticks_usec) — 히트스탑(time_scale 0.06)에도 얼굴은 제 속도로 움직인다.
## 원화의 가슴은 cutin_jiggle.gdshader 의 UV 모핑으로 흔든다: 패널이 움직이는 가속도의 반대로 끌리는 스프링(관성) +
## 합체 충격 때 패널이 쿵 내려앉는 충격. 좌우 두 스프링은 진동수를 조금 달리해 같이 흔들리지 않게 한다.

const PLATE := preload("res://assets/vfx/drone_cutin/cockpit_plate_clipped.png")
const FRAME := preload("res://assets/vfx/drone_cutin/panel_frame.svg")
const GLOW := preload("res://assets/vfx/drone_cutin/panel_glow.svg")
const RING := preload("res://assets/vfx/drone_cutin/lock_ring.svg")
const FLASH := preload("res://assets/vfx/drone_cutin/dock_flash.svg")
const STREAK := preload("res://assets/vfx/drone_cutin/sync_streak.svg")
const SHARD := preload("res://assets/vfx/drone_cutin/triangle_shard.svg")
const TICKS := preload("res://assets/vfx/drone_cutin/bashful_ticks.svg")
const JIGGLE := preload("res://scripts/drone/cutin_jiggle.gdshader")

const LAYER := 9                 ## HUD(10) 아래 · 게임 화면 위
const ENTER := 0.16
const SETTLE := 0.06
const HOLD := 0.36               ## 합체 뒤 얼굴 유지 (문서 제안 0.27 → 흔들림이 두세 번 보이게 조금 늘림)
const EXIT := 0.18
const WAIT_MAX := 1.2            ## 이 안에 합체 완료가 안 오면 접는다
const FLASH_T := 0.09
const RING_T := 0.26
const SHARDS := 7
const FACE_UV := Vector2(0.48, 0.35)
const EDGE_UV := Vector2(0.88, 0.30)
const ART := 1024.0

## 가슴 스프링 (원화 1024px 단위). 진동수 Hz · 감쇠비 · 관성 배율 · 최대 변위
const JIG_HZ := Vector2(4.6, 5.8)       ## 가로, 세로
const JIG_ZETA := 0.13
const JIG_GAIN := Vector2(0.26, 0.42)   ## 가로는 약하게 (옆으로 크게 쏠리면 어색하다)
const JIG_MAX := 30.0
const JIG_R_DETUNE := 1.08              ## 오른쪽은 조금 빠르게
const JIG_LAG := 0.035                  ## 오른쪽은 조금 늦게 반응 (초)

enum Ph { ENTER, WAIT, HOLD, EXIT, DONE }

var drone: Node                  ## PartnerDrone (합체 전 RECALL 이 끊기면 접는다)
var main: Main
var ph := Ph.ENTER
var t := 0.0                     ## begin 부터 실제 시간
var dock_t := -1.0               ## 합체 완료 시각 (t 기준)
var exit_t := -1.0
var root: Control
var panel: Control
var plate: TextureRect
var mat: ShaderMaterial
var glow: TextureRect
var frame: TextureRect
var ticks: TextureRect
var ring: Sprite2D
var flash: Sprite2D
var streaks: Array[Sprite2D] = []
var shards: Array = []           ## [Sprite2D, 방향, 거리, 회전 속도]
var side := 600.0
var dock_screen := Vector2.ZERO
var dock_ok := false
var rng := RandomNumberGenerator.new()
var _last_us := 0
## 패널 움직임 (화면 px) → 가속도 → 가슴 스프링
var _pan := Vector2.ZERO         ## 패널 기준 위치에서의 이동 (진입/퇴장 + 쿵)
var _pan_prev := Vector2.ZERO
var _pan_v := Vector2.ZERO
var _pan_init := false
var _jolt := Vector2.ZERO        ## 합체 충격으로 패널이 내려앉았다 돌아오는 스프링
var _jolt_v := Vector2.ZERO
var _rot := 0.0
var _rot_v := 0.0
var jig := [Vector2.ZERO, Vector2.ZERO]      ## 변위 (원화 px) 왼쪽, 오른쪽
var jig_v := [Vector2.ZERO, Vector2.ZERO]
var jig_peak := 0.0                          ## 확인용: 가장 크게 흔들린 변위
var _acc_hist: Array = []                    ## 오른쪽 지연용 [시각, 가속도]
static var fixed_dt := 0.0                   ## 캡처·테스트용: 0 보다 크면 실제 시계 대신 한 프레임에 이만큼 흐른다


static func begin(scene: Node, owner_drone: Node) -> CockpitCutin:
	var c := CockpitCutin.new()
	c.drone = owner_drone
	c.main = scene as Main
	scene.add_child(c)
	return c


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	panel = Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	glow = _rect(GLOW)
	plate = _rect(PLATE)
	mat = ShaderMaterial.new()
	mat.shader = JIGGLE
	plate.material = mat
	frame = _rect(FRAME)
	ticks = TextureRect.new()
	ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ticks.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ticks.stretch_mode = TextureRect.STRETCH_SCALE
	ticks.texture = TICKS
	ticks.modulate.a = 0.0
	panel.add_child(ticks)
	for i in 3:
		var s := _sprite(STREAK)
		streaks.append(s)
	ring = _sprite(RING)
	flash = _sprite(FLASH)
	for i in SHARDS:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / SHARDS
		shards.append([_sprite(SHARD), Vector2(cos(a), sin(a)), rng.randf_range(0.55, 1.0), rng.randf_range(-9.0, 9.0)])
	_last_us = Time.get_ticks_usec()
	_layout()
	_apply(0.0)


func _rect(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture = tex
	panel.add_child(r)
	return r


func _sprite(tex: Texture2D) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.visible = false
	root.add_child(s)
	return s


## 합체 완료 (드론이 등에 붙은 실제 순간)
func notify_dock() -> void:
	if ph == Ph.DONE or ph == Ph.EXIT or dock_t >= 0.0:
		return
	dock_t = t
	ph = Ph.HOLD
	# 패널이 쿵 내려앉았다 튀어 오른다 + 살짝 기운다 → 가슴이 관성으로 크게 출렁
	_jolt_v = Vector2(-90.0, 1500.0) * (side / 800.0)
	_rot_v = -1.6
	for i in 2:
		jig_v[i] += Vector2(rng.randf_range(-60.0, 60.0), -520.0 * (1.0 if i == 0 else 0.9))


## 접기: 진행 중이면 빠르게 퇴장, 이미 접히는 중이면 그대로
func cancel() -> void:
	if ph == Ph.DONE:
		return
	if ph != Ph.EXIT:
		ph = Ph.EXIT
		exit_t = t


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var dt := clampf(float(now - _last_us) / 1e6, 0.0, 1.0 / 20.0)
	_last_us = now
	if fixed_dt > 0.0:
		dt = fixed_dt
	if get_tree().paused:
		visible = false
		return
	visible = true
	t += dt
	# 합체 전에 비행이 끊겼거나(피격·분리·제거) 메카가 쓰러지면 접는다
	if dock_t < 0.0 and ph != Ph.EXIT:
		var lost: bool = not is_instance_valid(drone) or drone.get("state") != PartnerDrone.St.RECALL
		if lost or t > WAIT_MAX:
			cancel()
	if is_instance_valid(main) and is_instance_valid(main.player) and not main.player.alive:
		cancel()
	match ph:
		Ph.ENTER:
			if t >= ENTER + SETTLE:
				ph = Ph.WAIT
		Ph.HOLD:
			if t >= dock_t + HOLD:
				ph = Ph.EXIT
				exit_t = t
		Ph.EXIT:
			if t >= exit_t + EXIT:
				ph = Ph.DONE
				queue_free()
				return
	_layout()
	_track_dock()
	_apply(dt)


func _layout() -> void:
	var vs := root.get_viewport_rect().size
	# 문서 시작값(높이 1.22 · 너비 51%)은 화면 가운데의 메카·합체 지점을 덮어서 줄였다: 패널 오른쪽 끝이 화면 너비 42% 안
	side = minf(vs.y * 1.05, vs.x * 0.45)
	var sz := Vector2.ONE * side
	for r in [glow, plate, frame]:
		(r as TextureRect).size = sz
	ticks.size = Vector2.ONE * side * 0.15
	ticks.position = side * Vector2(0.64, 0.17)
	panel.size = sz
	panel.pivot_offset = side * FACE_UV


func _track_dock() -> void:
	dock_ok = false
	if not is_instance_valid(main) or not is_instance_valid(main.player):
		return
	var cam := main.camera as Camera3D
	if not is_instance_valid(cam):
		return
	var w := main.player.global_position + Vector3(0, 1.1, 0)
	if cam.is_position_behind(w):
		return
	dock_screen = cam.unproject_position(w)
	dock_ok = true


## 진입/퇴장 곡선 → 패널 이동 · 크기 · 알파
func _motion() -> Array:
	var base := Vector2(-side * 0.05, -side * 0.04)
	var off := 0.0
	var sc := 1.0
	var a := 1.0
	if t < ENTER:
		var k := t / ENTER
		var e := 1.0 - pow(1.0 - k, 3.0)
		off = lerpf(-0.9, 0.0, e)
		sc = lerpf(0.98, 1.03, e)
		a = smoothstep(0.0, 0.6, k)
	elif t < ENTER + SETTLE:
		sc = lerpf(1.03, 1.0, smoothstep(0.0, 1.0, (t - ENTER) / SETTLE))
	if ph == Ph.EXIT or ph == Ph.DONE:
		var k := clampf((t - exit_t) / EXIT, 0.0, 1.0)
		var e := k * k
		off = minf(off, 0.0) + lerpf(0.0, -0.55, e)
		a *= 1.0 - k
	return [base + Vector2(off * side, 0.0), sc, a]


func _apply(dt: float) -> void:
	var m := _motion()
	var pos: Vector2 = m[0]
	var sc: float = m[1]
	var a: float = m[2]
	# 합체 충격 스프링 (패널 쿵 · 기울기)
	if dt > 0.0:
		var n := maxi(1, ceili(dt * 240.0))
		var h := dt / n
		for i in n:
			_jolt_v += (-_jolt * 900.0 - _jolt_v * 24.0) * h
			_jolt += _jolt_v * h
			_rot_v += (-_rot * 700.0 - _rot_v * 18.0) * h
			_rot += _rot_v * h
	_pan = pos + _jolt
	panel.position = _pan
	panel.scale = Vector2.ONE * sc
	panel.rotation = _rot * 0.02
	panel.modulate.a = a
	var since := t - dock_t if dock_t >= 0.0 else -1.0
	glow.modulate.a = clampf(t / (ENTER + SETTLE), 0.0, 1.0) * (0.55 + 0.45 * (exp(-since * 6.0) if since >= 0.0 else 0.0))
	ticks.modulate.a = 0.0 if since < 0.0 else clampf(since / 0.06, 0.0, 1.0) * (1.0 - smoothstep(HOLD * 0.6, HOLD, since))
	ticks.scale = Vector2.ONE * (1.0 + 0.4 * exp(-maxf(since, 0.0) * 14.0))
	_jiggle(dt)
	_fx(since, a)


## 가슴 스프링: 패널 가속도의 반대 방향으로 끌린다(관성). 화면 px → 원화 px 로 바꿔 반응을 해상도와 무관하게.
func _jiggle(dt: float) -> void:
	if dt <= 0.0:
		return
	var px_to_art := ART / maxf(side * panel.scale.x, 1.0)
	if not _pan_init:
		_pan_prev = _pan
		_pan_init = true
	var v := (_pan - _pan_prev) / dt
	var acc := (v - _pan_v) / dt
	_pan_prev = _pan
	_pan_v = v
	acc = (acc * px_to_art).limit_length(60000.0)
	_acc_hist.append([t, acc])
	while _acc_hist.size() > 2 and float(_acc_hist[1][0]) <= t - JIG_LAG:
		_acc_hist.pop_front()
	var acc_r: Vector2 = _acc_hist[0][1]
	var n := maxi(1, ceili(dt * 240.0))
	var h := dt / n
	for side_i in 2:
		var w := TAU * JIG_HZ * (JIG_R_DETUNE if side_i == 1 else 1.0)
		var f_acc: Vector2 = (acc if side_i == 0 else acc_r) * -JIG_GAIN
		var x: Vector2 = jig[side_i]
		var xv: Vector2 = jig_v[side_i]
		for i in n:
			var f := Vector2(-w.x * w.x * x.x - 2.0 * JIG_ZETA * w.x * xv.x,
				-w.y * w.y * x.y - 2.0 * JIG_ZETA * w.y * xv.y) + f_acc
			# 가로로 흔들릴 때 세로로도 조금 (8자)
			f.y += absf(xv.x) * 0.9 * signf(-x.y + 0.001)
			xv += f * h
			x += xv * h
		# 가로는 20px, 세로는 30px 까지 (넘으면 그 축 속도를 깎아 튕겨 돌아오게)
		if absf(x.x) > JIG_MAX * 0.67:
			x.x = signf(x.x) * JIG_MAX * 0.67
			xv.x *= 0.5
		if absf(x.y) > JIG_MAX:
			x.y = signf(x.y) * JIG_MAX
			xv.y *= 0.5
		jig[side_i] = x
		jig_v[side_i] = xv
		jig_peak = maxf(jig_peak, x.length())
	var l: Vector2 = jig[0]
	var r: Vector2 = jig[1]
	mat.set_shader_parameter("off_l", l / ART)
	mat.set_shader_parameter("off_r", r / ART)
	# 위로 튈 때(-y) 세로로 눌리고, 아래로 처질 때 늘어난다
	mat.set_shader_parameter("sq_l", clampf(l.y / JIG_MAX * 0.12, -0.12, 0.12))
	mat.set_shader_parameter("sq_r", clampf(r.y / JIG_MAX * 0.12, -0.12, 0.12))


## 합체 지점의 잠금 효과: 연결 광선 3개 · 접속 별빛 · 삼중 링 · 파편
func _fx(since: float, panel_a: float) -> void:
	var vs := root.get_viewport_rect().size
	var u := vs.y / 800.0
	var show := dock_ok and since >= 0.0
	flash.visible = show and since < FLASH_T
	if flash.visible:
		var k := since / FLASH_T
		flash.position = dock_screen
		flash.scale = Vector2.ONE * (88.0 * u / 256.0) * lerpf(1.35, 0.6, k)
		flash.modulate.a = 1.0 - k
	ring.visible = show and since < RING_T
	if ring.visible:
		var k := since / RING_T
		var pop := 1.0 + 0.25 * exp(-since * 20.0) * cos(since * 40.0)
		ring.position = dock_screen
		ring.rotation = k * 1.3
		ring.scale = Vector2.ONE * (132.0 * u / 256.0) * minf(k * 6.0, 1.0) * pop
		ring.modulate.a = 1.0 - smoothstep(0.55, 1.0, k)
	# 광선: 합체 전에는 옅게 이어져 차오르고, 합체 순간 밝게 모였다가 사라진다
	var start := panel.position + panel.size * panel.scale.x * EDGE_UV
	var sa := 0.0
	if dock_ok:
		if since < 0.0:
			sa = 0.35 * clampf((t - ENTER * 0.5) / ENTER, 0.0, 1.0)
		else:
			sa = (1.0 - smoothstep(0.05, 0.32, since)) * 0.95
	sa *= panel_a
	var conv := 1.0 if since < 0.0 else clampf(1.0 - since / 0.12, 0.0, 1.0)
	for i in streaks.size():
		var s := streaks[i]
		s.visible = sa > 0.01
		if not s.visible:
			continue
		var spread := (float(i) - 1.0) * 12.0 * u
		var d := dock_screen - start
		var nrm := d.orthogonal().normalized()
		var p0 := start + nrm * spread * 2.0
		var p1 := dock_screen + nrm * spread * conv
		var dd := p1 - p0
		s.position = (p0 + p1) * 0.5
		s.rotation = dd.angle()
		s.scale = Vector2(dd.length() / 256.0, (0.55 + 0.45 * (1.0 if since >= 0.0 else 0.0)) * u)
		s.modulate.a = sa * (1.0 if i == 1 else 0.7)
	for sh: Array in shards:
		var sp := sh[0] as Sprite2D
		if not show or since > 0.32:
			sp.visible = false
			continue
		sp.visible = true
		var k := since / 0.32
		var dir: Vector2 = sh[1]
		sp.position = dock_screen + dir * (40.0 + 110.0 * float(sh[2]) * ease(k, 0.35)) * u
		sp.rotation = float(sh[3]) * since + dir.angle()
		sp.scale = Vector2.ONE * ((18.0 + 12.0 * float(sh[2])) * u / 96.0) * (1.0 - k * 0.5)
		sp.modulate.a = 1.0 - k
