class_name DialogueCast
extends RefCounted
## 대화에 나오는 인물 목록. 이름 · 색 · 표정 그림 · 목소리 높이 · 그림이 바라보는 쪽.
const DIR := "res://assets/portraits/opening_cast/"

## face/faces: 원화의 몸 방향 (+1 화면 오른쪽, -1 왼쪽). 시선은 플레이어 쪽으로 그린다.
## flip_ok/flip_expr: 반전 가능한 인물/표정. 비대칭 기존 디자인은 그대로 보존한다.
## voice: 글자 소리 기본 높이(Hz) · wave: 0 사각 / 1 삼각 / 2 사인
const CAST := {
	"owner": {
		"name": "사장", "en": "OWNER", "color": Color("91c7b7"), "voice": 290.0, "wave": 2,
		"face": 1, "flip_ok": true,
		"flip_expr": ["introduction"],
		"dir": "res://assets/portraits/opening_cast/",
		"expr": {"welcome": "owner_welcome", "briefing": "owner_briefing", "encouragement": "owner_encouragement", "introduction": "owner_welcome"},
		"default": "welcome",
	},
	"worker": {
		"name": "정비사", "en": "MECHANIC", "color": Color("b69be4"), "voice": 380.0, "wave": 1,
		"face": -1, "flip_ok": true,
		"dir": "res://assets/portraits/opening_cast/",
		"expr": {"introduction": "worker_introduction", "cheerful": "worker_cheerful"},
		"default": "introduction",
	},
	"partner": {
		"name": "청소 파트너", "en": "CLEANING PARTNER", "color": Color("e890b8"), "voice": 430.0, "wave": 1,
		"face": -1, "flip_ok": true,
		"dir": "res://assets/portraits/opening_cast/",
		"expr": {"greeting": "partner_greeting"}, "default": "greeting",
	},
	"me": {
		"name": "나", "en": "PILOT", "color": Color("7cf5ff"), "voice": 200.0, "wave": 0,
		"face": 1, "flip_ok": false, "speaker_only": true,
		"dir": "res://assets/portraits/opening_cast/",
		"expr": {"neutral": "pilot_neutral"}, "default": "neutral",
	},
}
## 그림 없이 말하는 화자 (무전 · 해설). 주인공은 대사창 포트레이트를 쓴다.
const VOICES := {
	"radio": {"name": "관제 무전", "en": "CTRL", "color": Color("9fe870"), "voice": 520.0, "wave": 0},
}

static var _tex := {}


static func has(id: String) -> bool:
	return CAST.has(id) or VOICES.has(id)


static func info(id: String) -> Dictionary:
	if CAST.has(id):
		return CAST[id]
	return VOICES.get(id, {"name": id, "en": "", "color": Color.WHITE, "voice": 330.0, "wave": 0})


static func has_portrait(id: String) -> bool:
	return CAST.has(id)


static func has_expr(id: String, expr: String) -> bool:
	return CAST.has(id) and CAST[id].expr.has(expr)


## 표정 그림. 없는 표정이면 기본 표정
static func texture(id: String, expr: String, closed := false) -> Texture2D:
	if not CAST.has(id):
		return null
	var c: Dictionary = CAST[id]
	var file: String = c.expr.get(expr, c.expr[c.default])
	if closed and id in ["owner", "worker", "partner"]:
		file += "_closed"
	var path: String = c.get("dir", DIR) + file + ".png"
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]
