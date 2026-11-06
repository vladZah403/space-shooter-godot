extends Node2D
## Дымовой тест механик секторов (sectors.gd): каждая механика работает 25 с на силе k=0 и k=3 —
## появление «обстановки», облака, гравитация и ветер двигают пули и корабль, порталы перебрасывают снаряды,
## столпы и Око бьют лучами, гибель льда/яда/спутника, отрисовка.

func setup() -> void:
	M.s = {}
	Game.state = "play"
	Game.diff = D.DIFFS.normal
	Game.st = {"coins": 1.0}
	Game.run = {"relics": {}, "bossDamaged": false, "skillFx": {}, "noDrops": false, "anomaly": null}
	Game.wave = {"n": 7, "boss": false, "danger": false}
	var p := Pl.new()
	p.x = G.FW / 2; p.y = G.H * 0.8; p.inv = 1e9; p.alive = true; p.lives = 3; p.maxLives = 3
	Game.player = p


func run_mech(id: String, k: int, ctx: Ctx) -> String:
	Game.enemies.clear(); Game.ebullets.clear(); Game.bullets.clear(); Game.timers.clear(); Game.pickups.clear(); Game.ov.beams.clear()
	var m := {"id": id, "wave": Game.wave, "k": k, "cd": 0.6}
	Events.mech = m
	var p: Pl = Game.player
	p.x = G.FW / 2; p.y = G.H * 0.8
	var dt := 1.0 / 60.0
	var tm := 0.0
	var spawned := {}
	var fogged := 0
	var beams := 0
	var moved := 0.0
	var hops := 0
	var frozen := 0
	var px0 := p.x
	while tm < 25.0:
		tm += dt; Game.t += dt
		# пробные снаряды: вражеский по центру и свой снизу вверх
		if int(tm / dt) % 30 == 0:
			Game.ebullet(G.FW * 0.25, G.H * 0.3, 0, 60 * G.S, "orb")
			var b := Bl.new()
			b.x = G.FW * 0.25; b.y = G.H * 0.6; b.vy = -300 * G.S; b.kind = "laser"
			Game.bullets.append(b)
		# туманности нужны враги, которых она спрячет
		if id == "nebula" and int(tm / dt) % 120 == 0: E.spawn("shooter", {"noElite": true})
		var before := {}
		for b in Game.ebullets: before[b] = Vector2(b.x, b.y)
		Sectors.update(m, dt)
		for b in Game.ebullets:
			if before.has(b) and (Vector2(b.x, b.y) - before[b]).length() > 50 * G.S: hops += 1
			b.x += b.vx * dt; b.y += b.vy * dt
		for b in Game.bullets: b.x += b.vx * dt; b.y += b.vy * dt
		Game.ebullets = Game.ebullets.filter(func(b): return b.y < G.H and b.y > -50 and b.x > -50 and b.x < G.FW + 50)
		Game.bullets = Game.bullets.filter(func(b): return b.y > -50 and b.x > -50 and b.x < G.FW + 50)
		E.updateAll(dt, dt)
		Game.runTimers(dt)
		beams += Game.ov.beams.size(); Game.ov.beams.clear()
		for e: En in Game.enemies:
			if e.alive:
				spawned[e.type] = true
				if e.fog: fogged += 1
		moved = maxf(moved, absf(p.x - px0))
		if int(tm / dt) % 6 == 0:
			ctx.begin(); Sectors.drawBack(ctx, m); E.drawAll(ctx); Sectors.drawMid(ctx, m)
		# раз в 5 с разбиваем одну глыбу/спутник — посмертные эффекты
		if int(tm / dt) % 300 == 299:
			for e: En in Game.enemies:
				if e.alive and e.def.prop:
					var near := E.spawn("scout", {"x": e.x + 20, "y": e.y, "noElite": true})
					E.kill(e, "test")
					if near and near.frozen > 0: frozen += 1
					break
	var extra := ""
	if id == "toxic": extra = " облаков %d" % m.st.clouds.size()
	return "%-8s k=%d  обстановка %s  в тумане %4d  лучей %2d  снос корабля %3.0f  порталом %3d  заморожено %d%s" % [
		id, k, spawned.keys(), fogged, beams, moved, hops, frozen, extra]


func _ready() -> void:
	setup()
	var ctx := Ctx.new(get_canvas_item())
	for id in Sectors.MECHS:
		for k in [0, 3]: print(run_mech(id, k, ctx))
	print("SMOKE DONE")
	get_tree().quit()
