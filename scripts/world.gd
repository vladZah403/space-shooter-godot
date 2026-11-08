extends Node2D
## Главная сцена: игровой цикл (Game.frame + Game.draw через Ctx), ввод пальцем/мышью/клавишами, смена размера,
## пауза при сворачивании. Интерфейс строит Ui на своём слое поверх (scripts/ui/ui.gd).
## Ключи запуска: «-- --autoplay» — бот-тестировщик играет сам (бессмертный корабль, выбирает первое),
## «--shots=ПАПКА» — снимки экрана в моменты SHOT_AT (с), «--seconds=N» — выйти через N секунд игры,
## «--prof» — раз в 10 с печатать среднее время кадра по частям (логика, отрисовка, интерфейс), мс.

const SHOT_AT := [2.5, 8.0, 20.0, 40.0, 70.0, 100.0, 130.0, 160.0, 200.0]
const KEYS := {
	KEY_LEFT: "ArrowLeft", KEY_RIGHT: "ArrowRight", KEY_UP: "ArrowUp", KEY_DOWN: "ArrowDown",
	KEY_A: "KeyA", KEY_D: "KeyD", KEY_W: "KeyW", KEY_S: "KeyS", KEY_B: "KeyB", KEY_Q: "KeyQ", KEY_E: "KeyE", KEY_P: "KeyP",
	KEY_SPACE: "Space", KEY_ENTER: "Enter", KEY_ESCAPE: "Escape",
	KEY_1: "Digit1", KEY_2: "Digit2", KEY_3: "Digit3",
}

var ctx: Ctx
## Godot: мир (фон, враги, пули, частицы) рисуется в свой буфер wvp и выводится на экран картинкой wview.
## Эффекты экрана (Post: волны, воронки, пузыри щитов, цвет) — шейдер на этой картинке: копировать экран не нужно,
## а именно копия экрана каждый кадр вешала Safari на айфоне
var wvp: SubViewport
var wcanvas: Node2D
var wview: TextureRect
var autoplay := false
var shots_dir := ""
var max_seconds := 0.0
var _clock := 0.0
var _shot_i := 0
var _bot_t := 0.0
var prof := false
## бот: «--mode=bossrush|survival», «--diff=easy|hard|…», «--challenge» (испытание дня), «--mortal» — корабль не бессмертный
var bot_mode := "normal"
var bot_diff := "normal"
var bot_challenge := false
var bot_mortal := false
var _prof := {"frame": 0.0, "draw": 0.0, "ui": 0.0, "n": 0, "max": 0.0, "t": 0.0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	wvp = SubViewport.new()
	wvp.disable_3d = true
	wvp.transparent_bg = false
	wvp.gui_disable_input = true
	wvp.size_2d_override_stretch = true   # рисуем в точках вёрстки, буфер — в пикселях экрана (шрифты чёткие)
	wvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(wvp)
	wcanvas = Node2D.new()
	wvp.add_child(wcanvas)
	wview = TextureRect.new()
	wview.texture = wvp.get_texture()
	wview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wview.stretch_mode = TextureRect.STRETCH_SCALE
	wview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wview)
	Post.world_view = wview
	ctx = Ctx.new(wcanvas.get_canvas_item())
	ctx.font = Kit.font(700)   # надписи на поле (реплики, «КОМБО», числа урона) — тем же шрифтом с кириллицей
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay": autoplay = true
		elif a.begins_with("--shots="): shots_dir = a.substr(8)
		elif a.begins_with("--seconds="): max_seconds = float(a.substr(10))
		elif a.begins_with("--mode="): bot_mode = a.substr(7)
		elif a.begins_with("--diff="): bot_diff = a.substr(7)
		elif a == "--challenge": bot_challenge = true
		elif a == "--mortal": bot_mortal = true
		elif a == "--prof":
			prof = true
			Ctx.stats_on = true
	if prof: print("[prof] ядер %d, качество Q%d (авто %s), телефон %s, свечение %s" % [OS.get_processor_count(), Main.quality, Main.autoQ, Main.is_mobile(), Main.bloom_ok()])
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	Vfx.attach(wcanvas)
	Ui.build(self)
	(func(): Warm.run(self)).call_deferred()   # шейдеры и глифы — заранее, а не в бою
	# заставка при запуске (её можно выключить в настройках)
	if M.s.settings.get("intro", true) and not autoplay: Intro.play(func(): pass)
	if autoplay:
		print("[bot] автоигра")
		M.s.seenIntro = true
		_bot_start()


func _on_resize() -> void:
	G.resize()
	var px := get_tree().root.size
	wvp.size = Vector2i(maxi(px.x, 1), maxi(px.y, 1))
	wvp.size_2d_override = Vector2i(maxi(roundi(G.W), 1), maxi(roundi(G.H), 1))
	wview.position = Vector2.ZERO
	wview.size = Vector2(G.W, G.H)
	Bg.resize()
	if Game.player: Game.clampPlayer()


func _process(delta: float) -> void:
	var rdt := delta
	if rdt > 0.25: rdt = 0.016   # после сворачивания — без скачка
	if autoplay: _bot(rdt)
	var t0 := Time.get_ticks_usec()
	Game.frame(rdt)
	var t1 := Time.get_ticks_usec()
	ctx.begin()
	Game.draw(ctx)
	Post.frame(rdt)
	Vfx.frame(rdt)
	var t2 := Time.get_ticks_usec()
	Ui.frame(rdt)
	if prof: _profile(t0, t1, t2, Time.get_ticks_usec(), rdt)
	Main.measure(rdt)
	_clock += rdt
	if shots_dir != "" and _shot_i < SHOT_AT.size() and _clock >= SHOT_AT[_shot_i]:
		_shot_i += 1
		_shot()
	if max_seconds > 0 and _clock >= max_seconds:
		print("[bot] %.0f с: состояние %s, волна %s, убито %d, очки %d" % [_clock, Game.state, Game.wave.n if Game.wave else "-", Game.run.get("kills", 0) if Game.run else 0, Game.run.get("score", 0) if Game.run else 0])
		get_tree().quit()


func _profile(t0: int, t1: int, t2: int, t3: int, dt: float) -> void:
	var p := _prof
	p.frame += t1 - t0; p.draw += t2 - t1; p.ui += t3 - t2; p.n += 1
	p.max = maxf(p.max, t3 - t0)
	if t3 - t0 > 12000: print("[prof] рывок %.1f мс: логика %.1f, отрисовка %.1f, интерфейс %.1f (%s, %.1f с)" % [(t3 - t0) / 1000.0, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, Game.state, _clock])
	p.t += dt
	if p.t < 10.0: return
	var n: float = p.n * 1000.0
	print("[prof] %.0f FPS (Q%d, %s) · логика %.2f, отрисовка %.2f, интерфейс %.2f, худший кадр %.1f мс · многоугольников %.0f/кадр · врагов %d, пуль %d/%d, частиц %d, %s" % [
		p.n / maxf(p.t, 0.001), Main.quality, str(get_tree().root.size), p.frame / n, p.draw / n, p.ui / n, p.max / 1000.0, (Ctx.stat_poly - p.get("poly0", 0)) / float(p.n), Game.enemies.size(), Game.bullets.size(), Game.ebullets.size(), FX.parts.size(), Game.state])
	print("[prof] виды за 10 с: ", Ctx.stat_kind)
	Ctx.stat_kind.clear()
	_prof = {"frame": 0.0, "draw": 0.0, "ui": 0.0, "n": 0, "max": 0.0, "t": 0.0, "poly0": Ctx.stat_poly}


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var path := shots_dir.path_join("shot_%02d.png" % _shot_i)
	img.save_png(path)
	print("[bot] снимок ", path)


# ── ввод: касания (мышь эмулирует касание — pointing/emulate_touch_from_mouse) ──
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			Game.onPointerDown(e.index, e.position)
		else:
			Game.onPointerUp(e.index, e.position)
	elif e is InputEventScreenDrag:
		Game.onPointerMove(e.index, e.position)
	elif e is InputEventKey and not e.echo:
		var code: String = KEYS.get(e.keycode, "")
		if code == "": return
		if e.pressed and Game.state == "tip" and (code == "Escape" or code == "Enter" or code == "Space"):
			Game.closeTip()
			return
		if e.pressed and (code == "Escape" or code == "KeyP") and (Game.inRun() or Game.state == "pause"):
			if Game.state == "pause": Game.resume()
			else: Game.pause()
			return
		if e.pressed and code == "Escape":
			Ui.back()
			return
		Game.onKey(code, e.pressed)


## сворачивание на телефоне и потеря фокуса окна — пауза (как visibilitychange/blur в JS)
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if Game.inRun() and not autoplay: Game.pause()
		if what == NOTIFICATION_APPLICATION_PAUSED: A.suspend()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		A.resume()


# ════════════════════════════════════════════════════════════
# БОТ-ТЕСТИРОВЩИК
# ════════════════════════════════════════════════════════════
func _bot_start() -> void:
	if bot_challenge: Ui.startRun(M.challenge().get("diff", "normal"), {"challenge": M.challenge()})
	else: Ui.startRun(bot_diff, {"mode": bot_mode})


func _bot(dt: float) -> void:
	_bot_t += dt
	var p: Pl = Game.player
	if p:
		if not bot_mortal: p.inv = maxf(p.inv, 5.0)
		if Game.state == "play": p.x = G.FW / 2 + sin(_bot_t * 0.8) * G.FW * 0.35
	match Game.state:
		"tip": Game.closeTip()
		"cutscene": if fmod(_bot_t, 3.0) < dt: Game.skipScene()
		"perk": Ui.botPick()
		# смертный бот: через раз воскресает за кредиты (если хватает), иначе — конец забега
		"revive":
			if fmod(_bot_t, 2.0) < dt:
				if int(_bot_t) % 4 >= 2 or not Game.revive():
					Ui.revive.close()
					Game.gameOver()
		"over":
			if fmod(_bot_t, 4.0) < dt:
				print("[bot] забег окончен: волна %s, очки %d" % [Game.wave.n if Game.wave else "-", Game.run.get("score", 0) if Game.run else 0])
				_bot_start()
