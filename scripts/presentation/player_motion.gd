class_name PlayerMotion
extends RefCounted
## 플레이어 사격·재장전·레이저·미사일 동작 연출 (판정·타이밍은 Player 가 정하고, 여기서는 자세만 덧입힌다).
##
## 젠레스 존 제로식 리듬: 키 포즈로 1~3프레임 만에 튀어 들어가고(expo) → 몇 프레임 버티며 읽히게 하고 →
## 넘쳤다 돌아오며(back) 풀린다. 모든 값은 Player._animate 가 정한 기본 자세 위에 "더하는" 오프셋이며,
## 매 틱 처음에 지난 오프셋을 빼고(pre) 끝에서 새로 더한다(post). 그래서 기본 애니메이션의 lerp 가 흐트러지지 않는다.
##
##  재장전  빈 탄창을 걷어차듯 뽑아 던짐(4F) → 버팀 → 총을 머리 위로 띄워 세 바퀴 돌림 → 탄창 내리꽂기(4F, 불꽃) → 장전 튕김 → 복귀
##  사격    쉬다가 첫 발: 총구가 튀어 오르는 퀵드로 · 매 발 상체가 좌우로 살짝 비틀림
##  충전    단계가 오를수록 다리를 벌리고 낮게 버티며, 광선검 팔이 총 팔을 받친다 · 단계 상승마다 움찔
##  레이저  2프레임 만에 몸이 뒤로 꺾이고 총이 치솟는 반동 포즈 → 버팀 → 탄성 복귀 (강하면 발이 바닥을 긁으며 밀린다)
##  지속 레이저  깊게 앉아 버티는 자세 + 진동
##  미사일  락온 중: 낮게 웅크린 준비 자세 · 발사: 3프레임에 뛰어올라 가슴을 젖히고 양팔을 벌린 채 일제 사격 →
##          떨어져 내리꽂듯 착지(충격파) → 복귀
##  미사일 준비동작 (R 을 뗀 뒤 ULT_WINDUP 실제 시간): 2~3프레임 만에 몸을 비틀어 깊게 웅크리고 양팔을 모아 잠근다 →
##          부르르 떨며 버티는 동안 붉은 에너지가 등의 발사구로 빨려 든다 → 마지막에 더 눌러 앉았다가 튕겨 오르며 일제 사격으로 이어진다

const F := 1.0 / 60.0

var p: Player
var gun: Node3D                     # 사격 팔 끝 총 부분 (재장전 때 돈다)
var _applied: Array = []            # [노드, 속성 경로, 더한 값]

# 재장전
var _rl_ev := 0
# 사격
var _idle := 1.0
var _draw := -1.0
var _twist := 0.0
var _side := 1.0
# 충전 · 레이저
var _cw := 0.0
var _pulse := 0.0
var _las := -1.0
var _las_k := 0.0
var _mw := 0.0
# 미사일
var _aw := 0.0
var _salvo := -1.0
var _salvo_ph := 0
var _drop_t := 0.0
var _shudder := 0.0
var _last_ms := 0
# 미사일 준비동작
var _wu_ev := 0


func _init(owner: Player) -> void:
	p = owner
	_last_ms = Time.get_ticks_msec()


## 사격 팔(ArmL)의 총 부분을 별도 축 노드로 옮긴다. 재장전 때 그 축을 돌려 리볼버처럼 회전시킨다.
func rig() -> void:
	var arm: Node3D = p.j.arm_l
	gun = Node3D.new()
	gun.name = "GunSpin"
	arm.add_child(gun)
	gun.position = Vector3(0, -0.34, -0.2)
	for c in arm.get_children():
		if c == gun or not (c is Node3D):
			continue
		var n := c as Node3D
		if n.position.z < -0.05:
			var xf := n.transform
			arm.remove_child(n)
			gun.add_child(n)
			n.transform = Transform3D(xf.basis, xf.origin - gun.position)


# ── 사건 (Player 가 부른다) ───────────────────────────────

func reload_begin() -> void:
	_rl_ev = 0


func on_shot() -> void:
	if _idle > 0.45:
		_draw = 0.0
	_idle = 0.0
	_side = -_side
	_twist = _side


func stage_pulse() -> void:
	_pulse = 1.0


func laser(k: float) -> void:
	_las = 0.0
	_las_k = k


## 레이저 반동으로 밀려나는 중 (발이 바닥을 긁는다)
func sliding() -> bool:
	return _las >= 0.0 and _las < 0.22 and _las_k > 0.5


func windup() -> void:
	_wu_ev = 0
	p.squash_v -= 10.0
	Main.inst.camera.fov_punch(-6.0)
	Main.inst.hud.screen_flash(Color(1, 0.4, 0.35), 0.3)
	var s := Sfx.play("echarge", 0.0, -2.0)
	if s:
		s.pitch_scale = 1.5
	_windup_burst()


func salvo() -> void:
	_salvo = 0.0
	_salvo_ph = 1
	p.hover_v += 6.0


func salvo_kick() -> void:
	_shudder = 1.0


# ── 오프셋 적용 ──────────────────────────────────────────

func pre() -> void:
	for a in _applied:
		var n: Node3D = a[0]
		if is_instance_valid(n):
			n.set_indexed(a[1], float(n.get_indexed(a[1])) - float(a[2]))
	_applied.clear()


func _add(n: Node3D, prop: NodePath, v: float) -> void:
	if absf(v) < 0.00001:
		return
	n.set_indexed(prop, float(n.get_indexed(prop)) + v)
	_applied.append([n, prop, v])


static func _expo(k: float) -> float:
	return 1.0 if k >= 1.0 else (1.0 - pow(2.0, -10.0 * k)) / (1.0 - pow(2.0, -10.0))


static func _out(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)


static func _back(k: float) -> float:
	var s := 1.7
	var q := k - 1.0
	return 1.0 + q * q * ((s + 1.0) * q + s)


static func _ez(k: float, kind: String) -> float:
	match kind:
		"expo":
			return _expo(k)
		"out":
			return _out(k)
		"back":
			return _back(k)
		"in":
			return k * k * k
	return k


## 키 포즈 트랙: [[시점, {키: 값}, 이징], ...] 에서 k 시점의 값
static func _track(keys: Array, k: float) -> Dictionary:
	var out := {}
	if k <= float(keys[0][0]):
		return (keys[0][1] as Dictionary).duplicate()
	for i in range(1, keys.size()):
		var k1 := float(keys[i][0])
		if k <= k1 or i == keys.size() - 1:
			var k0 := float(keys[i - 1][0])
			var a: Dictionary = keys[i - 1][1]
			var b: Dictionary = keys[i][1]
			var u := _ez(clampf((k - k0) / maxf(k1 - k0, 0.0001), 0.0, 1.0), String(keys[i][2]))
			for key in a.keys() + b.keys():
				out[key] = lerpf(float(a.get(key, 0.0)), float(b.get(key, 0.0)), u)
			return out
	return out


# 재장전 키 포즈 (재장전 진행도 0~1, RELOAD_TIME 1.25초 → 0.04 ≈ 3프레임)
# ax 사격 팔 들기 · az 팔 벌리기 · gs 총 회전 · ty/tx 상체 비틀기/젖히기 · ar 광선검 팔 · lift 몸 높이
const RELOAD_KEYS := [
	[0.0, {}, "lin"],
	[0.05, {"ax": -1.35, "az": -0.55, "ty": 0.5, "tx": 0.12, "ar": 0.55, "lift": -0.07, "gs": 0.0}, "expo"],
	[0.15, {"ax": -1.22, "az": -0.48, "ty": 0.44, "tx": 0.09, "ar": 0.48, "lift": -0.05, "gs": 0.0}, "out"],
	[0.22, {"ax": 0.95, "az": -0.15, "ty": -0.22, "tx": -0.2, "ar": -0.25, "lift": 0.03, "gs": -TAU}, "expo"],
	[0.47, {"ax": 1.05, "az": -0.1, "ty": -0.28, "tx": -0.22, "ar": -0.3, "lift": 0.02, "gs": -TAU * 3.0}, "out"],
	[0.52, {"ax": -0.9, "az": -0.38, "ty": 0.38, "tx": 0.16, "ar": 0.42, "lift": -0.09, "gs": -TAU * 3.0}, "expo"],
	[0.66, {"ax": -0.82, "az": -0.32, "ty": 0.32, "tx": 0.12, "ar": 0.36, "lift": -0.06, "gs": -TAU * 3.0}, "out"],
	[0.73, {"ax": 0.4, "az": 0.05, "ty": -0.16, "tx": -0.06, "ar": 0.0, "lift": 0.01, "gs": -TAU * 3.0}, "expo"],
	[1.0, {"gs": -TAU * 3.0}, "back"],
]


# 미사일 준비동작 키 포즈 (진행도 0~1, ULT_WINDUP 0.42초 → 0.1 ≈ 2.5프레임)
const WU_COIL := {"lift": -0.26, "hl": -0.75, "hr": 0.85, "kl": -1.35, "kr": -1.45, "tx": 0.5, "ty": 0.75,
	"az": 0.6, "ax": -0.5, "arz": -0.6, "ar": -0.45, "arx": 0.3}
const WU_HOLD := {"lift": -0.3, "hl": -0.82, "hr": 0.92, "kl": -1.5, "kr": -1.55, "tx": 0.58, "ty": 0.9,
	"az": 0.7, "ax": -0.55, "arz": -0.7, "ar": -0.5, "arx": 0.35}
const WU_PRESS := {"lift": -0.36, "hl": -0.92, "hr": 0.98, "kl": -1.65, "kr": -1.65, "tx": 0.66, "ty": 0.25,
	"az": 0.3, "ax": -0.25, "arz": -0.3, "ar": -0.2}
const WU_RELEASE := {"lift": -0.12, "hl": -0.5, "hr": 0.55, "kl": -1.0, "kr": -1.0, "tx": 0.1, "az": -0.5, "arz": 0.5, "ax": 0.25}
const WINDUP_KEYS := [
	[0.0, {}, "lin"],
	[0.1, WU_COIL, "expo"],
	[0.72, WU_HOLD, "out"],
	[0.88, WU_PRESS, "expo"],
	[1.0, WU_RELEASE, "in"],
]


func post(dt: float) -> void:
	var j := p.j
	var arm_l: Node3D = j.arm_l
	var arm_r: Node3D = j.arm_r
	var torso: Node3D = j.torso
	var now := Time.get_ticks_msec()
	var real_dt := clampf((now - _last_ms) / 1000.0, 0.0, 0.1)
	_last_ms = now
	var o := {}   # 이번 틱 오프셋 합
	var t := now * 0.001

	# ── 재장전 ──
	if p.reload_t > 0.0:
		var rk := p.reload_k()
		_add_all(o, _track(RELOAD_KEYS, rk))
		if _rl_ev == 0:
			_rl_ev = 1
			_eject_mag()
		if _rl_ev == 1 and rk >= 0.5:
			_rl_ev = 2
			_insert_mag()
		if _rl_ev == 2 and rk >= 0.71:
			_rl_ev = 3
			_cock()
	elif gun and absf(gun.rotation.x) > 0.0001:
		gun.rotation.x = 0.0

	# ── 사격 ──
	_idle += dt
	if _draw >= 0.0:
		_draw += dt
		var dk := clampf(_draw / 0.16, 0.0, 1.0)
		var w := pow(1.0 - dk, 2.0)
		o.ax = float(o.get("ax", 0.0)) + 0.5 * w
		o.tx = float(o.get("tx", 0.0)) - 0.14 * w
		o.az = float(o.get("az", 0.0)) - 0.15 * w
		if dk >= 1.0:
			_draw = -1.0
	_twist = move_toward(_twist, 0.0, dt * 14.0) if absf(_twist) > 0.0 else 0.0
	o.ty = float(o.get("ty", 0.0)) + _twist * 0.05

	# ── 충전 ──
	_cw = lerpf(_cw, p.charge if p.charging else 0.0, 1.0 - exp(-14.0 * dt))
	_pulse = maxf(0.0, _pulse - dt * 8.0)
	if _cw > 0.01 or _pulse > 0.0:
		var c := _cw
		_add_all(o, {"hl": -0.38 * c, "hr": 0.42 * c, "kl": -0.6 * c, "kr": -0.7 * c, "lift": -0.11 * c - 0.04 * _pulse,
			"ar": 0.75 * c, "arx": 0.25 * c, "ax": 0.35 * _pulse * _pulse, "tx": -0.08 * _pulse})

	# ── 레이저 반동 ──
	if _las >= 0.0:
		_las += dt
		var k := _las_k
		var kick := {"ax": 1.15 * k, "az": -0.35 * k, "tx": -0.55 * k, "ty": -0.3 * k, "hl": -0.75 * k, "hr": 0.65 * k,
			"kl": -0.5 * k, "kr": -0.85 * k, "lift": -0.1 * k, "ar": 0.65 * k, "arz": 0.4 * k}
		var w := 0.0
		if _las < 2.0 * F:
			w = _expo(_las / (2.0 * F))
		elif _las < 0.12:
			w = 1.0 + sin(_las * 120.0) * 0.04 * k
		elif _las < 0.45:
			w = 1.0 - _back((_las - 0.12) / 0.33)
		else:
			_las = -1.0
		var kd := {}
		for key in kick:
			kd[key] = float(kick[key]) * w
		_add_all(o, kd)

	# ── 지속 레이저 ──
	_mw = lerpf(_mw, 1.0 if p.mega_t > 0.0 else 0.0, 1.0 - exp(-18.0 * dt))
	if _mw > 0.01:
		var m := _mw
		_add_all(o, {"hl": -0.62 * m, "hr": 0.72 * m, "kl": -0.95 * m, "kr": -1.05 * m, "lift": -0.17 * m,
			"ar": 1.0 * m, "arx": 0.3 * m, "az": -0.12 * m, "ax": sin(t * 90.0) * 0.04 * m, "ty": sin(t * 70.0) * 0.03 * m})

	# ── 미사일 락온 준비 (슬로우모션 중이라 실제 시간으로 붙는다) ──
	_aw = lerpf(_aw, 1.0 if p.ult_aiming else 0.0, 1.0 - exp(-12.0 * real_dt))
	if _aw > 0.01:
		var a := _aw
		_add_all(o, {"hl": -0.35 * a, "hr": 0.4 * a, "kl": -0.6 * a, "kr": -0.7 * a, "lift": -0.1 * a, "tx": 0.18 * a,
			"arz": 0.5 * a, "az": -0.3 * a, "ax": 0.2 * a})

	# ── 미사일 준비동작 (실제 시간 진행도) ──
	if p.ult_winding():
		var wk := p.ult_windup_k()
		var pose := _track(WINDUP_KEYS, wk)
		var sh := wk * wk
		pose.tx = float(pose.get("tx", 0.0)) + sin(t * 95.0) * 0.04 * sh
		pose.lift = float(pose.get("lift", 0.0)) + sin(t * 130.0) * 0.015 * sh
		_add_all(o, pose)
		if _wu_ev == 0 and wk >= 0.35:
			_wu_ev = 1
			_jet_glow(0.55)
		if _wu_ev == 1 and wk >= 0.72:
			_wu_ev = 2
			_jet_glow(0.9)
			var s := Sfx.play("charged", 0.0, -4.0)
			if s:
				s.pitch_scale = 1.3

	# ── 미사일 일제 사격 ──
	if _salvo_ph > 0:
		_salvo += dt
		_shudder = maxf(0.0, _shudder - dt * 18.0)
		var up := {"lift": 0.95, "tx": -0.6, "az": -1.15, "arz": 1.15, "ax": 0.5, "hl": 0.9, "hr": 0.75, "kl": -1.5, "kr": -1.3}
		var land := {"lift": -0.18, "tx": 0.3, "az": -0.35, "arz": 0.35, "hl": -0.65, "hr": 0.75, "kl": -1.15, "kr": -1.25}
		var pose := {}
		match _salvo_ph:
			1:
				var k := _expo(clampf(_salvo / (3.0 * F), 0.0, 1.0))
				for key in up:
					pose[key] = float(up[key]) * k
				pose.tx = float(pose.tx) + _shudder * 0.08
				pose.lift = float(pose.lift) + sin(t * 40.0) * 0.03
				if _salvo > 0.22 and p.ult_queue <= 0:
					_salvo_ph = 2
					_drop_t = 0.0
			2:
				_drop_t += dt
				var k := clampf(_drop_t / 0.1, 0.0, 1.0)
				for key in up.keys() + land.keys():
					pose[key] = lerpf(float(up.get(key, 0.0)), float(land.get(key, 0.0)), k * k * k)
				if k >= 1.0:
					_salvo_ph = 3
					_drop_t = 0.0
					_slam_land()
			3:
				_drop_t += dt
				var k := clampf(_drop_t / 0.28, 0.0, 1.0)
				for key in land:
					pose[key] = float(land[key]) * (1.0 - _back(k))
				if k >= 1.0:
					_salvo_ph = 0
		_add_all(o, pose)

	_apply(o, arm_l, arm_r, torso)


func _add_all(o: Dictionary, d: Dictionary) -> void:
	for key in d:
		o[key] = float(o.get(key, 0.0)) + float(d[key])


func _apply(o: Dictionary, arm_l: Node3D, arm_r: Node3D, torso: Node3D) -> void:
	var j := p.j
	# 사격 팔 들기와 총 회전은 콤보가 건드리지 않는 축이라 콤보 중에도 더한다
	_add(arm_l, ^"rotation:x", float(o.get("ax", 0.0)))
	if gun:
		_add(gun, ^"rotation:x", float(o.get("gs", 0.0)))
	var sh = j.get("shoulder_l")
	if sh:
		_add(sh as Node3D, ^"rotation:z", -float(o.get("ax", 0.0)) * 0.06 + float(o.get("az", 0.0)) * 0.2)
	if p.combo.posing() or (p.tech != null and p.tech.posing()):
		return
	_add(arm_l, ^"rotation:z", float(o.get("az", 0.0)))
	_add(arm_r, ^"rotation:y", float(o.get("ar", 0.0)))
	_add(arm_r, ^"rotation:x", float(o.get("arx", 0.0)))
	_add(arm_r, ^"rotation:z", float(o.get("arz", 0.0)))
	_add(torso, ^"rotation:x", float(o.get("tx", 0.0)))
	_add(torso, ^"rotation:y", float(o.get("ty", 0.0)))
	_add(j.hip_l, ^"rotation:x", float(o.get("hl", 0.0)))
	_add(j.hip_r, ^"rotation:x", float(o.get("hr", 0.0)))
	_add(j.knee_l, ^"rotation:x", float(o.get("kl", 0.0)))
	_add(j.knee_r, ^"rotation:x", float(o.get("kr", 0.0)))
	_add(p.visual, ^"position:y", float(o.get("lift", 0.0)))


# ── 재장전 사건 연출 ─────────────────────────────────────

func _eject_mag() -> void:
	var g: Node3D = gun if gun else p.j.arm_l
	var pos := g.to_global(Vector3(0, -0.12, 0.02))
	var side := Vector3.UP.cross(p.aim_dir).normalized()
	_spawn_mag(pos, side * 3.5 - p.aim_dir * 1.5 + Vector3(0, 2.6, 0))
	FX.sparks(pos, 5, [Color.WHITE, Color("8ad8ff")], 3.5, 0.18, -10.0, 0.04)
	p.squash_v -= 5.0
	p.tilt_v += side * 3.0
	var s := Sfx.play("unfold", 0.05, -4.0)
	if s:
		s.pitch_scale = 1.4


func _insert_mag() -> void:
	var g: Node3D = gun if gun else p.j.arm_l
	var pos := g.to_global(Vector3(0, -0.1, 0.0))
	FX.flash(pos, Color("8ae8ff"), 0.55, 0.04)
	FX.sparks(pos, 12, [Color.WHITE, Color("ffd080"), Color("8ad8ff")], 6.0, 0.22, -10.0, 0.05)
	FX.shockwave(p.global_position, Color("8ad8ff"), 1.5, 0.18, 0.04)
	p.squash_v -= 9.0
	p.tilt_v += p.aim_dir * 4.0
	Sfx.play("clank", 0.03, -5.0)
	Main.inst.shake(0.08)


func _cock() -> void:
	var muzzle: Node3D = p.j.muzzle
	FX.flash(muzzle.global_position, Color("ffe0a0"), 0.35, 0.03)
	p.squash_v += 5.0
	var s := Sfx.play("tink", 0.0, -6.0)
	if s:
		s.pitch_scale = 1.6


## 빈 탄창: 회전하며 튀어 바닥에서 한 번 튀고 사라진다
func _spawn_mag(pos: Vector3, v0: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.2, 0.13)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Pal.P_DARK
	mat.emission_enabled = true
	mat.emission = Pal.CYAN
	mat.emission_energy_multiplier = 0.35
	mi.material_override = mat
	FX.root.add_child(mi)
	mi.global_position = pos
	var gy := Main.gy(pos)
	var st := {"p": pos, "v": v0, "bounced": false, "last": 0.0,
		"spin": Vector3(randf_range(14, 22), randf_range(-6, 6), randf_range(8, 14))}
	var tw := mi.create_tween()
	tw.tween_method(func(x: float):
		var dt := (x - float(st.last)) * 0.9
		st.last = x
		var v: Vector3 = st.v
		v.y -= 22.0 * dt
		var np: Vector3 = st.p + v * dt
		if np.y < gy + 0.05:
			np.y = gy + 0.05
			if not st.bounced:
				st.bounced = true
				v = Vector3(v.x * 0.4, -v.y * 0.35, v.z * 0.4)
				st.spin = (st.spin as Vector3) * 0.4
			else:
				v = Vector3(v.x * 0.9, 0.0, v.z * 0.9)
		st.v = v
		st.p = np
		if is_instance_valid(mi):
			mi.global_position = np
			mi.rotation += (st.spin as Vector3) * dt, 0.0, 1.0, 0.9)
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.25)
	tw.tween_callback(mi.queue_free)


# ── 미사일 준비동작 사건 연출 (슬로우모션 중이라 트윈은 실제 시간으로 돈다) ──

## 시작: 주변에서 붉은 에너지 줄기가 등 발사구로 빨려 들고, 발밑 고리가 조여 든다
func _windup_burst() -> void:
	var dur := Player.ULT_WINDUP
	var c0 := p.global_position + Vector3(0, 1.0, 0)
	var g := Vector3(p.global_position.x, Main.gy(p.global_position) + 0.08, p.global_position.z)
	var ring := Pal.flat_mesh(_ring_mesh(), Color(1, 0.3, 0.25), 2.2)
	FX.root.add_child(ring)
	ring.global_position = g
	ring.scale = Vector3(4.2, 0.06, 4.2)
	var tw := ring.create_tween().set_ignore_time_scale(true)
	tw.tween_property(ring, "scale", Vector3(0.5, 0.06, 0.5), dur * 0.9).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.parallel().tween_method(func(v: Color): ring.set_instance_shader_parameter("tint", v), Color(1, 0.3, 0.25), Color(1, 0.9, 0.8), dur * 0.9)
	tw.tween_callback(ring.queue_free)
	for i in 14:
		var a := TAU * i / 14.0 + randf_range(-0.15, 0.15)
		var from := c0 + Vector3(cos(a), randf_range(-0.4, 0.9), sin(a)) * randf_range(2.2, 3.4)
		var st := Pal.flat_mesh(_streak_mesh(), Color(1, 0.35, 0.3) if i % 3 else Color(1, 0.85, 0.7), 2.4)
		FX.root.add_child(st)
		st.global_position = from
		st.look_at(c0, Vector3.UP if absf((c0 - from).normalized().y) < 0.95 else Vector3.RIGHT)
		st.scale = Vector3(1, 1, randf_range(1.0, 2.2))
		var delay := randf_range(0.0, dur * 0.35)
		var t2 := st.create_tween().set_ignore_time_scale(true)
		t2.tween_interval(delay)
		t2.tween_property(st, "global_position", c0, dur * 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		t2.parallel().tween_property(st, "scale", Vector3(0.3, 0.3, 0.2), dur * 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		t2.tween_callback(st.queue_free)


## 등 발사구 두 개가 점점 크게 달아오른다
func _jet_glow(k: float) -> void:
	for jet in [p.j.jet_l, p.j.jet_r]:
		var pos := (jet as Node3D).global_position + Vector3(0, 0.2, 0)
		var mi := Pal.flat_mesh(_ball_mesh(), Color(1, 0.85, 0.7), 3.0)
		FX.root.add_child(mi)
		mi.global_position = pos
		mi.scale = Vector3.ONE * 0.1
		var tw := mi.create_tween().set_ignore_time_scale(true)
		tw.tween_property(mi, "scale", Vector3.ONE * (0.45 + 0.5 * k), 0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.16).set_ease(Tween.EASE_IN)
		tw.parallel().tween_method(func(v: Color): mi.set_instance_shader_parameter("tint", v), Color(1, 0.85, 0.7), Color(1, 0.25, 0.2), 0.16)
		tw.tween_callback(mi.queue_free)
	Main.inst.camera.shake(0.1 + 0.15 * k)


static var _ring: TorusMesh
static var _streak: BoxMesh
static var _ball: SphereMesh


static func _ring_mesh() -> TorusMesh:
	if _ring == null:
		_ring = TorusMesh.new()
		_ring.inner_radius = 0.92
		_ring.outer_radius = 1.0
		_ring.rings = 40
		_ring.ring_segments = 4
	return _ring


static func _streak_mesh() -> BoxMesh:
	if _streak == null:
		_streak = BoxMesh.new()
		_streak.size = Vector3(0.04, 0.04, 0.6)
	return _streak


static func _ball_mesh() -> SphereMesh:
	if _ball == null:
		_ball = SphereMesh.new()
		_ball.radius = 0.5
		_ball.height = 1.0
	return _ball


func _slam_land() -> void:
	var g := Vector3(p.global_position.x, Main.gy(p.global_position) + 0.05, p.global_position.z)
	p.squash_v -= 14.0
	FX.shockwave(g, Color("ffb050"), 3.0, 0.28, 0.08)
	FX.land_dust(g)
	Sfx.play("land", 0.05, -2.0)
	Main.inst.shake(0.25)
