extends SceneTree
## 필드 만화 말풍선 확인 캡처: 대사 · 감정(!! ?) 를 띄우고 (의성어 끼릭! 은 떠오르는 글자) 등장 순간을 시간별로 찍는다.
## 결과: <폴더>/pop_<ms>.png (띠용 단계) · settled.png
## 실행: powershell -File tools\godot.ps1 wait --resolution 1280x800 -s res://_capture/speech_bubble_show.gd -- --out=<폴더>

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "res://output/speech-bubble-20261005"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	var m: TrainingMain = load("res://scenes/training.tscn").instantiate()
	root.add_child(m)
	current_scene = m
	m.show_help = false
	for i in 150:
		await physics_frame
	var p := m.player
	var d := m.dummies[0] as Node3D
	var d2 := m.dummies[min(1, m.dummies.size() - 1)] as Node3D
	SpeechBubble.fixed_dt = 0.0001
	SpeechBubble.say(p, "영차!", SpeechBubble.SAY)
	SpeechBubble.say(d, "!!", SpeechBubble.EMOTE, {"life": 9.0})
	SpeechBubble.say(d2, "?", SpeechBubble.EMOTE, {"life": 9.0, "delay": 0.05})
	m.hud.popup("끼릭끼릭!", Color("ffe070"), p.global_position + Vector3(1.6, 1.2, 0))
	if PartnerDrone.inst:
		PartnerDrone.inst.bark("다녀올게요!")
	# 화면 프레임 = 1/60초로 고정해 띠용 단계를 시간별로 찍는다
	SpeechBubble.fixed_dt = 1.0 / 60.0
	var f := 0
	for fr in [1, 2, 3, 4, 6, 9, 14]:
		while f < fr:
			await process_frame
			f += 1
		root.get_viewport().get_texture().get_image().save_png(out + "/pop_%03d.png" % int(fr * 1000.0 / 60.0))
	while f < 60:
		await process_frame
		f += 1
	root.get_viewport().get_texture().get_image().save_png(out + "/settled.png")
	print("BUBBLES live=%d" % SpeechBubble.live().size())
	for b in SpeechBubble.live():
		print("B %s t=%.2f sx=%.2f sy=%.2f scale=%s vis=%s pos=%s" % [b.text, b.t, b.sx, b.sy, b.scale, b.visible, b.position])
	quit()
