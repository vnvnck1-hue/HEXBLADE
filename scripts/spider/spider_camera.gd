extends CameraRig
## 갱도 카메라: 통일 시야(CameraRig TACTICAL 62° · 화각 36°)를 그대로 쓰고, 각도는 바꾸지 않는 연출만 덧붙인다.
##  - 보스 담기: 보이는 보스 쪽으로 시선을 당기고 거리만큼 물러난다. 보스가 벽 높이 · 기둥 위 · 천장에 있으면 조금 더 물러난다
##  - 숨었을 때: 조금 물러나 시선이 천천히 좌우를 살핀다 (어디서 나올지 모르는 긴장)
##  - 등장 순간(revealed): 튀어나온 자리로 시선이 확 끌렸다가 돌아오고 짧게 줌인 펀치
##  - 천장 낙하: 떨어지는 순간 내려찍기와 함께 흔들린다
## (예전의 낮은 각도 · 좌우 시차 회전 · 올려다보기 기울임은 시야 통일로 뺐다)

const Stage := preload("res://scripts/spider/spider_stage.gd")
## 54×46m 갱도와 거대 거미를 담으려고 거리만 1.3배 (예전 (0,16.5,13.5) · 화각 44° 와 보이는 넓이가 같다)
const BASE := Vector3(0, 18.0, 9.6) * 1.3
const FOV := CameraRig.VIEW_FOV

var boss: Node3D
var _bias := Vector3.ZERO
var _back := 0.0
var _lift := 0.0
var _rev_t := 0.0
var _rev_at := Vector3.ZERO
var _rev_k := 0.0
var _search_t := 0.0


func _ready() -> void:
	super._ready()
	far = 420.0
	p = (PRESETS[preset_index] as Dictionary).duplicate()
	p.offset = BASE
	p.fov = FOV
	p.follow = 5.0
	cur_offset = BASE
	cur_fov = FOV


func set_preset(i: int) -> void:
	super.set_preset(i)
	p = (PRESETS[preset_index] as Dictionary).duplicate()
	p.offset = BASE * ((PRESETS[preset_index] as Dictionary).offset as Vector3).length() / (PRESETS[3].offset as Vector3).length()
	p.fov = FOV


## 보스가 어딘가에서 튀어나왔다
func reveal(at: Vector3, kind: String) -> void:
	_rev_at = at
	match kind:
		"burst", "enter":
			_rev_t = 1.1
			_rev_k = 0.55
			zoom_v -= 1.4
			fov_v -= 22.0
			shake(0.25)
		"drop":
			_rev_t = 0.0
		"slam":
			zoom_v -= 2.2
			fov_v -= 30.0
			kick_v += Vector3(0, -2.5, 0)


func update(dt: float, player: Player) -> void:
	var want := Vector3.ZERO
	var back := 0.0
	var lift := 0.0
	var hidden := true
	if is_instance_valid(boss) and boss.is_inside_tree():
		hidden = bool(boss.get("hidden"))
		var bp: Vector3 = boss.call("focus_point")
		if not hidden:
			var d := bp - player.global_position
			d.y = 0
			var l := d.length()
			if l < 40.0:
				want = d.limit_length(24.0) * 0.45
				back = clampf((l - 6.0) / 20.0, 0.0, 1.0) * 0.42
			lift = float(boss.get("look_up"))
		else:
			lift = float(boss.get("look_up"))
	if hidden and lift < 0.1:
		# 숨어 있다: 물러나 천천히 둘러본다
		_search_t += dt
		back = 0.14
		want += Vector3(sin(_search_t * 0.3) * 2.0, 0, -1.5)
	else:
		_search_t = 0.0
	# 등장 순간: 그 자리로 시선을 끌었다 놓는다
	if _rev_t > 0.0:
		_rev_t -= dt
		var k := clampf(_rev_t / 1.1, 0.0, 1.0)
		var w := sin(k * PI) * _rev_k if k < 0.85 else _rev_k * (1.0 - k) / 0.15
		var d2 := _rev_at - player.global_position
		d2.y = 0
		want = want.lerp(d2.limit_length(24.0) * 0.6, w)
	if lift > 0.05:
		back = maxf(back, 0.2 * lift)
	# 남쪽 끝(카메라 쪽 난간 너머)을 너무 비추지 않게 시선을 북쪽으로 받친다
	var south := player.global_position.z + want.z - (Stage.HZ - 9.0)
	if south > 0.0:
		want.z -= south
	_bias = _bias.lerp(want, 1.0 - exp(-2.4 * dt))
	_back = lerpf(_back, back, 1.0 - exp(-2.0 * dt))
	_lift = lerpf(_lift, lift, 1.0 - exp(-3.0 * dt))
	# 각도는 통일 시야 그대로, 거리만 늘린다
	p.offset = BASE * (1.0 + _back)
	super.update(dt, player)
	global_position += _bias
