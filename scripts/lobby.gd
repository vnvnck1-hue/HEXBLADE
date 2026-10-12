class_name Lobby
extends Control
## 게임 시작 화면. 메인 게임(헥스 섹터 런)과 테스트 씬(방 탐색 아레나 · 보스전 단독)을 고른다.
## 게임 중 Esc 로 언제든 이 화면으로 돌아온다 (Lobby.back()).

const SCENE := "res://scenes/lobby.tscn"
const RUN_SCENE := "res://scenes/run.tscn"
const DEATH_TEST_SCENE := "res://scenes/mammoth_death_lab.tscn"
const TEST_SCENES := [
	{"title": "방 탐색 아레나", "desc": "전투방 9곳을 통로로 이은 절차 생성 맵 · 벌레 괴생명체만 등장 · 방을 정리할 때마다 위험도 상승", "scene": "res://scenes/main.tscn"},
	{"title": "로그라이크 · HEX DEPTHS", "desc": "아이작의 번제식 6층 로그라이크 · 방 그리드 · 아이템방/상점/비밀방/악마·천사 거래 · 패시브 80+ · 액티브 · 장신구 · 알약 · 카드 · 결합 공격 · 변신", "scene": "res://scenes/rogue.tscn"},
	{"title": "무한 비행 · 종 스크롤 슈팅", "desc": "흐르는 도로 위를 끝없이 날아가며 편대로 몰려오는 전투기·포격 드론을 격추 · 30초마다 섹터 상승 · 정예 기체 · 최고 비행 거리 기록", "scene": "res://scenes/stream.tscn"},
	{"title": "전투 테스트 · 허수아비", "desc": "넓은 홀에서 허수아비로 콤보·무기·패링을 자유롭게 시험 · 피해 숫자·DPS 표시", "scene": "res://scenes/training.tscn"},
	{"title": "텍스처링 · 정비실 디오라마", "desc": "본편 바닥·벽·프랍·배관을 모은 작은 정비실 · 시험 텍스처 교체 · 조명과 원본 비교", "scene": "res://scenes/texture_diorama.tscn"},
	{"title": "핸드페인팅 정비실 · 크림 / 연보라", "desc": "선택한 3번 원화의 바닥·벽 PNG 실제 적용 · B 원본 비교 · 원색과 조명 비교", "scene": "res://scenes/painted_room_study.tscn"},
	{"title": "파트너 청소 드론", "desc": "미소녀 파트너의 드론 TRIAD: 따라다니며 잔해·체액 청소 · Q 합체 · X 보호막/볼텍스 · Z 직접 청소", "scene": "res://scenes/drone.tscn"},
	{"title": "필드 기믹", "desc": "연기 구역(은신) · 레일 · 가스통 폭발 · 수리키트 해치(F 연타) 를 한 홀에서 시험", "scene": "res://scenes/gimmicks.tscn"},
	{"title": "유체 연기 · 나비에-스토크스", "desc": "GPU 유체 격자로 푼 바닥 연기 · 대시로 가르고 검으로 베고 휠윈드로 감고 폭발로 날리고 청소 질주로 빨아들임 (연출 전용)", "scene": "res://scenes/fluid_smoke.tscn"},
	{"title": "벌레 괴생명체 · 개미 병정 · 공벌레 · 촘퍼 · 애벌레", "desc": "땅에서 기어 나오는 개미 병정(산 발사·물기) · 몸을 말아 구르는 공벌레 · 노란 체액을 흘리는 튜토리얼 벌레 촘퍼 · 몸을 수축·이완하며 기어 점액 흔적을 남기는 애벌레 · 4 키 애니메이션 전시", "scene": "res://scenes/bugs.tscn"},
	{"title": "MAMMOTH 추격전", "desc": "도로 위 전차 보스 단독 실행", "scene": "res://scenes/boss.tscn"},
	{"title": "VULCAN 용광로", "desc": "좁아지는 용암 아레나 보스 단독 실행", "scene": "res://scenes/forge.tscn"},
	{"title": "LAYER 01 · 심연 성소", "desc": "어두운 부유 아레나 · 페이즈마다 땅이 솟고 꺼짐 · 함정 · 중간보스 HALO WARDEN", "scene": "res://scenes/abyss.tscn"},
	{"title": "SHAFT 07 · 거미 보스 SHIPWRIGHT", "desc": "높은 벽의 갱도 · 벽과 구멍을 오가는 다관절 거미 · 거미줄 감속 · 새끼 소환 · 끝없는 기둥", "scene": "res://scenes/spider.tscn"},
	{"title": "캐릭터 대화", "desc": "청소업체 사장과 첫 출근 · 기존 격납고 브리핑 · 선택지 분기 · 자동 · 기록", "scene": "res://scenes/dialogue.tscn"},
	{"title": "동료 소개 · 사장과 정비사", "desc": "사장이 새 동료를 소개하고 파일럿까지 셋이서 대화 · 역할과 기체 점검 · 응답 선택", "scene": "res://scenes/coworker_dialogue.tscn"},
	{"title": "첫 청소 파트너 소개", "desc": "새 상체 포트레이트 · 첫 현장 동료와 역할 분담 · 파일럿 대사창 원화", "scene": "res://scenes/partner_dialogue.tscn"},
	{"title": "MAMMOTH 죽음 연출 · B안", "desc": "궤도 파손과 전복 컷씬 반복 확인 (본선 격파에 적용됨)", "scene": "res://scenes/lab_mammoth_b.tscn"},
]
## 로비에 있는 동안 백그라운드로 미리 읽어 둘 무거운 에셋 (첫 게임 진입 끊김 방지)
const WARM := [
	MechPlayer.GLB, PartnerDrone.MODEL,
	"res://assets/models/bg_claude_w01.glb", "res://assets/models/bg_claude_w01_half.glb", "res://assets/models/bg_claude_jamb.glb",
	"res://assets/models/bg_claude_a01.glb", "res://assets/models/bg_claude_a02.glb", "res://assets/models/bg_claude_f01.glb",
	"res://assets/models/bg_claude_block_wall.glb", "res://assets/models/bg_claude_block_cover.glb", "res://assets/models/bg_claude_block_pillar.glb",
]
var font: SystemFont
var art: LobbyArt
var main_btn: Button
var test_btns: Array[Button] = []
var _leaving := false


## 게임 씬에서 로비로 돌아간다. 기존 시간/물리 복구 계약을 유지한다.
static func back(tree: SceneTree) -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	tree.change_scene_to_file(SCENE)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	add_child(Sfx.new())
	if _route_cmdline():
		return
	ResCache.warm(WARM)
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Apple SD Gothic Neo", "Noto Sans CJK KR", "sans-serif"])
	font.font_weight = 700
	art = LobbyArt.new()
	add_child(art)
	art.build(TEST_SCENES, font)
	main_btn = art.menus[0]
	test_btns = art.rows
	main_btn.pressed.connect(_start_run)
	art.menus[1].pressed.connect(_go.bind(DEATH_TEST_SCENE))
	art.menus[2].pressed.connect(_toggle_tests)
	art.menus[3].pressed.connect(func(): get_tree().quit())
	for i in TEST_SCENES.size():
		test_btns[i].pressed.connect(_go.bind(TEST_SCENES[i].scene))
	main_btn.grab_focus.call_deferred()


## 자동 플레이 · 캡처 실행 인자로 켰을 때는 로비를 건너뛴다 (--test 는 방 탐색 아레나, 그 밖은 섹터 런)
func _route_cmdline() -> bool:
	var args := OS.get_cmdline_user_args()
	var skip := false
	for a in args:
		if a not in ["--toon", "--notoon", "--noimpact"]:
			skip = true
	if not skip:
		return false
	var target: String = TEST_SCENES[0].scene if args.has("--test") else RUN_SCENE
	get_tree().change_scene_to_file.call_deferred(target)
	return true


func _start_run() -> void:
	if _leaving:
		return
	_leaving = true
	Sfx.play("charged", 0.0)
	get_node("/root/Run").new_run()


func _go(scene: String) -> void:
	if _leaving:
		return
	_leaving = true
	Sfx.play("ready", 0.0)
	get_tree().change_scene_to_file(scene)


func _toggle_tests() -> void:
	art.set_drawer(not art.drawer.visible)
	Sfx.play("lock", 0.0, -4.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE and art and art.drawer.visible:
			art.set_drawer(false)
			get_viewport().set_input_as_handled()
