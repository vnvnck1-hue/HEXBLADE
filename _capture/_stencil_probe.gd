extends SceneTree
func _init():
	for code in ["shader_type spatial;\nrender_mode unshaded;\nstencil_mode write, compare_always, 77;\nvoid fragment(){ALBEDO=vec3(1);}",
			"shader_type spatial;\nrender_mode unshaded;\nstencil_mode read, compare_not_equal, 77;\nvoid fragment(){ALBEDO=vec3(1);}"]:
		var sh := Shader.new()
		sh.code = code
		var m := ShaderMaterial.new()
		m.shader = sh
		print("RID ok: ", sh.get_rid(), " mode=", sh.get_mode())
	print("PROBE DONE")
	quit()
