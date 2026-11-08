extends Node
## Стая жуков (запуск с окном): выводок из 10 жуков над кораблём бота — снимки через 1, 2, 3 с;
## печатает, сколько жуков сбито и сколько ушло вниз (уворот от пуль), и как широко стая разошлась клещами.
##   Godot_console.exe --path . --fixed-fps 60 --resolution 390x844 res://tools/check/swarm_shots.tscn -- --autoplay --shots=ПАПКА
var shots := ""


func snap(name: String) -> void:
	if shots == "": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots)
	get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))


func frames(n: int) -> void:
	for i in n: await get_tree().process_frame


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	M.s.settings.intro = false
	M.s.seenIntro = true
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await frames(240)
	for e in Game.enemies: e.alive = false
	var before := E.burns.size()
	E.brood(G.FW / 2, G.H * 0.05, 10, false, 22)
	var bugs: Array = Game.enemies.filter(func(e): return e.alive and e.type == "bug")
	for s in 3:
		await frames(60)
		var xs: Array = bugs.filter(func(e): return e.alive).map(func(e): return e.x)
		var spread: float = (xs.max() - xs.min()) if xs.size() > 1 else 0.0
		print("%d с: живы %d, ширина стаи %d, корабль x=%d" % [s + 1, xs.size(), spread, Game.player.x])
		await snap("swarm_%d" % (s + 1))
	await frames(180)
	var gone: int = bugs.filter(func(e): return e.leaving).size()
	var killed: int = bugs.filter(func(e): return not e.alive and not e.leaving).size()
	print("итог: сбито %d, ушли вниз %d, живы %d" % [killed, gone, bugs.size() - gone - killed])
	get_tree().quit()
