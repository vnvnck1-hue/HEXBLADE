class_name DialogueScript
extends RefCounted
## 대사 파일(.dlg)을 읽어 명령 목록으로 바꾼다. 문법은 docs/dialogue.md 참고.
##
##   # 주석                          == 라벨
##   @title 격납고 · 출격 준비          @enter mira left confident    @exit mira
##   @expr mira angry                @move mira right              @shake 0.6   @flash   @wait 0.5
##   @summary 건너뛸 때 보여 줄 줄거리 한 줄
##   @set trust += 1                 @if trust >= 1 -> 라벨          -> 라벨       @end
##   mira angry !: 이번엔 {shake}전부{/shake} 데려간다.   (! = 그림 흔들기)
##   > 해설 문장 (화자 없음)
##   * 선택지 문장 -> 라벨              * [if trust >= 1] <미라> 조건부 · 꼬리표 붙은 선택지 -> 라벨
##
## 글자 안 꾸밈: {shake} {wave} {b} {big} {small} {red} {cyan} {gold} {gray} {color=#hex} 와 닫는 {/…},
##              {p} {p=0.8} 멈춤, {fast} {slow} {/fast} {/slow} 속도. 문장부호 뒤에는 자동으로 잠깐 멈춘다.

const COLORS := {"red": "#ff4a5a", "cyan": "#7cf5ff", "gold": "#ffd166", "gray": "#8a8fa3", "green": "#9fe870"}
const OPEN := {
	"shake": "[shake rate=22.0 level=9 connected=1]", "wave": "[wave amp=28.0 freq=4.0 connected=1]",
	"b": "[b]", "big": "[font_size=46]", "small": "[font_size=24]", "i": "[i]",
}
const CLOSE := {"shake": "[/shake]", "wave": "[/wave]", "b": "[/b]", "big": "[/font_size]", "small": "[/font_size]", "i": "[/i]"}
## 문장부호 뒤 자동 멈춤 (초)
const PUNCT_PAUSE := {".": 0.22, "!": 0.22, "?": 0.22, "…": 0.3, ",": 0.1, "~": 0.12}
const SLOTS := ["left", "right", "left2", "right2", "center"]

var items: Array[Dictionary] = []
var labels := {}
var errors: PackedStringArray = []
var path := ""


static func load_file(file: String) -> DialogueScript:
	var s := DialogueScript.new()
	s.path = file
	var f := FileAccess.open(file, FileAccess.READ)
	if f == null:
		s.errors.append("파일을 열 수 없음: " + file)
		return s
	s.parse(f.get_as_text())
	return s


static func from_text(text: String) -> DialogueScript:
	var s := DialogueScript.new()
	s.parse(text)
	return s


func parse(text: String) -> void:
	var n := 0
	var choice: Dictionary = {}
	for raw in text.split("\n"):
		n += 1
		var ln := raw.strip_edges()
		if ln.begins_with("*"):
			if choice.is_empty():
				choice = {"op": "choice", "options": [], "line": n}
				items.append(choice)
			choice.options.append(_option(ln.substr(1).strip_edges(), n))
			continue
		choice = {}
		if ln == "" or ln.begins_with("#") or ln.begins_with("//"):
			continue
		if ln.begins_with("=="):
			var name := ln.substr(2).strip_edges().trim_suffix("==").strip_edges()
			if labels.has(name):
				_err(n, "라벨이 두 번 나옴: " + name)
			labels[name] = items.size()
		elif ln.begins_with("->"):
			items.append({"op": "jump", "to": ln.substr(2).strip_edges(), "line": n})
		elif ln.begins_with("@"):
			_command(ln.substr(1), n)
		elif ln.begins_with(">"):
			items.append(_say("", "", false, ln.substr(1).strip_edges(), n))
		else:
			_say_line(ln, n)
	# 점프 대상 확인
	for it in items:
		var targets: Array = []
		if it.op in ["jump", "if"]:
			targets.append(it.to)
		elif it.op == "choice":
			for o in it.options:
				if o.to != "":
					targets.append(o.to)
		for t in targets:
			if not labels.has(t):
				_err(it.line, "없는 라벨: " + t)


func _err(n: int, msg: String) -> void:
	errors.append("%s:%d %s" % [path, n, msg])


func _say_line(ln: String, n: int) -> void:
	var colon := ln.find(":")
	if colon <= 0:
		_err(n, "알 수 없는 줄: " + ln)
		return
	var head := ln.substr(0, colon).strip_edges().split(" ", false)
	var who := head[0]
	if not DialogueCast.has(who):
		_err(n, "없는 화자: " + who)
		return
	var expr := ""
	var punch := false
	for i in range(1, head.size()):
		var tok: String = head[i]
		if tok == "!":
			punch = true
		elif tok.ends_with("!"):
			punch = true
			expr = tok.trim_suffix("!")
		else:
			expr = tok
	if expr != "" and DialogueCast.has_portrait(who) and not DialogueCast.has_expr(who, expr):
		_err(n, "%s 에게 없는 표정: %s" % [who, expr])
	items.append(_say(who, expr, punch, ln.substr(colon + 1).strip_edges(), n))


func _say(who: String, expr: String, punch: bool, text: String, n: int) -> Dictionary:
	var d := markup(text)
	d.merge({"op": "say", "who": who, "expr": expr, "punch": punch, "line": n})
	return d


func _option(body: String, n: int) -> Dictionary:
	var cond := ""
	if body.begins_with("[if "):
		var close := body.find("]")
		cond = body.substr(4, close - 4).strip_edges()
		body = body.substr(close + 1).strip_edges()
	var tag := ""
	if body.begins_with("<"):
		var gt := body.find(">")
		tag = body.substr(1, gt - 1).strip_edges()
		body = body.substr(gt + 1).strip_edges()
	var to := ""
	var arrow := body.rfind("->")
	if arrow >= 0:
		to = body.substr(arrow + 2).strip_edges()
		body = body.substr(0, arrow).strip_edges()
	return {"text": body, "tag": tag, "to": to, "cond": cond, "line": n}


func _command(body: String, n: int) -> void:
	var arrow := body.find("->")
	var to := ""
	if arrow >= 0:
		to = body.substr(arrow + 2).strip_edges()
		body = body.substr(0, arrow).strip_edges()
	var sp := body.find(" ")
	var op := body if sp < 0 else body.substr(0, sp)
	var rest := "" if sp < 0 else body.substr(sp + 1).strip_edges()
	var a := rest.split(" ", false)
	match op:
		"title":
			items.append({"op": "title", "text": rest, "line": n})
		"summary":
			items.append({"op": "summary", "text": rest, "line": n})
		"enter":
			if a.size() < 2 or not DialogueCast.has_portrait(a[0]) or a[1] not in SLOTS:
				_err(n, "@enter 인물 자리 [표정] — " + rest)
				return
			items.append({"op": "enter", "who": a[0], "slot": a[1], "expr": a[2] if a.size() > 2 else "", "line": n})
		"exit":
			items.append({"op": "exit", "who": a[0] if a.size() > 0 else "", "line": n})
		"expr":
			if a.size() < 2 or not DialogueCast.has_expr(a[0], a[1]):
				_err(n, "@expr 인물 표정 — " + rest)
				return
			items.append({"op": "expr", "who": a[0], "expr": a[1], "line": n})
		"move":
			if a.size() < 2 or a[1] not in SLOTS:
				_err(n, "@move 인물 자리 — " + rest)
				return
			items.append({"op": "move", "who": a[0], "slot": a[1], "line": n})
		"shake":
			items.append({"op": "shake", "power": float(a[0]) if a.size() > 0 else 0.5, "line": n})
		"flash":
			items.append({"op": "flash", "color": Color(a[0]) if a.size() > 0 else Color.WHITE, "line": n})
		"wait":
			items.append({"op": "wait", "sec": float(a[0]) if a.size() > 0 else 0.5, "line": n})
		"set":
			var m := _expr(rest, ["+=", "-=", "="])
			if m.is_empty():
				_err(n, "@set 이름 = 값 — " + rest)
				return
			m.merge({"op": "set", "line": n})
			items.append(m)
		"if":
			if to == "":
				_err(n, "@if 조건 -> 라벨")
				return
			items.append({"op": "if", "cond": rest, "to": to, "line": n})
		"end":
			items.append({"op": "end", "line": n})
		_:
			_err(n, "알 수 없는 명령: @" + op)


## "이름 연산 값" 을 나눈다. 연산은 긴 것부터 찾는다
static func _expr(s: String, ops: Array) -> Dictionary:
	for o in ops:
		var i := s.find(o)
		if i > 0:
			return {"name": s.substr(0, i).strip_edges(), "how": o, "value": _value(s.substr(i + o.length()).strip_edges())}
	return {}


static func _value(s: String) -> Variant:
	if s == "true":
		return true
	if s == "false":
		return false
	if s.is_valid_float():
		return float(s)
	return s


## 조건식 하나: "trust >= 1", "met_sena", "not met_sena"
static func test(cond: String, flags: Dictionary) -> bool:
	cond = cond.strip_edges()
	if cond == "":
		return true
	if cond.begins_with("not "):
		return not test(cond.substr(4), flags)
	var m := _expr(cond, [">=", "<=", "==", "!=", ">", "<"])
	if m.is_empty():
		return bool(flags.get(cond, false))
	var l: Variant = flags.get(m.name, 0.0)
	var r: Variant = m.value
	if typeof(l) == TYPE_BOOL:
		l = 1.0 if l else 0.0
	if typeof(r) == TYPE_BOOL:
		r = 1.0 if r else 0.0
	match m.how:
		">=": return l >= r
		"<=": return l <= r
		">": return l > r
		"<": return l < r
		"==": return l == r
		"!=": return l != r
	return false


## 꾸밈 문법을 BBCode 로 바꾸고, 글자 순번 기준 멈춤 · 속도 표를 만든다
static func markup(text: String) -> Dictionary:
	var bb := ""
	var plain := ""
	var pauses := {}
	var speeds: Array = []
	var i := 0
	while i < text.length():
		var ch := text[i]
		if ch == "{":
			var close := text.find("}", i)
			if close > i:
				var tag := text.substr(i + 1, close - i - 1)
				i = close + 1
				var closing := tag.begins_with("/")
				var key := tag.trim_prefix("/")
				var at := plain.length()
				if key == "p" or key.begins_with("p="):
					pauses[at] = pauses.get(at, 0.0) + (float(key.substr(2)) if key.begins_with("p=") else 0.4)
				elif key == "fast" or key == "slow":
					speeds.append([at, 1.0 if closing else (3.0 if key == "fast" else 0.35)])
				elif COLORS.has(key) or key.begins_with("color="):
					bb += "[/color]" if closing else "[color=%s]" % (COLORS[key] if COLORS.has(key) else key.substr(6))
				elif OPEN.has(key):
					bb += CLOSE[key] if closing else OPEN[key]
				else:
					bb += "{" + tag + "}"
					plain += "{" + tag + "}"
				continue
		if ch == "[":
			bb += "[lb]"
		elif ch == "\\" and i + 1 < text.length() and text[i + 1] == "n":
			ch = "\n"
			i += 1
			bb += "\n"
		else:
			bb += ch
		plain += ch
		i += 1
		# 문장부호 묶음(… ?! 등)이 끝나는 곳에서 멈춘다. 문장 끝이면 멈추지 않는다
		if PUNCT_PAUSE.has(ch) and i < text.length() and not PUNCT_PAUSE.has(text[i]) and text[i] not in ["\"", "”", "'", ")"]:
			var at := plain.length()
			pauses[at] = maxf(pauses.get(at, 0.0), PUNCT_PAUSE[ch])
	return {"bb": bb, "plain": plain, "pauses": pauses, "speeds": speeds}
