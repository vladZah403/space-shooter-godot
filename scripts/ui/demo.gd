class_name Demo
extends RefCounted
## Живые превью (перенос demo.js): маленькие сцены в интерфейсе — корабль внизу стреляет выбранным оружием
## по трём мишеням (арсенал; с evo — эволюция оружия), показывает активный имплант (карточка импланта) или
## событие волны / аномалию сектора (окно-подсказка). Логика упрощённая — задача показать «форму» механики.
## Использование: Kit.ctx_view(Demo.weapon("laser").draw, Vector2(0, 160)).

const TARGETS := ["scout", "drone", "shooter"]
const SCENES := ["storm", "meteors", "solar", "debris", "convoy", "ionwind", "flagship", "swarm", "unstable"]
const MDIR := Vector2(-0.63, 0.77)
const MHEAD := {"fx_meteor1": [0.2, 0.81], "fx_meteor2": [0.24, 0.82]}

static func weapon(wid: String, evo := false) -> Scene:
	var d := WeaponDemo.new()
	d.wid = wid; d.evo = evo
	return d


static func skill(id: String) -> Scene:
	var d := SkillDemo.new()
	d.id = id
	return d


static func hasScene(key: String) -> bool:
	return key in SCENES


static func scene(key: String) -> Scene:
	var d := SceneDemo.new()
	d.key = key
	return d


## общая часть сцен: размер области, время кадра, фон, мишени, эффекты
class Scene extends RefCounted:
	var t := 0.0
	var _lastT := 0.0
	var W := 300.0
	var H := 160.0
	var k := 1.0
	var ship := {"x": 0.0, "y": 0.0, "w": 40.0, "hitT": 0.0}
	var stars: Array = []
	var tg: Array = []
	var shots: Array = []
	var fx: Array = []
	var eb: Array = []
	var inited := false


	## общий шаг: размер области, время кадра, фон со звёздами
	func draw(c: Ctx, sz: Vector2, tt: float) -> void:
		var dt := minf(0.05, maxf(0.0, tt - _lastT))
		_lastT = tt
		if sz.x < 10 or sz.y < 10: return
		if not inited or absf(sz.x - W) > 1 or absf(sz.y - H) > 1:
			W = sz.x; H = sz.y
			k = clampf(W / 340, 0.8, 1.3)
			init()
			inited = true
		t += dt
		step(c, dt)


	func init() -> void:
		stars.clear()
		for i in 40: stars.append({"x": U.random() * W, "y": U.random() * H, "v": U.rand(8, 30), "a": U.rand(0.2, 0.7)})


	func step(_c: Ctx, _dt: float) -> void:
		pass


	func _bg(c: Ctx, dt: float, speed := 1.0) -> void:
		c.fill_poly(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)]), PackedColorArray([Color("#060a1f"), Color("#060a1f"), Color("#0b1238"), Color("#0b1238")]))
		c.fill = Color("#cfe3ff")
		for st in stars:
			st.y += st.v * dt * speed
			if st.y > H:
				st.y = 0.0; st.x = U.random() * W
			c.alpha = st.a
			c.fill_rect(st.x, st.y, 1.2, 1.2)
		c.alpha = 1.0


	## мишень носом вниз; вспышка при попадании
	func _target(c: Ctx, e: Dictionary, glow_col := "") -> void:
		if glow_col != "":
			c.additive = true; c.alpha = 0.5
			c.draw_tex(G.soft(glow_col, 64), e.x - e.w * 0.7, e.y - e.w * 0.7, e.w * 1.4, e.w * 1.4)
			c.additive = false; c.alpha = 1.0
		c.save(); c.translate(e.x, e.y); c.rotate(PI)
		var f := G.frame(e.spr)
		if not f.is_empty():
			var h: float = e.w * f[3] / f[2]
			c.draw_image(G.src(f), f[0], f[1], f[2], f[3], -e.w / 2, -h / 2, e.w, h)
			if e.get("flash", 0.0) > 0:
				var wh := G.white(e.spr)
				if wh:
					c.additive = true; c.alpha = 0.7
					c.draw_tex(wh, -e.w / 2, -h / 2, e.w, h)
		c.restore()


	func _alive() -> Array:
		return tg.filter(func(e): return not e.dead)


	func _nearest(x: float, y: float, above := false):
		var b = null
		var bd := 1e9
		for e in _alive():
			if above and e.y > y: continue
			var d := Vector2(e.x - x, e.y - y).length()
			if d < bd:
				bd = d; b = e
		return b


	func _hit(e, dmg: float) -> void:
		if e == null or e.dead: return
		e.hp -= dmg; e.flash = 0.08
		if e.hp <= 0:
			e.dead = 0.7
			fx.append({"kind": "boom", "x": e.x, "y": e.y, "t": 0.0, "r": e.w * 1.4})


	func _fx(c: Ctx) -> void:
		for f in fx:
			var q: float = f.t / 0.5
			match f.kind:
				"boom":
					c.additive = true
					G.draw(c, "fx_ex_l", f.x, f.y, f.r * (0.6 + q), 0, maxf(0, 1 - q))
					c.additive = false
				"ring":
					c.alpha = maxf(0, 1 - q); c.stroke = U.col(f.col); c.line_width = 2 * k
					c.begin_path(); c.arc(f.x, f.y, f.r * (0.4 + 0.6 * q), 0, TAU); c.stroke_path()
					c.alpha = 1.0


	func _ship(c: Ctx, px: float, dt: float) -> void:
		var s: Dictionary = M.s
		Game.drawShip(c, s.ship.model, s.ship.skin, s.ship.trail, ship.x, ship.y, ship.w, (ship.x - px) / maxf(dt, 0.001) * 0.002, t, 1.0)
		if ship.hitT > 0:
			c.additive = true; c.alpha = ship.hitT * 3
			c.draw_tex(G.soft("#ff5c7a", 64), ship.x - ship.w * 0.6, ship.y - ship.w * 0.6, ship.w * 1.2, ship.w * 1.2)
			c.additive = false; c.alpha = 1.0


# ════════════════════════════════════════════════════════════
# ОРУЖИЕ: залп и перезарядка ракет, дробь в упор, волны серпа, рост плазмы, цепь молнии, сфера т. материи
# ════════════════════════════════════════════════════════════
class WeaponDemo extends Scene:
	var wid := "laser"
	var evo := false
	var def: Dictionary
	var cd := 0.3
	var mag := 0
	var reload := 0.0
	var sphere = null
	var charge := 0.0
	var trail: Array = []
	var baseY := 0.0
	var flailA := 0.0   # Godot: угол пилы на цепи
	var flailHit := {}

	func init() -> void:
		super.init()
		def = D.WEAPONS[wid]
		ship = {"x": W / 2, "y": H - 30 * k, "w": 40 * k, "hitT": 0.0}
		baseY = ship.y
		tg.clear(); shots.clear(); fx.clear(); eb.clear(); trail.clear()
		for i in 3:
			tg.append({"spr": TARGETS[i], "x": W * (0.25 + i * 0.25), "y": 34 * k + (i % 2) * 14 * k, "w": 30 * k, "hp": 100.0, "flash": 0.0, "dead": 0.0,
				"ph": i * 2.0, "frozen": 0.0, "burn": 0.0, "burnT": 0.0, "cd": 0.6 + i * 0.4})
		mag = int(def.base.mag)
		sphere = null

	func _nose() -> Vector2:
		return Vector2(ship.x, ship.y - ship.w * 0.45)

	func _fire() -> void:
		var n := _nose()
		match wid:
			"laser": shots.append({"k": "bolt", "x": n.x, "y": n.y, "vx": 0.0, "vy": -520 * k, "w": (9 if evo else 12) * k, "spr": "pb_laser" if evo and G.has("pb_laser") else "pb_bolt_m", "pierce": evo, "hit": [], "age": 0.0})
			"shotgun":
				for i in 7:
					var a := (i / 6.0 - 0.5) * 0.8
					shots.append({"k": "pellet", "x": n.x, "y": n.y, "vx": sin(a) * 430 * k, "vy": -cos(a) * 430 * k, "w": 10 * k, "life": 0.42, "age": 0.0})
			"rocket":
				var side := 1.0 if mag % 2 else -1.0
				shots.append({"k": "rocket", "x": n.x + side * 10 * k, "y": n.y + 8 * k, "vx": side * 120 * k, "vy": -80 * k, "w": 10 * k, "tgt": null, "age": 0.0})
			"arc": shots.append({"k": "wave", "x": n.x, "y": n.y, "vy": -300 * k, "age": 0.0, "life": 0.6, "hit": [], "ch": charge})
			"plasma": shots.append({"k": "plasma", "x": n.x, "y": n.y, "vx": 0.0, "vy": -230 * k, "age": 0.0, "tr": 0.0})
			"lightning":
				var pts: Array = [Vector2(n.x, n.y)]
				var done: Array = []
				var cx := n.x
				var cy := n.y
				for j in 3:
					var b = null
					var bd := 1e9
					for e in _alive():
						if e in done: continue
						var d := Vector2(e.x - cx, e.y - cy).length()
						if d < bd:
							bd = d; b = e
					if b == null: break
					done.append(b); pts.append(Vector2(b.x, b.y)); _hit(b, 22 * pow(0.8, j))
					if evo: b.frozen = 2.0
					cx = b.x; cy = b.y
				fx.append({"kind": "bolt", "pts": pts, "t": 0.0})
			"darkmatter": sphere = {"x": n.x, "y": n.y, "vy": -200 * k, "age": 0.0, "tick": 0.0}
			"boomerang":
				if shots.filter(func(b): return b.k == "boom").size() < 2:
					var sd := 1.0 if int(t * 10) % 2 else -1.0
					shots.append({"k": "boom", "x": n.x, "y": n.y, "vx": sd * 90 * k, "vy": -380 * k, "sd": sd, "back": false, "hit": [], "age": 0.0})
			"gravgun": shots.append({"k": "slug", "x": n.x, "y": n.y, "vx": 0.0, "vy": -420 * k, "age": 0.0})

	func step(c: Ctx, dt: float) -> void:
		var px: float = ship.x
		ship.x = W / 2 + sin(t * (1.6 if wid == "arc" else 0.7)) * W * (0.22 if wid == "arc" else 0.1)
		# пила: корабль подлетает к мишеням, пила кружит вокруг и режет
		if wid == "flail":
			ship.y = baseY - (0.5 + 0.5 * sin(t * 1.2)) * (baseY - 90 * k)
			flailA += dt * 5.5
			var sx: float = ship.x + cos(flailA) * 58 * k
			var sy: float = ship.y + sin(flailA) * 58 * k
			for e in _alive():
				if Vector2(e.x - sx, e.y - sy).length() < 20 * k and t >= flailHit.get(e, -1.0):
					flailHit[e] = t + 0.12; _hit(e, 7)
		if evo and wid == "shotgun": ship.y = baseY - maxf(0, sin(t * 1.3)) * (baseY - 70 * k)
		charge = clampf(charge + absf(ship.x - px) / (W * 0.8) - dt * 0.3, 0, 1)
		for e in tg:
			e.ph += dt
			if e.dead:
				e.dead -= dt
				if e.dead <= 0:
					e.dead = 0.0; e.hp = 100.0; e.x = U.rand(0.15, 0.85) * W
				continue
			e.x += sin(e.ph * 0.9) * 22 * k * dt * (0.15 if e.frozen > 0 else 1.0)
			e.flash = maxf(0, e.flash - dt)
			e.frozen = maxf(0, e.frozen - dt)
			if e.burn > 0:
				e.burn -= dt; e.burnT += dt
				if e.burnT >= 0.25:
					e.burnT = 0.0; _hit(e, 4)
			if evo and wid == "darkmatter":
				e.cd -= dt
				if e.cd <= 0:
					e.cd = U.rand(0.5, 0.9)
					var a := atan2(ship.y - e.y, ship.x - e.x)
					eb.append({"x": e.x, "y": e.y, "vx": cos(a) * 110 * k, "vy": sin(a) * 110 * k, "dead": false})
		# темп и магазин
		var base: Dictionary = def.base
		if wid == "darkmatter":
			if sphere == null:
				cd -= dt
				if cd <= 0:
					_fire(); cd = 0.3
		elif base.mag:
			if reload > 0:
				reload -= dt
				if reload <= 0: mag = int(base.mag) + (1 if wid == "rocket" else 0)
			else:
				cd -= dt
				if cd <= 0:
					_fire(); mag -= 1; cd = base.cd
					if mag <= 0: reload = 2.5 if wid == "rocket" else base.reload
		else:
			cd -= dt
			if cd <= 0:
				_fire(); cd = base.cd
		# снаряды
		for b in shots:
			b.age += dt
			if b.k == "rocket":
				if b.tgt == null or b.tgt.dead: b.tgt = _nearest(b.x, b.y)
				if b.tgt != null:
					var a := atan2(b.tgt.y - b.y, b.tgt.x - b.x)
					var sp := minf(380 * k, Vector2(b.vx, b.vy).length() + 600 * k * dt)
					var ca := atan2(b.vy, b.vx)
					var na := ca + clampf(U.angle_diff(ca, a), -6 * dt, 6 * dt)
					b.vx = cos(na) * sp; b.vy = sin(na) * sp
			if b.k == "boom":
				# вылет с дугой, потом возврат к кораблю
				if not b.back:
					b.vx += b.sd * 300 * k * dt; b.vy *= exp(-1.8 * dt)
					if b.age > 0.6:
						b.back = true; b.hit.clear()
				else:
					var to := Vector2(ship.x - b.x, ship.y - b.y)
					var v := to.normalized() * minf(520 * k, Vector2(b.vx, b.vy).length() + 900 * k * dt)
					b.vx = lerpf(b.vx, v.x, minf(1, dt * 7)); b.vy = lerpf(b.vy, v.y, minf(1, dt * 7))
					if to.length() < 14 * k: b.dead = true
			if b.k == "wave" or b.k == "plasma": b.y += b.vy * dt
			else:
				b.x += b.vx * dt; b.y += b.vy * dt
			if b.get("life", 0.0) and b.age > b.life: b.dead = true
			if b.k != "boom" and (b.y < -20 or b.x < -20 or b.x > W + 20): b.dead = true
			if b.get("dead", false): continue
			if b.k == "wave":
				var half: float = (40 + 60 * minf(1, b.age / b.life)) * k * (0.85 + 0.3 * b.ch)
				for e in _alive():
					if not e in b.hit and absf(e.y - b.y) < 10 * k and absf(e.x - b.x) < half:
						b.hit.append(e); _hit(e, 26 * (0.75 + 0.75 * b.ch))
				continue
			if evo and b.k == "plasma":
				b.tr -= dt
				if b.tr <= 0:
					b.tr = 0.05; trail.append({"x": b.x, "y": b.y, "t": 0.0})
			if b.k == "boom":
				for e in _alive():
					if not e in b.hit and Vector2(e.x - b.x, e.y - b.y).length() < e.w * 0.6:
						b.hit.append(e); _hit(e, 12)
				continue
			for e in _alive():
				if Vector2(e.x - b.x, e.y - b.y).length() > e.w * 0.55: continue
				if b.k == "slug":
					# отброс и «бильярд»: соседняя мишень получает удар
					_hit(e, 16); e.y -= 18 * k
					for o in _alive():
						if o != e and Vector2(o.x - e.x, o.y - e.y).length() < 70 * k:
							_hit(o, 10); fx.append({"kind": "ring", "x": (o.x + e.x) / 2, "y": (o.y + e.y) / 2, "t": 0.0, "r": 16 * k, "col": "#5cffb0"})
					fx.append({"kind": "ring", "x": b.x, "y": b.y, "t": 0.0, "r": 22 * k, "col": "#5cffb0"})
					b.dead = true
					break
				if b.get("pierce", false):
					if e in b.hit: continue
					b.hit.append(e); _hit(e, 12)
					continue
				if evo and b.k == "pellet" and b.age < 0.14 and e.hp < 20:
					_hit(e, 999); fx.append({"kind": "ring", "x": e.x, "y": e.y, "t": 0.0, "r": 34 * k, "col": "#ffd23d"}); b.dead = true
					break
				if b.k == "plasma":
					var g := minf(1, b.age / 0.6)
					for o in _alive():
						if Vector2(o.x - b.x, o.y - b.y).length() < (30 + 30 * g) * k: _hit(o, 30 + 50 * g)
					fx.append({"kind": "ring", "x": b.x, "y": b.y, "t": 0.0, "r": (30 + 30 * g) * k, "col": "#ff8af5"})
				elif b.k == "rocket":
					_hit(e, 26)
					for o in _alive():
						if o != e and Vector2(o.x - b.x, o.y - b.y).length() < 34 * k: _hit(o, 14)
					fx.append({"kind": "ring", "x": b.x, "y": b.y, "t": 0.0, "r": 34 * k, "col": "#ffb03d"})
					# кассетные боеголовки: 4 малых заряда вокруг взрыва
					if evo:
						for q in 4:
							var a := q / 4.0 * TAU + 0.6
							var cx: float = b.x + cos(a) * 30 * k
							var cy: float = b.y + sin(a) * 30 * k
							fx.append({"kind": "ring", "x": cx, "y": cy, "t": 0.0, "r": 16 * k, "col": "#ffd23d"})
							for o in _alive():
								if Vector2(o.x - cx, o.y - cy).length() < 18 * k: _hit(o, 10)
				else: _hit(e, (9 if b.age < 0.12 else 6) if b.k == "pellet" else 9)
				b.dead = true
				break
		shots = shots.filter(func(b): return not b.get("dead", false))
		# тёмная материя: тормозит, притягивает, схлопывается
		if sphere != null:
			sphere.age += dt; sphere.vy *= exp(-1.6 * dt); sphere.y += sphere.vy * dt
			sphere.tick -= dt
			for e in _alive():
				var d := Vector2(e.x - sphere.x, e.y - sphere.y).length()
				if d < 70 * k:
					e.x += (sphere.x - e.x) * dt * 1.5
					if sphere.tick <= 0: _hit(e, 6)
			if sphere.tick <= 0: sphere.tick = 0.15
			if evo:
				for b in eb:
					if not b.dead and Vector2(b.x - sphere.x, b.y - sphere.y).length() < 64 * k:
						b.dead = true; fx.append({"kind": "ring", "x": b.x, "y": b.y, "t": 0.0, "r": 8 * k, "col": "#d9b8ff"})
			if sphere.age > 1.3:
				var R := (95 if evo else 60) * k
				for e in _alive():
					if Vector2(e.x - sphere.x, e.y - sphere.y).length() < R: _hit(e, 90 if evo else 45)
				fx.append({"kind": "ring", "x": sphere.x, "y": sphere.y, "t": 0.0, "r": R, "col": "#d9b8ff"})
				sphere = null
		for b in eb:
			b.x += b.vx * dt; b.y += b.vy * dt
			if b.y > H + 10 or Vector2(b.x - ship.x, b.y - ship.y).length() < ship.w * 0.35: b.dead = true
		eb = eb.filter(func(b): return not b.dead)
		for p in trail:
			p.t += dt
			for e in _alive():
				if Vector2(e.x - p.x, e.y - p.y).length() < 16 * k: e.burn = 3.0
		while not trail.is_empty() and trail[0].t > 1.5: trail.pop_front()
		for f in fx: f.t += dt
		fx = fx.filter(func(f): return f.t <= 0.5)
		# ── отрисовка ──
		_bg(c, dt)
		for e in tg:
			if e.dead: continue
			_target(c, e)
			if e.frozen > 0 or e.burn > 0:
				c.additive = true; c.alpha = 0.55
				c.draw_tex(G.soft("#9be8ff" if e.frozen > 0 else "#ff7a2a", 64), e.x - e.w * 0.7, e.y - e.w * 0.7, e.w * 1.4, e.w * 1.4)
				c.additive = false; c.alpha = 1.0
		c.additive = true
		for p in trail:
			c.alpha = maxf(0, 0.7 * (1 - p.t / 1.5))
			c.draw_tex(G.soft("#ff8a3d", 64), p.x - 10 * k, p.y - 10 * k, 20 * k, 20 * k)
		c.alpha = 1.0
		for b in eb: G.draw(c, "eb_orb", b.x, b.y, 9 * k)
		for b in shots:
			match b.k:
				"bolt": G.draw(c, b.spr, b.x, b.y, b.w)
				"pellet": G.draw_canvas(c, G.tinted("pb_orb", {"hue": 44}), b.x, b.y, b.w)
				"rocket": G.draw(c, "fx_rocket2" if G.has("fx_rocket2") else "fx_rocket", b.x, b.y, b.w, atan2(b.vy, b.vx) + PI / 2)
				"plasma":
					var g := minf(1, b.age / 0.6)
					G.draw_canvas(c, G.tinted("fx_plasma2" if G.has("fx_plasma2") else "eb_fire", {"hue": 305}), b.x, b.y, (18 + 22 * g) * k, b.age * 4)
				"boom": Game.drawBlade(c, b.x, b.y, 11 * k, b.age * 22)
				"slug": G.draw_canvas(c, G.tinted("pb_orb", {"hue": 150}), b.x, b.y, 13 * k)
				"wave":
					var half: float = (40 + 60 * minf(1, b.age / b.life)) * k * (0.85 + 0.3 * b.ch)
					var R := half * 1.6
					var span := asin(minf(1, half / R))
					var fade := minf(1, (b.life - b.age) / 0.15)
					for ln in [["#3dc8ff", 0.15, 7.0], ["#7ff6ff", 0.5, 3.0], ["#e8ffff", 0.9, 1.2]]:
						c.alpha = ln[1] * fade; c.stroke = U.col(ln[0]); c.line_width = ln[2] * k
						c.begin_path(); c.arc(b.x, b.y + R, R, -PI / 2 - span, -PI / 2 + span); c.stroke_path()
					c.alpha = 1.0
		if sphere != null: G.draw(c, "fx_vortex" if G.has("fx_vortex") else "pb_orb", sphere.x, sphere.y, 54 * k, sphere.age * 5, 0.9)
		if wid == "flail":
			var sx: float = ship.x + cos(flailA) * 58 * k
			var sy: float = ship.y + sin(flailA) * 58 * k
			c.additive = false
			c.fill = Color("#8b97a8")
			for i in range(1, 6): c.fill_circle(lerpf(ship.x, sx, i / 6.0), lerpf(ship.y, sy, i / 6.0), 2.2 * k)
			Game.drawSaw(c, sx, sy, 12 * k, t * 14, 0.7)
			c.additive = true
		for f in fx:
			if f.kind == "bolt" and f.t < 0.14:
				c.alpha = 1 - f.t / 0.14; c.stroke = U.col("#fff36b"); c.line_width = 2 * k
				c.begin_path()
				var pts: Array = f.pts
				c.move_to(pts[0].x, pts[0].y)
				for i in range(1, pts.size()):
					var a: Vector2 = pts[i - 1]
					var p: Vector2 = pts[i]
					for j in range(1, 5):
						var q2 := j / 4.0
						c.line_to(lerpf(a.x, p.x, q2) + (U.rand(-6, 6) * k if j < 4 else 0.0), lerpf(a.y, p.y, q2) + (U.rand(-6, 6) * k if j < 4 else 0.0))
				c.stroke_path()
				c.alpha = 1.0
		_fx(c)
		c.additive = false
		_ship(c, px, dt)
		# шкала ресурса: перезарядка / заряд серпа
		var bar = null
		if base.mag: bar = {"k": 1 - reload / (2.5 if wid == "rocket" else base.reload), "dim": true} if reload > 0 else {"k": float(mag) / (base.mag + (1 if wid == "rocket" else 0)), "dim": false}
		if wid == "arc": bar = {"k": charge, "dim": false}
		if bar != null:
			var bw := 4 * k
			var bh: float = ship.w * 0.7
			var bx: float = ship.x - ship.w * 0.75
			var by: float = ship.y - bh / 2
			c.fill = Color(0, 0, 0, 0.5); c.fill_rect(bx - 1, by - 1, bw + 2, bh + 2)
			c.alpha = 0.5 if bar.dim else 1.0
			c.fill = U.col(def.color); c.fill_rect(bx, by + bh * (1 - bar.k), bw, bh * bar.k)
			c.alpha = 1.0


# ════════════════════════════════════════════════════════════
# АКТИВНЫЙ ИМПЛАНТ: мишени стреляют в корабль, имплант срабатывает по кругу (бой → запуск → действие)
# ════════════════════════════════════════════════════════════
class SkillDemo extends Scene:
	var id := ""
	var DUR := 3.0
	const IDLE := 1.3
	var cyc := 0.0
	var on := false
	var ft := 0.0
	var fireCd := 0.2
	var tick := 0.0
	var marks: Array = []
	var hole = null
	var turret = null
	var clone = null

	func init() -> void:
		super.init()
		DUR = {"sk_rail": 1.6, "sk_orbital": 2.2, "sk_barrier": 3.0, "sk_timewarp": 3.0, "sk_turret": 3.5, "sk_blackhole": 2.8, "sk_emp": 3.0, "sk_clone": 3.5}.get(id, 3.0)
		ship = {"x": W / 2, "y": H - 28 * k, "w": 38 * k, "hitT": 0.0}
		# раскладка мишеней: у Рельсы — колонна над кораблём, чтобы луч прошил всех
		var lay: Array = [[0.5, 26], [0.5, 58], [0.5, 90], [0.17, 40], [0.83, 50]] if id == "sk_rail" else [[0.16, 34], [0.38, 60], [0.6, 30], [0.83, 58], [0.5, 90]]
		var spr := ["scout", "drone", "shooter", "interceptor", "heavy"]
		tg.clear(); shots.clear(); eb.clear(); fx.clear()
		for i in lay.size():
			var fxx: float = lay[i][0]
			var fy: float = lay[i][1]
			tg.append({"spr": spr[i], "ox": fxx * W, "oy": fy * k, "hx": fxx * W, "hy": fy * k, "x": fxx * W, "y": fy * k, "w": 28 * k, "hp": 120.0, "flash": 0.0, "dead": 0.0,
				"ph": i * 1.7, "cd": 0.5 + i * 0.3, "emp": 0.0, "sh": 1 if id == "sk_emp" and i == 2 else 0})
		cyc = 0.0; on = false; marks.clear(); hole = null; turret = null; clone = null

	func _hit(e, dmg: float) -> void:
		if e == null or e.dead: return
		if e.sh:
			fx.append({"kind": "ring", "x": e.x, "y": e.y, "t": 0.0, "r": e.w * 0.9, "col": "#7fd8ff"})
			return
		e.hp -= dmg; e.flash = 0.08
		if e.hp <= 0:
			e.dead = 0.8; fx.append({"kind": "boom", "x": e.x, "y": e.y, "t": 0.0, "r": e.w * 1.4})

	func _cast() -> void:
		on = true; ft = 0.0
		match id:
			"sk_orbital":
				marks.clear()
				var al := _alive()
				for i in mini(4, al.size()): marks.append({"e": al[i], "x": al[i].x, "y": al[i].y, "at": 0.85 + i * 0.15, "fired": false, "ft": 0.0})
			"sk_barrier": fx.append({"kind": "ring", "x": ship.x, "y": ship.y, "t": 0.0, "r": ship.w * 1.6, "col": "#ffd23d"})
			"sk_turret": turret = {"x": ship.x - ship.w, "y": ship.y - ship.w * 0.9, "cd": 0.3, "ang": -PI / 2, "flash": 0.0}
			"sk_blackhole": hole = {"x": W / 2, "y": 54 * k, "t": 0.0}
			"sk_emp":
				fx.append({"kind": "emp", "x": ship.x, "y": ship.y, "t": 0.0})
				for e in _alive():
					e.emp = 2.4
					if e.sh:
						e.sh = 0; fx.append({"kind": "ring", "x": e.x, "y": e.y, "t": 0.0, "r": e.w * 1.3, "col": "#7fd8ff"})
					fx.append({"kind": "bolt", "pts": [Vector2(ship.x, ship.y - ship.w * 0.4), Vector2(e.x, e.y)], "t": 0.0})
				eb.clear()
			"sk_clone": clone = {"x": ship.x + ship.w * 1.05, "y": ship.y, "t": 0.0}

	func _end() -> void:
		on = false; cyc = 0.0
		turret = null; clone = null; marks.clear()
		if hole != null:
			for e in _alive():
				if Vector2(e.x - hole.x, e.y - hole.y).length() < 70 * k: _hit(e, 300)
			fx.append({"kind": "ring", "x": hole.x, "y": hole.y, "t": 0.0, "r": 80 * k, "col": "#d9b8ff"})
			fx.append({"kind": "boom", "x": hole.x, "y": hole.y, "t": 0.0, "r": 60 * k})
			hole = null
		for e in tg:
			e.hx = e.ox; e.hy = e.oy
			if id == "sk_emp" and e.spr == "shooter": e.sh = 1

	func _fire_ship(x: float, holo := false) -> void:
		shots.append({"x": x, "y": ship.y - ship.w * 0.45, "vx": 0.0, "vy": -520 * k, "w": (10 if holo else 12) * k, "spr": "pb_bolt_m", "dmg": 6 if holo else 9, "holo": holo, "dead": false})

	func step(c: Ctx, dt: float) -> void:
		var sk: Dictionary = D.SKILLS[id]
		cyc += dt
		if not on and cyc >= IDLE: _cast()
		if on:
			ft += dt
			if ft >= DUR: _end()
		var sl := 0.33 if on and id == "sk_timewarp" else 1.0
		var railOn := on and id == "sk_rail" and ft > 0.4
		var px: float = ship.x
		ship.x = W / 2 + sin(t * 0.8) * W * (0.03 if id == "sk_rail" else 0.12)
		ship.hitT = maxf(0, ship.hitT - dt)
		for e in tg:
			if e.dead:
				e.dead -= dt
				if e.dead <= 0:
					e.dead = 0.0; e.hp = 120.0; e.hx = e.ox; e.hy = e.oy
				continue
			e.flash = maxf(0, e.flash - dt)
			if hole != null:
				e.hx += (hole.x - e.hx) * dt * 1.3; e.hy += (hole.y - e.hy) * dt * 1.3
			if e.emp > 0:
				e.emp -= dt
				continue
			e.ph += dt * sl
			e.x = e.hx + sin(e.ph * 0.9) * 14 * k; e.y = e.hy
			e.cd -= dt * sl
			if e.cd <= 0:
				e.cd = U.rand(0.9, 1.4)
				var a := atan2(ship.y - e.y, ship.x - e.x)
				eb.append({"x": e.x, "y": e.y + e.w * 0.3, "vx": cos(a) * 120 * k, "vy": sin(a) * 120 * k, "dead": false})
		for b in eb:
			if hole != null:
				var dv := Vector2(hole.x - b.x, hole.y - b.y)
				var d := maxf(1, dv.length())
				if d < 130 * k:
					b.vx += dv.x / d * 320 * k * dt; b.vy += dv.y / d * 320 * k * dt
				if d < 12 * k:
					b.dead = true
					continue
			b.x += b.vx * dt * sl; b.y += b.vy * dt * sl
			var dd := Vector2(b.x - ship.x, b.y - ship.y).length()
			if on and id == "sk_barrier" and dd < ship.w * 0.85:
				b.dead = true
				var e = _nearest(b.x, b.y)
				var a := atan2(e.y - b.y, e.x - b.x) if e != null else -PI / 2
				shots.append({"x": b.x, "y": b.y, "vx": cos(a) * 520 * k, "vy": sin(a) * 520 * k, "w": 10 * k, "spr": "pb_bolt_s", "dmg": 30, "holo": false, "dead": false})
				fx.append({"kind": "ring", "x": b.x, "y": b.y, "t": 0.0, "r": 10 * k, "col": "#ffd23d"})
				continue
			if railOn and absf(b.x - ship.x) < 14 * k and b.y < ship.y:
				b.dead = true
				continue
			if dd < ship.w * 0.35:
				b.dead = true; ship.hitT = 0.15; fx.append({"kind": "ring", "x": b.x, "y": b.y, "t": 0.0, "r": 12 * k, "col": "#ff5c7a"})
				continue
			if b.y > H + 10 or b.y < -10 or b.x < -10 or b.x > W + 10: b.dead = true
		eb = eb.filter(func(b): return not b.dead)
		fireCd -= dt
		if fireCd <= 0:
			fireCd = 0.2; _fire_ship(ship.x)
			if clone != null: _fire_ship(clone.x, true)
		if turret != null:
			turret.x = U.damp(turret.x, ship.x - ship.w * 1.05, 6, dt)
			turret.y = U.damp(turret.y, ship.y - ship.w * 0.85 + sin(t * 3) * 3 * k, 6, dt)
			turret.cd -= dt; turret.flash -= dt
			var e = _nearest(turret.x, turret.y, true)
			if e != null: turret.ang = U.damp(turret.ang, atan2(e.y - turret.y, e.x - turret.x), 12, dt)
			if e != null and turret.cd <= 0:
				turret.cd = 0.15; turret.flash = 0.06
				shots.append({"x": turret.x + cos(turret.ang) * 12 * k, "y": turret.y + sin(turret.ang) * 12 * k, "vx": cos(turret.ang) * 700 * k, "vy": sin(turret.ang) * 700 * k, "w": 9 * k, "spr": "pb_bolt_s", "dmg": 9, "holo": false, "dead": false})
		if clone != null:
			clone.t += dt; clone.x = U.damp(clone.x, ship.x + ship.w * 1.05, 10, dt); clone.y = ship.y + ship.w * 0.15
		for b in shots:
			b.x += b.vx * dt; b.y += b.vy * dt
			if b.y < -20 or b.y > H + 20 or b.x < -20 or b.x > W + 20:
				b.dead = true
				continue
			for e in _alive():
				if Vector2(e.x - b.x, e.y - b.y).length() > e.w * 0.55: continue
				_hit(e, b.dmg); b.dead = true
				break
		shots = shots.filter(func(b): return not b.dead)
		tick -= dt
		if tick <= 0:
			tick = 0.08
			if railOn:
				for e in _alive():
					if absf(e.x - ship.x) < 18 * k: _hit(e, 16)
			if hole != null:
				for e in _alive():
					if Vector2(e.x - hole.x, e.y - hole.y).length() < 40 * k: _hit(e, 4)
		if hole != null: hole.t += dt
		for m in marks:
			if m.e != null and not m.e.dead:
				m.x = m.e.x; m.y = m.e.y
			if not m.fired and ft >= m.at:
				m.fired = true; fx.append({"kind": "boom", "x": m.x, "y": m.y, "t": 0.0, "r": 50 * k})
				for e in _alive():
					if Vector2(e.x - m.x, e.y - m.y).length() < 34 * k: _hit(e, 300)
			if m.fired: m.ft += dt
		for f in fx: f.t += dt
		fx = fx.filter(func(f): return f.t <= (0.7 if f.kind == "emp" else 0.5))
		# ── отрисовка ──
		_bg(c, dt, sl)
		if on and id == "sk_timewarp":
			c.fill = Color(61 / 255.0, 107 / 255.0, 1, 0.14); c.fill_rect(0, 0, W, H)
			if ft < 1.1:
				var f := ft / 1.1
				var R := (30 + 120 * f) * k
				c.alpha = 0.8 * (1 - f); c.stroke = U.col("#9fc8ff"); c.line_width = 2 * k
				c.begin_path(); c.arc(ship.x, ship.y, R, 0, TAU); c.stroke_path()
				for hd in [[0.55, -9.0], [0.8, -26.0]]:
					var a: float = -PI / 2 + t * hd[1]
					c.stroke_line(ship.x, ship.y, ship.x + cos(a) * R * hd[0], ship.y + sin(a) * R * hd[0])
				c.alpha = 1.0
		c.additive = true
		for m in marks:
			if not m.fired:
				var q := clampf(ft / m.at, 0, 1)
				var r := (34 - 20 * q) * k
				c.alpha = 0.4 + 0.6 * q; c.stroke = U.col("#ff5c4d"); c.line_width = 2 * k
				for j in 4:
					var a := (1 - q) * 2 + j * PI / 2
					c.begin_path(); c.arc(m.x, m.y, r, a - 0.35, a + 0.35); c.stroke_path()
				if q > 0.6: Game.drawBeamV(c, m.x, 0, m.y, 1.5 * k, "#ff5c4d", (q - 0.6) * 1.2, 1)
			elif m.ft < 0.4: Game.drawBeamV(c, m.x, 0, m.y, 12 * k * (1 - m.ft / 0.4 * 0.5), "#ff6a3d", 1 - m.ft / 0.4, 1, m.y)
		if on and id == "sk_orbital" and ft < 1.6:
			var sx := U.lerp(-20 * k, W + 20 * k, ft / 1.6)
			var sy := 10 * k
			c.alpha = 0.5; c.draw_tex(G.glow("#ff5c4d", 32), sx - 14 * k, sy - 14 * k, 28 * k, 28 * k)
			c.additive = false; c.alpha = 1.0; G.draw(c, "sp_radar", sx, sy, 20 * k, PI); c.additive = true
		if hole != null:
			var q := minf(1, hole.t * 3)
			var R := 90 * k
			var sz := R * 0.55 * q
			c.alpha = 0.35 * q; c.draw_tex(G.soft("#7a3dff", 64), hole.x - R, hole.y - R, R * 2, R * 2)
			c.alpha = q; G.draw(c, "fx_vortex" if G.has("fx_vortex") else "pb_orb", hole.x, hole.y, sz * 2.6, hole.t * 4)
			c.alpha = 1.0; c.additive = false
			c.fill = Color.BLACK; c.fill_circle(hole.x, hole.y, sz * 0.35)
		c.additive = false; c.alpha = 1.0
		for e in tg:
			if e.dead: continue
			_target(c, e, "#7fe7ff" if e.emp > 0 else "")
			if e.sh: G.draw(c, "fx_sh_bubble" if G.has("fx_sh_bubble") else "pb_orb", e.x, e.y, e.w * 1.5, 0, 0.8)
		c.additive = true
		for b in eb: G.draw(c, "eb_orb", b.x, b.y, 9 * k)
		for b in shots:
			c.alpha = 0.6 if b.holo else 1.0
			G.draw(c, b.spr, b.x, b.y, b.w, atan2(b.vy, b.vx) + PI / 2 if b.vx != 0 or b.vy != 0 else 0.0)
		c.alpha = 1.0
		if on and id == "sk_rail":
			if ft < 0.4:
				var q := ft / 0.4
				c.alpha = 0.4 + 0.5 * q
				c.draw_tex(G.glow("#7ffff0", 64), ship.x - 26 * k * q, ship.y - ship.w * 0.6 - 26 * k * q, 52 * k * q, 52 * k * q)
				Game.drawBeamV(c, ship.x, 0, ship.y - ship.w * 0.5, (1.5 + 2 * q) * k, "#7ffff0", 0.25 + 0.35 * q)
			else:
				var fade := minf(1, minf((ft - 0.4) * 8, (DUR - ft) * 4))
				Game.drawBeamV(c, ship.x, 0, ship.y - ship.w * 0.45, 18 * k * (0.6 + 0.4 * fade), "#3de0ff", fade, -1, ship.y - ship.w * 0.55)
			c.alpha = 1.0
		for f in fx:
			if f.kind == "emp":
				var qe: float = f.t / 0.7
				c.alpha = 1 - qe; c.stroke = U.col("#7fe7ff"); c.line_width = 4 * k
				c.begin_path(); c.arc(f.x, f.y, Vector2(W, H).length() * qe, 0, TAU); c.stroke_path()
				c.alpha = 1.0
			elif f.kind == "bolt" and f.t < 0.25:
				c.alpha = 1 - f.t / 0.25; c.stroke = U.col("#9fe8ff"); c.line_width = 2 * k
				var a: Vector2 = f.pts[0]
				var b: Vector2 = f.pts[1]
				c.begin_path(); c.move_to(a.x, a.y)
				for j in range(1, 6):
					var q2 := j / 5.0
					c.line_to(lerpf(a.x, b.x, q2) + (U.rand(-7, 7) * k if j < 5 else 0.0), lerpf(a.y, b.y, q2) + (U.rand(-7, 7) * k if j < 5 else 0.0))
				c.stroke_path()
				c.alpha = 1.0
		_fx(c)
		if turret != null:
			var w: float = ship.w * 0.7
			c.alpha = 0.35 + 0.1 * sin(t * 8)
			c.draw_tex(G.soft("#b06bff", 64), turret.x - w, turret.y - w, w * 2, w * 2)
			c.alpha = 1.0; c.additive = false
			G.draw(c, "sp_radar", turret.x, turret.y, w, turret.ang + PI / 2)
		c.additive = false; c.alpha = 1.0
		var tilt: float = (ship.x - px) / maxf(dt, 0.001) * 0.002
		var s: Dictionary = M.s
		if clone != null:
			c.save(); c.alpha = (0.42 + 0.08 * sin(t * 23)) * minf(1, clone.t / 0.4)
			Game.drawShip(c, s.ship.model, s.ship.skin, s.ship.trail, clone.x, clone.y, ship.w, tilt, t, 1)
			c.restore()
			c.additive = true; c.alpha = 0.18; c.fill = U.col("#7ff6ff")
			var y: float = clone.y - ship.w * 0.6 + fmod(t * 40, 6.0)
			while y < clone.y + ship.w * 0.6:
				c.fill_rect(clone.x - ship.w * 0.5, y, ship.w, 1)
				y += 6
			c.alpha = 1.0; c.additive = false
		_ship(c, px, dt)
		if on and id == "sk_barrier":
			var R: float = ship.w * 0.85
			var a0 := minf(1, minf(ft * 4, (DUR - ft) * 4))
			c.additive = true
			c.alpha = 0.25 * a0; c.draw_tex(G.soft("#ffd23d", 64), ship.x - R * 1.3, ship.y - R * 1.3, R * 2.6, R * 2.6)
			c.alpha = 0.8 * a0; c.stroke = U.col("#ffd23d"); c.line_width = 2 * k
			c.begin_path(); c.arc(ship.x, ship.y, R, 0, TAU); c.stroke_path()
			for j in 6:
				var a := j / 6.0 * TAU + t * 0.8
				var hx: float = ship.x + cos(a) * R * 0.75
				var hy: float = ship.y + sin(a) * R * 0.75
				var r := 5 * k
				c.begin_path()
				for q in 7:
					var bb := q / 6.0 * TAU + PI / 6
					if q: c.line_to(hx + cos(bb) * r, hy + sin(bb) * r)
					else: c.move_to(hx + cos(bb) * r, hy + sin(bb) * r)
				c.stroke_path()
			c.alpha = 1.0; c.additive = false
		# значок импланта в углу: во время действия — сколько осталось, в покое — заряд до запуска
		var ix := 18 * k
		var iy := 18 * k
		var ir := 13 * k
		c.fill = Color(0, 0, 0, 0.55); c.fill_circle(ix, iy, ir + 2 * k)
		c.alpha = 1.0 if on else 0.55
		if G.has(id): G.draw(c, id, ix, iy, ir * 2)
		else:
			c.font = Kit.font(600); c.fill = Color.WHITE; c.fill_text(sk.ico, ix, iy + ir * 0.5, int(ir * 1.3), 1)
		c.alpha = 1.0
		c.stroke = Kit.CYAN if on else Color(1, 1, 1, 0.45); c.line_width = 2.5 * k
		c.begin_path(); c.arc(ix, iy, ir + 2 * k, -PI / 2, -PI / 2 + TAU * ((1 - ft / DUR) if on else cyc / IDLE)); c.stroke_path()


# ════════════════════════════════════════════════════════════
# СОБЫТИЯ ВОЛНЫ И АНОМАЛИИ СЕКТОРА (окна-подсказки)
# ════════════════════════════════════════════════════════════
class SceneDemo extends Scene:
	var key := ""
	var mode := ""
	var modeT := 0.0
	var fast := 1.0
	var swarm := false
	var elite := false
	var fireCd := 0.2
	var spawn := 0.4
	var sun = null
	var truck = null
	var strikes: Array = []
	var lanes: Array = []
	var meteors: Array = []
	var rocks: Array = []
	var coins: Array = []
	var wind: Array = []
	const UNST := ["storm", "meteors", "solar"]

	func init() -> void:
		super.init()
		ship = {"x": W / 2, "y": H - 26 * k, "w": 36 * k, "hitT": 0.0}
		# аномалии: ветер — враги вдвое быстрее, рой — много мелких, флагман — элита в золотом ореоле
		fast = 2.2 if key == "ionwind" else 1.0
		swarm = key == "swarm"
		elite = key == "flagship"
		mode = UNST[0] if key == "unstable" else key
		var n := 9 if swarm else (3 if key == "convoy" or key == "debris" else 4)
		var spr := ["scout", "drone", "shooter", "interceptor", "heavy"]
		tg.clear(); shots.clear(); eb.clear(); fx.clear(); strikes.clear(); lanes.clear(); meteors.clear(); rocks.clear(); coins.clear(); wind.clear()
		for i in n:
			var fxx := 0.1 + (i % 5) * 0.2 if swarm else (i + 0.5) / n
			var fy := 22 + floorf(i / 5.0) * 30 + (i % 2) * 8 if swarm else 26.0 + (i % 2) * 22
			var el := elite and i % 2 == 0
			tg.append({"spr": "drone" if swarm else spr[i % 5], "ox": fxx * W, "x": fxx * W, "y": fy * k, "w": (20 if swarm else (34 if el else 26)) * k, "hp": 60.0, "flash": 0.0, "dead": 0.0, "ph": i * 1.3, "cd": 0.5 + i * 0.3, "elite": el})

	func _hit(e, dmg: float) -> void:
		if e == null or e.dead: return
		e.hp -= dmg; e.flash = 0.08
		if e.hp <= 0:
			e.dead = 0.9; fx.append({"kind": "boom", "x": e.x, "y": e.y, "t": 0.0, "r": e.w * 1.4})

	func step(c: Ctx, dt: float) -> void:
		# «Нестабильная зона»: события сменяют друг друга
		if key == "unstable":
			modeT += dt
			if modeT > 3.6:
				modeT = 0.0; mode = UNST[(UNST.find(mode) + 1) % UNST.size()]; strikes.clear(); lanes.clear(); sun = null
		var px: float = ship.x
		var want: float = truck.x if mode == "convoy" and truck != null else W / 2 + sin(t * 0.9) * W * 0.28
		ship.x = U.damp(ship.x, want, 3.0 if mode == "convoy" else 2.0, dt)
		ship.hitT = maxf(0, ship.hitT - dt)
		for e in tg:
			if e.dead:
				e.dead -= dt
				if e.dead <= 0:
					e.dead = 0.0; e.hp = 60.0
				continue
			e.flash = maxf(0, e.flash - dt)
			e.ph += dt * fast
			e.x = e.ox + sin(e.ph * 1.1) * (10 if swarm else 22) * k * (1.4 if fast > 1 else 1.0)
			e.cd -= dt * fast
			if e.cd <= 0:
				e.cd = U.rand(1, 1.6)
				var a := atan2(ship.y - e.y, ship.x - e.x)
				var sp := 110 * k * fast
				eb.append({"x": e.x, "y": e.y + e.w * 0.3, "vx": cos(a) * sp, "vy": sin(a) * sp, "dead": false})
		if key == "ionwind" and U.random() < dt * 14: wind.append({"x": U.rand(0, W + 60 * k), "y": -10.0, "t": 0.0})
		for w in wind:
			w.t += dt; w.x -= 260 * k * dt; w.y += 340 * k * dt
		while not wind.is_empty() and wind[0].t > 1.2: wind.pop_front()
		fireCd -= dt
		if fireCd <= 0:
			fireCd = 0.18; shots.append({"x": ship.x, "y": ship.y - ship.w * 0.45, "vy": -520 * k, "dead": false})
		# ── события ──
		spawn -= dt
		if mode == "storm" and spawn <= 0:
			spawn = 0.9
			var al := _alive()
			var tgt = {"x": ship.x + U.rand(-20, 20) * k, "y": ship.y} if U.random() < 0.45 or al.is_empty() else U.pick(al)
			strikes.append({"x": tgt.x, "y": tgt.y, "t": 0.0, "warn": 1.1, "R": 26 * k, "done": false})
		for st in strikes:
			st.t += dt
			if not st.done and st.t >= st.warn:
				st.done = true
				fx.append({"kind": "zap", "x": st.x, "y": st.y, "t": 0.0})
				for e in _alive():
					if Vector2(e.x - st.x, e.y - st.y).length() < st.R + e.w * 0.4: _hit(e, 40)
				if Vector2(ship.x - st.x, ship.y - st.y).length() < st.R * 0.8 + ship.w * 0.2: ship.hitT = 0.2
		strikes = strikes.filter(func(s): return not s.done)
		if mode == "meteors" and spawn <= 0:
			spawn = 0.8
			var tx: float = ship.x if U.random() < 0.35 else U.rand(0.1, 0.95) * W
			var ty := U.rand(0.2, 0.9) * H
			var y0 := -30 * k
			var kk := (ty - y0) / MDIR.y
			lanes.append({"x0": tx - MDIR.x * kk, "y0": y0, "t": 0.0, "warn": 0.85, "big": U.random() < 0.45, "gone": false})
		for l in lanes:
			l.t += dt
			if l.t >= l.warn and not l.gone:
				l.gone = true
				meteors.append({"x": l.x0, "y": l.y0, "big": l.big, "spr": "fx_meteor1" if l.big else "fx_meteor2", "w": (40 if l.big else 26) * k, "hit": [], "dead": false, "hitShip": false})
		lanes = lanes.filter(func(l): return not (l.gone and l.t > l.warn + 0.3))
		for m in meteors:
			m.x += MDIR.x * 300 * k * dt; m.y += MDIR.y * 300 * k * dt
			for e in _alive():
				if not e in m.hit and Vector2(e.x - m.x, e.y - m.y).length() < e.w * 0.6:
					m.hit.append(e); _hit(e, 50 if m.big else 28)
			if not m.hitShip and Vector2(ship.x - m.x, ship.y - m.y).length() < ship.w * 0.35:
				m.hitShip = true; ship.hitT = 0.2
			if m.y > H + 30 or m.x < -40: m.dead = true
		meteors = meteors.filter(func(m): return not m.dead)
		if mode == "solar":
			if sun == null: sun = {"t": 0.0, "fired": false}
			sun.t += dt
			if sun.t >= 1.6 and not sun.fired:
				sun.fired = true
				fx.append({"kind": "flash", "t": 0.0})
				eb.clear()
				for e in _alive(): _hit(e, 20)
			if sun.t > 3: sun = null
		if mode == "debris" and spawn <= 0:
			spawn = 0.55
			rocks.append({"x": U.rand(0.1, 0.9) * W, "y": -12 * k, "w": U.rand(20, 30) * k, "spr": "db_%d" % U.randi(1, 6), "rot": U.random() * 6, "vr": U.rand(-2, 2), "vy": U.rand(45, 70) * k, "hp": 18.0, "dead": false})
		for r in rocks:
			r.y += r.vy * dt; r.rot += r.vr * dt
			if r.y > H + 20: r.dead = true
		if mode == "convoy":
			if truck == null and spawn <= 0: truck = {"x": -40 * k, "y": 30 * k, "hp": 160.0, "flash": 0.0}
			if truck != null:
				truck.x += 55 * k * dt; truck.flash = maxf(0, truck.flash - dt)
				if truck.x > W + 50 * k:
					truck = null; spawn = 0.8
		for b in shots:
			b.y += b.vy * dt
			if b.y < -20:
				b.dead = true
				continue
			if truck != null and absf(b.x - truck.x) < 30 * k and absf(b.y - truck.y) < 18 * k:
				b.dead = true; truck.hp -= 9; truck.flash = 0.08
				if truck.hp <= 0:
					fx.append({"kind": "boom", "x": truck.x, "y": truck.y, "t": 0.0, "r": 70 * k})
					for q in 2: coins.append({"x": truck.x + (12 if q else -12) * k, "y": truck.y, "vx": (40 if q else -40) * k, "vy": -30 * k, "t": 0.0, "crate": true, "dead": false})
					truck = null; spawn = 1.2
				continue
			for r in rocks:
				if not r.dead and Vector2(r.x - b.x, r.y - b.y).length() < r.w * 0.6:
					b.dead = true; r.hp -= 9
					if r.hp <= 0:
						r.dead = true; fx.append({"kind": "boom", "x": r.x, "y": r.y, "t": 0.0, "r": r.w * 1.2})
						for q in 3: coins.append({"x": r.x, "y": r.y, "vx": U.rand(-50, 50) * k, "vy": U.rand(-60, -20) * k, "t": 0.0, "crate": false, "dead": false})
					break
			if b.dead: continue
			for e in _alive():
				if Vector2(e.x - b.x, e.y - b.y).length() < e.w * 0.55:
					_hit(e, 4 if e.elite else 9); b.dead = true
					break
		shots = shots.filter(func(b): return not b.dead)
		rocks = rocks.filter(func(r): return not r.dead)
		for cc in coins:
			cc.t += dt
			if cc.t < 0.4:
				cc.x += cc.vx * dt; cc.y += cc.vy * dt; cc.vy += 120 * k * dt
			else:
				var a := atan2(ship.y - cc.y, ship.x - cc.x)
				cc.x += cos(a) * 320 * k * dt; cc.y += sin(a) * 320 * k * dt
				if Vector2(ship.x - cc.x, ship.y - cc.y).length() < 12 * k:
					cc.dead = true; fx.append({"kind": "ring", "x": ship.x, "y": ship.y - 6 * k, "t": 0.0, "r": 16 * k, "col": "#ffd23d"})
		coins = coins.filter(func(cc): return not cc.dead and cc.t <= 3)
		for b in eb:
			b.x += b.vx * dt; b.y += b.vy * dt
			if Vector2(b.x - ship.x, b.y - ship.y).length() < ship.w * 0.3:
				b.dead = true; ship.hitT = 0.2
			if b.y > H + 10 or b.x < -10 or b.x > W + 10: b.dead = true
		eb = eb.filter(func(b): return not b.dead)
		for f in fx: f.t += dt
		fx = fx.filter(func(f): return f.t <= 0.5)
		# ── отрисовка ──
		_bg(c, dt, fast)
		c.additive = true
		c.stroke = U.col("#7fd8ff"); c.line_width = 1.5 * k
		for w in wind:
			c.alpha = 0.5 * (1 - w.t / 1.2)
			c.stroke_line(w.x, w.y, w.x + 26 * k, w.y - 34 * k)
		for st in strikes:
			var q: float = st.t / st.warn
			G.draw(c, "fx_ion", st.x, st.y, st.R * 2 * (0.75 + 0.25 * q), st.t * 2, 0.3 + 0.5 * q)
			c.alpha = 0.35 + 0.5 * q; c.stroke = U.col("#9fd0ff"); c.line_width = 2 * k
			c.begin_path(); c.arc(st.x, st.y, st.R * (1.7 - 0.7 * q), 0, TAU); c.stroke_path()
		c.dash = PackedFloat32Array([8 * k, 6 * k]); c.stroke = U.col("#ff8a3d"); c.line_width = 1.5 * k
		for l in lanes:
			if l.gone: continue
			c.alpha = 0.3 + 0.5 * (l.t / l.warn)
			c.begin_path(); c.move_to(l.x0, l.y0); c.line_to(l.x0 + MDIR.x * H * 2, l.y0 + MDIR.y * H * 2); c.stroke_path()
		c.dash = PackedFloat32Array()
		if sun != null and not sun.fired:
			var q: float = sun.t / 1.6
			G.draw(c, "fx_solar", W * 0.85, 20 * k, (40 + 50 * q) * k, sun.t * 0.8, 0.4 + 0.6 * q)
		c.alpha = 1.0; c.additive = false
		for e in tg:
			if e.dead: continue
			if e.elite:
				c.additive = true; c.alpha = 0.5 + 0.15 * sin(t * 6)
				c.draw_tex(G.soft("#ffc83d", 64), e.x - e.w, e.y - e.w, e.w * 2, e.w * 2)
				c.additive = false; c.alpha = 1.0
			_target(c, e)
		if truck != null:
			G.draw(c, "e_cargo" if G.has("e_cargo") else "heavy", truck.x, truck.y, 46 * k, PI / 2)
			c.fill = Color(0, 0, 0, 0.6); c.fill_rect(truck.x - 20 * k, truck.y - 26 * k, 40 * k, 3 * k)
			c.fill = Color.WHITE if truck.flash > 0 else Kit.GOLD; c.fill_rect(truck.x - 20 * k, truck.y - 26 * k, 40 * k * maxf(0, truck.hp / 160), 3 * k)
		for r in rocks: G.draw(c, r.spr, r.x, r.y, r.w, r.rot)
		c.additive = true
		for m in meteors:
			var f := G.frame(m.spr)
			if not f.is_empty():
				var h: float = m.w * f[3] / f[2]
				var a: Array = MHEAD[m.spr]
				c.draw_image(G.src(f), f[0], f[1], f[2], f[3], m.x - m.w * a[0], m.y - h * a[1], m.w, h)
		for b in eb: G.draw(c, "eb_orb", b.x, b.y, 9 * k)
		for b in shots: G.draw(c, "pb_bolt_m", b.x, b.y, 11 * k)
		c.additive = false
		for cc in coins:
			if cc.crate and G.has("p_crate"): G.draw(c, "p_crate", cc.x, cc.y, 16 * k)
			else:
				c.fill = Kit.GOLD; c.fill_circle(cc.x, cc.y, 3.5 * k)
				c.fill = Color("#fff3b0"); c.fill_circle(cc.x - k, cc.y - k, 1.3 * k)
		for f in fx:
			var q: float = f.t / 0.5
			if f.kind == "zap" and f.t < 0.2:
				c.additive = true; c.alpha = 1 - f.t / 0.2; c.stroke = U.col("#cfe8ff"); c.line_width = 2.5 * k
				c.begin_path(); c.move_to(f.x + U.rand(-10, 10) * k, 0)
				for j in range(1, 7): c.line_to(f.x + (U.rand(-9, 9) * k if j < 6 else 0.0), f.y * j / 6.0)
				c.stroke_path()
				c.draw_tex(G.glow("#9fd0ff", 64), f.x - 26 * k, f.y - 26 * k, 52 * k, 52 * k)
			elif f.kind == "flash":
				c.additive = true; c.alpha = 0.6 * (1 - q); c.fill = Color("#ffd98a"); c.fill_rect(0, 0, W, H)
			c.alpha = 1.0; c.additive = false
		_fx(c)
		c.additive = false
		_ship(c, px, dt)
