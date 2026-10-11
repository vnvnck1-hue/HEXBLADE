class_name StreamDrone
extends Enemy
## 무한 비행 모드의 호위 포격 드론. 기본 드론(Enemy)의 공격·패링 탄을 그대로 쓰되,
## 종 스크롤 슈팅의 중형기처럼 늘 플레이어보다 앞쪽(화면 위)에 머물며 버티고,
## stay 초가 지나면 공격을 멈추고 위로 날아올라 화면 밖으로 빠져나간다 (처치하지 못하면 "놓침").

const AHEAD := 5.0            # 플레이어보다 최소 이만큼 앞(-Z)에 머문다
const LEAVE_SPEED := 11.0

var stay := 13.0
var age := 0.0
var leaving := false
var wave_id := -1
var escaped := false


func _ready() -> void:
	super()
	orb_chance = 0.3
	evade.chance = 0.2


func _ai(dt: float) -> void:
	age += dt
	if not leaving and age >= stay:
		leaving = true
		windup_k = 0.0
		orb_next = false
		burst_left = 0
	if leaving:
		_leave(dt)
		return
	super(dt)
	# 플레이어 뒤(화면 아래)로 내려가지 않는다
	var limit := Main.inst.player.global_position.z - AHEAD
	if global_position.z > limit:
		global_position.z = lerpf(global_position.z, limit, 1.0 - exp(-6.0 * dt))


## 이탈: 몸을 숙여 위로 날아오르며 화면 위로 빠져나간다
func _leave(dt: float) -> void:
	var body: Node3D = j.body
	global_position += Vector3(0, 0, -LEAVE_SPEED) * dt
	body.position.y = lerpf(body.position.y, 2.6, 1.0 - exp(-2.0 * dt))
	body.rotation.x = lerpf(body.rotation.x, -0.5, 1.0 - exp(-5.0 * dt))
	rotation.y = lerp_angle(rotation.y, 0.0, 1.0 - exp(-5.0 * dt))
	(j.core_mat as StandardMaterial3D).emission_energy_multiplier = 0.4
	if global_position.z < StreamFighter.TOP_Z and not locked:
		escaped = true
		alive = false
		remove_from_group("enemies")
		if Main.inst.has_method("on_enemy_escaped"):
			Main.inst.call("on_enemy_escaped", self)
		queue_free()


func _update_death(dt: float) -> void:
	super(dt)
	global_position.z += WorldFlow.road_v() * 0.35 * dt
