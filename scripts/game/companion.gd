extends Node
## Дрон-напарник (автозагрузка Comp) — перенос companion.js.
##  Один дрон в бою (выбор и прокачка — вкладка «Дроны» в Ангаре): Стрелок, Санитар, Сборщик, Страж,
##  Подрывник. Уровень 1–5 усиливает его умение. Данные — D.COMPANIONS, сохранение — M.s.comp.

var d = null   # { id, lv, x, y, cd, a, flash }


## на старте забега — выбранный в Ангаре дрон
func start() -> void:
	var s = M.s.get("comp")
	var id: String = s.get("sel", "") if s else ""
	var p: Pl = Game.player
	if id != "" and D.COMPANIONS.has(id) and id in s.owned:
		d = {"id": id, "lv": maxi(1, int(s.lv.get(id, 1))), "x": p.x, "y": p.y + p.w, "cd": 2.0, "a": 0.0, "flash": 0.0}
	else:
		d = null


func has(id: String) -> bool:
	return d != null and d.id == id


func lv() -> int:
	return d.lv if d != null else 0


func update(dt: float) -> void:
	var p: Pl = Game.player
	var S := G.S
	if d == null or p == null: return
	var def: Dictionary = D.COMPANIONS[d.id]
	var k: int = d.lv - 1
	var guard: bool = d.id == "guard"
	d.a += dt * (3.0 if guard else 1.4)
	# Страж кружит вокруг корабля, остальные держатся слева-сзади
	var tx: float = p.x + cos(d.a) * p.w * 0.95 if guard else p.x - p.w * 0.95
	var ty: float = p.y + sin(d.a) * p.w * 0.75 if guard else p.y + p.w * 0.35 + sin(d.a * 2) * 5 * S
	d.x = U.damp(d.x, tx, 20 if guard else 7, dt)
	d.y = U.damp(d.y, ty, 20 if guard else 7, dt)
	d.flash -= dt
	if not p.alive or Game.state != "play": return
	d.cd -= dt
	if d.id == "gunner" and d.cd <= 0:
		var tgt: En = null
		var bd := 460 * S
		for e: En in Game.enemies:
			if not e.alive or not e.hittable or e.y > d.y or Foes.hidden(e): continue
			var dd := Vector2(e.x - d.x, e.y - d.y).length()
			if dd < bd:
				bd = dd; tgt = e
		if tgt:
			d.cd = def.cd[k] / Game.rateMul()
			var a := atan2(tgt.y - d.y, tgt.x - d.x)
			var sp := 900 * S
			Game.spawnShot({"x": d.x, "y": d.y, "vx": cos(a) * sp, "vy": sin(a) * sp, "dmg": def.dmg[k] * Game.dmgMul(), "r": 4 * S, "kind": "drone",
				"sprite": "pb_bolt_s", "w": 11 * S, "wid": "comp", "life": 1.2})
			d.flash = 0.06
	elif d.id == "medic" and d.cd <= 0:
		d.cd = def.cd[k]
		if p.lives < p.maxLives: Game.heal(1, "💚 САНИТАР")
		elif not p.shield:
			p.shield = true; Game.shieldFx()
		FX.lightning(d.x, d.y, p.x, p.y, "#5cff9d", 2 * S, 0.3)
	elif d.id == "bomber" and d.cd <= 0:
		var tgt: En = null
		var bh := -1.0
		for e: En in Game.enemies:
			if e.alive and e.hittable and e.y > 30 * S and not e.def.prop and e.hp > bh:
				bh = e.hp; tgt = e
		if tgt:
			d.cd = def.cd[k]
			var dmg: float = def.dmg[k] * Game.dmgMul() * (1 + Game.wave.n * 0.05)
			Game.spawnShot({"x": d.x, "y": d.y, "vx": 0.0, "vy": -200 * S, "dmg": dmg, "aoe": dmg, "aoeR": 70 * S,
				"r": 8 * S, "kind": "rocket", "sprite": "fx_rocket2", "w": 15 * S, "homing": 5.0, "acc": 700 * S, "maxSpd": 520 * S, "wid": "comp", "life": 3.0})
			A.play("rocket", {"rate": 1.3, "vol": 0.5})


## Страж ловит вражеские пули (из Game.updateEBullets); перезарядка между блоками
func block(b: Eb) -> bool:
	if d == null or d.id != "guard" or d.cd > 0 or Vector2(b.x - d.x, b.y - d.y).length() > 16 * G.S + b.r: return false
	d.cd = D.COMPANIONS.guard.cd[d.lv - 1]
	d.flash = 0.15
	FX.ring(d.x, d.y, 4 * G.S, 22 * G.S, "#7fd8ff", 0.25, 3)
	A.play("shieldHit", {"vol": 0.35, "rate": 1.6})
	return true


## Сборщик тянет к кораблю всё с экрана (кредиты, кристаллы, энергию; с 3-го уровня — и бонусы)
func pulls(it: Pk) -> bool:
	return has("collector") and ((it.kind != "pu" and it.kind != "crate") or d.lv >= 3)


func coinMul() -> float:
	return 1 + d.lv * 0.05 if has("collector") else 1.0


func draw(ctx: Ctx) -> void:
	var S := G.S
	if d == null or Game.player == null or not Game.player.alive: return
	var def: Dictionary = D.COMPANIONS[d.id]
	var w := 24 * S
	ctx.additive = true
	ctx.alpha = 0.45 + (0.4 if d.flash > 0 else 0.0)
	ctx.draw_tex(G.soft(def.color, 64), d.x - w, d.y - w, w * 2, w * 2)
	ctx.additive = false
	ctx.alpha = 1.0
	if def.hue != null: G.draw_canvas(ctx, G.tinted(def.sprite, {"hue": def.hue}), d.x, d.y, w, def.rot)
	else: G.draw(ctx, def.sprite, d.x, d.y, w, def.rot)
	# готовность умения — тонкая дуга
	if not def.cd.is_empty() and d.id != "gunner":
		var k := 1 - U.clamp(d.cd / def.cd[d.lv - 1], 0, 1)
		ctx.alpha = 0.7; ctx.stroke = U.col(def.color); ctx.line_width = 1.5 * S
		ctx.begin_path(); ctx.arc(d.x, d.y, w * 0.7, -PI / 2, -PI / 2 + TAU * k); ctx.stroke_path()
		ctx.alpha = 1.0
