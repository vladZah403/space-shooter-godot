extends Node2D
## Дымовой тест событий волны (events.gd): каждое событие идёт 15 с в волне с врагами — буря бьёт молниями,
## метеоры летят по линиям, вспышка выжигает пули, мусор и конвой появляются; плюс механики Пояса, Улья
## и Красного гиганта; отрисовка.

const Fx := preload("res://fixture.gd")


func run_event(def: Dictionary, ctx: Ctx) -> String:
	Fx.setup(8)
	var w: Dictionary = Game.wave
	w.done = false
	Events.cur = {"def": def, "wave": w, "t": 0.0, "start": 0.5, "cd": 0.0, "announced": false, "strikes": [], "lanes": [], "meteors": [], "solar": null, "convoys": 0}
	var dt := 1.0 / 60.0
	var strikes := 0
	var meteors := 0
	var solar := 0
	var spawned := {}
	var hp_lost := 0.0
	for f in 900:
		if f % 120 == 0:
			var e := E.spawn("heavy", {"noElite": true})
			e.ai = "none"; e.y = G.H * 0.3
		if f % 40 == 0: Game.ebullet(G.FW / 2, G.H * 0.4, 0, 30, "orb")
		var hp0 := 0.0
		for e: En in Game.enemies: hp0 += e.hp if e.alive else 0.0
		Fx.step(dt)
		Events.update(dt)
		var hp1 := 0.0
		for e: En in Game.enemies: hp1 += e.hp if e.alive else 0.0
		hp_lost += maxf(0, hp0 - hp1)
		var c = Events.cur
		if c == null: break
		strikes = maxi(strikes, c.strikes.size()); meteors = maxi(meteors, c.meteors.size())
		if c.solar != null: solar += 1
		for e: En in Game.enemies:
			if e.alive: spawned[e.type] = true
		if f % 6 == 0:
			ctx.begin(); Events.draw(ctx)
	var ann: bool = Events.cur != null and Events.cur.announced
	Events.finish()
	return "%-8s объявлено %s  молний %d  метеоров %d  кадров вспышки %3d  урон врагам %6.0f  враги %s  очки %d" % [
		def.id, ann, strikes, meteors, solar, hp_lost, spawned.keys(), Game.run.score]


func run_mech(id: String) -> String:
	Fx.setup(3)
	var m := {"id": id, "wave": Game.wave, "k": 3, "cd": 0.6}
	Events.cur = null
	Events.mech = m
	var dt := 1.0 / 60.0
	var spawned := {}
	for f in 900:
		Fx.step(dt)
		Events.update(dt)
		for e: En in Game.enemies:
			if e.alive: spawned[e.type] = spawned.get(e.type, 0) + 1
	return "механика %-10s %s" % [id, spawned]


func _ready() -> void:
	var ctx := Ctx.new(get_canvas_item())
	for def in D.EVENTS: print(run_event(def, ctx))
	for id in ["asteroids", "hive", "lava"]: print(run_mech(id))
	print("SMOKE DONE")
	get_tree().quit()
