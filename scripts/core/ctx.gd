class_name Ctx
extends RefCounted
## Немедленная отрисовка в духе Canvas 2D поверх RenderingServer — чтобы код отрисовки из JS-версии
## переносился почти строка в строку: alpha (globalAlpha), additive (режим 'lighter'), save/restore,
## translate/rotate/scale, draw_image, fill_rect, пути (move_to/line_to/arc) с stroke/fill, текст.
## Каждый кадр: begin() — затем команды. При смене режима смешивания начинается новый холст-слой,
## поэтому порядок наложения сохраняется как в браузере.
## clip_rect — обрезка по прямоугольнику (ctx.rect + ctx.clip в JS), действует до restore().
## embed(rid) — вставить в этот же порядок рисования чужой холст (узел-ребёнок того же родителя, например
## частицы Godot): он встанет между уже нарисованным и следующими командами.

var alpha := 1.0
var additive := false
var fill := Color.WHITE
var stroke := Color.WHITE
var line_width := 1.0
var font: Font
var font_size := 16
var dash: PackedFloat32Array = PackedFloat32Array()
## свой материал (шейдер) для следующих команд; null — обычный/аддитивный режим. Сохраняется в save/restore
var material: Material = null

var _parent: RID
var _mat_add: Material
var _items: Array = []      # [{ rid, add, mat, clip, xf }]
var _idx := -1
var _xf := Transform2D.IDENTITY
var _stack: Array = []
var _subpaths: Array = []   # Array[PackedVector2Array]
var _closed: Array = []
var _clip = null            # Rect2 в координатах холста или null
var _break := false         # после embed следующая команда начинает новый слой (поверх встроенного)
static var _white_tex: Texture2D


func _init(parent_canvas_item: RID) -> void:
	_parent = parent_canvas_item
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_mat_add = m
	font = ThemeDB.fallback_font


func free_items() -> void:
	for it in _items:
		RenderingServer.free_rid(it.rid)
	_items.clear()


## слои рисования — RID сервера, сами не освобождаются: отдаём их, когда Ctx больше не нужен
## (закрытые превью в меню, выход из игры), иначе каждое перестроение экрана копит «висящие» холсты
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# методы самого объекта здесь уже не вызвать — освобождаем напрямую
		for it in _items: RenderingServer.free_rid(it.rid)


## начало кадра: стереть всё нарисованное в прошлом кадре
func begin() -> void:
	for it in _items:
		RenderingServer.canvas_item_clear(it.rid)
		it.xf = Transform2D.IDENTITY
	_idx = -1
	alpha = 1.0
	additive = false
	_xf = Transform2D.IDENTITY
	_stack.clear()
	_clip = null
	material = null
	dash = PackedFloat32Array()
	_break = false


func _item() -> RID:
	if _idx < 0 or _break or _items[_idx].add != additive or _items[_idx].mat != material or _items[_idx].clip != _clip:
		_break = false
		_idx += 1
		if _idx >= _items.size():
			var rid := RenderingServer.canvas_item_create()
			RenderingServer.canvas_item_set_parent(rid, _parent)
			_items.append({"rid": rid, "add": false, "mat": null, "clip": null, "xf": Transform2D.IDENTITY})
		var it: Dictionary = _items[_idx]
		it.add = additive
		it.mat = material
		RenderingServer.canvas_item_set_material(it.rid, material.get_rid() if material != null else (_mat_add.get_rid() if additive else RID()))
		RenderingServer.canvas_item_set_draw_index(it.rid, _idx * 2)   # нечётные индексы — для embed
		if it.clip != _clip:
			it.clip = _clip
			RenderingServer.canvas_item_set_clip(it.rid, _clip != null)
			RenderingServer.canvas_item_set_custom_rect(it.rid, _clip != null, _clip if _clip != null else Rect2())
	var cur: Dictionary = _items[_idx]
	if cur.xf != _xf:
		RenderingServer.canvas_item_add_set_transform(cur.rid, _xf)
		cur.xf = _xf
	return cur.rid


## встроить холст rid (ребёнок того же родительского холста) в текущее место порядка рисования
func embed(rid: RID) -> void:
	RenderingServer.canvas_item_set_draw_index(rid, _idx * 2 + 1)
	_break = true


# ── состояние ──
func save() -> void:
	_stack.push_back([_xf, alpha, additive, fill, stroke, line_width, dash, _clip, material])


func restore() -> void:
	if _stack.is_empty():
		return
	var s: Array = _stack.pop_back()
	_xf = s[0]; alpha = s[1]; additive = s[2]; fill = s[3]; stroke = s[4]; line_width = s[5]; dash = s[6]; _clip = s[7]; material = s[8]


## обрезка по прямоугольнику в текущих координатах (с поворотом — по охватывающему прямоугольнику);
## вложенные обрезки пересекаются
func clip_rect(x: float, y: float, w: float, h: float) -> void:
	var r: Rect2 = _xf * Rect2(x, y, w, h)
	_clip = r if _clip == null else (_clip as Rect2).intersection(r)


func translate(x: float, y: float) -> void:
	_xf = _xf.translated_local(Vector2(x, y))


func rotate(a: float) -> void:
	_xf = _xf * Transform2D(a, Vector2.ZERO)


func scale(sx: float, sy: float) -> void:
	_xf = _xf.scaled_local(Vector2(sx, sy))


func set_transform(xf: Transform2D) -> void:
	_xf = xf


func reset_transform() -> void:
	_xf = Transform2D.IDENTITY


func _mod(c: Color) -> Color:
	return Color(c.r, c.g, c.b, c.a * alpha)


# ── картинки ──
## кусок текстуры (sx, sy, sw, sh) в прямоугольник (dx, dy, dw, dh)
func draw_image(tex: Texture2D, sx: float, sy: float, sw: float, sh: float, dx: float, dy: float, dw: float, dh: float, tint := Color.WHITE) -> void:
	if tex == null or alpha <= 0.0:
		return
	RenderingServer.canvas_item_add_texture_rect_region(_item(), Rect2(dx, dy, dw, dh), tex.get_rid(), Rect2(sx, sy, sw, sh), _mod(tint))


## прямоугольник, закрашенный шейдером mat (UV 0..1 по прямоугольнику, COLOR — белый с alpha)
func shader_rect(mat: Material, x: float, y: float, w: float, h: float) -> void:
	if alpha <= 0.0:
		return
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	var old := material
	material = mat
	RenderingServer.canvas_item_add_texture_rect(_item(), Rect2(x, y, w, h), _white_tex.get_rid(), false, _mod(Color.WHITE))
	material = old


## вся текстура в прямоугольник
func draw_tex(tex: Texture2D, dx: float, dy: float, dw: float, dh: float, tint := Color.WHITE) -> void:
	if tex == null or alpha <= 0.0:
		return
	RenderingServer.canvas_item_add_texture_rect(_item(), Rect2(dx, dy, dw, dh), tex.get_rid(), false, _mod(tint))


func fill_rect(x: float, y: float, w: float, h: float) -> void:
	if alpha <= 0.0:
		return
	RenderingServer.canvas_item_add_rect(_item(), Rect2(x, y, w, h), _mod(fill))


func fill_circle(x: float, y: float, r: float) -> void:
	if alpha <= 0.0 or r <= 0.0:
		return
	RenderingServer.canvas_item_add_circle(_item(), Vector2(x, y), r, _mod(fill))


# ── пути ──
func begin_path() -> void:
	_subpaths.clear()
	_closed.clear()


func move_to(x: float, y: float) -> void:
	_subpaths.append(PackedVector2Array([Vector2(x, y)]))
	_closed.append(false)


func line_to(x: float, y: float) -> void:
	if _subpaths.is_empty():
		move_to(x, y)
		return
	_subpaths[-1].append(Vector2(x, y))


func close_path() -> void:
	if not _closed.is_empty():
		_closed[-1] = true


## дуга окружности, как ctx.arc (углы в радианах; ccw — против часовой)
func arc(cx: float, cy: float, r: float, a0: float, a1: float, ccw := false) -> void:
	ellipse(cx, cy, r, r, 0.0, a0, a1, ccw)


func ellipse(cx: float, cy: float, rx: float, ry: float, rot: float, a0: float, a1: float, ccw := false) -> void:
	var span := a1 - a0
	if not ccw and span < 0.0:
		span = fmod(span, TAU) + TAU
	elif ccw and span > 0.0:
		span = fmod(span, TAU) - TAU
	if absf(span) >= TAU - 0.0001:
		span = -TAU if ccw else TAU
	var n := clampi(int(absf(span) * maxf(rx, ry) / 4.0), 8, 64)
	var cr := cos(rot)
	var sr := sin(rot)
	for i in n + 1:
		var a := a0 + span * i / n
		var px := cos(a) * rx
		var py := sin(a) * ry
		var p := Vector2(cx + px * cr - py * sr, cy + px * sr + py * cr)
		if i == 0:
			if _subpaths.is_empty():
				move_to(p.x, p.y)
			else:
				line_to(p.x, p.y)
		else:
			line_to(p.x, p.y)


func quadratic_curve_to(cpx: float, cpy: float, x: float, y: float) -> void:
	if _subpaths.is_empty():
		move_to(cpx, cpy)
	var p0: Vector2 = _subpaths[-1][-1]
	for i in range(1, 11):
		var t := i / 10.0
		var q := p0.lerp(Vector2(cpx, cpy), t).lerp(Vector2(cpx, cpy).lerp(Vector2(x, y), t), t)
		line_to(q.x, q.y)


## прямоугольник со скруглёнными углами (ctx.roundRect)
func round_rect(x: float, y: float, w: float, h: float, r: float) -> void:
	r = minf(r, minf(w, h) / 2.0)
	move_to(x + r, y)
	line_to(x + w - r, y)
	arc(x + w - r, y + r, r, -PI / 2, 0)
	line_to(x + w, y + h - r)
	arc(x + w - r, y + h - r, r, 0, PI / 2)
	line_to(x + r, y + h)
	arc(x + r, y + h - r, r, PI / 2, PI)
	line_to(x, y + r)
	arc(x + r, y + r, r, PI, PI * 1.5)
	close_path()


func rect(x: float, y: float, w: float, h: float) -> void:
	move_to(x, y)
	line_to(x + w, y)
	line_to(x + w, y + h)
	line_to(x, y + h)
	close_path()


func stroke_path() -> void:
	if alpha <= 0.0:
		return
	var item := _item()
	var c := _mod(stroke)
	for i in _subpaths.size():
		var pts: PackedVector2Array = _subpaths[i]
		if _closed[i] and pts.size() > 2:
			pts = pts.duplicate()
			pts.append(pts[0])
		if pts.size() < 2:
			continue
		if dash.size() >= 2:
			_dashed(item, pts, c)
		else:
			RenderingServer.canvas_item_add_polyline(item, pts, PackedColorArray([c]), line_width, true)


func _dashed(item: RID, pts: PackedVector2Array, c: Color) -> void:
	var on := true
	var di := 0
	var left := dash[0]
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var seg := a.distance_to(b)
		var pos := 0.0
		while pos < seg:
			var step := minf(left, seg - pos)
			if on:
				RenderingServer.canvas_item_add_line(item, a.lerp(b, pos / seg), a.lerp(b, (pos + step) / seg), c, line_width, true)
			pos += step
			left -= step
			if left <= 0.0001:
				on = not on
				di = (di + 1) % dash.size()
				left = dash[di]


func fill_path() -> void:
	if alpha <= 0.0:
		return
	var item := _item()
	var c := _mod(fill)
	for pts in _subpaths:
		if pts.size() < 3:
			continue
		var idx := Geometry2D.triangulate_polygon(pts)
		if idx.is_empty():
			continue
		var cols := PackedColorArray()
		cols.resize(pts.size())
		cols.fill(c)
		RenderingServer.canvas_item_add_triangle_array(item, idx, pts, cols)


## многоугольник с цветом в каждой вершине — цвета плавно смешиваются (замена радиальному градиенту:
## веер треугольников «центр → край» с прозрачным краем)
func fill_poly(pts: PackedVector2Array, cols: PackedColorArray) -> void:
	if alpha <= 0.0 or pts.size() < 3:
		return
	var c := PackedColorArray()
	c.resize(cols.size())
	for i in cols.size():
		c[i] = _mod(cols[i])
	RenderingServer.canvas_item_add_polygon(_item(), pts, c)


func stroke_line(x0: float, y0: float, x1: float, y1: float) -> void:
	if alpha <= 0.0:
		return
	RenderingServer.canvas_item_add_line(_item(), Vector2(x0, y0), Vector2(x1, y1), _mod(stroke), line_width, true)


# ── текст ──
## align: 0 — слева, 1 — по центру, 2 — справа; y — базовая линия, как в canvas с textBaseline 'alphabetic'
func fill_text(text: String, x: float, y: float, size := -1, align := 1, outline := 0, outline_color := Color(0, 0, 0, 0.8)) -> void:
	if alpha <= 0.0 or text == "":
		return
	text = Lang.t(text)
	var fs := font_size if size < 0 else size
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var px := x - (w / 2.0 if align == 1 else (w if align == 2 else 0.0))
	var item := _item()
	if outline > 0:
		font.draw_string_outline(item, Vector2(px, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, _mod(outline_color))
	font.draw_string(item, Vector2(px, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _mod(fill))


func text_width(text: String, size := -1) -> float:
	return font.get_string_size(Lang.t(text), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size if size < 0 else size).x
