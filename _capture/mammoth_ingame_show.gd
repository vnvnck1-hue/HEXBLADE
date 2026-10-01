extends SceneTree
## 캡처: 본선 boss.tscn 에서 기본총 착탄 · 왼쪽 충전 레이저 들림 · 격파 죽음 연출을 연속으로 찍는다.
## 실행: tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/mammoth_ingame_show.gd -- --bot --godmode --out=output/폴더
const BossEnemy := preload("res://scripts/boss_enemy.gd")

var out := "output/mammoth-ingame-20261001"
var f := 0
var t := 0.0
var fight_t := -1.0
var step := 0
var main: Main
var shots := {}


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out))
	main = load("res://scenes/boss.tscn").instantiate()
	root.add_child(main)
	current_scene = main


func _save(tag: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("res://%s/%s_%04d.png" % [out, tag, f])


func _process(dt: float) -> bool:
	t += dt
	f += 1
	var boss: BossEnemy = main.get("boss")
	if boss == null:
		return false
	if fight_t < 0.0 and boss.st == BossEnemy.St.FIGHT:
		fight_t = t
		boss.rest = 2.5
	if fight_t < 0.0:
		return false
	var e := t - fight_t
	var pl := main.player
	if e > 1.0 and e < 2.6 and f % 6 == 0:
		_save("a_gun")
	if e > 2.6 and step == 0:
		step = 1
		boss.rest = 99.0
		boss._abort_pattern()
		for b in get_nodes_in_group("enemy_bullets"):
			b.queue_free()
		pl.global_position = boss.global_position + Vector3(-6.5, 0, 8.5)
	if step == 1 and e > 3.0:
		step = 2
		pl.aim_point = boss.global_position + Vector3(-1.5, 0.95, 0)
		pl._fire_laser(1.0)
	if step == 2 and e < 4.4 and f % 2 == 0:
		_save("b_lift")
	if step == 2 and e > 4.6:
		step = 3
		pl.global_position = boss.global_position + Vector3(2.0, 0, 8.0)
		boss.phase = 2
		boss.boss_hp = 1.0
		boss.take_hit(5, Vector3(0, 0, -1), boss.global_position + Vector3(0, 1, 3.4), "bullet")
	if step == 3 and f % 4 == 0:
		_save("c_death")
	if step == 3 and main.state == Main.State.WIN and not shots.has("win"):
		shots["win"] = e
	return shots.has("win") and e - float(shots["win"]) > 1.5
