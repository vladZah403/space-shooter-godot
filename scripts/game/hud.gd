extends Node
## Боевой интерфейс (автозагрузка Hud): отступы под верхнюю и нижнюю панели (ui.topInset/bottomInset в JS)
## и значки-шестиугольники бонусов без своего спрайта (бомба, магнит, заморозка — PROC pu_* в gfx.js).
## Сами панели HUD (очки, жизни, полоса босса, оружие, навыки) — scripts/ui/hud_view.gd.

var view = null           # HudView, когда интерфейс построен
var _safe_top := 0.0
var _safe_bottom := 0.0


func _ready() -> void:
	get_viewport().size_changed.connect(_safe)
	_safe()


## вырез экрана и системные полосы телефона в координатах игры
func _safe() -> void:
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var vis := get_viewport().get_visible_rect().size
	if win.y <= 0 or safe.size.y <= 0:
		_safe_top = 0.0; _safe_bottom = 0.0
		return
	var k := vis.y / float(win.y)
	_safe_top = maxf(0.0, safe.position.y * k)
	_safe_bottom = maxf(0.0, (win.y - safe.end.y) * k)


func safe_top() -> float:
	return _safe_top


func safe_bottom() -> float:
	return _safe_bottom


## нижний край верхней панели HUD (с местом под полосу босса)
func top_inset() -> float:
	if view and view.visible: return view.top_inset()
	return _safe_top + 122.0


func bottom_inset() -> float:
	if view and view.visible: return view.bottom_inset()
	return 84.0 + _safe_bottom


## шестиугольный значок бонуса: тёмный корпус с градиентом, обводка цвета бонуса, рисунок по def.ico
func drawBadge(ctx: Ctx, def: Dictionary, x: float, y: float, s: float) -> void:
	var col: String = def.color
	var hexp := func(k: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 6:
			var a := PI / 6 + i * PI / 3
			pts.append(Vector2(x + cos(a) * s * 0.44 * k, y + sin(a) * s * 0.44 * k))
		return pts
	var pts: PackedVector2Array = hexp.call(1.0)
	ctx.save()
	# свечение вместо shadowBlur
	ctx.additive = true
	var a0 := ctx.alpha
	ctx.alpha = a0 * 0.5
	ctx.draw_tex(G.soft(col, 64), x - s * 0.62, y - s * 0.62, s * 1.24, s * 1.24)
	ctx.additive = false
	ctx.alpha = a0
	var cols := PackedColorArray()
	for p in pts: cols.append(U.col("#2a3046").lerp(U.col("#0d1020"), (p.y - (y - s * 0.44)) / (s * 0.88)))
	ctx.fill_poly(pts, cols)
	ctx.stroke = U.col(col); ctx.line_width = s * 0.06
	ctx.begin_path()
	for i in 6:
		if i: ctx.line_to(pts[i].x, pts[i].y)
		else: ctx.move_to(pts[i].x, pts[i].y)
	ctx.close_path(); ctx.stroke_path()
	var inner: PackedVector2Array = hexp.call(0.82)
	ctx.stroke = Color(1, 1, 1, 0.14); ctx.line_width = 2 * s / 80.0
	ctx.begin_path()
	for i in 6:
		if i: ctx.line_to(inner[i].x, inner[i].y)
		else: ctx.move_to(inner[i].x, inner[i].y)
	ctx.close_path(); ctx.stroke_path()
	# рисунок: координаты как в JS — доли стороны квадрата s от его левого верхнего угла
	var L := x - s / 2
	var T := y - s / 2
	match def.get("ico", ""):
		"bomb":
			ctx.fill = U.col("#2b2f3a"); ctx.fill_circle(L + s * 0.47, T + s * 0.55, s * 0.19)
			ctx.stroke = U.col("#ff8a3d"); ctx.line_width = s * 0.05
			ctx.begin_path(); ctx.move_to(L + s * 0.58, T + s * 0.4); ctx.quadratic_curve_to(L + s * 0.66, T + s * 0.26, L + s * 0.74, T + s * 0.3); ctx.stroke_path()
			ctx.fill = U.col("#ffe07a"); ctx.fill_circle(L + s * 0.75, T + s * 0.29, s * 0.05)
			ctx.fill = Color(1, 1, 1, 0.35); ctx.fill_circle(L + s * 0.41, T + s * 0.49, s * 0.05)
		"magnet":
			ctx.line_width = s * 0.12; ctx.stroke = U.col("#ff5cb3")
			ctx.begin_path(); ctx.arc(L + s / 2, T + s * 0.5, s * 0.17, PI, 0, true); ctx.stroke_path()
			ctx.stroke = U.col("#e6ecff")
			ctx.stroke_line(L + s * 0.33, T + s * 0.32, L + s * 0.33, T + s * 0.4)
			ctx.stroke_line(L + s * 0.67, T + s * 0.32, L + s * 0.67, T + s * 0.4)
		"snow":
			ctx.stroke = U.col("#d9f6ff"); ctx.line_width = s * 0.05
			for i in 3:
				var a := i * PI / 3
				ctx.stroke_line(L + s / 2 + cos(a) * s * 0.22, T + s / 2 + sin(a) * s * 0.22, L + s / 2 - cos(a) * s * 0.22, T + s / 2 - sin(a) * s * 0.22)
			ctx.fill = U.col("#9be8ff"); ctx.fill_circle(L + s / 2, T + s / 2, s * 0.06)
	ctx.restore()
