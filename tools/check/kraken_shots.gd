extends Node
## Щупальца Кракена (запуск с окном): висят и колышутся, хватка к кораблю, рубка правого щупальца до конца.
##   Godot_console.exe --path . --fixed-fps 60 --resolution 390x844 res://tools/check/kraken_shots.tscn -- --shots=ПАПКА
var shots := ""


func snap(name: String) -> void:
	if shots == "": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots)
	get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))


func frames(n: int) -> void:
	for i in n:
		if Game.state == "tip": Game.closeTip()
		elif Game.state == "perk": Ui.botPick()
		if Game.player: Game.player.inv = 1.0
		await get_tree().process_frame


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	M.s.settings.intro = false
	M.s.seenIntro = true
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await frames(10)
	Ui.startRun("normal")
	await frames(120)
	for e in Game.enemies: e.alive = false
	Game.run.bossOrder = null   # порядок как в D.BOSSES: третий — Кракен
	B.spawnBoss(15)
	await frames(260)
	var b: En = Game.boss
	var tents: Array = b.pt.get("tents", [])
	print("босс %s, щупалец %d, звеньев %s" % [b.bdef.id, tents.size(), tents.map(func(t): return t.pts.size())])
	var tip: Dictionary = tents[0].pts[-1]
	print("кончик левого: x %d y %d (якорь y %d)" % [tip.x, tip.y, B.tentAnchor(b, -1).y])
	await snap("a_hang")
	tents[0].warn = 0.3
	await frames(40)
	await snap("b_lash")
	var hp0 := b.hp
	for i in 3: B.cutTent(b, tents[1])
	await frames(20)
	await snap("c_cut")
	print("правое отрублено: кончик %s, звеньев %d, босс потерял %.1f%%" % [B.tentTip(b, 1), tents[1].pts.size(), (hp0 - b.hp) / b.maxHp * 100])
	get_tree().quit()
