class_name BladeTech
extends RefCounted
## 광선검 특수기 두 가지. Player 가 소유하고 입력(feed) → 진행(update) → 자세(pose) 순으로 부른다.
##
## ① 기 모으기 돌진 (좌클릭 길게)
##    가만히 있을 때 좌클릭을 HOLD 초 넘게 누르고 있으면 그 자리에 서서 기를 모은다. 모을수록 등 뒤 부스터가
##    점점 거세게 촤라라락 뿜고(불꽃·불티·배기·소리), 바닥에 돌진 경로가 길게 그려진다. 떼면 마우스 방향으로 돌진한다.
##    - 일반(최대 미만): 모은 만큼 멀리·세게 찌르며 지나간다. 지나간 자리의 적이 한 번씩 베인다.
##    - 최대: 대시처럼 몸을 눕혀 드릴 회전하며 길게 돌진, 광선검을 회오리처럼 휘둘러 경로 위 적을 여러 번 벤다.
##      폭이 더 넓고 끝에서 원형 참격이 한 번 더 터진다. 지나간 자리에 광선검 색 잔상 줄기(BeamAfterimage)가 남고,
##      한 박자 늦게 연기 잔흔이 경로를 따라 쫓아오며 터진다.
##    짧게 떼면(HOLD 미만) 평소처럼 콤보 검이 나간다. 콤보·관통 일격이 이어지는 중의 클릭은 기다리지 않고 바로 나간다.
##
## ② 회피 레이저 (콤보 도중 좌+우클릭 동시)
##    검술 콤보 사이에 좌·우클릭을 함께 누르면 콤보를 잠깐 멈추고 순간적으로 뒤로 물러서며(무적)
##    단타 레이저를 쏜다. 에너지를 쓰지 않는다. 링크가 열린 채라 곧바로 좌클릭하면 다음 단으로 이어진다.
##
## (E 키는 도약 내려찍기 LeapSlam 이 맡는다. 예전 E 돌진 스킬은 없어졌다.)

enum St { IDLE, PENDING, CHARGE, RUSH, BACKSTEP }

const F := 1.0 / 60.0
const HOLD := 0.2               # 이만큼 누르고 있으면 기 모으기 시작 (짧게 떼면 검)
const CHARGE_TIME := 1.1        # 기 모으기 시작부터 최대까지
# 일반 돌진 (모은 정도 k 0~1 로 보간)
const DIST := Vector2(4.0, 9.0)
const TIME := Vector2(0.1, 0.16)
const WIDTH := Vector2(1.1, 1.5)
const DMG := Vector2(6.0, 16.0)
# 최대 돌진
const MAX_DIST := 14.0
const MAX_TIME := 0.36
const MAX_WIDTH := 1.15         # 경로 폭 (예전 2.3 의 절반)
const MAX_TICK := 0.06          # 회오리 다단히트 간격 (같은 적)
const MAX_TICK_DMG := 6
const MAX_HITS := 5             # 한 적이 경로 위에서 맞는 최대 횟수
const MAX_SPIN := 6.0           # 돌진 동안 몸이 도는 바퀴 수
const FINISH_R := 1.6           # 끝에서 터지는 원형 참격 반경 (예전 3.2 의 절반)
const FINISH_DMG := 10
# 회피 레이저
# 기 모으기 줌아웃: 모은 정도가 이 문턱을 넘을 때마다 카메라가 한 칸씩 물러난다 (먼 적까지 보이게)
const ZOOM_STEPS := [0.25, 0.5, 0.75, 1.0]
const ZOOM_LEVELS := [1.0, 1.1, 1.2, 1.31, 1.45]
const ZOOM_HOLD := 0.35         # 돌진이 끝난 뒤 줌을 붙잡아 두는 시간
# 최대 돌진의 나선 잔상: 광선검 리본을 이만큼 오래 남긴다 (평소 0.038초)
const SPIRAL_LIFE := 0.5
const SPIRAL_REACH := 1.1       # 리본 폭 (평소 1.65 배)
const BS_TIME := 0.22
const BS_FIRE := 4.0 * F        # 물러서기 시작하고 이만큼 뒤 발사
const BS_SPEED := 19.0
const BS_K := 0.55              # 레이저 세기 (임팩트 프레임이 나오지 않는 단계)

const SMOKE_LIGHT: Array[Color] = [Color("d8d4e6"), Color("f2eef8"), Color("4a4660"), Color("2e2a40")]
const SMOKE_HOT: Array[Color] = [Color("ffd0e8"), Color("f4ecf6"), Color("6a3a5a"), Color("362838")]
const TRAIL_COLS: Array[Color] = [Color("ff2e3a"), Color("ff5aa8"), Color("ffd8cc"), Color("ff5aa8"), Color("ff2e3a")]

var p: Player
var st := St.IDLE
var t := 0.0
var k := 0.0                    # 모은 정도 0~1
var vel := Vector3.ZERO
var dir := Vector3.FORWARD
var maxed := false
var _prev_held := false
var _crackle := 0.0
var _spark := 0.0
var _stage := 0
var _preview: Node3D
var _jet_rest := -40.0
# 돌진
var _from := Vector3.ZERO
var _last := Vector3.ZERO
var _dur := 0.0
var _width := 0.0
var _dmg := 0
var _hit: Dictionary = {}       # 적 instance id → [맞은 횟수, 마지막 시각]
var _ghost := 0
var _spin := 0.0
var _spin_prev := 0.0
var _fired := false
var _zoom_step := 0
var _zoom_hold := 0.0
var _trail_life := 0.038
var _trail_reach := 1.65
var _trail_bright := 1.0
var _spiral_t := 0.0
var _queued := false            # 회피 레이저 도중 누른 검: 끝나자마자 다음 단으로


func _init(owner: Player) -> void:
	p = owner
	_jet_rest = (p.j.jet_l as Node3D).rotation_degrees.x
	if p.trail:
		_trail_life = p.trail.life
		_trail_reach = p.trail.reach


func _cam_zoom(z: float) -> void:
	var cam = Main.inst.camera if Main.inst else null
	if cam and cam.has_method("set_charge_zoom"):
		cam.set_charge_zoom(z)


## 노즐 각도: 기 모으기·돌진 중에는 등 뒤로 수평에 가깝게 눕혀 뒤로 뿜는다
func _aim_jets(deg: float) -> void:
	for jet in [p.j.jet_l, p.j.jet_r]:
		(jet as Node3D).rotation_degrees.x = deg


# ── 상태 질의 ───────────────────────────────────────────

func charging() -> bool:
	return st == St.CHARGE


func rushing() -> bool:
	return st == St.RUSH


## 최대 돌진(드릴 회오리) 중
func whirl() -> bool:
	return st == St.RUSH and maxed


func backstepping() -> bool:
	return st == St.BACKSTEP


## 이동·사격을 잡고 있는가
func busy() -> bool:
	return st == St.CHARGE or st == St.RUSH or st == St.BACKSTEP


## 자세를 직접 잡는가 (기 모으기 · 돌진)
func posing() -> bool:
	return st == St.CHARGE or st == St.RUSH


## 등 부스터 세기 (Player._animate_jets 에 넘긴다)
func jet_k() -> float:
	if st == St.CHARGE:
		return 0.35 + k * 1.6
	if st == St.RUSH:
		return 2.2 if maxed else 1.0 + k
	return 0.0


# ── 입력 ────────────────────────────────────────────────

## 좌클릭 상태를 매 틱 넘긴다. 검(탭)이 지금 나가야 하면 true.
## held: 좌클릭 누름 · rmb: 우클릭 누름 · allowed: 지금 조작 가능
func feed(held: bool, rmb: bool, allowed: bool, dt: float) -> bool:
	var pressed := held and not _prev_held
	var released := not held and _prev_held
	_prev_held = held
	if not allowed:
		if st == St.PENDING or st == St.CHARGE:
			abort()
		# 대시 · 관통 일격 등으로 묶인 동안 누른 좌클릭은 검 선입력으로 넘긴다 (기 모으기로 가리지 않는다)
		return pressed and not rmb and st == St.IDLE
	match st:
		St.BACKSTEP:
			if pressed and not rmb:
				_queued = true
		St.IDLE:
			if _queued:
				_queued = false
				return true
			if pressed and not rmb:
				# 콤보·관통 일격이 이어지는 중이면 기다리지 않고 바로 벤다
				if p.combo.posing() or p.combo.link_t > 0.0 or p.phantom_ready or p.whirl.armed() or p.slash_cd > 0.0 or p.charging:
					return true
				st = St.PENDING
				t = 0.0
		St.PENDING:
			t += dt
			if rmb:
				st = St.IDLE                 # 우클릭이 함께 눌리면 충전 레이저 쪽으로 넘긴다
			elif released:
				st = St.IDLE
				return true                  # 짧게 뗐다: 평소 검
			elif t >= HOLD:
				_begin_charge()
		St.CHARGE:
			if released:
				_release()
	return false


## 콤보 중 좌+우클릭 동시 입력: 회피 레이저 (Player 가 조건을 보고 부른다)
func try_backstep() -> bool:
	if st != St.IDLE or p.laser_cd > 0.0:
		return false
	if not (p.combo.posing() or p.combo.link_t > 0.0):
		return false
	_begin_backstep()
	return true


## 대시·피격·경직 등으로 끊는다
func abort() -> void:
	match st:
		St.CHARGE:
			_end_charge_fx()
			_cam_zoom(1.0)
		St.RUSH:
			_finish_rush(false)
			_cam_zoom(1.0)
	if st != St.IDLE:
		vel = Vector3.ZERO
	st = St.IDLE
	_queued = false


# ── 기 모으기 ───────────────────────────────────────────

func _begin_charge() -> void:
	st = St.CHARGE
	t = 0.0
	k = 0.0
	_stage = 0
	_zoom_step = 0
	_zoom_hold = 0.0
	_crackle = 0.0
	_spark = 0.0
	maxed = false
	Sfx.play("unfold", 0.05, -6.0)
	FX.shockwave(p.global_position, Color("ff8a5a"), 1.4, 0.2, 0.04)
	_preview = _make_preview()


func _end_charge_fx() -> void:
	RangeOutline.clear("rush")
	if is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	if st != St.RUSH:
		_aim_jets(_jet_rest)


func _charge_tick(dt: float) -> void:
	t += dt
	k = clampf(t / CHARGE_TIME, 0.0, 1.0)
	dir = p.aim_dir
	vel = vel.move_toward(Vector3.ZERO, 80.0 * dt)
	# 카메라: 문턱마다 한 칸씩 계단식으로 줌아웃
	while _zoom_step < ZOOM_STEPS.size() and k >= float(ZOOM_STEPS[_zoom_step]) - 0.0001:
		_zoom_step += 1
		_cam_zoom(float(ZOOM_LEVELS[_zoom_step]))
		if _zoom_step % 2 == 1:
			var tick := Sfx.play("tink", 0.0, -12.0)
			if tick:
				tick.pitch_scale = 0.7 + _zoom_step * 0.15
	# 단계: 절반 · 최대
	var s := 2 if k >= 1.0 else (1 if k >= 0.5 else 0)
	if s > _stage:
		_stage = s
		var ping := Sfx.play("charged" if s == 2 else "ready", 0.0, -2.0 if s == 2 else -5.0)
		if ping:
			ping.pitch_scale = 1.0 if s == 2 else 0.9
		p.squash_v -= 6.0 + s * 3.0
		FX.shockwave(p.global_position, Pal.BLADE if s == 2 else Color("ff8a5a"), 2.0 + s, 0.25, 0.06)
		if s == 2:
			FX.flash((p.j.blade as Node3D).global_position, Color(1.0, 0.8, 0.85), 1.0, 0.08)
			Main.inst.camera.fov_punch(2.5)
			Main.inst.shake(0.15)
	# 등 부스터: 모을수록 거세게 뒤로 뿜는다 (불꽃 배기 + 불티 + 촤라라락 소리)
	var back := -dir
	_crackle -= dt
	if _crackle <= 0.0:
		_crackle = lerpf(0.11, 0.028, k)
		var snd := Sfx.play("roll" if randf() < 0.6 else "dash", 0.02, lerpf(-16.0, -5.0, k))
		if snd:
			snd.pitch_scale = lerpf(1.2, 2.1, k) * randf_range(0.92, 1.08)
	_spark -= dt
	for jet in [p.j.jet_l, p.j.jet_r]:
		var n := jet as Node3D
		var jp := n.global_position
		FX.boost_puff(jp + back * 0.2, back * lerpf(3.0, 13.0, k) + Vector3(0, lerpf(-0.6, 0.3, k), 0) + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * lerpf(0.5, 2.0, k))
		if _spark <= 0.0:
			FX.sparks(jp + back * 0.3, int(lerpf(3.0, 10.0, k)), [Color.WHITE, Pal.JET_CORE, Pal.JET], lerpf(5.0, 13.0, k), 0.22, -5.0, 0.05)
		if k > 0.45 and randf() < k * 0.5:
			GustFX.boost_wash(jp, back * lerpf(6.0, 18.0, k))
		# 촤라라락: 노즐에서 튀어나가는 짧은 불꽃 혀 (모을수록 길고 잦다)
		for _i in (1 if k < 0.5 else 2):
			_tongue(jp + back * 0.15, back, lerpf(0.5, 1.9, k) * randf_range(0.6, 1.2), lerpf(0.07, 0.16, k))
	if _spark <= 0.0:
		_spark = lerpf(0.12, 0.04, k)
	# 발밑이 떨리며 몸이 앞쪽으로 쏠린다
	p.tilt_v += dir * (1.5 + k * 3.0) * dt * 10.0
	if k >= 1.0 and randf() < 0.3:
		Main.inst.shake(0.04)
	_update_preview()


## 노즐 불꽃 혀: 뒤로 길게 튀어나갔다 1~3프레임 만에 사라진다
func _tongue(pos: Vector3, back: Vector3, length: float, w: float) -> void:
	var bm := _unit_box()
	var c := Pal.JET_CORE if randf() < 0.45 else (Pal.JET if randf() < 0.6 else Color("ffb040"))
	var mi := Pal.flat_mesh(bm, c, 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	FX.root.add_child(mi)
	var d := (back + Vector3(randf_range(-0.25, 0.25), randf_range(-0.2, 0.15), randf_range(-0.25, 0.25))).normalized()
	mi.global_position = pos + d * length * 0.5
	var b := Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
	mi.basis = b * Basis.from_scale(Vector3(w, w, length))
	var tw := mi.create_tween()
	tw.tween_method(func(v: float): mi.basis = b * Basis.from_scale(Vector3(maxf(w * v, 0.001), maxf(w * v, 0.001), length * (1.4 - v * 0.4))), 1.0, 0.0, randf_range(0.03, 0.06))
	tw.tween_callback(mi.queue_free)


static var _box: BoxMesh


## 불꽃 혀가 함께 쓰는 단위 상자 (크기는 인스턴스 basis 로 늘린다)
static func _unit_box() -> BoxMesh:
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3.ONE
	return _box


## 바닥에 그리는 돌진 경로 미리보기: 가운데 선 + 양쪽 폭 선 (모을수록 길어지고, 최대면 넓어지며 깜빡인다)
func _make_preview() -> Node3D:
	var root := Node3D.new()
	FX.root.add_child(root)
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	for i in 3:
		var mi := Pal.flat_mesh(bm, Color(1.0, 0.35, 0.45), 1.4)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root


func _update_preview() -> void:
	if not is_instance_valid(_preview):
		return
	var full := k >= 1.0
	var dist := _free_dist(dir, MAX_DIST if full else lerpf(DIST.x, DIST.y, k))
	var w := MAX_WIDTH if full else lerpf(WIDTH.x, WIDTH.y, k)
	var base := p.global_position
	var mid := base + dir * dist * 0.5
	mid.y = Main.gy(base) + 0.04
	_preview.global_position = mid
	var b := Basis.looking_at(dir, Vector3.UP)
	var a := 0.45 + k * 0.45 + (sin(Time.get_ticks_msec() * 0.03) * 0.3 if full else 0.0)
	var c := Color(1.0, 0.55, 0.4) if not full else Color(1.0, 0.3, 0.55)
	var side := Vector3.UP.cross(dir).normalized()
	var kids := _preview.get_children()
	for i in kids.size():
		var mi := kids[i] as MeshInstance3D
		var off := (float(i) - 1.0) * w * 0.5
		var lw := 0.07 if i == 1 else 0.04
		mi.position = side * off
		# 바깥 선은 진행할수록 길게 자라나는 느낌으로 조금 짧게
		var len := dist * (1.0 if i == 1 else 0.92)
		mi.basis = b * Basis.from_scale(Vector3(lw, 0.01, len))
		var aa := a * (1.0 if i == 1 else 0.6)
		mi.set_instance_shader_parameter("tint", Color(c.r * aa, c.g * aa, c.b * aa))
	# 경로(최대면 끝의 원형 참격까지) 안 적: 실루엣에 굵은 붉은 외곽선
	var inside: Array = []
	var end := base + dir * dist
	for e in Enemy.live(p.get_tree()):
		var en := e as Enemy
		if not is_instance_valid(en) or not en.alive or not en.landed:
			continue
		var hit := p._seg_dist(base, dir, dist, en.global_position) <= en.radius + w * 0.5
		if full and not hit:
			var fe := en.global_position - end
			fe.y = 0
			hit = fe.length() <= FINISH_R + en.radius
		if hit:
			inside.append(en)
	RangeOutline.mark("rush", inside)


## 벽 앞에서 멈추는 거리
func _free_dist(d: Vector3, want: float) -> float:
	var main := Main.inst
	var free := 0.0
	while free < want:
		if main.is_blocked(p.global_position + d * (free + 0.25 + 0.45)):
			break
		free += 0.25
	return maxf(free, 0.6)


# ── 돌진 ────────────────────────────────────────────────

func _release() -> void:
	_end_charge_fx()
	_launch(p.aim_dir)


## 모은 정도 k 로 d 방향 돌진을 시작한다
func _launch(d: Vector3, reach := 1.0) -> void:
	maxed = k >= 1.0
	dir = d
	var want := (MAX_DIST if maxed else lerpf(DIST.x, DIST.y, k)) * reach
	var dist := _free_dist(dir, want)
	_dur = (MAX_TIME if maxed else lerpf(TIME.x, TIME.y, k)) * reach   # 늘린 거리만큼 시간도 늘려 속도는 같게
	_dur *= dist / want if want > 0.0 else 1.0
	_dur = maxf(_dur, 3.0 * F)
	_width = MAX_WIDTH if maxed else lerpf(WIDTH.x, WIDTH.y, k)
	_dmg = MAX_TICK_DMG if maxed else int(round(lerpf(DMG.x, DMG.y, k)))
	_from = p.global_position
	_last = _from
	_hit.clear()
	_ghost = 0
	_spin = 0.0
	_spin_prev = 0.0
	st = St.RUSH
	t = 0.0
	vel = dir * (dist / _dur)
	p.invuln = maxf(p.invuln, _dur + 0.12)
	p.tilt_v += dir * 12.0
	p.squash_v += 10.0
	var main := Main.inst
	FX.afterimage(p.visual, Color(1.0, 0.5, 0.6, 0.55), 0.25)
	FX.shockwave(p.global_position, Pal.BLADE, 2.6 if maxed else 1.8, 0.25, 0.08)
	FX.flash(p.global_position + Vector3(0, 0.9, 0), Color(1.0, 0.75, 0.7), 1.4 if maxed else 0.8, 0.06)
	GustFX.dash_burst(p.global_position, dir, Color(1.0, 0.55, 0.7))
	Distortion.burst(p.global_position + Vector3(0, 0.8, 0), 2.5, 0.25, 1.0)
	Sfx.play("launch" if maxed else "dash", 0.0, -2.0)
	var s := Sfx.play("slash", 0.03, 0.0)
	if s:
		s.pitch_scale = 0.8 if maxed else 1.05
	if maxed:
		# 나선 잔상: 리본을 오래 남겨 드릴 회전한 칼끝이 경로에 광선검 색 나선을 그린다 (원래 밝기로)
		# 되돌릴 값은 지금 잡는다 (기본 리본은 Player 가 잔상을 만든 뒤 정한다)
		if not is_equal_approx(p.trail.life, SPIRAL_LIFE):       # 나선이 이어질 때는 처음 값을 지킨다
			_trail_life = p.trail.life
			_trail_reach = p.trail.reach
			_trail_bright = p.trail.bright
		p.trail.life = SPIRAL_LIFE
		p.trail.reach = SPIRAL_REACH
		p.trail.bright = 1.0
		_spiral_t = -1.0
		Sfx.play("roll", 0.0, 0.0)
		main.hitstop(0.04)
		main.hud.popup("TEMPEST", Color(1.0, 0.55, 0.7), p.global_position + Vector3(0, 2.4, 0))
	main.camera.fov_punch(9.0 if maxed else 4.0 + k * 3.0)
	main.kick(dir * (1.2 if maxed else 0.6))
	main.shake(0.25 if maxed else 0.12)
	trail_on(true)


func trail_on(on: bool) -> void:
	p.trail.boost = 1.0 if on else 0.0


func _rush_tick(dt: float) -> void:
	t += dt
	var main := Main.inst
	vel = dir * vel.length()
	# 지나간 구간 판정
	var now := p.global_position
	var seg := now - _last
	seg.y = 0
	var l := seg.length()
	var full := now - _from
	full.y = 0
	var path_len := full.length()
	for e in p.get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var d := p._seg_dist(_from, dir, path_len, en.global_position)
		if d > en.radius + _width * 0.5:
			continue
		var id := en.get_instance_id()
		var rec: Array = _hit.get(id, [0, -1.0])
		if maxed:
			if int(rec[0]) >= MAX_HITS or t - float(rec[1]) < MAX_TICK:
				continue
		elif int(rec[0]) >= 1:
			continue
		_hit[id] = [int(rec[0]) + 1, t]
		en.slash_yaw = atan2(-dir.x, -dir.z) + (randf_range(-1.2, 1.2) if maxed else 0.0)
		var k0 := en.knock
		var push := dir if not maxed else (dir + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.6).normalized()
		en.take_hit(_dmg, push, en.global_position, "slash")
		en.knock = k0 + (en.knock - k0) * (0.15 if maxed else 0.8)
		var hp := en.global_position + Vector3(0, 1.0, 0)
		FX.sparks(hp, 8, [Color.WHITE, Color(1.0, 0.5, 0.8), Pal.BLADE], 7.0, 0.22, -10.0, 0.05)
		if maxed:
			var b := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.FORWARD, randf_range(-1.0, 1.0)) * Basis.from_scale(Vector3.ONE * 0.6)
			FX.crescent(hp, b, 0.02, 0.07)
			main.hitstop(0.018)
		else:
			main.hitstop(0.05 + k * 0.04)
			main.shake(0.2 + k * 0.2)
		var snd := Sfx.play("slash", 0.02, -4.0)
		if snd:
			snd.pitch_scale = randf_range(1.2, 1.5)
	# 적탄을 지운다
	for b in p.get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		if not bl.unslashable and p._seg_dist(_from, dir, path_len, bl.position) < _width * 0.5 + 0.3:
			FX.flash(bl.position, Pal.BLADE, 0.4, 0.06)
			bl.queue_free()
	# 잔상 · 회오리 · 기류
	_ghost -= 1
	if _ghost <= 0:
		_ghost = 1 if maxed else 2
		FX.afterimage(p.visual, Color(1.0, 0.5, 0.75, 0.32) if maxed else FX.GHOST, 0.14)
	if maxed:
		var ay := atan2(-dir.x, -dir.z)
		FX.vortex(p.visual.global_position, Basis(Vector3.UP, ay) * Basis(Vector3.RIGHT, -PI * 0.5), Color(1.0, 0.4, 0.65) if randf() < 0.5 else Color(1.0, 0.75, 0.85))
	if l > 0.01:
		GustFX.dash_trail(_last, now, Color(1.0, 0.55, 0.75), 1.3 if maxed else 1.0)
	_last = now
	if t >= _dur:
		_finish_rush(true)


func _finish_rush(completed: bool) -> void:
	var main := Main.inst
	var to := p.global_position
	st = St.IDLE
	vel = dir * (3.0 if completed else 0.0)
	p.velocity = vel                 # 돌진 속도가 남아 미끄러지지 않게 바로 멈춘다
	trail_on(false)
	_aim_jets(_jet_rest)
	var yaw := atan2(-dir.x, -dir.z)
	p.visual.basis = Basis.IDENTITY
	(p.j.upper as Node3D).rotation.y = yaw
	(p.j.legs as Node3D).rotation.y = yaw
	p.aim_dir = dir
	_zoom_hold = ZOOM_HOLD
	if maxed:
		_spiral_t = SPIRAL_LIFE          # 나선이 다 사라진 뒤 리본 수명을 되돌린다
	if not completed:
		return
	p.squash_v -= 10.0
	var g := Vector3(to.x, Main.gy(to) + 0.05, to.z)
	RushFX.brake(to, dir)
	var path := to - _from
	path.y = 0
	var length := path.length()
	if maxed:
		# 끝에서 원형 참격: 몸 둘레를 크게 가르는 가로 초승달 두 겹 + 범위 피해
		FX.crescent(to + Vector3(0, 0.9, 0), Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.8, 1, 0.8)), 0.03, 0.12)
		FX.crescent(to + Vector3(0, 0.6, 0), Basis(Vector3.UP, yaw + PI) * Basis(Vector3.FORWARD, 0.3) * Basis.from_scale(Vector3(0.95, 1, 0.95)), 0.04, 0.14)
		var any := false
		for e in p.get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy
			if not en.alive or not en.landed:
				continue
			var d := en.global_position - to
			d.y = 0
			if d.length() < FINISH_R + en.radius:
				en.slash_yaw = randf() * TAU
				en.take_hit(FINISH_DMG, d.normalized() if d.length() > 0.1 else dir, en.global_position, "slash")
				any = true
		FX.shockwave(g, Pal.BLADE, FINISH_R * 1.4, 0.3, 0.1)
		FX.shockwave(g, Color(1.0, 0.75, 0.85), FINISH_R, 0.22, 0.05)
		FX.sparks(g + Vector3(0, 0.3, 0), 18, [Color.WHITE, Color(1.0, 0.45, 0.75), Pal.BLADE], 7.0, 0.3, -14.0, 0.06)
		Distortion.burst(g + Vector3(0, 0.6, 0), 2.3, 0.3, 1.2)
		Sfx.play("boom", 0.05, -6.0 if any else -10.0)
		main.hitstop(0.1 if any else 0.03)
		main.shake(0.5)
		main.hud.screen_flash(Color(1.0, 0.7, 0.8), 0.2)
		main.camera.fov_punch(-6.0)
	else:
		FX.crescent(to + Vector3(0, 1.0, 0) + dir * 0.4, Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, deg_to_rad(-20)) * Basis.from_scale(Vector3(0.9 + k * 0.4, 1, 0.9 + k * 0.4)), 0.03, 0.1)
		FX.shockwave(g, Color(1.0, 0.5, 0.7), 1.6 + k * 1.4, 0.22, 0.05)
		main.camera.fov_punch(-2.0 - k * 3.0)
	# 지나간 자리에 남는 광선검 색 잔상 줄기 (강력 레이저 잔상처럼 일렁이다 부서진다)
	if length > 0.8 and (maxed or k >= 0.3):
		var side := Vector3.UP.cross(dir).normalized()
		var n := 5 if maxed else 3
		for i in n:
			var off := (float(i) / (n - 1) - 0.5) * _width
			var o := Vector3(_from.x, Main.gy(_from) + 0.95 + (absf(off) * 0.3 if maxed else 0.0), _from.z) + side * off
			BeamAfterimage.spawn(o, dir, length, 0.12 if i == n / 2 else 0.08, TRAIL_COLS[i * (TRAIL_COLS.size() - 1) / (n - 1)], i * 0.02)
	# 연기 잔흔: 한 박자 늦게 경로를 따라 쫓아오며 터진다
	_smoke_wake(_from, to, length)


func _smoke_wake(a: Vector3, b: Vector3, length: float) -> void:
	if length < 0.5:
		return
	var tree := p.get_tree()
	var d := (b - a)
	d.y = 0
	d = d.normalized()
	var step := 0.9
	var n := int(ceil(length / step))
	var cols := SMOKE_HOT if maxed else SMOKE_LIGHT
	var big := maxed
	var size := 0.62 if maxed else lerpf(0.6, 0.95, k)   # 최대는 예전(1.25)의 절반
	var spread := _width * 0.45
	for i in n + 1:
		var f := float(i) / maxi(n, 1)
		var pos := a + d * length * f
		pos.y = Main.gy(pos) + 0.05
		var delay := 0.08 + f * (0.16 if maxed else 0.1)
		tree.create_timer(delay, false).timeout.connect(func():
			FX.puffs(pos, 3 if maxed else 2, cols, spread, size, 0.75 if maxed else 0.55)
			if i % 3 == 0:
				FX.shockwave(pos, Color(0.85, 0.82, 0.95), (0.6 if big else 1.2) + size, 0.2, 0.04))
	# 연기 파도가 끝에 닿는 순간 한 번 크게 터진다
	var last := b
	last.y = Main.gy(b) + 0.05
	var land_dir := d
	tree.create_timer(0.1 + (0.16 if maxed else 0.1), false).timeout.connect(func():
		FX.puffs(last, 4 if big else 3, cols, spread * 1.5, size * 1.05, 0.7)
		FX.land_dust(last)
		Distortion.burst(last + Vector3(0, 0.5, 0), 1.75 if big else 2.0, 0.3, 1.0)
		GustFX.dash_stop(last, land_dir)
		Sfx.play("land", 0.05, -2.0 if big else -6.0)
		if is_instance_valid(Main.inst):
			Main.inst.shake(0.25 if big else 0.1))


# ── 회피 레이저 ─────────────────────────────────────────

func _begin_backstep() -> void:
	p.combo.suspend()
	st = St.BACKSTEP
	t = 0.0
	_fired = false
	var to := p.aim_point - p.global_position
	to.y = 0
	dir = to.normalized() if to.length() > 0.3 else p.aim_dir
	p.aim_dir = dir
	vel = -dir * BS_SPEED
	p.invuln = maxf(p.invuln, BS_TIME + 0.08)
	p.tilt_v += -dir * 10.0
	p.squash_v -= 6.0
	FX.afterimage(p.visual, Color(0.55, 0.9, 1.0, 0.5), 0.2)
	GustFX.dash_burst(p.global_position, -dir, Color("8ad8ff"))
	Sfx.play("dash", 0.03, -4.0)


func _backstep_tick(dt: float) -> void:
	t += dt
	if not _fired and t >= BS_FIRE:
		_fired = true
		p._fire_laser(BS_K)
		p.laser_cd = 0.3
	var k2 := clampf(t / BS_TIME, 0.0, 1.0)
	vel = -dir * BS_SPEED * (1.0 - k2) * (1.0 - k2) * (1.0 if not _fired else 1.3)
	if t >= BS_TIME:
		st = St.IDLE
		vel = Vector3.ZERO
		p.velocity = Vector3.ZERO


# ── 진행 · 자세 ─────────────────────────────────────────

func update(dt: float) -> void:
	if st == St.IDLE or st == St.BACKSTEP:
		if _zoom_hold > 0.0:
			_zoom_hold -= dt
			if _zoom_hold <= 0.0:
				_cam_zoom(1.0)
		if _spiral_t > 0.0:
			_spiral_t -= dt
			if _spiral_t <= 0.0:
				p.trail.life = _trail_life
				p.trail.reach = _trail_reach
				p.trail.bright = _trail_bright
	match st:
		St.CHARGE:
			_charge_tick(dt)
		St.RUSH:
			_rush_tick(dt)
		St.BACKSTEP:
			_backstep_tick(dt)


## Player._animate 끝에서 부른다 (기 모으기 · 돌진 자세). 광선검 잔상도 여기서 먹인다.
func pose(dt: float) -> void:
	var j := p.j
	var arm: Node3D = j.arm_r
	var blade: Node3D = j.blade
	var torso: Node3D = j.torso
	var tt := Time.get_ticks_msec() * 0.001
	if st == St.CHARGE or st == St.RUSH:
		_aim_jets(lerpf(_jet_rest, -82.0, clampf(k * 1.5, 0.3, 1.0)) if st == St.CHARGE else -85.0)
	if st == St.CHARGE:
		# 낮게 웅크려 칼을 등 뒤로 끌어당긴 자세. 모을수록 깊어지고 떨린다.
		var c := _out(clampf(t / 0.12, 0.0, 1.0))
		var sh := sin(tt * 70.0) * 0.03 * k
		arm.rotation = Vector3(-0.5 * c, -1.55 * c + sh, 0.1 * c)
		blade.rotation_degrees = Vector3(38, -18, 0).lerp(Vector3(8, -75, 0), c)
		var bs := 1.0 + k * 0.25
		blade.scale = Vector3(1.0 / sqrt(bs), 1.0 / sqrt(bs), bs)
		torso.rotation = Vector3((0.22 + k * 0.12) * c, (-0.85 - k * 0.15) * c, 0.06 * c + sh)
		(j.hip_l as Node3D).rotation.x = (-0.65 - k * 0.2) * c
		(j.hip_r as Node3D).rotation.x = (0.6 + k * 0.25) * c
		(j.knee_l as Node3D).rotation.x = (-0.5 - k * 0.3) * c
		(j.knee_r as Node3D).rotation.x = (-0.95 - k * 0.35) * c
		(j.arm_l as Node3D).rotation.y = 0.4 * c
		p.visual.position.y = Player.PIVOT_Y + p.hover - (0.1 + k * 0.1) * c
		if p.boost_snd.playing:
			p.boost_snd.pitch_scale = 0.75 + k * 1.0
			p.boost_snd.volume_db = lerpf(-14.0, -4.0, k)
		p.trail.feed(dt, [])
		return
	if st == St.RUSH:
		var yaw := atan2(-dir.x, -dir.z)
		var kr := clampf(t / _dur, 0.0, 1.0)
		if maxed:
			# 드릴 회오리: 몸을 눕혀 머리를 진행 방향에 두고 축 회전, 칼은 옆으로 뻗어 나선을 그린다
			(j.upper as Node3D).rotation.y = 0.0
			(j.legs as Node3D).rotation.y = 0.0
			arm.rotation = Vector3(-0.15, 0.0, 1.4)
			blade.rotation_degrees = Vector3(-90, 0, 0)
			blade.scale = Vector3(0.85, 0.85, 0.9)   # 범위를 줄인 만큼 칼도 짧게 (예전 1.8)
			torso.rotation = Vector3.ZERO
			for h in [j.hip_l, j.hip_r]:
				(h as Node3D).rotation.x = 0.25
			for kn in [j.knee_l, j.knee_r]:
				(kn as Node3D).rotation.x = -0.2
			(j.arm_l as Node3D).rotation.z = -0.5
			var lay := smoothstep(0.0, 0.12, kr) * (1.0 - smoothstep(0.88, 1.0, kr))
			_spin = MAX_SPIN * TAU * kr
			# 한 틱에 크게 도는 칼이 매끈한 나선을 남기도록 사이 각도를 잘게 샘플한다
			var samples: Array = []
			var n := clampi(int(ceil(absf(_spin - _spin_prev) / 0.35)), 1, 12)
			for i in range(1, n + 1):
				var sp := lerpf(_spin_prev, _spin, float(i) / n)
				var upright := Basis(Vector3.UP, yaw)
				var flat := upright * Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, sp)
				p.visual.basis = upright.slerp(flat, lay) if lay < 0.999 else flat
				if i < n:
					samples.append(p.trail.sample_now())
			_spin_prev = _spin
			p.visual.position.y = Player.PIVOT_Y + p.hover + 0.15 * lay
			p.trail.feed(dt, samples)
		else:
			# 찌르며 지나간다: 칼을 앞으로 길게 늘이고 몸을 앞으로 기울인다
			(j.upper as Node3D).rotation.y = yaw
			(j.legs as Node3D).rotation.y = yaw
			arm.rotation = Vector3(1.6, 0.1, 0.0)
			blade.rotation_degrees = Vector3(-90, 0, 0)
			var bs := 1.5 + k * 0.5
			blade.scale = Vector3(1.0 / sqrt(bs), 1.0 / sqrt(bs), bs)
			torso.rotation = Vector3(-0.3, 0.5, 0.0)
			(j.hip_l as Node3D).rotation.x = -0.9
			(j.hip_r as Node3D).rotation.x = 0.8
			(j.knee_l as Node3D).rotation.x = -0.15
			(j.knee_r as Node3D).rotation.x = -0.6
			var right := dir.cross(Vector3.UP).normalized()
			p.visual.basis = Basis(right, -0.35 * (1.0 - kr * 0.5))
			p.visual.position.y = Player.PIVOT_Y + p.hover
			p.trail.feed(dt, [])


static func _out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)
