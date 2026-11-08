extends Node
## Враги 3.1 (автозагрузка Foes) — перенос foes.js.
##  Защита от оружия (значок над врагом, подсказка при первой встрече):
##  Зеркало — лазер, Ледокол — дробовик, Гравитон — ракеты и т. материя,
##  Связка — серп, Проектор — плазма, Невидимка и Ионный — молния,
##  Мимик привыкает к оружию, которым его бьют.
##  Поддержка: Медик лечит соседей, Вор крадёт добычу, Мортира бьёт навесом.
##  Обстановка (лист 13): яйца Улья, грузовики Конвоя, санитарный корабль.
## Поведение подхватывает enemies.gd: _init_<ai> / _ai_<ai> отсюда, стрельба «lob» — _fire_lob.

## источник урона → оружие: для значка и привыкания Мимика
const SRC_W := {"laser": "laser", "shotgun": "shotgun", "rocket": "rocket", "arc": "arc", "plasma": "plasma", "lightning": "lightning", "dark": "darkmatter", "boomerang": "boomerang", "gravgun": "gravgun", "flail": "flail"}
const W_LETTER := {"laser": "Л", "shotgun": "Д", "rocket": "Р", "arc": "С", "plasma": "П", "lightning": "М", "darkmatter": "Т", "boomerang": "Б", "gravgun": "Г", "flail": "Ц"}
## английские буквы — по английским названиям оружия (TESLA, MISSILES, CRESCENT, RIPPER…)
const W_LETTER_EN := {"laser": "L", "shotgun": "S", "rocket": "M", "arc": "C", "plasma": "P", "lightning": "T", "darkmatter": "D", "boomerang": "B", "gravgun": "G", "flail": "R"}
const ARMOR_TXT := {"icebreaker": "ЛЁД"}
## Мимик: столько прочности от одного оружия — и он к нему привыкает на ADAPT_T с
const ADAPT_SHARE := 0.22
const ADAPT_T := 5.0
const HEAL_R := 150.0
const HEAL_CD := 2.2

var shells: Array = []        # снаряды Мортиры: { x0, y0, tx, ty, t, dur, R }
var heals: Array = []         # лучи Медика (только картинка): { e, o, t }
var domes: Array[En] = []     # Проекторы, Гравитоны и Связки на этом кадре
var gravs: Array[En] = []
var links: Array[En] = []
var med = null                # санитарный корабль: { t, x, y, dropped }


func reset() -> void:
	shells.clear(); heals.clear(); domes.clear(); gravs.clear(); links.clear(); med = null


## подсказка при первой встрече
func seen(e: En) -> void:
	hint(e.type, e.def.ico, e.def.name, e.def.hint)


func hint(key: String, ico: String, name_: String, text: String) -> void:
	var seen_: Array = M.s.get_or_add("foeSeen", [])
	if key in seen_: return
	seen_.append(key)
	M.soon()
	Bus.emit("toast", {"ico": ico if ico != "" else "⚠️", "title": name_.to_upper(), "text": text, "info": true, "dur": 3200})


## в JS спрайт из позднего атласа мог ещё качаться — тогда эту вещь пропускали; здесь атласы загружены сразу
func ready(name_: String) -> bool:
	return G.has(name_)


## надпись над врагом не чаще раза в полсекунды
func nope(e: En, text: String, color: String) -> void:
	if Game.t - e.nopeT < 0.5: return
	e.nopeT = Game.t
	FX.text(e.x, e.y - e.r * 0.8, text, color, 12, 0.6, -60)


func wColor(src: String) -> String:
	var w = D.WEAPONS.get(SRC_W.get(src, ""))
	return w.color if w else "#ffffff"


# ════════════════════════════════════════════════════════════
# ЗАЩИТА ОТ ОРУЖИЯ
# ════════════════════════════════════════════════════════════
## множитель урона: 0 — неуязвим, <1 — броня, >1 — уязвимость
func resist(e: En, src: String, dmg: float) -> float:
	if e.boss or src == "": return 1.0
	var d: Dictionary = e.def
	var k: float = d.resist.get(src, 1.0)
	# под куполом Проектора плазма не берёт
	if src == "plasma" and k > 0 and not domes.is_empty() and domeOf(e.x, e.y, 0) != null:
		nope(e, Lang.t("КУПОЛ"), "#7fd8ff")
		return 0.0
	if d.adapt and SRC_W.has(src):
		if e.adapt == src: k = 0.0
		else:
			e.adaptAcc[src] = e.adaptAcc.get(src, 0.0) + dmg
			if e.adaptAcc[src] >= e.maxHp * ADAPT_SHARE: adapt(e, src)
	if k <= 0:
		nope(e, Lang.t("НЕУЯЗВИМ"), wColor(src))
		e.shieldHitT = 0.1
		if U.random() < 0.2: A.play("hitArmor", {"vol": 0.4})
	elif k < 1:
		nope(e, Lang.t(ARMOR_TXT.get(e.type, "БРОНЯ")), "#bff4ff")
		if U.random() < 0.3: FX.sparks(e.x + U.rand(-0.3, 0.3) * e.w, e.y + e.h * 0.3, "#bff4ff", 3, 160)
	elif k > 1 and U.random() < 0.3:
		FX.sparks(e.x, e.y, "#e0fbff", 5, 220)
	return k


## Мимик перестраивается под оружие: неуязвим к нему ADAPT_T секунд
func adapt(e: En, src: String) -> void:
	var col := wColor(src)
	e.adapt = src; e.adaptT = ADAPT_T; e.adaptAcc = {}
	e.cv = G.tinted(e.sprite, {"hue": G.hue_of(col)})
	e.nopeT = Game.t
	FX.text(e.x, e.y - e.r * 0.8, Lang.t("ПРИВЫК: ") + D.WEAPONS[SRC_W[src]].name, col, 12, 1.1, -50)
	FX.ring(e.x, e.y, e.r, e.r * 2.2, col, 0.4, 3)
	A.play("shieldHit", {"rate": 1.3})


## невидимую цель не находят молния, ракеты и дроны
func hidden(e: En) -> bool:
	return (e.def.cloak and e.alpha < 0.6) or e.fog


## Зеркало: лазер отражается в игрока (не чаще ~3 раз в секунду, остальное просто гаснет)
func reflect(b: Bl, e: En) -> void:
	FX.hit(b.x, b.y, "#ffffff")
	nope(e, Lang.t("ОТРАЖЕНИЕ"), "#7ff6ff")
	if Game.t - e.reflT < 0.3 or not Game.player.alive: return
	e.reflT = Game.t
	Game.aimAt(b.x, b.y + e.h * 0.2, 300, "mirror")
	A.play("hitArmor", {"vol": 0.35, "rate": 1.6})


## Гравитон: ракета, влетевшая в поле, разворачивается в игрока
func bendRocket(b: Bl) -> bool:
	for g: En in gravs:
		var R := g.w * 1.25
		if U.dist2(b.x, b.y, g.x, g.y) > R * R: continue
		FX.ring(b.x, b.y, 4 * G.S, 26 * G.S, "#b06bff", 0.3, 2)
		if Game.player.alive: Game.aimAt(b.x, b.y, 210, "rocket", 0.0, {"homing": 1.1, "life": 4.0})
		nope(g, Lang.t("РАЗВОРОТ"), "#c89bff")
		A.play("teleport", {"vol": 0.35, "rate": 1.7})
		return true
	return false


## Проектор: чей купол накрывает точку
func domeOf(x: float, y: float, r: float) -> En:
	for d: En in domes:
		if U.dist2(x, y, d.x, d.y) < (d.domeR + r) * (d.domeR + r): return d
	return null


func inDome(x: float, y: float, r: float) -> bool:
	return not domes.is_empty() and domeOf(x, y, r * 0.3) != null


func domeHit(x: float, y: float) -> void:
	var d := domeOf(x, y, 20 * G.S)
	if d:
		d.domeHitT = 0.25
		nope(d, Lang.t("КУПОЛ"), "#7fd8ff")
	FX.ring(x, y, 4 * G.S, 30 * G.S, "#7fd8ff", 0.3, 3)
	A.play("shieldHit", {"vol": 0.5})


## Связка: луч гасит волну Серпа — проверяем точки дуги
func cutsWave(b: Bl, w: Dictionary) -> bool:
	if links.is_empty(): return false
	var S := G.S
	var rr := (b.r + 4 * S) * (b.r + 4 * S)
	for a: En in links:
		# напарника могли сбить в этом же кадре
		var m := a.mate
		if not a.alive or m == null or not m.alive: continue
		for i in 7:
			var ang: float = w.ang + (i / 3.0 - 1) * w.span
			var x: float = w.cx + cos(ang) * w.R
			var y: float = w.cy + sin(ang) * w.R
			if U.seg_dist2(x, y, a.x, a.y, m.x, m.y) > rr: continue
			FX.sparks(x, y, "#ff3d5a", 10, 220)
			nope(a, Lang.t("ЛУЧ ГАСИТ СЕРП"), "#ff6b7d")
			A.play("shieldHit", {"vol": 0.4, "rate": 1.4})
			return true
	return false


func spawnLink() -> float:
	var S := G.S
	var pair := {"cx": U.rand(0.35, 0.65) * G.FW, "y": -30 * S, "ty": U.rand(0.16, 0.26) * G.H, "sep": G.FW * 0.42,
		"vx": U.sign(U.random() - 0.5) * 35 * S, "t": 0.0, "st": 0, "stamp": -1.0}
	var a := E.spawn("link", {"x": pair.cx - pair.sep / 2, "y": pair.y, "noElite": true, "pair": pair, "side": -1.0})
	var b := E.spawn("link", {"x": pair.cx + pair.sep / 2, "y": pair.y, "noElite": true, "pair": pair, "side": 1.0})
	if a and b:
		a.mate = b; b.mate = a
	return 6.0  # две Связки по 3 в бюджете волны


## Улей: яйцо на стене у левого или правого края
func spawnEgg() -> En:
	var side := -1.0 if U.random() < 0.5 else 1.0
	return E.spawn("hive_egg", {"y": U.rand(0.16, 0.6) * G.H, "noElite": true, "side": side})


## санитарный корабль: если корабль ранен, иногда в начале волны пролетает сверху вниз и сбрасывает аптечку
func onWave(w: Dictionary) -> void:
	var run: Dictionary = Game.run
	var p: Pl = Game.player
	if w.boss or w.n < 4 or Game.noDrops() or p.lives >= p.maxLives or w.n - run.get("lastMed", -99) < 4 or U.random() > 0.3: return
	run.lastMed = w.n
	med = {"t": -U.rand(4, 8), "x": U.rand(0.25, 0.75) * G.FW, "y": -70 * G.S, "dropped": false}


func updateMed(dt: float) -> void:
	var m: Dictionary = med
	var S := G.S
	m.t += dt
	if m.t < 0: return
	if not ready("p_medship") or (Game.state != "play" and not m.dropped):
		if m.t > 0: med = null
		return
	if m.t < dt * 1.5: hint("medship", "🚑", Lang.t("Санитарный корабль"), Lang.t("Свои! Сбрасывает аптечку, когда вы ранены"))
	m.y += 150 * S * dt
	if not m.dropped and m.y >= G.H * 0.3:
		m.dropped = true
		Game.dropPowerup(m.x, m.y + 20 * S, "heal")
		FX.text(m.x, m.y + 40 * S, Lang.t("АПТЕЧКА!"), "#ff6b6b", 14, 1.0, -40)
		A.play("powerup", {"rate": 1.2, "vol": 0.6})
	if m.y > G.H + 90 * S: med = null


# ════════════════════════════════════════════════════════════
# ГИБЕЛЬ
# ════════════════════════════════════════════════════════════
func onKill(e: En) -> void:
	if e.def.prop: Sectors.onKill(e)
	# Вор возвращает добычу, кредиты — вдвойне
	if not e.loot.is_empty():
		var coins := 0.0
		for l: Dictionary in e.loot:
			if l.kind == "coin": coins += l.val * 2
			elif l.kind == "pu": Game.dropPowerup(e.x, e.y, l.pu)
			elif l.kind == "en": Game.dropEnergy(e.x, e.y, 1)
			elif l.kind == "crate": Game.dropCrate(e.x, e.y, l.val)
		if coins: Game.dropCoins(e.x, e.y, int(coins))
		FX.text(e.x, e.y - e.r, Lang.t("ДОБЫЧА ВОЗВРАЩЕНА"), "#ffc83d", 13, 1.0, -50)
		e.loot.clear()
	# грузовик Конвоя роняет ящики
	if e.type == "cargo":
		var n := 2 + (1 if Game.threatWave() >= 15 else 0)
		for i in n: Game.dropCrate(e.x + (i - (n - 1) / 2.0) * 26 * G.S, e.y)
		FX.text(e.x, e.y - e.r, Lang.t("ЯЩИКИ!"), "#ffc83d", 15, 1.0, -50)
	# напарник Связки в ярости — стреляет вдвое чаще
	if e.mate != null and e.mate.alive:
		e.mate.rage = true
		e.mate.mate = null
		FX.text(e.mate.x, e.mate.y - e.mate.r, Lang.t("ЯРОСТЬ"), "#ff3d5a", 13, 0.9, -50)


# ════════════════════════════════════════════════════════════
# ПОВЕДЕНИЕ
# ════════════════════════════════════════════════════════════
func has_init(ai: String) -> bool:
	return has_method("_init_" + ai)


func init_ai(e: En, o: Dictionary) -> void:
	call("_init_" + e.ai, e, o)


func hasAI(ai: String) -> bool:
	return has_method("_ai_" + ai)


func runAI(ai: String, e: En, dt: float) -> void:
	call("_ai_" + ai, e, dt)


## яйцо прилеплено к стене у края экрана: у правого края рисуется зеркально (horiz + vx < 0)
func _init_egg(e: En, o: Dictionary) -> void:
	e.side = o.get("side", -1.0)
	e.horiz = true; e.vx = -1e-6 if e.side > 0 else 1e-6
	e.x = e.w * 0.5 if e.side < 0 else G.FW - e.w * 0.5
	e.grow = U.rand(5.5, 7) / pow(E.fireRate(), 0.3)
	e.stage = 1; e.alpha = 0.0


func _init_cargo(e: En, _o: Dictionary) -> void:
	e.ty = U.rand(0.16, 0.3) * G.H; e.stay = U.rand(11, 13)


func _init_thief(e: En, _o: Dictionary) -> void:
	e.ty = U.rand(0.12, 0.28) * G.H; e.loot = []; e.idle = 0.0; e.prey = null; e.vy = 0.0


func _init_link(e: En, o: Dictionary) -> void:
	e.pair = o.get("pair"); e.side = o.get("side", 1.0)


## Вор: охотится за выпавшими бонусами, энергоблоками и кредитами, с добычей уходит вверх
func findLoot(e: En) -> Pk:
	var best: Pk = null
	var bd := INF
	for it: Pk in Game.pickups:
		if it.dead or it.pull or it.kind == "xp" or it.y < 0 or it.y > G.H * 0.62: continue
		var d := U.dist2(it.x, it.y, e.x, e.y) * (1.5 if it.kind == "coin" else 1.0)
		if d < bd:
			bd = d; best = it
	return best


func grab(e: En, it: Pk) -> void:
	it.dead = true
	e.loot.append({"kind": it.kind, "val": it.val, "pu": it.pu})
	e.prey = null
	FX.sparks(it.x, it.y, "#ffc83d", 8, 160)
	nope(e, Lang.t("УКРАЛ!"), "#ffc83d")
	A.play("coin", {"rate": 0.7, "vol": 0.6})


func eggSprite(e: En, n: int) -> void:
	e.sprite = "hive_egg" + str(n)
	e.h = e.w * G.aspect(e.sprite)
	e.cv = null


## яйцо Улья: зреет, трескается и выпускает личинок, которые ползут к кораблю
func _ai_egg(e: En, dt: float) -> void:
	e.t += dt
	var st := 1 if e.t < e.grow * 0.55 else (2 if e.t < e.grow else 3)
	if st != e.stage:
		e.stage = st
		eggSprite(e, st)
		if st == 2:
			FX.sparks(e.x, e.y, "#a6ff3d", 8, 140); A.play("mine", {"rate": 0.6, "vol": 0.4})
		if st == 3:
			e.hittable = false; e.leaving = true
			E.brood(e.x - e.side * e.w * 0.1, e.y, 2 + (1 if Game.threatWave() >= 20 else 0), true, 16)
			FX.explode(e.x, e.y, 0.7, "#a6ff3d")
			A.play("teleport", {"rate": 0.6, "vol": 0.5})
	# скорлупа после вылупления тает
	if st == 3:
		if e.t > e.grow + 0.8:
			e.alpha -= dt * 1.2
			if e.alpha <= 0: e.alive = false
	else:
		e.alpha = minf(1, e.alpha + dt * 2)


## грузовик Конвоя: встаёт наверху, ходит из стороны в сторону и через ~12 с уходит с грузом
func _ai_cargo(e: En, dt: float) -> void:
	var S := G.S
	if e.st == 0:
		if E.arrive(e, dt, 1.2):
			e.st = 1; e.vx = U.sign(U.random() - 0.5) * e.spd * 0.6
	elif e.st == 1:
		e.t += dt
		E.strafe(e, dt, 0.6)
		e.y = e.ty + sin(e.age * 0.9) * 6 * S
		if e.t > e.stay:
			e.st = 2; e.leaving = true; nope(e, Lang.t("УШЁЛ С ГРУЗОМ"), "#ffc83d"); A.play("rail", {"vol": 0.3, "rate": 0.8})
	else:
		e.vy = maxf(e.vy - 500 * S * dt, -e.spd * 5)
		e.y += e.vy * dt
		if e.y < -e.h: e.alive = false


func _ai_thief(e: En, dt: float) -> void:
	var S := G.S
	if e.st == 0:
		if E.arrive(e, dt, 2.6): e.st = 1
	elif e.st == 1:
		e.t += dt
		if e.prey == null or e.prey.dead or e.prey.pull: e.prey = findLoot(e)
		var it := e.prey
		if it:
			e.idle = 0.0
			var dx := it.x - e.x
			var dy := it.y - e.y
			var d := sqrt(dx * dx + dy * dy)
			if d == 0.0: d = 1.0
			var sp := e.spd * 1.5
			e.vx = U.damp(e.vx, dx / d * sp, 4, dt); e.vy = U.damp(e.vy, dy / d * sp, 4, dt)
			if d < e.r + 12 * S: grab(e, it)
		else:
			# красть нечего — кружит наверху и ждёт
			e.idle += dt
			e.vx = U.damp(e.vx, sin(e.age * 1.1 + e.phase) * e.spd * 0.8, 2, dt)
			e.vy = U.damp(e.vy, (e.ty - e.y) * 2, 2, dt)
		e.x = U.clamp(e.x + e.vx * dt, e.w * 0.5, G.FW - e.w * 0.5)
		e.y = U.clamp(e.y + e.vy * dt, E.minY(e), G.H * 0.62)
		if e.loot.size() >= 3 or e.idle > 7 or e.t > 16:
			e.st = 2; e.leaving = true
	else:
		# уходит вверх с добычей — ещё можно догнать
		e.vy = maxf(e.vy - 900 * S * dt, -e.spd * 2.6)
		e.y += e.vy * dt
		if e.y < -e.h: e.alive = false


## Связка: пара держится на одной высоте, медленно сползает вниз, луч между кораблями обжигает
func _ai_link(e: En, dt: float) -> void:
	var pr = e.pair
	var S := G.S
	if pr == null:
		E.leave(e, dt)
		return
	# общий центр пары двигает тот, кто обновляется первым в кадре
	if pr.stamp != Game.t:
		pr.stamp = Game.t
		pr.t += dt
		if pr.st == 0:
			pr.y = U.damp(pr.y, pr.ty, 1.8, dt) + 8 * S * dt
			if pr.y >= pr.ty - 6 * S: pr.st = 1
		elif pr.st == 1:
			pr.y += 8 * S * dt
			if pr.t > 17 or pr.y > G.H * 0.5: pr.st = 2
		else:
			pr.y += 55 * S * dt
		pr.sep = G.FW * (0.42 + 0.1 * sin(pr.t * 0.8))
		var half: float = pr.sep / 2 + e.w * 0.6
		pr.cx += pr.vx * dt
		if pr.cx < half or pr.cx > G.FW - half:
			pr.vx = -pr.vx; pr.cx = U.clamp(pr.cx, half, G.FW - half)
	e.x = pr.cx + e.side * pr.sep / 2
	e.y = pr.y + e.side * sin(pr.t * 1.3) * 12 * S
	if pr.st == 2: e.leaving = true
	if pr.st >= 1: E.tickFire(e, dt * 2 if e.rage else dt)


## Мортира: снаряд навесом в точку игрока — сначала красный круг, через 1,35 с взрыв
func _fire_lob(e: En, _f := {}, _mx := 0.0, _my := 0.0) -> void:
	var S := G.S
	var p: Pl = Game.player
	var n := 2 if Game.threatWave() >= 18 else 1
	for i in n:
		var tx: float = p.x + U.pick([-1.0, 1.0]) * U.rand(70, 120) * S if i else p.x + p.vxm * 0.5
		shells.append({"x0": e.x, "y0": e.y + e.h * 0.35, "tx": U.clamp(tx, 20 * S, G.FW - 20 * S), "ty": U.clamp(p.y + U.rand(-16, 16) * S, G.H * 0.3, G.H - 24 * S),
			"t": 0.0, "dur": 1.35, "R": 40 * S * (1.15 if e.elite else 1.0)})
	FX.glow_puff(e.x, e.y + e.h * 0.35, "#ff8a3d", 40 * S, 0.25)


## Медик: раз в HEAL_CD с лечит раненых соседей
func heal(e: En) -> void:
	var S := G.S
	var R := HEAL_R * S
	var share: float = e.def.heal * (1.3 if e.elite else 1.0)
	var n := 0
	for o: En in Game.enemies:
		if o == e or not o.alive or o.boss or o.def.prop or o.hp >= o.maxHp or U.dist2(o.x, o.y, e.x, e.y) > R * R: continue
		o.hp = minf(o.maxHp, o.hp + o.maxHp * share * (0.25 if o.mini else 1.0))
		heals.append({"e": e, "o": o, "t": 0.0})
		FX.text(o.x, o.y - o.r * 0.6, "+", "#5cff9d", 16, 0.6, -50)
		n += 1
	if n:
		FX.ring(e.x, e.y, e.r, R, "#5cff9d", 0.5, 2); A.play("powerup", {"vol": 0.25, "rate": 1.9})


## Невидимка: почти прозрачна; на миг проявляется, даёт очередь и снова исчезает
func cloak(e: En, dt: float) -> void:
	# Godot: попадание сбивает маскировку — корабль проявляется (и его видят ракеты и молния)
	if e.revealT > 0:
		e.revealT -= dt
		e.alpha = minf(0.8, e.alpha + dt * 8)
		return
	if e.st != 1:
		e.alpha = maxf(0.12, e.alpha - dt * 3)
		return
	if e.shown > 0:
		e.shown -= dt
		e.alpha = minf(1, e.alpha + dt * 5)
		if not e.shot and e.alpha >= 0.95:
			e.shot = true
			if E.canShoot(e): E.doFire(e, e.def.fire)
		if e.shown <= 0: e.cloakT = U.rand(2.2, 3.2) / pow(E.fireRate(), 0.5)
	else:
		e.alpha = maxf(0.12, e.alpha - dt * 3)
		e.cloakT = (U.rand(1, 1.8) if is_nan(e.cloakT) else e.cloakT) - dt
		if e.cloakT <= 0:
			e.shown = 1.1; e.shot = false; A.play("teleport", {"vol": 0.25, "rate": 1.8})


# ════════════════════════════════════════════════════════════
# ОБНОВЛЕНИЕ
# ════════════════════════════════════════════════════════════
func update(dt: float) -> void:
	var S := G.S
	var p: Pl = Game.player
	domes.clear(); gravs.clear(); links.clear()
	for e: En in Game.enemies:
		if not e.alive or e.boss: continue
		var d: Dictionary = e.def
		if d.dome:
			e.domeR = U.damp(e.domeR, d.dome * S * (1.2 if e.elite else 1.0) if e.st == 1 else 0.0, 3, dt)
			if e.domeHitT > 0: e.domeHitT -= dt
			if e.domeR > 8 * S: domes.append(e)
		if d.gravity: gravs.append(e)
		if e.side < 0 and e.mate != null and e.mate.alive: links.append(e)
		if d.heal and e.st == 1:
			e.healT = (1.5 if is_nan(e.healT) else e.healT) - dt
			if e.healT <= 0:
				e.healT = HEAL_CD; heal(e)
		if d.cloak: cloak(e, dt)
		if e.adapt != "":
			e.adaptT -= dt
			if e.adaptT <= 0:
				e.adapt = ""; e.cv = null
	# луч Связки обжигает корабль
	if p.alive:
		for a: En in links:
			if U.seg_dist2(p.x, p.y, a.x, a.y, a.mate.x, a.mate.y) < (p.r + 3 * S) * (p.r + 3 * S): Game.hitPlayer(p.x, p.y, Lang.t("Луч Связки"))
	# снаряды Мортиры
	for i in range(shells.size() - 1, -1, -1):
		var s: Dictionary = shells[i]
		s.t += dt
		if s.t < s.dur: continue
		shells.remove_at(i)
		FX.explode(s.tx, s.ty, 0.9, "#ff8a3d")
		FX.ring(s.tx, s.ty, 6 * S, s.R, "#ffb03d", 0.3, 3)
		FX.shake(0.08)
		A.play("explodeS", {"vol": 0.6})
		if p.alive and U.dist2(p.x, p.y, s.tx, s.ty) < (s.R + p.r * 0.5) * (s.R + p.r * 0.5): Game.hitPlayer(p.x, p.y, Lang.t("Снаряд Мортиры"))
		if Game.threatWave() >= 22 and p.alive:
			var sp := Game.bspd(120)
			var off := U.random() * TAU
			for k in 6:
				var a := off + k / 6.0 * TAU
				Game.ebullet(s.tx, s.ty, cos(a) * sp, sin(a) * sp, "orb")
	for i in range(heals.size() - 1, -1, -1):
		heals[i].t += dt
		if heals[i].t > 0.45: heals.remove_at(i)
	if med != null: updateMed(dt)


# ════════════════════════════════════════════════════════════
# ОТРИСОВКА
# ════════════════════════════════════════════════════════════
## под врагами: купола, поля Гравитонов, лучи Связок и Медиков, прицелы Мортир
func drawBack(ctx: Ctx) -> void:
	var S := G.S
	var t := Game.t
	ctx.additive = true
	for e: En in domes:
		var r := e.domeR
		var hit := e.domeHitT > 0
		ctx.alpha = 0.22 + (0.3 if hit else 0.0)
		if G.has("fx_sh_bubble"): G.draw(ctx, "fx_sh_bubble", e.x, e.y, r * 2.25)
		else: ctx.draw_tex(G.soft("#4cb8ff", 64), e.x - r * 1.1, e.y - r * 1.1, r * 2.2, r * 2.2)
		ctx.alpha = 0.4 + 0.15 * sin(t * 4) + (0.4 if hit else 0.0)
		ctx.stroke = Color.WHITE if hit else U.col("#7fd8ff"); ctx.line_width = 1.5 * S
		ctx.begin_path(); ctx.arc(e.x, e.y, r, 0, TAU); ctx.stroke_path()
	for g: En in gravs:
		var R := g.w * 1.25
		Post.lens(g.x, g.y, R * 0.9, 0.4)
		ctx.alpha = 0.16
		ctx.draw_tex(G.soft("#7a3dff", 64), g.x - R, g.y - R, R * 2, R * 2)
		ctx.alpha = 0.35; ctx.stroke = U.col("#c89bff"); ctx.line_width = 1.5 * S
		for k in 2:
			var a := t * (-1.6 if k else 2.2) + k
			ctx.begin_path(); ctx.arc(g.x, g.y, R * (0.82 if k else 1.0), a, a + 2.2); ctx.stroke_path()
	for a: En in links:
		if not a.alive or a.mate == null or not a.mate.alive: continue
		var m := a.mate
		var dx := m.x - a.x
		var dy := m.y - a.y
		var len := sqrt(dx * dx + dy * dy)
		if len == 0.0: len = 1.0
		var nx := -dy / len
		var ny := dx / len
		ctx.alpha = 0.3 + 0.12 * sin(t * 18)
		ctx.stroke = U.col("#ff2d4d"); ctx.line_width = 8 * S
		ctx.stroke_line(a.x, a.y, m.x, m.y)
		# ядро луча вьётся синусоидой, как на рисунке; красное — обычным смешиванием, иначе на синем небе выходит розовым
		ctx.additive = false
		ctx.alpha = 1.0
		for cl in [["#ff2d4d", 2.6], ["#ffc2ca", 1.0]]:
			ctx.stroke = U.col(cl[0]); ctx.line_width = cl[1] * S
			ctx.begin_path()
			for i in 25:
				var k := i / 24.0
				var o := sin(k * 22 - t * 14) * 3 * S * sin(k * PI)
				var x := a.x + dx * k + nx * o
				var y := a.y + dy * k + ny * o
				if i: ctx.line_to(x, y)
				else: ctx.move_to(x, y)
			ctx.stroke_path()
		ctx.additive = true
	# санитарный корабль — свой: под врагами, с зелёным ореолом
	var md = med
	if md != null and md.t >= 0:
		var w := 46 * S
		ctx.alpha = 0.35 + 0.1 * sin(t * 6)
		ctx.draw_tex(G.soft("#5cff9d", 64), md.x - w, md.y - w, w * 2, w * 2)
		ctx.additive = false
		ctx.alpha = 1.0
		G.draw(ctx, "p_medship", md.x, md.y, w, PI)
		ctx.additive = true
	# яйцо Улья светится, когда вот-вот вылупится
	for e: En in Game.enemies:
		if not e.alive or e.type != "hive_egg" or e.stage != 2: continue
		var gs := e.w * (1.5 + 0.2 * sin(t * 12))
		ctx.alpha = 0.3 + 0.25 * absf(sin(t * 8))
		ctx.draw_tex(G.soft("#a6ff3d", 64), e.x - gs / 2, e.y - gs / 2, gs, gs)
	for hb: Dictionary in heals:
		var k: float = 1 - hb.t / 0.45
		ctx.alpha = 0.8 * k; ctx.stroke = U.col("#5cff9d"); ctx.line_width = 3 * S * k + 1
		ctx.stroke_line(hb.e.x, hb.e.y, hb.o.x, hb.o.y)
	# прицел Мортиры — обычным смешиванием: в режиме сложения красный на синем небе выходил лиловым
	ctx.additive = false
	for s: Dictionary in shells:
		var k: float = s.t / s.dur
		ctx.alpha = 0.16 + 0.14 * k
		ctx.fill = U.col("#ff2d2d")
		ctx.fill_circle(s.tx, s.ty, s.R * k)
		ctx.alpha = 0.6 + 0.35 * absf(sin(t * (8 + k * 10)))
		ctx.stroke = U.col("#ff4d3d"); ctx.line_width = 2 * S
		ctx.begin_path(); ctx.arc(s.tx, s.ty, s.R, 0, TAU); ctx.stroke_path()
	ctx.alpha = 1.0


## над врагами: снаряды Мортиры в полёте, следы Невидимок, значки защиты
func drawFront(ctx: Ctx) -> void:
	var S := G.S
	var t := Game.t
	ctx.additive = true
	for s: Dictionary in shells:
		var k: float = s.t / s.dur
		var arc := sin(k * PI)
		var x := U.lerp(s.x0, s.tx, k)
		var y := U.lerp(s.y0, s.ty, k) - arc * 150 * S
		G.draw(ctx, "eb_fire", x, y, (16 + arc * 14) * S, t * 6)
	for e: En in Game.enemies:
		if not e.alive or not e.def.cloak or e.alpha > 0.5: continue
		# марево от двигателей — заметно, если присмотреться
		ctx.alpha = 0.18 + 0.1 * sin(t * 7 + e.uid)
		var gs := e.w * 0.9
		ctx.draw_tex(G.soft("#6b7bff", 64), e.x - gs / 2, e.y - e.h * 0.35 - gs / 2, gs, gs)
	ctx.additive = false
	# грузовик Конвоя: сколько ещё ждёт, прежде чем уйти с грузом
	for e: En in Game.enemies:
		if not e.alive or e.type != "cargo" or e.st != 1: continue
		var k := maxf(0, 1 - e.t / e.stay)
		var bw := e.w * 0.7
		var x := e.x - bw / 2
		var y := e.y + e.h * 0.55
		ctx.alpha = 0.9
		ctx.fill = Color(0, 0, 0, 0.55); ctx.fill_rect(x - 1, y - 1, bw + 2, 4 * S + 2)
		ctx.fill = U.col("#ff5c4d" if k < 0.3 else "#ffc83d"); ctx.fill_rect(x, y, bw * k, 4 * S)
	ctx.alpha = 1.0
	# значок: буква оружия в его цвете, перечёркнутая
	var fs := int(round(8 * S))
	for e: En in Game.enemies:
		if not e.alive or e.boss or e.alpha < 0.5: continue
		var wid: String = SRC_W.get(e.adapt, "") if e.adapt != "" else e.def.guard
		if wid == "": continue
		var col: String = D.WEAPONS[wid].color
		var r := 7 * S
		var x := e.x + e.w * 0.5
		var y := e.y - e.h * 0.3
		ctx.alpha = e.alpha * 0.92
		ctx.fill = Color(4 / 255.0, 8 / 255.0, 20 / 255.0, 0.8)
		ctx.fill_circle(x, y, r)
		ctx.stroke = U.col(col); ctx.line_width = 1.5 * S
		ctx.begin_path(); ctx.arc(x, y, r, 0, TAU); ctx.stroke_path()
		# y в fill_text — базовая линия: середина строки ≈ +0.36 кегля
		ctx.fill = U.col(col); ctx.fill_text((W_LETTER_EN if Lang.is_en() else W_LETTER)[wid], x, y + 0.5 * S + fs * 0.36, fs, 1)
		ctx.stroke = U.col("#ff3d5a"); ctx.line_width = 1.5 * S
		ctx.stroke_line(x - r * 0.7, y + r * 0.7, x + r * 0.7, y - r * 0.7)
	ctx.alpha = 1.0
