extends Node
## Интерфейс (автозагрузка Ui) — перенос ui.js: экраны поверх игры, переходы, уведомления (тосты), баннеры волн,
## предупреждение о боссе, связь с игрой через Bus. Экраны — Control-узлы из scripts/ui/*_view.gd.
## В JS это был HTML+CSS; здесь всё строится кодом (Kit), шрифт — Exo 2 с кириллицей.

const HudView := preload("res://scripts/ui/hud_view.gd")
const OfferView := preload("res://scripts/ui/offer_view.gd")
const MapView := preload("res://scripts/ui/map_view.gd")
const Views := preload("res://scripts/ui/views.gd")

var layer: CanvasLayer
var root: Control
var hud: Control
var offer: Control
var map: Control
var menu: Control
var pause_v: Control
var over: Control
var tip: Control
var revive: Control
var dialog_v: Control
var ship: Control
var toasts: VBoxContainer
var tutor: TutorView       # Godot: обучение в первом забеге
var banner_box: Control
var cur := "menu"
var runEvents: Array = []
var _toastQ: Array = []
var _runOpts = null


func build(world: Node) -> void:
	layer = CanvasLayer.new()
	layer.layer = 5
	world.add_child(layer)
	root = Control.new()
	root.theme = Kit.theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Kit.full(root)
	layer.add_child(root)
	hud = HudView.new(); root.add_child(hud); Hud.view = hud
	# баннеры волн — под окнами выбора и паузой
	banner_box = Views.Banner.new(); root.add_child(banner_box)
	menu = Views.MenuView.new(); root.add_child(menu)
	offer = OfferView.new(); root.add_child(offer)
	map = MapView.new(); root.add_child(map)
	pause_v = Views.PauseView.new(); root.add_child(pause_v)
	revive = Views.ReviveView.new(); root.add_child(revive)
	over = Views.OverView.new(); root.add_child(over)
	tip = Views.TipView.new(); root.add_child(tip)
	toasts = Kit.vbox(8)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toasts.offset_left = 12; toasts.offset_right = -12
	root.add_child(toasts)
	tutor = TutorView.new(); root.add_child(tutor)
	ship = preload("res://scripts/ui/ship_view.gd").new(); root.add_child(ship)
	dialog_v = Views.DialogView.new(); root.add_child(dialog_v)
	# окна появляются плавно (Tween), разделы меню въезжают сбоку
	for v in [pause_v, revive, over, tip, dialog_v, ship, menu.diff]: Kit.animate_on_show(v)
	Kit.animate_on_show(menu.screens, true)
	Kit.animate_on_show(map)
	_wire()
	toMenu()


func _wire() -> void:
	Bus.on("toast", func(t): toast(t))
	Bus.on("achievement", func(a):
		if inRun(): runEvents.append({"ico": a.ico, "text": a.name, "ach": a})
		toast({"ico": a.ico, "ach": a, "title": Lang.t("ДОСТИЖЕНИЕ"), "text": a.name, "rew": "+%d" % a.reward}))
	Bus.on("mission", func(m):
		if inRun():
			runEvents.append({"ico": "📋", "text": M.missionText(m)})
			return
		toast({"ico": "📋", "title": Lang.t("КОНТРАКТ ВЫПОЛНЕН"), "text": M.missionText(m), "rew": "+%d" % m.reward}))
	Bus.on("missionBonus", func(n):
		if inRun(): runEvents.append({"ico": "🏅", "text": Lang.t("Все ежедневные контракты: +%d") % n})
		else: toast({"ico": "🏅", "title": Lang.t("ВСЕ КОНТРАКТЫ ДНЯ"), "text": Lang.t("Бонус"), "rew": "+%d" % n}))
	Bus.on("skinUnlocked", func(sk):
		if inRun(): runEvents.append({"ico": "🎨", "text": Lang.t("Раскраска «") + sk.name + "»"})
		else: toast({"ico": "🎨", "title": Lang.t("НОВАЯ РАСКРАСКА"), "text": sk.name}))
	Bus.on("shipLevel", func(lvl, _r): toast({"ico": "🚀", "title": Lang.t("УРОВЕНЬ КОРАБЛЯ %d") % lvl, "text": Lang.t("+1 очко имплантов")}))
	Bus.on("waveStart", func(w): waveBanner(w))
	Bus.on("waveEvent", func(d): banner([[d.ico + " " + d.name, 2], [d.get("desc", ""), 3]], d.color, 2600))
	Bus.on("waveClear", func(w):
		if not Game.wave.boss: banner([[Lang.t("ВОЛНА %d ЗАЧИЩЕНА") % w.n, 2]], "#3dffa2", 1600))
	Bus.on("bossWarning", func(def): banner_box.boss(def))
	Bus.on("bossDefeated", func(d): banner([[Lang.t("БОСС ПОВЕРЖЕН"), 1], [d.def.name + "  +" + U.fmt(d.pts), 2]], "#ffc83d", 2600))
	Bus.on("perkOffer", func(ch): offer.showPerks(ch))
	Bus.on("moduleOffer", func(ch, kind): offer.showModules(ch, kind))
	Bus.on("eventOffer", func(o): offer.showEvent(o))
	Bus.on("mapOffer", func(d): map.open(d))
	Bus.on("reviveOffer", func(cost): revive.open(cost))
	Bus.on("revived", func(): revive.close())
	Bus.on("runEnd", func(sum): if sum: showGameOver(sum))
	Bus.on("paused", func(on):
		if on: pause_v.open()
		else: pause_v.close())
	Bus.on("tip", func(t):
		if t: tip.open(t)
		else:
			tip.close()
			_pump())
	Bus.on("playerHit", func(_l = null): hud.hit_flash())
	Bus.on("coins", func(_c): menu.refresh_wallet())


func inRun() -> bool:
	return Game.inRun() or Game.state == "pause" or Game.state == "perk" or Game.state == "tip" or Game.state == "dying" or Game.state == "revive"


## каждый кадр из сцены мира
func frame(dt: float) -> void:
	if hud.visible: hud.update_hud(dt)
	banner_box.tick(dt)


func bottomInset() -> float:
	return Hud.bottom_inset()


func topInset() -> float:
	return Hud.top_inset()


# ════════════════════════════════════════════════════════════
# ПЕРЕХОДЫ
# ════════════════════════════════════════════════════════════
func toMenu() -> void:
	Game.quit()
	hud.close()
	for v in [over, pause_v, offer, revive, map, tip, ship]: v.close()
	cur = "menu"
	menu.open()
	Main.setMusic("menu")
	_checkLogin()


## награда за вход: если сегодня ещё не забрали — окно с наградой дня (Intro, если идёт, — сначала)
func _checkLogin() -> void:
	var st := M.loginStatus()
	if not st.available or dialog_v.visible: return
	await get_tree().create_timer(0.5).timeout
	while Intro.playing: await get_tree().create_timer(0.3).timeout
	if cur != "menu" or not M.loginStatus().available: return
	var r: Dictionary = D.LOGIN[st.day]
	var claim := func():
		var got = M.claimLogin()
		if got:
			A.play("buy"); Haptic.success()
			toast({"ico": "🎁", "title": Lang.t("НАГРАДА"), "text": Lang.t("+%d кредитов%s") % [got.coins, Lang.t(" и +1 очко импланта") if got.get("sp", 0) else ""]})
			menu.refresh()
	var streak := (Lang.t("Серия: %d %s подряд!") % [st.streak, U.plural(st.streak, Lang.t("день"), Lang.t("дня"), Lang.t("дней"))]) if st.streak > 1 else Lang.t("Заходите каждый день — награда растёт!")
	dialog({"ico": "🎁", "title": Lang.t("НАГРАДА ЗА ВХОД · ДЕНЬ %d") % (st.day + 1), "text": Lang.t("+%d кредитов%s

%s") % [r.coins, Lang.t(" и +1 очко импланта") if r.get("sp", 0) else "", streak], "ok": Lang.t("ЗАБРАТЬ"), "noCancel": true, "onOk": claim})


func startRun(diffId: String, opts = null) -> void:
	# повтор забега сохраняет правила испытания, но только в тот же день
	if opts is Dictionary and opts.get("challenge") and opts.challenge.date != U.today_utc(): opts = {"challenge": M.challenge()}
	_runOpts = opts
	for v in [menu, over, pause_v, offer, revive, map, tip, ship, dialog_v]: v.close()
	cur = "game"
	runEvents = []
	Game.start(diffId, opts if opts is Dictionary else {})
	hud.open()
	Main.setMusic("game")
	if not M.s.seenIntro:
		M.s.seenIntro = true
		M.soon()
	# Godot: вместо двух баннеров первого забега — пошаговое обучение (scripts/ui/tutor_view.gd)
	tutor.start()


func again() -> void:
	startRun(M.s.settings.diff, _runOpts)


## Esc / системная «Назад»
func back() -> void:
	if dialog_v.visible:
		dialog_v.close()
		return
	if tip.visible:
		Game.closeTip()
		return
	if ship.visible:
		ship.close()
		return
	if pause_v.visible:
		Game.resume()
		return
	if over.visible:
		toMenu()
		return
	menu.back()


func showGameOver(sum: Dictionary) -> void:
	hud.close()
	for v in [pause_v, offer, revive, map, ship]: v.close()
	cur = "over"
	Main.setMusic("menu")
	get_tree().create_timer(0.35).timeout.connect(func(): over.open(sum))


func dialog(o: Dictionary) -> void:
	dialog_v.open(o)


# ════════════════════════════════════════════════════════════
# БАННЕРЫ И УВЕДОМЛЕНИЯ
# ════════════════════════════════════════════════════════════
## lines: [[текст, уровень 1|2|3], ...] — 1 крупно, 2 средне, 3 мелко
func banner(lines: Array, color := "#ffffff", dur := 2400) -> void:
	banner_box.show_lines(lines, color, dur / 1000.0)


func waveBanner(w: Dictionary) -> void:
	if w.boss: return
	if w.get("newSector", false) or w.n == 1:
		banner([[Lang.t("СЕКТОР %d") % (int(w.get("sector", 0)) + 1), 2], [w.get("sectorName", ""), 1], [Lang.t("Волна %d") % w.n, 3]], "#3de0ff", 2600)
	elif w.get("danger", false):
		banner([[Lang.t("☠️ ОПАСНЫЙ ПУТЬ · КРЕДИТЫ ×%s") % str(D.DANGER.coins), 2], [Lang.t("ВОЛНА %d") % w.n, 1]], "#ff5c7a", 2200)
	else:
		banner([[Lang.t("ВОЛНА %d") % w.n, 1]], "#ffffff", 1800)


## уведомления идут очередью — не больше двух на экране одновременно
func toast(t: Dictionary) -> void:
	_toastQ.append(t)
	if _toastQ.size() > 8: _toastQ = _toastQ.slice(_toastQ.size() - 8)
	_pump()


func _pump() -> void:
	# 4.3.2: пока открыто окно-подсказка, плашки ждут в очереди — иначе они закрывают его верх
	if tip.visible: return
	toasts.offset_top = Hud.safe_top() + (Hud.top_inset() - Hud.safe_top() + 6 if hud.visible else 12)
	while not _toastQ.is_empty() and toasts.get_child_count() < 2:
		var t: Dictionary = _toastQ.pop_front()
		var el := Views.toast_el(t)
		toasts.add_child(el)
		el.modulate.a = 0.0
		var tw := el.create_tween()
		tw.tween_property(el, "modulate:a", 1.0, 0.2)
		tw.tween_interval(t.get("dur", 2400) / 1000.0)
		tw.tween_property(el, "modulate:a", 0.0, 0.3)
		tw.tween_callback(func():
			el.queue_free()
			toasts.remove_child(el)
			_pump())


# ════════════════════════════════════════════════════════════
# БОТ-ТЕСТИРОВЩИК (world.gd --autoplay): первое из предложенного
# ════════════════════════════════════════════════════════════
func botPick() -> void:
	if map.visible:
		map.bot_pick()
	elif offer.visible:
		offer.bot_pick()
