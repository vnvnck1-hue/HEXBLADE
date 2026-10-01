extends CameraRig
## 심연 성소 카메라: 기본 쿼터뷰(CameraRig) 위에 두 가지를 덧붙인다.
##  - 보스가 있으면 시선을 보스 쪽으로 당기고 조금 물러나 둘을 한 화면에 담는다
##  - 전장이 바뀌는 동안은 살짝 물러나 솟고 가라앉는 판을 보여 준다

var boss: Node3D
var reveal := 0.0          # 0~1, 전장 변화 중 물러남
var _bias := Vector3.ZERO
var _back := 0.0


func _ready() -> void:
	super._ready()
	# 프리셋 사전은 상수라 복사해서 쓴다 (오프셋을 바꾸기 위해)
	p = (PRESETS[preset_index] as Dictionary).duplicate()


func set_preset(i: int) -> void:
	super.set_preset(i)
	p = (PRESETS[preset_index] as Dictionary).duplicate()


func update(dt: float, player: Player) -> void:
	var want := Vector3.ZERO
	var back := reveal * 0.22
	if is_instance_valid(boss) and boss.visible:
		var d := boss.global_position - player.global_position
		d.y = 0
		want = d.limit_length(20.0) * 0.48
		back = maxf(back, 0.32)
	_bias = _bias.lerp(want, 1.0 - exp(-2.2 * dt))
	_back = lerpf(_back, back, 1.0 - exp(-2.0 * dt))
	var base: Vector3 = (PRESETS[preset_index] as Dictionary).offset
	p.offset = base * (1.0 + _back)
	super.update(dt, player)
	global_position += _bias
