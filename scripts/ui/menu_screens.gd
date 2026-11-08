extends Control
## Экраны главного меню (перенос #scr-hangar, #scr-arsenal, #scr-skills, #scr-missions, #scr-relics,
## #scr-achievements, #scr-codex, #scr-settings и окна пилота из JS): шапка с «назад» и кошельком,
## содержимое раздела строится заново при каждом изменении (как innerHTML в ui.js).

const HudView := preload("res://scripts/ui/hud_view.gd")
const TITLES := {"hangar": "ВЕРФЬ", "arsenal": "ОРУЖЕЙНАЯ", "skills": "ИМПЛАНТЫ", "missions": "КОНТРАКТЫ", "relics": "КСЕНОТЕХ",
	"achievements": "МЕДАЛИ", "codex": "БАНК ДАННЫХ", "settings": "НАСТРОЙКИ", "leaders": "БОРТЖУРНАЛ"}
const W_LETTER := {"laser": "Л", "shotgun": "Д", "rocket": "Р", "arc": "С", "plasma": "П", "lightning": "М", "darkmatter": "Т", "boomerang": "Б", "gravgun": "Г", "flail": "Ц"}

var cur := ""
var tab := ""
var title: Label
var coins: Label
var body: VBoxContainer
var scroll: ScrollContainer
var preview = null          # { model, skin, trail } — что показывать в ангаре
## Godot: корабль в ангаре можно крутить пальцем — поворот вокруг продольной оси (псевдо-3D), с инерцией
var _yaw := 0.0
var _yawV := 0.0
var _spinT := -1.0
var _dragging := false
var ars := ""               # выбранное оружие в арсенале
var sk_sel := ""            # выбранный имплант
var relic_sel := ""


func _ready() -> void:
	Kit.full(self)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bgc := ColorRect.new(); bgc.color = Color(Color(Kit.BG), 0.94); Kit.full(bgc); add_child(bgc)
	var m := Kit.safe(Kit.margin(14, 12, 14, 12))
	Kit.full(m)
	add_child(m)
	var v := Kit.vbox(10)
	m.add_child(v)
	var head := Kit.hbox(8)
	head.add_child(Kit.icon_button("back", "", func(): back(), "", "sm"))
	title = Kit.label("", 20, Kit.TEXT, 900)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(Kit.tex_icon(G.proc("coin"), 20))
	coins = Kit.label("", 16, Kit.GOLD, 900)
	head.add_child(coins)
	v.add_child(head)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body = Kit.vbox(8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	v.add_child(scroll)


func open(id: String) -> void:
	if get_parent() and get_parent().has_method("set_content_visible"): get_parent().set_content_visible(false)
	cur = id
	tab = ""
	title.text = Lang.t(TITLES.get(id, id.to_upper()))
	Kit.unhide(self)
	visible = true
	scroll.scroll_vertical = 0
	render()


func close() -> void:
	if visible and get_parent() and get_parent().has_method("set_content_visible"): get_parent().set_content_visible(true)
	# Godot: раздел уезжает вбок и гаснет, главное меню проявляется под ним
	Kit.hide(self, true, 0.16, func():
		cur = ""
		preview = null)


func back() -> void:
	A.play("back")
	close()
	if Ui.menu: Ui.menu.refresh()


func refresh_wallet() -> void:
	coins.text = U.fmt(M.s.coins)


func render() -> void:
	refresh_wallet()
	var keep := scroll.scroll_vertical
	Kit.clear(body)
	if has_method("_render_" + cur): call("_render_" + cur)
	await get_tree().process_frame
	scroll.scroll_vertical = keep


func _rerender() -> void:
	render()
	if Ui.menu: Ui.menu.refresh()


func _toast(ico: String, t: String, text: String) -> void:
	Ui.toast({"ico": ico, "title": t, "text": text, "info": true})


func _poor(n: float) -> void:
	A.play("error")
	_toast("💸", Lang.t("НЕ ХВАТАЕТ КРЕДИТОВ"), Lang.t("Нужно ") + U.fmt(n))


## сетка карточек
func _grid(cols := 2) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	body.add_child(g)
	return g


## карточка товара: картинка (CtxView), имя, подпись, цена/требование
func _item(parent: Control, draw_fn: Callable, name_: String, sub: String, tag: String, tag_col: Color, selected: bool, locked: bool, on_tap: Callable, col := Kit.CYAN) -> void:
	var c := Kit.card(col, selected, on_tap)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if locked: c.modulate = Color(1, 1, 1, 0.7)
	var v := Kit.vbox(3)
	var pv := Kit.ctx_view(draw_fn, Vector2(64, 64))
	pv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pv)
	# подписи переносятся по ширине карточки: иначе длинное «🔒 Рекорд 50 000 очков» раздвигает сетку
	# из трёх столбцов шире экрана, и весь экран уезжает вправо
	v.add_child(_wrap(Kit.label(name_, 13, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER)))
	if sub != "":
		var s := Kit.para(sub, 11, Kit.MUTED, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(s)
	if tag != "": v.add_child(_wrap(Kit.label(tag, 12, tag_col, 800, HORIZONTAL_ALIGNMENT_CENTER)))
	c.add_child(v)
	Kit.passthrough(c)
	parent.add_child(c)


static func _wrap(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 10
	return l


## корабль в превью: облик модели и раскраски по центру области
static func _draw_look(c: Ctx, model: String, skin: String, sz: Vector2, k := 0.8, preview_ := false) -> void:
	var lk := Game.shipLook(model, skin, preview_)
	var w := minf(sz.x, sz.y) * k
	if lk.cv: G.draw_canvas(c, lk.cv, sz.x / 2, sz.y / 2, w)
	else: G.draw(c, lk.sprite, sz.x / 2, sz.y / 2, w)


# ════════════════════════════════════════════════════════════
# АНГАР: корабли, дроны, раскраски, двигатели, пилоты; престиж
# ════════════════════════════════════════════════════════════
## витрина ангара: платформа с вращающимся кольцом, корабль поворачивается вокруг продольной оси
## (ширина ~ cos угла, обратная сторона — темнее), по корпусу скользит блик; без касаний — лёгкое покачивание
func _draw_showcase(c: Ctx, sz: Vector2, t: float) -> void:
	var dt := 0.016 if _spinT < 0.0 else clampf(t - _spinT, 0.0, 0.05)
	_spinT = t
	if not _dragging:
		_yaw += _yawV * dt
		_yawV *= exp(-dt * 1.6)
		if absf(_yawV) < 0.4:
			# остановился — мягко к ближайшему «лицом вверх» и лёгкое покачивание
			var target := roundf(_yaw / TAU) * TAU + sin(t * 0.9) * 0.22
			_yaw = lerpf(_yaw, target, minf(1.0, dt * 2.0))
	var p = preview if preview else M.s.ship
	var cx := sz.x / 2
	var w := minf(sz.y * 0.5, 120.0)
	var cy := sz.y * 0.44 + sin(t * 1.6) * 5
	# платформа
	c.save(); c.translate(cx, sz.y * 0.88); c.scale(1.0, 0.26)
	c.additive = true
	c.alpha = 0.4; c.draw_tex(G.soft("#3de0ff", 64), -w * 1.1, -w * 1.1, w * 2.2, w * 2.2)
	c.alpha = 0.7; c.stroke = Kit.CYAN; c.line_width = 2.0
	c.rotate(t * 0.6)
	c.dash = PackedFloat32Array([10, 8]); c.begin_path(); c.arc(0, 0, w * 0.85, 0, TAU); c.stroke_path(); c.dash = PackedFloat32Array()
	c.additive = false; c.alpha = 1.0
	c.restore()
	# корабль
	var cs := cos(_yaw)
	c.save(); c.translate(cx, cy); c.scale(signf(cs if cs != 0.0 else 1.0) * maxf(absf(cs), 0.07), 1.0)
	c.alpha = 1.0 if cs >= 0 else 0.62
	Game.drawShip(c, p.model, p.skin, p.trail, 0, 0, w, 0.0, t, 1.15)
	c.alpha = 1.0
	c.restore()
	# блик по корпусу при повороте
	var sh := absf(sin(_yaw))
	if sh > 0.05:
		c.additive = true
		c.alpha = 0.35 * sh
		var bx := cx + sin(_yaw) * w * 0.3 * absf(cs)
		c.draw_tex(G.soft("#ffffff", 64), bx - w * 0.22, cy - w * 0.55, w * 0.44, w * 1.1)
		c.additive = false
		c.alpha = 1.0
	# подсказка в первые секунды
	if t < 4.0:
		c.alpha = clampf(1.0 - (t - 2.5) / 1.5, 0.0, 0.8)
		c.font = Kit.font(700)
		c.fill = Kit.MUTED
		c.fill_text(Lang.t("◀ покрутите пальцем ▶"), cx, sz.y - 6, 11, 1)
		c.alpha = 1.0


func _render_hangar() -> void:
	if tab == "": tab = "models"
	var s: Dictionary = M.s
	var pv = preview if preview else s.ship
	var big := Kit.ctx_view(func(c: Ctx, sz: Vector2, t: float): _draw_showcase(c, sz, t), Vector2(0, 200))
	big.mouse_filter = Control.MOUSE_FILTER_STOP
	big.gui_input.connect(func(e: InputEvent):
		var dx := 0.0
		if e is InputEventScreenDrag: dx = e.relative.x
		elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT): dx = e.relative.x
		elif (e is InputEventScreenTouch or e is InputEventMouseButton) and e.pressed: _dragging = true; _yawV = 0.0
		elif (e is InputEventScreenTouch or e is InputEventMouseButton) and not e.pressed: _dragging = false
		if dx != 0.0:
			_dragging = true
			_yaw += dx * 0.014
			_yawV = lerpf(_yawV, dx * 0.014 * 60.0, 0.5)
			big.accept_event())
	body.add_child(big)
	var sh: Dictionary = D.SHIPS[s.ship.model]
	body.add_child(Kit.label(sh.name, 18, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER))
	var chips := [Lang.t("⚡ Боевая мощь ") + U.fmt(M.power())] + Array(sh.get("perks", []))
	body.add_child(Kit.para("  •  ".join(chips), 12, Kit.CYAN, HORIZONTAL_ALIGNMENT_CENTER))
	body.add_child(Kit.tabs([["models", Lang.t("КОРАБЛИ")], ["drones", Lang.t("ДРОНЫ")], ["skins", Lang.t("РАСКРАСКИ")], ["trails", Lang.t("ДВИГАТЕЛИ")], ["pilots", Lang.t("ПИЛОТЫ")]], tab, func(id):
		tab = id; preview = null; render()))
	var g := _grid(3)
	match tab:
		"models":
			for id in D.SHIP_ORDER:
				var d: Dictionary = D.SHIPS[id]
				var owned: bool = id in s.ship.models
				var sel: bool = s.ship.model == id
				var lvlOk: bool = s.shipLvl >= d.lvl
				var mid: String = id
				var tag := "" if owned else ("◆ " + U.fmt(d.price) if lvlOk else Lang.t("🔒 Корабль ур. %d") % d.lvl)
				_item(g, func(c, sz, _t): _draw_look(c, mid, M.s.ship.skin, sz), d.name, "", tag, Kit.GOLD if lvlOk else Kit.MUTED, sel, not owned, func(): _ship_tap(mid))
		"drones":
			var cm: Dictionary = s.comp
			for id in D.COMPANION_ORDER:
				var d: Dictionary = D.COMPANIONS[id]
				var owned: bool = id in cm.owned
				var sel: bool = cm.sel == id
				var lv: int = int(cm.lv.get(id, 1))
				var did: String = id
				var tag := ""
				if owned: tag = ("↑ ◆ " + U.fmt(d.costs[lv - 1]) if lv < 5 else Lang.t("МАКС")) if sel else ""
				else: tag = "◆ " + U.fmt(d.price) if s.shipLvl >= d.lvl else Lang.t("🔒 Корабль ур. %d") % d.lvl
				_item(g, func(c, sz, _t):
					if d.hue != null: G.draw_canvas(c, G.tinted(d.sprite, {"hue": d.hue}), sz.x / 2, sz.y / 2, sz.x * 0.6)
					else: G.draw(c, d.sprite, sz.x / 2, sz.y / 2, sz.x * 0.6), d.ico + " " + d.name + (" · %d" % lv if owned else ""), "", tag, Kit.GOLD, sel, not owned, func(): _drone_tap(did))
		"skins":
			for sk in D.SKINS:
				var owned: bool = sk.id in s.ship.skins
				var sel: bool = s.ship.skin == sk.id
				var kid: String = sk.id
				_item(g, func(c, sz, _t): _draw_look(c, M.s.ship.model, kid, sz, 0.78, true), sk.name, D.RARITY_NAMES.get(sk.rar, ""), "" if owned else "🔒 " + sk.req, Kit.MUTED, sel, not owned, func(): _skin_tap(kid), U.col(D.RARITY.get(sk.rar, D.RARITY.common).color) if D.RARITY.has(sk.rar) else Kit.CYAN)
		"trails":
			for tr in D.TRAILS:
				var owned: bool = tr.id in s.ship.trails
				var sel: bool = s.ship.trail == tr.id
				var tid: String = tr.id
				_item(g, func(c, sz, t):
					var cols: Array = Game.trailColors(tid)
					c.additive = true
					c.draw_tex(Game.flameSprite(cols), sz.x * 0.32, sz.y * 0.12, sz.x * 0.36, sz.y * 0.82 * (0.9 + 0.1 * sin(t * 20))), tr.name, "", "" if owned else "◆ " + U.fmt(tr.price), Kit.GOLD, sel, not owned, func(): _trail_tap(tid))
		"pilots":
			for id in D.PILOT_ORDER:
				var p: Dictionary = D.PILOTS[id]
				var opened := M.pilotUnlocked(id)
				var pid: String = id
				_item(g, func(c, sz, _t):
					c.font = Kit.font(600); c.fill = Color.WHITE; c.fill_text(p.ico, sz.x / 2, sz.y / 2 + 14, 38, 1), p.name, p.title if opened else "", "" if opened else Lang.t("🔒 Корабль %d") % p.lvl, Kit.MUTED, s.pilot == id, not opened, func(): _pilot_tap(pid), U.col(p.color))
			var curp: Dictionary = D.PILOTS.get(s.pilot, D.PILOTS.kai)
			body.add_child(Kit.para(curp.ico + " " + curp.name + " — " + curp.desc, 13, Kit.TEXT))
	# престиж
	if M.canPrestige():
		body.add_child(Kit.button(Lang.t("✦ ПЕРЕЗАГРУЗКА ЯДРА %d") % (int(s.prestige) + 1), func():
			var ok := func():
				if M.doPrestige():
					A.play("levelup"); _toast("🌠", Lang.t("ПЕРЕЗАГРУЗКА ЯДРА %d") % M.s.prestige, Lang.t("Добро пожаловать в новый цикл!")); _rerender()
			Ui.dialog({"ico": "star", "title": Lang.t("ПЕРЕЗАГРУЗКА ЯДРА"), "text": Lang.t("Уровень корабля и импланты сбросятся.\nНавсегда: +8% кредитов и +4% урона за каждую перезагрузку.\nПрокачка, оружие, корабли, раскраски и кредиты останутся."), "ok": Lang.t("ПЕРЕЗАГРУЗИТЬ"), "onOk": ok}), "gold"))
	elif s.shipLvl >= 10:
		body.add_child(Kit.para(Lang.t("Перезагрузка ядра откроется на %d уровне корабля: постоянный бонус к кредитам и урону") % D.PRESTIGE_LVL, 12, Kit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))


func _ship_tap(id: String) -> void:
	var s: Dictionary = M.s
	var d: Dictionary = D.SHIPS[id]
	if id in s.ship.models:
		s.ship.model = id; M.save(); A.play("click"); _rerender()
		return
	if s.shipLvl < d.lvl and not M.DEV:
		A.play("error"); _toast("🔒", Lang.t("НУЖЕН УРОВЕНЬ"), Lang.t("Откроется на %d уровне корабля") % d.lvl)
		return
	preview = {"model": id, "skin": s.ship.skin, "trail": s.ship.trail}
	var ok := func():
		if M.buyShip(id):
			A.play("buy"); Haptic.success(); _toast("🚀", Lang.t("НОВЫЙ КОРАБЛЬ"), d.name)
		else: _poor(d.price)
		preview = null
		_rerender()
	Ui.dialog({"ico": "🚀", "title": d.name, "text": d.desc + "\n" + " • ".join(d.get("perks", [])) + Lang.t("\n\nЦена: ") + U.fmt(d.price) + Lang.t(" кредитов"), "ok": Lang.t("КУПИТЬ"), "onOk": ok})


func _drone_tap(id: String) -> void:
	var s: Dictionary = M.s
	var c: Dictionary = s.comp
	var d: Dictionary = D.COMPANIONS[id]
	var lv: int = int(c.lv.get(id, 1))
	if id in c.owned and c.sel != id:
		c.sel = id; M.save(); A.play("click"); _rerender()
		return
	if id in c.owned:
		if lv >= 5:
			A.play("error")
			return
		var up := func():
			if M.compUp(id):
				A.play("levelup"); Haptic.success()
			else: _poor(d.costs[lv - 1])
			_rerender()
		Ui.dialog({"ico": d.ico, "title": d.name + Lang.t(" · УРОВЕНЬ %d") % (lv + 1), "text": d.desc + Lang.t("\nСледующий уровень: ") + d.get("up", "") + Lang.t("\n\nЦена: ") + U.fmt(d.costs[lv - 1]) + Lang.t(" кредитов"), "ok": Lang.t("ПРОКАЧАТЬ"), "onOk": up})
		return
	if s.shipLvl < d.lvl and not M.DEV:
		A.play("error"); _toast("🔒", Lang.t("НУЖЕН УРОВЕНЬ"), Lang.t("Откроется на %d уровне корабля") % d.lvl)
		return
	var buy := func():
		if M.compBuy(id):
			A.play("buy"); Haptic.success(); _toast(d.ico, Lang.t("НОВЫЙ ДРОН"), d.name)
		else: _poor(d.price)
		_rerender()
	Ui.dialog({"ico": d.ico, "title": d.name, "text": d.desc + Lang.t("\n\nЦена: ") + U.fmt(d.price) + Lang.t(" кредитов"), "ok": Lang.t("КУПИТЬ"), "onOk": buy})


func _skin_tap(id: String) -> void:
	var s: Dictionary = M.s
	if not id in s.ship.skins:
		A.play("error")
		for sk in D.SKINS:
			if sk.id == id: _toast("🔒", sk.name, sk.req)
		preview = {"model": s.ship.model, "skin": id, "trail": s.ship.trail}
		return
	s.ship.skin = id; M.save(); A.play("click"); Haptic.select(); _rerender()


func _trail_tap(id: String) -> void:
	var s: Dictionary = M.s
	if id in s.ship.trails:
		s.ship.trail = id; M.save(); A.play("click"); _rerender()
		return
	var tr: Dictionary = {}
	for x in D.TRAILS:
		if x.id == id: tr = x
	preview = {"model": s.ship.model, "skin": s.ship.skin, "trail": id}
	var buy := func():
		if M.buyTrail(id):
			A.play("buy"); Haptic.success()
		else: _poor(tr.price)
		preview = null
		_rerender()
	Ui.dialog({"ico": "🔥", "title": Lang.t("ДВИГАТЕЛЬ «") + tr.name + "»", "text": Lang.t("Цена: ") + U.fmt(tr.price) + Lang.t(" кредитов"), "ok": Lang.t("КУПИТЬ"), "onOk": buy})


func _pilot_tap(id: String) -> void:
	var p: Dictionary = D.PILOTS[id]
	if not M.pilotUnlocked(id):
		A.play("error"); _toast("🔒", Lang.t("ЕЩЁ РАНО"), p.name + Lang.t(" откроется на %d уровне корабля") % p.lvl)
		return
	M.setPilot(id); A.play("click"); Haptic.select(); _rerender()


# ════════════════════════════════════════════════════════════
# АРСЕНАЛ: оружие, прокачка, раскладка «в бой»
# ════════════════════════════════════════════════════════════
static func _effText(up: Dictionary, lvl: int) -> String:
	if up.get("levelText") is Array and not up.levelText.is_empty(): return up.levelText[lvl - 1]
	var v: float = lvl * up.step if up.get("abs", false) else round(lvl * up.step * 100)
	var units = up.get("units")
	if up.get("abs", false) and units is Array and units.size() >= 3: return "+%s%s" % [str(int(v)), " " + U.plural(int(v), units[0], units[1], units[2])]
	return "+%s%s" % [str(int(v)) if v == int(v) else str(v), up.get("unit", "")]


## Арсенал (Godot, новый вид): стойка «В бою» на три слота, сетка оружия по 4 в ряд, витрина выбранного
## (живое демо, характеристики 2×2, урон в секунду), крупная кнопка действия и прокачка карточками
func _render_arsenal() -> void:
	var s: Dictionary = M.s
	var lo: Array = s.weapons.loadout
	if not D.WEAPONS.has(ars): ars = lo[0] if not lo.is_empty() else "laser"
	# ── стойка «В бою» ──
	body.add_child(_secLabel(Lang.t("В БОЮ  %d / 3") % lo.size(), Kit.GREEN))
	var rack := Kit.hbox(6)
	for i in 3:
		rack.add_child(_rackSlot(lo[i] if i < lo.size() else "", i))
	body.add_child(rack)
	# ── всё оружие ──
	body.add_child(_secLabel(Lang.t("ОРУЖИЕ"), Kit.CYAN))
	var g := _grid(4)
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	for id in D.WEAPON_ORDER: g.add_child(_weaponChip(id))
	# ── витрина выбранного ──
	var w: Dictionary = D.WEAPONS[ars]
	var wc := U.col(w.color)
	var own: bool = ars in s.weapons.owned
	var slot: int = lo.find(ars)
	var p := Kit.panel(12, Color(Kit.PANEL_SOLID, 0.94), Color(wc, 0.6), 16)
	var v := Kit.vbox(8)
	p.add_child(v)
	body.add_child(p)
	var top := Kit.hbox(8)
	var nm := Kit.label(w.name, 22, wc, 900)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	if slot >= 0: top.add_child(_pill(Lang.t("В БОЮ • %d") % (slot + 1), Kit.GREEN))
	elif own: top.add_child(_pill(Lang.t("КУПЛЕНО"), Kit.MUTED))
	else: top.add_child(_pill("◆ " + U.fmt(w.price), Kit.GOLD))
	v.add_child(top)
	if w.get("tags") is Array and not w.tags.is_empty():
		var tg := Kit.hbox(5)
		for t in w.tags: tg.add_child(_pill(t, Color(wc, 0.85), true))
		v.add_child(tg)
	# живая демонстрация в рамке
	var dv := Kit.demo_view(Demo.weapon(ars), Vector2(0, 180))
	var dp := PanelContainer.new()
	dp.add_theme_stylebox_override("panel", Kit.neo(Color(0.01, 0.02, 0.06, 0.9), Color(wc, 0.3), Color(wc, 0.7), 10, 2))
	dp.add_child(dv)
	v.add_child(dp)
	v.add_child(Kit.para(w.desc, 13, Kit.TEXT))
	# характеристики 2×2
	var r: Dictionary = w.get("rate", {})
	var sg := GridContainer.new()
	sg.columns = 2
	sg.add_theme_constant_override("h_separation", 12)
	sg.add_theme_constant_override("v_separation", 6)
	for x in [[Lang.t("УРОН"), "dmg"], [Lang.t("ТЕМП"), "speed"], [Lang.t("ПЛОЩАДЬ"), "area"], [Lang.t("ДАЛЬНОСТЬ"), "range"]]:
		var cell := Kit.vbox(3)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_child(Kit.label(x[0], 10, Kit.MUTED, 800))
		cell.add_child(_statBar(int(r.get(x[1], 0)), wc))
		sg.add_child(cell)
	v.add_child(sg)
	var dps := Kit.hbox(6)
	dps.add_child(Icons.rect("bolt", Kit.GOLD, 16))
	dps.add_child(Kit.label(Lang.t("≈ %s урона в секунду") % U.fmt(round(M.weaponDps(ars))), 13, Kit.GOLD, 800))
	v.add_child(dps)
	# главное действие — сразу под витриной
	if own:
		var wid2 := ars
		v.add_child(Kit.button(Lang.t("✓ В БОЮ • УБРАТЬ") if slot >= 0 else Lang.t("+ ВЗЯТЬ В БОЙ"), func(): _loadout(wid2), "" if slot >= 0 else "primary"))
	else:
		var poor: bool = s.coins < w.price and not M.DEV
		var wid3 := ars
		var bb := Kit.button(Lang.t("◆ КУПИТЬ ЗА ") + U.fmt(w.price), func():
			var ok := func():
				if M.buyWeapon(wid3):
					A.play("buy"); Haptic.success(); _toast("⚔️", Lang.t("НОВОЕ ОРУЖИЕ"), w.name + (Lang.t(" • уже в бою") if wid3 in M.s.weapons.loadout else ""))
				else: A.play("error")
				_rerender()
			Ui.dialog({"ico": "⚔️", "title": w.name, "text": w.desc + Lang.t("\n\nЦена: ") + U.fmt(w.price) + Lang.t(" кредитов"), "ok": Lang.t("КУПИТЬ"), "onOk": ok}), "gold", "big")
		bb.disabled = poor
		v.add_child(bb)
		if poor: v.add_child(Kit.para(Lang.t("Не хватает %s кредитов: они падают с врагов и даются за ежедневные контракты.") % U.fmt(w.price - s.coins), 12, Kit.MUTED))
	# ── прокачка ──
	if own:
		var total := 0
		var got := 0
		for up in w.ups:
			total += int(up.max); got += M.weaponLevel(ars, up.id)
		var hh := Kit.hbox(8)
		var hl := _secLabel(Lang.t("ПРОКАЧКА  %d / %d") % [got, total], Kit.GOLD)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hh.add_child(hl)
		body.add_child(hh)
		body.add_child(Kit.bar(float(got) / maxf(1, total), Kit.GOLD, 4))
		for up in w.ups: body.add_child(_upRow(ars, up, wc))


## подпись раздела: цветная чёрточка и заглавные
func _secLabel(text: String, col: Color) -> Control:
	var h := Kit.hbox(6)
	var bar := ColorRect.new()
	bar.color = col
	bar.custom_minimum_size = Vector2(3, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	h.add_child(Kit.label(text, 12, col, 900))
	return h


## плашка-метка: «В БОЮ», цена, теги оружия
func _pill(text: String, col: Color, soft := false) -> Control:
	var pc := PanelContainer.new()
	var st := Kit.neo(Color(col, 0.12 if soft else 0.18), Color(col, 0.5), Color(0, 0, 0, 0), 5, 0)
	st.content_margin_left = 7; st.content_margin_right = 7; st.content_margin_top = 2; st.content_margin_bottom = 2
	st.sheen = 0.0
	pc.add_theme_stylebox_override("panel", st)
	pc.add_child(Kit.label(text, 10 if soft else 11, col.lightened(0.25), 800))
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return pc


## шкала характеристики: 5 делений
func _statBar(v: int, col: Color) -> Control:
	var h := Kit.hbox(3)
	for i in 5:
		var r := ColorRect.new()
		r.color = col if i < v else Color(1, 1, 1, 0.08)
		r.custom_minimum_size = Vector2(10, 6)
		r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(r)
	return h


## слот стойки: оружие в бою (значок, имя, номер) или пустое место
func _rackSlot(id: String, i: int) -> Control:
	var empty := id == ""
	var col := U.col(D.WEAPONS[id].color) if not empty else Kit.DIM
	var c := Kit.card(col, not empty and id == ars, func():
		if empty: return
		ars = id; A.play("click"); Haptic.select(); render(), 6)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var h := Kit.hbox(4)
	h.add_child(Kit.label(str(i + 1), 16, Color(col, 0.9), 900))
	if empty:
		h.add_child(Kit.label(Lang.t("пусто"), 11, Kit.DIM, 700))
	else:
		var wid := id
		h.add_child(Kit.ctx_view(func(cx, sz, _t): HudView.weaponIcon(cx, wid, sz.x / 2, sz.y / 2, minf(sz.x, sz.y) * 0.95), Vector2(30, 30)))
		var nl := Kit.label(D.WEAPONS[id].name, 10, Kit.TEXT, 800)
		nl.clip_text = true
		nl.custom_minimum_size.x = 10
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(nl)
	h.custom_minimum_size.y = 32
	c.add_child(h)
	Kit.passthrough(c)
	return c


## клетка сетки оружия: значок, имя, состояние (в бою / куплено / цена)
func _weaponChip(id: String) -> Control:
	var s: Dictionary = M.s
	var d: Dictionary = D.WEAPONS[id]
	var col := U.col(d.color)
	var own: bool = id in s.weapons.owned
	var sl: int = s.weapons.loadout.find(id)
	var wid := id
	var c := Kit.card(col, id == ars, func():
		ars = wid; A.play("click"); Haptic.select(); render(), 5)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not own: c.modulate = Color(1, 1, 1, 0.75)
	var v := Kit.vbox(1)
	var pv := Kit.ctx_view(func(cx, sz, _t): HudView.weaponIcon(cx, wid, sz.x / 2, sz.y / 2, minf(sz.x, sz.y) * 0.95), Vector2(44, 40))
	pv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pv)
	var nl := Kit.label(d.name, 10, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER)
	nl.clip_text = true
	nl.custom_minimum_size.x = 10
	v.add_child(nl)
	var st := (Lang.t("В БОЮ %d") % (sl + 1)) if sl >= 0 else ("✓" if own else "◆ " + U.fmt(d.price))
	v.add_child(Kit.label(st, 10, Kit.GREEN if sl >= 0 else (Kit.MUTED if own else Kit.GOLD), 800, HORIZONTAL_ALIGNMENT_CENTER))
	c.add_child(v)
	Kit.passthrough(c)
	return c


## карточка улучшения: значок, имя и деления уровня, «сейчас › дальше», кнопка с ценой
func _upRow(wid: String, up: Dictionary, wc := Kit.CYAN) -> Control:
	var lvl := M.weaponLevel(wid, up.id)
	var mx: bool = lvl >= up.max
	var cost: int = 0 if mx else int(up.costs[lvl])
	var poor: bool = not mx and M.s.coins < cost and not M.DEV
	var p := Kit.panel(10, Color(Kit.PANEL_SOLID, 0.9), Color(wc, 0.22), 12)
	var h := Kit.hbox(10)
	p.add_child(h)
	if up.get("ico", "") != "": h.add_child(Kit.icon("", up.ico, 30))
	var v := Kit.vbox(3)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nh := Kit.hbox(6)
	var nl := Kit.label(up.name, 13, Kit.TEXT, 900)
	nh.add_child(nl)
	nh.add_child(Kit.label("%d/%d" % [lvl, up.max], 11, Kit.GOLD if mx else Kit.MUTED, 800))
	v.add_child(nh)
	var eff := (_effText(up, lvl) + Lang.t(" • максимум")) if mx else (((_effText(up, lvl)) if lvl else Lang.t("Сейчас нет")) + "  ›  " + _effText(up, lvl + 1))
	var el := Kit.label(eff, 11, Kit.CYAN if not mx else Kit.MUTED, 700)
	el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	el.custom_minimum_size.x = 10
	v.add_child(el)
	v.add_child(Kit.segs(lvl, int(up.max), Kit.GOLD))
	h.add_child(v)
	var upid: String = up.id
	var b := Kit.button("MAX" if mx else "◆ " + U.fmt(cost), func():
		if M.buyWeaponUp(wid, upid):
			A.play("buy"); Haptic.light()
		else: A.play("error")
		_rerender(), "" if mx or poor else "gold", "sm")
	b.disabled = mx or poor
	b.custom_minimum_size.x = 84
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(b)
	return p


func _loadout(id: String) -> void:
	var lo: Array = M.s.weapons.loadout
	var inLo := id in lo
	if inLo and lo.size() <= 1:
		A.play("error"); _toast("⚠️", Lang.t("НУЖНО ОРУЖИЕ"), Lang.t("Хотя бы одно оружие должно быть в бою"))
		return
	var out = lo[0] if not inLo and lo.size() >= 3 else null
	M.toggleLoadout(id); A.play("click"); Haptic.select()
	if out: _toast("🔁", Lang.t("ЗАМЕНА"), D.WEAPONS[out].name + Lang.t(" убран из боя"))
	_rerender()


# ════════════════════════════════════════════════════════════
# ИМПЛАНТЫ (3.1): ветки, ярусы, ранги, 2 слота активных
# ════════════════════════════════════════════════════════════
func _render_skills() -> void:
	var s: Dictionary = M.s
	var branches: Array = D.SKILL_BRANCHES
	if tab == "": tab = branches[0].id
	var br: Dictionary = branches[0]
	for b in branches:
		if b.id == tab: br = b
	var bc := U.col(br.color)
	body.add_child(Kit.label(Lang.t("Очков имплантов: %d") % M.skillPoints(), 15, Kit.VIOLET, 900))
	# слоты активных имплантов и счётчик пассивных
	var act: Array = s.skills.keys().filter(func(id): return D.SKILLS[id].type == "active")
	var slots := Kit.hbox(6)
	for i in int(D.MAX_ACTIVE):
		var txt := Lang.t("⚡ АКТИВ %d") % (i + 1)
		if i < act.size(): txt = D.SKILLS[act[i]].ico + " " + D.SKILLS[act[i]].name
		var l := Kit.label(txt, 11, Kit.CYAN if i < act.size() else Kit.DIM, 800, HORIZONTAL_ALIGNMENT_CENTER)
		var pp := Kit.panel(6); pp.add_child(l); pp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slots.add_child(pp)
	var ps := Kit.panel(6); ps.add_child(Kit.label(Lang.t("%d ПАССИВНЫХ") % M.skillCount("passive"), 11, Kit.TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER))
	ps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots.add_child(ps)
	body.add_child(slots)
	var tb: Array = []
	for b in branches: tb.append([b.id, b.name])
	body.add_child(Kit.tabs(tb, tab, func(id):
		tab = id; sk_sel = ""; render()))
	var ids: Array = D.SKILLS.keys().filter(func(id): return D.SKILLS[id].branch == br.id)
	if sk_sel == "" or not sk_sel in ids:
		sk_sel = ids[0]
		for id in ids:
			if M.skillState(id).canLearn:
				sk_sel = id
				break
	# ярусы сверху вниз
	for tier in range(1, 6):
		var row: Array = ids.filter(func(id): return int(D.SKILLS[id].tier) == tier)
		if row.is_empty(): continue
		row.sort_custom(func(a, b): return D.SKILLS[a].col < D.SKILLS[b].col)
		var h := Kit.hbox(6)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		for id in row:
			var sk: Dictionary = D.SKILLS[id]
			var st := M.skillState(id)
			var col := Kit.GREEN if st.learned else (Kit.DIM if st.locked else (bc if st.canLearn else Kit.MUTED))
			var sid: String = id
			var c := Kit.card(col, sid == sk_sel, func():
				sk_sel = sid; A.play("click"); render(), 6)
			c.custom_minimum_size = Vector2(76, 0)
			if st.locked: c.modulate.a = 0.55
			var v := Kit.vbox(1)
			v.add_child(Kit.icon(id, sk.ico, 34))
			v.add_child(Kit.label(sk.name, 10, Kit.TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER))
			var rk := ("✓" if st.maxed else Lang.t("очки: %d") % sk.cost) + (" · %d/%d" % [st.rank, st.max] if st.max > 1 else "") + (" ⚡" if sk.type == "active" else "")
			v.add_child(Kit.label(rk, 10, col, 800, HORIZONTAL_ALIGNMENT_CENTER))
			c.add_child(v)
			Kit.passthrough(c)
			h.add_child(c)
		body.add_child(h)
	# карточка выбранного импланта
	var sk: Dictionary = D.SKILLS[sk_sel]
	var st := M.skillState(sk_sel)
	var p := Kit.panel(12, Color(Kit.PANEL_SOLID, 0.92), Color(bc, 0.5), 16)
	var v := Kit.vbox(6)
	p.add_child(v)
	var hh := Kit.hbox(10)
	hh.add_child(Kit.icon(sk_sel, sk.ico, 44))
	var hv := Kit.vbox(2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(Kit.label(sk.name, 17, bc, 900))
	var meta: Array = []
	if sk.type == "active": meta.append(Lang.t("⚡ Активный · перезарядка %s с") % str(sk.cd))
	if st.max > 1: meta.append(Lang.t("Ранг %d из %d") % [st.rank, st.max])
	var req: Array = sk.req
	if not req.is_empty(): meta.append((Lang.t("🔒 Нужен: ") if st.locked else "✓ ") + Lang.t(" или ").join(req.map(func(r): return D.SKILLS[r].name)))
	hv.add_child(Kit.para(" · ".join(meta), 11))
	hh.add_child(hv)
	v.add_child(hh)
	v.add_child(Kit.para(sk.desc, 13, Kit.TEXT))
	# 4.3.2: у активного импланта — живой предпросмотр, как у оружия в арсенале
	if sk.type == "active": v.add_child(Kit.demo_view(Demo.skill(sk_sel), Vector2(0, 170)))
	var why := ""
	if not st.maxed:
		if st.locked: why = Lang.t("Сначала установите ") + Lang.t(" или ").join(req.map(func(r): return "«" + D.SKILLS[r].name + "»"))
		elif st.slotsFull: why = Lang.t("Уже два активных импланта — снимите один")
		elif not st.afford: why = Lang.t("Нужно %d %s, есть %d") % [sk.cost, U.plural(int(sk.cost), Lang.t("очко"), Lang.t("очка"), Lang.t("очков")), M.skillPoints()]
	if why != "": v.add_child(Kit.para(why, 12, Kit.ORANGE))
	var bh := Kit.hbox(8)
	var sid2 := sk_sel
	if not st.maxed:
		var lb := Kit.button((Lang.t("РАНГ %d") % (st.rank + 1) if st.learned else Lang.t("УСТАНОВИТЬ")) + " · ✦%d" % sk.cost, func():
			if M.learnSkill(sid2):
				A.play("levelup"); Haptic.success(); _toast(sk.ico, Lang.t("РАНГ %d") % (st.rank + 1) if st.learned else Lang.t("ИМПЛАНТ УСТАНОВЛЕН"), sk.name)
			else: A.play("error")
			_rerender(), "primary")
		lb.disabled = not (st.canLearn or (M.DEV and not st.locked and not st.slotsFull))
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bh.add_child(lb)
	if st.learned:
		var fb := Kit.button(Lang.t("СНЯТЬ"), func():
			var removed := M.forgetSkill(sid2)
			A.play("back")
			if removed.size() > 1: _toast("↩️", Lang.t("ИМПЛАНТЫ СНЯТЫ"), ", ".join(removed.map(func(x): return D.SKILLS[x].name)))
			_rerender(), "ghost")
		bh.add_child(fb)
	v.add_child(bh)
	body.add_child(p)
	body.add_child(Kit.button(Lang.t("↺ СНЯТЬ ВСЕ ИМПЛАНТЫ"), func():
		if M.s.skills.is_empty():
			A.play("error")
			return
		var ok := func():
			M.resetSkills(); A.play("back"); _rerender()
		Ui.dialog({"ico": "↺", "title": Lang.t("СНЯТЬ ВСЕ ИМПЛАНТЫ?"), "text": Lang.t("Все очки имплантов вернутся — можно собрать пилота заново."), "ok": Lang.t("СНЯТЬ"), "onOk": ok}), "ghost", "sm"))


# ════════════════════════════════════════════════════════════
# ЗАДАНИЯ ДНЯ И НАГРАДА ЗА ВХОД
# ════════════════════════════════════════════════════════════
func _render_missions() -> void:
	var s: Dictionary = M.s
	var d: Dictionary = s.daily
	var ms := M.missions()
	if d.seen != U.today():
		d.seen = U.today(); M.soon()
	var p := Kit.panel(12)
	var v := Kit.vbox(8)
	p.add_child(v)
	var now := Time.get_datetime_dict_from_system()
	var mins := maxi(1, (24 - int(now.hour)) * 60 - int(now.minute))
	v.add_child(Kit.label(Lang.t("🎯 ЕЖЕДНЕВНЫЕ КОНТРАКТЫ"), 13, Kit.TEXT, 900))
	v.add_child(Kit.label(Lang.t("новые через %s%d мин") % [Lang.t("%d ч ") % (mins / 60) if mins >= 60 else "", mins % 60], 11, Kit.MUTED, 700))
	for m in ms:
		var k := minf(1, m.progress / m.goal)
		var h := Kit.hbox(8)
		h.add_child(Kit.label("✓" if m.done else "%d%%" % int(k * 100), 13, Kit.GREEN if m.done else Kit.MUTED, 900))
		var mv := Kit.vbox(3)
		mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mv.add_child(Kit.para(M.missionText(m), 13, Kit.TEXT))
		mv.add_child(Kit.bar(k, Kit.GREEN if m.done else Kit.CYAN))
		var prog := "%s / %s%s" % [U.fmt(floorf(minf(m.progress, m.goal))), U.fmt(m.goal), Lang.t(" мин") if m.id == "minutes" else ""]
		mv.add_child(Kit.label(prog, 11, Kit.DIM, 700))
		h.add_child(mv)
		h.add_child(Kit.label("◆ %d" % m.reward, 13, Kit.GOLD, 900))
		v.add_child(h)
	v.add_child(Kit.label((Lang.t("✓ Бонус за все контракты получен") if d.bonus else Lang.t("🎁 Бонус за все три контракта")) + "   ◆ %d" % D.DAILY_BONUS, 13, Kit.GREEN if d.bonus else Kit.GOLD, 800))
	body.add_child(p)
	body.add_child(Kit.para(Lang.t("Прогресс засчитывается во время игры, награда приходит сразу"), 12, Kit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var st := M.loginStatus()
	var lp := Kit.panel(12)
	var lv := Kit.vbox(8)
	lp.add_child(lv)
	lv.add_child(Kit.label(Lang.t("🎁 НАГРАДА ЗА ВХОД") + (Lang.t("   ·   серия: %d %s") % [st.streak, U.plural(st.streak, Lang.t("день"), Lang.t("дня"), Lang.t("дней"))] if st.streak > 1 else ""), 13, Kit.TEXT, 900))
	var g := GridContainer.new(); g.columns = 4
	g.add_theme_constant_override("h_separation", 6); g.add_theme_constant_override("v_separation", 6)
	var days: Array = D.LOGIN
	for i in days.size():
		var r: Dictionary = days[i]
		var got: bool = i < st.day or (i == st.day and not st.available)
		var today: bool = i == st.day and st.available
		var c := Kit.panel(6, Color(Kit.GOLD, 0.15) if today else Color(Kit.PANEL_SOLID, 0.9), Kit.GOLD if today else (Color(Kit.GREEN, 0.5) if got else Kit.LINE), 10)
		var cv := Kit.vbox(0)
		cv.add_child(Kit.label(Lang.t("День %d") % (i + 1), 10, Kit.MUTED, 700, HORIZONTAL_ALIGNMENT_CENTER))
		cv.add_child(Kit.label(("🎁" if i == 6 else "◆") + " %d%s" % [r.coins, " + ✦" if r.get("sp", 0) else ""], 12, Kit.GREEN if got else Kit.GOLD, 900, HORIZONTAL_ALIGNMENT_CENTER))
		c.add_child(cv)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(c)
	lv.add_child(g)
	if st.available:
		lv.add_child(Kit.button(Lang.t("🎁 ЗАБРАТЬ НАГРАДУ"), func():
			var r = M.claimLogin()
			if r:
				A.play("buy"); Haptic.success(); Ui.toast({"ico": "🎁", "title": Lang.t("НАГРАДА"), "text": Lang.t("+%d кредитов%s") % [r.coins, Lang.t(" и +1 очко импланта") if r.get("sp", 0) else ""]})
			_rerender(), "gold"))
	else:
		lv.add_child(Kit.para(Lang.t("Следующая награда завтра. Заходите каждый день, чтобы серия не прервалась"), 12, Kit.MUTED))
	body.add_child(lp)


# ════════════════════════════════════════════════════════════
# РЕЛИКВИИ (4.1): слоты «в забег» и коллекция из контейнеров
# ════════════════════════════════════════════════════════════
func _render_relics() -> void:
	var s: Dictionary = M.s
	var slots := M.relicSlots()
	var lo := M.relicLoadout()
	body.add_child(Kit.label(Lang.t("В ЗАБЕГ"), 12, Kit.MUTED, 900))
	var sh := Kit.hbox(8)
	var rs: Array = D.RELIC_SLOTS
	for i in rs.size():
		var c: PanelContainer
		if i < lo.size():
			var id: String = lo[i]
			var rel: Dictionary = D.RELICS[id]
			c = Kit.card(U.col(D.RELIC_RARITY[rel.rar].color), true, func():
				relic_sel = id; A.play("click"); render(), 6)
			c.add_child(Kit.icon(id, rel.ico, 44))
		elif i < slots:
			c = Kit.panel(6); c.add_child(Kit.label("+", 26, Kit.DIM, 900, HORIZONTAL_ALIGNMENT_CENTER))
		else:
			c = Kit.panel(6); c.add_child(Kit.label(Lang.t("🔒 ур. %d") % rs[i], 11, Kit.DIM, 800, HORIZONTAL_ALIGNMENT_CENTER))
		c.custom_minimum_size = Vector2(70, 60)
		Kit.passthrough(c)
		sh.add_child(c)
	body.add_child(sh)
	body.add_child(Kit.label(Lang.t("КОЛЛЕКЦИЯ  %d / %d") % [M.relicCount(), D.RELICS.size()], 12, Kit.MUTED, 900))
	var g := _grid(5)
	var order := ["common", "rare", "epic", "legendary", "cursed"]
	var ids: Array = D.RELICS.keys()
	ids.sort_custom(func(a, b): return order.find(D.RELICS[a].rar) < order.find(D.RELICS[b].rar))
	for id in ids:
		var rel: Dictionary = D.RELICS[id]
		var have: bool = s.relics.has(id)
		var col := U.col(D.RELIC_RARITY[rel.rar].color)
		var rid: String = id
		var c := Kit.card(col, rid == relic_sel or rid in lo, func():
			relic_sel = rid; A.play("click"); render(), 4)
		c.custom_minimum_size = Vector2(0, 56)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if have: c.add_child(Kit.icon(id, rel.ico, 40))
		else:
			c.add_child(Kit.label("?", 22, Color(col, 0.6), 900, HORIZONTAL_ALIGNMENT_CENTER))
			c.modulate.a = 0.6
		Kit.passthrough(c)
		g.add_child(c)
	if relic_sel != "" and D.RELICS.has(relic_sel):
		var rel: Dictionary = D.RELICS[relic_sel]
		var have: bool = s.relics.has(relic_sel)
		var col := U.col(D.RELIC_RARITY[rel.rar].color)
		var p := Kit.panel(12, Color(Kit.PANEL_SOLID, 0.92), Color(col, 0.5), 16)
		var v := Kit.vbox(6)
		p.add_child(v)
		v.add_child(Kit.label((rel.ico + " " + rel.name) if have else "??? · " + D.RELIC_RARITY[rel.rar].name, 16, col, 900))
		v.add_child(Kit.label(D.RELIC_RARITY[rel.rar].name, 11, Color(col, 0.8), 800))
		v.add_child(Kit.para(rel.desc if have else Lang.t("Ещё не найден — выпадает из контейнеров"), 13, Kit.TEXT))
		if have:
			var rid2 := relic_sel
			var inLo := rid2 in lo
			v.add_child(Kit.button(Lang.t("✓ В ЗАБЕГЕ • УБРАТЬ") if inLo else Lang.t("+ ВЗЯТЬ В ЗАБЕГ"), func():
				var r = M.toggleRelic(rid2)
				if r is String and r == "full":
					A.play("error"); _toast("🔒", Lang.t("СЛОТЫ ЗАНЯТЫ"), Lang.t("Уберите один ксенотех, чтобы взять другой"))
				else: A.play("click")
				render(), "" if inLo else "primary"))
		body.add_child(p)
	if not s.chests.is_empty():
		body.add_child(Kit.para(Lang.t("Закрытых контейнеров: %d — откроются на экране итогов после забега") % s.chests.size(), 12, Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))


# ════════════════════════════════════════════════════════════
# НАГРАДЫ (достижения)
# ════════════════════════════════════════════════════════════
func _render_achievements() -> void:
	var s: Dictionary = M.s
	var list: Array = D.ACHIEVEMENTS.duplicate()
	list.sort_custom(func(a, b): return int(s.achievements.has(a.id)) < int(s.achievements.has(b.id)))
	body.add_child(Kit.label(Lang.t("Получено %d / %d") % [s.achievements.size(), D.ACHIEVEMENTS.size()], 13, Kit.MUTED, 800))
	for a in list:
		var done: bool = s.achievements.has(a.id)
		var p := Kit.panel(10, Color(Kit.GREEN, 0.08) if done else Color(Kit.PANEL_SOLID, 0.9), Color(Kit.GREEN, 0.4) if done else Kit.LINE, 14)
		var h := Kit.hbox(10)
		var ico := Kit.ach_icon(a, 40)
		if not done: ico.modulate = Color(0.55, 0.6, 0.75)   # не полученная — приглушена
		h.add_child(ico)
		var v := Kit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(Kit.label(a.name, 14, Kit.TEXT if done else Kit.TEXT, 900))
		var desc: String = a.desc
		if a.stat != "" and not done: desc += " (%s/%s)" % [U.fmt(minf(M.statValue(a.stat), a.goal)), U.fmt(a.goal)]
		v.add_child(Kit.para(desc, 12))
		if a.stat != "" and not done: v.add_child(Kit.bar(M.statValue(a.stat) / maxf(1, a.goal), Kit.CYAN, 4))
		h.add_child(v)
		h.add_child(Kit.label("✓" if done else "◆ %d" % a.reward, 13, Kit.GREEN if done else Kit.GOLD, 900))
		p.add_child(h)
		if not done: p.modulate.a = 0.85
		body.add_child(p)


# ════════════════════════════════════════════════════════════
# СПРАВОЧНИК (3.1): встреченные враги — с картинкой и защитой; секторы — с механикой
# ════════════════════════════════════════════════════════════
func _render_codex() -> void:
	var s: Dictionary = M.s
	if tab == "": tab = "foes"
	var seen: Array = s.get("foeSeen", [])
	var foes: Array = D.ENEMIES.keys().filter(func(k): return (D.ENEMIES[k].weight > 0 or D.ENEMIES[k].mini) and D.ENEMIES[k].wave < 99)
	foes.sort_custom(func(a, b): return D.ENEMIES[a].wave < D.ENEMIES[b].wave)
	var known := foes.filter(func(k): return k in seen).size()
	body.add_child(Kit.tabs([["foes", Lang.t("ВРАГИ %d/%d") % [known, foes.size()]], ["sectors", Lang.t("СЕКТОРЫ")]], tab, func(id):
		tab = id; render()))
	if tab == "sectors":
		var ss: Array = s.get("sectorSeen", [])
		for i in D.SECTORS.size():
			var sec: Dictionary = D.SECTORS[i]
			var opened: bool = i in ss or i == 0
			var p := Kit.panel(10)
			var h := Kit.hbox(10)
			h.add_child(Kit.label("🪐" if opened else "?", 26, U.col(sec.neb[0]), 900))
			var v := Kit.vbox(2)
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.add_child(Kit.label(sec.name if opened else "???", 14, U.col(sec.neb[1]), 900))
			v.add_child(Kit.para(sec.get("desc", Lang.t("Без особых правил")) if opened else Lang.t("Ещё не открыт — встретится в одном из забегов"), 12))
			h.add_child(v)
			p.add_child(h)
			body.add_child(p)
		return
	for k in foes:
		var d: Dictionary = D.ENEMIES[k]
		var kn: bool = k in seen
		var p := Kit.panel(8)
		var h := Kit.hbox(10)
		var spr: String = d.sprite
		var pv := Kit.ctx_view(func(c: Ctx, sz: Vector2, _t: float):
			if kn: G.draw(c, spr, sz.x / 2, sz.y / 2, minf(sz.x, sz.y) * 0.86, PI)
			else:
				c.font = Kit.font(900); c.fill = Color(1, 1, 1, 0.12); c.fill_text("?", sz.x / 2, sz.y / 2 + 14, 40, 1), Vector2(64, 64))
		h.add_child(pv)
		var v := Kit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm: String = d.name.to_upper() if kn else "???"
		if kn and d.guard != "": nm += "   [%s]" % (Foes.W_LETTER_EN if Lang.is_en() else W_LETTER).get(d.guard, "?")
		v.add_child(Kit.label(nm, 14, Kit.TEXT, 900))
		var desc: String = (d.hint if d.hint != "" else (Lang.t("Мини-босс") if d.mini else Lang.t("С %d-й волны") % d.wave)) if kn else Lang.t("Встречается с %d-й волны") % d.wave
		v.add_child(Kit.para(desc, 12))
		h.add_child(v)
		p.add_child(h)
		if not kn: p.modulate.a = 0.7
		body.add_child(p)


# ════════════════════════════════════════════════════════════
# РЕКОРДЫ: своя статистика и 10 лучших забегов на каждой сложности (мирового рейтинга без сервера нет)
# ════════════════════════════════════════════════════════════
func _render_leaders() -> void:
	var s: Dictionary = M.s
	var st: Dictionary = s.stats
	var g := _grid(2)
	for x in [[Lang.t("Игр сыграно"), U.fmt(st.games)], [Lang.t("Лучшая волна"), str(st.bestWave)], [Lang.t("Врагов уничтожено"), U.fmt(st.kills)], [Lang.t("Боссов побеждено"), U.fmt(st.bosses)],
			[Lang.t("Лучшее комбо"), "×%d" % st.maxCombo], [Lang.t("Время в бою"), U.fmt_time(st.playTime)], [Lang.t("Кредитов заработано"), U.fmt(st.coinsEarned)], [Lang.t("Улучшений выбрано"), U.fmt(st.perks)]]:
		var p := Kit.panel(8)
		var v := Kit.vbox(0)
		v.add_child(Kit.label(x[0], 11, Kit.MUTED, 700))
		v.add_child(Kit.label(x[1], 16, Kit.TEXT, 900))
		p.add_child(v)
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(p)
	if tab == "" or not D.DIFFS.has(tab): tab = s.settings.diff if D.DIFFS.has(s.settings.diff) else "normal"
	var tb: Array = []
	for id in D.DIFF_ORDER: tb.append([id, D.DIFFS[id].get("short", "") if D.DIFFS[id].get("short", "") != "" else D.DIFFS[id].name])
	body.add_child(Kit.tabs(tb.slice(0, 4), tab, func(id):
		tab = id; render()))
	body.add_child(Kit.tabs(tb.slice(4), tab, func(id):
		tab = id; render()))
	var rows: Array = s.lb.filter(func(r): return r.diff == tab)
	if rows.is_empty():
		body.add_child(Kit.para(Lang.t("На сложности «%s» ещё нет забегов") % D.DIFFS[tab].name, 13, Kit.MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	for i in rows.size():
		var r: Dictionary = rows[i]
		var p := Kit.panel(10)
		var h := Kit.hbox(10)
		h.add_child(Kit.label(["🥇", "🥈", "🥉"][i] if i < 3 else str(i + 1), 18, Kit.GOLD, 900))
		var v := Kit.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(Kit.label(U.fmt(r.score) + Lang.t(" очков"), 15, Kit.TEXT, 900))
		var dt := Time.get_datetime_dict_from_unix_time(int(r.date / 1000))
		v.add_child(Kit.label(Lang.t("Волна %d • %02d.%02d.%d") % [r.wave, dt.day, dt.month, dt.year], 11, Kit.MUTED, 700))
		h.add_child(v)
		p.add_child(h)
		body.add_child(p)


# ════════════════════════════════════════════════════════════
# НАСТРОЙКИ
# ════════════════════════════════════════════════════════════
func _row(label: String, ctl: Control) -> HBoxContainer:
	var h := Kit.hbox(10)
	var l := Kit.label(label, 14, Kit.TEXT, 700)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(ctl)
	return h


func _slider(key: String, mn: float, mx: float, step: float, fmt: Callable) -> Control:
	var st: Dictionary = M.s.settings
	var v := Kit.vbox(2)
	var val := Kit.label(fmt.call(st[key]), 13, Kit.CYAN, 800)
	var sl := HSlider.new()
	sl.min_value = mn; sl.max_value = mx; sl.step = step
	sl.value = st[key]
	sl.custom_minimum_size.y = 28
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.value_changed.connect(func(x: float):
		st[key] = snappedf(x, 0.01) if key == "sens" else x
		val.text = fmt.call(st[key])
		if key == "music" or key == "sfx": A.applyVolumes()
		M.soon())
	sl.drag_ended.connect(func(_c): if key == "sfx": A.play("coin"))
	v.add_child(val)
	v.add_child(sl)
	return v


func _segs(key: String, opts: Array, after := Callable()) -> HBoxContainer:
	var st: Dictionary = M.s.settings
	var h := Kit.hbox(4)
	for o in opts:
		var val = o[0]
		var b := Kit.button(o[1], func():
			st[key] = val
			M.soon()
			if after.is_valid(): after.call()
			render(), "primary" if str(st[key]) == str(val) else "", "sm")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)
	return h


func _render_settings() -> void:
	var st: Dictionary = M.s.settings
	var sec := func(t: String) -> PanelContainer:
		body.add_child(Kit.label(t, 12, Kit.MUTED, 900))
		var p := Kit.panel(12)
		var v := Kit.vbox(10)
		p.add_child(v)
		body.add_child(p)
		return p
	# Godot: язык — смена через перезапуск (данные переводятся при загрузке)
	var v: VBoxContainer = sec.call(Lang.t("ЯЗЫК · LANGUAGE")).get_child(0)
	var lh := Kit.hbox(4)
	var cur_lang := Lang.setting()
	for o in [["auto", Lang.t("Авто")], ["ru", Lang.t("Русский")], ["en", "English"]]:
		var code: String = o[0]
		var b := Kit.button(o[1], func():
			if Lang.setting() == code: return
			if Lang.choose(code):
				Ui.dialog({"ico": "🌐", "title": Lang.t("ЯЗЫК"), "text": Lang.t("Игра перезапустится, чтобы сменить язык."),
					"ok": Lang.t("ПЕРЕЗАПУСТИТЬ"), "onOk": func(): Lang.restart(get_tree())})
			render(), "primary" if cur_lang == code else "", "sm")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lh.add_child(b)
	v.add_child(lh)
	v = sec.call(Lang.t("ЗВУК")).get_child(0)
	v.add_child(Kit.label(Lang.t("♪ Музыка"), 14, Kit.TEXT, 700)); v.add_child(_slider("music", 0, 100, 5, func(x): return "%d%%" % int(x)))
	v.add_child(Kit.label(Lang.t("🔊 Эффекты"), 14, Kit.TEXT, 700)); v.add_child(_slider("sfx", 0, 100, 5, func(x): return "%d%%" % int(x)))
	v.add_child(Kit.label(Lang.t("Стиль музыки"), 14, Kit.TEXT, 700))
	var styles: Array = []
	for id in A.STYLE_IDS: styles.append([id, Lang.t(A.meta.music.get(id + "_0", {}).get("name", id))])
	v.add_child(_segs("musicStyle", styles.slice(0, 3), func(): Main.setMusic(Main.musicMode, true)))
	v.add_child(_segs("musicStyle", styles.slice(3), func(): Main.setMusic(Main.musicMode, true)))
	v = sec.call(Lang.t("ГРАФИКА")).get_child(0)
	v.add_child(Kit.label(Lang.t("Качество"), 14, Kit.TEXT, 700))
	v.add_child(_segs("quality", [["auto", Lang.t("Авто")], ["high", Lang.t("Высокое")], ["medium", Lang.t("Среднее")], ["low", Lang.t("Низкое")]], func(): Main.applyQuality()))
	v.add_child(_row(Lang.t("Тряска экрана"), Kit.toggle(st.shake, func(on):
		st.shake = on; FX.shake_on = on; M.soon())))
	v.add_child(_row(Lang.t("Эффекты экрана"), Kit.toggle(st.get("post", true), func(on):
		st.post = on; M.soon())))
	v.add_child(_row(Lang.t("Цифры урона"), Kit.toggle(st.dmgNums, func(on):
		st.dmgNums = on; M.soon())))
	v.add_child(_row(Lang.t("Показывать FPS"), Kit.toggle(st.fps, func(on):
		st.fps = on; M.soon())))
	var ih := Kit.hbox(8)
	ih.add_child(Kit.button(Lang.t("СМОТРЕТЬ"), func(): Intro.play(func(): pass), "", "sm"))
	ih.add_child(Kit.toggle(st.intro, func(on):
		st.intro = on; M.soon()))
	v.add_child(_row(Lang.t("Заставка при запуске"), ih))
	v = sec.call(Lang.t("УПРАВЛЕНИЕ")).get_child(0)
	v.add_child(Kit.label(Lang.t("Чувствительность"), 14, Kit.TEXT, 700)); v.add_child(_slider("sens", 0.6, 2.4, 0.05, func(x): return "×%.2f" % x))
	v.add_child(_row(Lang.t("Бомба двойным тапом"), Kit.toggle(st.dblBomb, func(on):
		st.dblBomb = on; M.soon())))
	v.add_child(_row(Lang.t("Вибрация"), Kit.toggle(st.vibro, func(on):
		st.vibro = on; M.soon()
		if on: Haptic.medium())))
	v = sec.call(Lang.t("ПРОГРЕСС")).get_child(0)
	v.add_child(_row(Lang.t("Сохранение"), Kit.label(Lang.t("на этом устройстве"), 12, Kit.MUTED, 700)))
	v.add_child(_row(Lang.t("Обучение"), Kit.button(Lang.t("ПРОЙТИ ЗАНОВО"), func():
		M.s.tutor = false
		M.soon()
		Ui.toast({"ico": "🎓", "title": Lang.t("ОБУЧЕНИЕ"), "text": Lang.t("Подсказки появятся в следующем забеге"), "info": true}), "", "sm")))
	v.add_child(_row(Lang.t("Сбросить прогресс"), Kit.button(Lang.t("СБРОС"), func():
		var really := func():
			M.reset(); A.play("explodeM"); Ui.toast({"ico": "🗑️", "title": Lang.t("ГОТОВО"), "text": Lang.t("Прогресс сброшен"), "info": true}); _rerender()
		var first := func():
			Ui.dialog({"ico": "💀", "title": Lang.t("ТОЧНО?"), "text": Lang.t("Последнее предупреждение."), "ok": Lang.t("ДА, СБРОСИТЬ"), "danger": true, "onOk": really})
		Ui.dialog({"ico": "↺", "title": Lang.t("СБРОС ПРОГРЕССА"), "text": Lang.t("Будут удалены кредиты, оружие, прокачка, корабли, импланты, рекорды и достижения.\nЭто нельзя отменить!"), "ok": Lang.t("УДАЛИТЬ ВСЁ"), "danger": true, "onOk": first}), "danger", "sm")))
	if M.DEV:
		v = sec.call(Lang.t("РАЗРАБОТЧИК")).get_child(0)
		v.add_child(_row(Lang.t("+10 000 кредитов"), Kit.button(Lang.t("ДАТЬ"), func():
			M.addCoins(10000, false); A.play("buy"); refresh_wallet(), "", "sm")))
		v.add_child(_row(Lang.t("+10 очков имплантов"), Kit.button(Lang.t("ДАТЬ"), func():
			M.s.spBonus += 10; M.save(); A.play("buy"), "", "sm")))
	body.add_child(Kit.label("Space Shooter · Godot", 11, Kit.DIM, 700, HORIZONTAL_ALIGNMENT_CENTER))
