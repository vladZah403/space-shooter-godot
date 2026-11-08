extends Node
## «Обезьяний» тест меню (без окна): в каждом разделе случайно жмёт видимые кнопки — покупки, прокачка, импланты,
## ксенотех, контейнеры, вкладки, окна подтверждения — и печатает, что нажимал. Ошибки скриптов видны в выводе.
##   Godot_console.exe --headless --path . res://tools/check/ui_monkey.tscn [-- --presses=N --seed=S --lang=en]
## Не жмёт: смену языка (перезапуск), «Поделиться» (файл в «Изображения»), заставку, сброс прогресса.
const SKIP := ["Русский", "English", "Авто", "Auto", "ПОДЕЛИТЬСЯ", "SHARE", "СМОТРЕТЬ", "WATCH", "СБРОС", "RESET"]

var presses := 400
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 7
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--presses="): presses = int(a.substr(10))
		elif a.begins_with("--seed="): rng.seed = int(a.substr(7))
	M.s.settings.intro = false
	M.s.seenIntro = true
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	for i in 30: await get_tree().process_frame
	if "--game" in OS.get_cmdline_user_args():
		await _game_phase()
		return
	var ids := ["hangar", "arsenal", "skills", "missions", "relics", "achievements", "codex", "leaders", "settings"]
	var log := {}
	for n in presses:
		if n % 40 == 0:
			_rich()
			var id: String = ids[(n / 40) % ids.size()]
			if Ui.dialog_v.visible: Ui.dialog_v.close()
			Ui.menu.open()
			Ui.menu.open_screen(id)
			for i in 2: await get_tree().process_frame
		var root: Control = Ui.dialog_v if Ui.dialog_v.visible else Ui.menu
		var btns: Array = []
		_collect(root, btns)
		if btns.is_empty():
			Ui.menu.open()
			await get_tree().process_frame
			continue
		var b: Button = btns[rng.randi() % btns.size()]
		var name := _name(b)
		log[name] = log.get(name, 0) + 1
		b.pressed.emit()
		for i in 2: await get_tree().process_frame
		if Game.state != "idle" and Game.state != "over":
			# кнопка запустила забег — возвращаемся в меню
			Ui.toMenu()
			for i in 2: await get_tree().process_frame
	print("нажатий: ", presses, ", разных кнопок: ", log.size())
	var keys := log.keys()
	keys.sort()
	print(", ".join(keys.map(func(k): return "%s×%d" % [k, log[k]])))
	print("UI MONKEY DONE")
	get_tree().quit()


## «-- --game»: то же в бою — пауза и её кнопки, выбор улучшений, карта, лавка, контейнеры на итогах, воскрешение
func _game_phase() -> void:
	var log := {}
	var ui_root: Node = Ui.hud.get_parent()
	for n in presses:
		_rich()
		if Game.state == "idle":
			Ui.startRun(["normal", "hard", "zen"][n % 3], {"mode": ["normal", "bossrush", "survival"][(n / 3) % 3]})
		var p = Game.player
		if p and n % 50 < 40: p.inv = maxf(p.inv, 3.0)
		for i in rng.randi_range(5, 90): await get_tree().process_frame
		if Game.state == "cutscene": Game.skipScene()
		# окна, где нужен выбор (улучшения, карта, лавка), и схема корабля не должны запирать бота навсегда
		if Ui.ship.visible and rng.randf() < 0.6: Ui.ship.close()
		if (Game.state == "perk" or Ui.map.visible) and rng.randf() < 0.4:
			Ui.botPick()
			continue
		if Game.state == "tip" and rng.randf() < 0.5: Game.closeTip()
		var btns: Array = []
		_collect(ui_root, btns)
		if btns.is_empty(): continue
		var b: Button = btns[rng.randi() % btns.size()]
		var name := _name(b)
		log[name] = log.get(name, 0) + 1
		b.pressed.emit()
	print("в бою: нажатий ", presses, ", разных кнопок: ", log.size())
	var keys := log.keys()
	keys.sort()
	print(", ".join(keys.map(func(k): return "%s×%d" % [k, log[k]])))
	print("UI MONKEY DONE")
	get_tree().quit()


func _rich() -> void:
	M.s.coins = 5000000
	M.s.shipLvl = maxi(M.s.shipLvl, 40)
	M.s.spBonus = maxi(int(M.s.get("spBonus", 0)), 40)
	if M.s.chests.size() < 3: M.s.chests.append_array(["bronze", "silver", "gold"])


func _collect(n: Node, out: Array) -> void:
	if n is CanvasItem and not n.is_visible_in_tree(): return
	if n is Button and not n.disabled:
		var t := _name(n)
		var skip := false
		for s in SKIP:
			if s in t: skip = true
		if not skip: out.append(n)
	for c in n.get_children(): _collect(c, out)


func _name(b: Button) -> String:
	if b.text != "": return b.text
	for c in b.find_children("*", "Label", true, false):
		if c.text != "": return c.text
	return b.name
