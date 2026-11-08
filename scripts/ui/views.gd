extends RefCounted
## Экраны интерфейса (перенос разделов index.html + ui.js): главное меню и выбор сложности, пауза, воскрешение,
## итоги забега с контейнерами, окно-подсказка, диалог, баннеры волн и предупреждение о боссе, плашки-уведомления.
## Экраны меню (ангар, арсенал, импланты, реликвии, задания, настройки…) — scripts/ui/menu_screens.gd.

const MenuScreens := preload("res://scripts/ui/menu_screens.gd")


static func fmtMul(v: float) -> String:
	return str(snappedf(v, 0.01)) if Lang.is_en() else str(snappedf(v, 0.01)).replace(".", ",")


## плашка-уведомление: значок, заголовок, текст, награда
static func toast_el(t: Dictionary) -> Control:
	var p := Kit.panel(10, Color(Kit.PANEL_SOLID, 0.94), Color(Kit.CYAN, 0.35) if t.get("info", false) else Color(Kit.GOLD, 0.45), 14)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := Kit.hbox(10)
	var ico: String = t.get("ico", "🏆")
	if ico == "chest": h.add_child(Kit.tex_icon(G.chest("silver").icon, 30))
	elif ico == "info": h.add_child(Kit.icon("", "ℹ️", 30))
	elif t.has("ach"): h.add_child(Kit.ach_icon(t.ach, 32))
	else: h.add_child(Kit.icon(t.get("icon", ""), ico, 30))
	var v := Kit.vbox(1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(Kit.label(t.get("title", ""), 12, Kit.CYAN if t.get("info", false) else Kit.GOLD, 900))
	v.add_child(Kit.para(t.get("text", ""), 13, Kit.TEXT))
	h.add_child(v)
	if t.get("rew", "") != "": h.add_child(Kit.label(t.rew + " ◆", 13, Kit.GOLD, 900))
	p.add_child(h)
	return p


# ════════════════════════════════════════════════════════════
# БАННЕРЫ ВОЛН И ПРЕДУПРЕЖДЕНИЕ О БОССЕ
# ════════════════════════════════════════════════════════════
class Banner extends Control:
	var box: VBoxContainer
	var _t := 0.0
	var _dur := 0.0
	var warn: Control
	var warn_name: Label
	var warn_title: Label
	var _wt := 0.0

	func _ready() -> void:
		Kit.full(self)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		box = Kit.vbox(2)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.set_anchors_preset(Control.PRESET_CENTER)
		box.grow_horizontal = Control.GROW_DIRECTION_BOTH
		box.grow_vertical = Control.GROW_DIRECTION_BOTH
		box.offset_top = -120; box.offset_bottom = -40
		add_child(box)
		box.visible = false
		warn = Kit.vbox(4)
		warn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		warn.set_anchors_preset(Control.PRESET_CENTER)
		warn.grow_horizontal = Control.GROW_DIRECTION_BOTH
		warn.grow_vertical = Control.GROW_DIRECTION_BOTH
		warn.add_child(Kit.label(Lang.t("⚠ ВНИМАНИЕ ⚠"), 16, Kit.RED, 900, HORIZONTAL_ALIGNMENT_CENTER))
		warn_name = Kit.label("", 30, Color.WHITE, 900, HORIZONTAL_ALIGNMENT_CENTER)
		warn_name.add_theme_constant_override("outline_size", 6)
		warn_name.add_theme_color_override("font_outline_color", Color(0.6, 0, 0.1, 0.8))
		warn.add_child(warn_name)
		warn_title = Kit.label("", 12, Kit.MUTED, 600, HORIZONTAL_ALIGNMENT_CENTER)
		warn.add_child(warn_title)
		warn.visible = false
		add_child(warn)

	func show_lines(lines: Array, color: String, dur: float) -> void:
		Kit.clear(box)
		for ln in lines:
			if str(ln[0]) == "": continue
			var lv: int = ln[1]
			var l := Kit.label(str(ln[0]), 34 if lv == 1 else (18 if lv == 2 else 13), U.col(color) if lv == 2 else (Color.WHITE if lv == 1 else Kit.MUTED), 900 if lv < 3 else 600, HORIZONTAL_ALIGNMENT_CENTER)
			l.add_theme_constant_override("outline_size", 6)
			l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(l)
		box.visible = true
		_t = 0.0; _dur = dur

	func boss(def: Dictionary) -> void:
		warn_name.text = def.name
		warn_title.text = def.get("title", "")
		warn.visible = true
		_wt = 2.9
		Haptic.warning()

	func tick(dt: float) -> void:
		if box.visible:
			_t += dt
			var k := _t / maxf(0.01, _dur)
			box.modulate.a = clampf(minf(_t / 0.2, (1 - k) / 0.2), 0, 1)
			box.scale = Vector2.ONE * (1.0 + 0.08 * maxf(0, 1 - _t / 0.25))
			box.pivot_offset = box.size / 2
			if k >= 1: box.visible = false
		if warn.visible:
			_wt -= dt
			warn.modulate.a = clampf(minf((2.9 - _wt) / 0.2, _wt / 0.3), 0, 1) * (0.75 + 0.25 * absf(sin(_wt * 8)))
			if _wt <= 0: warn.visible = false


# ════════════════════════════════════════════════════════════
# ГЛАВНОЕ МЕНЮ
# ════════════════════════════════════════════════════════════
class MenuView extends Control:
	var coins: Label
	var lvl: Label
	var best: Label
	var play_sub: Label
	var diff: Control
	var screens: Control
	var hero: Control
	var content: Control
	var mission_sub: Label

	## плитка раздела (.tile в JS): значок цвета раздела, название, подпись
	func _tile(icon: String, title: String, sub: String, col: Color, id: String) -> Button:
		var b := Kit.button("", func(): open_screen(id), "", "")
		# рамка цвета раздела: уголки и риски — его цвет, при нажатии вспыхивает
		b.add_theme_stylebox_override("normal", Kit.neo(Kit.PANEL2, Color(col, 0.4), Color(col, 0.9), 12, 4, 0.15))
		b.add_theme_stylebox_override("hover", Kit.neo(Kit.PANEL2.lightened(0.06), Color(col, 0.5), col, 12, 4, 0.25))
		b.add_theme_stylebox_override("pressed", Kit.neo(Color(col, 0.22), col, Color.WHITE, 12, 4, 0.6))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(10, 84)
		var v := Kit.vbox(4)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		Kit.full(v)
		var ic := Icons.rect(icon, col, 24)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		v.add_child(Kit.label(title, 11, Kit.TEXT, 800, HORIZONTAL_ALIGNMENT_CENTER))
		var s := Kit.label(sub, 11, Kit.DIM, 600, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(s)
		Kit.passthrough(v)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		b.set_meta("sub", s)
		return b

	## небольшая кнопка строки под плитками (.mb-btn в JS): значок и подпись
	func _bar_btn(icon: String, text: String, col: Color, id: String) -> Button:
		var b := Kit.button("", func(): open_screen(id), "ghost", "")
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, Kit.neo(Color(10 / 255.0, 16 / 255.0, 40 / 255.0, 0.5 if st != "pressed" else 0.75),
				Color(col, 0.18 if st != "pressed" else 0.6), Color(col, 0.45 if st != "pressed" else 1.0), 8, 4, 0.0 if st != "pressed" else 0.4))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(10, 56)
		var v := Kit.vbox(3)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		Kit.full(v)
		var ic := Icons.rect(icon, Color(col, 0.85), 19)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		v.add_child(Kit.label(text, 10, Kit.DIM.lightened(0.25), 600, HORIZONTAL_ALIGNMENT_CENTER))
		Kit.passthrough(v)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		return b

	## разделы меню закрывают главный экран целиком — и корабль на фоне прячем
	func set_content_visible(on: bool) -> void:
		content.visible = on
		Game.attract.slot = {"y": hero.global_position.y + hero.size.y / 2 - 10, "h": hero.size.y} if on else {"y": -999.0, "h": 0.0}

	func _ready() -> void:
		Kit.full(self)
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := Kit.margin(16, 14, 16, 16)
		Kit.full(m)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(m)
		content = m
		Kit.safe(m)   # Godot: вырез сверху и полоска «домой» снизу (айфон) — меню не прилипает к краям
		var v := Kit.vbox(10)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(v)
		# шапка: пилот и уровень корабля, кошелёк
		var head := Kit.hbox(8)
		var prof := Kit.vbox(0)
		prof.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lvl = Kit.label("", 13, Kit.MUTED, 700)
		prof.add_child(Kit.label(Lang.t("ПИЛОТ"), 11, Kit.DIM, 800))
		prof.add_child(lvl)
		head.add_child(prof)
		coins = Kit.label("", 18, Kit.GOLD, 900)
		head.add_child(Kit.tex_icon(G.proc("coin"), 22))
		head.add_child(coins)
		v.add_child(head)
		# логотип и рекорд
		var logo := Kit.vbox(0)
		logo.add_child(Kit.label("SPACE", 46, Color.WHITE, 900, HORIZONTAL_ALIGNMENT_CENTER))
		var l2 := Kit.label("SHOOTER", 27, Kit.CYAN, 900, HORIZONTAL_ALIGNMENT_CENTER)
		logo.add_child(l2)
		logo.add_child(Kit.label("GODOT EDITION", 12, Kit.GOLD, 800, HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(logo)
		var best_row := Kit.hbox(6)
		best_row.alignment = BoxContainer.ALIGNMENT_CENTER
		best_row.add_child(Icons.rect("trophy", Kit.GOLD, 16))
		best = Kit.label("", 13, Kit.MUTED, 700, HORIZONTAL_ALIGNMENT_CENTER)
		best_row.add_child(best)
		v.add_child(best_row)
		# место под корабль (Game.drawAttract рисует его в игровом слое)
		hero = Kit.spacer(0, true)
		v.add_child(hero)
		hero.resized.connect(func(): Game.attract.slot = {"y": hero.global_position.y + hero.size.y / 2 - 10, "h": hero.size.y})
		v.add_child(Kit.icon_button("play", Lang.t("ИГРАТЬ"), func(): show_diff(), "primary", "big"))
		play_sub = Kit.label("", 12, Kit.MUTED, 600, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(play_sub)
		# как в JS: четыре крупные плитки, ниже — строка небольших значков; цвет значка у каждого раздела свой
		var tiles := Kit.hbox(7)
		for it in [["ship", Lang.t("ВЕРФЬ"), Lang.t("Корабли"), Kit.CYAN, "hangar"], ["swords", Lang.t("ОРУЖЕЙНАЯ"), Lang.t("Оружие"), Kit.GOLD, "arsenal"],
				["atom", Lang.t("ИМПЛАНТЫ"), Lang.t("Нейросеть"), Kit.VIOLET, "skills"], ["target", Lang.t("КОНТРАКТЫ"), "", Kit.ORANGE, "missions"]]:
			var t := _tile(it[0], it[1], it[2], it[3], it[4])
			tiles.add_child(t)
			if it[4] == "missions": mission_sub = t.get_meta("sub")
		v.add_child(tiles)
		var bar := Kit.hbox(6)
		for it in [["trophy", Lang.t("Бортжурнал"), Kit.PINK, "leaders"], ["medal", Lang.t("Медали"), Kit.GREEN, "achievements"],
				["chest", Lang.t("Ксенотех"), Kit.GOLD, "relics"], ["list", Lang.t("Банк данных"), Kit.CYAN, "codex"], ["gear", Lang.t("Настройки"), Color("#aab4d8"), "settings"]]:
			bar.add_child(_bar_btn(it[0], it[1], it[2], it[3]))
		v.add_child(bar)
		diff = DiffView.new()
		add_child(diff)
		screens = MenuScreens.new()
		add_child(screens)

	func open() -> void:
		visible = true
		diff.visible = false
		screens.close()
		content.visible = true
		refresh()
		Game.attract.slot = {"y": hero.global_position.y + hero.size.y / 2 - 10, "h": hero.size.y}

	func close() -> void:
		visible = false
		diff.visible = false
		screens.close()

	func refresh() -> void:
		var s: Dictionary = M.s
		var pil: Dictionary = D.PILOTS.get(s.pilot, D.PILOTS.kai)
		lvl.text = Lang.t("%s %s • Корабль %d%s") % [pil.ico, pil.name, s.shipLvl, (" • ✦%d" % s.prestige) if s.prestige else ""]
		best.text = Lang.t("Рекорд: %s  •  Волна %d") % [U.fmt(s.stats.bestScore), s.stats.bestWave]
		var ms := M.missions()
		mission_sub.text = "%d / %d" % [ms.filter(func(m): return m.done).size(), ms.size()]
		var cd: Dictionary = D.DIFFS.get(s.settings.diff, D.DIFFS.normal)
		play_sub.text = Lang.t("Сложность: %s • награды ×%s") % [cd.name, Views_fmt(cd.coins)]
		refresh_wallet()

	func refresh_wallet() -> void:
		if coins: coins.text = U.fmt(M.s.coins)
		if screens and screens.visible: screens.refresh_wallet()

	func show_diff() -> void:
		A.play("click")
		Haptic.medium()
		set_content_visible(false)
		diff.open()

	func open_screen(id: String) -> void:
		screens.open(id)

	func back() -> void:
		if diff.visible:
			A.play("back")
			diff.visible = false
			set_content_visible(true)
			return
		if screens.visible:
			screens.back()

	static func Views_fmt(v: float) -> String:
		return str(snappedf(v, 0.01)) if Lang.is_en() else str(snappedf(v, 0.01)).replace(".", ",")


# ── выбор сложности, режима и испытание дня ──
class DiffView extends Control:
	var list: VBoxContainer
	var lives: Label
	var modes: HBoxContainer
	var go: Button
	var sel := "normal"

	func _ready() -> void:
		Kit.full(self)
		visible = false
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(Kit.dim(0.8))
		var m := Kit.safe(Kit.margin(16, 20, 16, 16))
		Kit.full(m)
		add_child(m)
		var v := Kit.vbox(10)
		m.add_child(v)
		var head := Kit.hbox(8)
		var t := Kit.label(Lang.t("СЛОЖНОСТЬ"), 22, Kit.TEXT, 900)
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(t)
		var close_fn := func():
			A.play("back")
			visible = false
			if get_parent().has_method("set_content_visible"): get_parent().set_content_visible(true)
		head.add_child(Kit.icon_button("close", "", close_fn, "ghost", "sm"))
		v.add_child(head)
		lives = Kit.label("", 13, Kit.MUTED, 600)
		v.add_child(lives)
		var sc := ScrollContainer.new()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		list = Kit.vbox(8)
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(list)
		v.add_child(sc)
		modes = Kit.hbox(6)
		v.add_child(modes)
		go = Kit.button(Lang.t("В БОЙ"), func(): _go(), "primary", "big")
		v.add_child(go)

	func open() -> void:
		var s: Dictionary = M.s
		sel = s.settings.diff if D.DIFFS.has(s.settings.diff) and M.diffUnlocked(s.settings.diff) else "normal"
		var power := M.power()
		var lv: int = int(D.BASE_LIVES + D.SHIPS[s.ship.model].stats.get("lives", 0))
		lives.text = Lang.t("❤ Жизней: %d • ⚡ Боевая мощь: %s") % [lv, U.fmt(power)]
		_render()
		visible = true

	func _row(id: String, col: String, name_: String, meta: String, rew: String, open_: bool, selected: bool, on_tap: Callable) -> Control:
		var c := U.col(col)
		var p := Kit.panel(12, Color(c, 0.14) if selected else Color(Kit.PANEL_SOLID, 0.9), c if selected else Color(c, 0.35), 14)
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		if not open_: p.modulate.a = 0.5
		var h := Kit.hbox(10)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var v := Kit.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var nm := Kit.label(name_, 15, c, 900)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(nm)
		var mt := Kit.para(meta, 12)
		mt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(mt)
		h.add_child(v)
		var r := Kit.label(rew, 14, Kit.GOLD, 900, HORIZONTAL_ALIGNMENT_RIGHT)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(r)
		p.add_child(h)
		p.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT and Rect2(Vector2.ZERO, p.size).has_point(e.position):
				on_tap.call())
		return p

	func _pct(v: float) -> String:
		var d := int(round((v - 1) * 100))
		return ("+" if d > 0 else "−") + str(absi(d)) + "%"

	func _render() -> void:
		Kit.clear(list)
		var s: Dictionary = M.s
		var power := M.power()
		# испытание дня — первой строкой
		var ch := M.challenge()
		var cs := M.challengeState()
		var mods: Array = []
		for mid in ch.mods:
			for x in D.CHALLENGE_MODS:
				if x.id == mid: mods.append(x.name)
		var tiers: Array = D.CHALLENGE_TIERS
		var rew := Lang.t("✓ всё получено") if cs.tiers >= tiers.size() else Lang.t("◆ %d за волну %d") % [tiers[cs.tiers].coins, tiers[cs.tiers].wave]
		list.add_child(_row("daily", "#ff5cf0", Lang.t("ИСПЫТАНИЕ ДНЯ") + (Lang.t("  · сегодня: волна %d") % cs.wave if cs.wave else ""), " · ".join(mods), rew, true, sel == "daily", func(): _pick("daily")))
		for id in D.DIFF_ORDER:
			var d: Dictionary = D.DIFFS[id]
			var bst: Dictionary = s.stats.diff.get(id, {"wave": 0})
			var opened := M.diffUnlocked(id)
			var meta := ""
			if opened:
				var parts: Array = []
				for x in [[Lang.t("Враги"), d.count], [Lang.t("Броня"), d.hp], [Lang.t("Огонь"), d.fire]]:
					if x[1] != 1.0: parts.append("%s %s" % [x[0], _pct(x[1])])
				meta = "  ".join(parts) if not parts.is_empty() else Lang.t("Обычные враги и награды")
			else:
				meta = Lang.t("🔒 Откроется: волна %d на «%s»") % [D.DIFF_UNLOCK_WAVE, D.DIFFS[d.unlock].name]
			var nm: String = d.name + (Lang.t("  · рекорд: волна %d") % bst.wave if bst.get("wave", 0) else "")
			var did: String = id
			list.add_child(_row(id, d.color, nm, meta, "◆ ×" + MenuView.Views_fmt(d.coins * M.overpowerK(id, power)), opened, did == sel, func():
				if opened: _pick(did)
				else:
					A.play("error"); Haptic.error()))
		Kit.clear(modes)
		var curm: String = s.settings.get("mode", "normal")
		if not D.MODES.has(curm): curm = "normal"
		for k in D.MODES:
			var md: Dictionary = D.MODES[k]
			var kk: String = k
			var mode_fn := func():
				M.s.settings.mode = kk; M.soon(); _render()
			var b := Kit.button(md.ico + " " + md.name, mode_fn, "primary" if k == curm else "", "sm")
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			modes.add_child(b)
		modes.visible = sel != "daily"

	func _pick(id: String) -> void:
		A.play("click")
		sel = id
		if id != "daily":
			M.s.settings.diff = id; M.soon()
		_render()

	func _go() -> void:
		visible = false
		if sel == "daily":
			Ui.startRun("normal", {"challenge": M.challenge()})
		else:
			Ui.startRun(sel, {"mode": M.s.settings.get("mode", "normal")})


# ════════════════════════════════════════════════════════════
# ПАУЗА
# ════════════════════════════════════════════════════════════
class PauseView extends Control:
	var info: Label
	var fx: VBoxContainer
	var build: VBoxContainer
	var tg_music: Button
	var tg_sfx: Button
	var tg_vibe: Button

	func _ready() -> void:
		Kit.full(self)
		visible = false
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(Kit.dim(0.75))
		var c := CenterContainer.new(); Kit.full(c); add_child(c)
		var p := Kit.panel(18)
		p.custom_minimum_size.x = 330
		c.add_child(p)
		var v := Kit.vbox(10)
		p.add_child(v)
		v.add_child(Kit.label(Lang.t("ПАУЗА"), 26, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER))
		info = Kit.label("", 14, Kit.MUTED, 700, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(info)
		fx = Kit.vbox(4); v.add_child(fx)
		build = Kit.vbox(4); v.add_child(build)
		var tg := Kit.hbox(6)
		tg_music = Kit.button(Lang.t("♪ МУЗЫКА"), func(): _vol("music"), "", "sm")
		tg_sfx = Kit.button(Lang.t("🔊 ЗВУК"), func(): _vol("sfx"), "", "sm")
		var vibe_fn := func():
			M.s.settings.vibro = not M.s.settings.vibro; M.soon(); _sync()
		tg_vibe = Kit.button(Lang.t("📳 ВИБРО"), vibe_fn, "", "sm")
		for b in [tg_music, tg_sfx, tg_vibe]:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tg.add_child(b)
		v.add_child(tg)
		v.add_child(Kit.button(Lang.t("🛠 СХЕМА КОРАБЛЯ"), func(): Ui.ship.open(), "", "sm"))
		v.add_child(Kit.button(Lang.t("▶  ПРОДОЛЖИТЬ"), func(): Game.resume(), "primary", "big"))
		var quit_fn := func():
			var leave := func():
				close()
				Game.gameOver()
			Ui.dialog({"ico": "🏠", "title": Lang.t("ВЫЙТИ В МЕНЮ?"), "text": Lang.t("Забег будет завершён.
Собранные кредиты останутся у вас."), "ok": Lang.t("ВЫЙТИ"), "onOk": leave})
		v.add_child(Kit.button(Lang.t("ВЫЙТИ В МЕНЮ"), quit_fn, "danger"))

	func open() -> void:
		var g = Game
		var run: Dictionary = g.run
		info.text = Lang.t("Счёт %s  •  Волна %d  •  ◆ %s") % [U.fmt_short(run.score), g.wave.n if g.wave else 1, U.fmt(run.coins)]
		Kit.clear(fx)
		var an = g.anomaly()
		if an:
			var d: Dictionary = D.ANOMALIES[an]
			fx.add_child(_fxrow(d.color, d.ico, Lang.t("Аномалия: ") + d.name, d.desc + Lang.t(" · награды +%d%%") % int(round(d.bonus * 100))))
		var wev = Events.active()
		if wev: fx.add_child(_fxrow(wev.color, wev.ico, wev.name, wev.get("desc", "")))
		for k in g.buffs: fx.add_child(_fxrow(D.POWERUPS[k].color, "★", D.POWERUPS[k].name, Lang.t("ещё %d с") % int(ceil(g.buffs[k]))))
		Kit.clear(build)
		var pil: Dictionary = D.PILOTS.get(run.pilot, D.PILOTS.kai)
		build.add_child(Kit.label(pil.ico + " " + pil.name + Lang.t("  · СБОРКА ЗАБЕГА"), 12, U.col(pil.color), 800))
		# значки сборки — спрайты (модули md_, улучшения pk_, ксенотех r_), уровень — цифрой в углу
		var items: Array = []
		for m in D.MODULES:
			if run.mods.get(m.id): items.append(["md_" + m.id, m.ico, int(run.mods[m.id])])
		for pk in D.PERKS:
			if run.perks.get(pk.id) and not pk.filler: items.append(["pk_" + pk.id, pk.ico, int(run.perks[pk.id])])
		for id in run.relics:
			if D.RELICS.has(id): items.append([id, D.RELICS[id].ico, 1])
		if items.is_empty():
			build.add_child(Kit.para(Lang.t("Пока пусто — модули на станциях, улучшения за кристаллы"), 13, Kit.MUTED))
		else:
			var grid := HFlowContainer.new()
			grid.add_theme_constant_override("h_separation", 4)
			grid.add_theme_constant_override("v_separation", 4)
			for it in items:
				var cell := Control.new()
				cell.custom_minimum_size = Vector2(34, 34)
				cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var ic := Kit.icon(it[0], it[1], 34)
				cell.add_child(ic)
				if it[2] > 1:
					var n := Kit.label(str(it[2]), 11, Kit.GOLD, 900)
					n.position = Vector2(24, 20)
					cell.add_child(n)
				grid.add_child(cell)
			build.add_child(grid)
		_sync()
		visible = true
		A.muffle(true)

	func close() -> void:
		if visible: A.muffle(false)
		visible = false

	func _fxrow(col: String, ico: String, name_: String, desc: String) -> Control:
		var h := Kit.hbox(8)
		h.add_child(Kit.label(ico, 18))
		var v := Kit.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(Kit.label(name_, 13, U.col(col), 800))
		v.add_child(Kit.para(desc, 12))
		h.add_child(v)
		return h

	func _vol(k: String) -> void:
		var st: Dictionary = M.s.settings
		if st[k] > 0:
			st["_" + k] = st[k]; st[k] = 0
		else:
			st[k] = st.get("_" + k, 70)
		M.soon()
		A.applyVolumes()
		_sync()

	func _sync() -> void:
		var st: Dictionary = M.s.settings
		tg_music.modulate.a = 1.0 if st.music > 0 else 0.45
		tg_sfx.modulate.a = 1.0 if st.sfx > 0 else 0.45
		tg_vibe.modulate.a = 1.0 if st.vibro else 0.45


# ════════════════════════════════════════════════════════════
# ВОСКРЕШЕНИЕ: 5 секунд на решение
# ════════════════════════════════════════════════════════════
class ReviveView extends Control:
	var cost_l: Label
	var sec_l: Label
	var _left := 0.0

	func _ready() -> void:
		Kit.full(self)
		visible = false
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(Kit.dim(0.7))
		var c := CenterContainer.new(); Kit.full(c); add_child(c)
		var p := Kit.panel(18)
		p.custom_minimum_size.x = 300
		c.add_child(p)
		var v := Kit.vbox(10)
		p.add_child(v)
		v.add_child(Kit.label(Lang.t("КОРАБЛЬ ПОДБИТ"), 22, Kit.RED, 900, HORIZONTAL_ALIGNMENT_CENTER))
		sec_l = Kit.label("5", 44, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(sec_l)
		cost_l = Kit.label("", 14, Kit.GOLD, 800, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(cost_l)
		v.add_child(Kit.button(Lang.t("❤ ВОСКРЕСНУТЬ"), func(): Game.revive(), "gold", "big"))
		var no_fn := func():
			close()
			Game.gameOver()
		v.add_child(Kit.button(Lang.t("НЕТ, СПАСИБО"), no_fn, "ghost"))

	func open(cost: int) -> void:
		cost_l.text = Lang.t("Стоимость: ◆ ") + U.fmt(cost)
		_left = 5.0
		visible = true

	func close() -> void:
		visible = false

	func _process(dt: float) -> void:
		if not visible: return
		_left -= dt
		sec_l.text = str(maxi(0, int(ceil(_left))))
		if _left <= 0:
			close()
			Game.gameOver()


# ════════════════════════════════════════════════════════════
# ИТОГИ ЗАБЕГА: счёт набегает, статистика, награды, опыт корабля, контейнеры (открываются здесь)
# ════════════════════════════════════════════════════════════
class OverView extends Control:
	var title: Label
	var sub: Label
	var cause: Label
	var score: Label
	var best: Label
	var stats: GridContainer
	var rew: Label
	var xp_bar: ProgressBar
	var xp_lvl: Label
	var chests: VBoxContainer
	var events: HFlowContainer
	var share_btn: Button
	var sum: Dictionary = {}
	var _t := 0.0
	var _counts: Array = []

	func _ready() -> void:
		Kit.full(self)
		visible = false
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(Kit.dim(0.86))
		var sc := ScrollContainer.new(); Kit.full(sc)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		add_child(sc)
		var c := CenterContainer.new()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		sc.add_child(c)
		var m := Kit.safe(Kit.margin(16, 24, 16, 24))
		c.add_child(m)
		var v := Kit.vbox(10)
		v.custom_minimum_size.x = 340
		m.add_child(v)
		title = Kit.label("", 26, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER); v.add_child(title)
		sub = Kit.label("", 12, Kit.MUTED, 700, HORIZONTAL_ALIGNMENT_CENTER); v.add_child(sub)
		cause = Kit.label("", 12, Kit.RED, 700, HORIZONTAL_ALIGNMENT_CENTER); v.add_child(cause)
		var sp := Kit.panel(14)
		var sv := Kit.vbox(2)
		sv.add_child(Kit.label(Lang.t("СЧЁТ"), 11, Kit.DIM, 800, HORIZONTAL_ALIGNMENT_CENTER))
		score = Kit.label("0", 40, Color.WHITE, 900, HORIZONTAL_ALIGNMENT_CENTER); sv.add_child(score)
		best = Kit.label("", 12, Kit.MUTED, 700, HORIZONTAL_ALIGNMENT_CENTER); sv.add_child(best)
		sp.add_child(sv)
		v.add_child(sp)
		stats = GridContainer.new(); stats.columns = 3
		stats.add_theme_constant_override("h_separation", 6); stats.add_theme_constant_override("v_separation", 6)
		v.add_child(stats)
		rew = Kit.label("", 18, Kit.GOLD, 900, HORIZONTAL_ALIGNMENT_CENTER); v.add_child(rew)
		var xh := Kit.hbox(8)
		xp_lvl = Kit.label("", 12, Kit.CYAN, 800); xh.add_child(xp_lvl)
		xp_bar = ProgressBar.new(); xp_bar.show_percentage = false; xp_bar.custom_minimum_size.y = 8
		xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		xp_bar.add_theme_stylebox_override("background", Kit.box(Color(1, 1, 1, 0.1), Color(0, 0, 0, 0), 4))
		xp_bar.add_theme_stylebox_override("fill", Kit.box(Kit.CYAN, Color(0, 0, 0, 0), 4))
		xh.add_child(xp_bar)
		v.add_child(xh)
		chests = Kit.vbox(6); v.add_child(chests)
		# события забега: значок (у достижений — медаль) и подпись
		events = HFlowContainer.new()
		events.alignment = FlowContainer.ALIGNMENT_CENTER
		events.add_theme_constant_override("h_separation", 10)
		events.add_theme_constant_override("v_separation", 4)
		v.add_child(events)
		var bh := Kit.hbox(8)
		var again := Kit.button(Lang.t("↻ ЕЩЁ РАЗ"), func(): Ui.again(), "primary", "big")
		again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var menu := Kit.button(Lang.t("МЕНЮ"), func(): Ui.toMenu(), "", "big")
		menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bh.add_child(again); bh.add_child(menu)
		v.add_child(bh)
		# Godot: карточка забега картинкой — в браузере системное «Поделиться», на компьютере файл
		share_btn = Kit.icon_button("share", Lang.t("ПОДЕЛИТЬСЯ"), func(): _share(), "ghost")
		v.add_child(share_btn)

	func _share() -> void:
		if share_btn.disabled: return
		share_btn.disabled = true
		var img: Image = await ShareCard.render(self, sum)
		var msg := ShareCard.share(img, int(sum.get("score", 0)))
		share_btn.disabled = false
		if msg != "": Ui.toast({"info": true, "ico": "info", "title": Lang.t("КАРТОЧКА ЗАБЕГА"), "text": msg})

	func open(s: Dictionary) -> void:
		sum = s
		var st: Dictionary = M.s.stats
		title.text = Lang.t("НОВЫЙ РЕКОРД") if s.isRecord else Lang.t("КОРАБЛЬ ПОДБИТ")
		title.add_theme_color_override("font_color", Kit.GOLD if s.isRecord else Kit.TEXT)
		var d: Dictionary = D.DIFFS.get(s.diff, D.DIFFS.normal)
		sub.text = Lang.t("%s • награды ×%s • Волна %d") % [d.name, MenuView.Views_fmt(d.coins), s.wave]
		cause.text = (Lang.t("Сбит: ") + s.cause) if s.get("cause", "") != "" else ""
		var md = st.get("modes", {}).get(s.get("mode", "normal")) if s.get("mode", "normal") != "normal" else null
		best.text = Lang.t("Лучший: ") + U.fmt(md.best if md else st.bestScore)
		Kit.clear(stats)
		_counts.clear()
		var dur: float = minf(1.6, 0.4 + log(s.score + 10) / log(10) * 0.25)
		_counts.append({"l": score, "to": float(s.score), "f": func(n): return U.fmt(n), "at": 0.35, "dur": dur})
		var rows := [[Lang.t("💀 Враги"), s.kills, func(n): return U.fmt(n)], [Lang.t("👑 Боссы"), s.bosses, func(n): return U.fmt(n)], [Lang.t("⚡ Комбо"), s.maxCombo, func(n): return "×%d" % int(n)],
			[Lang.t("📈 Уровень"), s.level, func(n): return U.fmt(n)], [Lang.t("🎯 Точность"), s.accuracy, func(n): return "%d%%" % int(n)], [Lang.t("⏱ Время"), s.time, func(n): return U.fmt_time(n)]]
		for i in rows.size():
			var r: Array = rows[i]
			var p := Kit.panel(8)
			var pv := Kit.vbox(0)
			pv.add_child(Kit.label(r[0], 11, Kit.MUTED, 700, HORIZONTAL_ALIGNMENT_CENTER))
			var val := Kit.label("0", 16, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER)
			pv.add_child(val)
			p.add_child(pv)
			p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stats.add_child(p)
			_counts.append({"l": val, "to": float(r[1]), "f": r[2], "at": 0.6 + i * 0.09, "dur": 0.65})
		rew.text = Lang.t("◆ +%s    ✦ +%s опыта") % [U.fmt(s.coins + s.get("lvlCoins", 0)), U.fmt(s.xp)]
		xp_lvl.text = Lang.t("Ур. %d") % M.s.shipLvl
		xp_bar.max_value = D.ship_xp_need(M.s.shipLvl)
		xp_bar.value = M.s.shipXP
		_render_chests()
		Kit.clear(events)
		for a in Ui.runEvents.slice(0, 8):
			var h := Kit.hbox(4)
			h.add_child(Kit.ach_icon(a.ach, 22) if a.has("ach") else Kit.icon("", a.ico, 20))
			var l := Kit.label(a.text, 12, Kit.MUTED, 700)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			h.add_child(l)
			events.add_child(h)
		_t = 0.0
		visible = true

	func close() -> void:
		visible = false

	func _process(dt: float) -> void:
		if not visible: return
		_t += dt
		for c in _counts:
			var k := clampf((_t - c.at) / c.dur, 0, 1)
			c.l.text = c.f.call(c.to * U.ease_out_cubic(k))

	## 4.1: контейнеры забега — открываются только здесь, по одному
	func _render_chests() -> void:
		Kit.clear(chests)
		var n: int = M.s.chests.size()
		if n == 0: return
		var h := Kit.hbox(8)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		for i in mini(n, 6): h.add_child(Kit.tex_icon(G.chest(M.s.chests[i]).icon, 48))
		chests.add_child(h)
		chests.add_child(Kit.button(Lang.t("ОТКРЫТЬ КОНТЕЙНЕР (%d)") % n, func(): _open_chest(), "gold"))

	func _open_chest() -> void:
		var r = M.openChest()
		if r == null: return
		var rel: Dictionary = D.RELICS[r.id]
		A.play("achievement")
		Haptic.success()
		var col: String = D.RELIC_RARITY[rel.rar].color
		Ui.dialog({"ico": rel.ico, "title": (Lang.t("ПОВТОР: ") if r.dupe else Lang.t("КСЕНОТЕХ: ")) + rel.name, "text": rel.desc + (Lang.t("\n\nУже в коллекции — взамен ◆ %d") % r.coins if r.dupe else Lang.t("\n\nДобавлен в коллекцию")), "ok": Lang.t("ОТЛИЧНО"), "noCancel": true, "color": col})
		_render_chests()


# ════════════════════════════════════════════════════════════
# ОКНО-ПОДСКАЗКА (4.3.2): игра стоит, пока окно открыто
# ════════════════════════════════════════════════════════════
class TipView extends Control:
	var kind: Label
	var ico: Label
	var title: Label
	var note: Label
	var how: Label
	var use: Label
	var panel: PanelContainer
	var demo_box: VBoxContainer

	func _ready() -> void:
		Kit.full(self)
		visible = false
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(Kit.dim(0.72))
		var c := CenterContainer.new(); Kit.full(c); add_child(c)
		panel = Kit.panel(18)
		panel.custom_minimum_size.x = 320
		c.add_child(panel)
		var v := Kit.vbox(8)
		panel.add_child(v)
		kind = Kit.label("", 11, Kit.MUTED, 800, HORIZONTAL_ALIGNMENT_CENTER); v.add_child(kind)
		ico = Kit.label("", 40, Kit.TEXT, 600, HORIZONTAL_ALIGNMENT_CENTER); v.add_child(ico)
		title = Kit.label("", 20, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER); v.add_child(title)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size.x = 10
		note = Kit.para("", 13, Kit.GOLD, HORIZONTAL_ALIGNMENT_CENTER); v.add_child(note)
		demo_box = Kit.vbox(0); v.add_child(demo_box)
		v.add_child(Kit.label(Lang.t("КАК РАБОТАЕТ"), 11, Kit.CYAN, 800))
		how = Kit.para("", 14, Kit.TEXT); v.add_child(how)
		v.add_child(Kit.label(Lang.t("КАК ИСПОЛЬЗОВАТЬ"), 11, Kit.GREEN, 800))
		use = Kit.para("", 14, Kit.TEXT); v.add_child(use)
		v.add_child(Kit.button(Lang.t("ПОНЯТНО"), func(): Game.closeTip(), "primary", "big"))

	func open(t: Dictionary) -> void:
		var col: String = t.get("color", "#3de0ff")
		var tb := Kit.neo(Kit.PANEL, Color(U.col(col), 0.6), U.col(col).lightened(0.3), 14, 18)
		tb.notch = true
		panel.add_theme_stylebox_override("panel", tb)
		kind.text = t.get("kind", "")
		var ic: String = t.get("ico", "")
		ico.text = "" if ic.begins_with("<") else ic
		title.text = t.get("title", "")
		title.add_theme_color_override("font_color", U.col(col))
		note.text = t.get("note", ""); note.visible = note.text != ""
		how.text = t.get("how", "")
		use.text = t.get("use", "")
		# живая сцена: эволюция — оружие в усиленном виде, событие или аномалия — своя сцена
		Kit.clear(demo_box)
		var key: String = t.get("key", "")
		if key.begins_with("evo_"): demo_box.add_child(Kit.demo_view(Demo.weapon(key.substr(4), true), Vector2(0, 150)))
		elif Demo.hasScene(key): demo_box.add_child(Kit.demo_view(Demo.scene(key), Vector2(0, 150)))
		A.play("perk", {"vol": 0.6})
		visible = true

	func close() -> void:
		visible = false


# ════════════════════════════════════════════════════════════
# ДИАЛОГ: { ico, title, text, ok, danger, noCancel, onOk }
# ════════════════════════════════════════════════════════════
class DialogView extends Control:
	var ico: Label
	var title: Label
	var text: Label
	var ok: Button
	var cancel: Button
	var _onOk = null

	func _ready() -> void:
		Kit.full(self)
		visible = false
		mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(Kit.dim(0.7))
		var c := CenterContainer.new(); Kit.full(c); add_child(c)
		var p := Kit.panel(18)
		p.custom_minimum_size.x = 310
		c.add_child(p)
		var v := Kit.vbox(10)
		p.add_child(v)
		ico = Kit.label("", 36, Kit.TEXT, 600, HORIZONTAL_ALIGNMENT_CENTER); v.add_child(ico)
		title = Kit.label("", 18, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(title)
		text = Kit.para("", 14, Kit.MUTED, HORIZONTAL_ALIGNMENT_CENTER); v.add_child(text)
		var h := Kit.hbox(8)
		var cancel_fn := func():
			A.play("back")
			close()
		cancel = Kit.button(Lang.t("ОТМЕНА"), cancel_fn, "ghost")
		cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(cancel)
		var ok_fn := func():
			close()
			if _onOk is Callable: _onOk.call()
		ok = Kit.button(Lang.t("ОК"), ok_fn, "primary")
		ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(ok)
		v.add_child(h)

	func open(o: Dictionary) -> void:
		var ic: String = o.get("ico", "")
		ico.text = "⭐" if ic == "star" else ic
		ico.visible = ico.text != ""
		title.text = o.get("title", "")
		if o.has("color"): title.add_theme_color_override("font_color", U.col(o.color))
		else: title.add_theme_color_override("font_color", Kit.TEXT)
		text.text = o.get("text", "")
		ok.text = o.get("ok", Lang.t("ОК"))
		cancel.visible = not o.get("noCancel", false)
		_onOk = o.get("onOk")
		visible = true

	func close() -> void:
		visible = false
