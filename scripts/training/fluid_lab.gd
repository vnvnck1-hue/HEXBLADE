class_name FluidLab
extends TrainingMain
## 유체 연기 시험장 (TrainingMain 상속: 같은 넓은 홀 · 허수아비 · 숫자 키 설정 그대로).
## 홀 바닥에 나비에-스토크스 연기(FluidSmoke)를 깔고 통풍구 넷이 저마다 다른 스타일 프리셋으로 연기를 뿜는다
## (왼쪽 위 MIST 안개 · 오른쪽 위 PUFF 뭉게 · 왼쪽 아래 TOXIC 독가스 · 오른쪽 아래 STEAM 증기).
## 대시·검·휠윈드·E 내려찍기·미사일·Space 청소 질주가 연기를 밀고 가르고 감고 빨아들인다. 연출 전용 (은신 판정 없음).
##
##  F6 통풍구 켜기/끄기   F7 연기 확 채우기 (Shift = 다 지우기)   F8 화면: 연기 ↔ 밀도·스타일 그대로
##  F9 조준점에 폭발 바람   F10 / Shift+F10 모든 통풍구를 한 스타일로 (통풍구마다 → MIST → PUFF → TOXIC → STEAM)
## 확인용 실행 인자: --bot · --fluidfill (시작부터 가득) · --fluidstyle=0~3 (모두 한 스타일)

const VENTS := [Vector3(-8, 0, -5), Vector3(8, 0, -5), Vector3(-8, 0, 5), Vector3(8, 0, 5)]
const VENT_STYLE := [0, 1, 2, 3]

var smoke: FluidSmoke
var _labels: Array[Label3D] = []
var _toxic_lights: Array[OmniLight3D] = []


## FluidField 쓰임새: 시험장은 안개 둑 · 독가스 세트를 만들지 않고 통풍구만 단다
func fluid_mode() -> String:
	return "lab"


func _ready() -> void:
	super._ready()
	smoke = FluidField.inst.smoke
	for i in VENTS.size():
		var p: Vector3 = center + VENTS[i]
		smoke.add_vent(p, VENT_STYLE[i], 1.1)
		_vent_disc(p)
		_labels.append(_vent_label(p))
		# 독가스 통풍구는 바닥을 초록으로 물들이는 약한 빛 (그림자 없음)
		var lt := OmniLight3D.new()
		lt.light_color = FluidSmoke.STYLES[2].glow
		lt.light_energy = 0.0
		lt.omni_range = 5.5
		lt.shadow_enabled = false
		world.add_child(lt)
		lt.global_position = p + Vector3(0, 0.6, 0)
		_toxic_lights.append(lt)
	for a in Main.cmd_args:
		if a.begins_with("--fluidstyle="):
			smoke.force_style = clampi(int(a.substr(13)), -1, 3)
	if Main.cmd_args.has("--fluidfill"):
		smoke.fill(1.0)
	_refresh_vents()
	var note := "통풍구마다 다른 스타일 · 대시 · 검 · 휠윈드 · 내려찍기가 연기를 밀어냅니다 · F6~F10"
	if not smoke.active:
		note = "이 실행 환경에선 GPU 계산이 없어 연기가 그려지지 않습니다"
	hud.banner("FLUID SMOKE", Color(0.75, 0.8, 1.0), note)


## 바닥 통풍구 (어두운 원판 + 격자 살)
func _vent_disc(p: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.7
	cm.bottom_radius = 0.76
	cm.height = 0.05
	cm.radial_segments = 20
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.09, 0.12)
	m.roughness = 0.8
	mi.material_override = m
	world.add_child(mi)
	mi.global_position = p + Vector3(0, 0.025, 0)
	for i in 5:
		var bar := Build.box(world, Vector3(1.1 - absf(i - 2) * 0.22, 0.03, 0.07), Vector3.ZERO, Color(0.28, 0.28, 0.33))
		bar.global_position = p + Vector3(0, 0.06, (i - 2) * 0.22)


## 통풍구 위 스타일 이름표
func _vent_label(p: Vector3) -> Label3D:
	var lb := Label3D.new()
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.font_size = 44
	lb.pixel_size = 0.006
	lb.outline_size = 10
	lb.outline_modulate = Color(0.05, 0.04, 0.1)
	lb.no_depth_test = true
	world.add_child(lb)
	lb.global_position = p + Vector3(0, 2.3, -0.4)
	return lb


func _refresh_vents() -> void:
	for i in _labels.size():
		var st: Dictionary = FluidSmoke.STYLES[smoke.vent_style(i)]
		_labels[i].text = "%s · %s" % [st.name, st.ko]
		_labels[i].modulate = (st.lit as Color).lerp(Color.WHITE, 0.2)
		_toxic_lights[i].light_energy = 0.9 if smoke.vent_style(i) == 2 and smoke.vents_on else 0.0
		_labels[i].visible = not Main.ui_hidden


func _process(dt: float) -> void:
	super._process(dt)
	for lb in _labels:
		lb.visible = not Main.ui_hidden


func _style_title() -> String:
	if smoke.force_style < 0:
		return "통풍구마다 (MIST · PUFF · TOXIC · STEAM)"
	var st: Dictionary = FluidSmoke.STYLES[smoke.force_style]
	return "%s · %s" % [st.name, st.ko]


func _panel_text() -> String:
	var base := super._panel_text()
	var lines := [
		"[ 유체 연기 ]  격자 %d×%d · 칸 %.2fm · %s · CPU %.2fms" % [smoke.nx, smoke.ny, smoke.cell, "GPU" if smoke.active else "GPU 없음", smoke.cpu_usec / 1000.0],
		"F6 통풍구 %s · F7 채우기 (Shift 지우기) · F8 화면 %s · F9 조준점 폭발" % [_onoff(smoke.vents_on), "밀도" if smoke.view_mode == 1 else "연기"],
		"F10 스타일  %s" % _style_title(),
		"Shift+F8 품질  %s" % FluidSmoke.QUALITY_NAMES[FluidSmoke.quality],
		"방출기 %d개" % smoke.emitters.size(),
	]
	return ((base + "\n") if base != "" else "") + "\n".join(lines)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var ke := event as InputEventKey
		var handled := true
		match ke.physical_keycode:
			KEY_F6:
				smoke.vents_on = not smoke.vents_on
				_refresh_vents()
				hud.banner("통풍구  %s" % _onoff(smoke.vents_on), Color(0.75, 0.8, 1.0), "")
			KEY_F7:
				if ke.shift_pressed:
					smoke.clear()
				else:
					smoke.fill(1.0)
			KEY_F8:
				if ke.shift_pressed:
					FluidSmoke.cycle_quality()
					hud.banner("연기 품질  %s" % FluidSmoke.QUALITY_NAMES[FluidSmoke.quality], Color(0.75, 0.8, 1.0), "")
				else:
					smoke.view_mode = 1 - smoke.view_mode
			KEY_F9:
				var at := player.aim_point
				at.y = Main.gy(at)
				FX.shockwave(at + Vector3(0, 0.1, 0), Color(0.8, 0.85, 1.0), 3.0)
				Distortion.burst(at + Vector3(0, 0.5, 0), 3.4, 0.4, 1.3, 1.0)
			KEY_F10:
				# -1(통풍구마다) → 0 → 1 → 2 → 3 → -1
				smoke.force_style = posmod(smoke.force_style + 1 + (-1 if ke.shift_pressed else 1), 5) - 1
				_refresh_vents()
				var desc: String = FluidSmoke.STYLES[smoke.force_style].desc if smoke.force_style >= 0 else "통풍구마다 다른 스타일"
				hud.banner("연기 스타일  %s" % _style_title(), Color(0.75, 0.8, 1.0), desc)
			_:
				handled = false
		if handled:
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)
