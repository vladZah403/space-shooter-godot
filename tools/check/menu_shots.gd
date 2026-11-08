extends Node
## Снимки экранов меню без всплывающих окон (запуск с окном): главное меню, арсенал (купленное оружие
## и некупленное, верх и низ прокрутки), ангар, навыки, ксенотех.
##   Godot_console.exe --path . --resolution 390x844 res://tools/check/menu_shots.tscn -- --shots=ПАПКА
var shots := ""


func snap(name: String) -> void:
	if shots == "": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots)
	get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))


func frames(n: int) -> void:
	for i in n:
		if Ui.dialog_v and Ui.dialog_v.visible: Ui.dialog_v.visible = false
		await get_tree().process_frame


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	M.s.settings.intro = false
	M.s.coins = 12000
	M.s.weapons.owned = ["laser", "shotgun", "rocket"]
	M.s.weapons.loadout = ["laser", "rocket"]
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await frames(40)
	Ui.menu.refresh()
	await frames(5)
	await snap("menu")
	var ms = Ui.menu.screens
	Ui.menu.open_screen("arsenal")
	ms.ars = "laser"; ms.render()
	await frames(10)
	await snap("arsenal_top")
	ms.scroll.scroll_vertical = 100000
	await frames(5)
	await snap("arsenal_bottom")
	ms.ars = "plasma"; ms.render()
	ms.scroll.scroll_vertical = 0
	await frames(10)
	await snap("arsenal_locked")
	for id in ["hangar", "skills", "relics"]:
		Ui.menu.open_screen(id)
		await frames(10)
		await snap("m_" + id)
	get_tree().quit()
