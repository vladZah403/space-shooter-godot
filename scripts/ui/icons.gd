class_name Icons
## Векторные значки из JS-версии (index.html, <symbol> в поле 24×24): ангар, арсенал, импланты, назад, пауза…
## Рисуются из SVG прямо в игре в нужном цвете (currentColor → цвет) и с запасом по чёткости под экран:
## на айфоне интерфейс увеличен почти втрое, поэтому картинка — px × масштаб окна. Данные — data/icons.json
## (собирает tools/svg_icons.py).

const LIST := "res://data/icons.json"

static var _svg := {}
static var _cache := {}


## текстура значка; null — нет такого значка
static func tex(id: String, col := Kit.TEXT, px := 24) -> Texture2D:
	if _svg.is_empty(): _load()
	var body: String = _svg.get(id, "")
	if body == "": return null
	var k := _scale()
	var hex := "#" + col.to_html(false)
	var key := "%s|%s|%d|%.1f" % [id, hex, px, k]
	if _cache.has(key): return _cache[key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24">%s</svg>' % body.replace("currentColor", hex)
	var img := Image.new()
	if img.load_svg_from_string(svg, px * k / 24.0) != OK: return null
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


## значок как элемент интерфейса: сторона px логических пикселей, полупрозрачность — через alpha цвета
static func rect(id: String, col := Kit.TEXT, px := 24) -> TextureRect:
	var r := Kit.tex_icon(tex(id, col, px), px)
	if col.a < 1.0: r.modulate.a = col.a
	return r


## сколько пикселей экрана в одном логическом (stretch canvas_items): 1 на компьютере, ~3 на айфоне
static func _scale() -> float:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null: return 2.0
	var vis := tree.root.get_visible_rect().size
	if vis.x <= 0: return 2.0
	return clampf(snappedf(float(tree.root.size.x) / vis.x, 0.5), 1.0, 4.0)


static func _load() -> void:
	var f := FileAccess.open(LIST, FileAccess.READ)
	if f == null: return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary: _svg = d
