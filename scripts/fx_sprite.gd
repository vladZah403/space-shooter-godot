class_name FxSprite
extends Sprite2D
## Короткий эффект из кадров атласа: взрыв (ex1…ex5), искра попадания и т.п.
## Кадры сменяются за dur секунд, спрайт растёт от w0 до w1 и гаснет.

var frames: Array = []
var dur := 0.4
var w0 := 40.0
var w1 := 60.0
var fade := true
var _t := 0.0


static func make(frame_list: Array, pos: Vector2, from_w: float, to_w: float, duration: float) -> FxSprite:
	var fx := FxSprite.new()
	fx.frames = frame_list
	fx.position = pos
	fx.w0 = from_w
	fx.w1 = to_w
	fx.dur = duration
	fx.rotation = randf() * TAU
	Atlas.set_frame(fx, frame_list[0], from_w)
	return fx


func _process(delta: float) -> void:
	_t += delta
	var k := _t / dur
	if k >= 1.0:
		queue_free()
		return
	var i := mini(int(k * frames.size()), frames.size() - 1)
	Atlas.set_frame(self, frames[i], lerpf(w0, w1, k))
	if fade:
		modulate.a = 1.0 - k * k
