extends Node
## Проверка вёрстки по ширине: каждый экран меню, каждая вкладка, окна игры — ничего не должно быть шире экрана
## телефона (390 логических пикселей; при stretch=expand ширина никогда не меньше). Дважды: новое сохранение
## (всё закрыто — длинные подписи «🔒 …») и богатое (всё открыто). Печатает самые глубокие узлы,
## чья минимальная ширина не влезает. Запуск:
##   Godot_console.exe --headless --path . res://tools/check/layout_check.tscn

var problems := 0


func _ready() -> void:
	M.s.settings.intro = false
	# узкий телефон: 390×844 логических (без окна размер берётся не из настроек проекта)
	get_window().size = Vector2i(390, 844)
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	for i in 30: await get_tree().process_frame
	print("экран ", get_viewport().get_visible_rect().size)
	for profile in ["новое сохранение", "всё открыто"]:
		var keep: Dictionary = M.s.settings.duplicate(true)
		M.s = M.defaults()
		M.s.settings = keep
		if profile == "всё открыто":
			M.s.coins = 100000
			M.s.shipLvl = 30
			M.s.ship.models = Array(D.SHIP_ORDER)
			M.s.ship.skins = D.SKINS.map(func(s): return s.id)
			M.s.ship.trails = D.TRAILS.map(func(t): return t.id)
		print("── ", profile)
		await _menu()
	await _game()
	print("ИТОГ: проблем ", problems)
	get_tree().quit(1 if problems > 0 else 0)


func _menu() -> void:
	var ms = Ui.menu.screens
	await _check("главное меню", Ui.root if "root" in Ui else get_tree().root)
	var cases := []
	for t in ["models", "drones", "skins", "trails", "pilots"]: cases.append(["hangar", t, ""])
	for w in D.WEAPON_ORDER: cases.append(["arsenal", "", w])
	for b in D.SKILL_BRANCHES: cases.append(["skills", b.id, ""])
	for id in ["missions", "relics", "achievements", "settings"]: cases.append([id, "", ""])
	for t in ["foes", "sectors"]: cases.append(["codex", t, ""])
	cases.append(["leaders", "", ""])
	for c in cases:
		ms.open(c[0])
		if c[1] != "": ms.tab = c[1]
		if c[2] != "": ms.ars = c[2]
		ms.render()
		await _check("%s/%s%s" % [c[0], c[1], c[2]], ms)
	ms.close()


## окна во время игры: сложность, забег, пауза, выбор улучшений, лавка, схема корабля, карта, итоги, подсказка
func _game() -> void:
	print("── окна игры")
	Ui.menu.show_diff()
	await _check("выбор сложности", Ui.root)
	Ui.menu.diff._go()
	for i in 120: await get_tree().process_frame
	await _check("забег (HUD)", Ui.root)
	Game.pause()
	await _check("пауза", Ui.root)
	Game.resume()
	Ui.offer.showPerks(Game.perkChoices())
	for i in 20: await get_tree().process_frame
	await _check("выбор улучшений", Ui.root)
	Ui.offer.close()
	Ui.offer.showEvent(Game.merchantOffer())
	for i in 20: await get_tree().process_frame
	await _check("лавка", Ui.root)
	Ui.offer.close()
	Game.run.mods["power"] = 2
	Ui.ship.open(["cooling", "gyro"])
	for i in 20: await get_tree().process_frame
	await _check("схема корабля", Ui.root)
	Ui.ship.close()
	Ui.map.open({"map": RunMap.generate(0), "step": 0, "choices": [0, 1, 2], "n": 2})
	for i in 30: await get_tree().process_frame
	await _check("карта", Ui.root)
	Ui.map.close()
	Game.gameOver()
	for i in 150: await get_tree().process_frame
	await _check("итоги", Ui.root)
	Ui.tip.open({"key": Demo.SCENES[0], "kind": "ТЕСТ", "title": "Длинный заголовок подсказки для проверки", "how": "-", "use": "-"})
	for i in 20: await get_tree().process_frame
	await _check("подсказка", Ui.root)
	Ui.tip.close()


## проверка: дерево узла root не должно требовать больше ширины, чем есть у экрана
func _check(name: String, root: Node) -> void:
	for i in 2: await get_tree().process_frame
	var vw := get_viewport().get_visible_rect().size.x
	var bad := []
	_walk(root, vw, bad)
	if root is Control and "body" in root:
		var chain := []
		var n: Node = root.body
		while n != null and n is Control:
			chain.append("%s %d/%d" % [n.get_class(), (n as Control).size.x, (n as Control).get_combined_minimum_size().x])
			if n == root: break
			n = n.get_parent()
		if (root as Control).size.x > vw + 0.5: bad.append("экран шире: " + " ← ".join(chain))
	if OS.get_cmdline_user_args().has("--debug") and name.begins_with("hangar"):
		for c in root.body.get_children():
			print("    ", name, " ", c.get_class(), " size ", c.size, " min ", c.get_combined_minimum_size(), " vis ", c.visible)
			if c is GridContainer and c.get_child_count() > 0:
				var card: Control = c.get_child(0)
				print("      card min ", card.get_combined_minimum_size(), " size ", card.size)
				for l in card.get_child(0).get_children(): print("        ", l.get_class(), " ", l.get_combined_minimum_size(), " «", l.get("text"), "»")
	if bad.is_empty(): return
	problems += 1
	print("  ✗ ", name, ":")
	for b in bad.slice(0, 6): print("      ", b)


## самые глубокие видимые узлы, чья минимальная ширина больше ширины экрана без полей меню (по 14 с каждой стороны)
func _walk(n: Node, vw: float, bad: Array) -> bool:
	var found := false
	for c in n.get_children():
		if c is CanvasItem and not (c as CanvasItem).visible: continue
		if c is Control and (c as Control).top_level: continue
		if _walk(c, vw, bad): found = true
	if found or not (n is Control): return found
	var ctl := n as Control
	var w := ctl.get_combined_minimum_size().x
	var x0 := ctl.get_global_rect().position.x
	if w > vw - 2 * clampf(x0, 0, 14) + 0.5:
		var txt := ""
		if "text" in ctl: txt = str(ctl.text).substr(0, 40)
		var extra := ""
		if ctl is Container:
			var parts := []
			for c in ctl.get_children():
				if c is Control and (c as Control).visible: parts.append(int((c as Control).get_combined_minimum_size().x))
			extra = " дети " + str(parts)
		bad.append("%s мин. ширина %d «%s»%s ← %s" % [ctl.get_class(), w, txt, extra, ctl.get_parent().get_class()])
		return true
	return false
