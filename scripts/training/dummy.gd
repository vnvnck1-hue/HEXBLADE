class_name TrainingDummy
extends Enemy
## 전투 테스트용 허수아비. Enemy 를 그대로 이어받아 검·총·레이저·미사일 락온·패링·절단 연출이 실제 적과 똑같이 들어간다.
## 바닥 받침에 꽂힌 기둥 위 몸통이 맞을 때마다 맞은 쪽으로 젖혀졌다 스프링처럼 돌아오고, 밀려나도 제자리로 되돌아온다.
##
##  immortal  무적: 체력이 1 아래로 내려가지 않고, 1.6초 동안 안 맞으면 다시 가득 찬다 (끝없이 때려 보기)
##            끄면 실제로 쓰러지고(죽음 연출) TrainingMain 이 잠시 뒤 다시 세운다
##  attack    반격: 패링 탄(금빛 예고)만 쏜다 → 패링 연습
##  mover     이동: 기준 자리를 중심으로 좌우로 왕복한다 → 움직이는 대상 조준·돌진 확인

const DUMMY_HP := 60            # × HP_SCALE(2.5) = 150
const REGEN_DELAY := 1.6
const SWAY := 3.2               # 이동 모드 왕복 폭 (m)
const SWAY_SPEED := 0.9         # 왕복 각속도 (rad/s)

var anchor := Vector3.ZERO
var immortal := true
var attack := false
var mover := false
var idle_t := 0.0
var _phase := 0.0


func _ready() -> void:
	hp = DUMMY_HP
	super._ready()
	evade.chance = 0.0
	orb_only = true
	fire_timer = randf_range(1.5, 2.5)
	desired = 99.0
	slice_size = Vector3(0.7, 0.8, 0.5)
	slice_color = Color("e9c98a")
	hp_bar_y = 2.25
	_phase = randf() * TAU


## 허수아비 몸: 받침(바닥 고정) + 기둥 + 몸통 · 머리 · 가로대 팔 · 가슴 과녁(코어)
func _build(v: Node3D) -> Dictionary:
	var jd := {}
	# 받침과 기둥 아랫부분은 바닥에 남는다
	Build.cyl(v, 0.48, 0.12, Vector3(0, 0.06, 0), Color("3a3850"))
	Build.cyl(v, 0.36, 0.06, Vector3(0, 0.15, 0), Color("5c5a72"))
	Build.cyl(v, 0.07, 0.5, Vector3(0, 0.4, 0), Color("8a8070"))
	var body := Build.pivot(v, Vector3(0, 1.0, 0), "Body")
	jd.body = body
	# 기둥 윗부분은 몸통과 함께 젖혀진다
	Build.cyl(body, 0.065, 0.42, Vector3(0, -0.36, 0), Color("8a8070"))
	var torso := Build.box(body, Vector3(0.66, 0.74, 0.42), Vector3(0, 0.05, 0), Color("e9c98a"))
	Build.box(body, Vector3(0.7, 0.12, 0.46), Vector3(0, -0.3, 0), Color("b8925a"))
	Build.box(body, Vector3(0.7, 0.08, 0.46), Vector3(0, 0.36, 0), Color("b8925a"))
	# 줄로 묶은 듯한 가로 띠
	Build.box(body, Vector3(0.68, 0.05, 0.44), Vector3(0, 0.12, 0), Color("6c5434"))
	# 가로대 팔
	Build.box(body, Vector3(1.5, 0.12, 0.12), Vector3(0, 0.22, 0.02), Color("8a8070"))
	Build.box(body, Vector3(0.18, 0.2, 0.2), Vector3(0.78, 0.22, 0.02), Color("e9c98a"))
	Build.box(body, Vector3(0.18, 0.2, 0.2), Vector3(-0.78, 0.22, 0.02), Color("e9c98a"))
	# 머리: 자루 머리 + 눈 대신 엑스 표시
	Build.box(body, Vector3(0.42, 0.38, 0.38), Vector3(0, 0.66, 0), Color("f0dcae"))
	Build.box(body, Vector3(0.22, 0.04, 0.02), Vector3(0, 0.7, -0.2), Color("4a3a2a"), Vector3(0, 0, 40))
	Build.box(body, Vector3(0.22, 0.04, 0.02), Vector3(0, 0.7, -0.2), Color("4a3a2a"), Vector3(0, 0, -40))
	# 가슴 과녁: 흰 테 + 빨간 코어 (코어는 패링 탄 준비 때 금빛으로 부푼다)
	Build.cyl(body, 0.26, 0.02, Vector3(0, 0.05, -0.215), Color("f6f2ea"), Vector3(90, 0, 0))
	Build.cyl(body, 0.18, 0.025, Vector3(0, 0.05, -0.22), Color("d0283a"), Vector3(90, 0, 0))
	var sm := SphereMesh.new()
	sm.radius = 0.09
	sm.height = 0.18
	var core := MeshInstance3D.new()
	core.mesh = sm
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Pal.E_RED
	cm.emission_enabled = true
	cm.emission = Pal.E_RED
	cm.emission_energy_multiplier = 0.6
	core.material_override = cm
	core.position = Vector3(0, 0.05, -0.24)
	body.add_child(core)
	jd.core = core
	jd.core_mat = cm
	return jd


func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	if not alive:
		return
	if max_hp == 0:
		_init_hp()
	var eff := dmg * (2 if stagger_t > 0.0 else 1)
	if immortal and hp - eff < 1:
		hp = eff + 1            # 무적: 이번 타격 뒤 체력 1 로 버틴다
	idle_t = 0.0
	var tm := Main.inst as TrainingMain
	if tm:
		tm.record_hit(self, eff, source)
	super.take_hit(dmg, dir, pos, source)


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	if not alive or not landed:
		return
	idle_t += dt
	if immortal and idle_t > REGEN_DELAY and hp < max_hp:
		hp = max_hp
		FX.flash((j.body as Node3D).global_position, Color("9affc0"), 0.5, 0.08)


## 착지 후: 공격은 반격 모드에서만, 자리는 기준점(이동 모드면 좌우 왕복점)으로 스프링처럼 돌아간다
func _ai(dt: float) -> void:
	var body: Node3D = j.body
	var keep := global_position
	if attack:
		# 패링 탄은 화면에 2발까지만 (무리 배치에서 금빛 탄이 쏟아지지 않게): 자리가 없으면 발사를 미룬다
		if not orb_next and fire_timer < ORB_WINDUP + 0.05 and get_tree().get_nodes_in_group("parry_orbs").size() >= 2:
			fire_timer = ORB_WINDUP + randf_range(0.3, 0.9)
		super._ai(dt)            # 패링 탄 준비·발사만 쓰고 이동은 아래에서 덮어쓴다
		global_position = keep
	else:
		windup_k = 0.0
		var cm: StandardMaterial3D = j.core_mat
		cm.emission_energy_multiplier = 0.6
		(j.core as Node3D).scale = Vector3.ONE
		wob_v += (-wob * 220.0 - wob_v * 11.0) * dt
		wob += wob_v * dt
		body.position.y = 1.0
		body.rotation = Vector3(wob.x, 0.0, wob.y)
		_face_slowly(dt)
	var home := anchor
	if mover:
		_phase += dt * SWAY_SPEED
		home += Vector3(sin(_phase) * SWAY, 0, 0)
	global_position += knock * dt
	knock = knock.move_toward(Vector3.ZERO, 30.0 * dt)
	global_position = global_position.lerp(Vector3(home.x, global_position.y, home.z), 1.0 - exp(-(9.0 if mover else 3.5) * dt))
	global_position = Main.inst.push_out(global_position, radius)


func _face_slowly(dt: float) -> void:
	var d := Main.inst.player.global_position - global_position
	d.y = 0
	if d.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-d.x, -d.z), 1.0 - exp(-3.0 * dt))


## 맞아서 젖혀진 동안에도 기준점으로 끌려 돌아온다 (넉백이 크면 일단 밀려난다)
func _update_hurt(dt: float) -> void:
	super._update_hurt(dt)
	global_position = global_position.lerp(Vector3(anchor.x, global_position.y, anchor.z), 1.0 - exp(-1.2 * dt))
