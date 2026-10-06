class_name TrainingBossRoom
extends Node
## 허수아비 씬(TrainingMain) 왼쪽의 보스 체험방. 홀 왼쪽 벽에 넓은 통로(폭 5칸)를 뚫고 그 끝에 28×24칸 방을 둔다.
## 방 안에는 LANCASTER 보스가 무릎 꿇고 정지해 있다가, 플레이어가 들어오면 기동해 싸운다. 나가면 싸움을 멈추고 방을 지킨다.
## 방에 들어가면 왼쪽 설정 패널이 보스 프리셋으로 바뀌고(나오면 허수아비 설정으로 돌아간다), 숫자 키도 보스 설정이 된다.
##
##  1 다시 소환(기동 연출부터)   2 패턴 세트   3 처치 가능 ↔ 무적   4 페이즈 1 ↔ 2(광폭화)   5 템포
##  8 크기(플레이어 키 × 2.0 / 1.5 / 2.5)   9 행동 정지   0 다음 패턴 바로 시전   (6 재화 무한 · 7 플레이어 무적은 그대로)
## 확인용 실행 인자: --bossroom 은 보스방 입구에서 시작, --bossroom=off 면 방을 만들지 않는다.
##   --bossset=<세트 id> --bosstempo=0~2 --bossphase=2 --bossimmortal

const ROOM_SIZE := Vector2i(28, 24)
const GAP := 8                   ## 홀과 보스방 사이 통로 길이 (칸)
const RESPAWN := 5.0
const BossBar := preload("res://scripts/boss_bar.gd")
const ACCENT := Color(1.0, 0.6, 0.25)

var main: TrainingMain
var room_id := -1
var rect := Rect2()              ## 방 바닥 (xz, 월드)
var center := Vector3.ZERO
var door := Vector3.ZERO         ## 통로 쪽 입구
var boss: LancasterBoss
var bar: BossBar
var inside := false
var killable := true
var set_i := 0
var tempo_i := 0
var size_i := 0
var hold := false
var _respawn := -1.0
var _bot_t := 0.0
var _bot_side := 1.0


## 맵 생성 직후 (build 전에) 홀 왼쪽에 방과 통로를 새긴다. 새 방 번호를 돌려준다.
static func carve(map: ArenaMap) -> int:
	var hall: Dictionary = map.rooms[map.start_room]
	var hc: Vector2i = hall.center
	var left := hc.x
	for c: Vector2i in hall.cells:
		left = mini(left, c.x)
	var bc := Vector2i(left - GAP - ROOM_SIZE.x + ROOM_SIZE.x / 2, hc.y)
	var id := map._stamp(bc, map._shape(ArenaMap.Shape.RECT, ROOM_SIZE), ArenaMap.Shape.RECT, false)
	var right := bc.x
	for c: Vector2i in map.rooms[id].cells:
		right = maxi(right, c.x)
	# 통로: 3칸 붓으로 세 줄 → 폭 5칸
	for dy in range(-1, 2):
		map._carve_line(Vector2i(right, hc.y + dy), Vector2i(left, hc.y + dy))
	map._compute_anchors()
	return id


func setup(id: int) -> void:
	room_id = id
	var map := main.map
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c: Vector2i in map.rooms[id].cells:
		var w := map.world_of(c)
		lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
		hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
	rect = Rect2(lo - Vector2(0.5, 0.5), hi - lo + Vector2(1, 1))
	center = Vector3(rect.get_center().x, 0, rect.get_center().y)
	door = Vector3(rect.end.x - 1.5, 0, center.z)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bossset="):
			var want := a.substr(10)
			for i in LancasterBoss.SETS.size():
				if LancasterBoss.SETS[i].id == want:
					set_i = i
		elif a.begins_with("--bosstempo="):
			tempo_i = clampi(int(a.substr(12)), 0, LancasterBoss.TEMPOS.size() - 1)
		elif a == "--bossimmortal":
			killable = false
	bar = BossBar.new()
	add_child(bar)
	bar.name_label.text = "LANCASTER  ·  광폭화 보안 로봇"
	bar.threshold = LancasterBoss.PHASE2_AT
	_spawn()
	if OS.get_cmdline_user_args().has("--bossroom"):
		main.player.global_position = door + Vector3(-1.0, 0, 0)
		main.camera.snap(main.player.global_position)


func _spawn() -> void:
	if is_instance_valid(boss):
		boss.queue_free()
	boss = LancasterBoss.new()
	boss.set_i = set_i
	boss.tempo_i = tempo_i
	boss.size_i = size_i
	boss.immortal = not killable
	boss.hold_ai = hold
	boss.bar = bar
	boss.home = center + Vector3(-3.0, 0, 0)
	main.world.add_child(boss)
	boss.global_position = boss.home
	boss.rotation.y = -PI * 0.5            # 통로(+X) 쪽을 본다
	boss.face_yaw = boss.rotation.y
	boss.aim_yaw = boss.face_yaw
	boss.rig.reset_feet()
	_apply_rect()
	boss.defeated.connect(_on_defeated)
	boss.phase_changed.connect(_on_phase)
	_respawn = -1.0
	if inside:
		boss.active = true
	if has_meta("p2"):
		remove_meta("p2")


func _apply_rect() -> void:
	if is_instance_valid(boss):
		boss.room_rect = rect.grow(-(boss.radius + 0.3))


func _on_defeated() -> void:
	main.hud.banner("LANCASTER  DOWN", ACCENT, ("%.0f초 뒤 다시 기동합니다" % RESPAWN) if killable else "")
	_respawn = RESPAWN


func _on_phase(p: int) -> void:
	if p >= 2:
		main.hud.banner("OVERDRIVE", Color(1.0, 0.3, 0.2), "PURGE PROTOCOL ACTIVE · 포드 포격이 겹치고 집게 돌진이 연달아 온다")


func _physics_process(dt: float) -> void:
	var p := main.player
	var now := is_instance_valid(p) and rect.has_point(Vector2(p.global_position.x, p.global_position.z))
	if now != inside:
		inside = now
		main.rebuild_panel()
		if inside:
			main.hud.banner("BOSS ROOM  ·  LANCASTER", ACCENT, "버려진 시설의 광폭화된 보안 로봇 · 숫자 키로 보스 프리셋")
	if is_instance_valid(boss):
		boss.active = inside
		if inside and boss.st == LancasterBoss.St.DORMANT and boss.alive:
			boss.wake()
		if inside and boss.st == LancasterBoss.St.FIGHT and OS.get_cmdline_user_args().has("--bossphase=2") and boss.phase == 1 and not has_meta("p2"):
			set_meta("p2", true)
			boss.force_phase(2)
	_frame(p)
	if _respawn >= 0.0:
		_respawn -= dt
		if _respawn < 0.0:
			_spawn()


## 보스방 카메라: 시선을 보스 쪽으로 조금 옮기고 살짝 줌아웃해 큰 보스와 플레이어를 함께 담는다
func _frame(p: Player) -> void:
	var cam := main.camera
	if inside and is_instance_valid(boss) and is_instance_valid(p) and boss.st != LancasterBoss.St.DEAD:
		var d := boss.global_position - p.global_position
		d.y = 0
		cam.frame_bias = (d * 0.38).limit_length(4.5)
		cam.frame_zoom = 1.18
	else:
		cam.frame_bias = Vector3.ZERO
		cam.frame_zoom = 1.0


func _exit_tree() -> void:
	if is_instance_valid(main) and is_instance_valid(main.camera):
		main.camera.frame_bias = Vector3.ZERO
		main.camera.frame_zoom = 1.0


# ── 패널 ────────────────────────────────────────────────

func build_panel(panel: TrainingPanel) -> void:
	panel.title("BOSS ROOM · LANCASTER")
	panel.section("보스")
	panel.row("1", "다시 소환", func(): return "기동 연출부터")
	panel.row("2", "패턴 세트", func(): return LancasterBoss.SETS[set_i].ko)
	panel.row("3", "보스", func(): return "처치 가능" if killable else "무적")
	panel.row("4", "페이즈", func(): return ("2 · OVERDRIVE" if boss.phase >= 2 else "1") if is_instance_valid(boss) else "-")
	panel.row("5", "템포", func(): return LancasterBoss.TEMPOS[tempo_i].ko)
	panel.row("8", "크기", func(): return "플레이어 × %.1f" % float(LancasterBoss.SIZES[size_i]))
	panel.row("9", "행동 정지", func(): return "ON" if hold else "OFF")
	panel.row("0", "다음 패턴 시전", _next_title)
	panel.row("P", "패링 히트스톱", func(): return String(Parry.stop_preset().ko))
	panel.section("상태")
	panel.row("", "체력", _hp_text)
	panel.row("", "지금", _state_text)
	panel.section("플레이어")
	panel.row("6", "재화 무한", func(): return main._onoff(main.infinite))
	panel.row("7", "무적", func(): return main._onoff(main.god))
	panel.footer("통로로 나가면 허수아비 설정으로 돌아갑니다\nSpace 패링(금빛 별빛) · F1 패널 숨기기 · F2 모든 UI 숨기기")


func _next_title() -> String:
	var list: Array = LancasterBoss.SETS[set_i].list
	if list.is_empty() or not is_instance_valid(boss):
		return "-"
	var i := (list.find(boss.last_pat) + 1) % list.size()
	return String(LancasterBoss.NAMES[list[i]]).get_slice(" · ", 1)


func _hp_text() -> String:
	if not is_instance_valid(boss):
		return "-"
	if not boss.alive:
		return "정지 · %.0f초 뒤 재기동" % maxf(_respawn, 0.0) if _respawn >= 0.0 else "정지"
	return "%d / %d" % [ceili(boss.boss_hp), int(LancasterBoss.MAX_HP)]


func _state_text() -> String:
	if not is_instance_valid(boss):
		return "-"
	match boss.st:
		LancasterBoss.St.DORMANT:
			return "정지 (들어오면 기동)"
		LancasterBoss.St.WAKE:
			return "기동"
		LancasterBoss.St.TRANSITION:
			return "OVERDRIVE"
		LancasterBoss.St.STAGGER:
			return "STAGGER · 피해 두 배"
		LancasterBoss.St.DYING, LancasterBoss.St.DEAD:
			return "SHUTDOWN"
	if boss.pat != "":
		return String(LancasterBoss.NAMES[boss.pat]).get_slice(" · ", 1)
	return "견제 · 이동" if not hold else "행동 정지"


## 보스방 안에서 누른 키. 처리했으면 true
func handle_key(k: int, shift: bool) -> bool:
	var _s := shift
	match k:
		KEY_1:
			_spawn()
			main.hud.banner("LANCASTER  다시 소환", ACCENT, "기동 연출부터 시작합니다")
		KEY_2:
			set_i = (set_i + 1) % LancasterBoss.SETS.size()
			if is_instance_valid(boss):
				boss.set_i = set_i
				boss.force_next = ""
			var list: Array = LancasterBoss.SETS[set_i].list
			var names := []
			for id in list:
				names.append(String(LancasterBoss.NAMES[id]).get_slice(" · ", 1))
			main.hud.banner("패턴 세트  %s" % LancasterBoss.SETS[set_i].ko, ACCENT, " · ".join(names) if not names.is_empty() else "공격하지 않고 움직이기만 합니다")
		KEY_3:
			killable = not killable
			if is_instance_valid(boss):
				boss.immortal = not killable
			main.hud.banner("보스  %s" % ("처치 가능" if killable else "무적"), ACCENT, "쓰러지면 %.0f초 뒤 다시 기동" % RESPAWN if killable else "체력이 1 아래로 내려가지 않고 잠시 뒤 회복")
		KEY_4:
			if is_instance_valid(boss) and boss.alive:
				boss.force_phase(1 if boss.phase >= 2 else 2)
				main.hud.banner("페이즈  %d" % (2 if boss.phase >= 2 or boss.st == LancasterBoss.St.TRANSITION else 1), ACCENT, "")
		KEY_5:
			tempo_i = (tempo_i + 1) % LancasterBoss.TEMPOS.size()
			if is_instance_valid(boss):
				boss.tempo_i = tempo_i
			main.hud.banner("템포  %s" % LancasterBoss.TEMPOS[tempo_i].ko, ACCENT, "이동 · 준비동작 · 공격 간격 ×%.2f" % float(LancasterBoss.TEMPOS[tempo_i].k))
		KEY_8:
			size_i = (size_i + 1) % LancasterBoss.SIZES.size()
			if is_instance_valid(boss):
				boss.set_size(size_i)
				boss.rig.reset_feet()
				_apply_rect()
			main.hud.banner("크기  플레이어 × %.1f" % float(LancasterBoss.SIZES[size_i]), ACCENT, "")
		KEY_9:
			hold = not hold
			if is_instance_valid(boss):
				boss.hold_ai = hold
			main.hud.banner("행동 정지  %s" % ("ON" if hold else "OFF"), ACCENT, "제자리에서 조준만 합니다" if hold else "")
		KEY_P:
			var pr := Parry.cycle_stop(shift)
			main.hud.banner("패링 히트스톱  %s" % pr.ko, ACCENT, "중간 타 %.2f초 · 마지막 타 %.2f초%s" % [pr.light, pr.heavy, " · 두 번 끊어 멈춤" if float(pr.stutter) > 0.0 else ""])
		KEY_0:
			if is_instance_valid(boss) and boss.alive:
				var id := boss.cast_next()
				if id != "":
					main.hud.banner(String(LancasterBoss.NAMES[id]), ACCENT, "")
		_:
			return false
	return true


# ── 자동 플레이 (--bot 확인용) ───────────────────────────

## 보스와 6~8m 를 두고 옆으로 돌며 쏘고, 가까우면 베고, 패링 판정 창이면 대시(패링), 위험 원 안이면 빠져나간다
func bot_input(p: Player, out: Dictionary) -> Dictionary:
	if not inside:
		var go := door + Vector3(-3.0, 0, 0) - p.global_position
		go.y = 0
		out.move = go.normalized() if go.length() > 0.5 else Vector3.ZERO
		return out
	if not is_instance_valid(boss) or not boss.alive:
		return out
	var to := boss.global_position - p.global_position
	to.y = 0
	var d := to.length()
	out.aim = boss.global_position + Vector3(0, 1.4, 0)
	_bot_t -= get_physics_process_delta_time()
	if _bot_t <= 0.0:
		_bot_t = randf_range(1.2, 2.4)
		_bot_side = -_bot_side
	var n := to / maxf(d, 0.01)
	var side := Vector3(-n.z, 0, n.x) * _bot_side
	var want := 7.0 if boss.phase == 1 else 6.0
	out.move = (side + n * clampf((d - want) * 0.5, -1.0, 1.0)).normalized()
	out.fire = d > 3.5
	if d < 4.2:
		out.slash = fmod(main.time, 0.12) < 0.02
	if Parry.inst and Parry.inst.best_threat() != null:
		out.dash = true
	elif boss.pat == "stomp" or (boss.pat == "spike" and d < 6.0) or (boss.pat == "burst" and String(boss.ps.get("ph", "")) == "fire" and randf() < 0.04):
		out.move = -n if boss.pat != "burst" else side
		out.dash = randf() < 0.08
	return out
