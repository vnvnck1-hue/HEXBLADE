class_name FluidField
extends Node
## 유체 연기(FluidSmoke)를 씬에 까는 관리자 + 기체 청소 기믹. [docs/fluid-smoke.md]
## Main._ready 의 attach 한 줄로 Main 계열 씬 전부에 붙는다 (보스 전장 · 쇼케이스는 제외).
##
## 쓰임새 (씬마다):
##  - field (방 탐색 · 섹터 런 · 그 밖의 Main 계열): 전투방이 열릴 때 가끔 —
##      안개 둑 MIST_CHANCE: 한동안 옅은 안개를 뿜다 그친다. 청소 대상 아님 (빨려도 게이지 없음).
##      독가스 세트 TOXIC_CHANCE: 구름 2~3개를 한 번만 만든다(계속 뿜지 않음). 독가스는 감쇠가 없어
##      Space 청소 질주 · Z 직접 청소로 빨아들여야 사라지고, 세트를 다 빨아들이면 정화 완료 = 다른 오염처럼 청소 1회.
##  - training (허수아비 시험장 · 드론 시험장): 안개 둑 하나(계속) + 독가스 세트 하나 (정화하면 잠시 뒤 다시 생김)
##  - lab (유체 연기 시험장): 아무것도 만들지 않는다 (시험장이 통풍구를 단다)
##
## 기체 청소 = 도트 다단 흡수: GPU 가 매 프레임 빨아 먹은 독가스 양을 합쳐 보내면, 세트 값(VALUE_PER_CLOUD × 구름 수)을
## 그 비율만큼 쌓아 두었다가 TICK 간격으로 1씩 게이지에 넣는다 — 숫자 "+1" 이 연달아 튀고 '틱' 소리가 점점 높아진다.
## 실행 인자: --gas=always (전투방마다 둘 다) · --gas=off (안 만듦) · --fluid=off (유체 연기 자체를 끔)

const TOXIC_CHANCE := 0.3
const MIST_CHANCE := 0.12
const VALUE_PER_CLOUD := 14.0      # 구름 하나를 다 빨아들이면 받는 지원 게이지 (보통 오염 하나 ≈ 12~36)
const CLOUD_R := 1.8               # 독가스 구름 반경 (m)
const CLOUD_RATE := 9.0            # 생성 중 초당 밀도
const FORM_T := 0.55               # 구름을 만드는 시간
const SETTLE_T := 0.35             # 만든 뒤 양을 재기까지 기다림 (GPU 합계가 몇 프레임 늦게 온다)
const CLEAR_LEFT := 0.07           # 이만큼 남으면 정화 완료 (나머지는 터뜨려 지운다)
const TICK := 0.05                 # 도트 한 번 간격 (초)
const MIST_LIFE := 26.0
const RESPAWN_T := 6.0             # 시험장: 정화 뒤 다시 생기기까지
const TOXIC_COL := Color(0.62, 1.0, 0.35)
const EXCLUDE := ["boss_main.gd", "forge_main.gd", "abyss_main.gd", "spider_main.gd", "mammoth_b_lab.gd"]

enum St { WAIT, FORMING, SETTLE, ACTIVE, CLEARED }

static var inst: FluidField

var main: Main
var smoke: FluidSmoke
var mode := "field"
var gas := "auto"                  # auto · always · off
var sets: Array = []               # {clouds: [{pos, light}], state, t, m0, eaten, value, paid, base}
var banks: Array = []              # {pos, t, life}
var ticks := 0                     ## 확인용: 지금까지 게이지에 넣은 도트 횟수
var paid := 0.0                    ## 확인용: 지금까지 도트로 넣은 게이지 합
var cleared := 0                   ## 정화한 세트 수
var _seen := {}
var _poll := 0.0
var _rng := RandomNumberGenerator.new()
var _acc := 0.0                    # 아직 넣지 않은 게이지
var _tick_t := 0.0
var _chain := 0
var _chain_t := 0.0
var _chain_sum := 0
var _dot_at := Vector3.ZERO
var _respawn := -1.0
var _poofs: Array = []             # {pos, t}
var _first_mist := false


static func attach(m: Main) -> FluidField:
	if m.showcase or Main.cmd_args.has("--fluid=off"):
		return null
	var path: String = m.get_script().resource_path
	for ex in EXCLUDE:
		if path.ends_with(ex):
			return null
	var f := FluidField.new()
	f.name = "FluidField"
	f.main = m
	m.add_child(f)
	return f


func _ready() -> void:
	inst = self
	for a in Main.cmd_args:
		if a.begins_with("--gas="):
			gas = a.substr(6)
	if main.has_method("fluid_mode"):
		mode = main.call("fluid_mode")
	elif main is TrainingMain:
		mode = "training"
	_rng.seed = hash([main.map_seed, "fluid"]) if main.map_seed >= 0 else randi()
	_build_grid()
	# 시험장 배치는 첫 프레임에 (attach 는 Main._ready 도중이라 시험장 가운데가 아직 정해지지 않았다)
	if mode == "training" and gas != "off":
		_respawn = 0.0
		_first_mist = true


func _exit_tree() -> void:
	if inst == self:
		inst = null


## 격자: 맵의 방들을 다 덮는 직사각형 (칸 크기는 긴 변이 384칸 안쪽이 되게)
func _build_grid() -> void:
	var map := main.map
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	if map and not map.rooms.is_empty():
		for r in map.rooms:
			for c in r.cells:
				var w := map.world_of(c)
				lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
				hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
	if lo.x == INF:
		lo = Vector2(-16, -16)
		hi = Vector2(16, 16)
	lo -= Vector2(2.5, 2.5)
	hi += Vector2(2.5, 2.5)
	var size := hi - lo
	var cell := clampf(maxf(size.x, size.y) / 384.0, 0.2, 0.5)
	var center := Vector3((lo.x + hi.x) * 0.5, 0, (lo.y + hi.y) * 0.5)
	smoke = FluidSmoke.attach(main.world, center, size, cell)


# ── 만들기 ─────────────────────────────────────────────

## 안개 둑: life 초 동안 옅은 안개를 뿜는다 (INF = 계속)
func add_mist(pos: Vector3, life := MIST_LIFE) -> void:
	banks.append({"pos": pos, "t": 0.0, "life": life})


## 독가스 세트: 자리마다 구름 하나 (한 번만 만든다)
func add_toxic(spots: Array) -> Dictionary:
	var clouds: Array = []
	for p in spots:
		var lt := OmniLight3D.new()
		lt.light_color = FluidSmoke.STYLES[FluidSmoke.Ch.TOXIC].glow
		lt.light_energy = 0.0
		lt.omni_range = 4.5
		lt.shadow_enabled = false
		main.world.add_child(lt)
		lt.global_position = p + Vector3(0, 0.7, 0)
		clouds.append({"pos": p, "light": lt})
	var s := {"clouds": clouds, "state": St.WAIT, "t": 0.0, "m0": 0.0, "eaten": 0.0, "value": VALUE_PER_CLOUD * spots.size(), "paid": 0.0, "base": 0.0}
	sets.append(s)
	return s


## 시험장 독가스 세트 자리 (오른쪽 아래)
func training_spots() -> Array:
	var c: Vector3 = (main as TrainingMain).center
	return [c + Vector3(7.5, 0, 3.5), c + Vector3(10.0, 0, 1.2), c + Vector3(9.8, 0, 5.4)]


func active_sets() -> Array:
	return sets.filter(func(s): return s.state == St.ACTIVE or s.state == St.SETTLE or s.state == St.FORMING)


## 세트의 남은 몫 0~1 (GPU 합계로 흐름 손실을 보정)
func left(s: Dictionary) -> float:
	if s.m0 <= 0.0:
		return 1.0
	var own: float = maxf(s.m0 - s.eaten, 0.0)
	var sum := 0.0
	for o in sets:
		if o.state == St.ACTIVE:
			sum += maxf(o.m0 - o.eaten, 0.0)
	var k := 1.0
	if smoke.active and sum > 0.01 and s.state == St.ACTIVE:
		k = clampf(smoke.stat_toxic / sum, 0.3, 1.3)
	return clampf(own * k / s.m0, 0.0, 1.0)


## 전투방 안 빈 바닥 자리 (맵 rng 를 건드리지 않게 따로 고른다)
func _spot(id: int, near := Vector3.INF, rmin := 0.0, rmax := INF) -> Vector3:
	var map := main.map
	var cells: Array = map.rooms[id].cells
	for tries in 80:
		var c: Vector2i = cells[_rng.randi_range(0, cells.size() - 1)]
		var ok := true
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if map.is_blocked_cell(c + Vector2i(dx, dy)):
					ok = false
		if not ok:
			continue
		var p := map.world_of(c)
		if near != Vector3.INF and tries < 60:
			# 거리 조건은 앞 60번만 (못 찾으면 방 안 아무 빈 바닥)
			var d := Vector2(p.x - near.x, p.z - near.z).length()
			if d < rmin or d > rmax:
				continue
		return p
	return Vector3.INF


func _on_room(id: int) -> void:
	if gas == "off":
		return
	var always := gas == "always"
	var pp := main.player.global_position
	if always or _rng.randf() < TOXIC_CHANCE:
		var first := _spot(id, pp, 5.0, 16.0)
		if first != Vector3.INF:
			var spots := [first]
			var n := _rng.randi_range(2, 3)
			for i in 12:
				if spots.size() >= n:
					break
				var p := _spot(id, first, 2.4, 4.6)
				if p != Vector3.INF and spots.all(func(q): return q.distance_to(p) > 2.2):
					spots.append(p)
			add_toxic(spots)
	if always or _rng.randf() < MIST_CHANCE:
		var mp := _spot(id, pp, 3.0, 20.0)
		if mp != Vector3.INF:
			add_mist(mp)


# ── 매 프레임 ──────────────────────────────────────────

func _process(dt: float) -> void:
	if not is_instance_valid(smoke):
		return
	if mode == "field":
		_poll -= dt
		if _poll <= 0.0 and main.map:
			_poll = 0.25
			for r in main.map.rooms:
				if r.combat and r.state != "idle" and not _seen.has(r.id):
					_seen[r.id] = true
					_on_room(r.id)
	_update_banks(dt)
	_update_sets(dt)
	_update_dot(dt)
	if mode == "training" and _respawn >= 0.0:
		_respawn -= dt
		if _respawn < 0.0:
			var c: Vector3 = (main as TrainingMain).center
			if _first_mist:
				_first_mist = false
				add_mist(c + Vector3(-9.5, 0, -5.5), INF)
			add_toxic(training_spots())


func _update_banks(dt: float) -> void:
	var keep: Array = []
	for b in banks:
		b.t += dt
		if b.t > b.life:
			continue
		var k := smoothstep(0.0, 2.0, b.t)
		if b.life < INF:
			k *= 1.0 - smoothstep(b.life - 4.0, b.life, b.t)
		var wob := Vector3(sin(b.t * 0.7), 0, cos(b.t * 0.53)) * 1.2
		var st: Dictionary = FluidSmoke.STYLES[FluidSmoke.Ch.MIST]
		smoke.push_emitter(FluidSmoke.Kind.RADIAL, b.pos + wob, 1.6, st.push * k, 0.0, 0.0, 2.6 * k, FluidSmoke.Ch.MIST)
		smoke.push_emitter(FluidSmoke.Kind.SWIRL, b.pos, 3.5, 1.4, 0.4, 1.0)
		keep.append(b)
	banks = keep


func _update_sets(dt: float) -> void:
	# 한 번에 한 세트만 만든다 (양을 잴 때 섞이지 않게)
	var forming := sets.any(func(s): return s.state == St.FORMING or s.state == St.SETTLE)
	for s in sets:
		match s.state:
			St.WAIT:
				if not forming:
					forming = true
					s.state = St.FORMING
					s.t = 0.0
					s.base = smoke.stat_toxic
					FX.ring(s.clouds[0].pos + Vector3(0, 0.1, 0), 3.0, [TOXIC_COL, Color(0.35, 0.8, 0.3), Color(0.15, 0.4, 0.2)] as Array[Color], 0.5)
					if is_instance_valid(main.hud):
						main.hud.popup("독가스 누출", TOXIC_COL, s.clouds[0].pos + Vector3(0, 2.2, 0))
			St.FORMING:
				s.t += dt
				for c in s.clouds:
					smoke.push_emitter(FluidSmoke.Kind.RADIAL, c.pos, CLOUD_R, 0.4, 0.0, 0.0, CLOUD_RATE, FluidSmoke.Ch.TOXIC)
				if s.t >= FORM_T:
					s.state = St.SETTLE
					s.t = 0.0
			St.SETTLE:
				s.t += dt
				if s.t >= SETTLE_T:
					s.state = St.ACTIVE
					# 만든 양: GPU 합계의 늘어난 몫 (헤드리스면 대략값)
					var est: float = CLOUD_RATE * FORM_T * PI * pow(CLOUD_R / smoke.cell, 2) * 0.3 * s.clouds.size()
					s.m0 = maxf(smoke.stat_toxic - s.base, est * 0.2) if smoke.active and smoke.stat_count > 0 else est
			St.ACTIVE:
				var l := left(s)
				for c in s.clouds:
					var lt: OmniLight3D = c.light
					if is_instance_valid(lt):
						lt.light_energy = lerpf(lt.light_energy, 0.9 * sqrt(l), 1.0 - exp(-4.0 * dt))
				if l < CLEAR_LEFT:
					_clear(s)
	# 정화 마무리: 남은 찌꺼기를 터뜨려 지운다
	var keep: Array = []
	for p in _poofs:
		p.t += dt
		if p.t < 0.45:
			smoke.push_emitter(FluidSmoke.Kind.RADIAL, p.pos, CLOUD_R * 1.7, 0.0, 0.0, 18.0, 0.0)
			keep.append(p)
	_poofs = keep
	if not _poofs.is_empty():
		smoke.consume_eaten()       # 마무리로 지운 양은 게이지로 치지 않는다
	# 빨아 먹은 양 → 가장 가까운 활성 세트 → 도트로 쌓기
	var e := smoke.consume_eaten()
	if e > 0.0:
		var s := _nearest_active()
		if not s.is_empty() and s.m0 > 0.0:
			var take: float = minf(e, maxf(s.m0 - s.eaten, 0.0))
			s.eaten += take
			var gain: float = take / s.m0 * s.value
			gain = minf(gain, s.value - s.paid)
			s.paid += gain
			_acc += gain
			_dot_at = main.player.global_position + Vector3(0, 1.4, 0)


func _nearest_active() -> Dictionary:
	var pp := main.player.global_position
	var best := {}
	var bd := INF
	for s in sets:
		if s.state != St.ACTIVE:
			continue
		for c in s.clouds:
			var d: float = (c.pos as Vector3).distance_to(pp)
			if d < bd:
				bd = d
				best = s
	return best


func _clear(s: Dictionary) -> void:
	s.state = St.CLEARED
	cleared += 1
	# 남은 몫은 마지막 도트로 마저 넣는다 (세트 값 전부)
	var rest: float = maxf(s.value - s.paid, 0.0)
	s.paid = s.value
	_acc += rest
	for c in s.clouds:
		_poofs.append({"pos": c.pos, "t": 0.0})
		var lt: OmniLight3D = c.light
		if is_instance_valid(lt):
			var tw := lt.create_tween()
			tw.tween_property(lt, "light_energy", 0.0, 0.6)
			tw.tween_callback(lt.queue_free)
		DroneFX.twinkle(c.pos + Vector3(0, 0.6, 0), 1.2)
	var mid: Vector3 = s.clouds[0].pos
	FX.ring(mid + Vector3(0, 0.1, 0), 4.0, [Color(0.9, 1.0, 0.8), TOXIC_COL, Color(0.3, 0.7, 0.3)] as Array[Color], 0.5)
	if is_instance_valid(main.hud):
		main.hud.popup("독가스 정화!", Color(0.8, 1.0, 0.6), mid + Vector3(0, 2.4, 0))
	var pop := Sfx.play("drone_pop", 0.02, -4.0)
	if pop:
		pop.pitch_scale = 0.75
	var drone := PartnerDrone.inst
	if is_instance_valid(drone):
		drone.player_cleaned += 1
	if mode == "training":
		_respawn = RESPAWN_T


## 도트 다단 흡수: 쌓인 게이지를 TICK 마다 1씩, "+1" 이 연달아 튀고 '틱' 소리가 점점 높아진다
func _update_dot(dt: float) -> void:
	_tick_t -= dt
	_chain_t += dt
	if _acc >= 1.0 and _tick_t <= 0.0:
		# 밀려 쌓이면 간격을 줄여 따라잡는다 (빨아들이는 손맛과 게이지가 너무 벌어지지 않게)
		_tick_t = TICK / (1.0 + _acc / 6.0)
		_acc -= 1.0
		ticks += 1
		paid += 1.0
		_chain += 1
		_chain_sum += 1
		_chain_t = 0.0
		var drone := PartnerDrone.inst
		if is_instance_valid(drone):
			drone.add_gauge(1.0)
		if is_instance_valid(main.hud):
			var j := Vector3(randf_range(-0.5, 0.5), randf_range(0.0, 0.5), randf_range(-0.3, 0.3))
			main.hud.popup("+1", TOXIC_COL.lerp(Color.WHITE, minf(_chain * 0.03, 0.5)), _dot_at + j)
		var tk := Sfx.play("drone_pop", 0.0, -15.0)
		if tk:
			tk.pitch_scale = 1.1 + minf(_chain, 24) * 0.035
	elif _chain_t > 0.6 and _chain > 0:
		# 묶음이 끝나면 합계 한 번
		if _chain >= 4 and is_instance_valid(main.hud):
			main.hud.popup("흡입 +%d" % _chain_sum, Color(0.85, 1.0, 0.75), _dot_at + Vector3(0, 0.9, 0))
		_chain = 0
		_chain_sum = 0
