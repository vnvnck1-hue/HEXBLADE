class_name RogueBoss
extends Node
## 층 보스 컨트롤러: 기존 전투 코어의 적을 크게 키워 보스로 쓴다. 전용 체력바 · 50% 이하 광폭화(부하 소환 + 붉은 고리).
## 보스가 모두 쓰러지면 RogueMain.on_boss_dead() 를 부른다.

const BossBar := preload("res://scripts/boss_bar.gd")

const BOSSES := [
	{"name": "GORGER", "sub": "거대 촘퍼", "type": "chomper", "scale": 2.0, "hp": 800.0, "adds": "grub"},
	{"name": "TWINFANG", "sub": "쌍둥이 요격기", "type": "striker", "count": 2, "scale": 1.5, "hp": 520.0, "adds": "drone"},
	{"name": "CRAWLER KING", "sub": "중력 크롤러의 왕", "type": "crawler", "scale": 1.6, "hp": 1400.0, "adds": "drone"},
	{"name": "BROOD QUEEN", "sub": "개미 여왕", "type": "ant", "scale": 2.3, "hp": 1700.0, "adds": "ant"},
	{"name": "BASTION", "sub": "포대 요새", "type": "drone_ring", "scale": 2.4, "hp": 2100.0, "adds": "turret"},
	{"name": "HEX HEART", "sub": "헥스 코어의 심장", "type": "drone_ring", "scale": 2.9, "hp": 3200.0, "adds": "striker", "final": true},
]

var main
var room := -1
var spec := {}
var bosses: Array = []
var total_hp := 0.0
var bar: CanvasLayer
var enraged := false
var add_cd := 4.0
var done := false
var t := 0.0


static func spec_for(depth: int) -> Dictionary:
	return BOSSES[clampi(depth - 1, 0, BOSSES.size() - 1)]


func start(m, room_id: int, depth: int) -> void:
	main = m
	room = room_id
	spec = spec_for(depth)
	var c: Vector3 = m.map.room_center(room_id)
	var n := int(spec.get("count", 1))
	for i in n:
		var off := Vector3((i - (n - 1) * 0.5) * 5.0, 0, -2.5)
		var e := _make(spec.type)
		var base_hp := float(e.hp)
		e.hp_mul = float(spec.hp) / maxf(base_hp * Enemy.HP_SCALE, 1.0)
		e.is_boss = true
		m.world.add_child(e)
		e.global_position = c + off
		e.scale = Vector3.ONE * float(spec.scale)
		e.radius *= float(spec.scale)
		bosses.append(e)
		total_hp += float(spec.hp)
	bar = BossBar.new()
	add_child(bar)
	bar.name_label.text = "%s  ·  %s" % [spec.name, spec.sub]
	bar.threshold = 0.5
	bar.appear()
	m.hud.banner(spec.name, Color("ff5a7a"), spec.sub + "  ·  " + RogueRun.floor_name())
	Sfx.play("twind", 0.0, -2.0)


func _make(type: String) -> Enemy:
	match type:
		"chomper": return BugChomper.new()
		"striker": return Striker.new()
		"crawler": return Crawler.new()
		"ant": return BugAnt.new()
		"grub": return BugGrub.new()
		"turret": return Turret.new()
		"drone_ring":
			var e := Enemy.new()
			e.pattern = 2
			return e
	var d := Enemy.new()
	d.pattern = randi() % 3
	return d


func _physics_process(dt: float) -> void:
	if done:
		return
	t += dt
	var left := 0.0
	var alive := 0
	for e in bosses:
		if is_instance_valid(e) and e.alive:
			alive += 1
			if is_instance_valid(e.hp_bar):
				e.hp_bar.visible = false        # 보스는 화면 위 체력바만
			if e.max_hp > 0:
				left += float(e.hp) / float(e.max_hp) * float(spec.hp)
			else:
				left += float(spec.hp)
	var k := left / maxf(total_hp, 1.0)
	bar.set_hp(k)
	if not enraged and k < 0.5:
		enraged = true
		bar.set_phase(2)
		main.hud.banner("ENRAGED", Color("ff3a4a"), spec.name + " 광폭화")
		main.shake(0.6)
		for e in bosses:
			if is_instance_valid(e) and e.alive:
				FX.shockwave(e.global_position, Color("ff3a4a"), 6.0, 0.5)
	if enraged:
		add_cd -= dt
		if add_cd <= 0.0:
			add_cd = 5.5
			_spawn_adds()
	if alive == 0:
		done = true
		bar.hide_bar()
		main.on_boss_dead(self)


func _spawn_adds() -> void:
	var live := 0
	for e in Enemy.live(get_tree()):
		if not e.get("prop") and not e.is_boss:
			live += 1
	if live >= 4:
		return
	for i in 2:
		main.spawn_enemy(spec.adds, main.map.random_spot(room, main.player.global_position, 5.0))
