extends Node2D
## Дымовой тест сцен узлов (scenes.gd): каждая сцена (лавка, ремонт, тайник, элита, эскорт, сундуки трёх
## ступеней, все события карты) идёт 2,8 с с обновлением и отрисовкой; плюс отлёт торговца и пиксельный сундук.

const Fx := preload("res://fixture.gd")


func play(sc: Dictionary, ctx: Ctx) -> String:
	sc.merge({"t": 0.0, "done": false, "cardT": 0.35, "v": {"cap": "C", "name": "N", "sub": "S"}}, false)
	for f in 168:
		sc.t += 1.0 / 60
		Scenes.update(sc)
		Fx.step(1.0 / 60)
		if f % 4 == 0:
			ctx.begin(); Scenes.draw(ctx, sc)
	var flags: Array = []
	for k in ["card", "done", "landed", "docked", "coins", "gone", "spun", "suck"]:
		if sc.get(k): flags.append(k)
	return "%-22s %s" % [sc.node + ("/" + sc.ev.id if sc.has("ev") and sc.ev else "") + ("/" + sc.tier if sc.has("tier") else ""), flags]


func _ready() -> void:
	Fx.setup()
	var ctx := Ctx.new(get_canvas_item())
	for node in ["shop", "repair", "cache", "elite", "escort"]: print(play({"node": node}, ctx))
	for tier in D.CHEST_ORDER: print(play({"node": "chest", "tier": tier}, ctx))
	for ev in D.MAP_EVENTS: print(play({"node": "event", "ev": ev}, ctx))
	Scenes.leave("merchant", true)
	for f in 120:
		Scenes.tick(1.0 / 60)
		ctx.begin(); Scenes.drawActors(ctx)
	print("отлёт торговца: актёров осталось %d" % Scenes.actors.size())
	var c := G.chest("gold")
	print("сундук: корпус %s, крышка %s, значок %s" % [c.body.get_size(), c.lid.get_size(), c.icon.get_size()])
	print("SMOKE DONE")
	get_tree().quit()
