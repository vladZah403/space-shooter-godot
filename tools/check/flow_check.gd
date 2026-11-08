extends Node
## Сценарии в бою (без окна): пауза и все её кнопки, выход в меню через подтверждение, гибель → воскрешение →
## гибель → итоги → открыть все контейнеры → «Ещё раз» → гибель → «Меню». Печатает шаги; ошибки скриптов — в выводе.
##   Godot_console.exe --headless --path . res://tools/check/flow_check.tscn [-- --lang=en]
func _ready() -> void:
	M.s.settings.intro = false
	M.s.seenIntro = true
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await _f(30)
	if Ui.dialog_v.visible: Ui.dialog_v.close()
	M.s.coins = 100000
	Ui.startRun("normal")
	await _f(60)
	if Game.state == "perk": Ui.botPick()
	await _f(30)
	Game.pause()
	await _f(5)
	_step("пауза", Ui.pause_v.visible)
	for b in _buttons(Ui.pause_v):
		if b.text.contains("ВЫЙТИ") or b.text.contains("ПРОДОЛЖ"): continue
		b.pressed.emit(); await _f(5)
		if Ui.ship.visible: Ui.ship.close(); await _f(2)
		b.pressed.emit(); await _f(3)   # переключатели — обратно
	_press(Ui.pause_v, "ВЫЙТИ В МЕНЮ"); await _f(5)
	_step("окно выхода", Ui.dialog_v.visible)
	Ui.dialog_v.ok.pressed.emit(); await _f(20)
	_step("в меню", Game.state, Ui.menu.visible)
	# гибель и воскрешение
	Ui.startRun("normal")
	await _f(40)
	if Game.state == "perk": Ui.botPick()
	await _f(10)
	await _die()
	_step("воскрешение", Game.state, Ui.revive.visible)
	_press(Ui.revive, "ВОСКРЕС"); await _f(20)
	_step("после воскрешения", Game.state)
	await _die()
	_press(Ui.revive, "НЕТ"); await _f(200)
	_step("итоги", Game.state, Ui.over.visible)
	M.s.chests.append_array(["bronze", "silver", "gold"])
	Ui.over._render_chests()
	_step("контейнеров до", M.s.chests.size(), _buttons(Ui.over).map(func(b): return b.text))
	for i in 4:
		if not _press(Ui.over, "КОНТЕЙНЕР"): break
		await _f(40)
		# анимация открытия: касание — к карточке, ещё касание — закрыть
		var tap := InputEventMouseButton.new()
		tap.pressed = true
		tap.button_index = MOUSE_BUTTON_LEFT
		if Ui.chest_v.visible: Ui.chest_v._gui_input(tap)
		await _f(5)
		if Ui.chest_v.visible: Ui.chest_v._gui_input(tap)
		await _f(5)
	_step("контейнеры открыты, осталось", M.s.chests.size())
	_press(Ui.over, "ЕЩЁ РАЗ"); await _f(40)
	_step("ещё раз", Game.state)
	if Game.state == "perk": Ui.botPick()
	await _f(10)
	await _die()
	if Ui.revive.visible: _press(Ui.revive, "НЕТ")
	await _f(200)
	_step("перед меню", Game.state, Ui._fader.visible)
	_press(Ui.over, "МЕНЮ"); await _f(40)
	_step("меню", Game.state, Ui.menu.visible)
	print("FLOW DONE")
	get_tree().quit()


func _die() -> void:
	for i in 80:
		if Game.state == "perk": Ui.botPick()
		var p = Game.player
		if p == null or not p.alive or Game.state == "revive" or Game.state == "over": break
		p.inv = 0.0
		Game.hitPlayer(p.x, p.y, "тест")
		await _f(4)
	for i in 400:
		if Game.state != "dying": break
		await _f(1)
	await _f(30)


func _f(n: int) -> void:
	for i in n: await get_tree().process_frame


func _buttons(root: Node) -> Array:
	return root.find_children("*", "Button", true, false).filter(func(b): return b.is_visible_in_tree() and not b.disabled)


func _press(root: Node, part: String) -> bool:
	for b in _buttons(root):
		if Lang.t(b.text).contains(part) or b.text.contains(part):
			b.pressed.emit()
			return true
	print("  нет кнопки «", part, "»")
	return false


func _step(what: String, a = null, b = null) -> void:
	print("[flow] ", what, " ", a if a != null else "", " ", b if b != null else "")
