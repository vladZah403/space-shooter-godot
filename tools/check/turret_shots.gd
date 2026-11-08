extends Node
## Турели босса (запуск с окном): Страж выходит с двумя турелями, одну сбиваем — деталь отлетает, босс теряет
## прочность; потом босс гибнет — вторая турель гаснет вместе с ним. Печатает проверки, снимки.
##   Godot_console.exe --path . --fixed-fps 60 --resolution 390x844 res://tools/check/turret_shots.tscn -- --shots=ПАПКА
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


func turrets() -> Array:
	return Game.enemies.filter(func(e): return e.alive and e.ai == "bturret")


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
	B.spawnBoss(5)
	await frames(240)
	var b: En = Game.boss
	var ts := turrets()
	print("босс %s, турелей %d, впереди босса в списке: %s" % [b.bdef.id, ts.size(), Game.enemies.find(ts[0]) < Game.enemies.find(b) if ts.size() else false])
	await snap("a_turrets")
	var hp0 := b.hp
	Game.damageEnemy(ts[0], ts[0].hp + 1)
	await frames(18)
	await snap("b_part_flies")
	print("турель сбита: осталось %d, босс потерял %.1f%% прочности" % [turrets().size(), (hp0 - b.hp) / b.maxHp * 100])
	b.trans = 0.0; b.phase = 3; b.shield = 0.0; b.hp = 1.0
	Game.damageEnemy(b, 99999.0)
	await frames(10)
	print("босс сбит: турелей осталось %d" % turrets().size())
	get_tree().quit()
