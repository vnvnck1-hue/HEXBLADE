class_name FxWarm
extends Node3D
## 전투 연출 미리 데우기. 첫 교전 순간에 처음 쓰이는 셰이더·파티클·글꼴 글리프를 씬을 불러온 직후에 한 번 써 둔다.
## (측정: 첫 명중 · 첫 총구 · 첫 폭발 · 첫 잔상이 겹치는 첫 교전 프레임이 40~60ms 끊겼다)
## 연출은 플레이어 발밑 25m 아래(바닥에 가려 보이지 않지만 카메라 시야 안이라 실제로 그려짐)에서 내고, 효과음은 그동안 끈다.
## 판정·게임 상태에는 닿지 않는다 — 적·점수·콤보를 건드리지 않는 연출 함수만 부른다.

const DEPTH := 25.0
const FRAMES := 4

var main: Main
var _f := 0
var _muted := false
var _quads: Array[Node] = []


static func attach(m: Main) -> void:
	var w := FxWarm.new()
	w.name = "FxWarm"
	w.main = m
	m.add_child(w)


func _process(_dt: float) -> void:
	_f += 1
	if _f == 2:
		_fire()
	elif _f >= 2 + FRAMES:
		if Sfx.inst:
			Sfx.inst.muted = _muted
		for q in _quads:
			q.queue_free()
		queue_free()


func _fire() -> void:
	if not is_instance_valid(main) or not is_instance_valid(main.player) or FX.root == null:
		queue_free()
		return
	if Sfx.inst:
		_muted = Sfx.inst.muted
		Sfx.inst.muted = true
	var p := main.player.global_position + Vector3(0, -DEPTH, 0)
	# 타격 버스트 · 총구 · 착탄 · 불꽃 · 폭발 (각자 셰이더·파티클 머티리얼을 처음 만든다)
	var mf := MocoFX.get_inst()
	if mf:
		mf.hit(p, Vector3.FORWARD, 1.0, false)
		mf.hit(p, Vector3.FORWARD, 1.0, true)
	ToonGunFX.muzzle(p, Vector3.FORWARD)
	ToonGunFX.impact(p, Vector3.UP)
	HitSpark.spawn(p, Vector3.FORWARD)
	FX.sparks(p, 6, [Color.WHITE, Color.ORANGE], 4.0, 0.3)
	StylizedExplosion.spawn(FX.root, p, 0.4, p.y)
	GustFX.boost_burst(p, Vector3.FORWARD)     # 기류 연출 메시·셰이더 (첫 부스터 때 약 20ms)
	ParryFX.warn(p, "melee")                    # 패링 공격 별빛 셰이더 (벌레의 첫 덮치기 예고 때 약 29ms)
	# 잔상 재질은 메시 하나에 씌워 그려 둔다
	var q := MeshInstance3D.new()
	q.mesh = BoxMesh.new()
	q.material_override = GhostPool.material()
	q.set_instance_shader_parameter("span", Vector2(GhostPool.clock, 10.0))
	add_child(q)
	q.global_position = p
	_quads.append(q)
	# 바닥 파괴(내려찍기 · 돌진 흔적) 재질: 바닥 자리에서 파생해 만들고 같은 깊이 상자에 씌워 그려 둔다
	for mat in GroundBreak.warm(main.player.global_position):
		var g := MeshInstance3D.new()
		g.mesh = BoxMesh.new()
		g.material_override = mat
		add_child(g)
		g.global_position = p
		_quads.append(g)
	_glyphs()
	_bubble_glyphs()
	CutIn.ensure()      # 컷인 층(띠 · 속도선 폴리곤 12개 · 글자)을 첫 컷인 순간이 아니라 지금 만든다
	BlastScorch._shared()    # 그을음 무늬 256² 를 GDScript 로 한 점씩 굽는다 (첫 가스통 폭발 때 약 30ms)
	# 최대 레이저: 원통·고리·구 메시와 빔 셰이더를 처음 만들 때 약 14ms. 같은 깊이에 한 번 띄웠다가 지운다
	var mb := MegaBeam.new()
	mb.set_process(false)
	mb.set_physics_process(false)
	add_child(mb)
	mb.global_position = p
	_quads.append(mb)


## 말풍선 글리프: 드론 대사 · 메카 기합 · 감정 기호를 투명하게 한 번 그려 글꼴 캐시에 굽는다.
## HUD 글꼴은 SystemFont 라 미리 굽는 API 가 없어서, 그리기(투명 색이어도 글리프를 굽는다)로 데운다.
## (새 한글 대사 말풍선이 처음 뜨는 프레임이 13~22ms 걸렸다)
func _bubble_glyphs() -> void:
	if main.hud == null or main.hud.font == null:
		return
	var texts: Array[String] = []
	for k in PartnerDrone.LINES:
		for t: String in PartnerDrone.LINES[k]:
			texts.append(t)
	for t: String in RepairHatch.SHOUTS:
		texts.append(t)
	var layer := CanvasLayer.new()
	var c := _GlyphCanvas.new()
	c.font = main.hud.font
	c.items = [[texts, SpeechBubble.FONT_SIZE[SpeechBubble.SAY]], [["!!", "?"], SpeechBubble.FONT_SIZE[SpeechBubble.EMOTE]], [["!!"], 44]]
	layer.add_child(c)
	add_child(layer)
	_quads.append(layer)


class _GlyphCanvas extends Control:
	var font: Font
	var items: Array = []

	func _draw() -> void:
		var y := 40.0
		for it: Array in items:
			for t: String in it[0]:
				draw_string(font, Vector2(10, y), t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(it[1]), Color(1, 1, 1, 0))
				y += 2.0


## 피해 숫자 글꼴: 쓰는 (크기, 외곽선) 조합의 숫자·상태 글자를 미리 굽는다
func _glyphs() -> void:
	var f := DamageLog.font() as FontFile
	if f == null:
		return
	for base in [DamageLog.SIZE, DamageLog.SIZE_BIG]:
		for sz: int in [roundi(base), roundi(base * 1.6)]:
			var ol := maxi(4, roundi(sz * DamageLog.OUTLINE))
			for o in [0, ol]:
				f.render_range(0, Vector2i(sz, o), "!".unicode_at(0), "Z".unicode_at(0))
