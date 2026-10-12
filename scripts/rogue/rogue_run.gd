class_name RogueRun
extends RefCounted
## 로그라이크 런 상태. 층을 내려갈 때 씬을 다시 불러오므로 모두 정적 변수로 들고 간다.
## 체력 단위는 반 칸: red = 빨간 반 칸 (Player.hp 와 같게 맞춘다), red_max = 빨간 그릇(반 칸, 짝수).

const FLOORS := 6
const FLOOR_NAMES := ["녹슨 지하층", "배수 터널", "주조 구역", "심층 갱도", "코어 외곽", "헥스 코어"]
const RED_CAP := 24          # 그릇 최대 12칸

static var started := false
static var depth := 1
static var run_seed := 0
static var items: Array = []          # 보유 패시브 id (주운 순서)
static var active_item := ""
static var charge := 0
static var trinket := ""
static var pocket := {}               # {"kind": "pill", "id": 색 번호, "horse": bool} · {"kind": "card", "id": 카드 id}
static var coins := 0
static var bombs := 1
static var keys := 1
static var red_max := 6
static var red := 6
static var soul := 0
static var black := 0
static var pill_map: Array = []       # 색 번호 → 알약 효과 id
static var pills_known := {}          # 색 번호 → true (먹어 봐서 정체를 앎)
static var stat_bonus := {}           # 알약 등으로 영구히 바뀐 스탯
static var seen := {}                 # 이번 런에 이미 나온 아이템 (다시 안 나온다)
static var kills := 0
static var time := 0.0
static var rooms := 0
static var deals_taken := 0
static var won := false


static func new_run(seed_value := -1) -> void:
	started = true
	depth = 1
	run_seed = seed_value if seed_value >= 0 else randi()
	items = []
	active_item = ""
	charge = 0
	trinket = ""
	pocket = {}
	coins = 0
	bombs = 1
	keys = 1
	red_max = 6
	red = 6
	soul = 0
	black = 0
	stat_bonus = {}
	seen = {}
	pills_known = {}
	kills = 0
	time = 0.0
	rooms = 0
	deals_taken = 0
	won = false
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	pill_map = []
	var effects: Array = []
	for p in RogueItems.PILLS:
		effects.append(p[0])
	for i in range(effects.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = effects[i]
		effects[i] = effects[j]
		effects[j] = tmp
	for i in RogueItems.PILL_COLORS.size():
		pill_map.append(effects[i])


static func floor_name() -> String:
	return FLOOR_NAMES[clampi(depth - 1, 0, FLOOR_NAMES.size() - 1)]


static func add_stat(key: String, v: float) -> void:
	stat_bonus[key] = float(stat_bonus.get(key, 0.0)) + v


static func hearts_total() -> int:
	return red + soul + black
