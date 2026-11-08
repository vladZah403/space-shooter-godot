extends Node
## Корабль в ангаре (запуск с окном): витрина при разных углах поворота.
##   Godot_console.exe --path . --resolution 390x844 res://tools/check/hangar_shots.tscn -- --shots=ПАПКА
func _ready() -> void:
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	M.s.settings.intro = false
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	for i in 30: await get_tree().process_frame
	if Ui.dialog_v.visible: Ui.dialog_v.close()
	Ui.menu.open_screen("hangar")
	DirAccess.make_dir_recursive_absolute(shots)
	var ms = Ui.menu.screens
	for a in [0.0, 0.8, 1.45, 2.4, 3.14]:
		ms._dragging = true
		ms._yaw = a
		for i in 6: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots.path_join("hangar_%.2f.png" % a))
	print("HANGAR DONE")
	get_tree().quit()
