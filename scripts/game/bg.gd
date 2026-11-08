extends Node
## Фон (автозагрузка Bg) — перенос gfx.bg из gfx.js. Небо и туманности, планета и детали сектора — шейдеры
## на видеокарте (assets/shaders/nebula, planet) вместо холстов с градиентами; звёзды, яркие звёзды с лучами,
## кометы, далёкие корабли и пыль гиперпрыжка — как в JS. Смена сектора — плавная (старый набор гаснет).
## Bg.setSector(i, instant), Bg.update(dt, скорость), Bg.draw(ctx, качество), Bg.warp — форсаж прыжка.

const NEBULA := preload("res://assets/shaders/nebula.gdshader")
const PLANET := preload("res://assets/shaders/planet.gdshader")
## своя деталь вдали у каждого сектора (по порядку D.SECTORS)
## Godot: живая деталь фона по механике сектора (assets/shaders/nebula.gdshader, uniform style)
const STYLES := {"sats": 1, "asteroids": 2, "nebula": 3, "ice": 4, "lava": 5, "toxic": 6, "gravity": 7, "wind": 8,
	"prism": 9, "hive": 10, "portals": 11, "pillars": 12, "eye": 13}
const KINDS := ["sun", "rocks", "galaxy", "moons", "giant", "galaxy", "blackhole", "core", "rocks", "moons", "rocks", "sun", "blackhole"]

var sector := -1
var sec: Dictionary = {}
var cur = null           # { neb: ShaderMaterial, planet, feats }
var prev = null
var fade := 1.0
var warp := 0.0
var scroll := 0.0
var stars: Array = []
var dust: Array = []
var bright: Array = []
var comets: Array = []
var ships: Array = []
var cometT := 4.0
var shipT := 6.0
var _spike: Texture2D
var _size := Vector2.ZERO
## Godot: туманность считается в уменьшенном буфере (доля пикселей окна по качеству) и растягивается на экран —
## шумовой шейдер работает в 4–10 раз меньше раз за кадр; облака мягкие, на глаз разницы нет
const NEB_SCALE := [0.3, 0.4, 0.5]
var _nvp: SubViewport
var _nprev: ColorRect
var _ncur: ColorRect
var _nodd := false
var neb_direct := false
## Godot: погода сектора — лёгкие частицы над фоном (снег у ледяных лун, пепел и искры у красного гиганта,
## споры в изумрудных полях, пыль пояса, порывы ветра…); на низком качестве нет
var weather: Array = []    # { x, y, vx, vy, s, a, ph, c (цвет), add (светится) }
var _wk := ""   # проверка: рисовать шейдер прямо на экран, как раньше


## звёзды и пыль под размер экрана (при смене размера окна)
func makeStars() -> void:
	var W := G.W
	var H := G.H
	_size = Vector2(W, H)
	stars.clear()
	var n := int(round(W * H / 5200.0))
	for i in n:
		var layer := i % 3
		stars.append({"x": U.random() * W, "y": U.random() * H, "layer": layer,
			"s": U.rand(0.5, 1.1) if layer == 0 else (U.rand(0.9, 1.6) if layer == 1 else U.rand(1.4, 2.4)),
			"a": U.rand(0.25, 0.5) if layer == 0 else U.rand(0.45, 0.95), "tw": U.rand(0, TAU), "ts": U.rand(1, 3)})
	dust.clear()
	for i in 26: dust.append({"x": U.random() * W, "y": U.random() * H, "len": U.rand(10, 40), "a": U.rand(0.05, 0.16)})
	# 4.0: несколько ярких звёзд с лучами — мерцают
	bright.clear()
	for i in 7: bright.append({"x": U.random() * W, "y": U.random() * H, "s": U.rand(9, 18), "ph": U.random() * TAU, "sp": U.rand(0.6, 1.6)})


func resize() -> void:
	makeStars()
	if sector >= 0:
		var s := sector
		sector = -1
		setSector(s, true)


## звезда с четырьмя лучами (рисуется один раз)
func spike() -> Texture2D:
	if _spike: return _spike
	var s := 64
	var h := s / 2.0
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var dx := x + 0.5 - h
			var dy := y + 0.5 - h
			var a := clampf(1.0 - Vector2(dx, dy).length() / (h * 0.35), 0, 1)
			# лучи: тонкий длинный и толстый короткий по горизонтали и вертикали
			for ray in [[1.6, h], [0.9, h * 0.6]]:
				for d in [[dx, dy], [dy, dx]]:
					if absf(d[1]) < ray[0] / 2.0 + 0.5 and absf(d[0]) < ray[1]:
						a = maxf(a, 0.9 * (1.0 - absf(d[0]) / ray[1]))
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_spike = ImageTexture.create_from_image(img)
	return _spike


func setSector(idx: int, instant := false) -> void:
	var n: int = D.SECTORS.size()
	var si := ((idx % n) + n) % n
	if sector == idx and cur != null: return
	if stars.is_empty() or _size != Vector2(G.W, G.H): makeStars()
	prev = null if instant else cur
	fade = 1.0 if instant else 0.0
	sector = idx
	sec = D.SECTORS[si]
	cur = {"neb": makeNebula(sec), "planet": makePlanet(sec), "feats": makeFeats(sec, si)}
	_make_weather(str(sec.get("mech", "")))


func makeNebula(s: Dictionary) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = NEBULA
	m.set_shader_parameter("sky_top", U.col(s.sky[1]))
	m.set_shader_parameter("sky_bot", U.col(s.sky[0]))
	var neb: Array = s.neb
	m.set_shader_parameter("neb0", U.col(neb[0]))
	m.set_shader_parameter("neb1", U.col(neb[1 % neb.size()]))
	m.set_shader_parameter("neb2", U.col(neb[2 % neb.size()]))
	m.set_shader_parameter("seed", U.rand(0, 50))
	m.set_shader_parameter("style", STYLES.get(s.get("mech", ""), 0))
	return m


## частица погоды по механике сектора: скорость, размер, цвет, светится ли
func _wp(kind: String, anywhere := true) -> Dictionary:
	var W := G.W
	var H := G.H
	var p := {"x": U.random() * W, "y": U.random() * H if anywhere else -10.0, "vx": 0.0, "vy": 0.0, "s": 2.0, "a": 0.6, "ph": U.random() * TAU, "c": "#ffffff", "add": false, "line": 0.0}
	match kind:
		"ice":       # снег: падает и покачивается
			p.vy = U.rand(30, 70); p.vx = U.rand(-12, 6); p.s = U.rand(1.6, 3.6); p.a = U.rand(0.45, 0.9); p.c = "#eaf8ff"
		"lava":      # пепел вниз, искры вверх
			if U.random() < 0.6:
				p.vy = U.rand(18, 40); p.vx = U.rand(-8, 8); p.s = U.rand(1.5, 3.2); p.a = U.rand(0.35, 0.6); p.c = "#3a2a2a"
			else:
				p.vy = U.rand(-55, -25); p.vx = U.rand(-10, 10); p.s = U.rand(1.5, 2.8); p.a = U.rand(0.5, 0.9); p.c = "#ff8a3d"; p.add = true
				if not anywhere: p.y = H + 10
		"toxic":     # споры всплывают и мерцают
			p.vy = U.rand(-30, -12); p.vx = U.rand(-6, 6); p.s = U.rand(2.5, 5.5); p.a = U.rand(0.35, 0.7); p.c = "#7dff6b"; p.add = true
			if not anywhere: p.y = H + 10
		"asteroids": # пыль пояса — быстрые тусклые штрихи
			p.vy = U.rand(140, 220); p.vx = U.rand(-20, 0); p.s = 1.0; p.a = U.rand(0.12, 0.25); p.c = "#c9b79c"; p.line = U.rand(10, 22)
		"wind":      # звёздный ветер — горизонтальные порывы
			p.vx = U.rand(220, 340) * (1 if U.random() < 0.7 else -1); p.vy = U.rand(10, 30); p.s = 1.0; p.a = U.rand(0.12, 0.28); p.c = "#bfe3ff"; p.line = U.rand(18, 40)
			if not anywhere: p.x = -40.0 if p.vx > 0 else W + 40; p.y = U.random() * H
		"prism":     # блёстки радужных искр
			p.vy = U.rand(8, 20); p.s = U.rand(1.5, 3.0); p.a = 0.8; p.c = U.pick(["#7fe7ff", "#ff7ad9", "#ffe066", "#7dff6b"]); p.add = true
		"pillars":   # золотые пылинки в лучах
			p.vy = U.rand(10, 24); p.vx = U.rand(-4, 4); p.s = U.rand(1.5, 3.0); p.a = U.rand(0.4, 0.8); p.c = "#ffd27a"; p.add = true
		"eye":       # красные угольки вверх
			p.vy = U.rand(-40, -18); p.vx = U.rand(-8, 8); p.s = U.rand(1.5, 3.0); p.a = U.rand(0.4, 0.8); p.c = "#ff3d5a"; p.add = true
			if not anywhere: p.y = H + 10
		"hive":      # пыльца улья
			p.vy = U.rand(6, 20); p.vx = U.rand(-14, 14); p.s = U.rand(2.0, 4.0); p.a = U.rand(0.3, 0.6); p.c = "#d8ff5c"; p.add = true
		"portals":   # фиолетовые искры кружат
			p.vy = U.rand(-10, 10); p.vx = U.rand(-10, 10); p.s = U.rand(1.5, 3.0); p.a = U.rand(0.5, 0.9); p.c = "#c77dff"; p.add = true
		"gravity":   # пылинки затягивает к центру
			p.s = U.rand(1.2, 2.4); p.a = U.rand(0.3, 0.7); p.c = "#ffd9a0"; p.add = true
		"nebula":    # клочья тумана
			p.vy = U.rand(6, 14); p.s = U.rand(60, 120); p.a = U.rand(0.04, 0.08); p.c = str(sec.neb[1 % sec.neb.size()]); p.add = true
		_:           # орбита: редкие искорки мусора
			p.vy = U.rand(20, 40); p.vx = U.rand(-6, 6); p.s = U.rand(1.0, 2.0); p.a = U.rand(0.25, 0.5); p.c = "#cfe6ff"
	return p


func _make_weather(kind: String) -> void:
	_wk = kind
	weather.clear()
	var n: int = {"ice": 46, "lava": 40, "toxic": 26, "asteroids": 26, "wind": 18, "prism": 30, "pillars": 30, "eye": 26, "hive": 24, "portals": 26, "gravity": 40, "nebula": 7}.get(kind, 12)
	for i in n: weather.append(_wp(kind))


func _update_weather(dt: float, sp: float) -> void:
	if weather.is_empty(): return
	var W := G.W
	var H := G.H
	var c := Vector2(W / 2, H * 0.35)
	for i in weather.size():
		var p: Dictionary = weather[i]
		p.ph += dt
		if _wk == "gravity":
			var d := c - Vector2(p.x, p.y)
			var l := maxf(20.0, d.length())
			var tang := Vector2(-d.y, d.x) / l
			p.vx = lerpf(p.vx, (d.x / l * 40.0 + tang.x * 70.0), dt * 2.0)
			p.vy = lerpf(p.vy, (d.y / l * 40.0 + tang.y * 70.0), dt * 2.0)
			if l < 24.0: weather[i] = _wp(_wk); continue
		var sway: float = sin(p.ph * 1.7) * 10.0 if _wk == "ice" or _wk == "hive" else 0.0
		p.x += (p.vx + sway) * dt
		p.y += p.vy * dt * (1.0 if p.vy < 0 else sp)
		if p.y > H + 20 or p.y < -30 or p.x < -60 or p.x > W + 60:
			weather[i] = _wp(_wk, false)


func _draw_weather(ctx: Ctx, quality: int) -> void:
	var n := weather.size() if quality >= 2 else weather.size() * 2 / 3
	for i in n:
		var p: Dictionary = weather[i]
		var tw: float = 0.65 + 0.35 * sin(p.ph * 3.0) if p.add else 1.0
		ctx.alpha = p.a * tw
		ctx.additive = p.add
		if p.line > 0:
			# штрих — тонким прямоугольником (без многоугольника на видеокарте): пыль вертикально, ветер горизонтально
			ctx.fill = U.col(p.c)
			if absf(p.vx) > absf(p.vy): ctx.fill_rect(p.x - (p.line if p.vx > 0 else 0.0), p.y, p.line, 1.0)
			else: ctx.fill_rect(p.x, p.y - p.line, 1.0, p.line)
		elif p.s > 20:
			ctx.draw_tex(G.soft(p.c, 64), p.x - p.s, p.y - p.s, p.s * 2, p.s * 2)
		elif p.add:
			var g: float = p.s * 3.0
			ctx.draw_tex(G.soft(p.c, 32), p.x - g, p.y - g, g * 2, g * 2)
			ctx.fill = U.col(p.c)
			ctx.fill_rect(p.x - p.s * 0.35, p.y - p.s * 0.35, p.s * 0.7, p.s * 0.7)
		else:
			ctx.fill = U.col(p.c)
			ctx.fill_circle(p.x, p.y, p.s * 0.5)
	ctx.alpha = 1.0
	ctx.additive = false


## планета: шейдер-шар; кольца (у половины планет) — дугами поверх
func makePlanet(s: Dictionary, hue_add := 0.0, k := 1.0) -> Dictionary:
	var R: float = round(minf(G.W, 520) * U.rand(0.16, 0.26)) * k
	var m := ShaderMaterial.new()
	m.shader = PLANET
	var h: float = fmod(s.planet + hue_add, 360.0)
	m.set_shader_parameter("hue", h / 360.0)
	m.set_shader_parameter("seed", U.rand(0, 50))
	var size := R * 3.4
	return {"kind": "planet", "mat": m, "R": R, "hue": h, "x": U.rand(0.1, 0.9) * G.W, "y": -size * 0.6 - U.random() * G.H * 0.5, "s": size,
		"speed": U.rand(9, 16), "rings": U.random() < 0.55 and k >= 1.0, "ringRot": U.rand(-0.5, 0.5)}


func makeFeats(s: Dictionary, idx: int) -> Array:
	var kind: String = KINDS[idx % KINDS.size()]
	var W := G.W
	var H := G.H
	var out: Array = []
	var col: String = s.neb[0]
	var col2: String = s.neb[1]
	match kind:
		"sun", "giant":
			var giant := kind == "giant"
			var R := W * 0.9 if giant else W * 0.12
			var size := R * (2.4 if giant else 5.0)
			var spots: Array = []
			if giant:
				for i in 30: spots.append({"x": U.rand(-R, R) * 0.4, "y": U.rand(-R, R) * 0.4, "r": U.rand(4, 20), "c": "#ffb03d" if U.random() < 0.5 else "#7a1020"})
			out.append({"kind": kind, "R": R, "col": col, "x": W * 0.5 if giant else W * U.rand(0.1, 0.9), "y": H * 1.15 if giant else H * 0.12, "s": size, "speed": 0.6, "spots": spots})
		"blackhole":
			var R := W * 0.16
			out.append({"kind": kind, "R": R, "col": col, "col2": col2, "x": W * U.rand(0.2, 0.8), "y": H * 0.3, "s": R * 5, "speed": 0.8})
		"galaxy", "core":
			var core := kind == "core"
			var R := W * (0.45 if core else 0.24)
			var size := ceilf(R * 2.4)
			out.append({"kind": kind, "R": R, "col": col, "tex": _galaxyTex(R, size, col, col2), "x": W * U.rand(0.25, 0.75), "y": -size / 2, "s": size, "speed": 2.0 if core else 3.0})
		"moons":
			for i in 2:
				var p := makePlanet(s, 40 + i * 60, 0.45 - i * 0.12)
				p.y = -p.s - H * (0.3 + i * 0.6); p.speed = 6 + i * 3
				out.append(p)
		"rocks":
			# далёкие глыбы: тёмные многоугольники с подсветкой края
			for i in 9:
				var r := U.rand(6, 18)
				var pts := PackedVector2Array()
				for k in 8:
					var a := k / 7.0 * TAU
					var rr := r * U.rand(0.7, 1)
					pts.append(Vector2(cos(a) * rr, sin(a) * rr))
				out.append({"kind": "rock", "pts": pts, "col": col, "x": U.random() * W, "y": U.random() * H, "s": r * 2.6, "speed": U.rand(18, 30), "rock": true})
	return out


## рукава галактики: точки по двум спиралям (рисуются в картинку один раз)
func _galaxyTex(R: float, size: float, col: String, col2: String) -> Texture2D:
	var s := int(size)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var h := s / 2.0
	# как translate(h, h) → scale(1; 0,55) → rotate(0,4) в JS
	var xf := Transform2D.IDENTITY.translated(Vector2(h, h)) * Transform2D.IDENTITY.scaled(Vector2(1, 0.55)) * Transform2D(0.4, Vector2.ZERO)
	for arm in 2:
		for i in 260:
			var t := i / 260.0
			var a := arm * PI + t * 7
			var r := R * (0.08 + t * 0.9)
			var p := xf * Vector2(cos(a) * r + U.rand(-6, 6), sin(a) * r + U.rand(-6, 6))
			var c := U.col(col if i % 3 else col2, 0.5 * (1 - t))
			for dy in 2:
				for dx in 2:
					var px := int(p.x) + dx
					var py := int(p.y) + dy
					if px >= 0 and py >= 0 and px < s and py < s:
						var o := img.get_pixel(px, py)
						img.set_pixel(px, py, Color(minf(1, o.r + c.r * c.a), minf(1, o.g + c.g * c.a), minf(1, o.b + c.b * c.a), minf(1, o.a + c.a)))
	return ImageTexture.create_from_image(img)


# ════════════════════════════════════════════════════════════
# ОБНОВЛЕНИЕ
# ════════════════════════════════════════════════════════════
func update(dt: float, speedMul := 1.0) -> void:
	if cur == null: return
	var sp := speedMul * (1 + warp * 14)
	scroll += dt * sp
	if fade < 1:
		fade = minf(1, fade + dt * 0.6)
		if fade >= 1: prev = null
	if warp > 0: warp = maxf(0, warp - dt * 0.55)
	var H := G.H
	var W := G.W
	for st: Dictionary in stars:
		st.y += (14 if st.layer == 0 else (34 if st.layer == 1 else 70)) * dt * sp
		if st.y > H + 4:
			st.y -= H + 8; st.x = U.random() * W
	for d: Dictionary in dust:
		d.y += 260 * dt * sp
		if d.y > H + d.len:
			d.y = -d.len; d.x = U.random() * W
	var p: Dictionary = cur.planet
	p.y += p.speed * dt * sp
	if p.y - p.s / 2 > H:
		p.y = -p.s / 2 - H * U.rand(1.5, 3); p.x = U.rand(0.1, 0.9) * W
	# 4.0: детали сектора, кометы и далёкие корабли
	for f: Dictionary in cur.feats:
		f.y += f.speed * dt * sp
		if f.y - f.s / 2 > H:
			f.y = -f.s / 2 - (U.random() * H * 0.5 if f.get("rock") else H * U.rand(1, 2))
			if f.get("rock"): f.x = U.random() * W
	_update_weather(dt, sp)
	cometT -= dt
	if cometT <= 0:
		cometT = U.rand(6, 13)
		var fromL := U.random() < 0.5
		var a := U.rand(0.35, 0.7) if fromL else PI - U.rand(0.35, 0.7)
		var v := U.rand(260, 420)
		comets.append({"x": -30.0 if fromL else W + 30, "y": U.rand(0.02, 0.4) * H, "vx": cos(a) * v, "vy": sin(a) * v, "life": 3.0, "len": U.rand(60, 120)})
	for i in range(comets.size() - 1, -1, -1):
		var c: Dictionary = comets[i]
		c.x += c.vx * dt; c.y += c.vy * dt; c.life -= dt
		if c.life <= 0: comets.remove_at(i)
	shipT -= dt
	if shipT <= 0:
		shipT = U.rand(10, 20)
		var spr: String = U.pick(["e_cruiser", "e_heavyfighter", "e_bombardier", "interceptor", "gunship"])
		var n := U.randi(1, 3)
		var up := U.random() < 0.5
		for i in n: ships.append({"spr": spr, "x": U.rand(0.15, 0.85) * W + i * 22, "y": H + 40 + i * 26 if up else -40.0 - i * 26, "vy": (-1 if up else 1) * U.rand(30, 45), "w": U.rand(16, 26)})
	for i in range(ships.size() - 1, -1, -1):
		var s: Dictionary = ships[i]
		s.y += s.vy * dt * (0.6 + sp * 0.4)
		if s.y < -80 or s.y > H + 80: ships.remove_at(i)


# ════════════════════════════════════════════════════════════
# ОТРИСОВКА
# ════════════════════════════════════════════════════════════
func _drawNebulaBuf(ctx: Ctx, fading: bool, quality: int) -> void:
	if _nvp == null:
		_nvp = SubViewport.new()
		_nvp.disable_3d = true
		_nvp.transparent_bg = false
		_nvp.gui_disable_input = true
		add_child(_nvp)
		_nprev = ColorRect.new()
		_ncur = ColorRect.new()
		_nvp.add_child(_nprev)
		_nvp.add_child(_ncur)
	var px := Vector2(get_tree().root.size)
	var k: float = NEB_SCALE[clampi(quality, 0, 2)]
	var sz := Vector2i(maxi(8, ceili(px.x * k)), maxi(8, ceili(px.y * k)))
	if _nvp.size != sz:
		_nvp.size = sz
		_nprev.size = Vector2(sz)
		_ncur.size = Vector2(sz)
	_nebLayer(_nprev, prev.neb if fading else null, 1.0, quality)
	_nebLayer(_ncur, cur.neb, fade if fading else 1.0, quality)
	# на высоком качестве и в форсаж буфер обновляется каждый кадр, иначе — через кадр (облака плывут медленно)
	if quality >= 2 or warp > 0.01 or fading:
		_nvp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		_nodd = not _nodd
		_nvp.render_target_update_mode = SubViewport.UPDATE_ONCE if _nodd else SubViewport.UPDATE_DISABLED
	if neb_direct:
		ctx.shader_rect(cur.neb, 0, 0, G.W, G.H)
		return
	ctx.draw_tex(_nvp.get_texture(), 0, 0, G.W, G.H)


func _nebLayer(r: ColorRect, m, a: float, quality: int) -> void:
	r.visible = m != null and a > 0.0
	if not r.visible: return
	if r.material != m: r.material = m
	var H := G.H
	m.set_shader_parameter("scroll1", fmod(scroll * 7.0, H) / H)
	m.set_shader_parameter("scroll2", fmod(scroll * 14.0, H) / H)
	m.set_shader_parameter("aspect", G.W / H)
	m.set_shader_parameter("layers", 2.0 if quality >= 2 else 1.0)
	r.modulate.a = a


## планета или деталь; за краем экрана не рисуется
func _drawFeat(ctx: Ctx, f: Dictionary, a: float) -> void:
	if a <= 0 or f.y + f.s / 2 < 0 or f.y - f.s / 2 > G.H: return
	var x: float = f.x
	var y: float = f.y
	ctx.save()
	ctx.alpha = a
	match f.kind:
		"planet":
			ctx.shader_rect(f.mat, x - f.s / 2, y - f.s / 2, f.s, f.s)
			if f.rings:
				var R: float = f.R
				ctx.translate(x, y); ctx.rotate(f.ringRot); ctx.scale(1, 0.26)
				ctx.stroke = Color.from_hsv(fmod(f.hue + 25, 360) / 360.0, 0.45, 0.85, 0.45); ctx.line_width = R * 0.14
				ctx.begin_path(); ctx.arc(0, 0, R * 1.5, PI * 1.05, PI * 2.95); ctx.stroke_path()
				ctx.stroke = Color.from_hsv(fmod(f.hue + 40, 360) / 360.0, 0.35, 0.9, 0.25); ctx.line_width = R * 0.07
				ctx.begin_path(); ctx.arc(0, 0, R * 1.75, 0, TAU); ctx.stroke_path()
		"sun":
			ctx.additive = true
			ctx.alpha = a * 0.35; ctx.draw_tex(G.soft(f.col, 64), x - f.s / 2, y - f.s / 2, f.s, f.s)
			var s2: float = f.s * 0.3
			ctx.alpha = a * 0.8; ctx.draw_tex(G.soft(sec.star, 64), x - s2 / 2, y - s2 / 2, s2, s2)
			# ядро: в JS — белое лишь в самом центре градиента (12% радиуса), дальше цвет звезды
			var s3: float = f.R * 0.55
			ctx.alpha = a * 0.75; ctx.draw_tex(G.glow("#fffae6", 64), x - s3, y - s3, s3 * 2, s3 * 2)
		"giant":
			ctx.additive = true
			ctx.alpha = a * 0.45; ctx.draw_tex(G.soft("#ff2d4d", 64), x - f.s / 2, y - f.s / 2, f.s, f.s)
			var s2: float = f.s * 0.62
			ctx.alpha = a * 0.6; ctx.draw_tex(G.soft("#ff7846", 64), x - s2 / 2, y - s2 / 2, s2, s2)
			ctx.alpha = a * 0.18
			for sp: Dictionary in f.spots: ctx.draw_tex(G.soft(sp.c, 32), x + sp.x - sp.r * 2, y + sp.y - sp.r * 2, sp.r * 4, sp.r * 4)
		"blackhole":
			var R: float = f.R
			ctx.additive = true
			ctx.alpha = a * 0.4; ctx.draw_tex(G.soft(f.col, 64), x - f.s / 2, y - f.s / 2, f.s, f.s)
			ctx.additive = false
			# аккреционный диск — наклонное кольцо
			ctx.save(); ctx.translate(x, y); ctx.rotate(-0.35); ctx.scale(1, 0.32)
			ctx.line_width = R * 0.12
			for i in 18:
				ctx.stroke = U.col(f.col2 if i % 2 else "#ffb03d", 0.12)
				ctx.begin_path(); ctx.arc(0, 0, R * (1.15 + i * 0.05), 0, TAU); ctx.stroke_path()
			ctx.restore()
			ctx.fill = Color.BLACK; ctx.fill_circle(x, y, R * 0.62)
			ctx.stroke = U.col("#ffd9a0", 0.7); ctx.line_width = 2
			ctx.begin_path(); ctx.arc(x, y, R * 0.66, 0, TAU); ctx.stroke_path()
		"galaxy", "core":
			var R: float = f.R
			var cr: float = R * (0.7 if f.kind == "core" else 0.35)
			ctx.additive = true
			ctx.alpha = a * 0.8; ctx.draw_tex(G.soft("#fff5dc", 64), x - cr, y - cr, cr * 2, cr * 2)
			ctx.alpha = a * 0.35; ctx.draw_tex(G.soft(f.col, 64), x - cr * 1.6, y - cr * 1.6, cr * 3.2, cr * 3.2)
			ctx.alpha = a; ctx.draw_tex(f.tex, x - f.s / 2, y - f.s / 2, f.s, f.s)
		"rock":
			ctx.translate(x, y)
			ctx.fill = U.col("#0d0f1c"); ctx.stroke = U.col(f.col, 0.5); ctx.line_width = 1.2
			ctx.begin_path()
			var pts: PackedVector2Array = f.pts
			for i in pts.size():
				if i: ctx.line_to(pts[i].x, pts[i].y)
				else: ctx.move_to(pts[i].x, pts[i].y)
			ctx.close_path(); ctx.fill_path(); ctx.stroke_path()
	ctx.restore()


func _drawSet(ctx: Ctx, set_: Dictionary, a: float, quality: int) -> void:
	if quality > 0:
		for f: Dictionary in set_.feats: _drawFeat(ctx, f, a * (0.8 if f.get("rock") else 1.0))
	_drawFeat(ctx, set_.planet, a)


func draw(ctx: Ctx, quality := 2) -> void:
	if cur == null: setSector(0, true)
	var W := G.W
	var H := G.H
	var fading: bool = prev != null and fade < 1
	ctx.save()
	_drawNebulaBuf(ctx, fading, quality)
	# при смене сектора старая планета и детали гаснут, новые проявляются
	if fading: _drawSet(ctx, prev, 1 - fade, quality)
	_drawSet(ctx, cur, fade if fading else 1.0, quality)
	# звёзды
	var t := Time.get_ticks_msec() / 1000.0
	var col := U.col(sec.get("star", "#ffffff"))
	ctx.fill = col
	var stretch := warp
	for st: Dictionary in stars:
		if quality == 0 and st.layer == 0: continue
		var tw: float = 1.0 if st.layer == 0 else 0.65 + 0.35 * sin(t * st.ts + st.tw)
		ctx.alpha = st.a * tw
		if stretch > 0.05:
			var len: float = st.s + stretch * (st.layer + 1) * 40
			ctx.fill_rect(st.x, st.y - len, st.s, len)
		else:
			ctx.fill_rect(st.x, st.y, st.s, st.s)
	# яркие звёзды с лучами, кометы и далёкие корабли
	if quality > 0:
		var sp := spike()
		ctx.additive = true
		for b: Dictionary in bright:
			var k: float = 0.45 + 0.4 * sin(t * b.sp + b.ph)
			var s: float = b.s * (0.8 + 0.3 * k)
			ctx.alpha = k
			ctx.draw_tex(sp, b.x - s, b.y - s, s * 2, s * 2)
		ctx.alpha = 1.0
		for c: Dictionary in comets:
			var a := minf(1, c.life)
			var d := Vector2(c.vx, c.vy).length()
			var dir := Vector2(c.vx, c.vy) / d
			var tail: Vector2 = Vector2(c.x, c.y) - dir * c.len
			var nrm := Vector2(-dir.y, dir.x)
			ctx.fill_poly(PackedVector2Array([Vector2(c.x, c.y) + nrm, Vector2(c.x, c.y) - nrm, tail - nrm * 0.3, tail + nrm * 0.3]),
				PackedColorArray([Color(1, 1, 1, 0.9 * a), Color(1, 1, 1, 0.9 * a), Color(col.r, col.g, col.b, 0), Color(col.r, col.g, col.b, 0)]))
		ctx.additive = false
		for s: Dictionary in ships:
			ctx.alpha = 0.28
			G.draw(ctx, s.spr, s.x, s.y, s.w, PI if s.vy > 0 else 0.0)
		ctx.alpha = 1.0
	# пыль скорости — только во время гиперпрыжка, у штриха затухающий хвост
	if quality > 0 and stretch > 0.05:
		ctx.fill = U.col("#9fc4ff")
		var k := minf(1, stretch * 3)
		for d: Dictionary in dust:
			var len: float = d.len * (1 + stretch * 6)
			ctx.alpha = d.a * 2.5 * k
			ctx.fill_rect(d.x, d.y - len * 0.4, 1, len * 0.4)
			ctx.alpha = d.a * 1.1 * k
			ctx.fill_rect(d.x, d.y - len, 1, len * 0.6)
	if quality > 0: _draw_weather(ctx, quality)
	ctx.restore()
