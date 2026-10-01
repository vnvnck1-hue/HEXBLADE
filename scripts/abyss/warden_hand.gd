extends Enemy
## 후광의 파수자 손 피격 판정. 내려찍어 바닥에 박혀 있는 동안만 맞는다 (landed = true).
## 받은 피해는 본체(warden.gd)에 넘긴다. 검으로 벨 수 있는 유일한 부위라 본체보다 크게 들어간다.

var boss: Node3D
var side := 0


func _ready() -> void:
	add_to_group("enemies")
	is_boss = true
	radius = 1.7
	slice_color = Color("5c4a3a")
	slice_size = Vector3(2, 1.5, 2)
	visual = Node3D.new()
	add_child(visual)
	landed = false


func _physics_process(_dt: float) -> void:
	pass


func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	if alive and landed and is_instance_valid(boss):
		boss.call("part_hit", self, dmg, dir, pos, source)


## 락온 빗금은 손 메시 위에 덮인다
func bind(hand: Node3D) -> void:
	j = {"body": hand}
