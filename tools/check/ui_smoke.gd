extends Node
## Дымовой тест интерфейса в настоящем проекте (все модули на месте): мир, меню, каждый экран и вкладка,
## выбор сложности, пауза, итоги, карта, окно выбора. Запуск:
##   Godot_console.exe --headless --path . res://tools/check/ui_smoke.tscn

var shots := ""


## «-- --shots=ПАПКА» (запуск с окном): снимок экрана после каждого шага
func snap(name: String) -> void:
	if shots == "": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots)
	get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	M.s.settings.intro = false   # заставка закрыла бы снимки экранов
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	for i in 30: await get_tree().process_frame
	await snap("menu")
	M.s.coins = 100000
	M.s.shipLvl = 30
	var ms = Ui.menu.screens
	for id in ["hangar", "arsenal", "skills", "missions", "relics", "achievements", "codex", "leaders", "settings"]:
		Ui.menu.open_screen(id)
		for i in 3: await get_tree().process_frame
		await snap("menu_" + id)
		print("экран ", id, ": элементов ", ms.body.get_child_count())
	for t in ["models", "drones", "skins", "trails", "pilots"]:
		ms.open("hangar"); ms.tab = t; ms.render()
		await get_tree().process_frame
		print("ангар/", t, ": ", ms.body.get_child_count())
	for w in D.WEAPON_ORDER:
		ms.open("arsenal"); ms.ars = w; ms.render()
		await get_tree().process_frame
	print("арсенал: все виды оружия")
	for b in D.SKILL_BRANCHES:
		ms.open("skills"); ms.tab = b.id; ms.render()
		await get_tree().process_frame
	print("навыки: все ветки")
	ms.open("codex"); ms.tab = "sectors"; ms.render()
	await get_tree().process_frame
	ms.close()
	Ui.menu.show_diff()
	await get_tree().process_frame
	await snap("diff")
	print("сложность открыта: ", Ui.menu.diff.visible, ", окно: ", Ui.dialog_v.visible, " прозрачность ", Ui.dialog_v.modulate.a)
	Ui.menu.diff._go()
	for i in 120: await get_tree().process_frame
	print("забег: ", Game.state, " волна ", Game.wave.n if Game.wave else "-")
	Game.pause()
	await get_tree().process_frame
	print("пауза: ", Ui.pause_v.visible)
	Game.resume()
	Ui.offer.showPerks(Game.perkChoices())
	await get_tree().process_frame
	for i in 20: await get_tree().process_frame
	await snap("offer")
	print("улучшения: карточек ", Ui.offer.cards.get_child_count())
	Ui.offer.close()
	# лавка торговца с живым портретом и схема корабля
	Ui.offer.showEvent(Game.merchantOffer())
	for i in 60: await get_tree().process_frame
	await snap("merchant")
	print("лавка: карточек ", Ui.offer.cards.get_child_count(), ", реплика «", Ui.offer.say.text, "»")
	Ui.offer.close()
	Game.run.mods["power"] = 2
	Ui.ship.open(["cooling", "gyro"])
	for i in 20: await get_tree().process_frame
	await snap("ship")
	print("схема корабля: отсек ", Ui.ship.sel)
	Ui.ship.close()
	Ui.map.open({"map": RunMap.generate(0), "step": 0, "choices": [0, 1, 2], "n": 2})
	for i in 10: await get_tree().process_frame
	for i in 30: await get_tree().process_frame
	await snap("map")
	print("карта: узлов ", Ui.map.nodes.size())
	Ui.map.close()
	Game.gameOver()
	for i in 60: await get_tree().process_frame
	for i in 90: await get_tree().process_frame
	await snap("over")
	print("итоги: ", Ui.over.visible)
	# окна-подсказки с живыми сценами: все события, аномалии и эволюции
	for key in Demo.SCENES + D.EVOLUTIONS.map(func(ev): return "evo_" + ev.weapon):
		Ui.tip.open({"key": key, "kind": "ТЕСТ", "title": key, "how": "-", "use": "-"})
		for i in 40: await get_tree().process_frame
	await snap("tip")
	Ui.tip.close()
	print("подсказки с демо: все сцены")
	print("UI SMOKE DONE")
	get_tree().quit()
