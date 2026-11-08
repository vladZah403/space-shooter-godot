extends Node
## Живые фоны секторов (запуск с окном): снимок фона каждого из 13 секторов, поле без врагов.
##   Godot_console.exe --path . --resolution 390x844 res://tools/check/bg_shots.tscn -- --shots=ПАПКА
var shots := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	M.s.settings.intro = false
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	for i in 20: await get_tree().process_frame
	Ui.menu.content.visible = false
	if Ui.dialog_v: Ui.dialog_v.visible = false
	for si in D.SECTORS.size():
		Bg.setSector(si, true)
		for i in 40: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(shots)
		get_viewport().get_texture().get_image().save_png(shots.path_join("bg_%02d.png" % si))
	get_tree().quit()
