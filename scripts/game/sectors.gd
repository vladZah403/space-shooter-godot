extends Node
## Механики секторов (автозагрузка Sectors) — перенос sectors.js.
##  У каждого сектора своё правило на волнах 1–4 (бой с боссом без него).
##  Пояс астероидов, Улей и Красный гигант — в events.gd; здесь остальные:
##  спутники, туманность, лёд, яд, гравитация, звёздный ветер, кристаллы,
##  порталы, столпы света и Око. Events.updateMech/draw вызывают механику по id.
##  m: { id, wave, k (0..3 — номер волны в секторе), cd, st } — сила растёт с k.
## Механика id — функции _<id>_start / _<id>_update / _<id>_back / _<id>_mid (MECH в JS).

const MECHS := ["sats", "nebula", "ice", "toxic", "gravity", "wind", "prism", "portals", "pillars", "eye"]


func has(id: String) -> bool:
	return id in MECHS


func update(m: Dictionary, dt: float) -> void:
	if m.get("st") == null:
		m.st = {}
		if has_method("_%s_start" % m.id): call("_%s_start" % m.id, m)
	call("_%s_update" % m.id, m, dt)


func drawBack(ctx: Ctx, m: Dictionary) -> void:
	if m.get("st") != null and has_method("_%s_back" % m.id): call("_%s_back" % m.id, ctx, m)


func drawMid(ctx: Ctx, m: Dictionary) -> void:
	if m.get("st") != null and has_method("_%s_mid" % m.id): call("_%s_mid" % m.id, ctx, m)


func count(type: String) -> int:
	var n := 0
	for e: En in Game.enemies:
		if e.alive and e.type == type: n += 1
	return n


func ready(name_: String) -> bool:
	return Foes.ready(name_)


# ── поведение «обстановки» (подхватывает enemies.gd, как и foes.gd) ──
func has_init(ai: String) -> bool:
	return has_method("_init_" + ai)


func init_ai(e: En, o: Dictionary) -> void:
	call("_init_" + e.ai, e, o)


func hasAI(ai: String) -> bool:
	return has_method("_ai_" + ai)


func runAI(ai: String, e: En, dt: float) -> void:
	call("_ai_" + ai, e, dt)


## спутник пролетает поперёк экрана, медленно вращаясь
func _init_satfly(e: En, _o: Dictionary) -> void:
	var side := -1.0 if U.random() < 0.5 else 1.0
	e.x = -e.w if side < 0 else G.FW + e.w
	e.y = U.rand(0.16, 0.45) * G.H
	e.vx = -side * e.spd; e.spinAng = 0.0; e.spin = U.rand(0.5, 1) * side


func _ai_satfly(e: En, dt: float) -> void:
	e.x += e.vx * dt
	e.y += sin(e.age * 1.3) * 8 * G.S * dt
	e.spinAng += e.spin * dt
	if (e.vx > 0 and e.x > G.FW + e.w) or (e.vx < 0 and e.x < -e.w):
		e.alive = false; e.leaving = true


## смерть «обстановки» (из Foes.onKill): лёд морозит, яд оставляет облако, спутник роняет бонус
func onKill(e: En) -> void:
	var S := G.S
	var m = Events.mech
	if e.type == "ice_rock":
		var R := 110 * S * (e.w / (48 * S))
		FX.ring(e.x, e.y, 8 * S, R, "#bff4ff", 0.45, 4)
		FX.sparks(e.x, e.y, "#dff9ff", 14, 240)
		for o: En in Game.enemies:
			if o.alive and not o.boss and o != e and U.dist2(o.x, o.y, e.x, e.y) < R * R:
				o.frozen = maxf(o.frozen, 2.5); FX.frost(o.x, o.y)
		A.play("shieldHit", {"rate": 1.6, "vol": 0.5})
	elif e.type == "toxic_rock" and m != null and m.id == "toxic" and m.get("st") != null:
		m.st.clouds.append({"x": e.x, "y": e.y, "r": 64 * S * (e.w / (48 * S)), "t": 0.0, "dur": 5.0, "tick": 0.0})
		A.play("mine", {"rate": 0.5, "vol": 0.4})
	elif e.type == "satellite":
		if U.random() < 0.6: Game.dropPowerup(e.x, e.y)
		else: Game.dropCoins(e.x, e.y, 5)
		FX.text(e.x, e.y - e.r, "ГРУЗ!", "#7fe7ff", 13, 0.8, -50)


# ════════════════════════════════════════════════════════════
# МЕХАНИКИ
# ════════════════════════════════════════════════════════════
# ── ОРБИТА ЗЕМЛИ: спутники связи пролетают поперёк — сбитый роняет бонус или монеты ──
func _sats_update(m: Dictionary, dt: float) -> void:
	m.cd -= dt
	if m.cd > 0: return
	m.cd = [9, 8, 7, 6][int(m.k)] * U.rand(0.8, 1.2)
	if count("satellite") < 2 and ready("sp_radar"): E.spawn("satellite", {"noElite": true})


# ── ТУМАННОСТЬ ОРИОНА: облака плывут вниз и прячут врагов (самонаведение их не видит) ──
func _nebula_start(m: Dictionary) -> void:
	m.st.clouds = []


func _nebula_update(m: Dictionary, dt: float) -> void:
	var S := G.S
	var cl: Array = m.st.clouds
	m.cd -= dt
	if m.cd <= 0 and cl.size() < [2, 3, 3, 4][int(m.k)]:
		m.cd = [6, 5, 4.5, 4][int(m.k)] * U.rand(0.8, 1.2)
		cl.append({"x": U.rand(0.15, 0.85) * G.FW, "y": -90 * S, "r": U.rand(70, 110) * S, "vy": U.rand(22, 34) * S, "ph": U.random() * TAU})
	for i in range(cl.size() - 1, -1, -1):
		cl[i].y += cl[i].vy * dt
		if cl[i].y > G.H * 0.75 + cl[i].r: cl.remove_at(i)
	for e: En in Game.enemies:
		if not e.alive or e.boss: continue
		e.fog = false
		for c: Dictionary in cl:
			if U.dist2(e.x, e.y, c.x, c.y) < c.r * c.r * 0.7:
				e.fog = true
				break


## поверх врагов — облака их и прячут
func _nebula_mid(ctx: Ctx, m: Dictionary) -> void:
	var t := Game.t
	for c: Dictionary in m.st.clouds:
		for i in 4:
			var a: float = c.ph + i * 1.7 + t * 0.2
			var x: float = c.x + cos(a) * c.r * 0.35
			var y: float = c.y + sin(a * 1.3) * c.r * 0.25
			var r: float = c.r * (0.75 + 0.15 * sin(t + i))
			ctx.alpha = 0.55
			ctx.draw_tex(G.soft("#8a3dff" if i % 2 else "#ff3dd2", 64), x - r, y - r, r * 2, r * 2)
		ctx.alpha = 0.35
		ctx.draw_tex(G.soft("#2a0a3a", 64), c.x - c.r, c.y - c.r, c.r * 2, c.r * 2)
	ctx.alpha = 1.0


# ── ЛЕДЯНЫЕ ЛУНЫ: ледяные глыбы закрывают от пуль; разбитая — замораживает врагов вокруг ──
func _ice_update(m: Dictionary, dt: float) -> void:
	m.cd -= dt
	if m.cd > 0: return
	m.cd = [3, 2.6, 2.2, 1.8][int(m.k)] * U.rand(0.8, 1.2)
	if count("ice_rock") >= [2, 3, 4, 5][int(m.k)] or not ready("asti_l"): return
	var scale: float = U.rand(0.85, 1.15) + m.k * 0.06
	var spr: String = U.pick(["asti_m1", "asti_m2"]) if scale < 1 else ("asti_l" if scale < 1.15 else "asti_xl")
	E.spawn("ice_rock", {"sprite": spr, "noElite": true, "scale": scale, "hpMul": scale * scale})


# ── ИЗУМРУДНЫЕ ПОЛЯ: ядовитые глыбы; разбитая оставляет облако — оно жжёт врагов, а корабль — если задержаться ──
func _toxic_start(m: Dictionary) -> void:
	m.st.clouds = []; m.st.inT = 0.0


func _toxic_update(m: Dictionary, dt: float) -> void:
	var st: Dictionary = m.st
	var p: Pl = Game.player
	m.cd -= dt
	if m.cd <= 0:
		m.cd = [3.2, 2.8, 2.4, 2][int(m.k)] * U.rand(0.8, 1.2)
		if count("toxic_rock") < [2, 3, 3, 4][int(m.k)] and ready("astp_l1"):
			var scale: float = U.rand(0.85, 1.15) + m.k * 0.06
			var spr: String = "astp_m" if scale < 1 else (U.pick(["astp_l1", "astp_l2"]) if scale < 1.15 else "astp_xl")
			E.spawn("toxic_rock", {"sprite": spr, "noElite": true, "scale": scale, "hpMul": scale * scale})
	var inside := false
	var clouds: Array = st.clouds
	for i in range(clouds.size() - 1, -1, -1):
		var c: Dictionary = clouds[i]
		c.t += dt; c.tick -= dt
		if c.t > c.dur:
			clouds.remove_at(i)
			continue
		if c.tick <= 0:
			c.tick = 0.5
			for e: En in Game.enemies:
				if e.alive and e.hittable and not e.def.prop and U.dist2(e.x, e.y, c.x, c.y) < c.r * c.r:
					Game.damageEnemy(e, e.maxHp * 0.005 if e.boss or e.mini else e.maxHp * 0.08 + 4, {"src": "toxic", "noText": true})
		if p.alive and U.dist2(p.x, p.y, c.x, c.y) < c.r * c.r * 0.8: inside = true
	# в облаке дольше 1,2 с — урон (рамка экрана зеленеет заранее)
	st.inT = st.inT + dt if inside else 0.0
	if st.inT > 1.2:
		st.inT = 0.0; Game.hitPlayer(p.x, p.y, "Ядовитое облако")


func _toxic_back(ctx: Ctx, m: Dictionary) -> void:
	var t := Game.t
	var S := G.S
	for c: Dictionary in m.st.clouds:
		var k: float = minf(1, minf(c.t * 3, (c.dur - c.t) * 1.5))
		ctx.alpha = 0.5 * k
		ctx.draw_tex(G.soft("#3dff7a", 64), c.x - c.r * 1.2, c.y - c.r * 1.2, c.r * 2.4, c.r * 2.4)
		ctx.alpha = 0.45 * k
		for i in 6:
			var a := i * 1.05 + t * 0.7
			var rr: float = c.r * (0.3 + 0.12 * ((i * 3) % 4))
			var y: float = c.y + sin(a) * rr - fmod(t * 20 * S + i * 13, c.r * 0.6)
			ctx.draw_tex(G.glow("#a6ff3d", 32), c.x + cos(a) * rr - 4 * S, y - 4 * S, 8 * S, 8 * S)
	ctx.alpha = 1.0
	if m.st.inT > 0.2:
		ctx.alpha = minf(1, m.st.inT) * 0.5
		ctx.draw_tex(FX._vignette_tex("#3dff7a"), 0, 0, G.FW, G.H)
		ctx.alpha = 1.0


# ── ГОРИЗОНТ СОБЫТИЙ: у края экрана — гравитационный колодец; гнёт все снаряды и тянет корабль ──
func _gravity_start(m: Dictionary) -> void:
	m.st.side = -1.0 if int(m.wave.n) % 2 else 1.0
	m.st.a = 0.0


func _gravity_update(m: Dictionary, dt: float) -> void:
	var S := G.S
	var st: Dictionary = m.st
	var p: Pl = Game.player
	var gx := -10 * S if st.side < 0 else G.FW + 10 * S
	var gy := G.H * 0.42
	st.a = minf(1, st.a + dt * 0.5)
	var pw: float = 260 * S * (1 + m.k * 0.25) * st.a
	var pull := func(b) -> void:
		var dx: float = gx - b.x
		var dy: float = gy - b.y
		var d := sqrt(dx * dx + dy * dy)
		if d == 0.0: d = 1.0
		var f := pw / (1 + d / (160 * S)) * dt
		b.vx += dx / d * f; b.vy += dy / d * f
	for b: Eb in Game.ebullets:
		if not b.dead and b.type != "mine": pull.call(b)
	for b: Bl in Game.bullets:
		if not b.dead and b.kind != "dark" and b.kind != "wave": pull.call(b)
	if p.alive and Game.state == "play":
		p.x += st.side * 16 * S * (1 + m.k * 0.2) * st.a * dt
		Game.clampPlayer()


func _gravity_back(ctx: Ctx, m: Dictionary) -> void:
	var S := G.S
	var st: Dictionary = m.st
	var t := Game.t
	var gx := 0.0 if st.side < 0 else G.FW
	var gy := G.H * 0.42
	var R: float = 150 * S * st.a
	ctx.additive = true
	ctx.alpha = 0.35 * st.a
	ctx.draw_tex(G.soft("#7a3dff", 64), gx - R * 1.6, gy - R * 1.6, R * 3.2, R * 3.2)
	if G.has("fx_vortex"):
		ctx.alpha = 0.75 * st.a
		G.draw(ctx, "fx_vortex", gx, gy, R * 1.5, -t * 1.8)
	ctx.additive = false
	ctx.alpha = st.a
	ctx.draw_tex(G.proc("voidcore"), gx - R * 0.3, gy - R * 0.3, R * 0.6, R * 0.6)
	ctx.alpha = 1.0


# ── СЕРДЦЕ ГАЛАКТИКИ: порывы звёздного ветра — стрелки предупреждают, потом сносит пули, бонусы и корабль ──
func _wind_start(m: Dictionary) -> void:
	m.st.gust = null; m.st.streaks = []


func _wind_update(m: Dictionary, dt: float) -> void:
	var S := G.S
	var st: Dictionary = m.st
	var p: Pl = Game.player
	m.cd -= dt
	if st.gust == null and m.cd <= 0:
		st.gust = {"t": 0.0, "dir": -1.0 if U.random() < 0.5 else 1.0, "warn": 1.1, "dur": [2, 2.3, 2.6, 3][int(m.k)]}
		A.play("warning", {"vol": 0.25, "rate": 1.6})
	var g = st.gust
	if g != null:
		g.t += dt
		if g.t > g.warn:
			var k: float = minf(1, minf((g.t - g.warn) * 3, (g.warn + g.dur - g.t) * 3))
			var v: float = g.dir * 150 * S * (1 + m.k * 0.15) * k
			for b: Eb in Game.ebullets:
				if not b.dead: b.x += v * dt * 0.8
			for it: Pk in Game.pickups:
				if not it.dead and not it.pull: it.x = U.clamp(it.x + v * dt, 10 * S, G.FW - 10 * S)
			for e: En in Game.enemies:
				if e.alive and not e.boss and not e.mini: e.x = U.clamp(e.x + v * dt * 0.25, e.w * 0.5, G.FW - e.w * 0.5)
			if p.alive and Game.state == "play":
				p.x += v * dt * 0.45; Game.clampPlayer()
			if U.random() < dt * 40:
				st.streaks.append({"x": -20 * S if g.dir > 0 else G.FW + 20 * S, "y": U.random() * G.H, "l": U.rand(30, 80) * S, "v": g.dir * U.rand(500, 800) * S})
		if g.t > g.warn + g.dur:
			st.gust = null; m.cd = [7, 6, 5.5, 5][int(m.k)] * U.rand(0.85, 1.15)
	var sk: Array = st.streaks
	for i in range(sk.size() - 1, -1, -1):
		var s: Dictionary = sk[i]
		s.x += s.v * dt
		if s.x < -100 * S or s.x > G.FW + 100 * S: sk.remove_at(i)


func _wind_back(ctx: Ctx, m: Dictionary) -> void:
	var S := G.S
	var st: Dictionary = m.st
	var g = st.gust
	var t := Game.t
	ctx.additive = true
	ctx.stroke = U.col("#ffd9a0"); ctx.line_width = 1.5 * S
	for s: Dictionary in st.streaks:
		ctx.alpha = 0.45
		ctx.stroke_line(s.x, s.y, s.x - signf(s.v) * s.l, s.y)
	# стрелки-предупреждения по центру экрана
	if g != null and g.t < g.warn:
		ctx.alpha = 0.5 + 0.5 * absf(sin(t * 10))
		ctx.fill = U.col("#ffc83d")
		for i in 3:
			var x: float = G.FW / 2 + g.dir * (i - 1) * 34 * S
			var y := G.H * 0.5
			var s := 14 * S
			ctx.begin_path(); ctx.move_to(x + g.dir * s, y); ctx.line_to(x - g.dir * s * 0.5, y - s); ctx.line_to(x - g.dir * s * 0.5, y + s); ctx.close_path(); ctx.fill_path()
	ctx.alpha = 1.0
	ctx.additive = false


# ── КРИСТАЛЬНЫЙ ПОЯС: кристаллы закрывают от пуль и преломляют ваши выстрелы веером из трёх (Game.collide) ──
func _prism_update(m: Dictionary, dt: float) -> void:
	m.cd -= dt
	if m.cd > 0: return
	m.cd = [3, 2.5, 2.1, 1.8][int(m.k)] * U.rand(0.8, 1.2)
	if count("prism_rock") >= [2, 3, 4, 4][int(m.k)]: return
	var scale: float = U.rand(0.85, 1.2) + m.k * 0.05
	E.spawn("prism_rock", {"sprite": "astc_m" if scale < 1 else ("astc_l" if scale < 1.15 else "astc_xl"), "noElite": true, "scale": scale, "hpMul": scale * scale})


# ── ПУСТОШЬ ХАОСА: пара порталов перебрасывает любые снаряды из одного в другой; порталы иногда переезжают ──
func _portals_start(m: Dictionary) -> void:
	m.st.p = null; m.st.t = 0.0


func _portals_update(m: Dictionary, dt: float) -> void:
	var S := G.S
	var st: Dictionary = m.st
	st.t -= dt
	if st.t <= 0:
		st.t = [11, 10, 9, 8][int(m.k)]
		var y1 := U.rand(0.22, 0.45) * G.H
		var y2 := U.rand(0.22, 0.45) * G.H
		st.p = [{"x": U.rand(0.12, 0.38) * G.FW, "y": y1, "born": Game.t}, {"x": U.rand(0.62, 0.88) * G.FW, "y": y2, "born": Game.t}]
		for o: Dictionary in st.p: FX.portal(o.x, o.y, 64 * S, "#ff7a2a", true)
		A.play("teleport", {"rate": 0.7, "vol": 0.5})
	if st.p == null: return
	var R := 24 * S
	var ps: Array = st.p
	var hop := func(b) -> void:
		if b.dead or (b.tpT > 0 and Game.t - b.tpT < 0.4): return
		for i in 2:
			var a: Dictionary = ps[i]
			var o: Dictionary = ps[1 - i]
			if U.dist2(b.x, b.y, a.x, a.y) < R * R:
				b.x = o.x; b.y = o.y; b.px = b.x; b.py = b.y; b.tpT = Game.t
				FX.glow_puff(o.x, o.y, "#ff9f3d", 26 * S, 0.2)
				return
	for b: Eb in Game.ebullets: hop.call(b)
	for b: Bl in Game.bullets:
		if b.kind != "wave" and b.kind != "dark": hop.call(b)


func _portals_back(ctx: Ctx, m: Dictionary) -> void:
	var st: Dictionary = m.st
	var S := G.S
	var t := Game.t
	if st.p == null: return
	ctx.additive = true
	for o: Dictionary in st.p:
		var k: float = minf(1, (t - o.born) * 2)
		ctx.alpha = 0.5 * k
		ctx.draw_tex(G.soft("#ff7a2a", 64), o.x - 40 * S, o.y - 40 * S, 80 * S, 80 * S)
		ctx.alpha = 0.9 * k
		if G.has("fx_portal_out"): G.draw_canvas(ctx, G.tinted("fx_portal_out", {"hue": 25}), o.x, o.y, 58 * S * k, t * 1.5)
	ctx.alpha = 1.0
	ctx.additive = false


# ── ЦИТАДЕЛЬ ИНКВИЗИЦИИ: столпы света бьют сверху по всем — подставляйте под них врагов ──
func _pillars_update(m: Dictionary, dt: float) -> void:
	var S := G.S
	var p: Pl = Game.player
	m.cd -= dt
	if m.cd > 0: return
	m.cd = [4.2, 3.6, 3.1, 2.6][int(m.k)] * U.rand(0.85, 1.15)
	var near := U.random() < 0.4
	var x := p.x + U.rand(-30, 30) * S if near else U.rand(0.1, 0.9) * G.FW
	if not near:
		var es := Game.enemies.filter(func(e): return e.alive and not e.boss and not e.def.prop)
		if not es.is_empty() and U.random() < 0.6: x = U.pick(es).x
	Game.ov.beams.append({"x": U.clamp(x, 20 * S, G.FW - 20 * S), "y0": 0.0, "w": 20 * S, "warn": 1.1, "dur": 0.5, "t": 0.0, "color": "#ffd23d", "hitDone": false, "owner": null, "foes": true})
	A.play("railCharge", {"vol": 0.3, "rate": 1.3})


# ── ТРОН ОВЕРЛОРДА: Око открывается и следит — стоите на месте дольше секунды, по вам бьёт луч ──
func _eye_start(m: Dictionary) -> void:
	m.st.ph = "closed"; m.st.t = 3.0; m.st.still = 0.0; m.st.lx = null; m.st.ly = 0.0; m.st.cool = 0.0; m.st.open = 0.0


func _eye_update(m: Dictionary, dt: float) -> void:
	var S := G.S
	var st: Dictionary = m.st
	var p: Pl = Game.player
	st.t -= dt
	if st.ph == "closed" and st.t <= 0:
		st.ph = "open"; st.t = [4, 4.5, 5, 5.5][int(m.k)]; A.play("bossRoar", {"vol": 0.25, "rate": 1.8})
	elif st.ph == "open" and st.t <= 0:
		st.ph = "closed"; st.t = [7, 6.5, 6, 5.5][int(m.k)] * U.rand(0.85, 1.15)
	st.open = U.damp(st.open, 1.0 if st.ph == "open" else 0.0, 6, dt)
	st.cool -= dt
	if st.ph != "open" or not p.alive:
		st.still = 0.0; st.lx = null
		return
	if st.lx != null and Vector2(p.x - st.lx, p.y - st.ly).length() > 24 * S:
		st.still = 0.0; st.lx = p.x; st.ly = p.y
	if st.lx == null:
		st.lx = p.x; st.ly = p.y
	st.still += dt
	if st.still > 1.1 and st.cool <= 0:
		st.still = 0.0; st.cool = 1.6; st.lx = null
		Game.ov.beams.append({"x": p.x, "y0": 0.0, "w": 18 * S, "warn": 0.6, "dur": 0.4, "t": 0.0, "color": "#ff3d8b", "hitDone": false, "owner": null})
		A.play("railCharge", {"vol": 0.45, "rate": 1.5})


func _eye_back(ctx: Ctx, m: Dictionary) -> void:
	var S := G.S
	var st: Dictionary = m.st
	var k: float = st.open
	var t := Game.t
	if k < 0.02: return
	var x := G.FW / 2
	var y: float = Hud.top_inset() + 34 * S
	var w := 70 * S
	var h := maxf(1, 26 * S * k)
	var hot: bool = st.still > 0.5
	ctx.additive = true
	ctx.alpha = 0.35 * k
	ctx.draw_tex(G.soft("#ff3d5a" if hot else "#c03dff", 64), x - w * 1.3, y - w * 0.8, w * 2.6, w * 1.6)
	ctx.additive = false
	# веко и зрачок, который следит за кораблём
	ctx.alpha = 0.85 * k
	ctx.fill = U.col("#12051c"); ctx.stroke = U.col("#ff6b7d" if hot else "#d07bff"); ctx.line_width = 2.5 * S
	ctx.begin_path(); ctx.ellipse(x, y, w, h, 0, 0, TAU); ctx.fill_path(); ctx.stroke_path()
	var px := x + U.clamp((Game.player.x - x) / G.FW, -0.5, 0.5) * w * 1.1
	# в JS зрачок обрезался по веку (clip); здесь — сплющивается до высоты века над зрачком
	var lid := h * sqrt(maxf(0, 1 - pow((px - x) / w, 2)))
	ctx.fill = U.col("#ff3d5a" if hot else "#ff3d8b")
	ctx.begin_path(); ctx.ellipse(px, y, 15 * S, minf(15 * S, lid), 0, 0, TAU); ctx.fill_path()
	ctx.fill = Color.BLACK
	ctx.begin_path(); ctx.ellipse(px, y, 4 * S, minf(11 * S * (0.7 + 0.3 * sin(t * 3)), lid), 0, 0, TAU); ctx.fill_path()
	ctx.alpha = 1.0
