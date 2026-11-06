extends Node
## Снимки постобработки (запуск с окном): без эффектов, свечение, ударная волна, сноп искр, воронка, аберрация, форсаж.
##   Godot.exe --path . --fixed-fps 60 res://tools/check/post_shots.tscn -- --autoplay --shots=ПАПКА
## (--autoplay — мир сам начинает забег и ведёт бота; снимки — на 10-й секунде боя)

var shots := ""


func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots)
	get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))
	print("снимок ", name, " fps ", Main.fps)


func frames(n: int) -> void:
	for i in n: await get_tree().process_frame


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	M.s.settings.intro = false
	M.s.seenIntro = true
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await frames(600)
	M.s.settings.post = false
	await frames(2)
	await snap("a_off")
	M.s.settings.post = true
	Main.quality = 2
	await frames(2)
	await snap("b_bloom")
	Post.wave(G.FW / 2, G.H * 0.45, 2.2)
	await frames(12)
	await snap("c_wave")
	Vfx.burst(G.FW / 2, G.H * 0.3, "#ffb03d", 3.0)
	await frames(6)
	await snap("c2_burst")
	Game.ov.hole = {"x": G.FW / 2, "y": G.H * 0.32, "t": 0.0, "dur": 4.0, "tick": 0.0}
	await frames(40)
	await snap("d_hole")
	Game.ov.hole = null
	Post.hurt(1.0)
	await frames(2)
	await snap("e_hurt")
	Post.warp = 0.8
	Post.warp_at = Vector2(G.FW / 2, G.H * 0.42)
	await snap("f_warp")
	get_tree().quit()
