class_name Bullet
extends Area2D
## Снаряд: выстрел корабля (бьёт врагов) или вражеская пуля (бьёт корабль).
## Слои столкновений: 1 — корабль, 2 — враги, 4 — снаряды корабля, 8 — вражеские пули.

var velocity := Vector2.ZERO
var damage := 10.0
var from_player := true
var life := 3.0
var _spent := false


func setup(frame: String, width: float, pos: Vector2, vel: Vector2, player_shot: bool, dmg := 10.0, radius := 5.0) -> Bullet:
	position = pos
	velocity = vel
	from_player = player_shot
	damage = dmg
	var spr := Atlas.sprite(frame, width)
	if player_shot:
		spr.rotation = velocity.angle() + PI / 2
	add_child(spr)
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	if player_shot:
		collision_layer = 4
		collision_mask = 2
		area_entered.connect(_on_area_entered)
	else:
		collision_layer = 8
		collision_mask = 0
		monitoring = false
	return self


func _physics_process(delta: float) -> void:
	position += velocity * delta
	life -= delta
	var size := get_viewport_rect().size
	if life <= 0.0 or position.y < -40.0 or position.y > size.y + 40.0 or position.x < -40.0 or position.x > size.x + 40.0:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if _spent or not area.has_method("take_damage"):
		return
	if area.take_damage(damage, global_position):
		_spent = true
		queue_free()
