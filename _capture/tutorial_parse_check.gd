extends SceneTree
## 튜토리얼 스크립트 문법 확인 (개발용)
func _initialize() -> void:
	for p in ["res://scripts/tutorial/run_tutorial.gd", "res://scripts/run_main.gd", "res://tests/run_tutorial_check.gd"]:
		var s = load(p)
		print("LOAD %s %s" % [p, "ok" if s != null and s.can_instantiate() else "FAIL"])
	quit()
