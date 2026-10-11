class_name DialogueIdleMotion
extends RefCounted
## 합체 컷인의 머리/옷가지 UV 변형 셰이더를 대화용의 작은 연속 움직임으로 구동한다.
## 원화는 수정하지 않는다. 마스크는 등록된 원화당 한 번 생성하는 유한 캐시다.

const SHADER := preload("res://scripts/drone/diagonal_cutin.gdshader")
const MASK_SIZE := 128
const FACE_LOCK := {
	"owner": Vector4(0.53, 0.40, 0.18, 0.15), "worker": Vector4(0.50, 0.38, 0.18, 0.16),
	"partner": Vector4(0.47, 0.34, 0.17, 0.15),
}
# tempo, 몸/머리/옷 진폭, 머리 영역 타원들 [cx,cy,rx,ry]. 얼굴/소품은 색/영역으로 제외.
const PROFILES := {
	"owner": {"tempo": 0.88, "body": 0.85, "hair": 0.88, "cloth": 0.8, "root": Vector2(0.53, 0.17), "len": 0.53,
		"zones": [Vector4(0.52, 0.28, 0.40, 0.34), Vector4(0.37, 0.51, 0.16, 0.18), Vector4(0.71, 0.50, 0.15, 0.18)]},
	"worker": {"tempo": 1.08, "body": 1.0, "hair": 1.15, "cloth": 0.7, "root": Vector2(0.50, 0.17), "len": 0.50,
		"zones": [Vector4(0.50, 0.28, 0.48, 0.31), Vector4(0.21, 0.43, 0.18, 0.23), Vector4(0.82, 0.38, 0.18, 0.20)]},
	"partner": {"tempo": 1.02, "body": 1.1, "hair": 1.3, "cloth": 1.1, "root": Vector2(0.44, 0.16), "len": 0.65,
		"zones": [Vector4(0.45, 0.27, 0.43, 0.29), Vector4(0.82, 0.49, 0.18, 0.37)]},
}
static var _masks := {}
var profile: Dictionary
var phase := 0.0
var clock := 0.0
var amount := 1.0
var body_offset := Vector2.ZERO
var body_scale := Vector2.ONE
var body_roll := 0.0
var hair := Vector2.ZERO
var hair_v := Vector2.ZERO
var cloth := Vector2.ZERO
var cloth_v := Vector2.ZERO
var ribbon := Vector2.ZERO
var ribbon_v := Vector2.ZERO
var materials: Array[ShaderMaterial] = []


static func supports(id: String) -> bool:
	return id != "me" and PROFILES.has(id)


func _init(id: String) -> void:
	profile = PROFILES[id]
	phase = float(absi(id.hash()) % 997) / 997.0 * TAU


func make_material(id: String, texture: Texture2D, shadow := false) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("clip_enabled", 0.0)
	mat.set_shader_parameter("bust", 0.0)
	mat.set_shader_parameter("motion", 1.0)
	mat.set_shader_parameter("hair_mask", mask_for(id, texture))
	mat.set_shader_parameter("hair_root", profile.root)
	mat.set_shader_parameter("hair_len", profile.len)
	mat.set_shader_parameter("silhouette", 1.0 if shadow else 0.0)
	mat.set_shader_parameter("sil_color", Color(0, 0, 0, 0.35))
	materials.append(mat)
	_apply(mat)
	return mat


func change_texture(id: String, mat: ShaderMaterial, texture: Texture2D) -> void:
	mat.set_shader_parameter("hair_mask", mask_for(id, texture))


# 합체 컷인과 같은 감쇠 스프링. 입력은 대화용의 작고 연속적인 흔들림이다.
func _spring(pos: Vector2, vel: Vector2, target: Vector2, hz: float, dt: float) -> Array[Vector2]:
	var w := TAU * hz
	var n := maxi(1, ceili(dt * 240.0))
	var h := dt / n
	for i in n:
		vel += ((target - pos) * w * w - 2.0 * 0.42 * w * vel) * h
		pos += vel * h
	return [pos, vel]


func step(dt: float, reduced: bool, speaking: bool) -> void:
	# 큰 프레임 간격 뒤에도 관성 적분은 안정적으로 유지한다.
	var h := minf(maxf(dt, 0.0), 0.05)
	clock += h
	amount = move_toward(amount, 0.0 if reduced else 1.0, h * 5.0)
	var time := clock * float(profile.tempo)
	var strength := float(profile.body) * (1.0 if speaking else 0.8) * amount
	var breath := sin(time * 1.6 + phase)
	body_offset = Vector2(sin(time * 0.86 + phase) * 2.2, -breath * 1.0) * strength
	body_scale = Vector2(1.0 + breath * 0.0018 * strength, 1.0 + breath * 0.006 * strength)
	body_roll = deg_to_rad(sin(time * 0.86 + phase + 0.4) * 0.32 * strength)
	var target := Vector2(sin(time * 0.86 + phase + 1.1), sin(time * 1.6 + phase + 0.8) * 0.22)
	var result := _spring(hair, hair_v, target * 0.006 * float(profile.hair), 1.5, h)
	hair = result[0]
	hair_v = result[1]
	result = _spring(cloth, cloth_v, target * 0.0024 * float(profile.cloth), 1.1, h)
	cloth = result[0]
	cloth_v = result[1]
	result = _spring(ribbon, ribbon_v, target * 0.0038 * float(profile.cloth), 1.75, h)
	ribbon = result[0]
	ribbon_v = result[1]
	for mat in materials:
		_apply(mat)


func _apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("hair_off", hair * amount)
	mat.set_shader_parameter("hair_time", clock * float(profile.tempo) + phase)
	mat.set_shader_parameter("hair_wave", 0.0038 * float(profile.hair) * amount)
	mat.set_shader_parameter("skirt_off", cloth * amount)
	mat.set_shader_parameter("cloth_off", ribbon * amount)
	mat.set_shader_parameter("flutter", 0.00025 * float(profile.cloth) * amount)


static func _ellipse(uv: Vector2, zone: Vector4) -> float:
	var rel := (uv - Vector2(zone.x, zone.y)) / Vector2(zone.z, zone.w)
	return 1.0 - smoothstep(0.76, 1.06, rel.length())


static func _hair_color(id: String, c: Color) -> bool:
	match id:
		"owner": return c.r > c.g * 1.07 and c.g > c.b * 1.18 and c.g > 0.24
		"worker": return c.b > c.g * 1.18 and c.r > c.g * 1.08
		"partner": return c.g > c.r * 1.09 and c.g > c.b * 1.03
		_: return c.v < 0.33


static func mask_for(id: String, texture: Texture2D) -> Texture2D:
	var key := texture.resource_path
	if _masks.has(key):
		return _masks[key]
	# 등록된 원화 경로만 저장한다. 동적 텍스처는 캐시에 넣지 않는다.
	var cfg: Dictionary = PROFILES[id]
	var source := texture.get_image()
	if source.is_compressed():
		source.decompress()
	source.resize(MASK_SIZE, MASK_SIZE, Image.INTERPOLATE_LANCZOS)
	var seeds := PackedFloat32Array()
	seeds.resize(MASK_SIZE * MASK_SIZE)
	for y in MASK_SIZE:
		for x in MASK_SIZE:
			var uv := Vector2(x + 0.5, y + 0.5) / float(MASK_SIZE)
			var region := 0.0
			for zone in cfg.zones:
				region = maxf(region, _ellipse(uv, zone))
			var c := source.get_pixel(x, y)
			if c.a > 0.5 and _hair_color(id, c):
				region *= 1.0 - _ellipse(uv, FACE_LOCK[id])
				# 검은 머리 인물의 눈/속눈썹/입/안경은 중앙 얼굴 영역에서 고정한다.
				seeds[y * MASK_SIZE + x] = region
	# 가우시안 max 확장을 가로/세로로 나눠 첫 원화 로드 때 49탭 대신 14탭만 계산한다.
	var horizontal := PackedFloat32Array()
	horizontal.resize(seeds.size())
	for y in MASK_SIZE:
		for x in MASK_SIZE:
			for dx in range(-3, 4):
				var sx := clampi(x + dx, 0, MASK_SIZE - 1)
				horizontal[y * MASK_SIZE + x] = maxf(horizontal[y * MASK_SIZE + x], seeds[y * MASK_SIZE + sx] * exp(-float(dx * dx) / 7.0))
	var mask := Image.create(MASK_SIZE, MASK_SIZE, false, Image.FORMAT_RGB8)
	for y in MASK_SIZE:
		for x in MASK_SIZE:
			var uv := Vector2(x + 0.5, y + 0.5) / float(MASK_SIZE)
			var hair_weight := 0.0
			# 3px 부드러운 확장으로 검은 외곽선/투명 경계도 같이 변형해 이중 선을 막는다.
			for dy in range(-3, 4):
				var sy := clampi(y + dy, 0, MASK_SIZE - 1)
				hair_weight = maxf(hair_weight, horizontal[sy * MASK_SIZE + x] * exp(-float(dy * dy) / 7.0))
			var c := source.get_pixel(x, y)
			var skin := c.r > c.g * 1.08 and c.g > c.b * 1.12 and c.r > 0.45
			var hem := _ellipse(uv, Vector4(0.51, 0.87, 0.24, 0.24)) * smoothstep(0.65, 0.93, uv.y)
			hem *= c.a * (0.0 if skin else 1.0) * (1.0 - hair_weight)
			var ribbon_weight := 0.0
			if id == "owner":
				ribbon_weight = _ellipse(uv, Vector4(0.58, 0.89, 0.13, 0.14)) * c.a
			elif id == "partner":
				ribbon_weight = _ellipse(uv, Vector4(0.49, 0.49, 0.12, 0.08)) * c.a
			else:
				ribbon_weight = _ellipse(uv, Vector4(0.69, 0.68, 0.12, 0.10)) * c.a * (0.0 if skin else 1.0)
			mask.set_pixel(x, y, Color(hair_weight, hem, ribbon_weight))
	var result := ImageTexture.create_from_image(mask)
	if key != "":
		_masks[key] = result
	return result
