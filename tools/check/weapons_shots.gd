extends Node
## Новое оружие на физике (запуск с окном): бумеранг, гравипушка, пила — каждое по 4 с против строя врагов.
## Печатает урон, сколько клинков вернулось, отбросы и удары «бильярда», снимки.
##   Godot_console.exe --path . --fixed-fps 60 --resolution 390x844 res://tools/check/weapons_shots.tscn -- --shots=ПАПКА
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
	M.s.weapons.owned = ["laser", "boomerang", "gravgun", "flail"]
	M.s.weapons.loadout = ["boomerang", "gravgun", "flail"]
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await frames(10)
	Ui.startRun("normal")
	await frames(60)
	var p: Pl = Game.player
	for wid in ["boomerang", "gravgun", "flail"]:
		Game.setWeapon(wid)
		for e in Game.enemies: e.alive = false
		var list: Array = []
		for i in 6:
			var e: En = E.spawn("scout", {"noElite": true, "x": G.FW * (0.2 + 0.12 * i), "y": G.H * (0.3 if wid != "flail" else 0.62) + (i % 2) * 30 * G.S})
			e.hp *= 6; e.maxHp = e.hp
			list.append(e)
		var hp0: float = list.reduce(func(a, e): return a + e.hp, 0.0)
		var knocks := 0
		var maxBoom := 0
		for f in 240:
			p.x = G.FW / 2 + sin(f * 0.05) * G.FW * 0.25
			if wid == "flail": p.y = G.H * 0.72
			for e in list:
				if e.alive:
					e.st = 1; e.ty = G.H * 0.3
					if e.kbT > 0: knocks += 1
			maxBoom = maxi(maxBoom, Game.countShots("boom"))
			await frames(1)
			if f == 120: await snap("w_" + wid)
		var hp1: float = list.reduce(func(a, e): return a + (e.hp if e.alive else 0.0), 0.0)
		var dead: int = list.filter(func(e): return not e.alive).size()
		print("%s: урон %d из %d, сбито %d; клинков в воздухе макс. %d; кадров с отбросом %d; пила %s" % [wid, hp0 - hp1, hp0, dead, maxBoom, knocks, "есть" if Game.flail != null else "нет"])
	get_tree().quit()
