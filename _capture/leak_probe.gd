extends SceneTree
## 누수 탐지: 한 씬을 여러 번 다시 불러오며 객체·노드·리소스·고아 노드 수를 잰다.
## 매 로드의 같은 시점(SETTLE 프레임)에 잰 값이 로드마다 늘면 씬 전환 사이에 무언가 남는 것이다.
##   godot --headless --fixed-fps 60 -s res://_capture/leak_probe.gd -- --probe=res://scenes/main.tscn --frames=900 --loads=5 --bot --capture= --seconds=9999

const SETTLE := 120
const BossTank := preload("res://scripts/boss_tank.gd")

var scene := "res://scenes/main.tscn"
var frames := 900
var loads := 5
var _f := 0
var _n := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe="):
			scene = a.substr(8)
		elif a.begins_with("--frames="):
			frames = int(a.substr(9))
		elif a.begins_with("--loads="):
			loads = int(a.substr(8))
	change_scene_to_file(scene)


func _sample(tag: String) -> void:
	print("PROBE %s load=%d f=%d obj=%d node=%d res=%d orphan=%d ts=%.2f" % [tag, _n, _f,
		Performance.get_monitor(Performance.OBJECT_COUNT),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		Engine.time_scale])
	# 정적 캐시 크기: 로드마다 늘면 실행 중 새 키가 계속 생기는 것이다
	print("CACHE lit=%d toon=%d box=%d bevel=%d cyl=%d sub=%d tank=%d/%d paint=%d/%d saber=%d decal=%d/%d wall=%d spark=%d" % [
		Pal._lit.size(), Pal._toon_mats.size(), Build._boxes.size(), Build._bevels.size(), Build._cyls.size(),
		Debris._sub_boxes.size(), BossTank._meshes.size(), BossTank._mats.size(),
		PaintedLook._mats.size(), PaintedLook._shaders.size(), SaberTrail._shaders.size(),
		MechDecals._tex.size(), MechDecals._frames.size(), WallProps._cache.size(), HitSpark._last.size()])
	print("CACHE2 spark_pm=%d ramp=%d spray=%d" % [FX._spark_pms.size(), FX._ramps.size(), GunFX._spray_pms.size()])


func _process(_dt: float) -> bool:
	_f += 1
	if _f == SETTLE:
		_sample("settle")
	if _f >= frames:
		_sample("end")
		_n += 1
		_f = 0
		if OS.get_cmdline_user_args().has("--keys"):
			print("KEYS lit ", Pal._lit.keys())
			print("KEYS box ", Build._boxes.keys())
			print("KEYS bevel ", Build._bevels.keys())
		if _n >= loads:
			Node.print_orphan_nodes()
			return true
		change_scene_to_file(scene)
	return false
