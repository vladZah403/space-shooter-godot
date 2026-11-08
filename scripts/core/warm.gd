class_name Warm
## Godot: прогрев при запуске. Браузер (особенно Safari на айфоне) собирает шейдер в момент первого рисования —
## первый взрыв, первый Невидимка или «Затмение» давали рывок в бою. Здесь каждый материал и надписи HUD
## рисуются один раз в крошечном невидимом вьюпорте, пока идёт заставка или открыто меню.

static func run(host: Node) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	var mats: Array = [Bg.makeNebula(D.SECTORS[0]), Bg.makePlanet(D.SECTORS[0]).mat, E._burnMat(), E.cloakMat(), Game.darkMat(),
		Post.mat_full, Post.mat_lite]
	for m in mats:
		var r := ColorRect.new()
		r.size = Vector2(8, 8)
		r.material = m
		vp.add_child(r)
	# надписи HUD: те же шрифты, кегли и обводки, что в бою — глифы растрируются заранее
	var n := Node2D.new()
	vp.add_child(n)
	var ctx := Ctx.new(n.get_canvas_item())
	ctx.begin()
	var txt := "0123456789,. ×+−%:/ WAVEBOSPHCMRKLIGDTNXYUF ВОЛНАБСФЗКМИРТЕДУЖПЫ"
	for w in [700, 800, 900]:
		ctx.font = Kit.font(w)
		for sz in [10, 11, 12, 13, 14, 24, 26]:
			for ol in [0, 3, 4]:
				ctx.fill = Color.WHITE
				ctx.fill_text(txt, 0, 20, sz, 0, ol)
	ctx.additive = true
	ctx.fill_circle(10, 10, 4)
	ctx.additive = false
	for i in 3: await host.get_tree().process_frame
	ctx.free_items()
	vp.queue_free()
