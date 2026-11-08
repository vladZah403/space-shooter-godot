extends Node
## Визуальные эффекты (автозагрузка FX) — перенос fx.js: искры, дым, обломки, взрывы (кадры из листа),
## кольца, молнии, всплывающие надписи и числа урона, спрайты листа эффектов, вспышка, тряска,
## цветная виньетка и дуга урона у края поля.

enum { P_SPARK, P_GLOW, P_SMOKE, P_DEBRIS, P_EMBER }


class Part:
	var t := 0
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0
	var life := 0.0
	var max := 1.0
	var size := 1.0
	var color := "#ffffff"
	var drag := 0.0
	var rot := 0.0
	var vr := 0.0
	var grow := 0.0
	var spr := ""


class Spr:
	var name := ""
	var x := 0.0
	var y := 0.0
	var w0 := 10.0
	var w1 := 10.0
	var dur := 0.5
	var life := 0.0
	var rot := 0.0
	var vr := 0.0
	var a := 1.0
	var hold := 0.35
	var fade_in := 0.0
	var vy := 0.0
	var sy := 1.0
	var follow: Object = null
	var ox := 0.0
	var oy := 0.0
	var cv: Texture2D = null


var parts: Array[Part] = []
var expl: Array = []       # { x, y, life, dur, w, rot, name, cv }
var rings: Array = []      # { x, y, r0, r1, color, life, max, w }
var texts: Array = []      # { x, y, s, c, size, life, max, vy, num }
var beams: Array = []      # { pts, color, w, life, max }
var sprites: Array[Spr] = []
var scr: Array = []        # { color, life, dur, a, pulse }
var arcs: Array = []       # { a, px, py, color, life, dur }
var trauma := 0.0
var shake_x := 0.0
var shake_y := 0.0
var flash_a := 0.0
var flash_color := "#ffffff"
var max_parts := 500
var quality := 2
var shake_on := true
var _vig := {}


func set_quality(q: int) -> void:
	quality = q
	max_parts = 520 if q >= 2 else (280 if q == 1 else 110)


func clear() -> void:
	parts.clear(); expl.clear(); rings.clear(); texts.clear(); beams.clear(); sprites.clear(); scr.clear(); arcs.clear()
	trauma = 0.0
	flash_a = 0.0
	Post.clear()
	Vfx.clear()


func _p(type: int, x: float, y: float, vx: float, vy: float, life: float, size: float, color: String) -> Part:
	if parts.size() >= max_parts:
		return null
	var p := Part.new()
	p.t = type; p.x = x; p.y = y; p.vx = vx; p.vy = vy; p.life = life; p.max = life; p.size = size; p.color = color
	parts.append(p)
	return p


func sparks(x: float, y: float, color: String, n: int, speed := 260.0, life := 0.45) -> void:
	n = int(ceil(n * 0.35)) if quality == 0 else (int(ceil(n * 0.65)) if quality == 1 else n)
	for i in n:
		var a := U.random() * TAU
		var s := speed * U.rand(0.35, 1.1)
		var p := _p(P_SPARK, x, y, cos(a) * s, sin(a) * s, life * U.rand(0.6, 1.2), U.rand(1.2, 2.6), color)
		if p: p.drag = 3.2


func embers(x: float, y: float, color: String, n: int, speed := 90.0) -> void:
	if quality == 0: return
	for i in n:
		var a := U.random() * TAU
		var s := speed * U.rand(0.3, 1.0)
		var p := _p(P_EMBER, x, y, cos(a) * s, sin(a) * s, U.rand(0.5, 1.1), U.rand(1.5, 3.0), color)
		if p: p.drag = 1.5


func glow_puff(x: float, y: float, color: String, size: float, life := 0.3, vx := 0.0, vy := 0.0) -> Part:
	var p := _p(P_GLOW, x, y, vx, vy, life, size, color)
	if p: p.grow = 0.6
	return p


func smoke(x: float, y: float, n: int, size: float) -> void:
	if quality == 0: return
	for i in n:
		var a := U.random() * TAU
		var s := U.rand(10, 50)
		var p := _p(P_SMOKE, x + U.rand(-6, 6), y + U.rand(-6, 6), cos(a) * s, sin(a) * s + 20.0, U.rand(0.7, 1.3), size * U.rand(0.6, 1.1), "#1a1d2e")
		if p:
			p.drag = 1.2
			p.grow = 1.2


func debris(x: float, y: float, color: String, n: int, speed := 160.0) -> void:
	if quality == 0: return
	var rocks := 6 if G.has("fx_rock1") else 0
	for i in n:
		var a := U.random() * TAU
		var s := speed * U.rand(0.4, 1.0)
		var p := _p(P_DEBRIS, x, y, cos(a) * s, sin(a) * s, U.rand(0.6, 1.2), U.rand(2, 4.5), color)
		if p:
			p.drag = 1.4; p.rot = U.random() * TAU; p.vr = U.rand(-12, 12)
			if rocks and U.random() < 0.55: p.spr = "fx_rock%d" % (1 + int(U.random() * rocks))


func ring(x: float, y: float, r0: float, r1: float, color: String, dur: float, width := 3.0) -> void:
	if rings.size() > 40: rings.pop_front()
	rings.append({"x": x, "y": y, "r0": r0, "r1": r1, "color": color, "life": dur, "max": dur, "w": width})
	# большое кольцо (бомба, нова, смерть босса) — ударная волна по экрану
	if r1 >= G.FW * 0.8 and width >= 6:
		Post.wave(x, y, 1.0 + (width - 6) * 0.1)
		Vfx.burst(x, y, color, 1.6)


## взрыв: size ~ 1 (малый) … 4 (босс); o.kind: crit | kill | ship | plasma | super | boss; o.hue — перекраска
func explode(x: float, y: float, size := 1.0, color := "", o := {}) -> void:
	var S := G.S
	var kind: String = o.get("kind", "")
	var base := "fx_ex_kill" if kind == "kill" or size >= 2.5 else ("fx_ex_l" if size >= 1.5 else ("fx_ex_m" if size >= 0.95 else "fx_ex_s"))
	var name := base
	match kind:
		"crit": name = "fx_ex_crit"
		"plasma": name = "fx_hit_plasma"
		"super": name = "fx_superblast"
		"boss": name = "fx_superex"
		"ship": name = "fx_kd_l" if size >= 1.5 else ("fx_kd_m" if size >= 0.95 else "fx_kd_s")
	if not G.has(name): name = base
	if G.has(name):
		var hue = o.get("hue")
		expl.append({"x": x, "y": y, "life": 0.0, "dur": 0.36 + size * 0.07, "w": (44 + size * 30) * S * (1.15 if kind != "" else 1.0),
			"rot": U.random() * TAU, "name": name, "cv": null if hue == null else G.tinted(name, {"hue": hue})})
	else:
		expl.append({"x": x, "y": y, "life": 0.0, "dur": 0.42 + size * 0.08, "w": (58 + size * 34) * S, "rot": U.random() * TAU, "name": "", "cv": null})
	glow_puff(x, y, color if color != "" else "#ffb03d", (90 + size * 70) * S, 0.25 + size * 0.05)
	ring(x, y, 6 * S, (40 + size * 38) * S, color if color != "" else "#ffd9a0", 0.32 + size * 0.06, 2 + size)
	sparks(x, y, color if color != "" else "#ffcf6b", 8 + int(round(size * 7)), 220 + size * 60, 0.4 + size * 0.06)
	if size >= 1.4: debris(x, y, "#8a93b8", int(round(size * 4)), 140 + size * 30)
	if size >= 1.2: smoke(x, y, int(round(size * 2.5)), (28 + size * 12) * S)
	if size >= 1.5: embers(x, y, color if color != "" else "#ff9f3d", int(round(size * 5)), 120)
	# искажение экрана: смерть босса — мощная волна, супервзрыв — средняя, крупные взрывы — лёгкая
	if kind == "boss": Post.wave(x, y, 2.2)
	elif kind == "super" or size >= 2.5: Post.wave(x, y, 0.8)
	elif size >= 1.6: Post.wave(x, y, 0.3)
	# сноп искр на частицах движка
	var sc := color if color != "" else "#ffb03d"
	if kind == "boss": Vfx.burst(x, y, sc, 3.0)
	elif kind == "super" or kind == "kill" or size >= 2.5: Vfx.burst(x, y, sc, 1.4)
	elif size >= 1.6: Vfx.burst(x, y, sc, 0.6)


func hit(x: float, y: float, color: String) -> void:
	glow_puff(x, y, color, 26 * G.S, 0.12)
	if quality > 0: sparks(x, y, color, 3, 180, 0.22)


func beam(points: PackedVector2Array, color: String, width := 3.0, dur := 0.14) -> void:
	if beams.size() > 30: beams.pop_front()
	beams.append({"pts": points, "color": color, "w": width, "life": dur, "max": dur})


func lightning(x0: float, y0: float, x1: float, y1: float, color: String, width := 3.0, dur := 0.14) -> void:
	var d := sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0))
	var segs := maxi(3, int(round(d / 22.0)))
	var dd := d if d > 0.0 else 1.0
	var nx := -(y1 - y0) / dd
	var ny := (x1 - x0) / dd
	var pts := PackedVector2Array([Vector2(x0, y0)])
	for i in range(1, segs):
		var t := float(i) / segs
		var off := U.rand(-1, 1) * minf(18.0, d * 0.12)
		pts.append(Vector2(lerpf(x0, x1, t) + nx * off, lerpf(y0, y1, t) + ny * off))
	pts.append(Vector2(x1, y1))
	beam(pts, color, width, dur)
	# у длинного разряда — одна-две короткие ветки
	if d > 70.0 and quality > 0:
		for k in (2 if d > 160.0 else 1):
			var i := 1 + int(U.random() * (pts.size() - 2))
			var p := pts[i]
			var a := atan2(y1 - y0, x1 - x0) + U.rand(0.5, 1.1) * (-1.0 if U.random() < 0.5 else 1.0)
			var L := U.rand(0.15, 0.3) * d
			var br := PackedVector2Array([p])
			for j in range(1, 4):
				br.append(Vector2(p.x + cos(a) * L * j / 3.0 + U.rand(-5, 5), p.y + sin(a) * L * j / 3.0 + U.rand(-5, 5)))
			beam(br, color, width * 0.5, dur * 0.8)


func text(x: float, y: float, s: String, color := "#ffffff", size := 13.0, dur := 0.7, vy := -55.0) -> void:
	if texts.size() > 60: texts.pop_front()
	texts.append({"x": x, "y": y, "s": s, "c": color, "size": size, "life": dur, "max": dur, "vy": vy})


func dmg_num(x: float, y: float, n: int, crit: bool) -> void:
	text(x, y, (str(n) + "!") if crit else str(n), "#ffd23d" if crit else "#ffffff", 15 if crit else 11, 0.65 if crit else 0.45, -70)


## спрайт листа эффектов: ширина растёт от w0 до w1, после доли hold — затухание
## o: w0, w1, dur, hue, rot, vr, alpha, hold, fadeIn, vy, sy, follow (объект с x/y), ox, oy, minor
func sprite(name: String, x: float, y: float, o: Dictionary) -> Spr:
	if not G.has(name) or (o.get("minor", false) and quality == 0):
		return null
	if sprites.size() > 50: sprites.pop_front()
	var s := Spr.new()
	s.name = name; s.x = x; s.y = y
	s.w0 = o.get("w0", 20.0); s.w1 = o.get("w1", s.w0)
	s.dur = o.get("dur", 0.5); s.rot = o.get("rot", 0.0); s.vr = o.get("vr", 0.0)
	s.a = o.get("alpha", 1.0); s.hold = o.get("hold", 0.35); s.fade_in = o.get("fadeIn", 0.0)
	s.vy = o.get("vy", 0.0); s.sy = o.get("sy", 1.0); s.follow = o.get("follow"); s.ox = o.get("ox", 0.0); s.oy = o.get("oy", 0.0)
	var hue = o.get("hue")
	s.cv = null if hue == null else G.tinted(name, {"hue": hue})
	sprites.append(s)
	return s


## портал: open — раскрывается (появление), иначе схлопывается
func portal(x: float, y: float, w: float, color: String, open: bool) -> void:
	var hue = G.hue_of(color) if color != "" else null
	if open:
		sprite("fx_portal_out", x, y, {"w0": w * 0.25, "w1": w, "dur": 0.5, "hold": 0.55, "hue": hue})
	else:
		sprite("fx_portal_in", x, y, {"w0": w, "w1": w * 0.15, "dur": 0.4, "hold": 0.5, "hue": hue})


func vignette(color: String, dur: float, a: float, pulse := false) -> void:
	for s in scr:
		if s.color == color:
			s.life = 0.0; s.dur = dur; s.a = maxf(s.a, a); s.pulse = pulse
			return
	scr.append({"color": color, "life": 0.0, "dur": dur, "a": a, "pulse": pulse})


## дуга урона у края поля со стороны, откуда прилетело (px, py — корабль, sx, sy — источник)
func dmg_arc(px: float, py: float, sx: float, sy: float, color := "#ff2a48") -> void:
	var dx := sx - px
	var dy := sy - py
	if dx * dx + dy * dy < 4.0: return
	if arcs.size() >= 4: arcs.pop_front()
	arcs.append({"a": atan2(dy, dx), "px": px, "py": py, "color": color, "life": 0.0, "dur": 0.8})


## снежинка инея: медленно падает и гаснет (заморозка)
func frost(x: float, y: float) -> void:
	var p := _p(P_EMBER, x, y, U.rand(-12, 12), U.rand(25, 55), U.rand(1.4, 2.4), U.rand(2.2, 3.6), "#e6fbff" if U.random() < 0.5 else "#9be8ff")
	if p: p.drag = 0.3


func flash(color := "#ffffff", a := 0.5) -> void:
	flash_color = color
	flash_a = maxf(flash_a, a)


func shake(amount: float) -> void:
	if shake_on: trauma = minf(1.0, trauma + amount)


func update(dt: float) -> void:
	if trauma > 0.0:
		trauma = maxf(0.0, trauma - dt * 1.6)
		var s := trauma * trauma * 16.0
		shake_x = U.rand(-1, 1) * s
		shake_y = U.rand(-1, 1) * s
	else:
		shake_x = 0.0
		shake_y = 0.0
	if flash_a > 0.0: flash_a = maxf(0.0, flash_a - dt * 2.2)
	var i := parts.size() - 1
	while i >= 0:
		var p := parts[i]
		p.life -= dt
		if p.life <= 0.0:
			parts[i] = parts[parts.size() - 1]
			parts.pop_back()
		else:
			if p.drag != 0.0:
				var k := exp(-p.drag * dt)
				p.vx *= k; p.vy *= k
			p.x += p.vx * dt; p.y += p.vy * dt
			if p.vr != 0.0: p.rot += p.vr * dt
			if p.grow != 0.0: p.size *= 1.0 + p.grow * dt
		i -= 1
	_age(expl, dt, true)
	for j in range(sprites.size() - 1, -1, -1):
		var s := sprites[j]
		s.life += dt
		if s.life >= s.dur:
			sprites.remove_at(j)
			continue
		s.rot += s.vr * dt
		s.oy += s.vy * dt
	_age(scr, dt, true)
	_age(arcs, dt, true)
	_age(rings, dt, false)
	_age(beams, dt, false)
	for j in range(texts.size() - 1, -1, -1):
		var t: Dictionary = texts[j]
		t.life -= dt
		t.y += t.vy * dt
		t.vy *= exp(-2.5 * dt)
		if t.life <= 0.0: texts.remove_at(j)


## up — жизнь растёт до dur; иначе убывает до нуля
func _age(arr: Array, dt: float, up: bool) -> void:
	for j in range(arr.size() - 1, -1, -1):
		var e: Dictionary = arr[j]
		if up:
			e.life += dt
			if e.life >= e.dur: arr.remove_at(j)
		else:
			e.life -= dt
			if e.life <= 0.0: arr.remove_at(j)


# ── отрисовка ──
## слой под врагами: дым и обломки
func draw_back(ctx: Ctx) -> void:
	for p in parts:
		if p.t == P_SMOKE:
			ctx.alpha = p.life / p.max * 0.55
			ctx.draw_tex(G.soft("#232845", 64), p.x - p.size, p.y - p.size, p.size * 2, p.size * 2)
		elif p.t == P_DEBRIS:
			ctx.alpha = minf(1.0, p.life / p.max * 2.0)
			if p.spr != "":
				G.draw(ctx, p.spr, p.x, p.y, p.size * 3.4, p.rot)
				continue
			ctx.fill = U.col(p.color)
			ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(p.rot)
			ctx.fill_rect(-p.size, -p.size * 0.5, p.size * 2, p.size)
			ctx.restore()
	ctx.alpha = 1.0


## аддитивный слой: взрывы, спрайты эффектов, искры, свечения, кольца, молнии
func draw_front(ctx: Ctx) -> void:
	ctx.additive = true
	for e in expl:
		var k: float = e.life / e.dur
		if e.name != "":
			ctx.alpha = 1.0 if k < 0.45 else (1.0 - k) / 0.55
			var w: float = e.w * (0.45 + 0.75 * U.ease_out_cubic(k))
			if e.cv: G.draw_canvas(ctx, e.cv, e.x, e.y, w, e.rot)
			else: G.draw(ctx, e.name, e.x, e.y, w, e.rot)
			continue
		var fi := mini(4, int(k * 5))
		ctx.alpha = (1.0 - k) / 0.3 if k > 0.7 else 1.0
		G.draw(ctx, "ex%d" % (fi + 1), e.x, e.y, e.w * (0.75 + k * 0.45), e.rot)
	for s in sprites:
		var k := s.life / s.dur
		var fade := (k / s.fade_in) if k < s.fade_in else ((1.0 - (k - s.hold) / (1.0 - s.hold)) if k > s.hold else 1.0)
		ctx.alpha = s.a * maxf(0.0, fade)
		var w := s.w0 + (s.w1 - s.w0) * U.ease_out_cubic(k)
		var x: float = (s.follow.x if s.follow else s.x) + s.ox
		var y: float = (s.follow.y if s.follow else s.y) + s.oy
		if s.sy != 1.0:
			ctx.save(); ctx.translate(x, y); ctx.scale(1.0, s.sy)
			x = 0.0; y = 0.0
		if s.cv: G.draw_canvas(ctx, s.cv, x, y, w, s.rot)
		else: G.draw(ctx, s.name, x, y, w, s.rot)
		if s.sy != 1.0: ctx.restore()
	for p in parts:
		var k := p.life / p.max
		if p.t == P_SPARK:
			ctx.alpha = k
			ctx.stroke = U.col(p.color); ctx.line_width = p.size
			ctx.stroke_line(p.x, p.y, p.x - p.vx * 0.035, p.y - p.vy * 0.035)
		elif p.t == P_GLOW:
			ctx.alpha = k
			ctx.draw_tex(G.glow(p.color, 64), p.x - p.size / 2.0, p.y - p.size / 2.0, p.size, p.size)
		elif p.t == P_EMBER:
			ctx.alpha = k
			ctx.fill = U.col(p.color)
			ctx.fill_rect(p.x - p.size / 2.0, p.y - p.size / 2.0, p.size, p.size)
	for r in rings:
		var k: float = 1.0 - r.life / r.max
		var rad := lerpf(r.r0, r.r1, U.ease_out_cubic(k))
		ctx.alpha = (1.0 - k) * 0.9
		ctx.stroke = U.col(r.color); ctx.line_width = r.w * (1.0 - k * 0.6)
		ctx.begin_path(); ctx.arc(r.x, r.y, rad, 0, TAU); ctx.stroke_path()
	for b in beams:
		var k: float = b.life / b.max
		for ps in 3:
			ctx.alpha = k if ps == 2 else (k * 0.5 if ps == 1 else k * 0.14)
			ctx.stroke = Color.WHITE if ps == 2 else U.col(b.color)
			ctx.line_width = b.w * 0.45 if ps == 2 else (b.w * 2.2 if ps == 1 else b.w * 6.0)
			ctx.begin_path()
			var pts: PackedVector2Array = b.pts
			for i in pts.size():
				if i == 0: ctx.move_to(pts[i].x, pts[i].y)
				else: ctx.line_to(pts[i].x, pts[i].y)
			ctx.stroke_path()
	ctx.alpha = 1.0
	ctx.additive = false


func draw_texts(ctx: Ctx) -> void:
	for t in texts:
		var k: float = t.life / t.max
		var pop := 1.0 + (k - 0.85) * 2.5 if k > 0.85 else 1.0
		ctx.alpha = minf(1.0, k * 2.2)
		ctx.fill = U.col(t.c)
		var size := int(round(t.size * pop * 1.15))
		# надпись у края поля (подобранный бонус, «УКЛОНЕНИЕ» у прижатого к краю корабля) не обрезается
		var hw := ctx.text_width(t.s, size) / 2.0 + 4.0
		var x: float = clampf(t.x, hw, maxf(hw, G.FW - hw))
		ctx.fill_text(t.s, x, t.y + size * 0.35, size, 1, 4, Color(0, 0, 0.04, 0.85))
	ctx.alpha = 1.0


func draw_flash(ctx: Ctx, w: float, h: float) -> void:
	if flash_a <= 0.01: return
	ctx.alpha = flash_a
	ctx.fill = U.col(flash_color)
	ctx.fill_rect(0, 0, w, h)
	ctx.alpha = 1.0


## цветная виньетка по краям экрана (урон, тревога босса, заморозка)
func draw_screen(ctx: Ctx, w: float, h: float) -> void:
	if scr.is_empty(): return
	ctx.additive = true
	for s in scr:
		var k: float = s.life / s.dur
		ctx.alpha = s.a * ((0.45 + 0.55 * absf(sin(s.life * 5.0))) if s.pulse else 1.0) * ((k / 0.12) if k < 0.12 else 1.0 - maxf(0.0, k - 0.45) / 0.55)
		ctx.draw_tex(_vignette_tex(s.color), 0, 0, w, h)
	ctx.alpha = 1.0
	ctx.additive = false


func _vignette_tex(color: String) -> Texture2D:
	var key := "v" + color
	if _vig.has(key): return _vig[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.8, 1.0])
	g.colors = PackedColorArray([U.col(color, 0.0), U.col(color, 0.0), U.col(color, 0.22), U.col(color, 0.75)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 128; t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.15, 0.5)
	_vig[key] = t
	return t


## дуги урона у края поля
func draw_arcs(ctx: Ctx, x0: float, w: float, h: float) -> void:
	if arcs.is_empty(): return
	var S := G.S
	var L := minf(w, h) * 0.34
	var D := 30.0 * S
	ctx.additive = true
	for s in arcs:
		var ox: float = x0 + s.px
		var oy: float = s.py
		var cx := cos(s.a)
		var cy := sin(s.a)
		var tx := (x0 + w - ox) / cx if cx > 1e-4 else ((x0 - ox) / cx if cx < -1e-4 else INF)
		var ty := (h - oy) / cy if cy > 1e-4 else (-oy / cy if cy < -1e-4 else INF)
		var t := maxf(0.0, minf(tx, ty))
		var k: float = s.life / s.dur
		ctx.alpha = ((k / 0.1) if k < 0.1 else 1.0 - maxf(0.0, k - 0.35) / 0.65) * 0.9
		ctx.save()
		ctx.translate(ox + cx * t, oy + cy * t)
		ctx.rotate(PI / 2 if tx < ty else 0.0)
		var im := G.soft(s.color, 64)
		ctx.draw_tex(im, -L, -D, L * 2, D * 2)
		ctx.draw_tex(im, -L * 0.5, -D * 0.45, L, D * 0.9)
		ctx.restore()
	ctx.alpha = 1.0
	ctx.additive = false
