class_name Boss
extends Area2D
## Страж — первый босс. Три фазы: на 2/3 и 1/3 прочности перестраивается (2,2 с неуязвим,
## экран чистится от пуль), дальше атакует чаще. Урон не перескакивает фазу.
##  фаза 1: кольца пуль и прицельный веер
##  фаза 2: + вызывает разведчиков
##  фаза 3: + спиральный поток

const NAME := "СТРАЖ"
const TITLE := "Хранитель первого рубежа"
const PHASE_T := 2.2
const WIDTH := 180.0

var game: Node
var hp := 1000.0
var max_hp := 1000.0
var phase := 1
var entering := true
var dead := false
var fight_time := 0.0
var _trans := 0.0
var _t := 0.0
var _timers := {}
var _flash := 0.0
var _sprite: Sprite2D
var _base_y := 210.0


func setup(g: Node, total_hp: float) -> Boss:
	game = g
	hp = total_hp
	max_hp = total_hp
	_sprite = Atlas.sprite("boss", WIDTH)
	add_child(_sprite)
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = WIDTH * 0.3
	capsule.height = WIDTH * 0.85
	capsule.height = maxf(capsule.height, capsule.radius * 2.0)
	shape.shape = capsule
	shape.rotation = PI / 2
	add_child(shape)
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	return self


func _ready() -> void:
	var size := get_viewport_rect().size
	position = Vector2(size.x / 2.0, -WIDTH * 0.6)
	_base_y = clampf(size.y * 0.24, 170.0, 260.0)


func _physics_process(delta: float) -> void:
	_t += delta
	var size := get_viewport_rect().size
	if entering:
		position.y = move_toward(position.y, _base_y, 110.0 * delta)
		if position.y >= _base_y - 0.5:
			entering = false
			game.on_boss_ready(self)
		return
	fight_time += delta
	if _trans > 0.0:
		_trans -= delta
		var k := 1.0 - _trans / PHASE_T
		position.x += sin(_t * 53.0) * 1.6 * k
		_sprite.modulate = Color(1.0 + k, 1.0 + k * 0.4, 1.0 + k * 0.4)
		if _trans <= 0.0:
			_phase_start()
		return
	position.x = size.x / 2.0 + sin(_t * 0.6) * size.x * 0.24
	var rate := 1.0 + (phase - 1) * 0.3
	if _timer("ring", 2.2 / rate, delta):
		game.fire_ring(position + Vector2(0, 40), 10 + phase * 2, 150.0, randf() * TAU)
	if _timer("fan", 1.7 / rate, delta):
		game.fire_aimed(position + Vector2(0, 60), 220.0, 1 + phase, 0.22)
	if phase >= 2 and _timer("summon", 6.0, delta):
		for side in [-1, 1]:
			game.spawn_enemy("scout", position + Vector2(side * WIDTH * 0.4, 30))
	if phase >= 3 and _timer("spiral", 0.11, delta):
		var a := _t * 3.4
		game.spawn_enemy_bullet(position + Vector2(0, 40), Vector2(cos(a), sin(a)) * 170.0)
	if _flash > 0.0:
		_flash -= delta
		_sprite.modulate = Color(1.8, 1.8, 1.8) if _flash > 0.0 else Color.WHITE


func _timer(key: String, period: float, delta: float) -> bool:
	if not _timers.has(key):
		_timers[key] = period * randf_range(0.4, 0.9)
	_timers[key] -= delta
	if _timers[key] <= 0.0:
		_timers[key] += period
		return true
	return false


func take_damage(dmg: float, at: Vector2) -> bool:
	if dead:
		return false
	game.spark(at)
	# пока входит или перестраивается — неуязвим, но пули гасит
	if entering or _trans > 0.0:
		return true
	if phase < 3:
		var floor_hp := max_hp * (2.0 / 3.0 if phase == 1 else 1.0 / 3.0)
		hp -= minf(dmg, hp - floor_hp)
		if hp <= floor_hp + 0.001:
			_phase_end(phase + 1)
	else:
		hp -= dmg
	_flash = 0.05
	if hp <= 0.0:
		dead = true
		game.on_boss_killed(self)
		queue_free()
	return true


func _phase_end(n: int) -> void:
	phase = n
	_trans = PHASE_T
	_timers.clear()
	game.clear_enemy_bullets()
	game.banner("ФАЗА %d" % n, "")
	game.shake(0.35)


func _phase_start() -> void:
	_sprite.modulate = Color.WHITE
	game.shake(0.5)
	game.fire_ring(position, 16, 160.0, randf() * TAU)
