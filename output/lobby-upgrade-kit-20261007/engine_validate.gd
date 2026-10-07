extends SceneTree
## Offline asset decode check only. No scene change, import or gameplay code modification.
func _initialize() -> void:
	var base := "res://output/lobby-upgrade-kit-20261007/"
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + "manifest.json"))
	var checked := 0
	var failed := 0
	for entry: Dictionary in manifest.files:
		var image := Image.new()
		var result := image.load(base + str(entry.path))
		var expected: Array = entry.size
		if result != OK or image.get_width() != int(expected[0]) or image.get_height() != int(expected[1]):
			push_error("LOBBY_ASSET_FAIL: %s error=%d" % [entry.path, result])
			failed += 1
		else:
			checked += 1
	print("LOBBY_ASSETS_CHECK: %d loaded, %d failed; engine=%s" % [checked, failed, Engine.get_version_info().string])
	quit(0 if failed == 0 else 1)
