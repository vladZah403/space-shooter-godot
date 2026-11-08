class_name ShareCard
## Карточка «поделиться» после забега: картинка 720×1080 — фон сектора (шейдер туманности), логотип, корабль
## игрока, счёт, волна, сектор, сложность, медали забега и ссылка на игру. Рисуется в отдельном SubViewport.
## В браузере (айфон) — системное меню «Поделиться» (Web Share API с файлом), если оно недоступно — скачивание;
## на компьютере — файл в папке «Изображения».

const SIZE := Vector2i(720, 1080)
const LINK := "vladzah403.github.io/space-shooter-godot"


## картинка карточки по итогам забега sum (Game.gameOver → summary); host — узел, куда ненадолго встанет вьюпорт
static func render(host: Node, sum: Dictionary) -> Image:
	var vp := SubViewport.new()
	vp.size = SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	var root := Control.new()
	root.size = Vector2(SIZE)
	root.theme = Kit.theme()
	vp.add_child(root)
	_build(root, sum)
	for i in 3: await host.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return img


static func _build(root: Control, sum: Dictionary) -> void:
	var W := float(SIZE.x)
	var H := float(SIZE.y)
	# порядок секторов в забеге перемешан — берём тот, что был на экране
	var sec: Dictionary = Game.sectorDef(int(sum.get("sector", 0)))
	# фон: небо и туманность этого сектора
	var bg := ColorRect.new()
	bg.size = Vector2(W, H)
	var mat: ShaderMaterial = Bg.makeNebula(sec)
	mat.set_shader_parameter("aspect", W / H)
	bg.material = mat
	root.add_child(bg)
	# звёзды и планета сектора в правом верхнем углу (звёзды — с постоянным зерном, карточка не мерцает)
	var pl: Dictionary = Bg.makePlanet(sec)
	var sky := Kit.ctx_view(func(c: Ctx, sz: Vector2, _t: float):
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		c.fill = U.col(sec.get("star", "#ffffff"))
		for i in 190:
			var r := rng.randf_range(1.0, 3.0)
			c.alpha = rng.randf_range(0.2, 0.85)
			c.fill_rect(rng.randf() * sz.x, rng.randf() * sz.y, r, r)
		c.alpha = 0.9
		var ps := 560.0
		c.shader_rect(pl.mat, sz.x - 40 - ps / 2, 200 - ps / 2, ps, ps), Vector2(W, H))
	sky.size = Vector2(W, H)
	root.add_child(sky)
	# корабль и свечение (Ctx)
	var s: Dictionary = M.s
	var ship := Kit.ctx_view(func(c: Ctx, sz: Vector2, t: float):
		c.additive = true
		c.alpha = 0.55
		var gs := sz.x * 0.9
		c.draw_tex(G.soft(sec.neb[1] if sec.neb.size() > 1 else "#3de0ff", 64), sz.x / 2 - gs / 2, sz.y / 2 - gs / 2, gs, gs)
		c.additive = false
		c.alpha = 1.0
		Game.drawShip(c, s.ship.model, s.ship.skin, s.ship.trail, sz.x / 2, sz.y * 0.45, sz.x * 0.46, 0.0, t + 1.0, 1.0), Vector2(380, 380))
	ship.position = Vector2(W / 2 - 190, 250)
	ship.size = Vector2(380, 380)
	root.add_child(ship)
	# рамка-карточка поверх
	var frame := Panel.new()
	frame.size = Vector2(W - 40, H - 40)
	frame.position = Vector2(20, 20)
	var nb := Kit.neo(Color(0, 0, 0, 0), Color(Kit.CYAN, 0.5), Kit.CYAN, 26, 0, 0.6, 2.0)
	nb.notch = true
	nb.sheen = 0.0
	frame.add_theme_stylebox_override("panel", nb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)
	var v := Kit.vbox(4)
	v.position = Vector2(40, 60)
	v.size = Vector2(W - 80, H - 120)
	root.add_child(v)
	# тот же логотип, что в меню, только крупнее
	var logo := Logo.new(1.75)
	logo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(logo)
	v.add_child(Kit.spacer(0, true))
	var rec: bool = sum.get("isRecord", false)
	v.add_child(Kit.label(Lang.t("НОВЫЙ РЕКОРД!") if rec else Lang.t("ИТОГ ЗАБЕГА"), 26, Kit.GOLD if rec else Kit.MUTED, 900, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(Kit.label(U.fmt(sum.get("score", 0)), 96, Color.WHITE, 900, HORIZONTAL_ALIGNMENT_CENTER))
	var d: Dictionary = D.DIFFS.get(sum.get("diff", "normal"), D.DIFFS.normal)
	v.add_child(Kit.label(Lang.t("ВОЛНА %d  ·  %s") % [int(sum.get("wave", 1)), d.name], 30, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(Kit.label(String(sec.name), 24, U.col(sec.neb[0]).lightened(0.35), 800, HORIZONTAL_ALIGNMENT_CENTER))
	var row := Kit.hbox(28)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for it in [["skull", Lang.t("ВРАГИ"), U.fmt(sum.get("kills", 0))], ["crown", Lang.t("БОССЫ"), U.fmt(sum.get("bosses", 0))], ["bolt", Lang.t("КОМБО"), "×%d" % int(sum.get("maxCombo", 0))]]:
		var cell := Kit.vbox(2)
		var ih := Kit.hbox(6)
		ih.alignment = BoxContainer.ALIGNMENT_CENTER
		ih.add_child(Icons.rect(it[0], Kit.GOLD, 22))
		ih.add_child(Kit.label(it[1], 16, Kit.MUTED, 800))
		cell.add_child(ih)
		cell.add_child(Kit.label(it[2], 34, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER))
		row.add_child(cell)
	v.add_child(row)
	# медали, полученные в этом забеге
	var medals: Array = Ui.runEvents.filter(func(a): return a.has("ach")).slice(0, 6)
	if not medals.is_empty():
		var mr := Kit.hbox(10)
		mr.alignment = BoxContainer.ALIGNMENT_CENTER
		for a in medals: mr.add_child(Kit.ach_icon(a.ach, 64))
		v.add_child(Kit.spacer(6))
		v.add_child(mr)
	v.add_child(Kit.spacer(10))
	var pil: Dictionary = D.PILOTS.get(s.get("pilot", "kai"), D.PILOTS.kai)
	var date := Time.get_date_dict_from_system()
	v.add_child(Kit.label(Lang.t("Пилот %s  ·  %02d.%02d.%d") % [pil.name, date.day, date.month, date.year], 20, Kit.MUTED, 700, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(Kit.label(LINK, 20, Kit.CYAN, 800, HORIZONTAL_ALIGNMENT_CENTER))


## отдать картинку: в браузере — «Поделиться» (или скачать), на компьютере — сохранить. Вернёт текст для тоста
static func share(img: Image, score: int) -> String:
	var png := img.save_png_to_buffer()
	var fname := "space-shooter-%d.png" % score
	if OS.has_feature("web"):
		var b64 := Marshalls.raw_to_base64(png)
		var js := """
(function (b64, name, text) {
	try {
		const bin = atob(b64); const u = new Uint8Array(bin.length);
		for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
		const file = new File([u], name, { type: 'image/png' });
		const save = function () {
			const a = document.createElement('a');
			a.href = URL.createObjectURL(file); a.download = name;
			document.body.appendChild(a); a.click(); a.remove();
			setTimeout(function () { URL.revokeObjectURL(a.href); }, 60000);
		};
		if (navigator.canShare && navigator.canShare({ files: [file] })) {
			// без жеста пользователя браузер откажет (NotAllowedError) — тогда просто скачиваем
			navigator.share({ files: [file], title: 'Space Shooter', text: text })
				.catch(function (e) { if (e && e.name === 'NotAllowedError') save(); });
			return 'share';
		}
		save();
		return 'download';
	} catch (e) {}
	return 'fail';
})('%s', '%s', '%s')
""" % [b64, fname, Lang.t("Мой результат в Space Shooter: %s очков! %s") % [U.fmt(score), "https://" + LINK]]
		var how = JavaScriptBridge.eval(js, true)
		if how == "fail":
			JavaScriptBridge.download_buffer(png, fname, "image/png")
		return "" if how == "share" else Lang.t("Картинка скачана")
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if dir == "": dir = OS.get_user_data_dir()
	var path := dir.path_join(fname)
	if img.save_png(path) != OK: return Lang.t("Не удалось сохранить картинку")
	return Lang.t("Сохранено: ") + path
