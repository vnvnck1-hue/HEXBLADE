extends "res://scripts/main.gd"
## 방 탐색 녹화용: main.gd 그대로 + 봇 궁극기는 캡처 스크립트가 허락할 때 한 번만,
## 이동은 벽을 피해 돌아가고(막히면 길 찾기), 근접 교전 때 적에게 길을 따라 붙는다.

var ult_allowed := false
var ult_used := 0
var close_in := false     ## 근접 교전 (적이 덤벼 패링 기회가 생기게 가까이 붙는다)
var _chase: Array[Vector3] = []
var _chase_t := 0.0
var _stuck_pos := Vector3.ZERO
var _stuck_t := 0.0


func _ready() -> void:
	super._ready()
	# 상속하면 벌레 아레나 판정이 꺼지므로 main.tscn 과 같게 되돌린다 (방 활성화는 나중이라 여기서 켜도 된다)
	if not cmd_args.has("--enemies=classic"):
		bug_arena = true
		BugEnemy.warm()
		BugEnemy.warm_rigs.call_deferred()


func bot_input(p: Player) -> Dictionary:
	var o := super.bot_input(p)
	if o.get("ult", false):
		if ult_allowed and ult_used == 0 and p.missiles > 0 and not p.ult_busy():
			ult_used = 1
		elif not p.ult_busy():
			o.ult = false
	if p.ult_busy():
		return o
	var dt := get_physics_process_delta_time()
	var e := _nearest_enemy(p, true, false)
	var m: Vector3 = o.move
	if e:
		var to := e.global_position - p.global_position
		to.y = 0
		var want_close := close_in and to.length() > 2.6
		var blocked_line := not _line_clear(p.global_position, e.global_position)
		if want_close or blocked_line or to.length() > 9.0:
			_chase_t -= dt
			if _chase_t <= 0.0 or _chase.is_empty():
				_chase_t = 0.4
				_chase = map.find_path(p.global_position, e.global_position)
			while _chase.size() > 1 and _chase[0].distance_to(p.global_position) < 1.1:
				_chase.pop_front()
			if not _chase.is_empty():
				var wp: Vector3 = _chase[mini(1, _chase.size() - 1)] - p.global_position
				wp.y = 0
				if wp.length() > 0.1:
					m = wp.normalized() if blocked_line else (wp.normalized() + m * 0.25).limit_length(1.0)
	# 오래 제자리면 (벽에 비비는 중) 바로 길을 다시 찾게 한다
	_stuck_t += dt
	if _stuck_t > 0.8:
		if p.global_position.distance_to(_stuck_pos) < 0.6 and m.length() > 0.3:
			_chase_t = 0.0
		_stuck_pos = p.global_position
		_stuck_t = 0.0
	o.move = _steer(p, m)
	return o


## 벽 앞에서 미끄러지지 않게: 원하는 방향이 막혔으면 가까운 열린 방향으로 돌린다
func _steer(p: Player, m: Vector3) -> Vector3:
	var l := m.length()
	if l < 0.05:
		return m
	var d := m / l
	for a in [0.0, 25.0, -25.0, 50.0, -50.0, 80.0, -80.0, 120.0, -120.0]:
		var dir := d.rotated(Vector3.UP, deg_to_rad(a))
		var ok := true
		for s in [0.6, 1.2, 1.8]:
			if map.is_blocked(p.global_position + dir * s):
				ok = false
				break
		if ok:
			return dir * l
	return Vector3.ZERO


func _line_clear(a: Vector3, b: Vector3) -> bool:
	var n := int(a.distance_to(b) / 0.5)
	for i in range(1, n):
		if map.is_blocked_cell(map.cell_of(a.lerp(b, float(i) / n))):
			return false
	return true
