extends Node
## Карта галактики (запуск с окном): открытие, выбор узла, полёт с «нырком» — снимки по ходу.
##   Godot_console.exe --path . --resolution 390x844 res://tools/check/map_shots.tscn -- --shots=ПАПКА
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
	for i in 90:
		await get_tree().process_frame
		if Game.state == "perk": Ui.botPick()
	DirAccess.make_dir_recursive_absolute(shots)
	Ui.map.open({"map": RunMap.generate(0), "step": 0, "choices": [0, 1, 2], "n": 2})
	await _snap(shots, "map_0_open", 0.15)
	await _snap(shots, "map_1_ready", 0.9)
	for n in Ui.map.nodes:
		if n.can:
			Ui.map._select(n)
			break
	await _snap(shots, "map_2_sel", 0.4)
	Ui.map.fly_go()
	await _snap(shots, "map_3_fly", 0.5)
	await _snap(shots, "map_4_dive", 0.35)
	await _snap(shots, "map_5_flash", 0.12)
	print("MAP DONE")
	get_tree().quit()


func _snap(dir: String, name: String, wait: float) -> void:
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) / 1000.0 < wait: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
