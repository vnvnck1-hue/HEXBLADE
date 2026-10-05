class_name RepairHatch
extends Node3D
## 수리키트 해치: 바닥에서 솟아오른 둥근 사일로 해치와, 옆에 선 손잡이 레버.
## 레버 가까이(CRANK_R)에서 F 를 연타하면 한 번 누를 때마다 레버가 한 바퀴 돌고 해치 문이 조금씩 열리며
## 안쪽 승강판에 실린 수리키트가 점점 올라온다 (PRESSES 번이면 활짝). 손을 놓으면 천천히 다시 닫힌다.
## 다 열리면 키트가 튀어 올라 해치 위에 떠 있고, 닿으면 체력 HEAL 회복.
## 돌리는 동안 플레이어는 제자리에 묶이고 공격할 수 없다 (대시로 빠져나갈 수 있고, 맞으면 손을 놓는다).
## 레버·문·키트·플레이어 자세의 과장된 만화 동작은 모두 이 노드가 맡는다 (pose_player 는 Player._animate 끝에서 불린다).

const LEVER_OFF := 1.75
const CRANK_R := 1.45            # 레버 기둥에서 이 거리 안이면 돌릴 수 있다
const PRESSES := 16
const HOLD := 0.32               # 마지막으로 누른 뒤 이 시간 동안 "돌리는 중"
const DECAY_WAIT := 1.3
const DECAY := 0.09              # 손을 놓으면 초당 이만큼 닫힌다
const HEAL := 2
const PICK_R := 1.15
const DOOR_R := 0.9
const WALL_H := 0.62
const LEVER_SCALE := 1.4       # 쿼터뷰에서 레버 동작이 읽히도록 크게
const CREAKS := ["끼릭!", "끼릭끼릭!", "덜컥!", "끼기긱!", "철컥!", "끼릭!"]   ## 손잡이 의성어 (떠오르는 글자)
const SHOUTS := ["영차!", "으랏차!", "끄응…!", "조금만 더!"]                ## 돌리는 메카의 기합 (대사 말풍선)

static var _font: SystemFont
static var _half_disc: ArrayMesh
static var _drop_mesh: SphereMesh
static var _door_mat: StandardMaterial3D

var lever_yaw := 0.0             # 해치 중심에서 레버 쪽 방향 (월드 yaw)
var emerge := true
var progress := 0.0
var done := false
var collected := false
var _rise := 0.0
var _hold := 0.0
var _idle := 99.0
var _presses := 0
var _crank_ang := 0.0
var _crank_target := 0.0
var _crank_v := 0.0
var _crank_squash := 0.0
var _door_l: Node3D
var _door_r: Node3D
var _lift: Node3D
var _kit: Node3D
var _kit_glow: MeshInstance3D
var _lever: Node3D
var _crank: Node3D
var _crank_arm: Node3D
var _prompt: Label3D
var _bar: Label3D
var _root: Node3D
var _kit_t := 0.0
var _sink_t := -1.0
var _full_t := 0
var _light: OmniLight3D
var _holder: Node3D
static var _swoosh_mesh: TorusMesh


static func _shared() -> void:
	if _font:
		return
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Apple SD Gothic Neo", "Noto Sans CJK KR", "sans-serif"])
	_half_disc = _make_half_disc(DOOR_R, 0.06, 12)
	_door_mat = StandardMaterial3D.new()
	_door_mat.albedo_color = Color(0.42, 0.44, 0.52)
	_door_mat.roughness = 0.6
	_door_mat.metallic = 0.3
	_door_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_swoosh_mesh = TorusMesh.new()
	_swoosh_mesh.inner_radius = 0.62
	_swoosh_mesh.outer_radius = 0.7
	_swoosh_mesh.rings = 24
	_swoosh_mesh.ring_segments = 4
	_drop_mesh = SphereMesh.new()
	_drop_mesh.radius = 0.07
	_drop_mesh.height = 0.14
	_drop_mesh.radial_segments = 8
	_drop_mesh.rings = 4


## 반원판 (+X 쪽 절반). 문 두 짝을 이것으로 만든다
static func _make_half_disc(r: float, h: float, seg: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := h * 0.5
	var bot := -h * 0.5
	for i in seg:
		var a0 := -PI * 0.5 + PI * i / seg
		var a1 := -PI * 0.5 + PI * (i + 1) / seg
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		# 윗면
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(0, top, 0))
		st.add_vertex(p1 + Vector3(0, top, 0))
		st.add_vertex(p0 + Vector3(0, top, 0))
		# 옆면
		var n := ((p0 + p1) * 0.5).normalized()
		st.set_normal(n)
		st.add_vertex(p0 + Vector3(0, top, 0))
		st.add_vertex(p1 + Vector3(0, top, 0))
		st.add_vertex(p1 + Vector3(0, bot, 0))
		st.add_vertex(p0 + Vector3(0, top, 0))
		st.add_vertex(p1 + Vector3(0, bot, 0))
		st.add_vertex(p0 + Vector3(0, bot, 0))
	# 곧은 면 (-X 쪽, 맞닿는 이음새)
	st.set_normal(Vector3.LEFT)
	st.add_vertex(Vector3(0, top, -r))
	st.add_vertex(Vector3(0, bot, r))
	st.add_vertex(Vector3(0, top, r))
	st.add_vertex(Vector3(0, top, -r))
	st.add_vertex(Vector3(0, bot, -r))
	st.add_vertex(Vector3(0, bot, r))
	return st.commit()


func _ready() -> void:
	_shared()
	add_to_group("repair_hatches")
	_root = Node3D.new()
	add_child(_root)
	_build_hatch()
	_build_lever()
	_build_labels()
	if emerge:
		_root.position.y = -0.9
		FX.spawn_marker(global_position, 0.6)
		Sfx.play("hrise", 0.05, -6.0)
	else:
		_rise = 1.0


func _build_hatch() -> void:
	# 바깥 벽: 상자 조각을 둥글게 둘러 안이 들여다보이게 한다
	var seg := 20
	for i in seg:
		var a := TAU * i / seg
		var wall := Build.box(_root, Vector3(0.34, WALL_H, 0.3), Vector3(sin(a), 0, cos(a)) * 1.0 + Vector3(0, WALL_H * 0.5, 0), Color(0.3, 0.32, 0.38), Vector3(0, rad_to_deg(a), 0))
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		# 윗테 경고 줄무늬
		Build.box(_root, Vector3(0.35, 0.03, 0.31), Vector3(sin(a), 0, cos(a)) * 1.0 + Vector3(0, WALL_H + 0.015, 0),
			Color(0.95, 0.75, 0.15) if i % 2 == 0 else Color(0.08, 0.08, 0.1), Vector3(0, rad_to_deg(a), 0))
	# 안쪽 바닥: 어두운 원판 + 초록 안내등
	var pit := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.9
	cm.bottom_radius = 0.9
	cm.height = 0.04
	pit.mesh = cm
	pit.material_override = Pal.lit(Color(0.05, 0.05, 0.07))
	pit.position.y = 0.04
	_root.add_child(pit)
	for i in 6:
		var a := TAU * i / 6.0
		Build.box(_root, Vector3(0.06, 0.06, 0.06), Vector3(sin(a) * 0.78, 0.12, cos(a) * 0.78), Color("4dff9a"), Vector3.ZERO, 2.0)
	_light = OmniLight3D.new()
	_light.light_color = Color("6dffb0")
	_light.omni_range = 2.6
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position.y = 0.5
	_root.add_child(_light)
	# 승강판 + 수리키트 (초록 상자 · 흰 십자 · 손잡이)
	_lift = Node3D.new()
	_lift.position.y = 0.07
	_root.add_child(_lift)
	Build.box(_lift, Vector3(1.1, 0.05, 1.1), Vector3.ZERO, Color(0.2, 0.22, 0.26))
	_kit = Node3D.new()
	_lift.add_child(_kit)
	_kit.position.y = 0.2
	Build.bevel(_kit, Vector3(0.66, 0.34, 0.46), Vector3.ZERO, Color("2fbf6a"), 0.04)
	Build.box(_kit, Vector3(0.68, 0.05, 0.48), Vector3(0, 0.0, 0), Color("1e7a46"))
	Build.box(_kit, Vector3(0.3, 0.02, 0.09), Vector3(0, 0.18, 0), Color.WHITE, Vector3.ZERO, 1.6)
	Build.box(_kit, Vector3(0.09, 0.02, 0.3), Vector3(0, 0.18, 0), Color.WHITE, Vector3.ZERO, 1.6)
	Build.box(_kit, Vector3(0.24, 0.05, 0.05), Vector3(0, 0.24, 0.0), Color(0.2, 0.22, 0.26))
	_kit_glow = Pal.flat_mesh(FX._ring_mesh(), Color("7dffb0"), 1.6)
	_kit_glow.scale = Vector3(0.75, 0.2, 0.75)
	_kit_glow.visible = false
	_kit.add_child(_kit_glow)
	# 문 두 짝 (반원판), 레버 쪽과 수직으로 갈라진다
	var doors := Node3D.new()
	doors.rotation.y = lever_yaw
	doors.position.y = WALL_H + 0.06
	_root.add_child(doors)
	_door_r = Node3D.new()
	_door_l = Node3D.new()
	doors.add_child(_door_r)
	doors.add_child(_door_l)
	_door_l.rotation.y = PI
	for d in [_door_r, _door_l]:
		var mi := MeshInstance3D.new()
		mi.mesh = _half_disc
		mi.material_override = _door_mat
		d.add_child(mi)
		# 문 위 경고 화살표 띠와 볼트
		Build.box(d, Vector3(0.1, 0.02, 1.2), Vector3(0.12, 0.04, 0), Color(0.95, 0.75, 0.15))
		Build.box(d, Vector3(0.36, 0.025, 0.12), Vector3(0.45, 0.04, 0), Color(0.15, 0.15, 0.2))


func _build_lever() -> void:
	var holder := Node3D.new()
	_holder = holder
	holder.position = Vector3(sin(lever_yaw), 0, cos(lever_yaw)) * LEVER_OFF
	holder.rotation.y = lever_yaw
	_root.add_child(holder)
	var base := Node3D.new()
	holder.add_child(base)
	_lever = base
	Build.box(base, Vector3(0.5, 0.18, 0.5), Vector3(0, 0.09, 0), Color(0.26, 0.27, 0.33))
	Build.box(base, Vector3(0.16, 0.82, 0.16), Vector3(0, 0.55, 0), Color(0.4, 0.42, 0.5))
	Build.box(base, Vector3(0.34, 0.3, 0.3), Vector3(0, 1.02, 0), Color(0.95, 0.75, 0.15))
	Build.box(base, Vector3(0.36, 0.06, 0.32), Vector3(0, 0.89, 0), Color(0.08, 0.08, 0.1))
	# 해치로 이어진 배관
	Build.box(base, Vector3(0.1, 0.1, LEVER_OFF - 1.0), Vector3(0, 0.06, -(LEVER_OFF - 1.0) * 0.5 - 0.1), Color(0.22, 0.23, 0.29))
	# 손잡이: 기둥 옆(+X) 축을 중심으로 돈다
	_crank = Node3D.new()
	_crank.position = Vector3(0.22, 1.02, 0)
	base.add_child(_crank)
	Build.box(_crank, Vector3(0.1, 0.16, 0.16), Vector3(0.03, 0, 0), Color(0.3, 0.31, 0.38))
	_crank_arm = Node3D.new()
	_crank.add_child(_crank_arm)
	Build.box(_crank_arm, Vector3(0.08, 0.5, 0.09), Vector3(0.1, 0.24, 0), Color(0.62, 0.64, 0.72))
	Build.box(_crank_arm, Vector3(0.3, 0.12, 0.12), Vector3(0.22, 0.48, 0), Color("e03a2a"), Vector3.ZERO, 0.4)


func _build_labels() -> void:
	_prompt = Label3D.new()
	_prompt.font = _font
	_prompt.font_size = 64
	_prompt.pixel_size = 0.006
	_prompt.outline_size = 14
	_prompt.outline_modulate = Color(0.05, 0.04, 0.12)
	_prompt.modulate = Color("ffe070")
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.render_priority = 30
	_prompt.text = "F 연타!"
	_prompt.visible = false
	add_child(_prompt)
	_bar = _prompt.duplicate() as Label3D
	_bar.font_size = 44
	_bar.modulate = Color("7dffb0")
	_bar.text = ""
	add_child(_bar)


func lever_pos() -> Vector3:
	return global_position + Vector3(sin(lever_yaw), 0, cos(lever_yaw)) * LEVER_OFF


func can_crank(p: Vector3) -> bool:
	if done or _rise < 1.0 or _sink_t >= 0.0:
		return false
	var d := p - lever_pos()
	return Vector2(d.x, d.z).length() < CRANK_R


func cranking() -> bool:
	return _hold > 0.0 and not done


## F 한 번: 레버 한 바퀴 + 해치가 1/PRESSES 열린다
func crank(p: Player) -> void:
	if done or p.hurt_t > 0.85:
		return
	_hold = HOLD
	_idle = 0.0
	_presses += 1
	progress = minf(1.0, progress + 1.0 / PRESSES)
	_crank_target += TAU
	_crank_squash = 1.0
	# 플레이어: 매번 크게 출렁인다
	p.squash_v -= 7.0
	var to := lever_pos() - p.global_position
	to.y = 0
	p.tilt_v += to.normalized() * 5.0
	var snd := Sfx.play("clank", 0.08, -7.0)
	if snd:
		snd.pitch_scale = 0.8 + progress * 0.9
	var hub := _crank.global_position
	FX.sparks(hub, 4, [Color.WHITE, Color("ffd060")], 4.5, 0.25, -12.0, 0.04)
	if _presses % 2 == 1:
		# 끼릭끼릭: 손잡이 곁에서 좌우 번갈아 떠오르는 의성어 글자
		var side := 1.0 if (_presses / 2) % 2 == 0 else -1.0
		var off := Vector3(side * randf_range(0.35, 0.7), 0.7 + randf_range(0.0, 0.35), 0)
		Main.inst.hud.popup(CREAKS[(_presses / 2) % CREAKS.size()], Color("ffe070"), hub + off)
	if _presses % 6 == 3:
		SpeechBubble.say(p, SHOUTS[(_presses / 6) % SHOUTS.size()], SpeechBubble.SAY, {"offset": Vector3(0, 2.3, 0)})
	if _presses % 2 == 0:
		_sweat(p)
	_swoosh()
	FX.puffs(p.global_position + Vector3(0, 0.05, 0), 1, [Color("c8c4d8"), Color("a8a4b8"), Color("6a6680"), Color("5a5670")], 0.35, 0.28, 0.4)
	Main.inst.shake(0.05)
	if progress >= 1.0:
		_open_fully()


## 손잡이가 그리는 원을 따라 번쩍이는 회전 잔상 고리 (만화식 속도선)
func _swoosh() -> void:
	var mi := Pal.flat_mesh(_swoosh_mesh, Color(1, 0.95, 0.8), 1.4)
	Main.inst.world.add_child(mi)
	var b := _holder.global_basis * Basis(Vector3.BACK, PI * 0.5)
	mi.global_transform = Transform3D(b.scaled(Vector3.ONE * LEVER_SCALE), _crank.global_position + _holder.global_basis.x * 0.32 * LEVER_SCALE)
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", mi.scale * Vector3(1.25, 0.2, 1.25), 0.16).set_ease(Tween.EASE_OUT)
	tw.tween_callback(mi.queue_free)


## 돌리는 동안 플레이어가 서는 자리: 손잡이 쪽(레버의 +X)으로 조금 떨어진 곳
func stand_spot() -> Vector3:
	return lever_pos() + _holder.global_basis.x * 1.0


func interrupt() -> void:
	_hold = 0.0


## 이마에서 땀방울이 튄다 (만화식 과장)
func _sweat(p: Player) -> void:
	var head := p.global_position + Vector3(0, 1.75, 0)
	for i in 2:
		var mi := Pal.flat_mesh(_drop_mesh, Color("9ad8ff"), 1.4)
		mi.scale = Vector3(0.8, 1.3, 0.8)
		Main.inst.world.add_child(mi)
		mi.global_position = head
		var side := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		var v := side * randf_range(1.6, 2.6) + Vector3(0, randf_range(2.5, 3.5), 0)
		var start := head
		var fly := func(t: float):
			if is_instance_valid(mi):
				mi.global_position = start + v * t + Vector3(0, -7.0 * t * t, 0)
		var tw := mi.create_tween()
		tw.tween_method(fly, 0.0, 0.45, 0.45)
		tw.parallel().tween_property(mi, "scale", Vector3.ONE * 0.2, 0.45).set_delay(0.2)
		tw.tween_callback(mi.queue_free)


func _open_fully() -> void:
	done = true
	_hold = 0.0
	_kit_t = 0.0
	_kit_glow.visible = true
	FX.flash(global_position + Vector3(0, 0.7, 0), Color("b0ffd0"), 1.6, 0.12)
	FX.shockwave(global_position + Vector3(0, 0.45, 0), Color("7dffb0"), 3.0, 0.4)
	FX.sparks(global_position + Vector3(0, 0.6, 0), 18, [Color.WHITE, Color("7dffb0")], 8.0, 0.5, -10.0, 0.06)
	Sfx.play("hatch", 0.05, -2.0)
	Sfx.play("charged", 0.0, -4.0)
	Main.inst.hud.popup("REPAIR KIT!", Color("7dffb0"), global_position + Vector3(0, 2.2, 0))
	Main.inst.hud.popup("덜커덩!", Color("ffe070"), global_position + Vector3(0.6, 1.4, 0))
	Main.inst.shake(0.2)


func _process(dt: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	# 솟아오르기
	if _rise < 1.0:
		_rise = minf(1.0, _rise + dt / 0.7)
		var k := ease(_rise, 0.4)
		_root.position.y = lerpf(-0.9, 0.0, k) + sin(_rise * PI) * 0.12
		if _rise >= 1.0:
			_root.position.y = 0.0
			FX.land_dust(global_position)
			Sfx.play("hatch", 0.05, -4.0)
			Main.inst.shake(0.15)
	if _sink_t >= 0.0:
		_sink_t += dt
		_root.position.y = -ease(clampf(_sink_t / 0.8, 0.0, 1.0), 2.0) * 0.95
		if _sink_t >= 0.8:
			queue_free()
		return
	_hold = maxf(0.0, _hold - dt)
	_idle += dt
	if not done and _idle > DECAY_WAIT and progress > 0.0:
		progress = maxf(0.0, progress - DECAY * dt)
	# 레버: 한 바퀴씩 휙 돌고 살짝 넘쳤다 돌아온다. 빠를수록 손잡이가 늘어진다 (만화식 잔상)
	_crank_v += ((_crank_target - _crank_ang) * 300.0 - _crank_v * 17.0) * dt
	_crank_ang += _crank_v * dt
	_crank.rotation.x = -_crank_ang
	var stretch := clampf(absf(_crank_v) / 40.0, 0.0, 0.6)
	_crank_arm.scale = Vector3(1.0 - stretch * 0.25, 1.0 + stretch, 1.0 - stretch * 0.25)
	_crank_squash = move_toward(_crank_squash, 0.0, dt * 5.0)
	var sq := _crank_squash * 0.12 * sin(_crank_squash * 12.0)
	_lever.scale = Vector3(1.0 + sq, 1.0 - sq, 1.0 + sq) * LEVER_SCALE
	# 문 · 승강판 · 키트
	var open := ease(progress, 0.6)
	var door_x := open * 0.95 + (sin(t * 60.0) * 0.006 if _hold > 0.0 else 0.0)
	_door_r.position.x = door_x
	_door_l.position.x = -door_x
	_light.light_energy = open * 1.6
	if not done:
		# 문이 어느 정도 벌어진 뒤부터 키트가 올라와 틈으로 모습을 드러낸다
		_lift.position.y = lerpf(0.07, 0.5, smoothstep(0.3, 1.0, open))
		_kit.rotation.y = sin(t * 2.0) * 0.08 * open
	elif not collected:
		# 다 열리면 키트가 튀어 올라 해치 위에서 빙글 돈다
		_kit_t += dt
		var up := 1.0 - pow(1.0 - clampf(_kit_t / 0.45, 0.0, 1.0), 3.0)
		_lift.position.y = lerpf(0.5, 0.62, up)
		_kit.position.y = 0.2 + up * 0.75 + sin(_kit_t * 3.0) * 0.08 * up
		_kit.rotation.y += dt * 2.4
		_kit_glow.rotation.y -= dt * 4.0
		_check_pick()
	# 안내 문구 · 진행 막대
	var p: Player = Main.inst.player
	var near := is_instance_valid(p) and p.alive and can_crank(p.global_position)
	_prompt.visible = near
	if near:
		var lp := lever_pos() - global_position
		var shake := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * (0.03 if _hold > 0.0 else 0.0)
		_prompt.position = lp + Vector3(0, 2.25 + sin(t * 8.0) * 0.06, 0) + shake
		_prompt.scale = Vector3.ONE * (1.0 + 0.12 * absf(sin(t * 10.0)))
	_bar.visible = progress > 0.0 and not done
	if _bar.visible:
		var cells := int(round(progress * 10.0))
		_bar.text = "■".repeat(cells) + "□".repeat(10 - cells)
		_bar.position = Vector3(0, 1.55, 0)


func _check_pick() -> void:
	if _kit_t < 0.45:
		return
	var p: Player = Main.inst.player
	if not is_instance_valid(p) or not p.alive:
		return
	var d := p.global_position - global_position
	if Vector2(d.x, d.z).length() > PICK_R:
		return
	if p.hp >= Player.MAX_HP:
		var now := Time.get_ticks_msec()
		if now - _full_t > 1200:
			_full_t = now
			Main.inst.hud.popup("FULL HP", Color("b8c8ff"), global_position + Vector3(0, 2.0, 0))
		return
	collected = true
	var gain := mini(HEAL, Player.MAX_HP - p.hp)
	p.hp += gain
	_kit.visible = false
	FX.flash(p.global_position + Vector3(0, 0.9, 0), Color("b0ffd0"), 1.5, 0.12)
	FX.shockwave(p.global_position + Vector3(0, 0.1, 0), Color("7dffb0"), 2.4, 0.35)
	FX.sparks(p.global_position + Vector3(0, 0.9, 0), 16, [Color.WHITE, Color("7dffb0")], 6.0, 0.6, 3.0, 0.05)
	Sfx.play("ready", 0.0, -2.0)
	Sfx.play("charged", 0.0, -6.0)
	Main.inst.hud.popup("+%d HP" % gain, Color("7dffb0"), p.global_position + Vector3(0, 2.3, 0))
	print("REPAIR_KIT hp=%d" % p.hp)
	# 문을 닫고 바닥으로 가라앉는다
	var tw := create_tween()
	tw.tween_property(self, "progress", 0.0, 0.5).set_delay(0.6)
	tw.tween_callback(func(): _sink_t = 0.0)


## Player._animate 끝에서 불린다: 레버 쪽을 보고, 칼 팔로 손잡이를 따라 큰 원을 그리며, 몸 전체가 펌프질한다
func pose_player(p: Player, dt: float) -> void:
	var j := p.j
	var to := _crank.global_position - p.global_position
	to.y = 0
	var yaw := atan2(-to.x, -to.z)
	var legs: Node3D = j.legs
	var upper: Node3D = j.upper
	var torso: Node3D = j.torso
	legs.rotation.y = lerp_angle(legs.rotation.y, yaw, 1.0 - exp(-20.0 * dt))
	upper.rotation.y = lerp_angle(upper.rotation.y, yaw + 0.35, 1.0 - exp(-25.0 * dt))
	var ph := _crank_ang
	# 상체를 숙였다 폈다 (한 바퀴에 한 번)
	torso.rotation.x = -0.32 - sin(ph) * 0.18
	torso.rotation.z = cos(ph) * 0.14
	var arm_r: Node3D = j.arm_r
	# 손잡이가 그리는 세로 원을 칼 팔이 크게 따라 그린다 (실제보다 과장)
	arm_r.rotation = Vector3(1.3 + sin(ph) * 0.7, 0.0, cos(ph) * 0.7)
	var arm_l: Node3D = j.arm_l
	arm_l.rotation = Vector3(0.5 + sin(ph + PI) * 0.35, 0.0, 0.45 + cos(ph) * 0.2)
	if j.has("blade"):
		(j.blade as Node3D).scale = (j.blade as Node3D).scale.lerp(Vector3.ONE * 0.05, 0.4)
