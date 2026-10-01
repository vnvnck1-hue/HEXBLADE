extends Enemy
## 중간보스 후광의 파수자 (HALO WARDEN): 심연 북쪽 위에 떠 있는 성유물 거체.
## 흑철 성유물 몸통(갈라진 판 사이로 살덩이 심장이 빛난다) · 두건 아래 눈 무리와 가운데 큰 눈(약점) ·
## 머리 뒤에서 도는 칼날 후광 · 7m 마디 두 개짜리 거대한 팔 · 아래로 늘어진 살덩이 관.
## 1페이즈: 후광 나선 · 심판의 창 · 움켜쥐기 · 부름(허스크 소환)
## 2페이즈(체력 50%): 전장이 십자로 줄어들고 분출구가 깨어난다 → 칼날 폭풍 · 멸각의 시선 · 연속 움켜쥐기 · 이중 나선 · 부름
## 움켜쥐기 뒤 손이 박혀 있는 동안과 멸각의 시선 직후에는 가운데 눈이 드러나 피해가 두 배다.
## 본체는 전장 밖이라 검이 닿지 않는다 → 박힌 손을 베거나, 총·레이저·미사일로 몸통을 친다.

signal phase_changed(phase: int)
signal defeated

const Hand := preload("res://scripts/abyss/warden_hand.gd")
const Shot := preload("res://scripts/abyss/abyss_shot.gd")
const Stage := preload("res://scripts/abyss/abyss_stage.gd")

enum St { ENTER, FIGHT, TRANSITION, DYING, DEAD }

const MAX_HP := 900.0
const PHASE2_AT := 0.5
const HOME := Vector3(0, 0, -14.8)
const HOVER := 3.2                 # 몸통 원점 높이
const RISE_FROM := -20.0
const ENTER_TIME := 4.2
const ARM_L := 7.0
const SLAM_R := 2.8
const LANCE_W := 1.1
const LANCE_LEN := 40.0
const GLARE_W := 2.3
const PATTERNS_1 := ["spiral", "lances", "grasp", "summon"]
const PATTERNS_2 := ["storm", "glare", "grasp2", "spiral2", "summon"]
const NAMES := {
	"spiral": "후광 나선", "lances": "심판의 창", "grasp": "움켜쥐기", "summon": "부름",
	"storm": "칼날 폭풍", "glare": "멸각의 시선", "grasp2": "연속 움켜쥐기", "spiral2": "이중 나선",
}
const PINK := Color(1.0, 0.12, 0.4)
const CRIMSON := Color(1.0, 0.07, 0.15)
const PALE := Color(1.0, 0.82, 0.86)
const HALO_C := Color(1.0, 0.78, 0.55)   # 후광은 붉은 배경과 대비되는 백금빛
const LANCE := Color(0.75, 0.3, 0.38)   # 심판의 창 빔 색 (빔 셰이더가 HDR 로 키운다)

const IRON := Color("232126")
const IRON_LIGHT := Color("3e3a41")
const BRONZE := Color("5c4a3a")
const GOLD := Color("a8844a")
const BONE := Color("a89a80")
const FLESH := Color("5a1420")

var stage: Stage
var bar: Node
var st := St.ENTER
var st_t := 0.0
var phase := 1
var boss_hp := MAX_HP
var skip_to_phase2 := false
var pat := ""
var pat_i := -1
var order: Array = []
var pt := 0.0
var ps := {}
var rest := 2.0
var weak := false
var weak_t := 0.0
var flash_cd := 0.0
var hit_snd_cd := 0.0
var threats: Array = []
var meshes: Array = []

var rig: Node3D                   # 몸 전체 (떠오름 · 흔들림)
var torso: Node3D
var head: Node3D
var halo: Node3D
var halo_glow_mat: StandardMaterial3D
var halo_spin := 0.4
var halo_blades: Array[Node3D] = []
var eye: MeshInstance3D
var eye_mat: StandardMaterial3D
var small_eyes: Array[MeshInstance3D] = []
var heart_mat: StandardMaterial3D
var heart_light: OmniLight3D
var eye_light: OmniLight3D
var arms: Array = []              # {side, upper, fore, hand, part, m, goal, rate, down, shoulder_l}
var tendrils: Array = []          # {nodes, ph, root_off}
var lean := Vector2.ZERO
var lean_v := Vector2.ZERO
var eye_open := 0.0
var _beams: Array = []
var _warns: Array = []
var _storm: Array = []            # 날아간 칼날 [node, a, fire_t]
var _falling: Array = []          # 부서져 떨어지는 조각 [node, vel, spin]
var _fx_t := 0.0


func _ready() -> void:
	add_to_group("enemies")
	is_boss = true
	radius = 3.2
	slice_size = Vector3(4, 4, 4)
	slice_color = IRON
	visual = Node3D.new()
	add_child(visual)
	_build_rig()
	j = {"body": torso, "core": eye}
	shadow = FX.blob_shadow(self, 0.1, 0.0)
	shadow.visible = false
	landed = false
	global_position = HOME
	rig.position.y = RISE_FROM
	meshes = find_children("*", "MeshInstance3D", true, false)
	meshes.erase(shadow)
	_add_hands.call_deferred()
	order = PATTERNS_1.duplicate()
	order.shuffle()
	if order[0] == "summon":
		order.reverse()


func _add_hands() -> void:
	for a in arms:
		get_parent().add_child(a.part)


# ── 조립 ────────────────────────────────────────────────

func _glow(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.roughness = 0.4
	return m


func _build_rig() -> void:
	rig = Build.pivot(visual, Vector3(0, HOVER, 0), "Rig")
	torso = Build.pivot(rig, Vector3.ZERO, "Torso")
	# 살덩이 심장 (판 사이로 비친다)
	heart_mat = _glow(Color(0.9, 0.06, 0.12), 1.6)
	var hc := CylinderMesh.new()
	hc.top_radius = 1.25
	hc.bottom_radius = 0.45
	hc.height = 3.0
	hc.radial_segments = 12
	var heart := MeshInstance3D.new()
	heart.mesh = hc
	heart.material_override = heart_mat
	torso.add_child(heart)
	heart.position = Vector3(0, 0.2, 0)
	heart_light = OmniLight3D.new()
	heart_light.light_color = Color(1.0, 0.1, 0.16)
	heart_light.light_energy = 4.0
	heart_light.omni_range = 13.0
	torso.add_child(heart_light)
	heart_light.position = Vector3(0, 0.4, 2.0)
	# 성유물 몸통: 위가 넓고 아래가 좁은 종 모양으로 여덟 장의 흑철 판이 둘러싼다 (판 사이가 갈라져 빛난다)
	for i in 8:
		var a := TAU * i / 8.0 + PI / 8.0
		var pv := Build.pivot(torso, Vector3(cos(a) * 1.05, 0.25, sin(a) * 1.05), "Plate%d" % i)
		pv.rotation = Vector3(0, -a + PI * 0.5, 0)
		var plate := Build.bevel(pv, Vector3(0.92, 3.1, 0.22), Vector3(0, 0, 0.18), IRON if i % 2 == 0 else IRON_LIGHT, 0.08, Vector3(-17.0, 0, 0), 0.62)
		plate.name = "Plate"
		Build.bevel(pv, Vector3(0.18, 2.4, 0.08), Vector3(0, 0.05, 0.36), BRONZE, 0.03, Vector3(-17.0, 0, 0), 0.6)
	# 청동 띠 셋
	for spec in [[1.55, 1.55], [0.75, 0.2], [0.55, -1.1]]:
		var tm := TorusMesh.new()
		tm.inner_radius = spec[0] - 0.12
		tm.outer_radius = spec[0] + 0.1
		tm.rings = 24
		var ring := MeshInstance3D.new()
		ring.mesh = tm
		ring.material_override = Pal.lit(BRONZE)
		torso.add_child(ring)
		ring.position = Vector3(0, spec[1], 0)
		ring.scale = Vector3(1, 1.6, 1)
	# 앞가슴 갈비 네 쌍 (뼈)
	for k in 4:
		for s in [-1.0, 1.0]:
			var rib := Build.bevel(torso, Vector3(0.14, 0.14, 1.3 - k * 0.15), Vector3(s * 0.55, 1.1 - k * 0.42, 1.25 - k * 0.12), BONE, 0.04, Vector3(0, s * -38.0, s * -12.0))
			rib.name = "Rib"
	# 어깨 갑주와 가시
	for s in [-1.0, 1.0]:
		var sh := Build.pivot(torso, Vector3(s * 1.75, 1.45, 0), "Shoulder")
		Build.bevel(sh, Vector3(1.3, 0.8, 1.4), Vector3.ZERO, IRON_LIGHT, 0.12, Vector3(0, 0, s * -14.0), 0.8)
		Build.bevel(sh, Vector3(1.0, 0.25, 1.1), Vector3(0, 0.5, 0), GOLD, 0.06, Vector3(0, 0, s * -14.0), 0.8)
		for k in 3:
			var sp := CylinderMesh.new()
			sp.top_radius = 0.0
			sp.bottom_radius = 0.14
			sp.height = 1.1 - k * 0.2
			sp.radial_segments = 5
			var spike := MeshInstance3D.new()
			spike.mesh = sp
			spike.material_override = Pal.lit(BONE)
			sh.add_child(spike)
			spike.position = Vector3(s * (0.15 + k * 0.3), 0.85, -0.3 + k * 0.3)
			spike.rotation = Vector3(-0.2, 0, s * -0.5)
	# 머리: 두건 + 얼굴판 + 눈 무리
	head = Build.pivot(torso, Vector3(0, 2.4, 0.35), "Head")
	var hood := CylinderMesh.new()
	hood.top_radius = 0.05
	hood.bottom_radius = 0.95
	hood.height = 2.2
	hood.radial_segments = 10
	var hm := MeshInstance3D.new()
	hm.mesh = hood
	hm.material_override = Pal.lit(Color("1a181c"))
	head.add_child(hm)
	hm.position = Vector3(0, 0.55, -0.15)
	hm.rotation.x = -0.18
	Build.bevel(head, Vector3(1.0, 1.2, 0.3), Vector3(0, 0.1, 0.55), IRON, 0.1, Vector3(-8, 0, 0), 0.7)
	eye_mat = _glow(CRIMSON, 2.0)
	var em := SphereMesh.new()
	em.radius = 0.36
	em.height = 0.72
	eye = MeshInstance3D.new()
	eye.mesh = em
	eye.material_override = eye_mat
	head.add_child(eye)
	eye.position = Vector3(0, 0.12, 0.78)
	var sem := SphereMesh.new()
	sem.radius = 0.09
	sem.height = 0.18
	for k in 6:
		var a := TAU * k / 6.0
		var se := MeshInstance3D.new()
		se.mesh = sem
		se.material_override = _glow(CRIMSON, 3.0)
		head.add_child(se)
		se.position = Vector3(cos(a) * 0.55, 0.12 + sin(a) * 0.45, 0.72)
		small_eyes.append(se)
	eye_light = OmniLight3D.new()
	eye_light.light_color = CRIMSON
	eye_light.light_energy = 1.5
	eye_light.omni_range = 8.0
	head.add_child(eye_light)
	eye_light.position = Vector3(0, 0.1, 1.6)
	# 보스 윤곽을 세우는 차가운 림 조명 (붉은 배경에서 실루엣이 읽히도록)
	var rim := SpotLight3D.new()
	rim.light_color = Color(0.62, 0.78, 1.0)
	rim.light_energy = 9.0
	rim.spot_range = 30.0
	rim.spot_angle = 24.0
	rim.spot_attenuation = 0.5
	rim.light_volumetric_fog_energy = 0.0
	visual.add_child(rim)
	rim.position = Vector3(6.0, 16.0, 9.0)
	rim.look_at_from_position(rim.position, Vector3(0, HOVER + 1.0, 0), Vector3.UP)
	# 칼날 후광: 머리 뒤에서 카메라 쪽을 향해 세운 고리 + 칼날 열두 장
	halo = Build.pivot(torso, Vector3(0, 2.8, -0.9), "Halo")
	halo.rotation.x = deg_to_rad(-78.0)
	var spin := Build.pivot(halo, Vector3.ZERO, "Spin")
	var back := OmniLight3D.new()
	back.light_color = HALO_C
	back.light_energy = 2.5
	back.omni_range = 9.0
	halo.add_child(back)
	back.position = Vector3(0, 1.0, 0)
	var tm2 := TorusMesh.new()
	tm2.inner_radius = 2.6
	tm2.outer_radius = 2.95
	tm2.rings = 40
	tm2.ring_segments = 8
	var ring2 := MeshInstance3D.new()
	ring2.mesh = tm2
	ring2.material_override = Pal.lit(IRON_LIGHT)
	spin.add_child(ring2)
	halo_glow_mat = _glow(HALO_C, 2.5)
	var tm3 := TorusMesh.new()
	tm3.inner_radius = 2.48
	tm3.outer_radius = 2.58
	tm3.rings = 40
	tm3.ring_segments = 6
	var glow_ring := MeshInstance3D.new()
	glow_ring.mesh = tm3
	glow_ring.material_override = halo_glow_mat
	spin.add_child(glow_ring)
	for k in 12:
		var a := TAU * k / 12.0
		var bl := Build.pivot(spin, Vector3(cos(a) * 3.0, 0, sin(a) * 3.0), "Blade%d" % k)
		bl.rotation.y = -a
		Build.bevel(bl, Vector3(1.6, 0.12, 0.42), Vector3(0.7, 0, 0), IRON if k % 2 == 0 else BRONZE, 0.04, Vector3.ZERO, 0.4)
		var edge := MeshInstance3D.new()
		var eb := BoxMesh.new()
		eb.size = Vector3(1.3, 0.04, 0.05)
		edge.mesh = eb
		edge.material_override = halo_glow_mat
		bl.add_child(edge)
		edge.position = Vector3(0.65, 0.07, 0.2)
		halo_blades.append(bl)
	# 팔 둘
	for s in [-1.0, 1.0]:
		var up := Build.pivot(visual, Vector3.ZERO, "UpperArm")
		Build.bevel(up, Vector3(0.62, 0.62, ARM_L), Vector3(0, 0, -ARM_L * 0.5), IRON_LIGHT, 0.12, Vector3.ZERO, 0.85)
		Build.bevel(up, Vector3(0.3, 0.3, ARM_L * 0.6), Vector3(0, 0.36, -ARM_L * 0.5), BONE, 0.06)
		var fore := Build.pivot(visual, Vector3.ZERO, "ForeArm")
		Build.bevel(fore, Vector3(0.52, 0.52, ARM_L), Vector3(0, 0, -ARM_L * 0.5), IRON, 0.1, Vector3.ZERO, 0.8)
		Build.glow_box(fore, Vector3(0.08, 0.08, ARM_L * 0.8), Vector3(0, 0.3, -ARM_L * 0.5), CRIMSON, 1.6)
		var hand := Build.pivot(visual, Vector3.ZERO, "Hand")
		Build.bevel(hand, Vector3(1.2, 0.5, 1.2), Vector3(0, 0.25, 0), IRON_LIGHT, 0.1, Vector3.ZERO, 0.8)
		for k in 4:
			var a := TAU * k / 4.0 + PI * 0.25
			var claw := Build.pivot(hand, Vector3(cos(a) * 0.5, 0.1, sin(a) * 0.5), "Claw")
			claw.rotation = Vector3(0, -a + PI * 0.5, 0)
			Build.bevel(claw, Vector3(0.18, 1.1, 0.24), Vector3(0, -0.4, 0.15), BONE, 0.05, Vector3(-28, 0, 0), 0.4)
		var part := Hand.new()
		part.boss = self
		part.side = int(s)
		part.bind(hand)
		var sh := Vector3(s * 2.3, HOVER + 1.4, 0.2)
		arms.append({"side": s, "upper": up, "fore": fore, "hand": hand, "part": part, "m": Vector3.ZERO, "goal": Vector3.ZERO,
			"rate": 3.0, "down": false, "sh": sh})
	# 아래로 늘어진 살덩이 관
	var fl_mat := Pal.lit(FLESH)
	var seg_mesh := CylinderMesh.new()
	seg_mesh.top_radius = 0.16
	seg_mesh.bottom_radius = 0.12
	seg_mesh.height = 1.15
	seg_mesh.radial_segments = 6
	for k in 9:
		var a := TAU * k / 9.0
		var nodes: Array = []
		for i in 9:
			var mi := MeshInstance3D.new()
			mi.mesh = seg_mesh
			mi.material_override = fl_mat if i % 3 != 2 else heart_mat
			visual.add_child(mi)
			nodes.append(mi)
		tendrils.append({"nodes": nodes, "ph": randf() * TAU, "off": Vector3(cos(a) * 0.45, -1.3, sin(a) * 0.45)})


# ── 매 프레임 ───────────────────────────────────────────

func _physics_process(dt: float) -> void:
	t += dt
	st_t += dt
	flash_cd -= dt
	hit_snd_cd -= dt
	threats.clear()
	if st == St.DEAD:
		_update_falling(dt)
		return
	var player := Main.inst.player
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
	_update_body(dt, player)
	_update_arms(dt)
	_update_tendrils()
	_update_storm(dt)
	_update_falling(dt)
	for w in _warns:
		if is_instance_valid(w.mi):
			threats.append({"type": "circle", "pos": w.pos, "r": w.r})


func _update_enter(_dt: float) -> void:
	var k := clampf(st_t / ENTER_TIME, 0.0, 1.0)
	rig.position.y = lerpf(RISE_FROM, 0.0, 1.0 - pow(1.0 - k, 3.0)) + HOVER
	halo_spin = lerpf(0.0, 0.5, k)
	halo_glow_mat.emission_energy_multiplier = lerpf(0.0, 2.5, smoothstep(0.5, 0.9, k))
	if randf() < 0.4:
		stage.dust(global_position + Vector3(randf_range(-5, 5), randf_range(-6, 0), randf_range(-3, 3)), randf_range(2.0, 3.5), Color(0.5, 0.03, 0.07, 0.35), true, Vector3(0, 3.0, 0), 1.6)
	if st_t > 2.6 and not ps.has("roared"):
		ps.roared = true
		Main.inst.shake(0.6)
		Main.inst.hud.banner("WARNING", Color("ff3a4a"), "후광의 파수자 HALO WARDEN — 심연에서 떠오르다")
		Sfx.play("twind", 0.0, 2.0)
		Sfx.play("boom", 0.0, -2.0)
		AbyssFX.light_flash(global_position + Vector3(0, 6, 4), CRIMSON, 14.0, 30.0, 1.2)
		FX.shockwave(Vector3(0, 0.1, -10.0), CRIMSON, 14.0, 0.7, 0.12)
	if k >= 1.0:
		st = St.FIGHT
		st_t = 0.0
		ps.clear()
		landed = true
		rest = 1.2
		if is_instance_valid(bar):
			bar.set("threshold", PHASE2_AT)
			bar.call("set_phase", 1)
		if skip_to_phase2:
			boss_hp = MAX_HP * PHASE2_AT
			bar.call("set_hp", PHASE2_AT)
			_begin_transition()


func _update_fight(dt: float, player: Player) -> void:
	if pat == "":
		rest -= dt
		if rest <= 0.0 and player.alive and Main.inst.state == Main.State.PLAY:
			_next_pattern()
		return
	pt += dt
	var done := false
	match pat:
		"spiral": done = _p_spiral(dt, false)
		"spiral2": done = _p_spiral(dt, true)
		"lances": done = _p_lances(dt, player)
		"grasp": done = _p_grasp(dt, player, 2, 1.1)
		"grasp2": done = _p_grasp(dt, player, 3, 0.85)
		"summon": done = _p_summon(dt)
		"storm": done = _p_storm(dt, player)
		"glare": done = _p_glare(dt, player)
	if done:
		_end_pattern()


func _next_pattern() -> void:
	var list: Array = PATTERNS_1 if phase == 1 else PATTERNS_2
	pat_i += 1
	if pat_i >= order.size():
		pat_i = 0
		order = list.duplicate()
		order.shuffle()
	pat = order[pat_i]
	# 잡몹이 많으면 부름은 건너뛴다
	if pat == "summon" and Main.inst.enemies_left() > 5:
		pat = "spiral" if phase == 1 else "spiral2"
	pt = 0.0
	ps = {}
	if is_instance_valid(bar):
		bar.call("set_pattern", NAMES[pat])
	print("WARDEN_PATTERN %s t=%.1f hp=%.0f" % [pat, Main.inst.time, boss_hp])


func _end_pattern() -> void:
	pat = ""
	ps = {}
	rest = randf_range(1.2, 1.8) if phase == 1 else randf_range(0.8, 1.3)
	_clear_beams()
	_clear_warns()
	for a in arms:
		a.goal = _rest_goal(a)
		a.rate = 3.0
		_set_down(a, false)


# ── 몸 · 팔 · 관 ────────────────────────────────────────

func _update_body(dt: float, player: Player) -> void:
	if st != St.ENTER and st != St.DYING:
		rig.position.y = HOVER + sin(t * 0.9) * 0.35
	lean_v += (-lean * 30.0 - lean_v * 5.0) * dt
	lean += lean_v * dt
	var to := player.global_position - global_position
	to.y = 0
	var yaw := atan2(to.x, to.z) * 0.35
	torso.rotation = Vector3(lean.x + sin(t * 0.7) * 0.03, lerp_angle(torso.rotation.y, yaw, 1.0 - exp(-2.0 * dt)), lean.y + sin(t * 0.5) * 0.03)
	(halo.get_node("Spin") as Node3D).rotate_y(halo_spin * dt)
	head.rotation.x = sin(t * 1.1) * 0.05
	# 가운데 눈: 열리면 금백색으로 달아오른다 (약점)
	eye_open = move_toward(eye_open, 1.0 if weak else 0.0, dt * 4.0)
	eye_mat.albedo_color = CRIMSON.lerp(Color(1.0, 0.85, 0.5), eye_open)
	eye_mat.emission = eye_mat.albedo_color
	eye_mat.emission_energy_multiplier = 2.0 + eye_open * 5.0 + (sin(t * 20.0) * 0.8 if weak else 0.0)
	eye.scale = Vector3.ONE * (0.8 + eye_open * 0.5)
	eye_light.light_color = eye_mat.albedo_color
	eye_light.light_energy = 1.5 + eye_open * 4.0
	for i in small_eyes.size():
		small_eyes[i].scale = Vector3.ONE * (1.0 if fmod(t * 0.7 + i * 0.37, 3.0) > 0.12 else 0.2)
	heart_mat.emission_energy_multiplier = 1.4 + 0.6 * sin(t * 3.2) + punch * 2.0
	heart_light.light_energy = 3.5 + 1.5 * sin(t * 3.2)
	punch = move_toward(punch, 0.0, dt * 4.0)
	torso.scale = Vector3.ONE * (1.0 + punch * 0.04)


func _shoulder(a: Dictionary) -> Vector3:
	var sh: Vector3 = a.sh
	return global_position + Vector3(sh.x, rig.position.y + (sh.y - HOVER), sh.z)


func _rest_goal(a: Dictionary) -> Vector3:
	var s: float = a.side
	return _shoulder(a) + Vector3(s * 3.4, -6.5 + sin(t * 0.8 + s) * 0.3, 0.8)


func _set_down(a: Dictionary, on: bool) -> void:
	a.down = on
	var part := a.part as Enemy
	if is_instance_valid(part):
		part.landed = on
		if on:
			part.global_position = Vector3((a.m as Vector3).x, 0, (a.m as Vector3).z)


func _update_arms(dt: float) -> void:
	for a in arms:
		if not a.down and pat == "" and st != St.DYING:
			a.goal = _rest_goal(a)
		var m: Vector3 = a.m
		if m == Vector3.ZERO:
			m = _rest_goal(a)
		m = m.lerp(a.goal, 1.0 - exp(-float(a.rate) * dt))
		a.m = m
		_pose_arm(a, m)


## 두 마디 팔 IK: 팔꿈치는 바깥 위로 굽는다
func _pose_arm(a: Dictionary, hand_p: Vector3) -> void:
	var s := _shoulder(a)
	var d := hand_p - s
	var l := d.length()
	var reach := ARM_L * 1.96
	if l > reach:
		hand_p = s + d / l * reach
		d = hand_p - s
		l = reach
	var mid := (s + hand_p) * 0.5
	var pole := (Vector3.UP * 1.0 + Vector3(float(a.side), 0, 0) * 0.8).normalized()
	var axis := d / maxf(l, 0.001)
	var perp := (pole - axis * pole.dot(axis))
	perp = perp.normalized() if perp.length() > 0.01 else Vector3.UP
	var hgt := sqrt(maxf(0.0, ARM_L * ARM_L - l * l * 0.25))
	var elbow := mid + perp * hgt
	var up := a.upper as Node3D
	var fore := a.fore as Node3D
	var hand := a.hand as Node3D
	up.global_transform = Transform3D(_look(elbow - s), s)
	fore.global_transform = Transform3D(_look(hand_p - elbow), elbow)
	var hb := Basis.looking_at(Vector3(axis.x, 0, axis.z).normalized() if Vector2(axis.x, axis.z).length() > 0.05 else Vector3.FORWARD, Vector3.UP)
	hand.global_transform = Transform3D(hb, hand_p)


static func _look(v: Vector3) -> Basis:
	var n := v.normalized()
	return Basis.looking_at(n, Vector3.UP if absf(n.y) < 0.98 else Vector3.FORWARD)


func _update_tendrils() -> void:
	var base := global_position + Vector3(0, rig.position.y, 0)
	for td in tendrils:
		var p: Vector3 = base + (td.off as Vector3)
		var ph: float = td.ph
		var nodes: Array = td.nodes
		for i in nodes.size():
			var k := float(i + 1) / nodes.size()
			var sway := Vector3(sin(t * 1.1 + ph + k * 2.0), 0, cos(t * 0.8 + ph + k * 1.7)) * 0.35 * k
			var q := p + Vector3(0, -1.1, 0) + sway + (td.off as Vector3) * 0.15 * k
			var mi := nodes[i] as MeshInstance3D
			mi.global_transform = Transform3D(_look(q - p) * Basis(Vector3.RIGHT, -PI * 0.5), (p + q) * 0.5)
			p = q


# ── 패턴: 후광 나선 ─────────────────────────────────────

func _origin() -> Vector3:
	return Vector3(global_position.x, 0.95, global_position.z + 3.2)


func _p_spiral(dt: float, dual: bool) -> bool:
	var wind := 0.9
	var dur := 3.4 if not dual else 4.2
	if pt < wind:
		halo_spin = lerpf(0.5, 7.0, pt / wind)
		halo_glow_mat.emission_energy_multiplier = 2.5 + pt / wind * 5.0
		if not ps.has("snd"):
			ps.snd = true
			Sfx.play("twind", 0.05, -2.0)
		return false
	ps.ft = float(ps.get("ft", 0.0)) - dt
	var tt := pt - wind
	if tt < dur:
		if ps.ft <= 0.0:
			ps.ft = 0.075 if not dual else 0.09
			var o := _origin()
			var arms_n := 4 if not dual else 5
			var dir := 1.0 if not dual or fmod(tt, 1.6) < 0.8 else -1.0
			var base := tt * 1.5 * dir + float(ps.get("off", 0.0))
			for k in arms_n:
				var a := base + TAU * k / arms_n
				var d := Vector3(sin(a), 0, cos(a))
				Main.inst.add_bullet(Shot.make(o + d * 0.5, d, 5.0, PINK, 0.6))
			if dual and int(tt / 0.09) % 3 == 0:
				# 반대로 도는 느린 겹
				for k in 3:
					var a2 := -tt * 0.9 + TAU * k / 3.0
					var d2 := Vector3(sin(a2), 0, cos(a2))
					Main.inst.add_bullet(Shot.make(o + d2 * 0.5, d2, 3.4, CRIMSON, 0.7))
			if int(tt / 0.075) % 4 == 0:
				Sfx.play("eshot", 0.15, -12.0)
		return false
	halo_spin = move_toward(halo_spin, 0.5, dt * 10.0)
	halo_glow_mat.emission_energy_multiplier = 2.5
	return tt > dur + 0.6


# ── 패턴: 심판의 창 ─────────────────────────────────────

func _p_lances(dt: float, player: Player) -> bool:
	var tele := 1.0
	var fire := 0.35
	var gap := 0.25
	var cycle := tele + fire + gap
	var vol := int(pt / cycle)
	if vol >= 3:
		return pt > 3 * cycle + 0.3
	var lt := pt - vol * cycle
	if int(ps.get("vol", -1)) != vol:
		ps.vol = vol
		_clear_beams()
		var o := _origin()
		var aim := atan2(player.global_position.z - o.z, player.global_position.x - o.x)
		var offs: Array = [-0.48, -0.16, 0.16, 0.48] if vol % 2 == 0 else [-0.64, -0.32, 0.0, 0.32, 0.64]
		ps.angles = []
		for off in offs:
			var a: float = aim + off
			(ps.angles as Array).append(a)
			_beams.append(AbyssFX.beam(LANCE))
		Sfx.play("echarge", 0.1, -6.0)
		ps.fired = false
	var o2 := _origin()
	var angles: Array = ps.angles
	for i in angles.size():
		var a: float = angles[i]
		var d := Vector3(cos(a), 0, sin(a))
		var mi := _beams[i] as MeshInstance3D
		if lt < tele:
			var k := lt / tele
			AbyssFX.set_beam(mi, o2, d, LANCE_LEN, 0.25 + k * 0.4, 0.0, 0.6 + k * 0.6)
			threats.append({"type": "beam", "origin": o2, "a": a, "a1": a, "half": LANCE_W * 0.5, "len": LANCE_LEN, "sweep": false})
		elif lt < tele + fire:
			var k := (lt - tele) / fire
			AbyssFX.set_beam(mi, o2, d, LANCE_LEN, LANCE_W * 1.5 * (1.0 - k * 0.7), 1.0, 0.75)
			threats.append({"type": "beam", "origin": o2, "a": a, "a1": a, "half": LANCE_W * 0.5, "len": LANCE_LEN, "sweep": false})
			if not ps.fired:
				_hit_line(player, o2, d, LANCE_LEN, LANCE_W * 0.5)
		else:
			mi.visible = false
	if lt >= tele and not ps.fired:
		ps.fired = true
		Sfx.play("elaser", 0.05, -1.0)
		Main.inst.shake(0.3)
		AbyssFX.light_flash(o2 + Vector3(0, 2, 4), PALE, 10.0, 26.0, 0.35)
		for a in angles:
			var d := Vector3(cos(a), 0, sin(a))
			var q := o2 + d * randf_range(8.0, 20.0)
			if stage.on_floor(q):
				FX.sparks(Vector3(q.x, 0.15, q.z), 8, [Color.WHITE, PALE, CRIMSON], 8.0, 0.4, -12.0, 0.07)
			AbyssFX.scorch(o2 + d * 4.0, d, 24.0, 0.8)
	return false


func _hit_line(player: Player, o: Vector3, d: Vector3, length: float, half: float) -> void:
	if not player.alive:
		return
	var rel := Vector3(player.global_position.x - o.x, 0, player.global_position.z - o.z)
	var along := clampf(rel.dot(d), 0.0, length)
	if (rel - d * along).length() < half + player.hit_radius:
		player.take_hit(o)


# ── 패턴: 움켜쥐기 ──────────────────────────────────────

func _slam_target(a: Dictionary, player: Player) -> Vector3:
	var tgt := player.global_position + player.velocity * 0.3
	tgt.y = 0
	tgt = stage.push_out(tgt, 0.8)
	var s := _shoulder(a)
	var flat := Vector3(tgt.x - s.x, 0, tgt.z - s.z)
	var maxr := sqrt(maxf(0.0, pow(ARM_L * 1.9, 2.0) - pow(s.y, 2.0)))
	if flat.length() > maxr:
		tgt = Vector3(s.x, 0, s.z) + flat.normalized() * maxr
	return tgt


func _p_grasp(dt: float, player: Player, count: int, warn: float) -> bool:
	var per := warn + 0.15 + 1.4
	var i := int(pt / per)
	if i >= count:
		return pt > count * per + 0.4
	var lt := pt - i * per
	var a: Dictionary = arms[i % 2]
	if int(ps.get("i", -1)) != i:
		ps.i = i
		var prev: Dictionary = arms[(i + 1) % 2]
		_set_down(prev, false)
		prev.goal = _rest_goal(prev)
		prev.rate = 3.0
		var tgt := _slam_target(a, player)
		ps.tgt = tgt
		ps.hit = false
		a.goal = tgt + Vector3(0, 5.5, 0)
		a.rate = 5.0
		var w := AbyssFX.warn_disc(tgt, SLAM_R)
		_warns.append({"mi": w, "pos": tgt, "r": SLAM_R})
		Sfx.play("twind", 0.1, -8.0)
	var tgt2: Vector3 = ps.tgt
	if lt < warn:
		var k := lt / warn
		for w in _warns:
			if is_instance_valid(w.mi):
				AbyssFX.set_warn(w.mi, k)
		a.goal = tgt2 + Vector3(0, 5.5 + k * 1.0, 0)
	elif lt < warn + 0.15:
		a.goal = tgt2 + Vector3(0, 0.3, 0)
		a.rate = 30.0
	else:
		if not ps.hit:
			ps.hit = true
			a.m = tgt2 + Vector3(0, 0.3, 0)
			_clear_warns()
			_slam_impact(tgt2, player)
			_set_down(a, true)
			weak = true
			weak_t = 1.4
		a.goal = tgt2 + Vector3(0, 0.3, 0)
	return false


func _slam_impact(c: Vector3, player: Player) -> void:
	if player.alive and Vector2(player.global_position.x - c.x, player.global_position.z - c.z).length() < SLAM_R + player.hit_radius:
		player.take_hit(c)
	Main.inst.shake(0.65)
	Main.inst.hitstop(0.05)
	FX.shockwave(Vector3(c.x, 0.08, c.z), CRIMSON, SLAM_R * 2.4, 0.35, 0.12)
	FX.ring(Vector3(c.x, 0.3, c.z), SLAM_R * 1.6, [CRIMSON, Color(0.6, 0.02, 0.08), PALE], 0.4)
	FX.sparks(c + Vector3(0, 0.3, 0), 30, [Color.WHITE, Color(1.0, 0.5, 0.5), CRIMSON, Color(0.3, 0.28, 0.3)], 12.0, 0.6, -16.0, 0.12)
	AbyssFX.geyser(c, 1.2, stage)
	AbyssFX.splat(c, 3.2, 1.2)
	AbyssFX.light_flash(c + Vector3(0, 1.0, 0), CRIMSON, 9.0, 12.0, 0.5)
	Distortion.burst(c + Vector3(0, 0.5, 0), 5.0, 0.4, 1.2, 0.6)
	Sfx.play("boom", 0.05, 0.0)
	var off := randf() * TAU
	for k in 12:
		var aa := off + TAU * k / 12.0
		var d := Vector3(sin(aa), 0, cos(aa))
		Main.inst.add_bullet(Shot.make(Vector3(c.x, 0.95, c.z) + d * 1.0, d, 5.0, CRIMSON, 0.7))


# ── 패턴: 부름 ──────────────────────────────────────────

func _p_summon(_dt: float) -> bool:
	head.rotation.x = -0.25 * sin(clampf(pt / 2.4, 0.0, 1.0) * PI)
	if pt > 0.6 and not ps.has("a"):
		ps.a = true
		Sfx.play("overload", 0.0, -4.0)
		Main.inst.shake(0.4)
		AbyssFX.light_flash(global_position + Vector3(0, 6, 3), CRIMSON, 8.0, 24.0, 0.8)
		Main.inst.call("spawn_group", "husk", 4)
	if pt > 1.4 and not ps.has("b"):
		ps.b = true
		Main.inst.call("spawn_group", "husk", 3 if phase == 1 else 4)
	return pt > 2.4


# ── 패턴: 칼날 폭풍 (2페이즈) ───────────────────────────

func _p_storm(dt: float, player: Player) -> bool:
	if not ps.has("go"):
		ps.go = true
		_storm.clear()
		# 칼날 여덟 장을 떼어 전장 둘레로 날려 보낸다
		var n_bl := halo_blades.size()
		for k in 8:
			var b: Node3D = halo_blades[mini(n_bl - 1, int(k * n_bl / 8.0))] if n_bl > 0 else halo
			if b != halo:
				b.visible = false
			var n := Node3D.new()
			FX.root.add_child(n)
			var mesh := MeshInstance3D.new()
			mesh.mesh = Build.bevel_mesh(Vector3(1.8, 0.14, 0.5), 0.04, 0.4)
			mesh.material_override = Pal.lit(IRON)
			n.add_child(mesh)
			var glow := Build.glow_box(n, Vector3(1.5, 0.05, 0.06), Vector3(0, 0.08, 0.22), CRIMSON, 2.4)
			glow.name = "Glow"
			n.global_position = b.global_position
			_storm.append([n, TAU * k / 8.0, randf_range(0.2, 0.9), n.global_position])
		Sfx.play("rev", 0.05, -2.0)
	var dur := 6.0
	var k := clampf(pt / 0.9, 0.0, 1.0)
	for s in _storm:
		var n := s[0] as Node3D
		s[1] = float(s[1]) + dt * 0.55
		var a: float = s[1]
		var ring_p := Vector3(cos(a) * 10.5, 1.3, sin(a) * 10.5 - 1.0)
		var from: Vector3 = s[3]
		n.global_position = from.lerp(ring_p, 1.0 - pow(1.0 - k, 3.0)) if pt < 0.9 else ring_p
		n.rotate_y(dt * 14.0)
		if pt > 1.0 and pt < dur:
			s[2] = float(s[2]) - dt
			if s[2] <= 0.0:
				s[2] = randf_range(0.8, 1.2)
				var to := player.global_position - n.global_position
				to.y = 0
				var d := to.normalized()
				for off in [-0.18, 0.0, 0.18]:
					Main.inst.add_bullet(Shot.make(Vector3(n.global_position.x, 0.95, n.global_position.z), d.rotated(Vector3.UP, off), 5.6, CRIMSON, 0.55))
				FX.flash(n.global_position, PALE, 0.5, 0.05)
		if pt >= dur:
			# 후광으로 돌아간다
			var back := clampf((pt - dur) / 0.8, 0.0, 1.0)
			n.global_position = ring_p.lerp(halo.global_position, back * back)
	if pt >= dur + 0.8:
		for s in _storm:
			(s[0] as Node3D).queue_free()
		_storm.clear()
		for b in halo_blades:
			b.visible = true
		return true
	return false


func _update_storm(_dt: float) -> void:
	pass


# ── 패턴: 멸각의 시선 (2페이즈) ─────────────────────────

func _p_glare(dt: float, player: Player) -> bool:
	var charge := 1.4
	var sweep := 2.5
	var o := Vector3(global_position.x, 0.95, global_position.z + 2.0)
	if not ps.has("a0"):
		var aim := atan2(player.global_position.z - o.z, player.global_position.x - o.x)
		var s := 1.0 if randf() < 0.5 else -1.0
		ps.a0 = aim - 0.95 * s
		ps.a1 = aim + 0.95 * s
		ps.beam = AbyssFX.beam(CRIMSON)
		_beams.append(ps.beam)
		Sfx.play("echarge", 0.0, -2.0)
	var mi := ps.beam as MeshInstance3D
	if pt < charge:
		var k := pt / charge
		eye_mat.emission_energy_multiplier = 3.0 + k * 10.0
		eye.scale = Vector3.ONE * (0.8 + k * 0.6)
		AbyssFX.set_beam(mi, o, Vector3(cos(ps.a0), 0, sin(ps.a0)), LANCE_LEN, 0.3 + k * 0.6, 0.0, 0.7 + k * 0.5)
		threats.append({"type": "beam", "origin": o, "a": ps.a0, "a1": ps.a1, "half": GLARE_W * 0.5, "len": LANCE_LEN, "sweep": true})
		if randf() < 0.6:
			var q := eye.global_position + Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-1, 2))
			FX.flash(q, CRIMSON, 0.25, 0.15)
		return false
	var tt := pt - charge
	if tt < sweep:
		if not ps.has("fired"):
			ps.fired = true
			Sfx.play("elaser", 0.0, 2.0)
			Main.inst.shake(0.4)
		var k := smoothstep(0.0, 1.0, tt / sweep)
		var a := lerp_angle(float(ps.a0), float(ps.a1), k)
		var d := Vector3(cos(a), 0, sin(a))
		AbyssFX.set_beam(mi, o, d, LANCE_LEN, GLARE_W * 1.6 * (1.0 + 0.1 * sin(t * 50.0)), 1.0, 0.8)
		threats.append({"type": "beam", "origin": o, "a": a, "a1": ps.a1, "half": GLARE_W * 0.5, "len": LANCE_LEN, "sweep": true})
		_hit_line(player, o, d, LANCE_LEN, GLARE_W * 0.5)
		Main.inst.shake(0.12)
		_fx_t -= dt
		if _fx_t <= 0.0:
			_fx_t = 0.06
			var q := o + d * randf_range(5.0, 30.0)
			if stage.on_floor(q):
				FX.sparks(Vector3(q.x, 0.15, q.z), 5, [Color.WHITE, CRIMSON], 7.0, 0.3, -12.0, 0.07)
				AbyssFX.scorch(q - d * 0.8, d, 1.6, 0.9)
		# 빔이 지나는 적도 탄다
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy
			if en.is_boss or not en.landed:
				continue
			var rel := Vector3(en.global_position.x - o.x, 0, en.global_position.z - o.z)
			var along := clampf(rel.dot(d), 0.0, LANCE_LEN)
			if (rel - d * along).length() < GLARE_W * 0.5 + en.radius:
				en.take_hit(3, d, en.global_position, "laser")
		return false
	if not ps.has("weak"):
		ps.weak = true
		mi.visible = false
		# 과열: 눈이 드러난다
		weak = true
		weak_t = 2.2
		Main.inst.hud.popup("WEAK POINT", Color("ffe080"), eye.global_position + Vector3(0, 1.5, 0))
	return tt > sweep + 0.6


# ── 피격 · 페이즈 ───────────────────────────────────────

func get_threats() -> Array:
	return threats.duplicate()


func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	_damage(float(mini(dmg, 20)), dir, pos, source, 1.0)


func part_hit(part: Enemy, dmg: int, dir: Vector3, pos: Vector3, source: String) -> void:
	if source == "slash" or source == "phantom":
		FX.sparks(part.global_position + Vector3(0, 0.8, 0), 18, [Color.WHITE, Pal.BLADE, CRIMSON], 9.0, 0.4, -10.0, 0.08)
		AbyssFX.ichor_burst(part.global_position + Vector3(0, 0.6, 0), dir, 1.2)
		Main.inst.hud.popup("SEVER", Color("ff8a90"), part.global_position + Vector3(0, 2.4, 0))
	_damage(float(mini(dmg, 20)), dir, pos, source, 1.4, (arms[0 if (part as Hand).side < 0 else 1] as Dictionary).hand)


func _damage(base: float, dir: Vector3, pos: Vector3, source: String, mult: float, flash_root: Node3D = null) -> void:
	if not alive or st != St.FIGHT:
		if randf() < 0.3:
			FX.sparks(pos, 3, [Color.WHITE, Color("a0a0c0")], 4.0, 0.2, -6.0, 0.05)
		return
	var amount := base
	if source == "slash":
		amount = 12.0
	elif source == "phantom":
		amount = 22.0
	amount *= mult
	if weak:
		amount *= 2.0
	boss_hp = maxf(0.0, boss_hp - amount)
	if is_instance_valid(bar):
		bar.call("set_hp", boss_hp / MAX_HP, amount >= 5.0)
	kill_source = source
	HitSpark.spawn(pos, dir, clampf(1.0 + amount * 0.06, 1.0, 2.4), self)
	lean_v += Vector2(-dir.z, dir.x) * minf(0.01 * amount, 0.2)
	punch = maxf(punch, minf(0.1 + amount * 0.04, 1.0))
	if randf() < 0.3:
		FX.sparks(pos, 4, [Color(1.0, 0.4, 0.4), CRIMSON], 5.0, 0.3, -12.0, 0.06)
	if amount >= 8.0 and flash_cd <= 0.0:
		flash_cd = 0.3
		var root: Node3D = flash_root if flash_root else torso
		var part := root.find_children("*", "MeshInstance3D", true, false)
		_set_flash_parts(true, part)
		get_tree().create_timer(0.06, true, false, true).timeout.connect(func():
			if is_instance_valid(self):
				_set_flash_parts(false, part))
	if hit_snd_cd <= 0.0:
		hit_snd_cd = 0.07
		Sfx.play("hit", 0.15, -8.0)
	if weak and randf() < 0.12:
		Main.inst.hud.popup("×2", Color("ffe060"), pos + Vector3(0, 1.5, 0))
	if phase == 1 and boss_hp <= MAX_HP * PHASE2_AT:
		boss_hp = MAX_HP * PHASE2_AT
		if is_instance_valid(bar):
			bar.call("set_hp", PHASE2_AT, true)
		_begin_transition()
	elif boss_hp <= 0.0:
		_begin_dying()


func _set_flash_parts(on: bool, only: Array) -> void:
	var rest_mat: Material = Pal.lock_hatch() if locked else null
	for mi in (only if not only.is_empty() else meshes):
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = Pal.flash() if on else rest_mat


func _set_flash(on: bool) -> void:
	_set_flash_parts(on, [])


func _abort_pattern() -> void:
	pat = ""
	ps = {}
	_clear_beams()
	_clear_warns()
	for s in _storm:
		(s[0] as Node3D).queue_free()
	_storm.clear()
	for b in halo_blades:
		b.visible = true
	halo_spin = 0.5
	for a in arms:
		_set_down(a, false)
		a.goal = _rest_goal(a)
		a.rate = 3.0


func _clear_beams() -> void:
	for b in _beams:
		if is_instance_valid(b):
			(b as Node).queue_free()
	_beams.clear()


func _clear_warns() -> void:
	for w in _warns:
		if is_instance_valid(w.mi):
			(w.mi as Node).queue_free()
	_warns.clear()


func _clear_bullets() -> void:
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		FX.flash(b.position, CRIMSON, 0.3, 0.08)
		b.queue_free()


func _begin_transition() -> void:
	_abort_pattern()
	_clear_bullets()
	st = St.TRANSITION
	st_t = 0.0
	weak = false
	landed = false
	print("WARDEN_TRANSITION t=%.1f" % Main.inst.time)


func _update_transition(dt: float) -> void:
	# 몸을 웅크렸다가 크게 젖히며 포효한다. 후광이 금 가며 칼날 몇 장이 떨어져 나간다.
	var k := clampf(st_t / 3.0, 0.0, 1.0)
	torso.rotation.x = -0.3 * sin(k * PI)
	halo_spin = lerpf(0.5, 9.0, sin(k * PI))
	halo_glow_mat.emission_energy_multiplier = 2.5 + sin(t * 40.0) * 2.0 * sin(k * PI)
	if randf() < dt * 8.0:
		AbyssFX.ichor_burst(torso.global_position + Vector3(randf_range(-1.5, 1.5), randf_range(-1, 2), randf_range(0.5, 1.5)), Vector3(randf_range(-1, 1), 0, 1), 1.2)
	if st_t > 0.9 and not ps.has("roar"):
		ps.roar = true
		Main.inst.shake(0.8)
		Sfx.play("overload", 0.0, 0.0)
		Sfx.play("boom", 0.0, 0.0)
		Main.inst.hud.banner("PHASE 2", Color("ff3a4a"), "성소가 무너진다 — 후광이 깨어났다")
		AbyssFX.light_flash(global_position + Vector3(0, 6, 4), CRIMSON, 16.0, 34.0, 1.4)
		phase = 2
		if is_instance_valid(bar):
			bar.call("set_phase", 2)
		phase_changed.emit(2)
		for k2 in [1, 7]:
			_break_off(halo_blades[k2], Vector3(randf_range(-3, 3), 4.0, 2.0))
	if st_t >= 3.0:
		st = St.FIGHT
		st_t = 0.0
		landed = true
		rest = 1.0
		order = PATTERNS_2.duplicate()
		order.shuffle()
		pat_i = -1


## 조각을 떼어 심연으로 떨어뜨린다
func _break_off(n: Node3D, vel: Vector3) -> void:
	if not is_instance_valid(n) or not n.visible:
		return
	var xf := n.global_transform
	n.get_parent().remove_child(n)
	FX.root.add_child(n)
	n.global_transform = xf
	_falling.append([n, vel, Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))])
	halo_blades.erase(n)
	FX.sparks(xf.origin, 14, [Color.WHITE, CRIMSON, Color(0.4, 0.38, 0.42)], 8.0, 0.5, -10.0, 0.09)


func _update_falling(dt: float) -> void:
	var i := _falling.size() - 1
	while i >= 0:
		var f: Array = _falling[i]
		var n := f[0] as Node3D
		if not is_instance_valid(n):
			_falling.remove_at(i)
			i -= 1
			continue
		var v: Vector3 = f[1]
		v.y -= 14.0 * dt
		f[1] = v
		n.global_position += v * dt
		var sp: Vector3 = f[2]
		n.rotate(sp.normalized(), sp.length() * dt)
		if n.global_position.y < -30.0:
			n.queue_free()
			_falling.remove_at(i)
		i -= 1


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
	for a in arms:
		if is_instance_valid(a.part):
			(a.part as Node).queue_free()
	if is_instance_valid(bar):
		bar.call("set_pattern", "")
	Main.inst.hitstop(0.12)
	Main.inst.shake(0.9)
	Sfx.play("overload", 0.0, 2.0)
	print("WARDEN_DYING t=%.1f" % Main.inst.time)


func _update_dying(dt: float) -> void:
	var k := clampf(st_t / 3.4, 0.0, 1.0)
	# 경련: 몸이 떨고 판 사이에서 체액이 뿜어 나온다. 팔은 힘이 빠져 늘어진다.
	torso.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.12 * (1.0 - k * 0.5)
	halo_spin = lerpf(4.0, 0.0, k)
	heart_mat.emission_energy_multiplier = 2.0 + k * 10.0
	heart_light.light_energy = 4.0 + k * 10.0
	for a in arms:
		var s: float = a.side
		a.goal = _shoulder(a) + Vector3(s * 1.5, -11.0, 2.0)
		a.rate = 1.5
	_fx_t -= dt
	if _fx_t <= 0.0 and k < 0.95:
		_fx_t = lerpf(0.22, 0.07, k)
		var p := torso.global_position + Vector3(randf_range(-1.6, 1.6), randf_range(-1.2, 2.4), randf_range(0.4, 1.6))
		AbyssFX.ichor_burst(p, Vector3(randf_range(-1, 1), 0, 1), 1.4)
		FX.flash(p, Color(1.0, 0.75, 0.7), 1.0, 0.07)
		AbyssFX.light_flash(p, CRIMSON, 5.0, 10.0, 0.25)
		Sfx.play("boom", 0.2, -8.0)
		Main.inst.shake(0.25)
		if halo_blades.size() > 0 and randf() < 0.5:
			_break_off(halo_blades[randi() % halo_blades.size()], Vector3(randf_range(-4, 4), randf_range(2, 6), randf_range(0, 4)))
	if k >= 1.0 and not ps.has("final"):
		ps.final = true
		_final_blast()


func _final_blast() -> void:
	var c := torso.global_position
	AbyssFX.rupture(c, 4.5)
	FX.flash(c, Color.WHITE, 6.0, 0.25)
	AbyssFX.light_flash(c + Vector3(0, 0, 4), Color(1.0, 0.5, 0.5), 30.0, 50.0, 1.6)
	Main.inst.shake(1.0)
	Main.inst.hitstop(0.15)
	Main.inst.hud.screen_flash(Color(1.0, 0.8, 0.8), 0.7)
	Sfx.play("boom", 0.0, 4.0)
	Sfx.play("lose", 0.3, -6.0)
	for b in halo_blades.duplicate():
		_break_off(b, Vector3(randf_range(-8, 8), randf_range(4, 10), randf_range(-2, 6)))
	defeated.emit()
	st = St.DEAD
	# 남은 몸은 심연으로 떨어진다
	var tw := create_tween()
	tw.tween_property(rig, "position:y", -34.0, 2.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(rig, "rotation:x", 0.6, 2.6)
	tw.tween_callback(func(): visible = false)
	for a in arms:
		for key in ["upper", "fore", "hand"]:
			var n := a[key] as Node3D
			var v := Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-1, 3))
			_falling.append([n, v, Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2))])
