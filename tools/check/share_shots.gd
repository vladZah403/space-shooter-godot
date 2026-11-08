extends Node
## Карточка «поделиться» (запуск с окном): короткий забег ботом, конец игры, картинка карточки сохраняется в ФАЙЛ.
##   Godot_console.exe --path . --resolution 390x844 res://tools/check/share_shots.tscn -- --autoplay --shot=ФАЙЛ.png
func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): out = a.substr(7)
	M.s.settings.intro = false
	M.s.seenIntro = true
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	for i in 600: await get_tree().process_frame
	Ui.runEvents.append({"ico": "🔫", "text": "Первая кровь", "ach": D.ACHIEVEMENTS[0]})
	Ui.runEvents.append({"ico": "👾", "text": "Убийца боссов", "ach": D.ACHIEVEMENTS[4]})
	var sum := {"score": 48250, "wave": 12, "sector": 2, "kills": 214, "bosses": 2, "maxCombo": 37, "diff": "normal", "isRecord": true}
	var img: Image = await ShareCard.render(world, sum)
	print("карточка ", img.get_size())
	if out != "": img.save_png(out)
	# экран итогов с кнопкой «Поделиться»
	var full := sum.duplicate()
	full.merge({"level": 9, "accuracy": 71, "time": 412, "coins": 820, "xp": 640, "mode": "normal", "cause": ""})
	Ui.over.open(full)
	for i in 150: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	if out != "": get_viewport().get_texture().get_image().save_png(out.get_basename() + "_over.png")
	get_tree().quit()
