extends SceneTree
## 캡처: 본선 boss.tscn 에서 기본총만 쏘는 장면 (총구 화염 · 예광 · 보스 착탄). 패턴·궁극기·충전 없음.
## 실행: tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/boss_gun_show.gd -- --bot --godmode [--viewk=1]
const BossEnemy := preload("res://scripts/boss_enemy.gd")
var out := "output/mammoth-ingame-20261001"
var _o := ""
var tag := "g_gun"
var f := 0
var t0 := -1.0
var main: Main
var vk := -1.0

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a.begins_with("--viewk="):
			vk = float(a.substr(8))
			tag = "g_gun_vk%s" % a.substr(8)
	main = load("res://scenes/boss.tscn").instantiate()
	root.add_child(main)
	current_scene = main

func _process(dt: float) -> bool:
	f += 1
	var boss: BossEnemy = main.get("boss")
	if boss == null or boss.st != BossEnemy.St.FIGHT:
		return false
	if t0 < 0.0:
		t0 = main.time
		if vk > 0.0:
			ToonGunFX.inst.view_k = vk
	boss.rest = 99.0
	main.player.missiles = 0
	main.time = 1.0 + fmod(main.time, 1.0) * 0.0
	var e := f
	if f % 3 == 0 and main.player.global_position.z > boss.global_position.z:
		root.get_viewport().get_texture().get_image().save_png("res://%s/%s_%04d.png" % [out, tag, f])
	return f > 400
