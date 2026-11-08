class_name NeoBox
extends StyleBox
## Рамка интерфейса в духе концепта меню Влада: срезанные углы, заливка светлее сверху, блик по верхней кромке,
## неоновая кромка, яркие уголки-скобы и мягкое свечение наружу. Рисуется векторно (RenderingServer), поэтому
## чёткая на любом экране — на айфоне интерфейс увеличен втрое. Создаётся через Kit.neo().

var bg := Color(0.05, 0.08, 0.2, 0.85)
var edge := Color(0.5, 0.7, 1.0, 0.3)
var accent := Color(0, 0, 0, 0)   # уголки-скобы; прозрачный — без них
var cut := 10.0                   # срез углов, px
var bw := 1.0                     # толщина кромки
var glow := 0.0                   # свечение наружу 0…1
var sheen := 0.07                 # блик сверху 0…1
var notch := false                # риски по центру боковых кромок (крупные панели)


func _draw(ci: RID, r: Rect2) -> void:
	if r.size.x < 4 or r.size.y < 4: return
	var c := minf(cut, minf(r.size.x, r.size.y) * 0.32)
	# свечение: расходящиеся контуры с убывающей прозрачностью
	if glow > 0.0:
		for i in 3:
			var col := Color(accent if accent.a > 0 else edge, glow * (0.3 - i * 0.08))
			RenderingServer.canvas_item_add_polyline(ci, _closed(_oct(r.grow(1.5 + i * 2.0), c + 0.7 + i * 0.8)), PackedColorArray([col]), 2.0, true)
	# заливка с вертикальным переходом
	if bg.a > 0.0:
		var pts := _oct(r, c)
		var top := bg.lightened(0.12)
		top.a = bg.a
		var bot := bg.darkened(0.18)
		bot.a = bg.a
		var cols := PackedColorArray()
		for p in pts: cols.append(top.lerp(bot, clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
		RenderingServer.canvas_item_add_polygon(ci, pts, cols)
		# блик: светлая полоса у верхней кромки, к середине сходит на нет
		if sheen > 0.0:
			var hy := r.position.y + minf(r.size.y * 0.45, 22.0)
			var x0 := r.position.x
			var x1 := r.end.x
			var y0 := r.position.y
			var a := Color(1, 1, 1, sheen)
			var z := Color(1, 1, 1, 0)
			var sp := PackedVector2Array([Vector2(x0 + c, y0 + 1), Vector2(x1 - c, y0 + 1), Vector2(x1 - 1, y0 + c), Vector2(x1 - 1, hy), Vector2(x0 + 1, hy), Vector2(x0 + 1, y0 + c)])
			if hy > y0 + c + 1:
				RenderingServer.canvas_item_add_polygon(ci, sp, PackedColorArray([a, a, a, z, z, a]))
	# кромка
	if edge.a > 0.0 and bw > 0.0:
		var h := bw * 0.5
		RenderingServer.canvas_item_add_polyline(ci, _closed(_oct(r.grow(-h), maxf(1.0, c - h * 0.4))), PackedColorArray([edge]), bw, true)
	# уголки-скобы вдоль срезов
	if accent.a > 0.0:
		var L := minf(14.0, minf(r.size.x, r.size.y) * 0.22)
		var w := maxf(1.6, bw + 0.8)
		var g := r.grow(-w * 0.5)
		var x0 := g.position.x
		var y0 := g.position.y
		var x1 := g.end.x
		var y1 := g.end.y
		var cc := PackedColorArray([accent])
		for q in [
			[Vector2(x0, y0 + c + L), Vector2(x0, y0 + c), Vector2(x0 + c, y0), Vector2(x0 + c + L, y0)],
			[Vector2(x1 - c - L, y0), Vector2(x1 - c, y0), Vector2(x1, y0 + c), Vector2(x1, y0 + c + L)],
			[Vector2(x1, y1 - c - L), Vector2(x1, y1 - c), Vector2(x1 - c, y1), Vector2(x1 - c - L, y1)],
			[Vector2(x0 + c + L, y1), Vector2(x0 + c, y1), Vector2(x0, y1 - c), Vector2(x0, y1 - c - L)]]:
			RenderingServer.canvas_item_add_polyline(ci, PackedVector2Array(q), cc, w, true)
		if notch and r.size.y > 56:
			var my := r.position.y + r.size.y * 0.5
			for x in [r.position.x - 1.0, r.end.x - 2.0]:
				RenderingServer.canvas_item_add_rect(ci, Rect2(x, my - 7, 3, 14), accent)


func _closed(p: PackedVector2Array) -> PackedVector2Array:
	var q := p.duplicate()
	q.append(p[0])
	return q


## восьмиугольник прямоугольника со срезанными углами (по часовой, от верхнего левого среза)
func _oct(r: Rect2, c: float) -> PackedVector2Array:
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	return PackedVector2Array([Vector2(x0 + c, y0), Vector2(x1 - c, y0), Vector2(x1, y0 + c), Vector2(x1, y1 - c),
		Vector2(x1 - c, y1), Vector2(x0 + c, y1), Vector2(x0, y1 - c), Vector2(x0, y0 + c)])
