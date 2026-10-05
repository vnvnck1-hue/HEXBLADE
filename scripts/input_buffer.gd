class_name InputBuffer
extends RefCounted
## 선입력 버퍼. Player 가 소유한다.
## 행동 버튼(검 · 대시 · 돌진 스킬)을 눌렀는데 지금 상태가 받아 주지 못하면 여기에 WINDOW 초 동안 담아 두고,
## 받아 줄 수 있게 되는 첫 틱에 꺼내 쓴다. 칸은 하나라서 마지막에 누른 행동이 이긴다 (검 → 대시를 누르면 대시).
## 시간은 게임 시간(dt)이라 히트스탑 동안에는 함께 멈춘다. 대시·돌진처럼 몸이 묶인 동작 중에는 줄지 않는다
## (그 동작이 끝나야 비로소 기다리기 시작한다 → 대시 도중 누른 검은 대시가 끝나자마자 나간다).
## 타이밍 판정(패링 · 2단 대시)에는 쓰지 않는다: 미리 눌러 두면 저절로 성공하게 되므로.

const WINDOW := 0.18

var act := ""
var t := 0.0


func push(a: String) -> void:
	act = a
	t = WINDOW


func tick(dt: float, hold := false) -> void:
	if act == "" or hold:
		return
	t -= dt
	if t <= 0.0:
		clear()


func has(a: String) -> bool:
	return act == a


## a 가 기다리고 있으면 꺼내고 true
func take(a: String) -> bool:
	if act != a:
		return false
	clear()
	return true


func clear() -> void:
	act = ""
	t = 0.0
