class_name DialogueRunner
extends RefCounted
## 대사 진행기. 화면 없이 DialogueScript 를 따라가며 신호만 낸다 (테스트에서 그대로 쓴다).
## advance() 는 다음 대사 · 선택지 · 대기 · 끝 중 하나를 만날 때까지 연출 명령을 cue 로 흘려보낸다.

signal said(line: Dictionary)
signal asked(options: Array)
signal cue(cmd: Dictionary)
signal ended

const STEP_LIMIT := 10000

var dlg: DialogueScript
var pc := 0
var flags := {}
var done := false
var waiting_choice := false
## 지금 보이는 선택지 (조건을 통과한 것만, 원래 순번 포함)
var options: Array = []
## 지나온 @summary 줄 (전체 건너뛰기 때 요약으로 보여 준다)
var summaries: PackedStringArray = []
## 한 번 본 대사 (경로:줄) — 넘기기(읽은 대사만)와 선택지 표시에 쓴다. 씬을 다시 불러도 유지
static var seen := {}
static var picked := {}


func _init(s: DialogueScript) -> void:
	dlg = s


func start(label := "") -> void:
	pc = dlg.labels.get(label, 0) if label != "" else 0
	done = false
	waiting_choice = false
	advance()


func advance() -> void:
	if done or waiting_choice:
		return
	var steps := 0
	while pc < dlg.items.size():
		steps += 1
		if steps > STEP_LIMIT:
			push_error("대사 무한 반복: " + dlg.path)
			break
		var it: Dictionary = dlg.items[pc]
		pc += 1
		match it.op:
			"say":
				var line := it.duplicate()
				line.was_seen = seen.has(key(it))
				seen[key(it)] = true
				said.emit(line)
				return
			"choice":
				options = []
				for i in it.options.size():
					var o: Dictionary = it.options[i]
					if DialogueScript.test(o.cond, flags):
						var d := o.duplicate()
						d.index = i
						d.picked = picked.has("%s:%d" % [dlg.path, o.line])
						options.append(d)
				if options.is_empty():
					continue
				waiting_choice = true
				asked.emit(options)
				return
			"jump":
				pc = dlg.labels[it.to]
			"if":
				if DialogueScript.test(it.cond, flags):
					pc = dlg.labels[it.to]
			"set":
				var v: Variant = it.value
				if it.how == "+=":
					v = float(flags.get(it.name, 0.0)) + float(v)
				elif it.how == "-=":
					v = float(flags.get(it.name, 0.0)) - float(v)
				flags[it.name] = v
			"summary":
				summaries.append(it.text)
			"end":
				break
			"wait":
				cue.emit(it)
				return
			_:
				cue.emit(it)
	done = true
	ended.emit()


func choose(i: int) -> void:
	if not waiting_choice or i < 0 or i >= options.size():
		return
	var o: Dictionary = options[i]
	picked["%s:%d" % [dlg.path, o.line]] = true
	waiting_choice = false
	options = []
	if o.to != "":
		pc = dlg.labels[o.to]
	advance()


func key(it: Dictionary) -> String:
	return "%s:%d" % [dlg.path, it.line]


