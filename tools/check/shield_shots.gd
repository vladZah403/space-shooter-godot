extends Node
## Пузырь щита (запуск с окном): щит игрока, щит босса Дредноута и рябь от попадания — снимки.
##   Godot_console.exe --path . --fixed-fps 60 --resolution 390x844 res://tools/check/shield_shots.tscn -- --autoplay --shots=ПАПКА
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
	await frames(300)
	for e in Game.enemies: e.alive = false
	Game.player.shield = true
	Game.shieldFx()
	B.spawnBoss(30)
	await frames(8)
	await snap("a_player_ripple")
	await frames(220)
	var b: En = Game.boss
	print("босс: ", b.bdef.id if b else "-", ", щит ", b.shield if b else 0.0)
	await snap("b_boss_shield")
	b.entering = false
	b.trans = 0.0
	Game.damageEnemy(b, 5.0)
	await frames(3)
	await snap("c_boss_hit")
	get_tree().quit()
