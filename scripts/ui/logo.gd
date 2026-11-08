class_name Logo
extends Control
## Логотип главного меню, нарисованный кодом: «SPACE» — серебро, «SHOOTER» — голубой металл, тёмная обводка
## и свечение, крылья-полосы по бокам, золотая плашка «GODOT EDITION», раз в несколько секунд по буквам
## пробегает блик. Шейдер букв — assets/shaders/logo_text.gdshader.

const SHADER := preload("res://assets/shaders/logo_text.gdshader")
const SHINE_EVERY := 4.5

var _lines: Array = []    # {back, front: Label, mat: ShaderMaterial, y, size, tw}
var _plaque: PanelContainer
var _t := 1.5
var k := 1.0              # масштаб (карточка «Поделиться» — крупнее): шрифты растут, а не растягиваются


func _init(scale_k := 1.0) -> void:
	k = scale_k
	custom_minimum_size = Vector2(340, 124) * k
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add_line("SPACE", int(52 * k), Color.WHITE, Color("#c9d9ff"), Color("#6b8fe8"), 0.0)
	_add_line("SHOOTER", int(31 * k), Color("#c8fbff"), Color("#3de0ff"), Color("#1a7fd6"), 56.0 * k)
	_plaque = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.05, 0.01, 0.92)
	sb.border_color = Kit.GOLD
	sb.set_border_width_all(int(round(2 * k)))
	sb.set_corner_radius_all(int(5 * k))
	sb.content_margin_left = 12 * k
	sb.content_margin_right = 12 * k
	sb.content_margin_top = 1 * k
	sb.content_margin_bottom = 2 * k
	sb.shadow_color = Color(1.0, 0.78, 0.24, 0.3)
	sb.shadow_size = int(6 * k)
	_plaque.add_theme_stylebox_override("panel", sb)
	_plaque.add_child(Kit.label("GODOT EDITION", int(12 * k), Kit.GOLD, 900, HORIZONTAL_ALIGNMENT_CENTER))
	_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plaque)


func _add_line(text: String, size: int, top: Color, mid: Color, bot: Color, y: float) -> void:
	# сзади — та же надпись с толстой тёмной обводкой и мягким свечением, спереди — металл
	var back := Kit.label(text, size, Color("#0b1640"), 900, HORIZONTAL_ALIGNMENT_CENTER)
	back.add_theme_constant_override("outline_size", maxi(6, size / 5))
	back.add_theme_color_override("font_outline_color", Color("#0b1640"))
	back.add_theme_color_override("font_shadow_color", Color(mid, 0.45))
	back.add_theme_constant_override("shadow_offset_x", 0)
	back.add_theme_constant_override("shadow_offset_y", 3)
	back.add_theme_constant_override("shadow_outline_size", maxi(10, size / 3))
	var front := Kit.label(text, size, Color.WHITE, 900, HORIZONTAL_ALIGNMENT_CENTER)
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("c_top", top)
	mat.set_shader_parameter("c_mid", mid)
	mat.set_shader_parameter("c_bot", bot)
	front.material = mat
	for l: Label in [back, front]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	_lines.append({"back": back, "front": front, "mat": mat, "y": y, "size": size, "tw": 200.0})


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_READY: _layout()


func _layout() -> void:
	for ln: Dictionary in _lines:
		var fs: int = ln.size
		var lh: float = fs * 1.3
		for l: Label in [ln.back, ln.front]:
			l.position = Vector2(0, ln.y)
			l.size = Vector2(size.x, lh)
		var f: Font = ln.front.get_theme_font("font")
		ln.tw = f.get_string_size(ln.front.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# заглавные буквы: от линии заглавных до базовой (Label центрирует строку по высоте)
		var base := (lh - f.get_height(fs)) / 2.0 + f.get_ascent(fs)
		ln.mat.set_shader_parameter("y0", base - fs * 0.72)
		ln.mat.set_shader_parameter("h", fs * 0.72)
		ln.mat.set_shader_parameter("w", size.x)
	var ps := _plaque.get_combined_minimum_size()
	_plaque.size = ps
	_plaque.position = Vector2((size.x - ps.x) / 2.0, 100 * k)
	queue_redraw()


func _process(dt: float) -> void:
	if not is_visible_in_tree(): return
	_t += dt
	var k := fmod(_t, SHINE_EVERY) / 0.9   # блик бежит 0.9 с, потом пауза
	for i in _lines.size():
		var kk := k - i * 0.12
		_lines[i].mat.set_shader_parameter("shine", kk if kk >= 0.0 and kk <= 1.0 else -1.0)
	queue_redraw()


## крылья: по три скошенные полосы с каждой стороны строки «SHOOTER» и светящаяся линия под ней
func _draw() -> void:
	if _lines.size() < 2: return
	var cx := size.x / 2.0
	var ln: Dictionary = _lines[1]
	var half: float = ln.tw / 2.0 + 12.0 * k
	var cy: float = ln.y + ln.size * 0.66
	var pulse := 0.85 + 0.15 * sin(_t * 2.2)
	for side: float in [-1.0, 1.0]:
		for i in 3:
			var x0: float = cx + side * (half + i * 8.0 * k)
			var len := (60.0 - i * 15.0) * k
			var y := cy + (-12.0 + i * 9.0) * k
			var th := (5.0 - i) * k
			var x1: float = x0 + side * len
			var pts := PackedVector2Array([Vector2(x0, y), Vector2(x1 + side * 7.0 * k, y), Vector2(x1, y + th), Vector2(x0 - side * 4.0 * k, y + th)])
			var c0 := Color(0.24, 0.88, 1.0, 0.95 * pulse)
			var c1 := Color(0.24, 0.55, 1.0, 0.0)
			draw_polygon(pts, PackedColorArray([c0, c1, c1, c0]))
	# линия-горизонт под «SHOOTER»: ярче в центре, гаснет к краям
	var ly: float = ln.y + ln.size * 1.22
	for j in 2:
		var a := 0.6 if j == 0 else 0.2
		var wv := (140.0 + j * 40.0) * k
		var y2 := ly + j * 2.5 * k
		draw_polygon(PackedVector2Array([Vector2(cx - wv, y2), Vector2(cx, y2 - 0.75 * k), Vector2(cx + wv, y2), Vector2(cx, y2 + 0.75 * k)]),
			PackedColorArray([Color(0.24, 0.88, 1.0, 0.0), Color(0.6, 0.97, 1.0, a), Color(0.24, 0.88, 1.0, 0.0), Color(0.6, 0.97, 1.0, a)]))
