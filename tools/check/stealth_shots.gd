extends Node
## Невидимки (запуск с окном): три штуки в маскировке — снимок; по одной попадание — снимок проявления.
##   Godot_console.exe --path . --fixed-fps 60 --resolution 390x844 res://tools/check/stealth_shots.tscn -- --autoplay --shots=ПАПКА
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
	Main.quality = 2
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await frames(240)
	Game.player.alive = false   # бот не стреляет — смотрим на маскировку спокойно
	for e in Game.enemies: e.alive = false
	var list := []
	for i in 3:
		var e: En = E.spawn("stealth", {"noElite": true})
		list.append(e)
	await frames(150)
	for f in 30:
		for e: En in list:
			e.x = G.FW * (0.25 + 0.25 * list.find(e)); e.y = G.H * 0.4
			e.shown = 0.0; e.cloakT = 99.0
		for e in Game.enemies: if not e in list: e.alive = false
		await frames(1)
	print("в маскировке: прозрачность ", list.map(func(e): return snappedf(e.alpha, 0.01)))
	await snap("a_cloaked")
	Game.damageEnemy(list[1], 1.0)
	for f in 12:
		for e: En in list:
			e.x = G.FW * (0.25 + 0.25 * list.find(e)); e.y = G.H * 0.4
		await frames(1)
	print("после попадания: ", list.map(func(e): return snappedf(e.alpha, 0.01)))
	await snap("b_revealed")
	get_tree().quit()
