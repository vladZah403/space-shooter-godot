extends Node
## Спрайты из атласов JS-версии игры (assets/sprites.png и sprites2.png, кадры — atlas_data.gd).
## Atlas.tex("ship1") — текстура кадра, Atlas.sprite("ship1", 56) — готовый Sprite2D нужной ширины.

const Data := preload("res://scripts/atlas_data.gd")

var _sheets: Array[Texture2D] = []
var _cache: Dictionary = {}
var add_material: CanvasItemMaterial


func _ready() -> void:
	_sheets = [load("res://assets/sprites.png"), load("res://assets/sprites2.png")]
	add_material = CanvasItemMaterial.new()
	add_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


func has(frame: String) -> bool:
	return Data.FRAMES.has(frame)


func tex(frame: String) -> Texture2D:
	if _cache.has(frame):
		return _cache[frame]
	if not Data.FRAMES.has(frame):
		push_warning("Нет кадра в атласе: " + frame)
		return null
	var f: Array = Data.FRAMES[frame]
	var at := AtlasTexture.new()
	at.atlas = _sheets[f[5]]
	at.region = Rect2(f[0], f[1], f[2], f[3])
	_cache[frame] = at
	return at


func is_additive(frame: String) -> bool:
	return Data.FRAMES.has(frame) and Data.FRAMES[frame][4] == 1


## Sprite2D с кадром атласа, отмасштабированный до ширины width (в пикселях экрана игры)
func sprite(frame: String, width: float) -> Sprite2D:
	var s := Sprite2D.new()
	set_frame(s, frame, width)
	return s


func set_frame(s: Sprite2D, frame: String, width: float) -> void:
	var t := tex(frame)
	s.texture = t
	if t:
		var k := width / t.get_width()
		s.scale = Vector2(k, k)
	s.material = add_material if is_additive(frame) else null
