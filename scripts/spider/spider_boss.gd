extends Enemy
## 거미 보스 SHIPWRIGHT (수선공 거미 기계): 바닥 · 벽 · 기둥을 가리지 않고 기어 다니며 벽의 구멍으로 숨었다 나타난다.
## 판정 몸통(이 노드)은 바닥 위 그림자 자리(보스 바로 아래, 벽에 붙어 있으면 벽 밑동)에 두고, 보이는 몸은 SpiderRig 이 따로 그린다.
## 숨어 있거나(구멍 속 · 기둥 위 어둠) 높이 올라가 있으면 맞지 않는다.
##
## 패턴 (1페이즈)
##   거미줄 포격  벽에 붙어 머리를 아래로 두고 거미줄 덩이를 포물선으로 뱉는다. 떨어진 자리는 감속 지대, 직격하면 묶인다.
##   매복 돌격    가까운 구멍으로 숨는다 → 다른 구멍들에서 눈빛이 번뜩이고 벽에서 부스러기가 떨어진다(가짜 단서도 있다)
##               → 진짜 구멍에서 눈이 켜지고 튀어나온다: 바닥 굴이면 돌진, 배관 구멍이면 도약해 내려찍는다(뒤에 약점)
##   기둥 사이 배회  기둥 뒤에서 기둥 뒤로 끊어 달리며 탐조등으로 훑고 가끔 거미줄을 뱉는다 → 갑자기 달려들어 다리 찌르기
##   산란         뒤 몸통을 들어 해치를 열고 새끼 거미를 던진다. 굴에서도 새끼가 몰려나온다 (해치가 열린 동안 약점)
##   천장 낙하    기둥을 타고 어둠 속으로 올라간다 → 플레이어 위로 실이 내려오고 그림자가 따라온다 → 실을 타고 떨어져 내려찍는다
##   기관포 소사  바닥에서 옆걸음질하며 턱 밑 개틀링으로 부채꼴 소사
## 2페이즈 (체력 50%): 비상등이 켜지고 더 빠르다 · 거미줄 그물(둘레를 가두는 포격) · 질주(지그재그 돌진 + 거미줄 자국) 추가
## 쓰러지면 벽에서 떨어져 다리를 오므리며 경련하다 폭발한다 (죽은 거미 자세).

signal phase_changed(phase: int)
signal defeated
signal revealed(at: Vector3, kind: String)     # 카메라 · 연출: 구멍에서 튀어나옴 · 낙하 · 등장

const Rig := preload("res://scripts/spider/spider_rig.gd")
const Stage := preload("res://scripts/spider/spider_stage.gd")
const WebShot := preload("res://scripts/spider/web_shot.gd")
const Brood := preload("res://scripts/spider/spiderling.gd")

enum St { ENTER, FIGHT, TRANSITION, DYING, DEAD }

const MAX_HP := 1300.0
const PHASE2_AT := 0.5
const PATTERNS_1 := ["web", "ambush", "stalk", "brood", "drop", "gatling"]
const PATTERNS_2 := ["web_net", "ambush", "skitter", "brood", "drop", "stalk", "gatling", "web"]
const NAMES := {
	"web": "거미줄 포격", "web_net": "거미줄 그물", "ambush": "매복 돌격", "stalk": "기둥 사이 배회", "brood": "산란",
	"drop": "천장 낙하", "gatling": "기관포 소사", "skitter": "질주",
}
const CYAN := Color(0.4, 0.95, 1.0)
const DANGER := Color(1.0, 0.22, 0.14)
const SLAM_R := 3.6
const STAB_R := 1.5

var stage: Stage
var bar: Node
var rig: Rig
var st := St.ENTER
var st_t := 0.0
var phase := 1
var boss_hp := MAX_HP
var skip_to_phase2 := false
var show_mode := false               # 확인 모드: 공격 없이 돌아다니기만
var pat := ""
var pat_i := -1
var order: Array = []
var pt := 0.0
var ps := {}
var rest := 2.0
var weak := false
var weak_t := 0.0
var weak_mult := 2.0
var flash_cd := 0.0
var hit_snd_cd := 0.0
var threats: Array = []

# 이동
var cur_c := Vector3.ZERO           # 몸 중심
var cur_n := Vector3.UP             # 붙은 면 법선
var loc: Dictionary = {}            # 마지막으로 도착한 자리
var dest: Dictionary = {}
var route: Array = []
var seg_from: Dictionary = {}
var move_speed := 7.0
var travel := Vector3.FORWARD
var face_to := Vector3.ZERO         # 서 있을 때 바라볼 점 (ZERO 면 플레이어)
var burst := false                  # 끊어 달리기 (멈칫 · 질주)
var _burst_t := 0.0
var _burst_go := true
var hidden := false
var look_up := 0.0                  # 카메라가 올려다볼 정도
var thread: MeshInstance3D          # 천장에서 내려오는 실
var thread_top := Vector3.ZERO
var _warns: Array = []
var _sight: MeshInstance3D          # 개틀링 조준선
var _fx_t := 0.0
var _snd_t := 0.0


func _ready() -> void:
	add_to_group("enemies")
	is_boss = true
	radius = 3.4
	slice_size = Vector3(5, 3, 6)
	slice_color = Rig.BLUE
	hp_bar_y = 99.0
	visual = Node3D.new()
	add_child(visual)
	j = {"body": visual, "core": null}
	shadow = FX.blob_shadow(self, 0.1, 0.0)
	shadow.visible = false
	landed = false
	rig = Rig.new()
	rig.stage = stage
	get_parent().add_child.call_deferred(rig)
	rig.foot_planted.connect(_on_foot)
	# 시작: 북쪽 벽 가운데 배관 구멍 속
	loc = Stage.hole_loc(4)
	cur_c = loc.c
	cur_n = loc.n
	rig.c = cur_c
	rig.up = cur_n
	rig.fwd = Stage.wall_n("N")
	seg_from = {"c": cur_c, "n": cur_n}
	hidden = true
	order = PATTERNS_1.duplicate()
	order.shuffle()
	var th := CylinderMesh.new()
	th.top_radius = 0.03
	th.bottom_radius = 0.03
	th.height = 1.0
	th.radial_segments = 4
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(0.85, 0.95, 1.0)
	tm.emission_enabled = true
	tm.emission = Color(0.8, 0.95, 1.0)
	tm.emission_energy_multiplier = 1.2
	thread = MeshInstance3D.new()
	thread.mesh = th
	thread.material_override = tm
	thread.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	thread.visible = false
	add_child(thread)
	var sb := BoxMesh.new()
	sb.size = Vector3(0.06, 0.06, 1.0)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1.0, 0.2, 0.15, 0.6)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.emission_enabled = true
	sm.emission = Color(1.0, 0.15, 0.1)
	sm.emission_energy_multiplier = 3.0
	_sight = MeshInstance3D.new()
	_sight.mesh = sb
	_sight.material_override = sm
	_sight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sight.visible = false
	add_child(_sight)


func _exit_tree() -> void:
	if is_instance_valid(rig):
		rig.queue_free()


# ── 이동 ────────────────────────────────────────────────

func go(to: Dictionary, spd: float) -> void:
	route = stage.route(loc, to)
	dest = to
	move_speed = spd
	seg_from = {"c": cur_c, "n": cur_n}


func arrived() -> bool:
	return route.is_empty()


## 순간 이동 (구멍 속 · 천장 어둠처럼 보이지 않는 곳에서만)
func warp(to: Dictionary) -> void:
	loc = to
	cur_c = to.c
	cur_n = to.n
	route.clear()
	seg_from = {"c": cur_c, "n": cur_n}
	rig.c = cur_c
	rig.up = cur_n
	rig.snap_feet()


func _move(dt: float) -> void:
	if route.is_empty():
		return
	var spd := move_speed
	if burst:
		# 진짜 거미처럼: 확 달렸다가 뚝 멈춘다
		_burst_t -= dt
		if _burst_t <= 0.0:
			_burst_go = not _burst_go
			_burst_t = randf_range(0.5, 1.1) if _burst_go else randf_range(0.18, 0.5)
		if not _burst_go:
			return
		spd *= 1.35
	var left := spd * dt
	while left > 0.0 and not route.is_empty():
		var tgt: Dictionary = route[0]
		var tc: Vector3 = tgt.c
		var d := tc - cur_c
		var l := d.length()
		if l > 0.001:
			travel = d / l
		if l <= left:
			cur_c = tc
			cur_n = tgt.n
			seg_from = tgt
			route.pop_front()
			left -= l
			if route.is_empty():
				loc = dest
		else:
			cur_c += d / l * left
			var seg_len := (seg_from.c as Vector3).distance_to(tc)
			var k := 1.0 - (l - left) / maxf(seg_len, 0.001)
			cur_n = (seg_from.n as Vector3).slerp(tgt.n, clampf(k, 0.0, 1.0)).normalized()
			left = 0.0


func _player() -> Player:
	return Main.inst.player


func _ppos() -> Vector3:
	var p := _player().global_position
	return Vector3(p.x, 0, p.z)


func on_floor() -> bool:
	return route.is_empty() and String(loc.get("s", "")) == "floor"


## 가장 가까운 구멍 (경로 길이)
func _near_hole(want_duct := -1) -> int:
	var best := 0
	var bl := INF
	for i in Stage.HOLES.size():
		if want_duct == 0 and Stage.is_duct(i):
			continue
		if want_duct == 1 and not Stage.is_duct(i):
			continue
		var l := Stage.route_len(cur_c, stage.route(loc, Stage.hole_loc(i)))
		if l < bl:
			bl = l
			best = i
	return best


## 플레이어에게서 적당히 떨어진 벽 자리
func _wall_spot(y: float) -> Dictionary:
	var pp := _ppos()
	var best: Dictionary = {}
	var bs := -INF
	for w in ["N", "E", "W"]:
		var uv := Stage.wall_uv(w, pp)
		var u := clampf(uv.x + randf_range(-6, 6), -Stage.wall_half(w) + 5.0, Stage.wall_half(w) - 5.0)
		var cand := Stage.wall_loc(w, u, y)
		var d := Vector2((cand.c as Vector3).x - pp.x, (cand.c as Vector3).z - pp.z).length()
		var s := -absf(d - 16.0) + randf() * 6.0
		# 정면(북쪽) 벽을 좋아한다. 플레이어가 붙어 선 벽은 피한다 (몸이 화면을 가리지 않게)
		if w == "N":
			s += 5.0
		if Stage.wall_uv(w, pp).y < 11.0:
			s -= 18.0
		# 구멍 입구에 몸이 걸치지 않게
		for i in Stage.HOLES.size():
			if Stage.in_opening(i, w, u, y, -3.0):
				s -= 20.0
		if s > bs:
			bs = s
			best = cand
	return best


# ── 매 프레임 ───────────────────────────────────────────

func _physics_process(dt: float) -> void:
	t += dt
	st_t += dt
	flash_cd -= dt
	hit_snd_cd -= dt
	threats.clear()
	if st == St.DEAD:
		return
	var player := _player()
	match st:
		St.ENTER:
			_update_enter(dt)
		St.FIGHT:
			_update_fight(dt, player)
		St.TRANSITION:
			_update_transition(dt)
		St.DYING:
			_update_dying(dt)
	if weak_t > 0.0:
		weak_t -= dt
		if weak_t <= 0.0:
			weak = false
	if st != St.DYING:
		_move(dt)
	_pose_rig(dt)
	_update_proxy()
	for w in _warns:
		if is_instance_valid(w.mi):
			threats.append({"type": "circle", "pos": w.pos, "r": w.r})


func _pose_rig(dt: float) -> void:
	if not rig.is_inside_tree():
		return
	rig.c = cur_c
	rig.up = cur_n
	var f := travel
	if route.is_empty() or (burst and not _burst_go):
		var at := face_to if face_to != Vector3.ZERO else _player().global_position
		f = at - cur_c
	f -= cur_n * f.dot(cur_n)
	if f.length() > 0.05:
		rig.fwd = rig.fwd.slerp(f.normalized(), 1.0 - exp(-5.0 * dt)) if rig.fwd.dot(f.normalized()) > -0.9 else f.normalized()
	rig.look_at_p = _player().global_position + Vector3(0, 1.0, 0)
	rig.update(dt)
	# 숨기: 구멍 깊숙이 들어가면 몸을 감춘다
	var hi := Stage.inside_hole(cur_c)
	var deep := false
	if hi >= 0:
		var uv := Stage.wall_uv(String((Stage.HOLES[hi] as Dictionary).wall), cur_c)
		deep = uv.y < -7.0
	hidden = deep or cur_c.y > 26.0
	rig.visible = not deep
	look_up = move_toward(look_up, clampf((cur_c.y - 6.0) / 14.0, 0.0, 1.0) if not hidden or cur_c.y > 26.0 else 0.0, dt * 1.5)
	# 실
	thread.visible = thread_top != Vector3.ZERO and st != St.DEAD
	if thread.visible:
		var bottom := rig.root.global_position + rig.root.global_basis.y * 1.2
		var mid := (thread_top + bottom) * 0.5
		thread.global_transform = Transform3D(Basis(), mid)
		thread.scale = Vector3(1, maxf(thread_top.distance_to(bottom), 0.1), 1)


## 판정 몸통: 보스 아래 바닥 (벽에 붙어 있으면 벽 밑동)
func _update_proxy() -> void:
	var c := cur_c
	var p := Vector3(clampf(c.x, -Stage.HX + 1.2, Stage.HX - 1.2), 0, clampf(c.z, -Stage.HZ + 1.2, Stage.HZ - 1.2))
	global_position = p
	var in_hall := absf(c.x) < Stage.HX + 0.5 and absf(c.z) < Stage.HZ + 0.5
	landed = alive and not hidden and in_hall and c.y < 9.0 and (st == St.FIGHT or st == St.TRANSITION) and not show_mode
	radius = 3.4 if cur_n.y > 0.7 else 2.6


func fx_point(_pos: Vector3, fwd: Vector3) -> Vector3:
	var c := rig.root.global_position
	return c - Vector3(fwd.x, 0, fwd.z).normalized() * 2.0 + Vector3(0, randf_range(-0.5, 0.8), 0)


func focus_point() -> Vector3:
	return rig.root.global_position if is_instance_valid(rig) and rig.is_inside_tree() else cur_c


func _on_foot(p: Vector3, n: Vector3, _leg: int, hard: float) -> void:
	var pl := _player()
	var d := p.distance_to(pl.global_position)
	if n.y > 0.7:
		if randf() < 0.7:
			stage.dust(p + Vector3(0, 0.3, 0), randf_range(1.2, 2.0) * (0.6 + hard), Color(0.3, 0.29, 0.28, 0.28), Vector3(0, 0.6, 0), 1.2)
	else:
		if randf() < 0.4:
			FX.sparks(p + n * 0.3, 3, [Color(0.4, 0.38, 0.36), Color(0.22, 0.22, 0.23)], 2.0, 0.6, -12.0, 0.06)
	if d < 26.0 and not hidden:
		var s := Sfx.play("land", 0.25, lerpf(-6.0, -20.0, d / 26.0))
		if s:
			s.pitch_scale = randf_range(0.5, 0.7)
		if d < 12.0 and hard > 0.5:
			Main.inst.shake(0.05 * hard)


# ── 등장 ────────────────────────────────────────────────

func _update_enter(dt: float) -> void:
	face_to = _ppos()
	if not ps.has("eyes"):
		ps.eyes = true
		stage.hole_eyes(4, 1.0)
		Sfx.play("twind", 0.0, -8.0)
	if st_t > 1.6 and not ps.has("out"):
		ps.out = true
		stage.hole_eyes(4, 0.0)
		go(Stage.wall_loc("N", 0.0, 7.0), 6.0)
		revealed.emit(Stage.hole_center(4), "enter")
		Main.inst.shake(0.25)
		stage.wall_trickle("N", 0.0, 10.5)
	if ps.has("out") and arrived() and not ps.has("roar"):
		ps.roar = true
		ps.roar_t = st_t
		Sfx.play("overload", 0.0, -3.0)
		Sfx.play("boom", 0.0, -6.0)
		Main.inst.shake(0.5)
		Main.inst.hud.banner("WARNING", Color("ff4a3a"), "SHIPWRIGHT · 수선공 거미 — 갱도의 주인이 내려온다")
		AbyssFX.light_flash(cur_c + Vector3(0, 0, 4), CYAN, 10.0, 30.0, 1.0)
	if ps.has("roar"):
		var k := clampf((st_t - float(ps.roar_t)) / 1.8, 0.0, 1.0)
		rig.rear = sin(k * PI) * 0.8
		rig.abd_raise = sin(k * PI) * 0.5
		_threat_legs(sin(k * PI))
		if k >= 1.0 and not ps.has("down"):
			ps.down = true
			_threat_legs(0.0)
			go(Stage.floor_loc(Vector3(0, 0, -10)), 9.0)
		if ps.has("down") and arrived():
			st = St.FIGHT
			st_t = 0.0
			ps.clear()
			rest = 0.8
			if is_instance_valid(bar):
				bar.set("threshold", PHASE2_AT)
				bar.call("set_phase", 1)
			if skip_to_phase2:
				boss_hp = MAX_HP * PHASE2_AT
				bar.call("set_hp", PHASE2_AT)
				_begin_transition()


## 위협 자세: 앞다리 둘을 높이 들고 공구 팔을 벌린다 (k 0~1)
func _threat_legs(k: float) -> void:
	var xf := rig.body_xf()
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		rig.set_leg_goal(i, xf * Vector3(s * 3.6, 3.4, -4.2), k, xf.basis.z)
	for i in 4:
		var s := -1.0 if i < 2 else 1.0
		rig.set_arm_goal(i, xf * Vector3(s * (1.6 + (i % 2) * 0.6), 0.6, -4.0), k * 0.8)


# ── 전투 ────────────────────────────────────────────────

func _update_fight(dt: float, player: Player) -> void:
	if pat == "":
		face_to = Vector3.ZERO
		rest -= dt
		if rest <= 0.0 and arrived() and player.alive and Main.inst.state == Main.State.PLAY:
			_next_pattern()
		return
	pt += dt
	var done := false
	match pat:
		"web": done = _p_web(dt, 3 if phase == 1 else 4, false)
		"web_net": done = _p_web(dt, 2, true)
		"ambush": done = _p_ambush(dt)
		"stalk": done = _p_stalk(dt)
		"brood": done = _p_brood(dt)
		"drop": done = _p_drop(dt)
		"gatling": done = _p_gatling(dt)
		"skitter": done = _p_skitter(dt)
		"show": done = _p_show(dt)
	if done:
		_end_pattern()


func _next_pattern() -> void:
	if show_mode:
		pat = "show"
		pt = 0.0
		ps = {}
		return
	var list: Array = PATTERNS_1 if phase == 1 else PATTERNS_2
	pat_i += 1
	if pat_i >= order.size():
		pat_i = 0
		order = list.duplicate()
		order.shuffle()
	pat = order[pat_i]
	if pat == "brood" and _brood_alive() > 5:
		pat = "web" if phase == 1 else "web_net"
	if pat == "gatling" and String(loc.get("s", "")) != "floor" and randf() < 0.3:
		pat = "web"
	pt = 0.0
	ps = {"step": 0}
	if is_instance_valid(bar):
		bar.call("set_pattern", NAMES.get(pat, pat))
	print("SPIDER_PATTERN %s t=%.1f hp=%.0f loc=%s" % [pat, Main.inst.time, boss_hp, loc.get("s", "?")])


func _end_pattern() -> void:
	pat = ""
	ps = {}
	burst = false
	rest = randf_range(0.9, 1.5) if phase == 1 else randf_range(0.5, 0.9)
	_clear_warns()
	_release_pose()
	thread_top = Vector3.ZERO


func _release_pose() -> void:
	rig.rear = 0.0
	rig.crouch = 0.0
	rig.abd_raise = 0.0
	rig.hatch_open = 0.0
	rig.eye_k = 1.0
	rig.light_k = 1.0
	rig.torch_k = 0.0
	rig.mouth_k = 0.0
	rig.gat_spin = 0.0
	rig.stride_k = 1.0
	_sight.visible = false
	for i in 4:
		rig.set_leg_goal(i, Vector3.ZERO, 0.0)
		rig.set_arm_goal(i, Vector3.ZERO, 0.0)


func _brood_alive() -> int:
	var n := 0
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e as Enemy).is_boss:
			n += 1
	return n


func _step() -> int:
	return int(ps.get("step", 0))


func _next(s := -1) -> void:
	ps.step = (_step() + 1) if s < 0 else s
	ps.t0 = pt


func _since() -> float:
	return pt - float(ps.get("t0", 0.0))


# ── 패턴: 거미줄 포격 / 그물 ────────────────────────────

func _p_web(dt: float, volleys: int, net: bool) -> bool:
	match _step():
		0:
			# 벽에 있고 너무 멀지 않으면 그 자리에서, 아니면 가까운 벽으로 기어간다
			var here := String(loc.get("s", ""))
			var d := Vector2(cur_c.x - _ppos().x, cur_c.z - _ppos().z).length()
			if here == "wall" and d < 26.0 and cur_c.y > 3.0:
				_next(2)
			else:
				go(_wall_spot(randf_range(5.5, 8.5)), 10.0 if phase == 1 else 13.0)
				_next(1)
		1:
			if arrived():
				_next(2)
		2:
			face_to = _ppos()
			var cyc := 1.25 if not net else 1.6
			var vi := int(_since() / cyc)
			if vi >= volleys:
				rig.mouth_k = move_toward(rig.mouth_k, 0.0, dt * 4.0)
				return _since() > volleys * cyc + 0.4
			var lt := _since() - vi * cyc
			var wind := 0.55
			if lt < wind:
				# 준비: 머리를 젖히고 입이 하얗게 달아오른다
				var k := lt / wind
				rig.mouth_k = k
				rig.abd_raise = k * 0.3
				rig.rear = k * 0.15
				if int(ps.get("snd", -1)) != vi:
					ps.snd = vi
					Sfx.play("echarge", 0.15, -10.0)
			elif int(ps.get("fired", -1)) != vi:
				ps.fired = vi
				rig.mouth_k = 0.2
				rig.rear = 0.0
				rig.abd_raise = 0.0
				rig._bob_v += 2.0
				_spit_volley(net, vi)
	return false


func _spit_volley(net: bool, vi: int) -> void:
	var from := rig.mouth_pos()
	var pl := _player()
	var aim := _ppos() + Vector3(pl.velocity.x, 0, pl.velocity.z) * 0.55
	Sfx.play("launch", 0.1, -6.0)
	Main.inst.shake(0.12)
	FX.flash(from, Color(0.9, 1.0, 1.0), 1.0, 0.08)
	var targets: Array = []
	if net:
		# 그물: 플레이어 둘레 고리 + 한가운데 하나
		var n := 7 if phase == 1 else 9
		var off := randf() * TAU
		for k in n:
			var a := off + TAU * k / n
			targets.append(aim + Vector3(cos(a), 0, sin(a)) * (4.6 + (vi % 2) * 1.2))
		targets.append(aim)
	else:
		var n := 3 if phase == 1 else 5
		for k in n:
			var spread := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * (0.0 if k == 0 else 3.4)
			targets.append(aim + spread)
	for k in targets.size():
		var tgt: Vector3 = stage.push_out(targets[k], 0.5)
		var dist := Vector2(tgt.x - from.x, tgt.z - from.z).length()
		var fl := clampf(0.55 + dist * 0.028, 0.6, 1.3) + k * 0.04
		var h := clampf(2.0 + dist * 0.12, 2.0, 5.5)
		var w := WebShot.make_web(from, tgt, fl, h, 2.0 if net else 2.3)
		Main.inst.add_bullet(w)


# ── 패턴: 매복 돌격 ─────────────────────────────────────

func _p_ambush(dt: float) -> bool:
	match _step():
		0:
			if String(loc.get("s", "")) == "duct" or String(loc.get("s", "")) == "tunnel":
				_next(2)
			else:
				go(Stage.hole_loc(_near_hole()), 13.0 if phase == 1 else 16.0)
				burst = phase == 2
				_next(1)
		1:
			if arrived():
				burst = false
				_next(2)
		2:
			# 숨어서 이동: 다른 구멍들에서 가짜 눈빛 · 벽 속 부스러기
			if not ps.has("hide"):
				ps.hide = randf_range(1.6, 2.6) if phase == 1 else randf_range(1.0, 1.8)
				ps.fake = randi() % Stage.HOLES.size()
				Sfx.play("roll", 0.1, -8.0)
			var e := _since()
			var fake: int = ps.fake
			stage.hole_eyes(fake, 1.0 if e > 0.3 and e < 0.9 else 0.0)
			_fx_t -= dt
			if _fx_t <= 0.0:
				_fx_t = randf_range(0.35, 0.7)
				var w: String = ["N", "E", "W"][randi() % 3]
				stage.wall_trickle(w, randf_range(-Stage.wall_half(w) + 3, Stage.wall_half(w) - 3), randf_range(3, 12))
				var s := Sfx.play("land", 0.3, -14.0)
				if s:
					s.pitch_scale = 0.4
			if e > float(ps.hide):
				stage.hole_eyes(fake, 0.0)
				# 나올 구멍: 플레이어에게서 10~30m
				var cands: Array = []
				for i in Stage.HOLES.size():
					var hc := Stage.hole_center(i)
					var d := Vector2(hc.x - _ppos().x, hc.z - _ppos().z).length()
					if d > 10.0 and d < 32.0 and i != int(loc.get("i", -1)):
						cands.append(i)
				if cands.is_empty():
					cands = [randi() % Stage.HOLES.size()]
				var h: int = cands[randi() % cands.size()]
				ps.hole = h
				warp(Stage.hole_loc(h, 5.0))
				stage.hole_eyes(h, 1.0)
				Sfx.play("pwarn", 0.05, -6.0)
				_next(3)
		3:
			var h: int = ps.hole
			if _since() > (0.85 if phase == 1 else 0.6):
				stage.hole_eyes(h, 0.0)
				revealed.emit(Stage.hole_center(h), "burst")
				Main.inst.shake(0.35)
				Sfx.play("boom", 0.1, -5.0)
				stage.wall_trickle(String((Stage.HOLES[h] as Dictionary).wall), float((Stage.HOLES[h] as Dictionary).u), float((Stage.HOLES[h] as Dictionary).y) + 6.0)
				go(Stage.hole_mouth(h), 18.0)
				_next(4)
		4:
			if arrived():
				var h: int = ps.hole
				if Stage.is_duct(h):
					_next(10)        # 도약
				else:
					_next(20)        # 돌진
		10:
			return _leap(dt)
		20:
			return _charge(dt)
	return false


## 벽에서 플레이어에게 도약해 내려찍기: 웅크림(예고) → 포물선 → 착지 충격 → 약점
func _leap(dt: float) -> bool:
	var e := _since()
	var wind := 0.6 if phase == 1 else 0.45
	if not ps.has("tgt"):
		var tg := stage.push_out(_ppos() + _player().velocity * 0.25, 3.0)
		ps.tgt = tg
		ps.from = cur_c
		_warn_at(tg, SLAM_R)
		Sfx.play("twind", 0.05, -6.0)
	var tgt: Vector3 = ps.tgt
	face_to = tgt
	if e < wind:
		rig.crouch = e / wind
		_set_warns(e / (wind + 0.65))
		return false
	var fl := 0.65
	var k := clampf((e - wind) / fl, 0.0, 1.0)
	var from: Vector3 = ps.from
	var to := Vector3(tgt.x, Stage.RIDE, tgt.z)
	var p := from.lerp(to, k)
	p.y = lerpf(from.y, to.y, k) + sin(k * PI) * 4.5
	cur_c = p
	cur_n = (ps.get("n0", cur_n) as Vector3).slerp(Vector3.UP, smoothstep(0.0, 0.6, k)).normalized()
	if not ps.has("n0"):
		ps.n0 = cur_n
		rig.crouch = 0.0
		Sfx.play("launch", 0.0, -2.0)
	_set_warns((e) / (wind + fl))
	route.clear()
	travel = (to - from).normalized()
	# 공중: 다리를 앞으로 벌린다
	var xf := rig.body_xf()
	for i in 4:
		var r: Vector3 = Rig.RESTS[i]
		rig.set_leg_goal(i, xf * Vector3(r.x * 0.8, -0.6 + (1.0 if i < 2 else -0.3), r.z * 0.9), 1.0 - k * k * 0.3, xf.basis.y)
	if k >= 1.0 and not ps.has("hit"):
		ps.hit = true
		loc = Stage.floor_loc(to)
		seg_from = {"c": cur_c, "n": cur_n}
		for i in 4:
			rig.set_leg_goal(i, Vector3.ZERO, 0.0)
		rig.snap_feet()
		rig._bob_v -= 9.0
		_slam(to, SLAM_R, 12)
		_clear_warns()
		weak = true
		weak_t = 1.8
		weak_mult = 2.0
	if ps.has("hit"):
		rig.crouch = clampf(1.0 - (e - wind - fl) / 0.6, 0.0, 1.0) * 0.7
		rig.eye_k = 0.6 + 0.4 * absf(sin(t * 18.0))
		if e > wind + fl + 1.6:
			return _stab(dt, "stab") if _ppos().distance_to(Vector3(cur_c.x, 0, cur_c.z)) < 8.0 else true
	return false


## 바닥 굴에서 튀어나와 직선 돌진
func _charge(dt: float) -> bool:
	var e := _since()
	if not ps.has("dir"):
		var d := _ppos() - Vector3(cur_c.x, 0, cur_c.z)
		ps.dir = d.normalized()
		ps.len = clampf(d.length() + 5.0, 8.0, 26.0)
		ps.o = Vector3(cur_c.x, 0, cur_c.z)
		ps.hit = false
		Sfx.play("rev", 0.0, -4.0)
	var dir: Vector3 = ps.dir
	var o: Vector3 = ps.o
	face_to = cur_c + dir * 10.0
	var wind := 0.45
	threats.append({"type": "beam", "origin": o, "a": atan2(dir.z, dir.x), "a1": atan2(dir.z, dir.x), "half": 2.4, "len": float(ps.len), "sweep": false})
	if e < wind:
		rig.crouch = e / wind * 0.8
		return false
	rig.crouch = 0.0
	var spd := 20.0 if phase == 1 else 24.0
	var gone := (e - wind) * spd
	if gone < float(ps.len):
		var p := o + dir * gone
		var q := stage.push_out(p, 3.0)
		cur_c = Vector3(q.x, Stage.RIDE, q.z)
		travel = dir
		route.clear()
		rig.stride_k = 1.4
		var pl := _player()
		if not bool(ps.hit) and pl.alive and Vector2(pl.global_position.x - cur_c.x, pl.global_position.z - cur_c.z).length() < 2.6 + pl.hit_radius:
			ps.hit = true
			if pl.take_hit(cur_c):
				pl.shove(Vector3(-dir.z, 0, dir.x) * signf(Vector3(-dir.z, 0, dir.x).dot(pl.global_position - cur_c) + 0.001), 14.0)
		if randf() < 0.5:
			stage.dust(Vector3(cur_c.x, 0.3, cur_c.z) - dir * 3.0, 2.0, Color(0.3, 0.29, 0.28, 0.3), -dir * 2.0, 1.0)
		return false
	if not ps.has("stop"):
		ps.stop = e
		loc = Stage.floor_loc(cur_c)
		seg_from = {"c": cur_c, "n": cur_n}
		Main.inst.shake(0.3)
		for k in 6:
			stage.dust(Vector3(cur_c.x, 0.3, cur_c.z) + dir * 2.0 + Vector3(randf_range(-2, 2), 0, randf_range(-2, 2)), 2.4, Color(0.3, 0.29, 0.28, 0.35), dir * 3.0, 1.3)
		rig._lean_v += Vector3(-2.5, 0, 0)
	rig.stride_k = 1.0
	if e - float(ps.stop) > 0.4:
		return _stab(dt, "stab") if _ppos().distance_to(Vector3(cur_c.x, 0, cur_c.z)) < 8.0 else e - float(ps.stop) > 0.8
	return false


# ── 다리 찌르기 (여러 패턴이 끝에 이어 쓴다) ─────────────

func _stab(dt: float, key: String) -> bool:
	var s: Dictionary = ps.get(key, {})
	if s.is_empty():
		s = {"t": 0.0, "i": 0, "n": 3 if phase == 1 else 5}
		ps[key] = s
		Sfx.play("overload", 0.1, -6.0)
	s.t = float(s.t) + dt
	var tt: float = s.t
	face_to = _ppos()
	var rear_t := 0.6
	var per := 0.5 if phase == 1 else 0.4
	var n: int = s.n
	if tt < rear_t:
		var k := tt / rear_t
		rig.rear = k
		_threat_legs(k)
		return false
	var si := int((tt - rear_t) / per)
	if si >= n:
		var k := clampf((tt - rear_t - n * per) / 0.5, 0.0, 1.0)
		rig.rear = 1.0 - k
		_threat_legs(1.0 - k)
		if k >= 1.0:
			_threat_legs(0.0)
			return true
		return false
	var lt := tt - rear_t - si * per
	var leg := si % 2
	var xf := rig.body_xf()
	if int(s.i) != si or not s.has("tgt"):
		s.i = si
		var tg := _ppos() + _player().velocity * 0.18
		# 다리가 닿는 곳까지만
		var hip := xf * (Rig.HIPS[leg] as Vector3)
		var flat := tg - Vector3(hip.x, 0, hip.z)
		if flat.length() > 6.5:
			tg = Vector3(hip.x, 0, hip.z) + flat.normalized() * 6.5
		s.tgt = stage.push_out(tg, 0.3)
		s.hit = false
		s.w = _warn_at(s.tgt, STAB_R)
	var tgt: Vector3 = s.tgt
	var raise := per * 0.62
	rig.rear = 0.75
	var other := 1 - leg
	rig.set_leg_goal(other, xf * Vector3((-1.0 if other == 0 else 1.0) * 3.4, 3.2, -4.0), 1.0, xf.basis.z)
	if lt < raise:
		var k := lt / raise
		_set_warn_at(s.w, k)
		rig.set_leg_goal(leg, tgt + Vector3(0, 4.2 - k * 0.6, 0) + (Vector3(cur_c.x, 0, cur_c.z) - tgt).normalized() * 1.5, 1.0, Vector3.UP)
	else:
		rig.set_leg_goal(leg, tgt, 1.0, Vector3.UP)
		if not bool(s.hit):
			s.hit = true
			_remove_warn_at(s.w)
			var pl := _player()
			if pl.alive and Vector2(pl.global_position.x - tgt.x, pl.global_position.z - tgt.z).length() < STAB_R + pl.hit_radius:
				pl.take_hit(tgt)
			Main.inst.shake(0.3)
			Main.inst.hitstop(0.03)
			FX.sparks(tgt + Vector3(0, 0.2, 0), 16, [Color.WHITE, Color(1.0, 0.7, 0.3), Color(0.4, 0.4, 0.42)], 9.0, 0.4, -16.0, 0.07)
			FX.shockwave(tgt + Vector3(0, 0.06, 0), Color(1.0, 0.5, 0.3), STAB_R * 2.2, 0.25, 0.08)
			stage.dust(tgt + Vector3(0, 0.3, 0), 2.2, Color(0.32, 0.3, 0.29, 0.35), Vector3(0, 1.0, 0), 1.0)
			Sfx.play("clank", 0.1, -2.0)
	return false


# ── 패턴: 기둥 사이 배회 ────────────────────────────────

## 플레이어에게서 보아 기둥 뒤쪽 자리
func _behind_pillar(skip := -1) -> Array:
	var pp := _ppos()
	var cands: Array = []
	for i in Stage.PILLARS.size():
		if i == skip:
			continue
		var c := Stage.pillar_pos(i)
		var away := c - pp
		away.y = 0
		var d := away.length()
		if d < 7.0 or d > 30.0:
			continue
		var q := c + away / d * (Stage.pillar_r(i) + 4.6)
		if absf(q.x) > Stage.HX - 5.0 or absf(q.z) > Stage.HZ - 5.0:
			continue
		cands.append([i, q, absf(d - 16.0) + randf() * 8.0])
	cands.sort_custom(func(a, b): return float(a[2]) < float(b[2]))
	if cands.is_empty():
		return [-1, stage.random_floor(pp, 12.0, 24.0)]
	return [cands[0][0], cands[0][1]]


func _p_stalk(dt: float) -> bool:
	match _step():
		0:
			var b := _behind_pillar()
			ps.pillar = b[0]
			go(Stage.floor_loc(b[1]), 11.0)
			burst = true
			_next(1)
		1:
			# 기둥 뒤에서 기둥 뒤로 끊어 달린다. 탐조등은 켠 채, 눈빛은 반쯤 죽인다.
			rig.eye_k = move_toward(rig.eye_k, 0.45, dt)
			rig.light_k = 1.0
			if not ps.has("spit"):
				ps.spit = 1.4
			ps.spit = float(ps.spit) - dt
			if float(ps.spit) <= 0.0 and on_floor():
				ps.spit = randf_range(1.4, 2.2)
				_spit_one()
			if arrived():
				var dur := 6.5 if phase == 1 else 4.8
				if _since() > dur:
					burst = false
					rig.eye_k = 1.0
					Sfx.play("overload", 0.05, -5.0)
					_next(2)
				else:
					var b := _behind_pillar(int(ps.get("pillar", -1)))
					ps.pillar = b[0]
					go(Stage.floor_loc(b[1]), 11.0)
		2:
			# 기습: 곧장 달려든다
			if not ps.has("rush"):
				ps.rush = true
				var tg := _ppos() + (Vector3(cur_c.x, 0, cur_c.z) - _ppos()).normalized() * 5.5
				go(Stage.floor_loc(stage.push_out(tg, 3.0)), 17.0 if phase == 1 else 20.0)
				rig.stride_k = 1.3
			if arrived() or _ppos().distance_to(Vector3(cur_c.x, 0, cur_c.z)) < 6.0:
				route.clear()
				loc = Stage.floor_loc(cur_c)
				seg_from = {"c": cur_c, "n": cur_n}
				rig.stride_k = 1.0
				_next(3)
		3:
			return _stab(dt, "stab")
	return false


func _spit_one() -> void:
	var from := rig.mouth_pos()
	var aim := _ppos() + _player().velocity * 0.5
	var dist := Vector2(aim.x - from.x, aim.z - from.z).length()
	Main.inst.add_bullet(WebShot.make_web(from, stage.push_out(aim, 0.5), clampf(0.55 + dist * 0.03, 0.6, 1.2), clampf(2.0 + dist * 0.1, 2.0, 4.5), 2.2))
	Sfx.play("launch", 0.15, -9.0)
	rig._bob_v += 1.5


# ── 패턴: 산란 ──────────────────────────────────────────

func _p_brood(dt: float) -> bool:
	match _step():
		0:
			var s := String(loc.get("s", ""))
			if s == "duct" or s == "tunnel":
				go(_wall_spot(6.5) if randf() < 0.5 else Stage.floor_loc(stage.random_floor(_ppos(), 10.0, 20.0)), 12.0)
				_next(1)
			else:
				_next(2)
		1:
			if arrived():
				_next(2)
		2:
			var e := _since()
			var open_t := 0.7
			face_to = _ppos()
			rig.abd_raise = clampf(e / open_t, 0.0, 1.0)
			rig.hatch_open = clampf((e - 0.3) / open_t, 0.0, 1.0)
			weak = true
			weak_t = 0.3
			weak_mult = 1.6
			if e > 0.3 and not ps.has("snd"):
				ps.snd = true
				Sfx.play("unfold", 0.0, -2.0)
				Sfx.play("overload", 0.2, -8.0)
			var n := 4 if phase == 1 else 6
			var shot := int(maxf(0.0, e - 0.9) / 0.2)
			while int(ps.get("thrown", 0)) < mini(shot, n):
				ps.thrown = int(ps.get("thrown", 0)) + 1
				_throw_brood()
			if e > 1.0 and not ps.has("tun"):
				ps.tun = true
				var tunnels: Array = []
				for i in Stage.HOLES.size():
					if not Stage.is_duct(i):
						tunnels.append(i)
				tunnels.shuffle()
				for k in (1 if phase == 1 else 2):
					_tunnel_brood(tunnels[k], 2 + phase)
			if e > 0.9 + n * 0.2 + 0.6:
				_next(3)
		3:
			var k := clampf(_since() / 0.6, 0.0, 1.0)
			rig.abd_raise = 1.0 - k
			rig.hatch_open = 1.0 - k
			return k >= 1.0
	return false


func _throw_brood() -> void:
	var b: Enemy = Brood.new()
	b.set("spawn_mode", "thrown")
	var from := rig.hatch_pos()
	b.set("from_p", from)
	var a := randf() * TAU
	var tg := stage.push_out(_ppos() + Vector3(cos(a), 0, sin(a)) * randf_range(3.5, 7.5), 0.6)
	b.set("to_p", tg)
	b.set("fly_t", randf_range(0.6, 0.85))
	Main.inst.world.add_child(b)
	FX.flash(from, Color(1.0, 0.6, 0.3), 0.7, 0.06)
	Sfx.play("launch", 0.2, -12.0)


func _tunnel_brood(h: int, n: int) -> void:
	var hd: Dictionary = Stage.HOLES[h]
	var wn := Stage.wall_n(hd.wall)
	stage.hole_eyes(h, 0.6)
	get_tree().create_timer(1.2, false).timeout.connect(func(): stage.hole_eyes(h, 0.0))
	for k in n:
		get_tree().create_timer(0.25 + k * 0.22, false).timeout.connect(func():
			if Main.inst.state != Main.State.PLAY:
				return
			var b: Enemy = Brood.new()
			b.set("spawn_mode", "tunnel")
			var side := Vector3(wn.z, 0, -wn.x) * randf_range(-3.0, 3.0)
			b.set("from_p", Stage.wall_point(hd.wall, hd.u, 0.0) - wn * 5.0 + side)
			b.set("to_p", Stage.wall_point(hd.wall, hd.u, 0.0) + wn * randf_range(3.0, 6.0) + side * 1.4)
			Main.inst.world.add_child(b))


# ── 패턴: 천장 낙하 ─────────────────────────────────────

func _p_drop(dt: float) -> bool:
	match _step():
		0:
			# 가까운 기둥 (플레이어 쪽 면)으로
			var best := 0
			var bl := INF
			for i in Stage.PILLARS.size():
				var l := Vector2(Stage.pillar_pos(i).x - cur_c.x, Stage.pillar_pos(i).z - cur_c.z).length()
				if l < bl:
					bl = l
					best = i
			var c := Stage.pillar_pos(best)
			var ang := atan2(cur_c.z - c.z, cur_c.x - c.x)
			ps.p = best
			ps.ang = ang
			go(Stage.pillar_loc(best, 7.0, ang), 12.0)
			_next(1)
		1:
			if arrived():
				go(Stage.pillar_loc(int(ps.p), 36.0, float(ps.ang)), 15.0)
				Sfx.play("roll", 0.1, -6.0)
				_next(2)
		2:
			if arrived() or cur_c.y > 30.0:
				route.clear()
				_next(3)
		3:
			# 어둠 속: 플레이어 위로 실을 내리고, 그림자가 따라온다
			var e := _since()
			if not ps.has("top"):
				var pp := _ppos()
				warp({"s": "air", "c": Vector3(pp.x, 34.0, pp.z), "n": Vector3.UP})
				ps.top = true
				thread_top = Vector3(pp.x, 120.0, pp.z)
				ps.w = _warn_at(pp, SLAM_R)
				Sfx.play("twind", 0.05, -4.0)
				revealed.emit(pp + Vector3(0, 16, 0), "drop")
			var track := 1.4 if phase == 1 else 1.0
			var pp2 := _ppos()
			var pos: Vector3 = cur_c
			if e < track:
				var tgt := Vector3(pp2.x, 0, pp2.z)
				pos = pos.lerp(Vector3(tgt.x, pos.y, tgt.z), 1.0 - exp(-5.0 * dt))
				pos.y = lerpf(34.0, 13.0, smoothstep(0.0, 1.0, e / track))
				ps.lock = Vector3(pos.x, 0, pos.z)
			elif e < track + 0.35:
				# 멈칫: 다리를 잔뜩 오므린다
				rig.twitch = 0.6
			else:
				rig.twitch = 0.0
				var k := clampf((e - track - 0.35) / 0.26, 0.0, 1.0)
				pos.y = lerpf(13.0, Stage.RIDE, k * k)
			cur_c = Vector3(pos.x, pos.y, pos.z)
			cur_n = Vector3.UP
			seg_from = {"c": cur_c, "n": cur_n}
			thread_top = Vector3(cur_c.x, 120.0, cur_c.z)
			var lk: Vector3 = ps.get("lock", pp2)
			_move_warn_at(ps.w, lk)
			_set_warn_at(ps.w, clampf(e / (track + 0.6), 0.0, 1.0))
			rig.curl = 0.55 if pos.y > Stage.RIDE + 0.6 else 0.0
			look_up = 1.0
			if pos.y <= Stage.RIDE + 0.01 and not ps.has("hit"):
				ps.hit = true
				rig.curl = 0.0
				loc = Stage.floor_loc(cur_c)
				rig.snap_feet()
				rig._bob_v -= 12.0
				_remove_warn_at(ps.w)
				_slam(Vector3(cur_c.x, 0, cur_c.z), SLAM_R, 14)
				stage.add_web(Vector3(cur_c.x, 0, cur_c.z), 4.5, 7.0)
				weak = true
				weak_t = 2.0
				weak_mult = 2.0
				_next(4)
		4:
			rig.crouch = clampf(1.0 - _since() / 0.8, 0.0, 1.0) * 0.8
			rig.eye_k = 0.6 + 0.4 * absf(sin(t * 18.0))
			if _since() > 0.5:
				thread_top = Vector3.ZERO
			if _since() > 1.9:
				return true
	return false


# ── 패턴: 기관포 소사 ───────────────────────────────────

func _p_gatling(dt: float) -> bool:
	match _step():
		0:
			if String(loc.get("s", "")) != "floor":
				go(Stage.floor_loc(stage.random_floor(_ppos(), 11.0, 20.0)), 12.0)
				_next(1)
			else:
				_next(2)
		1:
			if arrived():
				_next(2)
		2:
			var e := _since()
			face_to = _ppos()
			var wind := 0.9
			rig.gat_spin = lerpf(0.0, 40.0, clampf(e / wind, 0.0, 1.0))
			if not ps.has("snd"):
				ps.snd = true
				Sfx.play("rev", 0.0, -3.0)
			# 조준선
			_sight.visible = e < wind
			if _sight.visible:
				var m := rig.gun_muzzle()
				var d := _ppos() + Vector3(0, 1.0, 0) - m
				_sight.global_transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP), m + d * 0.5)
				_sight.scale = Vector3(1, 1, d.length())
			if e >= wind:
				_sight.visible = false
				var to := _ppos() - Vector3(cur_c.x, 0, cur_c.z)
				ps.a0 = atan2(to.z, to.x) - 0.75
				ps.a1 = atan2(to.z, to.x) + 0.75
				if randf() < 0.5:
					var tmp: float = ps.a0
					ps.a0 = ps.a1
					ps.a1 = tmp
				ps.side = Vector3(-to.z, 0, to.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
				ps.ft = 0.0
				_next(3)
		3:
			var e := _since()
			var dur := 1.9 if phase == 1 else 2.3
			var k := clampf(e / dur, 0.0, 1.0)
			var a := lerpf(float(ps.a0), float(ps.a1), k)
			var d := Vector3(cos(a), 0, sin(a))
			face_to = Vector3(cur_c.x, 0, cur_c.z) + d * 10.0
			# 옆걸음질 (게처럼)
			var side: Vector3 = ps.side
			var q := stage.push_out(Vector3(cur_c.x, 0, cur_c.z) + side * 4.5 * dt, 3.5)
			cur_c = Vector3(q.x, Stage.RIDE, q.z)
			loc = Stage.floor_loc(cur_c)
			seg_from = {"c": cur_c, "n": cur_n}
			rig.gat_spin = 40.0
			ps.ft = float(ps.ft) - dt
			if float(ps.ft) <= 0.0:
				ps.ft = 0.055 if phase == 1 else 0.045
				var m := rig.gun_muzzle()
				var from := Vector3(m.x, 1.0, m.z)
				var dd := d.rotated(Vector3.UP, randf_range(-0.04, 0.04))
				Main.inst.add_bullet(Bullet.make_enemy(from, dd, 13.0))
				FX.muzzle(m, dd)
				if int(e / 0.055) % 3 == 0:
					Sfx.play("tshot", 0.1, -10.0)
			if k >= 1.0:
				rig.gat_spin = 0.0
				return e > dur + 0.5
	return false


# ── 패턴: 질주 (2페이즈) ────────────────────────────────

func _p_skitter(dt: float) -> bool:
	match _step():
		0:
			if String(loc.get("s", "")) != "floor":
				go(Stage.floor_loc(stage.random_floor(_ppos(), 10.0, 18.0)), 14.0)
				_next(1)
			else:
				_next(2)
		1:
			if arrived():
				_next(2)
		2:
			if not ps.has("n"):
				ps.n = 0
				ps.drop = 0.0
			if arrived():
				if int(ps.n) >= 3:
					_next(3)
					return false
				ps.n = int(ps.n) + 1
				var to := _ppos() - Vector3(cur_c.x, 0, cur_c.z)
				var side := Vector3(-to.z, 0, to.x).normalized() * (1.0 if int(ps.n) % 2 == 0 else -1.0)
				var tg := _ppos() + side * 7.0 + to.normalized() * (2.0 if int(ps.n) < 3 else -4.0)
				go(Stage.floor_loc(stage.push_out(tg, 3.5)), 21.0)
				rig.stride_k = 1.4
				Sfx.play("dash", 0.1, -4.0)
			ps.drop = float(ps.drop) - dt
			if float(ps.drop) <= 0.0:
				ps.drop = 0.22
				stage.add_web(Vector3(cur_c.x, 0, cur_c.z) - travel * 3.0, 1.8, 6.0)
		3:
			rig.stride_k = 1.0
			return _stab(dt, "stab")
	return false


# ── 확인 모드: 공격 없이 바닥 · 벽 · 기둥 · 구멍을 오간다 ─────

func _p_show(_dt: float) -> bool:
	match _step():
		0:
			var r := randi() % 5
			var target: Dictionary
			match r:
				0: target = _wall_spot(randf_range(5.0, 10.0))
				1: target = Stage.pillar_loc(randi() % Stage.PILLARS.size(), randf_range(6.0, 12.0), randf() * TAU)
				2: target = Stage.hole_loc(randi() % Stage.HOLES.size(), 3.0)
				_: target = Stage.floor_loc(stage.random_floor(_ppos(), 6.0, 22.0))
			go(target, randf_range(6.0, 11.0))
			burst = randf() < 0.4
			_next(1)
		1:
			if arrived():
				burst = false
				return _since() > 1.0
	return false


# ── 공용 효과 ───────────────────────────────────────────

func _slam(c: Vector3, r: float, ring: int) -> void:
	var pl := _player()
	if pl.alive and Vector2(pl.global_position.x - c.x, pl.global_position.z - c.z).length() < r + pl.hit_radius:
		pl.take_hit(c)
	Main.inst.shake(0.8)
	Main.inst.hitstop(0.06)
	FX.shockwave(c + Vector3(0, 0.08, 0), Color(0.6, 0.9, 1.0), r * 2.6, 0.4, 0.14)
	FX.ring(c + Vector3(0, 0.3, 0), r * 1.6, [Color(0.5, 0.9, 1.0), Color(0.3, 0.4, 0.5), Color.WHITE], 0.45)
	FX.sparks(c + Vector3(0, 0.4, 0), 30, [Color.WHITE, Color(1.0, 0.7, 0.35), Color(0.4, 0.4, 0.42)], 12.0, 0.6, -16.0, 0.12)
	for k in 10:
		var a := TAU * k / 10.0
		stage.dust(c + Vector3(cos(a), 0.3, sin(a)) * r * 0.8, 2.6, Color(0.3, 0.29, 0.28, 0.4), Vector3(cos(a), 0.4, sin(a)) * 4.0, 1.6)
	AbyssFX.light_flash(c + Vector3(0, 1.5, 0), Color(0.6, 0.9, 1.0), 8.0, 14.0, 0.4)
	Distortion.burst(c + Vector3(0, 0.5, 0), 5.0, 0.4, 1.2, 0.6)
	Sfx.play("boom", 0.05, 0.0)
	revealed.emit(c, "slam")
	var off := randf() * TAU
	for k in ring:
		var a := off + TAU * k / ring
		var d := Vector3(cos(a), 0, sin(a))
		Main.inst.add_bullet(Bullet.make_enemy(Vector3(c.x, 1.0, c.z) + d * 1.6, d, 7.5, true))


func _warn_at(p: Vector3, r: float) -> MeshInstance3D:
	var w := AbyssFX.warn_disc(p, r, DANGER)
	_warns.append({"mi": w, "pos": Vector3(p.x, 0, p.z), "r": r})
	return w


func _set_warn_at(w: MeshInstance3D, k: float) -> void:
	if is_instance_valid(w):
		AbyssFX.set_warn(w, k)


func _set_warns(k: float) -> void:
	for w in _warns:
		_set_warn_at(w.mi, k)


func _move_warn_at(w: MeshInstance3D, p: Vector3) -> void:
	if not is_instance_valid(w):
		return
	w.global_position = Vector3(p.x, 0.05, p.z)
	for e in _warns:
		if e.mi == w:
			e.pos = Vector3(p.x, 0, p.z)


func _remove_warn_at(w: MeshInstance3D) -> void:
	for i in range(_warns.size() - 1, -1, -1):
		if _warns[i].mi == w:
			_warns.remove_at(i)
	if is_instance_valid(w):
		w.queue_free()


func _clear_warns() -> void:
	for w in _warns:
		if is_instance_valid(w.mi):
			(w.mi as Node).queue_free()
	_warns.clear()


func get_threats() -> Array:
	return threats.duplicate()


# ── 피격 ────────────────────────────────────────────────

func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	if not alive or st != St.FIGHT or hidden or show_mode:
		return
	var amount := float(mini(dmg, 20))
	if source == "slash":
		amount = 12.0
	elif source == "phantom":
		amount = 22.0
	if weak:
		amount *= weak_mult
	boss_hp = maxf(0.0, boss_hp - amount)
	if is_instance_valid(bar):
		bar.call("set_hp", boss_hp / MAX_HP, amount >= 5.0)
	kill_source = source
	var at := fx_point(pos, dir)
	HitSpark.spawn(at, dir, clampf(1.0 + amount * 0.06, 1.0, 2.4), self)
	rig._lean_v += rig.body_xf().basis.inverse() * Vector3(dir.x, 0, dir.z) * minf(0.05 * amount, 0.6) * Vector3(1, 0, 1)
	rig._bob_v -= minf(amount * 0.08, 1.5)
	if randf() < 0.3:
		FX.sparks(at, 4, [Color.WHITE, Color(0.6, 0.9, 1.0)], 5.0, 0.3, -12.0, 0.06)
	if amount >= 8.0 and flash_cd <= 0.0:
		flash_cd = 0.3
		rig.set_flash(Pal.flash())
		get_tree().create_timer(0.06, true, false, true).timeout.connect(func():
			if is_instance_valid(rig):
				rig.set_flash(null))
	if hit_snd_cd <= 0.0:
		hit_snd_cd = 0.07
		Sfx.play("hit", 0.15, -8.0)
	if weak and randf() < 0.12:
		Main.inst.hud.popup("×%.1f" % weak_mult, Color("ffe060"), at + Vector3(0, 1.5, 0))
	if phase == 1 and boss_hp <= MAX_HP * PHASE2_AT:
		boss_hp = MAX_HP * PHASE2_AT
		if is_instance_valid(bar):
			bar.call("set_hp", PHASE2_AT, true)
		_begin_transition()
	elif boss_hp <= 0.0:
		_begin_dying()


func _set_flash(_on: bool) -> void:
	pass


## 패링 경직은 받지 않는다 (거체)
func stagger(_dir: Vector3, _dur: float) -> void:
	pass


func set_locked(on: bool) -> void:
	locked = on
	if is_instance_valid(rig):
		rig.set_flash(Pal.lock_hatch() if on else null)


func _abort_pattern() -> void:
	pat = ""
	ps = {}
	burst = false
	_clear_warns()
	_release_pose()
	thread_top = Vector3.ZERO
	rig.curl = 0.0
	rig.twitch = 0.0
	stage.hole_eyes_off()
	# 공중 · 천장에 있으면 바로 아래 바닥으로
	if String(loc.get("s", "")) == "air" or (cur_c.y > Stage.RIDE + 0.5 and cur_n.y > 0.7 and Stage.inside_hole(cur_c) < 0):
		cur_c = Vector3(cur_c.x, Stage.RIDE, cur_c.z)
		cur_n = Vector3.UP
		loc = Stage.floor_loc(cur_c)
		route.clear()
		seg_from = {"c": cur_c, "n": cur_n}
		rig.snap_feet()


func _clear_bullets() -> void:
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		FX.flash(b.position, CYAN, 0.3, 0.08)
		b.queue_free()


# ── 2페이즈 전환 ────────────────────────────────────────

func _begin_transition() -> void:
	_abort_pattern()
	_clear_bullets()
	st = St.TRANSITION
	st_t = 0.0
	weak = false
	ps = {}
	print("SPIDER_TRANSITION t=%.1f" % Main.inst.time)


func _update_transition(dt: float) -> void:
	face_to = _ppos()
	if not arrived():
		return
	if not ps.has("t0"):
		ps.t0 = st_t
	var e := st_t - float(ps.t0)
	var k := clampf(e / 2.4, 0.0, 1.0)
	rig.rear = sin(k * PI) * 0.9
	rig.abd_raise = sin(k * PI) * 0.7
	_threat_legs(sin(k * PI))
	rig.twitch = 0.25 * sin(k * PI)
	if e > 0.8 and not ps.has("roar"):
		ps.roar = true
		Main.inst.shake(0.9)
		Sfx.play("overload", 0.0, 0.0)
		Sfx.play("boom", 0.0, -2.0)
		Main.inst.hud.banner("PHASE 2", Color("ff3a2a"), "비상 전원 — SHIPWRIGHT 가 미쳐 날뛴다")
		AbyssFX.light_flash(cur_c + Vector3(0, 3, 3), DANGER, 14.0, 34.0, 1.4)
		phase = 2
		if is_instance_valid(bar):
			bar.call("set_phase", 2)
		phase_changed.emit(2)
	if k >= 1.0:
		_threat_legs(0.0)
		rig.twitch = 0.0
		st = St.FIGHT
		st_t = 0.0
		rest = 0.4
		order = PATTERNS_2.duplicate()
		order.shuffle()
		# 2페이즈는 숨었다 나타나며 시작한다
		order.erase("ambush")
		order.push_front("ambush")
		pat_i = -1
		ps = {}


# ── 격파 ────────────────────────────────────────────────

func _begin_dying() -> void:
	_abort_pattern()
	_clear_bullets()
	st = St.DYING
	st_t = 0.0
	alive = false
	landed = false
	weak = false
	remove_from_group("enemies")
	route.clear()
	if is_instance_valid(bar):
		bar.call("set_pattern", "")
	Main.inst.hitstop(0.12)
	Main.inst.shake(0.9)
	Sfx.play("overload", 0.0, 2.0)
	ps = {"fall_v": Vector3.ZERO, "n0": cur_n, "c0": cur_c}
	print("SPIDER_DYING t=%.1f" % Main.inst.time)


func _update_dying(dt: float) -> void:
	# 벽 · 기둥에서 떨어져 바닥에 뒹군 뒤, 다리를 몸 아래로 오므리며 경련한다
	var floor_c := Vector3(clampf(cur_c.x, -Stage.HX + 4, Stage.HX - 4), Stage.RIDE, clampf(cur_c.z, -Stage.HZ + 4, Stage.HZ - 4))
	if cur_c.y > Stage.RIDE + 0.05 or cur_c.distance_to(floor_c) > 0.1:
		var v: Vector3 = ps.fall_v
		v.y -= 22.0 * dt
		v += (floor_c - cur_c) * Vector3(1, 0, 1) * 6.0 * dt
		ps.fall_v = v
		cur_c += v * dt
		cur_n = cur_n.slerp(Vector3.UP, 1.0 - exp(-4.0 * dt)).normalized()
		if cur_c.y <= Stage.RIDE:
			cur_c.y = Stage.RIDE
			cur_c.x = lerpf(cur_c.x, floor_c.x, 0.5)
			cur_c.z = lerpf(cur_c.z, floor_c.z, 0.5)
			if not ps.has("landed"):
				ps.landed = true
				Main.inst.shake(0.7)
				Sfx.play("boom", 0.05, -2.0)
				for k in 8:
					stage.dust(Vector3(cur_c.x, 0.3, cur_c.z) + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)), 2.6, Color(0.3, 0.29, 0.28, 0.4), Vector3(0, 1.2, 0), 1.6)
				rig.snap_feet()
			ps.fall_v = Vector3.ZERO
			if cur_c.distance_to(floor_c) < 0.2:
				cur_c = floor_c
	cur_n = cur_n.slerp(Vector3.UP, 1.0 - exp(-4.0 * dt)).normalized()
	var k := clampf(st_t / 3.6, 0.0, 1.0)
	rig.curl = smoothstep(0.1, 0.75, k)
	rig.twitch = (1.0 - k) * 0.9 * (0.5 + 0.5 * absf(sin(st_t * 9.0)))
	rig.eye_k = (1.0 - k) * (0.3 + 0.7 * float(randf() < 0.7))
	rig.light_k = 1.0 - k
	rig.abd_raise = -0.1 * k
	_fx_t -= dt
	if _fx_t <= 0.0 and k < 0.95:
		_fx_t = lerpf(0.3, 0.08, k)
		var p := rig.to_world(Vector3(randf_range(-1.5, 1.5), randf_range(-0.3, 1.5), randf_range(-2.5, 3.0)))
		FX.sparks(p, 12, [Color.WHITE, CYAN, Color(1.0, 0.6, 0.3)], 8.0, 0.5, -14.0, 0.08)
		FX.flash(p, Color(0.8, 1.0, 1.0), 1.0, 0.07)
		FX.puffs(p, 3, [Color(0.2, 0.2, 0.22), Color(0.14, 0.14, 0.16), Color(0.08, 0.08, 0.09), Color(0.05, 0.05, 0.06)], 0.8, 0.8, 1.0)
		AbyssFX.light_flash(p, CYAN, 5.0, 10.0, 0.25)
		Sfx.play("boom", 0.2, -8.0)
		Main.inst.shake(0.2)
	if k >= 1.0 and not ps.has("final"):
		ps.final = true
		_final_blast()


func _final_blast() -> void:
	var c := rig.root.global_position
	FX.flash(c, Color.WHITE, 6.0, 0.25)
	FX.fire_explosion(c, 2.2)
	AbyssFX.light_flash(c + Vector3(0, 2, 0), Color(0.7, 0.95, 1.0), 30.0, 50.0, 1.6)
	FX.shockwave(Vector3(c.x, 0.1, c.z), CYAN, 16.0, 0.7, 0.2)
	Main.inst.shake(1.0)
	Main.inst.hitstop(0.15)
	Main.inst.hud.screen_flash(Color(0.85, 1.0, 1.0), 0.7)
	Sfx.play("boom", 0.0, 4.0)
	Sfx.play("lose", 0.3, -6.0)
	rig.eye_k = 0.0
	rig.light_k = 0.0
	rig.twitch = 0.0
	st = St.DEAD
	defeated.emit()
