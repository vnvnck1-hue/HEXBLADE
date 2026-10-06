class_name BugEnemy
extends Enemy
## 벌레형 괴생명체 공통 (개미 병정 BugAnt · 공벌레 BugPill).
## 기계 적과 다른 점만 덮어쓴다: Blender 모델(GLB) 사용 · 땅을 뚫고 기어 나오는 등장 · 체액이 튀는 피격 ·
## 뒤집혀 다리를 버둥대다 터지는 죽음 / 광선검이면 몸이 두 동강 / 미사일·레이저 과부하는 그 자리에서 터짐.
## 애니메이션은 리그(AntRig · PillRig)가 하고, 하위 클래스는 _make_rig · _rig_update · _ai 만 채운다.
##
## 노드: self(위치·방향) > visual > body(피격 젖힘·눌림, Enemy 기본 동작) > pose(죽음 뒤집기) > [roller >] model(GLB)

enum Death2 { FLIP, POP, SEVER }

const GOO: Array[Color] = [Color("f2ff8a"), Color("b8e84a"), Color("6aa830"), Color("3c6a1e")]
const DIRT: Array[Color] = [Color("7a7066"), Color("6a6158"), Color("4e463f"), Color("332d29")]
const EMERGE_TIME := 0.62
const FLIP_TIME := 1.25

var model: Node3D
var pose: Node3D
var emerge_t := 0.0
var bug_death := Death2.FLIP
var flip_side := 1.0
var _goo_t := 0.0
var _severed: Node3D
var _sev_vel := Vector3.ZERO
var _sev_spin := Vector3.ZERO
var _dirt_t := 0.0
var eyes: Array[MeshInstance3D] = []
## 체액 색 (피격·죽음 파편). 하위 클래스가 바꾼다 (촘퍼 = 노랑). splat_kind: 바닥 얼룩 색 (0 초록 · 1 노랑 · 2 애벌레 크림)
var goo: Array[Color] = GOO
var splat_kind := 0
## 공격 빈도 배율 (벌레 아레나 위험도): 1 보다 크면 공격 쿨타임(attack_cd · roll_cd)이 그만큼 빨리 돈다
var aggro := 1.0

static var _splat_mesh: CylinderMesh
static var _splat_mats: Array[StandardMaterial3D] = []
static var _eye_mesh: SphereMesh
## 모델 PackedScene 캐시. 마지막 개체가 사라지면 리소스가 풀려 다음 등장 때 디스크에서 다시 읽는다
## (촘퍼 = 2048 텍스처 포함 약 75ms 끊김) — 정적으로 붙잡아 두고, 벌레 아레나는 씬을 불러올 때 미리 읽는다.
static var _scenes := {}
const MODELS: Array[String] = ["res://assets/models/bug_grub.glb", "res://assets/models/bug_chomper.glb",
	"res://assets/models/bug_ant.glb", "res://assets/models/bug_pillbug.glb"]


## 벌레 모델을 미리 읽어 붙잡아 둔다 (전투 중 첫 등장 끊김 방지). 씬을 불러오는 중에 부른다 — 4종 합쳐 약 90ms
static func warm() -> void:
	for p in MODELS:
		model_scene(p)


## 첫 등장 때 한 번 계산하는 리그 캐시(애벌레 스키닝 약 38ms · 공벌레 말림 높이표 약 12ms)를 미리 만든다.
## 씬을 불러오는 첫 프레임에 부른다 (보이지 않는 곳에서 끊김을 치른다)
static func warm_rigs() -> void:
	BugSound.ensure()        # 벌레 효과음 합성 (첫 벌레 등장 때 수십 ms)
	SlimeTrail._material()
	if GrubRig._skin_mesh == null:
		var gm := model_scene(BugGrub.MODEL).instantiate() as Node3D
		var body := gm.find_child("body", true, false) as MeshInstance3D
		if body and body.mesh is ArrayMesh:
			GrubRig._build_skin(body.mesh as ArrayMesh)
		gm.free()
	if PillRig._LIFT.is_empty():
		var roller := Node3D.new()
		var pm := model_scene(BugPill.MODEL).instantiate() as Node3D
		roller.add_child(pm)
		PillRig.new().setup(pm, roller)
		roller.free()


static func model_scene(path: String) -> PackedScene:
	var ps: PackedScene = _scenes.get(path)
	if ps == null:
		ps = load(path) as PackedScene
		_scenes[path] = ps
	return ps


## 하위 클래스가 덮어쓴다
func _model_path() -> String:
	return ""


## 리그를 만들고 돌려준다 (model 은 이미 트리에 있다)
func _make_rig() -> void:
	pass


## 리그 입력을 채우고 update 를 부른다 (살아 있는 동안 매 물리 프레임)
func _rig_update(_dt: float) -> void:
	pass


## 광선검에 잘릴 때 떨어져 나갈 노드 (개미 = 머리, 공벌레 = 앞 몸통)
func _sever_node() -> Node3D:
	return null


## 죽음 연출 중 리그 입력 (dead_k 등)
func _rig_dead(_dt: float, _k: float) -> void:
	pass


func _build(v: Node3D) -> Dictionary:
	var body := Node3D.new()
	body.name = "body"
	v.add_child(body)
	pose = Node3D.new()
	pose.name = "pose"
	body.add_child(pose)
	model = model_scene(_model_path()).instantiate() as Node3D
	_attach_model(pose, model)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.set_meta("keep_mat", true)      # 파편(Debris)이 원래 색을 쓰게
	# 눈: 평소엔 검은 눈 위에 꺼진 발광체, 공격 예고 때 붉게 빛난다 (Enemy 의 core / core_mat 계약)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = Color(0.05, 0.02, 0.02)
	cm.emission_enabled = true
	cm.emission = Pal.E_RED
	cm.emission_energy_multiplier = 0.0
	cm.roughness = 0.15
	if _eye_mesh == null:
		_eye_mesh = SphereMesh.new()
		_eye_mesh.radius = 0.05
		_eye_mesh.height = 0.1
		_eye_mesh.radial_segments = 10
		_eye_mesh.rings = 5
	var core: MeshInstance3D
	for k in ["pt_eye_l", "pt_eye_r"]:
		var pt := model.find_child(k, true, false) as Node3D
		if pt == null:
			continue
		var eye := MeshInstance3D.new()
		eye.mesh = _eye_mesh
		eye.material_override = cm
		eye.scale = Vector3.ONE * 0.0001     # 예고 때만 커진다 (Enemy 가 core.scale 을 쓰는 곳이 있어 첫 눈을 core 로)
		eye.set_meta("keep_mat", true)
		pt.add_child(eye)
		eyes.append(eye)
		if core == null:
			core = eye
	return {"body": body, "core": core, "core_mat": cm}


## 기본: pose 아래에 바로 붙인다 (공벌레는 굴림 피벗을 끼운다)
func _attach_model(p: Node3D, m: Node3D) -> void:
	p.add_child(m)


func _ready() -> void:
	BugSound.ensure()
	super._ready()
	(j.body as Node3D).position = Vector3(0, -1.2, 0)
	evade.chance = 0.0          # 기계 드론의 뒷걸음질·이탈 대시는 쓰지 않는다 (벌레는 자기 방식으로 움직인다)
	_make_rig()


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	if alive and not dying:
		_rig_update(dt)
		_eye_glow()
		if aggro > 1.0 and landed:
			for k: String in ["attack_cd", "roll_cd"]:
				if k in self:
					set(k, float(get(k)) - (aggro - 1.0) * dt)


## 눈 발광: core_mat 밝기를 따라 두 눈 크기를 맞춘다
func _eye_glow() -> void:
	var cm: StandardMaterial3D = j.core_mat
	var k := clampf(cm.emission_energy_multiplier / 3.0, 0.0, 1.0)
	for eye in eyes:
		eye.scale = Vector3.ONE * maxf(0.0001, k * 1.25)


# ── 등장: 땅을 뚫고 기어 나온다 ─────────────────

func _update_entry(dt: float) -> void:
	var body: Node3D = j.body
	if emerge_t == 0.0 and near_player(14.0):
		Sfx.play("bug_dig", 0.15, -8.0)
	emerge_t += dt
	var k := clampf(emerge_t / EMERGE_TIME, 0.0, 1.0)
	# 두세 번 들썩이며 올라온다 (꿈틀 — 쭉 올라오지 않는다)
	var steps := k + sin(k * TAU * 2.5) * 0.06 * (1.0 - k)
	body.position.y = lerpf(-1.2, 0.0, ease(steps, 0.6))
	body.rotation = Vector3(sin(emerge_t * 23.0) * 0.12, 0, sin(emerge_t * 19.0) * 0.1) * (1.0 - k)
	shadow.scale = Vector3.ONE * lerpf(0.3, 1.0, k)
	_set_emerge(k)
	_dirt_t -= dt
	if _dirt_t <= 0.0:
		_dirt_t = 0.07
		var p := global_position + Vector3(randf_range(-0.4, 0.4), 0.1, randf_range(-0.4, 0.4))
		FX.puffs(p, 2, DIRT, 0.35, 0.35, 0.5)
		FX.sparks(p, 3, DIRT, 3.5, 0.4, -14.0, 0.06)
	if k >= 1.0:
		landed = true
		body.position = Vector3.ZERO
		body.rotation = Vector3.ZERO
		_set_emerge(1.0)
		punch = 0.8
		FX.land_dust(global_position)
		Sfx.play("land", 0.15, -6.0)


## 패링 경직: Enemy 기본 동작은 드론 높이(1m)를 절대값으로 쓰므로 벌레는 바닥 기준으로 되돌린다
func _update_stagger(dt: float) -> void:
	super._update_stagger(dt)
	(j.body as Node3D).position.y -= 1.0
	if is_instance_valid(stun_halo):
		stun_halo.position.y = hp_bar_y - 0.2


## 하위 클래스: 리그의 emerge_k 를 맞춘다
func _set_emerge(_k: float) -> void:
	pass


# ── 피격: 체액이 튄다 ───────────────────────────

func _hit_spark(dmg: int, dir: Vector3, pos: Vector3, source: String) -> void:
	super._hit_spark(dmg, dir, pos, source)
	if not is_inside_tree():
		return
	var c := (j.body as Node3D).global_position + Vector3(0, _goo_height(), 0)
	FX.sparks(c + dir * -0.2, 4 + mini(dmg, 6), goo, 4.5, 0.4, -16.0, 0.06)
	if randf() < 0.3:
		Sfx.play("bug_chitter", 0.2, -10.0)


## 체액이 튀는 높이 (몸통 중심)
func _goo_height() -> float:
	return 0.7


# ── 죽음 ───────────────────────────────────────

func die(dir := Vector3.ZERO, source := "bullet") -> void:
	if not alive:
		return
	set_locked(false)
	alive = false
	dying = true
	death_t = 0.0
	remove_from_group("enemies")
	death_dir = Vector3(dir.x, 0, dir.z)
	if death_dir.length() < 0.01:
		death_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	death_dir = death_dir.normalized()
	kill_source = source
	warn_glow = false
	charge_on = false
	_end_warn()
	if is_instance_valid(hp_bar):
		hp_bar.queue_free()
	if is_instance_valid(stun_halo):
		stun_halo.queue_free()
	_set_flash(false)
	(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 0.0
	Main.inst.on_enemy_killed(self)
	match source:
		"slash", "phantom":
			bug_death = Death2.SEVER
		"missile", "parry":
			bug_death = Death2.POP if randf() < 0.6 else Death2.FLIP
		"laser":
			bug_death = Death2.POP if randf() < 0.4 else Death2.FLIP
		_:
			bug_death = Death2.FLIP
	# 맞은 방향 반대쪽(밀려나는 쪽)으로 뒤집힌다
	var l := global_basis.inverse() * death_dir
	flip_side = -1.0 if l.x > 0.0 else 1.0
	d_vel = death_dir * 3.0 + Vector3(0, 4.5, 0)
	var c := (j.body as Node3D).global_position + Vector3(0, _goo_height(), 0)
	FX.sparks(c, 14, goo, 6.5, 0.5, -16.0, 0.07)
	FX.flash(c, Color(0.9, 1.0, 0.6), 0.9, 0.06)
	Sfx.play("hit", 0.1, -2.0)
	Sfx.play("bug_chitter", 0.15, -4.0)
	match bug_death:
		Death2.POP:
			_pop(1.0)
		Death2.SEVER:
			_sever()


func _update_death(dt: float) -> void:
	death_t += dt
	var body: Node3D = j.body
	# 뒤집기: 튀어 올랐다 떨어지며 몸을 뒤집어 등으로 눕는다 → 다리 버둥 → 점점 잦아들다 체액을 터뜨리며 사라진다
	var k := clampf(death_t / 0.38, 0.0, 1.0)
	d_vel.y -= 22.0 * dt
	body.position.y = maxf(0.0, body.position.y + d_vel.y * dt)
	if body.position.y <= 0.0 and d_vel.y < 0.0:
		if d_vel.y < -3.0:
			FX.land_dust(global_position)
			Sfx.play("land", 0.15, -8.0)
		d_vel.y = -d_vel.y * 0.25 if d_vel.y < -3.0 else 0.0
	global_position += Vector3(d_vel.x, 0, d_vel.z) * dt
	d_vel.x *= exp(-4.0 * dt)
	d_vel.z *= exp(-4.0 * dt)
	global_position = Main.inst.push_out(global_position, radius * 0.7)
	_flip_pose(_ease_out_back(k))
	_rig_dead(dt, clampf(death_t / 0.25, 0.0, 1.0))
	shadow.scale = Vector3.ONE * 0.9
	_goo_t -= dt
	if _goo_t <= 0.0:
		_goo_t = randf_range(0.12, 0.25)
		FX.sparks(body.global_position + Vector3(0, 0.3, 0), 2, goo, 2.5, 0.3, -14.0, 0.05)
	if is_instance_valid(_severed):
		_update_severed(dt)
	if death_t >= FLIP_TIME:
		_pop(0.7)


## 뒤집힌 정도 a (0 → 1, 넘쳐도 된다): pose 를 앞뒤 축으로 돌리고 등이 바닥에 닿게 내린다
func _flip_pose(a: float) -> void:
	flip(pose, a, _flip_height(), flip_side)


## 몸 두께 h 의 절반 높이를 축으로 앞뒤 축 회전 → 도는 중에도 바닥에 파묻히지 않고, 다 뒤집히면 등이 바닥에 닿는다
static func flip(p: Node3D, a: float, h: float, side: float) -> void:
	var b := Basis(Vector3.BACK, PI * a * side)
	var pivot := Vector3(0, h * 0.5, 0)
	p.basis = b
	p.position = pivot - b * pivot


## 뒤집혔을 때 몸 원점을 들어 올릴 높이 (몸 두께)
func _flip_height() -> float:
	return 0.6


static func _ease_out_back(x: float) -> float:
	var c1 := 1.7
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


## 터짐: 체액 폭발 + 몸 조각 + 바닥 얼룩, 그리고 사라진다
func _pop(k: float) -> void:
	var body: Node3D = j.body
	var c := body.global_position + Vector3(0, _goo_height() * 0.8, 0)
	FX.sparks(c, int(22 * k), goo, 8.0 * k, 0.55, -18.0, 0.09)
	FX.puffs(c, 4, goo, 0.7 * k, 0.6 * k, 0.55)
	FX.flash(c, Color(0.85, 1.0, 0.55), 1.3 * k, 0.07)
	FX.shockwave(Vector3(c.x, global_position.y + 0.05, c.z), Color(0.75, 0.95, 0.45), 2.2 * k, 0.25, 0.05)
	Debris.burst(body, c, 5.0 * k, 4.0 * k, death_dir * 2.0)
	splat(Vector3(c.x, global_position.y, c.z), 0.9 + k * 0.5, splat_kind)
	Sfx.play("bug_squish", 0.15, -2.0)
	Sfx.play("boom", 0.15, -12.0)
	if Main.inst.player.global_position.distance_to(global_position) < 12.0:
		Main.inst.shake(0.12 * k)
	if is_instance_valid(_severed):
		Debris.burst(_severed, _severed.global_position, 3.0, 3.0)
		_severed.queue_free()
	dying = false
	queue_free()


## 광선검: 떨어져 나갈 부분을 몸에서 떼어 날려 보내고, 남은 몸은 뒤집혀 버둥댄다
func _sever() -> void:
	var part := _sever_node()
	if part == null:
		return
	var xf := part.global_transform
	part.get_parent().remove_child(part)
	FX.root.add_child(part)
	part.global_transform = xf
	_severed = part
	var side := Vector3(-death_dir.z, 0, death_dir.x) * (1.0 if randf() < 0.5 else -1.0)
	_sev_vel = death_dir * 3.5 + side * 1.5 + Vector3(0, 5.5, 0)
	_sev_spin = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(8.0, 13.0)
	var c := xf.origin
	FX.sparks(c, 24, goo, 7.0, 0.6, -14.0, 0.08)
	FX.sparks(c, 10, [Pal.BLADE, Color.WHITE], 6.0, 0.3, -6.0, 0.06)
	FX.flash(c, Color(1.0, 0.85, 0.7), 1.2, 0.08)
	Sfx.play("slash", 0.0, 2.0)


func _update_severed(dt: float) -> void:
	_sev_vel.y -= 20.0 * dt
	var p := _severed.global_position + _sev_vel * dt
	var floor_y := Main.gy(p) + 0.12
	if p.y < floor_y:
		p.y = floor_y
		if _sev_vel.y < -2.5:
			_sev_vel.y = -_sev_vel.y * 0.3
			FX.sparks(p, 6, goo, 3.0, 0.3, -14.0, 0.05)
		else:
			_sev_vel.y = 0.0
		_sev_vel.x *= 0.75
		_sev_vel.z *= 0.75
		_sev_spin *= 0.8
	_severed.global_position = p
	if _sev_spin.length() > 0.05:
		_severed.rotate(_sev_spin.normalized(), _sev_spin.length() * dt)
	_goo_t -= dt * 0.5
	if _goo_t <= 0.0:
		FX.sparks(p, 2, goo, 2.0, 0.3, -14.0, 0.05)


const SPLAT_GROUP := "bug_splat"


## 바닥에 납작한 체액 얼룩을 남긴다 (몇 초 뒤 오그라들며 사라짐). 크기는 단계로 묶어 넘긴다.
static func splat(at: Vector3, size: float, kind := 0) -> void:
	if FX.root == null:
		return
	if _splat_mesh == null:
		_splat_mesh = CylinderMesh.new()
		_splat_mesh.top_radius = 0.5
		_splat_mesh.bottom_radius = 0.5
		_splat_mesh.height = 0.01
		_splat_mesh.radial_segments = 14
		_splat_mesh.rings = 1
		for c in [Color(0.5, 0.75, 0.22), Color(1.0, 0.78, 0.16), Color(0.93, 0.9, 0.78)]:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.roughness = 0.15
			m.metallic_specular = 0.8
			_splat_mats.append(m)
	var mi := MeshInstance3D.new()
	mi.mesh = _splat_mesh
	mi.material_override = _splat_mats[clampi(kind, 0, _splat_mats.size() - 1)]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.add_to_group(SPLAT_GROUP)        # 청소 질주(FloorVac)가 빨아들일 수 있게
	FX.root.add_child(mi)
	mi.global_position = at + Vector3(0, 0.015, 0)
	mi.rotation.y = randf() * TAU
	var s := snappedf(size, 0.25)
	mi.scale = Vector3(s * 0.2, 1.0, s * 0.16)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(s, 1.0, s * 0.8), 0.18).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.5)
	tw.tween_property(mi, "scale", Vector3(0.01, 1.0, 0.01), 0.8).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


func _exit_tree() -> void:
	if is_instance_valid(_severed):
		_severed.queue_free()


# ── 공용 이동 도우미 ───────────────────────────

## 플레이어를 향한 수평 방향과 거리.
## 놓쳤을 때(연기 속 은신)는 플레이어 대신 배회 목적지를, 멈춰 서 있으면 두리번거리는 쪽을 가리킨다.
func _to_player() -> Vector3:
	if wander.on:
		var g := wander.goal - global_position if wander.walking else wander.face_dir() * 4.0
		g.y = 0
		return g
	var d := Main.inst.player.global_position - global_position
	d.y = 0
	return d


## 플레이어가 가까이 있나 (작은 소리는 가까울 때만 낸다)
func near_player(d: float) -> bool:
	return Main.inst != null and Main.inst.player != null and global_position.distance_to(Main.inst.player.global_position) < d


## 다른 적과 겹치지 않게 미는 힘
func _separation(r: float) -> Vector3:
	var out := Vector3.ZERO
	for o in Enemy.live(get_tree()):
		if o == self or not is_instance_valid(o):
			continue
		var d: Vector3 = global_position - (o as Node3D).global_position
		d.y = 0
		var l := d.length()
		if l < r and l > 0.001:
			out += d / l * (r - l)
	return out


## 방향으로 몸을 돌린다. 돌린 각속도(rad/s)를 돌려준다 (리그의 몸 기울임용)
func _face(dir: Vector3, dt: float, rate: float) -> float:
	if dir.length() < 0.01:
		return 0.0
	var before := rotation.y
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-rate * dt))
	return wrapf(rotation.y - before, -PI, PI) / maxf(dt, 0.0001)
