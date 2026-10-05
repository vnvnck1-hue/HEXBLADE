class_name FluidSmoke
extends Node3D
## 나비에-스토크스 유체 연기 (연출 격자). [docs/fluid-smoke.md]
##
## 바닥에 깐 2D 격자 하나에서 Stable Fluids(Jos Stam) 를 GPU 컴퓨트 셰이더로 푼다.
## 한 프레임: 이동(semi-Lagrangian) → 소용돌이 보강 → 발산 → 압력 야코비 jacobi 회 → 압력 빼기 + 힘 넣기.
## 힘(방출기)은 압력을 뺀 "뒤"에 넣는다: 폭발처럼 퍼지는 흐름·청소기처럼 빨아들이는 흐름은 발산이 있어서
## 압력 단계를 거치면 사라지기 때문 (그 프레임의 이동에는 남고, 다음 프레임 압력이 다시 걷어 낸다).
##
## 연기는 스타일 4종(STYLES: 안개 · 뭉게 · 독가스 · 증기)의 몫을 칸마다 따로 실어 나른다(염료 채널 4개).
## 압력을 뺀 단계 끝에서 화면이 행진 중에 읽을 값(높이 단면 · 결 세기 · 결 속도 · 밀도)을 한 장(A)에,
## 닿은 곳 색칠에만 쓰는 스타일 비율을 다른 한 장(B)에 미리 굽는다 → 행진 한 걸음에 텍스처 한 번만 읽는다.
## 그리기는 카메라의 컴포지터 효과(FluidSmokeFX)가 장면 깊이를 읽으며 절반 해상도로 행진하고 깊이를 보며 올려 붙인다.
##
## 같은 단계에서 독가스를 빨아 먹은 양 · 남은 독가스 · 전체 밀도를 GPU 에서 합쳐 비동기로 읽어 온다 (FluidField 청소 판정).
## 격자가 비어 있고 연기를 넣는 방출기가 없으면 계산·그리기를 쉰다.
## 헤드리스(RenderingDevice 없음)에서는 격자 계산·화면을 건너뛰고 방출기 수집만 한다.

const MAX_EMIT := 64
const HEAD := 4                 # 방출기 버퍼 앞 vec4 4개 = 스타일 값 (높이 · 결 세기 · 결 속도 · 감쇠)
const HMAX := 1.3               # 연기 최대 높이 (m, 스타일 height 를 곱한다)
const VEL_DAMP := 0.55          # 초당 속도 감쇠
const SOOT_DECAY := 0.45        # 초당 그을음 감쇠 (스타일 연기는 STYLES 의 decay)
const MAX_SPEED := 38.0         # m/s
const VORT := 9.0               # 소용돌이 보강 세기
const BLAST_LIFE := 0.32        # 폭발 바람이 이어지는 시간
const FIX := 1000.0             # 합계 고정소수 배율 (GPU atomicAdd 는 정수)

enum Kind { PUSH, RADIAL, SWIRL, PART }
enum Mode { ADVECT, VORT, DIV, JACOBI, PROJECT }
enum Ch { MIST, PUFF, TOXIC, STEAM }

## 그리기 품질: LOW = 절반 해상도 24걸음, HIGH = 절반 해상도 40걸음, FULL = 원래 해상도 40걸음 (비교용)
enum Quality { LOW, HIGH, FULL }
const QUALITY_NAMES := ["LOW · 절반 해상도 24걸음", "HIGH · 절반 해상도 40걸음", "FULL · 원 해상도 40걸음"]
static var quality := Quality.FULL   ## 기본: 원 해상도 40걸음 (사용자 확정 2026-10-06)

## 스타일 프리셋. 색은 sRGB. 화면(height 높이 배율 · alo/ahi 옅은/짙은 곳 불투명도 · soft 명암 경계 부드러움 ·
## line_k 외곽선 · rim 역광 테두리 · spec 해 쪽 하이라이트 · glow_k 안쪽 발광 · lump/lump_spd 결의 크기/속도)과
## 물리(decay 초당 감쇠 · rate 통풍구 초당 분출량 · push 분출 바람 m/s)를 함께 정한다.
## 독가스는 감쇠 0 — 빨아들여 치우기 전엔 사라지지 않는다 (청소 대상).
const STYLES := [
	{"id": "mist", "name": "MIST", "ko": "안개", "desc": "옅고 낮게 깔림 · 명암 경계 없이 부드럽게 · 역광 테두리만 은은히",
		"lit": Color(0.87, 0.89, 0.98), "mid": Color(0.76, 0.79, 0.92), "dark": Color(0.65, 0.68, 0.85), "line": Color(0.55, 0.57, 0.74), "glow": Color(0, 0, 0),
		"height": 0.45, "alo": 0.14, "ahi": 0.38, "soft": 0.4, "line_k": 0.0, "rim": 0.55, "spec": 0.0, "glow_k": 0.0, "lump": 0.35, "lump_spd": 0.6,
		"decay": 0.10, "rate": 4.2, "push": 0.6},
	{"id": "puff", "name": "PUFF", "ko": "뭉게", "desc": "가벼운 만화 구름 · 2단 명암 · 가는 외곽선 · 밝은 그림자",
		"lit": Color(0.97, 0.97, 1.0), "mid": Color(0.84, 0.86, 0.96), "dark": Color(0.70, 0.73, 0.89), "line": Color(0.46, 0.47, 0.66), "glow": Color(0, 0, 0),
		"height": 0.9, "alo": 0.34, "ahi": 0.66, "soft": 0.07, "line_k": 0.4, "rim": 0.18, "spec": 0.0, "glow_k": 0.0, "lump": 0.22, "lump_spd": 1.0,
		"decay": 0.06, "rate": 4.5, "push": 0.45},
	{"id": "toxic", "name": "TOXIC", "ko": "독가스", "desc": "형광 초록 · 안에서 맥박치듯 빛남 · 부글부글 끓는 결 · 치울 때까지 고임",
		"lit": Color(0.66, 0.92, 0.40), "mid": Color(0.42, 0.74, 0.33), "dark": Color(0.22, 0.45, 0.27), "line": Color(0.08, 0.24, 0.13), "glow": Color(0.55, 1.0, 0.25),
		"height": 0.7, "alo": 0.30, "ahi": 0.62, "soft": 0.1, "line_k": 0.5, "rim": 0.4, "spec": 0.0, "glow_k": 0.28, "lump": 0.42, "lump_spd": 3.2,
		"decay": 0.0, "rate": 3.4, "push": 0.35},
	{"id": "steam", "name": "STEAM", "ko": "증기", "desc": "새하얀 증기 · 해 쪽 반짝 하이라이트 · 세게 뿜고 빨리 흩어짐",
		"lit": Color(1.0, 1.0, 1.0), "mid": Color(0.86, 0.92, 0.98), "dark": Color(0.68, 0.78, 0.92), "line": Color(0.55, 0.64, 0.80), "glow": Color(0, 0, 0),
		"height": 1.05, "alo": 0.16, "ahi": 0.5, "soft": 0.22, "line_k": 0.0, "rim": 0.7, "spec": 0.35, "glow_k": 0.0, "lump": 0.3, "lump_spd": 1.7,
		"decay": 0.38, "rate": 8.0, "push": 1.8},
]

static var inst: FluidSmoke
static var _blasts: Array = []  # {pos, r, speed, soot, age}

var origin := Vector2.ZERO      # 격자 왼쪽 위 모서리 (월드 x, z)
var cell := 0.2
var nx := 160
var ny := 120
var vents: Array = []           # {pos: Vector3, r, style}
var vents_on := true
var force_style := -1           ## 0~3 이면 모든 통풍구가 그 스타일, -1 이면 통풍구마다 제 스타일
var view_mode := 1              ## 0 연기(높이장 행진) · 1 밀도 (기본, 사용자 확정 2026-10-06) — F8 로 전환
var active := false             ## GPU 계산이 실제로 도는가 (헤드리스면 false)
var emitters: Array = []        ## 이번 프레임에 모은 방출기 (확인용) [Kind, 위치(셀), 반경(셀), a, b, c, d, 채널]
var extra_emitters: Array = []  ## 다른 모듈(FluidField)이 이번 프레임에 넣는 방출기 — _gather 가 비우고 다시 모은다
var frames := 0
var idle := false               ## 비어 있어 계산·그리기를 쉬는 중
# 부하 분석용 손잡이
var jacobi := 20                ## 압력 반복 (짝수: 압력 버퍼가 제자리로 돌아온다)
var steps_override := -1        ## 0 보다 크면 품질과 상관없이 이 걸음 수
var skip_empty := true          ## 연기 없는 화소는 행진 전에 버린다
var gpu_compute := true         ## false 면 계산을 건너뛴다 (화면만)
var draw := true                ## false 면 그리기를 건너뛴다 (계산만)
var cpu_usec := 0               ## 지난 프레임 CPU 쪽 시간 (방출기 모으기 + 명령 기록, µs)
var measure_gpu := false        ## true 면 계산 앞뒤에 GPU 타임스탬프를 찍는다 (compute_gpu_ms 로 읽음)
# GPU 합계 (비동기로 몇 프레임 늦게 들어온다)
var stat_toxic := 0.0           ## 격자 전체 독가스 양
var stat_all := 0.0             ## 격자 전체 밀도 (그을음 포함)
var stat_eaten := 0.0           ## 아직 가져가지 않은 빨아 먹은 독가스 양 (consume_eaten 으로 가져간다)
var stat_count := 0             ## 합계가 들어온 횟수

var _rd: RenderingDevice
var _shader := RID()
var _pipe := RID()
var _s: Array[RID] = []         # 상태 (속도 x, 속도 z, -, 그을음) 두 장
var _d: Array[RID] = []         # 스타일 염료 (안개, 뭉게, 독가스, 증기의 밀도) 두 장 — 상태와 같이 주고받는다
var _p: Array[RID] = []         # 압력 두 장
var _div := RID()
var _obs := RID()
var _disp := RID()              # 화면용 A (높이 단면, 결 세기, 결 속도, 전체 밀도)
var _disp2 := RID()             # 화면용 B (스타일 비율 — 나머지는 그을음)
var _ebuf := RID()
var _stats := RID()
var _sets := {}                 # Vector2i(s 쪽, p 쪽) → 유니폼 세트
var _s_cur := 0
var _p_cur := 0
var _fx: FluidSmokeFX
var _cam: Camera3D
var _prev := {}                 # 인스턴스 id → 지난 위치 (속도 계산)
var _body_prev := Vector3.INF
var _tip_prev := Vector3.INF
var _mid_prev := Vector3.INF
var _t := 0.0
var _pending_clear := false
var _pending_fill := 0.0
var _busy_t := 0.0              # 연기를 넣는 방출기가 마지막으로 있던 뒤 지난 시간


## 씬에 붙인다. center = 격자 가운데(월드), size = 가로·세로 (m)
static func attach(parent: Node, center: Vector3, size: Vector2, cell_size := 0.2) -> FluidSmoke:
	var f := FluidSmoke.new()
	f.cell = cell_size
	f.nx = int(ceil(size.x / cell_size / 8.0)) * 8
	f.ny = int(ceil(size.y / cell_size / 8.0)) * 8
	f.origin = Vector2(center.x, center.z) - Vector2(f.nx, f.ny) * cell_size * 0.5
	f.name = "FluidSmoke"
	parent.add_child(f)
	return f


## 폭발·내려찍기 바람 (Distortion.burst 가 부른다). 반경 radius 의 충격 자리에서 바깥으로 밀고, haze 가 있으면 그을음 연기를 낸다.
static func blast(pos: Vector3, radius: float, strength := 1.0, haze := 0.0) -> void:
	if not is_instance_valid(inst):
		return
	if _blasts.size() >= 16:
		_blasts.pop_front()
	_blasts.append({"pos": pos, "r": radius * 1.45, "speed": (5.0 + radius * 3.2) * clampf(strength, 0.4, 1.8), "soot": haze, "age": 0.0})


static func cycle_quality(step := 1) -> void:
	quality = posmod(quality + step, Quality.size()) as Quality


## style = STYLES 번호 (분출량 · 바람 · 색은 스타일이 정한다)
func add_vent(pos: Vector3, style := 1, r := 1.0) -> void:
	vents.append({"pos": pos, "r": r, "style": style})


func vent_style(i: int) -> int:
	return force_style if force_style >= 0 else int(vents[i].style)


func clear() -> void:
	_pending_clear = true


## 한 번에 연기를 확 채운다 (확인용). 격자를 넷으로 나눠 왼쪽 위부터 스타일 0·1·2·3 (force_style 이면 그것만).
## lumpy = false 면 고르게 (수치 검사용)
func fill(amount := 0.7, lumpy := true) -> void:
	# 크기 = 양(< 10), 10 단위 자리 = 고정 스타일 + 1 (0 = 넷으로 나눔), 부호 = 결 있음(+) / 고르게(-)
	var k := minf(amount, 9.0) + 10.0 * (force_style + 1)
	_pending_fill = k if lumpy else -k


func size_m() -> Vector2:
	return Vector2(nx, ny) * cell


func to_cell(p: Vector3) -> Vector2:
	return (Vector2(p.x, p.z) - origin) / cell - Vector2(0.5, 0.5)


func covers(p: Vector3) -> bool:
	var c := to_cell(p)
	return c.x >= 0.0 and c.y >= 0.0 and c.x < nx and c.y < ny


## 빨아 먹은 독가스 양을 가져간다 (한 번 가져가면 0)
func consume_eaten() -> float:
	var e := stat_eaten
	stat_eaten = 0.0
	return e


## GPU 메모리 (바이트): 상태·염료 ×2 (rgba32f) · 압력 ×2 · 발산 · 막힌 칸 (r32f) · 화면용 ×2 (rgba16f) · 방출기 버퍼
func gpu_bytes() -> int:
	return nx * ny * (16 * 4 + 4 * 4 + 8 * 2) + (HEAD + MAX_EMIT * 2) * 16


func steps() -> int:
	if steps_override > 0:
		return steps_override
	return 24 if quality == Quality.LOW else 40


func res_scale() -> int:
	return 1 if quality == Quality.FULL else 2


func _ready() -> void:
	inst = self
	_blasts.clear()
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		return
	RenderingServer.call_on_render_thread(_init_gpu)
	active = _pipe.is_valid() and _s.size() == 2
	if active:
		_fx = FluidSmokeFX.new()
		_fx.smoke_a = _disp
		_fx.smoke_b = _disp2
		_hook_camera()


func _exit_tree() -> void:
	if inst == self:
		inst = null
	_blasts.clear()
	if _rd == null:
		return
	_unhook_camera()
	if _fx:
		_fx.release()
		_fx = null
	RenderingServer.call_on_render_thread(_free_gpu)


## 지금 화면 카메라의 컴포지터에 그리기 효과를 끼운다 (카메라가 바뀌면 옮긴다)
func _hook_camera() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == _cam:
		return
	_unhook_camera()
	_cam = cam
	if cam == null:
		return
	if cam.compositor == null:
		cam.compositor = Compositor.new()
	var list := cam.compositor.compositor_effects
	list.append(_fx)
	cam.compositor.compositor_effects = list


func _unhook_camera() -> void:
	if is_instance_valid(_cam) and _cam.compositor:
		var list := _cam.compositor.compositor_effects
		list.erase(_fx)
		_cam.compositor.compositor_effects = list
	_cam = null


# ── GPU 자원 ────────────────────────────────────────────

func _init_gpu() -> void:
	_shader = FluidSmokeFX.compile(_rd, SOLVER, "FluidSmoke")
	if not _shader.is_valid():
		return
	_pipe = _rd.compute_pipeline_create(_shader)
	for i in 2:
		_s.append(_make_tex(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, 16))
		_d.append(_make_tex(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, 16))
		_p.append(_make_tex(RenderingDevice.DATA_FORMAT_R32_SFLOAT, 4))
	_div = _make_tex(RenderingDevice.DATA_FORMAT_R32_SFLOAT, 4)
	_disp = _make_tex(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, 8)
	_disp2 = _make_tex(RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, 8)
	_obs = _make_tex(RenderingDevice.DATA_FORMAT_R32_SFLOAT, 4, _obstacles())
	var zero := PackedByteArray()
	zero.resize((HEAD + MAX_EMIT * 2) * 16)
	_ebuf = _rd.storage_buffer_create(zero.size(), zero)
	var z4 := PackedByteArray()
	z4.resize(16)
	_stats = _rd.storage_buffer_create(16, z4)
	for s in 2:
		for p in 2:
			_sets[Vector2i(s, p)] = _make_set(s, p)


func _make_tex(fmt: int, bpp: int, data := PackedByteArray()) -> RID:
	var tf := RDTextureFormat.new()
	tf.width = nx
	tf.height = ny
	tf.format = fmt
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	if data.is_empty():
		data.resize(nx * ny * bpp)
	return _rd.texture_create(tf, RDTextureView.new(), [data])


func _image(binding: int, rid: RID) -> RDUniform:
	var un := RDUniform.new()
	un.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	un.binding = binding
	un.add_id(rid)
	return un


func _buffer(binding: int, rid: RID) -> RDUniform:
	var b := RDUniform.new()
	b.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	b.binding = binding
	b.add_id(rid)
	return b


func _make_set(s: int, p: int) -> RID:
	var u: Array[RDUniform] = []
	var rids := [_s[s], _s[1 - s], _p[p], _p[1 - p], _div, _obs, _disp]
	for i in rids.size():
		u.append(_image(i, rids[i]))
	u.append(_buffer(7, _ebuf))
	u.append(_image(8, _d[s]))
	u.append(_image(9, _d[1 - s]))
	u.append(_image(10, _disp2))
	u.append(_buffer(11, _stats))
	return _rd.uniform_set_create(u, _shader, 0)


func _free_gpu() -> void:
	for st in _sets.values():
		if st.is_valid():
			_rd.free_rid(st)
	_sets.clear()
	for r in _s + _d + _p + [_div, _obs, _disp, _disp2, _ebuf, _stats]:
		if r.is_valid():
			_rd.free_rid(r)
	_s.clear()
	_d.clear()
	_p.clear()
	if _pipe.is_valid():
		_rd.free_rid(_pipe)
	if _shader.is_valid():
		_rd.free_rid(_shader)


## 막힌 칸 (벽·기둥·방 밖): 맵의 1m 칸을 격자 해상도로
func _obstacles() -> PackedByteArray:
	var out := PackedFloat32Array()
	out.resize(nx * ny)
	var map: ArenaMap = Main.inst.map if is_instance_valid(Main.inst) else null
	for y in ny:
		for x in nx:
			var w := origin + (Vector2(x, y) + Vector2(0.5, 0.5)) * cell
			var solid := map != null and map.is_blocked_cell(map.cell_of(Vector3(w.x, 0, w.y)))
			out[y * nx + x] = 1.0 if solid else 0.0
	return out.to_byte_array()


## 그리기 효과에 넘길 값 (색은 선형 mat4 의 열 = 스타일, 수치는 vec4 성분 = 스타일)
func _fx_params() -> PackedFloat32Array:
	var f := PackedFloat32Array()
	var sun := Vector3(0.4, 0.8, 0.3)
	if is_instance_valid(Main.inst) and Main.inst.sun:
		sun = Main.inst.sun.global_basis.z
	f.append_array([origin.x, origin.y, size_m().x, size_m().y])
	f.append_array([HMAX, _t, steps(), 3 if quality == Quality.LOW else 5])
	f.append_array([sun.x, sun.y, sun.z, view_mode])
	f.append_array([0, 0, res_scale(), 1 if skip_empty else 0])
	for key in ["lit", "mid", "dark", "line", "glow"]:
		for st in STYLES:
			var c: Color = (st[key] as Color).srgb_to_linear()
			f.append_array([c.r, c.g, c.b, 1.0])
	for key in ["soft", "line_k", "rim", "spec", "glow_k", "alo", "ahi", "lump_spd"]:
		for st in STYLES:
			f.append(st[key])
	var soot := Color(0.30, 0.27, 0.33).srgb_to_linear()
	f.append_array([soot.r, soot.g, soot.b, 1.0])
	return f


# ── 매 프레임 ──────────────────────────────────────────

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var dt := minf(delta, 1.0 / 30.0)
	_t += dt
	_gather(dt)
	if not active or dt <= 0.0:
		cpu_usec = Time.get_ticks_usec() - t0
		return
	_hook_camera()
	# 쉬기: 격자가 비었고(합계 기준) 연기를 넣는 방출기 · 채우기가 한동안 없으면 계산도 그리기도 하지 않는다
	var adds := _pending_fill != 0.0 or emitters.any(func(e): return e[6] > 0.0 or (e[0] == Kind.RADIAL and e[4] > 0.0))
	_busy_t = 0.0 if adds else _busy_t + dt
	idle = stat_count > 0 and stat_all < 0.01 and _busy_t > 0.5 and not _pending_clear
	_fx.enabled = draw and not idle
	_fx.measure = measure_gpu
	_fx.params = _fx_params()
	if gpu_compute and not idle:
		var bytes := _emit_bytes()
		var n := mini(emitters.size(), MAX_EMIT)
		RenderingServer.call_on_render_thread(_step.bind(dt, n, bytes, _pending_clear, _pending_fill))
		_pending_clear = false
		_pending_fill = 0.0
		frames += 1
	cpu_usec = Time.get_ticks_usec() - t0


func _step(dt: float, n: int, bytes: PackedByteArray, wipe: bool, fill_k: float) -> void:
	if wipe:
		var z := PackedByteArray()
		z.resize(nx * ny * 16)
		_rd.texture_update(_s[_s_cur], 0, z)
		_rd.texture_update(_d[_s_cur], 0, z)
	_rd.buffer_update(_ebuf, 0, bytes.size(), bytes)
	var z4 := PackedByteArray()
	z4.resize(16)
	_rd.buffer_update(_stats, 0, 16, z4)
	if measure_gpu:
		_rd.capture_timestamp("fluid_begin")
	_pass(Mode.ADVECT, Vector2i(_s_cur, _p_cur), dt, n, fill_k)
	_s_cur = 1 - _s_cur
	_pass(Mode.VORT, Vector2i(_s_cur, _p_cur), dt, n)
	_s_cur = 1 - _s_cur
	_pass(Mode.DIV, Vector2i(_s_cur, _p_cur), dt, n)
	for i in jacobi:
		_pass(Mode.JACOBI, Vector2i(_s_cur, _p_cur), dt, n)
		_p_cur = 1 - _p_cur
	_pass(Mode.PROJECT, Vector2i(_s_cur, _p_cur), dt, n)
	_s_cur = 1 - _s_cur
	if measure_gpu:
		_rd.capture_timestamp("fluid_end")
	_rd.buffer_get_data_async(_stats, _on_stats)


func _on_stats(data: PackedByteArray) -> void:
	if data.size() < 12:
		return
	stat_eaten += data.decode_u32(0) / FIX
	stat_toxic = data.decode_u32(4) / FIX
	stat_all = data.decode_u32(8) / FIX
	stat_count += 1


func _pass(mode: int, key: Vector2i, dt: float, n: int, extra := 0.0) -> void:
	var pc := PackedFloat32Array([mode, dt, n, _t, nx, ny, cell, VORT, VEL_DAMP, SOOT_DECAY, MAX_SPEED, extra, 0, 0, 0, 0])
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipe)
	_rd.compute_list_bind_uniform_set(cl, _sets[key], 0)
	var b := pc.to_byte_array()
	_rd.compute_list_set_push_constant(cl, b, b.size())
	_rd.compute_list_dispatch(cl, nx / 8, ny / 8, 1)
	_rd.compute_list_end()


## 부하 분석용: 지난번에 찍힌 계산 GPU 시간 (ms, 없으면 -1). measure_gpu 를 켜 둬야 한다.
func compute_gpu_ms() -> float:
	return _span_ms("fluid_begin", "fluid_end")


## 부하 분석용: 지난번 그리기(컴포지터) GPU 시간 (ms, 없으면 -1)
func draw_gpu_ms() -> float:
	return _span_ms("fluid_draw_begin", "fluid_draw_end")


func _span_ms(from: String, to: String) -> float:
	if not active:
		return -1.0
	var out := [-1.0]
	RenderingServer.call_on_render_thread(func():
		var a := -1
		var b := -1
		for i in _rd.get_captured_timestamps_count():
			var nm := _rd.get_captured_timestamp_name(i)
			if nm == from:
				a = i
			elif nm == to:
				b = i
		if a >= 0 and b > a:
			out[0] = (_rd.get_captured_timestamp_gpu_time(b) - _rd.get_captured_timestamp_gpu_time(a)) / 1000000.0)
	return out[0]


## 확인용: 그 자리 전체 밀도 (GPU 에서 화면용 텍스처를 통째로 읽어 온다 — 느리니 검사에서만)
func density_at(p: Vector3, r := 0.0) -> float:
	return _avg_at(_read(_disp), PackedByteArray(), p, r, 3)


## 확인용: 그 자리 스타일 si 의 밀도
func style_at(p: Vector3, si: int, r := 0.0) -> float:
	return _avg_at(_read(_disp), _read(_disp2), p, r, si)


## 확인용: 격자 전체 밀도 합
func total_density() -> float:
	var data := _read(_disp)
	var sum := 0.0
	for i in range(0, data.size(), 8):
		sum += data.decode_half(i + 6)
	return sum


## a = 화면용 A, b 가 있으면 b[ch] × A.밀도 (스타일 밀도), 없으면 A[ch]
func _avg_at(a: PackedByteArray, b: PackedByteArray, p: Vector3, r: float, ch: int) -> float:
	if a.is_empty():
		return 0.0
	var c := to_cell(p)
	var rc := maxf(r / cell, 0.0)
	var sum := 0.0
	var cnt := 0
	for y in range(floori(c.y - rc), floori(c.y + rc) + 1):
		for x in range(floori(c.x - rc), floori(c.x + rc) + 1):
			if x < 0 or y < 0 or x >= nx or y >= ny or Vector2(x, y).distance_to(c) > rc + 0.71:
				continue
			var i := (y * nx + x) * 8
			if b.is_empty():
				sum += a.decode_half(i + ch * 2)
			else:
				sum += b.decode_half(i + ch * 2) * a.decode_half(i + 6)
			cnt += 1
	return sum / maxf(cnt, 1)


func _read(rid: RID) -> PackedByteArray:
	if not active:
		return PackedByteArray()
	var out := [PackedByteArray()]
	RenderingServer.call_on_render_thread(func(): out[0] = _rd.texture_get_data(rid, 0))
	return out[0]


# ── 방출기 모으기 ───────────────────────────────────────

## ch = 연기를 넣을 스타일 채널 (밀도 추가가 있는 방출기만 쓴다)
func _emit(kind: int, at: Vector3, r: float, a := 0.0, b := 0.0, c := 0.0, d := 0.0, ch := 1) -> void:
	if emitters.size() >= MAX_EMIT:
		return
	emitters.append([kind, to_cell(at), r / cell, a, b, c, d, ch])


## 다른 모듈이 이번 프레임에 방출기를 넣는다 (매 프레임 다시 넣어야 한다)
func push_emitter(kind: int, at: Vector3, r: float, a := 0.0, b := 0.0, c := 0.0, d := 0.0, ch := 1) -> void:
	extra_emitters.append([kind, at, r, a, b, c, d, ch])


func _emit_bytes() -> PackedByteArray:
	var f := PackedFloat32Array()
	f.resize((HEAD + MAX_EMIT * 2) * 4)
	# 머리: 스타일 값 (높이 · 결 세기 · 결 속도 · 감쇠)
	var keys := ["height", "lump", "lump_spd", "decay"]
	for k in keys.size():
		for si in 4:
			f[k * 4 + si] = STYLES[si][keys[k]]
	for i in mini(emitters.size(), MAX_EMIT):
		var e: Array = emitters[i]
		var cp: Vector2 = e[1]
		var o := HEAD * 4 + i * 8
		f[o + 0] = cp.x
		f[o + 1] = cp.y
		f[o + 2] = e[2]
		f[o + 3] = e[0] + 8 * e[7]
		f[o + 4] = e[3]
		f[o + 5] = e[4]
		f[o + 6] = e[5]
		f[o + 7] = e[6]
	return f.to_byte_array()


## PUSH(a, b = 목표 속도 x, z · c = 초당 따라잡기 · d = 초당 밀도 추가 → 채널 ch)
## RADIAL(a = 바깥 속력(음수 = 빨아들임) · b = 그을음 추가 · c = 가운데 먹어 치우기(모든 채널) · d = 밀도 추가 → 채널 ch)
## PART(a, b = 진행 방향(단위) · c = 길 양옆으로 밀어내는 속력) — 몸이 지나가며 연기를 가른다
## SWIRL(a = 접선 속력(음수 = 휠윈드와 같은 쪽, yaw + 방향) · b = 바깥 속력 · c = 초당 따라잡기)
func _gather(dt: float) -> void:
	emitters.clear()
	var main: Main = Main.inst if is_instance_valid(Main.inst) else null
	var player: Player = main.player if main else null
	# 다른 모듈이 넣은 방출기 (독가스 구름 생성 · 안개 둑 · 정화 마무리)
	for e in extra_emitters:
		_emit(e[0], e[1], e[2], e[3], e[4], e[5], e[6], e[7])
	extra_emitters.clear()
	# 폭발 바람 (짧게 이어진다)
	var keep: Array = []
	for bl in _blasts:
		bl.age += dt
		if bl.age > BLAST_LIFE:
			continue
		var k: float = 1.0 - bl.age / BLAST_LIFE
		var grow: float = lerpf(0.55, 1.0, sqrt(bl.age / BLAST_LIFE))
		_emit(Kind.RADIAL, bl.pos, bl.r * grow, bl.speed * k, bl.soot * 2.4 * k * k, 0.0, 0.0)
		keep.append(bl)
	_blasts = keep
	# 통풍구: 숨쉬듯 세기가 오르내리며 제 스타일의 연기를 뿜는다
	if vents_on and not vents.is_empty():
		for i in vents.size():
			var v: Dictionary = vents[i]
			var si := vent_style(i)
			var st: Dictionary = STYLES[si]
			var puff := 0.7 + 0.3 * sin(_t * 2.3 + i * 1.7) + 0.25 * sin(_t * 5.1 + i * 3.1)
			var wob := Vector3(sin(_t * 1.3 + i), 0, cos(_t * 1.1 + i * 2.0)) * 0.25
			_emit(Kind.RADIAL, v.pos + wob, v.r, st.push * puff, 0.0, 0.0, st.rate * puff, si)
			# 통풍구마다 느린 소용돌이 (번갈아 반대) → 소용돌이 보강이 말려 오르는 연기 결을 만든다
			_emit(Kind.SWIRL, v.pos, v.r * 2.6, 2.2 * (1.0 if i % 2 == 0 else -1.0), 0.6, 1.5)
		# 방 전체의 느린 외풍: 연기가 한자리에 고이지 않고 천천히 떠돈다
		var wa := _t * 0.11
		var c := origin + size_m() * 0.5
		_emit(Kind.PUSH, Vector3(c.x, 0, c.y), size_m().length() * 0.5, cos(wa) * 0.7, sin(wa * 1.3) * 0.7, 0.25, 0.0)
	if player == null or not player.alive:
		return
	var pp := player.global_position
	var pv := Vector3.ZERO
	if _body_prev != Vector3.INF:
		pv = (pp - _body_prev) / maxf(dt, 1e-4)
		pv.y = 0
		if pv.length() > 60.0:      # 순간이동 · 재배치
			pv = Vector3.ZERO
	_body_prev = pp
	# 몸: 지나가는 자리의 공기를 몸 속도로 끌고 가며 옆으로 밀어낸다 (대시면 연기가 확 갈라진다)
	var spd := pv.length()
	_emit(Kind.PUSH, pp, 1.0, pv.x * 0.4, pv.z * 0.4, 10.0 if spd > 1.0 else 4.0, 0.0)
	if spd > 1.5:
		var m := pv / spd
		_emit(Kind.PART, pp - m * 0.3, 1.1 + minf(spd * 0.04, 0.7), m.x, m.z, minf(spd * 0.75, 16.0), 0.0)
	# 광선검: 칼끝·칼 가운데가 휘두르는 속도로 공기를 가른다
	if player.trail and is_instance_valid(player.trail.blade) and player.trail.blade.is_visible_in_tree():
		var bl: Node3D = player.trail.blade
		var tip := bl.to_global(player.trail.p_tip)
		var mid := bl.to_global((player.trail.p_tip + player.trail.p_base) * 0.5)
		for pair in [[tip, _tip_prev], [mid, _mid_prev]]:
			var now: Vector3 = pair[0]
			var was: Vector3 = pair[1]
			if was != Vector3.INF and now.y < pp.y + 2.4:
				var v := (now - was) / maxf(dt, 1e-4)
				v.y = 0
				if v.length() > 3.0:
					_emit(Kind.PUSH, now, 0.75, v.x * 0.8, v.z * 0.8, 30.0, 0.0)
		_tip_prev = tip
		_mid_prev = mid
	else:
		_tip_prev = Vector3.INF
		_mid_prev = Vector3.INF
	# 2단 대시 휠윈드: 몸 둘레로 감기며 바깥으로 흩뿌린다
	if player.whirl and player.whirl.active():
		_emit(Kind.SWIRL, pp, 3.4, -15.0, 2.5, 9.0)
	# 드론 합체 휠윈드: 더 크고 세게, 몬스터를 끌어들이듯 안쪽으로 감긴다
	var drone := PartnerDrone.inst
	if is_instance_valid(drone) and drone.whirl_t >= 0.0:
		_emit(Kind.SWIRL, pp, 4.2, -19.0, -3.5, 10.0)
	# 청소 질주: 둘레의 연기를 빨아들여 몸에서 먹어 치운다
	if is_instance_valid(drone) and drone.sweeping:
		var core := drone.sweep_core.global_position if is_instance_valid(drone.sweep_core) else pp
		_emit(Kind.RADIAL, core, PartnerDrone.SWEEP_R + 0.5, -10.0, 0.0, 14.0, 0.0)
	# Z 직접 청소: 앞쪽 노즐로 빨아들인다 (질주보다 좁고 약하게)
	elif is_instance_valid(drone) and drone.p_cleaning:
		var front := pp + player.aim_dir * 1.4
		_emit(Kind.RADIAL, front, PartnerDrone.PLAYER_CLEAN_RANGE, -7.0, 0.0, 10.0, 0.0)
	# 적 몸
	var seen := {}
	for e in Enemy.live(get_tree()):
		if not is_instance_valid(e):
			continue
		var en := e as Enemy
		if en == null or not en.alive:
			continue
		var id := en.get_instance_id()
		seen[id] = true
		var p := en.global_position
		var v := Vector3.ZERO
		if _prev.has(id):
			v = (p - _prev[id]) / maxf(dt, 1e-4)
			v.y = 0
		_prev[id] = p
		if v.length() > 0.6 and covers(p):
			_emit(Kind.PUSH, p, 0.85, v.x, v.z, 12.0, 0.0)
	for id in _prev.keys():
		if not seen.has(id):
			_prev.erase(id)


# ── 셰이더 ─────────────────────────────────────────────

const SOLVER := """#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0, rgba32f) uniform restrict readonly image2D s_in;
layout(set = 0, binding = 1, rgba32f) uniform restrict writeonly image2D s_out;
layout(set = 0, binding = 2, r32f) uniform restrict readonly image2D p_in;
layout(set = 0, binding = 3, r32f) uniform restrict writeonly image2D p_out;
layout(set = 0, binding = 4, r32f) uniform restrict image2D div_img;
layout(set = 0, binding = 5, r32f) uniform restrict readonly image2D obs;
layout(set = 0, binding = 6, rgba16f) uniform restrict writeonly image2D disp;
layout(set = 0, binding = 7, std430) restrict readonly buffer Emit { vec4 e[]; } em;
layout(set = 0, binding = 8, rgba32f) uniform restrict readonly image2D d_in;
layout(set = 0, binding = 9, rgba32f) uniform restrict writeonly image2D d_out;
layout(set = 0, binding = 10, rgba16f) uniform restrict writeonly image2D disp2;
layout(set = 0, binding = 11, std430) buffer Stats { uint v[4]; } st;
layout(push_constant, std430) uniform Params { vec4 a; vec4 b; vec4 c; vec4 d; } pc;

shared float sh_eat[64];
shared float sh_tox[64];
shared float sh_all[64];

ivec2 N() { return ivec2(pc.b.xy); }
bool solid(ivec2 q) {
	if (q.x < 0 || q.y < 0 || q.x >= N().x || q.y >= N().y) return true;
	return imageLoad(obs, q).r > 0.5;
}
vec4 S(ivec2 q) { return imageLoad(s_in, clamp(q, ivec2(0), N() - 1)); }
vec4 D(ivec2 q) { return imageLoad(d_in, clamp(q, ivec2(0), N() - 1)); }
vec2 V(ivec2 q) { return solid(q) ? vec2(0.0) : S(q).xy; }
vec4 sampleS(vec2 p) {
	p = clamp(p, vec2(0.0), vec2(N() - 1));
	ivec2 i = ivec2(floor(p));
	vec2 f = p - vec2(i);
	ivec2 j = min(i + 1, N() - 1);
	return mix(mix(S(i), S(ivec2(j.x, i.y)), f.x), mix(S(ivec2(i.x, j.y)), S(j), f.x), f.y);
}
// 염료 쌍선형 — 벽 칸은 빼고 무게를 다시 맞춘다 (벽 가까이서 연기가 0 과 섞여 줄어들지 않게)
vec4 sampleD(vec2 p) {
	p = clamp(p, vec2(0.0), vec2(N() - 1));
	ivec2 i = ivec2(floor(p));
	vec2 f = p - vec2(i);
	ivec2 j = min(i + 1, N() - 1);
	ivec2 q[4] = ivec2[4](i, ivec2(j.x, i.y), ivec2(i.x, j.y), j);
	float w[4] = float[4]((1.0 - f.x) * (1.0 - f.y), f.x * (1.0 - f.y), (1.0 - f.x) * f.y, f.x * f.y);
	vec4 sum = vec4(0.0);
	float ws = 0.0;
	for (int k = 0; k < 4; k++) {
		if (solid(q[k])) continue;
		sum += D(q[k]) * w[k];
		ws += w[k];
	}
	return ws > 1e-4 ? sum / ws : vec4(0.0);
}
float curl(ivec2 q) {
	return 0.5 * ((V(q + ivec2(1, 0)).y - V(q - ivec2(1, 0)).y) - (V(q + ivec2(0, 1)).x - V(q - ivec2(0, 1)).x));
}
float P(ivec2 q, float self) { return solid(q) ? self : imageLoad(p_in, clamp(q, ivec2(0), N() - 1)).r; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void main() {
	ivec2 c = ivec2(gl_GlobalInvocationID.xy);
	if (c.x >= N().x || c.y >= N().y) return;
	int mode = int(pc.a.x);
	float dt = pc.a.y;
	float h = pc.b.z;
	vec4 H_height = em.e[0];
	vec4 H_lump = em.e[1];
	vec4 H_lspd = em.e[2];
	vec4 H_decay = em.e[3];
	if (mode == 0) {
		// 이동: 속도를 거슬러 올라간 자리의 값을 가져온다 (상태 · 염료 함께)
		vec4 s = S(c);
		vec2 back = vec2(c) - dt * s.xy / h;
		vec4 o = sampleS(back);
		vec4 g = sampleD(back);
		o.xy *= exp(-dt * pc.c.x);
		o.w *= exp(-dt * pc.c.y);
		g *= exp(-dt * H_decay);
		// 압축·팽창 (∂ρ/∂t = -ρ∇·v): 거슬러 가져오기만으로는 고른 연기가 퍼지는 바람에도 고른 채로 남는다.
		// 압력을 뺀 뒤 넣은 폭발·가르기·흡입 흐름에만 발산이 있어서, 그 자리 연기가 비고 둘레에 쌓인다.
		float dv = 0.5 * ((V(c + ivec2(1, 0)).x - V(c - ivec2(1, 0)).x) + (V(c + ivec2(0, 1)).y - V(c - ivec2(0, 1)).y)) / h;
		// 압력 반복이 못다 지운 작은 발산은 빼고 (그대로 두면 가만히 있는 독가스가 저절로 불거나 준다)
		dv = sign(dv) * max(abs(dv) - 1.2, 0.0);
		float ex = exp(-clamp(dv * dt, -0.35, 0.6));
		o.w *= ex;
		g *= ex;
		// 아주 약한 확산: 갈라진 자리가 천천히 메워진다
		// 벽 칸은 빼고 평균 (벽으로 새어 나가 독가스가 저절로 줄지 않게)
		float kd = clamp(0.9 * dt, 0.0, 1.0);
		vec4 gn = vec4(0.0);
		float wn = 0.0;
		float on = 0.0;
		ivec2 nb4[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
		for (int k = 0; k < 4; k++) {
			ivec2 q = c + nb4[k];
			if (solid(q)) continue;
			gn += D(q);
			on += S(q).w;
			wn += 1.0;
		}
		if (wn > 0.0) {
			o.w = mix(o.w, on / wn, kd);
			g = mix(g, gn / wn, kd);
		}
		// 채우기 (확인용): 크기 = 양, 10 단위 = 고정 스타일 + 1 (0 = 격자를 넷으로 나눠 스타일 0~3), 부호 = 결/고르게
		if (pc.c.w != 0.0) {
			float fk = abs(pc.c.w);
			int fs = int(floor(fk / 10.0)) - 1;
			float amt = fk - 10.0 * float(fs + 1);
			int ch = fs >= 0 ? fs : (c.x >= N().x / 2 ? 1 : 0) + (c.y >= N().y / 2 ? 2 : 0);
			float add = amt;
			if (pc.c.w > 0.0) {
				vec2 q = vec2(c) / 13.0 + pc.a.w * 3.1;
				float cl = vnoise(q) * 0.65 + vnoise(q * 2.3 + 7.0) * 0.35;
				add = amt * smoothstep(0.25, 0.75, cl) * 1.6;
			}
			g[ch] += add;
		}
		o.z = 0.0;
		if (solid(c)) { o = vec4(0.0); g = vec4(0.0); }
		imageStore(s_out, c, o);
		imageStore(d_out, c, g);
	} else if (mode == 1) {
		// 소용돌이 보강: 수치 확산으로 뭉개지는 작은 회오리를 되살린다 (염료는 그대로 넘긴다)
		vec4 s = S(c);
		if (!solid(c)) {
			float w = curl(c);
			vec2 g = 0.5 * vec2(abs(curl(c + ivec2(1, 0))) - abs(curl(c - ivec2(1, 0))), abs(curl(c + ivec2(0, 1))) - abs(curl(c - ivec2(0, 1))));
			float gl = length(g);
			if (gl > 1e-5) s.xy += pc.b.w * vec2(g.y, -g.x) / gl * w * dt;
		}
		imageStore(s_out, c, s);
		imageStore(d_out, c, D(c));
	} else if (mode == 2) {
		float dv = 0.5 * ((V(c + ivec2(1, 0)).x - V(c - ivec2(1, 0)).x) + (V(c + ivec2(0, 1)).y - V(c - ivec2(0, 1)).y));
		imageStore(div_img, c, vec4(dv));
	} else if (mode == 3) {
		float self = imageLoad(p_in, c).r;
		float p = (P(c + ivec2(1, 0), self) + P(c - ivec2(1, 0), self) + P(c + ivec2(0, 1), self) + P(c - ivec2(0, 1), self) - imageLoad(div_img, c).r) * 0.25;
		imageStore(p_out, c, vec4(solid(c) ? 0.0 : p));
	} else {
		// 압력 빼기 → 방출기 (퍼지고 빨아들이는 흐름은 여기서 넣어야 이번 이동까지 살아남는다)
		vec4 o = S(c);
		vec4 g = D(c);
		float eaten = 0.0;
		float self = imageLoad(p_in, c).r;
		o.xy -= 0.5 * vec2(P(c + ivec2(1, 0), self) - P(c - ivec2(1, 0), self), P(c + ivec2(0, 1), self) - P(c - ivec2(0, 1), self));
		int n = int(pc.a.z);
		for (int k = 0; k < n; k++) {
			vec4 A = em.e[4 + k * 2];
			vec4 B = em.e[4 + k * 2 + 1];
			vec2 d = vec2(c) - A.xy;
			float l = length(d);
			if (l >= A.z) continue;
			float u = 1.0 - l / A.z;
			float w = u * u * (3.0 - 2.0 * u);
			vec2 dir = l > 1e-4 ? d / l : vec2(0.0);
			int code = int(A.w + 0.5);
			int kind = code % 8;
			int ch = clamp(code / 8, 0, 3);
			if (kind == 0) {
				o.xy = mix(o.xy, B.xy, clamp(w * B.z * dt, 0.0, 1.0));
				g[ch] += B.w * w * dt;
			} else if (kind == 1) {
				float want = B.x * u;
				float now = dot(o.xy, dir);
				if (B.x > 0.0) o.xy += dir * max(0.0, want - now);
				else o.xy += dir * min(0.0, want - now);
				g[ch] += B.w * w * dt;
				o.w += B.y * w * dt;
				if (B.z > 0.0) {
					float core = clamp(1.6 - 1.6 * l / max(A.z * 0.5, 1.0), 0.0, 1.0);
					float keep = max(0.0, 1.0 - B.z * dt * core);
					eaten += g[2] * (1.0 - keep);
					g *= keep;
					o.w *= keep;
				}
			} else if (kind == 2) {
				vec2 tgt = vec2(-dir.y, dir.x) * B.x + dir * B.y;
				o.xy = mix(o.xy, tgt * u, clamp(w * B.z * dt, 0.0, 1.0));
			} else {
				// 길 양옆으로: 진행 방향에 수직인 바깥쪽
				vec2 m = B.xy;
				vec2 perp = d - m * dot(d, m);
				float pl = length(perp);
				vec2 side = pl > 1e-3 ? perp / pl : vec2(-m.y, m.x) * (hash(vec2(c)) > 0.5 ? 1.0 : -1.0);
				float want = B.z * (0.35 + 0.65 * u);
				o.xy += side * max(0.0, want - dot(o.xy, side));
			}
		}
		float sp = length(o.xy);
		if (sp > pc.c.z) o.xy *= pc.c.z / sp;
		g = max(g, vec4(0.0));
		o.w = max(o.w, 0.0);
		float tot = dot(g, vec4(1.0)) + o.w;
		if (tot > 3.0) { g *= 3.0 / tot; o.w *= 3.0 / tot; tot = 3.0; }
		if (solid(c)) { o = vec4(0.0); g = vec4(0.0); tot = 0.0; }
		o.z = 0.0;
		imageStore(s_out, c, o);
		imageStore(d_out, c, g);
		// 화면용으로 미리 굽기: A = 행진 중 읽는 값 (높이 단면, 결 세기, 결 속도, 밀도) · B = 닿은 곳 색칠용 스타일 비율
		vec4 wts = tot > 1e-4 ? g / tot : vec4(0.0);
		float soot = tot > 1e-4 ? o.w / tot : 0.0;
		float hk = dot(wts, H_height) + soot * 0.85;
		float lk = (dot(wts, H_lump) + soot * 0.3) * smoothstep(0.1, 0.7, tot);
		float ls = dot(wts, H_lspd) + soot;
		imageStore(disp, c, vec4(hk * sqrt(smoothstep(0.03, 1.25, tot)), lk, ls, tot));
		imageStore(disp2, c, wts);
		// 합계: 빨아 먹은 독가스 · 남은 독가스 · 전체 밀도 (작업 묶음마다 합쳐 한 번만 더한다)
		uint li = gl_LocalInvocationIndex;
		sh_eat[li] = eaten;
		sh_tox[li] = g[2];
		sh_all[li] = tot;
		barrier();
		for (uint s2 = 32u; s2 > 0u; s2 >>= 1u) {
			if (li < s2) {
				sh_eat[li] += sh_eat[li + s2];
				sh_tox[li] += sh_tox[li + s2];
				sh_all[li] += sh_all[li + s2];
			}
			barrier();
		}
		if (li == 0u) {
			atomicAdd(st.v[0], uint(sh_eat[0] * 1000.0 + 0.5));
			atomicAdd(st.v[1], uint(sh_tox[0] * 1000.0 + 0.5));
			atomicAdd(st.v[2], uint(sh_all[0] * 1000.0 + 0.5));
		}
	}
}
"""
