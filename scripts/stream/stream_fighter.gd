class_name StreamFighter
extends Enemy
## 무한 비행 모드(StreamMain)의 전투기. 종 스크롤 슈팅처럼 화면 위(-Z)에서 날아 들어와 정해진 비행 경로를 따라
## 지나가며 플레이어를 향해 쏘고, 화면 밖으로 빠져나가면 사라진다 (처치하지 못하면 "놓침").
## 피격·처치·락온·체력바는 Enemy 그대로. 이동만 경로가 정하고, 피격 경직 중에도 경로는 계속 흐른다.
##
## 경로 (path)
##  STRAIGHT  곧장 내려온다
##  SINE      좌우로 사인파를 그리며 내려온다
##  SWOOP     화면 위 한쪽 구석에서 들어와 반대편으로 크게 휘어 나간다
##  HOOK      내려와 잠깐 멈춰 쏜 뒤 되돌아 위로 빠져나간다
##  DIVE      내려와 멈춰 두 번 연사한 뒤 플레이어가 있던 쪽으로 급강하해 지나간다
##
## 기체 (kind)
##  DART  작고 빠른 요격기 · 조준 단발
##  WING  큰 날개 폭격기 · 부채꼴 3발

enum Path { STRAIGHT, SINE, SWOOP, HOOK, DIVE }
enum Kind { DART, WING }

const TOP_Z := -26.0          # 경로 시작 (화면 위 바깥)
const BOTTOM_Z := 13.0        # 이보다 아래(+Z)로 나가면 사라진다
const SIDE_X := 15.0          # 좌우로 이보다 멀리 나가면 사라진다
const FLY_Y := 1.0            # 비행 높이 (몸체)
const SHOT_SPEED := 8.0

var path := Path.STRAIGHT
var kind := Kind.DART
var x0 := 0.0                 # 경로 기준 x
var z0 := TOP_Z               # 경로 기준 z
var speed := 7.0              # 내려오는 속도 (m/s)
var side := 1.0               # SWOOP · SINE 방향
var phase := 0.0              # SINE 위상
var amp := 3.0                # SINE 진폭
var stop_z := -9.0            # HOOK · DIVE 가 멈추는 z
var wave_id := -1             # 같은 편대 (StreamMain 이 편대 보너스 판정에 쓴다)
var s := 0.0                  # 경로 진행 시간
var shots := 0                # 남은 공격 횟수
var escaped := false

var _pos := Vector3.ZERO      # 경로상 위치 (넉백 오프셋 제외)
var _prev := Vector3.ZERO
var _off := Vector3.ZERO      # 맞아서 밀린 오프셋 (서서히 0으로)
var _bank := 0.0
var _dive_dir := Vector3.BACK
var _dive_from := Vector3.ZERO
var _dive_t := -1.0


func _ready() -> void:
	super()
	evade.chance = 0.0
	orb_chance = 0.0
	match kind:
		Kind.DART:
			hp = 1
			radius = 0.55
			hp_bar_y = 1.6
			hp_bar_w = 0.8
			slice_size = Vector3(0.5, 0.3, 0.9)
			shots = 2
			fire_timer = randf_range(0.5, 1.1)
		Kind.WING:
			hp = 3
			radius = 0.85
			hp_bar_y = 1.85
			hp_bar_w = 1.2
			slice_size = Vector3(1.4, 0.34, 0.9)
			shots = 3
			fire_timer = randf_range(0.7, 1.2)
	slice_color = Pal.E_WHITE
	_pos = _path_pos(0.0)
	_prev = _pos
	global_position = _pos
	(j.body as Node3D).position.y = FLY_Y
	shadow.scale = Vector3.ONE * 0.7


func _build(v: Node3D) -> Dictionary:
	var j := {}
	var body := Build.pivot(v, Vector3(0, FLY_Y, 0), "Body")
	j.body = body
	var big := kind == Kind.WING
	var k := 1.35 if big else 1.0
	# 동체: 앞(-Z)이 뾰족한 흰 기체 + 회색 엔진 · 붉은 콕핏 코어
	Build.box(body, Vector3(0.34, 0.26, 1.0) * k, Vector3.ZERO, Pal.E_WHITE)
	Build.box(body, Vector3(0.22, 0.2, 0.42) * k, Vector3(0, 0.02, -0.62) * k, Color("f6f5fb"), Vector3(0, 45, 0))
	Build.box(body, Vector3(0.26, 0.2, 0.3) * k, Vector3(0, 0.0, 0.58) * k, Pal.E_GREY)
	# 날개: 뒤로 젖힌 삼각 날개 대신 기울인 판 두 장 (폭격기는 넓고 끝이 붉다)
	var span := 1.7 if big else 1.1
	for sd in [-1.0, 1.0]:
		Build.box(body, Vector3(span * 0.5, 0.06, 0.46) * Vector3(1, 1, k), Vector3(sd * span * 0.3, -0.04, 0.12 * k), Pal.E_WHITE, Vector3(0, -sd * 22.0, -sd * 6.0))
		Build.box(body, Vector3(0.1, 0.16, 0.36) * k, Vector3(sd * span * 0.52, -0.02, 0.22 * k), Pal.E_RED if big else Pal.E_GREY)
	var sm := SphereMesh.new()
	sm.radius = 0.15 * k
	sm.height = 0.3 * k
	var core := MeshInstance3D.new()
	core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Pal.E_RED
	cm.emission_enabled = true
	cm.emission = Pal.E_RED
	cm.emission_energy_multiplier = 0.8
	cm.roughness = 0.35
	core.material_override = cm
	core.position = Vector3(0, 0.16, -0.18) * k
	body.add_child(core)
	j.core = core
	j.core_mat = cm
	return j


## 날아 들어오므로 낙하 등장 없이 바로 전투 상태
func _update_entry(_dt: float) -> void:
	landed = true
	(j.body as Node3D).position.y = FLY_Y


## 경로 진행 시간 u 에서의 위치 (DIVE 의 급강하 구간은 _advance 가 따로 처리)
func _path_pos(u: float) -> Vector3:
	match path:
		Path.SINE:
			return Vector3(x0 + sin(u * 2.2 + phase) * amp * side, 0, z0 + speed * u)
		Path.SWOOP:
			# 위 한쪽 구석 → 플레이어 위쪽 가운데 → 반대편 옆으로 빠짐 (2차 베지어)
			var dur := 46.0 / speed
			var w := u / dur
			var a := Vector3(side * 11.0, 0, z0)
			var c := Vector3(side * -3.0, 0, -2.0)
			var b := Vector3(-side * 19.0, 0, -9.0)
			if w > 1.0:
				var out := (b - c).normalized()
				return b + out * (w - 1.0) * 46.0
			return a.lerp(c, w).lerp(c.lerp(b, w), w)
		Path.HOOK, Path.DIVE:
			# 내려와서 stop_z 에 멈춘다 (멈춘 뒤는 _advance 가 처리)
			var go := (stop_z - z0) / speed
			if u < go:
				var k := u / go
				return Vector3(x0, 0, lerpf(z0, stop_z, 1.0 - pow(1.0 - k, 2.0)))
			if path == Path.HOOK:
				var back := u - go - 1.6
				if back <= 0.0:
					return Vector3(x0 + sin((u - go) * 3.0) * 0.4, 0, stop_z)
				return Vector3(x0 + side * back * back * 2.0, 0, stop_z - back * back * 6.0)
			return Vector3(x0, 0, stop_z)
	return Vector3(x0, 0, z0 + speed * u)


func _advance(dt: float) -> void:
	s += dt
	if path == Path.DIVE:
		var go := (stop_z - z0) / speed
		var hold := 1.7
		if s >= go + hold:
			if _dive_t < 0.0:
				# 급강하: 지금 플레이어 쪽으로 방향을 정하고 가속
				_dive_t = 0.0
				_dive_from = _pos
				var tp := Main.inst.player.global_position
				_dive_dir = Vector3(tp.x - _pos.x, 0, tp.z - _pos.z + 6.0).normalized()
				if _dive_dir.z < 0.3:
					_dive_dir = Vector3(_dive_dir.x, 0, 0.3).normalized()
				Sfx.play("dash", 0.1, -6.0)
			_dive_t += dt
			_pos = _dive_from + _dive_dir * (6.0 * _dive_t + 9.0 * _dive_t * _dive_t)
		else:
			_pos = _path_pos(s)
	else:
		_pos = _path_pos(s)
	_off = _off.move_toward(Vector3.ZERO, 6.0 * dt) + knock * dt
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	global_position = Vector3(_pos.x + _off.x, 0, _pos.z + _off.z)


func _ai(dt: float) -> void:
	_advance(dt)
	var body: Node3D = j.body
	var vel := (_pos - _prev) / maxf(dt, 0.0001)
	_prev = _pos
	# 진행 방향을 바라보고, 옆으로 꺾을 때 날개를 기울인다. 멈춰 있을 때는 플레이어를 본다
	var face := vel
	if vel.length() < 1.0:
		face = Main.inst.player.global_position - global_position
	face.y = 0
	if face.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-face.x, -face.z), 1.0 - exp(-8.0 * dt))
	var lat := vel.dot(global_basis.x)
	_bank = lerpf(_bank, clampf(-lat * 0.07, -0.8, 0.8), 1.0 - exp(-6.0 * dt))
	body.rotation = Vector3(0, 0, _bank)
	body.position.y = FLY_Y + sin(t * 3.1) * 0.06
	_shoot_logic(dt)
	_check_exit()


## 피격 경직 중에도 경로는 계속 흐른다 (멈춰 떠 있지 않게)
func _update_hurt(dt: float) -> void:
	super(dt)
	_advance(dt)
	_check_exit()


func _update_stagger(dt: float) -> void:
	super(dt)
	_advance(dt)
	_check_exit()


## 화면 안에서만 쏜다: 플레이어보다 위쪽 · 화면 위 가장자리 안
func _shoot_logic(dt: float) -> void:
	var player := Main.inst.player
	var core: MeshInstance3D = j.core
	var cm: StandardMaterial3D = j.core_mat
	var on_screen := global_position.z > -16.0 and global_position.z < player.global_position.z - 2.5 and absf(global_position.x) < 11.0
	var ok := shots > 0 and on_screen and player.alive and Main.inst.state == Main.State.PLAY and _dive_t < 0.0
	if ok:
		fire_timer -= dt
	var tele := clampf(1.0 - fire_timer / 0.45, 0.0, 1.0) if ok else 0.0
	core.scale = Vector3.ONE * (1.0 + tele * 0.8)
	cm.emission_energy_multiplier = 0.8 + tele * 3.5
	if ok and fire_timer <= 0.0:
		shots -= 1
		fire_timer = randf_range(1.1, 1.6) if kind == Kind.DART else randf_range(1.3, 1.8)
		var to := player.global_position - global_position
		to.y = 0
		var d := to.normalized() if to.length() > 0.1 else Vector3.BACK
		var origin := core.global_position
		origin.y = global_position.y + 0.95
		var spread: Array = [0.0] if kind == Kind.DART else [-0.28, 0.0, 0.28]
		for a in spread:
			var dd := d.rotated(Vector3.UP, a)
			Main.inst.add_bullet(Bullet.make_enemy(origin + dd * 0.3, dd, SHOT_SPEED, kind == Kind.WING))
		FX.flash(origin, Color("ff8a40"), 0.45, 0.06)
		Sfx.play("eshot", 0.08, -6.0)
		punch = 0.4


## 화면 밖으로 빠져나가면 처치 없이 사라진다. 락온 중이면 풀릴 때까지 기다린다 (궁극기 대상이 사라지지 않게)
func _check_exit() -> void:
	var p := global_position
	var gone := p.z > BOTTOM_Z or absf(p.x) > SIDE_X or (s > 2.0 and p.z < TOP_Z - 3.0)
	if not gone or locked or not alive:
		return
	escaped = true
	alive = false
	remove_from_group("enemies")
	if Main.inst.has_method("on_enemy_escaped"):
		Main.inst.call("on_enemy_escaped", self)
	queue_free()


## 격추된 잔해는 공간에 남지 않고 도로와 함께 뒤로 흘러간다
func _update_death(dt: float) -> void:
	super(dt)
	global_position.z += WorldFlow.road_v() * 0.35 * dt
