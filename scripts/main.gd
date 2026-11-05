extends Node2D
## Главная сцена: волны врагов, босс каждые 5 волн, очки, жизни, пауза, итоги.
## Запуск с ключом «-- --autoplay» включает бота-тестировщика (бессмертный корабль сам летает,
## после итогов игра начинается заново, в консоль пишутся волны и бои с боссом).

const Starfield := preload("res://scripts/starfield.gd")
const START_LIVES := 4
const BOSS_EVERY := 5
const SENS := 1.25            # чувствительность ведения пальцем
const BOSS_HP_K := 0.6        # прототип: без улучшений забега босс мягче, чем в JS-версии

var player: Player
var boss: Boss
var state := "menu"           # menu | play | over
var wave := 0
var score := 0
var lives := START_LIVES
var autoplay := false

var _world: Node2D
var _enemies: Node2D
var _pshots: Node2D
var _eshots: Node2D
var _fx: Node2D
var _hud: Hud
var _stars: Node2D
var _queue: Array[String] = []
var _spawn_cd := 0.0
var _next_wave := -1.0
var _shake := 0.0
var _bot_t := 0.0
var _clock := 0.0
var _shot_dir := ""             # «-- --shots=ПАПКА» — снимки экрана для проверки (в моменты _shot_at, с)
var _shot_at: Array = [3.0, 12.0, 30.0, 55.0, 62.0, 75.0]


func _ready() -> void:
	randomize()
	autoplay = "--autoplay" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shot_dir = a.substr(8)
	# главная сцена слушает клавиши и на паузе (Esc снимает паузу), а мир и фон замирают
	process_mode = Node.PROCESS_MODE_ALWAYS
	_stars = Starfield.new()
	_stars.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_stars)
	_world = Node2D.new()
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	for layer_name in ["_enemies", "_eshots", "_pshots", "_fx"]:
		var n := Node2D.new()
		n.name = layer_name
		_world.add_child(n)
		set(layer_name, n)
	_hud = Hud.new()
	add_child(_hud)
	_hud.start_pressed.connect(_on_start_pressed)
	_hud.pause_pressed.connect(toggle_pause)
	_hud.show_menu()
	if autoplay:
		print("[bot] автоигра")
		start_game()


func _on_start_pressed() -> void:
	if get_tree().paused:
		toggle_pause()
	else:
		start_game()


func start_game() -> void:
	for layer in [_enemies, _eshots, _pshots, _fx]:
		for c in layer.get_children():
			c.queue_free()
	if player:
		player.queue_free()
	boss = null
	score = 0
	wave = 0
	lives = START_LIVES
	_queue.clear()
	player = Player.new()
	player.game = self
	player.god = autoplay
	var size := get_viewport_rect().size
	player.position = Vector2(size.x / 2.0, size.y * 0.8)
	player.hit.connect(_on_player_hit)
	_world.add_child(player)
	state = "play"
	_hud.hide_overlay()
	_hud.hide_boss()
	_hud.set_lives(lives)
	_hud.set_score(0)
	_next_wave = 0.8


func toggle_pause() -> void:
	if state != "play":
		return
	get_tree().paused = not get_tree().paused
	if get_tree().paused:
		_hud.show_pause()
	else:
		_hud.hide_overlay()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.physical_keycode == KEY_ESCAPE or event.physical_keycode == KEY_P):
		toggle_pause()
		return
	if state == "play" and player and not get_tree().paused and event is InputEventScreenDrag:
		player.move_by(event.relative * SENS)


func _process(delta: float) -> void:
	_clock += delta
	if _shot_dir != "" and not _shot_at.is_empty() and _clock >= _shot_at[0]:
		var t: float = _shot_at.pop_front()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_shot_dir.path_join("shot_%03d.png" % int(t)))


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	# тряска экрана
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 1.6)
		_world.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 10.0
	else:
		_world.position = Vector2.ZERO
	if state != "play":
		return
	if autoplay and player:
		_bot(delta)
	# волны
	if _next_wave > 0.0:
		_next_wave -= delta
		if _next_wave <= 0.0:
			_start_wave(wave + 1)
	_spawn_cd -= delta
	if _spawn_cd <= 0.0 and not _queue.is_empty():
		_spawn_cd = 0.45
		var size := get_viewport_rect().size
		spawn_enemy(_queue.pop_front(), Vector2(randf_range(30.0, size.x - 30.0), -30.0))
	if wave > 0 and _next_wave <= 0.0 and _queue.is_empty() and boss == null and _enemies.get_child_count() == 0:
		_next_wave = 1.6
	if boss:
		_hud.set_boss(boss.hp / boss.max_hp)


func _start_wave(n: int) -> void:
	wave = n
	_hud.set_wave(n)
	if n % BOSS_EVERY == 0:
		_hud.banner("БОСС", Boss.NAME + " — " + Boss.TITLE, Color(1.0, 0.4, 0.45))
		boss = Boss.new().setup(self, _boss_hp(n))
		_enemies.add_child(boss)
		if autoplay:
			print("[bot] %.0f с, волна %d: босс, прочность %d" % [_clock, n, int(boss.max_hp)])
		return
	_hud.banner("ВОЛНА %d" % n, "")
	var count := 5 + n * 2
	for i in count:
		var r := randf()
		if n == 1 or r < 0.45:
			_queue.append("scout")
		elif r < 0.75:
			_queue.append("drone")
		else:
			_queue.append("shooter")
	if autoplay:
		print("[bot] %.0f с, волна %d: врагов %d" % [_clock, n, count])


func _hp_scale() -> float:
	return 1.0 + (wave - 1) * 0.14


func _boss_hp(n: int) -> float:
	var num := int(n / BOSS_EVERY)
	var ramp := 0.92 if num == 1 else 1.6 + (num - 2) * 0.3
	return 1000.0 * _hp_scale() * ramp * 1.6 * BOSS_HP_K


# ── спавн ──
func spawn_enemy(kind: String, pos: Vector2) -> Enemy:
	var e := Enemy.new().setup(self, kind, pos, _hp_scale())
	_enemies.add_child(e)
	return e


func can_fire() -> bool:
	return state == "play"


func spawn_player_bolt(pos: Vector2) -> void:
	_pshots.add_child(Bullet.new().setup("pb_bolt_m", 15.0, pos, Vector2(0, -1050), true, 10.0, 6.0))


func spawn_enemy_bullet(pos: Vector2, vel: Vector2) -> void:
	_eshots.add_child(Bullet.new().setup("eb_orb", 15.0, pos, vel, false, 1.0, 5.0))


## прицельный выстрел: extra — сколько пуль по бокам, spread — шаг угла между ними
func fire_aimed(pos: Vector2, speed: float, extra: int, spread: float) -> void:
	var target := player.position if player else pos + Vector2(0, 100)
	var a := (target - pos).angle()
	for i in range(-extra, extra + 1):
		spawn_enemy_bullet(pos, Vector2.from_angle(a + i * spread) * speed)


func fire_ring(pos: Vector2, count: int, speed: float, offset: float) -> void:
	for i in count:
		spawn_enemy_bullet(pos, Vector2.from_angle(offset + i * TAU / count) * speed)


func clear_enemy_bullets() -> void:
	for b in _eshots.get_children():
		b.queue_free()


# ── эффекты ──
func spark(at: Vector2) -> void:
	if _fx.get_child_count() < 80:
		_fx.add_child(FxSprite.make(["fx_ex_s"], at, 14.0, 24.0, 0.15))


func explosion(at: Vector2, size: float) -> void:
	_fx.add_child(FxSprite.make(["ex1", "ex2", "ex3", "ex4", "ex5"], at, size * 1.1, size * 1.8, 0.45))


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func banner(text: String, sub: String) -> void:
	_hud.banner(text, sub)


# ── события ──
func on_enemy_killed(e: Enemy, _rammed: bool) -> void:
	score += e.score
	_hud.set_score(score)
	explosion(e.position, e.width)


func on_boss_ready(b: Boss) -> void:
	_hud.show_boss(Boss.NAME)
	shake(0.4)


func on_boss_killed(b: Boss) -> void:
	score += 5000
	_hud.set_score(score)
	_hud.hide_boss()
	clear_enemy_bullets()
	for i in 6:
		explosion(b.position + Vector2(randf_range(-70, 70), randf_range(-50, 50)), randf_range(60.0, 110.0))
	shake(0.9)
	_hud.banner("БОСС ПОВЕРЖЕН", "+5000", Color(1.0, 0.82, 0.24))
	if autoplay:
		print("[bot] босс повержен за %.1f с" % b.fight_time)
	boss = null
	_next_wave = 3.0


func _on_player_hit() -> void:
	lives -= 1
	_hud.set_lives(lives)
	shake(0.6)
	explosion(player.position, 50.0)
	# пули вокруг гаснут — передышка после попадания
	for b in _eshots.get_children():
		if b.position.distance_to(player.position) < 130.0:
			b.queue_free()
	if lives <= 0:
		_game_over()


func _game_over() -> void:
	state = "over"
	explosion(player.position, 90.0)
	player.queue_free()
	player = null
	_hud.hide_boss()
	_hud.show_game_over(score, wave)
	if autoplay:
		print("[bot] итог: очки %d, волна %d" % [score, wave])


# ── бот-тестировщик: держится под ближайшим врагом, покачиваясь ──
func _bot(delta: float) -> void:
	_bot_t += delta
	var size := get_viewport_rect().size
	var tx := size.x / 2.0 + sin(_bot_t * 0.9) * size.x * 0.3
	if boss and not boss.entering:
		tx = boss.position.x + sin(_bot_t * 1.3) * 40.0
	else:
		var best: Node2D = null
		for e in _enemies.get_children():
			if e is Enemy and (best == null or e.position.y > best.position.y):
				best = e
		if best:
			tx = best.position.x
	player.position.x = move_toward(player.position.x, tx, 260.0 * delta)
	player.clamp_to_screen()
