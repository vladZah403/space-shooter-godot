extends Node2D
## Дымовой тест врагов 3.1 (foes.gd): каждый вид выходит на поле и живёт ~14 с — поведение, защиты от оружия,
## привыкание Мимика, лечение Медика, кража Вора, навес Мортиры, купол, поле Гравитона, луч Связки, отрисовка.

func setup() -> void:
	M.s = {}
	Game.state = "play"
	Game.diff = D.DIFFS.normal
	Game.st = {"coins": 1.0}
	Game.run = {"relics": {}, "bossDamaged": false, "bossDps": 0.0, "bossK": 1.0, "skillFx": {}, "noDrops": false, "anomaly": null}
	Game.wave = {"n": 25, "boss": false, "danger": false}
	var p := Pl.new()
	p.x = G.FW / 2; p.y = G.H * 0.8; p.inv = 1e9; p.alive = true; p.lives = 1; p.maxLives = 3
	Game.player = p


func pickup(x: float, y: float, kind: String) -> void:
	var it := Pk.new()
	it.kind = kind; it.x = x; it.y = y; it.val = 5.0; it.pu = "rapid" if kind == "pu" else ""
	Game.pickups.append(it)


func run_type(type: String, ctx: Ctx) -> String:
	Game.enemies.clear(); Game.ebullets.clear(); Game.timers.clear(); Game.pickups.clear(); Foes.reset()
	var es: Array = []
	match type:
		"link": Foes.spawnLink()
		"hive_egg": Foes.spawnEgg()
		_:
			es.append(E.spawn(type, {"noElite": true}))
			if type == "medic":
				var hurt := E.spawn("heavy", {"noElite": true})
				hurt.hp = hurt.maxHp * 0.3
	if Game.enemies.is_empty(): return "%-11s НЕ ПОЯВИЛСЯ" % type
	var dt := 1.0 / 60.0
	var tm := 0.0
	var info := {"shots": 0, "shells": 0, "heals": 0, "dome": 0, "grav": 0, "link": 0, "hidden": 0}
	var res := ""
	var p: Pl = Game.player
	while tm < 14.0:
		tm += dt; Game.t += dt
		p.x = G.FW / 2 + sin(tm * 0.7) * G.FW * 0.3
		if absf(tm - 3.0) < dt / 2:
			for i in 3: pickup(U.rand(0.2, 0.8) * G.FW, G.H * U.rand(0.3, 0.5), ["coin", "pu", "en"][i])
		E.updateAll(dt, dt)
		Foes.update(dt)
		Game.runTimers(dt)
		info.shots += Game.ebullets.size(); Game.ebullets.clear()
		info.shells = maxi(info.shells, Foes.shells.size())
		info.heals += Foes.heals.size()
		info.dome = maxi(info.dome, Foes.domes.size()); info.grav = maxi(info.grav, Foes.gravs.size()); info.link = maxi(info.link, Foes.links.size())
		for e: En in Game.enemies:
			if e.alive and Foes.hidden(e): info.hidden += 1
		if int(tm / dt) % 6 == 0:
			ctx.begin(); Foes.drawBack(ctx); E.drawAll(ctx); Foes.drawFront(ctx)
		if absf(tm - 6.0) < dt / 2 and not Game.enemies.is_empty():
			var e: En = Game.enemies[0]
			var ks := []
			for src in ["laser", "shotgun", "rocket", "plasma", "lightning", "dark"]: ks.append("%s=%.1f" % [src.substr(0, 3), Foes.resist(e, src, 1.0)])
			if type == "mimic":
				Foes.resist(e, "laser", e.maxHp)
				ks.append("после привыкания lase=%.1f" % Foes.resist(e, "laser", 1.0))
			res = " ".join(ks)
	var alive := Game.enemies.filter(func(e): return e.alive)
	var loot := 0
	for e: En in alive: loot += e.loot.size()
	# гибель: Вор возвращает добычу, Связка злит напарника, грузовик роняет ящики
	var rage := false
	if not alive.is_empty():
		E.kill(alive[0], "test")
		for e: En in alive: if e.alive and e.rage: rage = true
	var drops := Game.pickups.filter(func(it): return not it.dead).size()
	return "%-11s живых %d  пуль %4d  мин %d  лечений %3d  купол %d грав %d луч %d  скрыт %4d  добыча %d  ярость %s  предметов %d | %s" % [
		type, alive.size(), info.shots, info.shells, info.heals, info.dome, info.grav, info.link, info.hidden, loot, rage, drops, res]


func _ready() -> void:
	setup()
	var ctx := Ctx.new(get_canvas_item())
	for type in ["mirror", "icebreaker", "stealth", "graviton", "mimic", "medic", "thief", "link", "mortar", "projector", "ion", "hive_egg", "cargo"]:
		print(run_type(type, ctx))
	print("SMOKE DONE")
	get_tree().quit()
