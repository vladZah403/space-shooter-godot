extends Node
## Обучение первого забега (запуск с окном): чистый профиль новичка, бот летает; снимок на каждом шаге.
##   Godot_console.exe --path . --resolution 390x844 res://tools/check/tutor_shots.tscn -- --shots=ПАПКА [--lang=en]
func _ready() -> void:
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	M.s.settings.intro = false
	M.s.erase("tutor")
	M.s.stats.games = 0
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	for i in 30: await get_tree().process_frame
	if Ui.dialog_v.visible: Ui.dialog_v.close()
	Ui.startRun("normal")
	var seen := {}
	var t := 0.0
	DirAccess.make_dir_recursive_absolute(shots)
	while t < 70.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		var p = Game.player
		if p:
			p.inv = maxf(p.inv, 2.0)
			if Game.state == "play": p.x = G.FW / 2 + sin(t * 0.9) * G.FW * 0.3
		if Game.state == "perk" and Ui.tutor.step == "perk" and Ui.tutor.t > 1.2: Ui.botPick()
		elif Game.state == "perk" and Ui.tutor.step != "perk" and Ui.tutor.step != "xp": Ui.botPick()
		if Game.state == "tip": Game.closeTip()
		var st: String = Ui.tutor.step
		if int(t * 60) % 300 == 0: print("[tutor] t=", snappedf(t, 0.1), " state=", Game.state, " step=", st, " level=", Game.run.get("level"), " xp=", snappedf(Game.run.get("xp", 0.0), 0.1), " pickups xp=", Game.pickups.filter(func(it): return it.kind == "xp").size())
		if st != "" and not seen.has(st) and Ui.tutor.t > 0.8:
			seen[st] = true
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots.path_join("tut_%d_%s.png" % [seen.size(), st]))
			print("[tutor] шаг ", st, " на ", snappedf(t, 0.1), " с")
		if st == "" and seen.size() > 0 and not seen.has("done"):
			seen["done"] = true
			print("[tutor] пройдено: ", M.s.get("tutor"), " на ", snappedf(t, 0.1), " с")
			for i in 20: await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots.path_join("tut_done.png"))
			break
	get_tree().quit()
