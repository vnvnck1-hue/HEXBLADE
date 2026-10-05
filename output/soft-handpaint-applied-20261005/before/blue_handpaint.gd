extends RefCounted
## 승인한 청보라 A안. 기존 메시/UV 음영 유지, 새 붓질을 월드 투영한다.
## --bgpaint=old 로 변경 전 재질 비교. 캐시는 텍스처 두 개만 보관한다.
const FLOOR_PATH := "res://assets/textures/handpaint_blue/floor_brush.png"
const WALL_PATH := "res://assets/textures/handpaint_blue/wall_brush.png"
const FLOOR_TEXTURE := preload(FLOOR_PATH)
const WALL_TEXTURE := preload(WALL_PATH)
static var enabled := not OS.get_cmdline_user_args().has("--bgpaint=old")
static var _means := {}

static func texture_for(wall: bool) -> Texture2D:
	return WALL_TEXTURE if wall else FLOOR_TEXTURE

static func mean_for(wall: bool) -> Vector3:
	var path := WALL_PATH if wall else FLOOR_PATH
	if not _means.has(path):
		# Imported texture data remains available in an exported PCK; raw source PNG does not.
		var img := texture_for(wall).get_image()
		if img.is_compressed():
			img.decompress()
		var mean := Vector3.ZERO
		for y in 32:
			for x in 32:
				var px := mini(img.get_width() - 1, int((x * 2 + 1) * img.get_width() / 64.0))
				var py := mini(img.get_height() - 1, int((y * 2 + 1) * img.get_height() / 64.0))
				var c := img.get_pixel(px, py).srgb_to_linear()
				mean += Vector3(c.r, c.g, c.b)
		_means[path] = mean / 1024.0
	return _means[path]

static func configure(mat: ShaderMaterial, wall: bool) -> void:
	mat.set_shader_parameter("handpaint", enabled)
	if enabled:
		mat.set_shader_parameter("paint_tex", texture_for(wall))
		mat.set_shader_parameter("paint_mean", mean_for(wall))
