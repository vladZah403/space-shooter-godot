extends Node
## Боссы (автозагрузка B) — перенос второй части enemies.js: появление, атаки 13 боссов по фазам,
## движение, смена фаз, подстройка прочности под огневую мощь (4.3.2), гибель и отрисовка.
## Имена функций — как в JS (BOSS.guardian → _boss_guardian), чтобы их было легко сверять.

## движение по фазам: sway — качается по ширине, chase — держится над кораблём, low — опускается ниже и качается быстрее,
## hold — почти на месте в центре, blink — качается и время от времени телепортируется
const BOSS_MOVES := {
	"guardian": ["sway", "chase", "low"], "sniper": ["sway", "blink", "blink"], "kraken": ["sway", "hold", "low"],
	"phoenix": ["sway", "chase", "low"], "spider": ["hold", "chase", "hold"], "dreadnought": ["sway", "chase", "low"],
	"inquisitor": ["sway", "chase", "hold"], "queen": ["sway", "hold", "low"], "necro": ["sway", "blink", "blink"],
	"mothership": ["sway", "sway", "low"], "chaos": ["sway", "sway", "sway"], "cruiser": ["sway", "sway", "chase"], "overlord": ["hold", "sway", "low"],
}

# ── 3.1: смена фазы ──
const PHASE_HP := [2.0 / 3.0, 1.0 / 3.0]   # пороги прочности 2-й и 3-й фаз
const PHASE_T := 2.2                       # перестройка между фазами, с (босс неуязвим и не стреляет)

var _def_proto := {}


## «запись врага» босса: все поля обычного врага пустые (в JS у босса def был { coins, xp, score },
## остальное — undefined; здесь обращение к отсутствующему полю — ошибка)
func bossEnemyDef() -> Dictionary:
	if _def_proto.is_empty():
		for k in D.ENEMIES.scout:
			_def_proto[k] = D._empty_like(D.ENEMIES.scout[k])
		_def_proto.rot = 0.0
	return _def_proto.duplicate(true)


# ════════════════════════════════════════════════════════════
# ПОЯВЛЕНИЕ
# ════════════════════════════════════════════════════════════
func spawnBoss(n: int) -> void:
	var num := maxi(1, roundi(n / 5.0))
	var bdef: Dictionary = Game.bossDef(num)
	var cycle := int(floor((num - 1) / float(D.BOSSES.size())))
	var S := G.S
	# в JS свой спрайт босса лежал в позднем атласе и мог ещё качаться — босс ждал или выходил в облике Стража
	# своего цвета. Здесь все атласы загружены сразу, облик Стража — только если кадра нет вовсе
	var sprite: String = bdef.sprite
	var hue = bdef.get("hue")
	var fallback := false
	if not G.has(sprite):
		sprite = "boss"; hue = G.hue_of(bdef.color); fallback = true
	# прочность растёт вместе с прочностью обычных врагов; первые два босса — разминка
	var ramp := 0.92 if num == 1 else (1.6 if num == 2 else 2 + (num - 3) * 0.2)
	# в босс-раше улучшений за мелочь почти нет — боссы там слабее
	var baseHp: float = 1000 * bdef.hp * E.hpScale() * ramp * (1 + cycle * 0.3) * (D.BOSS_HP_FIRST if num == 1 else D.BOSS_HP) \
		* (0.55 if Game.mode == "rush" else 1.0)
	# 4.3.2: у сильной сборки — не меньше, чем нужно на минимальный бой при её уроне по прошлому боссу (adapt);
	# до первого босса урона ещё не знаем — запас по «Боевой мощи» (run.bossK). У новичка всё как раньше
	var run = Game.run
	var bossDps: float = run.get("bossDps", 0.0) if run else 0.0
	var bossK: float = run.get("bossK", 0.0) if run else 0.0
	var hp := minf(baseHp * D.BOSS_ADAPT.max, maxf(baseHp * (1.0 if bossDps > 0 else (bossK if bossK > 0 else 1.0)), bossDps * phaseMin(num) * 3))
	var w := minf(G.FW * bdef.wf, bdef.wmax * S)
	var asp := G.aspect(sprite)
	var h := w * asp
	var b := En.new()
	b.uid = E.uid; E.uid += 1
	b.type = "boss"; b.def = bossEnemyDef(); b.bdef = bdef; b.sprite = sprite; b.fallback = fallback
	b.boss = true; b.mini = false; b.alive = true; b.hittable = true; b.entering = true
	b.x = G.FW / 2; b.y = -h * 0.6; b.w = w; b.h = h; b.r = w * 0.37; b.rx = 0.0; b.ry = 0.0
	b.hp = hp; b.maxHp = hp; b.baseHp = baseHp; b.phase = 1; b.vt = 0.0; b.age = 0.0; b.mt = 0.0
	b.flash = 0.0; b.frozen = 0.0; b.alpha = 1.0; b.bank = 0.0; b.face = -1.0; b.lastX = G.FW / 2
	b.shield = hp * bdef.shield * 0.4 if bdef.shield else 0.0
	b.shieldMax = b.shield
	b.fx = 1.0
	b.cv = G.tinted(sprite, {"hue": hue}) if hue != null else null
	# корпус целиком ниже полосы босса, но не ниже середины экрана
	b.baseY = maxf(G.H * 0.2, minf(Hud.top_inset() + h * 0.5 + 4 * S, G.H * 0.52 - h * 0.5))
	b.reborn = false; b.cycle = cycle; b.num = num
	b.pt = {}; b.orbs = []; b.spin = 0.0; b.aim2 = null; b.dive = null; b.dash = null; b.vuln = 0.0; b.trans = 0.0; b.rage = false
	E.setHitbox(b, sprite)
	if bdef.id == "phoenix":
		for i in 3: b.orbs.append({"a": i / 3.0 * TAU})
	Game.boss = b
	Game.enemies.append(b)
	Game.run.bossDamaged = false
	FX.sprite("fx_warp", G.FW / 2, Hud.top_inset() + 50 * S, {"w0": 120 * S, "w1": 230 * S, "dur": 1.5, "hold": 0.45, "fadeIn": 0.15, "alpha": 0.8, "hue": G.hue_of(bdef.color)})
	# Godot: лёгкий наезд камеры туда, где босс встанет, — пока он выходит из варпа
	Game.camFocus(G.FW / 2, b.baseY, 1.06, 1.0)
	# в кат-сцене рёв и тряска — вместе с карточкой имени (Game.sceneName)
	if Game.state != "cutscene":
		A.play("bossRoar"); FX.shake(0.4)
	Bus.emit("bossSpawn", b)
	Bus.emit("intensity")


# ════════════════════════════════════════════════════════════
# ПОМОЩНИКИ АТАК
# ════════════════════════════════════════════════════════════
## перезарядка атаки: быстрее со сложностью, фазой, яростью и кругом боссов; первый босс — мягче
func bcd(b: En, base: float) -> float:
	return base / pow(Game.diff.fire, 0.55) / (1 + (b.phase - 1 + (1 if b.rage else 0)) * 0.18) / (1 + b.cycle * 0.12) * (1.3 if b.num == 1 else 1.0)


## таймер атаки key: true раз в period (первый раз — через first или случайную долю периода)
func timer(b: En, key: String, period: float, first := NAN) -> bool:
	if not b.pt.has(key): b.pt[key] = first if not is_nan(first) else period * U.rand(0.4, 0.9)
	b.pt[key] -= b._dt
	if b.pt[key] <= 0:
		b.pt[key] += period
		return true
	return false


func ring(x: float, y: float, n: int, spd: float, type: String, off := 0.0) -> void:
	var s := Game.bspd(spd)
	for i in n:
		var a := off + float(i) / n * TAU
		Game.ebullet(x, y, cos(a) * s, sin(a) * s, type)


func fan(x: float, y: float, n: int, spread: float, spd: float, type: String, base := NAN) -> void:
	var p: Pl = Game.player
	var b0 := base if not is_nan(base) else atan2(p.y - y, p.x - x)
	var s := Game.bspd(spd)
	for i in n:
		var a := b0 + (0.0 if n == 1 else (float(i) / (n - 1) - 0.5) * spread)
		Game.ebullet(x, y, cos(a) * s, sin(a) * s, type)


## перья: разлетаются веером, замирают и бросаются в игрока
func feathers(x: float, y: float, n: int, dir: float, spd := 150.0) -> void:
	var s := Game.bspd(spd)
	for i in n:
		var a := PI / 2 + dir * (0.35 + i * 0.22)
		Game.ebullet(x, y, cos(a) * s, sin(a) * s, "feather", {"redir": 0.65 + i * 0.05, "redirSpd": Game.bspd(280), "life": 6.0})


## атаки Хаоса выбираются случайно (CHAOS_MOVES в JS)
const CHAOS_MOVES := 5


func chaosMove(b: En, i: int) -> void:
	var S := G.S
	match i:
		0:  # шрапнель с рикошетом
			for k in 14:
				var a := PI / 2 + U.rand(-1.2, 1.2)
				var s := Game.bspd(U.rand(140, 230))
				Game.ebullet(b.x + U.rand(-0.3, 0.3) * b.w, b.y + b.h * 0.2, cos(a) * s, sin(a) * s, "junk", {"bounce": 1})
			A.play("explodeS", {"vol": 0.6})
		1:
			ring(b.x, b.y, 12, 150, "junk", U.random())
			A.play("enemyShot")
		2:
			for sd in [-1.0, 0.0, 1.0]:
				var s := Game.bspd(120)
				Game.ebullet(b.x + sd * b.w * 0.3, b.y + b.h * 0.2, sd * s * 0.5, s, "fire", {"homing": 1.1, "life": 5.0})
			A.play("rocket", {"rate": 0.8})
		3:
			Game.laser({"owner": b, "ox": 0.0, "oy": 0.05, "ang": PI / 2 + U.rand(-0.7, 0.7), "spin": U.rand(0.35, 0.6) * U.sign(U.random() - 0.5),
				"warn": 0.7, "dur": 1.0, "w": 12 * S, "color": "#ff7a2a"})
			A.play("railCharge", {"vol": 0.4, "rate": 1.5})
		_:
			for k in 2:
				E.spawn("scout", {"x": U.clamp(b.x + (1 if k else -1) * b.w * 0.4, 20 * S, G.FW - 20 * S), "y": b.y, "tint": 25.0, "hpMul": 0.7, "noElite": true})


# ════════════════════════════════════════════════════════════
# АТАКИ БОССОВ
# 3.1: у каждого босса три фазы со своим набором атак, а не «старые плюс новая»:
# 1-я — визитная карточка, 2-я — другая тактика, 3-я — самые опасные атаки вместе.
# Как босс двигается в каждой фазе — BOSS_MOVES (updateBoss)
# ════════════════════════════════════════════════════════════
## Страж: веер → кольца и спаренные пушки → огненный дождь и луч-развёртка
func _boss_guardian(b: En) -> void:
	var intro := b.num == 1
	var ph := int(b.phase)
	var S := G.S
	if ph == 1 and timer(b, "fan", bcd(b, 1.7), 1):
		fan(b.x, b.y + b.h * 0.35, 4 if intro else 6, 0.95, 210, "bolt"); A.play("enemyShot")
	if ph == 2:
		if timer(b, "ring", bcd(b, 2.4), 0.8):
			b.spin += 0.3; ring(b.x, b.y, 10 if intro else 14, 150, "orb", b.spin)
		if timer(b, "twin", bcd(b, 1.3), 1.5):
			for sd in [-1.0, 1.0]: Game.aimAt(b.x + sd * b.w * 0.4, b.y + b.h * 0.2, 240, "bolt")
			A.play("enemyShot")
	if ph >= 3:
		if timer(b, "fan", bcd(b, 2.2), 1):
			fan(b.x, b.y + b.h * 0.35, 5 if intro else 7, 1.1, 210, "bolt"); A.play("enemyShot")
		if timer(b, "rain", bcd(b, 1.6 if intro else 1.1)):
			for i in (2 if intro else 3): Game.ebullet(U.rand(0.05, 0.95) * G.FW, -10, 0, Game.bspd(170), "fire")
		if timer(b, "sweep", bcd(b, 9 if intro else 7), 3):
			var sd: float = U.pick([-1.0, 1.0])
			Game.laser({"owner": b, "ox": 0.0, "oy": 0.1, "ang": PI / 2 - sd * 1.0, "spin": sd * 0.55, "warn": 0.9, "dur": 2.2, "w": 12 * S, "color": "#ff3d5a"})
			A.play("railCharge", {"vol": 0.45})


## Снайпер: спаренные прицельные → засада из игл и веер, телепорты → тройные выстрелы и рельсотрон
func _boss_sniper(b: En) -> void:
	var ph := int(b.phase)
	var S := G.S
	var p: Pl = Game.player
	if ph != 2 and b.aim2 == null and timer(b, "snipe", bcd(b, 2.1 if ph >= 3 else 2.4), 1.2): b.aim2 = {"t": 0.95, "ang": []}
	if b.aim2 != null:
		p.lockT = 2.5
		if b.aim2.t <= 0.22: p.lockHot = 0.35
		b.aim2.t -= b._dt
		if b.aim2.t > 0.22:
			b.aim2.ang = [-1.0, 1.0].map(func(sd: float) -> float: return atan2(p.y - (b.y + b.h * 0.2), p.x - (b.x + sd * b.w * 0.32)))
		if b.aim2.t <= 0:
			var n := 3 if ph >= 3 else 1
			for i in 2:
				var sd := -1.0 if i == 0 else 1.0
				for k in n:
					var a: float = b.aim2.ang[i] + (k - (n - 1) / 2.0) * 0.1
					var s := Game.bspd(560)
					Game.ebullet(b.x + sd * b.w * 0.32, b.y + b.h * 0.2, cos(a) * s, sin(a) * s, "long")
			A.play("laser", {"rate": 0.5})
			b.aim2 = null
	if ph == 2:
		if timer(b, "sweep", bcd(b, 2.6), 0.8): fan(b.x, b.y + b.h * 0.3, 9, 1.7, 170, "orb", PI / 2)
		# засада: иглы разлетаются веером, замирают и бьют в корабль
		if timer(b, "trap", bcd(b, 3.4), 1.8):
			var s := Game.bspd(160)
			for i in 6:
				var a := PI / 2 + (i - 2.5) * 0.45
				Game.ebullet(b.x, b.y + b.h * 0.2, cos(a) * s, sin(a) * s, "long", {"redir": 0.75, "redirSpd": Game.bspd(330), "life": 6.0})
			A.play("enemyShot", {"rate": 0.8})
	# рельсотрон: луч по колонне игрока
	if ph >= 3 and timer(b, "rail", bcd(b, 4.2), 2):
		E.beam(p.x, b.y + b.h * 0.4, 16 * S, 0.9, 0.45, "#ff9f3d", b); A.play("railCharge", {"vol": 0.45})


## Кракен: завесы щупалец и чернила → вихри и хватка (рывок к кораблю) → завесы быстрее, вихри и выводок
func _boss_kraken(b: En) -> void:
	var S := G.S
	var ph := int(b.phase)
	var active := fmod(b.age, 4.6) < 3
	if ph != 2 and active and timer(b, "tent", 0.15 if ph >= 3 else 0.2):
		var sw := 1.9 if ph >= 3 else 1.4
		for sd in [-1.0, 1.0]:
			# Godot: завеса летит с кончика щупальца этой стороны; отрубленное щупальце не стреляет
			var tip = tentTip(b, sd)
			if tip == null: continue
			var a: float = PI / 2 + sd * (0.2 + 0.6 * (0.5 + 0.5 * sin(b.age * sw + (PI if sd > 0 else 0.0))))
			var s := Game.bspd(160)
			Game.ebullet(tip.x, tip.y, cos(a) * s, sin(a) * s, "violet")
	# Godot: хватка щупальцем — кончик краснеет, потом хлещет в сторону корабля
	if timer(b, "lash", bcd(b, 4.4 if ph == 1 else 3.2), 3.0):
		var best = null
		for tn: Dictionary in b.pt.get("tents", []):
			if tn.pts.size() > 4 and (best == null or tn.pts.size() > best.pts.size()): best = tn
		if best != null:
			best.warn = 0.55
			A.play("bossRoar", {"vol": 0.3, "rate": 1.7})
	if ph <= 2 and timer(b, "ink", bcd(b, 3.2), 1.8):
		var n := 1 + ph
		for i in n:
			var a := PI / 2 + (i - (n - 1) / 2.0) * 0.55
			var s := Game.bspd(115)
			Game.ebullet(b.x, b.y + b.h * 0.25, cos(a) * s, sin(a) * s, "ink", {"fuse": 1.25 + i * 0.12, "burst": {"n": 10, "type": "dot", "spd": 145.0}, "life": 6.0})
		A.play("enemyShot", {"rate": 0.6})
	if ph >= 2 and timer(b, "whirl", bcd(b, 3.4 if ph >= 3 else 2.6), 1):
		b.spin += 0.4; ring(b.x, b.y, 16, 135, "violet", b.spin)
	if ph == 2 and b.dash == null and timer(b, "grab", 5.5, 2.5):
		b.dash = {"t": 0.0, "x0": b.x, "y0": b.y, "tx": U.clamp(Game.player.x, b.w * 0.45, G.FW - b.w * 0.45), "dy": 50 * S}
		A.play("bossRoar", {"vol": 0.4, "rate": 1.3})
	if ph >= 3 and timer(b, "spawn", bcd(b, 7), 2.5): E.brood(b.x, b.y + b.h * 0.3, 3, false, 24)


# ── Godot: щупальца Кракена — цепочки звеньев с физикой (интегрирование Верле): висят под корпусом,
#    колышутся, хлещут в корабль, задевают его; пули рубят их с кончика кусками по 3 звена ──
const TENT_N := 11


func growTents(b: En) -> void:
	var tents: Array = []
	for sd in [-1.0, 1.0]:
		var a := tentAnchor(b, sd)
		var pts: Array = []
		for i in TENT_N: pts.append({"x": a.x + sd * i * 3 * G.S, "y": a.y + i * 14 * G.S, "px": a.x, "py": a.y + i * 14 * G.S})
		tents.append({"sd": sd, "pts": pts, "hp": b.maxHp * 0.025, "warn": 0.0, "lash": 0.0, "flash": 0.0})
	b.pt["tents"] = tents


func tentAnchor(b: En, sd: float) -> Vector2:
	return Vector2(b.x + sd * b.w * 0.3, b.y + b.h * 0.3)


## кончик щупальца стороны sd (−1 левое, 1 правое); null — отрублено
func tentTip(b: En, sd: float):
	for tn: Dictionary in b.pt.get("tents", []):
		if tn.sd == sd and tn.pts.size() > 3: return tn.pts[tn.pts.size() - 1]
	return null


## толщина звена: у основания толще, к кончику тоньше
func tentR(i: int, n: int) -> float:
	return lerpf(11.0, 4.0, float(i) / maxf(1, n - 1)) * G.S


func tentacles(b: En, dt: float) -> void:
	var S := G.S
	if not b.pt.has("tents"): growTents(b)
	var p: Pl = Game.player
	var seg := 15.0 * S
	var h := minf(dt, 1.0 / 30)
	for tn: Dictionary in b.pt.tents:
		var pts: Array = tn.pts
		tn.flash = maxf(0.0, tn.flash - dt)
		if tn.warn > 0:
			tn.warn -= dt
			if tn.warn <= 0: tn.lash = 0.7
		tn.lash = maxf(0.0, tn.lash - dt)
		var a := tentAnchor(b, tn.sd)
		var n := pts.size()
		for i in n:
			var q: Dictionary = pts[i]
			if i == 0:
				q.x = a.x; q.y = a.y; q.px = a.x; q.py = a.y
				continue
			var vx: float = (q.x - q.px) * 0.96
			var vy: float = (q.y - q.py) * 0.96
			q.px = q.x; q.py = q.y
			var k := float(i) / maxf(1, n - 1)
			var ax := sin(b.age * 2.1 + tn.sd * 1.7 + k * 3.0) * 260 * S * k   # колыхание
			var ay := 420 * S                                                  # тяжесть
			if tn.lash > 0 and p.alive:
				var f := k * k * 2600 * S
				var dx: float = p.x - q.x
				var dy: float = p.y - q.y
				var dl := maxf(1.0, sqrt(dx * dx + dy * dy))
				ax += dx / dl * f; ay += dy / dl * f
			q.x += vx + ax * h * h; q.y += vy + ay * h * h
		# звенья держат длину (основание неподвижно)
		for it in 4:
			for i in range(1, n):
				var q0: Dictionary = pts[i - 1]
				var q1: Dictionary = pts[i]
				var dx: float = q1.x - q0.x
				var dy: float = q1.y - q0.y
				var dl := maxf(0.001, sqrt(dx * dx + dy * dy))
				var d := (dl - seg) / dl
				if i == 1:
					q1.x -= dx * d; q1.y -= dy * d
				else:
					q0.x += dx * d * 0.5; q0.y += dy * d * 0.5
					q1.x -= dx * d * 0.5; q1.y -= dy * d * 0.5
		# касание щупальцем — удар по кораблю
		if p.alive and not b.entering:
			for i in range(2, n):
				var q: Dictionary = pts[i]
				var rr := tentR(i, n) + p.r
				if (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y) < rr * rr:
					Game.hitPlayer(q.x, q.y, "щупальце Кракена")
					break


## пуля игрока попала в щупальце? (с кончика) — урон куску, при обнулении кусок отрублен
func hitTentacle(bl: Bl) -> bool:
	var b: En = Game.boss
	if b == null or b.entering or not b.pt.has("tents"): return false
	for tn: Dictionary in b.pt.tents:
		var pts: Array = tn.pts
		for i in range(pts.size() - 1, 1, -1):
			var q: Dictionary = pts[i]
			var rr := tentR(i, pts.size()) + bl.r
			if (q.x - bl.x) * (q.x - bl.x) + (q.y - bl.y) * (q.y - bl.y) > rr * rr: continue
			tn.hp -= bl.dmg
			tn.flash = 0.08
			FX.hit(bl.x, bl.y, "#c89bff")
			if tn.hp <= 0: cutTent(b, tn)
			return true
	return false


func cutTent(b: En, tn: Dictionary) -> void:
	var pts: Array = tn.pts
	var tip: Dictionary = pts[pts.size() - 1]
	FX.explode(tip.x, tip.y, 1.1, "#b06bff")
	FX.debris(tip.x, tip.y, "#b06bff", 6, 160)
	A.play("explodeS", {"x": tip.x})
	pts.resize(maxi(2, pts.size() - 3))
	tn.hp = b.maxHp * 0.025
	tn.warn = 0.0; tn.lash = 0.0
	Game.damageEnemy(b, b.maxHp * 0.015, {"src": "part"})
	if pts.size() <= 3:
		FX.text(tip.x, tip.y - 20 * G.S, "ЩУПАЛЬЦЕ ОТРУБЛЕНО!", "#ffc83d", 15, 1.0)
		FX.shake(0.35)
		Game.hitstop(0.05)
		Haptic.medium()
		Game.damageEnemy(b, b.maxHp * 0.04, {"src": "part"})


func drawTentacles(ctx: Ctx, b: En) -> void:
	# механические щупальца под стать корпусу: металлические кольца, по оси — светящаяся жила цвета босса
	var glow := U.col(b.bdef.color)
	for tn: Dictionary in b.pt.tents:
		var pts: Array = tn.pts
		var n := pts.size()
		if n < 2: continue
		for pass_ in 2:
			var kk := 1.0 if pass_ == 1 else 1.3
			for i in n:
				var q: Dictionary = pts[i]
				var r := tentR(i, n) * kk
				if i > 0:
					var q0: Dictionary = pts[i - 1]
					ctx.fill = Color("#0b1016") if pass_ == 0 else Color("#2e3c47")
					ctx.fill_circle((q.x + q0.x) * 0.5, (q.y + q0.y) * 0.5, (r + tentR(i - 1, n) * kk) * 0.45)
				if pass_ == 0: ctx.fill = Color("#0b1016")
				elif tn.flash > 0: ctx.fill = Color.WHITE
				else: ctx.fill = Color("#5d7484") if i % 2 == 0 else Color("#8aa2b2")
				ctx.fill_circle(q.x, q.y, r)
		# жила
		ctx.additive = true
		ctx.stroke = glow
		for k in 2:
			ctx.alpha = 0.25 if k == 0 else 0.7
			ctx.line_width = (5.0 if k == 0 else 1.6) * G.S
			ctx.begin_path()
			ctx.move_to(pts[0].x, pts[0].y)
			for i in range(1, n): ctx.line_to(pts[i].x, pts[i].y)
			ctx.stroke_path()
		var tip: Dictionary = pts[n - 1]
		var gs := 18 * G.S
		ctx.alpha = 0.8
		ctx.draw_tex(G.glow(b.bdef.color, 64), tip.x - gs / 2, tip.y - gs / 2, gs, gs)
		# хватка вот-вот — кончик наливается красным
		if tn.warn > 0 or tn.lash > 0:
			ctx.alpha = 0.5 + 0.5 * absf(sin(b.age * 20))
			gs = 36 * G.S
			ctx.draw_tex(G.glow("#ff3d5a", 64), tip.x - gs / 2, tip.y - gs / 2, gs, gs)
		ctx.additive = false
		ctx.alpha = 1.0


## Феникс: кольца и перья → пикирует на корабль → огненный дождь и огненные кольца (и возрождение)
func _boss_phoenix(b: En) -> void:
	var S := G.S
	var p: Pl = Game.player
	var ph := int(b.phase)
	var want := 2 + ph + (1 if b.reborn else 0)
	while b.orbs.size() < want: b.orbs.append({"a": U.random() * TAU})
	var R := b.w * 0.5
	for o: Dictionary in b.orbs:
		o.a += b._dt * (1.4 + ph * 0.25)
		o["x"] = b.x + cos(o.a) * R; o["y"] = b.y + sin(o.a) * R * 0.8
		if p.alive and Vector2(o.x - p.x, o.y - p.y).length() < 14 * S + p.r: Game.hitPlayer(o.x, o.y)
	if ph != 2 and timer(b, "burst", bcd(b, 2.1), 1.2):
		b.spin += 0.4; ring(b.x, b.y, 16 if ph >= 3 else 10, 150, "fire" if ph >= 3 else "orb", b.spin)
	# огненные перья с крыльев
	if ph <= 2 and timer(b, "feather", bcd(b, 2.6 if ph == 2 else 3.4), 2.4):
		for sd in [-1.0, 1.0]: feathers(b.x + sd * b.w * 0.38, b.y, 3 + ph, sd, 150)
		A.play("enemyShot", {"rate": 1.2})
	if ph == 2 and b.dive == null and timer(b, "dive", 4.5, 1.5):
		b.dive = {"t": 0.0, "x0": b.x, "y0": b.y, "tx": p.x, "ty": minf(p.y - 140 * S, G.H * 0.55)}
	if (ph >= 3 or b.reborn) and timer(b, "rain", bcd(b, 1.3)):
		for i in 3: Game.ebullet(U.rand(0.05, 0.95) * G.FW, -10, 0, Game.bspd(170), "fire")


## Паук-реактор: вращающиеся лапы и дроны → паутина и иглы, преследует → лапы, паутина и дроны
func _boss_spider(b: En) -> void:
	var ph := int(b.phase)
	b.spinCycle += b._dt
	var cyc := fmod(b.spinCycle, 4.0)
	if ph != 2 and cyc < 2.6 and timer(b, "arm", 0.12):
		b.spin += 0.23
		ring(b.x, b.y, 6 if ph >= 3 else 4, 145, "violet", b.spin)
	if ph != 2 and timer(b, "spawn", bcd(b, 6.5), 3):
		var n := 4 if ph >= 3 else 3
		for i in n: E.spawn("drone", {"x": b.x + (i - (n - 1) / 2.0) * 30 * G.S, "y": b.y + b.h * 0.3, "idx": i, "amp": 30.0, "noElite": true})
	# паутина: медленное кольцо с проходами
	if ph >= 2 and timer(b, "web", bcd(b, 5.2 if ph >= 3 else 3.6), 1):
		var n := 24
		var s := Game.bspd(105)
		var gap := U.randi(0, 5)
		var off := U.random() * 0.3
		for i in n:
			if (i + gap) % 6 < 2: continue
			var a := off + float(i) / n * TAU
			Game.ebullet(b.x, b.y, cos(a) * s, sin(a) * s, "dot")
	if ph == 2 and timer(b, "tent", bcd(b, 2.2), 1.5):
		for sd in [-1.0, 1.0]:
			for k in 4:
				Game.after(k * 0.1, func():
					if b.alive: Game.aimAt(b.x + sd * b.w * 0.35, b.y + b.h * 0.25, 230, "needle"))


## Дредноут: пушки и луч → ракеты и заградительная стена (щит снова полный) → два луча и ракеты
func _boss_dreadnought(b: En) -> void:
	var S := G.S
	var ph := int(b.phase)
	var p: Pl = Game.player
	if ph != 2 and timer(b, "beam", bcd(b, 3.4), 1.5):
		var xs := [p.x]
		if ph >= 3: xs.append(U.clamp(p.x + U.pick([-1.0, 1.0]) * U.rand(90, 150) * S, 20 * S, G.FW - 20 * S))
		for x: float in xs: E.beam(x, b.y + b.h * 0.35, 22 * S, 1.0, 0.6, "#3db8ff", b)
		A.play("railCharge", {"vol": 0.5, "rate": 1.3})
	if ph >= 2 and timer(b, "missile", bcd(b, 3.4 if ph >= 3 else 2.6), 1):
		for sd in [-1.0, 0.0, 1.0]:
			var s := Game.bspd(120)
			Game.ebullet(b.x + sd * b.w * 0.35, b.y + b.h * 0.3, sd * s * 0.4, s, "fire", {"homing": 1.3, "life": 5.0})
		A.play("rocket", {"rate": 0.7})
	if ph == 2 and timer(b, "barrage", bcd(b, 4.2), 2.5):
		E._fire_wall(b, {"bullet": "blue", "spd": 120.0}); A.play("enemyShot")
	if timer(b, "cannon", bcd(b, 1.2 if ph == 2 else 1.5)):
		for sd in [-1.0, 1.0]: Game.aimAt(b.x + sd * b.w * 0.42, b.y + b.h * 0.25, 230, "bolt")
	# восстановление энергощита
	if b.shieldMax > 0 and b.shield < b.shieldMax:
		b.shieldRegenWait -= b._dt
		if b.shieldRegenWait <= 0: b.shield = minf(b.shieldMax, b.shield + b.shieldMax * 0.2 * b._dt)


## Инквизитор: гатлинги и перекрестье лазеров → столпы света и перья, преследует → всё вместе быстрее
func _boss_inquisitor(b: En) -> void:
	var S := G.S
	var p: Pl = Game.player
	var ph := int(b.phase)
	if ph != 2 and b.gat == null and timer(b, "gat", bcd(b, 2.5), 1.4):
		b.gatSide = -(b.gatSide if b.gatSide != 0.0 else 1.0)
		b.gat = {"n": 0, "t": 0.0}
	if b.gat != null:
		b.gat.t -= b._dt
		if b.gat.t <= 0:
			b.gat.t = 0.075
			Game.aimAt(b.x + b.gatSide * b.w * 0.36, b.y + b.h * 0.36, 300, "bolt", U.rand(-0.07, 0.07))
			A.play("enemyShot", {"vol": 0.35, "rate": 1.5})
			b.gat.n += 1
			if b.gat.n >= (12 if ph >= 3 else 9): b.gat = null
	# крест правосудия: два луча сходятся от краёв к центру
	if ph != 2 and timer(b, "cross", bcd(b, 5.6 if ph >= 3 else 6.8), 3.5):
		var spin := 0.32 * (1.3 if ph >= 3 else 1.0)
		Game.laser({"owner": b, "ox": 0.0, "oy": 0.05, "ang": PI / 2 - 0.85, "spin": spin, "warn": 0.9, "dur": 1.6, "w": 14 * S, "color": "#ff3d3d"})
		Game.laser({"owner": b, "ox": 0.0, "oy": 0.05, "ang": PI / 2 + 0.85, "spin": -spin, "warn": 0.9, "dur": 1.6, "w": 14 * S, "color": "#ff3d3d"})
		A.play("railCharge", {"vol": 0.5})
	if ph >= 2 and timer(b, "pillar", bcd(b, 5 if ph >= 3 else 3.8), 1.2):
		var xs := [p.x, U.rand(0.1, 0.9) * G.FW] if ph >= 3 else [p.x, U.rand(0.1, 0.9) * G.FW, U.rand(0.1, 0.9) * G.FW]
		for x: float in xs: E.beam(x, b.y + b.h * 0.4, 20 * S, 1.0, 0.5, "#ffd23d", b)
		A.play("railCharge", {"vol": 0.4, "rate": 1.2})
	if ph == 2 and timer(b, "wings", bcd(b, 3.2), 2):
		for sd in [-1.0, 1.0]: feathers(b.x + sd * b.w * 0.42, b.y - b.h * 0.05, 5, sd, 160)
		A.play("enemyShot", {"rate": 1.3})


## Королева роя: кислота и выводки → яйца и личинки, что ползут к кораблю → спираль, яйца и кислота
func _boss_queen(b: En) -> void:
	var ph := int(b.phase)
	if ph == 1 and timer(b, "brood", bcd(b, 4.6), 2):
		E.brood(b.x, b.y + b.h * 0.3, 4, false, 22); A.play("teleport", {"rate": 0.6, "vol": 0.5})
	if ph == 2 and timer(b, "larva", bcd(b, 4.2), 1.5):
		E.brood(b.x, b.y + b.h * 0.3, 4, true, 22); A.play("teleport", {"rate": 0.5, "vol": 0.5})
	if ph != 2 and timer(b, "spit", bcd(b, 1.9)):
		fan(b.x, b.y + b.h * 0.35, 5, 0.7, 200, "green"); A.play("enemyShot")
	if ph >= 2 and timer(b, "eggs", bcd(b, 3.8 if ph >= 3 else 3.0), 1):
		for i in 3:
			var a := PI / 2 + (i - 1) * 0.6
			var s := Game.bspd(110)
			Game.ebullet(b.x + (i - 1) * b.w * 0.25, b.y + b.h * 0.3, cos(a) * s, sin(a) * s, "egg", {"fuse": 1.2 + i * 0.2, "burst": {"n": 6, "type": "green", "spd": 150.0}, "life": 6.0})
	if ph >= 3 and fmod(b.age, 5.0) < 3 and timer(b, "spiral", 0.17):
		b.spin += 0.29; ring(b.x, b.y, 3, 150, "green", b.spin)


## Некромант: спираль и павшие разведчики → иглы крестом и души, телепорты → спираль, души и павшие
func _boss_necro(b: En) -> void:
	var ph := int(b.phase)
	if ph != 2 and timer(b, "spiral", bcd(b, 1.5), 1):
		b.spin += 0.35; ring(b.x, b.y, 12 if ph >= 3 else 7, 150, "violet", b.spin)
	if ph != 2 and timer(b, "summon", bcd(b, 5.5), 3):
		for i in (3 if ph >= 3 else 2): E.spawn("scout", {"tint": 110.0, "hpMul": 0.6, "noElite": true})
		A.play("bossRoar", {"vol": 0.4, "rate": 1.4})
	if ph == 2 and timer(b, "cross", bcd(b, 2.0), 0.8):
		b.xc = not b.xc; ring(b.x, b.y, 8, 190, "needle", PI / 8 if b.xc else 0.0)
	# души: разлетаются и бросаются в игрока
	if ph >= 2 and timer(b, "souls", bcd(b, 2.6 if ph >= 3 else 2.2), 1.5):
		var s := Game.bspd(140)
		for i in 6:
			var a := PI / 2 + (i - 2.5) * 0.4
			Game.ebullet(b.x, b.y + b.h * 0.2, cos(a) * s, sin(a) * s, "green", {"redir": 0.8, "redirSpd": Game.bspd(230), "life": 6.0})


## Материнский корабль: выводки дронов и пушки → кислотный дождь и стена с проходом → всё, кроме пушек
func _boss_mothership(b: En) -> void:
	var S := G.S
	var ph := int(b.phase)
	if ph != 2 and timer(b, "brood", bcd(b, 4.2), 2):
		var n := 5 if ph >= 3 else 3
		for i in n: E.spawn("drone", {"x": U.clamp(b.x + U.rand(-0.42, 0.42) * b.w, 20 * S, G.FW - 20 * S), "y": b.y + b.h * 0.2, "idx": i, "amp": 40.0, "noElite": true})
		A.play("teleport", {"rate": 0.6, "vol": 0.5})
	if ph >= 2 and timer(b, "acid", bcd(b, 3 if ph >= 3 else 2.3), 1):
		for i in 8: Game.ebullet(b.x + (i - 3.5) * b.w * 0.11, b.y + b.h * 0.3, U.rand(-30, 30) * S, Game.bspd(U.rand(110, 140)), "green")
	if ph != 3 and timer(b, "guns", bcd(b, 1.9)):
		for sd in [-1.0, 1.0]: Game.aimAt(b.x + sd * b.w * 0.38, b.y + b.h * 0.2, 220, "bolt")
	if ph >= 2 and timer(b, "wall", 4.6 if ph >= 3 else 5.5, 2.5):
		var n := roundi(G.FW / (26 * S))
		var gap := U.randi(2, n - 5)
		for i in n:
			if i < gap or i > gap + 3: Game.ebullet((i + 0.5) * G.FW / n, b.y + b.h * 0.45, 0, Game.bspd(140), "green")
		A.play("enemyShot")


## Хаос: случайные атаки и глитч-телепорты → по две атаки и перегрев → расплав: спираль обломков, телепорты чаще
func _boss_chaos(b: En) -> void:
	var S := G.S
	var ph := int(b.phase)
	if b.vuln > 0:
		b.vuln -= b._dt
		if U.random() < b._dt * 18: FX.smoke(b.x + U.rand(-0.3, 0.3) * b.w, b.y + U.rand(-0.3, 0.2) * b.h, 1, 16 * S)
		if b.vuln <= 0:
			FX.ring(b.x, b.y, b.r, b.r * 2.4, "#ff7a2a", 0.4, 4); A.play("bossRoar", {"vol": 0.5, "rate": 1.4})
		return
	if ph >= 2 and timer(b, "heat", 12 if ph >= 3 else 9.5, 6):
		b.vuln = 2.4
		FX.text(b.x, b.y - b.h * 0.3, "ПЕРЕГРЕВ! УРОН ×1.5", "#ffb03d", 16, 1.4, -40)
		A.play("explodeM", {"vol": 0.6})
		return
	if timer(b, "act", bcd(b, 1.6 if ph >= 3 else (2.3 if ph == 2 else 2.1)), 1.2):
		var n := 2 if ph >= 2 else 1
		for i in n: chaosMove(b, U.randi(0, CHAOS_MOVES - 1))
	if ph >= 3 and timer(b, "melt", bcd(b, 6), 3): E._fire_spiral(b, {"count": 18, "bullet": "junk", "spd": 160.0})
	if timer(b, "glitch", 3.5 if ph >= 3 else 5.5, 4):
		FX.glow_puff(b.x, b.y, "#ff7a2a", b.w * 1.2, 0.35)
		FX.portal(b.x, b.y, b.w * 0.9, "#ff7a2a", false)
		b.mtOff = U.rand(0, TAU)
		b.flashTele = 0.25
		A.play("teleport", {"rate": 0.8})


## Тяжёлый крейсер: бортовые залпы и рои ракет → таранные проходы и мины → всё вместе, преследует
func _boss_cruiser(b: En) -> void:
	var S := G.S
	var ph := int(b.phase)
	if ph != 2 and timer(b, "broad", bcd(b, 1.6), 1):
		var n := 4 + ph
		for i in n:
			var x := b.x + (float(i) / (n - 1) - 0.5) * b.w * 0.8
			Game.ebullet(x, b.y + b.h * 0.3, U.rand(-12, 12) * S, Game.bspd(185), "bolt")
		A.play("enemyShot")
	if ph != 2 and timer(b, "missiles", bcd(b, 3.2), 2.2):
		for i in (5 if ph >= 3 else 3):
			Game.after(i * 0.18, func():
				if b.alive:
					var s := Game.bspd(115)
					Game.ebullet(b.x - b.face * b.w * 0.4, b.y, U.rand(-40, 40) * S, s * 0.6, "fire", {"homing": 1.25, "life": 5.0}))
		A.play("rocket", {"rate": 0.7})
	if ph >= 2 and b.dash == null and timer(b, "dash", 7.5 if ph >= 3 else 4.8, 1.5):
		var dir := 1 if b.x < G.FW / 2 else -1
		b.dash = {"t": 0.0, "x0": b.x, "y0": b.y, "tx": G.FW - b.w * 0.42 if dir > 0 else b.w * 0.42, "dy": 70 * S}
		A.play("rail", {"vol": 0.4, "rate": 1.4})
	if b.dash != null and timer(b, "dashfire", 0.22): Game.ebullet(b.x, b.y + b.h * 0.3, 0, Game.bspd(230), "needle")
	if ph >= 2 and timer(b, "mines", bcd(b, 4.2 if ph >= 3 else 3.2), 2):
		for sd in [-1.0, 1.0]:
			Game.ebullet(b.x + sd * b.w * 0.3, b.y + b.h * 0.3, sd * 30 * S, 45 * S, "mine", {"fuse": 2.2, "life": 6.0, "sprite": "fx_mine_spider", "w": 36.0, "r": 12.0})
		A.play("mine")


## Оверлорд: следящий луч и батарея глаз → элитная стража и тёмная нова → два луча, батарея и столпы
func _boss_overlord(b: En) -> void:
	var S := G.S
	var p: Pl = Game.player
	var ph := int(b.phase)
	if ph != 2 and timer(b, "eye", bcd(b, 6.2), 2.5):
		var n := 2 if ph >= 3 else 1
		for i in n:
			var a0 := atan2(p.y - b.y, p.x - b.x) + ((0.45 if i else -0.45) if n > 1 else 0.0)
			Game.laser({"owner": b, "ox": 0.0, "oy": 0.02, "ang": a0, "track": 0.5, "warn": 1.0, "dur": 2.4, "w": 18 * S, "color": "#ff3d6b"})
		A.play("railCharge", {"vol": 0.6, "rate": 0.8})
	if ph != 2 and fmod(b.age, 5.0) < 2.8 and timer(b, "array", 0.16 if ph >= 3 else 0.2):
		b.spin += 0.37
		ring(b.x, b.y, 5 if ph >= 3 else 3, 130, "eye", b.spin)
	if ph == 2 and timer(b, "guard", bcd(b, 8), 1.5):
		for i in 2:
			E.spawn(U.pick(["heavyfighter", "assault", "interceptor", "ghost"]), {"x": U.clamp(b.x + (1 if i else -1) * b.w * 0.45, 30 * S, G.FW - 30 * S), "elite": true, "hpMul": 0.6})
		A.play("bossRoar", {"vol": 0.4, "rate": 1.2})
	if ph == 2 and timer(b, "nova", bcd(b, 4.6), 3):
		for k in 3:
			Game.after(k * 0.18, func():
				if b.alive: ring(b.x, b.y, 18, 115 + k * 30, "violet", k * 0.17))
	if ph >= 3 and timer(b, "pillar", bcd(b, 4.2)):
		for x: float in [p.x, U.rand(0.1, 0.9) * G.FW]: E.beam(x, b.y + b.h * 0.4, 20 * S, 1.0, 0.5, "#c03dff", b)


# ════════════════════════════════════════════════════════════
# ФАЗЫ И ПОДСТРОЙКА ПРОЧНОСТИ
# ════════════════════════════════════════════════════════════
## урон не перескакивает фазу: прочность упирается в порог, остальное сгорает
func bossCap(b: En, dmg: float) -> float:
	var floor_: float = b.maxHp * PHASE_HP[int(b.phase) - 1] if b.phase < 3 else 0.0
	return minf(dmg, maxf(0, b.hp - floor_)) if floor_ > 0 else dmg


func phaseMin(num: int) -> float:
	var MIN: Array = D.BOSS_PHASE_MIN
	return MIN[clampi(num, 1, MIN.size()) - 1]


## 4.3.2: подстройка под огневую мощь (D.BOSS_ADAPT). b.vt — сколько секунд босс был уязвим в этой фазе,
## part — какую долю прочности за это время сняли. Средний урон в секунду за весь бой (run.bossDps) решает,
## с какой прочностью выйдет следующий босс (spawnBoss). Фазу снесли быстрее минимума — с rescale крепнет
## и этот босс (прочность и максимум растут вместе — полоса не прыгает)
func adapt(b: En, rescale: bool, part: float) -> void:
	var run = Game.run
	var mn := phaseMin(b.num)
	var t := maxf(0.2, b.vt)
	b.vt = 0.0
	b.drained += b.maxHp * part
	b.vtAll += t
	if not run: return
	run.bossDps = b.drained / b.vtAll
	if not rescale or t >= mn: return
	var f := minf(minf(D.BOSS_ADAPT.step, mn / t), D.BOSS_ADAPT.max * b.baseHp / b.maxHp)
	if f <= 1.01: return
	b.hp *= f; b.maxHp *= f
	b.shield *= f; b.shieldMax *= f


func phaseEnd(b: En, n: int) -> void:
	b.phase = n
	b.trans = PHASE_T
	b.pt = {}; b.aim2 = null; b.gat = null; b.dive = null; b.dash = null; b.vuln = 0.0
	# экран очищается от пуль — передышка и знак, что бой меняется
	Game.clearBulletsAround(G.FW / 2, G.H / 2, G.FW + G.H)
	FX.text(G.FW / 2, G.H * 0.42, "ФАЗА " + str(n), b.bdef.color, 26, 1.9, -18)
	FX.flash(b.bdef.color, 0.2)
	A.play("bossRoar", {"rate": 0.8})
	Game.hitstop(0.06)
	Bus.emit("bossPhase", b)


func phaseFx(b: En, dt: float) -> void:
	var S := G.S
	var k := 1 - b.trans / PHASE_T
	# дрожит, искрит и наливается светом
	b.x += sin(b.age * 53) * 1.6 * S * k
	if U.random() < dt * 22: FX.sparks(b.x + U.rand(-0.4, 0.4) * b.w, b.y + U.rand(-0.35, 0.35) * b.h, U.pick(["#ffffff", b.bdef.color]), 4, 220)
	if U.random() < dt * 3: FX.ring(b.x, b.y, b.r * 0.4, b.r * (1.2 + k), b.bdef.color, 0.35, 3)


func phaseStart(b: En) -> void:
	b.trans = 0.0
	FX.ring(b.x, b.y, b.r, b.r * 3, b.bdef.color, 0.6, 6)
	FX.flash(b.bdef.color, 0.3)
	FX.shake(0.5)
	A.play("bossRoar")
	ring(b.x, b.y, 10 if b.num == 1 else 16, 160, "orb", U.random())
	# энергощит Дредноута в новой фазе восстанавливается до половины
	if b.shieldMax > 0: b.shield = maxf(b.shield, b.shieldMax * 0.5)
	# Godot: Кракен в последней фазе отращивает отрубленные щупальца
	if b.bdef.id == "kraken" and b.phase >= 3:
		growTents(b)
		FX.text(b.x, b.y + b.h * 0.5, "ЩУПАЛЬЦА ОТРОСЛИ", "#c89bff", 15, 1.0)


## 3.0: дополнительная атака из новых паттернов (E._fire_*): во 2-й фазе — по чётности номера босса, в 3-й — все
func bossPattern(b: En) -> void:
	b.xn += 1
	var set_: Array = ["spiral", "wall", "split", "sine"] if b.phase >= 3 else (["spiral", "split"] if b.num % 2 else ["wall", "sine"])
	var k: String = set_[b.xn % set_.size()]
	var f: Dictionary = {"spiral": {"count": 16, "bullet": "orb", "spd": 150.0}, "wall": {"bullet": "orb", "spd": 115.0},
		"split": {"bullet": "egg", "spd": 140.0, "count": 8}, "sine": {"bullet": "blue", "spd": 200.0}}[k]
	E.newFire(k, b, f, b.x, b.y + b.h * 0.3)
	A.play("enemyShot")


# ════════════════════════════════════════════════════════════
# ОБНОВЛЕНИЕ
# ════════════════════════════════════════════════════════════
func updateBoss(b: En, edt: float, dt: float) -> void:
	var S := G.S
	b._dt = edt
	b.age += dt
	b.lastX = b.x
	if b.bdef.id == "kraken": tentacles(b, edt)
	if b.entering:
		b.y = U.damp(b.y, b.baseY, 2.2, dt) + 30 * S * dt
		if b.y >= b.baseY - 4 * S:
			b.entering = false; b.y = b.baseY; Bus.emit("bossReady", b)
			attachTurrets(b)
		return
	# фазы: на 2/3 и 1/3 прочности босс перестраивается (PHASE_T с неуязвим), потом — новый набор атак
	var ratio := b.hp / b.maxHp
	if b.trans > 0:
		b.trans -= dt
		phaseFx(b, dt)
		if b.trans <= 0: phaseStart(b)
		return
	var want := 3 if ratio <= PHASE_HP[1] + 1e-6 else (2 if ratio <= PHASE_HP[0] + 1e-6 else 1)
	if want > b.phase:
		adapt(b, true, 1.0 / 3.0); phaseEnd(b, want)
		return
	b.vt += dt
	# «Кошмар» и «Бог войны»: ярость на последних 15% прочности — все атаки чаще
	if b.phase == 3 and not b.rage and ratio <= 0.15 and Game.diff.bossRage:
		b.rage = true
		Bus.emit("toast", {"ico": "😡", "title": "ЯРОСТЬ", "text": b.bdef.name + " в ярости — атаки чаще!", "info": true, "dur": 2200})
		FX.vignette("#ff2a48", 1.6, 0.6, true)
	# 3.0: во 2-й фазе — дополнительная атака из новых паттернов, в 3-й чаще (свой набор у каждого босса)
	if b.phase >= 2 and timer(b, "xpat", bcd(b, 4 if b.rage else (5.5 if b.phase >= 3 else 7.5)), 3): bossPattern(b)
	# движение
	if b.dive != null:
		var d: Dictionary = b.dive
		d.t += edt
		var k: float = U.ease_in_out(d.t / 0.6) if d.t < 0.6 else (1.0 if d.t < 1.0 else 1 - U.ease_in_out(minf(1, (d.t - 1.0) / 0.8)))
		b.x = U.lerp(d.x0, d.tx, k); b.y = U.lerp(d.y0, d.ty, k)
		if d.t > 1.8: b.dive = null
	elif b.dash != null:
		var d: Dictionary = b.dash
		d.t += edt
		var k := U.ease_in_out(minf(1, d.t / 1.4))
		b.x = U.lerp(d.x0, d.tx, k)
		b.y = d.y0 + sin(minf(1, d.t / 1.4) * PI) * d.dy
		if d.t >= 1.5:
			b.dash = null
			b.mt = asin(U.clamp((b.x - G.FW / 2) / maxf(1, (G.FW / 2 - b.w * 0.5) * 0.85), -1, 1)) / 0.55
	else:
		b.mt += edt
		var id: String = b.bdef.id
		var moves: Array = BOSS_MOVES.get(id, [])
		var mode: String = moves[int(b.phase) - 1] if int(b.phase) - 1 < moves.size() else "sway"
		var speed := 0.3 if id == "mothership" or id == "overlord" else (0.4 if id == "cruiser" or id == "queen" else (0.7 if id == "chaos" else 0.55))
		var span := maxf(0, G.FW / 2 - b.w * 0.5) * 0.85
		if mode == "low": speed *= 1.3
		var tx := G.FW / 2 + sin(b.mt * speed + b.mtOff) * span * (0.25 if mode == "hold" else 1.0)
		if mode == "chase": tx = U.clamp(Game.player.x, G.FW / 2 - span, G.FW / 2 + span)
		if id == "chaos": tx += sin(b.age * 7.3) * 12 * S
		# ниже — но не ближе середины экрана к кораблю
		var ty := (minf(b.baseY + G.H * 0.08, G.H * 0.5 - b.h * 0.3) if mode == "low" else b.baseY) + sin(b.mt * 1.1) * G.H * 0.03
		# телепорт: исчезает в портале и появляется в другой точке своего маршрута
		if mode == "blink" and timer(b, "blink", 4.5, 3):
			FX.glow_puff(b.x, b.y, b.bdef.color, b.w * 1.4, 0.4)
			FX.portal(b.x, b.y, b.w * 0.9, b.bdef.color, false)
			b.mtOff = U.rand(0, TAU)
			A.play("teleport")
			b.flashTele = 0.3
			ring(b.x, b.y, 10, 160, "dot", U.rand(0, 1))
		b.x = U.damp(b.x, tx, 30.0 if b.flashTele > 0 else (1.4 if mode == "chase" else 3.0), dt)
		b.y = U.damp(b.y, ty, 3, dt)
	# горизонтальные корабли смотрят по ходу движения
	var vx := (b.x - b.lastX) / maxf(dt, 0.001)
	if absf(vx) > 12 * S: b.face = 1.0 if vx > 0 else -1.0
	b.fx = U.damp(b.fx, E.horizFlip(b), 7, dt)
	if b.flashTele > 0: b.flashTele -= dt
	if b.frozen > 0: b.frozen -= dt
	# ЭМИ (имплант) глушит атаки босса, двигаться он продолжает
	if b.emp > 0: b.emp -= dt
	elif Game.player.alive: call("_boss_" + b.bdef.id, b)
	# искры повреждённого босса
	if b.phase >= 2 and U.random() < dt * (8 if b.phase >= 3 else 3):
		var x := b.x + U.rand(-0.35, 0.35) * b.w
		var y := b.y + U.rand(-0.3, 0.3) * b.h
		FX.sparks(x, y, "#ffcf6b", 3, 160)
		if b.phase >= 3: FX.smoke(x, y, 1, 14 * S)


## Godot: механические боссы несут две турели на корпусе (враг bturret): их можно отстрелить — деталь отлетает,
## босс теряет 4% прочности и одну пушку. Места — доли размеров корпуса, подобраны под силуэты
const TURRETS := {"guardian": [[-0.3, 0.12], [0.3, 0.12]], "spider": [[-0.28, 0.18], [0.28, 0.18]],
	"dreadnought": [[-0.32, 0.05], [0.32, 0.05]], "inquisitor": [[-0.3, 0.15], [0.3, 0.15]],
	"mothership": [[-0.28, 0.12], [0.28, 0.12]], "cruiser": [[-0.3, 0.1], [0.3, 0.1]], "overlord": [[-0.32, 0.12], [0.32, 0.12]]}


func attachTurrets(b: En) -> void:
	var spots: Array = TURRETS.get(b.bdef.id, [])
	if spots.is_empty(): return
	var at := Game.enemies.find(b)
	for sp in spots:
		var t: En = E.spawn("bturret", {"noElite": true, "x": b.x, "y": b.y})
		if t == null: continue
		t.host = b; t.hx = sp[0]; t.hy = sp[1]
		t.hp = b.maxHp * 0.06; t.maxHp = t.hp
		t.w = maxf(t.w, b.w * 0.09); t.h = t.w * G.aspect(t.sprite); t.r = t.w * 0.55
		t.dir = PI / 2; t.shotT = U.rand(0.8, 1.6)
		t.x = b.x + t.hx * b.w; t.y = b.y + t.hy * b.h
		# в списке врагов — перед боссом: пуля, попавшая в турель, достаётся ей, а не корпусу
		Game.enemies.erase(t)
		Game.enemies.insert(at, t)


func bossDeath(b: En) -> void:
	# Феникс возрождается с 30% прочности: первая смерть — конец 3-й фазы, вторая — конец возрождения
	adapt(b, b.bdef.id == "phoenix" and not b.reborn, 0.3 if b.reborn else 1.0 / 3.0)
	if b.bdef.id == "phoenix" and not b.reborn:
		b.reborn = true
		b.hp = b.maxHp * 0.3
		FX.explode(b.x, b.y, 3, "#ff6a2a")
		FX.flash("#ffb03d", 0.5)
		FX.text(b.x, b.y, "ВОЗРОЖДЕНИЕ!", "#ffb03d", 20, 1.4)
		A.play("bossRoar")
		Bus.emit("toast", {"ico": "🔥", "title": "БОСС", "text": "Феникс возрождается из пепла!", "info": true})
		return
	b.alive = false
	Game.boss = null
	E.corpses.append({"x": b.x, "y": b.y, "w": b.w, "h": b.h, "cv": b.cv, "sprite": b.sprite, "rot": 0.0 if b.fallback else float(b.bdef.rot),
		"flip": -1 if b.fx < 0 else 1, "t": 0.0, "dur": 1.6, "color": b.bdef.color})
	FX.shake(0.7)
	Haptic.success()
	if b.bdef.id == "overlord": M.unlock("overlord")
	Game.onBossDefeated(b)
	Bus.emit("intensity")


# ════════════════════════════════════════════════════════════
# ОТРИСОВКА
# ════════════════════════════════════════════════════════════
func drawBoss(ctx: Ctx, b: En) -> void:
	var S := G.S
	var t := b.age
	var col: String = b.bdef.color
	# орбиты феникса
	if not b.orbs.is_empty():
		ctx.additive = true
		for o: Dictionary in b.orbs:
			if not o.has("x"): continue
			var s := 30 * S
			ctx.draw_tex(G.glow("#ff9f3d", 64), o.x - s, o.y - s, s * 2, s * 2)
			if G.has("fx_plasma2"): G.draw(ctx, "fx_plasma2", o.x, o.y, s * 1.7, t * 2)
			else: G.draw(ctx, "eb_fire", o.x, o.y, s * 1.1, t * 3)
		ctx.additive = false
	if b.pt.has("tents"): drawTentacles(ctx, b)
	ctx.save()
	ctx.translate(b.x, b.y + sin(t * 1.6) * 3 * S)
	# свечение ядра (у перегретого Хаоса — красное и пульсирующее)
	ctx.additive = true
	ctx.alpha = 0.55 + 0.35 * sin(t * 18) if b.vuln > 0 else 0.35 + 0.15 * sin(t * 4)
	var gs := maxf(b.w, b.h) * 1.15
	ctx.draw_tex(G.soft("#ff3d1a" if b.vuln > 0 else col, 64), -gs / 2, -gs / 2, gs, gs)
	ctx.additive = false
	ctx.alpha = 0.85 if b.entering else 1.0
	ctx.rotate((0.0 if b.fallback else float(b.bdef.rot)) + sin(t * 0.8) * 0.03)
	if b.fx != 1.0: ctx.scale((-1.0 if b.fx < 0 else 1.0) * maxf(0.12, absf(b.fx)), 1)
	E.drawFrame(ctx, b.sprite, b.cv, b.w, b.h)
	if b.flash > 0 or b.entering or b.flashTele > 0 or b.vuln > 0 or b.trans > 0:
		ctx.additive = true
		if b.trans > 0: ctx.alpha = 0.25 + 0.45 * (1 - b.trans / PHASE_T) * absf(sin(t * 10))
		elif b.entering: ctx.alpha = 0.25 + 0.15 * sin(t * 12)
		elif b.vuln > 0: ctx.alpha = 0.2 + 0.2 * absf(sin(t * 12))
		else: ctx.alpha = minf(1, b.flash * 10) * 0.55
		var wh := G.white(b.sprite)
		if wh: ctx.draw_tex(wh, -b.w / 2, -b.h / 2, b.w, b.h)
	ctx.restore()
	if b.vuln > 0 and G.has("fx_crosshair"):
		ctx.additive = true
		ctx.alpha = 0.6 + 0.4 * absf(sin(t * 9))
		G.draw(ctx, "fx_crosshair", b.x, b.y, minf(b.w, b.h) * 0.6 * (1 + sin(t * 9) * 0.06), t * 0.9)
		ctx.alpha = 1.0
		ctx.additive = false
	# энергощит
	if b.shield > 0:
		var k := b.shield / b.shieldMax
		var r := maxf(b.w, b.h) * 0.6
		Post.bubble(b.x, b.y, r * 1.08, 0.6 + 0.6 * k, U.col("#7fd8ff"), b.shieldHitT / 0.15)
		ctx.additive = true
		ctx.alpha = 0.12 + k * 0.18 + (0.3 if b.shieldHitT > 0 else 0.0)
		if G.has("fx_sh_bubble"): G.draw(ctx, "fx_sh_bubble", b.x, b.y, r * 2.2)
		else: ctx.draw_tex(G.soft("#3db8ff", 64), b.x - r * 1.2, b.y - r * 1.2, r * 2.4, r * 2.4)
		ctx.stroke = Color.WHITE if b.shieldHitT > 0 else U.col("#7fd8ff")
		ctx.line_width = 2.5 * S
		ctx.alpha = 0.6
		ctx.begin_path(); ctx.arc(b.x, b.y, r, t * 0.8, t * 0.8 + TAU * 0.86); ctx.stroke_path()
		ctx.alpha = 0.35
		ctx.begin_path(); ctx.arc(b.x, b.y, r * 0.9, -t * 1.1, -t * 1.1 + TAU * 0.6); ctx.stroke_path()
		ctx.alpha = 1.0
		ctx.additive = false
	# прицелы снайпера
	if b.aim2 != null and not b.aim2.ang.is_empty():
		var locked: bool = b.aim2.t <= 0.22
		ctx.additive = true
		ctx.stroke = U.col("#ff3d5a")
		ctx.line_width = (2.2 if locked else 1.0) * S
		ctx.alpha = 0.6 + 0.4 * sin(t * 50) if locked else 0.3
		for i in 2:
			var sd := -1.0 if i == 0 else 1.0
			var x := b.x + sd * b.w * 0.32
			var y := b.y + b.h * 0.2
			var a: float = b.aim2.ang[i]
			ctx.stroke_line(x, y, x + cos(a) * 1500, y + sin(a) * 1500)
		ctx.alpha = 1.0
		ctx.additive = false
