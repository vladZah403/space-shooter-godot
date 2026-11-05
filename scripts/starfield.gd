extends Node2D
## Фон: тёмно-синий градиент и три слоя звёзд, летящих вниз с разной скоростью.

const TOP := Color(0.024, 0.039, 0.122)
const BOTTOM := Color(0.043, 0.071, 0.22)

var speed_mul := 1.0
var _stars: Array = []


func _ready() -> void:
	z_index = -100
	var size := get_viewport_rect().size
	for i in 140:
		var layer := i % 3
		_stars.append({
			"p": Vector2(randf() * size.x, randf() * size.y),
			"v": [18.0, 45.0, 95.0][layer] * randf_range(0.8, 1.2),
			"s": [1.0, 1.5, 2.2][layer],
			"a": [0.35, 0.55, 0.85][layer] * randf_range(0.7, 1.0),
		})


func _process(delta: float) -> void:
	var size := get_viewport_rect().size
	for st in _stars:
		var p: Vector2 = st.p
		p.y += st.v * speed_mul * delta
		if p.y > size.y:
			p = Vector2(randf() * size.x, -2.0)
		st.p = p
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
		PackedColorArray([TOP, TOP, BOTTOM, BOTTOM]))
	for st in _stars:
		draw_rect(Rect2(st.p, Vector2(st.s, st.s * (1.0 + speed_mul * 0.6))), Color(0.82, 0.9, 1.0, st.a))
