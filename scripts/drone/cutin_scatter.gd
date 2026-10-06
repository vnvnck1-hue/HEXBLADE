class_name CutinScatter
extends RefCounted
## 사선 DOCKING 컷인의 날아가는 소품 · 금빛 반짝이 (민트 메이드, docs/diagonal-docking-cutin.md "민트 메이드").
## DiagonalDockingCutin 이 만들고 매 프레임 update(dt) 한다. 그리기 노드 넷을 컷인 root 에 순서대로 끼운다:
##   back(소품 · 뒤 반짝이) → back_glow(가산: 둥근 광채 · 가루) → [캐릭터] → front · front_glow(띠 아래쪽의 반짝이만)
## 소품: 화면 왼쪽 밖에서 차례로 던져져 DOCKING 글자가 흐르는 띠 안을 왼쪽 → 오른쪽으로 우당탕탕 날아간다 —
##   빙글빙글 구르며 띠 아래 선에 통통 튀고(튈 때 찌그러짐 · 가끔 회전이 거꾸로), 위 선에 부딪히면 꺾여 내려온다.
##   진입 중엔 캐릭터 속도를 일부 받고, 합체 순간 위로 튕기고, 퇴장 때 돌풍에 빨라진다.
##   대부분 캐릭터 뒤 층이지만 셋(FRONT_EVERY 번째마다)은 캐릭터 **앞**을 지나간다(공간감): 더 크고(NEAR) 빠르며, 띠 아래쪽 절반에서만 튀어
##   얼굴 · 트레이를 가리지 않고, 오른쪽 아래로 살짝 떨어진 옅은 그림자를 끈다.
## 반짝이: 확정 시안의 둥글고 통통한 금빛 별(11_gold_sparkle.png) — 띠 안에서만, 날아가는 소품 꼬리와 띠 곳곳에서 생겨
##   오른쪽으로 휘날린다. 뿅 커졌다(넘침) 말랑하게 두근거리고 천천히 돌다 쏙 작아지며 사라짐 + 은은한 둥근 광채 · 작은 별 가루.

const GRAVITY := 5600.0                     ## 소품 낙하 (px/s², 800 높이 기준)
const BOUNCE := 0.18                        ## 띠 아래 선에서 튀는 정도 (낮게 · 자주: 우당탕)
const HOP := Vector2(260.0, 560.0)          ## 튈 때 보태는 위 방향 속도 (우당탕: 매번 다르게)
const HOP_MAX := 820.0                      ## 튀어 오르는 속도 상한 → 0.15~0.3초마다 한 번씩 튐
## 가로 속도 등급 (×W/초, 2026-10-06 사용자: 너무 빨리 지나감 → 빠른 것 · 느린 것 섞음). 소품마다 무작위로 하나:
##   SLOW 둥실 떠가듯(중력 약하게 · 천천히 구름) · MID · FAST 우당탕. 느린 것은 들어올 때만 ENTER_KICK 으로 밀려 들어왔다가 느려진다.
const TIERS := [
	{"w": 0.38, "vx": Vector2(0.16, 0.3), "grav": 0.32, "spin": Vector2(1.2, 3.0), "hop": 0.55},
	{"w": 0.34, "vx": Vector2(0.48, 0.72), "grav": 0.7, "spin": Vector2(3.0, 6.0), "hop": 0.8},
	{"w": 0.28, "vx": Vector2(1.0, 1.4), "grav": 1.0, "spin": Vector2(5.0, 11.0), "hop": 1.0},
]
const ENTER_KICK := 0.55                    ## 느린 소품이 들어올 때 더 받는 속도 (×W/초, 금방 줄어듦)
const CRUISE_K := 3.5                       ## 들어온 뒤 제 속도로 돌아가는 빠르기 (1/초)
const LAUNCH := Vector2(0.0, 0.42)          ## 던지는 시각 범위 (초)
const SPARK_RATE := 16.0                    ## 띠 곳곳 반짝이 (초당)
const TRAIL_RATE := 5.0                     ## 날아가는 소품 하나가 흘리는 반짝이 (초당)
const SPARK_MAX := 90
const DUST_MAX := 110
const SPARK_DRIFT := Vector2(0.025, 0.09)   ## 별빛이 흘러가는 속도 (×W/초) — 아주 천천히 (예전 0.25~0.6)
const SPARK_LIFE := Vector2(0.75, 1.15)
const FACE_RATE := 11.0                     ## 얼굴 둘레 반짝이 (초당)
const FACE_RING := Vector2(0.11, 0.2)       ## 얼굴 중심에서의 거리 (×side) — 얼굴 자체는 가리지 않는다
const FACE_MAX := 16
const GOLD := Color(1.0, 0.82, 0.32)
const HOT := Color(1.0, 0.96, 0.78)         ## 가산 별 심 (뜨거운 흰 금빛)
const STAR_DIM := 194.0                     ## 별 PNG 안 그림의 긴 변(px)
const FRONT_EVERY := 3                      ## 던지는 순서에서 이 간격마다 하나(1 · 4 · 7번째)가 캐릭터 앞으로
const NEAR := 1.22                          ## 앞 소품: 가까우니 더 크게
const NEAR_SPEED := 1.18                    ## 앞 소품: 가까우니 더 빠르게 (시차)
const NEAR_TOP := 0.48                      ## 앞 소품이 올라갈 수 있는 띠 높이 (0 = 위 선) — 얼굴 · 트레이 보호
const NEAR_SHADOW := Color(0.08, 0.10, 0.16, 0.32)   ## 앞 소품 그림자 (띠와 같은 슬레이트 남색 · 옅게)
const NEAR_SHADOW_OFF := Vector2(12.0, 20.0)         ## 그림자 어긋남 (px, 800 높이 기준)

static var _glow_tex: Texture2D
static var _add_mat: CanvasItemMaterial

var c: Node                 ## DiagonalDockingCutin
var back := Node2D.new()
var back_glow := Node2D.new()
var front := Node2D.new()
var front_glow := Node2D.new()
var props: Array = []
var sparks: Array = []
var face_sparks: Array = []  ## 얼굴 둘레 반짝이: 얼굴 중심 기준 오프셋(×side)이라 캐릭터를 따라 움직인다
var dust: Array = []
var _face_acc := 0.0
var face_total := 0         ## 확인용
var star_tex: Texture2D
var _spawn := 0.0
var _prev_ap := Vector2.ZERO
var _av := Vector2.ZERO
var _init_av := false
var rng := RandomNumberGenerator.new()
var spark_total := 0        ## 확인용: 지금까지 만든 반짝이 수
var spark_out := 0          ## 확인용: 띠 밖에서 생긴 반짝이 수 (0 이어야 함)
var bounces := 0            ## 확인용: 소품이 띠 아래 선에 튄 횟수
var max_x: Array = []       ## 확인용: 소품마다 지금까지 간 가장 오른쪽 x
var min_x: Array = []       ## 확인용: 소품마다 처음 나타난 x


func _init(cutin: Node, cfg_props: Array, star: Texture2D) -> void:
	c = cutin
	star_tex = star
	rng.randomize()
	if _glow_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.4, Color(1, 1, 1, 0.45))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(1.0, 0.5)
		gt.width = 64
		gt.height = 64
		_glow_tex = gt
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	for nd: Node2D in [back, back_glow, front, front_glow]:
		nd.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	back_glow.material = _add_mat
	front_glow.material = _add_mat
	back.draw.connect(_draw_back)
	back_glow.draw.connect(_draw_glow.bind(false))
	front.draw.connect(_draw_front)
	front_glow.draw.connect(_draw_glow.bind(true))
	# 던지는 순서는 섞되, 시각은 고르게 (한꺼번에 몰리지 않게)
	var n := cfg_props.size()
	var order := range(n)
	order.shuffle()
	# 속도 등급: 느림 · 보통 · 빠름이 늘 섞이게 (모두 같은 등급으로 몰리지 않게 가중치 순으로 나눠 준 뒤 섞음)
	var tiers: Array = []
	for ti in TIERS.size():
		for q in roundi(float(TIERS[ti].w) * n):
			tiers.append(ti)
	while tiers.size() < n:
		tiers.append(1)
	tiers.resize(n)
	tiers.shuffle()
	# 앞을 지나가는 소품은 빠름(가까우니 시차로 빨리 휙 — 얼굴 앞에 오래 머물지 않게): 빠름 칸을 앞 자리로 옮긴다
	for k in n:
		if k % FRONT_EVERY == 1 and tiers[k] != 2:
			for j in n:
				if j % FRONT_EVERY != 1 and tiers[j] == 2:
					tiers[j] = tiers[k]
					tiers[k] = 2
					break
			if tiers[k] != 2:
				tiers[k] = 2
	for k in n:
		var pd: Dictionary = cfg_props[order[k]]
		var near := k % FRONT_EVERY == 1
		var tier: int = tiers[k]
		var td: Dictionary = TIERS[tier]
		var born := lerpf(LAUNCH.x, LAUNCH.y, float(k) / maxf(n - 1, 1)) + rng.randf_range(0.0, 0.03)
		if tier == 0:
			born *= 0.35         # 느린 것은 일찍 던져야 화면을 지나간다
		var sp := (1.0 if rng.randf() < 0.75 else -1.0) * rng.randf_range(td.spin.x, td.spin.y)
		props.append({
			"near": near, "tier": tier,
			"cfg": pd, "tex": pd.tex, "alive": false,
			"born": born,
			"lane": rng.randf_range(0.65, 0.9) if near else rng.randf_range(0.35, 0.85),   ## 띠 안 높이 (0 = 위 선, 1 = 아래 선)
			"pos": Vector2.ZERO, "vel": Vector2.ZERO, "cruise": 0.0,
			"grav": float(td.grav), "hop": float(td.hop), "spin_max": float(td.spin.y) * 1.5,
			"rot": rng.randf_range(-PI, PI), "rot_v": sp,
			"squash": 0.0, "age": 0.0, "trail": 0.0,
		})
		max_x.append(-INF)
		min_x.append(INF)


func _u() -> float:
	return float(c.vs.y) / 800.0


func _prop_px(p: Dictionary) -> float:
	return float(p.cfg.size) * float(c.side) * (NEAR if bool(p.near) else 1.0)


## 띠의 위 · 아래 선 높이 (화면 x 에서)
func band_top(x: float) -> float:
	var to: Vector2 = c._top_origin_now()
	return to.y + tan(deg_to_rad(float(c.TOP_THETA))) * x


func band_bottom(x: float) -> float:
	return float(c.origin.y) + tan(deg_to_rad(float(c.THETA))) * x


func in_band(p: Vector2, margin := 0.0) -> bool:
	return p.y >= band_top(p.x) - margin and p.y <= band_bottom(p.x) + margin


func update(dt: float) -> void:
	if dt <= 0.0:
		return
	var ap: Vector2 = c.anchor.position
	if not _init_av:
		_prev_ap = ap
		_init_av = true
	_av = (ap - _prev_ap) / dt
	_prev_ap = ap
	var t: float = c.t
	var leaving := float(c.exit_t) >= 0.0
	var u := _u()
	var vs: Vector2 = c.vs
	var n := maxi(1, ceili(dt * 240.0))
	var h := dt / n
	# ── 소품: 왼쪽 밖에서 던져져 띠 안을 튀며 오른쪽으로
	for i in props.size():
		var p: Dictionary = props[i]
		if not bool(p.alive):
			if t < float(p.born):
				continue
			p.alive = true
			var r := _prop_px(p) * 0.5
			var x0 := -r - rng.randf_range(0.0, 0.06) * vs.x
			var y0 := lerpf(band_top(x0) + r * 0.6, band_bottom(x0) - r * 0.6, float(p.lane))
			p.pos = Vector2(x0, y0)
			var td: Dictionary = TIERS[int(p.tier)]
			var vx := rng.randf_range(td.vx.x, td.vx.y) * vs.x
			if bool(p.near):
				vx *= NEAR_SPEED
			p.cruise = vx
			if int(p.tier) == 0:
				vx += ENTER_KICK * vs.x                          ## 밀려 들어왔다가 둥실 느려짐
			vx += minf(maxf(_av.x, 0.0) * 0.04, 0.12 * vs.x)       ## 캐릭터 속도는 조금만 (진입 초반엔 매우 빠름)
			p.vel = Vector2(vx, -rng.randf_range(150.0, 600.0) * u * float(p.grav))
		p.age = float(p.age) + dt
		var pos: Vector2 = p.pos
		var vel: Vector2 = p.vel
		var rad := _prop_px(p) * 0.36
		var g := float(p.grav)
		for k in n:
			vel.y += GRAVITY * g * u * h
			if leaving:
				vel.x += (vs.x * 3.2 - vel.x) * 6.0 * h          ## 돌풍
			else:
				vel.x += (float(p.cruise) - vel.x) * minf(1.0, CRUISE_K * h)
			pos += vel * h
			var bot := band_bottom(pos.x) - rad
			if pos.y > bot and vel.y > 0.0:
				pos.y = bot
				var hk := float(p.hop)
				vel.y = -minf(absf(vel.y) * BOUNCE + rng.randf_range(HOP.x, HOP.y) * u * hk, HOP_MAX * u * hk)
				vel.x *= rng.randf_range(0.88, 1.08)
				if rng.randf() < 0.35:
					p.rot_v = float(p.rot_v) * rng.randf_range(-1.3, -0.6)
				else:
					p.rot_v = float(p.rot_v) * rng.randf_range(0.9, 1.3)
				p.rot_v = clampf(float(p.rot_v), -float(p.spin_max), float(p.spin_max))
				p.squash = 1.0
				bounces += 1
			var top := band_top(pos.x) + rad * 0.5
			if bool(p.near):
				top = maxf(top, lerpf(band_top(pos.x), band_bottom(pos.x), NEAR_TOP))
			if pos.y < top and vel.y < 0.0:
				pos.y = top
				vel.y = absf(vel.y) * 0.4
				p.rot_v = -float(p.rot_v)
				p.squash = 0.6
		p.pos = pos
		p.vel = vel
		p.rot = float(p.rot) + float(p.rot_v) * dt
		p.squash = maxf(0.0, float(p.squash) - dt * 7.0)
		max_x[i] = maxf(float(max_x[i]), pos.x)
		min_x[i] = minf(float(min_x[i]), pos.x)
		# 꼬리 반짝이
		if pos.x > -rad and pos.x < vs.x + rad and not leaving:
			p.trail = float(p.trail) + dt * TRAIL_RATE
			while float(p.trail) >= 1.0:
				p.trail = float(p.trail) - 1.0
				var back_pt := pos - vel.normalized() * rad * rng.randf_range(0.6, 1.2)
				_new_spark(back_pt + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * rad * 0.5, vel * rng.randf_range(0.04, 0.1))
	# ── 반짝이: 띠 안 곳곳 (진입 ~ 체류) — 천천히 떠 흐른다
	if not leaving and float(c.done_t) < 0.0:
		_spawn += SPARK_RATE * dt
		while _spawn >= 1.0:
			_spawn -= 1.0
			var x := rng.randf_range(-0.02, 0.92) * vs.x
			var y := lerpf(band_top(x), band_bottom(x), rng.randf_range(0.08, 0.92))
			_new_spark(Vector2(x, y), Vector2(rng.randf_range(SPARK_DRIFT.x, SPARK_DRIFT.y) * vs.x, rng.randf_range(-20.0, 12.0) * u))
		# 얼굴 둘레 반짝이 (띠 밖이어도 됨 — 얼굴을 빛내는 장식)
		_face_acc += FACE_RATE * dt
		while _face_acc >= 1.0:
			_face_acc -= 1.0
			_new_face_spark()
	_update_face_sparks(dt)
	var j := sparks.size() - 1
	while j >= 0:
		var s: Dictionary = sparks[j]
		s.age = float(s.age) + dt
		if float(s.age) > float(s.life):
			sparks.remove_at(j)
			j -= 1
			continue
		var v: Vector2 = s.vel
		var wind := Vector2(float(s.drift), 0.0)
		if leaving:
			wind.x = vs.x * 0.5
		v += (wind - v) * minf(1.0, 2.2 * dt)
		v.y += sin(float(s.age) * 3.0 + float(s.ph)) * 30.0 * u * dt     ## 살랑살랑
		s.vel = v
		var np := Vector2(s.pos) + v * dt
		np.y = clampf(np.y, band_top(np.x) + 4.0 * u, band_bottom(np.x) - 4.0 * u)   ## 띠 밖으로 나가지 않게
		s.pos = np
		s.dust_acc = float(s.dust_acc) + dt * 5.0
		while float(s.dust_acc) >= 1.0 and dust.size() < DUST_MAX:
			s.dust_acc = float(s.dust_acc) - 1.0
			dust.append({"pos": np + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)) * u,
				"vel": v * 0.35 + Vector2(rng.randf_range(-22, 22), rng.randf_range(-18, 18)) * u,
				"age": 0.0, "life": rng.randf_range(0.35, 0.6), "size": rng.randf_range(7.0, 13.0), "front": s.front,
				"star": rng.randf() < 0.55})
		j -= 1
	var di := dust.size() - 1
	while di >= 0:
		var d: Dictionary = dust[di]
		d.age = float(d.age) + dt
		if float(d.age) > float(d.life):
			dust.remove_at(di)
		else:
			d.vel = Vector2(d.vel) * exp(-3.0 * dt)
			var dp := Vector2(d.pos) + Vector2(d.vel) * dt
			dp.y = clampf(dp.y, band_top(dp.x), band_bottom(dp.x))
			d.pos = dp
		di -= 1
	back.queue_redraw()
	back_glow.queue_redraw()
	front.queue_redraw()
	front_glow.queue_redraw()


## 새 반짝이 (띠 안으로 붙여 둠). 앞 층은 띠 아래쪽 40% 에서만 — 띠 위쪽에 걸친 트레이 · 손을 가리지 않게.
func _new_spark(pos: Vector2, vel: Vector2, big := false) -> void:
	if sparks.size() >= SPARK_MAX and not big:
		return
	var u := _u()
	var top := band_top(pos.x)
	var bot := band_bottom(pos.x)
	pos.y = clampf(pos.y, top + 4.0 * u, bot - 4.0 * u)
	if not in_band(pos, 0.5):
		spark_out += 1
	var lower := (pos.y - top) / maxf(bot - top, 1.0) > 0.6
	spark_total += 1
	sparks.append({"pos": pos, "vel": vel, "age": 0.0, "life": rng.randf_range(SPARK_LIFE.x, SPARK_LIFE.y),
		"drift": rng.randf_range(SPARK_DRIFT.x, SPARK_DRIFT.y) * float(c.vs.x),
		"size": rng.randf_range(22.0, 42.0) * u * (1.4 if big else 1.0), "ph": rng.randf() * TAU,
		"tw": rng.randf_range(7.0, 12.0),
		"spin": rng.randf_range(-0.8, 0.8), "front": lower and rng.randf() < 0.45, "dust_acc": rng.randf()})


## 얼굴 둘레 반짝이: 얼굴 중심에서 FACE_RING 거리, 아래쪽(목 · 트레이 쪽)은 피해 위 · 옆 반원에만
func _new_face_spark() -> void:
	if face_sparks.size() >= FACE_MAX:
		return
	var a := rng.randf_range(PI * 0.8, PI * 2.2)          # 화면 좌표: 위쪽 반원 + 옆 조금 (아래 = PI/2 근처 제외)
	var r := rng.randf_range(FACE_RING.x, FACE_RING.y)
	face_total += 1
	face_sparks.append({"off": Vector2(cos(a) * 1.15, sin(a)) * r, "age": 0.0, "life": rng.randf_range(0.6, 1.0),
		"size": rng.randf_range(24.0, 44.0) * _u(), "ph": rng.randf() * TAU, "tw": rng.randf_range(8.0, 13.0),
		"spin": rng.randf_range(-0.7, 0.7), "rise": rng.randf_range(0.01, 0.035)})


func _update_face_sparks(dt: float) -> void:
	var i := face_sparks.size() - 1
	while i >= 0:
		var f: Dictionary = face_sparks[i]
		f.age = float(f.age) + dt
		if float(f.age) > float(f.life):
			face_sparks.remove_at(i)
		else:
			f.off = Vector2(f.off) + Vector2(0.0, -float(f.rise)) * dt   # 아주 천천히 떠오름
		i -= 1


## 얼굴 중심 (화면 좌표)
func face_center() -> Vector2:
	return c.anchor.position + (Vector2(c.cfg.face) - Vector2(c.anchor_uv)) * float(c.side)


## 반짝임 세기: 기본 밝기 위로 가끔 번쩍 (가산 층 · 별 크기에 같이 쓴다)
static func _twinkle(age: float, tw: float, ph: float) -> float:
	var s := 0.5 + 0.5 * sin(age * tw + ph)
	return 0.55 + 0.45 * s + 0.6 * pow(s, 12.0)


## 합체 순간: 소품이 위로 통 튀고, 띠 안 캐릭터 둘레에서 반짝이가 한 번에 터진다
func dock_burst() -> void:
	var u := _u()
	var ap: Vector2 = c.anchor.position
	for p: Dictionary in props:
		if bool(p.alive):
			p.vel = Vector2(p.vel) + Vector2(rng.randf_range(100.0, 400.0), -rng.randf_range(700.0, 1100.0)) * u
			p.rot_v = clampf(float(p.rot_v) * 1.6, -18.0, 18.0)
			p.squash = 1.0
	for i in 12:
		var x := ap.x + rng.randf_range(-0.3, 0.3) * float(c.side)
		var y := lerpf(band_top(x), band_bottom(x), rng.randf_range(0.1, 0.9))
		var a := rng.randf_range(-1.2, 1.2)
		_new_spark(Vector2(x, y), Vector2(cos(a), sin(a) * 0.5) * rng.randf_range(90.0, 220.0) * u, true)


# ── 그리기 ─────────────────────────────────────────

func _alpha() -> float:
	return float(c._fade)


static func _back_out(x: float, k := 2.6) -> float:
	var v := x - 1.0
	return 1.0 + (k + 1.0) * v * v * v + k * v * v


func _draw_prop(ci: CanvasItem, p: Dictionary, pos: Vector2, alpha: float, tint := Color(1, 1, 1)) -> void:
	var tex: Texture2D = p.tex
	var sc := _prop_px(p) / float(p.cfg.dim)                 ## dim = PNG 안 그림의 긴 변(px)
	var q := float(p.squash)
	ci.draw_set_transform(pos, float(p.rot), Vector2(1.0 + 0.22 * q, 1.0 - 0.2 * q) * sc)   ## 튈 때 납작
	ci.draw_texture(tex, -tex.get_size() * 0.5, Color(tint.r, tint.g, tint.b, alpha))


## 소품 하나 (+ 빠를 때 뒤로 옅은 잔상 두 겹 · 앞 소품은 그 아래 옅은 그림자)
func _draw_one(ci: CanvasItem, p: Dictionary, a: float) -> void:
	var u := _u()
	var v: Vector2 = p.vel
	if bool(p.near):
		var sh := NEAR_SHADOW
		_draw_prop(ci, p, Vector2(p.pos) + NEAR_SHADOW_OFF * u, a * sh.a, sh)
	var k := clampf((v.length() - 900.0 * u) / (2200.0 * u), 0.0, 1.0)
	if k > 0.0:
		_draw_prop(ci, p, Vector2(p.pos) - v * 0.02, a * 0.25 * k)
		_draw_prop(ci, p, Vector2(p.pos) - v * 0.04, a * 0.1 * k)
	_draw_prop(ci, p, p.pos, a)


func _draw_back() -> void:
	var a := _alpha()
	for p: Dictionary in props:
		if bool(p.alive) and not bool(p.near):
			_draw_one(back, p, a)
	_draw_sparks(back, false, a)
	back.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_front() -> void:
	var a := _alpha()
	for p: Dictionary in props:
		if bool(p.alive) and bool(p.near):
			_draw_one(front, p, a)
	_draw_sparks(front, true, a)
	front.draw_set_transform_matrix(Transform2D.IDENTITY)


## 카툰 별 크기: 뿅 넘치며 커짐 → 말랑하게 두근 → 끝에서 쏙 작아짐
func _star_k(age: float, life: float, ph: float) -> float:
	var grow := _back_out(clampf(age / 0.16, 0.0, 1.0))
	var end := 1.0 - smoothstep(life * 0.7, life, age)
	var beat := 1.0 + 0.12 * sin(age * 6.0 + ph)
	return maxf(grow, 0.0) * end * beat


func _draw_sparks(ci: CanvasItem, front_layer: bool, a: float) -> void:
	var u := _u()
	for d: Dictionary in dust:
		if bool(d.front) != front_layer or not bool(d.star):
			continue
		var k := float(d.age) / float(d.life)
		var sz := float(d.size) * u * maxf(_back_out(clampf(k / 0.3, 0.0, 1.0)), 0.0) * (1.0 - smoothstep(0.6, 1.0, k))
		ci.draw_set_transform(d.pos, 0.0, Vector2.ONE * (sz / STAR_DIM))
		ci.draw_texture(star_tex, -star_tex.get_size() * 0.5, Color(1, 1, 1, a))
	for s: Dictionary in sparks:
		if bool(s.front) != front_layer:
			continue
		var sz := float(s.size) * _star_k(float(s.age), float(s.life), float(s.ph))
		if sz < 0.5:
			continue
		ci.draw_set_transform(s.pos, float(s.spin) * float(s.age), Vector2.ONE * (sz / STAR_DIM))
		ci.draw_texture(star_tex, -star_tex.get_size() * 0.5, Color(1, 1, 1, a))
	if front_layer:
		var fc := face_center()
		var side := float(c.side)
		for f: Dictionary in face_sparks:
			var sz := float(f.size) * _star_k(float(f.age), float(f.life), float(f.ph))
			if sz < 0.5:
				continue
			ci.draw_set_transform(fc + Vector2(f.off) * side, float(f.spin) * float(f.age), Vector2.ONE * (sz / STAR_DIM))
			ci.draw_texture(star_tex, -star_tex.get_size() * 0.5, Color(1, 1, 1, a))


## 가산 층 (에디티브 머티리얼): 별마다 좁은 금빛 후광(별 크기의 1.55배, 2차: 넓다는 피드백으로 2.8 → 1.55) + 뜨거운 흰 심 + 별 모양 자체를 한 번 더 더해 번쩍이게.
## 세기는 _twinkle 로 반짝반짝 오르내린다. 가늘고 날카로운 플레어는 쓰지 않는다(2차 피드백).
func _glow_star(ci: Node2D, pos: Vector2, size: float, k: float, tw: float, spin: float, a: float) -> void:
	var gc := GOLD
	gc.a = a * 0.6 * minf(k, 1.0) * tw
	ci.draw_set_transform(pos, 0.0, Vector2.ONE * (size * 1.55 * k / 64.0))
	ci.draw_texture(_glow_tex, Vector2(-32, -32), gc)
	var hc := HOT
	hc.a = a * 0.75 * minf(k, 1.0) * tw
	ci.draw_set_transform(pos, 0.0, Vector2.ONE * (size * 0.7 * k / 64.0))
	ci.draw_texture(_glow_tex, Vector2(-32, -32), hc)
	var sc := Color(1.0, 0.9, 0.55, a * 0.85 * minf(k, 1.0) * clampf(tw - 0.35, 0.0, 1.0))
	ci.draw_set_transform(pos, spin, Vector2.ONE * (size * k * 1.08 / STAR_DIM))
	ci.draw_texture(star_tex, -star_tex.get_size() * 0.5, sc)


func _draw_glow(front_layer: bool) -> void:
	var ci: Node2D = front_glow if front_layer else back_glow
	var a := _alpha()
	var u := _u()
	for s: Dictionary in sparks:
		if bool(s.front) != front_layer:
			continue
		var k := clampf(_star_k(float(s.age), float(s.life), float(s.ph)), 0.0, 1.2)
		_glow_star(ci, s.pos, float(s.size), k, _twinkle(float(s.age), float(s.tw), float(s.ph)), float(s.spin) * float(s.age), a)
	if front_layer:
		var fc := face_center()
		var side := float(c.side)
		for f: Dictionary in face_sparks:
			var k := clampf(_star_k(float(f.age), float(f.life), float(f.ph)), 0.0, 1.2)
			_glow_star(ci, fc + Vector2(f.off) * side, float(f.size), k, _twinkle(float(f.age), float(f.tw), float(f.ph)), float(f.spin) * float(f.age), a)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	for d: Dictionary in dust:
		if bool(d.front) != front_layer or bool(d.star):
			continue
		var k := float(d.age) / float(d.life)
		var col := GOLD.lerp(Color(1, 0.97, 0.85), 0.4)
		col.a = a * (1.0 - k) * 0.95
		ci.draw_circle(d.pos, float(d.size) * 0.36 * u * (1.0 - 0.5 * k), col)
