class_name MegaBeam
extends Node3D
## 최대 충전 지속 레이저 연출. 매 프레임 set_beam(origin, dir, length) 로 갱신한다.
## 초고속으로 흐르는 줄무늬 빔 + 빔을 따라 쏜살같이 지나가는 속도선 + 총구 역풍 줄기
## + 빔 경로를 따라 놓인 강한 조명. 판정과 무관.
## 속도선·역풍 줄기·링은 노드를 지우지 않고 숨겨 두었다가 다시 쓴다 (초당 수백 개라 생성 비용이 크다).

const W := 1.15
const STREAK_SPEED := 110.0

var layers: Array[MeshInstance3D] = []
var floor_glow: MeshInstance3D
var tip: MeshInstance3D
var muzzle_orb: MeshInstance3D
var light: OmniLight3D
var tip_light: OmniLight3D
var path_lights: Array[OmniLight3D] = []
var length := 10.0
var dir := Vector3.FORWARD
var t := 0.0
var fade := 1.0
var ending := false
var ring_t := 0.0
var tip_t := 0.0
var streak_t := 0.0
var gust_t := 0.0
var flowing: Array = []   # [node, dist, speed]
var streaks: Array = []   # [node, dist, radius, angle]
var gusts: Array = []     # [node, from, to, scale, age]
var _pool_streak: Array[MeshInstance3D] = []
var _pool_ring: Array[MeshInstance3D] = []
var _pool_gust: Array[MeshInstance3D] = []   # 기울어진 basis 를 가지므로 속도선과 따로 둔다
var snd: AudioStreamPlayer
var trail: BeamTrail   # 끝점이 지나간 바닥 궤적 잔상 (빔보다 오래 남는다)

static var _cyl: CylinderMesh
static var _torus: TorusMesh
static var _sphere: SphereMesh
static var _strip: BoxMesh
static var _streak: BoxMesh
static var _beam_shader: Shader


func _ready() -> void:
	if _cyl == null:
		_cyl = CylinderMesh.new()
		_cyl.top_radius = 0.5
		_cyl.bottom_radius = 0.5
		_cyl.height = 1.0
		_cyl.radial_segments = 20
		_cyl.rings = 1
		_torus = TorusMesh.new()
		_torus.inner_radius = 0.85
		_torus.outer_radius = 1.0
		_torus.rings = 32
		_torus.ring_segments = 4
		_sphere = SphereMesh.new()
		_sphere.radius = 0.5
		_sphere.height = 1.0
		_strip = BoxMesh.new()
		_strip.size = Vector3(1, 0.01, 1)
		_streak = BoxMesh.new()
		_streak.size = Vector3(0.035, 0.035, 1.0)
		_beam_shader = Shader.new()
		_beam_shader.code = """
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float energy = 2.0;
uniform float reps = 8.0;
uniform float speed = 14.0;
uniform float contrast = 0.35;
void fragment() {
	// UV.y 는 원통 길이 방향. 빠르게 흐르는 줄무늬로 속도감을 준다
	float s1 = fract(UV.y * reps - TIME * speed);
	float s2 = fract(UV.y * reps * 2.7 - TIME * speed * 1.6 + UV.x * 0.5);
	float band = smoothstep(0.0, 0.15, s1) * (1.0 - smoothstep(0.35, 0.6, s1));
	float fine = step(0.8, s2);
	ALBEDO = tint.rgb * energy * (1.0 - contrast + contrast * 2.0 * max(band, fine * 0.6));
}
"""
	var specs := [[Color("2fd8ff"), 2.0, 1.0, 0.45, 9.0], [Color("a8f8ff"), 2.6, 0.64, 0.35, 12.0], [Color.WHITE, 3.4, 0.34, 0.2, 16.0]]
	for spec in specs:
		var mi := MeshInstance3D.new()
		mi.mesh = _cyl
		var m := ShaderMaterial.new()
		m.shader = _beam_shader
		m.set_shader_parameter("tint", spec[0])
		m.set_shader_parameter("energy", spec[1])
		m.set_shader_parameter("contrast", spec[3])
		m.set_shader_parameter("speed", spec[4])
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation_degrees.x = -90.0
		add_child(mi)
		mi.set_meta("r", spec[2])
		layers.append(mi)
	floor_glow = Pal.flat_mesh(_strip, Color(0.3, 0.8, 1.0), 1.3)
	add_child(floor_glow)
	tip = Pal.flat_mesh(_sphere, Color.WHITE, 2.6)
	add_child(tip)
	muzzle_orb = Pal.flat_mesh(_sphere, Color(0.8, 1.0, 1.0), 2.8)
	add_child(muzzle_orb)
	# 총구 조명 (매 프레임 움직이는 점광원 그림자는 6면을 다시 그려서 비싸 그림자는 끈다)
	light = OmniLight3D.new()
	light.light_color = Color(0.45, 0.9, 1.0)
	light.light_energy = 14.0
	light.omni_range = 11.0
	light.omni_attenuation = 1.2
	add_child(light)
	for i in 3:
		var l := OmniLight3D.new()
		l.light_color = Color(0.4, 0.85, 1.0)
		l.light_energy = 7.0
		l.omni_range = 7.5
		add_child(l)
		path_lights.append(l)
	tip_light = OmniLight3D.new()
	tip_light.light_color = Color(0.7, 0.95, 1.0)
	tip_light.light_energy = 12.0
	tip_light.omni_range = 8.0
	add_child(tip_light)
	trail = BeamTrail.new()
	(FX.root if FX.root else get_parent()).add_child(trail)
	tree_exiting.connect(func() -> void:
		if is_instance_valid(trail):
			trail.finish())
	snd = AudioStreamPlayer.new()
	add_child(snd)
	if is_instance_valid(Sfx.inst) and not Sfx.inst.muted:
		snd.stream = Sfx.inst.streams.beam
		snd.volume_db = -4.0
		snd.play()


func set_beam(origin: Vector3, d: Vector3, len: float) -> void:
	global_position = origin
	dir = d
	length = len
	basis = Basis.looking_at(d, Vector3.UP)
	if trail and not ending:
		trail.push(origin + d * len)


func finish() -> void:
	ending = true
	BeamAfterimage.spawn(global_position, dir, length, 0.16, Color("1ff0ff"), 0.12)
	if is_instance_valid(trail):
		trail.finish()


func _process(dt: float) -> void:
	t += dt
	if ending:
		fade = maxf(0.0, fade - dt / 0.22)
		snd.volume_db = lerpf(snd.volume_db, -40.0, 0.2)
		if fade <= 0.0:
			queue_free()
			return
	else:
		fade = minf(1.0, fade + dt * 10.0)
	# 굵기: 시작 직후 크게 부풀었다 안정, 고속 떨림
	var intro := 1.0 + maxf(0.0, 0.8 - t * 4.0)
	var wob := 1.0 + sin(t * 71.0) * 0.08 + sin(t * 43.0) * 0.05 + randf() * 0.04
	for mi in layers:
		var r: float = mi.get_meta("r")
		var w := W * r * intro * wob * fade
		mi.scale = Vector3(w, length, w)
		mi.position = Vector3(0, 0, -length * 0.5)
		(mi.material_override as ShaderMaterial).set_shader_parameter("reps", length / 1.6)
	floor_glow.position = Vector3(0, Main.gy(global_position) + 0.03 - global_position.y, -length * 0.5)
	floor_glow.scale = Vector3(W * 1.6 * fade, 1, length)
	tip.position = Vector3(0, 0, -length)
	tip.scale = Vector3.ONE * (1.7 + sin(t * 60.0) * 0.35) * fade
	muzzle_orb.scale = Vector3.ONE * (1.2 + sin(t * 75.0) * 0.25) * fade
	# 조명: 총구·경로·끝점. 깜빡임으로 전력 느낌
	var flick := 0.85 + randf() * 0.3
	light.light_energy = 14.0 * fade * flick
	for i in path_lights.size():
		path_lights[i].position = Vector3(0, 0, -length * float(i + 1) / 4.0)
		path_lights[i].light_energy = 7.0 * fade * flick
	tip_light.position = tip.position
	tip_light.light_energy = 12.0 * fade * flick
	_update_gusts(dt)
	if ending:
		return
	var end := global_position + dir * length
	# 끝점 충돌
	tip_t -= dt
	if tip_t <= 0.0:
		tip_t = 0.035
		FX.sparks(end, 7, [Color.WHITE, Pal.CYAN, Color("8a70ff")], 12.0, 0.35, -10.0, 0.09)
		FX.flash(end + Vector3(randf_range(-0.4, 0.4), randf_range(-0.2, 0.4), randf_range(-0.4, 0.4)), Color(0.7, 1, 1), 1.0, 0.06)
	# 속도선: 빔 둘레를 초고속으로 지나간다
	streak_t -= dt
	while streak_t <= 0.0:
		streak_t += 0.008
		var s := _take(_pool_streak, _streak, Color.WHITE if randf() < 0.6 else Color("9af4ff"), 2.4)
		var ang := randf() * TAU
		var rad := W * randf_range(0.35, 0.95)
		streaks.append([s, randf_range(0.0, 1.5), rad, ang, randf_range(1.5, 4.5)])
	var i := streaks.size() - 1
	while i >= 0:
		var st: Array = streaks[i]
		var node := st[0] as MeshInstance3D
		st[1] += STREAK_SPEED * dt
		if st[1] - st[4] > length:
			_give(_pool_streak, node)
			streaks.remove_at(i)
		else:
			var a: float = st[3]
			var r: float = st[2]
			var head: float = minf(st[1], length)
			var tail: float = maxf(st[1] - st[4], 0.0)
			node.position = Vector3(cos(a) * r, sin(a) * r, -(head + tail) * 0.5)
			node.scale = Vector3(1, 1, maxf(head - tail, 0.01))
		i -= 1
	# 총구에서 뒤로 뿜어지는 역풍 줄기 (반동 속도감)
	gust_t -= dt
	if gust_t <= 0.0:
		gust_t = 0.03
		for k in 2:
			var g := _take(_pool_gust, _streak, Color(0.8, 1.0, 1.0), 1.8)
			var ga := randf() * TAU
			var off := Vector3(cos(ga), sin(ga) * 0.6, 0) * randf_range(0.5, 1.2)
			g.position = off + Vector3(0, 0, 0.3)
			g.basis = Basis.looking_at(Vector3(off.x * 0.6, off.y * 0.6, 1.0).normalized(), Vector3.UP)
			g.scale = Vector3(1, 1, randf_range(0.8, 1.6))
			gusts.append([g, g.position, g.position + Vector3(off.x * 1.5, off.y * 1.5, 3.5), g.scale, 0.0])
	# 빔을 따라 바깥으로 흘러가는 링 (고속)
	ring_t -= dt
	if ring_t <= 0.0:
		ring_t = 0.045
		var ring := _take(_pool_ring, _torus, Pal.CYAN if randf() < 0.6 else Color("b8a0ff"), 1.8)
		flowing.append([ring, 0.4])
	i = flowing.size() - 1
	while i >= 0:
		var f: Array = flowing[i]
		var ring := f[0] as MeshInstance3D
		f[1] += dt * 60.0
		if f[1] > length:
			_give(_pool_ring, ring)
			flowing.remove_at(i)
		else:
			ring.position = Vector3(0, 0, -f[1])
			var rs: float = W * (0.9 + f[1] / length * 0.4)
			ring.basis = Basis(Vector3.RIGHT, -PI * 0.5) * Basis.from_scale(Vector3(rs, 0.08, rs))
		i -= 1
	if fmod(t, 0.25) < dt:
		FX.shockwave(global_position, Pal.CYAN, 2.0, 0.22, 0.05)


## 역풍 줄기: 0.12초 동안 밖으로 밀려나며 줄어든다 (예전 Tween 과 같은 선형 보간, 끝나는 중에도 마저 움직인다)
func _update_gusts(dt: float) -> void:
	var i := gusts.size() - 1
	while i >= 0:
		var gu: Array = gusts[i]
		var g := gu[0] as MeshInstance3D
		gu[4] += dt / 0.12
		if gu[4] >= 1.0:
			_give(_pool_gust, g)
			gusts.remove_at(i)
		else:
			var gk: float = gu[4]
			g.position = (gu[1] as Vector3).lerp(gu[2], gk)
			g.scale = (gu[3] as Vector3).lerp(Vector3(0.2, 0.2, 0.1), gk)
		i -= 1


## 숨겨 둔 노드를 꺼내 색을 다시 칠한다 (없으면 새로 만든다)
func _take(pool: Array[MeshInstance3D], mesh: Mesh, c: Color, energy: float) -> MeshInstance3D:
	if pool.is_empty():
		var mi := Pal.flat_mesh(mesh, c, energy)
		add_child(mi)
		return mi
	var n: MeshInstance3D = pool.pop_back()
	n.set_instance_shader_parameter("tint", c)
	n.set_instance_shader_parameter("energy", energy)
	n.visible = true
	return n


func _give(pool: Array[MeshInstance3D], n: MeshInstance3D) -> void:
	n.visible = false
	pool.append(n)
