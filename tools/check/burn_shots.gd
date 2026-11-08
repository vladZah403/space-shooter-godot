extends Node
## Распад сбитых врагов (запуск с окном): все враги на экране сбиваются разом, снимки через 0.1, 0.25, 0.4, 0.65 с.
##   Godot_console.exe --path . --fixed-fps 60 --resolution 390x844 res://tools/check/burn_shots.tscn -- --autoplay --shots=ПАПКА
var shots := ""


func snap(name: String) -> void:
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
	await frames(420)
	await snap("a_before")
	var n := 0
	for e in Game.enemies.duplicate():
		if e.alive and not e.boss: E.kill(e, "test"); n += 1
	print("сбито ", n, ", сгорает ", E.burns.size())
	await frames(6)
	await snap("b_010")
	await frames(9)
	await snap("c_025")
	await frames(9)
	await snap("d_040")
	await frames(15)
	await snap("e_065")
	print("через 0.65 с сгорает ", E.burns.size())
	get_tree().quit()
