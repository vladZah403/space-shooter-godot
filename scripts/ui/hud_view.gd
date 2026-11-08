extends Control
## Боевой HUD (перенос #hud и ui.updateHud из JS): счёт и волна, кредиты и контейнеры, жизни и щит, уровень и
## полоса опыта, полоса босса с фазами и щитом, комбо, значки бонусов, кнопки оружия, имплантов, бомбы и паузы.
## Рисуется через Ctx (как холст в JS) на своём слое; кнопки — невидимые области нажатия поверх рисунка.

const BUFF_ICONS := {"power": "🔥", "spread": "⚡", "multi": "✚", "rapid": "⚡", "magnet": "🧲", "freeze": "❄"}

var ctx: Ctx
var _pause: Button
var _bomb: Button
var _wbtns: Array = []      # [{ btn, wid }]
var _skbtns: Array = []     # [{ btn, id, slot }]
var _hitT := 0.0
var _coinBump := 0.0
var _lastCoins := -1
var _lastLives := -1
var _loseT := 0.0
var _scorePop := 0.0
var _lastScore := 0
var _comboA := 0.0
var t := 0.0


func _ready() -> void:
	Kit.full(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	ctx = Ctx.new(get_canvas_item())
	_pause = _area(func(): if Game.state == "play": Game.pause())
	_bomb = _area(func(): Game.useBomb())


## невидимая кнопка-область
func _area(fn: Callable) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for k in ["normal", "hover", "pressed", "disabled", "focus"]: b.add_theme_stylebox_override(k, StyleBoxEmpty.new())
	b.button_down.connect(func():
		A.play("click")
		Haptic.select()
		fn.call())
	add_child(b)
	return b


func open() -> void:
	visible = true
	_lastCoins = -1; _lastLives = -1
	for w in _wbtns: w.btn.queue_free()
	for s in _skbtns: s.btn.queue_free()
	_wbtns.clear(); _skbtns.clear()
	var p: Pl = Game.player
	if p:
		for wid in p.weapons:
			var id: String = wid
			_wbtns.append({"btn": _area(func(): Game.setWeapon(id)), "wid": id})
	var ids: Array = Game.activeSkills()
	for i in ids.size():
		var slot := i
		_skbtns.append({"btn": _area(func(): Game.useSkill(slot)), "id": ids[i], "slot": i})


func close() -> void:
	visible = false
	ctx.begin()


func hit_flash() -> void:
	_hitT = 0.35


# ── геометрия ──
func _top() -> float:
	return Hud.safe_top()


func top_inset() -> float:
	# как в JS: низ второй строки (верх + 82) + 38 — там же полоса босса
	return _top() + 120.0


func bottom_inset() -> float:
	return 84.0 + Hud.safe_bottom()


func _fieldX() -> float:
	return G.FX


func update_hud(dt: float) -> void:
	t += dt
	_hitT = maxf(0, _hitT - dt)
	_coinBump = maxf(0, _coinBump - dt)
	_loseT = maxf(0, _loseT - dt)
	_scorePop = maxf(0, _scorePop - dt)
	_layout()
	_draw_hud()


func _layout() -> void:
	var fx := _fieldX()
	var fw := G.FW
	var top := _top()
	_pause.position = Vector2(fx + 12, top + 10); _pause.size = Vector2(44, 44)
	var by := G.H - Hud.safe_bottom() - 12 - 56
	for i in _wbtns.size():
		var b: Button = _wbtns[i].btn
		b.position = Vector2(fx + 12 + i * 62, by); b.size = Vector2(56, 56)
		b.visible = _wbtns.size() > 1
	_bomb.position = Vector2(fx + fw - 12 - 60, by - 2); _bomb.size = Vector2(60, 60)
	for i in _skbtns.size():
		var b: Button = _skbtns[i].btn
		b.position = Vector2(fx + fw - 12 - 60 - (i + 1) * 64, by); b.size = Vector2(56, 56)


func _txt(text: String, x: float, y: float, size: int, col: Color, weight := 800, align := 1, outline := 0) -> void:
	ctx.font = Kit.font(weight)
	ctx.fill = col
	ctx.fill_text(text, x, y, size, align, outline, Color(0, 0, 0, 0.75))


func _heart(x: float, y: float, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 24:
		var a := i / 24.0 * TAU
		# сердце: x = 16 sin³, y = 13 cos − 5 cos 2 − 2 cos 3 − cos 4
		var hx := 16 * pow(sin(a), 3)
		var hy := 13 * cos(a) - 5 * cos(2 * a) - 2 * cos(3 * a) - cos(4 * a)
		pts.append(Vector2(x + hx * s / 34.0, y - hy * s / 34.0))
	var cols := PackedColorArray()
	for p in pts: cols.append(col)
	ctx.fill_poly(pts, cols)


func _ring(x: float, y: float, r: float, frac: float, col: Color, w := 3.0) -> void:
	ctx.stroke = Color(1, 1, 1, 0.12); ctx.line_width = w
	ctx.begin_path(); ctx.arc(x, y, r, 0, TAU); ctx.stroke_path()
	if frac > 0.001:
		ctx.stroke = col
		ctx.begin_path(); ctx.arc(x, y, r, -PI / 2, -PI / 2 + TAU * clampf(frac, 0, 1)); ctx.stroke_path()


func _draw_hud() -> void:
	ctx.begin()
	var g = Game
	var p: Pl = g.player
	var run: Dictionary = g.run
	if p == null or run.is_empty(): return
	var fx := _fieldX()
	var fw := G.FW
	var top := _top()
	var cx := fx + fw / 2
	# вспышка урона по краям экрана
	if _hitT > 0:
		ctx.alpha = _hitT / 0.35 * 0.55
		ctx.draw_tex(FX._vignette_tex("#ff2a48"), 0, 0, G.W, G.H)
		ctx.alpha = 1.0
	# счётчик кадров (настройка «Показывать FPS»)
	if M.s.settings.get("fps", false):
		_txt("%d FPS • Q%d" % [int(round(Main.fps)), Main.quality], fx + 12, G.H - Hud.safe_bottom() - 80, 10, Kit.GREEN, 700, 0, 3)
	# ── верх: пауза, счёт и волна, кредиты и контейнеры ──
	ctx.fill = Color(8 / 255.0, 12 / 255.0, 30 / 255.0, 0.6)
	ctx.begin_path(); ctx.round_rect(fx + 12, top + 10, 44, 44, 14); ctx.fill_path()
	ctx.fill = Kit.TEXT
	ctx.fill_rect(fx + 27, top + 22, 5, 20); ctx.fill_rect(fx + 36, top + 22, 5, 20)
	if run.score != _lastScore:
		_lastScore = run.score; _scorePop = 0.2
	var sp := 1.0 + 0.12 * (_scorePop / 0.2)
	_txt(U.fmt(run.score), cx, top + 36, int(24 * sp), Kit.TEXT, 900, 1, 4)
	var wave_txt := ""
	if g.wave: wave_txt = ("БОСС • ВОЛНА %d" if g.boss else "ВОЛНА %d") % g.wave.n
	_txt(wave_txt, cx, top + 52, 11, Kit.MUTED, 700, 1, 3)
	if run.coins != _lastCoins:
		if _lastCoins >= 0: _coinBump = 0.3
		_lastCoins = run.coins
	var ctext := U.fmt(run.coins)
	ctx.font = Kit.font(800)
	var cw := ctx.text_width(ctext, 14) + 40
	var cs := 1.0 + 0.15 * sin(_coinBump / 0.3 * PI)
	var px := fx + fw - 12 - cw
	ctx.save(); ctx.translate(px + cw / 2, top + 26); ctx.scale(cs, cs)
	ctx.fill = Color(8 / 255.0, 12 / 255.0, 30 / 255.0, 0.6); ctx.stroke = Color(1, 200 / 255.0, 61 / 255.0, 0.28); ctx.line_width = 1
	ctx.begin_path(); ctx.round_rect(-cw / 2, -16, cw, 32, 16); ctx.fill_path(); ctx.stroke_path()
	ctx.draw_tex(G.proc("coin"), -cw / 2 + 6, -9, 18, 18)
	_txt(ctext, -cw / 2 + 28, 5, 14, Kit.GOLD, 800, 0)
	ctx.restore()
	var chests: Array = run.get("chests", [])
	if not chests.is_empty():
		var chx := px - 62
		ctx.fill = Color(8 / 255.0, 12 / 255.0, 30 / 255.0, 0.6)
		ctx.begin_path(); ctx.round_rect(chx, top + 10, 54, 32, 16); ctx.fill_path()
		var ic: Texture2D = G.chest(chests[-1]).icon
		ctx.draw_tex(ic, chx + 6, top + 16, 26, 26 * ic.get_height() / ic.get_width())
		_txt(str(chests.size()), chx + 36, top + 31, 13, Kit.TEXT, 800, 0)
	# ── вторая строка: жизни и уровень ──
	var r2 := top + 72
	var shown := mini(p.maxLives, 8)
	if p.lives < _lastLives: _loseT = 0.45
	_lastLives = p.lives
	for i in shown:
		var on := i < p.lives
		var lose := _loseT > 0 and i == p.lives
		var hs := 17.0 * (1 + (0.4 * _loseT / 0.45 if lose else 0.0))
		if on:
			ctx.additive = true; ctx.alpha = 0.6
			ctx.draw_tex(G.soft("#ff4d6d", 32), fx + 14 + i * 19 - 4, r2 - 12, 26, 26)
			ctx.additive = false; ctx.alpha = 1.0
		_heart(fx + 14 + i * 19 + 9, r2 + 1, hs, U.col("#ff4d6d") if on else Color(1, 1, 1, 0.14))
	var lx := fx + 14 + shown * 19 + 4
	if p.maxLives > 8:
		_txt(str(p.lives), lx + 2, r2 + 5, 11, U.col("#ff8fa3"), 800, 0); lx += 18
	if p.shield:
		ctx.additive = true; ctx.alpha = 0.7
		ctx.draw_tex(G.soft("#3de0ff", 32), lx - 4, r2 - 13, 26, 26)
		ctx.additive = false; ctx.alpha = 1.0
		ctx.stroke = Kit.CYAN; ctx.line_width = 2
		ctx.begin_path(); ctx.move_to(lx + 9, r2 - 8); ctx.line_to(lx + 17, r2 - 5); ctx.line_to(lx + 16, r2 + 3); ctx.line_to(lx + 9, r2 + 9); ctx.line_to(lx + 2, r2 + 3); ctx.line_to(lx + 1, r2 - 5); ctx.close_path(); ctx.stroke_path()
		lx += 22
	# уровень и полоса до следующего улучшения
	var bx := lx + 8
	ctx.fill = Color(61 / 255.0, 1, 162 / 255.0, 0.16); ctx.stroke = Color(61 / 255.0, 1, 162 / 255.0, 0.6); ctx.line_width = 1
	ctx.begin_path(); ctx.round_rect(bx, r2 - 11, 22, 22, 7); ctx.fill_path(); ctx.stroke_path()
	_txt(str(run.level), bx + 11, r2 + 4, 10, Kit.GREEN, 900)
	var barx := bx + 28
	var barw := fx + fw - 14 - barx
	ctx.fill = Color(1, 1, 1, 0.1)
	ctx.begin_path(); ctx.round_rect(barx, r2 - 3, barw, 6, 3); ctx.fill_path()
	var pp := clampf(g.powerProgress(), 0, 1)
	if pp > 0:
		ctx.fill_poly(PackedVector2Array([Vector2(barx, r2 - 3), Vector2(barx + barw * pp, r2 - 3), Vector2(barx + barw * pp, r2 + 3), Vector2(barx, r2 + 3)]),
			PackedColorArray([U.col("#1fd18a"), U.col("#b6ffde"), U.col("#b6ffde"), U.col("#1fd18a")]))
	# ── босс: имя с фазой, полоса на три части, щит ──
	var boss: En = g.boss
	var extra := 0.0
	if boss and boss.alive:
		var y := top + 100
		var nm: String = boss.bdef.name + (" · ФАЗА %d" % boss.phase if boss.phase > 1 else "")
		_txt(nm, cx, y, 11, U.col("#ff6b81"), 900, 1, 3)
		var x0 := fx + 14
		var w := fw - 28
		ctx.fill = Color(40 / 255.0, 0, 10 / 255.0, 0.65); ctx.stroke = Color(1, 77 / 255.0, 109 / 255.0, 0.45); ctx.line_width = 1
		ctx.begin_path(); ctx.round_rect(x0, y + 5, w, 9, 5); ctx.fill_path(); ctx.stroke_path()
		var k := maxf(0, boss.hp / boss.maxHp)
		if k > 0:
			ctx.fill_poly(PackedVector2Array([Vector2(x0 + 1, y + 6), Vector2(x0 + 1 + (w - 2) * k, y + 6), Vector2(x0 + 1 + (w - 2) * k, y + 13), Vector2(x0 + 1, y + 13)]),
				PackedColorArray([U.col("#ff2d55"), U.col("#ff7a45"), U.col("#ff7a45"), U.col("#ff2d55")]))
		if boss.shieldMax > 0 and boss.shield > 0:
			ctx.fill = U.col("#bfefff"); ctx.fill_rect(x0 + 1, y + 6, (w - 2) * boss.shield / boss.shieldMax, 3)
		ctx.fill = Color(12 / 255.0, 0, 6 / 255.0, 0.9)
		ctx.fill_rect(x0 + w / 3.0 - 1, y + 5, 2, 9); ctx.fill_rect(x0 + w * 2 / 3.0 - 1, y + 5, 2, 9)
		extra = 30
	# ── значки бонусов (слева) и комбо (справа) ──
	var chips: Array = []
	var an = g.anomaly()
	if an:
		var ad: Dictionary = D.ANOMALIES[an]
		chips.append([ad.color, "an_" + an, ad.ico, 1.0, "+%d%%" % int(round(ad.bonus * 100))])
	var wev = Events.active()
	if wev: chips.append([wev.color, "", wev.ico, 1.0, ""])
	if run.waveDamage == 0 and g.wave and not g.wave.cleared and g.state == "play": chips.append(["#3dffa2", "", "★", 1.0, "×2"])
	for k in g.buffs: chips.append([D.POWERUPS[k].color, "", BUFF_ICONS.get(k, "★"), g.buffs[k] / D.POWERUPS[k].dur, ""])
	for id in run.skillFx:
		if run.skillFx[id] > 0 and D.SKILLS.has(id): chips.append(["#3de0ff", id, D.SKILLS[id].ico, run.skillFx[id] / maxf(0.01, D.SKILLS[id].dur), ""])
	if run.overload > 0: chips.append(["#ffc83d", "", "⚡", 1.0, ""])
	var chx2 := fx + 12
	var chy := top + 92 + extra
	for c in chips:
		var col := U.col(c[0])
		var cwid := 30.0
		ctx.font = Kit.font(700)
		if c[4] != "": cwid += ctx.text_width(c[4], 10) + 10
		if c[4] != "":
			ctx.fill = Color(8 / 255.0, 12 / 255.0, 30 / 255.0, 0.66)
			ctx.begin_path(); ctx.round_rect(chx2, chy, cwid, 30, 15); ctx.fill_path()
			_txt(c[4], chx2 + 34, chy + 19, 10, col, 700, 0)
		ctx.fill = Color(8 / 255.0, 12 / 255.0, 30 / 255.0, 0.7); ctx.fill_circle(chx2 + 15, chy + 15, 15)
		_ring(chx2 + 15, chy + 15, 13.5, c[3], col, 2.5)
		_icon(c[1], c[2], chx2 + 15, chy + 15, 18)
		chx2 += cwid + 6
	var comboOn: bool = run.combo >= 5
	_comboA = move_toward(_comboA, 1.0 if comboOn else 0.0, get_process_delta_time() * 4)
	if _comboA > 0.01:
		var rx := fx + fw - 12 + (1 - _comboA) * 16
		ctx.alpha = _comboA
		var fever: bool = run.get("fever", false)
		var mc := U.col("#ff5cf0") if fever else Kit.GOLD
		_txt("x%.1f" % g.comboMul(), rx, top + 92 + extra + 22, 22, mc, 900, 2, 4)
		_txt("КОМБО %d" % run.combo, rx, top + 92 + extra + 36, 10, Kit.MUTED, 800, 2, 3)
		var ct := clampf(run.comboT / (5.2 if g.relic("r_combo") else 2.6), 0, 1)
		ctx.fill = Color(1, 1, 1, 0.12); ctx.fill_rect(rx - 70, top + 92 + extra + 41, 70, 3)
		ctx.fill = mc; ctx.fill_rect(rx - 70, top + 92 + extra + 41, 70 * ct, 3)
		ctx.alpha = 1.0
	# ── низ: оружие, импланты, бомба ──
	for i in _wbtns.size():
		if _wbtns.size() <= 1: break
		var wid: String = _wbtns[i].wid
		var b: Button = _wbtns[i].btn
		var r := Rect2(b.position, b.size)
		var on := p.weapon == wid
		var wc := U.col(D.WEAPONS[wid].color)
		ctx.fill = Color(wc, 0.18) if on else Color(8 / 255.0, 12 / 255.0, 30 / 255.0, 0.66)
		ctx.stroke = wc if on else Color(1, 1, 1, 0.14); ctx.line_width = 2 if on else 1
		ctx.begin_path(); ctx.round_rect(r.position.x, r.position.y, r.size.x, r.size.y, 16); ctx.fill_path(); ctx.stroke_path()
		weaponIcon(ctx, wid, r.get_center().x, r.get_center().y, r.size.x * 0.82)
		_txt(str(i + 1), r.position.x + 9, r.position.y + 15, 10, Kit.MUTED, 800, 1)
		var res = g.weaponRes(wid)
		if res:
			var rk: float = res.k
			ctx.fill = Color(0, 0, 0, 0.5); ctx.fill_rect(r.position.x + 8, r.end.y - 8, r.size.x - 16, 3)
			ctx.fill = Kit.RED if res.kind == "reload" else (Color(0.5, 0.5, 0.6) if (res.kind == "energy" and rk <= 0) else wc)
			ctx.fill_rect(r.position.x + 8, r.end.y - 8, (r.size.x - 16) * rk, 3)
	for s in _skbtns:
		var b: Button = s.btn
		var r := Rect2(b.position, b.size)
		var id: String = s.id
		var sk: Dictionary = D.SKILLS[id]
		var cd: float = run.skillCd.get(id, 0.0)
		var fxv: float = run.skillFx.get(id, 0.0)
		var c := r.get_center()
		ctx.fill = Color(8 / 255.0, 12 / 255.0, 30 / 255.0, 0.7); ctx.fill_circle(c.x, c.y, 27)
		var frac := fxv / maxf(0.01, sk.dur) if fxv > 0 else (1 - cd / maxf(0.01, sk.cd * g.st.cdMul) if cd > 0 else 1.0)
		_ring(c.x, c.y, 26, frac, Kit.GREEN if fxv > 0 else (Kit.MUTED if cd > 0 else Kit.CYAN), 3)
		ctx.alpha = 0.45 if cd > 0 and fxv <= 0 else 1.0
		_icon(id, sk.ico, c.x, c.y, 30)
		ctx.alpha = 1.0
		if cd > 0 and fxv <= 0: _txt(str(int(ceil(cd))), c.x, c.y + 6, 16, Kit.TEXT, 900, 1, 4)
	# бомба
	var br := Rect2(_bomb.position, _bomb.size)
	var bc := br.get_center()
	var empty := p.bombs <= 0
	ctx.fill = Color(1, 138 / 255.0, 61 / 255.0, 0.12 if not empty else 0.04); ctx.stroke = Color(1, 138 / 255.0, 61 / 255.0, 0.55 if not empty else 0.2); ctx.line_width = 2
	ctx.begin_path(); ctx.arc(bc.x, bc.y, 29, 0, TAU); ctx.fill_path(); ctx.stroke_path()
	ctx.alpha = 0.4 if empty or p.bombCd > 0 else 1.0
	Hud.drawBadge(ctx, {"color": "#ff8a3d", "ico": "bomb"}, bc.x, bc.y, 42)
	ctx.alpha = 1.0
	ctx.fill = Kit.ORANGE; ctx.fill_circle(br.end.x - 10, br.position.y + 10, 10)
	_txt(str(p.bombs), br.end.x - 10, br.position.y + 14, 11, Color("#1b0e00"), 900)


## значок: кадр атласа или эмодзи
func _icon(sprite: String, emoji: String, x: float, y: float, s: float) -> void:
	if sprite != "" and G.has(sprite):
		G.draw(ctx, sprite, x, y, s)
	elif emoji != "":
		ctx.font = Kit.font(600)
		ctx.fill = Kit.TEXT
		ctx.fill_text(emoji, x, y + s * 0.3, int(s * 0.8), 1)


## иконка оружия (G.weaponIcon в JS): из спрайтов эффектов
static func weaponIcon(c: Ctx, wid: String, cx: float, cy: float, s: float) -> void:
	c.save()
	c.additive = true
	match wid:
		"laser":
			G.draw(c, "pb_bolt_m", cx - s * 0.16, cy, s * 0.26); G.draw(c, "pb_bolt_m", cx + s * 0.16, cy, s * 0.26)
		"shotgun":
			var tt := G.tinted("pb_orb", {"hue": 45, "alpha": true})
			for i in range(-2, 3):
				var a := i * 0.32 - PI / 2
				c.draw_tex(tt, cx + cos(a) * s * 0.3 - s * 0.1, cy + s * 0.12 + sin(a) * s * 0.3 - s * 0.1, s * 0.2, s * 0.2)
		"rocket":
			c.additive = false
			G.draw(c, "fx_rocket2", cx, cy, s * 0.34, 0.6)
		"plasma":
			var tt := G.tinted("fx_plasma2" if G.has("fx_plasma2") else "eb_fire", {"hue": 305, "alpha": true})
			if tt: G.draw_canvas(c, tt, cx, cy, s * 0.84)
		"lightning":
			c.stroke = U.col("#fff36b"); c.line_width = s * 0.07
			c.begin_path(); c.move_to(cx - s * 0.2 + s * 0.12, cy - s * 0.38); c.line_to(cx - s * 0.12, cy + s * 0.02); c.line_to(cx + s * 0.08, cy - s * 0.02); c.line_to(cx + s * 0.18 - s * 0.1, cy + s * 0.38); c.stroke_path()
		"arc":
			c.stroke = U.col("#7ff6ff"); c.line_width = s * 0.07
			for i in 3:
				c.begin_path(); c.arc(cx, cy + s * 0.3, s * (0.25 + i * 0.13), -PI * 0.82, -PI * 0.18); c.stroke_path()
		"darkmatter":
			G.draw(c, "fx_vortex", cx, cy, s * 0.82)
		"boomerang":
			Game.drawBlade(c, cx, cy, s * 0.36, 0.5)
		"gravgun":
			c.alpha = 0.6
			c.stroke = U.col("#5cffb0"); c.line_width = s * 0.04
			for i in 2:
				c.begin_path(); c.arc(cx, cy, s * (0.24 + i * 0.12), 0, TAU); c.stroke_path()
			c.alpha = 1.0
			G.draw_canvas(c, G.tinted("pb_orb", {"hue": 150, "alpha": true}), cx, cy, s * 0.36)
		"flail":
			c.fill = Color("#8b97a8")
			for i in 3: c.fill_circle(cx - s * 0.3 + i * s * 0.1, cy + s * 0.3 - i * s * 0.1, s * 0.035)
			Game.drawSaw(c, cx + s * 0.08, cy - s * 0.08, s * 0.24, 0.3, 0.6)
			c.additive = false
			c.draw_tex(G.proc("voidcore"), cx - s * 0.14, cy - s * 0.14, s * 0.28, s * 0.28)
	c.restore()
