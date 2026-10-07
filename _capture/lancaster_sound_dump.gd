extends SceneTree
## LANCASTER 기계음(LancasterSound)을 WAV 로 저장 — 귀로 확인용.
## powershell -File tools\godot.ps1 wait --headless -s res://_capture/lancaster_sound_dump.gd -- --out=DIR

var out := "res://output/lancaster-intro-20261007/sounds"


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	LancasterSound.ensure()
	for id in ["lan_servo", "lan_step", "lan_crush", "lan_hiss", "lan_clack", "lan_hum", "lan_alarm"]:
		var w: AudioStreamWAV = Sfx._cache[id]
		w.save_to_wav(ProjectSettings.globalize_path(out.path_join(id + ".wav")))
		var peak := 0
		var data := w.data
		for i in range(0, data.size(), 2):
			peak = maxi(peak, absi(data.decode_s16(i)))
		print("%s  %.2fs  peak %.2f" % [id, data.size() / 2.0 / w.mix_rate, peak / 32000.0])
	quit()
