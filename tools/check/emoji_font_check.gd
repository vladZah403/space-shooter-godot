extends Node
## Проверка WebEmoji.make_font без браузера: из картинок (красный круг, зелёный квадрат) собирается цветной
## шрифт CBDT; надписи тёмным и белым цветом с этими «эмодзи» снимаются с экрана, и проверяется, что красный
## и зелёный остались своими (Godot не умножил их на цвет надписи) и что ширина символа как задана.
## Запуск с окном (без --headless, нужен настоящий рендер):
##   Godot_console.exe --path . --resolution 390x844 res://tools/check/emoji_font_check.tscn [-- --shot=ФАЙЛ.png]

const PX := 48
const CW := 60
const CH := 70
const PAD := 6
const BY := 50


func _ready() -> void:
	var atlas := Image.create_empty(CW * 2, CH, false, Image.FORMAT_RGBA8)
	for y in CH:
		for x in CW:
			var d := Vector2(x - (PAD + 22), y - (BY - 22)).length()
			if d < 20: atlas.set_pixel(x, y, Color(1, 0, 0) if d > 8 else Color(0, 0, 1))
			if x >= PAD + 4 and x < PAD + 40 and y >= BY - 40 and y < BY - 4: atlas.set_pixel(CW + x, y, Color(0, 1, 0))
	var glyphs := [{"cp": 0x2B50, "adv": 44.0, "x": CW, "y": 0}, {"cp": 0x1F680, "adv": 46.0, "x": 0, "y": 0}]
	var font := WebEmoji.make_font(atlas, glyphs, PX, CW, CH, PAD, BY)
	var ok := true
	print("шрифт: «", font.get_font_name(), "», 🚀 есть: ", font.has_char(0x1F680), ", ⭐ есть: ", font.has_char(0x2B50),
		", ширина 🚀 при 48: ", font.get_char_size(0x1F680, 48), ", при 24: ", font.get_char_size(0x1F680, 24))
	if not font.has_char(0x1F680) or absf(font.get_char_size(0x1F680, 48).x - 46) > 1: ok = false
	var main: Font = Kit.font(800).duplicate()
	main.fallbacks = [font]
	var bg := ColorRect.new(); bg.color = Color("#3fb0ff"); bg.size = Vector2(390, 300); add_child(bg)
	var rows := [[Color("#04122b"), 20.0], [Color.WHITE, 120.0]]
	for r in rows:
		var l := Label.new()
		l.text = "A🚀B⭐️C"
		l.add_theme_font_override("font", main)
		l.add_theme_font_size_override("font_size", 40)
		l.add_theme_color_override("font_color", r[0])
		l.position = Vector2(20, r[1])
		add_child(l)
	for i in 6: await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): img.save_png(a.substr(7))
	# окно может быть меньше логических 390×844 (stretch) — переводим координаты надписи в пиксели снимка
	var k := img.get_height() / get_viewport().get_visible_rect().size.y
	for r in rows:
		var red := 0
		var green := 0
		for y in range(int(r[1] * k), mini(img.get_height(), int((r[1] + 70) * k))):
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.r > 0.8 and c.g < 0.25 and c.b < 0.25: red += 1
				if c.g > 0.8 and c.r < 0.25 and c.b < 0.4: green += 1
		print("надпись цвета ", r[0].to_html(false), ": красных пикселей ", red, ", зелёных ", green)
		if red < 20 or green < 20: ok = false
	print("ИТОГ: ", "ок" if ok else "ПРОБЛЕМА")
	get_tree().quit(0 if ok else 1)
