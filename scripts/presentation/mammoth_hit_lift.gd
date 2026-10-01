extends RefCounted
## 맘모스 강력 레이저 피격 반응 (연출 전용, 판정·체력과 무관).
## 레이저에 맞은 쪽 차체가 들리고(반대쪽 궤도 모서리가 도로에 붙은 채 축이 된다) 마구 떨리다가,
## 다시 떨어질 때 들렸던 모서리가 도로를 찍으며 불꽃·먼지를 튀긴다.
##  기울기   tilt: 2D 벡터(차체 로컬 x, z). 방향 = 들린 쪽, 길이 = 기운 각도(rad). 스프링으로 되돌아온다
##  진동     buzz: 맞을수록 쌓이고 빠르게 줄어드는 고주파 떨림 (회전 + 위아래)
## BossEnemy._update_body 가 기본 흔들림을 visual 에 쓴 뒤 compose() 를 곱한다.

const HALF := 3.4                 # 차체 반폭·반길이 (들린 반대쪽 모서리 = 회전축까지 거리)
const MAX_TILT := 0.38            # 최대 기울기 (rad, 약 22도)
const K := 55.0                   # 되돌아오는 힘
const DAMP := 7.5
const BUZZ_MAX := 1.6

var tilt := Vector2.ZERO
var tilt_v := Vector2.ZERO
var buzz := 0.0
var t := 0.0
var _land_cd := 0.0
var _was_up := false


## local_hit: 차체 중심에서 본 피격 지점(차체 로컬 x, z). k: 세기 (충전 레이저 0.4~1.3, 지속 레이저 틱 0.35)
func kick(local_hit: Vector2, k: float) -> void:
	var u := local_hit.normalized() if local_hit.length() > 0.2 else Vector2(0, 1)
	# 들리는 방향으로 각속도를 넣는다. 이미 크게 들려 있으면 덜 넣어 한계 근처에서 버틴다
	var room := clampf(1.0 - tilt.length() / MAX_TILT, 0.15, 1.0)
	tilt_v += u * 3.2 * k * room
	buzz = minf(BUZZ_MAX, buzz + 0.9 * k)


## dt 만큼 진행하고, 들렸던 모서리가 도로를 다시 찍으면 그 지점(차체 로컬)을 돌려준다. 아니면 null
func step(dt: float) -> Variant:
	t += dt
	_land_cd -= dt
	tilt_v += (-tilt * K - tilt_v * DAMP) * dt
	tilt += tilt_v * dt
	if tilt.length() > MAX_TILT:
		tilt = tilt.normalized() * MAX_TILT
		var out := tilt_v.dot(tilt.normalized())
		if out > 0.0:
			tilt_v -= tilt.normalized() * out
	buzz = maxf(0.0, buzz - buzz * 4.5 * dt - 0.05 * dt)
	var a := tilt.length()
	var landed: Variant = null
	# 크게 들렸다가 도로로 떨어지는 순간 (기울기가 작아지는 중 문턱을 지남)
	if _was_up and a < 0.03 and _land_cd <= 0.0:
		_land_cd = 0.25
		landed = (tilt_v.normalized() * -1.0 if tilt_v.length() > 0.01 else Vector2(0, 1)) * HALF
	if a > 0.08:
		_was_up = true
	elif a < 0.03:
		_was_up = false
	return landed


## 기본 흔들림 위에 곱할 변환. 들린 쪽 반대 모서리를 축으로 돌고, 떨림을 더한다
func compose() -> Transform3D:
	var a := tilt.length()
	var xf := Transform3D.IDENTITY
	if a > 0.0005:
		var u := Vector3(tilt.x, 0, tilt.y) / a
		var axis := u.cross(Vector3.UP).normalized()
		var b := Basis(axis, a)
		# 반대쪽 모서리(-u * HALF)가 도로 높이에 남도록 중심을 올린다
		var pivot := -u * HALF
		xf = Transform3D(b, pivot - b * pivot)
	if buzz > 0.001:
		var j := buzz * 0.045
		var r := Vector3(sin(t * 57.0) + sin(t * 91.0) * 0.6, 0, sin(t * 63.0 + 1.3) + sin(t * 83.0) * 0.5) * j
		xf = Transform3D(Basis.from_euler(r), Vector3(0, absf(sin(t * 47.0)) * buzz * 0.12, 0)) * xf
	return xf


func lifted() -> float:
	return tilt.length()
