extends Node3D
## Standalone material bench. Imported meshes and game materials are never edited.
## The saved scene contains the actual game assets, so layout is editable in Godot.

@export_group("시험 텍스처 (비워 두면 본편 재질)")
@export var floor_texture: Texture2D
@export var wall_texture: Texture2D
@export var prop_texture: Texture2D
@export var machinery_texture: Texture2D
@export_range(0.25, 4.0, 0.25) var texture_repeat := 1.0
@export var world_projection := true
@export_range(0.0, 1.0, 0.05) var preview_roughness := 0.85
@export_range(0.0, 1.0, 0.05) var preview_metallic := 0.0

const CATEGORY_NAMES := ["바닥 · 상부 / 설비실", "벽 · 엄폐물 / 기둥", "프랍 · 작업대 / 벽 설비", "설비 · 탱크 / 배관"]
const CATEGORY_NODES := ["Floors", "Walls", "Props", "Machinery"]
const VIEW_NAMES := ["전체", "바닥", "벽", "프랍", "설비"]
const VIEW_TARGETS := [Vector3(0, 0.7, 0.7), Vector3(0, 0, 0.3), Vector3(0, 1.5, -3), Vector3(-0.3, 1.5, -2.5), Vector3(0, -0.1, 4)]
const VIEW_ANGLES := [Vector2(32, 38), Vector2(0, 78), Vector2(5, 12), Vector2(22, 22), Vector2(20, 40)]
const VIEW_SIZES := [13.2, 10.4, 10.5, 9.4, 8.4]
const OUTPUT := "res://output/texture-diorama"

@onready var camera: Camera3D = $Camera3D
@onready var environment: Environment = $WorldEnvironment.environment
@onready var sun: DirectionalLight3D = $Sun

var surfaces: Array[Dictionary] = []
var settings: Array[Dictionary] = []
var selected := 0
var reference := false
var light_mode := 0
var view_mode := 0
var target := Vector3.ZERO
var angles := Vector2.ZERO
var span := 11.8
var ui: CanvasLayer
var status: Label
var source_label: Label
var category_select: OptionButton
var projection_select: OptionButton
var light_select: OptionButton
var compare_button: Button
var repeat_slider: HSlider
var rough_slider: HSlider
var metal_slider: HSlider
var file_dialog: FileDialog
var file_category := 0
var _syncing := false
var _checker: Texture2D
var _bot := false
var _seconds := -1.0
var _elapsed := 0.0
var _bot_step := -1
var _capture_dir := ""

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_collect_surfaces()
	var textures := [floor_texture, wall_texture, prop_texture, machinery_texture]
	for tex in textures:
		settings.append({"texture": tex, "source": tex.resource_path if tex else "본편 재질", "world": world_projection, "repeat": texture_repeat, "rough": preview_roughness, "metal": preview_metallic})
	_build_ui()
	get_viewport().size_changed.connect(_update_camera)
	set_view(0)
	set_light(0)
	apply_materials()
	for arg in OS.get_cmdline_user_args():
		if arg == "--bot":
			_bot = true
		elif arg.begins_with("--seconds="):
			_seconds = float(arg.trim_prefix("--seconds="))
		elif arg.begins_with("--capture="):
			_capture_dir = arg.trim_prefix("--capture=")
	if _bot and _seconds < 0:
		_seconds = 12.0
	print("TEXTURE_DIORAMA_READY surfaces=%d categories=4" % surfaces.size())

func _collect_surfaces() -> void:
	for group in CATEGORY_NODES.size():
		var parent := get_node("Diorama/" + CATEGORY_NODES[group])
		for mi: MeshInstance3D in parent.find_children("*", "MeshInstance3D", true, false):
			for surface in mi.mesh.get_surface_count():
				var source := mi.get_active_material(surface)
				var original: Material = source
				if group == 0:
					if mi.name == "ServiceDeck":
						original = ClaudeServiceDress.floor_material().duplicate()
					else:
						# The saved floor modules begin at (-4, -3); match their 2m seam phase.
						original = BrawlLook._floor_for(ClaudeBgDress.floor_material(Vector2(0, 1))).duplicate()
				elif source is BaseMaterial3D and BrawlLook.convertible(source):
					var role := BrawlLook.R_WALL if group == 1 else (BrawlLook.R_SERVICE if group == 3 else BrawlLook.R_WORLD)
					# Clone before material_for: its cached metadata belongs to this scene only.
					var copied_source := source.duplicate() as BaseMaterial3D
					# A visit from the main game can bring cached role materials in metadata.
					# Discard the copied cache so temporary always belongs to this scene.
					for key in copied_source.get_meta_list():
						if str(key).begins_with("bl_"):
							copied_source.remove_meta(key)
					var temporary := BrawlLook.material_for(copied_source, role)
					original = temporary.duplicate()
					# This scene has no player light pool. Remove only our temporary registration
					# so repeated lobby visits do not leave dead keys in the global registry.
					BrawlLook._pool_mats.erase(temporary.get_instance_id())
				if original is ShaderMaterial:
					original.set_shader_parameter("pool_use", 0.0)
				surfaces.append({"mesh": mi, "surface": surface, "group": group, "original": original, "preview": StandardMaterial3D.new()})

func apply_materials() -> void:
	for entry in surfaces:
		var state: Dictionary = settings[entry.group]
		var material: Material = entry.original
		if not reference and state.texture != null:
			var preview: StandardMaterial3D = entry.preview
			preview.albedo_texture = state.texture
			preview.albedo_color = Color.WHITE
			preview.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			preview.uv1_triplanar = state.world
			preview.uv1_world_triplanar = state.world
			preview.uv1_scale = Vector3.ONE * state.repeat
			preview.roughness = state.rough
			preview.metallic = state.metal
			material = preview
		var mi: MeshInstance3D = entry.mesh
		mi.set_surface_override_material(entry.surface, material)
	_update_status()

func set_texture(group: int, tex: Texture2D, label_text := "시험 텍스처") -> void:
	settings[group].texture = tex
	settings[group].source = label_text
	reference = false
	apply_materials()

func reset_category() -> void:
	settings[selected].texture = null
	settings[selected].source = "본편 재질"
	apply_materials()

func toggle_reference() -> void:
	reference = not reference
	apply_materials()

func checker_texture() -> Texture2D:
	if _checker == null:
		var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
		for y in 256:
			for x in 256:
				var odd := (x / 32 + y / 32) % 2 == 0
				image.set_pixel(x, y, Color("ccd5db") if odd else Color("394551"))
		image.generate_mipmaps()
		_checker = ImageTexture.create_from_image(image)
	return _checker

func load_texture_file(path: String) -> bool:
	var image := Image.new()
	var error := image.load(path)
	if error != OK:
		source_label.text = "이미지를 열 수 없습니다: " + error_string(error)
		return false
	image.generate_mipmaps()
	set_texture(file_category, ImageTexture.create_from_image(image), path.get_file())
	return true

func set_view(index: int) -> void:
	view_mode = index
	if index > 0:
		selected = index - 1
		category_select.select(selected)
	target = VIEW_TARGETS[index]
	angles = VIEW_ANGLES[index]
	span = VIEW_SIZES[index]
	_update_camera()
	_update_status()

func _update_camera() -> void:
	var yaw := deg_to_rad(angles.x)
	var pitch := deg_to_rad(angles.y)
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * 24.0
	camera.size = span
	# Reserve screen space for the panel without changing the inspectable geometry.
	camera.h_offset = span * 145.0 / get_viewport().get_visible_rect().size.y if ui.visible else 0.0
	camera.v_offset = 0.25
	camera.look_at(target)

func set_light(index: int) -> void:
	light_mode = index
	environment.adjustment_enabled = index == 1
	environment.adjustment_contrast = 1.03
	environment.adjustment_brightness = 1.02
	environment.glow_enabled = index == 1
	if index == 1:
		environment.ambient_light_color = BrawlLook.AMBIENT
		environment.ambient_light_energy = BrawlLook.AMBIENT_ENERGY
		sun.rotation_degrees = BrawlLook.SUN_ROT
		sun.light_color = BrawlLook.SUN_COLOR
		sun.light_energy = BrawlLook.SUN_ENERGY
		sun.shadow_opacity = BrawlLook.SHADOW_OPACITY
	else:
		environment.ambient_light_color = Color.WHITE
		environment.ambient_light_energy = 0.65 if index == 0 else 0.3
		sun.rotation_degrees = Vector3(-50, -30, 0) if index == 0 else Vector3(-18, -65, 0)
		sun.light_color = Color.WHITE
		sun.light_energy = 1.0
		sun.shadow_opacity = 0.65
	if light_select:
		light_select.select(index)
	_update_status()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5: set_view(event.physical_keycode - KEY_1)
			KEY_L: set_light((light_mode + 1) % 3)
			KEY_B: toggle_reference()
			KEY_R: reset_category()
			KEY_F: set_view(view_mode)
			KEY_TAB:
				ui.visible = not ui.visible
				_update_camera()
			KEY_F12: save_capture(OUTPUT + "/preview.png")
			KEY_ESCAPE: Lobby.back(get_tree())
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			span = maxf(2.0, span * 0.9)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			span = minf(24.0, span / 0.9)
		_update_camera()
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			angles.x -= event.relative.x * 0.35
			angles.y = clampf(angles.y + event.relative.y * 0.3, 5, 85)
		elif event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			target += (-camera.global_basis.x * event.relative.x + camera.global_basis.y * event.relative.y) * span / get_viewport().get_visible_rect().size.y
		_update_camera()

func _process(dt: float) -> void:
	_elapsed += dt
	if _bot:
		var step := mini(int(_elapsed / 1.5), 7)
		if step != _bot_step:
			_bot_step = step
			if step < 5:
				set_view(step)
				set_light(step % 3)
				if not _capture_dir.is_empty():
					save_capture(_capture_dir.path_join("%02d_%s.png" % [step + 1, ["overview", "floor", "wall", "props", "machinery"][step]]))
			elif step == 5:
				for group in 4:
					set_texture(group, checker_texture(), "체커 검사")
				set_view(0)
			elif step == 6:
				toggle_reference()
			else:
				toggle_reference()
				for group in 4:
					settings[group].texture = null
				apply_materials()
			print("TEXTURE_DIORAMA_BOT step=%d view=%d light=%d reference=%s" % [step, view_mode, light_mode, reference])
	if _seconds >= 0 and _elapsed >= _seconds:
		print("TEXTURE_DIORAMA_OK elapsed=%.2f" % _elapsed)
		get_tree().quit()

func save_capture(path: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var directory := ProjectSettings.globalize_path(path.get_base_dir())
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		push_error("Capture directory: " + error_string(error))
		return
	var ignore := directory.path_join(".gdignore")
	if not FileAccess.file_exists(ignore):
		var file := FileAccess.open(ignore, FileAccess.WRITE)
		file.close()
	error = get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	if error != OK:
		push_error("Capture: " + error_string(error))
	else:
		print("TEXTURE_DIORAMA_CAPTURE " + path)

func _button(parent: Node, text_: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text_
	button.custom_minimum_size.y = 28
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _label(parent: Node, text_: String, size := 14) -> Label:
	var label := Label.new()
	label.text = text_
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _slider(parent: Node, title: String, low: float, high: float, step: float, key: String) -> HSlider:
	_label(parent, title)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.custom_minimum_size.y = 18
	parent.add_child(slider)
	slider.value_changed.connect(func(value: float):
		if not _syncing:
			settings[selected][key] = value
			apply_materials())
	return slider

func _build_ui() -> void:
	ui = CanvasLayer.new()
	add_child(ui)
	var header := VBoxContainer.new()
	header.position = Vector2(28, 22)
	ui.add_child(header)
	_label(header, "HEXBLADE  /  MATERIAL LAB", 24)
	_label(header, "텍스처링 디오라마   ·   8 × 8 m 정비실   /   실제 게임 자산", 16)
	status = _label(header, "", 14)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -290
	panel.offset_right = -20
	panel.offset_top = 115
	ui.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("19202ded")
	style.border_color = Color("394958")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_label(box, "표면 테스트", 20)
	category_select = OptionButton.new()
	for name_ in CATEGORY_NAMES:
		category_select.add_item(name_)
	box.add_child(category_select)
	category_select.item_selected.connect(func(index: int):
		selected = index
		_update_status())
	source_label = _label(box, "")
	source_label.custom_minimum_size.x = 230
	source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(box, "텍스처 파일 열기…", func():
		file_category = selected
		file_dialog.popup_centered_ratio(0.7))
	_button(box, "체커 패턴으로 투영 확인", func(): set_texture(selected, checker_texture(), "체커 검사"))
	projection_select = OptionButton.new()
	projection_select.add_item("월드 삼면 투영 · 1m 반복")
	projection_select.add_item("모델 원래 UV · 아틀라스")
	box.add_child(projection_select)
	projection_select.item_selected.connect(func(index: int):
		settings[selected].world = index == 0
		apply_materials())
	repeat_slider = _slider(box, "반복 배율  ·  0.25 ~ 4", 0.25, 4, 0.25, "repeat")
	rough_slider = _slider(box, "거칠기  ·  0 ~ 1", 0, 1, 0.05, "rough")
	metal_slider = _slider(box, "금속성  ·  0 ~ 1", 0, 1, 0.05, "metal")
	_label(box, "시험 재질이 있을 때 위 값 적용", 12)
	compare_button = _button(box, "", toggle_reference)
	_button(box, "선택 표면 원복  [R]", reset_category)
	_label(box, "조명  [L]", 16)
	light_select = OptionButton.new()
	for name_ in ["중립 · 흰색 조명", "게임 · 본편 조명", "측광 · 요철 / 거칠기"]:
		light_select.add_item(name_)
	box.add_child(light_select)
	light_select.item_selected.connect(set_light)
	_label(box, "고정 시점  [1~5]", 16)
	var row := HBoxContainer.new()
	box.add_child(row)
	for index in 5:
		_button(row, str(index + 1), set_view.bind(index)).tooltip_text = VIEW_NAMES[index]
	_button(box, "화면 저장  [F12]", save_capture.bind(OUTPUT + "/preview.png"))
	var footer := Label.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.offset_left = 28
	footer.offset_top = -57
	footer.offset_right = 920
	footer.offset_bottom = -18
	footer.text = "우드래그 회전  ·  휠 확대  ·  가운데 드래그 이동  ·  F 시점 복구\nB 원본 비교  ·  Tab UI 숨김  ·  Esc 로비"
	ui.add_child(footer)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp; 이미지 텍스처"])
	file_dialog.title = "시험할 텍스처 선택"
	file_dialog.file_selected.connect(load_texture_file)
	ui.add_child(file_dialog)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Noto Sans CJK KR", "sans-serif"])
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 14
	for control: Control in [header, panel, footer]:
		control.theme = theme
	file_dialog.theme = theme

func _update_status() -> void:
	if status == null or settings.is_empty():
		return
	var mode := "본편 재질"
	if reference:
		mode = "원본 비교"
	elif settings.any(func(state: Dictionary): return state.texture != null):
		mode = "시험 재질"
	status.text = "%s 시점   /   %s   /   %s" % [VIEW_NAMES[view_mode], ["중립 조명", "본편 조명", "측광"][light_mode], mode]
	var state: Dictionary = settings[selected]
	source_label.text = "%s\n반복 %.2f  ·  거칠기 %.2f  ·  금속 %.2f" % [state.source, state.repeat, state.rough, state.metal]
	compare_button.text = "시험 재질 보기  [B]" if reference else "본편 원본 비교  [B]"
	_syncing = true
	repeat_slider.value = state.repeat
	rough_slider.value = state.rough
	metal_slider.value = state.metal
	projection_select.select(0 if state.world else 1)
	_syncing = false
