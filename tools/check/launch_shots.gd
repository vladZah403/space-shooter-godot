extends Node
## Взлёт из меню и выход из гиперпрыжка (запуск с окном): снимки по ходу.
##   Godot_console.exe --path . --resolution 390x844 res://tools/check/launch_shots.tscn -- --shots=ПАПКА
func _ready() -> void:
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	M.s.settings.intro = false
	M.s.tutor = true
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	for i in 40: await get_tree().process_frame
	if Ui.dialog_v.visible: Ui.dialog_v.close()
	for i in 20: await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(shots)
	Ui.menu.show_diff()
	for i in 20: await get_tree().process_frame
	Ui.menu.diff._go()
	var t0 := Time.get_ticks_msec()
	var marks := [0.15, 0.35, 0.5, 0.75, 1.05, 1.4, 2.2]
	var mi := 0
	while mi < marks.size():
		await get_tree().process_frame
		if (Time.get_ticks_msec() - t0) / 1000.0 >= marks[mi]:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots.path_join("launch_%d.png" % mi))
			mi += 1
	print("LAUNCH DONE state=", Game.state)
	get_tree().quit()
