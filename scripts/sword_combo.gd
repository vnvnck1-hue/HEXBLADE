class_name SwordCombo
extends RefCounted
## 광선검 6단 콤보. Player 가 소유하고 매 물리 틱 update() → pose() 순으로 부른다.
## 젠레스 존 제로·드래곤볼식 과장 연출: 키 포즈를 몇 프레임 버티다 1~2프레임 만에 폭발하고,
## 한 번 누를 때 여러 번 베며(다단히트), 중간에 뒤로 물러나 총을 쏘거나, 눈에 보이지 않는 속도로 돈다.
##
##  1타 섬광 삼연참    파고들며 가로 → 역 → 가로, 6프레임 동안 3번 벤다
##  2타 반동 사격      역베기 → 뒤로 공중제비를 돌며 물러나 총 4발 → 2프레임 만에 되돌아와 꿰뚫는 찌르기
##  3타 순섬 난무      적 둘레로 순간이동하며 사방에서 6번 X자로 긋고 마지막 십자 베기
##  4타 선풍           몸을 낮게 감았다가 0.33초에 5바퀴 돌며 7번 베는 회오리 (몸이 잔상으로만 보인다)
##  5타 도약 올려베기  웅크렸다 뛰어오르며 두 번 올려 벤다 (공중으로 떠오른다)
##  6타 낙월 · 지연참   정점에서 앞으로 두 바퀴 돌며 내리꽂고, 한 박자 뒤 주변 허공에 칼자국이 연달아 터진다
##
## 연결 규칙: 각 단의 타격 중 하나라도 실제로 적중(장갑에 막히지 않은 피해)했을 때만 다음 단으로 이어진다.
##  - 적중 → 짧은 캔슬 지점부터 선입력이 곧바로 다음 단을 낸다. 입력이 없으면 LINK_TIME 동안 기다린다.
##  - 헛침 → 휘두른 기세에 몸이 끌려가는 오버스윙 자세로 늘어지고 WHIFF_LOCK 동안 검을 못 쓴다. 콤보는 1타로.
##  - 막힘(장갑) → 칼이 튕겨 뒤로 밀리며 같은 경직.
## 자세는 준비(WINDUP: 빠르게 감기고 멈칫) → 스윙(SWING 1~4프레임, 폭발적으로 뻗는다) →
## 여운(FOLLOW: 살짝 넘쳤다 돌아온다) → 복귀(RETURN) 로 보간한다. 스윙 동안에는 프레임 사이 자세를
## 여러 번 계산해 광선검 잔상에 넘겨, 한 프레임에 크게 도는 칼도 매끈한 초승달을 남긴다.
##
## cut 확장 키:
##  hits  스윙 동안 고르게 나눠 판정하는 횟수 (다단히트, 기본 1 = 스윙 끝에서 한 번)
##  blink 준비 직전에 대상 둘레로 이만큼(도) 돌아 순간이동한다 (자리에 잔상을 남긴다)
##  gun   근접 판정 대신 스윙 동안 shots 발을 gap 프레임마다 쏜다 (탄창을 쓰지 않는다)
##  spin  회전 베기: 스윙 동안 몸이 잔상으로 깜빡이고, 타격마다 몸 둘레에 가로 초승달이 터진다
##  sub   잔상 보간 밀도 (한 스윙에 많이 도는 동작일수록 크게)
##  after 착지 뒤 지연 참격 {n, delay, gap, dmg, radius}

enum Ph { IDLE, LUNGE, WINDUP, SWING, FOLLOW, WHIFF, RETURN }

const F := 1.0 / 60.0
const LINK_TIME := 0.36         # 적중한 단이 끝난 뒤 다음 입력을 기다리는 시간
const WHIFF_LOCK := 0.46        # 헛치거나 막히면 이만큼 검을 다시 못 휘두른다
const WHIFF_POSE := 0.3         # 오버스윙 자세가 늘어지는 시간
const FINISH_REST := 0.24       # 마지막 단 뒤 숨 고르기
const BOSS_REST := 0.7          # 보스(no_slash_reset)에게 마지막 단을 넣은 뒤 숨 고르기
const STOP := 1.45              # 대상과 유지하는 거리
const LUNGE_SPEED := 62.0
const RANGE := 8.0
const BLINK_GAP := 1.35         # 순간이동해 서는 거리 (대상 표면에서)

const NEUTRAL := {
	"ax": 0.0, "ay": 0.0, "az": 0.0, "bl": Vector3(38, -18, 0), "bs": 1.0,
	"tx": 0.0, "ty": 0.0, "tz": 0.0, "uy": 0.0, "lift": 0.0, "pitch": 0.0,
	"hl": 0.0, "hr": 0.0, "kl": 0.0, "kr": 0.0, "al": 0.0,
}

## 단 정의. 시간은 프레임(60fps) 단위. 각 cut: wind(준비) · swing(1~20) · ready/impact 자세 ·
## back(준비 중 뒤로 m) · fwd(스윙 중 앞으로 m) · reach/cone/dmg · stop(히트스탑 초) · kb(넉백 배율) ·
## sq(찌그러짐 충격: 준비·스윙·임팩트) · ease(키별 스윙 이징 덮어쓰기) · pitch_s(스윙음 높이) + 위 확장 키
static var STEPS: Array = []

var p: Player
var trail: SaberTrail
var step := -1
var cut := 0
var ph := Ph.IDLE
var t := 0.0
var dur := 0.0
var hit_ok := false
var blocked := false
var buffered := false
var link_t := 0.0
var next_step := 0
var dir := Vector3.FORWARD
var vel := Vector3.ZERO
var target: Enemy
var cur: Dictionary = NEUTRAL.duplicate()
var from: Dictionary = NEUTRAL.duplicate()
var to: Dictionary = NEUTRAL.duplicate()
var ease_over: Dictionary = {}
var k_prev := 0.0
var move_d := 0.0
var move_prev := 0.0
var approach := 0.0
var lunged := false
var land_pending := false
var chain := 0                  # 연속 적중 단 수 (HUD·확인용)
var hits_done := 0              # 이번 스윙에서 이미 판정한 다단히트 수
var shots_done := 0             # 이번 사격 cut 에서 쏜 탄 수
var ghost_t := 0                # 스윙 잔상 간격 (물리 틱)


static func _pose(over: Dictionary) -> Dictionary:
	var d := NEUTRAL.duplicate()
	d.merge(over, true)
	return d


static func _build() -> void:
	if not STEPS.is_empty():
		return
	# 자주 쓰는 키 포즈
	var h_ready := _pose({"ay": -1.55, "ax": -0.45, "bl": Vector3(8, -72, 0), "ty": -0.95, "tz": 0.08, "pitch": 0.22,
		"hl": -0.55, "hr": 0.6, "kl": -0.25, "kr": -0.85, "al": 0.35})
	var h_hit := _pose({"ay": 2.0, "ax": -0.4, "bl": Vector3(8, -72, 0), "ty": 0.95, "tz": -0.06, "pitch": 0.1, "bs": 1.45,
		"hl": 0.5, "hr": -0.45, "kl": -0.5, "kr": -0.2, "al": -0.3})
	var b_hit := _pose({"ay": -1.7, "ax": -0.35, "bl": Vector3(8, -30, 0), "ty": -1.05, "tz": 0.08, "uy": -0.3, "pitch": 0.18, "bs": 1.5,
		"hl": -0.5, "hr": 0.55, "kl": -0.2, "kr": -0.6, "al": 0.4})
	var x1_ready := _pose({"ax": 2.4, "ay": 0.95, "bl": Vector3(-90, 0, 0), "ty": 0.7, "tx": 0.18, "pitch": -0.05,
		"hl": 0.3, "hr": -0.2, "kl": -0.4, "kr": -0.3})
	var x1_hit := _pose({"ax": 0.45, "ay": -1.25, "bl": Vector3(-90, 0, 0), "ty": -0.7, "tx": -0.25, "pitch": 0.25, "bs": 1.45,
		"hl": -0.3, "hr": 0.45, "kl": -0.3, "kr": -0.6})
	var x2_ready := _pose({"ax": 2.35, "ay": -1.05, "bl": Vector3(-90, 0, 0), "ty": -0.75, "tx": 0.15, "pitch": -0.05,
		"hl": -0.2, "hr": 0.3, "kl": -0.3, "kr": -0.4})
	var x2_hit := _pose({"ax": 0.4, "ay": 1.3, "bl": Vector3(-90, 0, 0), "ty": 0.75, "tx": -0.25, "pitch": 0.25, "bs": 1.45,
		"hl": 0.45, "hr": -0.3, "kl": -0.6, "kr": -0.3})
	var thrust_ready := _pose({"ax": 1.25, "ay": -0.45, "bl": Vector3(-90, 0, 0), "ty": -0.85, "tz": 0.1, "pitch": -0.12, "bs": 0.8,
		"hl": 0.5, "hr": 0.2, "kl": -0.9, "kr": -0.7, "al": 0.5})
	var thrust_hit := _pose({"ax": 1.62, "ay": 0.1, "bl": Vector3(-90, 0, 0), "ty": 0.55, "tz": -0.05, "pitch": 0.38, "bs": 1.95,
		"hl": -0.85, "hr": 0.7, "kl": -0.1, "kr": -0.5, "al": -0.6})
	# 난무: 사방에서 번갈아 긋는 X자. 순간이동 각도는 대상 둘레로 크게 엇갈린다.
	var flurry: Array = []
	var blinks := [150.0, -115.0, 165.0, -140.0, 120.0, -170.0]
	for i in blinks.size():
		var a := i % 2 == 0
		flurry.append({
			"wind": 1, "swing": 2, "back": 0.0, "fwd": 0.15, "blink": blinks[i],
			"ready": x1_ready if a else x2_ready, "impact": x1_hit if a else x2_hit,
			"reach": 2.8, "cone": 75.0, "dmg": 2, "stop": 0.018, "kb": 0.06, "sq": [-2.0, 4.0, -3.0], "pitch_s": 1.2 + i * 0.06,
		})
	flurry.append({   # 마무리 십자 베기: 정면으로 돌아와 칼을 길게 늘여 크게 긋는다
		"wind": 3, "swing": 2, "back": 0.0, "fwd": 0.5,
		"ready": _pose({"ax": 2.6, "ay": 0.2, "bl": Vector3(-90, 0, 0), "ty": 0.2, "tx": 0.25, "pitch": -0.2, "lift": 0.15,
			"hl": 0.6, "hr": -0.3, "kl": -0.9, "kr": -0.5, "al": 0.6}),
		"impact": _pose({"ax": 0.2, "ay": -0.1, "bl": Vector3(-90, 0, 0), "ty": -0.1, "tx": -0.35, "pitch": 0.45, "bs": 1.9,
			"hl": -0.7, "hr": 0.7, "kl": -0.2, "kr": -0.9, "al": -0.5}),
		"reach": 3.3, "cone": 70.0, "dmg": 5, "stop": 0.08, "kb": 0.8, "sq": [-6.0, 10.0, -7.0], "pitch_s": 0.85,
	})
	STEPS = [
		{   # 1타 섬광 삼연참: 6프레임 동안 가로 → 역 → 가로
			"name": "FLASH", "lunge": true, "approach": 1.2, "follow": 9, "cancel": 4,
			"cuts": [
				{
					"wind": 3, "swing": 2, "back": 0.0, "fwd": 0.3,
					"ready": h_ready, "impact": h_hit,
					"reach": 2.9, "cone": 80.0, "dmg": 3, "stop": 0.025, "kb": 0.2, "sq": [-5.0, 7.0, -4.0], "pitch_s": 1.0,
				},
				{
					"wind": 1, "swing": 1, "back": 0.0, "fwd": 0.15,
					"ready": h_hit, "impact": b_hit,
					"reach": 2.9, "cone": 80.0, "dmg": 3, "stop": 0.025, "kb": 0.2, "sq": [-2.0, 6.0, -4.0], "pitch_s": 1.15,
				},
				{
					"wind": 2, "swing": 2, "back": 0.0, "fwd": 0.45,
					"ready": _pose({"ay": -1.85, "ax": -0.5, "bl": Vector3(8, -72, 0), "ty": -1.15, "tz": 0.1, "pitch": 0.28, "uy": -0.25,
						"hl": -0.65, "hr": 0.7, "kl": -0.35, "kr": -1.0, "al": 0.4}),
					"impact": _pose({"ay": 2.25, "ax": -0.4, "bl": Vector3(8, -72, 0), "ty": 1.1, "tz": -0.08, "uy": 0.3, "pitch": 0.12, "bs": 1.7,
						"hl": 0.6, "hr": -0.5, "kl": -0.55, "kr": -0.2, "al": -0.35}),
					"reach": 3.0, "cone": 85.0, "dmg": 4, "stop": 0.06, "kb": 0.7, "sq": [-6.0, 9.0, -6.0], "pitch_s": 0.92, "sub": 20,
				},
			],
			"rest": _pose({"ay": 1.95, "ax": -0.3, "bl": Vector3(10, -60, 0), "ty": 0.85, "uy": 0.2, "pitch": 0.06, "hl": 0.35, "hr": -0.3, "kl": -0.4, "kr": -0.15}),
		},
		{   # 2타 반동 사격: 역베기 → 공중제비로 물러나며 4연사 → 되돌아와 찌르기
			"name": "RECOIL SHOT", "lunge": true, "approach": 1.4, "follow": 9, "cancel": 4,
			"cuts": [
				{
					"wind": 3, "swing": 2, "back": 0.0, "fwd": 0.6,
					"ready": _pose({"ay": 2.15, "ax": -0.3, "bl": Vector3(8, -30, 0), "ty": 1.05, "tz": -0.1, "uy": 0.25, "pitch": -0.2,
						"hl": 0.55, "hr": 0.35, "kl": -0.8, "kr": -0.9, "al": -0.5}),
					"impact": b_hit,
					"reach": 3.0, "cone": 85.0, "dmg": 5, "stop": 0.05, "kb": 0.35, "sq": [-6.0, 8.0, -5.0], "pitch_s": 1.12,
				},
				{   # 뒤로 공중제비 (6프레임에 한 바퀴) → 공중에서 조준해 3프레임마다 한 발
					"wind": 7, "swing": 12, "back": 2.8, "fwd": 0.0, "gun": true, "shots": 4, "gap": 3,
					"ready": _pose({"ax": 0.5, "ay": -1.1, "az": 0.4, "bl": Vector3(50, -10, 0), "ty": 0.0, "tx": -0.1, "lift": 0.75, "pitch": -TAU,
						"hl": 1.0, "hr": 0.8, "kl": -1.5, "kr": -1.3, "al": 0.0}),
					"impact": _pose({"ax": 0.4, "ay": -1.2, "az": 0.45, "bl": Vector3(50, -10, 0), "ty": 0.05, "tx": -0.18, "lift": 0.25, "pitch": -0.12,
						"hl": 0.35, "hr": -0.25, "kl": -0.7, "kr": -0.35, "al": 0.0}),
					"reach": 0.0, "cone": 0.0, "dmg": 0, "stop": 0.0, "kb": 0.0, "sq": [-8.0, 0.0, 0.0], "pitch_s": 1.0,
					"ease": {"lift": "inout", "pitch": "lin"},
				},
				{   # 2프레임에 되돌아와 꿰뚫는다
					"wind": 2, "swing": 2, "back": 0.0, "fwd": 3.0,
					"ready": thrust_ready, "impact": thrust_hit,
					"reach": 3.8, "cone": 34.0, "dmg": 6, "stop": 0.07, "kb": 0.9, "sq": [-6.0, 12.0, -5.0], "pitch_s": 0.88, "dashin": true,
				},
			],
			"rest": _pose({"ax": 1.45, "ay": 0.05, "bl": Vector3(-90, 0, 0), "ty": 0.4, "pitch": 0.2, "bs": 1.1, "hl": -0.5, "hr": 0.5, "kl": -0.15, "kr": -0.45}),
		},
		{   # 3타 순섬 난무
			"name": "PHANTOM FLURRY", "lunge": true, "approach": 1.0, "follow": 10, "cancel": 5,
			"cuts": flurry,
			"rest": _pose({"ax": 0.4, "ay": -0.2, "bl": Vector3(-90, 0, 0), "ty": -0.15, "tx": -0.25, "pitch": 0.32, "bs": 1.15,
				"hl": -0.55, "hr": 0.55, "kl": -0.2, "kr": -0.75, "al": -0.4}),
		},
		{   # 4타 선풍: 낮게 감았다가 5바퀴 (다리는 2바퀴) 돌며 7번 벤다
			"name": "CYCLONE", "lunge": true, "approach": 0.9, "follow": 10, "cancel": 5,
			"cuts": [{
				"wind": 4, "swing": 20, "back": 0.0, "fwd": 0.4, "hits": 7, "spin": true, "sub": 80,
				"ready": _pose({"ax": -0.15, "ay": 0.0, "az": 1.35, "bl": Vector3(-90, 0, 0), "uy": -1.1, "ty": -0.5, "tx": 0.25, "lift": -0.18, "pitch": 0.3,
					"hl": -0.8, "hr": 0.9, "kl": -1.1, "kr": -1.2, "al": 0.6}),
				"impact": _pose({"ax": -0.1, "ay": 0.0, "az": 1.45, "bl": Vector3(-90, 0, 0), "uy": TAU * 5.0, "ty": 0.3, "tx": -0.1, "lift": 0.35, "pitch": 0.0, "bs": 1.6,
					"hl": 0.3, "hr": -0.2, "kl": -0.5, "kr": -0.4, "al": -0.6}),
				"reach": 3.1, "cone": 180.0, "dmg": 2, "stop": 0.014, "kb": 0.04, "sq": [-9.0, 6.0, -8.0], "pitch_s": 1.35,
				"ease": {"uy": "lin", "lift": "inout", "ty": "lin"},
			}],
			"rest": _pose({"ax": -0.1, "az": 1.2, "bl": Vector3(-90, 0, 0), "uy": 0.35, "ty": 0.4, "lift": 0.0, "pitch": 0.15,
				"hl": 0.4, "hr": -0.3, "kl": -0.6, "kr": -0.3, "al": -0.5}),
		},
		{   # 5타 도약 올려베기: 두 번 올려 벤다
			"name": "RISE", "lunge": true, "approach": 1.2, "follow": 10, "cancel": 4,
			"cuts": [
				{
					"wind": 4, "swing": 2, "back": 0.0, "fwd": 0.5,
					"ready": _pose({"ax": -0.7, "ay": -1.0, "bl": Vector3(-90, 0, 0), "ty": -0.6, "tx": -0.15, "lift": -0.25, "pitch": 0.35,
						"hl": 0.85, "hr": 0.75, "kl": -1.5, "kr": -1.35, "al": 0.4}),
					"impact": _pose({"ax": 2.6, "ay": 0.75, "bl": Vector3(-90, 0, 0), "ty": 0.45, "tx": 0.3, "lift": 0.55, "pitch": -0.22, "bs": 1.5,
						"hl": -0.3, "hr": 0.9, "kl": -0.2, "kr": -1.4, "al": -0.5}),
					"reach": 3.0, "cone": 65.0, "dmg": 4, "stop": 0.035, "kb": 0.2, "sq": [-9.0, 13.0, -2.0], "pitch_s": 1.18,
					"ease": {"lift": "out"}, "arc": "rise",
				},
				{
					"wind": 2, "swing": 2, "back": 0.0, "fwd": 0.4,
					"ready": _pose({"ax": -0.4, "ay": 0.9, "bl": Vector3(-90, 0, 0), "ty": 0.6, "tx": -0.1, "lift": 0.7, "pitch": 0.2,
						"hl": 0.9, "hr": 0.6, "kl": -1.4, "kr": -1.2, "al": -0.4}),
					"impact": _pose({"ax": 2.95, "ay": -0.75, "bl": Vector3(-90, 0, 0), "ty": -0.45, "tx": 0.3, "lift": 1.1, "pitch": -0.3, "bs": 1.6,
						"hl": 0.3, "hr": 0.9, "kl": -0.4, "kr": -1.4, "al": 0.5}),
					"reach": 3.0, "cone": 65.0, "dmg": 5, "stop": 0.07, "kb": 0.25, "sq": [-4.0, 13.0, -2.0], "pitch_s": 1.3,
					"ease": {"lift": "out"}, "arc": "rise_r",
				},
			],
			# 여운 동안 계속 떠오르며 정점에서 멈칫한다 (6타의 발판)
			"rest": _pose({"ax": 2.8, "ay": -0.2, "bl": Vector3(-90, 0, 0), "ty": -0.25, "tx": 0.25, "lift": 1.6, "pitch": -0.32,
				"hl": 0.8, "hr": 1.0, "kl": -1.4, "kr": -1.6, "al": -0.6}),
		},
		{   # 6타 낙월 · 지연참: 정점에서 두 바퀴 돌며 내리꽂고, 한 박자 뒤 허공에 칼자국이 연달아 터진다
			"name": "CRESCENT", "lunge": true, "approach": 2.6, "follow": 22, "cancel": 99,
			"cuts": [{
				"wind": 5, "swing": 6, "back": 0.0, "fwd": 0.6, "sub": 40,
				"ready": _pose({"ax": 3.3, "ay": 0.0, "bl": Vector3(-90, 0, 0), "ty": 0.1, "tx": 0.35, "lift": 1.8, "pitch": -0.6,
					"hl": 1.0, "hr": 1.05, "kl": -1.6, "kr": -1.7, "al": -0.7}),
				"impact": _pose({"ax": 1.05, "ay": 0.0, "bl": Vector3(-90, 0, 0), "ty": 0.0, "tx": -0.35, "lift": -0.15, "pitch": TAU * 2.0 + 0.45, "bs": 1.7,
					"hl": 0.75, "hr": -0.2, "kl": -1.3, "kr": -0.5, "al": 0.5}),
				"reach": 3.5, "cone": 115.0, "dmg": 14, "stop": 0.13, "kb": 1.2, "sq": [-4.0, 8.0, -18.0], "pitch_s": 0.72,
				"ease": {"pitch": "inout", "lift": "in2"}, "slam": true,
				"after": {"n": 6, "delay": 0.16, "gap": 0.045, "dmg": 2, "radius": 3.8},
			}],
			"rest": _pose({"ax": 0.9, "ay": 0.0, "bl": Vector3(-90, 0, 0), "tx": -0.2, "lift": -0.05, "pitch": 0.3, "bs": 1.0,
				"hl": 0.6, "hr": -0.15, "kl": -1.1, "kr": -0.45}),
		},
	]


func _init(owner: Player) -> void:
	p = owner
	_build()


# ── 상태 질의 ───────────────────────────────────────────

## 이동·조준을 콤보가 잡고 있는가 (일반 이동 입력 무시)
func committed() -> bool:
	return ph == Ph.LUNGE or ph == Ph.WINDUP or ph == Ph.SWING or ph == Ph.FOLLOW or ph == Ph.WHIFF


func posing() -> bool:
	return ph != Ph.IDLE


func swinging() -> bool:
	return ph == Ph.LUNGE or ph == Ph.SWING or (ph == Ph.FOLLOW and t < 3.0 * F) or ph == Ph.WINDUP and cut > 0


func lift() -> float:
	return float(cur.lift) if ph != Ph.IDLE else 0.0


## 회전 베기 중: 몸이 눈에 보이지 않을 만큼 빠르다 (Player 가 몸을 잔상으로 깜빡인다)
func blur() -> bool:
	return ph == Ph.SWING and _cutd().get("spin", false)


## 사격 cut 중인가 (공중에서 총을 겨누는 동안)
func gunning() -> bool:
	return (ph == Ph.SWING or ph == Ph.WINDUP) and step >= 0 and _cutd().get("gun", false)


# ── 입력 ────────────────────────────────────────────────

## 검 버튼. 콤보가 처리하면 true.
func press() -> bool:
	if ph == Ph.WHIFF:
		return true                      # 헛친 뒤 경직 중: 무시
	if ph == Ph.LUNGE or ph == Ph.WINDUP or ph == Ph.SWING or ph == Ph.FOLLOW:
		buffered = true
		return true
	if link_t > 0.0:
		_start(next_step)
		return true
	if p.slash_cd > 0.0:
		return true
	_start(0)
	return true


## 대시·피격·패링 등으로 끊는다. hard 면 자세도 즉시 놓는다 (다른 모션이 바로 잇는다).
func cancel(hard := false) -> void:
	if ph == Ph.IDLE and link_t <= 0.0:
		return
	link_t = 0.0
	next_step = 0
	buffered = false
	chain = 0
	vel = Vector3.ZERO
	if hard or ph == Ph.IDLE:
		ph = Ph.IDLE
		cur = NEUTRAL.duplicate()
		(p.j.blade as Node3D).scale = Vector3.ONE
		return
	_enter_return(0.08)


## 회피 레이저 등으로 콤보를 잠깐 멈춘다: 자세는 풀되 링크를 열어 두어 다음 클릭이 다음 단으로 이어진다
func suspend() -> void:
	var nx := 0
	if step >= 0 and (ph != Ph.IDLE and ph != Ph.RETURN):
		nx = (step + 1) % STEPS.size()
	elif link_t > 0.0:
		nx = next_step
	var keep := chain
	cancel(false)
	link_t = LINK_TIME + 0.35
	next_step = nx
	chain = keep


# ── 진행 ────────────────────────────────────────────────

func _start(i: int) -> void:
	step = i
	cut = 0
	hit_ok = false
	blocked = false
	buffered = false
	link_t = 0.0
	lunged = false
	var s: Dictionary = STEPS[step]
	# 대상: 사거리 안 가장 가까운 적 (처치 후엔 다음 적에게로 이어 파고든다)
	target = _find_target() if step == 0 or not is_instance_valid(target) or not target.alive else target
	dir = p.aim_dir
	var gap := 0.0
	if target:
		var d := target.global_position - p.global_position
		d.y = 0
		if d.length() > 0.05:
			dir = d.normalized()
		gap = d.length() - STOP
	p.aim_dir = dir
	# 이 단의 동작 자체가 내딛는 거리(반동·찌르기 등)를 빼고 남은 만큼만 다가간다
	var net := 0.0
	for c in s.cuts:
		if c.has("blink"):
			break                         # 순간이동 뒤 동작은 대상 둘레에서 이루어진다
		net += float(c.fwd) - float(c.back)
	approach = clampf(gap - net, -1.2, float(s.approach)) if target else 0.0
	# 가까이 붙기에 너무 멀면 먼저 번개처럼 파고든다 (준비 동작을 겸한다)
	var far := gap - net - float(s.approach)
	if s.lunge and target and far > 0.25:
		_enter_lunge(far)
	else:
		_enter_windup()


func _enter_lunge(dist: float) -> void:
	ph = Ph.LUNGE
	t = 0.0
	dur = maxf(dist / LUNGE_SPEED, 2.0 * F)
	vel = dir * (dist / dur)
	lunged = true
	from = _wrapped(cur)
	to = (STEPS[step].cuts[0] as Dictionary).ready
	p.invuln = maxf(p.invuln, dur + 0.05)
	p.tilt_v += dir * 8.0
	FX.shockwave(p.global_position, Pal.BLADE, 1.8, 0.22, 0.05)
	Sfx.play("dash", 0.08, -5.0)
	Main.inst.camera.fov_punch(3.0)


func _cutd() -> Dictionary:
	return (STEPS[step].cuts as Array)[cut]


## 회전 키를 -PI~PI 로 감아 둔다 (한 바퀴 돈 뒤 다음 구간이 거꾸로 풀리지 않게)
func _wrapped(d: Dictionary) -> Dictionary:
	var o := d.duplicate()
	o.pitch = wrapf(float(o.pitch), -PI, PI)
	o.uy = wrapf(float(o.uy), -PI, PI)
	return o


func _enter_windup() -> void:
	var c := _cutd()
	ph = Ph.WINDUP
	t = 0.0
	# 파고들며 이미 자세를 잡았으면 준비는 짧게
	dur = float(c.wind) * F * (0.5 if lunged and cut == 0 else 1.0)
	cur = _wrapped(cur)
	from = cur.duplicate()
	to = c.ready
	ease_over = {}
	k_prev = 0.0
	move_d = -float(c.back) + approach * 0.3 * (1.0 if cut == 0 else 0.0)
	move_prev = 0.0
	p.squash_v += float(c.sq[0])
	p.tilt_v += -dir * 2.5
	if c.has("blink"):
		_blink(float(c.blink))
	elif cut > 0 and is_instance_valid(target) and target.alive:
		# 연타 사이에도 대상을 살짝 따라간다
		var d := target.global_position - p.global_position
		d.y = 0
		if d.length() > 0.3:
			dir = dir.slerp(d.normalized(), 0.6).normalized()
			p.aim_dir = dir
	if c.get("gun", false):
		# 뒤로 공중제비: 발밑 충격파와 함께 튀어 오른다
		FX.shockwave(p.global_position, Color("8a7ae0"), 1.8, 0.2, 0.05)
		GustFX.dash_burst(p.global_position, -dir, Color("8ad8ff"))
		Sfx.play("dash", 0.05, -4.0)
		shots_done = 0


## 대상 둘레로 deg 만큼 돌아간 자리에 순간이동한다. 원래 자리에 잔상, 새 자리에 섬광이 남는다.
func _blink(deg: float) -> void:
	if not is_instance_valid(target) or not target.alive:
		return
	var main := Main.inst
	var c := target.global_position
	var off := p.global_position - c
	off.y = 0
	if off.length() < 0.05:
		off = -dir
	var r := target.radius + BLINK_GAP
	var spot := c + off.normalized().rotated(Vector3.UP, deg_to_rad(deg)) * r
	spot.y = p.global_position.y
	# 벽 안이면 반대쪽, 그래도 막히면 그 자리에서 벤다
	if main.is_blocked(spot + Vector3(0, 0.5, 0)):
		spot = c + off.normalized().rotated(Vector3.UP, deg_to_rad(-deg)) * r
		spot.y = p.global_position.y
		if main.is_blocked(spot + Vector3(0, 0.5, 0)):
			return
	FX.afterimage(p.visual, Color(1.0, 0.55, 0.85, 0.42), 0.14)
	var from_pos := p.global_position
	p.global_position = spot
	var d := c - spot
	d.y = 0
	dir = d.normalized()
	p.aim_dir = dir
	FX.flash(spot + Vector3(0, 0.9, 0), Color(1.0, 0.8, 0.95), 0.5, 0.03)
	_streak(from_pos, spot)
	var snd := Sfx.play("dash", 0.05, -11.0)
	if snd:
		snd.pitch_scale = randf_range(1.3, 1.6)


static var _line: BoxMesh   # 빛줄기가 함께 쓰는 단위 상자


## 순간이동 경로에 1~2프레임 남는 가는 빛줄기
func _streak(a: Vector3, b: Vector3) -> void:
	var d := b - a
	d.y = 0
	var l := d.length()
	if l < 0.5:
		return
	var mid := (a + b) * 0.5 + Vector3(0, 0.95, 0)
	var basis := Basis.looking_at(d / l, Vector3.UP)
	if _line == null:
		_line = BoxMesh.new()
		_line.size = Vector3.ONE
	var line := _line
	for L in [[Color(1.0, 0.5, 0.9), 2.0, 0.09], [Color.WHITE, 3.0, 0.03]]:
		var mi := Pal.flat_mesh(line, L[0], L[1])
		FX.root.add_child(mi)
		mi.global_position = mid
		var w: float = L[2]
		mi.basis = basis * Basis.from_scale(Vector3(w, w, l))
		var tw := mi.create_tween()
		tw.tween_method(func(v: float): mi.basis = basis * Basis.from_scale(Vector3(maxf(w * v, 0.001), maxf(w * v, 0.001), l)), 1.0, 0.0, 0.07)
		tw.tween_callback(mi.queue_free)


func _enter_swing() -> void:
	var c := _cutd()
	ph = Ph.SWING
	t = 0.0
	dur = float(c.swing) * F
	cur = _wrapped(cur)
	from = cur.duplicate()
	to = c.impact
	ease_over = c.get("ease", {})
	k_prev = 0.0
	hits_done = 0
	ghost_t = 0
	move_d = float(c.fwd) + (approach * 0.7 if cut == 0 else 0.0)
	move_prev = 0.0
	p.squash_v += float(c.sq[1])
	p.tilt_v += dir * 6.0
	if c.get("gun", false):
		trail.boost = 0.0
		return
	var snd := Sfx.play("slash", 0.04, -1.0 if cut == 0 else -3.0)
	if snd:
		snd.pitch_scale = float(c.pitch_s) * randf_range(0.96, 1.04)
	if c.get("slam", false):
		p.invuln = maxf(p.invuln, dur + 0.15)
		Sfx.play("dash", 0.05, -3.0)
	if c.get("spin", false):
		p.invuln = maxf(p.invuln, dur + 0.05)
		Sfx.play("roll", 0.05, -2.0)
		FX.shockwave(p.global_position, Color(1.0, 0.45, 0.8), 3.2, 0.3, 0.06)
	if c.get("dashin", false):
		p.invuln = maxf(p.invuln, dur + 0.05)
		FX.afterimage(p.visual, Color(1.0, 0.6, 0.9, 0.45), 0.16)
		Sfx.play("dash", 0.03, -4.0)
		Main.inst.camera.fov_punch(4.0)
	var yaw := atan2(-dir.x, -dir.z)
	var up := Basis(Vector3.UP, yaw)
	match c.get("arc", "slam" if c.get("slam", false) else ""):
		"rise":
			# 아래 → 위 대각 호: 앞쪽으로 55° 세워 기울인다
			FX.crescent(p.global_position + Vector3(0, 1.1, 0) + dir * 0.3, up * Basis(Vector3.FORWARD, deg_to_rad(-60)) * Basis(Vector3.RIGHT, deg_to_rad(35)) * Basis.from_scale(Vector3(-0.85, 1, 0.85)), dur, 0.1)
		"rise_r":
			FX.crescent(p.global_position + Vector3(0, 1.5, 0) + dir * 0.3, up * Basis(Vector3.FORWARD, deg_to_rad(60)) * Basis(Vector3.RIGHT, deg_to_rad(35)) * Basis.from_scale(Vector3(0.9, 1, 0.9)), dur, 0.1)
		"slam":
			# 공중 회전 내려찍기: 몸 둘레를 크게 도는 세로 호 + 착지 순간 앞바닥을 가르는 호
			FX.crescent(p.global_position + Vector3(0, 1.5, 0), up * Basis(Vector3.FORWARD, deg_to_rad(90)) * Basis(Vector3.UP, deg_to_rad(-25)) * Basis.from_scale(Vector3(1.1, 1, 1.1)), dur * 0.5, 0.08)
			FX.crescent(p.global_position + Vector3(0, 1.2, 0), up * Basis(Vector3.FORWARD, deg_to_rad(90)) * Basis(Vector3.UP, deg_to_rad(-10)) * Basis.from_scale(Vector3(1.3, 1, 1.3)), dur, 0.12)
	# 회전 베기는 칼이 몸 둘레를 수십 번 긋는다: 잔상이 화면을 하얗게 덮지 않게 약하게
	trail.boost = 0.3 if c.get("spin", false) else 1.0


func _enter_follow() -> void:
	var s: Dictionary = STEPS[step]
	ph = Ph.FOLLOW
	t = 0.0
	dur = float(s.follow) * F
	from = cur.duplicate()
	to = s.rest
	ease_over = {}
	trail.boost = 0.0


func _enter_whiff() -> void:
	ph = Ph.WHIFF
	t = 0.0
	dur = WHIFF_POSE
	from = cur.duplicate()
	# 오버스윙: 휘두른 쪽으로 몸이 더 돌아가고 앞으로 쏠리며, 떠 있었으면 떨어진다
	var imp: Dictionary = _wrapped(_cutd().impact)
	to = imp.duplicate()
	var side := signf(float(imp.ty)) if absf(float(imp.ty)) > 0.1 else 1.0
	if blocked:
		# 튕김: 칼이 위로 튀고 몸이 뒤로 젖혀진다
		to.ax = 2.3
		to.ay = -float(imp.ay) * 0.4
		to.ty = -float(imp.ty) * 0.5
		to.pitch = -0.35
		to.bs = 0.9
		vel = -dir * 6.5
		p.tilt_v += -dir * 12.0
	else:
		to.uy = float(imp.uy) + side * 0.55
		to.ty = float(imp.ty) * 1.25
		to.pitch = 0.42
		to.bs = 1.0
		to.hl = -0.6
		to.hr = 0.7
		to.kl = -0.2
		to.kr = -0.9
		vel = dir * 3.5
		p.tilt_v += dir * 7.0
	to.lift = 0.0
	ease_over = {"lift": "in2"}
	trail.boost = 0.0
	p.slash_cd = WHIFF_LOCK
	land_pending = float(cur.lift) > 0.3
	link_t = 0.0
	next_step = 0
	buffered = false
	chain = 0


func _enter_return(d := -1.0) -> void:
	ph = Ph.RETURN
	t = 0.0
	var lf := float(cur.lift)
	dur = d if d > 0.0 else 0.12 + maxf(lf, 0.0) * 0.14
	land_pending = land_pending or lf > 0.3
	cur = _wrapped(cur)
	from = cur.duplicate()
	to = NEUTRAL.duplicate()
	ease_over = {"lift": "in2"}
	vel = Vector3.ZERO


func update(dt: float) -> void:
	if link_t > 0.0 and (ph == Ph.IDLE or ph == Ph.RETURN):
		link_t -= dt
		if link_t <= 0.0:
			next_step = 0
			chain = 0
	t += dt
	match ph:
		Ph.LUNGE:
			if t >= dur:
				_finish_phase()
				vel = dir * 2.0
				_enter_windup()
		Ph.WINDUP:
			var k := clampf(t / dur, 0.0, 1.0)
			_move(1.0 - pow(1.0 - k, 3.0), dt)
			if t >= dur:
				_finish_phase()
				_enter_swing()
		Ph.SWING:
			var c := _cutd()
			var k := clampf(t / dur, 0.0, 1.0)
			_move(_ease(k, "expo") if not c.get("spin", false) else k, dt)
			_swing_tick(c, k)
			if t >= dur:
				_finish_phase()
				_impact()
		Ph.FOLLOW:
			vel = vel.move_toward(Vector3.ZERO, 60.0 * dt)
			var last := step >= STEPS.size() - 1
			if not last and buffered and t >= float(STEPS[step].cancel) * F:
				_start(step + 1)
				return
			if t >= dur:
				if last:
					var boss: bool = is_instance_valid(target) and target.get("no_slash_reset") == true
					p.slash_cd = BOSS_REST if boss else FINISH_REST
					next_step = 0
					chain = 0
				else:
					link_t = LINK_TIME
					next_step = step + 1
				_enter_return()
		Ph.WHIFF:
			vel = vel.move_toward(Vector3.ZERO, 22.0 * dt)
			if t >= dur:
				_enter_return(0.16)
		Ph.RETURN:
			if t >= dur:
				ph = Ph.IDLE
				cur = NEUTRAL.duplicate()
				_land()
				# 기다리는 동안 링크가 열려 있으면 다음 입력을 받는다


## 스윙 도중 일어나는 일: 다단히트 판정 · 사격 · 회전 잔상
func _swing_tick(c: Dictionary, k: float) -> void:
	if c.get("gun", false):
		var gap := float(c.gap) * F
		while shots_done < int(c.shots) and t >= shots_done * gap:
			shots_done += 1
			var d := dir
			if is_instance_valid(target) and target.alive:
				d = target.global_position - p.global_position
				d.y = 0
				d = d.normalized() if d.length() > 0.2 else dir
				dir = d
				p.aim_dir = d
			p.combo_shot(d, shots_done == int(c.shots))
		return
	var n := int(c.get("hits", 1))
	while hits_done < n - 1 and k >= float(hits_done + 1) / n:
		hits_done += 1
		_strike(c, true)
	if c.get("spin", false) or c.get("dashin", false):
		ghost_t -= 1
		if ghost_t <= 0:
			ghost_t = 2
			FX.afterimage(p.visual, Color(1.0, 0.55, 0.9, 0.3), 0.09)


func _move(frac: float, dt: float) -> void:
	if dt <= 0.0:
		return
	vel = dir * (move_d * (frac - move_prev) / dt)
	move_prev = frac
	# 대상 몸 속으로 파고들지 않는다
	if is_instance_valid(target) and target.alive and vel.dot(dir) > 0.0:
		var d := target.global_position - p.global_position
		d.y = 0
		if d.length() < target.radius + 0.8 and d.dot(dir) > 0.0:
			vel -= dir * vel.dot(dir)


## 한 번의 판정. mini 는 다단히트 중간 타격 (짧은 정지·작은 흔들림)
func _strike(c: Dictionary, mini: bool) -> Dictionary:
	var main := Main.inst
	var r: Dictionary = p.combo_strike(dir, float(c.reach), float(c.cone), int(c.dmg), float(c.kb), c.get("slam", false))
	if int(r.hit) > 0:
		hit_ok = true
		var stp := float(c.stop)
		main.hitstop(stp)
		main.shake((0.18 if mini else 0.3) + stp * 3.0)
		if not mini:
			main.camera.fov_punch(-3.0 - stp * 30.0)
		main.kick(dir * (0.15 if mini else 0.45))
	elif int(r.blocked) > 0:
		blocked = true
		main.shake(0.25)
	elif not mini:
		main.shake(0.12)
	if c.get("spin", false):
		# 몸 둘레를 가르는 가로 초승달 (매 타격 다른 각도)
		var yaw := atan2(-dir.x, -dir.z) + float(cur.uy) + randf_range(-0.4, 0.4)
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, randf_range(-0.25, 0.25)) * Basis.from_scale(Vector3(1.25, 1, 1.25))
		FX.crescent(p.global_position + Vector3(0, 0.9 + float(cur.lift), 0), b, 0.025, 0.07)
		if int(r.hit) > 0:
			var snd := Sfx.play("slash", 0.02, -6.0)
			if snd:
				snd.pitch_scale = randf_range(1.3, 1.6)
	elif mini and int(r.hit) > 0:
		var snd2 := Sfx.play("slash", 0.02, -5.0)
		if snd2:
			snd2.pitch_scale = randf_range(1.2, 1.45)
	return r


## 스윙 끝: 판정
func _impact() -> void:
	var c := _cutd()
	var main := Main.inst
	var r := {"hit": 0, "blocked": 0}
	if not c.get("gun", false):
		r = _strike(c, false)
	if main.capture_mode:
		print("COMBO step=%d cut=%d %s hit=%d blocked=%d t=%.3f f=%d" % [step + 1, cut, STEPS[step].name, int(r.hit), int(r.blocked), main.time, main.capture_frame])
	p.squash_v += float(c.sq[2])
	cur = _wrapped(cur)
	if c.get("slam", false):
		_slam_fx(int(r.hit) > 0)
		if c.has("after"):
			_after_cuts(c.after)
	elif int(r.hit) > 0:
		var tip: Vector3 = (p.j.blade as Node3D).to_global(Vector3(0, 0, -1.3))
		FX.flash(tip, Color(1.0, 0.8, 0.92), 0.4, 0.035)
		Distortion.burst(tip, 1.3, 0.22, 0.8)
	var cuts: Array = STEPS[step].cuts
	if cut < cuts.size() - 1:
		cut += 1
		_enter_windup()
		return
	if hit_ok:
		chain += 1
		_enter_follow()
		if step == STEPS.size() - 1:
			main.hud.popup("CRESCENT", Color(1.0, 0.6, 0.85), p.global_position + Vector3(0, 2.4, 0))
	else:
		if blocked:
			FX.sparks((p.j.blade as Node3D).to_global(Vector3(0, 0, -1.0)), 10, [Color.WHITE, Color("ffd080")], 6.0, 0.25, -8.0, 0.05)
			Sfx.play("clank", 0.05, -4.0)
		_enter_whiff()


## 지연 참격 (미야비식): 착지 뒤 한 박자 쉬고, 주변 허공에 칼자국이 연달아 그어지며 범위 안 적이 여러 번 베인다
func _after_cuts(a: Dictionary) -> void:
	var tree := p.get_tree()
	var center := p.global_position + dir * 1.2
	if is_instance_valid(target) and target.alive:
		center = target.global_position
	var base_yaw := atan2(-dir.x, -dir.z)
	var n := int(a.n)
	for i in n:
		var delay := float(a.delay) + float(a.gap) * i
		tree.create_timer(delay, false).timeout.connect(_after_cut.bind(center, base_yaw + i * 2.17, i, n, a))


func _after_cut(center: Vector3, yaw: float, i: int, n: int, a: Dictionary) -> void:
	if not is_instance_valid(p) or not p.alive:
		return
	var main := Main.inst
	var pos := center + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
	pos.y = Main.gy(pos) + randf_range(0.7, 1.4)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, randf_range(-1.2, 1.2)) * Basis.from_scale(Vector3.ONE * randf_range(1.1, 1.6))
	FX.crescent(pos, b, 0.02, 0.09)
	FX.flash(pos, Color(1.0, 0.85, 0.95), 0.7, 0.03)
	var hit := false
	var r := float(a.radius)
	for e in p.get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var d := en.global_position - center
		d.y = 0
		if d.length() < r + en.radius:
			if en.has_method("is_armored") and en.is_armored():
				continue
			en.slash_yaw = yaw
			var k0 := en.knock
			en.take_hit(int(a.dmg), Vector3(cos(yaw), 0, sin(yaw)), en.global_position, "slash")
			en.knock = k0 + (en.knock - k0) * 0.05
			hit = true
	var snd := Sfx.play("slash", 0.02, -3.0 if i == n - 1 else -6.0)
	if snd:
		snd.pitch_scale = 1.1 + i * 0.08
	if hit:
		main.hitstop(0.05 if i == n - 1 else 0.016)
		main.shake(0.2 if i < n - 1 else 0.45)
	if i == n - 1:
		Distortion.burst(pos, 3.0, 0.3, 1.2)
		FX.shockwave(Vector3(center.x, Main.gy(center) + 0.05, center.z), Color(1.0, 0.5, 0.8), 3.6, 0.25, 0.06)
		main.hud.screen_flash(Color(1.0, 0.75, 0.9), 0.18)


func _slam_fx(hit: bool) -> void:
	var g := Vector3(p.global_position.x, Main.gy(p.global_position) + 0.05, p.global_position.z) + dir * 1.4
	FX.crescent(Vector3(p.global_position.x, Main.gy(p.global_position) + 0.25, p.global_position.z), Basis(Vector3.UP, atan2(-dir.x, -dir.z)) * Basis.from_scale(Vector3(1.35, 1, 1.35)), 0.03, 0.14)
	FX.shockwave(g, Color(1.0, 0.4, 0.75), 4.2, 0.3, 0.1)
	FX.shockwave(g, Color(0.55, 0.3, 1.0), 2.8, 0.22, 0.06)
	FX.sparks(g + Vector3(0, 0.15, 0), 26, [Color.WHITE, Color(1.0, 0.45, 0.75), Color(0.6, 0.35, 1.0)], 9.0, 0.35, -14.0, 0.08)
	FX.land_dust(g)
	FX.flash(g + Vector3(0, 0.4, 0), Color(1.0, 0.7, 0.9), 1.6, 0.06)
	Distortion.burst(g + Vector3(0, 0.4, 0), 4.6, 0.38, 1.4 if hit else 1.0)
	Sfx.play("land", 0.05, 2.0)
	Sfx.play("boom", 0.1, -8.0 if hit else -12.0)
	Main.inst.shake(0.5)


func _land() -> void:
	if not land_pending:
		return
	land_pending = false
	p.squash_v -= 9.0
	FX.shockwave(p.global_position, Color("8a7ae0"), 1.6, 0.22, 0.05)
	Sfx.play("land", 0.1, -8.0)


func _find_target() -> Enemy:
	var best: Enemy = null
	var bd := RANGE
	for e in p.get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if not en.alive or not en.landed:
			continue
		var d := en.global_position - p.global_position
		d.y = 0
		var l := d.length()
		# 1타: 조준 방향 70° 안, 또는 아주 가까운 적. 이어지는 단: 사방에서 찾되 정면일수록 우선
		# (벤 적이 쓰러지면 다음 적에게 몸을 돌려 파고든다). 방금 벤 대상은 계속 우선.
		var ang := p.aim_dir.angle_to(d / maxf(l, 0.001))
		var score := l - (0.6 if en == target else 0.0) + (ang * 0.8 if step > 0 else 0.0)
		if score < bd and (l < 2.2 or step > 0 or ang < deg_to_rad(70)):
			bd = score
			best = en
	return best


# ── 자세 ────────────────────────────────────────────────

func _ease(k: float, kind: String) -> float:
	match kind:
		"expo":
			return 1.0 if k >= 1.0 else (1.0 - pow(2.0, -10.0 * k)) / (1.0 - pow(2.0, -10.0))
		"out":
			return 1.0 - pow(1.0 - k, 3.0)
		"in":
			return k * k
		"in2":
			return k * k * k
		"inout":
			return k * k * (3.0 - 2.0 * k)
		"back":
			var s := 1.9
			var q := k - 1.0
			return 1.0 + q * q * ((s + 1.0) * q + s)
		"lin":
			return k
	return k


func _phase_k(k: float) -> Dictionary:
	# 구간별 기본 이징: 준비는 빠르게 감기고 멈칫(ease-out), 스윙은 폭발(expo), 여운은 넘쳤다 돌아옴(back)
	var base := "lin"
	match ph:
		Ph.WINDUP:
			base = "out"
		Ph.SWING:
			base = "expo"
		Ph.FOLLOW:
			base = "back"
		Ph.WHIFF:
			base = "out"
		Ph.RETURN:
			base = "out"
		Ph.LUNGE:
			base = "out"
	# 틱마다 최대 13번 불리므로 결과 사전을 새로 만들지 않고 다시 쓴다 (바로 _blend 가 읽는다)
	var out := _ks
	var kb := _ease(k, base)
	for key in NEUTRAL:
		out[key] = _ease(k, ease_over[key]) if ease_over.has(key) else kb
	return out


var _ks := {}


func _blend(ks: Dictionary) -> void:
	for key in NEUTRAL:
		var k: float = ks[key]
		if key == "bl":
			cur[key] = (from[key] as Vector3).lerp(to[key], k)
		else:
			cur[key] = lerpf(float(from[key]), float(to[key]), k)


## Player._animate 끝에서 부른다: 현재 구간 진행도에 맞춰 자세를 만들고 관절에 적용한다.
## 스윙 중에는 지난 틱과 이번 틱 사이 자세를 여러 번 적용해 잔상에 칼 위치를 넘긴다.
func pose(dt: float) -> void:
	if ph == Ph.IDLE:
		trail.feed(dt, [])
		return
	var k := clampf(t / maxf(dur, 0.0001), 0.0, 1.0)
	if ph == Ph.SWING or ph == Ph.LUNGE or (ph == Ph.WINDUP and _cutd().get("gun", false)):
		_substeps(k_prev, k)
	k_prev = k
	_blend(_phase_k(k))
	_apply()
	var samples := pending
	pending = []
	trail.feed(dt, samples)


var pending: Array = []


## 지난 틱 진행도 kp → k 사이 자세를 잘게 적용해 칼 위치를 잔상용으로 모은다
func _substeps(kp: float, k: float) -> void:
	var dens := float(_cutd().get("sub", 14)) if step >= 0 and ph != Ph.LUNGE else 14.0
	var n := clampi(int(ceil(absf(k - kp) * dens)), 1, 12)
	for i in range(1, n):
		var ki := lerpf(kp, k, float(i) / n)
		_blend(_phase_k(ki))
		_apply()
		pending.append(trail.sample_now())


## 구간이 이번 틱에 끝났다: 마지막 자세(k=1)까지 채워 적용한다 (임팩트 자세를 건너뛰지 않게)
func _finish_phase() -> void:
	if ph == Ph.SWING or ph == Ph.LUNGE:
		_substeps(k_prev, 1.0)
	_blend(_phase_k(1.0))
	_apply()
	if ph == Ph.SWING or ph == Ph.LUNGE:
		pending.append(trail.sample_now())
	k_prev = 0.0


func _apply() -> void:
	var j := p.j
	var yaw := atan2(-dir.x, -dir.z)
	var uy := float(cur.uy)
	(j.upper as Node3D).rotation.y = yaw + uy
	(j.legs as Node3D).rotation.y = yaw + uy * 0.4
	var arm: Node3D = j.arm_r
	arm.rotation = Vector3(float(cur.ax), float(cur.ay), float(cur.az))
	var blade: Node3D = j.blade
	blade.rotation_degrees = cur.bl
	# 스윙 순간 칼이 길게 늘어나는 만화적 스미어 (굵기는 살짝 얇아진다)
	var bs := float(cur.bs)
	blade.scale = Vector3(1.0 / sqrt(bs), 1.0 / sqrt(bs), bs)
	var torso: Node3D = j.torso
	torso.rotation = Vector3(float(cur.tx), float(cur.ty), float(cur.tz))
	(j.hip_l as Node3D).rotation.x = float(cur.hl)
	(j.hip_r as Node3D).rotation.x = float(cur.hr)
	(j.knee_l as Node3D).rotation.x = float(cur.kl)
	(j.knee_r as Node3D).rotation.x = float(cur.kr)
	var arm_l: Node3D = j.arm_l
	arm_l.rotation.y = float(cur.al)
	arm_l.rotation.z = -0.2 - maxf(float(cur.lift), 0.0) * 0.35
	p.visual.position.y = Player.PIVOT_Y + p.hover + float(cur.lift)
	var pitch := float(cur.pitch)
	if absf(pitch) > 0.0001:
		var right := dir.cross(Vector3.UP).normalized()
		p.visual.basis = Basis(right, -pitch)
	else:
		p.visual.basis = Basis.IDENTITY
