extends Enemy
## 심연 성소 적의 공통 바탕. Enemy 의 피격·경직·체력바·절단 연출·락온은 그대로 쓰고,
## 기본 드론의 이동·사격·거리 벌리기 대신 하위 기체가 _ai() 를 직접 짠다.
##  - 공격 예고: 몸 전체에 붉은 빛을 덮는다 (set_tele). 패링 예고(금빛)와 색으로 구별된다.
##  - 피격: 체액이 튀고 바닥에 얼룩이 남는다.
##  - 처치: 검이면 Enemy 의 절단 연출, 그 밖에는 하위 기체의 _begin_death()/_death_tick() 연출.
## 바탕 색: 뼈빛 갑각 · 흑철 · 짙은 살 · 붉은 눈.

const BONE := Color("a89a80")
const BONE_DARK := Color("6e6252")
const IRON := Color("2b292e")
const IRON_LIGHT := Color("47434a")
const FLESH := Color("6a1722")
const EYE := Color(1.0, 0.1, 0.18)

static var _tele_mat: ShaderMaterial

var tele_glow := false
var custom_death := false
var st := 0                      # 하위 기체 상태
var st_t := 0.0
var spawn_info: Dictionary = {}  # 등장 방식 (기어오를 가장자리 등)
var _splat_cd := 0.0


func _ready() -> void:
	super._ready()
	evade.chance = 0.0
	orb_chance = 0.0


## 공격 예고 발광: 가장자리가 강하게 맥동하는 진홍빛
static func tele_material() -> ShaderMaterial:
	if _tele_mat == null:
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, shadows_disabled;
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 1.4);
	float pulse = 0.5 + 0.5 * sin(TIME * 38.0);
	ALBEDO = mix(vec3(1.0, 0.05, 0.12), vec3(1.0, 0.75, 0.75), rim * 0.6) * 2.6;
	ALPHA = clamp(0.22 + pulse * 0.25 + rim * 0.9, 0.0, 1.0);
}
"""
		_tele_mat = ShaderMaterial.new()
		_tele_mat.shader = sh
	return _tele_mat


## 개체마다 따로 쓰는 발광 머티리얼 (눈·코어 밝기를 따로 바꾼다)
static func glow_mat(c: Color, e: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = e
	m.roughness = 0.4
	return m


func set_tele(on: bool) -> void:
	if tele_glow == on:
		return
	tele_glow = on
	_set_flash(flash_t > 0.0)


func _set_flash(on: bool) -> void:
	var rest: Material = Pal.lock_hatch() if locked else (tele_material() if tele_glow else null)
	if glow_t > 0.0:
		rest = Pal.parry_flash()
	if not is_instance_valid(j.get("body")):
		return
	for mi in (j.body as Node3D).find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_overlay = Pal.flash() if on else rest


func _physics_process(dt: float) -> void:
	if dying:
		_update_death(dt)
		return
	if not alive:
		return
	if max_hp == 0:
		_init_hp()
	t += dt
	_splat_cd -= dt
	_update_hp_bar(dt)
	if not landed:
		_update_entry(dt)
		return
	if stagger_t > 0.0:
		set_tele(false)
		_update_stagger(dt)
	elif hurt_t > 0.0:
		_update_hurt(dt)
	else:
		st_t += dt
		_ai(dt)
	punch = move_toward(punch, 0.0, dt * 6.0)
	_punch_scale()
	if flash_t > 0.0:
		flash_t -= dt
		if flash_t <= 0.0:
			_set_flash(false)
	if glow_t > 0.0:
		glow_t -= dt
		if glow_t <= 0.0:
			_set_flash(flash_t > 0.0)


## 피격 반동 크기 (하위 기체가 몸체 크기에 맞게 덮어쓴다)
func _punch_scale() -> void:
	(j.body as Node3D).scale = Vector3(1.0 + punch * 0.18, 1.0 - punch * 0.12, 1.0 + punch * 0.18)


func _ai(_dt: float) -> void:
	pass


func go(s: int) -> void:
	st = s
	st_t = 0.0


## 플레이어 쪽 수평 방향과 거리
func to_player() -> Array:
	var d := Main.inst.player.global_position - global_position
	d.y = 0
	var l := d.length()
	return [d / maxf(l, 0.001), l]


## 서로 겹치지 않게 밀어내는 힘
func separation(r := 1.6) -> Vector3:
	var out := Vector3.ZERO
	for o in get_tree().get_nodes_in_group("enemies"):
		if o == self:
			continue
		var d: Vector3 = global_position - (o as Node3D).global_position
		d.y = 0
		var l := d.length()
		var rr := r + (o as Enemy).radius * 0.5
		if l < rr and l > 0.001:
			out += d / l * (rr - l)
	return out


func face(dir: Vector3, dt: float, rate: float) -> void:
	if dir.length() < 0.01:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-rate * dt))


func forward() -> Vector3:
	var f := -global_basis.z
	f.y = 0
	return f.normalized()


func active() -> bool:
	return Main.inst.player.alive and Main.inst.state == Main.State.PLAY


func take_hit(dmg: int, dir: Vector3, pos: Vector3, source := "bullet") -> void:
	if not alive:
		return
	super.take_hit(dmg, dir, pos, source)
	if _splat_cd <= 0.0 and is_inside_tree():
		_splat_cd = 0.12
		var c := (j.body as Node3D).global_position
		FX.sparks(c, 5, [Color(1.0, 0.4, 0.4), AbyssFX.ICHOR_HOT, AbyssFX.ICHOR], 5.0, 0.35, -14.0, 0.07)
		if randf() < 0.4:
			AbyssFX.splat(global_position + Vector3(dir.x, 0, dir.z).normalized() * randf_range(0.4, 1.2), randf_range(0.5, 1.0), 0.5)


## 맞으면 진행 중이던 공격 예고를 끈다
func _on_stagger() -> void:
	set_tele(false)


func die(dir := Vector3.ZERO, source := "bullet") -> void:
	if not alive:
		return
	if source == "slash" or source == "phantom":
		set_tele(false)
		super.die(dir, source)
		AbyssFX.ichor_burst((j.body as Node3D).global_position, dir, slice_size.length() * 0.9)
		return
	alive = false
	dying = true
	custom_death = true
	death_t = 0.0
	remove_from_group("enemies")
	death_dir = Vector3(dir.x, 0, dir.z)
	if death_dir.length() < 0.01:
		death_dir = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
	death_dir = death_dir.normalized()
	kill_source = source
	locked = false
	warn_glow = false
	tele_glow = false
	if is_instance_valid(hp_bar):
		hp_bar.queue_free()
	if is_instance_valid(stun_halo):
		stun_halo.queue_free()
	_set_flash(false)
	Main.inst.on_enemy_killed(self)
	_begin_death()


func _update_death(dt: float) -> void:
	if not custom_death:
		super._update_death(dt)
		return
	death_t += dt
	_death_tick(dt)


## 기본 처치 연출: 체액을 터뜨리고 몸체를 조각내 흩뿌린다
func _begin_death() -> void:
	var body := j.body as Node3D
	var c := body.global_position
	AbyssFX.ichor_burst(c, death_dir, slice_size.length() * 0.9)
	AbyssFX.light_flash(c + Vector3(0, 0.6, 0), AbyssFX.ICHOR_HOT, 3.0, 4.5, 0.25)
	FX.flash(c, Color(1.0, 0.75, 0.75), 0.9, 0.07)
	Debris.burst(body, c - Vector3(0, 0.2, 0), 6.0, 5.0, death_dir * 2.5)
	Sfx.play("boom", 0.15, -6.0)
	dying = false
	queue_free()


func _death_tick(_dt: float) -> void:
	pass
