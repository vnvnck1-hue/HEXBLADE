extends SceneTree
## 승인한 청보라 재질이 실제 방/블록/파괴 조각에 연결되고 캐릭터에 새지 않는지 확인.
const PAINT := preload("res://scripts/claude_background/blue_handpaint.gd")
var fails := 0
var main: Main

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool, label_: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + label_)
	if not ok:
		fails += 1

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	for wall in [false, true]:
		var tex := PAINT.texture_for(wall)
		var img := tex.get_image()
		_check(tex.get_width() >= 1024 and tex.get_height() >= 1024, "실제 붓질 리소스 해상도 >=1024 (wall=%s)" % wall)
		_check(img.has_mipmaps(), "3D 미프맵 포함 (wall=%s)" % wall)
		var mean := PAINT.mean_for(wall)
		_check(mean.x > 0.01 and mean.y > 0.01 and mean.z > mean.x, "내보내기 가능한 임포트 데이터에서 청보라 평균 읽기")
	BrawlLook.on = true
	PaintedLook.game_preset = PaintedLook.NONE
	var wall_count := 0
	var floor_count := 0
	for k in 3:
		main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Main
		main.map_seed = 4
		root.add_child(main)
		current_scene = main
		await _frames(15)
		main.player.invuln = 999.0
		for mi: MeshInstance3D in main.map.find_children("*", "MeshInstance3D", true, false):
			var sm := mi.material_override as ShaderMaterial
			if sm and sm.shader == BrawlLook._shaders.get("floor"):
				floor_count += 1
				_check((sm.get_shader_parameter("handpaint") == true) == PAINT.enabled, "방 바닥 선택한 재질 적용")
				if PAINT.enabled:
					_check(sm.get_shader_parameter("paint_tex") == PAINT.texture_for(false), "새 바닥 붓질 리소스 직접 사용")
					_check((sm.get_shader_parameter("floor_direct") == true) == PAINT.direct_floor, "승인 PNG 직접 투영 / 직전 붓 혼합 비교 분기")
					_check(is_equal_approx(float(sm.get_shader_parameter("lift")), PAINT.FLOOR_LIFT if PAINT.direct_floor else 0.82), "기존 바닥 톤에 맞춘 밝기 배율")
				if mi.get_parent() == main.map:
					var phase: Vector2 = sm.get_shader_parameter("offset")
					var bounds := mi.global_transform * mi.get_aabb()
					_check(posmod(roundi(bounds.position.x - phase.x), 2) == 0 and posmod(roundi(bounds.position.z - phase.y), 2) == 0, "2m 줄눈 방 경계 위상 유지")
		for mm: MultiMeshInstance3D in main.map.find_children("*", "MultiMeshInstance3D", true, false):
			var sm := mm.material_override as ShaderMaterial
			if not sm:
				continue
			if str(mm.get_meta("claude_bg", "")).begins_with("blocks_"):
				wall_count += 1
				_check((sm.get_shader_parameter("handpaint") == true) == PAINT.enabled, "낮은벽/엄폐/기둥에 선택한 재질")
				_check(sm.get_shader_parameter("albedo_tex") != null, "원래 벽 UV 아틀라스의 베벨·볼트 음영 보존")
			elif mm.has_meta("claude_service"):
				_check(sm.get_shader_parameter("handpaint") != true, "외부 설비 재질 보존")
		for mi: MeshInstance3D in main.player.find_children("*", "MeshInstance3D", true, false):
			var sm := mi.material_override as ShaderMaterial
			if sm:
				_check(sm.get_shader_parameter("handpaint") != true, "플레이어는 배경 붓질 영향 없음")
		if k == 0:
			GroundBreak.burst(main.player.global_position, 0.6, Vector3.FORWARD, "crumble")
			await _frames(1)
			_check(is_instance_valid(GroundBreak.inst) and not GroundBreak.inst.bursts.is_empty(), "현재 바닥 위 파괴 연출 생성")
			if is_instance_valid(GroundBreak.inst) and not GroundBreak.inst.bursts.is_empty():
				var burst: GroundBreak.Burst = GroundBreak.inst.bursts[0]
				var material := burst.fmat as ShaderMaterial
				_check(material != null and (material.get_shader_parameter("handpaint") == true) == PAINT.enabled, "바닥 파괴도 선택한 바닥 재질 상속")
				if material != null and PAINT.enabled:
					_check(material.get_shader_parameter("paint_tex") == PAINT.texture_for(false) and (material.get_shader_parameter("floor_direct") == true) == PAINT.direct_floor, "파괴 조각도 승인 PNG 직접 투영 상속")
		main.queue_free()
		await _frames(5)
	_check(floor_count > 0 and wall_count > 0, "본편에 실제 방 바닥·블록 검증 대상 존재")
	_check(PAINT._means.size() == 2, "씬3회 로드 뒤 고정 평균 캐시2개")
	print("RESULT %s (%d fails)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(1 if fails else 0)
