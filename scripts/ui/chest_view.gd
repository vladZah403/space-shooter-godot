class_name ChestOpenView
extends Control
## Открытие контейнера на экране итогов (Godot): контейнер падает и подпрыгивает, трясётся сильнее и сильнее,
## створки крышки распахиваются «крыльями» (G.draw_chest), вверх бьёт луч цвета редкости, ксенотех взлетает
## под вращающиеся лучи с искрами, затем карточка: редкость, название, описание (у повтора — сколько кредитов
## взамен). Касание во время анимации — сразу к карточке; касание на карточке — закрыть.
##   Ui.chest_v.play(tier, результат M.openChest(), по_закрытию)

const T_DROP := 0.35
const T_SHAKE := 1.05
const T_OPEN := 1.35
const T_RISE := 1.9

var t := 0.0
var tier := "bronze"
var res: Dictionary = {}
var rel: Dictionary = {}
var col := Color.WHITE
var on_done: Callable
var canvas: Control
var card: PanelContainer
var c_rar: Label
var c_name: Label
var c_desc: Label
var c_hint: Label
var _sparks: Array = []    # { p: Vector2, v: Vector2, life, max, size }
var _boomed := false
var _frame: Array = []    # кадр спрайта ксенотеха в атласе (G.frame)


func _ready() -> void:
	Kit.full(self)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := Kit.dim(0.88)
	add_child(dim)
	canvas = Kit.ctx_view(func(c: Ctx, sz: Vector2, _tt: float): _draw_scene(c, sz), Vector2(10, 10))
	Kit.full(canvas)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	card = Kit.panel(16, Color(Kit.PANEL_SOLID, 0.96), Color(Kit.GOLD, 0.6), 18)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := Kit.vbox(6)
	c_rar = Kit.label("", 12, Kit.GOLD, 900, HORIZONTAL_ALIGNMENT_CENTER)
	c_name = Kit.label("", 22, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER)
	c_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	c_desc = Kit.para("", 14, Kit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	c_hint = Kit.label(Lang.t("касание — дальше"), 11, Kit.DIM, 700, HORIZONTAL_ALIGNMENT_CENTER)
	for l in [c_rar, c_name, c_desc, c_hint]: v.add_child(l)
	card.add_child(v)
	add_child(card)


func play(chest_tier: String, result: Dictionary, done := Callable()) -> void:
	tier = chest_tier
	res = result
	rel = D.RELICS.get(res.get("id", ""), {})
	var rar: Dictionary = D.RELIC_RARITY.get(rel.get("rar", "common"), {})
	col = U.col(rar.get("color", "#7fe7ff"))
	on_done = done
	_frame = G.frame(str(res.get("id", "")))   # спрайт ксенотеха называется как его id (r_lens…)
	t = 0.0
	_boomed = false
	_sparks.clear()
	c_rar.text = (Lang.t("ПОВТОР") + " · " if res.get("dupe", false) else "") + str(rar.get("name", "")).to_upper()
	c_rar.add_theme_color_override("font_color", col)
	c_name.text = str(rel.get("name", ""))
	c_desc.text = str(rel.get("desc", "")) + ((Lang.t("\n\nУже в коллекции — взамен ◆ %d") % int(res.get("coins", 0))) if res.get("dupe", false) else Lang.t("\n\nДобавлен в коллекцию"))
	var sb: StyleBox = card.get_theme_stylebox("panel")
	if sb is NeoBox: (sb as NeoBox).edge = Color(col, 0.75)
	card.modulate.a = 0.0
	visible = true
	A.play("click", {"rate": 0.7})


func _gui_input(e: InputEvent) -> void:
	var tap: bool = (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed)
	if not tap: return
	accept_event()
	if t < T_RISE + 0.35:
		t = T_RISE + 0.35   # пропустить анимацию
		if not _boomed: _boom()
	else:
		visible = false
		if on_done.is_valid(): on_done.call()


func _process(dt: float) -> void:
	if not visible: return
	t += dt
	if t >= T_OPEN and not _boomed: _boom()
	if t < T_SHAKE and t > T_DROP and fmod(t, 0.18) < dt: A.play("hit", {"rate": 1.4 + t * 0.3, "vol": 0.35})
	for s: Dictionary in _sparks:
		s.p += s.v * dt
		s.v *= 1.0 - dt * 1.6
		s.v.y += 120.0 * dt
		s.life -= dt
	_sparks = _sparks.filter(func(s): return s.life > 0)
	card.modulate.a = clampf((t - T_RISE) / 0.3, 0, 1)
	var w := minf(size.x - 40.0, 330.0)
	c_name.custom_minimum_size.x = w - 32.0
	c_desc.custom_minimum_size.x = w - 32.0
	card.size = Vector2(w, 0)
	card.size = card.get_combined_minimum_size()
	card.position = Vector2((size.x - card.size.x) / 2.0, size.y * 0.56)


func _boom() -> void:
	_boomed = true
	A.play("achievement")
	Haptic.success()
	var c := _chest_pos(size)
	for i in 70:
		var a := randf() * TAU
		var sp := randf_range(140.0, 520.0)
		_sparks.append({"p": c + Vector2(0, -20), "v": Vector2(cos(a) * sp, sin(a) * sp - 160.0), "life": randf_range(0.5, 1.2), "max": 1.2, "size": randf_range(6.0, 16.0)})


func _chest_pos(sz: Vector2) -> Vector2:
	return Vector2(sz.x / 2.0, sz.y * 0.42)


func _draw_scene(c: Ctx, sz: Vector2) -> void:
	var cp := _chest_pos(sz)
	var cw := minf(sz.x * 0.42, 170.0)
	# падение с отскоком
	var drop := clampf(t / T_DROP, 0, 1)
	var bounce := (1.0 - drop) * -sz.y * 0.5 + (sin(drop * PI) * -18.0 if drop >= 1.0 else 0.0)
	var y := cp.y + (bounce if drop < 1.0 else 0.0)
	var shake := clampf((t - T_DROP) / (T_SHAKE - T_DROP), 0, 1) if t < T_OPEN else 0.0
	var open := clampf((t - T_SHAKE) / (T_OPEN - T_SHAKE), 0, 1)
	var after := maxf(0.0, t - T_OPEN)
	# лучи сзади (вращаются) и луч вверх из контейнера
	if open > 0.0:
		c.additive = true
		var ray_a := minf(1.0, after * 3.0)
		var ic := cp + Vector2(0, -cw * 0.95 * minf(1.0, after / 0.5))
		c.save(); c.translate(ic.x, ic.y); c.rotate(t * 0.6)
		for i in 12:
			c.rotate(TAU / 12.0)
			c.alpha = 0.16 * ray_a
			c.fill_poly(PackedVector2Array([Vector2(0, 0), Vector2(-14, -sz.y * 0.5), Vector2(14, -sz.y * 0.5)]),
				PackedColorArray([Color(col, 0.9), Color(col, 0.0), Color(col, 0.0)]))
		c.restore()
		var bw := cw * (0.5 + 0.4 * open)
		c.alpha = open * (1.0 - minf(1.0, after / 1.6)) * 0.9 + 0.15
		c.fill_poly(PackedVector2Array([Vector2(cp.x - bw * 0.35, y), Vector2(cp.x + bw * 0.35, y), Vector2(cp.x + bw, -10), Vector2(cp.x - bw, -10)]),
			PackedColorArray([Color(col, 0.95), Color(col, 0.95), Color(col, 0.0), Color(col, 0.0)]))
		c.alpha = 0.7 * ray_a
		var gs := cw * 2.6
		c.draw_tex(G.soft(col.to_html(false), 64), ic.x - gs / 2, ic.y - gs / 2, gs, gs)
		c.additive = false
		c.alpha = 1.0
	# сам контейнер
	var sx := sin(t * 60.0) * 5.0 * shake * shake
	G.draw_chest(c, tier, cp.x + sx, y, cw, open, shake)
	# ксенотех взлетает
	if after > 0.0:
		var k := minf(1.0, after / 0.5)
		var e := 1.0 - pow(1.0 - k, 3.0)
		var ip := cp + Vector2(0, -cw * 0.95 * e)
		var isz := cw * (0.3 + 0.45 * e) * (1.0 + 0.05 * sin(t * 5.0))
		c.alpha = k
		if not _frame.is_empty():
			var f := _frame
			c.draw_image(G.src(f), f[0], f[1], f[2], f[3], ip.x - isz / 2, ip.y - isz / 2, isz, isz)
		else:
			c.fill = Color.WHITE
			c.fill_text(str(rel.get("ico", "✦")), ip.x, ip.y + isz * 0.35, int(isz), 1)
		c.alpha = 1.0
	# искры
	if not _sparks.is_empty():
		c.additive = true
		var tex := G.soft(col.to_html(false), 32)
		for s: Dictionary in _sparks:
			c.alpha = clampf(s.life / s.max, 0, 1)
			c.draw_tex(tex, s.p.x - s.size / 2, s.p.y - s.size / 2, s.size, s.size)
		c.additive = false
		c.alpha = 1.0
	# вспышка в момент открытия
	if after > 0.0 and after < 0.25:
		c.additive = true
		c.alpha = (1.0 - after / 0.25) * 0.6
		c.fill = Color(col.lightened(0.5), 1.0)
		c.fill_rect(0, 0, sz.x, sz.y)
		c.additive = false
		c.alpha = 1.0
