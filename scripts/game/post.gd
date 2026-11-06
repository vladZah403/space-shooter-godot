extends Node
## Постобработка поля боя (автозагрузка Post): полноэкранный шейдер assets/shaders/post.gdshader на своём слое —
## над миром (холст 0), под интерфейсом (Ui — слой 5), поэтому кнопки и HUD не искажаются.
##   Post.wave(x, y, сила)  — ударная волна (координаты поля, как у FX)
##   Post.lens(x, y, r, k)  — воронка чёрной дыры на этот кадр (вызывать из отрисовки каждый кадр)
##   Post.hurt(k)           — вспышка хроматической аберрации (попадание по игроку)
##   Post.warp, Post.warp_at — форсаж прыжка (выставляет Game.draw на этот кадр)
## Качество: низкое — выключено; среднее — волны/воронки/аберрация (слой включается, только пока они есть);
## высокое — плюс свечение (слой включён всегда). Выключается в настройках («Эффекты экрана»).

const MAX := 6

var layer: CanvasLayer
var rect: ColorRect
var mat: ShaderMaterial
var waves: Array = []        # { x, y (экран), t, dur, r1 (доли высоты), k }
var lenses: Array = []       # Vector4(x, y (экран), r, k) — на один кадр
var aberr := 0.0
var warp := 0.0
var warp_at := Vector2.ZERO
var bloom := 0.4
var _wv := PackedVector4Array()
var _lv := PackedVector4Array()


func _ready() -> void:
	layer = CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/post.gdshader")
	rect.material = mat
	rect.visible = false
	layer.add_child(rect)
	_wv.resize(MAX)
	_lv.resize(MAX)


func level() -> int:
	if not M.s.settings.get("post", true): return 0
	return Main.quality


## ударная волна из точки поля; power ≈ 0.4 — крупный взрыв, 1 — бомба/супервзрыв, 2 — смерть босса
func wave(x: float, y: float, power := 1.0) -> void:
	if level() == 0: return
	if waves.size() >= MAX:
		# вытесняем самую слабую из оставшихся
		var wi := 0
		for i in waves.size():
			if waves[i].k * (1.0 - waves[i].t / waves[i].dur) < waves[wi].k * (1.0 - waves[wi].t / waves[wi].dur): wi = i
		if waves[wi].k > 0.012 * power: return
		waves.remove_at(wi)
	waves.append({"x": x + G.FX + FX.shake_x, "y": y + FX.shake_y, "t": 0.0, "dur": 0.42 + 0.28 * minf(power, 2.0),
		"r1": 0.16 + 0.34 * minf(power, 2.2), "k": 0.012 * minf(power, 2.2)})


## воронка на этот кадр: r — радиус ядра в пикселях поля, k ≈ 0.3…1 — сила закрутки
func lens(x: float, y: float, r: float, k := 0.6) -> void:
	if lenses.size() >= MAX or r < 2: return
	lenses.append(Vector4((x + G.FX + FX.shake_x) / G.W, (y + FX.shake_y) / G.H, r / G.H, k))


func hurt(k := 1.0) -> void:
	aberr = maxf(aberr, 0.0045 * k)


func frame(dt: float) -> void:
	var lv := level()
	var n := 0
	for i in range(waves.size() - 1, -1, -1):
		var w: Dictionary = waves[i]
		w.t += dt
		if w.t >= w.dur: waves.remove_at(i)
	if lv > 0:
		for w: Dictionary in waves:
			var q: float = w.t / w.dur
			var r: float = w.r1 * (1.0 - pow(1.0 - q, 2.2))
			_wv[n] = Vector4(w.x / G.W, w.y / G.H, r, w.k * (1.0 - q) * (1.0 - q))
			n += 1
	var ln := mini(lenses.size(), MAX) if lv > 0 else 0
	for i in ln: _lv[i] = lenses[i]
	lenses.clear()
	aberr = maxf(0.0, aberr - dt * 0.012)
	var bl := bloom if lv >= 2 else 0.0
	var wp := warp if lv > 0 else 0.0
	warp = 0.0
	var on := lv > 0 and (bl > 0 or n > 0 or ln > 0 or aberr > 0.0004 or wp > 0.005)
	rect.visible = on
	if not on: return
	mat.set_shader_parameter("aspect", G.W / G.H)
	mat.set_shader_parameter("waves", _wv)
	mat.set_shader_parameter("wave_n", n)
	mat.set_shader_parameter("lenses", _lv)
	mat.set_shader_parameter("lens_n", ln)
	mat.set_shader_parameter("aberr", aberr)
	mat.set_shader_parameter("bloom", bl)
	mat.set_shader_parameter("warp", wp)
	mat.set_shader_parameter("warp_c", Vector2((warp_at.x + G.FX) / G.W, warp_at.y / G.H))


func clear() -> void:
	waves.clear()
	lenses.clear()
	aberr = 0.0
	warp = 0.0
