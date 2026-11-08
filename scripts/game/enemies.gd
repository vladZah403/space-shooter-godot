extends Node
## Враги (автозагрузка E) — перенос enemies.js: создание, поведение (ИИ), схемы стрельбы, группы и строи,
## мини-боссы, обновление и уничтожение. Боссы — в bosses.gd (B).
## Имена функций и полей — как в JS-версии, чтобы их было легко сверять.

const COLORS := {
	"scout": "#ff5c4d", "drone": "#5cff7a", "lancer": "#c86bff", "debris": "#d8c3a5", "asteroid": "#c9a27a", "shooter": "#c06bff", "assault": "#3dffd0", "kamikaze": "#ff9f3d", "interceptor": "#cfd8ff",
	"heavy": "#ffd23d", "splitter": "#7dff6b", "bomber": "#aab4d8", "sniper": "#5cb8ff", "shielder": "#7fd8ff", "techno": "#ff5c7a",
	"hunter": "#b06bff", "armored": "#ff9f3d", "heavyfighter": "#ff4d5e", "bombardier": "#ffb03d", "redoubt": "#c48bff", "cruiser": "#ff5c7a",
	"bug": "#9dff5c", "ram": "#ff6a2a", "swarm": "#a6ff3d", "crystal": "#3dffd2", "minelayer": "#ff5c4d", "platform": "#ffc83d",
	"ghost": "#7ff6ff", "orbit": "#ff7a3d", "parasite": "#b06bff", "ion": "#7fe7ff", "crab": "#ff9f3d", "biomech": "#ff5cf0",
	"gunship": "#ff4d4d", "destroyer": "#ff8a3d", "cruiser_h": "#ff4d6d", "battleship": "#ff6a3d", "frigate": "#ffb03d",
	"thief": "#ffc83d", "medic": "#5cff9d", "link": "#ff3d5a", "mortar": "#ff8a3d", "mirror": "#7ff6ff", "projector": "#4cb8ff",
	"icebreaker": "#bff4ff", "stealth": "#6b7bff", "graviton": "#b06bff", "mimic": "#ffb03d",
	"hive_egg": "#a6ff3d", "lava_rock": "#ff6a2a", "cargo": "#ff4d4d", "satellite": "#7fe7ff", "ice_rock": "#bff4ff", "toxic_rock": "#7dff6b", "prism_rock": "#3dffd2",
}

## стоимость врага в «бюджете» волны
const COST := {
	"scout": 1.0, "drone": 0.55, "shooter": 2.0, "assault": 2.0, "kamikaze": 1.2, "interceptor": 2.5, "heavy": 5.0, "splitter": 2.2,
	"bomber": 4.0, "sniper": 3.0, "shielder": 4.5, "techno": 3.5, "hunter": 3.5, "armored": 8.0, "heavyfighter": 4.5, "bombardier": 5.0, "redoubt": 5.5,
	"cruiser": 9.0, "bug": 0.5, "ram": 2.5, "swarm": 4.0, "crystal": 3.0, "minelayer": 4.0, "platform": 5.5, "ghost": 3.5, "orbit": 4.5, "parasite": 4.5,
	"ion": 5.0, "crab": 7.0, "biomech": 7.0, "lancer": 4.0, "debris": 0.0, "asteroid": 0.0, "gunship": 0.0, "destroyer": 0.0, "cruiser_h": 0.0, "battleship": 0.0, "frigate": 0.0,
	"thief": 2.0, "medic": 3.5, "link": 3.0, "mortar": 5.0, "mirror": 3.5, "projector": 4.0, "icebreaker": 7.0, "stealth": 4.0, "graviton": 5.0, "mimic": 5.5,
	"hive_egg": 0.0, "lava_rock": 0.0, "cargo": 0.0, "satellite": 0.0, "ice_rock": 0.0, "toxic_rock": 0.0, "prism_rock": 0.0,
}

## эллиптические хитбоксы крупных кораблей (доли ширины/высоты спрайта)
const HITBOX := {
	"boss": [0.4, 0.38], "b_spider": [0.3, 0.34], "b_battleship": [0.4, 0.43], "b_battleship2": [0.4, 0.43],
	"b_mothership": [0.45, 0.32], "b_heavycruiser": [0.45, 0.32], "e_destroyer": [0.38, 0.44], "e_cruiser_h": [0.45, 0.3],
	"b_sniper": [0.3, 0.42], "b_kraken": [0.33, 0.36], "b_dread": [0.42, 0.42], "b_phoenix": [0.3, 0.36], "b_necro": [0.36, 0.38],
	"b_queen": [0.4, 0.4], "b_inquisitor": [0.38, 0.4], "b_chaos": [0.38, 0.38], "b_overlord": [0.3, 0.36],
}

## поведения без разведения в стороны (строи, пикировщики, пролёты)
const NO_SEP := {"swarm": 1, "formation": 1, "kamikaze": 1, "dive": 1, "diver": 1, "flank": 1, "sweep": 1, "link": 1, "egg": 1, "thief": 1, "drift": 1, "bomber": 1, "flyby": 1}

var uid := 100000
var corpses: Array = []
## Godot: сгорающие корпуса сбитых врагов — шейдер распада (assets/shaders/dissolve.gdshader)
var burns: Array = []
var _burn_mat: ShaderMaterial


# ════════════════════════════════════════════════════════════
# СОЗДАНИЕ
# ════════════════════════════════════════════════════════════
## враги, которые зависают на месте, держатся ниже верхней панели HUD
func minY(e: En) -> float:
	return Hud.top_inset() + e.h * (0.5 if e.mini else 0.35)


func setHitbox(e: En, sprite: String) -> void:
	if HITBOX.has(sprite):
		var hb: Array = HITBOX[sprite]
		e.rx = e.w * hb[0]
		e.ry = e.h * hb[1]
		e.r = maxf(e.rx, e.ry) * 0.9


func hpScale() -> float:
	var w: float = Game.wave.n if Game.wave else 1.0
	# после 30-й волны прочность растёт круче: туда доходят только сильные сборки
	return Game.diff.hp * (1 + (w - 1) * 0.14) * (1 + maxf(0, w - 20) * 0.05) * (1 + maxf(0, w - 30) * 0.06) * (1.15 if Game.relic("r_cursedcoin") else 1.0)


## o: x, y, scale, hpMul, tint, child, noElite, elite, idx, amp, side, larva, sprite, ai, delay, ty
func spawn(type: String, o := {}) -> En:
	if not D.ENEMIES.has(type):
		return null
	var def: Dictionary = D.ENEMIES[type]
	var S := G.S
	var wn: float = Game.wave.n if Game.wave else 1.0
	var diff: Dictionary = Game.diff
	# аномалия «Сигнал флагмана» — элитные втрое чаще (не больше 40%)
	var eliteP: float = diff.elite + maxf(0, wn - 15) * 0.004 + (D.DANGER.elite if Game.wave and Game.wave.danger else 0.0)
	var elite: bool = o.get("elite", false) or (not def.mini and not o.get("noElite", false) and not o.get("child", false) \
		and U.random() < (minf(0.4, eliteP * 3) if Game.anomaly("flagship") else eliteP))
	# в дальних секторах флот противника обновляется — новые облики кораблей
	var sprite: String = o.get("sprite", "")
	if sprite == "":
		sprite = def.alt if def.alt != "" and wn > 10 and U.random() < 0.6 else def.sprite
	var scale: float = (1.12 if elite else 1.0) * o.get("scale", 1.0)
	var w: float = minf(def.w * S * scale, G.FW * 0.75 if def.horizontal else 9999.0)
	var asp := G.aspect(sprite)
	var hp: float = def.hp * hpScale() * (2.2 if elite else 1.0) * o.get("hpMul", 1.0)
	var e := En.new()
	e.uid = uid; uid += 1
	e.type = type; e.def = def; e.sprite = sprite; e.mini = def.mini; e.horiz = def.horizontal
	e.x = o.x if o.has("x") else U.rand(w * 0.6, G.FW - w * 0.6)
	e.y = o.y if o.has("y") else -w * asp * 0.6
	e.w = w; e.h = w * asp; e.r = w * 0.4
	e.hp = hp; e.maxHp = hp; e.score = def.score; e.coins = def.coins; e.xp = def.xp
	e.elite = elite; e.isChild = o.get("child", false); e.larva = o.get("larva", false)
	if elite: e.tint = {"hue": 44, "bright": 0.08}
	elif o.has("tint"): e.tint = {"hue": o.tint}
	elif def.has("tint") and def.tint is float: e.tint = {"hue": def.tint}
	e.phase = U.random() * TAU
	e.fireT = U.rand(0.9, 1.8); e.fireT2 = U.rand(1.6, 2.8)
	e.shield = def.shield * hpScale() if def.shield else 0.0
	e.shieldMax = e.shield
	e.spd = def.spd * S * diff.spd * (1 + minf(wn, 30) * 0.01) * (1.08 if elite else 1.0) * (1.25 if Game.anomaly("ionwind") else 1.0)
	if def.mini: setHitbox(e, sprite)
	# «Сложно» и «Бог войны»: элита со щитом и на 15% быстрее
	if elite and diff.eliteShield and not def.prop:
		e.shield += hp * 0.35; e.shieldMax += hp * 0.35; e.spd *= 1.15
	e.lastX = e.x
	e.baseX = e.x
	# поведение можно задать при появлении (строи из spawnGroup): o.ai
	e.ai = o.get("ai", def.ai)
	if has_method("_init_" + e.ai):
		call("_init_" + e.ai, e, o)
	elif Foes.has_init(e.ai):
		Foes.init_ai(e, o)
	elif Sectors.has_init(e.ai):
		Sectors.init_ai(e, o)
	if e.ty != 0.0: e.ty = maxf(e.ty, minY(e))
	Game.enemies.append(e)
	if def.hint: Foes.seen(e)
	var seen: Array = M.s.get_or_add("foeSeen", [])
	if not type in seen:
		seen.append(type)
		M.soon()
	return e


# ── начальные состояния поведений (INIT в JS) ──
func _init_dive(e: En, _o: Dictionary) -> void: e.amp = U.rand(10, 30) * G.S
func _init_formation(e: En, o: Dictionary) -> void:
	e.idx = o.get("idx", 0)
	e.amp = o.get("amp", 48.0) * G.S
func _init_hover(e: En, _o: Dictionary) -> void:
	e.ty = U.rand(0.1, 0.32) * G.H; e.stay = U.rand(9, 13)
func _init_zigzag(e: En, _o: Dictionary) -> void:
	e.vx = U.sign(U.random() - 0.5) * e.spd * 1.1; e.t = U.rand(0.5, 0.9)
func _init_kamikaze(e: En, _o: Dictionary) -> void: e.ty = U.rand(0.1, 0.24) * G.H
func _init_dasher(e: En, _o: Dictionary) -> void: e.ty = U.rand(0.12, 0.38) * G.H
func _init_tank(e: En, _o: Dictionary) -> void:
	e.ty = U.rand(0.14, 0.3) * G.H; e.stay = U.rand(14, 18)
func _init_bomber(e: En, o: Dictionary) -> void:
	var side: float = o.get("side", -1.0 if U.random() < 0.5 else 1.0)
	e.x = -e.w * 0.6 if side < 0 else G.FW + e.w * 0.6
	e.y = o.y if o.has("y") else maxf(minY(e), U.rand(0.08, 0.32) * G.H)
	e.vx = -side * e.spd
	e.baseY = e.y
func _init_sniper(e: En, _o: Dictionary) -> void: e.ty = U.rand(0.06, 0.16) * G.H
func _init_teleport(e: En, _o: Dictionary) -> void:
	e.x = U.rand(e.w, G.FW - e.w); e.y = U.rand(minY(e), maxf(minY(e) + 20, G.H * 0.45)); e.alpha = 0.0; e.hittable = false
func _init_hunter(e: En, _o: Dictionary) -> void: e.ty = U.rand(0.14, 0.22) * G.H
func _init_redoubt(e: En, _o: Dictionary) -> void:
	e.ty = U.rand(0.14, 0.3) * G.H; e.stay = U.rand(15, 19); e.cyc = 0.0
func _init_swarm(e: En, o: Dictionary) -> void:
	e.idx = o.get("idx", 0); e.amp = o.get("amp", 56.0) * G.S; e.jx = 0.0
	if e.larva: e.dir = PI / 2
func _init_ram(e: En, _o: Dictionary) -> void: e.ty = U.rand(0.1, 0.2) * G.H
func _init_carrier(e: En, _o: Dictionary) -> void:
	e.ty = U.rand(0.12, 0.28) * G.H; e.stay = U.rand(12, 15); e.spawnT = 2.4; e.spawned = 0
func _init_drift(e: En, _o: Dictionary) -> void:
	e.vx = U.rand(-32, 32) * G.S; e.spinAng = U.random() * TAU; e.spin = U.rand(0.6, 1.2) * U.sign(U.random() - 0.5)
func _init_turret(e: En, _o: Dictionary) -> void:
	e.ty = U.rand(0.14, 0.28) * G.H; e.stay = U.rand(14, 17); e.spinAng = 0.0; e.cyc = 1.4; e.on = false; e.shotT = 0.0
func _init_phase(e: En, _o: Dictionary) -> void: e.ty = U.rand(0.12, 0.3) * G.H
func _init_orbit(e: En, _o: Dictionary) -> void:
	e.ax = U.rand(0.25, 0.75) * G.FW; e.ay = U.rand(0.18, 0.32) * G.H
	e.R = U.rand(50, 80) * G.S; e.ang = -PI / 2; e.w0 = (-1.0 if U.random() < 0.5 else 1.0) * 1.4; e.stay = 16
	e.x = e.ax; e.spinAng = 0.0
func _init_ion(e: En, _o: Dictionary) -> void:
	e.ty = U.rand(0.12, 0.26) * G.H; e.stay = U.rand(13, 16); e.chargeT = U.rand(1.6, 2.4)
func _init_crab(e: En, _o: Dictionary) -> void:
	e.ty = U.rand(0.16, 0.3) * G.H; e.stay = U.rand(15, 18); e.dirx = -1.0 if U.random() < 0.5 else 1.0; e.stepT = 0.7; e.walking = false; e.volley = 0
func _init_gunship(e: En, _o: Dictionary) -> void:
	e.ty = 0.17 * G.H; e.x = G.FW / 2; e.vx = e.spd * 0.6; e.pat = 0; e.patT = 2.0
func _init_destroyer(e: En, _o: Dictionary) -> void:
	e.ty = 0.16 * G.H; e.x = G.FW / 2; e.vx = e.spd * 0.5; e.pat = 0; e.patT = 2.2
func _init_battleship(e: En, _o: Dictionary) -> void:
	e.ty = 0.16 * G.H; e.x = G.FW / 2; e.vx = e.spd * 0.5; e.pat = 0; e.patT = 2.4
func _init_frigate(e: En, _o: Dictionary) -> void:
	e.ty = 0.18 * G.H; e.x = G.FW / 2; e.vx = e.spd * 0.7; e.pat = 0; e.patT = 2.0; e.run = 0.0
## проход по горизонтали: входит сбоку на своей высоте и стреляет вниз
func _init_sweep(e: En, o: Dictionary) -> void:
	var side: float = o.get("side", 1.0)
	e.x = G.FW + e.w * 0.6 if side < 0 else -e.w * 0.6
	e.y = o.y if o.has("y") else U.rand(0.18, 0.4) * G.H
	e.baseY = e.y
	e.vx = (-1.0 if side < 0 else 1.0) * e.spd * 1.05
	e.fireT = U.rand(0.4, 1.0)
## пикировщик: занимает место наверху, по очереди пикирует на корабль и возвращается
func _init_diver(e: En, o: Dictionary) -> void:
	e.ty = o.get("ty", U.rand(0.12, 0.2) * G.H); e.slotX = e.x; e.t = o.get("delay", U.rand(0.8, 2.4)); e.n = 0
## фланг: заходит снизу из угла и уходит вверх, стреляя по кораблю
func _init_flank(e: En, o: Dictionary) -> void:
	var side: float = o.get("side", 1.0)
	e.x = -e.w * 0.4 if side < 0 else G.FW + e.w * 0.4
	e.y = G.H + e.h
	e.dir = atan2(-G.H * 0.9, (1.0 if side < 0 else -1.0) * G.FW * 0.55)
	e.fireT = 0.6; e.n = 0
func _init_flyby(e: En, _o: Dictionary) -> void:
	e.face = 1.0 if U.random() < 0.5 else -1.0
	e.x = -e.w * 0.55 if e.face > 0 else G.FW + e.w * 0.55
	e.ty = maxf(minY(e), G.H * 0.16)
	e.y = e.ty
	e.vx = e.face * e.spd
	e.passes = 0; e.broadT = 0.6; e.misT = 1.5


## новые враги первые две волны после появления встречаются чаще, дешёвые — со временем реже
func weightOf(k: String, wn: float) -> float:
	var d: Dictionary = D.ENEMIES[k]
	var w: float = d.weight
	if wn - d.wave <= 1 and d.wave > 2: w *= 1.4
	if COST.get(k, 1.0) <= 2.2: w *= maxf(0.3, 1 - (wn - d.wave) * 0.03)
	return w


## группы и строи; возвращает потраченный бюджет
func spawnGroup(wn: float, budgetLeft: float) -> float:
	var pool: Array = []
	for k in D.ENEMIES:
		var d: Dictionary = D.ENEMIES[k]
		if d.weight > 0 and d.wave <= wn and COST.get(k, 1.0) <= maxf(budgetLeft, 1.2):
			pool.append(k)
	if pool.is_empty(): return 1.0
	var type: String = U.pick_weighted(pool, func(k): return weightOf(k, wn))
	var S := G.S
	var FW := G.FW
	var cost := 0.0
	if type == "drone" and not (wn >= 10 and U.random() < 0.3):
		# V-строй или линия дронов
		var n := U.randi(4, mini(7, 4 + int(wn / 4)))
		var cx := U.rand(0.25, 0.75) * FW
		var vee := U.random() < 0.6
		for i in n:
			var off := i - (n - 1) / 2.0
			spawn("drone", {"x": U.clamp(cx + off * 34 * S, 20 * S, FW - 20 * S), "y": -30 * S - (absf(off) * 26 * S if vee else i * 30 * S), "idx": i, "amp": 26.0 if vee else 50.0})
		cost = n * COST.drone
	elif type == "drone":
		# стена дронов во всю ширину с одним проходом
		var step := 40 * S
		var n := int((FW - 20 * S) / step)
		var hole := U.randi(1, n - 2)
		for i in n:
			if i != hole: spawn("drone", {"x": 20 * S + step / 2 + i * step, "y": -30 * S, "idx": i, "amp": 0.0})
		cost = (n - 1) * COST.drone * 0.7
	elif type == "bug":
		# рой жуков
		var n := U.randi(5, mini(9, 5 + int(wn / 6)))
		var cx := U.rand(0.3, 0.7) * FW
		for i in n: spawn("bug", {"x": U.clamp(cx + U.rand(-50, 50) * S, 20 * S, FW - 20 * S), "y": -24 * S - i * 18 * S, "idx": i})
		cost = n * COST.bug
	elif type == "scout" and U.random() < (0.45 if wn >= 2 else 0.3):
		# линия разведчиков
		var n := U.randi(3, mini(5, 3 + int(wn / 5)))
		var gap := minf(64 * S, (FW - 60 * S) / n)
		var x0 := U.rand(30 * S, FW - 30 * S - gap * (n - 1))
		for i in n: spawn("scout", {"x": x0 + i * gap, "y": -40 * S - (i % 2) * 22 * S})
		cost = n * COST.scout
	elif type in ["shooter", "assault", "heavyfighter"] and wn >= 6 and U.random() < 0.35:
		# пара по краям
		spawn(type, {"x": FW * 0.22}); spawn(type, {"x": FW * 0.78})
		cost = COST[type] * 2
	elif type == "ram" and wn >= 12 and U.random() < 0.4:
		spawn("ram", {"x": FW * 0.25}); spawn("ram", {"x": FW * 0.75})
		cost = COST.ram * 2
	elif type in ["scout", "shooter"] and wn >= 5 and U.random() < 0.3:
		# клещи: две тройки заходят с боков на разной высоте и проходят экран, стреляя вниз
		var n := 4 if wn >= 14 else 3
		for side in [-1.0, 1.0]:
			var y: float = (0.2 if side < 0 else 0.32) * G.H
			for i in n:
				var e := spawn(type, {"ai": "sweep", "side": side, "y": y + i * 4 * S})
				if e: e.x -= side * i * 46 * S
		cost = COST[type] * n * 2 * 0.8
	elif type in ["interceptor", "assault"] and wn >= 8 and U.random() < 0.35:
		# эскадрилья пикировщиков
		var n := 4 if wn >= 16 else 3
		var gap := minf(70 * S, (FW - 80 * S) / n)
		var x0 := FW / 2 - gap * (n - 1) / 2
		for i in n: spawn(type, {"ai": "diver", "x": x0 + i * gap, "y": -40 * S - i * 20 * S, "delay": 1.4 + i * 1.1})
		cost = COST[type] * n
	elif type == "interceptor" and wn >= 12 and U.random() < 0.3:
		# фланг: пара заходит снизу из углов — с предупреждением у края экрана
		for side in [-1.0, 1.0]:
			var x: float = 16 * S if side < 0 else FW - 16 * S
			FX.sprite("fx_warn", x, G.H * 0.88, {"w0": 26 * S, "w1": 30 * S, "dur": 1.0, "hold": 0.8})
			var sd: float = side
			Game.after(0.9, func(): spawn("interceptor", {"ai": "flank", "side": sd}))
		A.play("warning", {"vol": 0.35, "rate": 1.4})
		cost = COST.interceptor * 2
	elif type == "link":
		# Связка всегда парой: луч между кораблями
		cost = Foes.spawnLink()
	else:
		spawn(type)
		cost = COST.get(type, 1.0)
	return maxf(cost, 0.5)


## мини-боссы по очереди: Ганшип → Эсминец → Рейдер → Линкор → Ракетный фрегат
func spawnMini(wn: float) -> En:
	var order: Array = D.MINI_ORDER
	var k := int(maxf(0, floorf((wn - 8) / 5))) % order.size()
	var e := spawn(order[k], {"x": G.FW / 2})
	if e: Bus.emit("toast", {"ico": "⚠️", "title": "МИНИ-БОСС", "text": e.def.name + " приближается!", "info": true, "dur": 1800})
	return e


func split(e: En) -> void:
	var S := G.S
	for side in [-1.0, 1.0]:
		var c := spawn("drone", {"x": e.x + side * 14 * S, "y": e.y, "child": true, "hpMul": 0.8, "amp": 0.0})
		if c:
			c.vx = side * 120 * S
			c.splitVx = side * 120 * S


## выводок жуков (рой, паразит, королева, кракен); личинки ползут к игроку
func brood(x: float, y: float, n: int, larva: bool, spread := 16.0) -> void:
	var S := G.S
	for i in n:
		spawn("bug", {"x": U.clamp(x + (i - (n - 1) / 2.0) * spread * S, 16 * S, G.FW - 16 * S), "y": y + U.rand(-6, 6) * S,
			"child": true, "noElite": true, "idx": i, "amp": 30.0, "larva": larva, "hpMul": 0.7 if larva else 1.0})


# ════════════════════════════════════════════════════════════
# СТРЕЛЬБА
# ════════════════════════════════════════════════════════════
func fireRate() -> float:
	return Game.diff.fire * (1 + minf(Game.threatWave(), 40) * 0.015)


func canShoot(e: En) -> bool:
	return Game.player.alive and e.y > 10 and e.y < G.H * 0.78 and not e.leaving and e.alpha > 0.5 and e.x > -10 and e.x < G.FW + 10


func doFire(e: En, f: Dictionary) -> void:
	var S := G.S
	var k: String = f.get("kind", "aimed")
	var mx := e.x
	var my := e.y + e.h * 0.32
	var bullet: String = f.get("bullet", "orb")
	var spd: float = f.get("spd", 200.0)
	match k:
		"aimed": Game.aimAt(mx, my, spd, bullet)
		"aimed3":
			for a in [-0.17, 0.0, 0.17]: Game.aimAt(mx, my, spd, bullet, a)
		"burst":
			for i in int(f.count):
				Game.after(i * 0.12, func():
					if e.alive and canShoot(e): Game.aimAt(e.x, e.y + e.h * 0.32, spd, bullet, U.rand(-0.05, 0.05)))
		"fan":
			var p: Pl = Game.player
			var base := PI / 2 if f.get("down", false) else atan2(p.y - my, p.x - mx)
			var cnt := int(f.count)
			for i in cnt:
				var a: float = base + (float(i) / (cnt - 1) - 0.5) * f.spread
				var s := Game.bspd(spd)
				Game.ebullet(mx, my, cos(a) * s, sin(a) * s, bullet)
		"ring":
			var s := Game.bspd(spd)
			var cnt := int(f.count)
			for i in cnt:
				var a := float(i) / cnt * TAU + e.age
				Game.ebullet(e.x, e.y, cos(a) * s, sin(a) * s, bullet)
		"twin":
			for sd in [-1.0, 1.0]: Game.aimAt(e.x + sd * e.w * 0.28, my, spd, bullet)
		"pincer":
			# клешни: пары снарядов сходятся в точке игрока
			for sd in [-1.0, 1.0]: Game.aimAt(e.x + sd * e.w * 0.42, e.y + e.h * 0.2, spd, bullet)
			for sd in [-1.0, 1.0]: Game.aimAt(e.x + sd * e.w * 0.42, e.y + e.h * 0.2, spd * 0.8, bullet, -sd * 0.18)
		"mine":
			Game.ebullet(e.x, e.y + e.h * 0.1, e.vx * 0.2, 50 * S, "mine",
				{"fuse": 1.9, "life": 6.0, "sprite": "fx_mine2", "w": 30.0, "r": 10.0} if e.elite else {"fuse": 1.9, "life": 6.0})
			A.play("mine")
			return
		_:
			if has_method("_fire_" + k): call("_fire_" + k, e, f, mx, my)
			elif Foes.has_method("_fire_" + k): Foes.call("_fire_" + k, e, f, mx, my)   # 3.1: навес Мортиры (lob)
	A.play("enemyShot", {"x": e.x})


# ── 3.0: новые атаки (их же берут боссы) ──
## спираль: два рукава пуль закручиваются за ~1 с
func _fire_spiral(e: En, f: Dictionary, _mx := 0.0, _my := 0.0) -> void:
	var n := int(f.get("count", 14))
	var dir := 1.0 if e.uid % 2 else -1.0
	var a0 := U.random() * TAU
	for i in n:
		Game.after(i * 0.07, func():
			if not e.alive or not canShoot(e): return
			var s := Game.bspd(f.spd)
			for arm in [0.0, PI]:
				var a: float = a0 + arm + dir * i * 0.38
				Game.ebullet(e.x, e.y, cos(a) * s, sin(a) * s, f.bullet))


## стена с проходом: ряд пуль во всю ширину, проход рядом с кораблём (но не ровно над ним)
func _fire_wall(e: En, f: Dictionary, _mx := 0.0, _my := 0.0) -> void:
	var S := G.S
	var step := 26 * S
	var gap := 74 * S
	var p: Pl = Game.player
	var gx := U.clamp(p.x + U.rand(-90, 90) * S, gap, G.FW - gap)
	var s := Game.bspd(f.spd)
	var x := step / 2
	while x < G.FW:
		if absf(x - gx) > gap / 2: Game.ebullet(x, e.y + e.h * 0.3, 0, s, f.bullet)
		x += step
	FX.ring(gx, e.y + e.h * 0.3, 4, gap / 2, "#ffd23d", 0.3, 2)


## делящаяся: крупный медленный шар через секунду лопается веером
func _fire_split(_e: En, f: Dictionary, mx := 0.0, my := 0.0) -> void:
	var sh = Game.aimAt(mx, my, f.spd, f.get("bullet", "egg") if f.get("bullet", "") != "" else "egg", 0.0,
		{"fuse": 1.0, "burst": {"n": f.get("count", 7), "spd": 150.0, "type": "dot"}})
	if sh: sh.w *= 1.3


## волна: пара снарядов в противофазе виляет по пути к кораблю
func _fire_sine(_e: En, f: Dictionary, mx := 0.0, my := 0.0) -> void:
	for ph in [0.0, PI]:
		Game.aimAt(mx, my, f.spd, f.bullet, 0.0, {"sine": {"amp": 26 * G.S, "f": 7.0, "ph": ph}})


func newFire(kind: String, e: En, f: Dictionary, mx: float, my: float) -> void:
	call("_fire_" + kind, e, f, mx, my)


func tickFire(e: En, dt: float) -> void:
	var f = e.def.get("fire")
	if f is Dictionary and f.get("cd", 0.0) and not (f.get("from", 0.0) and Game.threatWave() < f.from):
		e.fireT -= dt
		if e.fireT <= 0:
			e.fireT = f.cd / fireRate() * U.rand(0.8, 1.2) * (0.75 if e.elite else 1.0)
			if canShoot(e): doFire(e, f)
	# второе орудие у тяжёлых кораблей
	var f2 = e.def.get("fire2")
	if f2 is Dictionary and f2.size() > 0 and not (f2.get("from", 0.0) and Game.threatWave() < f2.from):
		e.fireT2 -= dt
		if e.fireT2 <= 0:
			e.fireT2 = f2.cd / fireRate() * U.rand(0.85, 1.15)
			if canShoot(e): doFire(e, f2)


## вертикальный луч с предупреждением; если владелец погиб до выстрела — луч гаснет
func beam(x: float, y0: float, w: float, warn: float, dur: float, color: String, owner: En = null) -> void:
	Game.ov.beams.append({"x": x, "y0": y0, "w": w, "warn": warn, "dur": dur, "t": 0.0, "color": color, "hitDone": false, "owner": owner})


# ════════════════════════════════════════════════════════════
# ПОВЕДЕНИЕ
# ════════════════════════════════════════════════════════════
func leave(e: En, dt: float) -> void:
	e.leaving = true
	e.y += e.spd * 1.4 * dt


func strafe(e: En, dt: float, k := 0.6) -> void:
	e.x += e.vx * dt
	var m := e.w * k
	if e.x < m or e.x > G.FW - m:
		e.vx = -e.vx
		e.x = U.clamp(e.x, m, G.FW - m)


## уклонение (с 6-й волны): враг замечает, что корабль под ним, и уходит с линии огня
func dodge(e: En, dt: float) -> void:
	if not Game.wave or Game.threatWave() < 6 or e.vx == 0.0: return
	if is_nan(e.vxBase): e.vxBase = absf(e.vx)
	e.vx = U.sign(e.vx) * U.damp(absf(e.vx), e.vxBase, 1.4, dt)
	e.dodgeCd = (U.rand(0.6, 1.6) if is_nan(e.dodgeCd) else e.dodgeCd) - dt
	var p: Pl = Game.player
	if e.dodgeCd > 0 or not p.alive or p.y < e.y or absf(p.x - e.x) > e.w * 0.65: return
	var away := U.sign(e.x - p.x)
	# у края уходить некуда — уклоняется в другую сторону
	var dir := -away if (away > 0 and e.x > G.FW - e.w * 1.4) or (away < 0 and e.x < e.w * 1.4) else away
	e.vx = dir * e.vxBase * 2.6
	e.dodgeCd = U.rand(1.3, 2.4) * (0.6 if e.elite else 1.0)


func arrive(e: En, dt: float, k := 2.2) -> bool:
	e.y = U.damp(e.y, e.ty, k, dt) + 10 * G.S * dt
	return e.y >= e.ty - 6 * G.S


func _ai_dive(e: En, dt: float) -> void:
	e.y += e.spd * dt
	e.x = U.clamp(e.baseX + sin(e.age * 1.7 + e.phase) * e.amp, e.w * 0.5, G.FW - e.w * 0.5)
	tickFire(e, dt)


func _ai_formation(e: En, dt: float) -> void:
	e.y += e.spd * dt
	if e.splitVx != 0.0:
		e.baseX += e.splitVx * dt
		e.splitVx *= exp(-1.5 * dt)
	e.x = U.clamp(e.baseX + sin(e.age * 2.2 + e.idx * 0.7) * e.amp, e.w * 0.5, G.FW - e.w * 0.5)


func _ai_hover(e: En, dt: float) -> void:
	if e.st == 0:
		if arrive(e, dt):
			e.st = 1
			e.vx = U.sign(U.random() - 0.5) * e.spd * 0.55
	elif e.st == 1:
		e.t += dt
		dodge(e, dt)
		strafe(e, dt)
		e.y = e.ty + sin(e.age * 1.5 + e.phase) * 6 * G.S
		tickFire(e, dt)
		if e.t > e.stay: e.st = 2
	else: leave(e, dt)
	# восстановление щита
	if e.shieldMax > 0 and e.shield < e.shieldMax:
		e.shieldRegenWait -= dt
		if e.shieldRegenWait <= 0: e.shield = minf(e.shieldMax, e.shield + e.shieldMax * 0.25 * dt)


func _ai_zigzag(e: En, dt: float) -> void:
	e.y += e.spd * 0.72 * dt
	e.x += e.vx * dt
	e.t -= dt
	if e.t <= 0 or e.x < e.w * 0.55 or e.x > G.FW - e.w * 0.55:
		e.vx = -e.vx; e.t = U.rand(0.5, 0.9); e.x = U.clamp(e.x, e.w * 0.55, G.FW - e.w * 0.55)
	tickFire(e, dt)


func _ai_kamikaze(e: En, dt: float) -> void:
	var p: Pl = Game.player
	var S := G.S
	if e.st == 0:
		e.y = U.damp(e.y, e.ty, 2.5, dt) + 10 * S * dt
		e.x = U.damp(e.x, p.x, 0.8, dt)
		e.t += dt
		if e.t > 0.9:
			e.st = 1; e.t = 0.45; e.dir = atan2(p.y - e.y, p.x - e.x); A.play("mine", {"rate": 0.7})
	elif e.st == 1:
		e.t -= dt
		e.dir = atan2(p.y - e.y, p.x - e.x)
		if e.t <= 0:
			e.st = 2; e.v = e.spd
	else:
		e.v = minf(560 * S * Game.diff.spd, e.v + 1100 * S * dt)
		e.x += cos(e.dir) * e.v * dt; e.y += sin(e.dir) * e.v * dt
		if U.random() < 0.6: FX.glow_puff(e.x - cos(e.dir) * e.h * 0.4, e.y - sin(e.dir) * e.h * 0.4, "#ff9f3d", 18 * S, 0.2)
		if e.y > G.H + e.h or e.x < -e.w or e.x > G.FW + e.w: e.leaving = true


func _ai_dasher(e: En, dt: float) -> void:
	var p: Pl = Game.player
	var S := G.S
	if e.st == 0:
		if arrive(e, dt, 2.4):
			e.st = 1; e.t = 0.5
	elif e.st == 1:
		e.t -= dt
		if e.t <= 0:
			var dir := U.sign(p.x - e.x)
			e.vx = dir * e.spd * 4.6
			e.target = U.clamp(p.x + dir * 70 * S, e.w * 0.6, G.FW - e.w * 0.6)
			e.st = 2
	elif e.st == 2:
		e.x += e.vx * dt
		if U.random() < 0.5: FX.glow_puff(e.x - U.sign(e.vx) * e.w * 0.4, e.y, "#9fb4ff", 16 * S, 0.18)
		var done := (e.vx > 0 and e.x >= e.target) or (e.vx < 0 and e.x <= e.target) or e.x < e.w * 0.6 or e.x > G.FW - e.w * 0.6
		if done:
			e.x = U.clamp(e.x, e.w * 0.6, G.FW - e.w * 0.6)
			e.vx = 0.0; e.n += 1
			if canShoot(e): doFire(e, e.def.fire)
			if e.n >= 3: e.st = 3
			else:
				e.st = 1; e.t = 0.65
	else: leave(e, dt)


func _ai_tank(e: En, dt: float) -> void:
	if e.st == 0:
		if arrive(e, dt, 1.2):
			e.st = 1; e.vx = U.sign(U.random() - 0.5) * e.spd * 0.6
	elif e.st == 1:
		e.t += dt
		dodge(e, dt)
		strafe(e, dt)
		e.y = e.ty + sin(e.age + e.phase) * 5 * G.S
		if e.t > e.stay: e.st = 2
	else: leave(e, dt)
	tickFire(e, dt)


func _ai_sweep(e: En, dt: float) -> void:
	e.x += e.vx * dt
	e.y = e.baseY + sin(e.age * 2.2) * 14 * G.S
	tickFire(e, dt)
	if (e.vx > 0 and e.x > G.FW + e.w) or (e.vx < 0 and e.x < -e.w):
		e.leaving = true; e.alive = false


func _ai_diver(e: En, dt: float) -> void:
	var p: Pl = Game.player
	var S := G.S
	if e.st == 0:
		# встаёт на своё место в строю и ждёт очереди
		e.y = U.damp(e.y, e.ty, 2.4, dt); e.x = U.damp(e.x, e.slotX, 2.4, dt)
		e.t -= dt
		if e.t <= 0 and e.y > e.ty - 10 * S:
			e.st = 1; e.t = 0.45; A.play("mine", {"rate": 1.3, "vol": 0.5})
	elif e.st == 1:
		# замах: чуть приподнимается и вздрагивает — предупреждение
		e.t -= dt; e.y -= 30 * S * dt; e.x += sin(e.age * 40) * 30 * S * dt
		if e.t <= 0:
			e.st = 2; e.v = e.spd * 1.2; e.dir = atan2(p.y - e.y, p.x - e.x); e.shot = false
	elif e.st == 2:
		# пике по дуге: курс доворачивает к кораблю, на полпути — выстрел
		var want := atan2(p.y - e.y, p.x - e.x)
		e.dir += U.clamp(U.angle_diff(e.dir, want), -1.6 * dt, 1.6 * dt)
		e.v = minf(470 * S * Game.diff.spd, e.v + 700 * S * dt)
		e.x += cos(e.dir) * e.v * dt; e.y += sin(e.dir) * e.v * dt
		if not e.shot and e.y > G.H * 0.35 and canShoot(e):
			e.shot = true
			doFire(e, e.def.fire if e.def.fire else {"kind": "aimed", "bullet": "orb", "spd": 230.0})
		if e.y > G.H + e.h:
			e.n += 1
			if e.n >= 2:
				e.alive = false; e.leaving = true
				return
			e.y = -e.h; e.st = 0; e.t = U.rand(1.2, 2.6)


func _ai_flank(e: En, dt: float) -> void:
	var S := G.S
	e.x += cos(e.dir) * e.spd * 1.7 * dt; e.y += sin(e.dir) * e.spd * 1.7 * dt
	if U.random() < 0.4: FX.glow_puff(e.x - cos(e.dir) * e.h * 0.4, e.y - sin(e.dir) * e.h * 0.4, "#9fb4ff", 14 * S, 0.18)
	e.fireT -= dt
	if e.fireT <= 0 and e.n < 3 and e.y < G.H * 0.85:
		e.fireT = 0.55; e.n += 1
		if Game.player.alive: Game.aimAt(e.x, e.y, 250, "bolt")
		A.play("enemyShot")
	if e.y < -e.h:
		e.leaving = true; e.alive = false


func _ai_bomber(e: En, dt: float) -> void:
	e.x += e.vx * dt
	var weave: float = e.def.weave
	e.y = e.baseY + sin(e.age * (1.3 if weave else 1.8)) * (weave if weave else 10.0) * G.S
	tickFire(e, dt)
	if (e.vx > 0 and e.x > G.FW + e.w) or (e.vx < 0 and e.x < -e.w):
		e.leaving = true; e.alive = false


func _ai_sniper(e: En, dt: float) -> void:
	var p: Pl = Game.player
	var f: Dictionary = e.def.fire
	if e.st == 0:
		if arrive(e, dt, 2):
			e.st = 1; e.t = 1.2
	elif e.st == 1:
		e.t -= dt
		e.aim = atan2(p.y - e.y, p.x - e.x)
		p.lockT = 2.5  # корабль в прицеле снайпера
		if e.t <= 0:
			e.st = 2; e.t = 0.3
	elif e.st == 2:
		e.t -= dt
		p.lockT = 2.5; p.lockHot = 0.35
		if e.t <= 0:
			if canShoot(e):
				var s := Game.bspd(f.spd)
				Game.ebullet(e.x, e.y + e.h * 0.3, cos(e.aim) * s, sin(e.aim) * s, f.bullet)
				A.play("laser", {"rate": 0.6, "vol": 0.8})
			e.n += 1
			if e.n >= 3: e.st = 3
			else:
				e.st = 1; e.t = f.cd / fireRate()
	else: leave(e, dt)


func _ai_teleport(e: En, dt: float) -> void:
	var S := G.S
	if e.st == 0:
		e.alpha = minf(1.0, e.alpha + dt * 3.2)
		e.hittable = e.alpha > 0.4
		if e.alpha >= 1:
			e.st = 1; e.t = 0.35
	elif e.st == 1:
		e.t -= dt
		if e.t <= 0:
			if canShoot(e): doFire(e, e.def.fire)
			e.st = 2; e.t = 1.4
	elif e.st == 2:
		e.t -= dt
		e.y += sin(e.age * 2) * 6 * S * dt
		if e.t <= 0: e.st = 3
	else:
		e.alpha = maxf(0.0, e.alpha - dt * 3.2)
		e.hittable = e.alpha > 0.4
		if e.alpha <= 0:
			e.n += 1
			if e.n >= 4:
				e.leaving = true; e.alive = false
				return
			FX.glow_puff(e.x, e.y, "#ff5c7a", 50 * S, 0.3)
			FX.portal(e.x, e.y, e.w * 1.1, "#ff5c7a", false)
			e.x = U.rand(e.w, G.FW - e.w); e.y = U.rand(minY(e), maxf(minY(e) + 20, G.H * 0.45))
			FX.glow_puff(e.x, e.y, "#ff5c7a", 60 * S, 0.35)
			FX.portal(e.x, e.y, e.w * 1.1, "#ff5c7a", true)
			A.play("teleport", {"vol": 0.5})
			e.st = 0


func _ai_hunter(e: En, dt: float) -> void:
	var p: Pl = Game.player
	var S := G.S
	if e.st == 0:
		e.y = U.damp(e.y, e.ty, 2.2, dt) + 8 * S * dt
		e.x = U.damp(e.x, p.x, 2.4, dt)
		e.t += dt
		if e.t > 1.3:
			e.st = 1; e.t = 0.38; e.dir = atan2(p.y - e.y, p.x - e.x)  # сразу: в JS до первого расчёта dir был undefined и спрайт не поворачивался
	elif e.st == 1:
		e.t -= dt
		e.dir = atan2(p.y - e.y, p.x - e.x)
		if e.t <= 0:
			e.st = 2; e.v = 120 * S
	else:
		e.v = minf(600 * S * Game.diff.spd, e.v + 1300 * S * dt)
		e.x += cos(e.dir) * e.v * dt; e.y += sin(e.dir) * e.v * dt
		if U.random() < 0.6: FX.glow_puff(e.x, e.y - e.h * 0.3, "#b06bff", 20 * S, 0.2)
		if e.y > G.H + e.h or e.x < -e.w or e.x > G.FW + e.w:
			e.n += 1
			if e.n >= 3:
				e.leaving = true; e.alive = false
				return
			e.y = -e.h; e.x = U.rand(e.w, G.FW - e.w); e.st = 0; e.t = 0.0


## Редут: периодически поднимает энергобарьер (неуязвим), без барьера бьёт кольцом
func _ai_redoubt(e: En, dt: float) -> void:
	if e.st == 0:
		if arrive(e, dt, 1.6):
			e.st = 1; e.vx = U.sign(U.random() - 0.5) * e.spd * 0.5; e.barrier = 1.6
	elif e.st == 1:
		e.t += dt
		strafe(e, dt)
		e.y = e.ty + sin(e.age * 1.2 + e.phase) * 5 * G.S
		if e.barrier > 0:
			e.barrier -= dt
			if e.barrier <= 0:
				e.cyc = 2.6
				if canShoot(e): doFire(e, e.def.fire)
		else:
			e.cyc -= dt
			if e.cyc <= 0:
				e.barrier = 1.8; A.play("shieldHit", {"vol": 0.4, "rate": 1.3})
		if e.t > e.stay:
			e.st = 2; e.barrier = 0.0
	else: leave(e, dt)


## Жук-дрон: рой с рывками; личинка паразита медленно ползёт к игроку
func _ai_swarm(e: En, dt: float) -> void:
	var S := G.S
	var p: Pl = Game.player
	if e.larva:
		var want := atan2(p.y - e.y, p.x - e.x)
		e.dir += U.clamp(U.angle_diff(e.dir, want), -1.6 * dt, 1.6 * dt)
		var v := e.spd * 0.62
		e.x += cos(e.dir) * v * dt; e.y += sin(e.dir) * v * dt
		if e.age > 9 or e.y > G.H + e.h:
			e.leaving = true; e.alive = false
		return
	e.y += e.spd * 0.85 * dt
	e.jx = U.damp(e.jx, U.rand(-1, 1) * 26 * S, 3, dt)
	e.x = U.clamp(e.baseX + sin(e.age * 3.1 + e.idx * 0.8) * e.amp + e.jx, e.w * 0.5, G.FW - e.w * 0.5)


## Таран: целится, показывает полосу удара и проносится вниз
func _ai_ram(e: En, dt: float) -> void:
	var p: Pl = Game.player
	var S := G.S
	if e.st == 0:
		if arrive(e, dt, 2.4):
			e.st = 1; e.t = 0.8
	elif e.st == 1:
		e.t -= dt
		e.x = U.damp(e.x, U.clamp(p.x, e.w * 0.5, G.FW - e.w * 0.5), 2.2, dt)
		if e.t <= 0:
			e.st = 2; e.t = 0.75; e.lane = e.x; A.play("railCharge", {"vol": 0.3, "rate": 1.6})
	elif e.st == 2:
		e.t -= dt
		e.x = e.lane + U.rand(-2, 2) * S
		if e.t <= 0:
			e.st = 3; e.v = e.spd; e.x = e.lane
	else:
		e.v = minf(900 * S * Game.diff.spd, e.v + 1800 * S * dt)
		e.y += e.v * dt
		if U.random() < 0.8: FX.glow_puff(e.x + U.rand(-0.3, 0.3) * e.w, e.y - e.h * 0.5, "#ff9f3d", 18 * S, 0.22)
		if e.y > G.H + e.h:
			e.n += 1
			if e.n >= 2:
				e.leaving = true; e.alive = false
				return
			e.y = -e.h; e.st = 0; e.ty = maxf(U.rand(0.1, 0.2) * G.H, minY(e))


## Рой: висит и выпускает жуков
func _ai_carrier(e: En, dt: float) -> void:
	if e.st == 0:
		if arrive(e, dt, 1.8):
			e.st = 1; e.vx = U.sign(U.random() - 0.5) * e.spd * 0.45
	elif e.st == 1:
		e.t += dt
		strafe(e, dt)
		e.y = e.ty + sin(e.age * 1.3 + e.phase) * 6 * G.S
		e.spawnT -= dt
		if e.spawnT <= 0 and e.spawned < 2 and canShoot(e):
			e.spawnT = 4.2; e.spawned += 1
			brood(e.x, e.y + e.h * 0.3, 3, false, 20)
			A.play("teleport", {"vol": 0.35, "rate": 1.4})
		if e.t > e.stay: e.st = 2
	else: leave(e, dt)


## Кристалл: медленно дрейфует и вращается; при гибели разлетается осколками
func _ai_drift(e: En, dt: float) -> void:
	e.y += e.spd * 0.55 * dt
	e.x += e.vx * dt
	if e.x < e.w * 0.6 or e.x > G.FW - e.w * 0.6:
		e.vx = -e.vx; e.x = U.clamp(e.x, e.w * 0.6, G.FW - e.w * 0.6)
	e.spinAng += e.spin * dt
	tickFire(e, dt)


## Платформа: турель — вращается и поливает четырьмя струями
func _ai_turret(e: En, dt: float) -> void:
	var S := G.S
	if e.st == 0:
		if arrive(e, dt, 1.6): e.st = 1
	elif e.st == 1:
		e.t += dt
		e.y = e.ty + sin(e.age * 0.9 + e.phase) * 4 * S
		e.spinAng += (1.3 if e.on else 0.5) * dt
		e.cyc -= dt
		if e.cyc <= 0:
			e.on = not e.on
			e.cyc = 1.9 if e.on else 1.8 / pow(fireRate(), 0.5)
		if e.on and canShoot(e):
			e.shotT -= dt
			if e.shotT <= 0:
				e.shotT = 0.3
				var s := Game.bspd(150)
				for k in 4:
					var a := e.spinAng + k * PI / 2
					Game.ebullet(e.x + cos(a) * e.w * 0.4, e.y + sin(a) * e.w * 0.4, cos(a) * s, sin(a) * s, "orb")
				A.play("enemyShot", {"vol": 0.35, "rate": 1.3})
		if e.t > e.stay: e.st = 2
	else: leave(e, dt)


## Призрак: становится почти невидимым, переносится к игроку и бьёт очередью
func _ai_phase(e: En, dt: float) -> void:
	var S := G.S
	var p: Pl = Game.player
	if e.st == 0:
		if arrive(e, dt, 2.4):
			e.st = 1; e.t = 0.45
	elif e.st == 1:
		e.t -= dt
		if e.t <= 0:
			if canShoot(e): doFire(e, e.def.fire)
			e.st = 2; e.t = 0.9
	elif e.st == 2:
		e.t -= dt
		if e.t <= 0:
			e.st = 3; A.play("teleport", {"vol": 0.3, "rate": 1.5})
	elif e.st == 3:
		e.alpha = maxf(0.12, e.alpha - dt * 3)
		e.hittable = e.alpha > 0.4
		if e.alpha <= 0.12:
			e.n += 1
			if e.n >= 4:
				e.leaving = true; e.alive = false
				return
			e.tx = U.clamp(p.x + U.rand(-90, 90) * S, e.w * 0.6, G.FW - e.w * 0.6)
			e.ty2 = U.rand(minY(e), maxf(minY(e) + 30, G.H * 0.4))
			e.st = 4
	elif e.st == 4:
		e.x = U.damp(e.x, e.tx, 5, dt); e.y = U.damp(e.y, e.ty2, 5, dt)
		if absf(e.x - e.tx) < 6 * S and absf(e.y - e.ty2) < 6 * S: e.st = 5
	else:
		e.alpha = minf(1.0, e.alpha + dt * 3)
		e.hittable = e.alpha > 0.4
		if e.alpha >= 1:
			e.st = 1; e.t = 0.35


## Орбита: кружит вокруг точки, которая медленно следует за игроком
func _ai_orbit(e: En, dt: float) -> void:
	if e.st == 0:
		e.y = U.damp(e.y, e.ay - e.R * 0.7, 2.2, dt) + 10 * G.S * dt
		if e.y >= e.ay - e.R * 0.7 - 6 * G.S: e.st = 1
	elif e.st == 1:
		e.t += dt
		e.ax = U.damp(e.ax, U.clamp(Game.player.x, e.R + e.w * 0.6, G.FW - e.R - e.w * 0.6), 0.35, dt)
		e.ang += e.w0 * dt
		e.x = e.ax + cos(e.ang) * e.R
		e.y = maxf(minY(e), e.ay + sin(e.ang) * e.R * 0.7)
		e.spinAng += dt * 2
		tickFire(e, dt)
		if e.t > e.stay: e.st = 2
	else: leave(e, dt)


## Ионный: заряжается и бьёт ионным лучом в своей колонне
func _ai_ion(e: En, dt: float) -> void:
	var S := G.S
	if e.st == 0:
		if arrive(e, dt, 2):
			e.st = 1; e.vx = U.sign(U.random() - 0.5) * e.spd * 0.5
	elif e.st == 1:
		e.t += dt
		strafe(e, dt)
		e.y = e.ty + sin(e.age * 1.4 + e.phase) * 5 * S
		e.chargeT -= dt
		if e.chargeT <= 0 and canShoot(e):
			e.st = 2; e.charge = 0.85
			beam(e.x, e.y + e.h * 0.45, 12 * S, 0.85, 0.45, "#7ff6ff", e)
			A.play("railCharge", {"vol": 0.35, "rate": 1.4})
		if e.t > e.stay: e.st = 3
	elif e.st == 2:
		e.charge -= dt
		if e.charge <= 0:
			e.st = 1; e.chargeT = U.rand(2.8, 3.6) / pow(fireRate(), 0.6); A.play("laser", {"rate": 0.7, "vol": 0.6})
	else: leave(e, dt)


## Крабоход: ходит боком рывками и бьёт клешнями
func _ai_crab(e: En, dt: float) -> void:
	var S := G.S
	if e.st == 0:
		if arrive(e, dt, 1.4): e.st = 1
	elif e.st == 1:
		e.t += dt
		e.stepT -= dt
		if e.walking:
			e.x += e.dirx * e.spd * 1.7 * dt
			if e.x < e.w * 0.6 or e.x > G.FW - e.w * 0.6:
				e.dirx = -e.dirx; e.x = U.clamp(e.x, e.w * 0.6, G.FW - e.w * 0.6)
		if e.stepT <= 0:
			e.walking = not e.walking
			e.stepT = 0.5 if e.walking else 0.65
			if not e.walking and canShoot(e):
				e.volley += 1
				doFire(e, e.def.fire)
				if e.volley % 3 == 0: doFire(e, {"kind": "fan", "count": 5, "spread": 0.9, "bullet": "orb", "spd": 165.0})
		e.y = e.ty + absf(sin(e.age * 7)) * (3.0 if e.walking else 0.0) * S
		if e.t > e.stay: e.st = 2
	else: leave(e, dt)


func _ai_gunship(e: En, dt: float) -> void:
	var S := G.S
	if e.st == 0:
		e.y = U.damp(e.y, e.ty, 1.4, dt) + 8 * S * dt
		if e.y >= e.ty - 6 * S: e.st = 1
		return
	strafe(e, dt, 0.55)
	e.y = e.ty + sin(e.age * 0.9) * 10 * S
	e.patT -= dt
	if e.patT <= 0 and canShoot(e):
		e.patT = 2.7 / pow(fireRate(), 0.7)
		var k := e.pat % 3
		e.pat += 1
		if k == 0:
			for i in 3:
				Game.after(i * 0.16, func():
					if e.alive:
						for sd in [-1.0, 1.0]: Game.aimAt(e.x + sd * e.w * 0.32, e.y + e.h * 0.3, 240, "bolt"))
		elif k == 1:
			var p: Pl = Game.player
			var base := atan2(p.y - e.y, p.x - e.x)
			for i in 7:
				var a := base + (i / 6.0 - 0.5) * 1.1
				var s := Game.bspd(170)
				Game.ebullet(e.x, e.y + e.h * 0.3, cos(a) * s, sin(a) * s, "orb")
		else:
			var s := Game.bspd(140)
			for i in 14:
				var a := i / 14.0 * TAU + e.age
				Game.ebullet(e.x, e.y, cos(a) * s, sin(a) * s, "needle")
		A.play("enemyShot")


## Эсминец: носовое орудие, бортовые веера, самонаводящиеся ракеты
func _ai_destroyer(e: En, dt: float) -> void:
	var S := G.S
	if e.st == 0:
		e.y = U.damp(e.y, e.ty, 1.2, dt) + 8 * S * dt
		if e.y >= e.ty - 6 * S: e.st = 1
		return
	strafe(e, dt, 0.6)
	e.y = e.ty + sin(e.age * 0.7) * 8 * S
	e.patT -= dt
	if e.patT <= 0 and canShoot(e):
		e.patT = 2.8 / pow(fireRate(), 0.7)
		var k := e.pat % 3
		e.pat += 1
		if k == 0:
			for i in 3:
				Game.after(i * 0.22, func():
					if e.alive:
						Game.aimAt(e.x, e.y + e.h * 0.46, 420, "long")
						A.play("laser", {"rate": 0.55, "vol": 0.6}))
		elif k == 1:
			for sd in [-1.0, 1.0]:
				var s := Game.bspd(165)
				for i in 5:
					var a: float = PI / 2 + sd * (0.25 + i * 0.16)
					Game.ebullet(e.x + sd * e.w * 0.35, e.y, cos(a) * s, sin(a) * s, "orb")
			A.play("enemyShot")
		else:
			for sd in [-1.0, 1.0]:
				var s := Game.bspd(120)
				Game.ebullet(e.x + sd * e.w * 0.3, e.y - e.h * 0.1, sd * s * 0.6, s * 0.5, "fire", {"homing": 1.4, "life": 5.0})
			A.play("rocket", {"rate": 0.7, "vol": 0.6})


## Линкор: бортовые завесы, двойные лучи, кольцо с прицельным выстрелом
func _ai_battleship(e: En, dt: float) -> void:
	var S := G.S
	if e.st == 0:
		e.y = U.damp(e.y, e.ty, 1.2, dt) + 8 * S * dt
		if e.y >= e.ty - 6 * S: e.st = 1
		return
	strafe(e, dt, 0.6)
	e.y = e.ty + sin(e.age * 0.6) * 8 * S
	e.patT -= dt
	if e.patT <= 0 and canShoot(e):
		e.patT = 2.9 / pow(fireRate(), 0.7)
		var k := e.pat % 3
		e.pat += 1
		if k == 0:
			for i in 4:
				Game.after(i * 0.16, func():
					if not e.alive: return
					var s := Game.bspd(200)
					for sd in [-1.0, 1.0]: Game.ebullet(e.x + sd * e.w * 0.42, e.y + e.h * 0.1, sd * 22 * S, s, "bolt"))
			A.play("enemyShot")
		elif k == 1:
			var px: float = Game.player.x
			for off in [-60.0, 60.0]: beam(U.clamp(px + off * S, 14 * S, G.FW - 14 * S), e.y + e.h * 0.45, 16 * S, 0.9, 0.5, "#ff8a3d", e)
			A.play("railCharge", {"vol": 0.45, "rate": 1.2})
		else:
			var s := Game.bspd(140)
			for i in 16:
				var a := i / 16.0 * TAU + e.age
				Game.ebullet(e.x, e.y, cos(a) * s, sin(a) * s, "orb")
			Game.aimAt(e.x, e.y + e.h * 0.46, 430, "long")
			A.play("laser", {"rate": 0.6, "vol": 0.6})


## Ракетный фрегат: рои ракет, проходы с пулемётом, прицельный веер
func _ai_frigate(e: En, dt: float) -> void:
	var S := G.S
	if e.st == 0:
		e.y = U.damp(e.y, e.ty, 1.4, dt) + 8 * S * dt
		if e.y >= e.ty - 6 * S: e.st = 1
		return
	strafe(e, dt, 0.55)
	e.y = e.ty + sin(e.age * 1.1) * 8 * S
	if e.run > 0:
		e.run -= dt
		e.runT -= dt
		if e.runT <= 0 and canShoot(e):
			e.runT = 0.09
			Game.ebullet(e.x, e.y + e.h * 0.45, 0, Game.bspd(320), "needle")
		if e.run <= 0: e.vx = U.sign(e.vx) * e.spd * 0.7
	e.patT -= dt
	if e.patT <= 0 and canShoot(e):
		e.patT = 2.6 / pow(fireRate(), 0.7)
		var k := e.pat % 3
		e.pat += 1
		if k == 0:
			for i in 4:
				Game.after(i * 0.14, func():
					if not e.alive: return
					var sd := 1.0 if i % 2 else -1.0
					var s := Game.bspd(115)
					Game.ebullet(e.x + sd * e.w * 0.35, e.y, sd * s * 0.7, s * 0.4, "fire", {"homing": 1.25, "life": 5.0}))
			A.play("rocket", {"rate": 0.75, "vol": 0.6})
		elif k == 1:
			e.run = 1.3; e.vx = U.sign(e.vx if e.vx != 0.0 else 1.0) * e.spd * 2.4
		else:
			var p: Pl = Game.player
			var base := atan2(p.y - e.y, p.x - e.x)
			var s := Game.bspd(175)
			for i in 9:
				var a := base + (i / 8.0 - 0.5) * 1.2
				Game.ebullet(e.x, e.y + e.h * 0.3, cos(a) * s, sin(a) * s, "orb")
			A.play("enemyShot")


## Рейдер: проходит по экрану горизонтально, бортовые залпы вниз; после трёх проходов уходит
func _ai_flyby(e: En, dt: float) -> void:
	var S := G.S
	e.x += e.vx * dt
	e.y = e.ty + sin(e.age * 1.3) * 6 * S
	e.hittable = e.x > -e.w * 0.35 and e.x < G.FW + e.w * 0.35
	if e.hittable:
		e.broadT -= dt
		if e.broadT <= 0 and canShoot(e):
			e.broadT = 0.75 / pow(fireRate(), 0.6)
			var s := Game.bspd(190)
			for i in range(-1, 2): Game.ebullet(e.x + i * e.w * 0.28, e.y + e.h * 0.3, i * 18 * S, s, "bolt")
			A.play("enemyShot", {"vol": 0.6})
		e.misT -= dt
		if e.misT <= 0 and canShoot(e):
			e.misT = 2.6 / pow(fireRate(), 0.6)
			var s := Game.bspd(115)
			Game.ebullet(e.x - e.face * e.w * 0.35, e.y, 0, s, "fire", {"homing": 1.2, "life": 5.0})
			A.play("rocket", {"rate": 0.75, "vol": 0.5})
	var out := (e.vx > 0 and e.x > G.FW + e.w * 0.6) or (e.vx < 0 and e.x < -e.w * 0.6)
	if out:
		e.passes += 1
		if e.passes >= 3:
			e.leaving = true; e.alive = false
			Bus.emit("toast", {"ico": "💨", "title": "РЕЙДЕР", "text": "Ушёл без боя", "info": true, "dur": 1500})
			return
		e.face = -e.face; e.vx = -e.vx * 1.08
		e.ty = maxf(minY(e), e.ty + U.rand(-20, 40) * S)


func hasAI(name: String) -> bool:
	return has_method("_ai_" + name)


func runAI(name: String, e: En, dt: float) -> void:
	call("_ai_" + name, e, dt)


# ════════════════════════════════════════════════════════════
# ОБНОВЛЕНИЕ
# ════════════════════════════════════════════════════════════
## зависшие наверху враги расходятся в стороны, а не лежат друг на друге
func separate(dt: float) -> void:
	var es: Array = Game.enemies
	var S := G.S
	for i in es.size():
		var a: En = es[i]
		if not a.alive or a.boss or a.mini or a.st != 1 or NO_SEP.has(a.ai): continue
		for j in range(i + 1, es.size()):
			var b: En = es[j]
			if not b.alive or b.boss or b.mini or b.st != 1 or NO_SEP.has(b.ai): continue
			var dx := b.x - a.x
			var dy := b.y - a.y
			var mn := (a.w + b.w) * 0.42
			if absf(dx) >= mn or absf(dy) >= (a.h + b.h) * 0.4: continue
			var push := (mn - absf(dx)) * minf(1.0, dt * 3) * 0.5
			var sd := (1.0 if i % 2 else -1.0) if dx == 0.0 else signf(dx)
			a.x = U.clamp(a.x - sd * push, a.w * 0.5, G.FW - a.w * 0.5)
			b.x = U.clamp(b.x + sd * push, b.w * 0.5, G.FW - b.w * 0.5)
			# с края не уйти — расходимся по высоте
			if absf(dx) < 4 * S and a.ty != 0.0:
				a.ty = maxf(a.ty - 20 * S * dt, minY(a))
				b.ty = minf((b.ty if b.ty != 0.0 else b.y) + 20 * S * dt, G.H * 0.5)


func updateAll(edt: float, dt: float) -> void:
	var H := G.H
	for e: En in Game.enemies:
		if not e.alive: continue
		if e.flash > 0: e.flash -= dt
		if e.shieldHitT > 0: e.shieldHitT -= dt
		if e.boss:
			B.updateBoss(e, edt, dt)
			continue
		var edt2 := edt
		if e.frozen > 0:
			e.frozen -= dt
			edt2 *= 0.15
		# ЭМИ (навык): враг замирает и молчит
		if e.emp > 0:
			e.emp -= dt
			edt2 = 0.0
		e.age += edt2
		e.lastX = e.x
		var ai: String = e.ai if e.ai != "" else e.def.ai
		if hasAI(ai): runAI(ai, e, edt2)
		elif Foes.hasAI(ai): Foes.runAI(ai, e, edt2)
		elif Sectors.hasAI(ai): Sectors.runAI(ai, e, edt2)
		if not e.horiz: e.bank = U.damp(e.bank, U.clamp((e.x - e.lastX) / maxf(edt2, 0.001) * 0.0012, -0.35, 0.35), 8, dt)
		if e.y > H + e.h + 20 or e.y < -H:
			e.alive = false; e.leaving = true
	separate(dt)
	for i in range(burns.size() - 1, -1, -1):
		var c: Dictionary = burns[i]
		c.t += dt
		c.x += c.vx * dt; c.y += c.vy * dt; c.rot += c.spin * dt
		if c.t >= c.dur: burns.remove_at(i)
	for i in range(corpses.size() - 1, -1, -1):
		var c: Dictionary = corpses[i]
		c.t += dt
		if c.t < c.dur and U.random() < dt * 14:
			FX.explode(c.x + U.rand(-0.4, 0.4) * c.w, c.y + U.rand(-0.35, 0.35) * c.h, U.rand(1, 2), U.pick(["#ffb03d", "#ff6a2a", c.color]))
			A.play("explodeS", {"vol": 0.6, "x": c.x})
		if c.t >= c.dur:
			corpses.remove_at(i)
			FX.explode(c.x, c.y, 4, c.color, {"kind": "boss"})
			FX.ring(c.x, c.y, 20, maxf(G.FW, G.H), "#ffffff", 0.8, 8)
			FX.flash("#ffffff", 0.7)
			FX.shake(1)
			A.play("explodeL")
			Haptic.boom()


# ════════════════════════════════════════════════════════════
# УНИЧТОЖЕНИЕ
# ════════════════════════════════════════════════════════════
func kill(e: En, src: String) -> void:
	if not e.alive: return
	if e.boss:
		B.bossDeath(e)
		return
	e.alive = false
	_addBurn(e)
	var S := G.S
	var size := U.clamp(maxf(e.w, e.h * 0.8) / (48 * S), 0.6, 2.6)
	var col: String = COLORS.get(e.type, "#ffb03d")
	var o := {}
	if e.mini: o = {"kind": "kill"}
	elif e.elite: o = {"kind": "crit"}
	elif U.random() < 0.5: o = {"kind": "ship"}
	FX.explode(e.x, e.y, size, "#ffb03d" if size > 1.4 else col, o)
	if e.mini:
		FX.explode(e.x - e.w * 0.25, e.y, 1.4, col)
		FX.explode(e.x + e.w * 0.25, e.y, 1.4, "#ffb03d")
	if FX.quality > 0: FX.debris(e.x, e.y, col, int(round(size * 3)), 140)
	A.play("explodeM" if size > 1.5 else "explodeS", {"vol": 0.8 if size > 1.5 else 0.6, "x": e.x})
	if size > 1.5: FX.shake(0.45 if e.mini else 0.18)
	if e.mini:
		FX.flash("#ffd9a0", 0.25)
		Haptic.heavy()
	# посмертные эффекты: осколки кристалла, кольцо орбиты, выводок роя и паразита
	# (бомба и нова их гасят, чтобы зачистка экрана оставалась зачисткой)
	var quiet := src == "bomb" or src == "nova"
	var d: Dictionary = e.def
	var death = d.get("death")
	if death is Dictionary and death.size() > 0 and not quiet and Game.player.alive:
		var s := Game.bspd(death.spd)
		var off := U.random() * TAU
		var dn := int(death.n)
		for i in dn:
			var a := off + float(i) / dn * TAU
			Game.ebullet(e.x, e.y, cos(a) * s, sin(a) * s, death.bullet)
	if d.brood and not quiet and not e.isChild: brood(e.x, e.y, int(d.brood), d.larva, 18)
	# «Ад»: сбитый враг огрызается кольцом медленных пуль
	if Game.diff.get("hell", false) and not quiet and not d.prop and not e.isChild and Game.player.alive:
		var s := Game.bspd(95)
		var off := U.random() * TAU
		var hn := 10 if e.mini else 5
		for i in hn:
			var a := off + float(i) / hn * TAU
			Game.ebullet(e.x, e.y, cos(a) * s, sin(a) * s, "dot")
	Foes.onKill(e)
	Game.onEnemyKilled(e, src)


## попадание по крупным кораблям — эллипс, по остальным — круг; k — множитель размеров корпуса
func hitTest(e: En, x: float, y: float, pad: float, k := 1.0) -> bool:
	if e.rx != 0.0:
		var dx := (x - e.x) / (e.rx * k + pad)
		var dy := (y - e.y) / (e.ry * k + pad)
		return dx * dx + dy * dy <= 1.0
	var rr := e.r * k + pad
	return U.dist2(e.x, e.y, x, y) <= rr * rr


## Godot: корпус сбитого врага выгорает пятнами (не на низком качестве и не для мелочи вроде пуль-врагов)
func _addBurn(e: En) -> void:
	if FX.quality == 0 or e.w < 14 * G.S or (e.cv == null and G.frame(e.sprite).is_empty()): return
	if burns.size() >= 24: burns.pop_front()
	var flip := horizFlip(e) if e.horiz else 1.0
	var rot := 0.0 if e.horiz else (e.spinAng if not is_nan(e.spinAng) else _rotOf(e))
	burns.append({"sprite": e.sprite, "cv": e.cv, "x": e.x, "y": e.y, "w": e.w, "h": e.h, "rot": rot, "flip": flip,
		"vx": U.rand(-20, 20) * G.S, "vy": U.rand(10, 40) * G.S, "spin": U.rand(-1.2, 1.2), "t": 0.0, "dur": 0.9 if not e.mini else 1.2})


## поворот корпуса при отрисовке (как в drawAll): курс ныряльщиков, камикадзе, личинок, крен
func _rotOf(e: En) -> float:
	var def: Dictionary = e.def
	var ai: String = def.ai
	var rot: float = def.rot + e.bank
	if (ai == "kamikaze" or ai == "hunter") and e.st >= 1: rot = e.dir - PI / 2
	if (e.ai == "diver" and e.st == 2) or e.ai == "flank": rot = def.rot + e.dir - PI / 2
	if e.larva: rot = e.dir - PI / 2
	return rot


func _burnMat() -> ShaderMaterial:
	if _burn_mat == null:
		_burn_mat = ShaderMaterial.new()
		_burn_mat.shader = load("res://assets/shaders/dissolve.gdshader")
		var fn := FastNoiseLite.new()
		fn.frequency = 0.05
		fn.fractal_octaves = 3
		_burn_mat.set_shader_parameter("noise", ImageTexture.create_from_image(fn.get_seamless_image(128, 128)))
	return _burn_mat


## горизонтальные спрайты: «смотрят» влево (босс) или вправо (Рейдер, миноукладчик, био-мех) — отражаем по ходу движения
func horizFlip(e: En) -> float:
	if e.boss: return -1.0 if (e.sprite == "b_mothership" or e.sprite == "b_heavycruiser") and e.face > 0 else 1.0
	if e.horiz: return -1.0 if e.vx < 0 else 1.0
	return 1.0


# ════════════════════════════════════════════════════════════
# ОТРИСОВКА
# ════════════════════════════════════════════════════════════
func drawFrame(ctx: Ctx, sprite: String, cv: Texture2D, w: float, h: float, tint := Color.WHITE) -> void:
	if cv:
		ctx.draw_tex(cv, -w / 2, -h / 2, w, h, tint)
		return
	var f := G.frame(sprite)
	if not f.is_empty(): ctx.draw_image(G.src(f), f[0], f[1], f[2], f[3], -w / 2, -h / 2, w, h, tint)


var _cloak_mat: ShaderMaterial

## Godot: Невидимка в маскировке — стеклянный контур (assets/shaders/cloak.gdshader) и марево (Post.bubble с k < 0)
func drawCloaked(ctx: Ctx, e: En) -> void:
	if _cloak_mat == null:
		_cloak_mat = ShaderMaterial.new()
		_cloak_mat.shader = load("res://assets/shaders/cloak.gdshader")
	var vis := clampf((e.alpha - 0.12) / 0.83, 0.0, 1.0)
	var oa := ctx.alpha
	ctx.alpha = 1.0
	ctx.material = _cloak_mat
	drawFrame(ctx, e.sprite, e.cv, e.w, e.h, Color(1, 1, 1, vis))
	ctx.material = null
	ctx.alpha = oa
	if vis < 0.6: Post.bubble(e.x, e.y, maxf(e.w, e.h) * 0.6, -(1.0 - vis), Color.BLACK)


func _lighter(ctx: Ctx, a: float) -> void:
	ctx.additive = true
	ctx.alpha = a


func _normal(ctx: Ctx, a := 1.0) -> void:
	ctx.additive = false
	ctx.alpha = a


func drawAll(ctx: Ctx) -> void:
	var S := G.S
	# останки боссов
	for c: Dictionary in corpses:
		var k: float = c.t / c.dur
		ctx.save()
		ctx.translate(c.x + U.rand(-3, 3) * S * k, c.y + U.rand(-3, 3) * S * k)
		if c.rot: ctx.rotate(c.rot)
		if c.flip < 0: ctx.scale(-1, 1)
		ctx.alpha = 1 - k * 0.6
		drawFrame(ctx, c.sprite, c.cv, c.w, c.h)
		_lighter(ctx, k * 0.8)
		var wh := G.white(c.sprite)
		if wh: ctx.draw_tex(wh, -c.w / 2, -c.h / 2, c.w, c.h)
		ctx.restore()
	# сгорающие корпуса: прогресс распада — в альфе цвета (шейдер читает её как долю выгоревшего)
	if not burns.is_empty():
		var mat := _burnMat()
		for c: Dictionary in burns:
			ctx.save()
			ctx.translate(c.x, c.y)
			if c.flip < 0: ctx.scale(-1, 1)
			ctx.rotate(c.rot)
			ctx.alpha = 1.0
			ctx.additive = false
			ctx.material = mat
			var tint := Color(1, 1, 1, clampf(c.t / c.dur, 0.0, 1.0))
			if c.cv: ctx.draw_tex(c.cv, -c.w / 2, -c.h / 2, c.w, c.h, tint)
			else:
				var f := G.frame(c.sprite)
				ctx.draw_image(G.src(f), f[0], f[1], f[2], f[3], -c.w / 2, -c.h / 2, c.w, c.h, tint)
			ctx.restore()
	var bubble := G.has("fx_sh_bubble")
	for e: En in Game.enemies:
		if not e.alive: continue
		if e.boss:
			B.drawBoss(ctx, e)
			continue
		var def: Dictionary = e.def
		var ai: String = def.ai
		if e.tint != null and e.cv == null: e.cv = G.tinted(e.sprite, e.tint)
		# полоса удара тарана
		if ai == "ram" and e.st == 2:
			_lighter(ctx, 0.16 + 0.14 * absf(sin(e.age * 20)))
			ctx.fill = U.col("#ff3d3d")
			ctx.fill_rect(e.lane - e.w * 0.35, e.y, e.w * 0.7, G.H - e.y)
			ctx.alpha = 0.55 + 0.45 * absf(sin(e.age * 10))
			G.draw(ctx, "fx_warn", e.lane, G.H * 0.8, 26 * S)
			_normal(ctx)
		ctx.save()
		ctx.translate(e.x, e.y)
		ctx.alpha = e.alpha
		# аура элиты / заморозка
		if e.elite or e.frozen > 0:
			_lighter(ctx, e.alpha * (0.35 + sin(e.age * 6) * 0.12))
			var gs := e.w * 1.6
			ctx.draw_tex(G.soft("#9be8ff" if e.frozen > 0 else "#ffc83d", 64), -gs / 2, -gs / 2, gs, gs)
			_normal(ctx, e.alpha)
		# предупреждение камикадзе/охотника
		if (ai == "kamikaze" or ai == "hunter") and e.st == 1:
			_lighter(ctx, 0.6 + 0.4 * sin(e.age * 40))
			var gs := e.w * 1.8
			ctx.draw_tex(G.glow("#ff3d5a", 64), -gs / 2, -gs / 2, gs, gs)
			_normal(ctx, e.alpha)
		# заряд ионного луча
		if ai == "ion" and e.st == 2:
			var k := 1 - maxf(0, e.charge) / 0.85
			var gs := e.w * (0.6 + k * 1.2)
			_lighter(ctx, 0.5 + 0.5 * k)
			ctx.draw_tex(G.glow("#7ff6ff", 64), -gs / 2, e.h * 0.4 - gs / 2, gs, gs)
			_normal(ctx, e.alpha)
		if e.horiz:
			if horizFlip(e) < 0: ctx.scale(-1, 1)
		elif not is_nan(e.spinAng):
			ctx.rotate(e.spinAng)
		else:
			# def.rot без своего поворота — PI (D дополняет при загрузке)
			var rot: float = def.rot + e.bank
			if (ai == "kamikaze" or ai == "hunter") and e.st >= 1: rot = e.dir - PI / 2
			if (e.ai == "diver" and e.st == 2) or e.ai == "flank": rot = def.rot + e.dir - PI / 2
			if e.larva: rot = e.dir - PI / 2
			ctx.rotate(rot)
		if def.cloak and e.alpha < 0.999 and FX.quality > 0: drawCloaked(ctx, e)
		else: drawFrame(ctx, e.sprite, e.cv, e.w, e.h)
		if e.flash > 0:
			_lighter(ctx, minf(1, e.flash * 12) * 0.8)
			var wh := G.white(e.sprite)
			if wh: ctx.draw_tex(wh, -e.w / 2, -e.h / 2, e.w, e.h)
		ctx.restore()
		# энергобарьер Редута
		if e.barrier > 0:
			var r := e.w * 0.62
			Post.bubble(e.x, e.y, r * 1.1, 0.8, U.col("#b06bff"), e.shieldHitT / 0.12)
			_lighter(ctx, 0.3 + 0.15 * sin(e.age * 14) + (0.35 if e.shieldHitT > 0 else 0.0))
			if bubble: G.draw_canvas(ctx, G.tinted("fx_sh_bubble", {"hue": 275}), e.x, e.y, r * 2.25, 0)
			else: ctx.draw_tex(G.soft("#b06bff", 64), e.x - r * 1.2, e.y - r * 1.2, r * 2.4, r * 2.4)
			ctx.alpha = 0.8
			ctx.stroke = Color.WHITE if e.shieldHitT > 0 else U.col("#d9b8ff"); ctx.line_width = 2 * S
			ctx.begin_path(); ctx.arc(e.x, e.y, r, e.age * 3, e.age * 3 + TAU * 0.85); ctx.stroke_path()
			_normal(ctx)
		# щит
		if e.shield > 0:
			var r := e.w * 0.66
			var k := e.shield / e.shieldMax
			Post.bubble(e.x, e.y, r * 1.1, 0.5 + 0.4 * k, U.col("#7fd8ff"), e.shieldHitT / 0.15)
			_lighter(ctx, 0.18 + k * 0.2 + (0.4 if e.shieldHitT > 0 else 0.0))
			if bubble: G.draw(ctx, "fx_sh_bubble", e.x, e.y, r * 2.25)
			else: ctx.draw_tex(G.soft("#4cb8ff", 64), e.x - r * 1.15, e.y - r * 1.15, r * 2.3, r * 2.3)
			ctx.alpha = 0.5 + k * 0.4
			ctx.stroke = Color.WHITE if e.shieldHitT > 0 else U.col("#7fd8ff"); ctx.line_width = 2 * S
			ctx.begin_path(); ctx.arc(e.x, e.y, r, 0, TAU * k); ctx.stroke_path()
			_normal(ctx)
		# значок угрозы над камикадзе/охотником
		if (ai == "kamikaze" or ai == "hunter") and e.st == 1:
			_lighter(ctx, 0.6 + 0.4 * absf(sin(e.age * 12)))
			G.draw(ctx, "fx_warn", e.x, e.y - e.h * 0.7, 24 * S)
			_normal(ctx)
		# прицел снайпера
		if ai == "sniper" and (e.st == 1 or e.st == 2):
			var locked := e.st == 2
			_lighter(ctx, 0.55 + 0.45 * sin(e.age * 50) if locked else 0.28)
			ctx.stroke = U.col("#ff3d5a"); ctx.line_width = (2.0 if locked else 1.0) * S
			ctx.stroke_line(e.x, e.y + e.h * 0.3, e.x + cos(e.aim) * 1400, e.y + sin(e.aim) * 1400)
			_normal(ctx)
		# полоса прочности: у мини-боссов и элиты всегда, у остальных — 1,5 с после попадания и гаснет (3.1: меньше мусора на экране)
		var barA := 1.0 if e.mini or e.elite else U.clamp((1.5 - (Game.t - e.hitT)) / 0.4, 0, 1)
		if e.hp < e.maxHp and e.alpha > 0.5 and barA > 0 and (e.mini or e.maxHp > 60 or e.elite):
			var bw := minf(e.w * 0.8, 120 * S) if e.mini else maxf(24 * S, e.w * 0.5)
			var bh := 5 * S if e.mini else 2.5 * S
			var bx := e.x - bw / 2
			var by := maxf(e.y - e.h * 0.55 - 6 * S, Hud.top_inset() - 32)
			ctx.alpha = barA
			ctx.fill = Color(0, 0, 0, 0.55); ctx.fill_rect(bx - 1, by - 1, bw + 2, bh + 2)
			var k := maxf(0, e.hp / e.maxHp)
			ctx.fill = U.col("#ff5c4d" if e.mini else ("#3dffa2" if k > 0.5 else ("#ffc83d" if k > 0.25 else "#ff4d5e")))
			ctx.fill_rect(bx, by, bw * k, bh)
			ctx.alpha = 1.0
	_normal(ctx)
