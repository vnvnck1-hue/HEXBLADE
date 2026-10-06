class_name PartnerDrone
extends Node3D
## 파트너 청소 드론 TRIAD — 미소녀 파트너가 탑승해 플레이어 메카와 함께 출격하는 소형 청소 기체.
## 내러티브 기준: docs/우주_출장_청소업체_내러티브.md 5~11절. 설계·조작·수치: docs/partner-drone.md
##
## 하는 일 (플레이어가 매번 명령하지 않아도 스스로 한다)
##  · 따라다니기: 플레이어 뒤쪽 옆에 붙어 다닌다. 멀어지면 뛰고, 너무 멀거나 벽에 막히면 추진기로 도약해 따라붙는다.
##  · 청소: 처치된 적이 남긴 잔해·체액(DroneMess)을 플레이어 둘레(WORK_RANGE)에서 가까운 것부터 하나씩 치운다.
##    세 모듈로 빨아들이며, 다 치우면 지원 게이지가 찬다. 플레이어가 LEASH 넘게 멀어지면 하던 일을 두고 따라간다.
##  · 위험 회피: 날아오는 적탄 · 근접 공격을 옆으로 콩 뛰어 피한다. 맞으면 잠깐 휘청이며 일을 멈춘다 (파괴되지 않음).
##  · 반응: 청소 끝 콩콩 · 방 정리 응원 · 심심하면 두리번 · 앞발 톡톡 · 탑승자 말풍선.
##
## 플레이어 조작
##  Q  누르면 바로: 합체(만화식 합체 연출) + 회오리 휠윈드 2초 → 끝나면 저절로 분리 (게이지 WHIRL_COST 필요, 휠윈드 동안 메카 무적).
##     어디 있든 추진기로 날아와 메카 등에 붙는다. (보통 합체 toggle_link 로 붙어 있을 때) 합체 중에는 드론 청소·충전이
##     멈추고 대신 광선검 속도 2배 · 기본 총 연사 2배 · 세 모듈 자동 사격 — 쓸 때마다 게이지를 깎는다. 게이지가 바닥나면 저절로 분리.
##     휠윈드: 몸 전체가 초당 12바퀴로 돌며 광선검·팔다리 리본이 원반을 그리고, 1.5배 빠르게 방향키로 움직이며
##     둘레 적에게 다단 피해. 허수아비 시험장(재화 무한)에서는 게이지가 늘 가득이라 무제한.
##  X  지원 스킬 (게이지 50): 분리 중 = 돌파 보호막(피격 1회 막음, 10초) · 합체 중 = 트리플 볼텍스(주변 적·오염을 끌어당겨 터뜨림)
##  Z  누르는 동안 직접 청소: 메카 팔로 앞쪽 오염을 빨아들인다 (빠르지만 공격 불가·조금 느려짐). 게이지도 찬다.
##  Space 누른 채 다니기 = 청소 질주: 짧게 누르면 평소 대시, 대시가 끝난 뒤에도 누르고 있으면 등 뒤에서 청소기를 꺼내
##     (등에 탱크가 튀어나옴) 앞바닥을 좌우로 쓸며(SweepGear), 둘레 SWEEP_R 안 오염을
##     전부 한꺼번에 빨아들인다 (오염마다 흡입 기류 · 발밑 민트 고리). 탄피 · 파편 · 몸체 조각 · 체액 얼룩 같은 바닥 잡조각도
##     함께 빨려 든다 (FloorVac, 게이지 없음 — 빨아들이지 않은 잡조각은 원래 수명대로 저절로 사라진다).
##     공격 불가 · 조금 느려짐 · 게이지.
##  (가만히) 플레이어가 오염 곁에 공격 없이 서 있으면 저절로 빨아들인다 (Z 보다 느림, 공격은 막지 않음).
##
## 기존 코드에 닿는 곳: Main._ready 의 attach 한 줄 · Main.on_enemy_killed 의 on_kill 한 줄 · Player.hit_guard (보호막 훅) ·
## Player.blade_boost / fire_boost (합체 강화) · Player.on_attack (강화 공격 게이지 소모) · Player.spin_pose (휠윈드 회오리 자세 · 리본).
## `--drone=off` 이면 붙지 않는다.

enum St { DEPLOY, FOLLOW, SEEK, CLEAN, HOP, HURT, RECALL, DOCKED, DETACH, CHEER, DOWN }

const STATUS := {
	St.DEPLOY: "출동", St.FOLLOW: "동행", St.SEEK: "오염으로 이동", St.CLEAN: "청소 중", St.HOP: "도약",
	St.HURT: "휘청!", St.RECALL: "합체 비행", St.DOCKED: "합체", St.DETACH: "분리", St.CHEER: "신남", St.DOWN: "대기",
}
const MODEL := "res://assets/models/partner_drone.glb"
const NAME := "TRIAD"

const WALK := 4.4
const RUN := 8.8
const ACCEL := 24.0
const TURN := 8.0                ## 최대 회전 (rad/s)
const NEAR := 2.0                ## 플레이어 곁 대기 자리까지 거리
const WORK_RANGE := 14.0         ## 플레이어에게서 이 거리 안의 오염을 맡는다 (적극적으로 넓게 찾는다)
const LEASH := 16.0              ## 일하다가도 플레이어가 이보다 멀어지면 따라간다
const JUMP_DIST := 18.0          ## 이보다 멀거나 막히면 추진기 도약
const CLEAN_RATE := 1.25         ## 초당 청소량 (잔해 하나 ≈ 1.0)
const CHAIN_RANGE := 7.0         ## 하나 치운 뒤 쉬지 않고 이어서 맡는 거리
const GAIN_MUL := 1.5            ## 청소 성과 → 게이지 효율 (오염 값 × 1.5)
const AUTO_RANGE := 3.0          ## 플레이어가 가만히 서 있으면 이 거리 안 오염을 저절로 빨아들인다
const AUTO_DELAY := 0.35         ## 이만큼 멈춰 있어야 자동 청소가 시작된다
const AUTO_RATE := 1.1
const PLAYER_CLEAN_RATE := 1.6
const PLAYER_CLEAN_RANGE := 3.6
const PLAYER_CLEAN_SLOW := 0.7
const SWEEP_R := 4.5             ## 청소 질주(Space 누른 채): 이 반경 안 오염을 전부 동시에
const SWEEP_RATE := 2.2          ## 청소 질주 중 오염 하나당 초당 청소량
const SWEEP_SLOW := 0.85
const SWEEP_STREAMS := 8         ## 동시에 보이는 흡입 기류 수 (가까운 것부터)
const GAUGE_MAX := 100.0
const SKILL_COST := 50.0
const PLAYER_GAIN := 0.8         ## 직접 청소한 오염의 게이지 비율
const SHIELD_TIME := 10.0
const LINK_CD := 0.5
const DOCK_MIN := 10.0           ## 합체하려면 이만큼 게이지가 있어야 한다 (합체 강화는 게이지를 먹고 산다)
const GATTAI_TIME := 0.22        ## Q 를 누른 뒤 드론이 날아와 붙기까지 (만화식 합체 비행)
const SLASH_COST := 2.5          ## 합체 중 광선검 한 단 (속도 2배 강화)
const SHOT_COST := 0.35          ## 합체 중 기본 총 한 발 (연사 2배 강화)
const TURRET_COST := 0.8         ## 합체 중 보조 사격 한 발
const WHIRL_COST := 30.0
const WHIRL_TIME := 2.0
const WHIRL_R := 2.8
const WHIRL_TICK := 0.1
const WHIRL_DMG := 2
const WHIRL_TURNS := 12.0        ## 초당 바퀴 수 — 눈으로 따라가기 힘든 회오리
const WHIRL_SPEED := 1.5         ## 휠윈드 중 이동 속도 배율
const WHIRL_LIFE := 0.24         ## 휠윈드 중 광선검 리본 수명 (평소 0.038 → 몇 바퀴가 겹쳐 원반처럼 남는다)
const WHIRL_REACH := 1.25
const WHIRL_PULL_R := 7.0        ## 휠윈드가 몬스터를 끌어들이는 반경 (칼날 WHIRL_R 바깥까지)
const WHIRL_PULL_V := Vector2(0.7, 2.1)   ## 끌려오는 속도 (m/s): 멀 때 ~ 가까울 때 — "조금씩" (2초 휠윈드 동안 2~3m)
const WHIRL_PULL_SWIRL := 0.45   ## 회전 방향으로 감기는 비율
const WHIRL_PULL_MIN := 1.1      ## 플레이어 몸에서 이 거리(+적 반경)까지만 끈다
const TURRET_GAP := 0.42
const TURRET_RANGE := 12.0
const VORTEX_R := 8.0
const VORTEX_PULL := 0.75
const VORTEX_DMG := 3
const DOCK_SCALE := 0.6
const DOCK_OFF := Vector3(0.0, 1.02, 0.66)   ## 조준 방향 기준 (뒤 = +Z)
const MINT := DroneFX.MINT

const LINES := {
	"deploy": ["출동 준비 완료!", "오늘도 깨끗하게!"],
	"clean_start": ["제가 치울게요!", "흡입 시작~!", "여긴 맡겨 주세요!"],
	"clean_done": ["반짝반짝!", "하나 끝!", "깨끗해졌어요!", "다음 거~!"],
	"follow": ["같이 가요~!", "잠깐만요!", "기다려요~!"],
	"dodge": ["어이쿠!", "위험해!", "휴~"],
	"hurt": ["꺄앗!", "아야…!", "으앗, 흔들려요!"],
	"ready": ["지원 준비됐어요! (X)", "게이지 충전 완료!"],
	"shield": ["보호막 갑니다!", "지켜 드릴게요!"],
	"block": ["막았어요!", "휴, 안전!"],
	"dock": ["합체할게요!", "꽉 붙을게요!"],
	"undock": ["다녀올게요!", "청소하러 갑니다~"],
	"vortex": ["트리플 볼텍스!", "전부 빨아들일게요!"],
	"clear": ["현장 정리 완료!", "우리 꽤 잘하죠?"],
	"idle": ["다음은 어디죠?", "흐음~", "오늘 보수 기대돼요!"],
	"down": ["안 돼…!"],
	"low": ["게이지가 모자라요!"],
	"empty": ["게이지가 바닥났어요!", "힘이 다 됐어요, 내려갈게요!"],
	"whirl": ["같이 돌아요!", "휘몰아쳐요~!", "회전 베기!"],
}

static var inst: PartnerDrone

var main: Main
var player: Player
var visual: Node3D               ## 몸 방향(yaw) · 도약 높이 · 합체 크기
var model: Node3D
var rig: DroneRig
var nozzle: Node3D
var top_pt: Node3D
var blob_anchor: Node3D
var shadow: MeshInstance3D
var suction: DroneFX.Suction
var p_suction: DroneFX.Suction
var shield: DroneFX.Shield
var bubble: SpeechBubble        ## 지금 떠 있는 대사 말풍선
var vac: AudioStreamPlayer
var hud_panel: DroneHud
var rng := RandomNumberGenerator.new()

var state := St.DEPLOY
var st_t := 0.0
var yaw := 0.0
var vel := Vector3.ZERO
var gauge := 0.0
var target: DroneMess
var cleaned := 0                 ## 드론이 치운 수
var player_cleaned := 0          ## 플레이어가 직접 치운 수
var shields_used := 0
var blocks := 0
var vortex_used := 0
var dodges := 0
var hits_taken := 0
var docks := 0
var hop := {}
var link_cd := 0.0
var turret_t := 0.0
var vortex_t := -1.0
var p_cleaning := false
var scale_k := 1.0
var bot := false
var whirl_t := -1.0              ## 휠윈드 경과 (-1 = 아님)
var whirls := 0
var auto_cleaning := false       ## 지금 플레이어가 가만히 서서 저절로 청소 중
var spent := 0.0                 ## 합체 강화로 쓴 게이지 합계 (확인용)
var sweeping := false            ## 지금 Space 를 누른 채 청소 질주 중
var sweep_k := 0.0               ## 청소 질주 세기 (켜지고 꺼질 때 부드럽게)
var swept := 0                   ## 청소 질주로 치운 수
var gear: SweepGear              ## 청소 질주 장비: 등 뒤에서 꺼내는 청소기 (탱크 · 흡입 막대 · 자세)
var junk: FloorVac               ## 청소 질주 잡조각 흡입: 탄피 · 파편 · 몸체 조각 · 체액 얼룩 · 웅덩이 (게이지 없음)
var sweep_streams: Array = []    ## 청소 질주 흡입 기류 (DroneFX.Suction)
var sweep_core: Node3D           ## 플레이어 가슴의 흡입 중심
var _sweep_ring_t := 0.0

var _blacklist := {}
var _search_t := 0.0
var _seek_best := INF
var _seek_stall := 0.0
var _stuck_t := 0.0
var _side := 1.0
var _idle_t := 0.0
var _look_t := 0.0
var _look_goal := 0.0
var _bark_t := 0.0
var _dodge_cd := 0.0
var _flash_t := 0.0
var _step_snd_t := 0.0
var _set_no_attack := false
var _slow_set := false
var _rooms_seen := 0
var _was_ready := false
var _down := false
var _dock_sway := Vector3.ZERO
var _dock_sway_v := Vector3.ZERO
var _prev_ppos := Vector3.ZERO
var _crouch_goal := 0.0
var _puff_t := 0.0
var _bot := {"phase": 0, "dock_t": 0.0, "clean_t": 0.0, "clean_cd": 6.0, "hold": 0}
var _whirl_pending := false      ## 합체가 끝나면 바로 휠윈드
var _whirl_ang := 0.0
var _whirl_tick := 0.0
var _whirl_ghost := 0
var _whirl_lock := false
var _still_t := 0.0
var _spin_prev := 0.0
var _whirl_fx := 0.0
var _pull_fx := 0.0
var _trail_keep := []
var _link_was := false
var _gattai := false            ## 지금 합체 비행이 만화식 합체인가
var cutin: CanvasLayer          ## Q 합체 컷인 (DiagonalDockingCutin 또는 예전 CockpitCutin — 같은 begin/notify_dock/cancel 계약)
## 합체 컷인 종류: "diagonal" 사선 DOCKING(기본, docs/diagonal-docking-cutin.md) · "cockpit" 예전 조종석(폐기 예정 보관본) ·
## "off" 컷인 없이 예전 GattaiFX 만. --cutin=diagonal|cockpit|off, 허수아비 시험장 0 키. static 이라 씬을 다시 불러도 유지.
const CUTIN_STYLES := ["diagonal", "cockpit", "off"]
static var cutin_style := "diagonal"
var _pop := 0.0                 ## 합체 직후 드론 크기 튕김 스프링 [값]
var _pop_v := 0.0
var _stretch := Vector3.ONE     ## 비행 중 늘어남 (과장)


## 지금 고른 종류의 합체 컷인을 띄운다 (off 면 null). preview = 드론 없이 보기 (허수아비 F3)
static func begin_cutin(scene: Node, owner_drone: Node, preview := false) -> CanvasLayer:
	match cutin_style:
		"diagonal":
			return DiagonalDockingCutin.begin(scene, owner_drone, preview)
		"cockpit":
			if preview:
				return null
			return CockpitCutin.begin(scene, owner_drone)
	return null


## Main 하위 씬(방 탐색 · 섹터 런 · 허수아비 · 기믹/벌레 시험장)에 드론 한 기를 붙인다
static func attach(m: Main) -> PartnerDrone:
	if m.showcase or Main.cmd_args.has("--drone=off"):
		return null
	var d := PartnerDrone.new()
	d.main = m
	m.world.add_child(d)
	return d


## 적 처치 → 그 자리에 오염을 남긴다 (Main.on_enemy_killed 가 부른다)
static func on_kill(e: Enemy) -> void:
	if not is_instance_valid(inst) or e == null or e.get("prop") or e.is_boss:
		return
	var pos := e.global_position
	if is_instance_valid(inst.main) and inst.main.map:
		pos = inst.main.push_out(pos, 0.5)
	pos.y = Main.gy(pos)
	var size := clampf(0.85 + float(e.max_hp) * 0.04, 0.85, 1.4)
	var goo: Variant = e.get("goo")
	if goo is Array and not (goo as Array).is_empty():
		DroneMess.spawn(inst.main.world, pos, DroneMess.Kind.GOO, size, (goo as Array)[0])
	else:
		DroneMess.spawn(inst.main.world, pos, DroneMess.Kind.SCRAP, size)


func _exit_tree() -> void:
	if inst == self:
		inst = null
	if is_instance_valid(cutin):
		cutin.queue_free()
	DockingVoice.stop()
	_release_player()


func _ready() -> void:
	inst = self
	rng.randomize()
	if main == null:
		main = Main.inst
	player = main.player
	DroneSound.ensure()
	_setup_input()
	bot = main.capture_mode and (Main.cmd_args.has("--dronebot") or main.has_method("drone_lab"))
	for a in Main.cmd_args:
		if String(a).begins_with("--cutin=") and CUTIN_STYLES.has(String(a).substr(8)):
			cutin_style = String(a).substr(8)
		elif String(a).begins_with("--cutin-tween="):
			DiagonalDockingCutin.use_tween_id(String(a).substr(14))
		elif String(a).begins_with("--cutin-char="):
			DiagonalDockingCutin.char_mode = String(a).substr(13)
		elif String(a).begins_with("--cutin-chars="):
			if String(a).substr(14) == "on":
				DiagonalDockingCutin.hidden_chars = []
	if cutin_style == "diagonal":
		DiagonalDockingCutin.prewarm.call_deferred(main)
		DockingVoice.warm()
	visual = Node3D.new()
	add_child(visual)
	model = (load(MODEL) as PackedScene).instantiate()
	visual.add_child(model)
	rig = DroneRig.new().setup(model)
	nozzle = model.find_child("pt_nozzle", true, false)
	top_pt = model.find_child("pt_top", true, false)
	blob_anchor = Node3D.new()
	add_child(blob_anchor)
	shadow = FX.blob_shadow(blob_anchor, 1.9, 0.6)
	BrawlLook.add_blob(blob_anchor, 0.62, Color(0.35, 1.0, 0.8, 0.8))
	suction = DroneFX.Suction.new()
	suction.nozzle = nozzle
	add_child(suction)
	p_suction = DroneFX.Suction.new()
	p_suction.nozzle = player.j.muzzle
	p_suction.width = 0.45
	add_child(p_suction)
	sweep_core = Node3D.new()
	player.add_child(sweep_core)
	sweep_core.position = Vector3(0, 1.0, 0)
	for i in SWEEP_STREAMS:
		var s := DroneFX.Suction.new()
		s.nozzle = sweep_core
		s.width = 0.38
		add_child(s)
		sweep_streams.append(s)
	gear = SweepGear.new()
	add_child(gear)
	gear.setup(player)
	junk = FloorVac.new()
	add_child(junk)
	vac = AudioStreamPlayer.new()
	vac.stream = DroneSound.vacuum_loop()
	vac.volume_db = -80.0
	add_child(vac)
	player.on_attack = _on_attack
	hud_panel = DroneHud.new()
	hud_panel.drone = self
	main.hud.root.add_child(hud_panel)
	# 플레이어 옆 하늘에서 떨어지며 등장한다
	yaw = atan2(-player.aim_dir.x, -player.aim_dir.z)
	var spot := player.global_position + Basis(Vector3.UP, yaw) * Vector3(1.6, 0, 1.2)
	global_position = _free_spot(spot)
	visual.rotation.y = yaw
	visual.position.y = 7.0
	rig.air = 1.0
	_prev_ppos = player.global_position
	_go(St.DEPLOY)
	_rooms_seen = main.rooms_cleared


func _setup_input() -> void:
	var keys := {"drone_link": KEY_Q, "drone_skill": KEY_X, "drone_clean": KEY_Z}
	for a: String in keys:
		if not InputMap.has_action(a):
			InputMap.add_action(a)
		InputMap.action_erase_events(a)
		var ev := InputEventKey.new()
		ev.physical_keycode = keys[a]
		InputMap.action_add_event(a, ev)


func _go(s: St) -> void:
	state = s
	st_t = 0.0


func status_text() -> String:
	if _down:
		return "대기"
	if whirl_t >= 0.0:
		return "합체 휠윈드"
	if auto_cleaning and state != St.CLEAN:
		return "같이 청소"
	return STATUS.get(state, "")


func docked() -> bool:
	return state == St.DOCKED


# ═══════════════════════════════════════════════════
#  매 틱
# ═══════════════════════════════════════════════════
func _physics_process(dt: float) -> void:
	if not is_instance_valid(player):
		return
	st_t += dt
	link_cd -= dt
	_dodge_cd -= dt
	_bark_t -= dt
	_read_input(dt)
	match state:
		St.DEPLOY: _deploy(dt)
		St.FOLLOW: _follow(dt)
		St.SEEK: _seek(dt)
		St.CLEAN: _clean(dt)
		St.HOP: _hop(dt)
		St.HURT: _hurt_state(dt)
		St.RECALL: _recall(dt)
		St.DOCKED: _docked(dt)
		St.DETACH: _hop(dt)
		St.CHEER: _cheer(dt)
		St.DOWN: _brake(dt)
	if state in [St.FOLLOW, St.SEEK, St.CLEAN]:
		_avoid_danger()
		_bullet_hits()
	_update_whirl(dt)               # 속도 배율(_goo_slow)보다 먼저: 끝난 틱에 바로 원래 속도로
	_player_clean(dt)
	_sweep(dt)
	_goo_slow()
	_update_shield(dt)
	_update_vortex(dt)
	_watch_events()
	_finish(dt)
	_prev_ppos = player.global_position


func _process(dt: float) -> void:
	if _flash_t > 0.0:
		_flash_t -= dt
		if _flash_t <= 0.0:
			rig.flash(false)


# ── 입력 (사람 · 봇) ─────────────────────────────────

func _read_input(dt: float) -> void:
	var playing := main.state == Main.State.PLAY and player.alive
	var link_held := false
	var skill := false
	var clean_held := false
	var sweep_held := false
	if bot:
		var b := _bot_input(dt)
		link_held = b.link
		skill = b.skill
		clean_held = b.clean
		sweep_held = b.get("sweep", false)
	else:
		link_held = Input.is_action_pressed("drone_link")
		skill = Input.is_action_just_pressed("drone_skill")
		clean_held = Input.is_action_pressed("drone_clean")
		# 누른 첫 틱은 대시 몫 (드론이 플레이어보다 먼저 돌아 대시 전 한 틱 청소기가 깜빡이지 않게)
		sweep_held = Input.is_action_pressed("dash") and not Input.is_action_just_pressed("dash")
	# 청소 질주: Space 를 누른 채로 대시가 끝났다 (누르는 순간의 대시 · 패링 · 2단 대시는 Player 가 그대로 처리한다)
	sweeping = sweep_held and playing and whirl_t < 0.0 and player.dash_t <= 0.0 and player.lunge_t <= 0.0 \
		and player.stun_t <= 0.0 and not player.tech.busy() and not player.ult_busy()
	p_cleaning = clean_held and playing and whirl_t < 0.0 and not sweeping
	if not playing:
		_link_was = false
		return
	_link_key(link_held, dt)
	if skill:
		use_skill()


## Q (누르는 순간): 분리 중이면 즉시 합체 → 붙자마자 회오리 휠윈드 → 끝나면 저절로 분리. (보통 합체로) 합체 중이면 휠윈드, 게이지가 모자라면 분리.
func _link_key(held: bool, _dt: float) -> void:
	var pressed := held and not _link_was
	_link_was = held
	if not pressed or link_cd > 0.0:
		return
	if state == St.DOCKED and whirl_t < 0.0 and gauge < WHIRL_COST:
		_detach()
		return
	whirl_link()


## 합체 + 휠윈드 → 휠윈드가 끝나면 저절로 분리. 게이지가 휠윈드만큼 없으면 거절 (합체 상태로 남지 않는다).
func whirl_link() -> void:
	if whirl_t >= 0.0 or _whirl_pending or state == St.RECALL:
		return
	if state == St.DOCKED:
		if gauge >= WHIRL_COST:
			_start_whirl()
		return
	if state not in [St.FOLLOW, St.SEEK, St.CLEAN, St.HOP, St.HURT, St.CHEER]:
		return
	if gauge < WHIRL_COST:
		main.hud.popup("휠윈드 게이지 %d/%d" % [int(gauge), int(WHIRL_COST)], Color("8affd8"), player.global_position + Vector3(0, 2.4, 0))
		bark_line("low", true)
		return
	_whirl_pending = true
	_begin_recall(true)
	link_cd = LINK_CD


## G: 합체 ↔ 분리
func toggle_link() -> void:
	if state == St.DOCKED:
		if whirl_t >= 0.0:
			return
		_detach()
	elif state in [St.FOLLOW, St.SEEK, St.CLEAN, St.HOP, St.HURT, St.CHEER]:
		if gauge < DOCK_MIN:
			main.hud.popup("합체 게이지 %d/%d" % [int(gauge), int(DOCK_MIN)], Color("8affd8"), player.global_position + Vector3(0, 2.4, 0))
			bark_line("low", true)
			return
		_begin_recall()
	else:
		return
	link_cd = LINK_CD


## X: 분리 중 보호막 · 합체 중 볼텍스
func use_skill() -> void:
	if state == St.DOCKED:
		if vortex_t >= 0.0:
			return
		if not _spend():
			return
		_begin_vortex()
	elif state in [St.FOLLOW, St.SEEK, St.CLEAN, St.HOP, St.CHEER]:
		if is_instance_valid(shield) and not shield.broken:
			main.hud.popup("보호막 유지 중", MINT, player.global_position + Vector3(0, 2.4, 0))
			return
		if not _spend():
			return
		_cast_shield()


func _spend() -> bool:
	if gauge < SKILL_COST:
		main.hud.popup("지원 게이지 %d/%d" % [int(gauge), int(SKILL_COST)], Color("8affd8"), player.global_position + Vector3(0, 2.4, 0))
		bark_line("low", true)
		return false
	gauge -= SKILL_COST
	return true


func add_gauge(v: float) -> void:
	gauge = minf(GAUGE_MAX, gauge + v)


# ═══════════════════════════════════════════════════
#  상태별 행동
# ═══════════════════════════════════════════════════

## 등장: 하늘에서 추진기로 감속하며 떨어져 쿵 착지
func _deploy(dt: float) -> void:
	var k := clampf(st_t / 0.65, 0.0, 1.0)
	visual.position.y = 7.0 * (1.0 - k) * (1.0 - k)
	rig.air = 1.0
	_thrust(dt, 0.04)
	if k >= 1.0:
		_land(1.0)
		bark_line("deploy", true)
		_go(St.FOLLOW)


## 따라다니기 · 오염 찾기 · 심심할 때 두리번
func _follow(dt: float) -> void:
	var goal := _follow_spot()
	var d := _flat(goal - global_position)
	var pd := _flat(player.global_position - global_position)
	_steer(goal, RUN if pd > NEAR * 3.0 else WALK, dt)
	if pd > JUMP_DIST or _stuck_t > 1.2:
		_catch_up()
		return
	_search_t -= dt
	if _search_t <= 0.0:
		_search_t = 0.1
		var m := _pick_mess(global_position)
		if m:
			_take(m)
			if rng.randf() < 0.45:
				bark_line("clean_start")
			return
	# 서 있을 때: 적이나 플레이어가 보는 곳을 바라보고, 가끔 두리번 · 혼잣말
	if d < 0.5 and vel.length() < 0.6:
		_idle_t += dt
		_face(_watch_point(), dt, 3.0)
		_look_t -= dt
		if _look_t <= 0.0:
			_look_t = rng.randf_range(1.2, 2.8)
			_look_goal = rng.randf_range(-0.6, 0.6) if rng.randf() < 0.6 else 0.0
		if _idle_t > 9.0 and rng.randf() < dt * 0.15:
			_idle_t = 0.0
			rig.happy = 0.5
			bark_line("idle")
	else:
		_idle_t = 0.0
		_look_goal = 0.0
		_face_vel(dt)


## 오염 앞 서는 자리로 간다
func _seek(dt: float) -> void:
	if not _target_ok():
		_after_clean()
		return
	if _flat(player.global_position - global_position) > LEASH:
		_leave_target(true)
		return
	var stand := _stand_spot(target)
	var d := _flat(stand - global_position)
	_steer(stand, RUN if d > 4.0 else WALK, dt)
	if d < 1.8:
		_face(target.global_position, dt, TURN)
	else:
		_face_vel(dt)
	# 가까워지지 않으면(벽 너머 등) 포기하고 잠시 목록에서 뺀다
	if d < _seek_best - 0.2:
		_seek_best = d
		_seek_stall = 0.0
	else:
		_seek_stall += dt
	if _seek_stall > 1.6 or _stuck_t > 1.0:
		_blacklist[target.get_instance_id()] = main.time + 6.0
		_leave_target(false)
		return
	if d < 0.32 or (d < 0.7 and vel.length() < 0.5):
		_go(St.CLEAN)
		Sfx.play("drone_hop", 0.1, -20.0)


## 숙여서 세 모듈로 빨아들인다
func _clean(dt: float) -> void:
	if not _target_ok():
		_after_clean()
		return
	if _flat(player.global_position - global_position) > LEASH:
		_leave_target(true)
		return
	_steer(_stand_spot(target), 1.2, dt)
	_face(target.global_position, dt, TURN)
	suction.from = target.global_position + Vector3(0, 0.12, 0)
	suction.width = target.radius * 0.8
	suction.col = MINT if target.kind == DroneMess.Kind.SCRAP else target.goo_col.lerp(MINT, 0.4)
	# 모듈이 바닥을 향할 만큼 숙인 뒤부터 빨린다
	if rig.clean < 0.6:
		return
	var m := target
	if m.clean(CLEAN_RATE * dt, nozzle.global_position):
		add_gauge(m.value * GAIN_MUL)
		cleaned += 1
		rig.happy = 1.0
		Sfx.play("drone_pop", 0.08, -6.0)
		if rng.randf() < 0.5:
			bark_line("clean_done")
		target = null
		_after_clean()


func _after_clean() -> void:
	target = null
	var m := _pick_mess(global_position, CHAIN_RANGE)
	if m:
		_take(m)
	else:
		_go(St.FOLLOW)


## 도약 (회피 · 따라붙기 · 분리 착지 공용): 웅크렸다 포물선으로 날아 착지
func _hop(dt: float) -> void:
	if float(hop.crouch) > 0.0:
		hop.crouch = float(hop.crouch) - dt
		_crouch_goal = 1.0
		vel = vel.move_toward(Vector3.ZERO, dt * 20.0)
		return
	_crouch_goal = 0.0
	hop.t = float(hop.t) + dt
	var k := clampf(float(hop.t) / float(hop.dur), 0.0, 1.0)
	var e := k if hop.kind != "jet" else k * k * (3.0 - 2.0 * k)
	var from: Vector3 = hop.from
	var to: Vector3 = hop.to
	var p := from.lerp(to, e)
	var prev := global_position
	p.y = lerpf(from.y, to.y, e)
	global_position = p
	vel = (p - prev) / dt
	vel.y = 0.0
	visual.position.y = float(hop.h) * 4.0 * k * (1.0 - k) + float(hop.get("y0", 0.0)) * (1.0 - k)
	rig.air = 1.0 if k < 0.92 else 0.0
	if hop.has("scale_from"):
		scale_k = lerpf(float(hop.scale_from), 1.0, minf(k * 1.6, 1.0))
		rig.fold = maxf(0.0, 1.0 - k * 2.0)
	if hop.kind == "jet":
		_thrust(dt, 0.035)
	if hop.kind != "dodge":
		_face(to if _flat(to - from) > 0.5 else _watch_point(), dt, TURN)
	if k >= 1.0:
		visual.position.y = 0.0
		_land(0.7 if hop.kind == "dodge" else 1.0)
		_go(hop.next)


func _hurt_state(dt: float) -> void:
	_brake(dt)
	if st_t > 0.85:
		_go(St.FOLLOW)


func _cheer(dt: float) -> void:
	_brake(dt)
	# 제자리 한 바퀴 + 콩콩
	yaw += dt * TAU / 1.1
	rig.yaw_rate = TAU / 1.1
	visual.rotation.y = yaw
	rig.happy = 1.0
	if st_t > 1.1:
		_go(St.FOLLOW)


func _brake(dt: float) -> void:
	vel = vel.move_toward(Vector3.ZERO, ACCEL * dt)
	_move(dt)


# ── 합체 · 분리 ───────────────────────────────────────

func _begin_recall(fast := false) -> void:
	_leave_target(false)
	var dur := clampf(_flat(player.global_position - global_position) / 18.0, 0.28, 0.65)
	_gattai = fast
	if fast:
		dur = GATTAI_TIME
		# 메카가 받을 준비: 움찔 웅크림 · 위를 올려다보듯 젖힘
		player.squash_v -= 7.0
		main.camera.fov_punch(-4.0)
		FX.flash(nozzle.global_position, Color(0.85, 1.0, 0.95), 0.8, 0.06)
		Sfx.play("launch", 0.0, -4.0)
		# 조종석 컷인 (소유자당 하나: 남아 있던 것은 바로 지우고 새로)
		if is_instance_valid(cutin):
			cutin.queue_free()
		cutin = begin_cutin(main, self)
	hop = {"from": global_position + Vector3(0, visual.position.y, 0), "t": 0.0, "dur": dur}
	visual.position.y = 0.0
	rig.air = 1.0
	_go(St.RECALL)
	DroneFX.tether(nozzle, player, 0.25)
	Sfx.play("drone_hop", 0.06, -4.0)
	bark_line("dock", true)


func _dock_xf() -> Transform3D:
	var py := atan2(-player.aim_dir.x, -player.aim_dir.z)
	var b := Basis(Vector3.UP, py)
	return Transform3D(b, player.global_position + b * DOCK_OFF + _dock_sway)


func _recall(dt: float) -> void:
	# 사선 컷인은 게임을 슬로우모션으로 거는데, 합체 비행은 컷인의 실제 시계에 맞춰 날아와 붙는다 (컷인 체류 안에 합체가 들어오게)
	if _gattai and is_instance_valid(cutin) and cutin is DiagonalDockingCutin:
		hop.t = maxf(float(hop.t), (cutin as DiagonalDockingCutin).t)
	else:
		hop.t = float(hop.t) + dt
	var k := clampf(float(hop.t) / float(hop.dur), 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	var xf := _dock_xf()
	var from: Vector3 = hop.from
	global_position = from.lerp(xf.origin, e) + Vector3.UP * sin(PI * k) * (2.4 if _gattai else 1.4)
	yaw = lerp_angle(yaw, xf.basis.get_euler().y, minf(1.0, dt * 10.0))
	visual.rotation.y = yaw
	scale_k = lerpf(1.0, DOCK_SCALE, e)
	if _gattai:
		# 만화식 과장: 두 바퀴 공중제비 · 위아래로 쭉 늘어났다 · 민트 잔상 줄줄이
		visual.rotation.x = -e * TAU * 2.0
		var st := sin(PI * k)
		_stretch = Vector3(1.0 - 0.3 * st, 1.0 + 0.6 * st, 1.0 - 0.3 * st)
		FX.afterimage(visual, Color(0.45, 1.0, 0.8, 0.5), 0.16)
		rig.charge = 1.0
	rig.air = 1.0
	rig.fold = e
	vel = Vector3.ZERO
	_thrust(dt, 0.03)
	if k >= 1.0:
		_go(St.DOCKED)
		docks += 1
		rig.fold = 1.0
		rig.air = 0.0
		visual.rotation.x = 0.0
		_stretch = Vector3.ONE
		turret_t = 0.3
		if _gattai:
			_gattai = false
			_gattai_impact()
		else:
			FX.flash(nozzle.global_position, Color(0.8, 1.0, 0.95), 0.9, 0.1)
			FX.ring(player.global_position + Vector3(0, 1.2, 0), 1.6, [Color.WHITE, MINT, Color("bffff0")], 0.3)
			Sfx.play("drone_dock", 0.03, -2.0)
			main.shake(0.15)
		if _whirl_pending:
			_whirl_pending = false
			_start_whirl()


func _docked(dt: float) -> void:
	# 메카 몸놀림을 따라 출렁 (스프링)
	var pv := (player.global_position - _prev_ppos) / dt
	_dock_sway_v += (-_dock_sway * 140.0 - _dock_sway_v * 13.0) * dt - Vector3(pv.x, 0, pv.z) * 0.012
	_dock_sway += _dock_sway_v * dt
	_dock_sway.y = clampf(_dock_sway.y, -0.15, 0.15)
	var xf := _dock_xf()
	global_position = xf.origin
	var gy := xf.basis.get_euler().y
	var before := yaw
	yaw = lerp_angle(yaw, gy, minf(1.0, dt * 14.0))
	rig.yaw_rate = angle_difference(before, yaw) / dt
	visual.rotation.y = yaw
	# 합체 직후 크기가 통 튀었다가 출렁이며 자리 잡는다
	_pop_v += (-_pop * 260.0 - _pop_v * 9.0) * dt
	_pop += _pop_v * dt
	scale_k = DOCK_SCALE * (1.0 + _pop)
	rig.fold = 1.0
	rig.air = 0.0
	vel = Vector3.ZERO
	if not player.alive:
		_detach()
		return
	_turret(dt)


## 합체 중 보조 사격: 세 모듈이 가까운 적에게 짧게 쏜다
func _turret(dt: float) -> void:
	turret_t -= dt
	if turret_t > 0.0 or player.no_attack or main.state != Main.State.PLAY:
		return
	var best: Enemy = null
	var bd := TURRET_RANGE
	for e in Enemy.live(get_tree()):
		var en := e as Enemy
		if not is_instance_valid(en) or not en.alive or not en.landed or en.get("prop"):
			continue
		var d := _flat(en.global_position - player.global_position)
		if d < bd and not _wall_between(nozzle.global_position, en.global_position):
			bd = d
			best = en
	if best == null:
		turret_t = 0.15
		return
	turret_t = TURRET_GAP
	_drain(TURRET_COST)
	var o := nozzle.global_position
	var dir := best.global_position - o
	dir.y = 0
	dir = dir.normalized().rotated(Vector3.UP, rng.randf_range(-0.03, 0.03))
	main.add_bullet(Bullet.make_player(o, dir, 48.0))
	FX.flash(o + dir * 0.15, MINT, 0.35, 0.06)
	rig.happy = maxf(rig.happy, 0.25)
	Sfx.play("drone_shot", 0.1, -12.0)


func _detach() -> void:
	var from := global_position
	var back := player.global_position - Basis(Vector3.UP, atan2(-player.aim_dir.x, -player.aim_dir.z)) * Vector3(_side * 1.0, 0, -2.2)
	var to := _free_spot(back)
	hop = {"from": Vector3(from.x, Main.gy(from), from.z), "to": to, "t": 0.0, "crouch": 0.0, "dur": 0.42, "h": 1.0,
		"y0": from.y - Main.gy(from), "kind": "detach", "next": St.FOLLOW, "scale_from": scale_k}
	global_position = hop.from
	visual.position.y = float(hop.y0)
	rig.air = 1.0
	_go(St.DETACH)
	Sfx.play("drone_undock", 0.04, -3.0)
	FX.sparks(from + Vector3(0, 0.3, 0), 8, [Color.WHITE, MINT], 4.0, 0.3, -8.0, 0.05)
	if player.alive:
		bark_line("undock", true)
	link_cd = LINK_CD


# ── 지원 스킬 ───────────────────────────────────────

## 돌파 보호막: 노즐에서 빔을 쏘아 플레이어를 감싼다. 피격 1회를 막고 깨진다
func _cast_shield() -> void:
	if is_instance_valid(shield):
		shield.queue_free()
	shield = DroneFX.Shield.new()
	shield.life = SHIELD_TIME
	player.add_child(shield)
	player.hit_guard = _guard
	shields_used += 1
	DroneFX.tether(nozzle, player, 0.35)
	rig.charge = 1.0
	rig.happy = 0.6
	Sfx.play("drone_shield", 0.02, -3.0)
	FX.ring(player.global_position + Vector3(0, 0.95, 0), 2.2, [Color.WHITE, MINT, Color("bffff0")], 0.3)
	bark_line("shield", true)


## Player.take_hit 이 피해 전에 부른다: 보호막이 있으면 막고 true
func _guard(from: Vector3) -> bool:
	if not is_instance_valid(shield) or shield.broken:
		return false
	blocks += 1
	shield.hit = 1.0
	var c := player.global_position + Vector3(0, 0.95, 0)
	var d := (c - from)
	d.y = 0
	shield.pop(d)
	FX.shockwave(player.global_position, MINT, 3.2, 0.3)
	FX.sparks(c - d.normalized() * 0.9, 16, [Color.WHITE, MINT, Color("bffff0")], 7.0, 0.4, -6.0, 0.06)
	Sfx.play("drone_break", 0.04, -2.0)
	main.shake(0.2)
	main.hitstop(0.05)
	# 깨지는 충격으로 몸 둘레 적탄을 지운다 (같은 탄이 바로 다음 틱에 맞지 않게)
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bn := b as Node3D
		if is_instance_valid(bn) and _flat(bn.global_position - player.global_position) < 1.8:
			FX.flash(bn.global_position, MINT, 0.35, 0.06)
			bn.queue_free()
	player.invuln = maxf(player.invuln, 0.6)
	bark_line("block", true)
	return true


func _update_shield(dt: float) -> void:
	if not is_instance_valid(shield):
		if player.hit_guard.is_valid() and player.hit_guard.get_object() == self:
			player.hit_guard = Callable()
		return
	if shield.broken:
		return
	shield.life -= dt
	if shield.life <= 0.0 or not player.alive:
		shield.pop()


## 트리플 볼텍스 (합체 중): 바닥 소용돌이로 주변 적·오염을 끌어당겼다가 한꺼번에 터뜨린다
func _begin_vortex() -> void:
	vortex_t = 0.0
	vortex_used += 1
	rig.charge = 1.0
	DroneFX.vortex_disc(player, VORTEX_R, VORTEX_PULL)
	Sfx.play("drone_charge", 0.02, -2.0)
	bark_line("vortex", true)


func _update_vortex(dt: float) -> void:
	if vortex_t < 0.0:
		return
	vortex_t += dt
	var c := player.global_position
	if vortex_t < VORTEX_PULL:
		var k := vortex_t / VORTEX_PULL
		for e in Enemy.live(get_tree()):
			var en := e as Enemy
			if not is_instance_valid(en) or not en.alive or en.is_boss or en.get("prop"):
				continue
			var to := c - en.global_position
			to.y = 0
			var d := to.length()
			if d > VORTEX_R or d < 2.0:
				continue
			var step := to / d * minf(d - 2.0, (4.0 + 10.0 * k) * dt)
			en.global_position = main.push_out(en.global_position + step, en.radius)
			if rng.randf() < dt * 10.0:
				FX.sparks(en.global_position + Vector3(0, 0.8, 0), 2, [MINT, Color.WHITE], 3.0, 0.2, 0.0, 0.04)
		for m in get_tree().get_nodes_in_group(DroneMess.GROUP):
			var dm := m as DroneMess
			if is_instance_valid(dm) and not dm.done and _flat(dm.global_position - c) < VORTEX_R:
				dm.clean(dm.work_max * dt / VORTEX_PULL * 1.3, nozzle.global_position)
		return
	# 터짐
	vortex_t = -1.0
	rig.charge = 0.0
	rig.happy = 1.0
	var hit := 0
	for e in Enemy.live(get_tree()):
		var en := e as Enemy
		if not is_instance_valid(en) or not en.alive or en.get("prop"):
			continue
		var out := en.global_position - c
		out.y = 0
		if out.length() > VORTEX_R * 0.6:
			continue
		var dir := out.normalized() if out.length() > 0.1 else Vector3.FORWARD
		en.take_hit(VORTEX_DMG, dir, en.global_position + Vector3(0, 0.9, 0), "vortex")
		if en.alive and en.has_method("stagger") and not en.is_boss:
			en.stagger(dir, 1.1)
		hit += 1
	FX.shockwave(c, MINT, VORTEX_R * 0.9, 0.45, 0.12)
	FX.shockwave(c, Color.WHITE, VORTEX_R * 0.5, 0.3)
	FX.sparks(c + Vector3(0, 1.0, 0), 30, [Color.WHITE, MINT, Color("bffff0")], 11.0, 0.5, -6.0, 0.07)
	FX.flash(c + Vector3(0, 1.0, 0), Color(0.8, 1.0, 0.95), 2.4, 0.12)
	Sfx.play("drone_burst", 0.02, 0.0)
	main.shake(0.55)
	main.hitstop(0.08)
	if hit > 0:
		main.hud.popup("VORTEX ×%d" % hit, MINT, c + Vector3(0, 2.6, 0))


# ── 플레이어 직접 청소 (Z) ────────────────────────────

func _player_clean(dt: float) -> void:
	# 가만히 서 있나: 움직이지 않고 · 쏘거나 베거나 모으지 않는 채로 AUTO_DELAY 지남
	var mv := _flat(player.global_position - _prev_ppos) / maxf(dt, 0.0001)
	var calm := player.alive and main.state == Main.State.PLAY and mv < 0.3 and not player.combo.committed() \
		and player.fire_cd < -0.25 and not player.charging and not player.tech.busy() and whirl_t < 0.0 and player.dash_t <= 0.0
	_still_t = _still_t + dt if calm else 0.0
	var auto := not p_cleaning and not sweeping and _still_t >= AUTO_DELAY
	if p_cleaning or sweeping:
		player.no_attack = true
		_set_no_attack = true
	elif _set_no_attack:
		_set_no_attack = false
		player.no_attack = false
	auto_cleaning = false
	if not (p_cleaning or auto):
		p_suction.on = move_toward(p_suction.on, 0.0, dt * 5.0)
		return
	var aim := player.aim_dir
	aim.y = 0
	aim = aim.normalized() if aim.length() > 0.1 else Vector3.FORWARD
	var best: DroneMess = null
	var bd := PLAYER_CLEAN_RANGE if p_cleaning else AUTO_RANGE
	for m in get_tree().get_nodes_in_group(DroneMess.GROUP):
		var dm := m as DroneMess
		if not is_instance_valid(dm) or dm.done:
			continue
		var rel := dm.global_position - player.global_position
		rel.y = 0
		var d := rel.length()
		# Z 는 앞쪽(가까우면 아무 쪽) · 가만히 서 있으면 둘레 아무 쪽
		if d < bd and (auto or d < 1.3 or rel.normalized().dot(aim) > 0.55):
			bd = d
			best = dm
	if best == null:
		if p_cleaning:
			# 대상이 없어도 앞쪽으로 흡입 기류는 보인다
			p_suction.from = player.global_position + aim * 2.6 + Vector3(0, 0.1, 0)
			p_suction.on = move_toward(p_suction.on, 0.35, dt * 6.0)
		else:
			p_suction.on = move_toward(p_suction.on, 0.0, dt * 5.0)
		return
	auto_cleaning = auto
	var muzzle: Node3D = player.j.muzzle
	p_suction.from = best.global_position + Vector3(0, 0.12, 0)
	p_suction.on = move_toward(p_suction.on, 1.0 if p_cleaning else 0.8, dt * 6.0)
	p_suction.col = MINT if best.kind == DroneMess.Kind.SCRAP else best.goo_col.lerp(MINT, 0.4)
	if best == target:
		_leave_target(false)
	if best.clean((PLAYER_CLEAN_RATE if p_cleaning else AUTO_RATE) * dt, muzzle.global_position):
		var gain := best.value * PLAYER_GAIN * GAIN_MUL
		add_gauge(gain)
		player_cleaned += 1
		Sfx.play("drone_pop", 0.08, -8.0)
		main.hud.popup("+%d" % int(gain), MINT, best.global_position + Vector3(0, 1.2, 0))


## 청소 질주 (Space 누른 채): 둘레 SWEEP_R 안 오염을 전부 동시에 빨아들인다. 가까운 SWEEP_STREAMS 개에는 흡입 기류가 보인다.
## 그동안 SweepGear 는 등 뒤에서 청소기를 꺼내 앞바닥을 쓰는 자세만 맡는다 (판정 · 효과는 여기).
func _sweep(dt: float) -> void:
	gear.update(dt, sweeping)
	sweep_k = move_toward(sweep_k, 1.0 if sweeping else 0.0, dt * (8.0 if sweeping else 5.0))
	var near: Array = []
	if sweeping:
		for m in get_tree().get_nodes_in_group(DroneMess.GROUP):
			var dm := m as DroneMess
			if not is_instance_valid(dm) or dm.done:
				continue
			var d := _flat(dm.global_position - player.global_position)
			if d < SWEEP_R + dm.radius * 0.5:
				near.append([d, dm])
		near.sort_custom(func(a: Array, b: Array): return float(a[0]) < float(b[0]))
		# 발밑 민트 고리: 빨아들이는 범위가 보이게 일정 간격으로 조여 든다
		_sweep_ring_t -= dt
		if _sweep_ring_t <= 0.0:
			_sweep_ring_t = 0.22
			var g := player.global_position + Vector3(0, 0.06, 0)
			FX.ring(g, SWEEP_R, [MINT, Color("bffff0"), Color.WHITE], 0.3)
			if not near.is_empty():
				FX.sparks(g + Vector3(0, 0.4, 0), 4, [Color.WHITE, MINT], 3.0, 0.3, -2.0, 0.04)
	var core := sweep_core.global_position
	# 바닥의 잡조각(탄피 · 파편 · 몸체 조각 · 체액)도 전부 함께 빨려 든다. 게이지에는 들어가지 않는다.
	if sweeping:
		junk.pull(player.global_position, SWEEP_R)
	junk.step(dt, core)
	junk.flush_count(dt, player.global_position)
	for i in sweep_streams.size():
		var s: DroneFX.Suction = sweep_streams[i]
		if i < near.size():
			var dm: DroneMess = near[i][1]
			s.from = dm.global_position + Vector3(0, 0.12, 0)
			s.col = MINT if dm.kind == DroneMess.Kind.SCRAP else dm.goo_col.lerp(MINT, 0.4)
			s.on = move_toward(s.on, sweep_k * 0.55, dt * 8.0)     # 여러 줄이 겹치므로 한 줄은 옅게
		else:
			s.on = move_toward(s.on, 0.0, dt * 6.0)
	for e: Array in near:
		var dm: DroneMess = e[1]
		if dm == target:
			_leave_target(false)
		if dm.clean(SWEEP_RATE * dt * sweep_k, core):
			var gain := dm.value * PLAYER_GAIN * GAIN_MUL
			add_gauge(gain)
			player_cleaned += 1
			swept += 1
			var pop := Sfx.play("drone_pop", 0.08, -8.0)
			if pop:
				pop.pitch_scale = 1.0 + minf(swept % 8, 7) * 0.06     # 연달아 치우면 음이 올라간다
			main.hud.popup("+%d" % int(gain), MINT, dm.global_position + Vector3(0, 1.2, 0))


## 체액 웅덩이를 밟으면 살짝 느려진다 · 직접 청소 중에도 느려진다
func _goo_slow() -> void:
	var k := 1.0
	for m in get_tree().get_nodes_in_group(DroneMess.GROUP):
		var dm := m as DroneMess
		if is_instance_valid(dm) and dm.covers(player.global_position):
			k = DroneMess.GOO_SLOW
			break
	if p_cleaning:
		k *= PLAYER_CLEAN_SLOW
	if sweeping:
		k *= SWEEP_SLOW
	if whirl_t >= 0.0:
		k *= WHIRL_SPEED          # 회오리 상태는 평소보다 빠르게 달린다
	if not is_equal_approx(k, 1.0) or _slow_set:
		player.slow_mul = k
		_slow_set = not is_equal_approx(k, 1.0)


func _release_player() -> void:
	if not is_instance_valid(player):
		return
	if _set_no_attack:
		player.no_attack = false
	if _slow_set:
		player.slow_mul = 1.0
	if is_instance_valid(gear):
		gear.release()
	if is_instance_valid(junk):
		junk.clear()
	if is_instance_valid(sweep_core):
		sweep_core.queue_free()
	if player.hit_guard.is_valid() and player.hit_guard.get_object() == self:
		player.hit_guard = Callable()
	if player.on_attack.is_valid() and player.on_attack.get_object() == self:
		player.on_attack = Callable()
	_end_whirl_pose()
	if _whirl_lock:
		player.no_attack = false
	player.blade_boost = 1.0
	player.fire_boost = 1.0


# ── 위험 회피 · 피격 ───────────────────────────────────

func _avoid_danger() -> void:
	if _dodge_cd > 0.0:
		return
	var c := global_position + Vector3(0, 0.6, 0)
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		if bl == null or not is_instance_valid(bl):
			continue
		var rel := c - bl.global_position
		rel.y = 0
		var v := Vector3(bl.vel.x, 0, bl.vel.z)
		var sp := v.length()
		if sp < 0.5 or rel.length() > 3.2:
			continue
		var tt := rel.dot(v) / (sp * sp)
		if tt < 0.0 or tt > 0.4:
			continue
		var miss := (rel - v * tt).length()
		if miss > 0.9:
			continue
		# 탄 진행 방향의 옆으로, 탄 궤적에서 먼 쪽으로 뛴다
		var side := v.cross(Vector3.UP).normalized()
		if side.dot(rel - v * tt) < 0.0:
			side = -side
		if rng.randf() < 0.8:
			_dodge(side)
		else:
			_dodge_cd = 0.5
		return
	for e in Enemy.live(get_tree()):
		var en := e as Enemy
		if not is_instance_valid(en) or not en.alive or en.get("prop"):
			continue
		var rel := global_position - en.global_position
		rel.y = 0
		if rel.length() < en.radius + 1.0 and (en.windup_k > 0.15 or en.parry_committed()):
			_dodge(rel.normalized())
			return


func _dodge(dir: Vector3) -> void:
	_dodge_cd = 1.0
	dodges += 1
	var to := _free_spot(global_position + dir * 1.8)
	var back := St.SEEK if is_instance_valid(target) else St.FOLLOW
	if state == St.CLEAN:
		back = St.SEEK
	hop = {"from": global_position, "to": to, "t": 0.0, "crouch": 0.0, "dur": 0.3, "h": 0.55, "kind": "dodge", "next": back}
	_seek_best = INF
	_go(St.HOP)
	rig.happy = 0.0
	Sfx.play("drone_hop", 0.1, -10.0)
	if rng.randf() < 0.5:
		bark_line("dodge")


## 피하지 못한 적탄은 드론에 맞는다: 탄은 사라지고 드론은 잠깐 휘청 (파괴되지 않는다)
func _bullet_hits() -> void:
	var c := global_position + Vector3(0, 0.6 * scale_k, 0)
	for b in get_tree().get_nodes_in_group("enemy_bullets"):
		var bl := b as Bullet
		if bl == null or not is_instance_valid(bl):
			continue
		var rel := bl.global_position - c
		if Vector2(rel.x, rel.z).length() < 0.62 and absf(rel.y) < 0.9:
			_hurt(bl.vel)
			FX.bullet_hit(bl.global_position, Pal.E_BULLETS[1])
			bl.queue_free()
			return


func _hurt(dir: Vector3) -> void:
	hits_taken += 1
	rig.hurt = 1.0
	rig.hurt_dir = dir.normalized()
	rig.flash(true)
	_flash_t = 0.07
	FX.sparks(global_position + Vector3(0, 0.7, 0), 10, [Color.WHITE, Color("ffd070"), MINT], 5.0, 0.35, -10.0, 0.05)
	FX.puffs(global_position + Vector3(0, 0.9, 0), 2, [Color(0.45, 0.45, 0.55), Color(0.38, 0.38, 0.48), Color(0.14, 0.14, 0.2), Color(0.1, 0.1, 0.16)], 0.3, 0.4, 0.8)
	Sfx.play("drone_hurt", 0.1, -6.0)
	bark_line("hurt", true)
	vel = Vector3(dir.x, 0, dir.z).normalized() * 3.0
	if state == St.CLEAN or state == St.SEEK:
		_leave_target(false)
	_go(St.HURT)


# ── 사건에 반응 ───────────────────────────────────────

func _watch_events() -> void:
	if main.rooms_cleared > _rooms_seen:
		_rooms_seen = main.rooms_cleared
		if state in [St.FOLLOW, St.SEEK, St.CLEAN]:
			_leave_target(false)
			_go(St.CHEER)
		bark_line("clear", true)
	var ready := gauge >= SKILL_COST
	if ready and not _was_ready:
		bark_line("ready", true)
		FX.ring(global_position + Vector3(0, 0.1, 0), 1.6, [Color.WHITE, MINT, Color("bffff0")], 0.35)
	_was_ready = ready
	if not player.alive and not _down:
		_down = true
		_leave_target(false)
		if state == St.DOCKED:
			_detach()
		bark_line("down", true)
	if main.state == Main.State.WIN and state == St.FOLLOW and fmod(main.time, 2.5) < get_physics_process_delta_time():
		_go(St.CHEER)


# ═══════════════════════════════════════════════════
#  공통 이동 · 방향 · 마무리
# ═══════════════════════════════════════════════════

## 플레이어 뒤쪽 옆자리 (조준 방향 기준). 좌우는 지금 있는 쪽을 유지한다
func _follow_spot() -> Vector3:
	var aim := player.aim_dir
	aim.y = 0
	aim = aim.normalized() if aim.length() > 0.1 else Vector3.FORWARD
	var right := aim.cross(Vector3.UP)
	var rel := global_position - player.global_position
	var s := rel.dot(right)
	if absf(s) > 0.6:
		_side = signf(s)
	if _down:
		return global_position
	return main.push_out(player.global_position - aim * 1.5 + right * _side * 1.25, 0.6)


func _stand_spot(m: DroneMess) -> Vector3:
	var from := global_position - m.global_position
	from.y = 0
	if from.length() < 0.1:
		from = Vector3.BACK
	return main.push_out(m.global_position + from.normalized() * (m.radius + 0.55), 0.5)


func _steer(goal: Vector3, max_speed: float, dt: float) -> void:
	var to := goal - global_position
	to.y = 0
	var d := to.length()
	var want := Vector3.ZERO
	if d > 0.12:
		want = to / d * minf(max_speed, d * 3.0 + 0.4)
	# 메카와 겹치지 않게 비켜선다
	var ap := global_position - player.global_position
	ap.y = 0
	if ap.length() < 1.35 and ap.length() > 0.01:
		want += ap.normalized() * (1.35 - ap.length()) * 7.0
	vel = vel.move_toward(want, ACCEL * dt)
	_move(dt)


func _move(dt: float) -> void:
	var want := vel * dt
	var p := global_position + want
	if main.map:
		p = main.push_out(p, 0.5)
	p.y = Main.gy(p)
	var moved := _flat(p - global_position)
	if want.length() > 0.02 and moved < want.length() * 0.3:
		_stuck_t += dt
	else:
		_stuck_t = maxf(0.0, _stuck_t - dt * 2.0)
	global_position = p


func _face(at: Vector3, dt: float, rate: float) -> void:
	var to := at - global_position
	if Vector2(to.x, to.z).length() < 0.05:
		rig.yaw_rate = 0.0
		return
	var goal := atan2(-to.x, -to.z)
	var diff := angle_difference(yaw, goal)
	var step := clampf(diff, -rate * dt, rate * dt)
	yaw += step
	rig.yaw_rate = step / dt
	visual.rotation.y = yaw


func _face_vel(dt: float) -> void:
	if vel.length() > 0.4:
		_face(global_position + vel, dt, TURN)
	else:
		rig.yaw_rate = 0.0


## 서 있을 때 바라볼 곳: 가까운 적 → 플레이어가 조준하는 곳
func _watch_point() -> Vector3:
	var best: Enemy = null
	var bd := 9.0
	for e in Enemy.live(get_tree()):
		var en := e as Enemy
		if is_instance_valid(en) and en.alive and not en.get("prop"):
			var d := _flat(en.global_position - global_position)
			if d < bd:
				bd = d
				best = en
	if best:
		return best.global_position
	return player.aim_point


## 너무 멀거나 막혔을 때: 웅크렸다가 추진기로 크게 뛰어 플레이어 옆에 내려앉는다 (벽도 넘는다)
func _catch_up() -> void:
	var to := _free_spot(_follow_spot())
	var d := _flat(to - global_position)
	hop = {"from": global_position, "to": to, "t": 0.0, "crouch": 0.14, "dur": clampf(d / 15.0, 0.45, 0.95),
		"h": 2.2 + d * 0.07, "kind": "jet", "next": St.FOLLOW}
	_stuck_t = 0.0
	_go(St.HOP)
	Sfx.play("drone_hop", 0.08, -6.0)
	bark_line("follow")


func _land(k: float) -> void:
	visual.position.y = 0.0
	rig.air = 0.0
	rig.crouch = 0.9 * k
	rig.reset_feet()
	FX.land_dust(global_position)
	Sfx.play("drone_step", 0.1, -8.0)
	if k >= 1.0:
		FX.shockwave(global_position, Color(0.75, 1.0, 0.92), 1.4, 0.25)


func _thrust(dt: float, gap: float) -> void:
	_puff_t -= dt
	if _puff_t > 0.0:
		return
	_puff_t = gap
	var b := global_position + Vector3(0, visual.position.y + 0.35 * scale_k, 0)
	FX.boost_puff(b + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)), Vector3(0, -6, 0))


func _free_spot(p: Vector3) -> Vector3:
	var q := main.push_out(p, 0.6) if main.map else p
	if main.map and main.is_blocked(q):
		q = player.global_position
	q.y = Main.gy(q)
	return q


func _wall_between(a: Vector3, b: Vector3) -> bool:
	if not main.map:
		return false
	var n := int(ceil(_flat(b - a) / 0.5))
	for i in range(1, n):
		if main.is_blocked(a.lerp(b, float(i) / n)):
			return true
	return false


# ── 오염 고르기 ───────────────────────────────────────

## 플레이어 둘레 WORK_RANGE 안 · 드론에서 가까운 것 (아직 남은 일이 많은 체액 웅덩이를 조금 먼저)
func _pick_mess(from: Vector3, max_d := INF) -> DroneMess:
	if _down:
		return null
	var best: DroneMess = null
	var bs := INF
	for m in get_tree().get_nodes_in_group(DroneMess.GROUP):
		var dm := m as DroneMess
		if not is_instance_valid(dm) or dm.done:
			continue
		if _blacklist.get(dm.get_instance_id(), -1.0) > main.time:
			continue
		if _flat(dm.global_position - player.global_position) > WORK_RANGE:
			continue
		var d := _flat(dm.global_position - from)
		if d > max_d:
			continue
		var score := d - (0.8 if dm.kind == DroneMess.Kind.GOO else 0.0)
		if score < bs:
			bs = score
			best = dm
	return best


func _take(m: DroneMess) -> void:
	target = m
	m.claim = self
	_seek_best = INF
	_seek_stall = 0.0
	_go(St.SEEK)


func _target_ok() -> bool:
	return is_instance_valid(target) and not target.done


func _leave_target(follow: bool) -> void:
	if is_instance_valid(target) and target.claim == self:
		target.claim = null
	target = null
	if follow:
		_go(St.FOLLOW)
		bark_line("follow")


# ── 마무리: 리그 입력 · 소리 · 말풍선 ─────────────────

func _finish(dt: float) -> void:
	# 합체 강화: 광선검 속도 2배 · 기본 총 연사 2배 (쓸 때마다 _on_attack 이 게이지를 깎는다)
	var boosted := state == St.DOCKED
	player.blade_boost = 2.0 if boosted else 1.0
	player.fire_boost = 2.0 if boosted else 1.0
	if boosted and gauge <= 0.0 and whirl_t < 0.0 and vortex_t < 0.0:
		gauge = 0.0
		bark_line("empty", true)
		_detach()
	visual.scale = _stretch * scale_k
	blob_anchor.visible = state != St.DOCKED and state != St.RECALL
	rig.vel = vel
	rig.clean = move_toward(rig.clean, 1.0 if state == St.CLEAN else 0.0, dt * 4.0)
	rig.crouch = move_toward(rig.crouch, _crouch_goal, dt * 5.0)
	rig.charge = move_toward(rig.charge, 1.0 if vortex_t >= 0.0 else 0.0, dt * 3.0)
	rig.look = lerpf(rig.look, _look_goal, 1.0 - exp(-5.0 * dt))
	if state not in [St.RECALL, St.DOCKED, St.DETACH, St.HOP, St.DEPLOY]:
		rig.fold = move_toward(rig.fold, 0.0, dt * 4.0)
	rig.glow = 0.55 if gauge >= SKILL_COST else 0.35
	rig.update(dt)
	suction.on = move_toward(suction.on, 1.0 if state == St.CLEAN and rig.clean > 0.5 else 0.0, dt * 5.0)
	# 발소리 (너무 잦지 않게)
	_step_snd_t -= dt
	if (rig.stepped > 0 or rig.tapped) and _step_snd_t <= 0.0:
		_step_snd_t = 0.07
		Sfx.play("drone_step", 0.15, -15.0 if rig.stepped > 0 else -19.0)
	# 흡입 소리: 드론 · 플레이어 · 볼텍스 중 센 쪽
	var v := maxf(maxf(suction.on, p_suction.on * 0.85), sweep_k * 0.95)
	if vortex_t >= 0.0:
		v = 1.0
	if v > 0.02:
		if not vac.playing:
			vac.play()
		vac.volume_db = linear_to_db(v * 0.42) - (80.0 if Sfx.inst and Sfx.inst.muted else 0.0)
		vac.pitch_scale = 0.9 + v * 0.25 + (0.4 if vortex_t >= 0.0 else 0.0)
	elif vac.playing:
		vac.stop()


# ── 합체 강화의 게이지 소모 · 휠윈드 ─────────────────

## Player.on_attack: 합체 중 강화된 공격을 쓸 때마다 게이지를 깎는다
func _on_attack(kind: String) -> void:
	if state != St.DOCKED:
		return
	match kind:
		"slash": _drain(SLASH_COST)
		"shot": _drain(SHOT_COST)


func _drain(v: float) -> void:
	var before := gauge
	gauge = maxf(0.0, gauge - v)
	spent += before - gauge


## 합체 휠윈드: 임팩트(흑백 프레임 · 섬광 · 충격파) 뒤 1.5초 동안 메카가 광선검을 펼친 채 회전한다.
## 플레이어는 방향키로 움직일 수 있고, 둘레 WHIRL_R 안 적에게 WHIRL_TICK 마다 피해.
func _start_whirl() -> void:
	gauge -= WHIRL_COST
	spent += WHIRL_COST
	whirls += 1
	whirl_t = 0.0
	_whirl_tick = 0.0
	_whirl_ang = atan2(-player.aim_dir.x, -player.aim_dir.z)
	player.combo.cancel(true)
	player.no_attack = true
	_whirl_lock = true
	_whirl_guard()
	player.spin_pose = _whirl_pose
	_spin_prev = _whirl_ang
	_trail_keep = [player.trail.life, player.trail.reach, player.trail.bright]
	player.trail.life = WHIRL_LIFE
	player.trail.reach = WHIRL_REACH
	player.trail.bright = 1.0          # 회오리는 원래 밝기 그대로 (기본 광선검은 절반)
	player.trail.boost = 1.0
	main.camera.fov_punch(9.0)
	Distortion.burst(player.global_position + Vector3(0, 0.8, 0), 3.0, 0.3, 1.2)
	GustFX.dash_burst(player.global_position, -player.aim_dir, Color(0.6, 1.0, 0.85))
	Sfx.play("roll", 0.0, 0.0)
	var c := player.global_position + Vector3(0, 0.95, 0)
	FX.flash(c, Color(0.85, 1.0, 0.95), 2.6, 0.12)
	FX.shockwave(player.global_position, MINT, 5.0, 0.4, 0.12)
	FX.shockwave(player.global_position, Color.WHITE, 3.0, 0.25)
	FX.sparks(c, 26, [Color.WHITE, MINT, Pal.BLADE], 10.0, 0.45, -6.0, 0.07)
	Sfx.play("drone_burst", 0.02, -2.0)
	main.shake(0.5)
	rig.happy = 1.0
	bark_line("whirl", true)


## 휠윈드 무적: 시작 순간부터 끝나는 순간까지. 남은 휠윈드 시간만큼만 걸어 끝난 뒤로 무적이 길게 남지 않는다 (기존 무적이 더 길면 그대로).
func _whirl_guard() -> void:
	player.invuln = maxf(player.invuln, WHIRL_TIME - maxf(whirl_t, 0.0) + 0.02)


func _update_whirl(dt: float) -> void:
	if whirl_t < 0.0:
		return
	whirl_t += dt
	if player.alive:
		_whirl_guard()
	var k := whirl_t / WHIRL_TIME
	# 0.1초 만에 최고 회전 → 끝 0.2초에 살짝 풀린다. 약 8바퀴
	var ramp := smoothstep(0.0, 0.1, whirl_t) * (1.0 - 0.45 * smoothstep(0.86, 1.0, k))
	_whirl_ang += dt * TAU * WHIRL_TURNS * ramp
	if player.alive:
		_whirl_pull(dt, ramp)
	# 회오리: 몸 둘레로 감기는 고리 · 발밑 흙먼지 · 약한 떨림
	_whirl_fx -= dt
	if _whirl_fx <= 0.0 and player.alive:
		_whirl_fx = 0.05
		var c := player.global_position + Vector3(0, randf_range(0.4, 1.4), 0)
		FX.vortex(c, Basis(Vector3.UP, _whirl_ang) * Basis.from_scale(Vector3.ONE * randf_range(1.6, 2.4)), MINT if randf() < 0.5 else Pal.BLADE)
		FX.puffs(Vector3(player.global_position.x, Main.gy(player.global_position) + 0.05, player.global_position.z), 1,
			[Color(0.55, 0.6, 0.75), Color(0.45, 0.5, 0.65), Color(0.2, 0.22, 0.32), Color(0.16, 0.18, 0.28)], 1.2, 0.4, 0.5)
		main.shake(0.06)
	_whirl_tick -= dt
	if _whirl_tick <= 0.0 and player.alive:
		_whirl_tick = WHIRL_TICK
		FX.slash(player, _whirl_ang + PI * 0.5, 3 if int(whirl_t / WHIRL_TICK) % 4 == 0 else 0)
		var sl := Sfx.play("slash", 0.15, -5.0)
		if sl:
			sl.pitch_scale = randf_range(1.15, 1.35)
		for e in Enemy.live(get_tree()):
			var en := e as Enemy
			if not is_instance_valid(en) or not en.alive or not en.landed or en.get("prop"):
				continue
			var out := en.global_position - player.global_position
			out.y = 0
			if out.length() > WHIRL_R + en.radius:
				continue
			var dir := out.normalized() if out.length() > 0.1 else Vector3.FORWARD
			# 넉백은 약하게 (dir 길이가 밀림 세기): 회오리에 휘말려 계속 맞는다
			en.take_hit(WHIRL_DMG, dir * 0.12, en.global_position + Vector3(0, 0.9, 0), "slash")
			FX.sparks(en.global_position + Vector3(0, 0.9, 0), 4, [Color.WHITE, Pal.BLADE, MINT], 6.0, 0.25, -10.0, 0.05)
	_whirl_ghost -= 1
	if _whirl_ghost <= 0:
		_whirl_ghost = 2
		FX.afterimage(player.visual, Color(0.55, 1.0, 0.85, 0.3), 0.12)
	if whirl_t >= WHIRL_TIME or not player.alive:
		whirl_t = -1.0
		_end_whirl_pose()
		if _whirl_lock:
			_whirl_lock = false
			player.no_attack = false
		# 마무리: 회전을 멈추며 한 번 더 크게 베어 낸다
		FX.slash(player, _whirl_ang, 3)
		FX.shockwave(player.global_position, MINT, 3.6, 0.3)
		main.camera.fov_punch(4.0)
		# Q 합체는 휠윈드 한 번으로 끝: 저절로 분리
		if state == St.DOCKED:
			_detach()


## 회오리 빨아들이기: 둘레 WHIRL_PULL_R 안 몬스터를 조금씩 플레이어 쪽으로 끌어 회오리 칼날 안으로 들인다.
## 가까울수록 세게, 회전 방향으로 살짝 감기며 들어온다. 몸에 겹치기 직전(WHIRL_PULL_MIN)에서 멈추고, 벽은 push_out 으로 막는다.
## 보스 · 소품(가스통 등) · 아직 땅에 안 내린 적 · 패링 공격 중인 적은 끌지 않는다.
func _whirl_pull(dt: float, ramp: float) -> void:
	var pp := player.global_position
	_pull_fx -= dt
	var fx_now := _pull_fx <= 0.0
	if fx_now:
		_pull_fx = 0.12
	for e in Enemy.live(get_tree()):
		var en := e as Enemy
		if not is_instance_valid(en) or not en.alive or not en.landed or en.is_boss or en.get("prop"):
			continue
		if en.parry_committed():
			continue
		var to := pp - en.global_position
		to.y = 0
		var d := to.length()
		var stop := WHIRL_PULL_MIN + en.radius
		if d > WHIRL_PULL_R + en.radius or d <= stop:
			continue
		var dir := to / d
		var near_k := 1.0 - clampf((d - stop) / WHIRL_PULL_R, 0.0, 1.0)
		var speed := lerpf(WHIRL_PULL_V.x, WHIRL_PULL_V.y, near_k) * ramp
		var swirl := Vector3(-dir.z, 0, dir.x) * speed * WHIRL_PULL_SWIRL      # 회전 방향으로 감긴다
		var step := (dir * speed + swirl) * dt
		if step.length() > d - stop:
			step = step.limit_length(maxf(d - stop, 0.0))
		var np := en.global_position + step
		en.global_position = main.push_out(np, en.radius)
		if fx_now:
			# 끌려오는 발밑 바람 · 흙먼지
			FX.puffs(Vector3(en.global_position.x, Main.gy(en.global_position) + 0.05, en.global_position.z) - dir * en.radius, 1,
				[Color(0.75, 1.0, 0.92), MINT, Color(0.3, 0.4, 0.45), Color(0.22, 0.28, 0.34)], 0.5, 0.3, 0.35)


## 로봇 합체 만화처럼: 쾅! 붙는 순간 흑백 임팩트 프레임 · 화면 집중선 + "합체!!" 톱니 말풍선(GattaiFX) ·
## 거대한 섬광 · 겹 충격파 · 사방 불꽃 · 공간 일그러짐 · 카메라 줌 펀치와 큰 흔들림 · 히트스탑.
## 메카는 짓눌렸다 튀어 오르고(squash), 드론은 1.6배로 통 튀었다 출렁이며 자리 잡는다.
func _gattai_impact() -> void:
	var c := player.global_position + Vector3(0, 1.1, 0)
	var cam := main.camera as Camera3D
	var with_cutin := is_instance_valid(cutin)
	if with_cutin:
		cutin.call("notify_dock")
		# 사선 DOCKING 의 미소녀 보이스: 실제 합체 성공 순간 한 번, 9개 중 무작위 (docs/drone-docking-voice-handoff.md)
		if cutin is DiagonalDockingCutin:
			DockingVoice.play(main)
	if is_instance_valid(cam) and not cam.is_position_behind(c):
		GattaiFX.play(main, cam.unproject_position(c), "합체!!", with_cutin)
	if is_instance_valid(ImpactFrame.inst) and ImpactFrame.inst.enabled:
		ImpactFrame.inst.parry(c, player.aim_dir)
	main.hud.screen_flash(Color(1.0, 1.0, 0.92), 0.3 if with_cutin else 0.6)
	FX.flash(c, Color.WHITE, 3.6, 0.14)
	FX.shockwave(player.global_position, Color.WHITE, 6.5, 0.45, 0.14)
	FX.shockwave(player.global_position, MINT, 4.0, 0.3, 0.1)
	FX.ring(c, 4.2, [Color.WHITE, MINT, Color("ffe14a")], 0.35)
	FX.sparks(c, 48, [Color.WHITE, MINT, Color("ffe14a"), Pal.BLADE], 14.0, 0.55, -8.0, 0.08)
	FX.puffs(Vector3(c.x, Main.gy(c) + 0.1, c.z), 8, [Color(0.75, 0.8, 0.95), Color(0.6, 0.65, 0.85), Color(0.25, 0.27, 0.4), Color(0.2, 0.22, 0.34)], 2.2, 0.9, 0.7)
	Distortion.burst(c, 4.0, 0.35, 1.4)
	GustFX.dash_burst(player.global_position, Vector3.FORWARD, Color(0.7, 1.0, 0.9))
	main.camera.fov_punch(14.0)
	main.shake(0.8)
	main.hitstop(0.16)
	player.squash_v -= 16.0
	_pop = 0.0
	_pop_v = 9.0
	rig.happy = 1.0
	Sfx.play("drone_dock", 0.0, 2.0)
	Sfx.play("boom", 0.05, -6.0)
	Sfx.play("drone_burst", 0.0, -3.0)


func _end_whirl_pose() -> void:
	if player.spin_pose.is_valid() and player.spin_pose.get_object() == self:
		player.spin_pose = Callable()
	if _trail_keep.size() >= 2:
		player.trail.life = _trail_keep[0]
		player.trail.reach = _trail_keep[1]
		if _trail_keep.size() >= 3:
			player.trail.bright = _trail_keep[2]
		_trail_keep = []
	player.trail.boost = 0.0


## 휠윈드 자세 (Player._animate 의 spin_pose): 몸 전체를 세운 축으로 아주 빠르게 돌린다. 양팔을 펴고 광선검은 옆으로 길게 뻗어
## 칼끝이 원반을 그린다. 한 틱에 크게 도는 칼이 매끈한 원을 남기도록 사이 각도를 잘게 샘플해 리본에 넘긴다 (BladeTech TEMPEST 와 같은 방식).
func _whirl_pose(p: Player, dt: float) -> void:
	var j := p.j
	var arm: Node3D = j.arm_r
	var blade: Node3D = j.blade
	(j.upper as Node3D).rotation.y = 0.0
	(j.legs as Node3D).rotation.y = 0.0
	(j.torso as Node3D).rotation = Vector3(0.0, 0.0, 0.0)
	arm.rotation = Vector3(-0.1, 0.0, 1.45)
	blade.rotation_degrees = Vector3(-90, 0, 0)
	blade.scale = Vector3(0.95, 0.95, 1.3)
	(j.arm_l as Node3D).rotation.z = -1.1
	for h in [j.hip_l, j.hip_r]:
		(h as Node3D).rotation.x = -0.3
	for kn in [j.knee_l, j.knee_r]:
		(kn as Node3D).rotation.x = -0.45
	# 움직이는 쪽으로 살짝 기운 팽이
	var mv := p.velocity
	mv.y = 0
	var tilt := Basis.IDENTITY
	if mv.length() > 0.5:
		tilt = Basis(mv.normalized().cross(Vector3.DOWN).normalized(), clampf(mv.length() * 0.025, 0.0, 0.25))
	var samples: Array = []
	var n := clampi(int(ceil(absf(_whirl_ang - _spin_prev) / 0.3)), 1, 14)
	for i in range(1, n + 1):
		p.visual.basis = tilt * Basis(Vector3.UP, lerpf(_spin_prev, _whirl_ang, float(i) / n))
		if i < n:
			samples.append(p.trail.sample_now())
	_spin_prev = _whirl_ang
	p.visual.position.y = Player.PIVOT_Y + p.hover + 0.12
	p.trail.boost = 1.0
	p.trail.feed(dt, samples)


## 탑승자 말풍선. force 가 아니면 너무 잦지 않게 거른다
func bark_line(kind: String, force := false) -> void:
	if not force and _bark_t > 0.0:
		return
	var arr: Array = LINES.get(kind, [])
	if arr.is_empty():
		return
	bark(arr[rng.randi() % arr.size()])


func bark(text: String) -> void:
	_bark_t = 3.0
	# 만화 말풍선: 머리 위에서 띠용! 튀어나와 따라다닌다 (새 대사가 오면 이전 것은 비킨다)
	var head: Node3D = top_pt if is_instance_valid(top_pt) else self
	bubble = SpeechBubble.say(head, text, SpeechBubble.SAY, {"offset": Vector3(0, 0.5, 0), "key": get_instance_id()})
	Sfx.play("drone_chirp", 0.08, -12.0)


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


# ── 자동 조작 (--bot 확인용) ───────────────────────────
## 보호막 → (게이지 넉넉하면) Q 길게 합체 휠윈드 / 짧게 합체 → (적이 가까우면) 볼텍스 → 8초 뒤 분리 를 돌고,
## 플레이어 곁에 오염이 쌓이면 잠깐 직접 청소한다. link 는 "Q 를 누르고 있나" 이다.
func _bot_input(dt: float) -> Dictionary:
	var out := {"link": false, "skill": false, "clean": false}
	_bot.clean_cd = float(_bot.clean_cd) - dt
	if float(_bot.clean_t) > 0.0:
		_bot.clean_t = float(_bot.clean_t) - dt
		out.clean = true
	elif float(_bot.clean_cd) <= 0.0:
		var near := 0
		for m in get_tree().get_nodes_in_group(DroneMess.GROUP):
			if _flat((m as Node3D).global_position - player.global_position) < PLAYER_CLEAN_RANGE:
				near += 1
		if near >= 2:
			_bot.clean_t = 1.6
			_bot.clean_cd = 10.0
	if int(_bot.hold) > 0:
		_bot.hold = int(_bot.hold) - 1
		out.link = true
		return out
	if link_cd > 0.0 or whirl_t >= 0.0:
		return out
	if state == St.DOCKED:
		_bot.dock_t = float(_bot.dock_t) + dt
		if gauge >= SKILL_COST and vortex_t < 0.0:
			for e in Enemy.live(get_tree()):
				if is_instance_valid(e) and (e as Enemy).alive and _flat((e as Node3D).global_position - player.global_position) < 6.5:
					out.skill = true
					break
		if float(_bot.dock_t) > 8.0:
			out.link = true
			_bot.dock_t = 0.0
	elif state in [St.FOLLOW, St.SEEK, St.CLEAN] and gauge >= SKILL_COST:
		if int(_bot.phase) == 0:
			out.skill = true
			_bot.phase = 1
		else:
			# 번갈아: 길게(휠윈드) · 짧게
			_bot.hold = 1
			_bot.phase = 2 if int(_bot.phase) == 1 else 1
			_bot.dock_t = 0.0
			out.link = true
	return out
