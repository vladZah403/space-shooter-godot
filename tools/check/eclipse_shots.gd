extends Node
## Аномалия «Затмение» (запуск с окном): тьма сгущается, бот стреляет — снимки боя во тьме и взрыва.
##   Godot_console.exe --path . --fixed-fps 60 --resolution 390x844 res://tools/check/eclipse_shots.tscn -- --autoplay --shots=ПАПКА
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
	await frames(200)
	Game.run.anomaly = "eclipse"
	await frames(200)
	print("тьма: ", snappedf(Game.darkK, 0.01))
	await snap("a_dark")
	FX.explode(G.FW * 0.3, G.H * 0.3, 2.4, "#ffb03d")
	await frames(4)
	await snap("b_blast")
	Game.run.anomaly = null
	await frames(150)
	print("после аномалии тьма: ", snappedf(Game.darkK, 0.01))
	get_tree().quit()
