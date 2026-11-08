extends Node
## Наезд камеры (запуск с окном): появление босса и его гибель — снимки и увеличение Game.cam.z по времени.
##   Godot_console.exe --path . --fixed-fps 60 --resolution 390x844 res://tools/check/camera_shots.tscn -- --autoplay --shots=ПАПКА
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
	await frames(300)
	for e in Game.enemies: e.alive = false
	B.spawnBoss(5)
	var zmax := 1.0
	for i in 40:
		await frames(1)
		zmax = maxf(zmax, Game.cam.z)
	print("появление босса: наибольшее увеличение %.3f" % zmax)
	await snap("a_spawn")
	await frames(200)
	var b: En = Game.boss
	if b == null: print("босса нет"); get_tree().quit(1); return
	b.entering = false
	b.trans = 0.0
	b.phase = 3
	b.shield = 0.0
	b.hp = 1.0
	Game.damageEnemy(b, 99999.0)
	print("босс жив после удара: ", b.alive, ", фаза ", b.phase)
	var log := []
	for i in 150:
		await frames(1)
		if i % 15 == 0: log.append("%.2f" % Game.cam.z)
		if i == 25: await snap("b_kill")
		if i == 90: await snap("c_back")
	print("гибель босса: увеличение по кадрам ", " ".join(log), ", замедление ", "%.2f" % Game.timeScale)
	get_tree().quit()
