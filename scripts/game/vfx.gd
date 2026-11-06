extends Node
## Частицы движка Godot (автозагрузка Vfx) поверх немедленной отрисовки Ctx: CPUParticles2D считаются в C++
## (а не в GDScript, как FX) и одинаково работают на телефоне, в Windows и в браузере.
##  • след двигателя корабля игрока — частицы остаются в пространстве, поэтому при манёврах шлейф изгибается;
##  • снопы искр крупных взрывов (смерть босса, бомба, мини-боссы) — сотни вытянутых по скорости искр.
## Узлы — дети мира (того же холста, что и Ctx) и встают в порядок рисования через ctx.embed().
##   Vfx.attach(world) — один раз; Vfx.wake(ctx, …) — в drawPlayer перед кораблём;
##   Vfx.burst(x, y, цвет, сила) — сноп (координаты поля, как у FX); Vfx.draw(ctx) — встроить снопы;
##   Vfx.frame() — после кадра: что в этом кадре не рисовали — прячем; на паузе частицы замирают.

const BURSTS := 8

var root: Node2D
var _wake: CPUParticles2D
var _wake_col := ""
var _wake_on := false
var _bursts: Array[CPUParticles2D] = []
var _left: Array[float] = []
var _bi := 0
var _drawn := false
var _add: CanvasItemMaterial


func attach(world: Node2D) -> void:
	root = world
	_add = CanvasItemMaterial.new()
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_wake = _make_wake()
	world.add_child(_wake)
	for i in BURSTS:
		var b := _make_burst()
		world.add_child(b)
		_bursts.append(b)
		_left.append(0.0)


func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for p in points: c.add_point(Vector2(p[0], p[1]))
	return c


func _ramp(offsets: Array, alphas: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	var cols := PackedColorArray()
	for a in alphas: cols.append(Color(1, 1, 1, a))
	g.colors = cols
	return g


## мягкая точка (след) и вытянутая искра (снопы)
func _tex(w: int, h: int) -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = w
	t.height = h
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


func _make_wake() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = 72
	p.lifetime = 0.45
	p.local_coords = false
	p.texture = _tex(32, 32)
	p.material = _add
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0, 1)
	p.spread = 7.0
	p.gravity = Vector2.ZERO
	p.scale_amount_curve = _curve([[0.0, 1.0], [1.0, 0.0]])
	p.color_ramp = _ramp([0.0, 0.25, 1.0], [0.85, 0.55, 0.0])
	p.emitting = false
	p.visible = false
	return p


func _make_burst() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.local_coords = false
	p.texture = _tex(10, 40)
	p.material = _add
	p.particle_flag_align_y = true      # искра вытянута вдоль своей скорости
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.scale_amount_curve = _curve([[0.0, 1.0], [0.6, 0.7], [1.0, 0.0]])
	p.color_ramp = _ramp([0.0, 0.15, 1.0], [0.85, 0.7, 0.0])
	p.emitting = false
	p.visible = false
	return p


## след двигателя: x, y — центр сопел на поле, w — ширина корабля, color — цвет пламени скина
func wake(ctx: Ctx, x: float, y: float, w: float, color: String, boost := 1.0) -> void:
	if root == null or Main.quality == 0: return
	var S := G.S
	_wake.position = Vector2(x + G.FX + FX.shake_x, y + FX.shake_y)
	_wake.emission_rect_extents = Vector2(w * 0.1, 2 * S)
	_wake.initial_velocity_min = 70 * S * boost
	_wake.initial_velocity_max = 120 * S * boost
	_wake.scale_amount_min = w / 32.0 * 0.22
	_wake.scale_amount_max = w / 32.0 * 0.34
	if color != _wake_col:
		_wake_col = color
		_wake.color = U.col(color)
	if not _wake.emitting: _wake.emitting = true
	_wake.visible = true
	_wake_on = true
	ctx.embed(_wake.get_canvas_item())


## сноп искр: power ≈ 0.6 — крупный взрыв, 1.5 — бомба/супервзрыв, 3 — смерть босса
func burst(x: float, y: float, color: String, power := 1.0) -> void:
	if root == null or Main.quality == 0: return
	var S := G.S
	var b := _bursts[_bi]
	_left[_bi] = 0.6 + 0.25 * power
	_bi = (_bi + 1) % BURSTS
	b.position = Vector2(x + G.FX + FX.shake_x, y + FX.shake_y)
	b.amount = int(clampf(36.0 * power, 16, 150) * (1.0 if Main.quality >= 2 else 0.6))
	b.lifetime = 0.45 + 0.2 * power
	b.emission_sphere_radius = 6 * S * sqrt(power)
	b.initial_velocity_min = 140 * S * sqrt(power)
	b.initial_velocity_max = 520 * S * sqrt(power)
	b.damping_min = 260 * S
	b.damping_max = 520 * S
	b.scale_amount_min = 0.35 * S
	b.scale_amount_max = (0.7 + 0.1 * power) * S
	b.color = U.col(color).lerp(Color.WHITE, 0.1)
	b.visible = true
	b.restart()


## встроить живые снопы в текущее место порядка рисования (в Game.draw — вместе с FX.draw_front)
func draw(ctx: Ctx) -> void:
	if root == null: return
	_drawn = true
	for i in BURSTS:
		if _left[i] > 0: ctx.embed(_bursts[i].get_canvas_item())


func frame(dt: float) -> void:
	if root == null: return
	# на паузе и в окнах выбора частицы замирают вместе с игрой
	var sp := 1.0 if Game.state in ["play", "cutscene", "idle", "over"] else 0.0
	_wake.speed_scale = sp
	if not _wake_on:
		_wake.emitting = false
		_wake.visible = false
	_wake_on = false
	for i in BURSTS:
		var b := _bursts[i]
		b.speed_scale = sp
		_left[i] = maxf(0.0, _left[i] - dt * sp)
		b.visible = _left[i] > 0 and _drawn
	_drawn = false


func clear() -> void:
	for i in _bursts.size():
		_left[i] = 0.0
		_bursts[i].visible = false
		_bursts[i].emitting = false
