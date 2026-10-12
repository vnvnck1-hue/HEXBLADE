extends SceneTree
## 로그 모드 스크립트를 모두 불러 문법 오류를 한 번에 본다 (개발용)
func _initialize() -> void:
	var d := DirAccess.open("res://scripts/rogue")
	for f in d.get_files():
		if f.ends_with(".gd"):
			var s = load("res://scripts/rogue/" + f)
			print("LOAD %s %s" % [f, "ok" if s != null and s.can_instantiate() else "FAIL"])
	var t = load("res://tests/rogue_check.gd")
	print("LOAD rogue_check %s" % ("ok" if t != null else "FAIL"))
	quit()
