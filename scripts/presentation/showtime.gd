class_name Showtime
extends CanvasLayer
## 연출 전용: 보스 격파 쇼타임 — 게임 흐름을 한 번만 멈추고 보여 주는 순간 (젠레스 존 제로의 피니시 컷 대응).
## 결정타가 들어간 순간 한 번만 재생한다. 이때는 탄이 모두 지워져 피할 것이 없으므로 쿼터뷰를 벗어나도 판독성을 해치지 않는다.
##   0.00  흑백 임팩트 프레임 2장 (기존 ImpactFrame) · 세계 거의 정지
##   0.07  컷 1: 쿼터뷰 → 보스를 낮게 올려다보는 클로즈업. 화면은 강조색·먹색 2도 망점 필터, HUD 숨김, 컷인 타이포
##   1.05  컷 백: 원래 카메라로 돌아와 필터가 걷히고, 세계 속도가 0.3초에 걸쳐 정상으로 돌아온다
## 카메라는 CameraRig 가 매 프레임 계산한 자세를 덮어쓰기만 하므로(process_priority 로 나중에 돈다) 끝나면 그대로 이어진다.
## 시간은 연출용 실제 시간(Parry.now_ms). 판정과 무관. 실행 인자 `--noshowtime` 으로 끌 수 있다.

static var inst: Showtime

const FREEZE := 0.04          # 쇼타임 동안의 세계 시간 배율 (거의 정지, 불꽃만 아주 느리게 흐른다)
const CUT_AT := 0.07          # 흑백 프레임 뒤 클로즈업으로 끊는 시각
const BACK_AT := 1.05         # 원래 카메라로 돌아오는 시각
const END_AT := 1.35          # 세계 속도 완전 복귀
const FOV := 34.0

var rect: ColorRect
var mat: ShaderMaterial
var _start := -1
var _focus := Vector3.ZERO
var _dist := 11.0
var _from := Vector3.FORWARD      # 보스 → 카메라 수평 방향
var _side := 1.0
var _hidden: Array = []
var _restore_proj := Camera3D.PROJECTION_PERSPECTIVE
var _cut := false

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 ink : source_color = vec4(0.035, 0.025, 0.07, 1.0);
uniform vec4 accent : source_color = vec4(1.0, 0.3, 0.3, 1.0);
uniform vec4 paper : source_color = vec4(1.0, 0.97, 0.92, 1.0);
uniform float amount = 0.0;
uniform float cell = 7.0;
uniform float seed = 0.0;

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	float l = dot(src, vec3(0.299, 0.587, 0.114));
	l = clamp((l - 0.05) * 1.6, 0.0, 1.0);
	// 망점: 밝을수록 강조색 점이 커지고, 가장 밝은 곳은 종이색으로 날린다
	vec2 g = FRAGCOORD.xy / cell;
	g = vec2(g.x * 0.966 - g.y * 0.259, g.x * 0.259 + g.y * 0.966);
	float d = length(fract(g) - 0.5);
	float dotm = 1.0 - smoothstep(0.0, 0.08, d - sqrt(l) * 0.62);
	vec3 c = mix(ink.rgb, accent.rgb, dotm);
	c = mix(c, paper.rgb, smoothstep(0.78, 0.9, l));
	// 가장자리 먹 테두리 (만화 칸)
	vec2 q = abs(SCREEN_UV - 0.5) * 2.0;
	float frame = smoothstep(0.9, 1.0, max(q.x, q.y));
	c = mix(c, ink.rgb, frame);
	COLOR = vec4(mix(src, c, amount), 1.0);
}
"""


func _exit_tree() -> void:
	if inst == self:
		inst = null


static func active() -> bool:
	return inst != null and inst._start >= 0


## 보스 결정타 순간에 부른다. focus = 보스 몸통 중심, dist = 클로즈업 거리(보스 크기에 맞춘다)
static func boss_down(boss: Node3D, focus: Vector3, dist: float, text: String, small: String, accent: Color) -> void:
	var main := Main.inst
	if main == null or OS.get_cmdline_user_args().has("--noshowtime"):
		return
	# 궁극기 락온 중이면 시간 연출을 궁극기가 쥐고 있으므로 쇼타임을 건너뛴다
	if main.player == null or main.player.ult_aiming:
		CutIn.slam(text, small, accent)
		return
	if inst == null:
		main.add_child(Showtime.new())
	inst._play(boss, focus, dist, text, small, accent)


func _ready() -> void:
	inst = self
	layer = 7
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 100
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


func _play(_boss: Node3D, focus: Vector3, dist: float, text: String, small: String, accent: Color) -> void:
	var main := Main.inst
	_start = Parry.now_ms()
	_focus = focus
	_dist = dist
	_cut = false
	# 플레이어 쪽에서 비스듬히 올려다본다 (플레이어가 보스 뒤에 있으면 카메라 쪽)
	var to_p := main.player.global_position - focus
	to_p.y = 0
	if to_p.length() < 0.5:
		to_p = main.camera.global_position - focus
		to_p.y = 0
	_from = to_p.normalized()
	_side = 1.0 if randf() < 0.5 else -1.0
	mat.set_shader_parameter("accent", accent)
	mat.set_shader_parameter("amount", 0.0)
	main.player.invuln = maxf(main.player.invuln, END_AT + 0.5)
	var dir := -_from
	if ImpactFrame.inst:
		ImpactFrame.inst.parry(focus, dir)
	main.set_slowmo(FREEZE)
	CutIn.showtime(text, small, accent)
	Sfx.play("slowin", 0.0, 2.0)
	print("SHOWTIME %s t=%.2f" % [text, main.time])


func _cut_in() -> void:
	_cut = true
	var main := Main.inst
	visible = true
	# HUD · 보스 체력바를 숨긴다 (컷인 타이포만 남긴다)
	_hidden.clear()
	for n in [main.hud, main.get("bar")]:
		if n is CanvasLayer and (n as CanvasLayer).visible:
			(n as CanvasLayer).visible = false
			_hidden.append(n)
	_restore_proj = main.camera.projection
	main.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	main.shake(0.0)


func _cut_back() -> void:
	_cut = false
	visible = false
	var main := Main.inst
	for n in _hidden:
		if is_instance_valid(n):
			(n as CanvasLayer).visible = true
	_hidden.clear()
	if main:
		main.camera.projection = _restore_proj
		main.shake(0.5)
		main.camera.fov_punch(6.0)
		if main.hud:
			main.hud.screen_flash(Color.WHITE, 0.35)


func _process(_dt: float) -> void:
	if _start < 0:
		return
	var main := Main.inst
	if main == null:
		_start = -1
		return
	var e := (Parry.now_ms() - _start) * 0.001
	if e >= END_AT:
		_start = -1
		main.set_slowmo(1.0)
		return
	if e < BACK_AT:
		main.set_slowmo(FREEZE)
	else:
		var k := smoothstep(BACK_AT, END_AT, e)
		main.set_slowmo(lerpf(FREEZE, 1.0, k * k))
	if e >= CUT_AT and e < BACK_AT and not _cut:
		_cut_in()
	elif e >= BACK_AT and _cut:
		_cut_back()
	if not _cut:
		return
	# 필터: 컷 순간 확 들어왔다가, 끝나기 직전 살짝 걷힌다
	var ce := e - CUT_AT
	mat.set_shader_parameter("amount", clampf(ce / 0.04, 0.0, 1.0) * (1.0 - smoothstep(BACK_AT - 0.12, BACK_AT, e) * 0.5))
	if Engine.get_process_frames() % 3 == 0:
		mat.set_shader_parameter("seed", randf())
	# 카메라: 낮은 앵글에서 보스를 올려다보며 천천히 밀고 들어간다 (살짝 기울어짐)
	var cam := main.camera
	var span := BACK_AT - CUT_AT
	var k := clampf(ce / span, 0.0, 1.0)
	var push := lerpf(1.0, 0.86, 1.0 - pow(1.0 - k, 2.0))
	var right := Vector3(-_from.z, 0, _from.x) * _side
	var eye := _focus + (_from * 0.9 + right * 0.45).normalized() * _dist * push
	eye.y = maxf(Main.gy(eye) + 0.8, _focus.y - _dist * 0.12)
	var look := _focus + Vector3(0, _dist * 0.08, 0) + right * _dist * 0.04 * k
	cam.global_position = eye
	cam.look_at(look, Vector3.UP)
	cam.rotate_object_local(Vector3.FORWARD, _side * lerpf(0.1, 0.06, k))
	cam.fov = FOV
