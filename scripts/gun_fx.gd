class_name GunFX
extends Node3D
## 총기 연출 전용: 총구 화염(별 모양 불꽃·순간 조명·연기), 탄피 배출, 착탄(파편·먼지·불꽃).
## 탄피와 벽 파편은 바닥에 떨어져 한동안 남아 전투 흔적을 쌓는다. 게임 판정과 무관하다.

const GRAVITY := 22.0
const MAX_CASINGS := 200
const MAX_CHIPS := 160
const CASING_LIFE := 16.0
const CHIP_LIFE := 11.0
const FADE := 1.5

const BRASS := Color("f2c22e")
const FLASH_CORE := Color("fffbe0")
const FLASH_MID := Color("ffd23a")
const FLASH_TIP := Color("ff7a14")
const SPARK_COLORS: Array[Color] = [Color("fffbe0"), Color("ffd23a"), Color("ff8a1a")]
const SMOKE := Color(0.62, 0.62, 0.7)

static var inst: GunFX

var _flash_mesh: ArrayMesh
var _flash_mat: StandardMaterial3D
var _smoke_mat: ShaderMaterial
var _sphere: SphereMesh
var _casing_mesh: CylinderMesh
var _casing_mat: StandardMaterial3D
var _chip_meshes: Array[BoxMesh] = []
var _streak_mesh: BoxMesh
var _spark_pm: ParticleProcessMaterial

var casings: Array = []   # {node, vel, ang, life, rest, bounced}
var chips: Array = []     # {node, vel, ang, life, rest, half}
var _tink_t := 0.0


func _ready() -> void:
	inst = self
	_flash_mesh = _build_flash_mesh()
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.vertex_color_use_as_albedo = true
	_flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flash_mat.albedo_color = Color(1.6, 1.6, 1.6)
	_flash_mesh.surface_set_material(0, _flash_mat)

	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;
instance uniform vec4 tint : source_color = vec4(0.6, 0.6, 0.7, 1.0);
instance uniform float alpha = 0.5;
void fragment() {
	float rim = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = alpha * smoothstep(0.0, 0.6, rim);
}
"""
	_smoke_mat = ShaderMaterial.new()
	_smoke_mat.shader = sh
	_sphere = SphereMesh.new()
	_sphere.radius = 0.5
	_sphere.height = 1.0
	_sphere.radial_segments = 10
	_sphere.rings = 5

	_casing_mesh = CylinderMesh.new()
	_casing_mesh.top_radius = 0.042
	_casing_mesh.bottom_radius = 0.046
	_casing_mesh.height = 0.17
	_casing_mesh.radial_segments = 6
	_casing_mesh.rings = 1
	_casing_mat = StandardMaterial3D.new()
	_casing_mat.albedo_color = BRASS
	_casing_mat.metallic = 0.6
	_casing_mat.roughness = 0.35
	_casing_mat.emission_enabled = true
	_casing_mat.emission = BRASS
	_casing_mat.emission_energy_multiplier = 1.1

	# 벽·바닥 파편: 크기가 조금씩 다른 납작한 상자
	for s in [Vector3(0.09, 0.06, 0.08), Vector3(0.12, 0.07, 0.07), Vector3(0.07, 0.05, 0.11), Vector3(0.14, 0.09, 0.1)]:
		var b := BoxMesh.new()
		b.size = s
		_chip_meshes.append(b)

	# 불꽃: 진행 방향으로 늘어난 가는 막대
	_streak_mesh = BoxMesh.new()
	_streak_mesh.size = Vector3(0.025, 0.22, 0.025)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.vertex_color_use_as_albedo = true
	smat.albedo_color = Color(1.5, 1.5, 1.5)
	_streak_mesh.material = smat


## 4갈래 별 모양 불꽃. 앞(-Z)으로 긴 갈래, 옆으로 짧은 갈래. 가운데는 흰색, 끝은 주황.
func _build_flash_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# [각도(앞=0), 길이, 폭]
	var spikes := [[0.0, 0.62, 0.11], [0.95, 0.3, 0.08], [-0.95, 0.3, 0.08], [2.3, 0.14, 0.06], [-2.3, 0.14, 0.06]]
	for plane in 2:
		for s in spikes:
			var a: float = s[0]
			var d := Vector3(-sin(a), 0, -cos(a))
			var side := d.cross(Vector3.UP).normalized() * float(s[2])
			var tip := d * float(s[1])
			var base_c := Vector3(0, 0, 0)
			if plane == 1:
				# 세로 판: 앞 갈래만 위아래로 (옆 갈래는 위·아래로 세운다)
				tip = Basis(Vector3.FORWARD, PI * 0.5) * tip
				side = Basis(Vector3.FORWARD, PI * 0.5) * side
			st.set_color(FLASH_CORE); st.add_vertex(base_c + side)
			st.set_color(FLASH_TIP); st.add_vertex(tip)
			st.set_color(FLASH_CORE); st.add_vertex(base_c - side)
			# 안쪽 밝은 심
			st.set_color(FLASH_CORE); st.add_vertex(base_c + side * 0.45)
			st.set_color(FLASH_MID); st.add_vertex(tip * 0.6)
			st.set_color(FLASH_CORE); st.add_vertex(base_c - side * 0.45)
	return st.commit()


# ── 총구 화염 ───────────────────────────────────────────

## size 1.0 = 플레이어 소총. light: 순간 조명을 켤지 (연사 중 조명이 너무 많아지지 않게)
static func muzzle(pos: Vector3, dir: Vector3, size := 1.0, light := true) -> void:
	if inst == null:
		return
	var g := inst
	var fwd := Vector3(dir.x, 0, dir.z).normalized()
	# 별 모양 불꽃: 매번 크기·비틀림이 달라 깜빡이듯 보인다
	var mi := MeshInstance3D.new()
	mi.mesh = g._flash_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(mi)
	mi.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.FORWARD, randf_range(-0.5, 0.5)), pos)
	var k := size * randf_range(0.8, 1.2)
	mi.scale = Vector3(k * randf_range(0.8, 1.1), k, k * randf_range(0.85, 1.25))
	var tw := mi.create_tween()
	tw.tween_interval(0.025)
	tw.tween_property(mi, "scale", mi.scale * Vector3(0.2, 0.2, 1.3), 0.035)
	tw.tween_callback(mi.queue_free)
	# 가운데 섬광 구체
	FX.flash(pos + fwd * 0.06 * size, FLASH_CORE, 0.3 * size, 0.045)
	if light:
		var l := OmniLight3D.new()
		l.light_color = Color("ffb850")
		l.light_energy = 2.2 * size
		l.omni_range = 3.2 * size
		l.shadow_enabled = false
		g.add_child(l)
		l.global_position = pos + fwd * 0.2 + Vector3(0, 0.2, 0)
		var lt := l.create_tween()
		lt.tween_property(l, "light_energy", 0.0, 0.07)
		lt.tween_callback(l.queue_free)
	# 옅은 총구 연기
	if randf() < 0.7:
		g._smoke(pos + fwd * 0.25 * size, fwd * 0.6 + Vector3(0, 0.5, 0), 0.16 * size, 0.35, 0.4)
	g._spray(pos + fwd * 0.1, fwd, 3, 40.0, 7.0, 0.1)


# ── 탄피 ────────────────────────────────────────────────

## 총 옆으로 튀어나가 바닥에서 짤랑이며 튕기고, 한동안 바닥에 남는다.
## out: 배출 방향(수평), fwd: 총 방향
static func eject(pos: Vector3, out: Vector3, fwd: Vector3, size := 1.0) -> void:
	if inst == null:
		return
	var g := inst
	var mi := MeshInstance3D.new()
	mi.mesh = g._casing_mesh
	mi.material_override = g._casing_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.add_child(mi)
	mi.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5), pos)
	mi.scale = Vector3.ONE * size
	var vel := out * randf_range(2.2, 3.6) + Vector3(0, randf_range(3.0, 4.6), 0) - fwd * randf_range(0.4, 1.4)
	vel += Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	var ang := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(14.0, 26.0)
	g.casings.append({"node": mi, "vel": vel, "ang": ang, "life": CASING_LIFE, "rest": false, "bounced": false, "r": 0.044 * size, "s0": size})
	while g.casings.size() > MAX_CASINGS:
		var old: Dictionary = g.casings.pop_front()
		(old.node as Node).queue_free()


# ── 착탄 ────────────────────────────────────────────────

## 벽·엄폐물에 맞음: 회색 파편이 튀어 바닥에 남고, 먼지가 피어오르며, 불꽃이 반사 방향으로 튄다.
static func impact_wall(pos: Vector3, normal: Vector3, fwd: Vector3, k := 1.0) -> void:
	if inst == null:
		return
	var g := inst
	var n := Vector3(normal.x, 0, normal.z).normalized()
	var refl := (fwd - 2.0 * fwd.dot(n) * n).normalized()
	FX.flash(pos, FLASH_CORE, 0.34 * k, 0.05)
	g._star(pos, n, 0.45 * k)
	g._spray(pos, (refl + n).normalized(), int(7 * k), 55.0, 9.0, 0.22)
	for i in int(randf_range(2, 4) * k):
		var c := Color(0.2, 0.2, 0.33).lerp(Color(0.09, 0.09, 0.16), randf())
		var v := (n * randf_range(1.5, 3.5) + refl * randf_range(0.5, 2.0)).rotated(Vector3.UP, randf_range(-0.7, 0.7))
		v.y = randf_range(2.0, 4.5)
		g._chip(pos + n * 0.05, v, c, randf_range(0.7, 1.2))
	for i in 2:
		g._smoke(pos + n * 0.15, n * randf_range(0.4, 0.9) + Vector3(0, randf_range(0.3, 0.7), 0), 0.22 * k, 0.55, 0.45 + randf() * 0.2)


## 적 몸체에 맞음: 흰 섬광, 관통 방향으로 뿜는 불꽃, 몸체색 부스러기
static func impact_body(pos: Vector3, fwd: Vector3, body_c: Color, k := 1.0) -> void:
	if inst == null:
		return
	var g := inst
	FX.flash(pos, Color.WHITE, 0.5 * k, 0.06)
	g._star(pos - fwd * 0.1, -fwd, 0.55 * k)
	g._spray(pos, fwd, int(6 * k), 35.0, 8.0, 0.2)
	g._spray(pos, -fwd, int(3 * k), 60.0, 5.0, 0.15)
	for i in int(randf_range(1, 3) * k):
		var v := (fwd * randf_range(1.5, 3.0)).rotated(Vector3.UP, randf_range(-0.9, 0.9))
		v.y = randf_range(2.0, 4.0)
		g._chip(pos, v, body_c if randf() < 0.6 else Color("5a1428"), randf_range(0.5, 0.8))


# ── 내부 요소 ───────────────────────────────────────────

## 착탄 지점의 작은 별 모양 섬광 (normal 방향으로 벌어진다)
func _star(pos: Vector3, n: Vector3, size: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _flash_mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var d := Vector3(n.x, 0, n.z)
	if d.length() < 0.01:
		d = Vector3.FORWARD
	mi.global_transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.UP) * Basis(Vector3.FORWARD, randf() * TAU), pos)
	mi.scale = Vector3.ONE * size * Vector3(1.2, 1.2, 0.6)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 0.01, 0.07).set_ease(Tween.EASE_IN)
	tw.tween_callback(mi.queue_free)


## 방향이 있는 불꽃 막대 (속도 방향으로 정렬)
func _spray(pos: Vector3, dir: Vector3, count: int, spread: float, speed: float, life: float) -> void:
	if count <= 0:
		return
	var p := GPUParticles3D.new()
	p.amount = count
	p.one_shot = true
	p.explosiveness = 1.0
	p.lifetime = life
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.direction = (dir + Vector3(0, 0.25, 0)).normalized()
	pm.spread = spread
	pm.initial_velocity_min = speed * 0.45
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, -18.0, 0)
	pm.damping_min = 4.0
	pm.damping_max = 8.0
	pm.particle_flag_align_y = true
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var cv := Curve.new()
	cv.add_point(Vector2(0, 1))
	cv.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = cv
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray(SPARK_COLORS)
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	p.draw_pass_1 = _streak_mesh
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.3).timeout.connect(p.queue_free)


func _smoke(pos: Vector3, drift: Vector3, size: float, alpha: float, life: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere
	mi.material_override = _smoke_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", SMOKE.lerp(Color(0.4, 0.4, 0.5), randf()))
	mi.set_instance_shader_parameter("alpha", alpha)
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size * 0.5
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size * randf_range(1.6, 2.2), life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mi, "position", mi.position + drift * life, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float): mi.set_instance_shader_parameter("alpha", v), alpha, 0.0, life)
	tw.tween_callback(mi.queue_free)


func _chip(pos: Vector3, vel: Vector3, c: Color, size: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _chip_meshes[randi() % _chip_meshes.size()]
	mi.material_override = Pal.lit(c)
	add_child(mi)
	mi.global_position = pos
	mi.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	mi.scale = Vector3.ONE * size
	var ang := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(8.0, 18.0)
	chips.append({"node": mi, "vel": vel, "ang": ang, "life": CHIP_LIFE * randf_range(0.7, 1.0), "rest": false, "half": 0.035 * size, "s0": size})
	while chips.size() > MAX_CHIPS:
		var old: Dictionary = chips.pop_front()
		(old.node as Node).queue_free()


func _physics_process(dt: float) -> void:
	_tink_t -= dt
	_step(casings, dt, true)
	_step(chips, dt, false)


## 간단한 낙하·튕김. 멈추면 바닥에 눕혀 두고, 수명 끝에 줄어들며 사라진다.
func _step(list: Array, dt: float, is_casing: bool) -> void:
	var main := Main.inst
	var i := list.size() - 1
	while i >= 0:
		var pc: Dictionary = list[i]
		var mi := pc.node as MeshInstance3D
		pc.life -= dt
		if pc.life <= 0.0:
			mi.queue_free()
			list.remove_at(i)
			i -= 1
			continue
		if pc.life < FADE:
			mi.scale = Vector3.ONE * float(pc.s0) * maxf(0.01, pc.life / FADE)
		if pc.rest:
			i -= 1
			continue
		var v: Vector3 = pc.vel
		v.y -= GRAVITY * dt
		var old := mi.global_position
		var pos := old + v * dt
		var floor_y: float = pc.r if is_casing else pc.half
		var ang: Vector3 = pc.ang
		if pos.y < floor_y:
			pos.y = floor_y
			if v.y < -1.2:
				v.y = -v.y * (0.42 if is_casing else 0.3)
				ang *= 0.7
				if is_casing and _tink_t <= 0.0:
					_tink_t = 0.03
					Sfx.play("tink", 0.18, -20.0 if pc.bounced else -15.0)
				pc.bounced = true
			else:
				v.y = 0.0
			v.x *= 0.65
			v.z *= 0.65
			ang *= 0.75
			if Vector2(v.x, v.z).length() < 0.15 and absf(v.y) < 0.01:
				pc.rest = true
				if is_casing:
					# 옆으로 누운 자세로 정착 (원기둥 축이 수평)
					var yaw := randf() * TAU
					mi.global_basis = Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, PI * 0.5)
					mi.scale = Vector3.ONE * float(pc.s0)
				else:
					mi.rotation = Vector3(0, mi.rotation.y, 0)
					mi.scale = Vector3.ONE * float(pc.s0)
				pos.y = floor_y
		if main and pos.y < 1.3:
			if main.is_blocked(Vector3(pos.x, 0, old.z)):
				pos.x = old.x
				v.x = -v.x * 0.35
			if main.is_blocked(Vector3(pos.x, 0, pos.z)):
				pos.z = old.z
				v.z = -v.z * 0.35
		mi.global_position = pos
		if ang.length() > 0.05:
			mi.rotate(ang.normalized(), ang.length() * dt)
		pc.vel = v
		pc.ang = ang
		i -= 1
