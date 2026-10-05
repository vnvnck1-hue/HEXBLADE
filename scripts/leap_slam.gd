class_name LeapSlam
extends RefCounted
## E 도약 내려찍기. Player 가 소유하고 입력(feed) → 진행(update · step) → 자세(pose) 순으로 부른다.
##
## E 를 누르고 있는 동안 마우스 자리에 원형 착지 인디케이터(메카닉 조준 장치)가 뜬다.
##   - 착지 원 = 내려찍기 범위 (RADIUS). 사거리 RANGE 를 넘으면 사거리 끝에 붙고 주황 MAX 로 표시한다.
##   - 발밑에서 착지점까지 점선 포물선(실제 도약 궤적) · 발밑 사거리 원 · 범위 안 적 위의 잠금 꺾쇠.
## 떼면(짧게 톡 누르면 바로) 그 자리로 도약해 칼을 머리 위로 치켜들고 앞으로 한 바퀴 돌며 날아가
## 내려찍는다: 범위 안 적에게 DMG 피해 + STUN 초 기절(보스 · 소품은 피해만). 도약 중에는 무적, 벽 · 엄폐물을 넘는다.
## 쿨타임 CD 초.

enum St { IDLE, CROUCH, AIR, LAND }

const RANGE := 9.0              # 최대 도약 거리 (m)
const MIN_DIST := 0.0
const RADIUS := 3.0             # 내려찍기 범위 반경 (m)
const DMG := 8
const STUN := 1.0               # 기절 시간 (초)
const CD := 4.0
const CROUCH := 0.07            # 도약 전 웅크림
const AIR := Vector2(0.36, 0.52)   # 체공 시간 (가까움 ~ 멀리)
const APEX := Vector2(2.2, 3.4)    # 정점 높이 (가까움 ~ 멀리)
const LAND := 0.2               # 착지 후 굳는 시간 (칼을 바닥에 박은 채)
const COL := Color("4ff5d2")    # 푸른 민트 (예전 돌진 스킬 색 그대로)
const WARN := Color("ffb347")   # 사거리 끝에 붙었을 때

var p: Player
var st := St.IDLE
var t := 0.0
var cd := 0.0
var slams := 0                  # 내려찍은 횟수 · 마지막에 맞힌 수 · 기절시킨 수 (확인용)
var last_hits := 0
var last_stuns := 0
var _prev := false
var _aim := false
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _air := 0.4
var _apex := 3.0
var _flip := 0.0
var _ghost := 0
var _y := 0.0                   # 지금 발 높이 (도약 중)
# 인디케이터
var _ind: Node3D
var _im: ImmediateMesh
var _label: Label3D
var _ind_t := 0.0
var aim_to := Vector3.ZERO      # 지금 겨눈 착지점 (월드) · 사거리 끝에 붙었나 (확인용)
var aim_clamped := false
var aim_count := 0              # 범위 안 적 수
# 착지 자국 (바닥 금 · 링): 몇 초 남았다 옅어진다
var _marks: Array = []          # [node, im, pos, 나이, 시드]

static var _mat: StandardMaterial3D


func _init(owner: Player) -> void:
	p = owner


# ── 상태 질의 ───────────────────────────────────────────

func ready() -> bool:
	return cd <= 0.0


func aiming() -> bool:
	return _aim


## 몸이 도약에 묶여 있다 (이동 · 공격 · 대시 불가)
func busy() -> bool:
	return st != St.IDLE


## 위치를 직접 잡는다 (Player 의 이동 · 바닥 처리 대신 step)
func flying() -> bool:
	return st == St.CROUCH or st == St.AIR


# ── 입력 ────────────────────────────────────────────────

## E 상태를 매 틱 넘긴다. held: E 누름 · allowed: 지금 조작 가능. 도약이 나가면 true.
func feed(held: bool, allowed: bool) -> bool:
	var pressed := held and not _prev
	var released := not held and _prev
	_prev = held
	var free := st == St.IDLE
	# 선입력: 묶여 있거나 쿨타임이 거의 끝났을 때 누른 E 는 버퍼에 담는다
	if pressed and (not allowed or not free or cd > 0.0):
		if cd <= InputBuffer.WINDOW:
			p.inbuf.push("skill")
		elif allowed:
			_deny()
	if not allowed or not free:
		if not allowed:
			_aim_end()
		return false
	if cd <= 0.0 and p.inbuf.take("skill") and not held:
		_go()                    # 짧게 톡 눌렀다: 풀리자마자 마우스 자리로 (아직 누르고 있으면 아래에서 조준이 뜬다)
		return true
	if held and not _aim and cd <= 0.0:
		_aim = true
		_ind = _make_ind()
		_update_ind(0.0)
		var tick := Sfx.play("tink", 0.0, -12.0)
		if tick:
			tick.pitch_scale = 1.4
	if released and _aim:
		_aim_end()
		if cd <= 0.0:
			_go()
			return true
	return false


func _aim_end() -> void:
	_aim = false
	if is_instance_valid(_ind):
		_ind.queue_free()
	_ind = null


func _deny() -> void:
	Main.inst.hud.popup("%.1f" % cd, Color(0.5, 0.75, 0.72), p.global_position + Vector3(0, 2.2, 0))
	var ping := Sfx.play("tink", 0.0, -8.0)
	if ping:
		ping.pitch_scale = 0.6


## 마우스 자리 → 착지점. 사거리를 넘으면 사거리 끝, 벽 · 바닥 없는 곳이면 내 쪽으로 당겨 빈 자리를 찾는다.
func _target() -> Vector3:
	var main := Main.inst
	var o := p.global_position
	var to := p.aim_point - o
	to.y = 0
	var d := to.length()
	var dir := to / d if d > 0.05 else p.aim_dir
	aim_clamped = d > RANGE
	d = clampf(d, MIN_DIST, RANGE)
	while d > 0.0:
		var c := o + dir * d
		if not main.is_blocked(c) and not main.is_blocked(c + Vector3(0.45, 0, 0)) and not main.is_blocked(c - Vector3(0.45, 0, 0)) \
				and not main.is_blocked(c + Vector3(0, 0, 0.45)) and not main.is_blocked(c - Vector3(0, 0, 0.45)):
			break
		d -= 0.25
	d = maxf(d, 0.0)
	var c := o + dir * d
	c.y = main.floor_at(c)
	return c


# ── 도약 ────────────────────────────────────────────────

func _go() -> void:
	p._combo_break()
	p.combo.cancel(true)
	_from = p.global_position
	_to = _target()
	var d := Vector2(_to.x - _from.x, _to.z - _from.z).length()
	var f := clampf(d / RANGE, 0.0, 1.0)
	_air = lerpf(AIR.x, AIR.y, f)
	_apex = lerpf(APEX.x, APEX.y, f) + maxf(_to.y - _from.y, 0.0)
	var dir := Vector3(_to.x - _from.x, 0, _to.z - _from.z)
	if dir.length() > 0.1:
		p.aim_dir = dir.normalized()
	st = St.CROUCH
	t = 0.0
	_flip = 0.0
	_ghost = 0
	_y = _from.y
	cd = CD
	p.velocity = Vector3.ZERO
	p.invuln = maxf(p.invuln, CROUCH + _air + 0.1)
	p.airborne = false
	p.squash_v -= 10.0
	Sfx.play("unfold", 0.0, -6.0)


func _takeoff() -> void:
	st = St.AIR
	t = 0.0
	var main := Main.inst
	var g := Vector3(_from.x, Main.gy(_from) + 0.05, _from.z)
	p.squash_v += 14.0
	p.jump_fx.launch(g)
	FX.shockwave(g, COL, 2.2, 0.25, 0.06)
	FX.puffs(g, 4, [Color(0.75, 0.8, 0.95), Color(0.6, 0.65, 0.85), Color(0.25, 0.27, 0.4), Color(0.2, 0.22, 0.34)], 0.8, 0.6, 0.5)
	GustFX.dash_burst(p.global_position, p.aim_dir, Color(0.6, 1.0, 0.9))
	FX.afterimage(p.visual, Color(0.55, 1.0, 0.9, 0.5), 0.22)
	Sfx.play("launch", 0.0, -4.0)
	Sfx.play("dash", 0.05, -6.0)
	main.camera.fov_punch(6.0)
	main.kick(p.aim_dir * 0.5)
	if p.trail:
		p.trail.boost = 1.0


## 도약 중 위치: 수평은 출발 → 착지점으로 (끝에서 내리꽂히듯 빨라짐), 높이는 천천히 올라 정점을 지나 빠르게 떨어진다
func _air_pos(f: float) -> Vector3:
	var h := f * f * (3.0 - 2.0 * f)
	var pos := _from.lerp(_to, lerpf(h, f, 0.35))
	var base := lerpf(_from.y, _to.y, f)
	var up: float
	if f < 0.58:
		up = sin(f / 0.58 * PI * 0.5)
	else:
		var u := (f - 0.58) / 0.42
		up = 1.0 - u * u
	pos.y = base + _apex * up
	return pos


## Player 의 이동 · 바닥 처리 대신 부른다 (CROUCH · AIR)
func step(dt: float) -> void:
	var main := Main.inst
	t += dt
	if st == St.CROUCH:
		p.global_position = Vector3(_from.x, _y, _from.z)
		if t >= CROUCH:
			_takeoff()
		_follow_ground()
		return
	var f := clampf(t / _air, 0.0, 1.0)
	var pos := _air_pos(f)
	p.global_position = pos
	_y = pos.y
	p.velocity = Vector3.ZERO
	_flip = TAU * smoothstep(0.08, 0.8, f)
	_ghost -= 1
	if _ghost <= 0:
		_ghost = 2
		FX.afterimage(p.visual, Color(0.55, 1.0, 0.9, 0.3), 0.14)
	_follow_ground()
	if f >= 1.0:
		_slam()
	elif f > 0.62 and main:
		# 내려꽂히는 동안 바닥에 공기가 눌린다
		if Engine.get_physics_frames() % 3 == 0:
			var g := Vector3(_to.x, Main.gy(_to) + 0.05, _to.z)
			FX.shockwave(g, Color(COL, 0.7), RADIUS * (1.0 - f) * 2.0 + 0.6, 0.12, 0.03)


## 그림자 · 카메라 기준 높이는 지면에 남는다
func _follow_ground() -> void:
	var pos := p.global_position
	var g := Main.inst.floor_at(pos)
	p.gy = g
	p.view_y = lerpf(p.view_y, g, 0.15)
	p.shadow.position.y = g - pos.y + 0.015
	p.dodge_ring.position.y = g - pos.y + 0.03
	p.jump_fx.follow(pos, g)
	# 높이 뜰수록 그림자가 작고 옅게
	var hgt := clampf((pos.y - g) / 3.5, 0.0, 1.0)
	p.shadow.scale = Vector3.ONE * lerpf(1.0, 0.55, hgt)


func _slam() -> void:
	var main := Main.inst
	st = St.LAND
	t = 0.0
	var at := _to
	at.y = main.floor_at(at)
	p.global_position = main.push_out_feet(at, 0.42, at.y, ArenaMap.STEP)
	p.global_position.y = at.y
	p.gy = at.y
	_y = at.y
	_follow_ground()
	p.shadow.scale = Vector3.ONE
	p.velocity = Vector3.ZERO
	p.squash_v -= 18.0
	slams += 1
	# 판정: 범위 안 적에게 피해 + 기절
	var hits := 0
	var stuns := 0
	for e in Enemy.live(p.get_tree()):
		var en := e as Enemy
		if not is_instance_valid(en) or not en.alive or not en.landed:
			continue
		var d := en.global_position - at
		if absf(d.y) > 2.2:
			continue
		d.y = 0
		var l := d.length()
		if l > RADIUS + en.radius:
			continue
		var out := d / l if l > 0.1 else p.aim_dir
		en.slash_yaw = atan2(-out.x, -out.z)
		var k0 := en.knock
		en.take_hit(DMG, out, en.global_position, "slash")
		en.knock = k0 + (en.knock - k0) * 0.4
		hits += 1
		if en.alive and not en.is_boss and not en.prop:
			en.stagger(out, STUN)
			en.knock = out * 5.0            # 경직의 큰 튕김 대신 살짝 밀려 그 자리에서 비틀거린다
			stuns += 1
	for b in p.get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		var d := bl.position - at
		d.y = 0
		if not bl.unslashable and d.length() < RADIUS:
			FX.flash(bl.position, COL, 0.4, 0.06)
			bl.queue_free()
	last_hits = hits
	last_stuns = stuns
	# 연출: 칼을 바닥에 박는 섬광 · 겹 충격파 · 사방 먼지 · 바닥 금 · 공간 일그러짐
	var g := Vector3(at.x, at.y + 0.05, at.z)
	var tip := p.global_position + p.aim_dir * 1.1 + Vector3(0, 0.15, 0)
	FX.flash(tip, Color(0.85, 1.0, 0.95), 2.4, 0.1)
	FX.shockwave(g, Color.WHITE, RADIUS * 1.25, 0.28, 0.12)
	FX.shockwave(g, COL, RADIUS * 2.1, 0.42, 0.09)
	FX.ring(g + Vector3(0, 0.3, 0), RADIUS * 1.1, [Color.WHITE, COL, Color("2a8f86")], 0.4)
	FX.sparks(tip, 30, [Color.WHITE, COL, Pal.BLADE], 11.0, 0.45, -16.0, 0.07)
	FX.puffs(g, 9, [Color(0.75, 0.8, 0.95), Color(0.6, 0.65, 0.85), Color(0.25, 0.27, 0.4), Color(0.2, 0.22, 0.34)], RADIUS * 0.75, 1.0, 0.75)
	FX.land_dust(g)
	Distortion.burst(g + Vector3(0, 0.5, 0), RADIUS * 1.2, 0.32, 1.4)
	GustFX.dash_stop(g, p.aim_dir)
	_mark(g)
	GroundBreak.burst(at, 1.0, p.aim_dir)       # 바닥이 깨져 판이 들리고 파편이 튄다 (스타일은 GroundBreak.style)
	if hits > 0:
		main.hitstop(0.11)
		main.hud.screen_flash(Color(0.8, 1.0, 0.95), 0.25)
		main.hud.popup("SLAM ×%d" % hits if hits > 1 else "SLAM", COL, g + Vector3(0, 2.6, 0))
	else:
		main.hitstop(0.04)
	main.shake(0.7)
	main.camera.fov_punch(-7.0)
	main.kick(Vector3.DOWN * 0.6)
	Sfx.play("boom", 0.03, -2.0)
	Sfx.play("land", 0.05, 0.0)
	var cl := Sfx.play("clank", 0.05, -4.0)
	if cl:
		cl.pitch_scale = 0.7


## 착지 후 굳음이 끝나면 칼을 뽑아 일어선다
func _recover() -> void:
	st = St.IDLE
	t = 0.0
	p.visual.basis = Basis.IDENTITY
	var yaw := atan2(-p.aim_dir.x, -p.aim_dir.z)
	(p.j.upper as Node3D).rotation.y = yaw
	(p.j.legs as Node3D).rotation.y = yaw
	if p.trail:
		p.trail.boost = 0.0


## 피격 · 경직 · 사망 등으로 끊는다: 공중이면 그 자리 바닥으로 내려 놓는다
func abort() -> void:
	_aim_end()
	if st == St.IDLE:
		return
	if flying():
		var pos := p.global_position
		var main := Main.inst
		pos = main.push_out(pos, 0.42)
		pos.y = main.floor_at(pos)
		p.global_position = pos
		p.gy = pos.y
		p.shadow.scale = Vector3.ONE
		_follow_ground()
	_recover()


func update(dt: float) -> void:
	cd = maxf(0.0, cd - dt)
	if _aim:
		_update_ind(dt)
	if st == St.LAND:
		t += dt
		p.velocity = Vector3.ZERO
		if t >= LAND:
			_recover()
	_update_marks(dt)


# ── 자세 ────────────────────────────────────────────────

## Player._animate 끝에서 부른다 (웅크림 · 공중제비 · 내려찍기)
func pose(dt: float) -> void:
	var j := p.j
	var arm: Node3D = j.arm_r
	var blade: Node3D = j.blade
	var torso: Node3D = j.torso
	var yaw := atan2(-p.aim_dir.x, -p.aim_dir.z)
	(j.upper as Node3D).rotation.y = yaw
	(j.legs as Node3D).rotation.y = yaw
	var right := p.aim_dir.cross(Vector3.UP).normalized()
	match st:
		St.CROUCH:
			var c := clampf(t / CROUCH, 0.0, 1.0)
			arm.rotation = Vector3(lerpf(0.0, 2.4, c), 0.0, 0.0)
			blade.rotation_degrees = Vector3(-90, 0, 0)
			torso.rotation = Vector3(0.35 * c, 0.0, 0.0)
			for h in [j.hip_l, j.hip_r]:
				(h as Node3D).rotation.x = -0.8 * c
			for kn in [j.knee_l, j.knee_r]:
				(kn as Node3D).rotation.x = -1.1 * c
			p.visual.position.y = Player.PIVOT_Y - 0.22 * c
			p.visual.basis = Basis.IDENTITY
		St.AIR:
			var f := clampf(t / _air, 0.0, 1.0)
			# 칼을 머리 위로 치켜든 채 앞으로 한 바퀴 → 내려오며 크게 내려친다
			var down := smoothstep(0.72, 0.97, f)
			arm.rotation = Vector3(lerpf(2.9, 0.7, down), 0.0, 0.0)
			blade.rotation_degrees = Vector3(-90, 0, 0)
			var bs := 1.0 + 0.35 * down
			blade.scale = Vector3(1.0, 1.0, bs)
			torso.rotation = Vector3(lerpf(0.25, -0.45, down), 0.0, 0.0)
			var tuck := 1.0 - absf(f - 0.45) / 0.45
			tuck = clampf(tuck, 0.0, 1.0)
			for h in [j.hip_l, j.hip_r]:
				(h as Node3D).rotation.x = lerpf(-0.2, -1.2, tuck)
			for kn in [j.knee_l, j.knee_r]:
				(kn as Node3D).rotation.x = lerpf(-0.3, -1.6, tuck)
			(j.arm_l as Node3D).rotation.z = -0.6
			p.visual.position.y = Player.PIVOT_Y
			p.visual.basis = Basis(right, -_flip)
		St.LAND:
			var k := clampf(t / LAND, 0.0, 1.0)
			# 칼끝을 앞바닥에 박고 웅크린 채 버틴다
			arm.rotation = Vector3(0.55, 0.0, 0.0)
			blade.rotation_degrees = Vector3(-90, 0, 0)
			blade.scale = Vector3(1.0, 1.0, 1.35 - 0.35 * k)
			torso.rotation = Vector3(-0.5 * (1.0 - k * 0.6), 0.0, 0.0)
			(j.hip_l as Node3D).rotation.x = -1.0 * (1.0 - k * 0.5)
			(j.hip_r as Node3D).rotation.x = 0.5 * (1.0 - k * 0.5)
			(j.knee_l as Node3D).rotation.x = -1.0 * (1.0 - k * 0.5)
			(j.knee_r as Node3D).rotation.x = -1.4 * (1.0 - k * 0.5)
			(j.arm_l as Node3D).rotation.z = -0.4
			p.visual.position.y = Player.PIVOT_Y - 0.28 * (1.0 - k)
			p.visual.basis = Basis.IDENTITY
	p.trail.feed(dt, [])


# ── 착지 인디케이터 ─────────────────────────────────────

static func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.vertex_color_use_as_albedo = true
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat.albedo_color = Color(1.3, 1.3, 1.3)
		_mat.render_priority = 2
	return _mat


func _make_ind() -> Node3D:
	_ind_t = 0.0
	var root := Node3D.new()
	FX.root.add_child(root)
	root.top_level = true
	_im = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _im
	mi.material_override = _material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.006
	_label.font_size = 40
	_label.outline_size = 8
	_label.outline_modulate = Color(0.02, 0.08, 0.08, 0.9)
	_label.render_priority = 3
	root.add_child(_label)
	return root


## 매 틱 ImmediateMesh 로 다시 그린다 (월드 좌표).
##   착지 원: 바깥 4분할 장갑 링(천천히 회전) · 눈금 링(45° 마다 큰 눈금) · 안쪽 3분할 역회전 링 · 옅은 채움(가장자리로 진해짐)
##            · 레이더처럼 도는 스캔 부채꼴 · 십자선 · 가운데 맥동 마름모 · 네 귀퉁이 꺾쇠(펼침 때 바깥에서 조여 든다)
##   궤적: 발밑에서 착지점까지 실제 도약 포물선을 따라 흐르는 점선 + 착지점 쪽 화살촉
##   발밑: 사거리 원(점선) · 범위 안 적 발밑의 잠금 꺾쇠
func _update_ind(dt: float) -> void:
	if not is_instance_valid(_ind):
		return
	_ind_t += dt
	var open := BladeTech._out(clampf(_ind_t / 0.16, 0.0, 1.0))
	var lock := BladeTech._out(clampf((_ind_t - 0.08) / 0.16, 0.0, 1.0))
	var to := _target()
	aim_to = to
	var tt := Time.get_ticks_msec() * 0.001
	var mc := COL
	var tc := WARN if aim_clamped else mc
	var im := _im
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var cy := to.y + 0.06
	var c := Vector2(to.x, to.z)
	var r := RADIUS * lerpf(0.35, 1.0, open)
	# 옅은 채움: 가운데는 거의 투명, 가장자리로 진해진다
	var rings := 8
	for i in rings:
		var r0 := r * float(i) / rings
		var r1 := r * float(i + 1) / rings
		var a := 0.04 + 0.2 * pow(float(i + 1) / rings, 2.5)
		_disc(im, c, r0, r1, Color(tc, a * open), 48, cy)
	# 스캔 부채꼴: 레이더처럼 돈다 (꼬리 쪽으로 옅어짐)
	var sweep := tt * 3.2
	for q in 10:
		var a0 := sweep - q * 0.09
		_wedge(im, c, r * 0.97, a0 - 0.09, a0, Color(tc, 0.16 * (1.0 - q / 10.0) * open), cy + 0.001)
	_line(im, c, c + Vector2.from_angle(sweep) * r, 0.04, Color(tc, 0.7 * open), cy + 0.002)
	# 바깥 장갑 링: 4분할, 천천히 회전 · 펼침 때 빠르게 돌다 잠긴다
	var rot := tt * lerpf(4.0, 0.5, lock)
	for q in 4:
		var a0 := rot + q * PI * 0.5 + 0.12
		_arc(im, c, r, a0, a0 + PI * 0.5 - 0.24, 0.14, Color(tc, 0.95 * open), 14, cy + 0.003)
		# 장갑 마디 끝의 작은 돌기
		for e in [a0, a0 + PI * 0.5 - 0.24]:
			var u := Vector2.from_angle(e)
			_line(im, c + u * (r - 0.16), c + u * (r + 0.16), 0.06, Color(tc, 0.95 * open), cy + 0.004)
	# 눈금 링 (바깥): 7.5° 마다, 45° 마다 길게
	var rr := r + 0.32
	_arc(im, c, rr, 0.0, TAU, 0.03, Color(tc, 0.5 * open), 64, cy + 0.003)
	for q in 48:
		var big := q % 6 == 0
		var u := Vector2.from_angle(q * TAU / 48.0 - rot * 0.25)
		_line(im, c + u * rr, c + u * (rr + (0.26 if big else 0.1)), 0.035 if big else 0.022, Color(tc, (0.9 if big else 0.45) * open), cy + 0.003)
	# 안쪽 역회전 링: 3분할
	var ri := r * 0.42
	for q in 3:
		var a0 := -tt * 1.6 + q * TAU / 3.0
		_arc(im, c, ri, a0, a0 + TAU / 3.0 - 0.5, 0.07, Color(tc, 0.75 * open), 12, cy + 0.004)
	_arc(im, c, r * 0.68, 0.0, TAU, 0.022, Color(tc, 0.35 * open), 48, cy + 0.004)
	# 십자선 (안쪽 링 밖 ~ 장갑 링 안)
	for q in 4:
		var u := Vector2.from_angle(q * PI * 0.5)
		_line(im, c + u * (ri + 0.18), c + u * (r - 0.3), 0.04, Color(tc, 0.6 * open * lock), cy + 0.004)
		_line(im, c + u * 0.12, c + u * 0.32, 0.05, Color(tc, 0.95 * open), cy + 0.005)
	# 가운데 마름모: 맥동
	var dm := 0.13 * (1.0 + 0.25 * sin(tt * 14.0))
	_quad(im, c + Vector2(0, -dm), c + Vector2(dm, 0), c + Vector2(0, dm), c + Vector2(-dm, 0), Color(tc, open), cy + 0.006)
	# 네 귀퉁이 꺾쇠: 바깥에서 조여 든다
	var gap := (1.0 - lock) * 1.2
	var bk := r + 0.55 + gap
	var bl := 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var k := c + Vector2(sx, sz) * bk * 0.7071
			_line(im, k, k + Vector2(-sx * bl, 0), 0.07, Color(tc, 0.95 * lock), cy + 0.005)
			_line(im, k, k + Vector2(0, -sz * bl), 0.07, Color(tc, 0.95 * lock), cy + 0.005)
	# 범위 안 적 발밑: 잠금 꺾쇠 (작은 삼각 마커 3개가 조여 듦)
	aim_count = 0
	for e in Enemy.live(p.get_tree()):
		var en := e as Enemy
		if not is_instance_valid(en) or not en.alive or not en.landed or en.prop:
			continue
		var d := Vector2(en.global_position.x, en.global_position.z) - c
		if d.length() > RADIUS + en.radius:
			continue
		aim_count += 1
		var ec := Vector2(en.global_position.x, en.global_position.z)
		var ey := en.global_position.y + 0.07
		var er := en.radius + 0.35 + 0.08 * sin(tt * 12.0)
		var hot := Color("ffffff").lerp(tc, 0.35)
		for q in 3:
			var ang := tt * 2.0 + q * TAU / 3.0
			var u := Vector2.from_angle(ang)
			var nn := Vector2(-u.y, u.x)
			_tri(im, ec + u * er, ec + u * (er + 0.3) + nn * 0.14, ec + u * (er + 0.3) - nn * 0.14, Color(hot, 0.95 * lock), ey)
		_arc(im, ec, er - 0.06, 0.0, TAU, 0.03, Color(hot, 0.5 * lock), 24, ey)
	# 발밑 사거리 원 (점선)
	var pc := Vector2(p.global_position.x, p.global_position.z)
	var py := p.gy + 0.05
	var seg := 64
	for q in seg:
		if q % 2 == 1:
			continue
		var a0 := q * TAU / seg + tt * 0.15
		_arc(im, pc, RANGE, a0, a0 + TAU / seg * 0.8, 0.03, Color(mc, 0.13 * open), 2, py)
	# 궤적: 실제 도약 포물선 위를 흐르는 점선
	_from = p.global_position
	_to = to
	var dd := Vector2(_to.x - _from.x, _to.z - _from.z).length()
	_apex = lerpf(APEX.x, APEX.y, clampf(dd / RANGE, 0.0, 1.0)) + maxf(_to.y - _from.y, 0.0)
	var n := maxi(int(dd / 0.28), 6)
	var flow := fmod(tt * 2.2, 1.0)
	var side := Vector3(_to.z - _from.z, 0, -(_to.x - _from.x)).normalized() if dd > 0.1 else Vector3.RIGHT
	for i in n:
		if (i + int(flow * 2.0)) % 2 == 1:
			continue
		var f0 := (float(i) + flow) / n
		var f1 := minf((float(i) + flow + 0.6) / n, 1.0)
		if f0 > open:
			break
		var a3 := _air_pos(f0)
		var b3 := _air_pos(f1)
		var fade := 0.35 + 0.6 * f0
		_ribbon(im, a3, b3, side, 0.06, Color(mc, fade))
	if open > 0.9 and dd > 1.0:
		# 착지점 쪽 화살촉 (떨어지는 방향)
		var tip := _air_pos(0.97)
		var back := _air_pos(0.9)
		var fw := (tip - back).normalized()
		var s2 := side * 0.22
		_tri3(im, tip + fw * 0.25, back + s2, back - s2, Color(tc, 0.95))
	im.surface_end()
	_from = p.global_position
	# 거리 · 상태 표시
	_label.visible = lock > 0.5
	_label.global_position = Vector3(to.x + r + 0.9, cy + 0.2, to.z - 0.4)
	var txt := "MAX %.1fm" % dd if aim_clamped else "%.1fm" % dd
	if aim_count > 0:
		txt += "  LOCK ×%d" % aim_count
	_label.text = txt
	_label.modulate = Color(tc.r, tc.g, tc.b, lock)


# ── 착지 자국: 바닥 금 + 옅어지는 링 ─────────────────────

func _mark(g: Vector3) -> void:
	var root := Node3D.new()
	FX.root.add_child(root)
	root.top_level = true
	var im := ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	mi.material_override = _material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	_marks.append([root, im, g, 0.0, randi()])
	while _marks.size() > 4:
		var old: Array = _marks.pop_front()
		if is_instance_valid(old[0]):
			(old[0] as Node).queue_free()


func _update_marks(dt: float) -> void:
	var i := 0
	while i < _marks.size():
		var m: Array = _marks[i]
		m[3] = float(m[3]) + dt
		var age: float = m[3]
		if age > 2.2 or not is_instance_valid(m[0]):
			if is_instance_valid(m[0]):
				(m[0] as Node).queue_free()
			_marks.remove_at(i)
			continue
		_draw_mark(m[1], m[2], age, m[4])
		i += 1


func _draw_mark(im: ImmediateMesh, g: Vector3, age: float, sd: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = sd
	var a := clampf(1.0 - (age - 0.6) / 1.6, 0.0, 1.0)
	var c := Vector2(g.x, g.z)
	var y := g.y + 0.02
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# 퍼지는 링 (처음 0.35초)
	var e := clampf(age / 0.35, 0.0, 1.0)
	if e < 1.0:
		_arc(im, c, RADIUS * lerpf(0.3, 1.05, BladeTech._out(e)), 0.0, TAU, lerpf(0.4, 0.05, e), Color(COL, 0.8 * (1.0 - e)), 48, y + 0.01)
	# 바닥 금: 가운데서 사방으로 갈라진 짙은 금 + 밝게 달아오른 속
	var grow := BladeTech._out(clampf(age / 0.12, 0.0, 1.0))
	for k in 9:
		var ang := k * TAU / 9.0 + rng.randf_range(-0.25, 0.25)
		var ln := RADIUS * rng.randf_range(0.45, 0.95) * grow
		var pt := c
		var segs := 4
		for s in segs:
			var nx := pt + Vector2.from_angle(ang + rng.randf_range(-0.35, 0.35)) * ln / segs
			var w := lerpf(0.13, 0.03, float(s) / segs)
			_line(im, pt, nx, w, Color(0.08, 0.07, 0.14, 0.75 * a), y)
			_line(im, pt, nx, w * 0.35, Color(COL.lerp(Color.WHITE, 0.4), 0.9 * a * clampf(1.0 - age / 0.9, 0.0, 1.0)), y + 0.003)
			pt = nx
	_disc(im, c, 0.0, 0.55, Color(0.08, 0.07, 0.14, 0.5 * a), 20, y)
	im.surface_end()


# ── 바닥 그리기 도우미 (월드 XZ, 높이 y) ───────────────

static func _quad(im: ImmediateMesh, a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color, y: float) -> void:
	im.surface_set_color(col)
	for v: Vector2 in [a, b, c, a, c, d]:
		im.surface_add_vertex(Vector3(v.x, y, v.y))


static func _tri(im: ImmediateMesh, a: Vector2, b: Vector2, c: Vector2, col: Color, y: float) -> void:
	im.surface_set_color(col)
	for v: Vector2 in [a, b, c]:
		im.surface_add_vertex(Vector3(v.x, y, v.y))


static func _tri3(im: ImmediateMesh, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	im.surface_set_color(col)
	for v: Vector3 in [a, b, c]:
		im.surface_add_vertex(v)


static func _line(im: ImmediateMesh, a: Vector2, b: Vector2, w: float, col: Color, y: float) -> void:
	var t := b - a
	if t.length() < 0.0001:
		return
	var nn := Vector2(-t.y, t.x).normalized() * w * 0.5
	_quad(im, a + nn, b + nn, b - nn, a - nn, col, y)


## 공중 점선 한 토막: 수평 폭을 가진 띠
static func _ribbon(im: ImmediateMesh, a: Vector3, b: Vector3, side: Vector3, w: float, col: Color) -> void:
	var s := side * w * 0.5
	im.surface_set_color(col)
	for v: Vector3 in [a + s, b + s, b - s, a + s, b - s, a - s]:
		im.surface_add_vertex(v)


static func _arc(im: ImmediateMesh, c: Vector2, r: float, a0: float, a1: float, w: float, col: Color, n: int, y: float) -> void:
	var r0 := r - w * 0.5
	var r1 := r + w * 0.5
	for i in n:
		var u0 := Vector2.from_angle(lerpf(a0, a1, float(i) / n))
		var u1 := Vector2.from_angle(lerpf(a0, a1, float(i + 1) / n))
		_quad(im, c + u0 * r0, c + u0 * r1, c + u1 * r1, c + u1 * r0, col, y)


static func _disc(im: ImmediateMesh, c: Vector2, r0: float, r1: float, col: Color, n: int, y: float) -> void:
	_arc(im, c, (r0 + r1) * 0.5, 0.0, TAU, r1 - r0, col, n, y)


static func _wedge(im: ImmediateMesh, c: Vector2, r: float, a0: float, a1: float, col: Color, y: float) -> void:
	_tri(im, c, c + Vector2.from_angle(a0) * r, c + Vector2.from_angle(a1) * r, col, y)


## 정리 (Player 가 사라질 때)
func free_all() -> void:
	_aim_end()
	for m in _marks:
		if is_instance_valid(m[0]):
			(m[0] as Node).queue_free()
	_marks.clear()
