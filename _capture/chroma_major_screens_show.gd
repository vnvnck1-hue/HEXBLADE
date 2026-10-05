extends SceneTree
## 아트 컨셉 참조용 실제 씬 렌더. 게임 코드/원화는 바꾸지 않는다.
const OUT := "res://output/chroma-major-screens-20261005/sources/"
const SCENES := [
	["01_lobby", "res://scenes/lobby.tscn"],
	["02_sector_map", "res://scenes/run.tscn"],
	["03_combat", "res://scenes/main.tscn"],
	["06_forge", "res://scenes/forge.tscn"],
	["07_spider", "res://scenes/spider.tscn"],
]

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await physics_frame

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var run: Node = root.get_node("Run")
	for item in SCENES:
		run.active = false
		run.map_view.want = false
		Engine.time_scale = 1.0
		seed(4)
		var scene: Node = (load(item[1]) as PackedScene).instantiate()
		root.add_child(scene)
		current_scene = scene
		await _frames(150)
		await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var result := img.save_png(OUT + String(item[0]) + ".png")
		print("ART_SOURCE name=%s scene=%s size=%s save=%s" % [item[0], item[1], img.get_size(), result])
		if String(item[0]) == "02_sector_map":
			run.map_view.want = false
			await _frames(45)
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUT + "02_sector_portals.png")
		run.active = false
		run.map_view.want = false
		scene.queue_free()
		await _frames(8)
	quit()
