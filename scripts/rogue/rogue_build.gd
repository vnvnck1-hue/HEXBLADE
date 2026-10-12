class_name RogueBuild
extends Node
## 보유 아이템 → 스탯 · 공격 축 플래그 · 결합 공격 · 변신을 계산하고 플레이어에 연결한다.
## 기본 총은 Player.shot_hook 으로, 검은 on_strike, 대시는 on_dash, 피격은 hit_guard, 적 피해는 Enemy.dmg_hook 으로 바꾼다.
## 상태이상(화상·중독)도 여기서 돈다.

const BASE_DMG := 3.5
const BASE_TEARS := 4.2          # 초당 발사
const BASE_RANGE := 9.0          # m
const BASE_SHOT_SPEED := 24.0    # m/s

static var inst: RogueBuild

var main
var player: Player
var stats := {}
var flags := {}
var syn := {}                    # 결합 공격 id → true
var trans := {}                  # 변신 태그 → true
var tag_count := {}
var dmg := BASE_DMG
var tears := BASE_TEARS
var range_m := BASE_RANGE
var shot_speed := BASE_SHOT_SPEED
var speed := 1.0
var luck := 0.0

# 일시 효과
var room_dmg := 0.0              # 분노의 서 · 면도날 · 힘 카드 (방을 나가면 사라짐)
var room_homing := false         # 마술사 카드
var berserk_until := 0.0
var shield_ready := false        # 성스러운 망토: 이번 방 첫 피해를 막는다
var bloodlust := 0
var focus := 0                   # 연속 명중
var shot_count := 0
var fly_spawn_cd := 0.0
var pending := -1                # deal() 이 take_hit 에 넘길 실제 피해 (dmg_hook 이 꺼내 쓴다)
var familiars: Array = []
var look: RogueLook
var time := 0.0

# 상태이상: 적 id → {e, burn, poison, tick, dps}
var status := {}
var _status_t := 0.0
var _trail_t := 0.0
var _plague_t := 0.0


func _enter_tree() -> void:
	inst = self


func _exit_tree() -> void:
	if inst == self:
		inst = null
	Enemy.dmg_hook = Callable()


func attach(m, p: Player) -> void:
	main = m
	player = p
	p.shot_hook = _shot
	p.on_dash = _dash
	p.on_strike = _strike
	p.hit_guard = _guard
	Enemy.dmg_hook = _dmg_hook
	look = RogueLook.new()
	add_child(look)
	recompute(true)


# ── 계산 ────────────────────────────────────────────────

func owned_ids() -> Array:
	var ids: Array = RogueRun.items.duplicate()
	if RogueRun.trinket != "":
		ids.append(RogueRun.trinket)
	return ids


func has(id: String) -> bool:
	return RogueRun.items.has(id) or RogueRun.trinket == id


func f(key: String) -> int:
	return int(flags.get(key, 0))


func recompute(first := false) -> void:
	stats = {}
	flags = {}
	tag_count = {}
	for id in owned_ids():
		var it := RogueItems.get_item(id)
		if it.is_empty():
			continue
		for k in it.stats:
			stats[k] = float(stats.get(k, 0.0)) + float(it.stats[k])
		for k in it.flags:
			flags[k] = int(flags.get(k, 0)) + int(it.flags[k])
		if it.type == RogueItems.T.PASSIVE:
			for t in it.tags:
				tag_count[t] = int(tag_count.get(t, 0)) + 1
	for k in RogueRun.stat_bonus:
		stats[k] = float(stats.get(k, 0.0)) + float(RogueRun.stat_bonus[k])
	# 결합 공격
	var old_syn := syn.duplicate()
	syn = {}
	for s in RogueItems.SYNERGIES:
		var ok := true
		for group in s.need:
			var any := false
			for id in group:
				if RogueRun.items.has(id):
					any = true
			if not any:
				ok = false
		if ok:
			syn[s.id] = true
	# 변신 (태그 3개)
	var old_trans := trans.duplicate()
	trans = {}
	for t in tag_count:
		if tag_count[t] >= RogueItems.TRANSFORM_NEED and RogueItems.TRANSFORMS.has(t):
			trans[t] = true
	_trans_bonus()
	# 최종 스탯
	var tx := float(stats.get("tears_x", 0.0))
	if syn.has("mortar") and has("ipecac"):
		tx += 0.55
	dmg = maxf(0.5, (BASE_DMG + float(stats.get("dmg", 0.0))) * maxf(0.3, 1.0 + float(stats.get("dmg_x", 0.0))))
	tears = clampf((BASE_TEARS + float(stats.get("tears", 0.0))) * maxf(0.25, 1.0 + tx), 0.8, 16.0)
	range_m = maxf(3.0, BASE_RANGE + float(stats.get("range", 0.0)))
	shot_speed = clampf(BASE_SHOT_SPEED + float(stats.get("shot_speed", 0.0)), 10.0, 48.0)
	speed = clampf(1.0 + float(stats.get("speed", 0.0)), 0.5, 2.0)
	luck = float(stats.get("luck", 0.0))
	if is_instance_valid(look):
		look.refresh(self)
	_sync_familiars()
	if not first and is_instance_valid(main):
		for s in syn:
			if not old_syn.has(s):
				main.announce_synergy(s)
		for t in trans:
			if not old_trans.has(t):
				main.announce_transform(t)


## 변신 보너스: 스탯·플래그를 더한다 (한 번만 주는 체력·폭탄은 RogueMain.announce_transform 이 준다)
func _trans_bonus() -> void:
	var add := func(k: String, v):
		if v is float:
			stats[k] = float(stats.get(k, 0.0)) + v
		else:
			flags[k] = int(flags.get(k, 0)) + int(v)
	if trans.has("angel"):
		add.call("flight", 1)
		add.call("holy", 10)
	if trans.has("demon"):
		add.call("flight", 1)
		add.call("dmg", 1.0)
	if trans.has("fly"):
		add.call("fam_fly", 3)
		add.call("fly_shot", 15)
	if trans.has("poison"):
		add.call("poison", 30)
		add.call("poison_trail", 1)
	if trans.has("mushroom"):
		add.call("blade_reach", 1)
		add.call("dmg", 0.5)
		add.call("grow", 1)
	if trans.has("tech"):
		add.call("tech_laser", 1)
		add.call("speed", 0.15)
	if trans.has("blade"):
		add.call("blade_wave", 1)
		add.call("slash_x", 0.5)
	if trans.has("bomb"):
		add.call("bomb_big", 1)
		add.call("bomb_immune", 1)
	if trans.has("gun"):
		add.call("tears", 1.0)
		add.call("multi", 1)


## 지금 피해 (일시 효과 포함)
func cur_dmg() -> float:
	var d := dmg + room_dmg + bloodlust * 0.5
	if f("wrath") > 0 and RogueRun.red <= 2:
		d += 1.5
	if f("last_stand") > 0 and RogueRun.red <= 1 and RogueRun.soul + RogueRun.black == 0:
		d *= 2.0
	if time < berserk_until:
		d *= 1.5
	if f("focus") > 0:
		d *= 1.0 + minf(focus, 12) * 0.05
	return d


func cur_tears() -> float:
	return tears * (2.5 if time < berserk_until else 1.0)


func flying() -> bool:
	return f("flight") > 0


func roll(pct: float) -> bool:
	return randf() * 100.0 < pct + luck * 2.0


# ── 매 틱 ───────────────────────────────────────────────

func _physics_process(dt: float) -> void:
	time += dt
	if not is_instance_valid(player):
		return
	player.fire_boost = cur_tears() * Player.FIRE_INTERVAL
	var sp := speed
	if f("wrath") > 0 and RogueRun.red <= 2:
		sp += 0.2
	player.speed_mul = sp
	player.mag = Player.MAG_SIZE          # 로그 모드는 재장전 없음
	player.reload_t = 0.0
	fly_spawn_cd -= dt
	_update_status(dt)
	_update_trails(dt)


func _update_status(dt: float) -> void:
	_status_t -= dt
	if _status_t > 0.0:
		return
	_status_t = 0.5
	for k in status.keys():
		var s: Dictionary = status[k]
		var e = s.e
		if not is_instance_valid(e) or not e.alive:
			status.erase(k)
			continue
		s.burn = maxf(0.0, s.burn - 0.5)
		s.poison = maxf(0.0, s.poison - 0.5)
		if s.burn <= 0.0 and s.poison <= 0.0:
			status.erase(k)
			continue
		var tick := 0.0
		if s.burn > 0.0:
			tick += maxf(1.0, cur_dmg() * 0.35)
			FX.sparks(e.global_position + Vector3(0, 1.0, 0), 4, [Color("ffd060"), Color("ff5a20")], 3.0, 0.3, 4.0, 0.06)
		if s.poison > 0.0:
			tick += maxf(1.0, cur_dmg() * 0.3)
			FX.puffs(e.global_position + Vector3(0, 0.8, 0), 2, [Color("70ff60"), Color("2a8030"), Color("2a8030"), Color("2a8030")], 0.4, 0.4, 0.4)
		deal(e, tick, Vector3.ZERO, e.global_position, 0.0)


func apply_status(e, kind: String, sec: float) -> void:
	if not is_instance_valid(e) or not e.alive or e.get("prop"):
		return
	var k: int = e.get_instance_id()
	if not status.has(k):
		status[k] = {"e": e, "burn": 0.0, "poison": 0.0}
	status[k][kind] = maxf(status[k][kind], sec)


func _update_trails(dt: float) -> void:
	if f("poison_trail") > 0 or syn.has("plague"):
		_trail_t -= dt
		if _trail_t <= 0.0 and player.velocity.length() > 2.0:
			_trail_t = 0.35
			RogueEffects.poison_cloud(player.global_position, 1.3, 2.2, cur_dmg() * 0.3)
	if syn.has("plague"):
		_plague_t -= dt
		if _plague_t <= 0.0:
			_plague_t = 0.5
			for e in Enemy.live(get_tree()):
				if e.get("prop") or not e.landed:
					continue
				if e.global_position.distance_to(player.global_position) < 3.2:
					apply_status(e, "poison", 2.0)
			var a := time * 5.0
			for i in 3:
				var aa := a + TAU * i / 3.0
				FX.puffs(player.global_position + Vector3(cos(aa) * 2.4, 0.6, sin(aa) * 2.4), 1, [Color("90ff70"), Color("308a40"), Color("308a40"), Color("308a40")], 0.3, 0.6, 0.6)


# ── 피해 ────────────────────────────────────────────────

## 적에게 amount 피해. knock_k 는 넉백 배율 (0 이면 밀지 않음). 피해 숫자에는 실제 값이 보인다.
func deal(e, amount: float, dir: Vector3, pos: Vector3, knock_k := 1.0, source := "rogue") -> void:
	if not is_instance_valid(e) or not e.alive:
		return
	var a := amount
	if e.get("is_boss") and f("boss_dmg") > 0:
		a *= 1.0 + f("boss_dmg") / 100.0
	pending = maxi(1, roundi(a))
	var k0: Vector3 = e.knock
	e.take_hit(1, dir, pos, source)
	pending = -1
	if is_instance_valid(e):
		e.knock = k0 + (e.knock - k0) * knock_k


func _dmg_hook(e: Enemy, d: int, source: String) -> int:
	if pending >= 0:
		return pending
	var k := cur_dmg() / BASE_DMG
	match source:
		"slash", "phantom":
			k *= 1.6 * (1.0 + float(stats.get("slash_x", 0.0)))
			if f("blade_fire") > 0:
				apply_status(e, "burn", 3.0)
		"laser", "missile", "parry":
			k *= 1.8
		_:
			k *= 1.2
	if e.is_boss and f("boss_dmg") > 0:
		k *= 1.0 + f("boss_dmg") / 100.0
	return maxi(1, roundi(d * k))


# ── 기본 총 ─────────────────────────────────────────────

func _shot(origin: Vector3, d: Vector3) -> void:
	shot_count += 1
	RogueEffects.fire(self, origin, d)
	if f("fly_shot") > 0 and fly_spawn_cd <= 0.0 and roll(f("fly_shot")):
		fly_spawn_cd = 0.6
		spawn_temp_familiar("hunter", 6.0)


## 연속 명중 (전투 흥분)
func on_shot_hit() -> void:
	focus += 1


func on_shot_miss() -> void:
	focus = 0


# ── 검 · 대시 ───────────────────────────────────────────

func _strike(dir: Vector3, reach: float, result: Dictionary) -> void:
	if f("blade_wave") > 0 and (result.hit > 0 or randf() < 0.5):
		var n := 3 if syn.has("blade_storm") else 1
		for i in n:
			var a := (i - (n - 1) * 0.5) * 0.35
			RogueEffects.blade_wave(self, player.global_position + Vector3(0, 0.95, 0), dir.rotated(Vector3.UP, a))
	if f("blade_vamp") > 0 and result.killed > 0:
		for i in result.killed:
			if roll(f("blade_vamp")) or syn.has("vampire"):
				main.heal_red(1, true)
	# 장검 연장: 같은 방향으로 한 번 더 판정 (닿는 거리를 늘린다)
	if f("blade_reach") > 0 and result.hit == 0:
		var extra := reach * 0.4 * f("blade_reach")
		for e in Enemy.live(get_tree()):
			if not e.landed or e.get("prop"):
				continue
			var to: Vector3 = e.global_position - player.global_position
			to.y = 0
			var l := to.length()
			if l > reach and l < reach + extra + e.radius and dir.angle_to(to / maxf(l, 0.01)) < 0.8:
				deal(e, cur_dmg() * 1.4 * (1.0 + float(stats.get("slash_x", 0.0))), dir, e.global_position, 0.6, "slash")


func _dash(p: Player, _chained: bool) -> void:
	var start := p.global_position
	if f("dash_mine") > 0:
		RogueBomb.spawn(main, start, true)
	if f("dash_fire") > 0:
		var tw := create_tween()
		for i in 6:
			tw.tween_callback(func():
				if is_instance_valid(p):
					RogueEffects.flame(p.global_position, cur_dmg() * 0.5, 2.5, syn.has("comet")))
			tw.tween_interval(0.05)
	if f("dash_shock") > 0 or f("dash_shots") > 0:
		get_tree().create_timer(Player.DASH_TIME).timeout.connect(func():
			if not is_instance_valid(p):
				return
			var at := p.global_position
			if f("dash_shock") > 0:
				RogueEffects.shockwave(at, 3.0, cur_dmg() * 1.2)
			if f("dash_shots") > 0:
				for i in 8:
					var dv := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 8.0)
					RogueEffects.bullet(self, at + Vector3(0, 0.95, 0), dv, cur_dmg() * 0.6, {"life_k": 0.6}))


# ── 피격 ────────────────────────────────────────────────

func _guard(from: Vector3) -> bool:
	if not is_instance_valid(player) or player.invuln > 0.0:
		return false
	if shield_ready:
		shield_ready = false
		_absorb(from, Color("fff4c0"), "SHIELD")
		look.mantle_pop()
		return true
	if f("dodge") > 0 and roll(f("dodge")):
		_absorb(from, Color("8ad8ff"), "DODGE", false)
		return true
	_on_hurt_effects(from)
	if RogueRun.soul > 0 or RogueRun.black > 0:
		var black := RogueRun.soul == 0
		if black:
			RogueRun.black -= 1
			RogueEffects.room_damage(40.0)
		else:
			RogueRun.soul -= 1
		_absorb(from, Color("8aa8ff") if not black else Color("302040"), "")
		main.on_player_hurt()
		bloodlust += f("bloodlust")
		focus = 0
		return true
	bloodlust += f("bloodlust")
	focus = 0
	# 빨간 체력이 깎이는 경우 (Player.take_hit 가 hp 를 1 줄인다)
	RogueRun.red = maxi(0, player.hp - 1)
	if f("iframe") > 0:
		get_tree().process_frame.connect(func():
			if is_instance_valid(player):
				player.invuln = maxf(player.invuln, 1.7), CONNECT_ONE_SHOT)
	return false


func _absorb(from: Vector3, c: Color, text: String, hurt := true) -> void:
	player.invuln = 1.1 + (0.6 if f("iframe") > 0 else 0.0)
	FX.ring(player.global_position + Vector3(0, 0.3, 0), 3.2, [c, Color.WHITE, c], 0.35)
	if hurt:
		FX.player_hurt(player.global_position + Vector3(0, 0.9, 0))
		Sfx.play("hurt", 0.05, -3.0)
		main.shake(0.25)
		main.hitstop(0.06)
	else:
		Sfx.play("roll", 0.05)
	if text != "":
		main.hud.popup(text, c, player.global_position + Vector3(0, 2.3, 0))
	var d := player.global_position - from
	d.y = 0
	player.velocity += d.normalized() * 5.0


func _on_hurt_effects(from: Vector3) -> void:
	var at := player.global_position
	if f("react") > 0:
		RogueEffects.shockwave(at, 3.5, cur_dmg() * 2.0)
		for b in get_tree().get_nodes_in_group("enemy_bullets"):
			if (b as Node3D).global_position.distance_to(at) < 4.0:
				b.queue_free()
	if f("gas") > 0:
		RogueEffects.poison_cloud(at, 2.6, 4.0, cur_dmg() * 0.4)
	if f("hurt_coin") > 0:
		main.drop("coin", at)
	if f("hurt_slow") > 0:
		for e in Enemy.live(get_tree()):
			if not e.get("prop") and e.global_position.distance_to(at) < 5.0 and not e.is_boss:
				e.stagger((e.global_position - at).normalized(), 0.8)


# ── 패밀리어 ────────────────────────────────────────────

func _sync_familiars() -> void:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	var want := {
		"shield": f("fam_shield"), "fly": f("fam_fly"), "turret": f("fam_turret"),
		"hunter": f("fam_hunter"), "sat": f("fam_sat"),
	}
	var have := {}
	for fm in familiars.duplicate():
		if not is_instance_valid(fm):
			familiars.erase(fm)
			continue
		if fm.temp > 0.0:
			continue
		have[fm.kind] = int(have.get(fm.kind, 0)) + 1
		if int(have[fm.kind]) > int(want.get(fm.kind, 0)):
			familiars.erase(fm)
			fm.queue_free()
	for k in want:
		for i in range(int(have.get(k, 0)), int(want[k])):
			var fm := RogueFamiliar.make(k, self)
			if k == "hunter" and f("hunter_poison") > 0:
				fm.poison = true
			familiars.append(fm)
			main.world.add_child(fm)
			fm.global_position = player.global_position
	var idx := {}
	for fm in familiars:
		if is_instance_valid(fm) and fm.temp <= 0.0:
			idx[fm.kind] = int(idx.get(fm.kind, 0)) + 1
	var n := {}
	for fm in familiars:
		if is_instance_valid(fm) and fm.temp <= 0.0:
			n[fm.kind] = int(n.get(fm.kind, 0)) + 1
			fm.slot = float(n[fm.kind] - 1) / maxf(1, int(idx[fm.kind]))


func spawn_temp_familiar(kind: String, sec: float) -> RogueFamiliar:
	var fm := RogueFamiliar.make(kind, self)
	fm.temp = sec
	fm.slot = randf()
	familiars.append(fm)
	main.world.add_child(fm)
	fm.global_position = player.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	return fm


## 방이 바뀌면 일시 효과를 지운다
func on_room_enter() -> void:
	room_dmg = 0.0
	room_homing = false
	bloodlust = 0
	shield_ready = f("mantle") > 0
	if is_instance_valid(look):
		look.mantle_show(shield_ready)
	for fm in familiars.duplicate():
		if is_instance_valid(fm) and fm.kind == "minion":
			familiars.erase(fm)
			fm.queue_free()
