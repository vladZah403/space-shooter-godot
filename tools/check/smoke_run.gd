extends Node2D
## Дымовой тест целого забега: новый профиль → Game.start → Game.frame 60 раз в секунду до 7 минут игрового
## времени. Бот: корабль бессмертен и качается по ширине, улучшения/модули/события/узлы карты выбирает первыми,
## подсказки закрывает, кат-сцены пропускает. Пишет ход волн и что в итоге сломалось (если сломалось).

const SECONDS := 420.0

var nodes: Array = []


func pick_offer() -> void:
	match Game.offerKind:
		"perk":
			var ch: Array = Game.perkChoices()
			if not ch.is_empty(): Game.choosePerk(ch[0].id)
		"map":
			var step: int = (int(Game.run.mapStep) - 1) % 5
			var ch: Array = RunMap.choices(Game.run.map, step)
			nodes.append(Game.run.map.cols[step][ch[0]].t)
			RunMap.choose(step, ch[0])
		"event", "module-buy":
			var cards: Array = Game.offer.get("cards", []) if Game.offer is Dictionary else []
			var free := cards.filter(func(c): return not c.get("price", 0))
			if not free.is_empty(): Game.pickOffer(free[0].id)
			elif not cards.is_empty(): Game.pickOffer(cards[0].id)
		_:
			var ms: Array = Game.moduleChoices()
			if not ms.is_empty(): Game.chooseModule(ms[0].id)


func _ready() -> void:
	M.s = M.defaults()
	M.s.seenIntro = true
	Game.start("normal")
	var dt := 1.0 / 60.0
	var tm := 0.0
	var lastWave := -1
	var stuck := 0.0
	var ctx := Ctx.new(get_canvas_item())
	print("старт: состояние %s, волна %s, жизней %d, оружие %s" % [Game.state, Game.wave.n if Game.wave else "-", Game.player.lives, Game.player.weapons])
	while tm < SECONDS:
		tm += dt
		var p: Pl = Game.player
		p.inv = 1e9
		if Game.state == "play": p.x = G.FW / 2 + sin(tm * 0.8) * G.FW * 0.35
		var st0: String = Game.state
		if Game.state == "perk": pick_offer()
		elif Game.state == "tip": Game.closeTip()
		elif Game.state == "cutscene" and fmod(tm, 3.0) < dt: Game.skipScene()
		elif Game.state == "over" or Game.state == "idle": break
		Game.frame(dt)
		if int(tm / dt) % 10 == 0:
			ctx.begin(); Game.draw(ctx)
		var wn: int = int(Game.wave.n) if Game.wave else -1
		if wn != lastWave:
			lastWave = wn
			print("%6.1f с  волна %d%s  врагов %d  убито %d  очки %d  уровень %d  монет %d" % [tm, wn, " (босс)" if Game.wave.boss else "", Game.enemies.size(),
				Game.run.kills, Game.run.score, Game.run.level, Game.run.coins])
		stuck = stuck + dt if Game.state == st0 and Game.state != "play" else 0.0
		if stuck > 20:
			print("ЗАСТРЯЛ в состоянии %s (%s)" % [Game.state, Game.offerKind])
			break
	print("узлы карты: ", nodes)
	print("сундуков: ", Game.run.chests, "  в сохранении: ", M.s.chests)
	print("итог: %.0f с, состояние %s, волна %s, убито %d, боссов %d, улучшений %d" % [tm, Game.state, Game.wave.n if Game.wave else "-", Game.run.kills, Game.run.bosses, Game.run.perkCount])
	print("SMOKE DONE")
	get_tree().quit()
