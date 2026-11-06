extends Node2D
## Дымовой тест боссов: каждый из 13 боссов выходит, проходит три фазы под постоянным уроном и погибает.
## Проверяет, что атаки, движение, смена фаз, подстройка прочности и отрисовка работают без ошибок.

const Fx := preload("res://fixture.gd")


func setup() -> void:
	Fx.setup(5)


func fight(i: int, phase_sec: float, ctx: Ctx) -> String:
	Game.enemies.clear(); Game.ebullets.clear(); Game.timers.clear(); Game.boss = null
	Game.wave.n = (i + 1) * 5
	B.spawnBoss((i + 1) * 5)
	var b: En = Game.boss
	if b == null: return "НЕ ПОЯВИЛСЯ"
	var hp0 := b.maxHp
	var dt := 1.0 / 60.0
	var shots := 0
	var lasers := 0
	var phases := {}
	var minions := 0
	var reborn := false
	var tm := 0.0
	var killed := false
	while tm < 120.0:
		tm += dt; Game.t += dt
		E.updateAll(dt, dt)
		Game.runTimers(dt)
		shots += Game.ebullets.size(); Game.ebullets.clear()
		lasers += Game.ov.lasers.size() + Game.ov.beams.size(); Game.ov.lasers.clear(); Game.ov.beams.clear()
		for e in Game.enemies:
			if e.alive and not e.boss: minions += 1; e.alive = false
		Game.enemies = Game.enemies.filter(func(e): return e.alive)
		if int(tm / dt) % 6 == 0:
			ctx.begin(); E.drawAll(ctx)
		if not b.alive:
			killed = true
			break
		phases[int(b.phase)] = true
		if b.reborn: reborn = true
		if not b.entering and b.trans <= 0:
			var dmg := B.bossCap(b, hp0 / 3.0 / phase_sec * dt)
			b.hp -= dmg
			if b.hp <= 0: E.kill(b, "test")
	# останки догорают
	for k in 120: E.updateAll(dt, dt)
	return "%-12s %s за %5.1f с  фазы %s%s  пуль %5d  лучей %3d  миньонов %3d  прочн. ×%.2f  bossDps %.0f" % [
		b.bdef.id, "убит" if killed else "ЖИВ ", tm, phases.keys(), " +возрождение" if reborn else "", shots, lasers, minions,
		b.maxHp / hp0, Game.run.bossDps]


func _ready() -> void:
	setup()
	var ctx := Ctx.new(get_canvas_item())
	ctx.font = ThemeDB.fallback_font
	print("— обычный урон (фаза ≈ 8 с) —")
	for i in D.BOSSES.size(): print(fight(i, 8.0, ctx))
	print("— сильная сборка (фаза ≈ 1 с): прочность должна подрасти —")
	Game.run.bossDps = 0.0
	for i in 3: print(fight(i, 1.0, ctx))
	print("SMOKE DONE")
	get_tree().quit()
