class_name DiagonalDockingCutin
extends CanvasLayer
## 사선 DOCKING 합체 컷인 (docs/diagonal-docking-cutin-study.md · 구현 기록 docs/diagonal-docking-cutin.md).
## 하단 사선 하나(8°, 왼쪽 높이 0.731H)를 기준으로 포트레이트가 왼쪽 밖 → 중앙 체류 → 오른쪽 밖으로 이동하고,
## 몸 아래는 그 선에서 잘린다. 같은 방향으로 DOCKING 글자가 계속 흐르고 긴 집중선이 속도를 보탠다.
## 위치는 단일 거리 s 로만 계산한다: anchor = O + s·T (x/y 를 따로 움직이면 궤적이 휜다).
## Q 즉시 합체(_begin_recall(fast=true))에서 begin, 실제로 등에 붙는 순간(_gattai_impact) notify_dock — CockpitCutin 과 같은 계약.
## 시간은 실제 단조 시계의 누적 경과(일시정지 제외) — 히트스탑에도 제 속도. 스프링만 제한 dt 로 적분한다.
## 가슴은 diagonal_cutin.gdshader 의 UV 모핑: 포트레이트 이동 가속도의 관성 + 합체 충격으로 출렁인다.
## 캐릭터 2명(CHARACTERS)이 합체마다 번갈아 나오고, 캐릭터마다 컷인 전체 테마 색(띠·테두리·글자·집중선·잔상)이 다르다:
## 보라 양갈래 정비사 = 퍼플 톤, 초록 머리 메이드 = 그린 톤. 머리카락은 마스크 영역만 관성 + 잔잔한 물결로 흔들린다.
## 민트 메이드(2026-10-06): 머리색 테마(옅은 민트 #B6D5BF · 그늘 #8EAE9D · 짙은 그늘 #769587 에서 뽑은 짙은 청록 띠 · 민트 글자),
## 가슴 모핑 대신 머리카락 · 치마 · 리본 꼬리가 각자 스프링으로 흔들리고, 바로 오른쪽 뒤에 같은 모양 그림자가 자라나며,
## 확정 시안의 소품 10종이 띠 안을 왼쪽 → 오른쪽으로 우당탕탕 튀며 날아가고 카툰 금빛 별이 띠 안에서 휘날린다(CutinScatter).

const FONT := preload("res://assets/fonts/ARCO.otf")
const SHADER := preload("res://scripts/drone/diagonal_cutin.gdshader")
const TEXT_SHADER := preload("res://scripts/drone/diagonal_band_clip.gdshader")

const LAYER := 11                ## HUD(10) 위 — 원본 GIF 처럼 포트레이트가 상단 HUD 를 덮는다 (1초 남짓)
const THETA := 8.0               ## 하단 기준선 각도 (도)
const BOTTOM_LEFT := 0.731       ## 하단선 왼쪽 높이 (×H)
const TOP_THETA := 5.7           ## 위 경계 각도
const TOP_LEFT := 0.383          ## 위 경계 왼쪽 높이 (×H)
const X_HOLD := 0.50             ## 중앙 체류 x (×W)
const SIDE_MAX_W := 0.60         ## 포트레이트 크기 상한 (×W). 높이 상한·머리끝 위치는 캐릭터마다(side_max_h · hair_screen)

## 타임라인 (초). GIF 1초 리듬: 진입 0.16 · 정착 0.04 · 체류 ~0.70 · 퇴장 0.10
const ENTER := 0.16
const SETTLE := 0.20
const HOLD_END := 0.90
const DOCK_TAIL := 0.15          ## 합체가 늦으면 hold_end = max(0.90, dock + 0.15)
const EXIT := 0.10
const CLEAN := 0.12              ## 퇴장 뒤 띠·선 정리
const BAND_IN := 0.06
const WAIT_MAX := 1.2            ## 이 안에 합체 완료가 안 오면 접는다
const PREVIEW_DOCK := 0.22       ## 미리보기(드론 없이)는 이때 합체한 것으로 친다 = PartnerDrone.GATTAI_TIME

## 테마 색. 그린은 레퍼런스(사용자 GIF F3) 픽셀에서 잼: 바탕 (72,75,101) 슬레이트 — 배경(28,32,49)보다 밝게 덮는다 ·
## 위 테두리 탁한 민트 (68,155,124) + 그 아래 옅은 밝은 줄 (96,129,147) · 띠 안 아래 남색 줄 (23,45,67) → 흰 줄 → 민트 하단 테두리 (70,140,114) ·
## 띠 밖 어두운 그림자 · 글자 (94,255,187). 퍼플은 같은 명도 관계를 보라로 옮겼다.
const THEMES := {
	"green": {
		"fill": Color(0.305, 0.318, 0.424, 0.88), "top_edge": Color(0.27, 0.61, 0.49), "top_hi": Color(0.38, 0.51, 0.58),
		"low_dark": Color(0.09, 0.18, 0.26), "bottom_edge": Color(0.27, 0.55, 0.45), "shadow": Color(0.06, 0.09, 0.13, 0.7),
		"text": Color(0.369, 1.0, 0.733), "accent": Color("5cf2b4"), "accent_hi": Color(0.75, 1.0, 0.9, 0.9), "ghost": Color(0.75, 1.0, 0.92),
	},
	"purple": {
		"fill": Color(0.33, 0.27, 0.45, 0.88), "top_edge": Color(0.57, 0.37, 0.80), "top_hi": Color(0.58, 0.48, 0.68),
		"low_dark": Color(0.17, 0.08, 0.27), "bottom_edge": Color(0.52, 0.34, 0.74), "shadow": Color(0.09, 0.05, 0.14, 0.7),
		"text": Color(0.82, 0.63, 1.0), "accent": Color(0.76, 0.52, 1.0), "accent_hi": Color(0.92, 0.82, 1.0, 0.9), "ghost": Color(0.88, 0.76, 1.0),
	},
	## 민트 메이드 전용: 머리카락 색에서 뽑음 — 옅은 민트(182,213,191) · 그늘(142,174,157) · 짙은 그늘(118,149,135).
	## 띠 = 짙은 그늘을 더 어둡게 낮춘 청록 · 위 테두리 = 머리 밝은 면 · 그 아래 줄 = 그늘 · 글자 = 머리 밝은 면을 조금 더 맑게 ·
	## 하단 테두리 = 머리 민트를 살짝 진하게 · 캐릭터 그림자 = 짙은 청록
	"mint": {
		"fill": Color(0.14, 0.24, 0.195, 0.9), "top_edge": Color(0.71, 0.84, 0.75), "top_hi": Color(0.56, 0.68, 0.62),
		"low_dark": Color(0.07, 0.13, 0.12), "bottom_edge": Color(0.60, 0.85, 0.71), "shadow": Color(0.03, 0.07, 0.06, 0.7),
		"text": Color(0.78, 0.95, 0.84), "accent": Color(0.56, 0.80, 0.69), "accent_hi": Color(0.90, 1.0, 0.94, 0.9), "ghost": Color(0.80, 0.95, 0.86),
		"sil": Color(0.07, 0.16, 0.12, 0.62),
	},
}
const BAND_LOW_WHITE := Color(0.97, 0.99, 1.0)
## 캐릭터 (원화는 투명 정사각 · tools/cutin_portraits.py 로 가공). art = 원화 한 변 px
##  anchor: 원화에서 하단선에 놓이는 기준점(그 아래는 선 밑에서 잘림) · hair_top: 머리끝 높이(위 투명 여백)
##  hair_screen: 체류 때 머리끝이 오는 화면 높이(×H, 음수면 화면 위로 살짝 넘김) · side_max_h: 크기 상한(×H) — 전신에 가까운 원화는 크게 써야 얼굴이 작아지지 않는다
##  c_l/c_r/r/tilt: 가슴 두 타원(UV) · hair_root/hair_len: 머리카락 뿌리와 길이(뿌리는 고정, 끝으로 갈수록 크게 흔들림) · face: 앞 집중선이 피할 얼굴
##  pops: 원화에서 떼어낸 장식(말풍선 등)을 순서대로 튀어나오게 · papers: 등장 바람에 휘날리는 서류 종이 수(0 이면 없음)
const CHARACTERS := [
	{"id": "purple", "ko": "보라 양갈래 정비사", "theme": "purple", "art": 1254.0,
		"tex": preload("res://assets/portraits/purple_worker/purple-worker-cheerful.png"),
		"mask": preload("res://assets/portraits/purple_worker/purple-worker-cheerful-hairmask.png"),
		"anchor": Vector2(0.50, 0.80), "hair_top": 0.05, "hair_screen": 0.04, "side_max_h": 0.92,
		"c_l": Vector2(0.403, 0.618), "c_r": Vector2(0.574, 0.622), "r": 0.16, "tilt": -0.05,
		"hair_root": Vector2(0.52, 0.20), "hair_len": 0.30, "face": Vector2(0.53, 0.33)},
	{"id": "green", "ko": "초록 머리 메이드", "theme": "green", "art": 1226.0,
		"tex": preload("res://assets/portraits/green_maid/green-maid-docking.png"),
		"mask": preload("res://assets/portraits/green_maid/green-maid-hairmask.png"),
		"anchor": Vector2(0.50, 0.832), "hair_top": 0.0, "hair_screen": 0.06, "side_max_h": 0.88,
		"c_l": Vector2(0.608, 0.680), "c_r": Vector2(0.701, 0.673), "r": 0.104, "tilt": 0.0,
		"hair_root": Vector2(0.488, 0.208), "hair_len": 0.51, "face": Vector2(0.476, 0.318),
		## 원화에서 떼어낸 하트 말풍선 · 반짝이: 원화 픽셀 중심(1226² 기준) · 등장 시각(초) · 동작 종류 — 순서대로 튀어나온다
		"pops": [
			{"tex": preload("res://assets/portraits/green_maid/green-maid-bubble.png"), "px": Vector2(134.5, 298.5), "pivot": Vector2(181.0, 357.0), "at": 0.15, "kind": "bubble"},
			{"tex": preload("res://assets/portraits/green_maid/green-maid-heart.png"), "px": Vector2(134.5, 298.5), "at": 0.25, "kind": "heart"},
			{"tex": preload("res://assets/portraits/green_maid/green-maid-sparkle-a.png"), "px": Vector2(74.5, 408.5), "at": 0.32, "kind": "sparkle"},
			{"tex": preload("res://assets/portraits/green_maid/green-maid-sparkle-b.png"), "px": Vector2(115.0, 463.5), "at": 0.39, "kind": "sparkle"},
		],
		"papers": 16},
	## 민트 메이드: 전신(1122×1402 → 가운데 정렬 1402²) · 무릎 높이가 하단선 · bust=false(가슴 모핑 없음) · motion=true(치마 · 리본 흔들림) ·
	## shadow: 바로 오른쪽 뒤에 자라는 같은 모양 그림자(off ×side) · props: 확정 시안(output/maid-bold-cutin-props-20261005/concept_gold_no_trails.png)의
	## 소품 — 띠 안을 왼쪽 → 오른쪽으로 날아감, size = 그림 긴 변 ×side, dim = PNG 안 그림의 긴 변(px)
	{"id": "mint", "ko": "민트 메이드", "theme": "mint", "art": 1402.0,
		"tex": preload("res://assets/portraits/mint_maid/mint-maid-docking.png"),
		"mask": preload("res://assets/portraits/mint_maid/mint-maid-motionmask.png"),
		"anchor": Vector2(0.50, 0.76), "hair_top": 0.004, "hair_screen": 0.05, "side_max_h": 1.0,
		"c_l": Vector2(0.45, 0.42), "c_r": Vector2(0.55, 0.42), "r": 0.06, "tilt": 0.0, "bust": false, "motion": true,
		"hair_root": Vector2(0.47, 0.086), "hair_len": 0.7, "hair_k": 1.35, "face": Vector2(0.50, 0.235),
		"shadow": {"off": Vector2(0.032, -0.006), "scale": 0.01},
		"props": [
			{"tex": preload("res://assets/vfx/maid_props/01_coffee_cup.png"), "dim": 342, "size": 0.25},
			{"tex": preload("res://assets/vfx/maid_props/02_coffee_saucer.png"), "dim": 251, "size": 0.2},
			{"tex": preload("res://assets/vfx/maid_props/03_black_pink_ribbon.png"), "dim": 300, "size": 0.18},
			{"tex": preload("res://assets/vfx/maid_props/04_cherries.png"), "dim": 261, "size": 0.14},
			{"tex": preload("res://assets/vfx/maid_props/05_white_napkin.png"), "dim": 286, "size": 0.2},
			{"tex": preload("res://assets/vfx/maid_props/06_teapot.png"), "dim": 310, "size": 0.26},
			{"tex": preload("res://assets/vfx/maid_props/07_cherry_cake.png"), "dim": 284, "size": 0.19},
			{"tex": preload("res://assets/vfx/maid_props/08_pink_macaron.png"), "dim": 269, "size": 0.15},
			{"tex": preload("res://assets/vfx/maid_props/09_silver_spoon.png"), "dim": 270, "size": 0.19},
			{"tex": preload("res://assets/vfx/maid_props/10_service_bell.png"), "dim": 212, "size": 0.15},
		],
		"sparkle": preload("res://assets/vfx/maid_props/11_gold_sparkle.png")},
]
static var char_mode := "alt"    ## "alt" = 합체마다 번갈아(숨긴 캐릭터는 건너뜀) · 캐릭터 id = 고정. --cutin-char=alt|purple|green|mint, 허수아비 [ 키
## 숨긴 캐릭터: 원화 · 잔상 · 그림자 · 말풍선 팝업 · 서류 종이 · 소품을 그리지 않는다(계산은 그대로). 보라 정비사 · 초록 메이드는
## 지금 작업 중인 장소에 안 맞아 잠시 숨김(사용자 요청 2026-10-06) — 다시 보이려면 이 목록에서 빼거나 --cutin-chars=on (모두 보임).
## 띠 · DOCKING 글자 · 집중선 · 슬로우모션 · 보이스는 숨겨도 그대로.
static var hidden_chars: Array = ["purple", "green"]
static var _next_char := 0
## 글자: 회전하지 않고 세운 채 세로로만 비스듬히(Y 기울이기 — 세로획은 수직, 윗변·아랫변이 하단선 8°를 따름).
## 세로로 길쭉 · 가로로 눌림 (레퍼런스 폭/높이 ≈ 0.6, 원 글꼴 ≈ 0.9). 높이 0.27H, 바닥은 하단선에서 띠 높이의 21% 위.
const TEXT_SX := 0.6              ## 7차: 가로로 더 눌림 (폭/높이 ≈ 0.48)
const TEXT_SY := 1.15
const TEXT_H := 0.22             ## 글자(대문자) 높이 ×H (7차: 0.27 → 윗부분이 위 테두리에 잘려 줄임)
const TEXT_TOP_GAP := 0.03       ## 띠가 가장 좁은 화면 왼쪽 끝에서도 글자 윗변이 위 테두리 아래 이만큼(×H) 떨어지게 — 넘으면 글자를 더 줄인다
const TEXT_CAP := 0.554          ## ARCO 대문자 높이 / 글꼴 크기 (게임 화면에서 잼)
const TEXT_LIFT := 0.21          ## 글자 바닥선: 하단선에서 띠 두께의 이 비율만큼 위
const TEXT_GAP := 0.1            ## 단어 사이 (글꼴 크기 비율)
const TEXT := "DOCKING"
const TEXT_SPEED := 3.0          ## 글자 흐름 (×W / 초), +T 방향 — 눈에 거의 안 보일 만큼 빠르게 (빠를 때는 잔상 3겹)
const LINES := 16
const FRONT_LINES := 4

## 가슴 스프링 (원화 px). **좌우가 주인공**: 왼쪽→오른쪽으로 달려오다 서면 오른쪽으로 쏠림(약 69px) → 합체 충격에 몸이 앞으로 밀리며
## 왼쪽으로 뒤처짐(약 −60) → 오른쪽(+39) → 왼쪽(−20) 으로 출렁이다 1초 안에 섬 (2.3Hz · 감쇠 0.22).
## 세로는 작게: 무겁게 처지는 성질(위로 들릴 때만 중력 G · 아래로는 DOWN_SOFT)은 두되 합체 충격·진자 들림·늘임을 줄였다.
const JIG_HZ := Vector2(2.3, 2.7)
const JIG_ZETA := Vector2(0.22, 0.26)
const JIG_GAIN := Vector2(0.36, 0.2)
const JIG_G := 2600.0
const JIG_DOWN_SOFT := 0.75
const JIG_LIFT := 0.003
const JIG_MAX := 72.0
const JIG_SQ := 0.1
const JIG_DOCK_KICK := Vector2(-600.0, 650.0)   ## 합체 충격: 몸이 앞(오른쪽)으로 밀리며 가슴은 왼쪽으로 뒤처짐 · 아래로 조금 처짐 (원화 px/초)

## 캐릭터 트위닝 프리셋 (기준점 = 하단선 위 한 점을 축으로 회전·크기만 → 하단선과의 접점은 그대로).
## 기본은 LATE(멈추는 순간 최대 쏠림, 사용자 선택). SNAP·WHIP·SQUASH·LUNGE 는 더 이른 쏠림 변형, NONE 은 비교용.
##  pre/pre_t: 처음 뒤로 젖히는 예비 동작 · peak_t/amp: 앞(오른쪽)으로 최대 쏠림 시각·크기(rad) · settle/back: 그 뒤 되돌림 시간·크기
##  stretch: 달리는 동안 가로로 늘어남(멈출수록 줄어듦) · squash/squash_t: 쏠림 최대 뒤 세로로 찌그러짐 · pop: 합체 팝 · enter_scale · out: 퇴장 젖힘
const TWEEN_PRESETS := [
	{"id": "late", "name": "LATE", "ko": "멈출 때 쏠림 (기본)", "desc": "멈추는 순간(0.16초) 최대로 쏠렸다 작은 되돌림 한 번으로 섬",
		"pre": 0.0, "pre_t": 0.0, "peak_t": 0.16, "amp": 0.06, "settle": 0.14, "back": 0.18,
		"stretch": 0.0, "squash": 0.0, "squash_t": 0.1, "pop": 0.055, "enter_scale": 0.9, "out": 0.06},
	{"id": "snap", "name": "SNAP", "ko": "빠른 쏠림", "desc": "달려오는 도중(0.07초) 이미 최대로 쏠렸다가 멈추며 바로 섬",
		"pre": 0.0, "pre_t": 0.0, "peak_t": 0.07, "amp": 0.065, "settle": 0.12, "back": 0.2,
		"stretch": 0.0, "squash": 0.0, "squash_t": 0.1, "pop": 0.055, "enter_scale": 0.9, "out": 0.06},
	{"id": "whip", "name": "WHIP", "ko": "채찍", "desc": "처음 0.03초 뒤로 젖혔다가 채찍처럼 앞으로 (0.08초 최대)",
		"pre": 0.035, "pre_t": 0.03, "peak_t": 0.08, "amp": 0.08, "settle": 0.12, "back": 0.25,
		"stretch": 0.0, "squash": 0.0, "squash_t": 0.1, "pop": 0.06, "enter_scale": 0.92, "out": 0.07},
	{"id": "squash", "name": "SQUASH", "ko": "늘어남·찌그러짐", "desc": "달리는 동안 가로로 늘어났다 쏠림 최대에서 세로로 찌그러짐",
		"pre": 0.0, "pre_t": 0.0, "peak_t": 0.06, "amp": 0.03, "settle": 0.1, "back": 0.1,
		"stretch": 0.08, "squash": 0.07, "squash_t": 0.12, "pop": 0.08, "enter_scale": 0.94, "out": 0.04},
	{"id": "lunge", "name": "LUNGE", "ko": "크게 덤벼듦", "desc": "일찍(0.06초) 크게 6° 쏠리고 합체 팝도 크게",
		"pre": 0.0, "pre_t": 0.0, "peak_t": 0.06, "amp": 0.11, "settle": 0.16, "back": 0.3,
		"stretch": 0.03, "squash": 0.03, "squash_t": 0.1, "pop": 0.09, "enter_scale": 0.85, "out": 0.09},
	{"id": "none", "name": "NONE", "ko": "트위닝 없음", "desc": "기울기·크기 변화 없이 비교용",
		"pre": 0.0, "pre_t": 0.0, "peak_t": 0.07, "amp": 0.0, "settle": 0.1, "back": 0.0,
		"stretch": 0.0, "squash": 0.0, "squash_t": 0.1, "pop": 0.0, "enter_scale": 1.0, "out": 0.0},
]
static var tween_preset := 0     ## 허수아비 시험장 - 키 · --cutin-tween=id. static 이라 씬을 다시 불러도 유지
const POP_T := 0.16
const BREATH := 0.005            ## 체류 중 숨쉬기 크기 (흔들림 없이 아주 약하게)

## 슬로우모션: 컷인 동안 게임 시간 배율 (Main.set_slowmo). 퇴장~정리 동안 1 로 되돌린다
const SLOW := 0.1
## 임팩트(합체 순간) 때 DOCKING 글자 흐름: 급제동 → 거의 정지 유지 → 다시 흐름 (합체 뒤 경과 초)
## 7차: 기계적인 급제동/급가속 대신 "슬로우모션이 걸렸다 풀리는" 느낌 — 속도 배율을 로그 공간에서 보간한다
## (1 → MIN 으로 갈 때 처음엔 크게, 갈수록 잘게 줄어 부드럽게 멎고, 풀릴 때도 천천히 깨어나 원래 속도로).
const TEXT_BRAKE := 0.12         ## 합체 순간부터 거의 멈출 때까지 (사인 ease-out)
const TEXT_FREEZE := 0.24        ## 여기까지 거의 정지
const TEXT_RESUME := 0.56        ## 여기까지 원래 속도로 (smoothstep)
const TEXT_MIN := 0.01           ## 멈춤 동안 (빠른 속도의 1%)
## 머리카락 스프링 (원화 px): 가슴보다 느리고 덜 감쇠 → 달려오면 뒤로 날렸다 멈추면 앞으로 넘어가며 출렁. 끝은 tanh 로 HAIR_MAX 까지
const HAIR_HZ := 1.5
const HAIR_ZETA := 0.28
const HAIR_GAIN := 0.22
const HAIR_MAX := 46.0
const HAIR_DOCK_KICK := -420.0   ## 합체 충격에 몸이 앞으로 밀리며 머리는 뒤(왼쪽)로
## 치마 · 리본 꼬리 스프링 (민트 메이드, 원화 px · 가로 위주). 치마는 머리카락보다 빠르고 무겁게, 리본은 더 가볍게 · 한 박자 늦게(JIG_LAG 가속도).
## 달려오면 뒤(왼쪽)로 날렸다 멈추면 앞으로 넘어가며 출렁, 흔들릴수록 밑단이 들린다(lift). 펄럭임 = 이동 속도 · 합체 펄스에 비례한 잔물결
const SKIRT_HZ := 2.1
const SKIRT_ZETA := 0.3
const SKIRT_GAIN := 0.2
const SKIRT_MAX := 36.0
const SKIRT_LIFT := 0.3
const SKIRT_DOCK_KICK := -420.0
const CLOTH_HZ := 2.7
const CLOTH_ZETA := 0.2
const CLOTH_GAIN := 0.32
const CLOTH_MAX := 52.0
const CLOTH_DOCK_KICK := -640.0
const FLUTTER := Vector3(0.0012, 0.0035, 0.004)   ## 펄럭임 UV 크기: 기본 · 이동 속도 최대 · 합체 펄스
## 그림자: 진입 후반에 캐릭터 자리에서 바로 오른쪽 뒤(off ×side, 머리카락 한 가닥 폭쯤)로 자라난다(넘침 → 자리). 이동 중엔 속도만큼 조금 뒤로 끌리고, 퇴장 때 살짝 벌어지며 사라짐
const SHADOW_GROW := Vector2(0.10, 0.42)          ## 자라기 시작 · 끝 (초)
const SHADOW_DRAG := 0.0015
const JIG_R_DETUNE := 1.05
const JIG_LAG := 0.05

enum Ph { ENTER, WAIT, HOLD, EXIT, DONE }

var drone: Node
var main: Node
var preview := false             ## 드론 없이 보기 (허수아비 F3): PREVIEW_DOCK 에 스스로 합체 처리
var ph := Ph.ENTER
var t := 0.0
var dock_t := -1.0
var exit_t := -1.0
var exit_s0 := 0.0               ## 퇴장 시작 s
var done_t := -1.0               ## 포트레이트가 화면 밖으로 나간 시각
var rng := RandomNumberGenerator.new()
var _last_us := 0
static var fixed_dt := 0.0       ## 캡처·테스트용

## 공통 좌표계 (매 프레임 화면 크기로)
var vs := Vector2(1280, 800)
var tangent := Vector2.RIGHT
var normal := Vector2.DOWN
var origin := Vector2.ZERO
var top_origin := Vector2.ZERO
var top_normal := Vector2.DOWN
var side := 800.0                ## 포트레이트 표시 크기 (정사각형)
var s_start := 0.0
var s_hold := 0.0
var s_end := 0.0
var s := 0.0                     ## 지금 포트레이트 위치 (하단선 위 거리)
var s_vel := 0.0

var root: Node2D
var back: Node2D                 ## 어둡힘 · 띠 · 뒤 집중선
var text_track: Node2D
var text_mat: ShaderMaterial
var anchor: Node2D               ## O + s·T
var portrait: Sprite2D
var ghosts: Array[Sprite2D] = []
var mat: ShaderMaterial
var front: Node2D                ## 앞 집중선 · 하단 이음선
var lines := []                  ## 집중선 [{s, q, len, w, col, age, life, v, ang}]
var front_lines := []
var _spawn_acc := 0.0
var _text_off := 0.0
var _font_size := 200
var _period := 1000.0
var _band_k := 0.0               ## 띠 펼침 0~1
var _fade := 1.0                 ## 정리 알파
var _pulse := 0.0                ## 합체 펄스 (테두리 · 선)
var _jolt := 0.0                 ## 합체 충격: s 축으로만 밀렸다 돌아옴 (하단선을 벗어나지 않게)
var _jolt_v := 0.0
## 가슴
var _pan := Vector2.ZERO
var _pan_prev := Vector2.ZERO
var _pan_v := Vector2.ZERO
var _pan_init := false
var jig := [Vector2.ZERO, Vector2.ZERO]       ## 화면에 쓰는 변위 (tanh 로 한계)
var jig_raw := [Vector2.ZERO, Vector2.ZERO]   ## 스프링 상태
var jig_v := [Vector2.ZERO, Vector2.ZERO]
var jig_peak := 0.0
var _acc_hist: Array = []
var max_clip_err := 0.0          ## 확인용: 기준점이 하단선에서 벗어난 최대 거리 (px)
## 캐릭터 · 테마 (begin 때 정해짐)
var char_i := -1
var cfg: Dictionary
var art := 1254.0
var anchor_uv := Vector2(0.5, 0.8)
var hair_uv := 0.05
var jig_scale := 1.0             ## 가슴 반경에 맞춘 흔들림 크기 (기준: 보라 정비사 반경 200px)
var band_fill: Color
var band_top_edge: Color
var band_top_hi: Color
var band_low_dark: Color
var band_bottom_edge: Color
var band_shadow: Color
var text_col: Color
var accent: Color
var accent_hi: Color
## 머리카락 스프링 (원화 px, 가로 위주)
var hair := Vector2.ZERO
var hair_v := Vector2.ZERO
## 원화에서 떼어낸 장식 팝업 [{node, cfg, seed}] · 서류 종이
var pops: Array = []
var papers: Array = []
var paper_back: Node2D
var paper_front: Node2D
## 민트 메이드: 치마 · 리본 스프링 (원화 px), 그림자, 소품 · 반짝이
var skirt := Vector2.ZERO
var skirt_v := Vector2.ZERO
var cloth := Vector2.ZERO
var cloth_v := Vector2.ZERO
var skirt_peak := 0.0            ## 확인용
var cloth_peak := 0.0
var shadow: Sprite2D
var shadow_mat: ShaderMaterial
var shadow_k := 0.0              ## 확인용: 그림자 자람 0~1
var scatter: CutinScatter


static func begin(scene: Node, owner_drone: Node, is_preview := false) -> DiagonalDockingCutin:
	var c := DiagonalDockingCutin.new()
	c.drone = owner_drone
	c.main = scene
	c.preview = is_preview
	c.char_i = pick_character()
	scene.add_child(c)
	return c


## 다음 합체에 나올 캐릭터: 번갈아(alt, 숨긴 캐릭터는 건너뜀 — 모두 숨겼으면 전부 대상) 또는 고정
static func pick_character() -> int:
	if char_mode != "alt":
		for i in CHARACTERS.size():
			if CHARACTERS[i].id == char_mode:
				return i
	var n := CHARACTERS.size()
	var any := CHARACTERS.any(func(ch): return char_visible(ch.id))
	for k in n:
		var i := (_next_char + k) % n
		if not any or char_visible(CHARACTERS[i].id):
			_next_char = (i + 1) % n
			return i
	return 0


static func char_visible(id: String) -> bool:
	return not hidden_chars.has(id)


static func character_title(mode: String) -> String:
	if mode == "alt":
		return "번갈아"
	for ch in CHARACTERS:
		if ch.id == mode:
			return ch.ko
	return mode


## 씬 시작 때 한 번: 보이지 않게(알파 0.004) 2프레임 그려 셰이더 파이프라인 · 원화 업로드 · 큰 글자 글리프를 미리 만든다.
## 첫 합체 컷인에서 한 번 튀던 프레임을 줄인다. 슬로우모션·드론 검사 없음.
static func prewarm(scene: Node) -> void:
	for i in CHARACTERS.size():
		if not char_visible(CHARACTERS[i].id):
			continue
		var c := DiagonalDockingCutin.new()
		c.main = scene
		c.preview = true
		c._warm = 3
		c.char_i = i
		scene.add_child(c)


var _warm := 0


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	root = Node2D.new()
	add_child(root)
	back = Node2D.new()
	back.draw.connect(_draw_back)
	root.add_child(back)
	text_track = Node2D.new()
	text_mat = ShaderMaterial.new()
	text_mat.shader = TEXT_SHADER
	text_track.material = text_mat
	text_track.draw.connect(_draw_text)
	root.add_child(text_track)
	paper_back = Node2D.new()
	paper_back.draw.connect(_draw_papers.bind(false))
	root.add_child(paper_back)
	anchor = Node2D.new()
	root.add_child(anchor)
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	_use_character(char_i if char_i >= 0 else 0)
	var vis := char_visible(String(cfg.id))
	# 같은 모양 그림자 (캐릭터 맨 뒤): 같은 셰이더 · 같은 변형을 단색으로
	if cfg.has("shadow"):
		shadow_mat = ShaderMaterial.new()
		shadow_mat.shader = SHADER
		shadow_mat.set_shader_parameter("silhouette", 1.0)
		shadow_mat.set_shader_parameter("sil_color", THEMES[cfg.theme].sil)
		for k in ["c_l", "c_r", "r_l", "r_r", "tilt", "hair_mask", "hair_root", "hair_len", "bust", "motion"]:
			shadow_mat.set_shader_parameter(k, mat.get_shader_parameter(k))
		shadow = _portrait_sprite()
		shadow.material = shadow_mat
		shadow.modulate.a = 0.0
	if cfg.has("props") and vis:
		scatter = CutinScatter.new(self, cfg.props, cfg.sparkle)
		root.add_child(scatter.back)
		root.add_child(scatter.back_glow)
		root.move_child(anchor, -1)
	for i in 2:
		var g := _portrait_sprite()
		var gc: Color = THEMES[cfg.theme].ghost
		g.modulate = Color(gc.r, gc.g, gc.b, 0.0)
		ghosts.append(g)
	portrait = _portrait_sprite()
	for pd: Dictionary in cfg.get("pops", []):
		var sp := Sprite2D.new()
		sp.texture = pd.tex
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sp.scale = Vector2.ZERO
		if pd.has("pivot"):
			sp.offset = Vector2(pd.px) - Vector2(pd.pivot)   ## 꼬리 끝을 축으로 커진다
		anchor.add_child(sp)
		pops.append({"node": sp, "cfg": pd, "seed": rng.randf() * TAU})
	paper_front = Node2D.new()
	paper_front.draw.connect(_draw_papers.bind(true))
	root.add_child(paper_front)
	if scatter:
		root.add_child(scatter.front)
		root.add_child(scatter.front_glow)
	for i in int(cfg.get("papers", 0)):
		papers.append(_new_paper(i, int(cfg.get("papers", 0))))
	# 숨겨도 계산(이동 · 흔들림 · 팝업 · 종이)은 그대로 돌고 그리기만 끈다
	anchor.visible = vis
	paper_back.visible = vis
	paper_front.visible = vis
	front = Node2D.new()
	front.draw.connect(_draw_front)
	root.add_child(front)
	for i in LINES:
		lines.append(_new_line(false, true))
	for i in FRONT_LINES:
		front_lines.append(_new_line(true, true))
	_last_us = Time.get_ticks_usec()
	_layout()
	s = s_start
	_apply(0.0)
	# 화면 밖에서 이미 달려오던 중으로 친다: 첫 프레임에 0 → 최고 속도로 튀는 가짜 가속(가슴이 왼쪽으로 한번 튐)을 없앤다
	_pan_prev = anchor.position
	_pan_v = tangent * (3.0 * (s_hold + vs.x * 0.02 / tangent.x - s_start) / ENTER)
	_pan_init = true
	if _warm > 0:
		root.modulate.a = 0.004
		s = s_hold
		_apply(0.0)
		return
	_update_slow()


## 캐릭터 설정 · 테마 색 · 셰이더(가슴 영역 · 머리카락 마스크)
func _use_character(i: int) -> void:
	char_i = clampi(i, 0, CHARACTERS.size() - 1)
	cfg = CHARACTERS[char_i]
	art = cfg.art
	anchor_uv = cfg.anchor
	hair_uv = cfg.hair_top
	jig_scale = float(cfg.r) * art / 200.0
	var th: Dictionary = THEMES[cfg.theme]
	band_fill = th.fill
	band_top_edge = th.top_edge
	band_top_hi = th.top_hi
	band_low_dark = th.low_dark
	band_bottom_edge = th.bottom_edge
	band_shadow = th.shadow
	text_col = th.text
	accent = th.accent
	accent_hi = th.accent_hi
	var rr: float = cfg.r
	mat.set_shader_parameter("c_l", cfg.c_l)
	mat.set_shader_parameter("c_r", cfg.c_r)
	mat.set_shader_parameter("r_l", Vector2(rr, rr))
	mat.set_shader_parameter("r_r", Vector2(rr, rr))
	mat.set_shader_parameter("tilt", cfg.tilt)
	mat.set_shader_parameter("hair_mask", cfg.mask)
	mat.set_shader_parameter("hair_root", cfg.hair_root)
	mat.set_shader_parameter("hair_len", cfg.hair_len)
	mat.set_shader_parameter("bust", 1.0 if bool(cfg.get("bust", true)) else 0.0)
	mat.set_shader_parameter("motion", 1.0 if bool(cfg.get("motion", false)) else 0.0)


## 포트레이트와 그림자 셰이더에 같은 값을 (그림자는 같은 변형을 따라 한다)
func _mp(key: String, v: Variant) -> void:
	mat.set_shader_parameter(key, v)
	if shadow_mat:
		shadow_mat.set_shader_parameter(key, v)


func _portrait_sprite() -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = cfg.tex
	sp.centered = false
	sp.material = mat
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	anchor.add_child(sp)
	return sp


## 합체 완료 (드론이 등에 붙은 실제 순간)
func notify_dock() -> void:
	if ph == Ph.DONE or ph == Ph.EXIT or dock_t >= 0.0:
		return
	dock_t = t
	if ph == Ph.WAIT or ph == Ph.ENTER:
		ph = Ph.HOLD if t >= SETTLE else ph
	_pulse = 1.0
	hair_v.x += HAIR_DOCK_KICK
	skirt_v.x += SKIRT_DOCK_KICK
	cloth_v.x += CLOTH_DOCK_KICK
	if scatter:
		scatter.dock_burst()
	# 미리보기(F3)의 합체 순간 보이스. 본편은 PartnerDrone._gattai_impact 가 한 번 부른다(겹치지 않게 여기선 미리보기만).
	if preview and _warm <= 0:
		DockingVoice.play(main)
	# s 축으로만 툭 밀렸다 돌아온다 + 가슴이 위로 튄다
	_jolt_v = side * 2.2
	for i in 2:
		jig_v[i] += JIG_DOCK_KICK * (1.0 if i == 0 else 0.9) + Vector2(rng.randf_range(-60.0, 60.0), 0.0)
	# 강한 선 펄스
	for i in 6:
		lines.append(_new_line(false, false, 1.0))


## 접기: 합체 완료 전 취소·사망 → 성공 연출 없이 바로 오른쪽으로 빠진다
func cancel() -> void:
	if ph == Ph.DONE or ph == Ph.EXIT:
		return
	_begin_exit()


func _begin_exit() -> void:
	ph = Ph.EXIT
	exit_t = t
	exit_s0 = s


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	var raw := float(now - _last_us) / 1e6
	_last_us = now
	if fixed_dt > 0.0:
		raw = fixed_dt
	if _warm > 0:
		_warm -= 1
		if _warm == 0:
			queue_free()
		return
	if get_tree().paused:
		visible = false
		return
	visible = true
	# 표시 단계는 누적 절대 경과 (프레임 dt 상한으로 길이가 늘어나지 않게), 스프링만 제한 dt
	t += minf(raw, 0.25)
	var dt := minf(raw, 1.0 / 20.0)
	if preview:
		if dock_t < 0.0 and t >= PREVIEW_DOCK:
			notify_dock()
	elif dock_t < 0.0 and ph != Ph.EXIT and ph != Ph.DONE:
		var lost: bool = not is_instance_valid(drone) or drone.get("state") != PartnerDrone.St.RECALL
		if lost or t > WAIT_MAX:
			cancel()
	var pl: Variant = main.get("player") if is_instance_valid(main) else null
	if pl is Node and is_instance_valid(pl) and not bool((pl as Node).get("alive")):
		cancel()
	match ph:
		Ph.ENTER:
			if t >= SETTLE:
				ph = Ph.HOLD if dock_t >= 0.0 else Ph.WAIT
		Ph.WAIT:
			if dock_t >= 0.0:
				ph = Ph.HOLD
		Ph.HOLD:
			if t >= maxf(HOLD_END, dock_t + DOCK_TAIL):
				_begin_exit()
		Ph.EXIT:
			if t >= exit_t + EXIT and done_t < 0.0:
				done_t = t
	if done_t >= 0.0 and t >= done_t + CLEAN:
		ph = Ph.DONE
		_release_slow()
		queue_free()
		return
	_update_slow()
	_layout()
	_apply(dt)


## 임팩트 때 글자 흐름 배율: 합체 순간 급제동 → 거의 멈춤 → 다시 흐름
func text_k() -> float:
	if dock_t < 0.0:
		return 1.0
	var since := t - dock_t
	var b := 1.0                                     ## 슬로우모션 깊이 0~1
	if since < TEXT_BRAKE:
		b = sin(0.5 * PI * since / TEXT_BRAKE)
	elif since >= TEXT_FREEZE:
		b = 1.0 - smoothstep(TEXT_FREEZE, TEXT_RESUME, since)
	return exp(lerpf(0.0, log(TEXT_MIN), b))


# ── 슬로우모션 ─────────────────────────────────────

var _slow_on := false

## 지금 걸 게임 시간 배율: 진입~체류 SLOW, 퇴장 시작부터 정리 끝까지 제곱으로 1 에 복귀
func slow_rate() -> float:
	if ph != Ph.EXIT and ph != Ph.DONE:
		return SLOW
	var k := clampf((t - exit_t) / (EXIT + CLEAN), 0.0, 1.0)
	return lerpf(SLOW, 1.0, k * k)


func _update_slow() -> void:
	if not is_instance_valid(main) or not main.has_method("set_slowmo"):
		return
	var pl: Variant = main.get("player")
	# 궁극기 락온이 시간을 쥐고 있으면 건드리지 않는다
	if pl is Node and is_instance_valid(pl) and (pl as Node).has_method("ult_busy") and (pl as Node).call("ult_busy"):
		_slow_on = false
		return
	main.call("set_slowmo", slow_rate())
	_slow_on = true


func _release_slow() -> void:
	if _slow_on and is_instance_valid(main) and main.has_method("set_slowmo"):
		main.call("set_slowmo", 1.0)
	_slow_on = false


func _exit_tree() -> void:
	_release_slow()


## 화면 크기 → 하단선 O·T·N, 위 경계, 포트레이트 크기, 진입/체류/퇴장 s
func _layout() -> void:
	vs = get_viewport().get_visible_rect().size
	var th := deg_to_rad(THETA)
	tangent = Vector2(cos(th), sin(th))
	normal = Vector2(-sin(th), cos(th))
	origin = Vector2(0.0, vs.y * BOTTOM_LEFT)
	var tt := deg_to_rad(TOP_THETA)
	top_origin = Vector2(0.0, vs.y * TOP_LEFT)
	top_normal = Vector2(-sin(tt), cos(tt))
	s_hold = vs.x * X_HOLD / tangent.x
	var hold_y := origin.y + tangent.y * s_hold
	side = minf((hold_y - vs.y * float(cfg.hair_screen)) / (anchor_uv.y - hair_uv), minf(vs.x * SIDE_MAX_W, vs.y * float(cfg.side_max_h)))
	var margin := side * 0.08
	s_start = (-side * anchor_uv.x - margin) / tangent.x
	s_end = (vs.x + side * (1.0 - anchor_uv.x) + margin) / tangent.x
	# 글자 크기는 화면 가운데 띠 높이에 맞춘다 (정수로 묶어 글리프 캐시가 늘지 않게)
	var band_h := _band_height(vs.x * 0.5)
	# 글자 높이: TEXT_H, 단 띠가 가장 좁은 왼쪽 끝(x=0)에서 바닥선~위 테두리 사이에 들어가게
	var room := (origin.y - _band_height(vs.x * 0.25) * TEXT_LIFT / cos(deg_to_rad(THETA))) - (top_origin.y + vs.y * TEXT_TOP_GAP)
	var cap_h := minf(vs.y * TEXT_H, room)
	_font_size = clampi(int(snappedf(cap_h / (TEXT_CAP * TEXT_SY), 4.0)), 24, 800)
	# 반복 간격은 하단선(T) 방향 거리: 가로 폭 / cosθ
	_period = (FONT.get_string_size(TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size).x * TEXT_SX + _font_size * TEXT_GAP) / tangent.x


## x 에서 위 경계 ~ 하단선 사이의 법선 방향 두께
func _band_height(x: float) -> float:
	var yb := origin.y + tan(deg_to_rad(THETA)) * x
	var yt := top_origin.y + tan(deg_to_rad(TOP_THETA)) * x
	return (yb - yt) * cos(deg_to_rad(THETA))


func _point(ss: float, q := 0.0) -> Vector2:
	return origin + tangent * ss + normal * q


## 진입 · 정착 · 체류 · 퇴장 → s
func _motion() -> float:
	var over := vs.x * 0.02 / tangent.x          ## 정착 때 살짝 지나쳤다 돌아옴 (같은 s 축)
	var drift := vs.x * 0.025 / tangent.x        ## 체류 중 미세 전진 (F2 → F3)
	var v := s_hold
	if t < ENTER:
		var k := t / ENTER
		v = lerpf(s_start, s_hold + over, 1.0 - pow(1.0 - k, 3.0))
	elif t < SETTLE:
		v = lerpf(s_hold + over, s_hold, smoothstep(0.0, 1.0, (t - ENTER) / (SETTLE - ENTER)))
	else:
		v = s_hold + drift * clampf((t - SETTLE) / (HOLD_END - SETTLE), 0.0, 1.0)
	if ph == Ph.EXIT or ph == Ph.DONE:
		var k := clampf((t - exit_t) / EXIT, 0.0, 1.0)
		v = lerpf(exit_s0, s_end, k * k * k)
	return v


func _apply(dt: float) -> void:
	if dt > 0.0:
		var n := maxi(1, ceili(dt * 240.0))
		var h := dt / n
		for i in n:
			_jolt_v += (-_jolt * 900.0 - _jolt_v * 26.0) * h
			_jolt += _jolt_v * h
	var prev_s := s
	s = _motion() + _jolt
	if dt > 0.0:
		s_vel = (s - prev_s) / dt
	anchor.position = _point(s)
	max_clip_err = maxf(max_clip_err, absf((anchor.position - origin).dot(normal)))
	_tween(dt)
	portrait.scale = Vector2.ONE * (side / art)
	portrait.position = -anchor_uv * side
	# 잔상: 진입·퇴장에만, s - Δs 자리에 (같은 하단 마스크). 기준점의 회전·크기를 되돌려 화면에서 진행 방향 뒤로
	var moving := absf(s_vel) / maxf(vs.x, 1.0)
	for i in ghosts.size():
		var g := ghosts[i]
		g.scale = portrait.scale
		g.position = portrait.position - (tangent * s_vel * 0.011 * float(i + 1)).rotated(-anchor.rotation) / anchor.scale
		g.modulate.a = clampf((moving - 0.6) / 3.0, 0.0, 1.0) * (0.3 if i == 0 else 0.14)
	_band_k = clampf(t / BAND_IN, 0.0, 1.0)
	_fade = 1.0 if done_t < 0.0 else clampf(1.0 - (t - done_t) / CLEAN, 0.0, 1.0)
	_pulse = maxf(0.0, _pulse - dt * 4.0)
	_mp("clip_origin", origin)
	_mp("clip_normal", normal)
	mat.set_shader_parameter("flash", 0.32 * _pulse * _pulse)
	_update_shadow()
	text_mat.set_shader_parameter("bottom_origin", origin)
	text_mat.set_shader_parameter("bottom_normal", normal)
	text_mat.set_shader_parameter("top_origin", _top_origin_now())
	text_mat.set_shader_parameter("top_normal", top_normal)
	_text_off = fposmod(_text_off + TEXT_SPEED * text_k() * vs.x * dt, _period)
	_update_lines(dt)
	_update_pops()
	_update_papers(dt)
	_jiggle(dt)
	if scatter:
		scatter.update(dt)
	back.queue_redraw()
	text_track.queue_redraw()
	front.queue_redraw()
	if not papers.is_empty():
		paper_back.queue_redraw()
		paper_front.queue_redraw()


## 캐릭터 트위닝: 등장 타임라인에 맞춘 짧은 곡선. 모두 기준점(하단선 위)을 축으로 하므로 하단선 접점과 마스크는 그대로다.
func _tween(_dt: float) -> void:
	var P: Dictionary = tween()
	anchor.rotation = tilt_at()
	var enter_k := lerpf(float(P.enter_scale), 1.0, 1.0 - pow(1.0 - clampf(t / ENTER, 0.0, 1.0), 3.0))
	var hold_k := smoothstep(SETTLE, SETTLE + 0.15, t)
	if exit_t >= 0.0:
		hold_k *= 1.0 - smoothstep(0.0, EXIT, t - exit_t)
	var breath := 1.0 + BREATH * sin(TAU * 1.0 * maxf(t - SETTLE, 0.0)) * hold_k
	var p := pop_at()
	# 달리는 동안 가로로 늘어남 → 쏠림 최대 뒤 세로로 찌그러짐
	var peak_t: float = P.peak_t
	var st: float = float(P.stretch) * (1.0 - smoothstep(0.0, peak_t, t))
	var q := 0.0
	var sq_t: float = P.squash_t
	if t >= peak_t and t < peak_t + sq_t:
		q = float(P.squash) * sin(PI * (t - peak_t) / sq_t)
	anchor.scale = Vector2((1.0 + st - q) * (1.0 - 0.45 * p), (1.0 - 0.5 * st + q) * (1.0 + p)) * enter_k * breath


static func tween() -> Dictionary:
	return TWEEN_PRESETS[clampi(tween_preset, 0, TWEEN_PRESETS.size() - 1)]


static func use_tween_id(id: String) -> bool:
	for i in TWEEN_PRESETS.size():
		if TWEEN_PRESETS[i].id == id:
			tween_preset = i
			return true
	return false


## 기울기 (rad, + = 위쪽이 오른쪽). [예비 젖힘] → peak_t 에 최대 → settle 동안 작은 되돌림 한 번 → 0.
## 퇴장에서는 오른쪽으로 가속하는 만큼 뒤로 젖혀진다.
func tilt_at() -> float:
	var P: Dictionary = tween()
	var amp: float = P.amp
	var pre: float = P.pre
	var pre_t: float = P.pre_t
	var peak_t: float = P.peak_t
	var settle: float = P.settle
	var r := 0.0
	if t < peak_t:
		if pre > 0.0 and t < pre_t:
			r = -pre * smoothstep(0.0, 1.0, t / pre_t)
		else:
			var a0 := pre_t if pre > 0.0 else 0.0
			var r0 := -pre if pre > 0.0 else 0.0
			var u := clampf((t - a0) / maxf(peak_t - a0, 0.001), 0.0, 1.0)
			r = lerpf(r0, amp, u * u * (3.0 - 2.0 * u))
	elif t < peak_t + settle:
		var v := (t - peak_t) / settle
		r = amp * (pow(1.0 - v, 3.0) - float(P.back) * sin(PI * v))
	if exit_t >= 0.0:
		var k := clampf((t - exit_t) / EXIT, 0.0, 1.0)
		r = r * (1.0 - k) - float(P.out) * k * k
	return r


## 합체 팝: 세로로 쭉 늘었다(앞 60%) 살짝 눌리고(뒤 40%) POP_T 안에 끝
func pop_at() -> float:
	if dock_t < 0.0:
		return 0.0
	var d := (t - dock_t) / POP_T
	if d < 0.0 or d >= 1.0:
		return 0.0
	var pop: float = tween().pop
	if d < 0.6:
		return pop * sin(PI * d / 0.6)
	return -pop * 0.3 * sin(PI * (d - 0.6) / 0.4)


## 띠가 펼쳐지는 동안 위 경계를 하단선 쪽에서 끌어올린다
func _top_origin_now() -> Vector2:
	var e := 1.0 - pow(1.0 - _band_k, 3.0)
	return origin.lerp(top_origin, e)


# ── 그리기 ─────────────────────────────────────────

func _draw_back() -> void:
	var a := _fade
	back.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.0, 0.0, 0.03, 0.16 * a * _band_k))
	var x0 := -40.0
	var x1 := vs.x + 40.0
	var tb := tan(deg_to_rad(THETA))
	var to := _top_origin_now()
	var tt := tan(deg_to_rad(TOP_THETA))
	var e := 1.0 - pow(1.0 - _band_k, 3.0)
	var slope_t := lerpf(tb, tt, e)
	var b0 := Vector2(x0, origin.y + tb * x0)
	var b1 := Vector2(x1, origin.y + tb * x1)
	var t0 := Vector2(x0, to.y + slope_t * x0)
	var t1 := Vector2(x1, to.y + slope_t * x1)
	var u := vs.y / 800.0
	# 띠 밖 아래 그림자
	_line(back, b0, b1, normal * 5.0 * u, band_shadow, 10.0 * u, a * _band_k)
	var fill := band_fill
	fill.a *= a
	back.draw_colored_polygon(PackedVector2Array([t0, t1, b1, b0]), fill)
	var tn := Vector2(-slope_t, 1.0).normalized()
	# 위: 탁한 민트 테두리 + 그 아래 옅은 밝은 줄
	_line(back, t0, t1, tn * 4.5 * u, band_top_edge.lerp(Color.WHITE, _pulse * 0.6), (9.0 + 4.0 * _pulse) * u, a)
	_line(back, t0, t1, tn * 16.0 * u, band_top_hi, 6.0 * u, a * 0.85)
	# 아래(띠 안): 남색 줄 → 흰 줄 (하단선에서 띠 두께 비율로)
	var bh := _band_height(vs.x * 0.25)
	_line(back, b0, b1, -normal * bh * 0.135, band_low_dark, 12.0 * u, a * _band_k)
	_line(back, b0, b1, -normal * bh * 0.098, BAND_LOW_WHITE.lerp(accent, _pulse * 0.4), 6.0 * u, a * _band_k)
	for l in lines:
		_draw_streak(back, l, a)


## 띠와 평행한 줄 (p0→p1 을 off 만큼 옮겨서)
func _line(ci: CanvasItem, p0: Vector2, p1: Vector2, off: Vector2, col: Color, width: float, alpha: float) -> void:
	var c := col
	c.a *= alpha
	if c.a <= 0.005:
		return
	ci.draw_line(p0 + off, p1 + off, c, width, true)


## DOCKING 반복: 글자는 세운 채 Y 기울이기(가로축 = 하단선 방향, 세로축 = 수직) · 세로 늘임 · 가로 눌림.
## 빠르게 흐를 때는 뒤쪽으로 옅은 잔상 3겹(속도감 · 눈에 거의 안 보일 만큼).
func _draw_text() -> void:
	if _period <= 1.0:
		return
	var bh := _band_height(vs.x * 0.25)
	var q_base := -bh * TEXT_LIFT
	var length := vs.x / tangent.x
	var tb := tan(deg_to_rad(THETA))
	var x_axis := Vector2(TEXT_SX, TEXT_SX * tb)
	var y_axis := Vector2(0.0, TEXT_SY)
	var speed_k := text_k()
	var step := TEXT_SPEED * speed_k * vs.x / tangent.x / 60.0          ## 한 프레임(60fps)에 흐르는 거리
	var ghost_k := smoothstep(0.08, 0.6, speed_k)    ## 느려질수록 잔상이 부드럽게 사라짐
	var ghosts := 3 if ghost_k > 0.01 else 0
	for g in range(ghosts, -1, -1):
		var col := text_col
		col.a = _fade * (1.0 if g == 0 else [0.0, 0.32, 0.18, 0.09][g] * ghost_k)
		var back_off := -step * 0.33 * float(g)
		var i := -2
		while true:
			var ss := float(i) * _period + _text_off + back_off
			if ss > length + _period:
				break
			var p := _point(ss, q_base)
			text_track.draw_set_transform_matrix(Transform2D(x_axis, y_axis, p))
			text_track.draw_string(FONT, Vector2.ZERO, TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, col)
			i += 1
	text_track.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_front() -> void:
	var a := _fade
	var u := vs.y / 800.0
	var tb := tan(deg_to_rad(THETA))
	var x0 := -40.0
	var x1 := vs.x + 40.0
	var b0 := Vector2(x0, origin.y + tb * x0)
	var b1 := Vector2(x1, origin.y + tb * x1)
	# 하단 테두리: 민트 (포트레이트가 잘린 면을 깔끔하게 덮는다)
	_line(front, b0, b1, -normal * 2.5 * u, band_bottom_edge.lerp(Color.WHITE, _pulse * 0.7), (6.0 + 5.0 * _pulse) * u, a * _band_k)
	for l in front_lines:
		_draw_streak(front, l, a)


## 긴 쐐기: 앞뒤가 뾰족한 마름모
func _draw_streak(ci: CanvasItem, l: Dictionary, a: float) -> void:
	var life: float = l.life
	var age: float = l.age
	if age < 0.0 or age > life:
		return
	var k := age / life
	var alpha := sin(k * PI) * a * float(l.get("str", 1.0))
	if alpha <= 0.01:
		return
	var dir := tangent.rotated(float(l.ang))
	var nrm := Vector2(-dir.y, dir.x)
	var c := _point(float(l.s), float(l.q))
	var half := float(l.len) * 0.5
	var w := float(l.w) * (vs.y / 800.0)
	var col: Color = l.col
	col.a *= alpha
	var p0 := c - dir * half
	var p1 := c + dir * half
	var m := c + dir * half * 0.35
	ci.draw_colored_polygon(PackedVector2Array([p0, m + nrm * w * 0.5, p1, m - nrm * w * 0.5]), col)


# ── 집중선 ─────────────────────────────────────────

func _new_line(is_front: bool, idle := false, strength := 1.0) -> Dictionary:
	var cols := [Color(1, 1, 1, 0.95), Color(0.02, 0.03, 0.06, 0.9), accent, accent_hi]
	var q: float
	if is_front:
		q = rng.randf_range(-0.04, 0.10) * vs.y           ## 하단선 근처만 (얼굴은 가리지 않는다)
	else:
		q = rng.randf_range(-0.62, 0.22) * vs.y
	var col: Color = cols[rng.randi() % cols.size()]
	if is_front:
		col = cols[rng.randi() % 2]                        ## 앞 선은 흰색·검정만
	return {
		"s": rng.randf_range(-0.2, 1.1) * vs.x / tangent.x,
		"q": q,
		"len": rng.randf_range(0.3, 0.9) * vs.x,
		"w": rng.randf_range(2.0, 5.0) if is_front else rng.randf_range(2.0, 12.0),
		"col": col,
		"age": -1.0 if idle else 0.0,
		"life": rng.randf_range(0.07, 0.16),
		"v": rng.randf_range(1.6, 2.8) * vs.x,
		"ang": rng.randf_range(-0.03, 0.05),                 ## 오른쪽 밖으로 완만하게 모인다
		"str": strength,
	}


## 강도: 진입·퇴장 강하게 · 체류 약하게 · 정리 중 없음
func _line_rate() -> float:
	if done_t >= 0.0:
		return 0.0
	if ph == Ph.EXIT:
		return 90.0
	if t < SETTLE:
		return 120.0
	return 36.0


func _update_lines(dt: float) -> void:
	if dt <= 0.0:
		return
	var face := _face_rect()
	for arr in [lines, front_lines]:
		for l: Dictionary in arr:
			if float(l.age) >= 0.0:
				l.age = float(l.age) + dt
				l.s = float(l.s) + float(l.v) * dt / tangent.x
	# 수명 단위로 재사용 (매 프레임 새로 만들지 않는다). 추가로 붙은 펄스 선은 끝나면 뺀다.
	var i := lines.size() - 1
	while i >= LINES:
		if float(lines[i].age) > float(lines[i].life):
			lines.remove_at(i)
		i -= 1
	_spawn_acc += _line_rate() * dt
	while _spawn_acc >= 1.0:
		_spawn_acc -= 1.0
		var front_pick := rng.randf() < 0.2
		var arr: Array = front_lines if front_pick else lines
		var cap := FRONT_LINES if front_pick else LINES
		for j in cap:
			var l: Dictionary = arr[j]
			if float(l.age) < 0.0 or float(l.age) > float(l.life):
				var nl := _new_line(front_pick)
				if front_pick and char_visible(String(cfg.id)) and face.has_point(_point(float(nl.s), float(nl.q))):
					break
				arr[j] = nl
				break


## 얼굴 영역 (앞 선을 피한다)
func _face_rect() -> Rect2:
	var c := anchor.position + (Vector2(cfg.face) - anchor_uv) * side
	return Rect2(c - Vector2(0.22, 0.2) * side, Vector2(0.44, 0.4) * side)


# ── 가슴 스프링 ───────────────────────────────────

func _jiggle(dt: float) -> void:
	if dt <= 0.0:
		return
	_pan = anchor.position
	var px_to_art := art / maxf(side, 1.0)
	if not _pan_init:
		_pan_prev = _pan
		_pan_init = true
	var v := (_pan - _pan_prev) / dt
	var acc := (v - _pan_v) / dt
	_pan_prev = _pan
	_pan_v = v
	acc = (acc * px_to_art).limit_length(60000.0)
	_acc_hist.append([t, acc])
	while _acc_hist.size() > 2 and float(_acc_hist[1][0]) <= t - JIG_LAG:
		_acc_hist.pop_front()
	var acc_r: Vector2 = _acc_hist[0][1]
	var n := maxi(1, ceili(dt * 240.0))
	var h := dt / n
	for side_i in 2:
		var w := TAU * JIG_HZ * (JIG_R_DETUNE if side_i == 1 else 1.0)
		var f_acc: Vector2 = (acc if side_i == 0 else acc_r) * -JIG_GAIN
		var x: Vector2 = jig_raw[side_i]
		var xv: Vector2 = jig_v[side_i]
		for i in n:
			var ky := w.y * w.y * (JIG_DOWN_SOFT if x.y > 0.0 else 1.0)
			var rest_y := -JIG_LIFT * x.x * x.x
			var f := Vector2(-w.x * w.x * x.x - 2.0 * JIG_ZETA.x * w.x * xv.x,
				-ky * (x.y - rest_y) - 2.0 * JIG_ZETA.y * w.y * xv.y + (JIG_G if x.y < 0.0 else 0.0)) + f_acc
			xv += f * h
			x += xv * h
		jig_raw[side_i] = x
		jig_v[side_i] = xv
		var shown := Vector2(JIG_MAX * tanh(x.x / JIG_MAX), JIG_MAX * tanh(x.y / JIG_MAX))
		jig[side_i] = shown
		jig_peak = maxf(jig_peak, shown.length())
	var l: Vector2 = jig[0]
	var r: Vector2 = jig[1]
	# 머리카락: 같은 가속도 관성(가로 위주), 좌우로 날리면 끝이 살짝 들림
	var hw := TAU * HAIR_HZ
	for i in n:
		var fh := -hw * hw * hair.x - 2.0 * HAIR_ZETA * hw * hair_v.x - acc.x * HAIR_GAIN
		hair_v.x += fh * h
		hair.x += hair_v.x * h
	var hx := HAIR_MAX * tanh(hair.x / HAIR_MAX)
	hx *= float(cfg.get("hair_k", 1.0))
	_mp("hair_off", Vector2(hx, -absf(hx) * 0.18) / art)
	_mp("hair_time", t)
	_mp("off_l", l * jig_scale / art)
	_mp("off_r", r * jig_scale / art)
	# 아래로 처지면 세로로 늘어지고, 들리면 눌린다
	_mp("sq_l", clampf(l.y / JIG_MAX * JIG_SQ, -JIG_SQ, JIG_SQ))
	_mp("sq_r", clampf(r.y / JIG_MAX * JIG_SQ, -JIG_SQ, JIG_SQ))
	if bool(cfg.get("motion", false)):
		_cloth_springs(acc, acc_r, n, h)


## 치마 · 리본 꼬리: 가로 관성 스프링(리본은 한 박자 늦은 가속도) → 셰이더의 G · B 영역. 흔들릴수록 밑단이 들린다.
func _cloth_springs(acc: Vector2, acc_r: Vector2, n: int, h: float) -> void:
	var ws := TAU * SKIRT_HZ
	var wc := TAU * CLOTH_HZ
	for i in n:
		skirt_v.x += (-ws * ws * skirt.x - 2.0 * SKIRT_ZETA * ws * skirt_v.x - acc.x * SKIRT_GAIN) * h
		skirt.x += skirt_v.x * h
		cloth_v.x += (-wc * wc * cloth.x - 2.0 * CLOTH_ZETA * wc * cloth_v.x - acc_r.x * CLOTH_GAIN) * h
		cloth.x += cloth_v.x * h
	var sx := SKIRT_MAX * tanh(skirt.x / SKIRT_MAX)
	var cx := CLOTH_MAX * tanh(cloth.x / CLOTH_MAX)
	skirt_peak = maxf(skirt_peak, absf(sx))
	cloth_peak = maxf(cloth_peak, absf(cx))
	_mp("skirt_off", Vector2(sx, -absf(sx) * SKIRT_LIFT) / art)
	_mp("cloth_off", Vector2(cx, -absf(cx) * 0.2) / art)
	var speed := clampf(absf(s_vel) * tangent.x / maxf(vs.x * 3.0, 1.0), 0.0, 1.0)
	_mp("flutter", FLUTTER.x + FLUTTER.y * speed + FLUTTER.z * _pulse)


## 그림자: 캐릭터 자리에서 오른쪽으로 자라남(back-out 넘침) · 이동 중엔 속도만큼 뒤로 끌림 · 퇴장 때 더 벌어지며 흐려짐
func _update_shadow() -> void:
	if shadow == null:
		return
	var sc: Dictionary = cfg.shadow
	var k := clampf((t - SHADOW_GROW.x) / (SHADOW_GROW.y - SHADOW_GROW.x), 0.0, 1.0)
	var g := _back_out(k, 1.8) if k > 0.0 else 0.0
	var alpha := smoothstep(0.0, 0.35, k)
	if exit_t >= 0.0:
		var e := clampf((t - exit_t) / EXIT, 0.0, 1.0)
		g += 0.4 * e
		alpha *= 1.0 - e
	shadow_k = k
	var off: Vector2 = sc.off
	var lag := (tangent * s_vel * SHADOW_DRAG).rotated(-anchor.rotation) / anchor.scale
	var grow := 1.0 + float(sc.scale) * g
	shadow.scale = portrait.scale * grow
	shadow.position = portrait.position * grow + off * side * g - lag
	shadow.modulate.a = alpha * _fade



# ── 장식 팝업 (초록 메이드의 하트 말풍선 · 반짝이) ─────────────────
## 순서대로: 말풍선이 꼬리 쪽에서 비틀며 튀어나옴(넘침 → 살짝 눌림 → 자리) → 하트가 크게 뿅 → 두근두근 →
## 반짝이 둘이 돌며 반짝. 퇴장이 시작되면 모두 0.08초에 쏙 들어간다. 기준점(anchor)의 자식이라 캐릭터와 같이 움직이고 기운다.

static func _back_out(x: float, k := 2.4) -> float:
	var u := x - 1.0
	return 1.0 + (k + 1.0) * u * u * u + k * u * u


func _update_pops() -> void:
	if pops.is_empty():
		return
	var px_scale := side / art
	var gone := 1.0
	if exit_t >= 0.0:
		gone = 1.0 - smoothstep(0.0, 0.08, t - exit_t)
	for p: Dictionary in pops:
		var sp: Sprite2D = p.node
		var pd: Dictionary = p.cfg
		var u := t - float(pd.at)
		var base := (Vector2(pd.get("pivot", pd.px)) / art - anchor_uv) * side
		if u <= 0.0:
			sp.scale = Vector2.ZERO
			continue
		var sc := 1.0
		var rot := 0.0
		var off := Vector2.ZERO
		match String(pd.kind):
			"bubble":
				# 0~0.09 꼬리(오른쪽 아래)에서 비틀며 넘치게 · 0.09~0.2 살짝 눌렸다 자리 · 그 뒤 둥실
				var k := clampf(u / 0.11, 0.0, 1.0)
				sc = _back_out(k, 3.2)
				rot = lerpf(-0.55, 0.0, _back_out(k, 2.0))
				var bob := sin((u - 0.11) * 5.5 + float(p.seed)) * 4.0 * px_scale * 3.0 * smoothstep(0.11, 0.3, u)
				off.y += bob
				sp.scale = Vector2(1.0 + 0.12 * sin(clampf((u - 0.11) / 0.12, 0.0, 1.0) * PI), 1.0 - 0.1 * sin(clampf((u - 0.11) / 0.12, 0.0, 1.0) * PI)) * sc * px_scale * gone
			"heart":
				var k := clampf(u / 0.1, 0.0, 1.0)
				sc = _back_out(k, 4.0)
				# 두근두근: 0.45초마다 두 번 뛴다
				var beat := fmod(maxf(u - 0.14, 0.0), 0.45)
				sc *= 1.0 + 0.16 * exp(-beat * 22.0) * sin(beat * 40.0) * smoothstep(0.1, 0.16, u)
				var bob2 := sin((u - 0.11) * 5.5 + float(pops[0].seed)) * 4.0 * px_scale * 3.0 * smoothstep(0.0, 0.2, u)
				off.y += bob2
				sp.scale = Vector2.ONE * sc * px_scale * gone
			"sparkle":
				var k := clampf(u / 0.12, 0.0, 1.0)
				sc = _back_out(k, 2.6) * (0.9 + 0.18 * sin(u * 13.0 + float(p.seed)))
				rot = (1.0 - k) * 1.6 + sin(u * 3.0 + float(p.seed)) * 0.15
				sp.modulate.a = 0.75 + 0.25 * sin(u * 17.0 + float(p.seed))
				sp.scale = Vector2.ONE * sc * px_scale * gone
		sp.position = base + off
		sp.rotation = rot


# ── 서류 종이 (초록 메이드: 캐릭터가 달려오는 바람에 같은 방향으로 휘날림) ─────
## 캐릭터 뒤(왼쪽)에서 생겨 캐릭터 속도로 함께 끌려오다, 캐릭터가 서도 관성으로 앞질러 오른쪽으로 날아간다.
## 바람 = 캐릭터 진행 속도(하단선 방향)를 따라가는 항력 · 종이는 뒤집히며(가로 cos) 돌고 팔랑이며 천천히 떨어진다. 퇴장 때 다시 돌풍.
## 40% 는 캐릭터 뒤, 60% 는 앞(얼굴을 가리지 않게 몸 아래쪽).

func _new_paper(i: int, n: int) -> Dictionary:
	var front_side := (i % 5) >= 2
	return {
		"born": 0.01 + 0.13 * float(i) / maxf(n - 1, 1) + rng.randf_range(0.0, 0.02),
		"alive": false, "front": front_side,
		"pos": Vector2.ZERO, "vel": Vector2.ZERO,
		"rot": rng.randf_range(-PI, PI), "rot_v": rng.randf_range(-7.0, 7.0),
		"flip": rng.randf_range(0.0, TAU), "flip_v": rng.randf_range(7.0, 15.0) * (1.0 if rng.randf() < 0.5 else -1.0),
		"w": rng.randf_range(54.0, 92.0), "carry": rng.randf_range(0.95, 1.35),
		"up": rng.randf_range(0.15, 0.75) if not front_side else rng.randf_range(-0.05, 0.42),
		"back": rng.randf_range(0.05, 0.6), "sway": rng.randf_range(0.0, TAU), "age": 0.0,
	}


func _update_papers(dt: float) -> void:
	if papers.is_empty() or dt <= 0.0:
		return
	var u := vs.y / 800.0
	var wind := tangent * maxf(s_vel, 0.0) * 0.9
	for p: Dictionary in papers:
		if not bool(p.alive):
			if t >= float(p.born):
				# 캐릭터 뒤(왼쪽)·몸 높이에서 생겨 지금 캐릭터 속도로 출발
				p.alive = true
				p.pos = anchor.position - tangent * side * float(p.back) - Vector2(0.0, side * float(p.up))
				p.vel = tangent * maxf(s_vel, 0.0) * float(p.carry) + Vector2(0.0, -rng.randf_range(80.0, 260.0) * u)
			continue
		p.age = float(p.age) + dt
		var v: Vector2 = p.vel
		# 항력으로 바람(캐릭터 속도)을 따라감 · 바람이 잦아들면 오른쪽으로 잔잔히 흘러가며 떨어짐
		var drift := tangent * 70.0 * u
		v += ((wind + drift) - v) * minf(1.0, 2.6 * dt)
		v.y += 140.0 * u * dt
		v.x += sin(float(p.age) * 7.0 + float(p.sway)) * 260.0 * u * dt
		p.vel = v
		p.pos = Vector2(p.pos) + v * dt
		p.rot_v = float(p.rot_v) * exp(-1.2 * dt)
		p.rot = float(p.rot) + float(p.rot_v) * dt
		p.flip = float(p.flip) + float(p.flip_v) * dt


func _draw_papers(front_layer: bool) -> void:
	var ci: Node2D = paper_front if front_layer else paper_back
	var u := vs.y / 800.0
	for p: Dictionary in papers:
		if not bool(p.alive) or bool(p.front) != front_layer:
			continue
		var a := _fade * clampf(float(p.age) / 0.05, 0.0, 1.0)
		if exit_t >= 0.0 and done_t >= 0.0:
			a *= clampf(1.0 - (t - done_t) / CLEAN, 0.0, 1.0)
		if a <= 0.01:
			continue
		var w := float(p.w) * u
		var h := w * 1.3
		var fx := cos(float(p.flip))
		var face_up := fx >= 0.0
		var hw := w * 0.5 * maxf(absf(fx), 0.08)
		var hh := h * 0.5
		var xf := Transform2D(float(p.rot), Vector2(p.pos))
		var quad := PackedVector2Array([xf * Vector2(-hw, -hh), xf * Vector2(hw, -hh), xf * Vector2(hw, hh), xf * Vector2(-hw, hh)])
		var paper := Color(0.97, 0.98, 1.0, a) if face_up else Color(0.80, 0.84, 0.90, a)
		ci.draw_colored_polygon(quad, paper)
		var edge := Color(0.12, 0.13, 0.2, a * 0.9)
		ci.draw_polyline(PackedVector2Array([quad[0], quad[1], quad[2], quad[3], quad[0]]), edge, 1.6 * u, true)
		if face_up and absf(fx) > 0.35:
			# 서류 글줄 몇 개 + 위쪽 제목 줄
			var lc := Color(0.45, 0.55, 0.7, a * 0.8)
			for k in 5:
				var yy := -hh * 0.62 + float(k) * hh * 0.3
				var x1 := hw * (0.7 if k == 0 else 0.6 - 0.15 * float(k % 2))
				ci.draw_line(xf * Vector2(-hw * 0.7, yy), xf * Vector2(x1, yy), lc, (2.4 if k == 0 else 1.3) * u, true)
