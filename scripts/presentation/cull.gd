class_name Cull
## 플레이어에서 먼 곳의 꾸밈 갱신(연기 구역 덩이 · 레일 롤러 · 가스통 경고등 …)을 쉬게 하는 거리 판정.
## 맵 전체에 깔린 기믹이 화면 밖에서도 매 프레임 돌던 비용을 없앤다. 판정·게임 진행에는 쓰지 않는다 (연출만).
## 카메라(TACTICAL 62° · FOV 36°)가 플레이어 둘레 약 ±12m 를 보고, 궁극기 조준 때 최대 7.5m 더 옮겨 가므로 26m 면 화면 밖이다.

const FAR := 26.0


## p 가 플레이어에서 FAR + extra 보다 멀면 true. 플레이어가 없으면 false (멀다고 단정하지 않는다)
static func far(p: Vector3, extra := 0.0) -> bool:
	var m := Main.inst
	if m == null or not is_instance_valid(m) or not is_instance_valid(m.player):
		return false
	var d := m.player.global_position - p
	var r := FAR + extra
	return d.x * d.x + d.z * d.z > r * r
