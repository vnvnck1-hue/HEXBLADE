class_name TurretHatch
extends Node3D
## 포탑이 숨어 있던 바닥 해치. 테두리 경고등 → 두 덮개가 아래로 열림 → 승강판이 포탑을 밀어 올림.
## 포탑이 부서진 뒤에도 승강판과 꺼진 테두리가 바닥에 남는다. 격자에 맞춰 놓는다 (회전 없음).
## 연출 전용이며, 진행 시각은 포탑(turret.gd)이 넘겨준다.

const HALF := 1.2               # 해치 반폭 (3×3 칸 안에 들어간다)
const WARN := Color("ffae1e")
const DEAD := Color("5a1418")

var _flaps: Array[Node3D] = []
var _stripes: Array[MeshInstance3D] = []
var _pit: MeshInstance3D
var _platform: Node3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	var s := HALF * 2.0
	# 어두운 구멍 (덮개가 열렸을 때만 보인다). 바닥 위에 얹은 판이라 그 아래로 내려간 부분은 가려진다.
	var q := QuadMesh.new()
	q.size = Vector2(s, s)
	q.orientation = PlaneMesh.FACE_Y
	_pit = Pal.flat_mesh(q, Color(0.012, 0.01, 0.025), 1.0)
	_pit.position.y = 0.008
	_pit.visible = false
	add_child(_pit)
	# 테두리 틀과 경고 띠
	for i in 4:
		var a := TAU * i / 4.0
		var d := Vector3(sin(a), 0, cos(a))
		var along := Basis(Vector3.UP, a)
		var frame := Build.box(self, Vector3(s + 0.24, 0.05, 0.12), d * (HALF + 0.06) + Vector3(0, 0.025, 0), Pal.T_DARK)
		frame.basis = along
		var strip := Build.glow_box(self, Vector3(s + 0.08, 0.02, 0.05), d * (HALF + 0.03) + Vector3(0, 0.055, 0), WARN, 0.4)
		strip.basis = along
		_stripes.append(strip)
	# 덮개 두 장: 바깥 모서리가 경첩. 가운데 이음새에 경고등이 있다.
	for side in [-1, 1]:
		var hinge := Build.pivot(self, Vector3(HALF * side, 0.02, 0), "Flap")
		Build.box(hinge, Vector3(HALF - 0.02, 0.04, s - 0.04), Vector3(-HALF * 0.5 * side, 0, 0), Pal.T_METAL)
		Build.box(hinge, Vector3(HALF * 0.62, 0.02, s * 0.7), Vector3(-HALF * 0.55 * side, 0.03, 0), Pal.T_METAL_LIGHT)
		for k in 3:
			# 사선 경고 줄무늬
			Build.box(hinge, Vector3(0.1, 0.022, 0.42), Vector3(-HALF * 0.16 * side, 0.032, (k - 1) * 0.62), Pal.T_DARK, Vector3(0, 35 * side, 0))
		var seam := Build.glow_box(hinge, Vector3(0.04, 0.02, s - 0.1), Vector3(-(HALF - 0.04) * side, 0.03, 0), WARN, 0.3)
		_stripes.append(seam)
		_flaps.append(hinge)
	# 승강판: 처음엔 바닥 아래에 숨어 있다
	_platform = Build.pivot(self, Vector3(0, -1.2, 0), "Lift")
	Build.box(_platform, Vector3(s - 0.08, 0.14, s - 0.08), Vector3(0, -0.07, 0), Pal.T_DARK)
	Build.box(_platform, Vector3(s - 0.4, 0.02, s - 0.4), Vector3(0, 0.005, 0), Pal.T_METAL)
	_platform.visible = false
	_light = OmniLight3D.new()
	_light.light_color = WARN
	_light.light_energy = 0.0
	_light.omni_range = 3.5
	_light.position.y = 0.4
	add_child(_light)


## 0~1: 테두리·이음새 경고등이 점점 빠르게 깜빡이고 덮개가 덜컹거린다
func warn(k: float, dt: float) -> void:
	_t += dt
	var on := fmod(_t, lerpf(0.22, 0.08, k)) < lerpf(0.11, 0.04, k)
	for s in _stripes:
		s.set_instance_shader_parameter("energy", 2.4 if on else 0.35)
	for i in 2:
		_flaps[i].rotation.z = randf_range(-1.0, 1.0) * deg_to_rad(1.5) * k
	_light.light_energy = (1.2 if on else 0.2) * k


## 0~1: 덮개가 바깥 경첩을 축으로 아래로 젖혀 열린다
func open(k: float) -> void:
	_pit.visible = k > 0.0
	var a := deg_to_rad(105.0) * k
	_flaps[0].rotation.z = -a
	_flaps[1].rotation.z = a
	_light.light_energy = 1.4 * (1.0 - k * 0.3)
	for s in _stripes:
		s.set_instance_shader_parameter("energy", 2.0)


## 승강판 윗면 높이
func lift(y: float) -> void:
	_platform.visible = true
	_platform.position.y = y


## 포탑이 올라와 고정됨: 구멍은 승강판이 덮고 테두리는 은은하게 켜 둔다
func lock() -> void:
	_pit.visible = false
	for f in _flaps:
		f.visible = false
	_platform.position.y = 0.03
	for s in _stripes:
		s.set_instance_shader_parameter("energy", 0.7)
	var tw := create_tween()
	tw.tween_property(_light, "light_energy", 0.0, 0.4)


## 포탑이 부서짐: 테두리가 꺼진다
func shut_down() -> void:
	for s in _stripes:
		s.set_instance_shader_parameter("tint", DEAD)
		s.set_instance_shader_parameter("energy", 0.8)
	_light.light_energy = 0.0
