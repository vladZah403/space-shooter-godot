extends Node
## Туманность через буфер и напрямую — один и тот же материал (запуск с окном): -- --shots=ПАПКА
func _ready() -> void:
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	M.s.settings.intro = false
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	for i in 20: await get_tree().process_frame
	Ui.menu.content.visible = false
	if Ui.dialog_v: Ui.dialog_v.visible = false
	DirAccess.make_dir_recursive_absolute(shots)
	for si in [0, 3, 9]:
		Bg.setSector(si, true)
		for mode in [false, true]:
			Bg.neb_direct = mode
			for i in 10: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots.path_join("n%02d_%s.png" % [si, "direct" if mode else "buf"]))
	get_tree().quit()
