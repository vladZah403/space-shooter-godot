extends Node2D
## Главная сцена: игровой цикл (Game.frame + Game.draw через Ctx), ввод пальцем/мышью/клавишами, смена размера,
## пауза при сворачивании. Интерфейс строит Ui на своём слое поверх (scripts/ui/ui.gd).
## Ключи запуска: «-- --autoplay» — бот-тестировщик играет сам (бессмертный корабль, выбирает первое),
## «--shots=ПАПКА» — снимки экрана в моменты SHOT_AT (с), «--seconds=N» — выйти через N секунд игры.

const SHOT_AT := [2.5, 8.0, 20.0, 40.0, 70.0, 100.0, 130.0, 160.0, 200.0]
const KEYS := {
	KEY_LEFT: "ArrowLeft", KEY_RIGHT: "ArrowRight", KEY_UP: "ArrowUp", KEY_DOWN: "ArrowDown",
	KEY_A: "KeyA", KEY_D: "KeyD", KEY_W: "KeyW", KEY_S: "KeyS", KEY_B: "KeyB", KEY_Q: "KeyQ", KEY_E: "KeyE", KEY_P: "KeyP",
	KEY_SPACE: "Space", KEY_ENTER: "Enter", KEY_ESCAPE: "Escape",
	KEY_1: "Digit1", KEY_2: "Digit2", KEY_3: "Digit3",
}

var ctx: Ctx
var autoplay := false
var shots_dir := ""
var max_seconds := 0.0
var _clock := 0.0
var _shot_i := 0
var _bot_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	ctx = Ctx.new(get_canvas_item())
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay": autoplay = true
		elif a.begins_with("--shots="): shots_dir = a.substr(8)
		elif a.begins_with("--seconds="): max_seconds = float(a.substr(10))
	get_viewport().size_changed.connect(_on_resize)
	_on_resize()
	Ui.build(self)
	if autoplay:
		print("[bot] автоигра")
		M.s.seenIntro = true
		Ui.startRun("normal")


func _on_resize() -> void:
	G.resize()
	Bg.resize()
	if Game.player: Game.clampPlayer()


func _process(delta: float) -> void:
	var rdt := delta
	if rdt > 0.25: rdt = 0.016   # после сворачивания — без скачка
	if autoplay: _bot(rdt)
	Game.frame(rdt)
	ctx.begin()
	Game.draw(ctx)
	Ui.frame(rdt)
	Main.measure(rdt)
	_clock += rdt
	if shots_dir != "" and _shot_i < SHOT_AT.size() and _clock >= SHOT_AT[_shot_i]:
		_shot_i += 1
		_shot()
	if max_seconds > 0 and _clock >= max_seconds:
		print("[bot] %.0f с: состояние %s, волна %s, убито %d, очки %d" % [_clock, Game.state, Game.wave.n if Game.wave else "-", Game.run.get("kills", 0) if Game.run else 0, Game.run.get("score", 0) if Game.run else 0])
		get_tree().quit()


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
func _bot(dt: float) -> void:
	_bot_t += dt
	var p: Pl = Game.player
	if p:
		p.inv = maxf(p.inv, 5.0)
		if Game.state == "play": p.x = G.FW / 2 + sin(_bot_t * 0.8) * G.FW * 0.35
	match Game.state:
		"tip": Game.closeTip()
		"cutscene": if fmod(_bot_t, 3.0) < dt: Game.skipScene()
		"perk": Ui.botPick()
		"over":
			if fmod(_bot_t, 4.0) < dt: Ui.startRun("normal")
