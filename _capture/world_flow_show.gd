extends SceneTree
## 캡처: 추격전에서 흐르는 공간 확인 — 도로 위 폭발(연기·그을음)과 기본총 탄피·착탄 연기가 화면 아래로 흘러가는지.
## 실행: tools\godot.ps1 wait --fixed-fps 60 -s res://_capture/world_flow_show.gd -- --bot --godmode
const BossEnemy := preload("res://scripts/boss_enemy.gd")
var out := "output/world-flow-20261001"
var f := 0
var t0 := -1
var main: Main

func _initialize() -> void:
	main = load("res://scenes/boss.tscn").instantiate()
	root.add_child(main)
	current_scene = main

func _process(_dt: float) -> bool:
	f += 1
	if main.player:
		main.player.missiles = 0
	var boss: BossEnemy = main.get("boss")
	if boss == null or boss.st != BossEnemy.St.FIGHT:
		return false
	if t0 < 0:
		t0 = f
	boss.rest = 99.0
	main.player.missiles = 0
	main.time = 1.0
	var e := f - t0
	if e == 30:
		var at := main.player.global_position + Vector3(-3.5, 0.6, -3.0)
		FX.fire_explosion(at, 1.4)
		FX.sparks(at, 20, [Color.WHITE, Color("ffd060")], 9.0, 0.6)
		FX.shockwave(at, Color("ffd060"), 5.0, 0.4)
	if e >= 30 and e <= 100 and (e - 30) % 7 == 0:
		root.get_viewport().get_texture().get_image().save_png("res://%s/x_%04d.png" % [out, e])
	return e > 110
