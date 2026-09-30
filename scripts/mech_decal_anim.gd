class_name MechDecalAnim
extends Node
## 메카닉 데칼의 네온 순차 점등. 발광 전용 데칼의 텍스처를 프레임 단위로 넘긴다.
## 한 바퀴 = 점등 프레임들 + rest 단계 소등. 데칼마다 시작 위상이 달라 박자가 겹치지 않는다.

var _items: Array = []     # [Decal, frames, rate, rest, offset, energy, last]
var _t := 0.0


func add(d: Decal, frames: Array, rate: float, rest: int, offset: float, energy: float) -> void:
	_items.append([d, frames, rate, rest, offset, energy, -1])


func _process(dt: float) -> void:
	_t += dt
	for it in _items:
		var fr: Array = it[1]
		var cycle: int = fr.size() + it[3]
		var k := int(_t * it[2] + it[4]) % cycle
		if k == it[6]:
			continue
		it[6] = k
		var d: Decal = it[0]
		if k < fr.size():
			d.texture_emission = fr[k]
			d.emission_energy = it[5]
		else:
			d.emission_energy = 0.0
