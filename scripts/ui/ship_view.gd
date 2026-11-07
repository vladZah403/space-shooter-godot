extends Control
## Схема корабля (3.1, перенос ui.showShip): модули забега по отсекам на разрезе корабля
## (assets/ship_cutaway.webp из tools/make_cutaway.py JS-версии). Отсеки — прямоугольники [x0, y0, x1, y1]
## в долях картинки (нос вверху). Предложенные сейчас модули — их отсеки мигают.

const SHIP_ROOMS := [
	{"id": "bridge", "name": "МОСТИК", "ico": "🎖️", "mods": [], "rects": [[0.31, 0.112, 0.73, 0.18]]},
	{"id": "armor", "name": "БРОНЯ", "ico": "🧱", "mods": ["plating"], "rects": [[0.31, 0.075, 0.73, 0.11]]},
	{"id": "sensors", "name": "СЕНСОРЫ", "ico": "📡", "mods": ["targeting", "scanner"], "rects": [[0.16, 0.158, 0.37, 0.237], [0.68, 0.158, 0.87, 0.237]]},
	{"id": "cargo", "name": "ТРЮМ", "ico": "📦", "mods": ["salvage", "bombbay"], "rects": [[0.37, 0.181, 0.68, 0.405]]},
	{"id": "guns", "name": "ОРУЖИЕ", "ico": "🔫", "mods": ["power", "wings", "hunter"], "rects": [[0.15, 0.24, 0.37, 0.526], [0.68, 0.24, 0.89, 0.526]]},
	{"id": "shields", "name": "ЩИТЫ", "ico": "🔰", "mods": ["shieldcore", "emergency"], "rects": [[0.4, 0.405, 0.667, 0.563]]},
	{"id": "reactor", "name": "РЕАКТОР", "ico": "⚛️", "mods": ["cooling", "chrono"], "rects": [[0.267, 0.563, 0.8, 0.735]]},
	{"id": "life", "name": "РЕМОНТ", "ico": "🩺", "mods": ["repair"], "rects": [[0.06, 0.567, 0.253, 0.693], [0.76, 0.567, 0.97, 0.693]]},
	{"id": "engines", "name": "ДВИГАТЕЛИ", "ico": "🔥", "mods": ["gyro"], "rects": [[0.253, 0.744, 0.827, 0.98]]},
]

var tex: Texture2D
var fig: Control
var info: VBoxContainer
var offer: Array = []
var sel := ""
var _t := 0.0


func _ready() -> void:
	Kit.full(self)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	tex = load("res://assets/ship_cutaway.webp")
	add_child(Kit.dim(0.9))
	var m := Kit.margin(14, 14, 14, 14)
	Kit.full(m)
	add_child(m)
	var v := Kit.vbox(8)
	m.add_child(v)
	var head := Kit.hbox(8)
	var tl := Kit.label("КОРАБЛЬ · МОДУЛИ", 18, Kit.TEXT, 900)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	head.add_child(Kit.icon_button("close", "", func(): close(), "ghost", "sm"))
	v.add_child(head)
	var h := Kit.hbox(10)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fig = Kit.ctx_view(_draw_fig, Vector2(150, 0))
	fig.mouse_filter = Control.MOUSE_FILTER_STOP
	fig.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fig.size_flags_stretch_ratio = 0.9
	fig.gui_input.connect(_on_fig)
	h.add_child(fig)
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info = Kit.vbox(6)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(info)
	h.add_child(sc)
	v.add_child(h)


## offer — модули, которые сейчас предлагают на выбор (их отсеки мигают)
func open(off: Array = []) -> void:
	offer = off
	var run: Dictionary = Game.run
	if run.is_empty(): return
	var pick := ""
	for r in SHIP_ROOMS:
		if not offer.is_empty() and r.mods.any(func(id): return id in offer):
			pick = r.id
			break
	if pick == "" and sel == "":
		for r in SHIP_ROOMS:
			if _lvl(r) > 0:
				pick = r.id
				break
	if pick != "": sel = pick
	if sel == "": sel = "bridge"
	_render()
	visible = true


func close() -> void:
	if visible: A.play("back")
	visible = false


func _lvl(r: Dictionary) -> int:
	var n := 0
	for id in r.mods: n += int(Game.run.mods.get(id, 0))
	return n


func _fig_rect() -> Rect2:
	var sz := fig.size
	var asp := float(tex.get_width()) / tex.get_height()
	var w := minf(sz.x, sz.y * asp)
	var h := w / asp
	return Rect2((sz.x - w) / 2, (sz.y - h) / 2, w, h)


func _draw_fig(c: Ctx, _sz: Vector2, t: float) -> void:
	_t = t
	var r := _fig_rect()
	c.draw_tex(tex, r.position.x, r.position.y, r.size.x, r.size.y)
	for room in SHIP_ROOMS:
		var on: bool = _lvl(room) > 0 or room.id == "bridge"
		var off: bool = not offer.is_empty() and room.mods.any(func(id): return id in offer)
		var is_sel: bool = room.id == sel
		for q in room.rects:
			var x: float = r.position.x + q[0] * r.size.x
			var y: float = r.position.y + q[1] * r.size.y
			var w: float = (q[2] - q[0]) * r.size.x
			var h: float = (q[3] - q[1]) * r.size.y
			var col := Kit.GOLD if off else (Kit.CYAN if on else Color(1, 1, 1, 0.3))
			c.alpha = (0.35 + 0.35 * absf(sin(t * 5))) if off else (0.22 if is_sel else (0.1 if on else 0.0))
			c.fill = col; c.fill_rect(x, y, w, h)
			c.alpha = 1.0 if is_sel else (0.7 if on or off else 0.25)
			c.stroke = Color.WHITE if is_sel else col; c.line_width = 2 if is_sel else 1
			c.begin_path(); c.rect(x, y, w, h); c.stroke_path()
	c.alpha = 1.0


func _on_fig(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT): return
	var r := _fig_rect()
	var p: Vector2 = (e.position - r.position) / r.size
	for room in SHIP_ROOMS:
		for q in room.rects:
			if p.x >= q[0] and p.x <= q[2] and p.y >= q[1] and p.y <= q[3]:
				sel = room.id
				A.play("click")
				_render()
				return


func _render() -> void:
	Kit.clear(info)
	var run: Dictionary = Game.run
	for room in SHIP_ROOMS:
		var n := _lvl(room)
		var on: bool = n > 0 or room.id == "bridge"
		var ico: String = D.PILOTS.get(run.pilot, D.PILOTS.kai).ico if room.id == "bridge" else room.ico
		var rid: String = room.id
		var b := Kit.button(ico + " " + room.name + ("  %d" % n if n else ""), func():
			sel = rid; A.play("click"); _render(), "primary" if room.id == sel else ("" if on else "ghost"), "sm")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		info.add_child(b)
		if room.id != sel: continue
		var box := Kit.vbox(4)
		if room.id == "bridge":
			var pil: Dictionary = D.PILOTS.get(run.pilot, D.PILOTS.kai)
			box.add_child(Kit.para(pil.ico + " " + pil.name + " · " + pil.title, 13, Kit.TEXT))
			box.add_child(Kit.para(pil.desc, 12))
			box.add_child(Kit.para("Улучшений в забеге: %d" % run.perks.size(), 12))
		else:
			for id in room.mods:
				var md = null
				for x in D.MODULES:
					if x.id == id: md = x
				if md == null: continue
				var lv: int = int(run.mods.get(id, 0))
				var off: bool = id in offer
				var txt: String = (md.name + (" %d/%d" % [lv, md.max] if md.max > 1 else "") + " — " + md.desc) if lv else (md.name + (" — предлагают сейчас" if off else " — свободно"))
				var row := Kit.hbox(6)
				row.add_child(Kit.icon("md_" + id, md.ico, 22))
				var l := Kit.para(txt, 12, Kit.TEXT if lv else (Kit.GOLD if off else Kit.MUTED))
				l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				row.add_child(l)
				box.add_child(row)
		info.add_child(box)
