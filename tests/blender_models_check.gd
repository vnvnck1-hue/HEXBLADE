extends SceneTree
## Run with: Godot --headless --path . -s tests/blender_models_check.gd
## Blender 파이프라인(tools\blender.ps1 model)이 만든 assets/models/*.glb 가 Godot 에서 제대로 열리는지 본다.
##  1. 모든 .glb 가 PackedScene 으로 불러와지고 메시가 하나 이상 있다.
##  2. 예제 sample_turret: 파츠 계층 base > turret > barrel, 부착점 pt_muzzle_l/r 이 barrel 아래 있다.
##  3. 축 변환: Blender +Y(정면) 가 Godot -Z 로, 총구가 포탑 앞(-Z)·바닥 위(+Y)에 있다.
##  4. 거미 보스 spider_boss: 다리·공구 팔 관절 사슬, 발 부착점이 바닥, 눈이 앞, 용접기 오른쪽, 태블릿 높이.

const DIR := "res://assets/models"

var fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		fails += 1


func _meshes(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for k in n.get_children():
		c += _meshes(k)
	return c


func _run() -> void:
	var files := Array(DirAccess.get_files_at(DIR)).filter(func(f: String) -> bool: return f.ends_with(".glb"))
	_check(files.size() > 0, "assets/models 에 .glb 가 있다 (%d개)" % files.size())
	for f: String in files:
		var ps := load(DIR + "/" + f) as PackedScene
		_check(ps != null, "%s 불러오기" % f)
		if ps == null:
			continue
		var inst := ps.instantiate()
		root.add_child(inst)
		_check(_meshes(inst) > 0, "%s 메시 %d개" % [f, _meshes(inst)])
		inst.queue_free()

	var ps := load(DIR + "/sample_turret.glb") as PackedScene
	if ps:
		var t := ps.instantiate() as Node3D
		root.add_child(t)
		await process_frame
		var barrel := t.get_node_or_null("base/turret/barrel") as Node3D
		_check(barrel != null, "sample_turret 계층 base/turret/barrel")
		var mz := t.get_node_or_null("base/turret/barrel/pt_muzzle_l") as Node3D
		_check(mz != null, "sample_turret 부착점 pt_muzzle_l 이 barrel 아래")
		if mz:
			var p := mz.global_position
			_check(p.z < -1.2 and p.y > 0.7 and p.x < 0.0, "총구 위치 %s (앞 = -Z, 위 = +Y, 왼쪽 = -X)" % p)
		if barrel:
			_check(barrel.position.is_equal_approx(Vector3(0, 0.3, -0.45)), "barrel 피벗(포이) 로컬 위치 %s" % barrel.position)
		t.queue_free()

	# 거미 보스 (원화 재현 모델): 다리·팔 관절 사슬 · 부착점 · 원화 치수
	var sp := load(DIR + "/spider_boss.glb") as PackedScene
	if sp:
		var s := sp.instantiate() as Node3D
		root.add_child(s)
		await process_frame
		for k in ["fl", "fr", "bl", "br"]:
			var chain := "body/leg_%s_coxa/leg_%s_femur/leg_%s_tibia/leg_%s_foot" % [k, k, k, k]
			_check(s.get_node_or_null(chain) != null, "spider_boss 다리 사슬 " + chain)
			var ft := s.find_child("pt_foot_" + k) as Node3D
			_check(ft != null and absf(ft.global_position.y) < 0.05, "spider_boss 발 pt_foot_%s 바닥 위" % k)
		for k in ["welder", "saw"]:
			_check(s.get_node_or_null("body/arm_%s_upper/arm_%s_fore/arm_%s_tool" % [k, k, k]) != null, "spider_boss 공구 팔 " + k)
		_check(s.get_node_or_null("body/arm_saw_upper/arm_saw_fore/arm_saw_tool/arm_saw_disc") != null, "spider_boss 톱날 회전 노드")
		_check(s.get_node_or_null("body/head/gatling") != null and s.get_node_or_null("body/abdomen/tablet") != null, "spider_boss 개틀링 · 태블릿")
		var eye := s.find_child("pt_eye_l") as Node3D
		_check(eye != null and eye.global_position.z < -4.5 and eye.global_position.x < 0.0, "spider_boss 왼눈이 앞(-Z) 왼쪽(-X)")
		var weld := s.find_child("pt_torch") as Node3D
		_check(weld != null and weld.global_position.x > 0.0, "spider_boss 용접기는 오른쪽 (원화 정면의 화면 왼쪽)")
		var tablet := s.get_node_or_null("body/abdomen/tablet") as Node3D
		_check(tablet != null and tablet.global_position.y > 6.5, "spider_boss 태블릿이 뒤 몸통 위 (원화 높이 약 7m)")
		s.queue_free()

	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
