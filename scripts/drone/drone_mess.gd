class_name DroneMess
extends Node3D
## 청소 대상. 처치된 적이 남긴 잔해(SCRAP: 기계 조각 · 기름 얼룩 · 가는 연기)와 체액(GOO: 출렁이는 웅덩이 · 거품).
## 드론이나 플레이어가 clean() 으로 work 를 깎으면 조각이 하나씩 흡입구로 빨려 들어가고 얼룩이 옅어진다.
## 다 치우면 반짝이며 사라지고 value 만큼 지원 게이지를 준다 (같은 대상은 한 번만).
## 체액 웅덩이는 위에 선 플레이어를 살짝 느리게 한다 (특수 오염 = 약한 이동 방해. 일반 잔해는 이동을 막지 않음).

enum Kind { SCRAP, GOO }

const GROUP := "drone_mess"
const MAX := 40                    ## 동시에 남는 오염 상한 (넘으면 가장 오래된 것이 저절로 녹아 없어진다, 게이지 없음)
const GOO_SLOW := 0.78
const SCRAP_COLS: Array[Color] = [Color(0.2, 0.18, 0.28), Color(0.82, 0.8, 0.9), Color(0.36, 0.33, 0.5), Color(0.62, 0.6, 0.72)]
const SPARK := Color(1.0, 0.3, 0.62)
const GOO_DEFAULT := Color(0.62, 0.92, 0.22)

static var _box: BoxMesh
static var _prism: PrismMesh
static var _ball: SphereMesh
static var _disc: CylinderMesh
static var _stain_mat: StandardMaterial3D
static var _goo_mats := {}

var kind := Kind.SCRAP
var size_k := 1.0
var work := 1.0
var work_max := 1.0
var value := 12.0
var radius := 0.7
var goo_col := GOO_DEFAULT
var done := false
var age := 0.0
var sucking := 0.0                  ## 지금 빨려 들어가는 중 (흔들림)
var claim: Node = null              ## 이 오염을 맡은 드론
var chunks: Array = []              ## [node, 다 빨려 들어가는 진행도 문턱, 날아가는 중?]
var blobs: Array = []               ## GOO 웅덩이 덩어리 [node, 기본 크기]
var stain: MeshInstance3D
var _smoke_t := 1.0
var _bubble_t := 0.6
var _sucker := Vector3.ZERO
var rng := RandomNumberGenerator.new()


static func spawn(parent: Node, pos: Vector3, k: int, size: float, col := GOO_DEFAULT) -> DroneMess:
	var all := parent.get_tree().get_nodes_in_group(GROUP)
	if all.size() >= MAX:
		(all[0] as DroneMess).dissolve()
	var m := DroneMess.new()
	m.kind = k
	m.size_k = size
	m.goo_col = col
	parent.add_child(m)
	m.global_position = pos
	return m


func _ready() -> void:
	add_to_group(GROUP)
	rng.randomize()
	_meshes()
	radius = (0.6 if kind == Kind.SCRAP else 0.75) * size_k
	work_max = (1.0 if kind == Kind.SCRAP else 1.35) * size_k
	work = work_max
	value = clampf(10.0 * size_k * (1.0 if kind == Kind.SCRAP else 1.2), 8.0, 30.0)
	rotation.y = rng.randf() * TAU
	if kind == Kind.SCRAP:
		_build_scrap()
	else:
		_build_goo()
	# 떨어지며 생기는 연출: 조각이 툭 튀어 흩어진다
	scale = Vector3.ONE * 0.3
	create_tween().tween_property(self, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func _meshes() -> void:
	if _box:
		return
	_box = BoxMesh.new()
	_prism = PrismMesh.new()
	_ball = SphereMesh.new()
	_ball.radius = 0.5
	_ball.height = 1.0
	_ball.radial_segments = 16
	_ball.rings = 8
	_disc = CylinderMesh.new()
	_disc.top_radius = 0.5
	_disc.bottom_radius = 0.5
	_disc.height = 0.01
	_disc.radial_segments = 24
	_stain_mat = StandardMaterial3D.new()
	_stain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_stain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_stain_mat.albedo_color = Color(0.05, 0.04, 0.08, 0.62)
	_stain_mat.render_priority = -5


## 체액 색은 몇 단계로 묶어 캐시한다 (무작위 색을 키로 쓰면 씬을 불러올 때마다 캐시가 커진다)
static func _goo_mat(c: Color) -> StandardMaterial3D:
	var q := Color(snappedf(c.r, 0.1), snappedf(c.g, 0.1), snappedf(c.b, 0.1))
	var key := q.to_html(false)
	if not _goo_mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = q
		m.roughness = 0.12
		m.metallic_specular = 0.8
		m.emission_enabled = true
		m.emission = q
		m.emission_energy_multiplier = 0.25
		_goo_mats[key] = m
	return _goo_mats[key]


func _build_scrap() -> void:
	stain = MeshInstance3D.new()
	stain.mesh = _disc
	stain.material_override = _stain_mat
	stain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stain.scale = Vector3(1.6, 1, 1.25) * size_k
	stain.position.y = 0.02
	add_child(stain)
	var n := 5 + int(size_k * 2.0)
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = _box if rng.randf() < 0.6 else _prism
		var big := i < 2
		var s := Vector3(rng.randf_range(0.14, 0.3), rng.randf_range(0.06, 0.16), rng.randf_range(0.12, 0.26)) * size_k * (1.4 if big else 1.0)
		mi.scale = s
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.0, 0.5) * size_k
		mi.position = Vector3(cos(a) * r, s.y * 0.45, sin(a) * r)
		mi.rotation = Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6))
		mi.material_override = Pal.lit(SCRAP_COLS[i % SCRAP_COLS.size()])
		add_child(mi)
		chunks.append([mi, float(i + 1) / float(n + 1), false])
	# 아직 불빛이 남은 작은 부품 하나 (깜빡임)
	var glow := Pal.flat_mesh(_ball, SPARK, 1.6)
	glow.scale = Vector3.ONE * 0.09 * size_k
	glow.position = Vector3(0.12, 0.12, -0.05) * size_k
	add_child(glow)
	chunks.append([glow, 0.95, false])
	chunks.shuffle()


func _build_goo() -> void:
	var m := _goo_mat(goo_col)
	var n := 4 + int(size_k * 2.0)
	for i in n:
		var mi := MeshInstance3D.new()
		mi.mesh = _ball
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := rng.randf() * TAU
		var r := (0.0 if i == 0 else rng.randf_range(0.2, 0.55)) * size_k
		var w := (rng.randf_range(0.6, 0.9) if i == 0 else rng.randf_range(0.25, 0.5)) * size_k
		var base := Vector3(w, 0.07 + rng.randf() * 0.03, w * rng.randf_range(0.7, 1.0))
		mi.scale = base
		mi.position = Vector3(cos(a) * r, 0.02, sin(a) * r)
		mi.rotation.y = rng.randf() * TAU
		add_child(mi)
		blobs.append([mi, base])
	# 튄 방울 몇 개: 웅덩이와 같이 빨려 들어간다
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = _ball
		mi.material_override = m
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.6, 0.9) * size_k
		mi.scale = Vector3(0.14, 0.05, 0.12) * size_k
		mi.position = Vector3(cos(a) * r, 0.02, sin(a) * r)
		add_child(mi)
		chunks.append([mi, 0.2 + i * 0.25, false])


## 청소: amount 만큼 깎는다. sucker = 빨아들이는 곳(흡입구). 다 치우면 true.
func clean(amount: float, sucker: Vector3) -> bool:
	if done:
		return false
	work = maxf(0.0, work - amount)
	sucking = 1.0
	_sucker = sucker
	var p := 1.0 - work / work_max
	for c: Array in chunks:
		if not c[2] and p >= float(c[1]):
			c[2] = true
			_fly(c[0] as Node3D, sucker)
	if work <= 0.0:
		finish(sucker)
		return true
	return false


func progress() -> float:
	return 1.0 - work / work_max


## 조각 하나가 흡입구로 빨려 들어간다 (빙글 돌며 작아짐)
func _fly(n: Node3D, to: Vector3) -> void:
	var from := n.global_position
	n.top_level = true
	n.global_position = from
	var s0 := n.scale
	var spin := Vector3(rng.randf_range(-12, 12), rng.randf_range(-12, 12), 0)
	var tw := n.create_tween()
	tw.tween_method(func(k: float):
		if not is_instance_valid(n):
			return
		var e := k * k
		var p := from.lerp(to, e) + Vector3.UP * sin(PI * k) * 0.35
		n.global_position = p
		n.rotation += spin * 0.016
		n.scale = s0 * (1.0 - e * 0.85), 0.0, 1.0, 0.3)
	tw.tween_callback(func():
		if is_instance_valid(n):
			n.visible = false)


## 다 치움: 반짝 · 작게 쪼그라들며 사라진다
func finish(at: Vector3) -> void:
	done = true
	remove_from_group(GROUP)
	var c := global_position + Vector3(0, 0.25, 0)
	FX.sparks(c, 10, [Color.WHITE, Color("bffff0"), DroneRig.CORE], 4.0, 0.45, -6.0, 0.05)
	FX.ring(global_position + Vector3(0, 0.05, 0), radius * 1.6, [Color.WHITE, DroneRig.CORE, Color("bffff0")], 0.35)
	DroneFX.twinkle(global_position + Vector3(0, 0.35, 0), radius)
	for b: Array in blobs:
		var n: Node3D = b[0]
		create_tween().tween_property(n, "scale", Vector3.ZERO, 0.18)
	if stain:
		create_tween().tween_property(stain, "transparency", 1.0, 0.3)
	var tw := create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(queue_free)


## 너무 많이 쌓였을 때: 게이지 없이 조용히 녹아 없어진다
func dissolve() -> void:
	if done:
		return
	done = true
	remove_from_group(GROUP)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.0, 0.05, 1.0), 0.4)
	tw.tween_callback(queue_free)


func _process(dt: float) -> void:
	age += dt
	if done:
		return
	var p := 1.0 - work / work_max
	sucking = move_toward(sucking, 0.0, dt * 4.0)
	# 화면 밖 먼 오염은 꿀렁임·연기·거품을 쉰다 (빨아들이는 중이면 계속). 최대 40개가 매 프레임 돌던 것
	if sucking <= 0.0 and Cull.far(global_position):
		return
	if stain:
		stain.transparency = p * 0.8
	for b: Array in blobs:
		var n: Node3D = b[0]
		var base: Vector3 = b[1]
		var wob := 1.0 + sin(age * 3.0 + n.position.x * 9.0) * 0.06 + sin(age * 30.0 + n.position.z * 7.0) * 0.08 * sucking
		var shrink := 1.0 - p * 0.85
		n.scale = Vector3(base.x * wob * shrink, base.y * (2.0 - wob) * maxf(shrink, 0.4), base.z * wob * shrink)
		if sucking > 0.0:
			# 흡입구 쪽으로 끌려 늘어난다
			var to := _sucker - global_position
			to.y = 0
			n.position = n.position.move_toward(to.normalized() * 0.15 * size_k + Vector3(0, 0.02, 0), dt * 0.3 * sucking)
	if sucking > 0.0:
		for c: Array in chunks:
			if not c[2]:
				var n: Node3D = c[0]
				n.rotation.x += rng.randf_range(-1, 1) * 0.06 * sucking
	if kind == Kind.SCRAP:
		_smoke_t -= dt
		if _smoke_t <= 0.0:
			_smoke_t = rng.randf_range(1.2, 2.4)
			FX.puffs(global_position + Vector3(rng.randf_range(-0.2, 0.2), 0.3, rng.randf_range(-0.2, 0.2)), 1,
				[Color(0.36, 0.34, 0.44), Color(0.3, 0.28, 0.38), Color(0.12, 0.11, 0.18), Color(0.1, 0.09, 0.15)], 0.15, 0.35 * size_k, 1.2)
	else:
		_bubble_t -= dt
		if _bubble_t <= 0.0:
			_bubble_t = rng.randf_range(0.5, 1.4)
			DroneFX.bubble(global_position + Vector3(rng.randf_range(-0.4, 0.4) * size_k, 0.06, rng.randf_range(-0.4, 0.4) * size_k), _goo_mat(goo_col))


## 이 자리에 선 캐릭터가 체액을 밟고 있나
func covers(p: Vector3) -> bool:
	return kind == Kind.GOO and not done and Vector2(p.x - global_position.x, p.z - global_position.z).length() < radius * (1.0 - progress() * 0.7)
