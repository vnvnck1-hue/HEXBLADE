class_name WorldFlow
extends Node3D
## 흐르는 공간 (연출 전용, 판정과 무관). 추격 보스전처럼 플레이어·보스는 제자리이고 도로가 +Z(화면 아래)로 흐르는 씬에서,
## 바닥에 남거나 공중에 떠 있는 연출이 제자리에 박혀 있지 않고 공간을 따라 흘러가게 한다.
##  운반 노드  holder(a): 연출 노드를 이 아래에 넣으면, 처음엔 제자리였다가 공기 저항처럼 v = 도로속도·(1 − e^(−a·나이)) 로 가속해 흘러간다.
##             Tween 이 연출 노드의 position 을 움직여도 부모가 흐르므로 그대로 함께 흐른다.
##             AIR = 연기·불꽃·폭발 (짧은 섬광은 거의 제자리, 오래 남는 연기는 뒤로 길게 끌림)
##             GROUND = 바닥 흔적·바닥 충격파 (바로 도로와 같은 속도)
##  자체 물리  탄피·파편·잔해처럼 스스로 움직이는 것은 road_v() 로 도로 기준 마찰을 걸고, gone() 이면 지운다.
## 씬에 attach() 하지 않으면(일반 방 전투) holder() 는 FX.root 를 돌려주고 road_v() 는 0 이라 아무것도 바뀌지 않는다.

const AIR := 2.2
const GROUND := 80.0
const FREE_AFTER := 80.0          # 운반 노드가 이만큼 흘러가면 화면 밖이므로 지운다

static var inst: WorldFlow

var source: Object                # speed 속성을 가진 도로 (boss_stage.gd)
var far_z := 40.0                 # 이보다 아래(+Z)로 내려간 탄피·파편은 지운다
var speed := 0.0
var _items: Array = []            # [운반 노드, 나이, a]


## 흐르는 씬에서 한 번 부른다. src.speed 를 매 프레임 읽는다
static func attach(parent: Node3D, src: Object, far := 40.0) -> WorldFlow:
	var w := WorldFlow.new()
	w.name = "WorldFlow"
	w.source = src
	w.far_z = far
	w.speed = float(src.get("speed"))
	parent.add_child(w)
	return w


static func active() -> bool:
	return inst != null and is_instance_valid(inst) and inst.is_inside_tree()


## 지금 도로 속도 (m/s, +Z). 흐르지 않는 씬이면 0
static func road_v() -> float:
	return inst.speed if active() else 0.0


## 화면 아래로 흘러 나간 위치인가
static func gone(p: Vector3) -> bool:
	return active() and p.z > inst.far_z


## 연출 노드를 넣을 부모. 흐르는 씬이면 새 운반 노드, 아니면 FX.root
static func holder(a := AIR) -> Node3D:
	if not active() or a <= 0.0:
		return FX.root
	var c := Node3D.new()
	inst.add_child(c)
	inst._items.append([c, 0.0, a])
	return c


func _ready() -> void:
	inst = self


func _exit_tree() -> void:
	if inst == self:
		inst = null


func _process(dt: float) -> void:
	if source and is_instance_valid(source):
		speed = float(source.get("speed"))
	var i := _items.size() - 1
	while i >= 0:
		var it: Array = _items[i]
		var c: Node3D = it[0]
		if not is_instance_valid(c):
			_items.remove_at(i)
			i -= 1
			continue
		if c.get_child_count() == 0 or c.position.z > FREE_AFTER:
			c.queue_free()
			_items.remove_at(i)
			i -= 1
			continue
		it[1] = float(it[1]) + dt
		c.position.z += speed * (1.0 - exp(-float(it[2]) * float(it[1]))) * dt
		i -= 1
