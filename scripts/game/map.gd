extends Node
## Карта сектора и реликвии (автозагрузка RunMap) — перенос map.js.
##  Сектор: 4 шага по 2–3 узла и босс. Перед каждой обычной волной (кроме самой первой в забеге) игрок
##  выбирает узел, связанный с прошлым: бой, элита, торговец, ремонт, тайник, событие. После волны — награда узла.
##  4.1: реликвии больше не выдаются в забеге — вместо них сундуки (элита, босс, тайник, события, торговец);
##  открываются на экране итогов, реликвия — в коллекцию, в забег берутся из коллекции (startRelics).
##  4.2: эскорт — Торговец идёт через волну, враги бьют по нему огненными шарами.

const STEPS := 4
const LANES := 3
const ESCORT := {"hp": 10, "w": 84.0, "cut": 0.7, "shotCd": 2.0}
## сцены узлов: 2,4 с — что происходит, до окна выбора (тап — пропустить)
const VISIT := {
	"shop": {"cap": "УЗЕЛ КАРТЫ", "name": "ТОРГОВЕЦ", "sub": "Лавка пристыковалась — заглянем", "color": "#ffc83d"},
	"cache": {"cap": "УЗЕЛ КАРТЫ", "name": "ТАЙНИК", "sub": "Контейнер с добычей", "color": "#b06bff"},
	"repair": {"cap": "УЗЕЛ КАРТЫ", "name": "РЕМОНТ", "sub": "Ремонтный корабль чинит обшивку", "color": "#3dffa2"},
	"elite": {"cap": "ТРЕВОГА", "name": "ЭЛИТНЫЙ ПАТРУЛЬ", "sub": "Врагов больше — награда: сундук", "color": "#ff3d5a"},
	"escort": {"cap": "УЗЕЛ КАРТЫ", "name": "ЭСКОРТ", "sub": "Доведите Торговца живым — скидка и сундук", "color": "#ffc83d"},
}


static func key(c: int, r: int) -> String:
	return "%d:%d" % [c, r]


# ════════════════════════════════════════════════════════════
# ГЕНЕРАЦИЯ И ВЫБОР УЗЛА
# ════════════════════════════════════════════════════════════
## в каждом шаге 2–3 узла, связи — к тому же или соседнему ряду. cols[c][r] — { r, t } или null
func generate(sector: int) -> Dictionary:
	var cols: Array = []
	var shops := 0
	var elites := 0
	var escorts := 0
	for c in STEPS:
		var col: Array = []
		for r in LANES: col.append({"r": r} if c == 0 or U.random() < 0.8 else null)
		if col.filter(func(n): return n != null).size() < 2 and col[1] == null: col[1] = {"r": 1}
		for n in col:
			if n == null: continue
			# лавка и эскорт — не больше одного на сектор, элита — не больше двух
			var types: Array = D.MAP_NODES.keys().filter(func(t): return (c > 0 or D.MAP_NODES[t].first) and not (t == "shop" and shops >= 1) \
				and not (t == "escort" and escorts >= 1) and not (t == "elite" and elites >= 2))
			n.t = U.pick_weighted(types, func(t): return D.MAP_NODES[t].w)
			if n.t == "shop": shops += 1
			if n.t == "escort": escorts += 1
			if n.t == "elite": elites += 1
		cols.append(col)
	# связи вперёд: у каждого узла хотя бы одна, у каждого следующего — хотя бы одна входящая
	var links := {}
	for c in STEPS - 1:
		var next: Array = cols[c + 1]
		for r in LANES:
			if cols[c][r] == null: continue
			var near: Array = [r - 1, r, r + 1].filter(func(q): return q >= 0 and q < LANES and next[q] != null)
			var pick: Array = near.filter(func(_q): return U.random() < 0.6) if not near.is_empty() else []
			if pick.is_empty(): pick.append(U.pick(near) if not near.is_empty() else next.find_custom(func(n): return n != null))
			links[key(c, r)] = pick
		for q in LANES:
			if next[q] == null: continue
			var has_in := false
			for k in links:
				if int(k.split(":")[0]) == c and q in links[k]: has_in = true
			if has_in: continue
			for r in [q - 1, q, q + 1, 0, 1, 2]:
				if r >= 0 and r < LANES and cols[c][r] != null:
					links[key(c, r)].append(q)
					break
	return {"sector": sector, "cols": cols, "links": links, "at": null, "path": []}


## какие узлы можно выбрать на шаге step
func choices(map: Dictionary, step: int) -> Array:
	var col: Array = map.cols[step]
	if step == 0 or map.at == null:
		return col.filter(func(n): return n != null).map(func(n): return n.r)
	return map.links.get(key(map.at.c, map.at.r), []).filter(func(r): return col[r] != null)


## нужна ли карта перед волной n: обычная волна, не первая в забеге, корабль цел и бой идёт
func need(n: int) -> bool:
	return n > 1 and n % 5 != 0 and Game.state == "play" and Game.player.alive and Game.run.mapStep != n


func offer(n: int) -> void:
	var run: Dictionary = Game.run
	var sector := (n - 1) / 5
	var step := (n - 1) % 5
	if run.map == null or run.map.sector != sector: run.map = generate(sector)
	var ch := choices(run.map, step)
	run.mapStep = n
	if ch.is_empty():
		Game.nextWave()
		return
	Game.state = "perk"
	Game.offerKind = "map"
	Game.pointer.id = -1
	A.play("skill", {"rate": 1.1})
	Bus.emit("mapOffer", {"map": run.map, "step": step, "choices": ch, "n": n})


func choose(step: int, r: int) -> bool:
	var run: Dictionary = Game.run
	var map = run.map
	if Game.state != "perk" or Game.offerKind != "map" or map == null or not r in choices(map, step): return false
	map.at = {"c": step, "r": r}
	map.path.append(key(step, r))
	run.mapNode = map.cols[step][r].t
	Game.offerKind = ""
	Game.state = "play"
	Game.player.inv = maxf(Game.player.inv, 0.8)
	A.play("click")
	if run.mapNode == "elite" or run.mapNode == "escort": visit(run.mapNode, null, func(): Game.nextWave())
	else: Game.nextWave()
	return true


## узел меняет саму волну: элита — больше врагов и элита чаще (как опасный путь), тайник — волна полегче,
## эскорт — в волне летит Торговец
func apply(w: Dictionary) -> void:
	var run: Dictionary = Game.run
	w.node = "boss" if w.boss else (run.mapNode if run.mapNode != null else "fight")
	run.mapNode = null
	run.escort = null
	if w.node == "elite":
		w.danger = true; w.budget *= D.DANGER.count
	if w.node == "cache": w.budget *= 0.8
	if w.node == "escort":
		run.escort = {"x": G.FW / 2, "y": G.H * 0.66, "hp": ESCORT.hp, "t": 0.0, "cd": 2.5, "flash": 0.0}
		Game.after(w.intro + 0.8, func(): Game.hintOnce("escort", "ПОДСКАЗКА", "Враги бьют по Торговцу огненными шарами — сбивайте их выстрелами. Довезёте живым — скидка в лавке и сундук"))


## награда узла после волны; true — показано окно, волна начнётся после выбора
func reward(w: Dictionary) -> bool:
	var p: Pl = Game.player
	if Game.state != "play" or not p.alive: return false
	var node: String = w.get("node", "fight")
	if node == "escort": return escortDone()
	if node == "elite":
		chestScene("silver" if U.random() < 0.25 else "bronze", "ЭЛИТА ПОВЕРЖЕНА", func(): Game.nextWave())
		return true
	# торговец, тайник, ремонт и событие — сначала короткая сцена, награда в её конце
	if node in ["shop", "cache", "repair", "event"]:
		var ev = U.pick(D.MAP_EVENTS) if node == "event" else null
		visit(node, ev, func(): if not nodeReward(w, ev): Game.nextWave())
		return true
	return false


func nodeReward(w: Dictionary, ev) -> bool:
	var p: Pl = Game.player
	var run: Dictionary = Game.run
	match w.node:
		"shop":
			var o := Game.merchantOffer()
			# вместо реликвии — закрытый сундук (откроется после забега); значок рисует интерфейс по полю chest
			o.cards.insert(o.cards.size() - 1, {"id": "chest:silver", "chest": "silver", "ico": "📦", "name": D.CHESTS.silver.name,
				"desc": "Откроется после забега: реликвия в коллекцию", "rar": "epic", "price": roundf((300 + w.n * 25) * o.cut / 10) * 10})
			return show(o)
		"event":
			var cards: Array = ev.cards.map(func(c):
				var c2: Dictionary = c.duplicate()
				c2.id = "ev:" + ev.id + ":" + c.id
				return c2)
			return show({"title": ev.title, "sub": ev.sub, "cards": cards})
		"repair":
			if p.lives < p.maxLives: Game.heal(mini(2, p.maxLives - p.lives), "🔧 РЕМОНТ")
			elif not p.shield:
				p.shield = true; Game.shieldFx(); FX.text(p.x, p.y - p.w, "🔧 ЩИТ", "#3dffa2", 15, 1.1)
			return false
		"cache":
			# st.coins уже включает штраф за фарм лёгкой сложности (coinK) — тайник его не обходит
			var coins := int(round((20 + w.n * 2.5) * Game.st.coins))
			run.coins += coins; M.addCoins(coins)
			FX.text(p.x, p.y - p.w, "📦 +%d" % coins, "#ffc83d", 16, 1.2)
			A.play("coin", {"rate": 0.8})
			if U.random() < 0.35: giveChest("bronze")
			Game.hudDirty = true
			return false
	return false


func show(o: Dictionary) -> bool:
	Game.state = "perk"
	Game.offerKind = "event"
	Game.offer = o
	Game.pointer.id = -1
	A.play("skill", {"rate": 1.2})
	Bus.emit("eventOffer", o)
	return true


# ════════════════════════════════════════════════════════════
# 4.2: ЭСКОРТ — Торговец идёт через волну снизу вверх, враги по очереди бьют по нему огненными снарядами.
#  Его ранят только они (пули в игрока пролетают мимо), и их можно сбить своими выстрелами.
#  Довели живым — скидка в следующей лавке и сундук; сбили — без награды (и без штрафа)
# ════════════════════════════════════════════════════════════
func updateEscort(dt: float) -> void:
	var es = Game.run.get("escort") if Game.run else null
	var w = Game.wave
	if es == null or w == null: return
	var S := G.S
	es.t += dt; es.flash -= dt
	# поднимается по мере того, как волна выпускает врагов, и покачивается из стороны в сторону
	var k := U.clamp(w.spent / w.budget, 0, 1) if w.budget > 0 else 1.0
	var ty := U.lerp(G.H * 0.66, G.H * 0.3, k)
	var tx := G.FW / 2 + sin(es.t * 0.45) * G.FW * 0.2
	es.x = U.damp(es.x, tx, 1.2, dt); es.y = U.damp(es.y, ty, 0.8, dt)
	if Game.state != "play" or w.intro > 0: return
	# время от времени кто-то из врагов выше Торговца бьёт по нему
	es.cd -= dt
	if es.cd <= 0:
		es.cd = ESCORT.shotCd * U.rand(0.7, 1.3)
		var shooters: Array = Game.enemies.filter(func(e): return e.alive and e.hittable and not e.def.prop and not e.leaving and e.y > 20 * S and e.y < es.y - 60 * S)
		if not shooters.is_empty():
			var e: En = U.pick(shooters)
			var a := atan2(es.y - e.y, es.x - e.x)
			var sp := Game.bspd(150)
			Game.ebullet(e.x, e.y, cos(a) * sp, sin(a) * sp, "fire", {"escort": true})
	# снаряды, летящие в Торговца, сбиваются выстрелами игрока
	for b: Eb in Game.ebullets:
		if b.dead or not b.escort: continue
		for pb: Bl in Game.bullets:
			if pb.dead: continue
			var rr := b.r + (pb.r if pb.r else 4 * S) + 6 * S
			if U.dist2(b.x, b.y, pb.x, pb.y) < rr * rr:
				b.dead = true; pb.dead = true
				FX.hit(b.x, b.y, "#ffc83d"); FX.text(b.x, b.y - 10 * S, "СБИТ", "#ffc83d", 11, 0.6, -40)
				break


## снаряд, пущенный в Торговца, попал в него (из Game.updateEBullets); true — снаряд погас
func escortHit(b: Eb) -> bool:
	var run: Dictionary = Game.run
	var es = run.get("escort") if run else null
	if es == null or not b.escort: return false
	var S := G.S
	if absf(b.x - es.x) > ESCORT.w * S * 0.42 or absf(b.y - es.y) > ESCORT.w * S * 0.6: return false
	es.hp -= 1; es.flash = 0.12
	FX.hit(b.x, b.y, "#ffc83d")
	A.play("shieldHit", {"vol": 0.3, "rate": 0.8})
	if es.hp <= 0:
		run.escort = null
		FX.explode(es.x, es.y, 1.6, "#ffc83d"); FX.shake(0.25)
		A.play("explodeL", {"vol": 0.7})
		Bus.emit("toast", {"ico": "💥", "title": "ЭСКОРТ", "text": "Торговца сбили — награды не будет", "info": true, "dur": 2600})
	return true


func drawEscort(ctx: Ctx) -> void:
	var es = Game.run.get("escort") if Game.run else null
	if es == null: return
	var S := G.S
	var w: float = ESCORT.w * S
	ctx.save()
	Scenes.merchant(ctx, es.x, es.y, w, es.t, {"thrust": 0.35})
	if es.flash > 0:
		ctx.additive = true; ctx.alpha = 0.6
		ctx.draw_tex(G.glow("#ff5c3d", 64), es.x - w * 0.6, es.y - w * 0.6, w * 1.2, w * 1.2)
	ctx.restore()
	# полоска прочности над кораблём
	var bw := w * 0.8
	var bh := 5 * S
	var bx: float = es.x - bw / 2
	var by: float = es.y - w * G.aspect("p_merchant") * 0.62 - 10 * S
	var k: float = float(es.hp) / ESCORT.hp
	ctx.fill = Color(0, 0, 0, 0.55); ctx.fill_rect(bx - 1, by - 1, bw + 2, bh + 2)
	ctx.fill = U.col("#3dffa2" if k > 0.5 else ("#ffc83d" if k > 0.25 else "#ff3d5a")); ctx.fill_rect(bx, by, bw * k, bh)


## волна зачищена: Торговец уходит в прыжок, скидка в следующей лавке и сундук
func escortDone() -> bool:
	var run: Dictionary = Game.run
	var es = run.escort
	var S := G.S
	run.escort = null
	if es == null: return false
	run.shopCut = ESCORT.cut
	FX.ring(es.x, es.y, 10 * S, 120 * S, "#ffc83d", 0.5, 4); FX.glow_puff(es.x, es.y, "#ffc83d", 140 * S, 0.5)
	A.play("teleport", {"rate": 1.2, "vol": 0.5})
	Bus.emit("toast", {"ico": "🛡", "title": "ЭСКОРТ", "text": "Торговец доставлен: −30% в следующей лавке", "info": true, "dur": 2600})
	chestScene("silver" if U.random() < 0.35 else "bronze", "ТОРГОВЕЦ ДОСТАВЛЕН", func(): Game.nextWave())
	return true


# ════════════════════════════════════════════════════════════
# 4.1: СУНДУКИ — сразу в сохранение (закрытыми), в забеге только счётчик
# ════════════════════════════════════════════════════════════
## Звёздная карта и высокие сложности иногда улучшают сундук на ступень
func giveChest(tier: String, quiet := false) -> String:
	var run: Dictionary = Game.run
	var up := (0.3 if Game.relic("r_chart") else 0.0) + (0.2 if Game.diffId in ["nightmare", "god", "hell"] else 0.0)
	if tier != "gold" and U.random() < up: tier = D.CHEST_ORDER[D.CHEST_ORDER.find(tier) + 1]
	M.addChest(tier)
	run.get_or_add("chests", []).append(tier)
	if not quiet:
		A.play("perk", {"rate": 0.8})
		Bus.emit("toast", {"ico": "chest", "title": "СУНДУК", "text": D.CHESTS[tier].short + " — откроется после забега", "info": true, "dur": 2200})
	Bus.emit("chest", tier)
	Game.hudDirty = true
	return tier


## сундук босса: первые боссы — серебро, дальше всё чаще золото
func bossChest() -> String:
	var n: int = Game.run.bosses
	return "gold" if U.random() < minf(0.75, maxf(0, n - 1) * 0.2) else "silver"


## сцена: сундук падает в кадр, рвётся открыться и улетает в трюм; дальше onEnd
func chestScene(tier: String, cap: String, onEnd: Callable) -> void:
	if Game.state != "play":
		giveChest(tier); onEnd.call()
		return
	tier = giveChest(tier, true)
	var def: Dictionary = D.CHESTS[tier]
	Game.startScene({"kind": "visit", "node": "chest", "tier": tier, "color": def.color, "v": {"cap": cap, "name": def.short + " СУНДУК", "sub": "Откроется после забега"},
		"end": 2.3, "cardT": 0.55, "onEnd": onEnd, "done": false})
	A.play("teleport", {"rate": 1.1, "vol": 0.5})


# ── реликвия в забеге (4.1 — только взятые из коллекции на старте) ──
func grant(id: String, quiet := false) -> void:
	var run: Dictionary = Game.run
	var p: Pl = Game.player
	var def = D.RELICS.get(id)
	if def == null or run.relics.get(id): return
	run.relics[id] = 1
	if id == "r_kevlar":
		p.maxLives += 1; p.lives += 1
	if id == "r_arsenal": p.bombs = mini(9, p.bombs + 2)
	if id == "r_glassblade":
		p.maxLives = maxi(1, p.maxLives - 2); p.lives = mini(p.lives, p.maxLives)
	Game.refreshStats()
	if not quiet:
		var col: String = D.RELIC_RARITY[def.rar].color
		FX.glow_puff(p.x, p.y, col, 120 * G.S, 0.5)
		FX.ring(p.x, p.y, p.w * 0.4, p.w * 1.8, col, 0.5, 4)
		A.play("perk", {"rate": 0.9})
		Bus.emit("toast", {"ico": def.ico, "title": "РЕЛИКВИЯ", "text": def.name, "info": true, "dur": 2200})
	Game.hudDirty = true


## старт забега: реликвии из коллекции (в испытании дня — нет: у всех одинаковые условия)
func startRelics() -> void:
	if Game.run.challenge != null: return
	for id in M.relicLoadout(): grant(id, true)


# ════════════════════════════════════════════════════════════
# СЦЕНЫ УЗЛОВ (анимации — scenes.gd)
# ════════════════════════════════════════════════════════════
func visit(node: String, ev, onEnd: Callable) -> void:
	if Game.state != "play":
		onEnd.call()
		return
	var v: Dictionary = {"cap": "СОБЫТИЕ", "name": ev.title, "sub": ev.sub, "color": "#7fe7ff"} if node == "event" else VISIT[node]
	Game.startScene({"kind": "visit", "node": node, "ev": ev, "color": v.color, "v": v, "end": 2.7 if node == "shop" else 2.4, "cardT": 0.35, "onEnd": onEnd, "done": false})
	A.play("warning" if node == "elite" else "teleport", {"rate": 1.0 if node == "elite" else 0.8, "vol": 0.6})


func updateVisit(sc: Dictionary) -> void:
	Scenes.update(sc)


func drawVisit(ctx: Ctx, sc: Dictionary) -> void:
	Scenes.draw(ctx, sc)


## вращающиеся лучи за наградой (сундук в бою и при открытии): веер клиньев с прозрачным краем
func rays(ctx: Ctx, x: float, y: float, r: float, col: String, t: float, a: float, n := 10) -> void:
	var c0 := U.col(col, 0.9)
	var c1 := U.col(col, 0.0)
	var old := ctx.alpha
	ctx.alpha = a
	for i in n:
		var a0 := i * TAU / n + t * 0.5
		var a1 := a0 + TAU / n * 0.38
		var pts := PackedVector2Array([Vector2(x, y)])
		var cols := PackedColorArray([c0])
		for j in 5:
			var aa := lerpf(a0, a1, j / 4.0)
			pts.append(Vector2(x + cos(aa) * r, y + sin(aa) * r))
			cols.append(c1)
		ctx.fill_poly(pts, cols)
	ctx.alpha = old


# ── событие на карте: исход выбора ──
func resolve(ev: String, card: String) -> void:
	var p: Pl = Game.player
	var run: Dictionary = Game.run
	var say := func(ico: String, text: String): Bus.emit("toast", {"ico": ico, "title": "СОБЫТИЕ", "text": text, "info": true, "dur": 2400})
	if card == "pass": return
	if ev == "wreck" and card == "search":
		if U.random() < 0.6: giveChest("bronze")
		else:
			run.nextDanger = true; say.call("⚠️", "Засада! Следующая волна элитная")
	elif ev == "black" and card == "blood":
		p.lives = maxi(1, p.lives - 1)
		FX.flash("#ff3d5a", 0.3); A.play("playerHit", {"vol": 0.5}); Bus.emit("playerHit")
		giveChest("gold")
	elif ev == "anomaly" and card == "enter":
		if U.random() < 0.5:
			var mods: Array = D.MODULES.filter(func(m): return Game.mod(m.id) < m.max)
			if not mods.is_empty():
				var m: Dictionary = U.pick(mods)
				run.mods[m.id] = run.mods.get(m.id, 0) + 1
				run.parts = Game.shipParts(run.mods)
				Game.refreshStats()
				say.call(m.ico, "Аномалия подарила модуль: " + m.name)
		else:
			p.lives = maxi(1, p.lives - 1); FX.flash("#b06bff", 0.3); Bus.emit("playerHit"); say.call("🌀", "Аномалия задела корабль: −1 жизнь")
	elif ev == "distress":
		if card == "help":
			run.coins += 100; M.addCoins(100); say.call("🤝", "Экипаж спасён: +100 монет")
		else:
			giveChest("silver"); run.nextDanger = true
	elif ev == "station":
		if card == "fix": Game.heal(1, "🏚️ РЕМОНТ")
		else:
			p.bombs = mini(9, p.bombs + 1); run.coins += 50; M.addCoins(50); say.call("💣", "+1 бомба и 50 монет")
	elif ev == "slot" and card == "play":
		if U.random() < 0.5:
			run.coins += 250; M.addCoins(250); A.play("coin", {"rate": 1.3}); say.call("🎰", "Джекпот! +250 монет")
		else: say.call("🎰", "Не повезло")
	Game.hudDirty = true
