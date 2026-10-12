class_name RogueItems
extends RefCounted
## 로그라이크 모드(HEX DEPTHS) 데이터: 패시브 · 액티브 · 장신구 · 알약 · 카드/룬 · 결합 공격 · 변신.
## 기획: docs/roguelike-isaac-mode.md. 이 파일이 아이템 목록의 원본이다.
##
## 패시브 행: id → {name, desc, type, q(품질 0~4), pools, tags, stats, flags}
##  stats (더하기): dmg 공격 · dmg_x 공격 배율(더해서 1+합) · tears 초당 발사 · tears_x · range 사거리(m) · shot_speed 탄속(m/s)
##                  speed 이동 배율 · luck 행운 · hearts 빨간 그릇(칸) · heal 회복(반 칸) · soul · black (반 칸) · slash_x 검 피해 배율 · size 탄 크기
##  flags (개수·확률): 공격 축 · 패밀리어 · 규칙 변경. 의미는 RogueBuild 가 해석한다.

enum T { PASSIVE, ACTIVE, TRINKET }

const TAGS := ["gun", "blade", "tech", "angel", "demon", "fly", "poison", "mushroom", "bomb"]
const TAG_NAMES := {"gun": "탄막", "blade": "검", "tech": "기계", "angel": "천사", "demon": "악마", "fly": "벌떼", "poison": "독", "mushroom": "버섯", "bomb": "폭탄"}
const TAG_COLORS := {
	"gun": Color("ffb040"), "blade": Color("ff6ab0"), "tech": Color("40e8ff"), "angel": Color("fff4c0"),
	"demon": Color("ff3a40"), "fly": Color("a0a060"), "poison": Color("70ff60"), "mushroom": Color("e0a070"), "bomb": Color("b0b0c0"),
}

const POOLS := ["treasure", "shop", "boss", "devil", "angel", "secret", "library"]

static var _db := {}
static var _built := false


static func db() -> Dictionary:
	if not _built:
		_built = true
		_build()
	return _db


static func get_item(id: String) -> Dictionary:
	return db().get(id, {})


static func color_of(id: String) -> Color:
	var it := get_item(id)
	if it.is_empty():
		return Color.WHITE
	for t in it.tags:
		return TAG_COLORS[t]
	match it.type:
		T.ACTIVE: return Color("8ad8ff")
		T.TRINKET: return Color("d0c0ff")
	return Color("ffd870")


## 풀에서 아직 안 나온 아이템 하나 (없으면 "")
static func roll(pool: String, rng: RandomNumberGenerator, seen: Dictionary, type := -1) -> String:
	var cands: Array = []
	var weights: Array = []
	var total := 0.0
	for id in db():
		var it: Dictionary = _db[id]
		if seen.has(id) or not (pool in it.pools):
			continue
		if type >= 0 and it.type != type:
			continue
		if type < 0 and it.type == T.TRINKET:
			continue
		var w: float = [1.0, 1.0, 0.8, 0.55, 0.3][clampi(it.q, 0, 4)]
		cands.append(id)
		weights.append(w)
		total += w
	if cands.is_empty():
		return ""
	var r := rng.randf() * total
	for i in cands.size():
		r -= weights[i]
		if r <= 0.0:
			return cands[i]
	return cands[-1]


static func trinket_ids() -> Array:
	var out: Array = []
	for id in db():
		if _db[id].type == T.TRINKET:
			out.append(id)
	return out


# ── 행 만들기 ───────────────────────────────────────────

static func _p(id: String, name: String, desc: String, q: int, pools: Array, tags: Array, stats := {}, flags := {}) -> void:
	_db[id] = {"id": id, "name": name, "desc": desc, "type": T.PASSIVE, "q": q, "pools": pools, "tags": tags, "stats": stats, "flags": flags}


static func _a(id: String, name: String, desc: String, charge: int, q: int, pools: Array, tags := []) -> void:
	_db[id] = {"id": id, "name": name, "desc": desc, "type": T.ACTIVE, "q": q, "pools": pools, "tags": tags, "stats": {}, "flags": {}, "charge": charge}


static func _t(id: String, name: String, desc: String, stats := {}, flags := {}) -> void:
	_db[id] = {"id": id, "name": name, "desc": desc, "type": T.TRINKET, "q": 1, "pools": ["treasure", "shop", "secret"], "tags": [], "stats": stats, "flags": flags}


static func _build() -> void:
	var TR := ["treasure"]
	var TS := ["treasure", "shop"]
	var TB := ["treasure", "boss"]
	var B := ["boss"]
	var DV := ["devil"]
	var AN := ["angel"]
	# ── 패시브: 탄 변형 ──
	_p("twin", "쌍열 총신", "한 번에 탄 2발", 2, TR, ["gun"], {"dmg_x": -0.1}, {"multi": 1})
	_p("inner_eye", "삼중 총구", "탄 3발 부채꼴 · 연사 감소", 2, TR, ["gun"], {"tears_x": -0.35}, {"triple": 1})
	_p("quad", "사중 포신", "탄 4발 · 연사 크게 감소", 3, TR, ["gun"], {"tears_x": -0.45}, {"quad": 1})
	_p("homing", "유도 칩", "탄이 적을 쫓아간다", 3, TR, ["tech"], {}, {"homing": 1})
	_p("pierce", "관통 탄두", "탄이 적을 꿰뚫는다", 2, TR, [], {}, {"pierce": 1})
	_p("rubber", "고무 탄", "탄이 벽에 두 번 튕긴다", 1, TS, [], {}, {"bounce": 2})
	_p("parasite", "분열 탄", "맞으면 작은 탄 둘로 갈라진다", 2, TR, ["fly"], {}, {"split": 1})
	_p("ipecac", "폭발 탄두", "탄이 폭발한다 · 연사 크게 감소 · 공격 증가", 3, TR, ["bomb"], {"tears_x": -0.55, "dmg": 3.0}, {"explode": 1})
	_p("fire_mind", "화염 탄", "25% 확률로 적을 불태운다", 2, TR, [], {}, {"burn": 25})
	_p("cold", "독침 탄", "25% 확률로 중독", 1, TS, ["poison"], {}, {"poison": 25})
	_p("uranus", "냉각 코어", "맞은 적이 느려진다", 2, TR, [], {}, {"freeze": 1})
	_p("jacob", "전격 코일", "맞으면 주변 적에게 번개가 튄다", 3, TR, ["tech"], {}, {"chain": 1})
	_p("polyphemus", "거대 탄환", "탄 크기·피해 2배 · 연사 감소", 3, TR, [], {"tears_x": -0.4, "dmg_x": 1.0, "size": 0.6}, {"giant": 1})
	_p("boomerang", "부메랑 탄", "탄이 날아갔다 돌아온다", 2, TR, [], {"range": 2.0}, {"boomerang": 1})
	_p("wiggle", "사인 파형", "탄이 물결치며 날아간다", 1, TS, [], {}, {"wave": 1})
	_p("back_shot", "후방 사수", "뒤로도 한 발", 1, TS, ["gun"], {}, {"back": 1})
	_p("tiny_planet", "소형 행성", "탄이 몸 둘레를 공전하다 퍼진다", 2, TR, [], {"range": 3.0}, {"orbit": 1})
	_p("loki", "사방 난사", "25% 확률로 4방향 동시 발사", 2, TR, ["gun"], {}, {"spray": 25})
	_p("technology", "레이저 렌즈", "탄이 즉발 레이저가 된다", 4, TB, ["tech"], {}, {"laser": 1})
	_p("brimstone", "혈사포 코어", "탄 대신 굵은 관통 빔 · 느린 연사 · 큰 피해", 4, ["treasure", "devil"], ["demon"], {"tears_x": -0.6, "dmg_x": 1.6}, {"brim": 1})
	_p("scope", "저격 조준경", "15% 확률 치명타 (3배 피해)", 2, TS, ["gun"], {}, {"crit": 15})
	_p("vamp_shot", "흡혈 탄", "처치 시 15% 확률로 반 칸 회복", 2, TR, ["demon"], {}, {"vamp": 15})
	_p("pisces", "충격 탄", "탄이 적을 크게 밀어낸다 · 연사 증가", 1, TS, [], {"tears": 0.4}, {"knock": 1})
	_p("double_shot", "산탄 확장", "탄 1발 추가 · 피해 소폭 감소", 2, TR, ["gun"], {"dmg_x": -0.15}, {"multi": 1})
	# ── 패시브: 스탯 ──
	_p("protein", "단백질 캔", "공격 +1", 2, TB, [], {"dmg": 1.0})
	_p("fuel", "고급 연료", "공격 +0.5, 공격 ×1.3", 4, TB, [], {"dmg": 0.5, "dmg_x": 0.3})
	_p("speed_gear", "고속 기어", "이동 +0.25, 탄속 +", 1, TS, [], {"speed": 0.25, "shot_speed": 6.0})
	_p("trigger", "트리거 스프링", "연사 +1", 2, TB, ["gun"], {"tears": 1.0})
	_p("cool_pin", "냉각 핀", "연사 +0.6, 사거리 +", 1, TS, [], {"tears": 0.6, "range": 1.5})
	_p("telescope", "망원 조준기", "사거리 크게 증가, 탄속 +", 1, TS, [], {"range": 4.0, "shot_speed": 4.0})
	_p("lucky_coin", "행운의 동전", "행운 +1, 동전 +3", 1, TS, [], {"luck": 1.0}, {"coins": 3})
	_p("big_heart", "대형 하트", "빨간 그릇 +1, 모두 회복", 2, TB, [], {"hearts": 1, "heal": 24})
	_p("soul_cap", "소울 캡슐", "소울 하트 2칸", 1, ["treasure", "shop", "angel"], ["angel"], {"soul": 4})
	_p("black_heart", "검은 심장", "블랙 하트 2칸 (깎일 때 방 전체 피해)", 2, ["devil", "secret"], ["demon"], {"black": 4})
	_p("grail", "성배", "비행 · 소울 하트 1칸", 3, AN, ["angel"], {"soul": 2}, {"flight": 1})
	_p("magic_mush", "거대 버섯", "그릇 +1, 공격 +0.3, 이동 +, 몸이 커진다", 3, TB, ["mushroom"], {"hearts": 1, "heal": 2, "dmg": 0.3, "speed": 0.15, "range": 1.0}, {"grow": 1})
	_p("mini_mush", "꼬마 버섯", "이동 +0.3, 사거리 -, 몸이 작아진다", 1, TS, ["mushroom"], {"speed": 0.3, "range": -1.0}, {"shrink": 1})
	_p("odd_mush", "독버섯", "연사 +1.2, 공격 -0.5", 1, TS, ["mushroom", "poison"], {"tears": 1.2, "dmg": -0.5})
	_p("blue_cap", "파란 버섯", "그릇 +1, 연사 +0.5, 탄속 -", 2, TR, ["mushroom"], {"hearts": 1, "heal": 2, "tears": 0.5, "shot_speed": -4.0})
	_p("tech_heart", "기계 심장", "연사 +0.6, 탄속 +", 2, TS, ["tech"], {"tears": 0.6, "shot_speed": 6.0})
	_p("ammo_belt", "탄약 벨트", "연사 +0.5, 사거리 +", 1, TS, ["gun"], {"tears": 0.5, "range": 1.0})
	_p("pentagram", "악마의 뿔", "공격 +1, 악마방 확률 증가", 3, DV, ["demon"], {"dmg": 1.0}, {"devil_up": 1})
	_p("feather", "천사의 깃털", "연사 +0.4, 천사방 확률 증가", 2, AN, ["angel"], {"tears": 0.4}, {"angel_up": 1})
	# ── 패시브: 방어·회복 ──
	_p("mantle", "성스러운 망토", "방마다 첫 피해를 막는 보호막", 4, AN, ["angel"], {}, {"mantle": 1})
	_p("react_armor", "반응 장갑", "피격 시 주변에 충격파 (적 피해·탄 제거)", 2, TS, [], {}, {"react": 1})
	_p("nano", "나노 수리", "방 정리 시 50% 확률로 반 칸 회복", 2, TR, ["tech"], {}, {"regen": 50})
	_p("dodge_chip", "회피 회로", "15% 확률로 피해 회피", 2, TR, ["tech"], {}, {"dodge": 15})
	_p("plating", "강화 장갑판", "소울 2칸 · 피격 무적 시간 증가", 1, TS, [], {"soul": 4}, {"iframe": 1})
	_p("gas_tank", "독가스 탱크", "피격 시 독구름", 1, TS, ["poison"], {}, {"gas": 1})
	# ── 패시브: 패밀리어 ──
	_p("orb_shield", "궤도 방패", "몸 둘레를 돌며 적 탄을 막는다", 2, TS, [], {}, {"fam_shield": 1})
	_p("fly_halo", "파리 떼", "파리 2마리가 돌며 적 탄을 막는다", 1, TS, ["fly"], {}, {"fam_fly": 2})
	_p("buddy", "꼬마 포탑", "가까운 적을 쏘는 포탑이 따라다닌다", 2, TR, [], {}, {"fam_turret": 1})
	_p("twin_buddy", "쌍둥이 포탑", "포탑 2기", 3, TR, [], {}, {"fam_turret": 2})
	_p("hunter_fly", "사냥 파리", "적을 쫓아가 물어뜯는 파리", 1, TS, ["fly"], {}, {"fam_hunter": 1})
	_p("satellite", "레이저 위성", "공전하며 레이저를 쏘는 위성", 3, TR, ["tech"], {}, {"fam_sat": 1})
	_p("fly_queen", "파리 여왕", "처치 시 33% 확률로 사냥 파리", 2, TR, ["fly"], {}, {"fly_queen": 33})
	_p("plague_fly", "독 파리", "중독시키는 사냥 파리", 2, TR, ["fly", "poison"], {}, {"fam_hunter": 1, "hunter_poison": 1})
	# ── 패시브: 검 ──
	_p("sword_wave", "검기 발생기", "검이 맞을 때마다 검기 발사", 3, TB, ["blade"], {}, {"blade_wave": 1})
	_p("long_blade", "장검 연장", "검 사거리 +40%", 2, TS, ["blade"], {}, {"blade_reach": 1})
	_p("fire_blade", "화염 검", "검이 적을 불태운다", 2, TR, ["blade"], {}, {"blade_fire": 1})
	_p("vamp_blade", "흡혈 검", "검으로 처치하면 25% 확률 반 칸 회복", 2, ["treasure", "devil"], ["blade", "demon"], {}, {"blade_vamp": 25})
	_p("whetstone", "숫돌", "검 피해 +50%", 2, TS, ["blade"], {"slash_x": 0.5})
	# ── 패시브: 대시 ──
	_p("dash_fire", "화염 분사", "대시 자취가 불타오른다", 2, TR, [], {}, {"dash_fire": 1})
	_p("dash_shock", "충격 착지", "대시가 끝나면 충격파", 2, TR, [], {}, {"dash_shock": 1})
	_p("dash_mine", "기뢰 투하", "대시 시작점에 기뢰", 2, TR, ["bomb"], {}, {"dash_mine": 1})
	_p("dash_shots", "잔탄 방출", "대시가 끝나면 8방향 탄", 2, TR, ["gun"], {}, {"dash_shots": 1})
	# ── 패시브: 처치·상황 ──
	_p("chain_blast", "연쇄 폭발", "처치한 적이 폭발한다", 3, TR, ["bomb"], {}, {"kill_explode": 1})
	_p("soul_harvest", "영혼 수확", "처치 시 5% 소울 반 칸", 2, DV, ["demon"], {}, {"kill_soul": 5})
	_p("bloodlust", "피의 욕망", "이번 방에서 맞을수록 공격 증가", 2, DV, ["demon"], {}, {"bloodlust": 1})
	_p("babylon", "바빌론의 분노", "빨간 체력 1칸 이하일 때 공격 +1.5, 이동 +", 2, DV, ["demon"], {}, {"wrath": 1})
	_p("focus", "전투 흥분", "연속 명중할수록 공격 증가 (최대 ×1.6)", 2, TR, ["gun"], {}, {"focus": 1})
	_p("holy_light", "성스러운 빛", "10% 확률로 빛기둥", 3, AN, ["angel"], {}, {"holy": 10})
	_p("wings", "날개", "비행 (가시·불·저주방 피해 무시)", 3, ["angel", "boss"], ["angel"], {"speed": 0.1}, {"flight": 1})
	_p("viper", "독사 송곳니", "중독 확률 +20%, 공격 +0.5", 2, TS, ["poison"], {"dmg": 0.5}, {"poison": 20})
	_p("bomb_book", "폭탄 연구서", "폭탄이 커지고 폭발 피해 2배", 2, TS, ["bomb"], {}, {"bomb_big": 1})
	_p("antenna", "안테나", "10% 확률로 번개 연쇄", 1, TS, ["tech"], {}, {"antenna": 10})
	_p("spores", "버섯 포자", "처치한 자리에 독 포자 구름", 2, TR, ["mushroom", "poison"], {}, {"spore": 1})
	# ── 패시브: 규칙 변경 ──
	_p("treasure_map", "보물 지도", "특수방 위치 공개", 1, ["shop"], [], {}, {"map_special": 1})
	_p("compass", "나침반", "모든 방 위치 공개", 1, ["shop"], [], {}, {"map_all": 1})
	_p("blueprint", "청사진", "비밀방 위치 공개", 1, ["shop", "secret"], [], {}, {"map_secret": 1})
	_p("skeleton_key", "해골 열쇠", "열쇠 99", 3, ["secret", "treasure"], [], {}, {"keys": 99})
	_p("pyro", "화약 상자", "폭탄 99", 3, ["secret", "treasure"], ["bomb"], {}, {"bombs": 99})
	_p("coupon", "할인 쿠폰", "상점 반값", 2, ["shop"], [], {}, {"discount": 1})
	_p("options", "더 많은 선택", "아이템방에 받침대 2개 (하나만 가질 수 있다)", 2, ["shop", "treasure"], [], {}, {"options": 1})
	_p("goat", "악마의 계약서", "보스 뒤 악마방 확정", 3, ["devil", "secret"], ["demon"], {}, {"goat": 1})
	_p("magnet", "자석 장갑", "픽업이 끌려온다", 1, ["shop"], [], {}, {"magnet": 1})
	_p("battery", "배터리 팩", "액티브 충전 +1 추가", 2, ["shop", "treasure"], ["tech"], {}, {"battery": 1})

	# ── 액티브 ──
	_a("a_bomb", "폭탄 투하기", "무료 폭탄 1개", 1, 1, ["treasure", "shop", "library"], ["bomb"])
	_a("a_ring", "링 버스트", "현재 탄으로 16방향 일제 사격", 1, 2, ["treasure", "library"], ["gun"])
	_a("a_d6", "리롤 D6", "이 방의 아이템을 다시 굴린다", 6, 4, ["treasure", "library", "secret"])
	_a("a_d20", "D20", "이 방의 픽업을 다시 굴린다", 5, 2, ["shop", "library"])
	_a("a_watch", "시간 정지 시계", "적과 적 탄이 3초 멈춘다", 4, 3, ["treasure", "library"])
	_a("a_shadows", "그림자의 서", "8초 무적", 3, 3, ["library", "angel"], ["angel"])
	_a("a_belial", "분노의 서", "이 방에서 공격 +2, 블랙 반 칸", 3, 3, ["devil", "library"], ["demon"])
	_a("a_razor", "면도날", "빨간 반 칸 → 이 방 공격 +1.2 (중첩)", 1, 2, ["devil", "shop"], ["demon"])
	_a("a_necro", "네크로노미콘", "방 전체 적 40 피해", 4, 3, ["library", "devil"], ["demon"])
	_a("a_teleport", "순간이동기", "무작위 방으로 이동", 2, 1, ["shop", "library"], ["tech"])
	_a("a_crystal", "수정구", "지도 전체 + 비밀방 공개", 3, 2, ["shop", "library"])
	_a("a_nickel", "나무 동전", "50% 확률로 동전", 1, 1, ["shop"])
	_a("a_hole", "블랙홀 발생기", "6초간 적을 빨아들이는 블랙홀", 4, 3, ["treasure", "library"], ["tech"])
	_a("a_sat", "위성 호출", "8초간 레이저 위성", 3, 2, ["treasure", "library"], ["tech"])
	_a("a_berserk", "폭주", "6초간 연사 ×2.5, 공격 ×1.5", 6, 4, ["treasure", "devil"], ["demon"])
	_a("a_supply", "보급 신호기", "보급 상자 (픽업 4~6개)", 6, 2, ["shop", "library"])
	_a("a_minions", "부하 소환", "이 방 동안 공격 드론 2기", 3, 2, ["treasure", "library"], ["fly"])
	_a("a_chaos", "혼돈 주사위 D∞", "보유 패시브를 전부 다시 굴린다", 6, 4, ["secret", "devil"])

	# ── 장신구 ──
	_t("t_foot", "토끼발", "행운 +1", {"luck": 1.0})
	_t("t_purse", "찢어진 주머니", "방 보상에 동전이 잘 나온다", {}, {"drop_coin": 1})
	_t("t_rkey", "녹슨 열쇠", "방 보상에 열쇠가 잘 나온다", {}, {"drop_key": 1})
	_t("t_match", "성냥갑", "방 보상에 폭탄이 잘 나온다", {}, {"drop_bomb": 1})
	_t("t_bcoin", "피 묻은 동전", "피격 시 동전", {}, {"hurt_coin": 1})
	_t("t_crown", "금 간 왕관", "공격 +0.5", {"dmg": 0.5})
	_t("t_spring", "감긴 태엽", "연사 +0.3", {"tears": 0.3})
	_t("t_lace", "신발끈", "이동 +0.15", {"speed": 0.15})
	_t("t_lens", "렌즈 조각", "사거리 +2", {"range": 2.0})
	_t("t_band", "고무줄", "탄이 한 번 튕긴다", {}, {"bounce": 1})
	_t("t_sting", "독침", "10% 중독", {}, {"poison": 10})
	_t("t_ember", "불씨", "10% 화상", {}, {"burn": 10})
	_t("t_ring", "성자의 반지", "방 진입 시 20% 소울 반 칸", {}, {"room_soul": 20})
	_t("t_tail", "악마의 꼬리", "악마방 확률 증가", {}, {"devil_up": 1})
	_t("t_cell", "예비 전지", "방 정리 시 50% 액티브 충전 추가", {}, {"cell": 50})
	_t("t_lode", "자철석", "픽업이 끌려온다", {}, {"magnet": 1})
	_t("t_mark", "사냥꾼의 증표", "보스 피해 +20%", {}, {"boss_dmg": 20})
	_t("t_fang", "분노의 송곳니", "빨간 반 칸만 남으면 공격 ×2", {}, {"last_stand": 1})
	_t("t_scrap", "지도 조각", "보스방 위치 공개", {}, {"map_boss": 1})
	_t("t_egg", "거미 알", "피격 시 주변 적 둔화", {}, {"hurt_slow": 1})


# ── 알약 (색 ↔ 효과는 런마다 무작위) ─────────────────────

const PILL_COLORS := [
	["흰·파랑", Color("f0f4ff"), Color("4a7aff")], ["흰·빨강", Color("f0f4ff"), Color("ff4a5a")], ["주황", Color("ffa040"), Color("ffa040")],
	["검정·노랑", Color("202028"), Color("ffe040")], ["분홍", Color("ff8ad0"), Color("ff8ad0")], ["하늘·흰", Color("8ae0ff"), Color("f0f4ff")],
	["초록", Color("50e070"), Color("50e070")], ["보라·흰", Color("a060ff"), Color("f0f4ff")], ["노랑·초록", Color("ffe040"), Color("50e070")],
	["빨강", Color("ff3a40"), Color("ff3a40")], ["회색", Color("909098"), Color("909098")], ["청록·주황", Color("40e8d0"), Color("ffa040")],
	["갈색", Color("a06a40"), Color("a06a40")], ["금색", Color("ffd060"), Color("fff0a0")],
]
## [id, 이름, 좋음?]
const PILLS := [
	["full_health", "체력 회복", true], ["health_up", "체력 업", true], ["health_down", "체력 다운", false],
	["dmg_up", "공격 업", true], ["dmg_down", "공격 다운", false], ["tears_up", "연사 업", true], ["tears_down", "연사 다운", false],
	["speed_up", "이동 업", true], ["speed_down", "이동 다운", false], ["range_up", "사거리 업", true], ["range_down", "사거리 다운", false],
	["luck_up", "행운 업", true], ["luck_down", "행운 다운", false], ["bombs", "폭탄 발견", true], ["keys", "열쇠 발견", true],
	["coins", "동전 비", true], ["power", "파워 필", true], ["energy", "48시간 에너지", true], ["tele", "텔레필", true],
	["vision", "망원 시야", true], ["blast", "역류", false],
]


static func pill_name(effect: String) -> String:
	for p in PILLS:
		if p[0] == effect:
			return p[1]
	return effect


# ── 카드 · 룬 ───────────────────────────────────────────

## [id, 이름, 설명]
const CARDS := [
	["fool", "0 · 바보", "시작 방으로"],
	["magician", "I · 마술사", "이 방 동안 유도 탄"],
	["emperor", "IV · 황제", "보스방 앞으로"],
	["lovers", "VI · 연인", "빨간 하트 2칸"],
	["chariot", "VII · 전차", "6초 무적"],
	["hermit", "IX · 은둔자", "상점으로"],
	["strength", "XI · 힘", "이 방 공격 +1.5, 몸이 커진다"],
	["star", "XVII · 별", "아이템방으로"],
	["moon", "XVIII · 달", "비밀방으로"],
	["sun", "XIX · 태양", "풀 회복 · 지도 공개 · 방 전체 피해"],
	["world", "XXI · 세계", "지도 공개"],
	["justice", "VIII · 정의", "동전·폭탄·열쇠 1개씩"],
	["death", "XIII · 죽음", "방 전체 적 40 피해"],
	["tower", "XVI · 탑", "주변에 폭탄 6개"],
	["hagalaz", "룬 · 하갈라즈", "상자·장애물 전부 파괴"],
	["berkano", "룬 · 버카나", "사냥 파리 3마리"],
	["algiz", "룬 · 알기즈", "10초 무적 + 소울 반 칸"],
]


static func card(id: String) -> Array:
	for c in CARDS:
		if c[0] == id:
			return c
	return [id, id, ""]


# ── 결합 공격 (이름 붙은 시너지) ─────────────────────────
## need: 각 칸에서 하나 이상 가지고 있으면 성립 (칸끼리는 AND)

const SYNERGIES := [
	{"id": "missile", "name": "유도 폭뢰", "desc": "탄이 소형 미사일로 — 가속 · 연기 꼬리 · 큰 폭발", "need": [["homing"], ["ipecac", "chain_blast"]]},
	{"id": "prism", "name": "프리즘 레이저", "desc": "레이저가 첫 적에서 3갈래로 굴절", "need": [["technology"], ["twin", "inner_eye", "quad", "double_shot"]]},
	{"id": "saw", "name": "회전 톱날", "desc": "탄이 회전 톱날 — 나갔다 돌아오며 다단 히트", "need": [["boomerang"], ["pierce"]]},
	{"id": "storm_net", "name": "전격 그물", "desc": "번개가 튈 때마다 분열 탄", "need": [["jacob", "antenna"], ["parasite"]]},
	{"id": "flare", "name": "태양 플레어", "desc": "거대 화염구 — 맞은 자리에 불바다", "need": [["fire_mind"], ["polyphemus"]]},
	{"id": "singularity", "name": "중력 구체", "desc": "8발마다 적을 빨아들이는 특이점", "need": [["homing"], ["uranus"]]},
	{"id": "blade_storm", "name": "칼날 폭풍", "desc": "검기가 3갈래 부채꼴", "need": [["sword_wave"], ["twin", "inner_eye", "quad", "double_shot"]]},
	{"id": "comet", "name": "혜성 대시", "desc": "대시 자취가 연쇄 폭발", "need": [["dash_fire"], ["ipecac", "chain_blast", "dash_mine"]]},
	{"id": "mirror", "name": "거울 반사", "desc": "튕길 때마다 피해 +50%, 튕김 4회", "need": [["rubber"], ["back_shot"]]},
	{"id": "plague", "name": "역병 구름", "desc": "몸 둘레를 도는 독 소용돌이", "need": [["cold", "viper", "plague_fly"], ["tiny_planet"]]},
	{"id": "brim_spin", "name": "회전 혈사포", "desc": "빔이 몸 둘레를 휩쓸며 회전", "need": [["brimstone"], ["tiny_planet"]]},
	{"id": "meteor", "name": "유성우", "desc": "4방향 난사 탄이 별똥별처럼 휘어 적에게", "need": [["loki"], ["homing"]]},
	{"id": "vampire", "name": "흡혈귀", "desc": "처치마다 반 칸 회복 확률 100%", "need": [["vamp_shot"], ["vamp_blade"]]},
	{"id": "powder", "name": "화약고", "desc": "폭탄을 놓으면 폭탄 3개가 사방으로 굴러간다", "need": [["bomb_book"], ["pyro"]]},
	{"id": "mortar", "name": "연사 박격", "desc": "폭발 탄두의 연사 감소가 사라진다", "need": [["trigger"], ["ipecac"]]},
]

# ── 변신 (태그 3개) ─────────────────────────────────────

const TRANSFORMS := {
	"angel": {"name": "기계 세라핌", "desc": "비행 · 소울 2칸 · 10% 빛기둥"},
	"demon": {"name": "지옥 계약자", "desc": "비행 · 블랙 2칸 · 공격 +1"},
	"fly": {"name": "벌떼 군주", "desc": "파리 3마리가 탄을 흡수 · 공격 시 15% 사냥 파리"},
	"poison": {"name": "역병 운반자", "desc": "독 자취 · 모든 탄 30% 중독"},
	"mushroom": {"name": "거인", "desc": "그릇 +1 · 검 사거리 +30% · 공격 +0.5"},
	"tech": {"name": "사이보그", "desc": "4발마다 레이저 · 이동 +0.15"},
	"blade": {"name": "검성", "desc": "검기 항상 · 검 피해 ×1.5"},
	"bomb": {"name": "폭파광", "desc": "폭탄 +5 · 폭탄 피해 면역 · 폭탄 크게"},
	"gun": {"name": "탄막광", "desc": "연사 +1 · 탄 +1"},
}
const TRANSFORM_NEED := 3
