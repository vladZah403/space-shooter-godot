class_name Enemy
extends Area2D
## Обычный враг. Поведение (как в JS-версии):
##  scout   — пикирует на корабль, покачиваясь; пролетел мимо — заходит сверху снова
##  drone   — встаёт в строй на своей высоте, качается, изредка стреляет прицельно
##  shooter — зависает и бьёт веером из трёх пуль

const DEFS := {
	"scout":   {"frame": "scout",   "w": 46.0, "hp": 22.0, "spd": 125.0, "score": 100},
	"drone":   {"frame": "drone",   "w": 34.0, "hp": 12.0, "spd": 150.0, "score": 60},
	"shooter": {"frame": "shooter", "w": 50.0, "hp": 42.0, "spd": 95.0,  "score": 220},
}

var game: Node
var kind := "scout"
var hp := 10.0
var max_hp := 10.0
var score := 0
var width := 40.0
var dead := false
var _spd := 100.0
var _t := 0.0
var _fire_cd := 2.0
var _home_x := 0.0
var _slot_y := 200.0
var _flash := 0.0
var _sprite: Sprite2D


func setup(g: Node, k: String, pos: Vector2, hp_scale: float) -> Enemy:
	game = g
	kind = k
	position = pos
	var d: Dictionary = DEFS[k]
	hp = d.hp * hp_scale
	max_hp = hp
	score = d.score
	width = d.w
	_spd = d.spd
	_sprite = Atlas.sprite(d.frame, width)
	_sprite.rotation = PI   # на листе враги смотрят вверх
	add_child(_sprite)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = width * 0.4
	shape.shape = circle
	add_child(shape)
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	_home_x = pos.x
	_slot_y = randf_range(110.0, 300.0)
	_fire_cd = randf_range(1.2, 2.6)
	_t = randf() * 10.0
	return self


func _physics_process(delta: float) -> void:
	_t += delta
	var size := get_viewport_rect().size
	match kind:
		"scout":
			var px: float = game.player.position.x if game.player else size.x / 2.0
			position.x = move_toward(position.x, px, 55.0 * delta) + sin(_t * 3.0) * 45.0 * delta
			position.y += _spd * delta
			if position.y > size.y + 40.0:
				position = Vector2(randf_range(30.0, size.x - 30.0), -40.0)
		"drone":
			position.y = move_toward(position.y, _slot_y, _spd * delta)
			position.x = _home_x + sin(_t * 1.6) * 40.0
			if position.y >= _slot_y - 1.0:
				_fire_cd -= delta
				if _fire_cd <= 0.0:
					_fire_cd = randf_range(2.6, 3.6)
					game.fire_aimed(position, 170.0, 0, 0.0)
		"shooter":
			position.y = move_toward(position.y, _slot_y, _spd * delta)
			position.x = _home_x + sin(_t * 0.8) * 25.0
			if position.y >= _slot_y - 1.0:
				_fire_cd -= delta
				if _fire_cd <= 0.0:
					_fire_cd = randf_range(1.8, 2.4)
					game.fire_aimed(position + Vector2(0, width * 0.3), 190.0, 1, 0.28)
	if _flash > 0.0:
		_flash -= delta
		_sprite.modulate = Color(2.2, 2.2, 2.2) if _flash > 0.0 else Color.WHITE


func take_damage(dmg: float, at: Vector2) -> bool:
	if dead:
		return false
	hp -= dmg
	_flash = 0.06
	game.spark(at)
	if hp <= 0.0:
		die(false)
	return true


## rammed — враг врезался в корабль (очки всё равно даём)
func die(rammed: bool) -> void:
	if dead:
		return
	dead = true
	game.on_enemy_killed(self, rammed)
	queue_free()
