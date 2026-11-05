class_name Player
extends Area2D
## Корабль игрока: ведётся пальцем/мышью (сдвиг, а не прыжок под палец) или стрелками/WASD,
## стреляет сам. После попадания 1,8 с неуязвим и мигает.

signal hit

const KEY_SPEED := 420.0
const FIRE_CD := 0.14
const WIDTH := 56.0

var game: Node
var invuln := 2.0
var god := false          # бот-тестер: попадания не снимают жизни
var _fire_cd := 0.3
var _last_x := 0.0
var _tilt := 0.0
var _sprite: Sprite2D
var _flame: Sprite2D


func _ready() -> void:
	collision_layer = 1
	collision_mask = 2 | 8
	_flame = Atlas.sprite("fx_tr_engine", 15.0)
	_flame.position = Vector2(0, WIDTH * 0.62)
	add_child(_flame)
	_sprite = Atlas.sprite("ship1", WIDTH)
	add_child(_sprite)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	add_child(shape)
	area_entered.connect(_on_area_entered)
	_last_x = position.x


func move_by(d: Vector2) -> void:
	position += d
	clamp_to_screen()


func clamp_to_screen() -> void:
	var size := get_viewport_rect().size
	position.x = clampf(position.x, WIDTH * 0.42, size.x - WIDTH * 0.42)
	position.y = clampf(position.y, size.y * 0.14, size.y - WIDTH * 0.7)


func _physics_process(delta: float) -> void:
	# клавиатура: стрелки и WASD
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_physical_key_pressed(KEY_A): dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D): dir.x += 1
	if Input.is_physical_key_pressed(KEY_W): dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S): dir.y += 1
	if dir != Vector2.ZERO:
		move_by(dir.limit_length(1.0) * KEY_SPEED * delta)
	# крен по горизонтальной скорости
	var vx := (position.x - _last_x) / maxf(delta, 0.001)
	_last_x = position.x
	_tilt = lerpf(_tilt, clampf(vx * 0.0007, -0.28, 0.28), 0.25)
	_sprite.rotation = _tilt
	_flame.scale.y = _flame.scale.x * randf_range(0.8, 1.2)
	# неуязвимость: мигание
	if invuln > 0.0:
		invuln -= delta
		_sprite.modulate.a = 0.35 if int(invuln * 12.0) % 2 == 0 else 1.0
		if invuln <= 0.0:
			_sprite.modulate.a = 1.0
	else:
		# босс не исчезает при таране: пока корабль в нём, попадание повторяется
		for a in get_overlapping_areas():
			if a is Boss:
				take_hit()
				break
	# автоматическая стрельба
	_fire_cd -= delta
	if _fire_cd <= 0.0 and game.can_fire():
		_fire_cd = FIRE_CD
		game.spawn_player_bolt(position + Vector2(0, -WIDTH * 0.45))


func _on_area_entered(area: Area2D) -> void:
	if area is Bullet and not area.from_player:
		area.queue_free()
		take_hit()
	elif area is Enemy:
		area.die(true)
		take_hit()
	elif area is Boss:
		take_hit()


func take_hit() -> void:
	if invuln > 0.0:
		return
	invuln = 1.8
	if not god:
		hit.emit()
