extends Node
## Сверка перекраски на видеокарте (G.tinted/G.white) со старой попиксельной (процессор). Запуск с окном:
##   Godot.exe --path . res://tools/check/tint_check.tscn

var _images: Array = [null, null]
const CASES := [["e_drone2", {"hue": 190.0}], ["scout", {"hue": 44, "bright": 0.08}], ["fx_flare", {"hue": 45}],
	["fx_pickup", {"hue": 43.0}], ["p_merchant", {"sat": -0.9, "dark": 0.45}], ["pb_orb", {"hue": 45, "alpha": true}], ["e_bug", {"hue": 44, "bright": 0.08}]]


func _ready() -> void:
	var gpu := []
	for c in CASES: gpu.append(G.tinted(c[0], c[1]))
	gpu.append(G.white("scout"))
	for i in 3: await RenderingServer.frame_post_draw
	var worst := 0.0
	for i in CASES.size():
		var ref: Image = cpu_tinted(CASES[i][0], CASES[i][1])
		worst = maxf(worst, _cmp(CASES[i][0] + str(CASES[i][1]), ref, gpu[i].get_image()))
	worst = maxf(worst, _cmp("white scout", cpu_white("scout"), gpu[-1].get_image()))
	print("TINT CHECK DONE, худшее среднее отличие %.4f" % worst)
	get_tree().quit()


func _cmp(label: String, a: Image, b: Image) -> float:
	b.convert(Image.FORMAT_RGBA8)
	if a.get_size() != b.get_size():
		print(label, ": размер ", a.get_size(), " ≠ ", b.get_size())
		return 1.0
	var sum := 0.0
	var mx := 0.0
	var n := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			var d := (absf(p.r * p.a - q.r * q.a) + absf(p.g * p.a - q.g * q.a) + absf(p.b * p.a - q.b * q.a)) / 3.0 + absf(p.a - q.a)
			sum += d; mx = maxf(mx, d); n += 1
	print("%s: среднее %.4f, макс %.3f" % [label, sum / n, mx])
	return sum / n


func _region_image(f: Array) -> Image:
	if _images[f[5]] == null:
		var img: Image = G._sheets[f[5]].get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		_images[f[5]] = img
	return (_images[f[5]] as Image).get_region(Rect2i(f[0], f[1], f[2], f[3]))



func cpu_tinted(name: String, t: Dictionary) -> Image:
	var hue = t.get("hue")
	var sat: float = t.get("sat", 0.0)
	var dark: float = t.get("dark", 0.0)
	var bright: float = t.get("bright", 0.0)
	var keep_a: bool = t.get("alpha", false)
	if hue == null and sat == 0.0 and dark == 0.0 and bright == 0.0:
		return null
	var key := "%s|%s|%s|%s|%s|%s" % [name, hue, sat, dark, bright, keep_a]
	if false:
		pass
	var f: Array = G.frames.get(name, [])
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
	return img
	



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



func _blend_hue(base: Color, tint: Color) -> Color:
	var mx := maxf(base.r, maxf(base.g, base.b))
	var mn := minf(base.r, minf(base.g, base.b))
	return _set_lum(_set_sat(tint, mx - mn), _lum(base))



func cpu_white(name: String) -> Image:
	if false:
		pass
	var f: Array = G.frames.get(name, [])
	if f.is_empty():
		return null
	var img := _region_image(f)
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img
	

