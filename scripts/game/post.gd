extends Node
## Постобработка поля боя (автозагрузка Post): полноэкранный шейдер assets/shaders/post.gdshader на своём слое —
## над миром (холст 0), под интерфейсом (Ui — слой 5), поэтому кнопки и HUD не искажаются.
##   Post.wave(x, y, сила)  — ударная волна (координаты поля, как у FX)
##   Post.lens(x, y, r, k)  — воронка чёрной дыры на этот кадр (вызывать из отрисовки каждый кадр)
##   Post.hurt(k)           — вспышка хроматической аберрации (попадание по игроку)
##   Post.bubble(x, y, r, k, цвет, удар) — пузырь щита на этот кадр: преломление у кромки, светящийся край, рябь от удара
##   Post.warp, Post.warp_at — форсаж прыжка (выставляет Game.draw на этот кадр)
## Сам следит за игрой: под окнами (пауза, выбор, подсказка, итоги) игра размывается; на последней жизни
## цвета блекнут, при заморозке — холодный тон, при замедлении времени — синеватый.
## Качество: низкое — выключено; среднее — волны/воронки/аберрация (слой включается, только пока они есть);
## высокое — плюс свечение (слой включён всегда). Выключается в настройках («Эффекты экрана»).

const MAX := 6

var layer: CanvasLayer
var rect: ColorRect
var mat: ShaderMaterial
var waves: Array = []        # { x, y (экран), t, dur, r1 (доли высоты), k }
var lenses: Array = []       # Vector4(x, y (экран), r, k) — на один кадр
var bubbles: Array = []      # [Vector4(x, y (UV), r, k), Color(цвет, удар)] — на один кадр
var aberr := 0.0
var warp := 0.0
var warp_at := Vector2.ZERO
var bloom := 0.4
var blur := 0.0
var sat := 1.0
var grade := Vector3.ONE
var _wv := PackedVector4Array()
var _lv := PackedVector4Array()
var _bv := PackedVector4Array()
var _bc := PackedVector4Array()
const MAXB := 4


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
	_bv.resize(MAXB)
	_bc.resize(MAXB)


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
	var sp := Game.toScreen(x, y)
	waves.append({"x": sp.x, "y": sp.y, "t": 0.0, "dur": 0.42 + 0.28 * minf(power, 2.0),
		"r1": 0.16 + 0.34 * minf(power, 2.2), "k": 0.012 * minf(power, 2.2)})


## пузырь щита на этот кадр (вызывать из отрисовки каждый кадр): r — радиус в пикселях поля, k ≈ 0.5…1.2 — сила
## преломления, hit 0…1 — рябь и вспышка от попадания. Больше MAXB — берутся самые крупные
func bubble(x: float, y: float, r: float, k: float, col: Color, hit := 0.0) -> void:
	if r < 4: return
	var sp := Game.toScreen(x, y)
	if sp.y < -r or sp.y > G.H + r: return
	var it := [Vector4(sp.x / G.W, sp.y / G.H, r * Game.cam.z / G.H, k), Color(col, clampf(hit, 0, 1))]
	if bubbles.size() < MAXB:
		bubbles.append(it)
		return
	var wi := 0
	for i in bubbles.size():
		if bubbles[i][0].z < bubbles[wi][0].z: wi = i
	if bubbles[wi][0].z < it[0].z: bubbles[wi] = it


## воронка на этот кадр: r — радиус ядра в пикселях поля, k ≈ 0.3…1 — сила закрутки
func lens(x: float, y: float, r: float, k := 0.6) -> void:
	if lenses.size() >= MAX or r < 2: return
	var sp := Game.toScreen(x, y)
	lenses.append(Vector4(sp.x / G.W, sp.y / G.H, r * Game.cam.z / G.H, k))


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
	var bn := mini(bubbles.size(), MAXB) if lv > 0 else 0
	for i in bn:
		var c: Color = bubbles[i][1]
		_bv[i] = bubbles[i][0]
		_bc[i] = Vector4(c.r, c.g, c.b, c.a)
	bubbles.clear()
	aberr = maxf(0.0, aberr - dt * 0.012)
	var bl := bloom if lv >= 2 else 0.0
	var wp := warp if lv > 0 else 0.0
	warp = 0.0
	_mood(dt)
	var on := lv > 0 and (bl > 0 or n > 0 or ln > 0 or bn > 0 or aberr > 0.0004 or wp > 0.005 or blur > 0.01 or sat < 0.99 or not grade.is_equal_approx(Vector3.ONE))
	rect.visible = on
	if not on: return
	mat.set_shader_parameter("aspect", G.W / G.H)
	mat.set_shader_parameter("waves", _wv)
	mat.set_shader_parameter("wave_n", n)
	mat.set_shader_parameter("lenses", _lv)
	mat.set_shader_parameter("lens_n", ln)
	mat.set_shader_parameter("bubbles", _bv)
	mat.set_shader_parameter("bubble_col", _bc)
	mat.set_shader_parameter("bubble_n", bn)
	mat.set_shader_parameter("aberr", aberr)
	mat.set_shader_parameter("bloom", bl)
	mat.set_shader_parameter("warp", wp)
	mat.set_shader_parameter("warp_c", Vector2((warp_at.x + G.FX) / G.W, warp_at.y / G.H))
	mat.set_shader_parameter("blur", blur)
	mat.set_shader_parameter("sat", sat)
	mat.set_shader_parameter("grade", grade)


## размытие и цветокоррекция по состоянию игры — плавно, без скачков
func _mood(dt: float) -> void:
	var st: String = Game.state
	var blur_to := 0.85 if st in ["pause", "perk", "tip", "over", "revive"] else 0.0
	var sat_to := 1.0
	var gr_to := Vector3.ONE
	var p = Game.player
	if p != null and Game.run and st in ["play", "dying"]:
		if Game.buffs.get("freeze", 0.0) > 0:
			sat_to = 0.55; gr_to = Vector3(0.88, 1.0, 1.12)
		elif Game.run.skillFx.get("sk_timewarp", 0.0) > 0:
			sat_to = 0.75; gr_to = Vector3(0.92, 0.96, 1.1)
		elif p.alive and p.lives == 1:
			sat_to = 0.7
	var k := 1.0 - exp(-dt * 7.0)
	blur = lerpf(blur, blur_to, k)
	if blur < 0.005: blur = 0.0
	sat = lerpf(sat, sat_to, k)
	if absf(sat - 1.0) < 0.005: sat = 1.0
	grade = grade.lerp(gr_to, k)
	if grade.is_equal_approx(Vector3.ONE) or (grade - Vector3.ONE).length() < 0.004: grade = Vector3.ONE


func clear() -> void:
	waves.clear()
	lenses.clear()
	bubbles.clear()
	aberr = 0.0
	warp = 0.0
	blur = 0.0
	sat = 1.0
	grade = Vector3.ONE
