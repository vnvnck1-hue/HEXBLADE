extends CanvasLayer
## 심연 성소 전용 화면 표시 (기본 HUD 위에 덧붙인다).
##  - 위 가운데: 레이어 이름 · 페이즈 진행 칸 · 남은 적
##  - 오른쪽 위: 공명 고리 (킬 나이트의 킬 파워). 결정을 모으면 단계가 오르고, 맞으면 깎인다.

const ACC := Color(1.0, 0.16, 0.26)
const TEAL := Color(0.3, 1.0, 0.72)

var root: Control
var font: SystemFont
var layer_name := "LAYER 01  ·  심연 성소"
var phase := 0
var phase_count := 6
var phase_name := ""
var left := 0
var res_level := 0
var res_k := 0.0
var res_shown := 0.0
var res_flash := 0.0
var res_mult := 1.0
var trap_text := ""
var t := 0.0
var top := 0.0              # 보스 체력바가 있으면 아래로 내린다


func _ready() -> void:
	layer = 11
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "맑은 고딕", "Noto Sans CJK KR", "sans-serif"])
	font.font_weight = 700
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.draw.connect(_draw_root)
	add_child(root)


func flash_res() -> void:
	res_flash = 1.0


func _process(dt: float) -> void:
	var rdt := dt / maxf(Engine.time_scale, 0.01)
	t += rdt
	res_shown = move_toward(res_shown, res_k, rdt * 2.5)
	res_flash = maxf(0.0, res_flash - rdt * 2.0)
	root.queue_redraw()


func _draw_root() -> void:
	var sz := root.size
	# ── 위 가운데: 레이어 · 페이즈 칸 ──
	var cx := sz.x * 0.5
	var y0 := top
	var title := layer_name
	if top > 0.0:
		# 보스전: 위쪽은 보스 체력바 자리다. 페이즈 칸만 체력바 아래 오른쪽에 작게 둔다.
		_draw_res(sz)
		var x1 := sz.x * 0.5 + 250.0
		for i in phase_count:
			var r2 := Rect2(x1 + i * 16.0, 70, 12, 5)
			root.draw_rect(r2, Color(0.7, 0.1, 0.16, 0.9) if i < phase else (ACC if i == phase else Color(0.22, 0.05, 0.08, 0.8)))
		return
	var tw := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	root.draw_string(font, Vector2(cx - tw * 0.5, 30 + y0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1, 0.85, 0.86, 0.9))
	var cell_w := 34.0
	var gap := 6.0
	var total := phase_count * cell_w + (phase_count - 1) * gap
	var x0 := cx - total * 0.5
	for i in phase_count:
		var r := Rect2(x0 + i * (cell_w + gap), 40 + y0, cell_w, 7)
		var c := Color(0.22, 0.05, 0.08, 0.8)
		if i < phase:
			c = Color(0.7, 0.1, 0.16, 0.9)
		elif i == phase:
			c = ACC.lerp(Color.WHITE, 0.25 + 0.25 * sin(t * 6.0))
		root.draw_rect(r, c)
		if i == phase_count - 1:
			root.draw_rect(r.grow(2.0), Color(1, 0.3, 0.35, 0.6), false, 1.0)
	var sub := phase_name
	if left > 0:
		sub += "   ·   남은 적 %d" % left
	if trap_text != "":
		sub += "   ·   " + trap_text
	var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	root.draw_string(font, Vector2(cx - sw * 0.5, 68 + y0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.7, 0.72, 0.85))
	_draw_res(sz)


## 오른쪽 위: 공명 고리
func _draw_res(sz: Vector2) -> void:
	var c0 := Vector2(sz.x - 70, 262)
	var rr := 34.0
	root.draw_arc(c0, rr, 0, TAU, 48, Color(0.15, 0.04, 0.07, 0.85), 7.0)
	var col := TEAL.lerp(Color.WHITE, res_flash * 0.6)
	if res_shown > 0.0:
		root.draw_arc(c0, rr, -PI * 0.5, -PI * 0.5 + TAU * res_shown, 48, col, 7.0)
	for k in 5:
		var a := -PI * 0.5 + TAU * k / 5.0
		root.draw_line(c0 + Vector2(cos(a), sin(a)) * (rr - 5), c0 + Vector2(cos(a), sin(a)) * (rr + 5), Color(0, 0, 0, 0.7), 2.0)
	var num := str(res_level)
	var nw := font.get_string_size(num, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	root.draw_string(font, c0 + Vector2(-nw * 0.5, 11), num, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, col)
	var lab := "RESONANCE"
	var lw := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	root.draw_string(font, c0 + Vector2(-lw * 0.5, rr + 22), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 1.0, 0.9, 0.8))
	var m := "×%.2f" % res_mult
	var mw := font.get_string_size(m, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	root.draw_string(font, c0 + Vector2(-mw * 0.5, rr + 38), m, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 1.0, 0.95, 0.75))
