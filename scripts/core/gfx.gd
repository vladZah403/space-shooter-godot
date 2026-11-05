extends Node
## Графика (автозагрузка G) — перенос gfx.js: атлас спрайтов, размеры поля, перекраска (hue),
## белый силуэт для вспышки, мягкие свечения, процедурные спрайты. Рисование — через Ctx.
##  G.W, G.H — размер экрана игры; G.FW — ширина игрового поля (на телефоне = W), G.FX — его сдвиг;
##  G.S — масштаб (1 при ширине поля 400).

const Data := preload("res://scripts/atlas_data.gd")

var W := 390.0
var H := 844.0
var FW := 390.0
var FX := 0.0
var S := 1.0
var frames: Dictionary = Data.FRAMES
var nozzles: Dictionary = Data.NOZZLES

var _sheets: Array[Texture2D] = []
var _images: Array = [null, null]
var _tint := {}
var _white := {}
var _glow := {}
var _soft := {}
var _hue := {}
var _proc := {}
var _icons := {}


func _ready() -> void:
	_sheets = [load("res://assets/sprites.png"), load("res://assets/sprites2.png")]
	get_viewport().size_changed.connect(resize)
	resize()


## размеры поля, как в main.js JS-версии
func resize() -> void:
	var sz := get_viewport().get_visible_rect().size
	W = sz.x
	H = sz.y
	FW = minf(minf(W, maxf(360.0, H * 0.62)), 640.0)
	if W < 700.0:
		FW = W
	FX = roundf((W - FW) / 2.0)
	S = U.clamp(FW / 400.0, 0.82, 1.22)


func frame(name: String) -> Array:
	return frames.get(name, [])


func has(name: String) -> bool:
	return frames.has(name)


func aspect(name: String) -> float:
	var f: Array = frames.get(name, [])
	return float(f[3]) / f[2] if f else 1.0


func src(f: Array) -> Texture2D:
	return _sheets[f[5]]


## кадр атласа по центру (x, y) шириной w; rot — поворот; a — прозрачность (по умолчанию текущая)
func draw(ctx: Ctx, name: String, x: float, y: float, w: float, rot := 0.0, a := -1.0) -> void:
	var f: Array = frames.get(name, [])
	if f.is_empty():
		return
	var h: float = w * f[3] / f[2]
	var old := ctx.alpha
	if a >= 0.0:
		ctx.alpha = a
	if rot != 0.0:
		ctx.save()
		ctx.translate(x, y)
		ctx.rotate(rot)
		ctx.draw_image(_sheets[f[5]], f[0], f[1], f[2], f[3], -w / 2.0, -h / 2.0, w, h)
		ctx.restore()
	else:
		ctx.draw_image(_sheets[f[5]], f[0], f[1], f[2], f[3], x - w / 2.0, y - h / 2.0, w, h)
	ctx.alpha = old


## готовая текстура (перекрашенная, свечение) по центру (x, y) шириной w
func draw_canvas(ctx: Ctx, tex: Texture2D, x: float, y: float, w: float, rot := 0.0) -> void:
	if tex == null:
		return
	var h := w * tex.get_height() / tex.get_width()
	if rot != 0.0:
		ctx.save()
		ctx.translate(x, y)
		ctx.rotate(rot)
		ctx.draw_tex(tex, -w / 2.0, -h / 2.0, w, h)
		ctx.restore()
	else:
		ctx.draw_tex(tex, x - w / 2.0, y - h / 2.0, w, h)


## текстура кадра для интерфейса (TextureRect и т.п.)
func icon(name: String) -> Texture2D:
	if _icons.has(name):
		return _icons[name]
	var f: Array = frames.get(name, [])
	if f.is_empty():
		return null
	var at := AtlasTexture.new()
	at.atlas = _sheets[f[5]]
	at.region = Rect2(f[0], f[1], f[2], f[3])
	_icons[name] = at
	return at


func _region_image(f: Array) -> Image:
	if _images[f[5]] == null:
		var img: Image = _sheets[f[5]].get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		_images[f[5]] = img
	return (_images[f[5]] as Image).get_region(Rect2i(f[0], f[1], f[2], f[3]))


# ── перекраска: hue — тон 0..360; sat — насыщенность; dark — затемнение; bright — осветление;
#    alpha — сохранить прозрачность и у аддитивных кадров (иконки) ──
func tinted(name: String, t: Dictionary) -> Texture2D:
	var hue = t.get("hue")
	var sat: float = t.get("sat", 0.0)
	var dark: float = t.get("dark", 0.0)
	var bright: float = t.get("bright", 0.0)
	var keep_a: bool = t.get("alpha", false)
	if hue == null and sat == 0.0 and dark == 0.0 and bright == 0.0:
		return null
	var key := "%s|%s|%s|%s|%s|%s" % [name, hue, sat, dark, bright, keep_a]
	if _tint.has(key):
		return _tint[key]
	var f: Array = frames.get(name, [])
	if f.is_empty():
		return null
	var img := _region_image(f)
	var add: bool = f[4] == 1
	var hc := Color.from_hsv(float(hue) / 360.0, 1.0, 1.0) if hue != null else Color.WHITE
	var dk := Color.from_hsv(float(hue if hue != null else 0) / 360.0, 0.4, 1.0 - dark) if dark > 0.0 else Color.WHITE
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var a := c.a
			if add and not keep_a:
				c = Color(c.r * a, c.g * a, c.b * a, 1.0)
			if hue != null:
				c = _blend_hue(c, hc)
			if sat != 0.0:
				c = _set_lum(_set_sat(c, sat), _lum(c))
			if dark > 0.0:
				c = Color(c.r * dk.r, c.g * dk.g, c.b * dk.b, c.a)
			if bright > 0.0:
				c = Color(1.0 - (1.0 - c.r) * (1.0 - bright), 1.0 - (1.0 - c.g) * (1.0 - bright), 1.0 - (1.0 - c.b) * (1.0 - bright), c.a)
			c.a = 1.0 if add and not keep_a else a
			img.set_pixel(x, y, c)
	var tex := ImageTexture.create_from_image(img)
	_tint[key] = tex
	return tex


func _lum(c: Color) -> float:
	return 0.3 * c.r + 0.59 * c.g + 0.11 * c.b


func _clip(c: Color) -> Color:
	var l := _lum(c)
	var n := minf(c.r, minf(c.g, c.b))
	var x := maxf(c.r, maxf(c.g, c.b))
	var r := c
	if n < 0.0:
		r = Color(l + (c.r - l) * l / (l - n), l + (c.g - l) * l / (l - n), l + (c.b - l) * l / (l - n), c.a)
	if x > 1.0:
		r = Color(l + (r.r - l) * (1.0 - l) / (x - l), l + (r.g - l) * (1.0 - l) / (x - l), l + (r.b - l) * (1.0 - l) / (x - l), c.a)
	return r


func _set_lum(c: Color, l: float) -> Color:
	var d := l - _lum(c)
	return _clip(Color(c.r + d, c.g + d, c.b + d, c.a))


func _set_sat(c: Color, s: float) -> Color:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	if mx - mn <= 0.0:
		return Color(0, 0, 0, c.a)
	var k := s / (mx - mn)
	return Color((c.r - mn) * k, (c.g - mn) * k, (c.b - mn) * k, c.a)


## режим смешивания 'hue': тон источника, насыщенность и яркость фона
func _blend_hue(base: Color, tint: Color) -> Color:
	var mx := maxf(base.r, maxf(base.g, base.b))
	var mn := minf(base.r, minf(base.g, base.b))
	return _set_lum(_set_sat(tint, mx - mn), _lum(base))


## тон цвета '#rrggbb' в градусах — для перекраски эффектов под цвет врага или бонуса
func hue_of(hex: String) -> float:
	if _hue.has(hex):
		return _hue[hex]
	var c := Color.from_string(hex, Color.WHITE)
	var h := roundf(c.h * 360.0)
	_hue[hex] = h
	return h


## белый силуэт кадра — вспышка при попадании
func white(name: String) -> Texture2D:
	if _white.has(name):
		return _white[name]
	var f: Array = frames.get(name, [])
	if f.is_empty():
		return null
	var img := _region_image(f)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var tex := ImageTexture.create_from_image(img)
	_white[name] = tex
	return tex


func hex_a(hex: String, a: float) -> Color:
	return U.col(hex, a)


## мягкое свечение цвета с белым ядром
func glow(color: String, size := 64) -> Texture2D:
	var key := color + str(size)
	if _glow.has(key):
		return _glow[key]
	var tex := _radial(size, PackedFloat32Array([0.0, 0.18, 0.45, 1.0]),
		PackedColorArray([Color.WHITE, U.col(color), U.col(color, 0.35), U.col(color, 0.0)]))
	_glow[key] = tex
	return tex


## мягкий круг без белого ядра (дым, подсветка)
func soft(color: String, size := 64) -> Texture2D:
	var key := color + str(size)
	if _soft.has(key):
		return _soft[key]
	var tex := _radial(size, PackedFloat32Array([0.0, 0.5, 1.0]),
		PackedColorArray([U.col(color, 1.0), U.col(color, 0.45), U.col(color, 0.0)]))
	_soft[key] = tex
	return tex


func _radial(size: int, offsets: PackedFloat32Array, colors: PackedColorArray) -> Texture2D:
	var g := Gradient.new()
	g.offsets = offsets
	g.colors = colors
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = size
	t.height = size
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t


# ── процедурные спрайты (рисуются один раз попиксельно) ──
func proc(name: String) -> Texture2D:
	if _proc.has(name):
		return _proc[name]
	var img: Image
	match name:
		"coin":
			img = _disc(48, func(u: float, v: float, r: float) -> Color:
				var d := Vector2(u - 0.38, v - 0.32).length() / 0.62
				var base := Color("#fff7c2").lerp(Color("#ffd23d"), clampf(d / 0.35, 0, 1))
				if d > 0.35: base = Color("#ffd23d").lerp(Color("#e09a12"), clampf((d - 0.35) / 0.5, 0, 1))
				if d > 0.85: base = Color("#e09a12").lerp(Color("#8a5a06"), clampf((d - 0.85) / 0.15, 0, 1))
				if absf(r - 0.68) < 0.05: base = Color("#a86d08")
				return base)
		"xp":
			img = _diamond(40, Color("#d8ffec"), Color("#3dffa2"), Color("#0d9a5c"))
		"xpBig":
			img = _diamond(52, Color("#f0fbff"), Color("#5cc8ff"), Color("#6b3dff"))
		"voidcore":
			img = _disc(64, func(_u: float, _v: float, r: float) -> Color:
				return Color(0, 0, 0, 1).lerp(Color(0.016, 0, 0.047, 0.92), clampf(r / 0.55, 0, 1)) if r < 0.55 else Color(0.016, 0, 0.047, 0.92).lerp(Color(0.04, 0, 0.12, 0), clampf((r - 0.55) / 0.45, 0, 1)))
		"vortex":
			img = _disc(64, func(_u: float, _v: float, r: float) -> Color:
				if r < 0.26: return Color.BLACK
				if r < 0.32: return Color("#1a0533")
				if r < 0.55: return Color("#1a0533").lerp(Color(0.69, 0.42, 1.0, 0.85), (r - 0.32) / 0.23)
				return Color(0.69, 0.42, 1.0, 0.85).lerp(Color(0.43, 0.16, 0.86, 0.0), (r - 0.55) / 0.45))
		"mine":
			img = _disc(36, func(u: float, v: float, r: float) -> Color:
				if r < 0.61:
					var d := Vector2(u - 0.42, v - 0.4).length() / 0.3
					return Color("#ffb3b3").lerp(Color("#d22b3d"), clampf(d, 0, 1)).lerp(Color("#5c0a14"), clampf(d - 1.0, 0, 1))
				var a := atan2(v - 0.5, u - 0.5)
				if r < 0.9 and fmod(absf(a) + PI / 8, PI / 4) < 0.18: return Color("#ff5c5c")
				return Color(0, 0, 0, 0))
		"energy":
			img = Image.create(28, 36, false, Image.FORMAT_RGBA8)
			for y in 36:
				for x in 28:
					if x >= 2 and x <= 26 and y >= 4 and y <= 35:
						var k := float(y) / 36.0
						var c := Color("#fffbd0").lerp(Color("#ffe23d"), clampf(k / 0.45, 0, 1)) if k < 0.45 else Color("#ffe23d").lerp(Color("#c98a06"), (k - 0.45) / 0.55)
						if x <= 3 or x >= 25 or y <= 5 or y >= 34: c = Color("#7a5600")
						img.set_pixel(x, y, c)
					elif x >= 9 and x < 19 and y < 5:
						img.set_pixel(x, y, Color("#6b5000"))
			_bolt_into(img)
		_:
			img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var tex := ImageTexture.create_from_image(img)
	_proc[name] = tex
	return tex


func _disc(size: int, shade: Callable) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := (x + 0.5) / size
			var v := (y + 0.5) / size
			var r := Vector2(u - 0.5, v - 0.5).length() * 2.0
			if r <= 1.0:
				img.set_pixel(x, y, shade.call(u, v, r))
	return img


func _diamond(size: int, c0: Color, c1: Color, c2: Color) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var h := size / 2.0
	for y in size:
		for x in size:
			var dx := absf(x + 0.5 - h) / (h - 9.0)
			var dy := absf(y + 0.5 - h) / (h - 4.0)
			if dx + dy <= 1.0:
				var k := (x + y) / float(size * 2)
				var c := c0.lerp(c1, clampf(k * 2.0, 0, 1)) if k < 0.5 else c1.lerp(c2, (k - 0.5) * 2.0)
				img.set_pixel(x, y, c)
			elif dx + dy <= 1.35:
				img.set_pixel(x, y, Color(c1.r, c1.g, c1.b, 0.35 * (1.35 - dx - dy) / 0.35))
	return img


func _bolt_into(img: Image) -> void:
	var poly := PackedVector2Array([Vector2(16, 8), Vector2(8, 21), Vector2(13, 21), Vector2(11, 31), Vector2(20, 17), Vector2(15, 17), Vector2(17, 8)])
	for y in img.get_height():
		for x in img.get_width():
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), poly):
				img.set_pixel(x, y, Color.WHITE)
