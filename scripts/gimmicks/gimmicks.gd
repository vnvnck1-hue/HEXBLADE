class_name Gimmicks
extends Node3D
## 필드 기믹 관리자. 전투방마다 연기 구역 · 레일 · 가스통 · 수리키트 해치를 배치하고,
## 매 물리 틱 플레이어 상태 플래그(Player.no_attack / hidden / rooted / carry / interact_ok / gimmick_pose)를 정한다.
##
##  연기 구역 (SmokeZone)   안에 들어가면 적이 보지 못한다(사격 중단). 대신 이동기만 쓸 수 있고 공격은 막힌다.
##                         몸은 빗금 홀로그램으로 보이고, 나올 때 연기가 움직임을 따라 끌려 나온다.
##  레일 (RailBelt)         바닥 컨베이어. 올라탄 캐릭터를 레일 속도만큼 실어 나른다 (기 모으기 중에도).
##  가스통 (GasCanister)    맞으면 터져 주변 플레이어·적·다른 가스통에 피해. 그을린 자국과 불이 남는다.
##  수리키트 해치 (RepairHatch) 전투 중 가끔 바닥에서 솟는다. 옆 레버를 F 연타로 돌리면 해치가 열리며 수리키트가 올라온다.
##
## 기존 코드에 닿는 곳: Main._ready 의 attach 한 줄, Player 의 플래그 훅, 적 AI 의 "숨은 플레이어는 쏘지 않음" 조건.
## Main 하위 씬이 gimmick_layout(g) 를 가지면 자동 배치 대신 그것을 부른다 (기믹 시험장).

const SMOKE_CHANCE := 0.5
const BELT_CHANCE := 0.45
const BARREL_CHANCE := 0.65
const HATCH_CHANCE := 0.5          # 전투방마다 이 확률로 전투 도중 해치가 한 번 솟는다
const HATCH_DELAY := Vector2(5.0, 11.0)
const DROP_GAP := Vector2(13.0, 20.0)   # 전투 중 가스통이 하늘에서 떨어지는 간격
const DROP_MAX := 4                # 방 하나에 동시에 있는 가스통 상한 (떨어뜨릴 때)
const REVEAL_DIST := 2.0           # 이 거리 안의 적에게는 연기 속에서도 보인다
const BOT_CRANK_GAP := 0.11

static var inst: Gimmicks

var main: Main
var map: ArenaMap
var rng := RandomNumberGenerator.new()
var smokes: Array[SmokeZone] = []
var belts: Array[RailBelt] = []
var hatches: Array[RepairHatch] = []
var used: Array = []               # [Vector3, 반지름] 이미 쓴 자리
var room_plan := {}                # 방 id → {"hatch": bool}
var auto := true                   # false 면 전투 중 해치·가스통 자동 등장 없음 (시험장)
var bot_crank := true              # 봇이 레버 범위에 있으면 연타한다

var _room := -1
var _room_t := 0.0
var _hatch_at := -1.0
var _drop_at := -1.0
var _was_in_smoke := false
var _was_hidden := false
var _deny_t := 0
var _bot_t := 0.0


static func attach(m: Main) -> Gimmicks:
	var g := Gimmicks.new()
	g.main = m
	m.world.add_child(g)
	return g


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _ready() -> void:
	inst = self
	map = main.map
	rng.seed = hash([main.map_seed, map.rooms.size(), map.start_room]) if main.map_seed >= 0 else randi()
	# 하위 씬의 _ready 가 플레이어 시작 위치·포탈을 정한 다음에 배치한다
	_layout.call_deferred()


func _layout() -> void:
	if main.has_method("gimmick_layout"):
		main.call("gimmick_layout", self)
		return
	if main.showcase:
		return
	_reserve_scene_spots()
	for r in map.rooms:
		if r.combat:
			_populate(r.id)


## 플레이어 시작 자리·포탈·수리 발판 둘레는 비워 둔다
func _reserve_scene_spots() -> void:
	if is_instance_valid(main.player):
		used.append([main.player.global_position, 3.0])
	var ps = main.get("portals")
	if ps is Array:
		for p in ps:
			if is_instance_valid(p):
				used.append([(p as Node3D).global_position, 2.6])
	var pad = main.get("rest_pad")
	if pad is Node3D and is_instance_valid(pad):
		used.append([pad.global_position, 3.0])


# ── 자동 배치 ───────────────────────────────────────────

func _populate(id: int) -> void:
	var r: Dictionary = map.rooms[id]
	var big: float = r.scale
	var spots := map.open_spots(id)
	if spots.is_empty():
		return
	for i in (2 if big >= 2.5 else 1):
		if rng.randf() < SMOKE_CHANCE:
			var p := _free_spot(spots, 2.8, 5.0)
			if p != Vector3.INF:
				add_smoke(p, rng.randf_range(2.4, 3.0))
	for i in (2 if big >= 2.0 else 1):
		if rng.randf() < BELT_CHANCE:
			var b := _find_belt(id)
			if not b.is_empty():
				add_belt(b.center, b.dir, b.len)
	if rng.randf() < BARREL_CHANCE:
		var n := rng.randi_range(1, 2 if big <= 1.0 else 4)
		for i in n:
			var p := _free_spot(spots, 1.6, 2.0)
			if p != Vector3.INF:
				add_barrel(p)
	room_plan[id] = {"hatch": rng.randf() < HATCH_CHANCE}


## 출입구에서 door_gap 넘게 떨어진, 이미 쓴 자리와 겹치지 않는 빈 자리 (없으면 INF)
func _free_spot(spots: Array[Vector3], r: float, door_gap: float) -> Vector3:
	for tries in 40:
		var p: Vector3 = spots[rng.randi_range(0, spots.size() - 1)]
		if not _clear(p, r) or _near_door(p, door_gap):
			continue
		used.append([p, r])
		return p
	return Vector3.INF


func _clear(p: Vector3, r: float) -> bool:
	for u in used:
		var q: Vector3 = u[0]
		if Vector2(p.x - q.x, p.z - q.z).length() < r + float(u[1]):
			return false
	return true


func _near_door(p: Vector3, gap: float) -> bool:
	var rid := map.room_at(p)
	if rid < 0:
		return true
	for door in map.rooms[rid].doors:
		if map.world_of(door[0]).distance_to(p) < gap:
			return true
	return false


## 방 안 평평한 직선 자리 (폭 3칸 · 길이 8~12칸). 찾으면 {center, dir, len}
func _find_belt(id: int) -> Dictionary:
	var cells: Array = map.rooms[id].cells
	for tries in 70:
		var c: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var along_x := rng.randf() < 0.5
		var n := rng.randi_range(8, 12)
		var h0 := map.cell_h(c)
		var ok := true
		for i in n:
			for w in range(-1, 2):
				var cc: Vector2i = c + (Vector2i(i, w) if along_x else Vector2i(w, i))
				if map.is_blocked_cell(cc) or map.room_of[map._idx(cc)] != id or absf(map.cell_h(cc) - h0) > 0.03:
					ok = false
					break
			if not ok:
				break
		if not ok:
			continue
		var a := map.world_of(c)
		var b := map.world_of(c + (Vector2i(n - 1, 0) if along_x else Vector2i(0, n - 1)))
		var center := (a + b) * 0.5
		center.y = h0
		var free := true
		for k in n + 1:
			var q := a.lerp(b, float(k) / n)
			if not _clear(q, 1.4) or _near_door(q, 2.5):
				free = false
				break
		if not free:
			continue
		for k in n + 1:
			used.append([a.lerp(b, float(k) / n), 1.3])
		var d := Vector3.RIGHT if along_x else Vector3.BACK
		if rng.randf() < 0.5:
			d = -d
		return {"center": center, "dir": d, "len": float(n) * ArenaMap.CELL}
	return {}


# ── 생성 ────────────────────────────────────────────────

func add_smoke(p: Vector3, radius := 2.7) -> SmokeZone:
	var s := SmokeZone.new()
	s.radius = radius
	add_child(s)
	s.global_position = Vector3(p.x, map.height_at(p), p.z)
	smokes.append(s)
	return s


func add_belt(center: Vector3, dir: Vector3, length: float, speed := RailBelt.SPEED) -> RailBelt:
	var b := RailBelt.new()
	b.dir = dir.normalized()
	b.length = length
	b.speed = speed
	add_child(b)
	b.global_position = Vector3(center.x, map.height_at(center), center.z)
	belts.append(b)
	return b


func add_barrel(p: Vector3, drop := false) -> GasCanister:
	var g := GasCanister.new()
	g.drop_h = 9.0 if drop else 0.0
	main.world.add_child(g)
	g.global_position = Vector3(p.x, map.height_at(p), p.z)
	return g


func add_hatch(p: Vector3, lever_yaw := 0.0, emerge := true) -> RepairHatch:
	var h := RepairHatch.new()
	h.lever_yaw = lever_yaw
	h.emerge = emerge
	add_child(h)
	h.global_position = Vector3(p.x, map.height_at(p), p.z)
	hatches.append(h)
	return h


# ── 전투 중 등장 ─────────────────────────────────────────

func _watch_room(dt: float) -> void:
	if main.active_room != _room:
		_room = main.active_room
		_room_t = 0.0
		_hatch_at = -1.0
		_drop_at = rng.randf_range(DROP_GAP.x, DROP_GAP.y)
		if _room >= 0 and room_plan.get(_room, {}).get("hatch", false):
			_hatch_at = rng.randf_range(HATCH_DELAY.x, HATCH_DELAY.y)
			room_plan[_room].hatch = false
	if _room < 0 or main.state != Main.State.PLAY:
		return
	_room_t += dt
	if _hatch_at > 0.0 and _room_t >= _hatch_at:
		_hatch_at = -1.0
		_spawn_hatch(_room)
	if _room_t >= _drop_at:
		_drop_at = _room_t + rng.randf_range(DROP_GAP.x, DROP_GAP.y)
		if rng.randf() < 0.6 and _barrels_in(_room) < DROP_MAX:
			_drop_barrel(_room)


func _spawn_hatch(id: int) -> void:
	var pp := main.player.global_position
	var spots := map.open_spots(id)
	spots.shuffle()
	for p in spots:
		var d := Vector2(p.x - pp.x, p.z - pp.z).length()
		# 레버 자리(해치 옆 1.7m)까지 비어 있어야 한다
		var yaw := rng.randf() * TAU
		var lever := p + Vector3(sin(yaw), 0, cos(yaw)) * RepairHatch.LEVER_OFF
		if d < 4.0 or d > 13.0 or not _clear(p, 1.6) or map.is_blocked(lever + Vector3(0, 0.3, 0)) or _near_door(p, 2.5):
			continue
		used.append([p, 1.6])
		add_hatch(p, yaw)
		main.hud.popup("REPAIR HATCH", Color("7dffb0"), p + Vector3(0, 2.4, 0))
		return


func _barrels_in(id: int) -> int:
	var n := 0
	for e in Enemy.live(get_tree()):
		if e is GasCanister and is_instance_valid(e) and (e as GasCanister).alive and map.room_at((e as Node3D).global_position) == id:
			n += 1
	return n


func _drop_barrel(id: int) -> void:
	var p := map.random_spot(id, main.player.global_position, 3.5, 14.0)
	for s in smokes:
		if s.contains(p, 0.6):
			return
	FX.spawn_marker(p, 0.9)
	add_barrel(p, true)


# ── 매 틱: 플레이어 플래그 ───────────────────────────────

func _physics_process(dt: float) -> void:
	var p := main.player
	if not is_instance_valid(p):
		return
	_watch_room(dt)
	if not p.alive:
		_set_hidden(p, false, false)
		p.no_attack = false
		p.rooted = false
		p.carry = Vector3.ZERO
		p.interact_ok = false
		p.gimmick_pose = Callable()
		return
	var pos := p.global_position

	# ── 연기 ──
	var zone: SmokeZone = null
	for s in smokes:
		if s.contains(pos):
			zone = s
			break
	var in_smoke := zone != null
	var hidden := in_smoke
	if in_smoke:
		for e in Enemy.live(get_tree()):
			if is_instance_valid(e) and (e as Enemy).alive and not (e as Enemy).prop:
				var d: Vector3 = (e as Node3D).global_position - pos
				if Vector2(d.x, d.z).length() < REVEAL_DIST:
					hidden = false
					break
	_set_hidden(p, in_smoke, hidden)

	# ── 레일 ──
	var carry := Vector3.ZERO
	if not p.airborne:
		for b in belts:
			carry += b.push_at(pos)
	p.carry = carry
	_carry_enemies(dt)

	# ── 레버 ──
	var lever: RepairHatch = null
	for h in hatches:
		if is_instance_valid(h) and h.can_crank(pos):
			lever = h
			break
	p.interact_ok = lever != null
	var pressed := false
	if lever:
		if p.bot:
			_bot_t -= dt
			if bot_crank and _bot_t <= 0.0:
				_bot_t = BOT_CRANK_GAP
				pressed = true
		else:
			pressed = Input.is_action_just_pressed("interact")
		if pressed and p.dash_t <= 0.0 and p.stun_t <= 0.0 and main.state == Main.State.PLAY:
			lever.crank(p)
	var cranking: RepairHatch = null
	for h in hatches:
		if is_instance_valid(h) and h.cranking():
			cranking = h
	if cranking and (p.dash_t > 0.0 or p.hurt_t > 0.9 or p.stun_t > 0.0):
		cranking.interrupt()            # 대시로 빠져나가거나 맞으면 손을 놓는다
		cranking = null
	p.rooted = cranking != null
	if cranking:
		# 손잡이 앞으로 끌어다 세운다 (레일 위가 아니면 carry 를 이 용도로 쓴다)
		var to := cranking.stand_spot() - pos
		to.y = 0
		if to.length() > 0.08:
			p.carry = to.limit_length(1.0) * 6.0
	p.gimmick_pose = cranking.pose_player if cranking else Callable()
	p.no_attack = in_smoke or cranking != null
	if in_smoke and not p.bot:
		_deny_attack(p)
	hatches = hatches.filter(func(h): return is_instance_valid(h))


func _set_hidden(p: Player, in_smoke: bool, hidden: bool) -> void:
	if in_smoke != _was_in_smoke:
		_was_in_smoke = in_smoke
		if in_smoke:
			GimmickHolo.apply(p)
			main.hud.popup("SMOKE", Color("b8c8ff"), p.global_position + Vector3(0, 2.3, 0))
		else:
			GimmickHolo.remove(p)
	if hidden != _was_hidden:
		_was_hidden = hidden
		# 놓치면 "?" · 다시 들키면 "!!" — 적마다 조금씩 어긋나게 띠용! 튀어나온다
		var mark := "?" if hidden else "!!"
		var n := 0
		for e in Enemy.live(get_tree()):
			if is_instance_valid(e) and (e as Enemy).alive and not (e as Enemy).prop and (e as Enemy).landed:
				SpeechBubble.say(e as Node3D, mark, SpeechBubble.EMOTE, {"offset": Vector3(0, 2.3, 0), "delay": n * 0.06 + randf() * 0.05})
				n += 1
	p.hidden = hidden


## 연기 속에서 공격하려 하면 짧게 알린다 (연타해도 한 번씩만)
func _deny_attack(p: Player) -> void:
	if not (Input.is_action_just_pressed("fire_mouse") or Input.is_action_just_pressed("slash_mouse")
			or Input.is_action_just_pressed("slash") or Input.is_action_just_pressed("ult")
			or (InputMap.has_action("rush_skill") and Input.is_action_just_pressed("rush_skill"))):
		return
	var now := Time.get_ticks_msec()
	if now - _deny_t < 800:
		return
	_deny_t = now
	var ping := Sfx.play("tink", 0.0, -8.0)
	if ping:
		ping.pitch_scale = 0.55
	main.hud.popup("연기 속 · 공격 불가", Color("b8c8ff"), p.global_position + Vector3(0, 2.3, 0))


## 레일 위의 적도 실어 나른다 (포탑·가스통·보스 제외)
func _carry_enemies(dt: float) -> void:
	if belts.is_empty():
		return
	for e in Enemy.live(get_tree()):
		if not is_instance_valid(e):
			continue
		var en := e as Enemy
		if not en.alive or not en.landed or en.prop or en.is_boss or en is Turret:
			continue
		var v := Vector3.ZERO
		for b in belts:
			v += b.push_at(en.global_position)
		if v != Vector3.ZERO:
			en.global_position = main.push_out(en.global_position + v * dt, en.radius)


## 지금 연기 속에 있는가 (시험·외부 조회용)
func in_smoke(p: Vector3) -> bool:
	for s in smokes:
		if s.contains(p):
			return true
	return false
