class_name HangarBackdrop
extends Control
## 포트레이트 뒤의 이미지 배경. 원화의 낮은 채도/명도를 그대로 유지한다.
## 화면 비율이 달라도 늘이거나 빈 띠를 만들지 않고 중앙 기준으로 잘라 채운다.

const HANGAR := preload("res://assets/ui/dialogue_backgrounds/blue_service_hangar.png")
const BRIEFING := preload("res://assets/ui/dialogue_backgrounds/dusty_brick_briefing_room.png")

var location_id := "hangar"
var image: TextureRect


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	image = TextureRect.new()
	image.name = "BackgroundImage"
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(image)
	_apply_texture()


func select_for_script(script_id: String) -> void:
	# 제목은 한 대본 안에서도 바뀌므로 장소 선택에는 대본 ID만 사용한다.
	location_id = "briefing" if script_id in ["hangar_briefing", "feature_demo"] else "hangar"
	if image:
		_apply_texture()


func _apply_texture() -> void:
	image.texture = BRIEFING if location_id == "briefing" else HANGAR
