class_name BlastScorch
extends Node3D
## 가스통이 터진 자리 (연출 전용): 사방으로 뻗은 그을음 데칼 + 줄기를 따라 일렁이는 불꽃 + 깜빡이는 불빛.
## 불은 몇 초 타다 하나씩 사그라들고, 그을음은 오래 남았다가 옅어진다. 게임 판정 없음.
## 그을음 무늬는 한 번만 만들어 공유한다 (각도별 줄기 길이표 → 픽셀).

const SIZE := 7.6
const LIFE := 18.0
const FADE := 5.0
const FLAMES := Vector2i(7, 10)

const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
instance uniform float seed = 0.0;
instance uniform float power = 1.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += noise(p) * a; p *= 2.1; a *= 0.5; } return v; }
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	float h = 1.0 - UV.y;
	float x = (UV.x - 0.5) * 2.0;
	float n = fbm(vec2(UV.x * 3.0 + seed * 9.0, h * 2.2 - TIME * 2.6 + seed * 5.0));
	float lick = (n - 0.5) * 0.9 * h;
	float w = 0.85 * pow(max(1.0 - h, 0.0), 0.65) + 0.04;
	float d = abs(x + lick) / w;
	float body = smoothstep(1.0, 0.35, d) * smoothstep(1.0, 0.55, h + (n - 0.4) * 0.45) * smoothstep(0.0, 0.07, h);
	float heat = body * (1.15 - h * 0.85);
	vec3 c = mix(vec3(0.55, 0.06, 0.02), vec3(1.0, 0.36, 0.05), smoothstep(0.1, 0.45, heat));
	c = mix(c, vec3(1.0, 0.78, 0.25), smoothstep(0.45, 0.8, heat));
	c = mix(c, vec3(1.0, 0.97, 0.82), smoothstep(0.85, 1.05, heat));
	ALBEDO = c * body * power * 1.5;
	ROUGHNESS = 0.0;
}
"""

static var _tex: ImageTexture
static var _flame_mat: ShaderMaterial
static var _flame_quad: QuadMesh

var age := 0.0
var _decal: Decal
var _flames: Array = []           # [mesh, 시작, 끝, 기본 크기, 시드]
var _light: OmniLight3D
var _smoke_t := 0.0


static func spawn(parent: Node3D, pos: Vector3) -> BlastScorch:
	var s := BlastScorch.new()
	parent.add_child(s)
	s.global_position = pos
	return s


static func _shared() -> void:
	if _tex:
		return
	_tex = ImageTexture.create_from_image(_make_image(256))
	var sh := Shader.new()
	sh.code = FLAME_SHADER
	_flame_mat = ShaderMaterial.new()
	_flame_mat.shader = sh
	_flame_mat.render_priority = 3
	_flame_quad = QuadMesh.new()
	_flame_quad.size = Vector2(1, 1)
	_flame_quad.center_offset = Vector3(0, 0.5, 0)


## 사방으로 뻗은 그을음: 가운데 짙은 원 + 길이가 제각각인 날카로운 줄기 + 얼룩
static func _make_image(n: int) -> Image:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7171
	const BINS := 720
	var reach := PackedFloat32Array()
	reach.resize(BINS)
	reach.fill(0.32)
	# 줄기: 각도 폭 안에서 끝으로 갈수록 가늘어지는 삼각형 길이표
	for i in 64:
		var a := rng.randf() * BINS
		var ln := rng.randf_range(0.45, 0.98) if rng.randf() < 0.6 else rng.randf_range(0.36, 0.6)
		var w := rng.randf_range(3.0, 11.0)
		for k in range(-int(w), int(w) + 1):
			var b := posmod(int(a) + k, BINS)
			var l := ln * (1.0 - absf(k) / (w + 1.0))
			reach[b] = maxf(reach[b], l)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var spk := FastNoiseLite.new()
	spk.seed = 33
	spk.frequency = 0.09
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			if r >= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var b := int((atan2(v, u) / TAU + 0.5) * BINS) % BINS
			var rl: float = reach[b]
			var nz := spk.get_noise_2d(x, y) * 0.5 + 0.5
			var core := 1.0 - smoothstep(0.12, 0.36, r)
			var ray := 1.0 - smoothstep(rl * 0.55, rl, r + (nz - 0.5) * 0.12)
			var a := clampf(core * 0.95 + ray * (0.55 + nz * 0.4), 0.0, 1.0)
			a *= 1.0 - smoothstep(0.88, 1.0, r)
			# 가운데는 갈색 탄 자국, 바깥은 검은 그을음
			var c := Color(0.07, 0.05, 0.04).lerp(Color(0.02, 0.02, 0.025), smoothstep(0.1, 0.5, r))
			img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	return img


func _ready() -> void:
	_shared()
	add_to_group("blast_scorches")
	_decal = Decal.new()
	_decal.size = Vector3(SIZE, 1.4, SIZE)
	_decal.texture_albedo = _tex
	_decal.albedo_mix = 1.0
	_decal.upper_fade = 0.25
	_decal.lower_fade = 0.25
	_decal.normal_fade = 0.55
	_decal.rotation.y = randf() * TAU
	add_child(_decal)
	# 불꽃: 그을음 줄기 위 여기저기서 타오른다 (가운데일수록 크고 오래)
	var n := randi_range(FLAMES.x, FLAMES.y)
	for i in n:
		var a := randf() * TAU
		var r := sqrt(randf()) * 2.4 + 0.15
		var big := 1.0 - r / 2.8
		var mi := MeshInstance3D.new()
		mi.mesh = _flame_quad
		mi.material_override = _flame_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sd := snappedf(randf(), 0.05)
		mi.set_instance_shader_parameter("seed", sd)
		mi.set_instance_shader_parameter("power", 0.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		p.y = Main.gy(global_position + p) - global_position.y
		mi.position = p
		mi.scale = Vector3.ONE * 0.01
		add_child(mi)
		var size := Vector2(lerpf(0.5, 1.0, big), lerpf(0.8, 1.7, big)) * randf_range(0.85, 1.15)
		_flames.append([mi, randf() * 0.25, lerpf(3.5, 8.5, big) + randf() * 1.5, size, sd * 13.0])
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.22)
	_light.omni_range = 5.5
	_light.light_energy = 2.5
	_light.shadow_enabled = false
	_light.position.y = 0.8
	add_child(_light)


func _process(dt: float) -> void:
	age += dt
	var alive := 0.0
	for f in _flames:
		if not is_instance_valid(f[0]):
			continue
		var mi: MeshInstance3D = f[0]
		var t0: float = f[1]
		var t1: float = f[2]
		var u := age - t0
		var k := smoothstep(0.0, 0.25, u) * (1.0 - smoothstep(t1 - 1.2, t1, age))
		if age > t1:
			mi.queue_free()
			continue
		alive += k
		var sd: float = f[4]
		# 일렁임: 높이가 숨 쉬듯 늘었다 줄고 좌우로 흔들린다
		var flick := 1.0 + sin(age * 9.0 + sd) * 0.12 + sin(age * 23.0 + sd * 2.0) * 0.07
		var sz: Vector2 = f[3]
		mi.scale = Vector3(sz.x * (1.0 + sin(age * 7.0 + sd) * 0.06), sz.y * flick, 1.0) * maxf(k, 0.01)
		mi.set_instance_shader_parameter("power", k)
	var n := maxf(float(_flames.size()), 1.0)
	_light.light_energy = 2.6 * clampf(alive / n * 1.6, 0.0, 1.0) * (0.85 + 0.15 * sin(age * 17.0) * sin(age * 5.3))
	_light.visible = _light.light_energy > 0.02
	# 불이 남아 있는 동안 검은 연기와 불티가 가끔 오른다
	if alive > 0.5:
		_smoke_t -= dt
		if _smoke_t <= 0.0:
			_smoke_t = randf_range(0.18, 0.4)
			var off := Vector3(randf_range(-1.6, 1.6), 0.9, randf_range(-1.6, 1.6))
			FX.puffs(global_position + off, 1, [Color("3a3036"), Color("2a2428"), Color("161216"), Color("100c10")], 0.3, 0.45, 1.1)
			if randf() < 0.5:
				FX.sparks(global_position + off * 0.6, 3, [Color("ffd060"), Color("ff7a30")], 2.5, 0.8, 2.0, 0.04)
	var fade := 1.0 - smoothstep(LIFE - FADE, LIFE, age)
	_decal.modulate = Color(1, 1, 1, fade)
	if age >= LIFE:
		queue_free()
