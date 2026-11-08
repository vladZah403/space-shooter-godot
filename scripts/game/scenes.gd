extends Node
## Сцены узлов карты: анимации (автозагрузка Scenes) — перенос scenes.js.
##  Контрабандист (прилёт с торможением, огни, неоновая вывеска, грузы на орбите, луч стыковки, реплика, отлёт),
##  ремонт (сварка, наноботы), тайник (падает, трясётся, лопается — кредиты летят в кошелёк), элита (строй,
##  мигалки), события (обломки с искрами, маяк SOS, чёрный рынок, аномалия, заброшенная станция, игральный
##  автомат), контейнер. Плюс актёры после сцены (отлёт контрабандиста). Координаты — поля боя.
##  Живой портрет контрабандиста в окне лавки (SC.portrait) — часть интерфейса, переносится вместе с ним.
##  Градиенты canvas здесь — многоугольники с цветом в вершинах (Ctx.fill_poly), тени текста — мягкое свечение.

## реплики контрабандиста
const HELLO := ["Заходи, пилот!", "Свежий товар!", "Лучшие цены в секторе!", "Для тебя — скидок нет", "Только сегодня!", "Всё с гарантией. Почти"]
const BYE_BUY := ["Спасибо за покупку!", "Отличный выбор!", "Приходи ещё!"]
const BYE := ["Не надумал? Бывает", "Удачи в бою!", "Ещё увидимся"]

var actors: Array = []


# ── мелкие помощники ──
## язык пламени из точки (x, y) по направлению ang (0 — вниз), длина len
func flame(ctx: Ctx, x: float, y: float, w: float, len: float, ang: float, c1 := "#9be8ff", c2 := "#3d7dff", t := 0.0) -> void:
	var fl := 0.8 + 0.2 * sin(t * 40 + x) + U.random() * 0.12
	ctx.save()
	ctx.translate(x, y); ctx.rotate(ang)
	ctx.additive = true
	ctx.alpha = 0.95
	ctx.draw_tex(Game.flameSprite(["#ffffff", c1, c2]), -w / 2, -len * 0.05, w, len * fl)
	ctx.alpha = 0.5
	ctx.draw_tex(G.glow(c1, 64), -w * 1.3, -w * 0.9, w * 2.6, w * 2.6)
	ctx.restore()


func lamp(ctx: Ctx, x: float, y: float, col: String, s: float, a: float) -> void:
	if a <= 0: return
	ctx.save(); ctx.additive = true; ctx.alpha = a
	ctx.draw_tex(G.glow(col, 32), x - s / 2, y - s / 2, s, s)
	ctx.restore()


func glow(ctx: Ctx, x: float, y: float, r: float, col: String, a: float) -> void:
	ctx.save(); ctx.additive = true; ctx.alpha = a
	ctx.draw_tex(G.soft(col, 64), x - r, y - r, r * 2, r * 2)
	ctx.restore()


## текст по центру (x, y — середина строки) с мягким свечением вместо shadowBlur
func glowText(ctx: Ctx, text: String, x: float, y: float, size: int, col: Color, shadow := "", blur := 0.0) -> void:
	if shadow != "" and blur > 0:
		var tw := ctx.text_width(text, size)
		var a0 := ctx.alpha
		ctx.save(); ctx.additive = true; ctx.alpha = a0 * 0.55
		ctx.draw_tex(G.soft(shadow, 64), x - tw / 2 - blur, y - size * 0.5 - blur, tw + blur * 2, size + blur * 2)
		ctx.restore()
	ctx.fill = col
	ctx.fill_text(text, x, y + size * 0.36, size, 1)


## реплика в облачке; a — прозрачность, side — хвостик слева (-1) или справа (1)
func bubble(ctx: Ctx, x: float, y: float, text: String, a: float, side := 0.0) -> void:
	if a <= 0 or text == "": return
	var S := G.S
	ctx.save()
	ctx.alpha = a
	var fs := int(round(13 * S))
	var tw := ctx.text_width(text, fs)
	var pw := tw + 18 * S
	var ph := 26 * S
	var bx := maxf(6 * S, minf(G.FW - pw - 6 * S, x - pw / 2))
	var by := y - ph
	ctx.fill = Color(1, 250 / 255.0, 235 / 255.0, 0.96)
	ctx.begin_path(); ctx.round_rect(bx, by, pw, ph, 9 * S); ctx.fill_path()
	var tx := U.clamp(x + side * 14 * S, bx + 12 * S, bx + pw - 12 * S)
	ctx.begin_path(); ctx.move_to(tx - 6 * S, by + ph - 1); ctx.line_to(tx + 6 * S, by + ph - 1); ctx.line_to(tx - side * 4 * S, by + ph + 8 * S); ctx.close_path(); ctx.fill_path()
	ctx.fill = U.col("#1b1430")
	ctx.fill_text(text, bx + pw / 2, by + ph / 2 + 1 + fs * 0.36, fs, 1)
	ctx.restore()


## неоновая вывеска: включается с миганием (on — когда начать)
func neon(ctx: Ctx, x: float, y: float, text: String, col: String, t: float, on: float) -> void:
	var lt := t - on
	if lt < 0: return
	# первые 0,4 с — неуверенное мигание, потом ровный свет с лёгким гулом
	var flick := false
	for q in [0.05, 0.12, 0.2, 0.28, 0.36]:
		if lt > q and lt < q + 0.05: flick = true
	var vis := 0.9 + 0.1 * sin(t * 50) if lt > 0.4 else (1.0 if flick else 0.15)
	var S := G.S
	var fs := int(round(14 * S))
	ctx.save()
	var tw := ctx.text_width(text, fs)
	ctx.alpha = 0.75; ctx.fill = Color(20 / 255.0, 8 / 255.0, 30 / 255.0, 0.85); ctx.stroke = U.col(col, 0.5 * vis); ctx.line_width = 1.5 * S
	ctx.begin_path(); ctx.round_rect(x - tw / 2 - 9 * S, y - 12 * S, tw + 18 * S, 24 * S, 6 * S); ctx.fill_path(); ctx.stroke_path()
	ctx.alpha = vis
	glowText(ctx, text, x, y + 1, fs, U.col("#fff6d8") if vis > 0.5 else U.col(col, 0.5), col, 14 * S * vis)
	ctx.restore()


static func ease3(k: float) -> float:
	return 1 - pow(1 - clampf(k, 0, 1), 3)


static func bounceOut(k: float) -> float:
	var n := 7.5625
	var d := 2.75
	k = clampf(k, 0, 1)
	if k < 1 / d: return n * k * k
	if k < 2 / d:
		k -= 1.5 / d
		return n * k * k + 0.75
	if k < 2.5 / d:
		k -= 2.25 / d
		return n * k * k + 0.9375
	k -= 2.625 / d
	return n * k * k + 0.984375


## луч-трапеция с вертикальным градиентом (canvas createLinearGradient сверху вниз)
func beamQuad(ctx: Ctx, pts: PackedVector2Array, ctop: Color, cbot: Color) -> void:
	ctx.fill_poly(pts, PackedColorArray([ctop, ctop, cbot, cbot]))


## контрабандист целиком: свечение, огни, пламя, грузы на орбите; (x, y) — центр, w — ширина
## o: thrust, cargo (0..1), sign (когда зажечь вывеску), tilt
func merchant(ctx: Ctx, x: float, y: float, w: float, t: float, o: Dictionary) -> void:
	var S := G.S
	var h := w * G.aspect("p_merchant")
	var thrust: float = o.get("thrust", 0.0)
	var cargo: float = o.get("cargo", 0.0)
	glow(ctx, x, y, w * 0.95, "#ffc83d", 0.32 + 0.06 * sin(t * 3))
	# грузы на орбите: дальняя половина — за корпусом
	var items := 7 if cargo > 0 else 0
	var orb := func(front: bool) -> void:
		for i in items:
			var a := t * 0.9 + i * TAU / items
			var z := sin(a)
			if (z > 0) != front: continue
			var ox := x + cos(a) * w * 0.78
			var oy := y + h * 0.05 + z * h * 0.18
			var sc := 0.75 + 0.25 * z
			var a0 := ctx.alpha
			ctx.alpha = (0.55 + 0.45 * (z + 1) / 2) * cargo * a0
			if i % 3 == 0: G.draw(ctx, "p_crate", ox, oy, 20 * S * sc, a)
			else: ctx.draw_tex(G.proc("coin"), ox - 8 * S * sc, oy - 8 * S * sc, 16 * S * sc, 16 * S * sc)
			ctx.alpha = a0
	orb.call(false)
	# двигатель: при торможении — длинный язык
	flame(ctx, x, y + h * 0.44, w * 0.16, w * (0.25 + thrust * 0.75), 0, "#9be8ff", "#3d7dff", t)
	var tilt: float = o.get("tilt", 0.0)
	if tilt:
		ctx.save(); ctx.translate(x, y); ctx.rotate(tilt); G.draw(ctx, "p_merchant", 0, 0, w); ctx.restore()
	else:
		G.draw(ctx, "p_merchant", x, y, w)
	# антенны мигают по очереди, боковые фонари — медленно
	lamp(ctx, x - w * 0.22, y - h * 0.49, "#ff4d3d", 14 * S, 1.0 if sin(t * 6) > 0 else 0.15)
	lamp(ctx, x + w * 0.26, y - h * 0.49, "#ff4d3d", 14 * S, 0.15 if sin(t * 6) > 0 else 1.0)
	lamp(ctx, x - w * 0.47, y - h * 0.04, "#ffc83d", 18 * S, 0.45 + 0.4 * sin(t * 2.2))
	lamp(ctx, x + w * 0.47, y - h * 0.04, "#ffc83d", 18 * S, 0.45 + 0.4 * sin(t * 2.2 + 1.5))
	# огоньки витрины
	var cols := ["#ff5c7a", "#3de0ff", "#ffc83d", "#3dffa2", "#b06bff"]
	for i in 5: lamp(ctx, x + (i - 2) * w * 0.14, y - h * 0.02, cols[i], 8 * S, 0.9 if sin(t * 5 + i * 1.3) > 0.2 else 0.2)
	orb.call(true)
	if o.get("sign", 0.0): neon(ctx, x, y - h * 0.62, "ЛАВКА", "#ffc83d", t, o.sign)


# ════════════════════════════════════════════════════════════
# СЦЕНЫ УЗЛОВ
# ════════════════════════════════════════════════════════════
func update(sc: Dictionary) -> void:
	var p: Pl = Game.player
	var S := G.S
	var t: float = sc.t
	var cx := G.FW / 2
	# в эскорте Контрабандист встаёт посередине — подпись выше него
	if sc.get("card") == null and t >= sc.cardT:
		sc.card = {"cap": sc.v.cap, "name": sc.v.name, "sub": sc.v.sub, "at": t, "y": 0.4 if sc.node == "escort" else 0.58}
	match sc.node:
		"shop":
			if sc.get("hello", "") == "": sc.hello = U.pick(HELLO)
			if not sc.get("braked", false) and t > 0.5:
				sc.braked = true; A.play("teleport", {"rate": 0.6, "vol": 0.35}); FX.shake(0.08)
			if not sc.get("docked", false) and t > 1.15:
				sc.docked = true; A.play("coin", {"rate": 0.9, "vol": 0.5})
		"repair":
			# сварка: искры по корпусу, «+» поднимаются
			if t > 0.9 and t < 2.0 and U.random() < 0.35: FX.sparks(p.x + U.rand(-0.35, 0.35) * p.w, p.y + U.rand(-0.3, 0.3) * p.w, "#ffe9a0" if U.random() < 0.5 else "#3dffa2", 3, 160, 0.3)
			if t > 1.0 and t < 2.0 and U.random() < 0.06: FX.text(p.x + U.rand(-0.4, 0.4) * p.w, p.y - p.w * 0.4, "+", "#3dffa2", 18, 0.7, -70)
			if not sc.done and t >= 1.5:
				sc.done = true; FX.ring(p.x, p.y, p.w * 0.3, p.w * 1.6, "#3dffa2", 0.5, 4); FX.sparks(p.x, p.y, "#3dffa2", 14, 200); A.play("powerup", {"vol": 0.6})
		"cache":
			var y := G.H * 0.42
			if not sc.get("landed", false) and t >= 0.7:
				sc.landed = true; FX.ring(cx, y + 26 * S, 8 * S, 80 * S, "#b06bff", 0.4, 3); FX.smoke(cx, y + 26 * S, 5, 26 * S); A.play("mine", {"rate": 0.7, "vol": 0.4}); FX.shake(0.1)
			if not sc.done and t >= 1.5:
				sc.done = true
				FX.explode(cx, y, 1, "#ffc83d"); FX.ring(cx, y, 10 * S, 90 * S, "#ffc83d", 0.4, 4)
				FX.debris(cx, y, "#8a6a3a", 8, 260)
				# кредиты летят в кошелёк (вверх вправо)
				var coins: Array = []
				for i in 14: coins.append({"a": U.rand(-PI, 0), "v": U.rand(80, 200) * S, "d": U.rand(0, 0.25)})
				sc.coins = coins
				A.play("coin", {"rate": 0.8})
		"elite":
			if not sc.done and t >= 1.5:
				sc.done = true; FX.vignette("#ff2a48", 1.2, 0.6, true)
			if U.random() < 0.1: FX.shake(0.05)
		"event":
			var id: String = sc.ev.id
			var y := G.H * 0.36
			if (id == "wreck" or id == "distress") and U.random() < 0.12: FX.sparks(cx + U.rand(-40, 40) * S, y + U.rand(-25, 25) * S, "#ffd27a", 4, 140, 0.35)
			if (id == "wreck" or id == "station") and U.random() < 0.05: FX.smoke(cx + U.rand(-30, 30) * S, y + U.rand(-20, 20) * S, 1, 18 * S)
			if id == "slot" and not sc.get("spun", false) and t > 0.9:
				sc.spun = true; A.play("coin", {"rate": 1.4, "vol": 0.4})
			if id == "anomaly" and U.random() < 0.5:
				# частицы затягивает в воронку
				var a := U.random() * TAU
				var r := U.rand(90, 150) * S
				sc.get_or_add("suck", []).append({"a": a, "r": r, "r0": r, "t": 0.0})
		"chest":
			var col: String = D.CHESTS[sc.tier].color
			var cy := G.H * 0.36
			if not sc.get("landed", false) and t >= 0.6:
				sc.landed = true
				FX.ring(cx, cy + 20 * S, 10 * S, 110 * S, col, 0.45, 4)
				FX.sparks(cx, cy + 24 * S, col, 16, 260)
				FX.shake(0.18)
				A.play("mine", {"rate": 0.6, "vol": 0.45})
			if sc.get("landed", false) and t < 1.6 and U.random() < 0.25: FX.sparks(cx + U.rand(-40, 40) * S, cy + U.rand(-30, 20) * S, col, 1, 60)
			if not sc.get("gone", false) and t >= 1.6:
				sc.gone = true; A.play("coin", {"rate": 0.7, "vol": 0.7})


func draw(ctx: Ctx, sc: Dictionary) -> void:
	var S := G.S
	var t: float = sc.t
	var p: Pl = Game.player
	var cx := G.FW / 2
	ctx.save()
	match sc.node:
		"shop":
			# прилёт сверху с торможением: длинное пламя, потом зависание
			var k := U.clamp(t / 1.0, 0, 1)
			var y := U.lerp(-140 * S, G.H * 0.33, ease3(k)) + (sin(t * 2) * 4 * S if k >= 1 else 0.0)
			var w := 130 * S
			var thrust := 1 - ease3(k) * 0.6 if t < 1.0 else 0.15
			# луч стыковки к кораблю
			if t > 1.15:
				var a := minf(1, (t - 1.15) / 0.3) * (0.28 + 0.06 * sin(t * 9))
				var top := y + w * 0.62
				var pw := p.w * 0.7
				ctx.save(); ctx.additive = true; ctx.alpha = a
				beamQuad(ctx, PackedVector2Array([Vector2(cx - w * 0.1, top), Vector2(cx + w * 0.1, top), Vector2(p.x + pw, p.y - p.w * 0.2), Vector2(p.x - pw, p.y - p.w * 0.2)]),
					Color(1, 200 / 255.0, 61 / 255.0, 0.9), Color(1, 200 / 255.0, 61 / 255.0, 0.1))
				# искорки бегут по лучу
				for i in 6:
					var q := fmod(t * 0.8 + i / 6.0, 1.0)
					lamp(ctx, U.lerp(cx, p.x, q) + sin(q * 20 + i) * pw * 0.4 * q, U.lerp(top, p.y - p.w * 0.2, q), "#fff1a6", 9 * S, a * 2.2)
				ctx.restore()
			merchant(ctx, cx, y, w, t, {"thrust": thrust, "cargo": U.clamp((t - 1.0) / 0.4, 0, 1), "sign": 0.95})
			bubble(ctx, cx + w * 0.42, y - w * G.aspect("p_merchant") * 0.76, sc.get("hello", ""), U.clamp((t - 1.2) / 0.2, 0, 1), -1)
		"repair":
			var k := U.clamp(t / 0.9, 0, 1)
			var leave := U.clamp((t - 1.95) / 0.45, 0, 1)
			var y := U.lerp(-100 * S, p.y - p.w * 1.6, ease3(k)) + sin(t * 3) * 3 * S - leave * leave * 260 * S
			var w := 64 * S
			# медкорабль смотрит вниз: двигатели сверху
			flame(ctx, cx, y - w * 0.55, w * 0.22, w * (0.35 + (1 - k) * 0.8 + leave * 1.2), PI, "#9be8ff", "#3d7dff", t)
			glow(ctx, cx, y, w * 0.9, "#3dffa2", 0.25)
			G.draw(ctx, "p_medship", cx, y, w, PI)
			lamp(ctx, cx, y + w * 0.1, "#ff3d5a", 12 * S, 1.0 if sin(t * 8) > 0 else 0.2)
			if t > 0.9 and leave < 1:
				# ремонтный луч и наноботы по спирали вокруг корабля
				var a := (1 - leave) * (0.45 + 0.25 * sin(t * 18))
				ctx.save(); ctx.additive = true; ctx.alpha = a
				beamQuad(ctx, PackedVector2Array([Vector2(cx - 5 * S, y + w * 0.5), Vector2(cx + 5 * S, y + w * 0.5), Vector2(p.x + p.w * 0.5, p.y), Vector2(p.x - p.w * 0.5, p.y)]),
					Color(61 / 255.0, 1, 162 / 255.0, 0.85), Color(61 / 255.0, 1, 162 / 255.0, 0.15))
				ctx.restore()
				for i in 10:
					var q := t * 3 + i * TAU / 10
					var r := p.w * (0.55 + 0.15 * sin(t * 4 + i))
					lamp(ctx, p.x + cos(q) * r, p.y + sin(q) * r * 0.6, "#3dffa2", 8 * S, (1 - leave) * 0.9)
		"cache":
			var y0 := G.H * 0.42
			var y := U.lerp(-70 * S, y0, bounceOut(t / 0.7))
			# перед вскрытием — трясётся всё сильнее, из щелей свет
			var rattle := (t - 0.8) / 0.7 if t > 0.8 and t < 1.5 else 0.0
			var sx := sin(t * 60) * 4 * S * rattle if rattle else 0.0
			glow(ctx, cx, y, 70 * S, "#ffc83d", 0.3 + rattle * 0.5 + 0.1 * sin(t * 8))
			if not sc.done:
				ctx.alpha = 1.0
				G.draw(ctx, "p_crate", cx + sx, y, 66 * S, t * 4 if t < 0.7 else sin(t * 50) * 0.06 * rattle)
				if rattle > 0.3: lamp(ctx, cx + sx, y - 6 * S, "#fff1a6", 60 * S * rattle, rattle)
			# кредиты дугой в кошелёк
			if sc.get("coins") != null:
				var lt := t - 1.5
				var hx := G.FW - 40 * S
				var hy := 20 * S
				for c: Dictionary in sc.coins:
					var q := U.clamp((lt - c.d) / 0.75, 0, 1)
					if q <= 0 or q >= 1: continue
					var bx: float = cx + cos(c.a) * c.v * 0.6
					var by: float = y0 + sin(c.a) * c.v * 0.6
					var x := U.lerp(U.lerp(cx, bx, minf(1, q * 3)), hx, q * q)
					var yy := U.lerp(U.lerp(y0, by, minf(1, q * 3)), hy, q * q)
					ctx.alpha = 1 - q * 0.3
					ctx.draw_tex(G.proc("coin"), x - 8 * S, yy - 8 * S, 16 * S, 16 * S)
				ctx.alpha = 1.0
		"escort":
			# 4.2: Контрабандист поднимается снизу на позицию, откуда пойдёт под охраной (map.gd — ESCORT)
			var k := U.clamp(t / 1.3, 0, 1)
			merchant(ctx, cx, U.lerp(G.H + 90 * S, G.H * 0.66, ease3(k)), 84 * S, t, {"thrust": 1 - ease3(k) * 0.65})
		"elite":
			# мигалки тревоги из верхних углов: веер с прозрачным краем
			ctx.save(); ctx.additive = true
			for s in [-1.0, 1.0]:
				var a0: float = PI / 2 + s * (0.5 + 0.45 * sin(t * 5 + (PI if s > 0 else 0.0)))
				var ox := 0.0 if s < 0 else G.FW
				var L := G.H * 0.7
				var pts := PackedVector2Array([Vector2(ox, 0)])
				var cols := PackedColorArray([Color(1, 40 / 255.0, 70 / 255.0, 0.35)])
				for j in 7:
					var aa := lerpf(a0 - 0.18, a0 + 0.18, j / 6.0)
					pts.append(Vector2(ox + cos(aa) * L, sin(aa) * L))
					cols.append(Color(1, 40 / 255.0, 70 / 255.0, 0))
				ctx.fill_poly(pts, cols)
			ctx.restore()
			var k := ease3(t / 0.9)
			for i in 3:
				var x := cx + (i - 1) * 80 * S
				var y := U.lerp(-80 * S, G.H * 0.22, k) - absf(i - 1) * 30 * S + sin(t * 2.4 + i) * 3 * S
				var w := 58 * S
				flame(ctx, x - w * 0.18, y - w * 0.42, w * 0.16, w * (0.35 + (1 - k) * 0.6), PI, "#ffb36b", "#ff3d5a", t)
				flame(ctx, x + w * 0.18, y - w * 0.42, w * 0.16, w * (0.35 + (1 - k) * 0.6), PI, "#ffb36b", "#ff3d5a", t)
				glow(ctx, x, y, 40 * S, "#ff3d5a", 0.45)
				G.draw(ctx, "e_heavyfighter", x, y, w, PI)
				lamp(ctx, x, y + w * 0.2, "#ff2a48", 10 * S, 1.0 if sin(t * 10 + i * 2) > 0 else 0.2)
		"chest":
			drawChestScene(ctx, sc)
		"event":
			drawEvent(ctx, sc)
	ctx.restore()


func drawChestScene(ctx: Ctx, sc: Dictionary) -> void:
	var S := G.S
	var t: float = sc.t
	var cx := G.FW / 2
	var col: String = D.CHESTS[sc.tier].color
	var x := cx
	var y := U.lerp(-90 * S, G.H * 0.36, bounceOut(t / 0.6))
	var w := 96 * S
	var a := 1.0
	# улетает в трюм — к счётчику контейнеров вверху справа
	if t > 1.6:
		var q := U.clamp((t - 1.6) / 0.55, 0, 1)
		var e := q * q
		x = U.lerp(cx, G.FW - 34 * S, e); y = U.lerp(G.H * 0.36, 34 * S, e); w *= 1 - 0.75 * e; a = 1 - q * 0.7
	ctx.additive = true
	RunMap.rays(ctx, x, y, w * 1.7, col, t, 0.3 * a * minf(1, t * 2))
	ctx.alpha = 0.5 * a; ctx.draw_tex(G.soft(col, 64), x - w, y - w, w * 2, w * 2)
	ctx.additive = false; ctx.alpha = a
	# крышка подпрыгивает рывками — контейнер «просится» открыться
	var jolt := absf(sin(t * 40)) if t > 0.75 and t < 1.55 and sin(t * 9) > 0.2 else 0.0
	var m := G.draw_chest(ctx, sc.tier, x + ((U.random() - 0.5) * 3 * S if jolt else 0.0), y, w, 0, jolt)
	if jolt > 0.1: lamp(ctx, x, m.mouth, col, w * 1.1, jolt * 0.9 * a)
	ctx.alpha = 1.0


func drawEvent(ctx: Ctx, sc: Dictionary) -> void:
	var S := G.S
	var t: float = sc.t
	var cx := G.FW / 2
	var id: String = sc.ev.id
	var y := G.H * 0.36 + sin(t * 1.5) * 4 * S
	var a := minf(1, t * 2)
	ctx.alpha = a
	match id:
		"anomaly":
			# воронка, сжимающиеся кольца и затягиваемые частицы
			ctx.save(); ctx.additive = true
			for i in 4:
				var q := 1 - fmod(t * 0.6 + i / 4.0, 1.0)
				ctx.alpha = a * (1 - q) * 0.6; ctx.stroke = U.col("#b06bff"); ctx.line_width = 2 * S
				ctx.begin_path(); ctx.ellipse(cx, y, 150 * S * q, 90 * S * q, t * 0.3, 0, TAU); ctx.stroke_path()
			ctx.alpha = a; G.draw(ctx, "fx_vortex", cx, y, 180 * S, t * 2)
			var suck: Array = sc.get("suck", [])
			for pp: Dictionary in suck:
				pp.t += 1 / 60.0; pp.r = pp.r0 * (1 - pp.t / 1.1); pp.a += 0.08
				if pp.r > 4: lamp(ctx, cx + cos(pp.a) * pp.r, y + sin(pp.a) * pp.r * 0.6, "#d0a8ff", 8 * S, a * 0.9)
			if not suck.is_empty(): sc.suck = suck.filter(func(pp): return pp.t < 1.1)
			ctx.restore()
		"wreck", "distress":
			var x := cx + sin(t * 0.7) * 10 * S
			var rot := 2.4 + t * 0.15
			var w := 110 * S
			G.draw(ctx, "e_cargo", x, y, w, rot)
			# повреждённые огни мигают вразнобой
			for i in 4:
				var q := rot + i * 1.7
				var r := w * 0.28
				lamp(ctx, x + cos(q) * r, y + sin(q) * r, "#ffd27a" if i % 2 else "#7fe7ff", 12 * S, 0.9 if U.random() < 0.4 else 0.1)
			if id == "distress":
				# маяк SOS: вспышка и расходящиеся кольца сигнала
				var ph := fmod(t, 1.0)
				var on := ph < 0.18 or (ph > 0.3 and ph < 0.48)
				lamp(ctx, x, y - w * 0.15, "#ff3d5a", 70 * S, 1.0 if on else 0.15)
				ctx.save(); ctx.additive = true
				for i in 3:
					var q := fmod(t * 0.7 + i / 3.0, 1.0)
					ctx.alpha = a * (1 - q) * 0.7; ctx.stroke = U.col("#ff5c7a"); ctx.line_width = 2.5 * S
					ctx.begin_path(); ctx.arc(x, y - w * 0.15, 20 * S + q * 120 * S, 0, TAU); ctx.stroke_path()
				ctx.restore()
				ctx.save(); ctx.alpha = a * (1.0 if on else 0.4)
				glowText(ctx, "SOS", x, y - w * 0.62 - 6 * S, int(round(16 * S)), U.col("#ff5c7a"), "#ff3d5a", 12 * S)
				ctx.restore()
		"black":
			# тёмная аура, красные огни, голограмма знака вопроса
			glow(ctx, cx, y, 120 * S, "#6a1030", 0.5 + 0.15 * sin(t * 3))
			flame(ctx, cx, y + 48 * S, 12 * S, 30 * S, 0, "#ff9fb0", "#b0204a", t)
			G.draw(ctx, "p_merchant_s", cx, y, 100 * S)
			lamp(ctx, cx - 34 * S, y - 40 * S, "#ff2a48", 14 * S, 1.0 if sin(t * 7) > 0.3 else 0.15)
			lamp(ctx, cx + 34 * S, y - 40 * S, "#b06bff", 14 * S, 1.0 if sin(t * 7 + 2) > 0.3 else 0.15)
			ctx.save(); ctx.alpha = a * (0.55 + 0.35 * sin(t * 20) * (1.0 if U.random() < 0.9 else 0.0))
			glowText(ctx, "$?", cx - 66 * S, y - 50 * S, int(round(26 * S)), U.col("#ff7ab0"), "#ff2a7a", 16 * S)
			ctx.restore()
			bubble(ctx, cx + 62 * S, y - 66 * S, "Тсс… есть товар", U.clamp((t - 0.8) / 0.2, 0, 1), -1)
		"station":
			# заброшенная станция: тёмная, огни еле живы, вокруг плавают обломки
			var dark := G.tinted("p_merchant", {"sat": -0.9, "dark": 0.45})
			ctx.save(); ctx.translate(cx, y); ctx.rotate(0.3 + sin(t * 0.4) * 0.05)
			if dark: G.draw_canvas(ctx, dark, 0, 0, 140 * S)
			else: G.draw(ctx, "p_merchant", 0, 0, 140 * S)
			ctx.restore()
			lamp(ctx, cx - 30 * S, y - 30 * S, "#3dffa2", 12 * S, 1.0 if U.random() < 0.08 else 0.15)
			lamp(ctx, cx + 40 * S, y + 10 * S, "#ffc83d", 10 * S, 1.0 if U.random() < 0.05 else 0.1)
			for i in 5:
				var q := t * 0.3 + i * 1.3
				var r := (90 + i * 8) * S
				G.draw(ctx, "ast_m1" if i % 2 else "ast_m2", cx + cos(q) * r, y + sin(q) * r * 0.45, (14 + i * 2) * S, q * 2)
		"slot":
			drawSlot(ctx, cx, y, t, a)
		_:
			ctx.fill = Color.WHITE
			ctx.fill_text(sc.ev.ico, cx, y + 80 * S * 0.36, int(round(80 * S)), 1)
	ctx.alpha = 1.0


## игральный автомат: корпус, бегущие огни, три барабана крутятся и встают
func drawSlot(ctx: Ctx, x: float, y: float, t: float, a: float) -> void:
	var S := G.S
	var w := 130 * S
	var h := 150 * S
	var L := x - w / 2
	var T := y - h / 2
	ctx.save()
	ctx.alpha = a
	glow(ctx, x, y, w, "#ff5cf0", 0.3)
	# корпус с вертикальным градиентом: рамка — полигон с цветами вершин, поверх обводка
	var top := T + 18 * S
	ctx.fill_poly(PackedVector2Array([Vector2(L, top), Vector2(L + w, top), Vector2(L + w, T + h), Vector2(L, T + h)]),
		PackedColorArray([U.col("#5a1f7a"), U.col("#5a1f7a"), U.col("#2a0c3d"), U.col("#2a0c3d")]))
	ctx.line_width = 4 * S; ctx.stroke = U.col("#ffc83d")
	ctx.begin_path(); ctx.round_rect(L, top, w, h - 18 * S, 14 * S); ctx.stroke_path()
	# купол с надписью
	ctx.fill = U.col("#ff3d8b"); ctx.begin_path(); ctx.round_rect(L + 14 * S, T, w - 28 * S, 30 * S, 12 * S); ctx.fill_path()
	glowText(ctx, "ДЖЕКПОТ", x, T + 15 * S, int(round(12 * S)), Color.WHITE, "#ffc83d", 8 * S)
	# бегущие огни по периметру
	for i in 14:
		var q := i / 14.0
		var px := L + 6 * S + q * 2 * (w - 12 * S) if q < 0.5 else L + w - 6 * S - (q - 0.5) * 2 * (w - 12 * S)
		var py := T + 26 * S if q < 0.5 else T + h - 6 * S
		lamp(ctx, px, py, "#ffc83d" if i % 2 else "#3de0ff", 10 * S, 1.0 if int(floor(t * 10 + i)) % 3 == 0 else 0.2)
	# окно барабанов
	var wx := L + 14 * S
	var wy := T + 46 * S
	var ww := w - 28 * S
	var wh := 54 * S
	var cw := ww / 3
	ctx.fill = U.col("#f4f0ff"); ctx.begin_path(); ctx.round_rect(wx, wy, ww, wh, 8 * S); ctx.fill_path()
	var SYM := ["7", "★", "$", "♦", "7"]
	var COL := ["#ff3d5a", "#ffc83d", "#3dffa2", "#3de0ff", "#ff3d5a"]
	ctx.save(); ctx.clip_rect(wx, wy, ww, wh)
	var fs := int(round(26 * S))
	for i in 3:
		# барабан i встаёт в момент 1,0 + 0,25·i; встают «почти джекпотом»: 7, 7 и звезда — дразнит сыграть
		var stopT := 1.0 + i * 0.25
		var spin := t < stopT
		var off := fmod(t * 9 + i * 0.37, 1.0) if spin else 0.0
		var base := int(floor(t * 9 + i)) if spin else 0
		for j in range(-1, 2):
			var k := (base + j + 10) % SYM.size()
			var sy := wy + wh / 2 + (j + off) * wh * 0.62
			var kk: int = k if spin else ([0, 0, 1][i] if j == 0 else (i + j + 5) % 4)
			ctx.fill = U.col(COL[kk])
			ctx.alpha = a * (0.75 if spin else 1.0)
			ctx.fill_text(SYM[kk], wx + cw * (i + 0.5), sy + fs * 0.36, fs, 1)
	ctx.restore()
	ctx.stroke = Color(0, 0, 0, 0.35); ctx.line_width = 2 * S
	for i in range(1, 3): ctx.stroke_line(wx + cw * i, wy, wx + cw * i, wy + wh)
	# рычаг
	var pull := sin((t - 0.6) / 0.4 * PI) if t > 0.6 and t < 1.0 else 0.0
	var ky := T + 60 * S - (30 - pull * 50) * S
	ctx.stroke = U.col("#c9d4ea"); ctx.line_width = 5 * S
	ctx.stroke_line(L + w, T + 60 * S, L + w + 16 * S, ky)
	ctx.fill = U.col("#ff3d5a"); ctx.fill_circle(L + w + 16 * S, ky, 7 * S)
	# лоток с кредитами
	ctx.fill = U.col("#1a0828"); ctx.begin_path(); ctx.round_rect(L + 24 * S, T + h - 34 * S, w - 48 * S, 18 * S, 6 * S); ctx.fill_path()
	ctx.restore()


# ════════════════════════════════════════════════════════════
# АКТЁРЫ ПОСЛЕ СЦЕНЫ: контрабандист улетает, пока начинается волна
# ════════════════════════════════════════════════════════════
func leave(kind: String, bought: bool) -> void:
	if kind != "merchant": return
	actors.append({"kind": kind, "t": 0.0, "y0": G.H * 0.33, "say": U.pick(BYE_BUY if bought else BYE), "boom": false})


## время актёров идёт вместе с игрой (Game.update): на паузе и в окнах выбора они замирают
func tick(dt: float) -> void:
	for a in actors: a.t += dt


func drawActors(ctx: Ctx) -> void:
	if actors.is_empty(): return
	if not Game.run or Game.state == "idle" or Game.state == "over":
		actors.clear()
		return
	var S := G.S
	for a: Dictionary in actors:
		if a.kind == "merchant":
			# пауза-реплика, кивок, потом форсаж вверх
			var go := U.clamp((a.t - 0.55) / 0.9, 0, 1)
			var y: float = a.y0 - go * go * (G.H * 0.33 + 220 * S)
			var tilt := sin(a.t * 14) * 0.04 if a.t < 0.55 else 0.0
			ctx.save()
			ctx.alpha = minf(1, 1.6 - a.t)
			merchant(ctx, G.FW / 2, y, 130 * S * (1 - go * 0.25), a.t + 3, {"thrust": 1.2 if go > 0 else 0.2, "cargo": 0.0, "tilt": tilt})
			ctx.restore()
			bubble(ctx, G.FW / 2 + 55 * S, y - 95 * S, a.say, U.clamp(1 - (a.t - 0.9) / 0.25, 0, 1), -1)
			if go > 0 and not a.boom:
				a.boom = true; A.play("teleport", {"rate": 1.4, "vol": 0.4})
	actors = actors.filter(func(a): return a.t < 1.6)
