extends Node
## Подбитые враги и взрывы по материалу (запуск с окном): металл, живое, кристалл.
##   Godot_console.exe --path . --resolution 390x844 res://tools/check/vfx_shots.tscn -- --shots=ПАПКА
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
	Ui.startRun("normal")
	for i in 240:
		await get_tree().process_frame
		if Game.state == "perk": Ui.botPick()
		if Game.state == "tip": Game.closeTip()
		if i > 60 and Game.state == "play": break
	for e in Game.enemies: e.alive = false
	Game.enemies.clear()
	var S := G.S
	var es: Array = []
	for it in [["heavy", 0.25], ["bug", 0.5], ["crystal", 0.75], ["heavyfighter", 0.5]]:
		var e: En = E.spawn(it[0], {"x": G.FW * it[1], "y": G.H * (0.3 if it[0] != "heavyfighter" else 0.48)})
		if e:
			e.hp = e.maxHp * 0.2
			e.vy = 0.0; e.vx = 0.0
			es.append(e)
	DirAccess.make_dir_recursive_absolute(shots)
	for i in 70:
		Game.player.inv = 3.0
		if Game.state == "perk": Ui.botPick()
		for e: En in es:
			if e.alive: e.y = G.H * (0.3 if e.type != "heavyfighter" else 0.48)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join("damaged.png"))
	for e: En in es: E.kill(e, "test")
	for i in 9: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join("explode.png"))
	print("VFX DONE ", es.size())
	get_tree().quit()
