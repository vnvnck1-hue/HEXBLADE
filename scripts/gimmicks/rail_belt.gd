class_name RailBelt
extends Node3D
## 레일(바닥 컨베이어): 길이 length · 폭 WIDTH 의 띠가 dir 방향으로 끊임없이 흐른다.
## 위에 선 캐릭터는 push_at 이 돌려주는 속도만큼 실려 간다 (Player.carry 로 이동에 더해진다).
## 띠 무늬(가로 살 · 진행 방향 화살표)는 셰이더가 TIME 으로 흘려 보낸다. 노드 원점 = 띠 가운데.

const WIDTH := 2.2
const SPEED := 5.0

const SHADER := """
shader_type spatial;
render_mode cull_back;
uniform float speed = 5.0;
uniform float length_m = 10.0;
uniform float width_m = 2.2;
uniform vec4 slat : source_color = vec4(0.16, 0.17, 0.22, 1.0);
uniform vec4 seam : source_color = vec4(0.05, 0.05, 0.07, 1.0);
uniform vec4 arrow : source_color = vec4(1.0, 0.72, 0.2, 1.0);
void fragment() {
	// UV.y = 띠 길이 방향(진행 방향이 +), UV.x = 폭 방향
	float along = UV.y * length_m - TIME * speed;
	float across = (UV.x - 0.5) * width_m;
	// 가로 살: 0.5m 마다 이음새
	float f = fract(along / 0.5);
	float sm = smoothstep(0.0, 0.06, f) * smoothstep(1.0, 0.92, f);
	vec3 c = mix(seam.rgb, slat.rgb, sm);
	// 살 위의 미끄럼 방지 홈
	c *= 0.9 + 0.1 * step(0.5, fract(across * 6.0));
	// 진행 방향 화살표 (2m 마다 V 자 두 줄)
	float g = fract(along / 2.0) * 2.0;
	float v = g + abs(across) * 0.55;
	float ar = smoothstep(0.02, 0.0, abs(v - 0.6) - 0.05) + smoothstep(0.02, 0.0, abs(v - 0.85) - 0.05);
	ar *= step(abs(across), 0.62);
	// 양 옆 경고 줄무늬
	float edge = step(width_m * 0.5 - 0.14, abs(across));
	float stripe = step(0.5, fract((along + across * (across > 0.0 ? 1.0 : -1.0)) / 0.4));
	vec3 hz = mix(vec3(0.07, 0.06, 0.05), vec3(0.95, 0.72, 0.12), stripe);
	c = mix(c, hz, edge);
	ALBEDO = c;
	ALBEDO = mix(c, arrow.rgb * 0.5, ar * (1.0 - edge));
	EMISSION = arrow.rgb * ar * 0.75 * (1.0 - edge);
	ROUGHNESS = 0.55;
	METALLIC = 0.5;
}
"""

static var _shader: Shader
static var _roller_mesh: CylinderMesh

var dir := Vector3.RIGHT
var length := 10.0
var speed := SPEED
var _rollers: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("rail_belts")
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
		_roller_mesh = CylinderMesh.new()
		_roller_mesh.top_radius = 0.16
		_roller_mesh.bottom_radius = 0.16
		_roller_mesh.height = WIDTH - 0.1
		_roller_mesh.radial_segments = 10
	# 띠의 로컬 -Z 가 아닌 +Z 를 진행 방향으로 둔다 (UV.y 가 +Z 로 늘어나도록)
	basis = Basis.looking_at(-dir, Vector3.UP)
	# 띠 표면 (바닥에서 6cm 띄움)
	var belt := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(WIDTH, length)
	belt.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("speed", speed)
	mat.set_shader_parameter("length_m", length)
	mat.set_shader_parameter("width_m", WIDTH)
	belt.material_override = mat
	belt.position.y = 0.06
	belt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(belt)
	# 받침 틀 · 옆 레일 · 양 끝 롤러 덮개
	Build.box(self, Vector3(WIDTH + 0.1, 0.05, length + 0.2), Vector3(0, 0.025, 0), Color(0.12, 0.12, 0.16))
	for sx in [-1.0, 1.0]:
		Build.box(self, Vector3(0.12, 0.13, length + 0.3), Vector3(sx * (WIDTH * 0.5 + 0.06), 0.065, 0), Color(0.36, 0.38, 0.46))
		Build.box(self, Vector3(0.05, 0.03, length + 0.2), Vector3(sx * (WIDTH * 0.5 + 0.06), 0.14, 0), Color(1.0, 0.7, 0.22), Vector3.ZERO, 1.2)
		for k in int(length / 2.0) + 1:
			var z := -length * 0.5 + k * 2.0
			Build.box(self, Vector3(0.16, 0.16, 0.16), Vector3(sx * (WIDTH * 0.5 + 0.08), 0.08, z), Color(0.22, 0.23, 0.29))
	for sz in [-1.0, 1.0]:
		var r := MeshInstance3D.new()
		r.mesh = _roller_mesh
		r.material_override = Pal.lit(Color(0.42, 0.44, 0.52))
		r.rotation.z = PI * 0.5
		r.position = Vector3(0, 0.08, sz * length * 0.5)
		add_child(r)
		_rollers.append(r)
		Build.box(self, Vector3(WIDTH + 0.3, 0.07, 0.22), Vector3(0, 0.035, sz * (length * 0.5 + 0.14)), Color(0.3, 0.31, 0.38))


func _process(dt: float) -> void:
	# 롤러는 띠 속도에 맞춰 돈다
	for r in _rollers:
		r.rotate_object_local(Vector3.UP, speed / 0.16 * dt)


## 점 p 에 선 캐릭터가 받는 속도 (띠 밖이면 0)
func push_at(p: Vector3) -> Vector3:
	var l := global_transform.affine_inverse() * p
	if absf(l.x) > WIDTH * 0.5 or absf(l.z) > length * 0.5 or l.y > 0.45 or l.y < -0.4:
		return Vector3.ZERO
	return dir * speed


func contains(p: Vector3) -> bool:
	return push_at(p) != Vector3.ZERO
