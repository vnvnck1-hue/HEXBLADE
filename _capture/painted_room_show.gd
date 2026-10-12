extends SceneTree
const SCENE := preload("res://scenes/painted_room_study.tscn")
const OUT := "res://output/painted-room-muted-20261012"
var studio

func _initialize() -> void:
	_run.call_deferred()

func shot(name_: String) -> void:
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + "/" + name_ + ".png"))
	assert(error == OK)
	print("PAINTED_ROOM_SHOT ", name_)

func _run() -> void:
	studio = SCENE.instantiate()
	root.add_child(studio)
	await process_frame
	root.size = Vector2i(1600, 1000)
	studio.ui.visible = false
	studio.set_view(0)
	studio.set_light(0)
	await shot("01_after_neutral")
	studio.toggle_reference()
	await shot("02_before_neutral")
	studio.toggle_reference()
	studio.set_light(1)
	await shot("03_after_game_light")
	studio.toggle_reference()
	await shot("04_before_game_light")
	studio.toggle_reference()
	studio.set_light(0)
	studio.toggle_raw_color()
	await shot("05_corrected_color")
	studio.toggle_raw_color()
	studio.set_view(1)
	await shot("06_floor_top")
	studio.set_view(2)
	await shot("07_wall_front")
	studio.set_view(0)
	studio.angles.x = -70
	studio.angles.y = 27
	studio._update_camera()
	await shot("08_reverse_angle")
	studio.set_view(0)
	studio.ui.visible = true
	studio._update_camera()
	await shot("09_controls")
	studio.ui.visible = false
	studio._update_camera()
	studio.toggle_props()
	await shot("10_floor_wall_only")
	studio.set_palette(1.0, 1.0)
	await shot("15_previous_bright_floor_wall")
	studio.set_palette(studio.MUTED_SATURATION, studio.MUTED_BRIGHTNESS)
	studio.toggle_reference()
	await shot("11_original_floor_wall_only")
	studio.toggle_reference()
	studio.toggle_props()
	studio.ui.visible = true
	root.size = Vector2i(1280, 800)
	studio._update_camera()
	await shot("12_controls_1280")
	print("PAINTED_ROOM_RENDER_OK")
	quit()
