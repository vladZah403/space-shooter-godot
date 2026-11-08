extends Node
## Активные импланты (автозагрузка Skills) — перенос skills.js.
##  Запуск каждого импланта со своей анимацией (cast) и работа тех, которым нужно своё состояние:
##  Орбитальный удар, Турель, ЭМИ, Двойник, отражение пуль Барьером. Рельса, Замедление и Чёрная дыра
##  живут в game.gd (ov.rail, ov.hole, enemySlow).

var orb = null       # орбитальный удар: { t, marks: [{ e, x, y, at, fired, ft }] }
var turret = null    # турель: { x, y, cd, flash, ang }
var clone = null     # двойник: { x, y, t }
var casts: Array = []  # анимации запуска: { kind, t, dur, x, y, color }


func reset() -> void:
	orb = null; turret = null; clone = null; casts.clear()


func _cast(kind: String, dur: float, x: float, y: float, color: String) -> void:
	casts.append({"kind": kind, "t": 0.0, "dur": dur, "x": x, "y": y, "color": color})


# ════════════════════════════════════════════════════════════
# ЗАПУСК
# ════════════════════════════════════════════════════════════
func cast(id: String, sk: Dictionary) -> void:
	var p: Pl = Game.player
	var S := G.S
	match id:
		"sk_rail":
			Game.ov.rail = {"t": 0.0, "dur": sk.dur, "tick": 0.0, "charge": 0.35}
			_cast("converge", 0.35, p.x, p.y - p.w * 0.55, "#7ffff0")
			A.play("railCharge")
		"sk_orbital":
			# цели — самые крепкие враги на экране, по очереди
			var es: Array = Game.enemies.filter(func(e): return e.alive and e.hittable and e.y > 40 * S and e.y < G.H * 0.85 and not Foes.hidden(e))
			es.sort_custom(func(a, b): return a.hp > b.hp)
			es = es.slice(0, 6)
			var marks: Array = []
			for i in es.size():
				var e: En = es[i]
				marks.append({"e": e, "x": e.x, "y": e.y, "at": 0.85 + i * 0.12, "fired": false, "ft": 0.0})
			if es.is_empty(): marks.append({"e": null, "x": G.FW / 2, "y": G.H * 0.3, "at": 0.85, "fired": false, "ft": 0.0})
			orb = {"t": 0.0, "marks": marks}
			_cast("satellite", 1.6, 0, 0, "#ff5c4d")
			A.play("railCharge", {"rate": 1.3, "vol": 0.5})
		"sk_barrier":
			FX.ring(p.x, p.y, p.w * 0.3, p.w * 1.7, "#ffd23d", 0.5, 5)
			FX.sprite("fx_sh_restore", 0, 0, {"follow": p, "w0": p.w * 2.6, "w1": p.w * 1.4, "dur": 0.5, "hold": 0.4, "hue": 46})
			_cast("hex", 0.6, p.x, p.y, "#ffd23d")
			A.play("shieldHit", {"rate": 0.7})
		"sk_timewarp":
			FX.flash("#3d6bff", 0.25)
			_cast("clock", 1.1, p.x, p.y, "#9fc8ff")
			A.play("teleport", {"rate": 0.5})
		"sk_turret":
			turret = {"x": p.x - p.w, "y": p.y - p.w * 0.9, "cd": 0.4, "flash": 0.0, "ang": -PI / 2}
			_cast("portal", 0.45, turret.x, turret.y, "#b06bff")
			A.play("teleport", {"rate": 1.4})
		"sk_blackhole":
			Game.ov.hole = {"x": G.FW / 2, "y": G.H * 0.32, "t": 0.0, "dur": sk.dur, "tick": 0.0}
			_cast("implode", 0.6, G.FW / 2, G.H * 0.32, "#b06bff")
			A.play("dark", {"rate": 0.6})
		"sk_emp":
			emp()
		"sk_clone":
			clone = {"x": p.x + p.w, "y": p.y, "t": 0.0}
			_cast("scan", 0.45, 0, 0, "#3de0ff")
			A.play("teleport", {"rate": 1.8, "vol": 0.6})


## ЭМИ: кольцо через весь экран, разряды к врагам; враги замирают и теряют щиты
func emp() -> void:
	var p: Pl = Game.player
	var S := G.S
	var diag := Vector2(G.FW, G.H).length()
	FX.ring(p.x, p.y, 10 * S, diag, "#7fe7ff", 0.7, 6)
	FX.ring(p.x, p.y, 10 * S, diag * 0.7, "#ffffff", 0.5, 2)
	FX.flash("#7fe7ff", 0.2)
	FX.shake(0.3)
	A.play("zap", {"rate": 0.6})
	var n := 0
	for e: En in Game.enemies:
		if not e.alive or e.def.prop: continue
		e.emp = 1.5 if e.boss else 3.0
		if e.shield > 0:
			e.shield = 0.0; FX.sparks(e.x, e.y, "#7fd8ff", 10, 260)
		e.barrier = 0.0
		if n < 6: FX.lightning(p.x, p.y - p.w * 0.4, e.x, e.y, "#9fe8ff", 2.2 * S, 0.25)
		n += 1


# ════════════════════════════════════════════════════════════
# ОБНОВЛЕНИЕ
# ════════════════════════════════════════════════════════════
func update(dt: float) -> void:
	var p: Pl = Game.player
	var run: Dictionary = Game.run
	var S := G.S
	for i in range(casts.size() - 1, -1, -1):
		casts[i].t += dt
		if casts[i].t >= casts[i].dur: casts.remove_at(i)
	# орбитальный удар: прицелы держат цель, потом луч с орбиты
	if orb != null:
		orb.t += dt
		var left := 0
		for m: Dictionary in orb.marks:
			var me = m.e
			if me != null and me.alive:
				m.x = me.x; m.y = me.y
			if not m.fired and orb.t >= m.at:
				m.fired = true
				FX.explode(m.x, m.y, 1.4, "#ff8a3d")
				FX.ring(m.x, m.y, 6 * S, 70 * S, "#ff5c4d", 0.35, 4)
				FX.shake(0.15)
				A.play("explodeM", {"vol": 0.55})
				for e: En in Game.enemies:
					if not e.alive or not e.hittable or not Game.inBlast(e, m.x, m.y, 60 * S): continue
					Game.damageEnemy(e, (110 if e.boss else 190) * Game.dmgMul() * (1 + Game.wave.n * 0.06), {"src": "orbital", "heavy": true})
			if m.fired: m.ft += dt
			if not m.fired or m.ft < 0.4: left += 1
		if not left: orb = null
	# турель: висит над кораблём и бьёт ближайших
	if turret != null:
		var t: Dictionary = turret
		if not (run.skillFx.get("sk_turret", 0.0) > 0) or not p.alive:
			FX.glow_puff(t.x, t.y, "#b06bff", 50 * S, 0.3); turret = null
		else:
			t.x = U.damp(t.x, U.clamp(p.x - p.w * 1.05, 20 * S, G.FW - 20 * S), 6, dt)
			t.y = U.damp(t.y, p.y - p.w * 0.85 + sin(Game.t * 3) * 4 * S, 6, dt)
			t.cd -= dt; t.flash -= dt
			var tgt: En = null
			var bd := 480 * S
			for e: En in Game.enemies:
				if not e.alive or not e.hittable or e.y > t.y or Foes.hidden(e): continue
				var d := Vector2(e.x - t.x, e.y - t.y).length()
				if d < bd:
					bd = d; tgt = e
			if tgt: t.ang = U.damp(t.ang, atan2(tgt.y - t.y, tgt.x - t.x), 12, dt)
			if t.cd <= 0 and tgt and Game.state == "play":
				t.cd = 0.15
				t.flash = 0.06
				var sp := 900 * S
				Game.spawnShot({"x": t.x + cos(t.ang) * 14 * S, "y": t.y + sin(t.ang) * 14 * S, "vx": cos(t.ang) * sp, "vy": sin(t.ang) * sp,
					"dmg": 9 * Game.dmgMul(), "r": 4 * S, "kind": "drone", "sprite": "pb_bolt_s", "w": 11 * S, "wid": "turret", "life": 1.2})
				if U.random() < 0.4: A.play("laser", {"vol": 0.25, "rate": 1.6})
	# двойник летит рядом (у края — с другой стороны)
	if clone != null:
		var c: Dictionary = clone
		c.t += dt
		if not (run.skillFx.get("sk_clone", 0.0) > 0) or not p.alive:
			FX.glow_puff(c.x, c.y, "#3de0ff", 60 * S, 0.3); clone = null
		else:
			var side := -1.0 if p.x > G.FW - p.w * 1.6 else 1.0
			c.x = U.damp(c.x, p.x + side * p.w * 1.05, 10, dt)
			c.y = U.damp(c.y, p.y + p.w * 0.15, 10, dt)
	# заглушённые ЭМИ враги искрят
	if FX.quality > 0:
		for e: En in Game.enemies:
			if e.alive and e.emp > 0 and U.random() < dt * 6:
				var a := U.random() * TAU
				var r := (e.rx if e.rx != 0.0 else e.r) * 0.9
				FX.lightning(e.x + cos(a) * r, e.y + sin(a) * r, e.x + U.rand(-0.3, 0.3) * e.w, e.y + U.rand(-0.3, 0.3) * e.h, "#9fe8ff", 1.4 * S, 0.12)


## Барьер: пуля, коснувшаяся барьера, летит обратно — в ближайшего врага
func reflect(b: Eb) -> bool:
	var p: Pl = Game.player
	var S := G.S
	if not (Game.run.skillFx.get("sk_barrier", 0.0) > 0) or Vector2(b.x - p.x, b.y - p.y).length() > p.w * 0.85: return false
	var tgt: En = null
	var bd := INF
	for e: En in Game.enemies:
		if not e.alive or not e.hittable: continue
		var d := Vector2(e.x - b.x, e.y - b.y).length()
		if d < bd:
			bd = d; tgt = e
	var a := atan2(tgt.y - b.y, tgt.x - b.x) if tgt else -PI / 2
	var sp := 760 * S
	Game.spawnShot({"x": b.x, "y": b.y, "vx": cos(a) * sp, "vy": sin(a) * sp, "dmg": 14 * Game.dmgMul(), "r": 5 * S, "kind": "drone", "sprite": "pb_bolt_s", "w": 12 * S, "wid": "barrier", "life": 1.2})
	FX.hit(b.x, b.y, "#ffd23d")
	return true


## Двойник повторяет выстрелы: копии новых снарядов этого кадра со сдвигом, урон 60%
func echo(from: int) -> void:
	var c = clone
	var p: Pl = Game.player
	if c == null: return
	var dx: float = c.x - p.x
	var dy: float = c.y - p.y
	var bs: Array = Game.bullets
	var n := bs.size()
	for i in range(from, n):
		var b: Bl = bs[i]
		if b.dead or b.wid == "turret" or b.wid == "barrier" or b.wid == "drone": continue
		Game.spawnShot({"x": b.x + dx, "y": b.y + dy, "vx": b.vx, "vy": b.vy, "dmg": b.dmg * 0.6, "r": b.r, "kind": b.kind, "sprite": b.sprite, "cv": b.cv, "w": b.w, "w1": b.w1, "ch": b.ch,
			"pierce": b.pierce, "life": b.life, "homing": b.homing, "aoe": b.aoe * 0.6, "aoeR": b.aoeR, "acc": b.acc, "maxSpd": b.maxSpd, "tickT": b.tickT, "pull": b.pull,
			"burst": b.burst * 0.6, "burstR": b.burstR, "wid": b.wid})


# ════════════════════════════════════════════════════════════
# ОТРИСОВКА
# ════════════════════════════════════════════════════════════
## под кораблём: прицелы и лучи орбитального удара
func drawBack(ctx: Ctx) -> void:
	var S := G.S
	if orb == null: return
	ctx.additive = true
	for m: Dictionary in orb.marks:
		if not m.fired:
			# прицел: четыре уголка сжимаются на цели к моменту удара
			var k := U.clamp(orb.t / m.at, 0, 1)
			var r := (60 - 36 * k) * S
			var rot := (1 - k) * 2
			ctx.alpha = 0.35 + 0.6 * k * (0.6 + 0.4 * sin(Game.t * 30))
			ctx.stroke = U.col("#ff5c4d"); ctx.line_width = 2 * S
			for q in 4:
				var a := rot + q * PI / 2
				ctx.begin_path(); ctx.arc(m.x, m.y, r, a - 0.35, a + 0.35); ctx.stroke_path()
			ctx.alpha = 0.5 * k
			ctx.fill = U.col("#ff9f8a"); ctx.fill_circle(m.x, m.y, 3 * S)
			# тонкая нить с орбиты перед ударом
			if k > 0.6: Game.drawBeamV(ctx, m.x, 0, m.y, 1.5 * S, "#ff5c4d", (k - 0.6) * 1.2, 1)
		elif m.ft < 0.4:
			var f: float = 1 - m.ft / 0.4
			Game.drawBeamV(ctx, m.x, 0, m.y, 16 * S * (0.5 + 0.5 * f), "#ff6a3d", f, 1, m.y)
	ctx.alpha = 1.0
	ctx.additive = false


## над кораблём: турель, двойник, анимации запуска
func drawFront(ctx: Ctx) -> void:
	var S := G.S
	var p: Pl = Game.player
	var t := Game.t
	var s: Dictionary = M.s
	var c = clone
	if c != null:
		# голограмма: полупрозрачный корабль с бегущими полосами развёртки
		var born := U.clamp(c.t / 0.45, 0, 1)
		ctx.save()
		ctx.clip_rect(c.x - p.w, c.y + p.w * (0.8 - 1.8 * born), p.w * 2, p.w * 2)
		ctx.alpha = (0.42 + 0.08 * sin(t * 23)) * (0.4 if U.random() < 0.04 else 1.0)
		Game.drawShip(ctx, s.ship.model, s.ship.skin, s.ship.trail, c.x, c.y, p.w, p.tilt, t, 1, Game.run.get("parts"))
		ctx.restore()
		ctx.additive = true
		ctx.alpha = 0.25
		ctx.draw_tex(G.soft("#3de0ff", 64), c.x - p.w, c.y - p.w, p.w * 2, p.w * 2)
		ctx.alpha = 0.18; ctx.fill = U.col("#7ff6ff")
		var y: float = c.y - p.w * 0.6 + fmod(t * 40 * S, 6 * S)
		while y < c.y + p.w * 0.6:
			ctx.fill_rect(c.x - p.w * 0.5, y, p.w, 1 * S)
			y += 6 * S
		ctx.alpha = 1.0
		ctx.additive = false
	var tu = turret
	if tu != null:
		var w := p.w * 0.75
		ctx.additive = true
		ctx.alpha = 0.35 + 0.1 * sin(t * 8)
		ctx.draw_tex(G.soft("#b06bff", 64), tu.x - w, tu.y - w, w * 2, w * 2)
		if tu.flash > 0:
			ctx.alpha = 1.0
			var fx: float = tu.x + cos(tu.ang) * w * 0.55
			var fy: float = tu.y + sin(tu.ang) * w * 0.55
			ctx.draw_tex(G.glow("#e0c8ff", 32), fx - 8 * S, fy - 8 * S, 16 * S, 16 * S)
		ctx.additive = false
		ctx.alpha = 1.0
		G.draw(ctx, "sp_radar", tu.x, tu.y, w, tu.ang + PI / 2)
	if casts.is_empty(): return
	ctx.additive = true
	for k: Dictionary in casts: drawCast(ctx, k, p, S, t)
	ctx.alpha = 1.0
	ctx.line_width = 1.0
	ctx.additive = false


func drawCast(ctx: Ctx, k: Dictionary, p: Pl, S: float, t: float) -> void:
	var f: float = k.t / k.dur
	ctx.stroke = U.col(k.color); ctx.fill = U.col(k.color)
	match k.kind:
		"converge":
			# искры стягиваются к носу корабля
			var x := p.x
			var y := p.y - p.w * 0.55
			for i in 14:
				var a := i / 14.0 * TAU + i * 0.7
				var r := (80 - 74 * f) * S
				ctx.alpha = 0.3 + 0.7 * f
				ctx.draw_tex(G.glow(k.color, 32), x + cos(a) * r - 4 * S, y + sin(a) * r - 4 * S, 8 * S, 8 * S)
		"hex":
			# соты барьера разбегаются от корабля
			var R := p.w * (0.4 + 0.5 * f)
			ctx.alpha = 1 - f; ctx.line_width = 2 * S
			for i in 6:
				var a := i / 6.0 * TAU + f
				hexagon(ctx, p.x + cos(a) * R, p.y + sin(a) * R, 9 * S)
		"clock":
			# циферблат: кольцо с делениями расходится, стрелки крутятся назад
			var R := (40 + 150 * f) * S
			ctx.alpha = 0.8 * (1 - f); ctx.line_width = 2.5 * S
			ctx.begin_path(); ctx.arc(p.x, p.y, R, 0, TAU); ctx.stroke_path()
			for i in 12:
				var a := i / 12.0 * TAU
				ctx.stroke_line(p.x + cos(a) * R * 0.86, p.y + sin(a) * R * 0.86, p.x + cos(a) * R, p.y + sin(a) * R)
			ctx.line_width = 3 * S
			for hand in [[0.55, -9.0], [0.8, -26.0]]:
				var a: float = -PI / 2 + t * hand[1]
				ctx.stroke_line(p.x, p.y, p.x + cos(a) * R * hand[0], p.y + sin(a) * R * hand[0])
		"portal":
			var r := 26 * S * sin(minf(1, f * 1.4) * PI / 2)
			ctx.alpha = 1 - f * 0.6; ctx.line_width = 2.5 * S
			var px: float = turret.x if turret != null else k.x
			var py: float = turret.y if turret != null else k.y
			ctx.begin_path(); ctx.ellipse(px, py, r, r * 0.45, 0, 0, TAU); ctx.stroke_path()
		"implode":
			# спираль частиц сходится в центр дыры
			for i in 18:
				var a := i / 18.0 * TAU + f * 6
				var r := (180 - 170 * f) * S * (0.6 + 0.4 * ((i * 7) % 5) / 5.0)
				ctx.alpha = 0.25 + 0.6 * f
				ctx.draw_tex(G.glow(k.color, 32), k.x + cos(a) * r - 5 * S, k.y + sin(a) * r - 5 * S, 10 * S, 10 * S)
		"scan":
			# двойник собирается полосой развёртки
			var c = clone
			if c == null: return
			var y: float = c.y + p.w * (0.8 - 1.8 * f)
			ctx.alpha = 0.9 * (1 - f * 0.5); ctx.fill_rect(c.x - p.w * 0.6, y - 1.5 * S, p.w * 1.2, 3 * S)
			ctx.alpha = 0.4; ctx.draw_tex(G.glow(k.color, 32), c.x - p.w * 0.7, y - 10 * S, p.w * 1.4, 20 * S)
		"satellite":
			# спутник проходит по верху экрана и раздаёт целеуказание
			var x := U.lerp(-30 * S, G.FW + 30 * S, f)
			var y: float = Hud.top_inset() + 8 * S
			ctx.alpha = 0.5
			ctx.draw_tex(G.glow(k.color, 32), x - 18 * S, y - 18 * S, 36 * S, 36 * S)
			ctx.additive = false
			ctx.alpha = 1.0
			G.draw(ctx, "sp_radar", x, y, 26 * S, PI)
			ctx.additive = true


func hexagon(ctx: Ctx, x: float, y: float, r: float) -> void:
	ctx.begin_path()
	for i in 7:
		var a := i / 6.0 * TAU + PI / 6
		if i: ctx.line_to(x + cos(a) * r, y + sin(a) * r)
		else: ctx.move_to(x + cos(a) * r, y + sin(a) * r)
	ctx.stroke_path()
