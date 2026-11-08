extends Control
## Окно выбора (перенос #scr-perk из JS): улучшения за уровень (с перебором за кредиты), модули корабля
## (старт и станция), события между волнами — развилка, контрабандист, события карты (карточки с ценой).
## Карточки «спят» 150–480 мс после показа — чтобы палец, который вёл корабль, не выбрал случайно.

var box: VBoxContainer
var title: Label
var sub: Label
var art: TextureRect
var cards: VBoxContainer
var reroll: Button
var ship_btn: Button
var portrait: Control
var say: Label
var _phrase := ""
var _pt := 0.0
var _mod_offer: Array = []
var _wait := 0.0
var _picks: Array = []       # [Callable] — что выбрать боту


func _ready() -> void:
	Kit.full(self)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(Kit.dim(0.72))
	var scroll := ScrollContainer.new()
	Kit.full(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var m := Kit.safe(Kit.margin(16, 24, 16, 24))
	center.add_child(m)
	box = Kit.vbox(10)
	box.custom_minimum_size.x = 340
	m.add_child(box)
	art = TextureRect.new()
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(0, 92)
	box.add_child(art)
	# 4.1: контрабандист — живой портрет с репликой, которая печатается по буквам
	portrait = Kit.ctx_view(func(c: Ctx, sz: Vector2, t: float):
		var s0 := G.S
		G.S = 0.62   # портрет мельче поля: помощники сцены берут масштаб из G.S
		Scenes.merchant(c, sz.x / 2, sz.y * 0.5 + sin(t * 2) * 3, 74, t, {"thrust": 0.15, "cargo": 1.0})
		G.S = s0, Vector2(200, 110))
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(portrait)
	say = Kit.label("", 14, Color("#1b1430"), 800, HORIZONTAL_ALIGNMENT_CENTER)
	var sp := PanelContainer.new()
	sp.add_theme_stylebox_override("panel", Kit.box(Color(1, 250 / 255.0, 235 / 255.0, 0.96), Color(0, 0, 0, 0), 10, 1, 6))
	sp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sp.add_child(say)
	box.add_child(sp)
	title = Kit.label("", 26, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(title)
	sub = Kit.label("", 14, Kit.MUTED, 600, HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	cards = Kit.vbox(10)
	box.add_child(cards)
	reroll = Kit.button("", func(): _reroll(), "", "sm")
	box.add_child(reroll)
	ship_btn = Kit.button(Lang.t("🛠 СХЕМА КОРАБЛЯ"), func(): Ui.ship.open(_mod_offer), "", "sm")
	box.add_child(ship_btn)


func _process(dt: float) -> void:
	if visible and _wait > 0: _wait -= dt
	if visible and portrait.visible:
		_pt += dt
		var n := mini(_phrase.length(), int(_pt * 28))
		if say.text.length() != n: say.text = _phrase.substr(0, n)
	# ширина под поле боя: на широком экране — по центру
	box.custom_minimum_size.x = minf(G.FW - 32, 420)


func close() -> void:
	visible = false


func _open(t: String, s: String) -> void:
	title.text = t
	title.add_theme_font_size_override("font_size", 20 if t.length() > 12 else 26)
	sub.text = s
	art.visible = false
	portrait.visible = false
	say.get_parent().visible = false
	reroll.visible = false
	ship_btn.visible = false
	Kit.clear(cards)
	_picks.clear()
	visible = true
	# пока палец на экране — карточки «спят» дольше
	_wait = 0.48 if Game.pointer.id != -1 else 0.15


## карточка: значок, имя, описание, метка справа (редкость или цена), доп. строки
func _card(col: String, icon: Control, name_: String, desc: String, tag: String, extra: Array, on_pick: Callable, poor := false) -> void:
	var cc := U.col(col)
	var c := PanelContainer.new()
	# карточка-рамка цвета редкости (NeoBox): уголки и риски; при нажатии — свечение
	var st_n := Kit.neo(Color(Kit.PANEL_SOLID, 0.92), Color(cc, 0.55), Color(cc.lightened(0.3), 0.95), 13, 14)
	st_n.notch = true
	var st_p := Kit.neo(Color(Kit.PANEL_SOLID.lightened(0.08), 0.95), cc, Color.WHITE, 13, 14, 0.5)
	st_p.notch = true
	c.add_theme_stylebox_override("panel", st_n)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var row := Kit.hbox(14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ib := PanelContainer.new()
	ib.add_theme_stylebox_override("panel", Kit.neo(Color(cc, 0.16), Color(cc, 0.45), Color(0, 0, 0, 0), 10, 6))
	ib.custom_minimum_size = Vector2(56, 56)
	ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ib.add_child(icon)
	row.add_child(ib)
	var info := Kit.vbox(3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := Kit.hbox(6)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nm := Kit.label(name_, 14, cc, 900)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(nm)
	var tg := Kit.label(tag, 11, Color(cc, 0.85), 800)
	tg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(tg)
	info.add_child(head)
	var d := Kit.para(desc, 14, Color("#cfd8f5"))
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(d)
	for e in extra:
		e.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.add_child(e)
	row.add_child(info)
	c.add_child(row)
	# нажатие: подсветка при касании, выбор при отпускании над карточкой
	c.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				c.add_theme_stylebox_override("panel", st_p)
			else:
				c.add_theme_stylebox_override("panel", st_n)
				if not Rect2(Vector2.ZERO, c.size).has_point(e.position) or _wait > 0: return
				if poor:
					A.play("error"); Haptic.error()
					return
				A.play("click")
				on_pick.call())
	cards.add_child(c)
	if not poor: _picks.append(on_pick)
	# появление по очереди
	var a1 := 0.45 if poor else 1.0
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_interval(0.07 * (cards.get_child_count() - 1))
	tw.tween_property(c, "modulate:a", a1, 0.2)


func _pips(mx: int, lv: int, col: String) -> Control:
	var h := Kit.hbox(4)
	for i in mx:
		var r := ColorRect.new()
		r.custom_minimum_size = Vector2(14, 4)
		r.color = U.col(col) if i < lv else (Color(U.col(col), 0.55) if i == lv else Color(1, 1, 1, 0.12))
		h.add_child(r)
	return h


func showPerks(choices: Array, rerolled := false) -> void:
	_open(Lang.t("УРОВЕНЬ %d") % Game.run.level, Lang.t("Выберите улучшение"))
	for pk in choices:
		var lv := Game.perk(pk.id)
		var rar: Dictionary = D.RARITY[pk.rar]
		var extra: Array = []
		var ev = Game.evoStep(pk.id)
		if ev:
			extra.append(Kit.label("🧬 " + (Lang.t("ЭВОЛЮЦИЯ СЕЙЧАС: ") if lv + 1 >= ev.lvl else Lang.t("К эволюции %d/%d: ") % [lv + 1, ev.lvl]) + ev.name, 12, Kit.GOLD, 800))
		if pk.max > 1 and pk.max < 99: extra.append(_pips(int(pk.max), lv, rar.color))
		var id: String = pk.id
		var fn := func():
			close()
			Game.choosePerk(id)
			Haptic.success()
		_card(rar.color, Kit.icon("pk_" + id, pk.ico, 44), pk.name + (" %d" % (lv + 1) if lv else ""), pk.desc, rar.name, extra, fn)
	var cost := Game.rerollCost()
	reroll.text = Lang.t("🎲 ДРУГИЕ  ◆ %d") % cost
	reroll.visible = true
	reroll.disabled = M.s.coins < cost and not M.DEV
	if rerolled: _wait = 0.12


func _reroll() -> void:
	var ch = Game.rerollPerks()
	if ch is Array: showPerks(ch, true)


func showModules(choices: Array, kind: String) -> void:
	_open(Lang.t("СТАРТОВЫЙ МОДУЛЬ") if kind == "start" else Lang.t("СТАНЦИЯ"), Lang.t("Модуль корабля — до конца забега"))
	_mod_offer = choices.map(func(m): return m.id)
	ship_btn.visible = true
	for m in choices:
		var rar: Dictionary = D.RARITY[m.rar]
		var lv := Game.mod(m.id)
		var id: String = m.id
		var fn := func():
			close()
			Game.chooseModule(id)
			Haptic.success()
		_card(rar.color, Kit.icon("md_" + id, m.ico, 44), m.name + (" %d" % (lv + 1) if lv else ""), m.desc, rar.name, [], fn)


func showEvent(o: Dictionary) -> void:
	_open(o.title, o.get("sub", ""))
	var a: String = o.get("art", "")
	if a == "p_merchant":
		portrait.visible = true
		say.get_parent().visible = true
		_phrase = Lang.t(U.pick(Scenes.HELLO))
		_pt = 0.0
		say.text = ""
	elif a != "" and G.has(a):
		art.texture = G.icon(a)
		art.visible = true
	for c in o.cards:
		var rar: Dictionary = D.RARITY.get(c.get("rar", "common"), D.RARITY.common)
		var price: float = c.get("price", 0)
		var poor: bool = price > 0 and M.s.coins < price and not M.DEV
		var ic: Control
		if c.get("chest"): ic = Kit.tex_icon(G.chest(c.chest).icon, 44)
		else: ic = Kit.icon(c.get("icon", ""), c.get("ico", ""), 44)
		var tag: String = ("◆ " + U.fmt(price) + (Lang.t(" · мало") if poor else "")) if price > 0 else rar.name
		var id: String = c.id
		var fn := func():
			if Game.pickOffer(id):
				close()
				Haptic.success()
		_card(rar.color, ic, c.name, c.desc, tag, [], fn, poor)


func bot_pick() -> void:
	if _wait > 0 or _picks.is_empty(): return
	_picks[0].call()
