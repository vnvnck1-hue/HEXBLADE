class_name ImpactFrame
extends CanvasLayer
## 임팩트 프레임: 강한 레이저 발사 순간 1~4프레임 동안 화면을 순수 흑백으로 바꾼다.
## - 한 프레임 안의 대비: 밝기를 문턱값으로 잘라 순수한 흑과 백만 남긴다
## - 프레임 사이의 대비: 다음 프레임에서 흑백을 반전하고 선 배치를 바꾼다
## - 방향성: 총구(충격의 원점)를 소실점으로 하는 1점 투시 쐐기. 빔 축 방향에 몰린다
## 시간은 실제 시간(ms)으로 재서 히트스탑(time_scale) 중에도 정해진 길이만 보인다.
## HUD(layer 10) 아래에 두어 조준점·게이지는 그대로 보인다. 판정과 무관.

static var inst: ImpactFrame

var enabled := true
var rect: ColorRect
var mat: ShaderMaterial
## 재생 중인 단계: [지속 ms, 반전, 선 밀도, 시드]
var _phases: Array = []
var _phase_i := -1
var _phase_end := 0
var _shown := false
var _center := Vector3.ZERO
var _dir := Vector3.FORWARD
var _after: Array[Callable] = []

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 center = vec2(0.5);
uniform vec2 dir = vec2(1.0, 0.0);
uniform float aspect = 1.6;
uniform float invert = 0.0;
uniform float seed = 0.0;
uniform float density = 1.0;
uniform float threshold = 0.4;

float hash(float n) { return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453); }

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	float v = step(threshold, dot(c, vec3(0.299, 0.587, 0.114)));
	vec2 p = SCREEN_UV - center;
	p.x *= aspect;
	float r = length(p);
	float a = atan(p.y, p.x) / 6.2831853 + 0.5;
	float n = 110.0;
	float cell = floor(a * n);
	float f = fract(a * n);
	// 빔 축(앞뒤)에 가까울수록 쐐기가 많고 길다
	float along = abs(dot(p / max(r, 1e-4), dir));
	float prob = mix(0.10, 0.62, pow(along, 4.0)) * density;
	float width = mix(0.08, 0.7, hash(cell + 17.0));
	float start = mix(0.05, 0.32, hash(cell + 5.0)) * (1.0 - along * 0.6);
	float wedge = step(1.0 - prob, hash(cell)) * step(abs(f - 0.5), width * 0.5) * step(start, r);
	// 쐐기는 흰 판과 검은 판을 섞는다
	v = mix(v, step(0.45, hash(cell + 9.0)), wedge);
	// 원점의 작은 흰 핵
	v = max(v, step(r, 0.035));
	v = mix(v, 1.0 - v, invert);
	COLOR = vec4(vec3(v), 1.0);
}
"""


func _ready() -> void:
	inst = self
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SHADER
	mat.shader = sh
	rect.material = mat
	add_child(rect)
	visible = false


func active() -> bool:
	return _phase_i >= 0


## 재생이 끝난 뒤 실행할 일 (예: 화면 섬광이 흑백 프레임을 덮지 않게 뒤로 미룸)
func after(cb: Callable) -> void:
	if active():
		_after.append(cb)
	else:
		cb.call()


## 충전 레이저: 1프레임 원판 + 1프레임 반전
func laser(origin: Vector3, dir: Vector3) -> void:
	_play(origin, dir, [[17, 0.0, 1.0], [17, 1.0, 1.35]])


## 최대 충전 레이저: 원점 강조 2프레임 → 반전·굵은 선 2프레임
func mega(origin: Vector3, dir: Vector3) -> void:
	_play(origin, dir, [[34, 0.0, 1.0], [34, 1.0, 1.5]])


## 패링: 흰 원판 2프레임 → 반전·굵은 선 3프레임
func parry(origin: Vector3, dir: Vector3) -> void:
	_play(origin, dir, [[34, 0.0, 1.3], [50, 1.0, 1.8]])


## 재생 길이(초). 호출 쪽이 히트스탑 길이를 맞출 때 쓴다
func duration(kind: String) -> float:
	return 0.034 if kind == "laser" else 0.068


func _play(origin: Vector3, dir: Vector3, phases: Array) -> void:
	if not enabled:
		return
	_center = origin
	_dir = dir
	_phases = []
	var base := randf() * 100.0
	for i in phases.size():
		_phases.append(phases[i] + [base + i * 13.0])
	_phase_i = -1
	_next_phase()


func _next_phase() -> void:
	_phase_i += 1
	if _phase_i >= _phases.size():
		_phase_i = -1
		visible = false
		var cbs := _after.duplicate()
		_after.clear()
		for cb in cbs:
			cb.call()
		return
	var ph: Array = _phases[_phase_i]
	_phase_end = Time.get_ticks_msec() + int(ph[0])
	_shown = false
	mat.set_shader_parameter("invert", ph[1])
	mat.set_shader_parameter("density", ph[2])
	mat.set_shader_parameter("seed", ph[3])
	_aim()
	visible = true


func _aim() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var size := get_viewport().get_visible_rect().size
	var c := cam.unproject_position(_center)
	var d := cam.unproject_position(_center + _dir * 4.0) - c
	mat.set_shader_parameter("center", c / size)
	mat.set_shader_parameter("dir", d.normalized() if d.length() > 1.0 else Vector2.RIGHT)
	mat.set_shader_parameter("aspect", size.x / size.y)


func _process(_dt: float) -> void:
	if _phase_i < 0:
		return
	# 단계마다 최소 한 프레임은 화면에 나가게 한 뒤 시간을 본다
	if not _shown:
		_shown = true
		return
	if Time.get_ticks_msec() >= _phase_end:
		_next_phase()
