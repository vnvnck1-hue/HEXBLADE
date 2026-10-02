extends SceneTree
## 새 메카 플레이어 어댑터(MechPlayer)가 기존 관절 계약을 채우고, 원본 외피를 줄이지 않으며, 총구·발·부스터가 제자리인지 본다.
var fails := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		fails += 1
		print("FAIL " + message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var body := Node3D.new()
	root.add_child(body)
	var j := MechPlayer.build(body)
	await process_frame
	for k in ["legs", "upper", "torso", "hip_l", "hip_r", "knee_l", "knee_r", "foot_l", "foot_r",
			"arm_l", "arm_r", "shoulder_l", "shoulder_r", "muzzle", "blade", "jet_l", "jet_r", "gun"]:
		check(j.get(k) is Node3D, "contract node " + k)
	for k in ["arm_base", "arm_tip_l", "arm_tip_r", "leg_trail"]:
		check(j.has(k), "contract value " + k)
	# 조준 yaw 는 거울 밖에서 돈다: Upper/Legs 는 거울이 아니다
	check((j.upper as Node3D).global_basis.determinant() > 0.0, "upper is not mirrored")
	check((j.legs as Node3D).global_basis.determinant() > 0.0, "legs are not mirrored")
	# 원본 외피: 전역 배율 1, 반전되지 않은 모습
	var shells := 0
	for mi in body.find_children("*_original", "MeshInstance3D", true, false):
		var b := (mi as MeshInstance3D).global_basis
		shells += 1
		check(b.determinant() > 0.0 and b.get_scale().is_equal_approx(Vector3.ONE), "shell keeps original scale: " + mi.name)
	check(shells >= 20, "original shells attached (%d)" % shells)
	# 총은 화면 오른쪽(+X), 총구는 정면 수평
	var mz := j.muzzle as Node3D
	var fwd := -mz.global_basis.z.normalized()
	check(mz.global_position.x > 0.3 and mz.global_position.z < -0.4, "muzzle on the gun side in front")
	check(fwd.dot(Vector3.FORWARD) > 0.99, "barrel points forward")
	# 발 기준점: Player._update_rush 의 오프셋을 빼면 발바닥(지면)
	for s in ["l", "r"]:
		var f := (j["foot_" + s] as Node3D).to_global(Vector3(0, -0.12, -0.05))
		check(absf(f.y) < 0.01, "foot sole on ground " + s)
	check((j.foot_l as Node3D).global_position.x > 0.0, "foot_l is the gun-side leg (+X)")
	# 팔 회전이 실제 외피를 움직인다 (예전 계약대로 arm_r 가 검 팔)
	var tip := (j.blade as Node3D).to_global(Vector3(0, 0, -1.3))
	(j.arm_r as Node3D).rotation.y = 1.0
	check(tip.distance_to((j.blade as Node3D).to_global(Vector3(0, 0, -1.3))) > 0.3, "arm_r swings the blade")
	# 발목 보정: 허벅지·무릎을 굽혀도 발이 거의 수평
	(j.hip_l as Node3D).rotation.x = 0.6
	(j.knee_l as Node3D).rotation.x = -0.9
	MechPlayer.settle(j)
	var up := (j.foot_l as Node3D).global_basis.y.normalized()
	check(up.dot(Vector3.UP) > 0.99, "ankle keeps the sole level")
	body.free()
	print("RESULT mech_player_check fails=%d" % fails)
	quit(1 if fails else 0)
