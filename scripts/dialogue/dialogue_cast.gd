class_name DialogueCast
extends RefCounted
## 대화에 나오는 인물 목록. 이름 · 색 · 표정 그림 · 목소리 높이 · 그림이 바라보는 쪽.
## 그림은 아직 아트 시안 폴더(output/character-dialogue-20261001)에 있다. 옮기면 DIR 만 바꾼다.

const DIR := "res://output/character-dialogue-20261001/"

## face: 그림 속 얼굴이 향한 쪽 (+1 화면 오른쪽, -1 왼쪽). flip_ok: 좌우 반전해도 디자인이 깨지지 않는가
## voice: 글자 소리 기본 높이(Hz) · wave: 0 사각 / 1 삼각 / 2 사인
const CAST := {
	"mira": {
		"name": "미라", "en": "MIRA", "color": Color("c8303c"), "voice": 300.0, "wave": 0,
		"face": 1, "flip_ok": false,
		"expr": {"confident": "mira-confident", "angry": "mira-angry", "flustered": "mira-flustered"},
		"default": "confident",
	},
	"sena": {
		"name": "세나", "en": "SENA", "color": Color("f08a24"), "voice": 470.0, "wave": 1,
		"face": 1, "flip_ok": true,
		"expr": {"joy": "sena-joy", "angry": "sena-angry", "surprised": "sena-surprised"},
		"default": "joy",
	},
	"noa": {
		"name": "노아", "en": "NOA", "color": Color("3fb7a8"), "voice": 390.0, "wave": 2,
		"face": 1, "flip_ok": true,
		"expr": {"neutral": "noa-neutral", "skeptical": "noa-skeptical", "warm": "noa-warm"},
		"default": "neutral",
	},
	"eirin": {
		"name": "에이린", "en": "EIRIN", "color": Color("b9c3d6"), "voice": 250.0, "wave": 2,
		"face": -1, "flip_ok": true,
		"expr": {"confident": "eirin-confident", "stern": "eirin-stern", "vulnerable": "eirin-vulnerable"},
		"default": "confident",
	},
}
## 그림 없이 말하는 화자 (주인공 · 무전 · 해설)
const VOICES := {
	"me": {"name": "나", "en": "PILOT", "color": Color("7cf5ff"), "voice": 200.0, "wave": 0},
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
static func texture(id: String, expr: String) -> Texture2D:
	if not CAST.has(id):
		return null
	var c: Dictionary = CAST[id]
	var file: String = c.expr.get(expr, c.expr[c.default])
	if not _tex.has(file):
		_tex[file] = load(DIR + file + ".png")
	return _tex[file]
