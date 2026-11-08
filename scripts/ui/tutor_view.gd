class_name TutorView
extends Control
## Обучение в первом забеге (Godot): подсказки по шагам — вести пальцем, стрельба сама, кристаллы опыта,
## выбор улучшения, бомба. Касания проходят насквозь — игре не мешает; шаг ждёт действия игрока или через
## несколько секунд идёт дальше сам. Пройдено — M.s.tutor = true (повторить: Настройки → «Обучение»).
## Опытным игрокам (уже есть сыгранные забеги) не показывается.

var step := ""
var t := 0.0
var _moved := 0.0
var _last := Vector2.ZERO
var _kills0 := 0
var _bombs0 := 0
var _a := 0.0              # прозрачность подсказки (плавно)
var box: PanelContainer
var txt: Label


func _ready() -> void:
	Kit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	box = Kit.panel(12, Color(Kit.PANEL_SOLID, 0.93), Color(Kit.CYAN, 0.7), 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt = Kit.para("", 15, Kit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(txt)
	add_child(box)
	box.modulate.a = 0.0


## Ui.startRun: первый забег новичка — начинаем с первого шага
func start() -> void:
	step = ""
	if M.s.get("tutor", false): return
	if not M.s.has("tutor") and int(M.s.stats.get("games", 0)) > 0:
		M.s.tutor = true   # уже играл до обучения — не мучаем
		M.soon()
		return
	_go("move")


func stop() -> void:
	step = ""


func _go(s: String) -> void:
	step = s
	t = 0.0
	var p = Game.player
	if p: _last = Vector2(p.x, p.y)
	_moved = 0.0
	_kills0 = int(Game.run.get("kills", 0)) if Game.run else 0
	_bombs0 = int(p.bombs) if p else 0
	match s:
		"move": txt.text = Lang.t("Ведите пальцем по экрану — корабль летит за пальцем")
		"shoot": txt.text = Lang.t("Стрельба автоматическая. Держитесь под врагами и уворачивайтесь от пуль")
		"xp": txt.text = Lang.t("Собирайте зелёные кристаллы — за новый уровень дают улучшение")
		"perk": txt.text = Lang.t("Выберите улучшение — оно действует до конца забега")
		"bomb": txt.text = Lang.t("Бомба уничтожает всё вокруг: кнопка справа внизу или двойной тап")
		"done":
			step = ""
			M.s.tutor = true
			M.soon()
			Ui.toast({"ico": "🎓", "title": Lang.t("ОБУЧЕНИЕ ПРОЙДЕНО"), "text": Lang.t("Удачи, пилот! Повторить обучение можно в настройках"), "info": true})


func _process(dt: float) -> void:
	# выбор улучшения открылся, пока ждали кристаллы (или раньше), — сразу подсказка про выбор
	if (step == "xp" or step == "shoot") and Game.state == "perk" and Game.run and int(Game.run.get("level", 1)) >= 2: _go("perk")
	var on := step != "" and Ui.cur == "game" and Game.run and (Game.state == "play" or (step == "perk" and Game.state == "perk"))
	_a = move_toward(_a, 1.0 if on else 0.0, dt * 4.0)
	box.modulate.a = _a
	box.visible = _a > 0.01
	if step != "": _layout()
	queue_redraw()
	if not on: return
	t += dt
	var p = Game.player
	match step:
		"move":
			if p:
				_moved += Vector2(p.x, p.y).distance_to(_last)
				_last = Vector2(p.x, p.y)
			if _moved > 260.0 or t > 9.0: _go("shoot")
		"shoot":
			if int(Game.run.kills) - _kills0 >= 3 or t > 10.0: _go("xp")
		"xp":
			if Game.state == "perk": _go("perk")
			elif t > 25.0: _go("bomb")
		"perk":
			if Game.state == "play": _go("bomb")
		"bomb":
			if p == null or p.bombs <= 0 and _bombs0 <= 0: _go("done")
			elif p.bombs < _bombs0 or t > 9.0: _go("done")


func _layout() -> void:
	var w := minf(size.x - 32.0, 340.0)
	txt.custom_minimum_size.x = w - 24.0
	box.size = Vector2(w, 0)
	box.size = box.get_combined_minimum_size()
	var y := size.y * 0.6
	if step == "perk": y = Hud.safe_top() + 64.0
	box.position = Vector2((size.x - box.size.x) / 2.0, y)


## указатели: палец под кораблём, кольцо на кристалле, кольцо на кнопке бомбы
func _draw() -> void:
	if _a <= 0.01 or step == "": return
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 5.0)
	var col := Color(Kit.CYAN, _a)
	match step:
		"move":
			var p = Game.player
			if p == null: return
			var sp := Game.toScreen(p.x, p.y)
			var k := sin(Time.get_ticks_msec() / 1000.0 * 2.2)
			var f := sp + Vector2(k * 70.0, 70.0)
			draw_circle(f, 16.0, Color(1, 1, 1, 0.18 * _a))
			draw_arc(f, 16.0, 0, TAU, 32, Color(1, 1, 1, 0.8 * _a), 2.0, true)
			draw_circle(f, 6.0, Color(1, 1, 1, 0.9 * _a))
			for s in [-1.0, 1.0]:
				var tip := sp + Vector2(s * 118.0, 70.0)
				draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-s * 14.0, -9.0), tip + Vector2(-s * 14.0, 9.0)]), Color(col, 0.5 + 0.4 * pulse))
		"xp":
			var best = null
			var bd := 1e9
			var p = Game.player
			for it: Pk in Game.pickups:
				if it.kind != "xp" or it.dead: continue
				var d := Vector2(it.x, it.y).distance_squared_to(Vector2(p.x, p.y)) if p else 0.0
				if d < bd:
					bd = d
					best = it
			if best:
				var sp := Game.toScreen(best.x, best.y)
				draw_arc(sp, 18.0 + pulse * 8.0, 0, TAU, 40, Color(0.24, 1.0, 0.64, (0.9 - pulse * 0.5) * _a), 3.0, true)
		"bomb":
			var hud = Ui.hud
			if hud == null or hud.get("_bomb") == null: return
			var b: Control = hud._bomb
			var r := b.get_global_rect()
			var c := get_global_transform().affine_inverse() * r.get_center()
			draw_arc(c, r.size.x * 0.6 + pulse * 10.0, 0, TAU, 48, Color(1.0, 0.78, 0.24, (0.95 - pulse * 0.5) * _a), 3.0, true)
