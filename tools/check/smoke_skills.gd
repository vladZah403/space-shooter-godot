extends Node2D
## Дымовой тест навыков (skills.gd) и дронов-напарников (companion.gd): каждый активный навык
## запускается среди врагов и работает 6 с; каждый дрон 8 с летает рядом и применяет умение.

const Fx := preload("res://fixture.gd")


func spawn_targets() -> void:
	for i in 4:
		var e := E.spawn("heavy", {"x": G.FW * (0.2 + i * 0.2), "y": G.H * 0.25, "noElite": true})
		e.ai = "none"; e.y = G.H * 0.25
		if i == 0: e.shield = e.maxHp * 0.3; e.shieldMax = e.shield


func hp_sum() -> float:
	var s := 0.0
	for e: En in Game.enemies:
		if e.alive: s += e.hp
	return s


func run_skill(id: String, ctx: Ctx) -> String:
	Fx.setup()
	spawn_targets()
	var hp0 := hp_sum()
	var sk: Dictionary = D.SKILLS.get(id, {})
	Game.run.skillFx[id] = sk.get("dur", 6.0) if sk.get("dur", 0.0) else 6.0
	Skills.cast(id, sk)
	var dt := 1.0 / 60.0
	var shots := 0
	var echoes := 0
	var reflected := 0
	var emp := 0
	for f in 360:
		Game.run.skillFx[id] -= dt
		Fx.step(dt)
		# двойник повторяет «выстрел» игрока
		if id == "sk_clone" and f % 10 == 0:
			var nb := Game.bullets.size()
			Game.spawnShot({"x": Game.player.x, "y": Game.player.y, "vx": 0.0, "vy": -600.0, "dmg": 5.0, "r": 4.0, "kind": "laser", "w": 8.0, "wid": "laser"})
			Skills.echo(nb)
			echoes += Game.bullets.size() - nb - 1
		# барьер отражает пули, летящие в корабль
		if id == "sk_barrier" and f % 20 == 0:
			var b := Game.ebullet(Game.player.x, Game.player.y - 20, 0, 0, "orb")
			if b and Skills.reflect(b): reflected += 1
		Skills.update(dt)
		for b: Bl in Game.bullets:
			if b.wid == "turret": shots += 1
		Game.bullets.clear(); Game.ebullets.clear()
		for e: En in Game.enemies:
			if e.alive and e.emp > 0: emp += 1
		if f % 6 == 0:
			ctx.begin(); Skills.drawBack(ctx); E.drawAll(ctx); Skills.drawFront(ctx)
	return "%-13s урон врагам %6.0f  турель %3d  эхо %2d  отражено %2d  ЭМИ-кадров %4d  rail %s hole %s" % [
		id, hp0 - hp_sum(), shots, echoes, reflected, emp, Game.ov.rail != null, Game.ov.hole != null]


func run_comp(id: String, ctx: Ctx) -> String:
	Fx.setup()
	M.s.comp = {"sel": id, "owned": [id], "lv": {id: 3}}
	var p: Pl = Game.player
	p.lives = 1
	Comp.start()
	spawn_targets()
	var hp0 := hp_sum()
	var dt := 1.0 / 60.0
	var shots := 0
	var blocked := 0
	var rockets := 0
	var heals := 0
	for f in 480:
		Fx.step(dt)
		p.x = G.FW / 2 + sin(f * 0.02) * 60
		var lives0 := p.lives
		var sh0 := p.shield
		Comp.update(dt)
		if p.lives > lives0 or (p.shield and not sh0): heals += 1
		for b: Bl in Game.bullets:
			if b.wid == "comp" and b.kind == "rocket": rockets += 1
			elif b.wid == "comp": shots += 1
		Game.bullets.clear()
		if id == "guard" and f % 5 == 0 and Comp.d:
			var b := Game.ebullet(Comp.d.x, Comp.d.y, 0, 0, "orb")
			if b and Comp.block(b): blocked += 1
		Game.ebullets.clear()
		if f % 6 == 0:
			ctx.begin(); Comp.draw(ctx)
	return "дрон %-9s есть %s  выстрелов %3d  ракет %d  лечений/щитов %d  блоков %2d  тянет монеты %s  ×монет %.2f" % [
		id, Comp.has(id), shots, rockets, heals, blocked, Comp.pulls(Pk.new()), Comp.coinMul()]


func _ready() -> void:
	var ctx := Ctx.new(get_canvas_item())
	for id in ["sk_rail", "sk_orbital", "sk_barrier", "sk_timewarp", "sk_turret", "sk_blackhole", "sk_emp", "sk_clone"]:
		print(run_skill(id, ctx))
	for id in D.COMPANIONS: print(run_comp(id, ctx))
	print("SMOKE DONE")
	get_tree().quit()
