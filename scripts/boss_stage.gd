extends Node3D
## 추격 보스전 무한 배경 (연출 전용).
## 플레이어와 보스는 원점 근처에 머물고, 바닥 무늬·양옆 구조물·바람 줄기가 +Z(화면 아래)로 흘러 전진하는 느낌을 만든다.
## 구조물은 구간 단위로 재활용한다.

const HALF_W := 10.0              # 플레이어가 움직일 수 있는 좌우 반폭
const SEG_LEN := 12.0             # 양옆 구조물 한 구간 길이
const SEG_COUNT := 11
const FAR_Z := -95.0              # 구조물이 나타나는 곳
const NEAR_Z := 37.0              # 여기를 지나면 맨 뒤로 되돌린다
const STREAKS := 46

var speed := 42.0                 # 흐르는 속도 (m/s)
var scroll := 0.0
var floor_mat: ShaderMaterial
var segments: Array[Node3D] = []
var streaks: Array = []           # [node, speed_mul]
var drifters: Array = []          # [node, vel, spin, floor_bounce, life]
var _streak_mesh: BoxMesh
var t := 0.0

const FLOOR_SHADER := """
shader_type spatial;
render_mode cull_disabled, shadows_disabled;
uniform float scroll = 0.0;
uniform float speed = 40.0;
uniform float half_w = 10.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float hash(float n) { return fract(sin(n * 91.345) * 47453.21); }
void fragment() {
	float z = wp.z - scroll;          // 바닥에 붙은 좌표 (앞으로 갈수록 +Z 로 흘러감)
	float x = wp.x;
	float ax = abs(x);
	// 속도에 비례해 이음선을 진행 방향으로 번지게 한다 (모션 블러)
	float blur = clamp(speed / 40.0, 0.2, 2.0);
	vec3 base = vec3(0.10, 0.10, 0.17);
	// 판 이음선: 가로 이음은 번지고, 세로(차선) 이음은 선명하다
	float cz = fract(z / 6.0);
	float seam_z = smoothstep(0.06 * blur, 0.0, min(cz, 1.0 - cz) * 6.0 / 6.0);
	float lane = fract((x + half_w) / 4.0);
	float seam_x = smoothstep(0.03, 0.0, min(lane, 1.0 - lane) * 4.0 / 4.0 * 0.5);
	float row = floor(z / 6.0);
	float cell = floor((x + 40.0) / 4.0);
	float shade = hash(row * 13.0 + cell) * 0.035;
	vec3 col = base + vec3(shade, shade, shade * 1.4);
	col = mix(col, vec3(0.05, 0.05, 0.09), seam_z * 0.8);
	col = mix(col, vec3(0.05, 0.05, 0.1), seam_x * 0.7);
	// 차선 중앙 청록 점선: 길게 늘어진 채 빠르게 흘러간다
	float lx = fract((x + half_w - 2.0) / 4.0);
	float in_lane = smoothstep(0.035, 0.0, abs(lx - 0.5) * 4.0 / 4.0 * 0.5);
	float dash = step(0.55, fract(z / 9.0));
	float dash_soft = smoothstep(0.35, 0.55, fract(z / 9.0)) * (1.0 - smoothstep(0.95, 1.0, fract(z / 9.0)));
	vec3 glow = vec3(0.2, 0.9, 1.0) * in_lane * mix(dash, dash_soft, 0.5) * 0.9 * step(ax, half_w);
	// 전장 가장자리: 주황·검정 빗금 띠
	float edge = step(half_w, ax) * step(ax, half_w + 1.1);
	float chev = step(0.5, fract((z * 0.5 + ax) * 0.6));
	vec3 edge_col = mix(vec3(0.05, 0.04, 0.05), vec3(1.0, 0.45, 0.08) * 0.9, chev);
	col = mix(col, edge_col, edge);
	float rim = smoothstep(0.12, 0.0, abs(ax - half_w - 1.2));
	glow += vec3(1.0, 0.35, 0.1) * rim * 1.2;
	// 바깥 도로: 더 어둡고 줄무늬가 빠르게 지나간다
	float outside = step(half_w + 1.3, ax);
	float stripe = smoothstep(0.1, 0.0, abs(fract(z / 3.0) - 0.5) - 0.3) * 0.3;
	col = mix(col, vec3(0.05, 0.05, 0.08) + stripe * vec3(0.05, 0.05, 0.1), outside);
	// 멀리 갈수록 어두워진다
	float fog = smoothstep(-20.0, -85.0, wp.z);
	col = mix(col, vec3(0.02, 0.02, 0.05), fog);
	glow *= 1.0 - fog * 0.7;
	ALBEDO = col;
	EMISSION = glow;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
}
"""


func _ready() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 150)
	var fl := MeshInstance3D.new()
	fl.mesh = plane
	fl.position = Vector3(0, 0, -30)
	var sh := Shader.new()
	sh.code = FLOOR_SHADER
	floor_mat = ShaderMaterial.new()
	floor_mat.shader = sh
	floor_mat.set_shader_parameter("half_w", HALF_W)
	fl.material_override = floor_mat
	add_child(fl)
	for i in SEG_COUNT:
		var s := _build_segment(i)
		s.position.z = NEAR_Z - (i + 1) * SEG_LEN
		add_child(s)
		segments.append(s)
	_streak_mesh = BoxMesh.new()
	_streak_mesh.size = Vector3(0.05, 0.05, 1.0)
	for i in STREAKS:
		var mi := Pal.flat_mesh(_streak_mesh, Color(0.75, 0.95, 1.0), 1.4)
		add_child(mi)
		streaks.append([mi, 1.0])
		_reset_streak(streaks[i], true)


## 한 구간: 양옆 벽 + 발광 띠 + 기둥 + 가로등 + 멀리 서 있는 탑
func _build_segment(i: int) -> Node3D:
	var s := Node3D.new()
	var BT := preload("res://scripts/boss_tank.gd")
	var wall_c := Color("2a2a44")
	var wall_top := Color("3a3a5a")
	for side in [-1, 1]:
		var x: float = side * (HALF_W + 3.4)
		BT.rbox(s, Vector3(2.4, 1.6, SEG_LEN - 0.4), 0.3, Vector3(x, 0.8, 0), wall_c)
		BT.rbox(s, Vector3(2.6, 0.3, SEG_LEN - 0.2), 0.12, Vector3(x, 1.7, 0), wall_top)
		BT.glow(s, Vector3(0.1, 0.1, SEG_LEN - 1.2), Vector3(x - side * 1.3, 1.25, 0), Color("ff7a2a") if i % 2 == 0 else Pal.CYAN, 1.6)
		# 기둥과 가로등 (구간마다 하나)
		var px: float = side * (HALF_W + 5.2)
		BT.rbox(s, Vector3(0.9, 7.0, 0.9), 0.3, Vector3(px, 3.5, -SEG_LEN * 0.5 + 0.6), Color("30304c"))
		BT.rbox(s, Vector3(2.8, 0.35, 0.6), 0.15, Vector3(px - side * 1.2, 6.9, -SEG_LEN * 0.5 + 0.6), Color("3c3c5c"))
		BT.glow(s, Vector3(1.8, 0.1, 0.3), Vector3(px - side * 1.5, 6.7, -SEG_LEN * 0.5 + 0.6), Color(1.0, 0.9, 0.7), 2.2)
		# 먼 탑: 높이를 섞어 스카이라인을 만든다
		var h := 8.0 + fmod(float(i * 7 + (3 if side > 0 else 0)), 5.0) * 3.0
		BT.rbox(s, Vector3(4.0, h, 5.0), 0.5, Vector3(side * (HALF_W + 12.0 + fmod(i * 3.0, 4.0)), h * 0.5, 0), Color("1c1c30"))
		for k in 3:
			BT.glow(s, Vector3(0.12, 0.35, 3.0), Vector3(side * (HALF_W + 9.95 + fmod(i * 3.0, 4.0)), h * (0.35 + 0.22 * k), 0), Color("ff3a5a") if (i + k) % 3 == 0 else Color("5ae0ff"), 1.4)
	return s


func _reset_streak(s: Array, anywhere := false) -> void:
	var mi: MeshInstance3D = s[0]
	var x := randf_range(-HALF_W - 6.0, HALF_W + 6.0)
	var y := randf_range(0.4, 7.0) if absf(x) > HALF_W else randf_range(0.2, 4.5)
	var z := randf_range(FAR_Z * 0.6, NEAR_Z * 0.8) if anywhere else randf_range(FAR_Z * 0.6, FAR_Z * 0.3)
	mi.position = Vector3(x, y, z)
	s[1] = randf_range(1.15, 1.7)
	var l := randf_range(3.0, 7.0)
	mi.scale = Vector3(1, 1, l)
	mi.set_instance_shader_parameter("energy", randf_range(0.6, 1.5))


func _process(dt: float) -> void:
	t += dt
	var d := speed * dt
	scroll += d
	floor_mat.set_shader_parameter("scroll", scroll)
	floor_mat.set_shader_parameter("speed", speed)
	for s in segments:
		s.position.z += d
		if s.position.z > NEAR_Z:
			s.position.z -= SEG_COUNT * SEG_LEN
	var k := clampf(speed / 40.0, 0.0, 1.5)
	for s in streaks:
		var mi: MeshInstance3D = s[0]
		mi.position.z += d * s[1]
		mi.visible = k > 0.1
		if mi.position.z > NEAR_Z * 0.8:
			_reset_streak(s)
	_update_drifters(dt)


# ── 흘러가는 조각 · 연기 ────────────────────────────────

## 전장 좌표에 떨어진 물체를 도로와 함께 뒤로 흘려보낸다. 바닥에 닿으면 튕기다 미끄러진다.
func drift(n: Node3D, vel: Vector3, spin := Vector3.ZERO, bounce := true, life := 6.0) -> void:
	drifters.append([n, vel, spin, bounce, life])


func _update_drifters(dt: float) -> void:
	for i in range(drifters.size() - 1, -1, -1):
		var e: Array = drifters[i]
		var n: Node3D = e[0]
		if not is_instance_valid(n):
			_swap_remove(drifters, i)
			continue
		var v: Vector3 = e[1]
		if e[3]:
			v.y -= 22.0 * dt
			if n.global_position.y < 0.35 and v.y < 0.0:
				v.y = -v.y * 0.35 if v.y < -3.0 else 0.0
				# 도로에 닿는 순간 도로 속도로 끌려간다
				v.z = lerpf(v.z, speed, 0.6)
				v.x *= 0.7
				e[2] = (e[2] as Vector3) * 0.7
				if randf() < 0.5:
					FX.sparks(n.global_position, 5, [Color("ffd060"), Color("ff6a20")], 5.0, 0.3, -8.0, 0.06)
		n.global_position += v * dt
		var sp: Vector3 = e[2]
		if sp.length() > 0.01:
			n.rotate(sp.normalized(), sp.length() * dt)
		e[1] = v
		e[4] -= dt
		if e[4] <= 0.0 or n.global_position.z > NEAR_Z + 10.0:
			n.queue_free()
			_swap_remove(drifters, i)


## 순서가 상관없는 목록에서 i 번째를 마지막 원소로 덮어 지운다 (remove_at 의 당김 비용 없이).
## 뒤에서 앞으로 도는 반복 안에서만 쓴다: 옮겨 오는 마지막 원소는 이미 이번 프레임에 처리됐다.
static func _swap_remove(arr: Array, i: int) -> void:
	var last := arr.size() - 1
	if i != last:
		arr[i] = arr[last]
	arr.resize(last)


## 도로 속도로 뒤로 날리는 연기 (가장자리가 부드러운 반투명 구체, 점점 옅어지며 사라진다)
## add=true 면 빛나는 배기(가산 혼합)
func puff(pos: Vector3, c: Color, size: float, life := 0.6, rel_speed := 1.0, add := false) -> void:
	if _puff_mesh == null:
		_puff_mesh = SphereMesh.new()
		_puff_mesh.radius = 0.5
		_puff_mesh.height = 1.0
		_puff_mesh.radial_segments = 12
		_puff_mesh.rings = 6
		for i in 2:
			var sh := Shader.new()
			sh.code = PUFF_SHADER.replace("MODE", "blend_add" if i == 1 else "blend_mix")
			var m := ShaderMaterial.new()
			m.shader = sh
			_puff_mats.append(m)
	var mi := MeshInstance3D.new()
	mi.mesh = _puff_mesh
	mi.material_override = _puff_mats[1 if add else 0]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("fade", 1.0)
	add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * size * 0.35
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * size, life).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v: float): mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, life)
	drift(mi, Vector3(randf_range(-0.6, 0.6), randf_range(0.8, 2.0), speed * rel_speed * randf_range(0.8, 1.0)), Vector3.ZERO, false, life + 0.05)


var _puff_mesh: SphereMesh
var _puff_mats: Array[ShaderMaterial] = []

const PUFF_SHADER := """
shader_type spatial;
render_mode unshaded, MODE, depth_draw_never, cull_back, shadows_disabled;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float fade = 1.0;
void fragment() {
	float rim = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = tint.rgb;
	ALPHA = tint.a * fade * pow(rim, 1.6);
}
"""
