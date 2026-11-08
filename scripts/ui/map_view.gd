extends Control
## Карта галактики — окно выбора узла перед волной (перенос galaxy.js). Холст вместо кнопок: туманность
## сектора, узлы — объекты в космосе (враги, торговец, медкорабль, тайник, аномалия), гиперкоридоры с бегущим
## светом, корабль игрока на карте. Тап по узлу — описание и подсветка всех узлов, куда можно попасть дальше
## этим путём; повторный тап или «ЛЕТИМ» — корабль летит по коридору, потом начинается волна. Иногда мимо
## дрейфует потерянный груз — тап по нему даёт немного кредитов. Генерация и правила карты — map.gd.

## враги, которые «стоят» на узлах боя
const FIGHT := ["e_interceptor2", "e_assault2", "e_swarm", "e_crab", "e_bombardier", "e_ram"]

var ctx: Ctx
var area: Control          # где рисуется карта (между заголовком и описанием)
var title: Label
var sub: Label
var steps: Label
var info_name: Label
var info_desc: Label
var info_more: Label
var go: Button
var d = null               # { map, step, choices, n }
var t := 0.0
var nodes: Array = []
var boss: Dictionary = {}
var entry := Vector2.ZERO
var sel = null
var reach = null           # Dictionary-множество ключей «c:r» или null
var open_set := {}
var ship_at = null
var fly = null
var trail: Array = []
var pod = null
var comet = null
var cometT := 3.0
var bg := {}
var W := 360.0
var H := 520.0


static func key(c: int, r: int) -> String:
	return "%d:%d" % [c, r]


func _ready() -> void:
	Kit.full(self)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var back := ColorRect.new(); back.color = Color("#010208"); Kit.full(back); add_child(back)
	var v := Kit.vbox(0)
	Kit.full(v)
	add_child(v)
	var head := Kit.margin(16, 12, 16, 4)
	var hv := Kit.vbox(2)
	title = Kit.label("СЕКТОР 1", 20, Kit.TEXT, 900, HORIZONTAL_ALIGNMENT_CENTER)
	sub = Kit.label("", 13, Kit.MUTED, 600, HORIZONTAL_ALIGNMENT_CENTER)
	steps = Kit.label("", 14, Kit.CYAN, 800, HORIZONTAL_ALIGNMENT_CENTER)
	hv.add_child(title); hv.add_child(sub); hv.add_child(steps)
	head.add_child(hv)
	v.add_child(head)
	area = Control.new()
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.mouse_filter = Control.MOUSE_FILTER_STOP
	area.clip_contents = true
	area.gui_input.connect(_on_area_input)
	v.add_child(area)
	ctx = Ctx.new(area.get_canvas_item())
	var foot := Kit.margin(14, 6, 14, 14)
	var fv := Kit.vbox(8)
	var pnl := Kit.panel(12)
	var pv := Kit.vbox(3)
	info_name = Kit.label("", 15, Kit.TEXT, 900)
	info_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_desc = Kit.para("", 13)
	info_more = Kit.para("", 12, Kit.GOLD)
	pv.add_child(info_name); pv.add_child(info_desc); pv.add_child(info_more)
	pnl.add_child(pv)
	fv.add_child(pnl)
	go = Kit.button("ЛЕТИМ", func(): fly_go(), "primary", "big")
	fv.add_child(go)
	foot.add_child(fv)
	v.add_child(foot)


func close() -> void:
	visible = false
	d = null


## открыть карту: d = { map, step, choices, n } (map.gd → mapOffer)
func open(dd: Dictionary) -> void:
	d = dd
	t = 0.0; sel = null; reach = null; fly = null; trail.clear(); bg = {}
	pod = {"t": 0.0, "side": -1.0 if U.random() < 0.5 else 1.0, "y": U.rand(0.35, 0.7), "got": false, "gt": 0.0, "x": 0.0, "py": 0.0, "coins": 0} if U.random() < 0.4 else null
	var map: Dictionary = d.map
	var sec := Game.sectorDef(map.sector)
	if not map.has("seed"): map.seed = int(U.random() * 1e9)
	title.text = "СЕКТОР %d" % (int(map.sector) + 1)
	sub.text = "%s · волна %d" % [sec.name, d.n]
	var s := ""
	for c in 4: s += ("●" if c < d.step else ("◉" if c == d.step else "○")) + "  "
	steps.text = s + "👑"
	visible = true
	await get_tree().process_frame
	W = maxf(240, area.size.x); H = maxf(300, area.size.y)
	_make_bg(sec, map.seed)
	_layout()
	_info(null)
	go.disabled = true


## раскладка: 4 шага снизу вверх, босс наверху; узлы чуть сдвинуты, чтобы не было сетки
func _layout() -> void:
	var map: Dictionary = d.map
	var rnd := U.seeded(int(map.seed))
	var padX := minf(W * 0.2, 80)
	nodes.clear()
	for c in map.cols.size():
		var col: Array = map.cols[c]
		for r in col.size():
			var n = col[r]
			if n == null:
				rnd.call(); rnd.call()
				continue
			var x: float = U.lerp(padX, W - padX, r / 2.0) + (rnd.call() - 0.5) * W * 0.1
			var y: float = H * (0.8 - c * 0.165) + (rnd.call() - 0.5) * H * 0.045
			nodes.append({"c": c, "r": r, "t": n.t, "x": x, "y": y, "ph": rnd.call() * TAU, "spr": FIGHT[(int(map.seed) + c * 5 + r * 2) % FIGHT.size()], "def": D.MAP_NODES[n.t]})
	boss = {"x": W / 2, "y": H * 0.115, "def": Game.bossDef(int(map.sector) + 1), "boss": true}
	entry = Vector2(W / 2, H * 0.95)
	for n in nodes:
		var k := key(n.c, n.r)
		n.done = k in map.path
		n.cur = map.at != null and map.at.c == n.c and map.at.r == n.r
		n.can = n.c == d.step and n.r in d.choices
	open_set = _reachFrom(d.choices.map(func(r): return key(d.step, r)))
	ship_at = null
	for n in nodes:
		if n.cur: ship_at = n


func _nodeAt(c: int, r: int):
	for n in nodes:
		if n.c == c and n.r == r: return n
	return null


## все узлы, куда можно попасть из набора узлов (включая их самих)
func _reachFrom(keys: Array) -> Dictionary:
	var map: Dictionary = d.map
	var out := {}
	for k in keys: out[k] = true
	var q: Array = keys.duplicate()
	while not q.is_empty():
		var k: String = q.pop_front()
		var parts := k.split(":")
		var c := int(parts[0])
		for nr in map.links.get(k, []):
			var nk := key(c + 1, nr)
			if not out.has(nk):
				out[nk] = true; q.append(nk)
	return out


## фон: небо сектора, туманности, далёкая спиральная галактика, пыль и звёзды (раскладка один раз)
func _make_bg(sec: Dictionary, seed: int) -> void:
	var rnd := U.seeded(seed + 7)
	var blobs: Array = []
	for i in 9:
		var r := U.lerp(90, 230, rnd.call())
		blobs.append({"col": sec.neb[i % sec.neb.size()], "a": 0.1 + rnd.call() * 0.14, "x": rnd.call() * W - r, "y": rnd.call() * H - r, "w": r * 2, "h": r * 2 * (0.6 + rnd.call() * 0.5)})
	var gx := W * (0.18 if rnd.call() < 0.5 else 0.82)
	var gy := H * U.lerp(0.25, 0.6, rnd.call())
	var gal: Array = []
	for i in 420:
		var arm := i % 2
		var k: float = rnd.call()
		var a := arm * PI + k * 5.2
		var rr := 4 + k * 46
		gal.append([gx + cos(a) * rr + (rnd.call() - 0.5) * 7, gy + sin(a) * rr * 0.45 + (rnd.call() - 0.5) * 4, (1 - k) * 0.55, "#ffffff" if rnd.call() < 0.3 else sec.neb[(i >> 1) % sec.neb.size()]])
	var dust: Array = []
	for i in 260:
		var a: float = 0.15 + rnd.call() * 0.55
		var col: String = sec.star if rnd.call() < 0.15 else "#ffffff"
		var s := 2.0 if rnd.call() < 0.06 else 1.0
		dust.append([rnd.call() * W, rnd.call() * H, s, a, col])
	var stars: Array = []
	for i in 26: stars.append({"x": rnd.call() * W, "y": rnd.call() * H, "p": rnd.call() * TAU, "s": 1 + rnd.call() * 1.6, "col": sec.star if rnd.call() < 0.4 else "#ffffff"})
	bg = {"sky": [U.col(sec.sky[1]), U.col(sec.sky[0])], "blobs": blobs, "gal": gal, "gx": gx, "gy": gy, "galCol": sec.neb[1], "dust": dust, "stars": stars}


func _process(dt: float) -> void:
	# раскладка готова только со следующего кадра после open (нужен размер области карты)
	if not visible or d == null or bg.is_empty(): return
	dt = minf(dt, 0.05)
	t += dt
	_update(dt)
	_draw_map()


func _update(dt: float) -> void:
	# полёт по коридору
	if fly != null:
		fly.t += dt
		var k := minf(1, fly.t / fly.dur)
		var e := 2 * k * k if k < 0.5 else 1 - pow(-2 * k + 2, 2) / 2
		var p := _bez(fly.a, fly.b, e)
		var p2 := _bez(fly.a, fly.b, minf(1, e + 0.02))
		fly.x = p.x; fly.y = p.y; fly.ang = atan2(p2.y - p.y, p2.x - p.x) + PI / 2
		for i in 2: trail.append({"x": p.x + U.rand(-2, 2), "y": p.y + U.rand(-2, 2), "t": 0.0, "life": 0.5})
		if k >= 1 and not fly.ended:
			fly.ended = true
			var fn: Callable = fly.done
			get_tree().create_timer(0.12).timeout.connect(fn)
	for p in trail: p.t += dt
	trail = trail.filter(func(p): return p.t < p.life)
	cometT -= dt
	if comet == null and cometT <= 0:
		var l := U.random() < 0.5
		comet = {"x": -20.0 if l else W + 20, "y": U.rand(0.05, 0.5) * H, "vx": (1 if l else -1) * U.rand(160, 240), "vy": U.rand(30, 70)}
		cometT = U.rand(5, 9)
	if comet != null:
		comet.x += comet.vx * dt; comet.y += comet.vy * dt
		if comet.x < -40 or comet.x > W + 40 or comet.y > H + 40: comet = null
	if pod != null and not pod.got:
		pod.t += dt
		if pod.t > 16: pod = null


## кривая коридора: вертикальные касательные — плавная «лиана» между узлами
static func _bez(a: Vector2, b: Vector2, k: float) -> Vector2:
	var dy := (b.y - a.y) * 0.5
	var u := 1 - k
	var x := u * u * u * a.x + 3 * u * u * k * a.x + 3 * u * k * k * b.x + k * k * k * b.x
	var y := u * u * u * a.y + 3 * u * u * k * (a.y + dy) + 3 * u * k * k * (b.y - dy) + k * k * k * b.y
	return Vector2(x, y)


func _lane(a: Vector2, b: Vector2) -> void:
	ctx.begin_path()
	for i in 21:
		var p := _bez(a, b, i / 20.0)
		if i: ctx.line_to(p.x, p.y)
		else: ctx.move_to(p.x, p.y)


func _pos(n) -> Vector2:
	return Vector2(n.x, n.y)


func _ship_pos() -> Vector2:
	if ship_at == null: return entry
	return Vector2(ship_at.x, ship_at.y + 36)


func _draw_map() -> void:
	ctx.begin()
	var map: Dictionary = d.map
	# фон чуть «дышит»
	var ox := sin(t * 0.07) * 4
	var oy := cos(t * 0.05) * 3
	ctx.save(); ctx.translate(ox, oy)
	ctx.fill_poly(PackedVector2Array([Vector2(-6, -6), Vector2(W + 6, -6), Vector2(W + 6, H * 0.6), Vector2(-6, H * 0.6)]), PackedColorArray([bg.sky[0], bg.sky[0], bg.sky[1], bg.sky[1]]))
	ctx.fill_poly(PackedVector2Array([Vector2(-6, H * 0.6), Vector2(W + 6, H * 0.6), Vector2(W + 6, H + 6), Vector2(-6, H + 6)]), PackedColorArray([bg.sky[1], bg.sky[1], Color("#010208"), Color("#010208")]))
	ctx.additive = true
	for b in bg.blobs:
		ctx.alpha = b.a
		ctx.draw_tex(G.soft(b.col, 128), b.x, b.y, b.w, b.h)
	ctx.alpha = 0.5
	ctx.draw_tex(G.soft(bg.galCol, 64), bg.gx - 26, bg.gy - 18, 52, 36)
	for p in bg.gal:
		ctx.alpha = p[2]; ctx.fill = U.col(p[3]); ctx.fill_rect(p[0], p[1], 1.2, 1.2)
	ctx.additive = false
	for p in bg.dust:
		ctx.alpha = p[3]; ctx.fill = U.col(p[4]); ctx.fill_rect(p[0], p[1], p[2], p[2])
	ctx.restore()
	for s in bg.stars:
		ctx.alpha = 0.35 + 0.65 * maxf(0, sin(t * 1.7 + s.p)); ctx.fill = U.col(s.col); ctx.fill_rect(s.x - s.s / 2, s.y - s.s / 2, s.s, s.s)
	ctx.alpha = 1.0
	if comet != null: _comet()
	var intro := func(k: float) -> float: return U.clamp((t - k) / 0.35, 0, 1)
	# ── коридоры ──
	var selKey: String = key(sel.c, sel.r) if sel != null and not sel.get("boss", false) else ""
	var on := func(n) -> bool: return reach.has(key(n.c, n.r)) if reach != null else open_set.has(key(n.c, n.r))
	for k in map.links:
		var parts: PackedStringArray = k.split(":")
		var ac := int(parts[0])
		var a = _nodeAt(ac, int(parts[1]))
		if a == null: continue
		for br in map.links[k]:
			var b = _nodeAt(ac + 1, br)
			if b == null: continue
			var kind := "walk" if a.done and b.done else (("prev" if reach != null else "open") if on.call(a) and on.call(b) and ac >= d.step else "dim")
			_drawLane(_pos(a), _pos(b), kind, intro.call(0.1 + ac * 0.08))
	for n in nodes:
		if n.c == 3: _drawLane(_pos(n), Vector2(boss.x, boss.y), ("prev" if reach != null else "open") if on.call(n) else "dim", intro.call(0.4))
	# от корабля к доступным узлам — бегущий свет
	for n in nodes:
		if n.can: _drawLane(_ship_pos(), _pos(n), "sel" if selKey == key(n.c, n.r) else "can", intro.call(0.05))
	if map.at == null:
		for n in nodes:
			if n.c == 0 and not n.can: _drawLane(entry, _pos(n), "dim", intro.call(0.05))
	# ── узлы ──
	for n in nodes: _drawNode(n, intro.call(0.12 + n.c * 0.08), on.call(n))
	_drawBoss(intro.call(0.45))
	if pod != null: _drawPod()
	# ── корабль и шлейф ──
	ctx.additive = true
	for p in trail:
		var k: float = 1 - p.t / p.life
		ctx.alpha = k * 0.8; ctx.draw_tex(G.glow("#7fe7ff", 32), p.x - 7 * k, p.y - 7 * k, 14 * k, 14 * k)
	ctx.additive = false; ctx.alpha = 1.0
	_drawShip()


func _drawLane(a: Vector2, b: Vector2, kind: String, k: float) -> void:
	if k <= 0: return
	ctx.save()
	ctx.alpha = k
	match kind:
		"walk":
			ctx.additive = true; ctx.alpha = k * 0.35; ctx.stroke = Kit.CYAN; ctx.line_width = 8; _lane(a, b); ctx.stroke_path()
			ctx.additive = false; ctx.alpha = k; ctx.stroke = Color(61 / 255.0, 224 / 255.0, 1, 0.85); ctx.line_width = 3; _lane(a, b); ctx.stroke_path()
		"can", "sel":
			var s := kind == "sel"
			ctx.stroke = Color(1, 1, 1, 0.35 if s else 0.14); ctx.line_width = 6 if s else 4; _lane(a, b); ctx.stroke_path()
			# бегущий свет: короткие штрихи вдоль коридора, сдвиг по времени
			ctx.stroke = Color.WHITE if s else Color(200 / 255.0, 240 / 255.0, 1, 0.85); ctx.line_width = 3.5 if s else 2.5
			var n := 26
			var off := fmod(t * (60.0 if s else 30.0) / 14.0, 1.0)
			for i in n:
				var q0 := (i + off) / n
				var p0 := _bez(a, b, q0)
				var p1 := _bez(a, b, minf(1, q0 + 0.012))
				ctx.stroke_line(p0.x, p0.y, p1.x, p1.y)
		"prev":
			ctx.dash = PackedFloat32Array([6, 7]); ctx.stroke = Color(1, 214 / 255.0, 120 / 255.0, 0.7); ctx.line_width = 2; _lane(a, b); ctx.stroke_path()
		"open":
			ctx.dash = PackedFloat32Array([4, 8]); ctx.stroke = Color(170 / 255.0, 200 / 255.0, 1, 0.32); ctx.line_width = 1.6; _lane(a, b); ctx.stroke_path()
		_:
			ctx.dash = PackedFloat32Array([2, 9]); ctx.stroke = Color(140 / 255.0, 160 / 255.0, 220 / 255.0, 0.12); ctx.line_width = 1.2; _lane(a, b); ctx.stroke_path()
	ctx.restore()


## узел: подсветка, диск-«портал» цвета узла, объект на нём, подпись
func _drawNode(n: Dictionary, k: float, on: bool) -> void:
	if k <= 0: return
	var col: String = n.def.color
	var isSel: bool = sel != null and is_same(sel, n)
	var R := 21 * (1.18 if isSel else 1.0) * (0.6 + 0.4 * U.ease_out_back(k))
	var live: bool = n.can or n.done or on
	var a := k * (1.0 if n.can or isSel else (0.85 if n.done else (((0.9 if reach != null else 0.62)) if on else 0.22)))
	var x: float = n.x
	var y: float = n.y + sin(t * 1.6 + n.ph) * 2
	ctx.save()
	ctx.additive = true
	ctx.alpha = a * (0.55 + 0.25 * sin(t * 4 + n.ph) if n.can else 0.3)
	ctx.draw_tex(G.soft(col, 64), x - R * 2.4, y - R * 2.4, R * 4.8, R * 4.8)
	ctx.additive = false
	# диск: радиальный градиент — веер с цветом в центре
	ctx.alpha = a
	_disc(x, y, R, U.col(col, 0.55), Color(10 / 255.0, 14 / 255.0, 36 / 255.0, 0.92), Color(4 / 255.0, 6 / 255.0, 18 / 255.0, 0.95))
	ctx.line_width = 2.4 if n.can or isSel else 1.4
	ctx.stroke = Kit.CYAN if n.done and not n.can else U.col(col, 0.95 if live else 0.5)
	ctx.begin_path(); ctx.arc(x, y, R, 0, TAU); ctx.stroke_path()
	# вращающееся кольцо у доступных
	if n.can or isSel:
		ctx.save(); ctx.translate(x, y); ctx.rotate(t * (1.6 if isSel else 0.8) + n.ph)
		ctx.dash = PackedFloat32Array([5, 6]); ctx.line_width = 2.5 if isSel else 1.8; ctx.stroke = Color.WHITE if isSel else U.col(col)
		ctx.begin_path(); ctx.arc(0, 0, R + 6 + (2.0 if isSel else sin(t * 4) * 1.5), 0, TAU); ctx.stroke_path()
		ctx.restore()
	if not live: ctx.alpha = a * 0.55
	_drawObj(n, x, y, R)
	ctx.alpha = a
	# отметка пройденного
	if n.done:
		ctx.fill = Kit.CYAN; ctx.fill_circle(x + R * 0.75, y - R * 0.75, 6)
		ctx.stroke = Color("#04121f"); ctx.line_width = 2
		ctx.begin_path(); ctx.move_to(x + R * 0.75 - 3, y - R * 0.75); ctx.line_to(x + R * 0.75 - 0.5, y - R * 0.75 + 2.5); ctx.line_to(x + R * 0.75 + 3.5, y - R * 0.75 - 2.5); ctx.stroke_path()
	# подпись
	if n.can or isSel or (on and reach != null):
		ctx.font = Kit.font(800)
		var fs := 11 if isSel else 10
		ctx.fill = Color(0, 0, 0, 0.6); ctx.fill_text(n.def.name, x + 1, y + R + 13 + fs, fs, 1)
		ctx.fill = Color.WHITE if n.can or isSel else U.col(col, 0.9); ctx.fill_text(n.def.name, x, y + R + 12 + fs, fs, 1)
	ctx.restore()


func _disc(x: float, y: float, R: float, c0: Color, c1: Color, c2: Color) -> void:
	var pts := PackedVector2Array([Vector2(x - R * 0.3, y - R * 0.4)])
	var cols := PackedColorArray([c0])
	for i in 33:
		var a := i / 32.0 * TAU
		pts.append(Vector2(x + cos(a) * R, y + sin(a) * R))
		cols.append(c2)
	ctx.fill_poly(pts, cols)
	# средний тон поверх — кольцом к краю
	var a0 := ctx.alpha
	ctx.alpha = a0 * 0.6
	ctx.fill = c1; ctx.fill_circle(x, y, R * 0.6)
	ctx.alpha = a0


## что стоит на узле: враги, торговец, медкорабль, ящик, аномалия
func _drawObj(n: Dictionary, x: float, y: float, R: float) -> void:
	match n.t:
		"fight": G.draw(ctx, n.spr, x, y, R * 1.35, PI)
		"elite":
			for s in [-1.0, 1.0]: G.draw(ctx, "e_interceptor2", x + s * R * 0.62, y + R * 0.3, R * 0.75, PI)
			G.draw(ctx, "e_heavyfighter", x, y - R * 0.08, R * 1.25, PI)
		"shop":
			G.draw(ctx, "p_merchant_s", x, y + sin(t * 2 + n.ph) * 1.5, R * 1.45)
			if sin(t * 5 + n.ph) > 0.3:
				ctx.save(); ctx.additive = true
				ctx.draw_tex(G.glow("#ffc83d", 32), x - R * 0.7 - 5, y - R * 0.55 - 5, 10, 10); ctx.draw_tex(G.glow("#ff5c3d", 32), x + R * 0.7 - 5, y - R * 0.55 - 5, 10, 10)
				ctx.restore()
		"escort":
			G.draw(ctx, "p_merchant_s", x, y + sin(t * 2 + n.ph) * 1.5, R * 1.15)
			ctx.save(); ctx.additive = true; ctx.alpha *= 0.55 + 0.25 * sin(t * 2.5 + n.ph)
			ctx.stroke = U.col("#7fd8ff"); ctx.line_width = 2; ctx.begin_path(); ctx.arc(x, y, R * 0.95, 0, TAU); ctx.stroke_path()
			ctx.restore()
		"repair":
			G.draw(ctx, "p_medship", x, y, R * 1.05)
			ctx.save(); ctx.additive = true; ctx.alpha *= 0.5 + 0.5 * sin(t * 3 + n.ph)
			ctx.stroke = Kit.GREEN; ctx.line_width = 2; ctx.begin_path(); ctx.arc(x, y, R * (0.55 + fmod(t * 0.8 + n.ph, 1.0) * 0.5), 0, TAU); ctx.stroke_path()
			ctx.restore()
		"cache":
			G.draw(ctx, "ast_m1", x + R * 0.15, y + R * 0.18, R * 1.35, n.ph + t * 0.2)
			G.draw(ctx, "p_crate", x - R * 0.05, y - R * 0.12, R * 1.0, sin(t * 1.5 + n.ph) * 0.12)
		"event":
			ctx.save(); ctx.additive = true; ctx.alpha *= 0.8
			G.draw(ctx, "fx_vortex", x, y, R * 1.9, t * 1.4 + n.ph)
			ctx.restore()
			ctx.font = Kit.font(900)
			var fs := int(round(R * 1.05))
			ctx.fill = Color("#e8fbff"); ctx.fill_text("?", x, y + 1 + fs * 0.36, fs, 1, 3, Color(127 / 255.0, 231 / 255.0, 1, 0.5))


## босс сектора: красная планета-крепость и сам босс
func _drawBoss(k: float) -> void:
	if k <= 0: return
	var col: String = boss.def.get("color", "#ff3d5a")
	var R := 34 * (0.6 + 0.4 * U.ease_out_back(k))
	var x: float = boss.x
	var y: float = boss.y
	var isSel: bool = sel != null and sel.get("boss", false)
	ctx.save()
	ctx.additive = true
	ctx.alpha = k * (0.45 + 0.2 * sin(t * 2.2))
	ctx.draw_tex(G.soft(col, 64), x - R * 2.6, y - R * 2.2, R * 5.2, R * 4.4)
	ctx.additive = false
	ctx.alpha = k
	_disc(x, y, R, U.col(col, 0.6), Color(40 / 255.0, 6 / 255.0, 14 / 255.0, 0.95), Color(12 / 255.0, 2 / 255.0, 6 / 255.0, 0.98))
	ctx.line_width = 3 if isSel else 2; ctx.stroke = Color.WHITE if isSel else U.col(col)
	ctx.begin_path(); ctx.arc(x, y, R, 0, TAU); ctx.stroke_path()
	ctx.save(); ctx.translate(x, y); ctx.rotate(-t * 0.4); ctx.dash = PackedFloat32Array([3, 9]); ctx.stroke = U.col(col, 0.8); ctx.line_width = 2
	ctx.begin_path(); ctx.arc(0, 0, R + 7, 0, TAU); ctx.stroke_path(); ctx.restore()
	G.draw(ctx, boss.def.sprite, x, y + sin(t * 1.3) * 2, R * 1.55, boss.def.get("rot", 0.0))
	ctx.font = Kit.font(800)
	var txt: String = "БОСС · " + boss.def.name
	ctx.fill = Color(0, 0, 0, 0.6); ctx.fill_text(txt, x + 1, y + R + 19, 10, 1)
	ctx.fill = Color("#ffd0d6"); ctx.fill_text(txt, x, y + R + 18, 10, 1)
	ctx.restore()


func _drawShip() -> void:
	var p := _ship_pos()
	var ang := 0.0
	if fly != null:
		p = Vector2(fly.x, fly.y); ang = fly.ang
	else:
		p.y += sin(t * 2.4) * 1.5
	var s: Dictionary = M.s
	ctx.save()
	ctx.translate(p.x, p.y); ctx.rotate(ang)
	Game.drawShip(ctx, s.ship.model, s.ship.skin, s.ship.trail, 0, 0, 30, 0, t, 1.0)
	ctx.restore()


func _comet() -> void:
	var a := atan2(comet.vy, comet.vx)
	var L := 46.0
	var tail := Vector2(comet.x - cos(a) * L, comet.y - sin(a) * L)
	var nrm := Vector2(-sin(a), cos(a))
	var hd := Vector2(comet.x, comet.y)
	ctx.fill_poly(PackedVector2Array([hd + nrm, hd - nrm, tail - nrm * 0.4, tail + nrm * 0.4]),
		PackedColorArray([Color(220 / 255.0, 245 / 255.0, 1, 0.9), Color(220 / 255.0, 245 / 255.0, 1, 0.9), Color(120 / 255.0, 200 / 255.0, 1, 0), Color(120 / 255.0, 200 / 255.0, 1, 0)]))
	ctx.save(); ctx.additive = true; ctx.draw_tex(G.glow("#bfe9ff", 32), comet.x - 6, comet.y - 6, 12, 12); ctx.restore()


## потерянный груз: дрейфует через карту, мигает; тап — кредиты
func _podPos() -> Vector2:
	var k: float = pod.t / 16.0
	return Vector2(U.lerp(-20, W + 20, k) if pod.side < 0 else U.lerp(W + 20, -20, k), H * pod.y + sin(pod.t * 1.3) * 10)


func _drawPod() -> void:
	if pod.got:
		pod.gt += 1 / 60.0
		ctx.save(); ctx.alpha = maxf(0, 1 - pod.gt); ctx.font = Kit.font(800); ctx.fill = Kit.GOLD
		ctx.fill_text("+%d" % pod.coins, pod.x, pod.py - 14 - pod.gt * 30, 14, 1); ctx.restore()
		if pod.gt > 1: pod = null
		return
	var q := _podPos()
	pod.x = q.x; pod.py = q.y
	ctx.save()
	ctx.additive = true; ctx.alpha = 0.5 + 0.5 * sin(t * 6)
	ctx.draw_tex(G.glow("#ffc83d", 32), q.x - 16, q.y - 16, 32, 32)
	ctx.additive = false; ctx.alpha = 1.0
	G.draw(ctx, "p_crate", q.x, q.y, 22, t * 0.8)
	ctx.restore()


# ── тап по карте ──
func _on_area_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT): return
	if d == null or fly != null: return
	var x: float = e.position.x
	var y: float = e.position.y
	# груз
	if pod != null and not pod.got and Vector2(pod.x - x, pod.py - y).length() < 30:
		var coins := int(round(8 + d.n * 1.2))
		pod.got = true; pod.coins = coins
		Game.run.coins += coins; M.addCoins(coins); Game.hudDirty = true
		A.play("coin", {"rate": 1.2}); Haptic.success()
		return
	var best = null
	var bd := 40.0
	for n in nodes:
		var dd := Vector2(n.x - x, n.y - y).length()
		if dd < bd:
			bd = dd; best = n
	if Vector2(boss.x - x, boss.y - y).length() < 48: best = boss
	if best == null: return
	# повторный тап по выбранному доступному узлу — летим
	if sel != null and is_same(best, sel) and best.get("can", false):
		fly_go()
		return
	_select(best)


func _select(n: Dictionary) -> void:
	sel = n
	reach = null if n.get("boss", false) else _reachFrom([key(n.c, n.r)])
	_info(n)
	go.disabled = not n.get("can", false)
	A.play("click" if n.get("can", false) else "back", {"vol": 0.6})
	Haptic.select()


func _info(n) -> void:
	if n == null:
		info_name.text = ""
		info_desc.text = "Тап по узлу — подробности · по светящемуся ещё раз — летим"
		info_more.text = ""
		return
	if n.get("boss", false):
		info_name.text = "БОСС: " + n.def.name
		info_name.add_theme_color_override("font_color", U.col(n.def.get("color", "#ff3d5a")))
		info_desc.text = n.def.get("title", "") + ". После боя — трофейный сундук и станция"
		info_more.text = ""
		return
	var tag := "ТАП ЕЩЁ РАЗ — ЛЕТИМ" if n.can else ("ПРОЙДЕН" if n.done else ("ПОЗАДИ" if n.c < d.step else ("ДАЛЬШЕ ПО ПУТИ" if open_set.has(key(n.c, n.r)) else "НЕТ ПУТИ")))
	info_name.text = n.def.name + "   · " + tag
	info_name.add_theme_color_override("font_color", U.col(n.def.color))
	info_desc.text = n.def.desc
	info_more.text = ("Отсюда дальше: " + _routeText(reach, n)) if n.can and reach != null else ""


## что встретится дальше по выбранному пути (по типам)
func _routeText(r: Dictionary, from: Dictionary) -> String:
	var cnt := {}
	for n in nodes:
		if not is_same(n, from) and n.c > from.c and r.has(key(n.c, n.r)): cnt[n.t] = cnt.get(n.t, 0) + 1
	var parts: Array = []
	for tp in cnt: parts.append(D.MAP_NODES[tp].name.to_lower() + (" ×%d" % cnt[tp] if cnt[tp] > 1 else ""))
	return ", ".join(parts) if not parts.is_empty() else "сразу босс"


## «ЛЕТИМ»: корабль летит по коридору, затем волна
func fly_go() -> bool:
	var n = sel
	if n == null or not n.get("can", false) or fly != null: return false
	var from := _ship_pos()
	var nc: int = n.c
	var nr: int = n.r
	var done := func():
		fly = null
		if not RunMap.choose(nc, nr):
			A.play("error")
			return
		close()
	fly = {"a": from, "b": Vector2(n.x, n.y), "t": 0.0, "dur": 0.75, "x": from.x, "y": from.y, "ang": 0.0, "ended": false, "done": done}
	go.disabled = true
	A.play("teleport", {"rate": 1.3, "vol": 0.5})
	Haptic.success()
	return true


func bot_pick() -> void:
	if d == null or fly != null or nodes.is_empty(): return
	for n in nodes:
		if n.can:
			_select(n)
			fly_go()
			return
