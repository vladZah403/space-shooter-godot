extends Node
## Иконка игры и картинка заставки загрузки — рисуются из графики игры (запуск с окном):
##   Godot_console.exe --path . res://tools/check/make_brand.tscn
## → icon.png (1024×1024: корабль на туманности, для экрана «Домой», PWA и окна) и assets/splash.png (логотип на
## прозрачном фоне — экран загрузки, application/boot_splash/image). Перезапускать при смене логотипа/корабля.

func _ready() -> void:
	await get_tree().process_frame
	var icon: Image = await _render(Vector2i(1024, 1024), false, func(root: Control):
		var bg := ColorRect.new()
		bg.size = Vector2(1024, 1024)
		var mat: ShaderMaterial = Bg.makeNebula(D.SECTORS[0])
		mat.set_shader_parameter("aspect", 1.0)
		mat.set_shader_parameter("seed", 7.0)
		bg.material = mat
		root.add_child(bg)
		var ship := Kit.ctx_view(func(c: Ctx, sz: Vector2, _t: float):
			# звёзды
			var rng := RandomNumberGenerator.new()
			rng.seed = 3
			c.fill = Color.WHITE
			for i in 110:
				var r := rng.randf_range(2.0, 5.0)
				c.alpha = rng.randf_range(0.25, 0.8)
				c.fill_rect(rng.randf() * sz.x, rng.randf() * sz.y, r, r)
			# свечение за кораблём и сам корабль, крупно, с двигателями
			c.additive = true
			c.alpha = 0.75
			c.draw_tex(G.soft("#3de0ff", 64), sz.x / 2 - 420, sz.y / 2 - 420, 840, 840)
			c.alpha = 0.5
			c.draw_tex(G.soft("#6b5bff", 64), sz.x / 2 - 520, sz.y / 2 - 360, 1040, 1040)
			c.additive = false
			c.alpha = 1.0
			Game.drawShip(c, "ship1", "default", "ice", sz.x / 2, sz.y * 0.47, sz.x * 0.56, 0.0, 1.3, 1.4), Vector2(1024, 1024))
		ship.size = Vector2(1024, 1024)
		root.add_child(ship)
		# сам корабль — поверх, чётко: кадр из исходного PNG без сжатия, увеличен по пикселям (без размытия)
		var f: Array = Game.drawLook("ship1", "default", "ice").f
		var src := Image.load_from_file(ProjectSettings.globalize_path(["res://assets/sprites.png", "res://assets/sprites2.png"][int(f[5])]))
		var fr := src.get_region(Rect2i(int(f[0]), int(f[1]), int(f[2]), int(f[3])))
		var w := 1024.0 * 0.56
		var h: float = w * float(f[3]) / float(f[2])
		var k := maxi(1, int(ceil(w / float(f[2]))))
		fr.resize(int(f[2]) * k, int(f[3]) * k, Image.INTERPOLATE_NEAREST)
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(fr)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.position = Vector2(512 - w / 2, 1024 * 0.47 - h / 2)
		tr.size = Vector2(w, h)
		root.add_child(tr))
	icon.convert(Image.FORMAT_RGB8)
	icon.save_png("res://icon.png")
	var splash: Image = await _render(Vector2i(760, 300), true, func(root: Control):
		var logo := Logo.new(2.1)
		logo.size = Vector2(760, 300)
		logo.position = Vector2(0, 16)
		root.add_child(logo))
	splash.save_png("res://assets/splash.png")
	print("BRAND DONE: icon ", icon.get_size(), ", splash ", splash.get_size())
	get_tree().quit()


func _render(sz: Vector2i, transparent: bool, build: Callable) -> Image:
	var vp := SubViewport.new()
	vp.size = sz
	vp.transparent_bg = transparent
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Control.new()
	root.size = Vector2(sz)
	root.theme = Kit.theme()
	vp.add_child(root)
	build.call(root)
	for i in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img
