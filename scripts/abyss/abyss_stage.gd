extends Node3D
## 심연 성소(LAYER 01) 전장. 판정은 abyss_main.gd 가 이 파일의 격자(walk/block)를 읽는다.
## 2m 석판 15×15 격자가 붉은 심연 위에 떠 있고, 페이즈마다 판이 솟고 가라앉아 전장 모양이 바뀐다 (apply_layout).
## 판 종류: 빈칸(심연으로 가라앉음) · 바닥 · 기둥(솟아 엄폐물이 됨) · 분출구(바닥, 주기적으로 체액이 솟는다).
## 바깥 배경(거석·아치·가시·사슬·후광 잔해)은 abyss_props.gd, 함정(레이저 탑·분출구)은 abyss_hazards.gd 가 맡는다.

const Props := preload("res://scripts/abyss/abyss_props.gd")

const TILE := 2.0
const N := 15
const HALF := 7                       # 가운데 칸 번호
const BLOCK_H := 6.0                  # 판 두께 (윗면 기준 아래로)
const PILLAR_Y := 3.2                 # 기둥 윗면 높이
const SUNK_Y := -15.0                 # 가라앉은 판 윗면 높이 (보이지 않는다)
const VOID_Y := -30.0                 # 심연 바닥면
const ABYSS := Color(1.0, 0.07, 0.13) # 심연의 빛

enum K { VOID, FLOOR, PILLAR, VENT }

## 페이즈별 판 배치. '.' 빈칸 · '#' 바닥 · 'P' 기둥 · 'v' 분출구. 첫 줄이 북쪽(-Z).
const LAYOUTS := {
	"descent": [
		"...............",
		"...............",
		"...............",
		".....#####.....",
		"....#######....",
		"...#########...",
		"...#########...",
		"...#########...",
		"...#########...",
		"...#########...",
		"....#######....",
		".....#####.....",
		"...............",
		"...............",
		"...............",
	],
	"wings": [
		"...............",
		"......###......",
		".....#####.....",
		"...#########...",
		"..###########..",
		".####v###v####.",
		".#############.",
		".#############.",
		".#############.",
		".####v###v####.",
		"..###########..",
		"...#########...",
		".....#####.....",
		"......###......",
		"...............",
	],
	"ring": [
		"...............",
		"...............",
		"..###########..",
		"..###########..",
		"..###########..",
		"..###.....###..",
		"..###.....###..",
		"..###.....###..",
		"..###.....###..",
		"..###.....###..",
		"..###########..",
		"..###########..",
		"..###########..",
		"...............",
		"...............",
	],
	"colonnade": [
		"...............",
		".#############.",
		".#############.",
		".##P##v#v##P##.",
		".#############.",
		".#v#P#####P#v#.",
		".#############.",
		".#############.",
		".#############.",
		".#v#P#####P#v#.",
		".#############.",
		".##P##v#v##P##.",
		".#############.",
		".#############.",
		"...............",
	],
	"sanctum": [
		"...............",
		"...............",
		"..###########..",
		".#############.",
		".#############.",
		".###P#####P###.",
		".#############.",
		".#############.",
		".#############.",
		".###P#####P###.",
		".#############.",
		"..###########..",
		"...#########...",
		"...............",
		"...............",
	],
	"cross": [
		"...............",
		"...............",
		"....#######....",
		"....###v###....",
		"....#######....",
		".#############.",
		".#v#########v#.",
		".#############.",
		".#############.",
		".#############.",
		"....#######....",
		"....###v###....",
		"....#######....",
		"...............",
		"...............",
	],
	"last": [
		"...............",
		"...............",
		"...............",
		"...............",
		"...............",
		".....#####.....",
		".....#####.....",
		".....#####.....",
		".....#####.....",
		".....#####.....",
		"...............",
		"...............",
		"...............",
		"...............",
		"...............",
	],
}

## 판 하나: {node, mi, kind(목표), y, vy, target, walk, block, warn, delay, moving, deco}
var tiles: Array = []
var layout := ""
var tile_mat: ShaderMaterial
var void_mat: ShaderMaterial
var props: Node3D
var t := 0.0
var vent_rev := 0                    # 분출구 목록이 바뀔 때마다 1씩 오른다 (함정 쪽이 다시 읽을지 판단)
var _vent_cache: Array[Vector2i] = []
var _vent_dirty := true              # 판이 움직이는 동안만 분출구 목록을 다시 센다
var shift_t := 0.0                    # 지금 진행 중인 전장 변화의 남은 시간
var _box: BoxMesh
var _rubble: Array = []               # [node, vel, spin, life]
var _dust_mesh: SphereMesh
var _dust_mats: Array[ShaderMaterial] = []
var _puffs: Array = []                # [node, vel, life, max, s0, s1, grav]
var _brazier_lights: Array = []       # [OmniLight3D, base_energy, phase]
var heat := 0.0                       # 심연의 빛 세기 (보스전·연출에서 오른다)


# ── 셰이더 ──────────────────────────────────────────────

const NOISE := """
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float s = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { s += vnoise(p) * a; p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return s;
}
// 그래디언트 노이즈 (값 노이즈의 격자 계단이 드러나지 않는다) · 옥타브마다 회전하는 fbm
vec2 ghash(vec2 p) {
	float a = hash2(p) * 6.2831853;
	return vec2(cos(a), sin(a));
}
float gnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = dot(ghash(i), f);
	float b = dot(ghash(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float c = dot(ghash(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float d = dot(ghash(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return 0.5 + 0.7 * mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
float gfbm(vec2 p) {
	mat2 r = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8));
	float s = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { s += gnoise(p) * a; p = r * p * 2.02 + vec2(3.1, 1.7); a *= 0.5; }
	return s / 0.97;
}
"""

## 석판: 윗면은 낡은 청회색 판석(이음매·균열·젖은 얼룩·각인 고리·분출구 창살), 옆면은 지층 무늬 위로 아래에서 심연 빛이 번진다
const TILE_SHADER := """
shader_type spatial;
instance uniform float warn = 0.0;
instance uniform float vent = 0.0;
instance uniform float seed = 0.0;
instance uniform float pillar = 0.0;
uniform vec3 abyss_col : source_color = vec3(1.0, 0.07, 0.13);
uniform float heat = 0.0;
uniform int dbg = 0;
varying vec3 wp;
varying vec3 wn;
varying vec3 lp;
NOISE
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	lp = VERTEX;
}
float line(float d, float w) { return 1.0 - smoothstep(0.0, w, abs(d)); }
void fragment() {
	vec3 col;
	vec3 em = vec3(0.0);
	float rough = 0.82;
	float spec = 0.4;
	if (wn.y > 0.6) {
		vec2 uv = lp.xz / 1.98 + 0.5;
		float h = hash2(vec2(seed, 3.1));
		vec2 suv = uv;
		if (h < 0.3) suv = fract(uv * 2.0);
		else if (h < 0.55) suv = vec2(fract(uv.x * 2.0), uv.y);
		else if (h < 0.7) suv = vec2(uv.x, fract(uv.y * 2.0));
		float edge = min(min(suv.x, 1.0 - suv.x), min(suv.y, 1.0 - suv.y));
		float tedge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
		float n = gfbm(wp.xz * 0.45);
		float n2 = gnoise(wp.xz * 6.0);
		vec3 base = mix(vec3(0.055, 0.065, 0.07), vec3(0.095, 0.105, 0.11), n);
		base *= 0.95 + 0.07 * hash2(floor(suv * 0.999 + vec2(seed)) + vec2(seed * 3.0, 1.0));
		// 젖은 얼룩: 어둡고 매끈해 빛을 받으면 번들거린다
		float stain = smoothstep(0.55, 0.72, gfbm(wp.xz * 0.3 + vec2(7.0, 3.0)));
		if (dbg == 2) stain = 0.0;
		base = mix(base, base * 0.42 + vec3(0.02, 0.0, 0.003), stain);
		rough = mix(0.86, 0.18, stain);
		spec = mix(0.35, 0.75, stain);
		// 이음매와 모서리 마모
		base *= mix(0.62, 1.0, smoothstep(0.0, 0.012, edge));
		base *= mix(0.2, 1.0, smoothstep(0.0, 0.01, tedge));
		// 갈라진 금
		float cn = gnoise(wp.xz * 0.9 + seed * 3.0);
		float cr = line(cn - 0.5, 0.012) * step(0.72, hash2(vec2(seed, 9.0)));
		base = mix(base, vec3(0.015, 0.012, 0.015), cr * 0.9);
		base *= 0.88 + 0.24 * n2;
		col = base;
		// 가운데 각인 고리: 점선 고리 · 가는 고리 · 눈금 · 안쪽 별꼴
		float r = length(wp.xz);
		float ang = atan(wp.z, wp.x);
		float dash = step(0.42, fract(ang * 36.0 / 6.2831853 + TIME * 0.05));
		float rune = line(r - 5.2, 0.07) * dash + line(r - 4.55, 0.025) + line(r - 2.1, 0.03) * 0.8;
		rune += line(r - 4.85, 0.22) * step(0.9, fract(ang * 60.0 / 6.2831853)) * 0.8;
		float star = 0.0;
		for (int i = 0; i < 3; i++) {
			float a = float(i) * 1.0471976 + 0.2618;
			vec2 d = vec2(cos(a), sin(a));
			star = max(star, line(dot(wp.xz, vec2(-d.y, d.x)), 0.03) * step(r, 4.4) * step(2.1, r));
		}
		rune += star * 0.7;
		col = mix(col, vec3(0.02, 0.006, 0.008), clamp(rune, 0.0, 1.0) * 0.75);
		em += abyss_col * rune * (0.22 + 0.14 * sin(TIME * 1.4 - r * 0.8)) * (1.0 + heat * 1.5);
		// 분출구 창살: 구멍 사이로 심연 빛이 새고, 분출이 가까우면 끓어오른다
		if (vent > 0.0) {
			float inside = step(0.14, tedge);
			vec2 g = fract(uv * 5.0) - 0.5;
			float hole = (1.0 - smoothstep(0.17, 0.23, length(g))) * inside;
			float charge = clamp(vent - 1.0, 0.0, 1.0);
			col = mix(col, vec3(0.075, 0.07, 0.075), inside * 0.7);
			col = mix(col, vec3(0.006, 0.0, 0.0), hole);
			float boil = 0.6 + 0.4 * sin(TIME * (8.0 + charge * 30.0) + hash2(floor(uv * 5.0)) * 6.0);
			em += abyss_col * hole * (0.35 + charge * charge * 7.0) * boil;
			em += abyss_col * line(tedge - 0.14, 0.012) * (0.4 + charge * 2.0);
			rough = mix(rough, 0.45, inside);
		}
		if (pillar > 0.5) {
			// 기둥 윗면: 안쪽으로 파인 판과 붉은 홈
			float inner = step(0.16, tedge);
			col = mix(col, col * 0.55, inner);
			em += abyss_col * line(tedge - 0.16, 0.012) * 1.2;
		}
		// 가라앉기 직전: 이음매와 금이 시뻘겋게 달아오른다
		float wf = warn * (0.75 + 0.25 * sin(TIME * 34.0));
		em += abyss_col * wf * (1.0 - smoothstep(0.0, 0.07, tedge)) * 3.2;
		em += abyss_col * wf * cr * 4.0;
		col *= 1.0 - warn * 0.3;
	} else {
		float depth = -wp.y;
		vec3 base = vec3(0.06, 0.064, 0.074);
		float strata = vnoise(vec2((wp.x + wp.z) * 0.7, wp.y * 2.6 + seed));
		base *= 0.55 + 0.75 * strata;
		float rib = step(0.86, fract(wp.y * 0.9 + hash2(vec2(seed, 4.0))));
		base *= 1.0 - rib * 0.45;
		col = base;
		// 아래에서 올라오는 심연 빛과 빛나는 핏줄
		float glow = smoothstep(1.0, 6.0, depth);
		float vein = smoothstep(0.66, 0.78, gnoise(vec2((wp.x - wp.z) * 1.6, wp.y * 0.8 + seed * 2.0)));
		em += abyss_col * (glow * glow * 0.07 + vein * glow * 0.55) * (0.85 + 0.15 * sin(TIME * 2.0 + wp.y)) * (1.0 + heat);
		// 윗모서리 바로 아래는 어둡게 (판 두께가 읽히도록)
		col *= 0.6 + 0.4 * smoothstep(0.0, 0.25, depth);
		// 기둥 옆면: 가는 세로 홈에 붉은 빛
		if (pillar > 0.5 && wp.y > 0.2) {
			float slit = line(fract((wp.x + wp.z) * 0.5) - 0.5, 0.03) * step(0.6, wp.y) * step(wp.y, 2.7);
			em += abyss_col * slit * (0.8 + 0.4 * sin(TIME * 3.0 + wp.y * 2.0));
		}
		em += abyss_col * warn * (0.6 + 0.4 * sin(TIME * 30.0)) * 0.8;
		rough = 0.9;
		spec = 0.25;
	}
	if (dbg == 1) { col = vec3(0.1); rough = 0.8; spec = 0.4; em = vec3(0.0); }
	if (dbg == 3) { col = vec3(gfbm(wp.xz * 0.3 + vec2(7.0, 3.0))); rough = 1.0; spec = 0.0; em = vec3(0.0); }
	ALBEDO = col;
	EMISSION = em;
	ROUGHNESS = rough;
	SPECULAR = spec;
}
"""

## 심연 바닥: 아주 아래에서 진홍빛이 소용돌이친다. 전장 바로 아래가 가장 밝다.
const VOID_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec3 abyss_col : source_color = vec3(1.0, 0.07, 0.13);
uniform float heat = 0.0;
varying vec3 wp;
NOISE
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz;
	float r = length(p);
	float a = atan(p.y, p.x);
	vec2 sw = vec2(a * 3.0 + TIME * 0.08 + r * 0.06, r * 0.08 - TIME * 0.12);
	float n = fbm(sw * 1.4 + fbm(p * 0.05 + TIME * 0.02) * 2.0);
	float cracks = smoothstep(0.6, 0.78, n);
	float core = exp(-r * 0.035);
	vec3 c = abyss_col * (0.03 + 0.3 * core) * (0.5 + n * 0.9);
	c += mix(abyss_col, vec3(1.0, 0.6, 0.55), 0.3) * cracks * (0.25 + core * 0.9);
	c *= 1.0 + heat * 0.8;
	ALBEDO = c;
}
"""

const DUST_SHADER := """
shader_type spatial;
render_mode unshaded, MODE, depth_draw_never, cull_back, shadows_disabled;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float fade = 1.0;
void fragment() {
	float rim = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = tint.rgb * (1.0 + 0.5 * rim);
	ALPHA = tint.a * fade * pow(rim, 1.6);
}
"""


func _shader(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code.replace("NOISE", NOISE)
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


# ── 구성 ────────────────────────────────────────────────

func _ready() -> void:
	tile_mat = _shader(TILE_SHADER)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dbgfloor="):
			tile_mat.set_shader_parameter("dbg", int(a.substr(11)))
	void_mat = _shader(VOID_SHADER)
	for i in 2:
		_dust_mats.append(_shader(DUST_SHADER.replace("MODE", "blend_add" if i == 1 else "blend_mix")))
	_dust_mesh = SphereMesh.new()
	_dust_mesh.radius = 0.5
	_dust_mesh.height = 1.0
	_dust_mesh.radial_segments = 10
	_dust_mesh.rings = 5
	_box = BoxMesh.new()
	_box.size = Vector3(TILE - 0.02, BLOCK_H, TILE - 0.02)
	_build_void()
	_build_tiles()
	props = Props.new()
	props.stage = self
	add_child(props)


func _build_void() -> void:
	var v := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(420, 420)
	v.mesh = pm
	v.material_override = void_mat
	v.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	v.position = Vector3(0, VOID_Y, 0)
	add_child(v)
	# 심연에 고인 빛 안개 (볼류메트릭): 전장 아래를 진홍빛으로 채우고, 가장자리 너머로 피어오른다
	var fv := FogVolume.new()
	fv.size = Vector3(90, 26, 90)
	fv.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	var fm := FogMaterial.new()
	fm.density = 0.05
	fm.albedo = Color(0.1, 0.015, 0.03)
	fm.emission = Color(0.1, 0.005, 0.015)
	fm.height_falloff = 0.09
	fm.edge_fade = 0.6
	fv.material = fm
	fv.position = Vector3(0, -19.0, 0)
	add_child(fv)
	# 전장 바로 밑의 더 짙은 빛 기둥
	var fv2 := FogVolume.new()
	fv2.size = Vector3(26, 16, 26)
	fv2.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	var fm2 := FogMaterial.new()
	fm2.density = 0.08
	fm2.albedo = Color(0.3, 0.05, 0.07)
	fm2.emission = Color(0.2, 0.01, 0.025)
	fm2.edge_fade = 1.0
	fv2.material = fm2
	fv2.position = Vector3(0, -17.0, 0)
	add_child(fv2)


func _build_tiles() -> void:
	tiles.clear()
	for j in N:
		for i in N:
			var node := Node3D.new()
			node.name = "T%d_%d" % [i, j]
			add_child(node)
			var mi := MeshInstance3D.new()
			mi.mesh = _box
			mi.material_override = tile_mat
			mi.layers = 1 | 2            # 2번 층: 체액 얼룩 데칼이 투영되는 면
			mi.position = Vector3(0, -BLOCK_H * 0.5, 0)
			mi.set_instance_shader_parameter("seed", randf() * 100.0)
			mi.set_instance_shader_parameter("warn", 0.0)
			mi.set_instance_shader_parameter("vent", 0.0)
			mi.set_instance_shader_parameter("pillar", 0.0)
			node.add_child(mi)
			node.position = Vector3((i - HALF) * TILE, SUNK_Y, (j - HALF) * TILE)
			node.visible = false
			tiles.append({"i": i, "j": j, "node": node, "mi": mi, "kind": K.VOID, "y": SUNK_Y, "vy": 0.0, "target": SUNK_Y,
				"walk": false, "block": false, "warn": 0.0, "delay": 0.0, "moving": false, "deco": null, "vent": 0.0})


# ── 격자 계산 ───────────────────────────────────────────

static func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(int(floor(p.x / TILE + 0.5)) + HALF, int(floor(p.z / TILE + 0.5)) + HALF)


static func cell_center(c: Vector2i) -> Vector3:
	return Vector3((c.x - HALF) * TILE, 0, (c.y - HALF) * TILE)


func tile_at(c: Vector2i) -> Dictionary:
	if c.x < 0 or c.y < 0 or c.x >= N or c.y >= N:
		return {}
	return tiles[c.y * N + c.x]


func walkable(c: Vector2i) -> bool:
	var tl := tile_at(c)
	return not tl.is_empty() and tl.walk


func blocked(c: Vector2i) -> bool:
	var tl := tile_at(c)
	return not tl.is_empty() and tl.block


## 수평 위치가 걸을 수 있는 판 위인가
func on_floor(p: Vector3) -> bool:
	return walkable(cell_of(p))


## 반지름 radius 의 원을 걸을 수 있는 판 안으로 밀어 넣는다 (기둥·빈칸 모두 벽처럼 취급)
func push_out(p: Vector3, radius: float) -> Vector3:
	var c := cell_of(p)
	if not walkable(c):
		p = nearest_floor(p, radius)
		c = cell_of(p)
	for _pass in 2:
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				if di == 0 and dj == 0:
					continue
				var nc := Vector2i(c.x + di, c.y + dj)
				if walkable(nc):
					continue
				var cc := cell_center(nc)
				var h := TILE * 0.5
				var q := Vector2(clampf(p.x, cc.x - h, cc.x + h), clampf(p.z, cc.z - h, cc.z + h))
				var d := Vector2(p.x, p.z) - q
				var l := d.length()
				if l < radius:
					if l < 0.0001:
						d = Vector2(p.x - cc.x, p.z - cc.z).normalized()
						l = 0.0
					else:
						d /= l
					p.x += d.x * (radius - l)
					p.z += d.y * (radius - l)
	return p


## 가장 가까운 바닥 칸 안쪽 점
func nearest_floor(p: Vector3, radius := 0.4) -> Vector3:
	var best := p
	var bd := INF
	for tl in tiles:
		if not tl.walk:
			continue
		var cc := cell_center(Vector2i(tl.i, tl.j))
		var h := TILE * 0.5 - minf(radius, 0.9)
		var q := Vector3(clampf(p.x, cc.x - h, cc.x + h), p.y, clampf(p.z, cc.z - h, cc.z + h))
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < bd:
			bd = d
			best = q
	return best


## 모든 바닥 칸 중심
func floor_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for tl in tiles:
		if tl.walk:
			out.append(Vector2i(tl.i, tl.j))
	return out


## 심연과 맞닿은 바닥 칸과 그 바깥 방향 (기어오르는 적의 등장 자리)
func edge_spots() -> Array:
	var out: Array = []
	for tl in tiles:
		if not tl.walk:
			continue
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nc: Vector2i = Vector2i(tl.i, tl.j) + d
			var nt := tile_at(nc)
			if nt.is_empty() or nt.kind == K.VOID:
				out.append({"cell": Vector2i(tl.i, tl.j), "out": Vector3(d.x, 0, d.y)})
	return out


## 지금 디딜 수 있는 분출구 칸 (읽기 전용 — 판이 움직일 때만 다시 센다)
func vent_cells() -> Array[Vector2i]:
	if _vent_dirty:
		_vent_dirty = false
		var out: Array[Vector2i] = []
		for tl in tiles:
			if tl.kind == K.VENT and tl.walk:
				out.append(Vector2i(tl.i, tl.j))
		if out != _vent_cache:
			_vent_cache = out
			vent_rev += 1
	return _vent_cache


# ── 전장 변화 ───────────────────────────────────────────

static func _kind_of(ch: String) -> int:
	match ch:
		"#": return K.FLOOR
		"P": return K.PILLAR
		"v": return K.VENT
	return K.VOID


## 판 배치를 name 으로 바꾼다. 가라앉을 판은 warn_time 동안 달아오른 뒤 떨어지고,
## 새로 생길 판은 심연에서 가운데부터 바깥으로 차례로 솟아오른다. instant 면 곧바로 놓는다.
func apply_layout(name: String, warn_time := 1.3, instant := false) -> float:
	layout = name
	_vent_dirty = true
	var rows: Array = LAYOUTS[name]
	var longest := 0.0
	for tl in tiles:
		var kind := _kind_of((rows[tl.j] as String)[tl.i])
		var old: int = tl.kind
		tl.kind = kind
		var target := SUNK_Y
		match kind:
			K.FLOOR, K.VENT: target = 0.0
			K.PILLAR: target = PILLAR_Y
		var mi := tl.mi as MeshInstance3D
		mi.set_instance_shader_parameter("vent", 1.0 if kind == K.VENT else 0.0)
		mi.set_instance_shader_parameter("pillar", 1.0 if kind == K.PILLAR else 0.0)
		# 같은 높이의 판끼리 그림자를 드리우면 계단 무늬(그림자 여드름)가 생긴다 → 기둥만 그림자를 드리운다
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if kind == K.PILLAR else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if instant:
			tl.y = target
			tl.target = target
			(tl.node as Node3D).position.y = target
			(tl.node as Node3D).visible = kind != K.VOID
			tl.walk = kind == K.FLOOR or kind == K.VENT
			tl.block = kind == K.PILLAR
			_deco(tl)
			continue
		if is_equal_approx(float(tl.target), target):
			continue
		var dist := Vector2(tl.i - HALF, tl.j - HALF).length()
		tl.target = target
		tl.moving = true
		if target < float(tl.y):
			# 가라앉는다 / 기둥이 내려앉는다: 먼저 달아오른다
			tl.delay = warn_time + dist * 0.04 + randf() * 0.15
			tl.warn = 0.001
		else:
			# 솟아오른다: 경고 없이, 가운데부터 차례로
			tl.delay = warn_time * 0.6 + dist * 0.07 + randf() * 0.12
			tl.warn = 0.0
			if old == K.VOID:
				(tl.node as Node3D).visible = true
		longest = maxf(longest, float(tl.delay) + 1.2)
	shift_t = longest
	if not instant:
		Sfx.play("hrise", 0.0, -2.0)
	return longest


func _deco(tl: Dictionary) -> void:
	if tl.deco != null and is_instance_valid(tl.deco):
		(tl.deco as Node3D).queue_free()
	tl.deco = null
	if tl.kind == K.PILLAR:
		tl.deco = props.brazier(tl.node)
	elif tl.kind == K.FLOOR:
		var out := _void_dir(tl)
		if out != Vector3.ZERO:
			var h := fposmod(sin(tl.i * 12.9898 + tl.j * 78.233 + layout.length() * 3.1) * 43758.5453, 1.0)
			if h < 0.07:
				tl.deco = props.floor_decor(tl.node, 0, out)
			elif h < 0.12:
				tl.deco = props.floor_decor(tl.node, 1, out)
			elif h < 0.17:
				tl.deco = props.floor_decor(tl.node, 2, out)


## 바깥(빈칸) 쪽 방향. 빈칸과 맞닿지 않았으면 0
func _void_dir(tl: Dictionary) -> Vector3:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nt := tile_at(Vector2i(tl.i, tl.j) + d)
		if nt.is_empty() or nt.kind == K.VOID:
			return Vector3(d.x, 0, d.y)
	return Vector3.ZERO


func _update_tiles(dt: float) -> void:
	shift_t = maxf(0.0, shift_t - dt)
	for tl in tiles:
		if not tl.moving:
			continue
		_vent_dirty = true
		var node := tl.node as Node3D
		var mi := tl.mi as MeshInstance3D
		var target: float = tl.target
		var y: float = tl.y
		if tl.delay > 0.0:
			tl.delay -= dt
			if tl.warn > 0.0:
				tl.warn = minf(1.0, tl.warn + dt * 1.2)
				mi.set_instance_shader_parameter("warn", tl.warn)
				# 달아오른 판이 덜덜 떤다
				node.position = Vector3(node.position.x, y + randf_range(-1.0, 1.0) * 0.025 * tl.warn, node.position.z)
				if randf() < dt * 3.0 * tl.warn:
					FX.sparks(node.global_position + Vector3(randf_range(-0.9, 0.9), 0.05, randf_range(-0.9, 0.9)), 3, [Color("ffb0a0"), ABYSS], 3.0, 0.3, -10.0, 0.05)
			if tl.delay <= 0.0:
				_on_move_start(tl)
			continue
		if target < y:
			# 가라앉음: 점점 빨라지며 떨어진다
			tl.vy = minf(float(tl.vy) + 26.0 * dt, 22.0)
			y = maxf(target, y - float(tl.vy) * dt)
			if target >= 0.0:
				# 기둥이 바닥 높이로 내려앉음: 부드럽게 멈춘다
				y = move_toward(float(tl.y), target, dt * 5.0)
			if tl.block and y < 0.6:
				tl.block = false
				tl.walk = true
		else:
			# 솟아오름: 처음엔 빠르게, 끝에서 살짝 튀어 오르며 멈춘다
			var k := clampf((target - y) / 15.0, 0.0, 1.0)
			y = move_toward(y, target, dt * (6.0 + k * 22.0))
			if (tl.kind == K.FLOOR or tl.kind == K.VENT) and y > -0.25 and not tl.walk:
				tl.walk = true
			if tl.kind == K.PILLAR and y > 0.9 and not tl.block:
				tl.block = true
				tl.walk = false
		tl.y = y
		node.position = Vector3(node.position.x, y, node.position.z)
		if is_equal_approx(y, target):
			_on_move_end(tl)


func _on_move_start(tl: Dictionary) -> void:
	var node := tl.node as Node3D
	var p := node.global_position
	if float(tl.target) < float(tl.y):
		tl.vy = 0.0
		if float(tl.target) <= SUNK_Y + 0.1:
			tl.walk = false
			tl.block = false
		# 떨어져 나가는 돌 부스러기와 먼지
		for i in 3:
			_rubble_piece(p + Vector3(randf_range(-0.9, 0.9), -0.2, randf_range(-0.9, 0.9)), Vector3(randf_range(-1, 1), randf_range(0, 2), randf_range(-1, 1)))
		dust(p + Vector3(0, 0.2, 0), 1.6, Color(0.24, 0.2, 0.22, 0.35))
		if randf() < 0.35:
			Sfx.play("land", 0.2, -10.0)
	else:
		tl.vy = 0.0
		if tl.deco != null and is_instance_valid(tl.deco):
			(tl.deco as Node3D).queue_free()
			tl.deco = null


func _on_move_end(tl: Dictionary) -> void:
	tl.moving = false
	tl.warn = 0.0
	(tl.mi as MeshInstance3D).set_instance_shader_parameter("warn", 0.0)
	var node := tl.node as Node3D
	tl.walk = tl.kind == K.FLOOR or tl.kind == K.VENT
	tl.block = tl.kind == K.PILLAR
	if tl.kind == K.VOID:
		node.visible = false
	else:
		# 솟아 맞물리는 순간: 이음매에서 먼지와 붉은 불티
		var p := node.global_position
		dust(p + Vector3(0, 0.15, 0), 1.3, Color(0.2, 0.17, 0.19, 0.28))
		FX.sparks(p + Vector3(0, 0.1, 0), 5, [Color("ffc0b0"), ABYSS], 4.0, 0.35, -12.0, 0.05)
		if randf() < 0.25:
			Sfx.play("land", 0.2, -12.0)
		_deco(tl)


# ── 부스러기 · 먼지 ─────────────────────────────────────

func _rubble_piece(p: Vector3, v: Vector3) -> void:
	if _rubble.size() > 120:
		return
	var b := BoxMesh.new()
	var s := randf_range(0.12, 0.32)
	b.size = Vector3(s, s * randf_range(0.5, 1.0), s * randf_range(0.6, 1.2))
	var mi := MeshInstance3D.new()
	mi.mesh = b
	mi.material_override = Pal.lit(Color(0.1, 0.11, 0.12))
	add_child(mi)
	mi.global_position = p
	_rubble.append([mi, v, Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6)), 3.0])


## 가장자리가 부드러운 먼지 구름. add 면 가산 혼합(빛나는 안개)
func dust(p: Vector3, size: float, c: Color, add := false, vel := Vector3(0, 0.6, 0), life := 1.4) -> void:
	if _puffs.size() > 400:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = _dust_mesh
	mi.material_override = _dust_mats[1 if add else 0]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_instance_shader_parameter("tint", c)
	mi.set_instance_shader_parameter("fade", 1.0)
	add_child(mi)
	mi.global_position = p
	mi.scale = Vector3.ONE * size * 0.4
	_puffs.append([mi, vel + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)), life, life, size * 0.4, size, 0.0])


func _update_fx(dt: float) -> void:
	var i := _rubble.size() - 1
	while i >= 0:
		var r: Array = _rubble[i]
		var mi := r[0] as MeshInstance3D
		r[3] = float(r[3]) - dt
		var v: Vector3 = r[1]
		v.y -= 18.0 * dt
		r[1] = v
		mi.global_position += v * dt
		var sp: Vector3 = r[2]
		mi.rotate(sp.normalized(), sp.length() * dt)
		if float(r[3]) <= 0.0 or mi.global_position.y < -20.0:
			mi.queue_free()
			_rubble.remove_at(i)
		i -= 1
	i = _puffs.size() - 1
	while i >= 0:
		var pf: Array = _puffs[i]
		var mi := pf[0] as MeshInstance3D
		pf[2] = float(pf[2]) - dt
		var k := 1.0 - float(pf[2]) / float(pf[3])
		mi.global_position += (pf[1] as Vector3) * dt
		mi.scale = Vector3.ONE * lerpf(float(pf[4]), float(pf[5]), 1.0 - pow(1.0 - k, 2.0))
		mi.set_instance_shader_parameter("fade", 1.0 - k)
		if float(pf[2]) <= 0.0:
			mi.queue_free()
			_puffs.remove_at(i)
		i -= 1


func add_brazier_light(l: OmniLight3D, base: float) -> void:
	_brazier_lights.append([l, base, randf() * 10.0])


# ── 매 프레임 ───────────────────────────────────────────

func _process(dt: float) -> void:
	t += dt
	tile_mat.set_shader_parameter("heat", heat)
	void_mat.set_shader_parameter("heat", heat)
	_update_fx(dt)
	var k := 0
	while k < _brazier_lights.size():
		var b: Array = _brazier_lights[k]
		if not is_instance_valid(b[0]):
			_brazier_lights.remove_at(k)
			continue
		var l := b[0] as OmniLight3D
		var ph: float = b[2]
		l.light_energy = float(b[1]) * (0.82 + 0.12 * sin(t * 9.0 + ph) + 0.06 * sin(t * 23.0 + ph * 2.0))
		k += 1


func _physics_process(dt: float) -> void:
	_update_tiles(dt)
