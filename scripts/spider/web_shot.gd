extends Bullet
## 거미줄 덩이: 입에서 포물선으로 날아가 떨어진 자리에 끈적한 거미줄 판(감속 지대)을 펼친다.
## 직격하면 피해 없이 플레이어를 칭칭 감아 크게 느리게 만든다 (SpiderMain.web_player). 검·레이저로 지울 수 있다.
## 날아가는 동안 흰 실 꼬리를 남기고, 착지 직전 바닥에 옅은 그림자 표식이 커진다.

var from_p := Vector3.ZERO
var to_p := Vector3.ZERO
var flight := 0.9
var height := 4.0
var patch_r := 2.2
var strong := 1.0               # 직격 속박 세기
var glob: MeshInstance3D
var mark: MeshInstance3D
var _trail_t := 0.0

static var _glob_mesh: SphereMesh
static var _glob_mat: StandardMaterial3D
static var _mark_mat: StandardMaterial3D
static var _mark_mesh: QuadMesh


static func make_web(from: Vector3, to: Vector3, flight_t: float, h: float, r := 2.2) -> Bullet:
	if _glob_mesh == null:
		_glob_mesh = SphereMesh.new()
		_glob_mesh.radius = 0.5
		_glob_mesh.height = 1.0
		_glob_mesh.radial_segments = 12
		_glob_mesh.rings = 6
		_glob_mat = StandardMaterial3D.new()
		_glob_mat.albedo_color = Color(0.88, 0.95, 1.0)
		_glob_mat.emission_enabled = true
		_glob_mat.emission = Color(0.75, 0.95, 1.0)
		_glob_mat.emission_energy_multiplier = 1.6
		_glob_mat.roughness = 0.15
		_mark_mat = StandardMaterial3D.new()
		_mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mark_mat.albedo_color = Color(0.7, 0.92, 1.0, 0.0)
		_mark_mat.no_depth_test = false
		_mark_mesh = QuadMesh.new()
		_mark_mesh.orientation = PlaneMesh.FACE_Y
		_mark_mesh.size = Vector2(1, 1)
	var b = load("res://scripts/spider/web_shot.gd").new()
	b.from_player = false
	b.from_p = from
	b.to_p = Vector3(to.x, 0.0, to.z)
	b.flight = flight_t
	b.height = h
	b.patch_r = r
	b.radius = 0.4
	b.life = flight_t + 0.1
	b.position = from
	b.vel = (b.to_p - from) / flight_t
	b.glob = MeshInstance3D.new()
	b.glob.mesh = _glob_mesh
	b.glob.material_override = _glob_mat
	b.glob.scale = Vector3.ONE * 0.75
	b.add_child(b.glob)
	b.mesh = b.glob
	return b


func _ready() -> void:
	var m := _mark_mat.duplicate() as StandardMaterial3D
	mark = MeshInstance3D.new()
	mark.mesh = _mark_mesh
	mark.material_override = m
	mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child.call_deferred(mark)
	mark.position = to_p + Vector3(0, 0.06, 0)


func _physics_process(dt: float) -> void:
	age += dt
	var k := clampf(age / flight, 0.0, 1.0)
	var prev := position
	position = from_p.lerp(to_p, k)
	position.y = lerpf(from_p.y, 0.0, k) + sin(k * PI) * height
	vel = (position - prev) / maxf(dt, 0.0001)
	vel.y = 0.0
	# 꿈틀대는 덩이 · 실 꼬리
	glob.scale = Vector3(0.75 + sin(age * 30.0) * 0.06, 0.75 - sin(age * 30.0) * 0.05, 0.9)
	if prev.distance_to(position) > 0.001:
		glob.look_at(global_position + (position - prev), Vector3.UP if absf((position - prev).normalized().y) < 0.95 else Vector3.FORWARD)
	_trail_t -= dt
	if _trail_t <= 0.0:
		_trail_t = 0.03
		FX.sparks(global_position, 1, [Color(0.85, 0.95, 1.0), Color(0.6, 0.75, 0.85)], 0.6, 0.35, -2.0, 0.04)
	if is_instance_valid(mark):
		(mark.material_override as StandardMaterial3D).albedo_color.a = 0.08 + k * 0.32
		mark.scale = Vector3.ONE * patch_r * 2.0 * lerpf(0.35, 0.9, k)
	# 직격: 내려오는 중 플레이어 높이에서 닿으면 감긴다
	var p := Main.inst.player
	if k > 0.45 and p.alive and position.y < 2.6:
		if Vector2(position.x - p.global_position.x, position.z - p.global_position.z).length() < 1.05 + p.hit_radius:
			_land(true)
			return
	if k >= 1.0:
		_land(false)


func _land(direct: bool) -> void:
	var main := Main.inst
	var at := Vector3(position.x, 0, position.z)
	if direct:
		at = Vector3(main.player.global_position.x, 0, main.player.global_position.z)
		if main.has_method("web_player"):
			main.call("web_player", strong)
	if main.has_method("web_patch") and not main.is_blocked(at + Vector3(0, 0.5, 0)):
		main.call("web_patch", at, patch_r)
	FX.flash(at + Vector3(0, 0.3, 0), Color(0.85, 1.0, 1.0), 0.8, 0.07)
	FX.sparks(at + Vector3(0, 0.3, 0), 10, [Color.WHITE, Color(0.75, 0.92, 1.0)], 4.0, 0.35, -10.0, 0.05)
	Sfx.play("land", 0.3, -14.0)
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(mark):
		mark.queue_free()
