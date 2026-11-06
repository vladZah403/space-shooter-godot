extends Node
## Вступительная заставка при запуске (автозагрузка Intro) — перенос intro.js. Короткая сцена (≈8 с) поверх меню:
## прыжок из гиперпространства, флот Оверлорда выходит из порталов, корабль игрока сбивает разведку и уходит
## в бой. Касание пропускает заставку; отключается в настройках («Заставка при запуске»).
## Звёзды гиперпрыжка (warpStars/warpStep/warpDraw) — общие с прыжком между секторами (Game.jumpScene).

const DUR := 8.4
## подписи: начало, конец, текст
const CAPS := [[0.5, 2.4, "2387 ГОД · ОРБИТА ЗЕМЛИ"], [2.6, 4.5, "Флот Оверлорда прорвал оборону"], [4.7, 6.3, "Остался только ты, пилот"]]

var playing := false
var _layer: CanvasLayer
var _view: Control
var _ctx: Ctx
var _cap: Label
var _logo: Control
var _t := 0.0
var _done: Callable
var _stars: Array = []
var _fleet: Array = []
var _shots: Array = []
var _booms: Array = []
var _said := {}
var _capIdx := -1


static func ease3(k: float) -> float:
	return 1 - pow(1 - clampf(k, 0, 1), 3)


## done вызывается, когда заставка закончилась или пропущена
func play(done: Callable) -> void:
	_done = done
	_t = 0.0
	_said.clear()
	_capIdx = -1
	_stars = warpStars(220)
	# флот: портал, корабль, время появления; центральный — флагман
	_fleet = [{"x": 0.22, "y": 0.26, "spr": "shooter", "w": 58.0, "t0": 2.2}, {"x": 0.78, "y": 0.26, "spr": "shooter", "w": 58.0, "t0": 2.5},
		{"x": 0.5, "y": 0.2, "spr": "boss", "w": 170.0, "t0": 2.9, "boss": true}, {"x": 0.36, "y": 0.36, "spr": "scout", "w": 46.0, "t0": 3.3},
		{"x": 0.64, "y": 0.36, "spr": "scout", "w": 46.0, "t0": 3.5}]
	# кого сбивает игрок и когда
	_shots = [[5.25, 3], [5.55, 4], [5.85, 0], [6.1, 1]]
	_booms.clear()
	_layer = CanvasLayer.new()
	_layer.layer = 20
	# заставка стартует из _ready сцены мира — корень дерева в этот момент занят, добавляем следующим шагом
	get_tree().root.add_child.call_deferred(_layer)
	_view = Control.new()
	Kit.full(_view)
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed: _finish())
	_layer.add_child(_view)
	_ctx = Ctx.new(_view.get_canvas_item())
	_cap = Kit.label("", 18, Color("#e3f6ff"), 800, HORIZONTAL_ALIGNMENT_CENTER)
	_cap.add_theme_constant_override("outline_size", 8)
	_cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	_cap.set_anchors_preset(Control.PRESET_CENTER)
	_cap.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_cap.modulate.a = 0.0
	_view.add_child(_cap)
	_logo = Kit.vbox(0)
	_logo.set_anchors_preset(Control.PRESET_CENTER)
	_logo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_logo.grow_vertical = Control.GROW_DIRECTION_BOTH
	_logo.add_child(Kit.label("SPACE", 46, Color.WHITE, 900, HORIZONTAL_ALIGNMENT_CENTER))
	_logo.add_child(Kit.label("SHOOTER", 27, Kit.CYAN, 900, HORIZONTAL_ALIGNMENT_CENTER))
	_logo.modulate.a = 0.0
	_view.add_child(_logo)
	var skip := Kit.label("касание — пропустить", 12, Color(200 / 255.0, 220 / 255.0, 1, 0.55), 600, HORIZONTAL_ALIGNMENT_CENTER)
	skip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	skip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	skip.offset_top = -40; skip.offset_bottom = -20
	_view.add_child(skip)
	playing = true


func _sfx(key: String, name: String, o := {}) -> void:
	if _said.has(key): return
	_said[key] = true
	A.play(name, o)


func _finish() -> void:
	if not playing: return
	playing = false
	var tw := _view.create_tween()
	tw.tween_property(_view, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): _layer.queue_free())
	if _done.is_valid(): _done.call()


func _process(dt: float) -> void:
	if not playing: return
	dt = minf(dt, 0.05)
	_t += dt
	if _t >= DUR:
		_finish()
		return
	var t := _t
	var W := G.W
	var H := G.H
	var k := clampf(minf(W / 400, H / 720), 0.8, 1.6)
	var FW := minf(W, 640)
	var FX0 := (W - FW) / 2
	var c := _ctx
	c.begin()
	# фон: глубокий космос — радиальный градиент веером от центра
	var pts := PackedVector2Array([Vector2(W / 2, H * 0.35)])
	var cols := PackedColorArray([Color("#16194a")])
	var R := maxf(W, H) * 1.2
	for i in 41:
		var a := i / 40.0 * TAU
		pts.append(Vector2(W / 2 + cos(a) * R, H * 0.35 + sin(a) * R))
		cols.append(Color("#02030b"))
	c.fill = Color("#02030b"); c.fill_rect(0, 0, W, H)
	c.fill_poly(pts, cols)
	# звёзды: в начале прыжок (длинные штрихи), потом спокойный полёт
	var warp := 1.0 if t < 1.4 else maxf(0.06, 1 - (t - 1.4) * 1.2)
	warpStep(_stars, dt, warp)
	warpDraw(c, _stars, warp, W / 2, H * 0.42, maxf(W, H) * 0.7, 1.0)
	# вспышка выхода из прыжка
	if t > 1.3 and t < 2.0:
		c.fill = Color(190 / 255.0, 225 / 255.0, 1, 0.35 * (1 - (t - 1.3) / 0.7)); c.fill_rect(0, 0, W, H)
	# флот выходит из порталов
	for i in _fleet.size():
		var e: Dictionary = _fleet[i]
		if t < e.t0 or e.get("dead", false) or t > 6.85: continue
		var lt: float = t - e.t0
		var x: float = FX0 + e.x * FW
		var y: float = e.y * H + lt * 6 * k
		if lt < 1.1:
			var pk := lt / 0.3 if lt < 0.3 else (1 - (lt - 0.8) / 0.3 if lt > 0.8 else 1.0)
			c.additive = true
			G.draw(c, "fx_portal_in", x, e.y * H, (150 if e.get("boss", false) else 80) * k * (0.4 + 0.6 * pk), 0, pk)
			c.additive = false
			_sfx("p%d" % i, "teleport", {"vol": 0.5})
		if lt > 0.25:
			var a := ease3((lt - 0.25) / 0.5)
			var w := minf(e.w * k, FW * 0.46 if e.get("boss", false) else 999.0)
			G.draw(c, e.spr, x, y, w * (0.6 + 0.4 * a), 0, a)
		e.cx = x; e.cy = y
	# красная тревога, пока выходит флот
	if t > 2.6 and t < 4.6:
		c.alpha = 0.18 * (0.5 + 0.5 * sin((t - 2.6) * 7)) / 0.18 * 0.5
		c.draw_tex(FX._vignette_tex("#ff1e3c"), 0, 0, W, H)
		c.alpha = 1.0
		_sfx("warn", "warning", {"vol": 0.45})
	# корабль игрока: выходит снизу, стреляет, уходит вверх
	if t > 4.3:
		var sw := 72 * k
		var sy := H + 80 * k
		if t < 5.1: sy = U.lerp(H + 80 * k, H * 0.72, ease3((t - 4.3) / 0.8))
		elif t < 6.4: sy = H * 0.72 + sin((t - 5.1) * 3) * 4 * k
		else: sy = U.lerp(H * 0.72, -120 * k, ease3((t - 6.4) / 0.7) * ease3((t - 6.4) / 0.7))
		var sx := W / 2 + sin(t * 1.3) * 10 * k
		var boost := 2.2 if t > 6.4 else (1.6 if t < 5.1 else 1.1)
		var s: Dictionary = M.s
		Game.drawShip(c, s.ship.model, s.ship.skin, s.ship.trail, sx, sy, sw, sin(t * 1.3) * 0.08, t, boost)
		if t < 5.0: _sfx("eng", "skill", {"vol": 0.4, "rate": 0.7})
		# выстрелы по разведке
		for sh in _shots:
			var e: Dictionary = _fleet[sh[1]]
			if t < sh[0] or e.get("dead", false) or not e.has("cx"): continue
			var lt: float = t - sh[0]
			if lt < 0.16:
				c.additive = true
				c.stroke = Color(127 / 255.0, 231 / 255.0, 1, 1 - lt / 0.16); c.line_width = 4 * k
				c.stroke_line(sx, sy - sw * 0.5, e.cx, e.cy)
				c.stroke = Color(1, 1, 1, 1 - lt / 0.16); c.line_width = 1.5 * k
				c.stroke_line(sx, sy - sw * 0.5, e.cx, e.cy)
				c.additive = false
				_sfx("s%d" % sh[1], "laser", {"vol": 0.6})
			else:
				e.dead = true
				_booms.append({"x": e.cx, "y": e.cy, "t": 0.0, "w": e.w * k * 1.6})
				A.play("explodeM", {"vol": 0.6})
	# взрывы
	for b in _booms:
		b.t += dt
		if b.t > 0.7: continue
		var q: float = b.t / 0.7
		c.additive = true
		G.draw(c, "fx_ex_l" if q < 0.5 else "fx_ex_crit", b.x, b.y, b.w * (0.6 + q * 0.8), 0, 1 - q * q)
		c.additive = false
	# финал: вспышка и логотип
	if t > 6.75:
		var q := (t - 6.75) / 0.5
		if q < 1:
			c.fill = Color(1, 1, 1, 0.85 * (1 - q)); c.fill_rect(0, 0, W, H)
		if not _said.has("logo"):
			_sfx("logo", "levelup", {"vol": 0.5})
			var tw := _logo.create_tween()
			_logo.scale = Vector2(1.3, 1.3)
			_logo.pivot_offset = _logo.size / 2
			tw.set_parallel(true)
			tw.tween_property(_logo, "modulate:a", 1.0, 0.5)
			tw.tween_property(_logo, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_cap.modulate.a = 0.0
	# подписи
	var ci := -1
	for i in CAPS.size():
		if t >= CAPS[i][0] and t < CAPS[i][1]: ci = i
	if ci != _capIdx and t <= 6.75:
		_capIdx = ci
		if ci >= 0:
			_cap.text = CAPS[ci][2]
			_cap.modulate.a = 0.0
			_cap.create_tween().tween_property(_cap, "modulate:a", 1.0, 0.45)
		else:
			_cap.create_tween().tween_property(_cap, "modulate:a", 0.0, 0.3)


# ── звёзды гиперпрыжка: общие для заставки и прыжка между секторами (Game.jumpScene) ──
func warpStars(n: int) -> Array:
	var stars: Array = []
	for i in n: stars.append({"x": U.rand(-1, 1), "y": U.rand(-1, 1), "z": U.random()})
	return stars


## warp 0..1 — скорость полёта и длина штрихов
func warpStep(stars: Array, dt: float, warp: float) -> void:
	for st in stars:
		st.z -= dt * (0.12 + warp * 1.4)
		if st.z <= 0.02:
			st.z = 1.0; st.x = U.rand(-1, 1); st.y = U.rand(-1, 1)


func warpDraw(c: Ctx, stars: Array, warp: float, cx: float, cy: float, R: float, alpha: float) -> void:
	c.save()
	c.additive = true
	var rgb := Color(150 / 255.0, 210 / 255.0, 1) if warp > 0.3 else Color(220 / 255.0, 235 / 255.0, 1)
	for st in stars:
		var px: float = cx + st.x / st.z * R * 0.25
		var py: float = cy + st.y / st.z * R * 0.25
		var z2: float = st.z + warp * 0.08
		var qx: float = cx + st.x / z2 * R * 0.25
		var qy: float = cy + st.y / z2 * R * 0.25
		var a := minf(1, (1 - st.z) * 1.6) * alpha
		c.stroke = Color(rgb, a)
		c.line_width = maxf(1, (1 - st.z) * 2.6)
		c.stroke_line(qx, qy, px + 0.01, py)
	c.restore()
