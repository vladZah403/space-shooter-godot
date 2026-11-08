extends Node
## Отражение лучей щитом (запуск с окном): Ионный стреляет лучом в корабль со щитом — луч уходит обратно и
## сбивает Ионного; потом поворотный лазер в корабль со щитом — урон стрелку. Печатает итог и снимки.
##   Godot_console.exe --path . --fixed-fps 60 --resolution 390x844 res://tools/check/reflect_shots.tscn -- --shots=ПАПКА
var shots := ""


func snap(name: String) -> void:
	if shots == "": return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots)
	get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))


func frames(n: int) -> void:
	for i in n: await get_tree().process_frame


## окна, которые останавливают бой (подсказка, выбор улучшения), закрываем сразу
func unstick() -> void:
	if Game.state == "tip": Game.closeTip()
	elif Game.state == "perk": Ui.botPick()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="): shots = a.substr(8)
	M.s.settings.intro = false
	M.s.seenIntro = true
	var world: Node = load("res://scenes/world.tscn").instantiate()
	get_tree().root.add_child.call_deferred(world)
	await frames(10)
	Ui.startRun("normal")   # без бота: он держит корабль неуязвимым и сам водит его
	await frames(200)
	unstick()
	var p: Pl = Game.player
	p.inv = 0.0
	for e in Game.enemies: e.alive = false
	var ion: En = E.spawn("ion", {"noElite": true})
	ion.x = G.FW / 2; ion.y = G.H * 0.25; ion.st = 1; ion.ty = ion.y; ion.chargeT = 0.0; ion.stay = 99.0
	p.shield = true
	var shield_after := false
	for i in 110:
		unstick()
		p.x = ion.x; ion.vx = 0.0; ion.x = G.FW / 2
		for e in Game.enemies: if e != ion: e.alive = false
		await frames(1)
		if i == 70: await snap("a_beam_reflect")
	shield_after = p.shield
	print("луч: Ионный сбит = ", not ion.alive, ", щит цел = ", shield_after, ", отражений ", Game.ov.refl.size())
	# поворотный лазер, нацеленный в корабль; владелец — враг-мишень
	var tgt: En = E.spawn("heavy", {"noElite": true})
	tgt.x = G.FW / 2; tgt.y = G.H * 0.2
	var hp0 := tgt.hp
	var L := Game.laser({"owner": tgt, "ang": PI / 2, "warn": 0.2, "dur": 0.9, "color": "#ff3d5a"})
	p.inv = 0.0
	for i in 70:
		unstick()
		p.x = tgt.x; tgt.x = G.FW / 2; tgt.y = G.H * 0.2; L.ang = PI / 2
		await frames(1)
		if i == 40: await snap("b_laser_reflect")
	print("лазер: урон стрелку %d из %d, щит цел = %s" % [hp0 - tgt.hp, hp0, p.shield])
	get_tree().quit()
