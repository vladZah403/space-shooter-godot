extends Node
## События волны и механики секторов (автозагрузка Events) — перенос events.js.
##  С 6-й волны иногда одна волна идёт по особым правилам: ионная буря, метеоритный дождь, солнечные
##  вспышки, космический мусор, конвой. Событие объявляется после баннера волны и длится до её зачистки.
##  3.0: механики секторов — то же, но постоянно на волнах 1–4 сектора (бой с боссом без них) и мягче;
##  сила растёт от первой волны сектора к четвёртой. Пояс астероидов, Улей и Красный гигант — здесь,
##  остальные механики — в sectors.gd.

## метеор летит вниз-влево, как нарисован на листе; голова — в левом нижнем углу кадра
const MDIR := Vector2(-0.63, 0.77)
const MHEAD := {"fx_meteor1": [0.2, 0.81], "fx_meteor2": [0.24, 0.82]}

var cur = null    # событие волны { def, wave, t, start, cd, announced, strikes, lanes, meteors, solar, convoys }
var mech = null   # механика текущего сектора { id, wave, k, cd, st }


func reset() -> void:
	cur = null; mech = null


func active():
	return cur.def if cur != null and cur.announced else null


## на старте волны решаем, будет ли событие
func roll(w: Dictionary) -> void:
	cur = null
	var run: Dictionary = Game.run
	var ch = run.challenge
	var sec := Game.sectorDef(run.sector)
	# справочник (3.1): какие секторы уже видели
	var si := Game.sectorIdx(run.sector)
	var ss: Array = M.s.get_or_add("sectorSeen", [])
	if not si in ss:
		ss.append(si); M.soon()
	# k: 0..3 — номер волны в секторе; бой с боссом проходит без механики
	mech = {"id": sec.mech, "wave": w, "k": mini(3, (int(w.n) - 1) % 5), "cd": 0.6} if sec.mech != "" and not w.boss else null
	if w.boss: return
	var always: bool = (ch != null and "events" in ch.mods) or Game.anomaly("unstable")
	if w.n < (3 if always else D.EVENT_WAVE): return
	if not always and (run.lastEvent >= w.n - 1 or U.random() > D.EVENT_CHANCE): return
	var no: Array = sec.get("noEvents", [])
	var pool: Array = D.EVENTS.filter(func(d): return d.id != run.lastEventId and not d.id in no)
	var def: Dictionary = pool[int(floor(U.random() * pool.size()))]
	run.lastEvent = w.n; run.lastEventId = def.id
	cur = {"def": def, "wave": w, "t": 0.0, "start": w.intro + 1.3, "cd": 0.0, "announced": false, "strikes": [], "lanes": [], "meteors": [], "solar": null, "convoys": 0}


## волна зачищена — событие пережито
func finish() -> void:
	var c = cur
	cur = null
	if c == null or not c.announced: return
	var st: Dictionary = M.s.stats
	st.events = st.get("events", 0) + 1
	M.trackMission("events", 1)
	M.checkAchievements()
	var pts := roundf(400 * c.wave.n * Game.diff.score)
	Game.addScore(pts)
	FX.text(G.FW / 2, G.H * 0.46, c.def.name + " ПОЗАДИ  +" + U.fmt(pts), c.def.color, 14, 1.6, -22)


func update(dt: float) -> void:
	if mech != null: updateMech(dt)
	var c = cur
	if c == null: return
	if not is_same(c.wave, Game.wave):
		cur = null
		return
	var edt := dt * Game.enemySlow()
	c.t += dt
	updateStrikes(edt)
	updateMeteors(edt)
	if c.solar != null: updateSolar(edt)
	if c.t < c.start: return
	if not c.announced:
		c.announced = true
		Bus.emit("waveEvent", c.def)
		Game.tipOnce(c.def.id, {"kind": "СОБЫТИЕ ВОЛНЫ", "ico": c.def.ico, "title": c.def.name, "color": c.def.color})
		A.play("skill", {"rate": 0.8})
		Game.hudDirty = true
		c.cd = 1.4
	# пока в волне ещё есть враги; обломки — только пока волна не выпустила всех
	var alive := 0
	for e: En in Game.enemies:
		if e.alive and not e.leaving and e.type != "debris" and not e.def.prop: alive += 1
	if c.wave.done and not alive: return
	c.cd -= edt
	if c.cd > 0 or not Game.player.alive: return
	call("spawn_" + c.def.id, c)


# ── ИОННАЯ БУРЯ: метка на месте удара, через секунду молния ──
func spawn_storm(c: Dictionary) -> void:
	var S := G.S
	var p: Pl = Game.player
	var r := U.random()
	c.cd = U.rand(1.05, 1.55)
	var x: float
	var y: float
	if r < 0.45:
		x = p.x + U.rand(-30, 30) * S; y = p.y + U.rand(-30, 30) * S
	else:
		var es: Array = Game.enemies.filter(func(e): return e.alive and not e.boss and e.hittable and e.y > 60 * S and e.y < G.H * 0.8)
		if not es.is_empty() and r < 0.85:
			var e: En = es[int(floor(U.random() * es.size()))]
			x = e.x; y = e.y
		else:
			x = U.rand(0.1, 0.9) * G.FW; y = U.rand(0.25, 0.85) * G.H
	c.strikes.append({"x": U.clamp(x, 20 * S, G.FW - 20 * S), "y": U.clamp(y, 60 * S, G.H - 30 * S), "t": 0.0, "warn": 1.1, "R": 46 * S, "done": false})


func updateStrikes(dt: float) -> void:
	var c: Dictionary = cur
	var S := G.S
	var p: Pl = Game.player
	for s: Dictionary in c.strikes:
		s.t += dt
		if s.done or s.t < s.warn: continue
		s.done = true
		FX.lightning(s.x + U.rand(-40, 40) * S, -10, s.x, s.y, "#cfe6ff", 3.6 * S, 0.24)
		FX.lightning(s.x + U.rand(-60, 60) * S, -10, s.x, s.y, "#7fb8ff", 1.8 * S, 0.2)
		FX.sprite("fx_bolt", s.x, s.y, {"w0": 44 * S, "w1": 74 * S, "dur": 0.32, "hold": 0.3, "hue": 215, "rot": U.rand(-0.5, 0.5)})
		FX.ring(s.x, s.y, 6, s.R * 1.3, "#9fd0ff", 0.35, 3)
		FX.shake(0.12)
		A.play("zap", {"vol": 0.8, "rate": 0.7})
		for e: En in Game.enemies:
			if not e.alive or not e.hittable or not E.hitTest(e, s.x, s.y, s.R): continue
			Game.damageEnemy(e, e.maxHp * 0.015 if e.boss or e.mini else e.maxHp * 0.6 + 20, {"src": "storm"})
		if p.alive and Vector2(p.x - s.x, p.y - s.y).length() < s.R * 0.8 + p.r: Game.hitPlayer(p.x, p.y, "Ионная буря")
	if not c.strikes.is_empty() and c.strikes[0].t > c.strikes[0].warn + 0.4: c.strikes = c.strikes.filter(func(s): return s.t <= s.warn + 0.4)


# ── МЕТЕОРИТНЫЙ ДОЖДЬ: сначала линия пути, потом метеор по ней ──
func spawn_meteors(c: Dictionary) -> void:
	var S := G.S
	var p: Pl = Game.player
	c.cd = U.rand(0.7, 1.15)
	var tx := p.x if U.random() < 0.35 else U.rand(0.05, 0.95) * G.FW
	var ty := U.rand(0.4, 0.95) * G.H
	var y0 := -60 * S
	var k := (ty - y0) / MDIR.y
	var big := U.random() < 0.45
	c.lanes.append({"x0": tx - MDIR.x * k, "y0": y0, "t": 0.0, "warn": 0.85, "big": big, "spd": U.rand(330, 420) * S * Game.diff.bspd, "gone": false})


func updateMeteors(dt: float) -> void:
	var c: Dictionary = cur
	var S := G.S
	var p: Pl = Game.player
	for l: Dictionary in c.lanes:
		l.t += dt
		if l.t >= l.warn and not l.gone:
			l.gone = true
			c.meteors.append({"x": l.x0, "y": l.y0, "vx": MDIR.x * l.spd, "vy": MDIR.y * l.spd, "big": l.big,
				"spr": "fx_meteor1" if l.big else "fx_meteor2", "w": (56 if l.big else 34) * S, "r": (13 if l.big else 8) * S, "hit": [], "dead": false})
	if not c.lanes.is_empty() and c.lanes[0].gone: c.lanes = c.lanes.filter(func(l): return not l.gone)
	for m: Dictionary in c.meteors:
		m.x += m.vx * dt; m.y += m.vy * dt
		if FX.quality > 0 and U.random() < dt * 30: FX.glow_puff(m.x - MDIR.x * m.r, m.y - MDIR.y * m.r, "#ff8a3d", m.r * 2.4, 0.25)
		for e: En in Game.enemies:
			if not e.alive or not e.hittable or e.uid in m.hit or not E.hitTest(e, m.x, m.y, m.r): continue
			m.hit.append(e.uid)
			Game.damageEnemy(e, e.maxHp * 0.01 if e.boss or e.mini else e.maxHp * (0.8 if m.big else 0.45) + 10, {"src": "meteor"})
			FX.hit(m.x, m.y, "#ffb03d")
		if p.alive and Vector2(p.x - m.x, p.y - m.y).length() < m.r + p.r:
			if Game.hitPlayer(p.x, p.y, "Метеорит"):
				m.dead = true; FX.explode(m.x, m.y, 1.0 if m.big else 0.7, "#ff8a3d")
		if m.y > G.H + 80 * S or m.x < -120 * S: m.dead = true
	if not c.meteors.is_empty(): c.meteors = c.meteors.filter(func(m): return not m.dead)


# ── СОЛНЕЧНАЯ ВСПЫШКА: солнце разгорается над полем и выжигает вражеские снаряды ──
func spawn_solar(c: Dictionary) -> void:
	c.cd = 6.5
	c.solar = {"t": 0.0, "charge": 1.5, "fired": false}
	FX.vignette("#ffb03d", 1.8, 0.4)
	A.play("railCharge", {"vol": 0.5, "rate": 0.7})


func sunPos() -> Vector2:
	return Vector2(G.FW / 2, Hud.top_inset() + 34 * G.S)


func updateSolar(dt: float) -> void:
	var c: Dictionary = cur
	var s: Dictionary = c.solar
	var S := G.S
	s.t += dt
	if not s.fired and s.t >= s.charge:
		s.fired = true
		var o := sunPos()
		FX.flash("#fff1c4", 0.35)
		FX.sprite("fx_solar", o.x, o.y, {"w0": 110 * S, "w1": 200 * S, "dur": 0.6, "hold": 0.25})
		FX.ring(o.x, o.y, 30 * S, maxf(G.FW, G.H) * 1.1, "#ffd88a", 0.7, 6)
		A.play("rail", {"vol": 0.6, "rate": 1.3})
		Game.clearBulletsAround(o.x, o.y, 99999)
		for e: En in Game.enemies:
			if not e.alive or not e.hittable or e.y < 0: continue
			Game.damageEnemy(e, e.maxHp * 0.01 if e.boss or e.mini else e.maxHp * 0.25 + 8, {"src": "solar", "noText": true})
	if s.t > s.charge + 0.6: c.solar = null


# ── КОСМИЧЕСКИЙ МУСОР: медленные обломки, в каждом монеты ──
func spawn_debris(c: Dictionary) -> void:
	c.cd = U.rand(0.55, 0.9)
	if c.wave.done: return
	var n := 0
	for e: En in Game.enemies:
		if e.alive and e.type == "debris": n += 1
	if n >= 10: return
	E.spawn("debris", {"sprite": "fx_rock%d" % U.randi(1, 6), "noElite": true, "scale": U.rand(0.8, 1.35)})


# ── КОНВОЙ (3.1): грузовики с ящиками, два-три за волну ──
func spawn_convoy(c: Dictionary) -> void:
	c.cd = U.rand(6, 8)
	if c.wave.done or c.convoys >= (3 if c.wave.n >= 20 else 2) or not Foes.ready("e_cargo"): return
	c.convoys += 1
	E.spawn("cargo", {"noElite": true})


# ════════════════════════════════════════════════════════════
# МЕХАНИКИ СЕКТОРОВ — в кат-сценах новое не появляется, уже летящее продолжает движение
# ════════════════════════════════════════════════════════════
func updateMech(dt: float) -> void:
	var m: Dictionary = mech
	if not is_same(m.wave, Game.wave):
		mech = null
		return
	if Game.state != "play" or not Game.player.alive: return
	# 3.1: механики остальных секторов — в sectors.gd
	if Sectors.has(m.id):
		Sectors.update(m, dt)
		return
	m.cd -= dt
	if m.cd <= 0: call("mech_" + m.id, m)


func _count(type: String) -> int:
	var n := 0
	for e: En in Game.enemies:
		if e.alive and e.type == type: n += 1
	return n


## ПОЯС АСТЕРОИДОВ: медленные астероиды закрывают от вражеских пуль и мешают стрелять; в части из них монеты
## или кристаллы. Чем дальше в сектор, тем их больше и они крупнее
func mech_asteroids(m: Dictionary) -> void:
	var k: int = m.k
	m.cd = [3, 2.5, 2, 1.6][k] * U.rand(0.8, 1.2)
	if _count("asteroid") >= [2, 3, 4, 5][k]: return
	var scale := U.rand(0.85, 1.15) + k * 0.08
	# добычу видно заранее: камни с самоцветами — монеты, с кристаллами — опыт (лист art/sheet11_asteroids.png)
	var r := U.random()
	var loot := "coin" if r < 0.4 else ("xp" if r < 0.6 else "")
	var size := "m" if scale < 1 else ("l" if scale < 1.2 else "xl")
	var SPR := {
		"": {"m": ["ast_m1", "ast_m2"], "l": ["ast_l1", "ast_l2"], "xl": ["ast_xl"]},
		"coin": {"m": ["astr_m1", "astr_m2"], "l": ["astr_l"], "xl": ["astr_xl1", "astr_xl2"]},
		"xp": {"m": ["astc_m"], "l": ["astc_l"], "xl": ["astc_xl"]},
	}
	var e := E.spawn("asteroid", {"sprite": U.pick(SPR[loot][size]), "noElite": true, "scale": scale, "hpMul": scale * scale})
	if e == null: return
	if loot == "coin": e.coins = 4
	elif loot == "xp": e.xp = 2


## УЛЕЙ (3.1): на стенах у краёв экрана зреют яйца, не разбитые — выпускают личинок
func mech_hive(m: Dictionary) -> void:
	var k: int = m.k
	m.cd = [5, 4.2, 3.6, 3][k] * U.rand(0.8, 1.2)
	if _count("hive_egg") >= [2, 3, 3, 4][k] or not Foes.ready("hive_egg1"): return
	Foes.spawnEgg()


## КРАСНЫЙ ГИГАНТ (3.1): раскалённые астероиды, разбитые, брызжут огнём во все стороны
func mech_lava(m: Dictionary) -> void:
	var k: int = m.k
	m.cd = [2.8, 2.3, 1.9, 1.6][k] * U.rand(0.8, 1.2)
	if _count("lava_rock") >= [2, 3, 4, 5][k] or not Foes.ready("astl_1"): return
	var scale := U.rand(0.8, 1.2) + k * 0.06
	E.spawn("lava_rock", {"sprite": "astl_%d" % U.randi(1, 5), "noElite": true, "scale": scale, "hpMul": scale * scale})


## механика сектора: под врагами и поверх них (облака туманности)
func drawBack(ctx: Ctx) -> void:
	if mech != null and Sectors.has(mech.id): Sectors.drawBack(ctx, mech)


func drawMid(ctx: Ctx) -> void:
	if mech != null and Sectors.has(mech.id): Sectors.drawMid(ctx, mech)


# ── отрисовка (координаты поля) ──
func draw(ctx: Ctx) -> void:
	var c = cur
	if c == null: return
	var S := G.S
	ctx.additive = true
	# линии метеоров
	if not c.lanes.is_empty():
		ctx.line_width = 2 * S
		ctx.dash = PackedFloat32Array([10 * S, 8 * S])
		for l: Dictionary in c.lanes:
			var k: float = l.t / l.warn
			ctx.stroke = Color(1, 138 / 255.0, 61 / 255.0, 0.18 + 0.32 * k * (0.6 + 0.4 * sin(l.t * 30)))
			ctx.begin_path(); ctx.move_to(l.x0, l.y0); ctx.line_to(l.x0 + MDIR.x * G.H * 2, l.y0 + MDIR.y * G.H * 2); ctx.stroke_path()
		ctx.dash = PackedFloat32Array()
	# метки ионной бури: кольцо сжимается к моменту удара
	for s: Dictionary in c.strikes:
		if s.done: continue
		var k: float = s.t / s.warn
		G.draw(ctx, "fx_ion", s.x, s.y, s.R * 2 * (0.75 + 0.25 * k), s.t * 2, 0.3 + 0.5 * k)
		ctx.alpha = 0.35 + 0.5 * k
		ctx.stroke = U.col("#9fd0ff")
		ctx.line_width = 2 * S
		ctx.begin_path(); ctx.arc(s.x, s.y, s.R * (1.7 - 0.7 * k), 0, TAU); ctx.stroke_path()
		ctx.alpha = 1.0
	# метеоры
	for m: Dictionary in c.meteors:
		var f := G.frame(m.spr)
		if f.is_empty(): continue
		var h: float = m.w * f[3] / f[2]
		var a: Array = MHEAD[m.spr]
		ctx.draw_image(G.src(f), f[0], f[1], f[2], f[3], m.x - m.w * a[0], m.y - h * a[1], m.w, h)
	# солнце разгорается перед вспышкой
	var s = c.solar
	if s != null and not s.fired:
		var o := sunPos()
		var k: float = s.t / s.charge
		G.draw(ctx, "fx_solar", o.x, o.y, (60 + 70 * k) * S, s.t * 0.8, 0.4 + 0.6 * k)
	ctx.additive = false
