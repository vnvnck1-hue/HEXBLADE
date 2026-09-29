extends Enemy
## 거신 팔 끝(도가니 포신) 피격 판정. 내려찍은 뒤 발판에 박혀 있는 동안만 맞는다 (landed = true).
## 받은 피해는 본체(forge_boss.gd)에 넘긴다. 검·관통 일격은 본체보다 크게 들어간다.
## 탄·검·미사일·락온이 일반 적처럼 이 노드를 찾도록 "enemies" 그룹에 둔다.

var boss: Node3D
var arm_index := 0


func _ready() -> void:
	add_to_group("enemies")
	radius = 1.9
	slice_color = Color("5b5566")
	slice_size = Vector3(2, 2, 2)
	visual = Node3D.new()
	add_child(visual)
	landed = false


func _physics_process(_dt: float) -> void:
	pass


func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	if alive and landed and is_instance_valid(boss):
		boss.call("part_hit", self, dmg, dir, pos, source)


## 락온 빗금은 j.body(아래팔) 메시 위에 덮인다 (Enemy.set_locked / _set_flash 가 사용)
func bind(fore: Node3D) -> void:
	j = {"body": fore}
