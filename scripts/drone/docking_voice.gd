class_name DockingVoice
extends Node
## 사선 DOCKING 합체 컷인의 미소녀 보이스 (docs/drone-docking-voice-handoff.md · 사용자 선택 9개, 스파랜드 무료 보이스).
## 실제 합체 순간(PartnerDrone._gattai_impact) 한 번, 9개 중 하나를 무작위로 — 직전 파일은 연속으로 안 나온다.
## 허수아비 F3 미리보기의 합체 순간에도 같은 헬퍼(씬 시작 prewarm 은 무음). Shift+F3 은 9개를 순서대로 강제 재생.
## 씬 노드의 자식(컷인의 자식이 아님) → 컷인이 먼저 사라져도 긴 음성(약 1.3초)이 끝까지 나온다. 동시 보이스는 최대 1개.
## 일시정지에 같이 멈추고(PAUSABLE), M 음소거(Sfx.muted)는 새 재생 차단 + 재생 중인 것도 무음. 피치 1.0 고정(슬로우모션과 무관).
##
## 믹싱 (보이스가 다른 소리보다 확실히 잘 들리게, _capture/voice_level_probe.gd 측정 기준):
##  ① 파일별 음량 맞춤 GAIN_DB: 9개의 평균 크기(-6.7 ~ -12.6)를 -7 로 통일
##  ② 전용 버스 "DockVoice": EQ(100Hz -3 · 1k +1 · 3.2k +4 · 10k +1.5 — 탁한 저음 빼고 말소리 대역 올림) → 컴프레서(고르게, 되올림 +10dB) → 하드 리미터(-1dBFS)
##  ③ 덕킹: 보이스가 나오는 동안 Master 를 DUCK_DB(-10) 내리고 보이스 버스는 그만큼 올려 상쇄 → 보이스는 그대로, 다른 모든 소리만 작아짐.
##     0.04초에 내려가고, 보이스가 끝나면 0.45초에 걸쳐 돌아온다. 씬이 바뀌거나 이 노드가 사라지면 Master 를 원래대로.

const DIR := "res://assets/audio/voices/spaland_docking/"
const NAMES := ["shozyo2-torya", "shozyo2-atare", "shozyo2-eiya", "shozyo2-ta", "shozyo1-to",
	"shozyo1-ya", "shozyo1-atattekudasai", "shozyo1-ei", "zyosei4-ta"]
const VOLUME_DB := 2.0           ## 보이스 기본 음량 (파일 맞춤 뒤, 버스 처리 전)
## 파일별 맞춤 (평균 크기를 -7 로): 측정 크기 -6.9 -8.0 -6.7 -7.0 -12.6 -7.7 -10.2 -7.2 -10.9
const GAIN_DB := [0.0, 1.0, -0.3, 0.0, 7.5, 0.7, 3.2, 1.5, 2.5]   ## 버스 처리 뒤 크기를 다시 재서 to·ei 올리고 zyosei4 내림
const BUS := "DockVoice"
const DUCK_DB := -10.0           ## 보이스 동안 다른 소리 (Master)
const DUCK_ATTACK := 0.04
const DUCK_RELEASE := 0.45
## 원본 MP3 는 약관상 공개 저장소에 올리지 않는다(.gitignore) → preload 대신 있으면 불러온다.
## 파일이 없는 PC 에서는 그 자리가 null 이고 합체 보이스만 조용히 빠진다 (받는 법: 인수인계 문서 7절).
static var VOICES: Array = _load_voices()


static func _load_voices() -> Array:
	var out := []
	for n in NAMES:
		var path: String = DIR + n + ".mp3"
		out.append(load(path) if ResourceLoader.exists(path) else null)
	return out


static var inst: DockingVoice
static var force := -1           ## 0~8 이면 다음 재생을 이 파일로 (개발용 · Shift+F3)
static var plays := 0            ## 확인용: 지금까지 재생 횟수
static var last_name := ""

var player: AudioStreamPlayer
var rng := RandomNumberGenerator.new()   ## 게임 RNG(seed)와 독립
var last := -1
var duck := 0.0                  ## 지금 덕킹 깊이 0~1
var _master_base := 0.0          ## 덕킹 전 Master 음량 (되돌릴 값)
var _ducking := false


## 합체 성공 순간 한 번 부른다. scene = Main 계열 씬(노드 주인).
static func play(scene: Node) -> void:
	if scene == null or not is_instance_valid(scene):
		return
	if not is_instance_valid(inst) or inst.get_parent() != scene:
		var v := DockingVoice.new()
		scene.add_child(v)
	inst._play()


static func stop() -> void:
	if is_instance_valid(inst) and is_instance_valid(inst.player):
		inst.player.stop()


static func is_playing() -> bool:
	return is_instance_valid(inst) and is_instance_valid(inst.player) and inst.player.playing


func _enter_tree() -> void:
	inst = self


func _exit_tree() -> void:
	if inst == self:
		inst = null
	_set_duck(0.0)


## 보이스 전용 버스 (없으면 만든다 · 한 번만)
static func ensure_bus() -> int:
	var i := AudioServer.get_bus_index(BUS)
	if i >= 0:
		return i
	i = AudioServer.bus_count
	AudioServer.add_bus(i)
	AudioServer.set_bus_name(i, BUS)
	AudioServer.set_bus_send(i, "Master")
	var eq := AudioEffectEQ6.new()
	eq.set_band_gain_db(1, -3.0)     ## 100Hz
	eq.set_band_gain_db(3, 1.0)      ## 1kHz
	eq.set_band_gain_db(4, 4.0)      ## 3.2kHz 말소리
	eq.set_band_gain_db(5, 1.5)      ## 10kHz 공기감
	AudioServer.add_bus_effect(i, eq)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -16.0
	comp.ratio = 3.0
	comp.attack_us = 5000.0
	comp.release_ms = 120.0
	comp.gain = 10.0                 ## 눌린 만큼 되올림 (측정: 버스 뒤 평균 크기 ≈ -4, 최대 -1)
	AudioServer.add_bus_effect(i, comp)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0
	AudioServer.add_bus_effect(i, lim)
	return i


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	rng.randomize()
	player = AudioStreamPlayer.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.pitch_scale = 1.0
	player.volume_db = VOLUME_DB
	ensure_bus()
	player.bus = BUS
	add_child(player)


func _play() -> void:
	if Sfx.inst != null and Sfx.inst.muted:
		return
	var i := force
	force = -1
	if i < 0 or i >= VOICES.size():
		i = rng.randi_range(0, VOICES.size() - 2)
		if i >= last and last >= 0:
			i += 1                              ## 직전 파일은 건너뜀 (남은 8개 중 균등)
	last = i
	if VOICES[i] == null:
		return                                  ## 원본 MP3 가 없는 PC (공개 저장소 클론)
	player.stop()                               ## 동시 보이스 최대 1개: 남아 있던 것은 교체
	player.stream = VOICES[i]
	player.volume_db = VOLUME_DB + float(GAIN_DB[i])
	player.set_meta("gain", float(GAIN_DB[i]))
	player.play()
	plays += 1
	last_name = NAMES[i]
	print("DOCK_VOICE %s (%d)" % [last_name, plays])


func _process(dt: float) -> void:
	# 덕킹: 재생 중이면 빠르게 내려가고, 끝나면 천천히 돌아온다 (실제 시간 — 슬로우모션과 무관)
	var rdt := dt / maxf(Engine.time_scale, 0.01)
	var target := 1.0 if player.playing else 0.0
	if target > duck:
		duck = minf(target, duck + rdt / DUCK_ATTACK)
	else:
		duck = maxf(target, duck - rdt / DUCK_RELEASE)
	_set_duck(duck)
	if not player.playing:
		return
	# 재생 중 M 음소거 → 바로 무음, 풀면 다시 들림
	var muted := Sfx.inst != null and Sfx.inst.muted
	player.volume_db = -80.0 if muted else VOLUME_DB + float(player.get_meta("gain", 0.0))
	# 메카가 쓰러지면 정리
	var pl: Variant = get_parent().get("player")
	if pl is Node and is_instance_valid(pl) and not bool((pl as Node).get("alive")):
		player.stop()


## Master 를 깊이 k(0~1)만큼 DUCK_DB 로 내리고, 보이스 버스는 그만큼 올려 보이스 크기는 그대로 둔다.
## 덕킹이 끝나면(0) 원래 Master 값으로 정확히 되돌린다.
func _set_duck(k: float) -> void:
	var m := AudioServer.get_bus_index("Master")
	var v := AudioServer.get_bus_index(BUS)
	if k <= 0.0001:
		if _ducking:
			AudioServer.set_bus_volume_db(m, _master_base)
			if v >= 0:
				AudioServer.set_bus_volume_db(v, 0.0)
			_ducking = false
		return
	if not _ducking:
		_master_base = AudioServer.get_bus_volume_db(m)
		_ducking = true
	var d := DUCK_DB * k
	AudioServer.set_bus_volume_db(m, _master_base + d)
	if v >= 0:
		AudioServer.set_bus_volume_db(v, -d)
