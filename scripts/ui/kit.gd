class_name Kit
extends RefCounted
## Набор для интерфейса: цвета и шрифты как в style.css JS-версии («стекло + неон»), тема Godot и строители
## элементов — метки, кнопки (обычная, primary, gold, danger, ghost), панели, значки (спрайт или эмодзи).

const BG := "#05060f"
const PANEL := Color(14 / 255.0, 22 / 255.0, 52 / 255.0, 0.72)
const PANEL2 := Color(20 / 255.0, 30 / 255.0, 70 / 255.0, 0.6)
const PANEL_SOLID := Color("#0d1534")
const LINE := Color(130 / 255.0, 170 / 255.0, 1.0, 0.16)
const LINE2 := Color(130 / 255.0, 170 / 255.0, 1.0, 0.28)
const TEXT := Color("#eaf0ff")
const MUTED := Color("#8e9bc9")
const DIM := Color("#5b6796")
const CYAN := Color("#3de0ff")
const BLUE := Color("#4c7dff")
const VIOLET := Color("#a06bff")
const PINK := Color("#ff3d8b")
const GOLD := Color("#ffc83d")
const GREEN := Color("#3dffa2")
const RED := Color("#ff4d5e")
const ORANGE := Color("#ff8a3d")
## цвета редкости (карточки улучшений, реликвии)
const RAR := {"common": "#9fb3d9", "uncommon": "#3dffa2", "rare": "#3de0ff", "epic": "#b06bff", "legendary": "#ffc83d"}

static var _font: FontFile
static var _fonts := {}
static var _theme: Theme
static var _emoji: SystemFont


## шрифт Exo 2 (OFL, с кириллицей) нужной насыщенности; запасной — системные эмодзи
static func font(weight := 600) -> Font:
	if _fonts.has(weight): return _fonts[weight]
	if _font == null:
		_font = load("res://assets/fonts/Exo2.ttf")
		# эмодзи: на компьютере и телефоне — цветные системные; в браузере системных шрифтов не видно —
		# цветные значки берём у браузера (WebEmoji), остальное — свой Noto Emoji (OFL, контурный)
		var noto: Font = load("res://assets/fonts/NotoEmoji.ttf")
		if OS.has_feature("web"):
			# значки рисует сам браузер (как в JS-версии): цветные эмодзи и символы цветом текста;
			# чего нет у браузера — контурный Noto Emoji
			var fb: Array[Font] = WebEmoji.build()
			fb.append(noto)
			_font.fallbacks = fb
			# системных шрифтов в браузере нет; с этим флагом Godot пропускает «не цветные» шрифты для эмодзи
			# (растровый из браузера он считает не цветным) в поисках системного, которого нет
			_font.allow_system_fallback = false
		else:
			_emoji = SystemFont.new()
			_emoji.font_names = PackedStringArray(["Segoe UI Emoji", "Noto Color Emoji", "Apple Color Emoji", "Segoe UI Symbol"])
			_font.fallbacks = [_emoji, noto]
	var f := FontVariation.new()
	f.base_font = _font
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	_fonts[weight] = f
	return f


static func box(bg: Color, border := Color(0, 0, 0, 0), radius := 12, bw := 1, pad := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw if border.a > 0 else 0)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.anti_aliasing = true
	return s


## рамка в духе концепта (NeoBox): срезанные углы, заливка с бликом, кромка edge, уголки accent, свечение glow
static func neo(bg: Color, edge := Color(0, 0, 0, 0), accent := Color(0, 0, 0, 0), cut := 10.0, pad := 0, glow := 0.0, bw := 1.0) -> NeoBox:
	var s := NeoBox.new()
	s.bg = bg
	s.edge = edge
	s.accent = accent
	s.cut = cut
	s.glow = glow
	s.bw = bw
	s.set_content_margin_all(pad)
	return s


static func theme() -> Theme:
	if _theme: return _theme
	var t := Theme.new()
	t.default_font = font(600)
	t.default_font_size = 15
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", TEXT)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(TEXT, 0.4))
	t.set_stylebox("normal", "Button", neo(PANEL2, LINE2, Color(CYAN, 0.7), 9, 8))
	t.set_stylebox("hover", "Button", neo(PANEL2.lightened(0.08), LINE2, Color(CYAN, 0.7), 9, 8))
	t.set_stylebox("pressed", "Button", neo(PANEL2.darkened(0.15), LINE2, CYAN, 9, 8))
	t.set_stylebox("disabled", "Button", neo(Color(PANEL2, 0.3), Color(LINE2, 0.15), Color(0, 0, 0, 0), 9, 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", neo(PANEL, LINE, Color(0, 0, 0, 0), 12, 12))
	t.set_stylebox("panel", "Panel", neo(PANEL, LINE, Color(0, 0, 0, 0), 12, 0))
	# прокрутка: тонкая полоса
	var grab := box(Color(LINE2, 0.6), Color(0, 0, 0, 0), 3)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.15), Color(0, 0, 0, 0), 3))
	_theme = t
	return t


static func label(text: String, size := 15, color := TEXT, weight := 600, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(weight))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


## текст в несколько строк по ширине контейнера
static func para(text: String, size := 14, color := MUTED, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := label(text, size, color, 500, align)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 10
	return l


## kind: "" | primary | gold | danger | ghost; size: sm | "" | big
static func button(text: String, on_press: Callable, kind := "", size := "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font(800))
	b.add_theme_font_size_override("font_size", 11 if size == "sm" else (16 if size == "big" else 13))
	b.custom_minimum_size.y = 36 if size == "sm" else (58 if size == "big" else 48)
	var bg := PANEL2
	var border := LINE2
	var fc := TEXT
	match kind:
		"primary": bg = Color("#3fb0ff"); border = Color(0, 0, 0, 0); fc = Color("#04122b")
		"gold": bg = Color("#ffbf4a"); border = Color(0, 0, 0, 0); fc = Color("#2b1700")
		"danger": bg = Color(1, 77 / 255.0, 94 / 255.0, 0.08); border = Color(1, 77 / 255.0, 94 / 255.0, 0.35); fc = Color("#ff8a96")
		"ghost": bg = Color(0, 0, 0, 0); border = Color(0, 0, 0, 0); fc = MUTED
	# рамка в стиле концепта: срезанные углы, уголки-скобы, у главных кнопок — свечение
	var cut := 7.0 if size == "sm" else (12.0 if size == "big" else 10.0)
	var acc := Color(CYAN, 0.7)
	var glow := 0.0
	match kind:
		"primary": acc = Color("#e2f6ff"); glow = 0.6; border = Color("#9fdcff")
		"gold": acc = Color("#fff3cc"); glow = 0.55; border = Color("#ffe08a")
		"danger": acc = Color(1, 0.55, 0.62, 0.8)
		"ghost": acc = Color(0, 0, 0, 0)
	b.add_theme_stylebox_override("normal", neo(bg, border, acc, cut, 8, glow))
	b.add_theme_stylebox_override("hover", neo(bg.lightened(0.08), border, acc, cut, 8, glow))
	b.add_theme_stylebox_override("pressed", neo(bg.darkened(0.12), border, acc.lightened(0.3), cut, 8, glow * 0.4))
	b.add_theme_stylebox_override("disabled", neo(Color(bg, bg.a * 0.4), Color(border, border.a * 0.4), Color(0, 0, 0, 0), cut, 8))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(k, fc)
	b.add_theme_color_override("font_disabled_color", Color(fc, 0.4))
	b.pressed.connect(func():
		A.play("click")
		Haptic.select()
		on_press.call())
	# «нажатие»: кнопка сжимается и отпружинивает обратно (Tween)
	b.button_down.connect(func():
		b.pivot_offset = b.size / 2
		_spring(b, Vector2(0.94, 0.94), 0.06, Tween.TRANS_QUAD))
	b.button_up.connect(func(): _spring(b, Vector2.ONE, 0.28, Tween.TRANS_BACK))
	return b


## кнопка со значком из Icons (как <svg><use href="#i-…"> в JS): значок и надпись вместе по центру;
## text "" — только значок (назад, закрыть). Цвет значка — цвет надписи кнопки
static func icon_button(id: String, text: String, on_press: Callable, kind := "", size := "", px := 0) -> Button:
	var b := button("", on_press, kind, size)
	var fc := b.get_theme_color("font_color")
	if px <= 0: px = 20 if size == "sm" else (26 if size == "big" else 22)
	var h := hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	full(h)
	h.add_child(Icons.rect(id, fc, px))
	if text != "":
		var l := label(text, b.get_theme_font_size("font_size"), fc, 800)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(l)
	passthrough(h)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)
	b.custom_minimum_size.x = maxf(b.custom_minimum_size.y, h.get_combined_minimum_size().x + 20)
	return b


static func _spring(c: Control, to: Vector2, dur: float, trans: int) -> void:
	var old = c.get_meta("_spring") if c.has_meta("_spring") else null
	if old is Tween and old.is_valid(): old.kill()
	var tw := c.create_tween()
	tw.tween_property(c, "scale", to, dur).set_trans(trans).set_ease(Tween.EASE_OUT)
	c.set_meta("_spring", tw)


## плавное появление окна: само окно проявляется, его первая панель «выпрыгивает» из 94 % размера;
## slide — экран въезжает сбоку (разделы меню). Подключается раз: Kit.animate_on_show(окно)
static func animate_on_show(c: Control, slide := false) -> void:
	c.visibility_changed.connect(func(): if c.is_visible_in_tree(): appear(c, slide))


static func appear(c: Control, slide := false) -> void:
	var old = c.get_meta("_appear") if c.has_meta("_appear") else null
	if old is Tween and old.is_valid(): old.kill()
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.16)
	if slide:
		# исходное место запоминаем один раз — повторное открытие посреди анимации не сдвинет экран
		if not c.has_meta("_x0"): c.set_meta("_x0", c.position.x)
		var x0: float = c.get_meta("_x0")
		c.position.x = x0 + 28
		tw.tween_property(c, "position:x", x0, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		var p := _first_panel(c)
		if p:
			# размер панели может быть ещё не посчитан — центр берём на каждом шаге
			tw.tween_method(func(k: float):
				p.pivot_offset = p.size / 2
				p.scale = Vector2.ONE * lerpf(0.94, 1.0, k), 0.0, 1.0, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	c.set_meta("_appear", tw)


static func _first_panel(c: Node) -> PanelContainer:
	var q: Array[Node] = [c]
	while not q.is_empty():
		var n: Node = q.pop_front()
		if n is PanelContainer and n != c: return n
		q.append_array(n.get_children())
	return null


## панель-рамка: у заметной (цветной) кромки — уголки-скобы, у обычной — только срез и блик
static func panel(pad := 12, bg := PANEL, border := LINE, radius := 16) -> PanelContainer:
	var p := PanelContainer.new()
	var acc := border.lightened(0.35) if border.a >= 0.35 else Color(0, 0, 0, 0)
	if acc.a > 0: acc.a = minf(1.0, border.a + 0.3)
	var nb := neo(bg, border, acc, radius * 0.75, pad)
	nb.notch = acc.a > 0
	p.add_theme_stylebox_override("panel", nb)
	return p


static func vbox(sep := 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func margin(l := 16, t := 16, r := 16, b := 16) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	return m


## значок: кадр атласа (если есть) или эмодзи; size — сторона в пикселях
static func icon(sprite: String, emoji: String, size := 32) -> Control:
	var tex := G.icon(sprite) if sprite != "" else null
	if tex:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = Vector2(size, size)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return r
	var l := label(emoji, int(size * 0.8), TEXT, 600, HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(size, size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## значок достижения: медаль группы (M.ACH_MEDAL) с номером ступени в цветной плашке;
## нет медали — эмодзи из данных, как раньше
const TIER_COL := [Color("#d08a4e"), Color("#c9d3e6"), Color("#ffc83d"), Color("#b98cff"), Color("#3de0ff"), Color("#ff6fa8"), Color("#3dffa2"), Color("#ff9a52")]

static func ach_icon(a: Dictionary, size := 34) -> Control:
	var m: Array = M.ACH_MEDAL.get(a.id, [])
	var tex: Texture2D = G.icon("ach_" + str(m[0])) if m.size() == 2 else null
	if tex == null: return icon("", a.ico, size)
	var c := Control.new()
	c.custom_minimum_size = Vector2(size, size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var r := tex_icon(tex, size)
	full(r)
	c.add_child(r)
	var tier: int = m[1]
	var bs := maxi(13, roundi(size * 0.4))
	var b := Panel.new()
	b.add_theme_stylebox_override("panel", box(TIER_COL[(tier - 1) % TIER_COL.size()], Color(0.02, 0.03, 0.08, 0.85), bs, 1))
	b.size = Vector2(bs, bs)
	b.position = Vector2(size - bs * 0.8, size - bs * 0.8)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(str(tier), maxi(9, roundi(bs * 0.66)), Color("#140c02"), 900, HORIZONTAL_ALIGNMENT_CENTER)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	full(l)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	c.add_child(b)
	return c


## значок из готовой текстуры (контейнер, иконка оружия)
static func tex_icon(tex: Texture2D, size := 32) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## растянуть на весь родитель
static func full(c: Control) -> Control:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0; c.offset_top = 0; c.offset_right = 0; c.offset_bottom = 0
	return c


## полупрозрачная подложка окна
static func dim(alpha := 0.62) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(2 / 255.0, 4 / 255.0, 14 / 255.0, alpha)
	full(r)
	return r


static func spacer(h := 0.0, expand := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = h
	if expand: c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


## холст внутри интерфейса: рисует через Ctx каждый кадр (превью кораблей, оружия, спрайтов)
## fn(ctx, size: Vector2, t: float)
class CtxView extends Control:
	var fn: Callable
	var ctx: Ctx
	var t := 0.0
	var holder = null   # объект, чей метод рисует (Callable сам его не удерживает)

	func _init(draw_fn: Callable, min_size := Vector2(64, 64), keep = null) -> void:
		fn = draw_fn
		holder = keep
		custom_minimum_size = min_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		ctx = Ctx.new(get_canvas_item())

	func _process(dt: float) -> void:
		if not is_visible_in_tree(): return
		t += dt
		ctx.begin()
		fn.call(ctx, size, t)


static func ctx_view(draw_fn: Callable, min_size := Vector2(64, 64), keep = null) -> CtxView:
	return CtxView.new(draw_fn, min_size, keep)


## живое превью из demo.gd: сцена держится, пока жив сам холст
static func demo_view(scene, min_size: Vector2) -> CtxView:
	return CtxView.new(scene.draw, min_size, scene)


## ряд вкладок: tabs = [[id, текст], ...]; on_pick(id)
static func tabs(items: Array, cur: String, on_pick: Callable) -> HBoxContainer:
	var h := hbox(4)
	for it in items:
		var id: String = it[0]
		var fn := func(): on_pick.call(id)
		var b := button(it[1], fn, "primary" if id == cur else "", "sm")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# узкие поля по бокам (как .tab в JS): пять вкладок влезают в экран 390
		for st in ["normal", "hover", "pressed", "disabled"]:
			var sb := b.get_theme_stylebox(st)
			sb.content_margin_left = 3
			sb.content_margin_right = 3
		h.add_child(b)
	return h


## переключатель-кнопка «вкл/выкл»
static func toggle(on: bool, on_change: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 34)
	b.text = Lang.t("ВКЛ") if on else Lang.t("ВЫКЛ")
	b.add_theme_font_override("font", font(800))
	b.add_theme_font_size_override("font_size", 11)
	var st_on := box(Color(GREEN, 0.25), GREEN, 17, 1, 4)
	var st_off := box(Color(1, 1, 1, 0.06), LINE2, 17, 1, 4)
	b.add_theme_stylebox_override("normal", st_off)
	b.add_theme_stylebox_override("hover", st_off)
	b.add_theme_stylebox_override("pressed", st_on)
	b.add_theme_stylebox_override("hover_pressed", st_on)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.toggled.connect(func(v: bool):
		b.text = Lang.t("ВКЛ") if v else Lang.t("ВЫКЛ")
		A.play("click")
		on_change.call(v))
	return b


## карточка-кнопка с содержимым: PanelContainer, нажатие — on_tap
static func card(col: Color, selected: bool, on_tap: Callable, pad := 10) -> PanelContainer:
	var p := panel(pad, Color(col, 0.14) if selected else Color(PANEL_SOLID, 0.9), col if selected else Color(col, 0.3), 14)
	if selected:
		var nb: NeoBox = p.get_theme_stylebox("panel")
		nb.glow = 0.45
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and Rect2(Vector2.ZERO, p.size).has_point(e.position):
			on_tap.call())
	return p


## все дочерние узлы пропускают нажатия к родителю-карточке
static func passthrough(n: Node) -> void:
	for c in n.get_children():
		if c is Control: (c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		passthrough(c)


## полоска прогресса
static func bar(k: float, col: Color, h := 6.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size.y = h
	b.max_value = 1.0
	b.value = clampf(k, 0, 1)
	b.add_theme_stylebox_override("background", box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), int(h / 2)))
	b.add_theme_stylebox_override("fill", box(col, Color(0, 0, 0, 0), int(h / 2)))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## сегменты уровня: v из n
static func segs(v: int, n: int, col: Color) -> HBoxContainer:
	var h := hbox(3)
	for i in n:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(12, 5)
		r.color = col if i < v else Color(1, 1, 1, 0.1)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(r)
	return h
