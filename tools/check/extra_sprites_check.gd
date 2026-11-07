extends Node
## Спрайты из tools/extra_sprites.py: все кадры медалей и обломков есть в G и не пустые; с окном и
## «-- --shot=ФАЙЛ.png» — снимок подсказки «Космический мусор» (живая сцена с обломками) и окна «Награды».
##   Godot_console.exe --path . --resolution 390x844 res://tools/check/extra_sprites_check.tscn [-- --shot=ФАЙЛ.png]

func _ready() -> void:
	M.s.settings.intro = false
	var bad := 0
	for n in ["ach_kills", "ach_boss", "ach_combo", "ach_score", "ach_wave", "ach_hard", "ach_survive", "ach_aim",
			"ach_evo", "ach_arsenal", "ach_fleet", "ach_pilot", "db_1", "db_2", "db_3", "db_4", "db_5", "db_6"]:
		var f: Array = G.frame(n)
		if f.is_empty() or G.icon(n) == null: bad += 1; print("нет кадра ", n)
	for a in D.ACHIEVEMENTS:
		if not M.ACH_MEDAL.has(a.id): bad += 1; print("без медали: ", a.id)
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot = a.substr(7)
	if shot != "":
		var world: Node = load("res://scenes/world.tscn").instantiate()
		get_tree().root.add_child.call_deferred(world)
		for i in 30: await get_tree().process_frame
		Ui.dialog_v.visible = false
		Ui.tip.open({"key": "debris", "kind": "СОБЫТИЕ", "title": "Космический мусор", "how": "-", "use": "-"})
		for i in 150: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot)
		Ui.tip.close()
		M.s.achievements = {"first_kill": 1, "boss1": 1, "combo5": 1, "score1000": 1, "kill5000": 1}
		Ui.menu.open_screen("achievements")
		for i in 20: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(shot.replace(".png", "_ach.png"))
	print("ИТОГ: ", "ок" if bad == 0 else "проблем %d" % bad)
	get_tree().quit(0 if bad == 0 else 1)
