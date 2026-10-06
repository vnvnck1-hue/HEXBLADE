class_name HitSpark
extends RefCounted
## 적 피격 섬광 (연출 전용). 기본총 예광탄과 같은 납작한 방추(비행접시) 모양을 ToonGunFX 로 겹쳐 띄운다.
## 외곽선 없이 주황 몸체 + 뜨거운 노랑·흰 심지로, 총구 화염·예광·착탄과 같은 결로 그린다.
##  비행접시   맞은 방향에 가로로 누운 넓적한 방추가 번쩍 펴졌다가 가늘어진다 (안쪽에 더 작고 뜨거운 방추)
##  잔물결     한 박자 늦게 더 얇은 방추가 옆으로 길게 퍼져 나간다
##  관통 방추  맞은 방향으로 탄이 꿰뚫고 지나가듯 짧은 방추
##  방추 불똥  작은 방추들이 맞은 쪽 반구로 튀며 날아가는 방향으로 늘어난다
## 밝기는 예광탄보다 낮게(1.1~1.35) 잡아 화면 글로우가 번지지 않고 모양이 또렷하게 남게 한다.

## SPINDLE 의 폭은 size.x 의 약 0.26 배라, size.x 를 길이(size.y)와 비슷하게 주면 폭:길이 ≈ 0.3 의 납작한 렌즈가 된다.
const MIN_GAP := 0.045          # 같은 적이 연사로 맞을 때 이보다 촘촘하게는 새로 띄우지 않는다
const PULL := 0.7               # 기체에 파묻히지 않게 카메라 쪽으로 띄우는 거리 (m)

static var _last := {}


## pos: 맞은 지점 · dir: 맞은 방향(월드) · k: 세기 (총알 1, 검·강공격일수록 크게) · key: 연사 간격 판정용(맞은 적)
## heavy: 강타 분류 (1 강타 · 0 일반 · -1 = k 로 추정). mo.co 무드(MocoFX.on)면 MocoFX 프리셋으로 그린다.
## source: 피해 원천 ("bullet" · "slash" …). MISFITZ 버스트는 원거리(MisfitzHit.RANGED)면 노랑, 나머지는 보라
static func spawn(pos: Vector3, dir: Vector3, k := 1.0, key: Object = null, heavy := -1, source := "") -> void:
	if MocoFX.on:
		var m := MocoFX.get_inst()
		if m:
			var w := 1.24
			if key is Enemy:
				w = (key as Enemy).radius * 2.0
			m.hit(pos, dir, w, heavy == 1 or (heavy < 0 and k >= 1.6), k, key, source)
		return
	var g := ToonGunFX.inst
	if g == null or not is_instance_valid(g) or not g.is_inside_tree():
		return
	if key != null:
		var now := Time.get_ticks_msec() * 0.001
		var id := key.get_instance_id()
		if now - float(_last.get(id, -1.0)) < MIN_GAP:
			return
		_last[id] = now
		if _last.size() > 64:
			_last.clear()
	var f := Vector3(dir.x, 0, dir.z)
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	f = f.rotated(Vector3.UP, randf_range(-0.12, 0.12))
	var side := f.cross(Vector3.UP).normalized()
	var at := pos
	var cam := g.get_viewport().get_camera_3d()
	if cam:
		at = pos + (cam.global_position - pos).normalized() * PULL
	var s := sqrt(k)
	var tilt := side.rotated(f, randf_range(-0.18, 0.18))

	# 비행접시: 가로로 누운 넓적한 방추 + 안쪽의 작고 뜨거운 방추
	g.spawn(ToonGunFX.SPINDLE, at, 0.09, 0, Vector2(1.7, 1.5) * s * randf_range(0.9, 1.1),
		ToonGunFX.ORANGE, 1.25, tilt, {"tint2": ToonGunFX.HOT})
	g.spawn(ToonGunFX.SPINDLE, at, 0.06, 0, Vector2(1.05, 0.9) * s,
		ToonGunFX.AMBER, 1.35, tilt, {"tint2": ToonGunFX.WHITE})
	# 잔물결: 한 박자 늦게 더 얇고 길게 옆으로 퍼진다
	g.spawn(ToonGunFX.SPINDLE, at, 0.1, 0, Vector2(0.75, 1.5) * s,
		ToonGunFX.ORANGE, 1.1, -tilt, {"tint2": ToonGunFX.AMBER, "grow": 5.0, "delay": 0.035})
	# 관통 방추: 맞은 방향으로 짧게 꿰뚫는다
	g.spawn(ToonGunFX.SPINDLE, at + f * 0.2 * s, 0.07, 0, Vector2(0.8, 0.85) * s,
		ToonGunFX.AMBER, 1.3, f, {"tint2": ToonGunFX.HOT})
	# 방추 불똥: 맞은 쪽 반구로 튀고, 날아가는 방향으로 늘어난다
	for i in randi_range(4, 6):
		var a := (f * randf_range(0.2, 1.0) + side * randf_range(-1.1, 1.1) + Vector3(0, randf_range(0.1, 0.9), 0)).normalized()
		g.spawn(ToonGunFX.SPINDLE, at + a * 0.2 * s, randf_range(0.11, 0.17), 0,
			Vector2(randf_range(0.42, 0.55), randf_range(0.36, 0.52)) * s,
			ToonGunFX.ORANGE if randf() < 0.6 else ToonGunFX.AMBER, randf_range(1.15, 1.35), a,
			{"tint2": ToonGunFX.HOT, "vel": a * randf_range(6.0, 9.0) * s, "drag": 9.0})
