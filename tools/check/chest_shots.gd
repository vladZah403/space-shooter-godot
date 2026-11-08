extends Node
## Анимация открытия контейнера (запуск с окном): кадры падения, тряски, открытия, взлёта ксенотеха и карточка.
##   Godot_console.exe --path . --resolution 390x844 res://tools/check/chest_shots.tscn -- --shots=ПАПКА
func _ready() -> void:
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	M.s.settings.intro = false
	M.s.tutor = true
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	for i in 30: await get_tree().process_frame
	if Ui.dialog_v.visible: Ui.dialog_v.close()
	DirAccess.make_dir_recursive_absolute(shots)
	for tier in ["gold"]:
		M.s.chests = [tier]
		var r = M.openChest()
		Ui.chest_v.play(tier, r)
		var t := 0.0
		for at in [0.2, 0.8, 1.25, 1.5, 2.6]:
			while Ui.chest_v.t < at: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots.path_join("chest_%s_%.1f.png" % [tier, at]))
	print("CHEST DONE")
	get_tree().quit()
