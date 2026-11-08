extends Node
## Шапка меню и окно «Что нового» (запуск с окном): профиль, который уже играл до обновления.
##   Godot_console.exe --path . --resolution 390x844 res://tools/check/notes_shots.tscn -- --shots=ПАПКА [--lang=en]
func _ready() -> void:
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	M.s.settings.intro = false
	M.s.stats.games = maxi(int(M.s.stats.games), 3)
	M.s.notes = [{"type": "g44"}]
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	for i in 90: await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(shots)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join("notes.png"))
	print("окно: ", Ui.dialog_v.visible, " «", Ui.dialog_v.title.text, "»")
	Ui.dialog_v.ok.pressed.emit()
	for i in 60: await get_tree().process_frame
	if Ui.dialog_v.visible: Ui.dialog_v.close()
	for i in 20: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join("menu.png"))
	get_tree().quit()
