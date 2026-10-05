class_name InfestMesh
extends RefCounted
## 감염 오염물의 메시·재질을 코드로 만든다 (배경 키트 I05 감염 포낭 · I04 감염 연결막, docs/infestation.md).
##
##  포낭 (I05)  폭 0.5m · 높이 약 0.3m. 낮은 연보라 돔 위에 포도주색 알주머니 여러 개가 솟은 덩어리.
##              방향마다 돔·알주머니의 광선 교차 거리를 '부드러운 최댓값'으로 섞어 한 겹 표면으로 만든다
##              (알주머니 사이 이음 = 연보라 그물). 정점 색 r = 알주머니 정도, g = 알주머니마다 다른 위상.
##  연결막 (I04) 1×1m · 두께 ≤ 0.08m. 네 갈래로 뻗은 얇은 막 + 구멍 2~3개 + 가장자리·구멍 테의 알주머니 혹.
##              모양은 마스크 텍스처(r = 안쪽 경계, g = 혹, b = 안쪽 깊이)로 잘라 내고(discard), 높이는 같은 장으로 만든다.
##
## 꿀렁임은 셰이더(TIME)가 한다 — 알주머니마다 위상이 다른 맥동 + 그물 잔물결 + 덩어리 숨쉬기. CPU 는 맞았을 때만 값을 바꾼다.
## 인스턴스 값: phase(위상) · hit(피격 섬광) · swell(터지기 직전 부풂) · dead(터진 껍질/시든 막) · agit(흥분 = 빠르고 크게).
## 메시·재질은 변형 수가 정해진 정적 캐시 (씬을 다시 불러도 늘지 않는다).

const CYST_VARIANTS := 6
const MEMBRANE_VARIANTS := 4
const SPLAT_VARIANTS := 4
const SEG := 34
const RINGS := 13
const MEM_N := 36            ## 연결막 격자 칸 수 (한 변)
const MEM_TEX := 96

## 배경 키트 공용 팔레트 (I04/I05 시트 아래 색 칩)
const WEB := Color("b9a3c1")       ## 연보라 그물·막
const WEB_DARK := Color("8b6a93")
const BULB := Color("8a2e66")      ## 포도주 알주머니
const BULB_DARK := Color("4a2a5e")
const BULB_HI := Color("c85690")
const HUSK := Color("3e1f36")
const GOO := Color("7e2462")       ## 체액
const GOO_HI := Color("ff8fc8")

static var _cysts: Array[ArrayMesh] = []
static var _membranes: Array[ArrayMesh] = []
static var _mem_tex: Array[ImageTexture] = []
static var _splats: Array[ArrayMesh] = []
static var _cyst_mat: ShaderMaterial
static var _mem_mats: Array[ShaderMaterial] = []
static var _goo_mat: ShaderMaterial
static var _goo_dark: ShaderMaterial
static var _drop: SphereMesh
static var _strand: CylinderMesh


static func cyst(i: int) -> ArrayMesh:
	_ensure()
	return _cysts[posmod(i, CYST_VARIANTS)]


static func membrane(i: int) -> ArrayMesh:
	_ensure()
	return _membranes[posmod(i, MEMBRANE_VARIANTS)]


static func membrane_mat(i: int) -> ShaderMaterial:
	_ensure()
	return _mem_mats[posmod(i, MEMBRANE_VARIANTS)]


static func cyst_mat() -> ShaderMaterial:
	_ensure()
	return _cyst_mat


static func splat(i: int) -> ArrayMesh:
	_ensure()
	return _splats[posmod(i, SPLAT_VARIANTS)]


## 체액 재질 (밝은 = 튀는 방울, 어두운 = 바닥에 고인 얼룩)
static func goo_mat(dark := false) -> ShaderMaterial:
	_ensure()
	return _goo_dark if dark else _goo_mat


static func drop_mesh() -> SphereMesh:
	_ensure()
	return _drop


static func strand_mesh() -> CylinderMesh:
	_ensure()
	return _strand


static func _ensure() -> void:
	if _cyst_mat:
		return
	var sh := Shader.new()
	sh.code = CYST_SHADER.replace("//POOL", BrawlLook.POOL).replace("//LIGHT", LIGHT)
	_cyst_mat = ShaderMaterial.new()
	_cyst_mat.shader = sh
	BrawlLook.track_pool(_cyst_mat)
	for i in CYST_VARIANTS:
		_cysts.append(_build_cyst(1701 + i * 37))
	var msh := Shader.new()
	msh.code = MEMBRANE_SHADER.replace("//POOL", BrawlLook.POOL).replace("//LIGHT", LIGHT)
	for i in MEMBRANE_VARIANTS:
		var built := _build_membrane(911 + i * 53)
		_membranes.append(built[0])
		_mem_tex.append(built[1])
		var m := ShaderMaterial.new()
		m.shader = msh
		m.set_shader_parameter("mask_tex", built[1])
		BrawlLook.track_pool(m)
		_mem_mats.append(m)
	var gsh := Shader.new()
	gsh.code = GOO_SHADER.replace("//LIGHT", LIGHT)
	_goo_mat = ShaderMaterial.new()
	_goo_mat.shader = gsh
	_goo_mat.set_shader_parameter("col", Color("7e2462"))
	_goo_dark = ShaderMaterial.new()
	_goo_dark.shader = gsh
	_goo_dark.set_shader_parameter("col", Color("5a1a48"))
	_goo_dark.set_shader_parameter("gloss", 0.8)
	for i in SPLAT_VARIANTS:
		_splats.append(_build_splat(77 + i * 19))
	_drop = SphereMesh.new()
	_drop.radius = 0.5
	_drop.height = 1.0
	_drop.radial_segments = 10
	_drop.rings = 6
	_strand = CylinderMesh.new()
	_strand.top_radius = 0.5
	_strand.bottom_radius = 0.5
	_strand.height = 1.0
	_strand.radial_segments = 6
	_strand.rings = 1
	_strand.cap_top = false
	_strand.cap_bottom = false


# ── 포낭 (I05) ─────────────────────────────────────────

## 광선(원점 o, 방향 d)이 타원체(중심 c, 기저 b, 반지름 r)를 빠져나가는 거리. 안 닿으면 -1
static func _exit_t(o: Vector3, d: Vector3, c: Vector3, b: Basis, r: Vector3) -> float:
	var lo := b.transposed() * (o - c)
	var ld := b.transposed() * d
	lo = Vector3(lo.x / r.x, lo.y / r.y, lo.z / r.z)
	ld = Vector3(ld.x / r.x, ld.y / r.y, ld.z / r.z)
	var a := ld.dot(ld)
	var bb := 2.0 * lo.dot(ld)
	var cc := lo.dot(lo) - 1.0
	var disc := bb * bb - 4.0 * a * cc
	if disc < 0.0:
		return -1.0
	var t := (-bb + sqrt(disc)) / (2.0 * a)
	return t if t > 0.0 else -1.0


static func _build_cyst(seed_v: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var o := Vector3(0, 0.03, 0)
	var dome_r := Vector3(0.235, 0.165, 0.235)
	# 알주머니: [중심, 기저, 반지름, 위상]
	var bulbs: Array = []
	var specs: Array = []
	var top_n := rng.randi_range(1, 2)
	for i in top_n:
		specs.append([rng.randf_range(0.95, 1.35), rng.randf() * TAU, rng.randf_range(0.105, 0.13)])
	var ring_n := rng.randi_range(4, 6)
	var a0 := rng.randf() * TAU
	for i in ring_n:
		specs.append([rng.randf_range(0.22, 0.62), a0 + TAU * i / ring_n + rng.randf_range(-0.3, 0.3), rng.randf_range(0.075, 0.11)])
	for i in rng.randi_range(2, 4):
		specs.append([rng.randf_range(0.1, 0.9), rng.randf() * TAU, rng.randf_range(0.04, 0.065)])
	for s: Array in specs:
		var el: float = s[0]
		var az: float = s[1]
		var rad: float = s[2]
		var dir := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az)).normalized()
		var t := _exit_t(o, dir, Vector3.ZERO, Basis.IDENTITY, dome_r)
		var c := o + dir * t * 0.84
		var n := Vector3(c.x / (dome_r.x * dome_r.x), c.y / (dome_r.y * dome_r.y), c.z / (dome_r.z * dome_r.z)).normalized()
		var tang := n.cross(Vector3.UP if absf(n.y) < 0.95 else Vector3.RIGHT).normalized()
		var bas := Basis(tang, n, tang.cross(n)).orthonormalized()
		# 접선 방향으로 길쭉, 법선 방향으로 납작한 알
		var r := Vector3(rad * rng.randf_range(1.0, 1.35), rad * rng.randf_range(0.62, 0.8), rad * rng.randf_range(0.85, 1.1))
		bulbs.append([c, bas, r, rng.randf()])
	var k := 75.0           # 반지름 부드러운 최댓값 (돔·알 이음새 둥글게)
	var kc := 140.0         # 색 가중치 (더 날카롭게)
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var el_lo := -0.14
	for j in RINGS + 1:
		var el := lerpf(el_lo, PI * 0.5 - 0.06, float(j) / RINGS)
		for i in SEG:
			var az := TAU * i / SEG
			var d := Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
			var rs := PackedFloat32Array()
			rs.append(_exit_t(o, d, Vector3.ZERO, Basis.IDENTITY, dome_r))
			for b: Array in bulbs:
				rs.append(_exit_t(o, d, b[0], b[1], b[2]))
			var mx := 0.0
			for r in rs:
				mx = maxf(mx, r)
			var sum := 0.0
			for r in rs:
				if r > 0.0:
					sum += exp(k * (r - mx))
			var rr := mx + log(sum) / k
			# 색: 가장 센 알주머니가 돔과 두 번째 알보다 얼마나 앞서는가 (사이 경계 = 연보라 그물 줄)
			var w := PackedFloat32Array()
			var ws := 0.0
			for r in rs:
				var e := exp(kc * (r - mx)) if r > 0.0 else 0.0
				w.append(e)
				ws += e
			var w1 := 0.0
			var w2 := 0.0
			var top := -1
			for bi in range(1, w.size()):
				var v := w[bi] / ws
				if v > w1:
					w2 = w1
					w1 = v
					top = bi
				elif v > w2:
					w2 = v
			var bulbness := clampf((w1 - maxf(w2, w[0] / ws)) * 1.7, 0.0, 1.0)
			rr += 0.008 * (1.0 - bulbness) * (1.0 if w[0] / ws < 0.5 else 0.0)   # 알 사이 그물 줄은 살짝 돋는다
			var p := o + d * rr
			p.y = maxf(p.y, 0.0)
			verts.append(p)
			var ph: float = bulbs[top - 1][3] if top > 0 else 0.0
			cols.append(Color(bulbness, ph, 0.0, 1.0))
	var pole_i := verts.size()
	var pd := Vector3.UP
	var prs := _exit_t(o, pd, Vector3.ZERO, Basis.IDENTITY, dome_r)
	for b: Array in bulbs:
		prs = maxf(prs, _exit_t(o, pd, b[0], b[1], b[2]))
	verts.append(o + pd * prs)
	cols.append(Color(0.6, 0.5, 0, 1))
	var base_i := verts.size()
	verts.append(Vector3.ZERO)
	cols.append(Color(0, 0, 0, 1))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vi in verts.size():
		st.set_color(cols[vi])
		st.add_vertex(verts[vi])
	for j in RINGS:
		for i in SEG:
			var a := j * SEG + i
			var b := j * SEG + (i + 1) % SEG
			var c := (j + 1) * SEG + i
			var d := (j + 1) * SEG + (i + 1) % SEG
			st.add_index(a)
			st.add_index(c)
			st.add_index(b)
			st.add_index(b)
			st.add_index(c)
			st.add_index(d)
	for i in SEG:
		st.add_index(RINGS * SEG + i)
		st.add_index(pole_i)
		st.add_index(RINGS * SEG + (i + 1) % SEG)
		st.add_index(i)
		st.add_index((i + 1) % SEG)
		st.add_index(base_i)
	st.generate_normals()
	return st.commit()


# ── 연결막 (I04) ───────────────────────────────────────

static func _smin(a: float, b: float, kk: float) -> float:
	var h := clampf(0.5 + 0.5 * (b - a) / kk, 0.0, 1.0)
	return lerpf(b, a, h) - kk * h * (1.0 - h)


static func _seg_d(p: Vector2, a: Vector2, b: Vector2) -> Array:
	var ab := b - a
	var h := clampf((p - a).dot(ab) / ab.dot(ab), 0.0, 1.0)
	return [(p - a - ab * h).length(), h]


static func _build_membrane(seed_v: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var noise := FastNoiseLite.new()
	noise.seed = seed_v
	noise.frequency = 6.0
	noise.fractal_octaves = 2
	var arms: Array = []
	var a0 := rng.randf_range(-0.3, 0.3)
	for i in 4:
		var a := a0 + PI * 0.25 + PI * 0.5 * i + rng.randf_range(-0.25, 0.25)
		arms.append([Vector2(cos(a), sin(a)) * rng.randf_range(0.42, 0.5), rng.randf_range(0.085, 0.12)])
	var lobes: Array = []
	for i in rng.randi_range(2, 4):
		var a := rng.randf() * TAU
		lobes.append([Vector2(cos(a), sin(a)) * rng.randf_range(0.18, 0.34), rng.randf_range(0.08, 0.14)])
	var holes: Array = []
	for i in rng.randi_range(2, 3):
		for tries in 20:
			var a := rng.randf() * TAU
			var c := Vector2(cos(a), sin(a)) * rng.randf_range(0.1, 0.3)
			var r := rng.randf_range(0.055, 0.12)
			var ok := true
			for h: Array in holes:
				if c.distance_to(h[0]) < r + float(h[1]) + 0.06:
					ok = false
			if ok:
				holes.append([c, r])
				break
	var core_r := rng.randf_range(0.22, 0.28)
	var sd := func(p: Vector2) -> float:
		var d := p.length() - core_r
		for arm: Array in arms:
			var s := _seg_d(p, Vector2.ZERO, arm[0])
			var rr := lerpf(float(arm[1]) * 1.25, float(arm[1]) * 0.55, float(s[1]))
			d = _smin(d, float(s[0]) - rr, 0.09)
			# 갈래 끝은 둥근 혹
			d = _smin(d, p.distance_to(arm[0]) - float(arm[1]) * 0.75, 0.04)
		for l: Array in lobes:
			d = _smin(d, p.distance_to(l[0]) - float(l[1]), 0.07)
		for h: Array in holes:
			d = -_smin(-d, p.distance_to(h[0]) - float(h[1]), 0.03)
		d += noise.get_noise_2d(p.x, p.y) * 0.022
		return d
	# 혹: 가장자리·구멍 테 근처 점들
	var lumps: Array = []
	for tries in 400:
		if lumps.size() >= 12:
			break
		var p := Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
		var dv: float = sd.call(p)
		if dv > -0.035 or dv < -0.075:
			continue
		var r := rng.randf_range(0.035, 0.085)
		var ok := true
		for l: Array in lumps:
			if p.distance_to(l[0]) < r + float(l[1]):
				ok = false
		if ok:
			lumps.append([p, r])
	var lump_at := func(p: Vector2) -> float:
		var v := 0.0
		for l: Array in lumps:
			var q := p.distance_to(l[0]) / float(l[1])
			if q < 1.0:
				v = maxf(v, sqrt(1.0 - q * q))
		return v
	var height := func(p: Vector2) -> float:
		var inside: float = -sd.call(p)
		if inside <= 0.0:
			return 0.0
		var lv: float = lump_at.call(p)
		return 0.004 + 0.02 * smoothstep(0.0, 0.14, inside) + lv * 0.05
	# 마스크 텍스처
	var img := Image.create(MEM_TEX, MEM_TEX, false, Image.FORMAT_RGBA8)
	for y in MEM_TEX:
		for x in MEM_TEX:
			var p := Vector2((x + 0.5) / MEM_TEX - 0.5, (y + 0.5) / MEM_TEX - 0.5)
			var inside: float = -sd.call(p)
			img.set_pixel(x, y, Color(clampf(0.5 + inside * 7.0, 0.0, 1.0), lump_at.call(p), clampf(inside / 0.16, 0.0, 1.0), 1.0))
	var tex := ImageTexture.create_from_image(img)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in MEM_N + 1:
		for i in MEM_N + 1:
			var u := float(i) / MEM_N
			var v := float(j) / MEM_N
			var p := Vector2(u - 0.5, v - 0.5)
			st.set_uv(Vector2(u, v))
			st.add_vertex(Vector3(p.x, height.call(p), p.y))
	for j in MEM_N:
		for i in MEM_N:
			var a := j * (MEM_N + 1) + i
			var b := a + 1
			var c := a + MEM_N + 1
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	st.generate_normals()
	return [st.commit(), tex]


# ── 체액 얼룩 ──────────────────────────────────────────

## 지름 1m 기준 불규칙한 얼룩 (가운데 볼록한 렌즈 + 둘레 튄 점들). 바닥에 납작하게.
static func _build_splat(seed_v: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blobs: Array = [[Vector2.ZERO, 0.32, 0.03]]
	var n := rng.randi_range(5, 8)
	for i in n:
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.3, 0.5)
		blobs.append([Vector2(cos(a), sin(a)) * d, rng.randf_range(0.035, 0.08), 0.012])
		# 가운데에서 그 점까지 이어진 꼬리
		blobs.append([Vector2(cos(a), sin(a)) * d * 0.62, rng.randf_range(0.06, 0.1), 0.018])
	var lobes := PackedFloat32Array()
	for i in 7:
		lobes.append(rng.randf_range(-1, 1))
	for bi in blobs.size():
		var b: Array = blobs[bi]
		var c: Vector2 = b[0]
		var r: float = b[1]
		var h: float = b[2]
		var seg := 22 if bi == 0 else 10
		var ring: Array[Vector3] = []
		for i in seg:
			var a := TAU * i / seg
			var rr := r
			if bi == 0:
				var w := 0.0
				for li in lobes.size():
					w += sin(a * (li + 2) + lobes[li] * 3.0) * lobes[li] * 0.12 / (li * 0.5 + 1.0)
				rr *= 1.0 + w
			ring.append(Vector3(c.x + cos(a) * rr, 0.0, c.y + sin(a) * rr))
		var mid := Vector3(c.x, h, c.y)
		for i in seg:
			var p0 := ring[i]
			var p1 := ring[(i + 1) % seg]
			var m0 := p0.lerp(mid, 0.55)
			m0.y = h * 0.8
			var m1 := p1.lerp(mid, 0.55)
			m1.y = h * 0.8
			for tri in [[p0, m0, p1], [p1, m0, m1], [m0, mid, m1]]:
				for q: Vector3 in tri:
					st.add_vertex(q)
	st.index()
	st.generate_normals()
	return st.commit()


# ── 셰이더 ─────────────────────────────────────────────

## 공통 조명: BrawlLook 과 같은 2단 셀 + 그림자 색조 + 해에서 오는 림 + 점광원 램버트. 하이라이트는 픽셀마다 젖은 정도(v_gloss)
const LIGHT := """
uniform vec3 shade_tint : source_color = vec3(0.56, 0.52, 0.98);
uniform float shade_floor = 0.42;
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float s = smoothstep(-0.05, 0.2, ndl + 0.08);
	vec3 lc = LIGHT_COLOR / PI;
	vec3 hv = normalize(LIGHT + VIEW);
	float nh = dot(NORMAL, hv);
	// 젖은 반짝임: 작고 또렷한 점 하나 + 아주 옅은 넓은 윤기
	float hl = (smoothstep(0.988, 0.996, nh) * 0.32 + smoothstep(0.82, 0.96, nh) * 0.04) * v_gloss;
	if (LIGHT_IS_DIRECTIONAL) {
		float sh = mix(1.0, smoothstep(0.15, 0.85, ATTENUATION), 0.75);
		float lit = s * sh;
		DIFFUSE_LIGHT += lc * mix(shade_tint * shade_floor, vec3(1.0), lit) * v_pool;
		SPECULAR_LIGHT += lc * vec3(1.0, 0.82, 0.93) * hl * lit * v_pool;
		SPECULAR_LIGHT += lc * v_rim;
	} else {
		float c = clamp(ndl, 0.0, 1.0);
		DIFFUSE_LIGHT += lc * ATTENUATION * c;
		SPECULAR_LIGHT += lc * ATTENUATION * hl * c;
	}
}
"""

const NOISE := """
float ih(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vn(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(ih(i), ih(i + vec3(1,0,0)), f.x), mix(ih(i + vec3(0,1,0)), ih(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(ih(i + vec3(0,0,1)), ih(i + vec3(1,0,1)), f.x), mix(ih(i + vec3(0,1,1)), ih(i + vec3(1,1,1)), f.x), f.y), f.z);
}
"""

const CYST_SHADER := """
shader_type spatial;
render_mode cull_back;
//POOL
uniform vec3 web_col : source_color = vec3(0.725, 0.639, 0.757);
uniform vec3 web_dark : source_color = vec3(0.545, 0.416, 0.576);
uniform vec3 bulb_col : source_color = vec3(0.42, 0.155, 0.35);
uniform vec3 bulb_dark : source_color = vec3(0.23, 0.13, 0.3);
uniform vec3 bulb_hi : source_color = vec3(0.66, 0.3, 0.52);
uniform vec3 husk_col : source_color = vec3(0.243, 0.122, 0.212);
uniform float value_k = 0.74;
instance uniform float phase = 0.0;
instance uniform float hit = 0.0;
instance uniform float swell = 0.0;
instance uniform float dead = 0.0;
instance uniform float agit = 0.0;
varying float v_b;
varying vec3 v_lp;
varying vec3 wpos;
varying vec3 wn;
varying vec3 v_rim;
varying float v_gloss;
""" + NOISE + """
void vertex() {
	float b = COLOR.r;
	float ph = COLOR.g * 6.2831853;
	float alive = 1.0 - dead;
	float t = TIME * (1.5 + agit * 5.5) + phase;
	// 알주머니마다 위상이 다른 맥동 (천천히 부풀고 빠르게 꺼진다)
	float pulse = 0.5 + 0.5 * sin(t + ph + 0.6 * sin(t * 0.5 + ph));
	pulse = pulse * pulse * (3.0 - 2.0 * pulse);
	float ripple = sin(TIME * (1.2 + agit * 5.0) + phase * 1.7 + VERTEX.x * 19.0 + VERTEX.z * 15.0 + VERTEX.y * 11.0);
	float d = (b * (0.006 + 0.024 * pulse) * (1.0 + agit * 1.4) + (1.0 - b) * 0.004 * ripple) * alive;
	d += swell * (0.014 + 0.034 * b);
	v_lp = VERTEX;
	vec3 v = VERTEX + NORMAL * d;
	// 덩어리 숨쉬기: 위로 늘었다 옆으로 퍼진다
	float br = sin(TIME * (0.85 + agit * 2.0) + phase) * (0.045 + agit * 0.05) * alive;
	v.y *= 1.0 + br + swell * 0.18;
	v.xz *= 1.0 - br * 0.45;
	// 터진 껍질: 쭈그러들어 주름진 가죽
	float wr = sin(VERTEX.x * 41.0 + VERTEX.z * 33.0) * sin(VERTEX.z * 37.0 - VERTEX.x * 23.0);
	v.y = mix(v.y, v.y * 0.28 + wr * 0.012 * step(0.012, VERTEX.y), dead);
	v.xz *= 1.0 + dead * 0.16;
	VERTEX = v;
	v_b = b;
	wpos = (MODEL_MATRIX * vec4(v, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float b = smoothstep(0.42, 0.82, v_b);
	float n1 = vn(v_lp * 34.0);
	float n2 = vn(v_lp * 85.0 + 3.1);
	vec3 web = mix(web_dark, web_col, smoothstep(0.2, 0.75, n1));
	web = mix(web, web_col * 1.14, smoothstep(0.62, 0.86, n2) * 0.7);       // 밝은 핏줄
	web = mix(web, bulb_dark, smoothstep(0.78, 0.9, vn(v_lp * 60.0 + 9.0)) * 0.45);   // 작은 구멍
	vec3 bulb = mix(bulb_dark, bulb_col, smoothstep(0.3, 1.0, v_b));
	bulb = mix(bulb, bulb_hi, smoothstep(0.92, 1.0, v_b) * smoothstep(0.3, 0.9, normalize(wn).y) * 0.35);
	bulb = mix(bulb, bulb_dark, smoothstep(0.64, 0.82, vn(v_lp * 52.0 + 7.0)) * 0.3);
	vec3 col = mix(web, bulb, b);
	col *= (1.0 + 0.1 * normalize(wn).y) * value_k;
	col = mix(col, mix(husk_col, web_dark * 0.55, 1.0 - b), dead * 0.85);
	col = mix(col, vec3(0.95, 0.62, 0.8), clamp(hit, 0.0, 1.0) * 0.45);
	ALBEDO = clamp(col, 0.0, 1.0);
	v_gloss = mix(0.3, 1.0, b) * (1.0 - dead * 0.2);
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	v_rim = (ALBEDO * 0.6 + vec3(0.95, 0.78, 0.95) * 0.4) * fr * 0.32 * smoothstep(-0.3, 0.6, normalize(wn).y);
	// 알주머니 속이 은은하게 비친다 (어두운 구석에서도 형태가 읽히게)
	EMISSION = bulb_hi * b * (0.05 + 0.05 * agit + swell * 0.4) * (1.0 - dead) + vec3(0.9, 0.4, 0.65) * hit * 0.12;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	v_pool = pool_k(wpos);
	if (pool_on > 0.0) {
		AO = mix(v_pool, 1.0, 0.35);
		AO_LIGHT_AFFECT = 0.0;
	}
}
//LIGHT
"""

const MEMBRANE_SHADER := """
shader_type spatial;
render_mode cull_back;
//POOL
uniform sampler2D mask_tex : filter_linear, repeat_disable;
uniform vec3 web_col : source_color = vec3(0.725, 0.639, 0.757);
uniform vec3 web_dark : source_color = vec3(0.545, 0.416, 0.576);
uniform vec3 bulb_col : source_color = vec3(0.49, 0.17, 0.39);
uniform vec3 bulb_dark : source_color = vec3(0.26, 0.14, 0.33);
uniform vec3 husk_col : source_color = vec3(0.243, 0.122, 0.212);
instance uniform float phase = 0.0;
instance uniform float hit = 0.0;
instance uniform float dead = 0.0;
instance uniform float agit = 0.0;
varying vec3 v_lp;
varying vec3 wpos;
varying vec3 wn;
varying vec3 v_rim;
varying float v_gloss;
""" + NOISE + """
void vertex() {
	vec4 m = textureLod(mask_tex, UV, 0.0);
	float alive = 1.0 - dead;
	float t = TIME * (1.3 + agit * 5.0) + phase;
	float pulse = 0.5 + 0.5 * sin(t + UV.x * 9.0 + UV.y * 5.0);
	// 혹이 맥동하고 막 전체에 느린 물결이 지나간다
	float lift = m.g * (0.004 + 0.018 * pulse) + m.b * 0.006 * sin(t * 0.7 + UV.x * 7.0 - UV.y * 6.0);
	v_lp = VERTEX;
	VERTEX.y += lift * alive * (1.0 + agit);
	VERTEX.y *= 1.0 - dead * 0.6;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	vec4 m = texture(mask_tex, UV);
	// 시드는 막은 가장자리부터 오그라든다
	if (m.r < 0.5 + dead * 0.3) discard;
	float n1 = vn(v_lp * 30.0 + phase);
	float n2 = vn(v_lp * 80.0 + 3.1);
	vec3 col = mix(web_dark, web_col, smoothstep(0.15, 0.8, n1) * smoothstep(0.0, 0.5, m.b));
	col = mix(col, web_col * 1.15, smoothstep(0.6, 0.85, n2) * 0.6 * m.b);   // 핏줄
	float edge = 1.0 - smoothstep(0.0, 0.18, m.b);
	col = mix(col, mix(bulb_dark, bulb_col, 0.5), edge * 0.75);              // 가장자리 짙은 포도주 테
	float lump = smoothstep(0.05, 0.6, m.g);
	col = mix(col, mix(bulb_dark, bulb_col, smoothstep(0.2, 1.0, m.g)), lump);
	col *= 0.8;
	col = mix(col, husk_col, dead * 0.75);
	col = mix(col, vec3(0.95, 0.62, 0.8), clamp(hit, 0.0, 1.0) * 0.4);
	ALBEDO = clamp(col, 0.0, 1.0);
	v_gloss = 0.2 + lump * 0.6;
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	v_rim = (ALBEDO * 0.5 + vec3(0.95, 0.78, 0.95) * 0.5) * fr * 0.3;
	EMISSION = vec3(0.784, 0.337, 0.565) * lump * 0.05 * (1.0 - dead);
	ROUGHNESS = 0.5;
	SPECULAR = 0.2;
	v_pool = pool_k(wpos);
	if (pool_on > 0.0) {
		AO = mix(v_pool, 1.0, 0.25);
		AO_LIGHT_AFFECT = 0.0;
	}
}
//LIGHT
"""

## 체액: 젖은 포도주색. 방울·줄·얼룩 공용 (외곽선 없음: ROUGHNESS 0)
const GOO_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec3 col : source_color = vec3(0.61, 0.18, 0.45);
uniform vec3 hi : source_color = vec3(1.0, 0.56, 0.78);
uniform float gloss = 1.0;
varying vec3 v_rim;
varying float v_gloss;
varying float v_pool;
void fragment() {
	float fr = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	ALBEDO = mix(col, col * 0.62, fr * 0.6) * 0.8;
	v_gloss = gloss;
	v_rim = hi * fr * 0.35;
	v_pool = 1.0;
	EMISSION = col * 0.12;
	ROUGHNESS = 0.0;
	SPECULAR = 0.3;
}
//LIGHT
"""
