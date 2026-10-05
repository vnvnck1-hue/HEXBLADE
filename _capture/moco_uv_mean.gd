extends SceneTree
## 배경 모델 텍스처의 '실제 쓰는 UV 영역' 평균 선형 휘도 (윗면 / 옆면 따로).
## 삼각형마다 면적 가중으로 6점을 텍스처에서 읽는다 (아틀라스의 빈 검은 공간은 안 읽힘).
## BrawlLook 의 벽·설비 명암 압축 기준값(WALL_DETAIL_MEAN 등)을 정할 때 쓴다.
## powershell -File tools\godot.ps1 wait --headless -s res://_capture/moco_uv_mean.gd
const KINDS := {
	"block_wall": "res://assets/models/bg_claude_block_wall.glb",
	"block_cover": "res://assets/models/bg_claude_block_cover.glb",
	"block_pillar": "res://assets/models/bg_claude_block_pillar.glb",
	"w01": "res://assets/models/bg_claude_w01.glb",
	"w01_half": "res://assets/models/bg_claude_w01_half.glb",
	"jamb": "res://assets/models/bg_claude_jamb.glb",
	"s01_vent": "res://assets/models/bg_claude_service_s01_vent.glb",
	"s02_tank": "res://assets/models/bg_claude_service_s02_tank.glb",
	"s03_pipe": "res://assets/models/bg_claude_service_s03_pipe.glb",
	"s05_column": "res://assets/models/bg_claude_service_s05_column.glb",
}
const BARY := [Vector3(1, 1, 1) / 3.0, Vector3(0.6, 0.2, 0.2), Vector3(0.2, 0.6, 0.2), Vector3(0.2, 0.2, 0.6),
		Vector3(0.45, 0.45, 0.1), Vector3(0.1, 0.45, 0.45)]


func _initialize() -> void:
	var out := {}
	for k in KINDS:
		var n := (load(KINDS[k]) as PackedScene).instantiate()
		var mi := n.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		var mat := mi.mesh.surface_get_material(0) as BaseMaterial3D
		var img := mat.albedo_texture.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBAF)
		var arr := mi.mesh.surface_get_arrays(0)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var acc := {"top": [0.0, 0.0], "side": [0.0, 0.0]}
		var w := img.get_width()
		var h := img.get_height()
		for t in range(0, idx.size(), 3):
			var a := v[idx[t]]
			var b := v[idx[t + 1]]
			var c := v[idx[t + 2]]
			var cr := (b - a).cross(c - a)
			var area := cr.length() * 0.5
			if area <= 0.0:
				continue
			var ny := absf(cr.normalized().y)
			var role := "top" if ny > 0.6 else "side"
			for bw: Vector3 in BARY:
				var u: Vector2 = uv[idx[t]] * bw.x + uv[idx[t + 1]] * bw.y + uv[idx[t + 2]] * bw.z
				var px := Vector2i(clampi(int(fposmod(u.x, 1.0) * w), 0, w - 1), clampi(int(fposmod(u.y, 1.0) * h), 0, h - 1))
				var col := img.get_pixelv(px).srgb_to_linear()
				var l := 0.2126 * col.r + 0.7152 * col.g + 0.0722 * col.b
				acc[role][0] += l * area
				acc[role][1] += area
		n.free()
		var res := {}
		for r in acc:
			res[r] = snappedf(acc[r][0] / maxf(acc[r][1], 1e-6), 0.00001)
		res.all = snappedf((acc.top[0] + acc.side[0]) / maxf(acc.top[1] + acc.side[1], 1e-6), 0.00001)
		out[k] = res
		print("UV MEAN ", k, " ", res)
	var f := FileAccess.open("res://output/moco-bg-20261004/uv_means.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	quit()
