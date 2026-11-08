extends Node
## Игровая логика (автозагрузка Game) — перенос game.js: забег, характеристики, оружие, снаряды,
## столкновения, урон, награды, бонусы, бомба и навыки, вражеские снаряды, улучшения забега, волны,
## кат-сцены, отрисовка мира. Имена функций и полей — как в JS-версии.
## run, wave, st, diff — словари (в JS у них много необязательных полей).

const BURN_T := 3.0
const FIRE_DUR := 1.4
const DMG_NUM_T := 0.35

## чем сбит игрок — показывается на экране итогов
const SHOT_NAMES := {"mine": "мина", "needle": "прицельный выстрел", "long": "прицельный выстрел", "fire": "огненный шар", "ink": "чернильная бомба",
	"egg": "кладка роя", "shard": "осколок кристалла", "feather": "перо Феникса", "junk": "обломок", "eye": "взгляд Оверлорда", "plaser": "фиолетовый лазер",
	"rocket": "своя ракета от Гравитона", "mirror": "лазер от Зеркала"}

## виды вражеских снарядов
const EB := {
	"orb": {"sprite": "eb_orb", "w": 15, "r": 5.5, "color": "#ff6b3d"},
	"bolt": {"sprite": "eb_bolt_s", "w": 13, "r": 5, "color": "#ff4d3d", "rotate": true},
	"long": {"sprite": "eb_bolt_l", "w": 13, "r": 5, "color": "#ff3d5a", "rotate": true},
	"needle": {"sprite": "eb_needle", "w": 18, "r": 6, "color": "#ff6b6b", "rotate": true},
	"fire": {"sprite": "eb_fire", "w": 26, "r": 10, "color": "#ff9f3d"},
	"dot": {"sprite": "eb_orb", "w": 11, "r": 4, "color": "#ff5cf0", "tint": 305},
	"green": {"sprite": "eb_orb", "w": 15, "r": 5.5, "color": "#7dff6b", "tint": 110},
	"violet": {"sprite": "eb_orb", "w": 15, "r": 5.5, "color": "#b06bff", "tint": 275},
	"blue": {"sprite": "eb_orb", "w": 15, "r": 5.5, "color": "#4cc9ff", "tint": 200},
	"mine": {"sprite": "fx_mine", "proc": "mine", "w": 26, "r": 9, "color": "#ff3d5a"},
	"shard": {"sprite": "eb_needle", "w": 16, "r": 5, "color": "#3dffd2", "tint": 165, "rotate": true},
	"feather": {"sprite": "eb_bolt_l", "w": 14, "r": 5, "color": "#ffd23d", "tint": 40, "rotate": true},
	"ink": {"sprite": "eb_orb", "w": 30, "r": 11, "color": "#8a5cff", "tint": 255},
	"egg": {"sprite": "eb_orb", "w": 26, "r": 9, "color": "#a6ff3d", "tint": 95},
	"junk": {"sprite": "eb_fire", "w": 18, "r": 7, "color": "#ff8a3d", "tint": 20},
	"eye": {"sprite": "eb_orb", "w": 17, "r": 6, "color": "#ff3dd2", "tint": 320},
	"plaser": {"sprite": "eb_plaser", "w": 9, "r": 4, "color": "#c86bff", "rotate": true},
	"rocket": {"sprite": "fx_rocket", "w": 13, "r": 6, "color": "#ff8a3d", "rotate": true},
	"mirror": {"sprite": "eb_plaser", "w": 9, "r": 4, "color": "#7ff6ff", "tint": 185, "rotate": true},
}
const EN_SPR := {"std": "en_orange", "boss": "en_blue", "big": "en_green"}
const EN_COL := {"std": "#ffb03d", "boss": "#5cc8ff", "big": "#5cff7a"}

var state := "idle"           # idle | play | cutscene | pause | perk | tip | dying | revive | over
var mode := "normal"
var diffId := "normal"
var diff: Dictionary = {}
var coinK := 1.0
var t := 0.0
var timeScale := 1.0
var slowT := 0.0
## камера (Godot): наезд на точку поля — смерть босса, его появление. z — текущее увеличение, tz — цель,
## hold — сколько ещё держать (с, по реальному времени: замедление мира камеру не тормозит)
var cam := {"x": 0.0, "y": 0.0, "z": 1.0, "tz": 1.0, "hold": 0.0}
## аномалия «Затмение» (Godot): насколько сгустилась тьма 0…1 (плавно приходит и уходит)
var darkK := 0.0
var _dark_mat: ShaderMaterial
var _dark_l := PackedVector4Array()
var stopT := 0.0
var player: Pl = null
var bullets: Array[Bl] = []
var ebullets: Array[Eb] = []
var enemies: Array[En] = []
var pickups: Array[Pk] = []
var drones: Array = []        # { x, y, cd }
var boss: En = null
var wave = null               # словарь волны или null
var run: Dictionary = {}
var st: Dictionary = {}
var buffs := {}
var blasts: Array = []
var keys := {}
var pointer := {"id": -1, "x": 0.0, "y": 0.0, "downT": 0.0, "downX": 0.0, "downY": 0.0, "moved": 0.0, "lastTap": 0.0, "lastTapX": 0.0, "lastTapY": 0.0}
var ov := {"rail": null, "hole": null, "beams": [], "lasers": [], "fire": []}
var attract := {"t": 0.0}
var hudDirty := true
var timers: Array = []
var scene = null              # кат-сцена (bossScene / jumpScene)
var offerKind := ""
var critFxT := -1.0
var _cover: Array[En] = []


# ════════════════════════════════════════════════════════════
# ЗАПУСК / ПАУЗА / КОНЕЦ
# ════════════════════════════════════════════════════════════
func _ready() -> void:
	diff = D.DIFFS.normal


## отложенное действие по игровому времени (на паузе не идёт, при новом забеге сбрасывается)
func after(sec: float, fn: Callable) -> void:
	timers.append({"t": sec, "fn": fn})


func runTimers(dt: float) -> void:
	if timers.is_empty(): return
	var due: Array = []
	for tm in timers:
		tm.t -= dt
		if tm.t <= 0: due.append(tm)
	if due.is_empty(): return
	timers = timers.filter(func(tm): return tm.t > 0)
	for tm in due: tm.fn.call()


## o.challenge — испытание дня { date, mods, weapon }; o.mode — режим забега
func start(newDiffId: String, o := {}) -> void:
	var s: Dictionary = M.s
	var ch = o.get("challenge")
	mode = o.mode if ch == null and o.has("mode") and D.MODES.has(o.mode) else "normal"
	diffId = newDiffId if D.DIFFS.has(newDiffId) else "normal"
	diff = D.DIFFS[diffId]
	if ch != null:
		# правила дня меняют копию сложности, сама таблица сложностей не трогается
		diff = diff.duplicate()
		if "swift" in ch.mods:
			diff.spd *= 1.25; diff.coins *= 1.5
		if "elite" in ch.mods: diff.elite = maxf(0.09, diff.elite * 3)
	s.settings.diff = diffId
	# страховка от фарма лёгкой сложности (M.overpowerK) — считается один раз на забег
	coinK = M.overpowerK(diffId)
	clearWorld()
	var S := G.S
	run = {
		"score": 0, "coins": 0, "kills": 0, "bosses": 0, "bossIds": [], "combo": 0, "comboT": 0.0, "maxCombo": 0,
		"level": 1, "xp": 0.0, "pendingPerks": 0, "perks": {}, "perkCount": 0, "rerolls": 0, "relics": {}, "chests": [], "map": null, "mapNode": null, "mapStep": 0,
		"time": 0.0, "shots": 0, "hits": 0, "pickups": 0, "reviveUsed": false, "phoenixUsed": false, "featherUsed": false,
		"waveDamage": 0, "bossDamage": 0.0, "bossDamaged": false, "oneHpT": 0.0, "killsForVamp": 0, "critsForVamp": 0, "detCount": 0, "bloodKills": 0, "evo": {}, "lastHit": "", "hitAt": 0.0,
		"skillCd": {}, "skillFx": {}, "overload": 0.0, "regenT": 0.0, "shieldRegenT": 0.0, "repairT": 0.0, "emergT": 0.0, "stormT": 0.0, "nanoT": 0.0, "fever": false, "nextCrit": false,
		"lastAchCheck": 0.0, "sector": 0, "lastEvent": 0, "lastEventId": "", "energy": 1.0, "arc": 0.0, "focus": {"uid": 0, "n": 0, "t": 0.0},
		"mods": {}, "pilot": s.pilot if D.PILOTS.has(s.pilot) and M.pilotUnlocked(s.pilot) else "kai",
		"challenge": ch, "noDrops": ch != null and "nodrops" in ch.mods,
		"anomaly": null, "lastAnomaly": "", "anomalies": 0, "tipQ": [], "waveRng": null, "perkRng": null,
		# 4.3.2: боссы под огневую мощь (bosses.gd adapt): bossDps — урон в секунду по прошлому боссу;
		# bossK — запас прочности первого босса, если «Боевая мощь» вдвое и больше выше рекомендуемой
		"bossDps": 0.0, "bossK": U.clamp(sqrt(M.power() / maxf(100.0, diff.power) / 2.0), 1.0, D.BOSS_ADAPT.start),
	}
	# рогалик: порядок секторов и боссов свой в каждом забеге; первыми всегда Орбита Земли и Страж
	var rnd: Callable = U.seeded(U.hash_str("order:" + ch.date)) if ch != null else Callable(U, "random")
	var shuffle := func(a: Array) -> Array:
		for i in range(a.size() - 1, 0, -1):
			var j := int(rnd.call() * (i + 1))
			var tmp = a[i]; a[i] = a[j]; a[j] = tmp
		return a
	run.sectorOrder = [0] + shuffle.call(range(1, D.SECTORS.size()))
	# боссы мешаются внутри своей ступени сложности: ранние (до 4-го), средние, поздние; Оверлорд — финальный
	run.bossOrder = [0] + shuffle.call(range(1, 4)) + shuffle.call(range(4, 9)) + shuffle.call(range(9, 12)) + [12]
	if ch != null and "glass" in ch.mods: run.perks.glass = 1
	# испытание дня: свои генераторы для состава волн и выбора улучшений — одинаковые у всех в этот день
	if ch != null:
		run.waveRng = U.seeded(U.hash_str("waves:" + ch.date))
		run.perkRng = U.seeded(U.hash_str("perks:" + ch.date))
	st = computeStats()
	var ship: Dictionary = D.SHIPS[s.ship.model]
	player = Pl.new()
	var p := player
	p.x = G.FW / 2; p.y = G.H * 0.8
	p.w = 56 * S * (ship.scale if ship.scale else 1.0); p.r = 6 * S; p.pickR = 28 * S
	p.weapons = s.weapons.loadout.duplicate()
	p.weapon = s.weapons.loadout[0] if s.weapons.loadout.size() else "laser"
	var pil: String = run.pilot
	p.maxLives = int(D.BASE_LIVES + ship.stats.get("lives", 0) + (1 if pil == "bork" else 0) + skillLv("sk_armor"))
	p.lives = p.maxLives
	p.bombs = int(1 + ship.stats.get("bombs", 0) + (2 if pil == "rex" else 0))
	p.wingCd = 0.2
	if ch != null and "weapon" in ch.mods:
		p.weapons = [ch.weapon]; p.weapon = ch.weapon
	Comp.start()
	if run.perks.get("glass", 0):
		p.maxLives = 1; p.lives = 1
	# 4.1: реликвии из коллекции, взятые в забег
	RunMap.startRelics()
	if ch != null and "perks" in ch.mods:
		for i in 3:
			var choices: Array = U.with_rng(run.perkRng, perkChoices)
			for x in choices:
				if not x.filler and x.id != "glass":
					grantPerk(x.id, true)
					break
	buffs = {}
	wave = null
	t = 0.0; timeScale = 1.0; slowT = 0.0; stopT = 0.0
	cam = {"x": 0.0, "y": 0.0, "z": 1.0, "tz": 1.0, "hold": 0.0}
	darkK = 0.0
	Bg.setSector(0, true)
	Bg.warp = 0.6
	state = "play"
	hudDirty = true
	# в босс-раше первый босс выходит после выбора стартового модуля; до него — пустая «волна 0»
	if mode == "rush":
		wave = {"n": 0, "boss": false, "budget": 0.0, "spent": 0.0, "spawnT": 0.0, "intro": 999.0, "done": true, "cleared": true, "clearT": 0.0, "miniDone": true, "startT": t, "danger": false}
	else:
		nextWave()
	Bus.emit("runStart")
	# стартовый модуль корабля — первый выбор забега
	after(0.2 if mode == "rush" else 0.7, func(): offerModules("start"))


func clearWorld() -> void:
	bullets.clear(); ebullets.clear(); pickups.clear()
	enemies.clear(); drones.clear(); blasts.clear()
	boss = null
	timers = []
	if scene != null:
		scene = null
		Bus.emit("cinema", false)
	ov = {"rail": null, "hole": null, "beams": [], "lasers": [], "fire": []}
	E.corpses.clear()
	E.burns.clear()
	Events.reset()
	Foes.reset()
	Skills.reset()
	FX.clear()


func pause() -> void:
	if state == "cutscene": skipScene()
	if state != "play": return
	state = "pause"
	pointer.id = -1
	Bus.emit("paused", true)


func resume() -> void:
	if state != "pause": return
	state = "play"
	player.inv = maxf(player.inv, 0.6)
	Bus.emit("paused", false)


func quit() -> void:
	state = "idle"
	clearWorld()
	Bus.emit("runEnd", null)


# ════════════════════════════════════════════════════════════
# ХАРАКТЕРИСТИКИ ИГРОКА (мета-прокачка + навыки + улучшения забега)
# ════════════════════════════════════════════════════════════
func perk(id: String) -> int:
	return int(run.perks.get(id, 0)) if run else 0


func skill(id: String) -> bool:
	return bool(M.s.skills.get(id, 0))


## 3.1: ранг навыка (0 — не изучен)
func skillLv(id: String) -> int:
	return int(M.s.skills.get(id, 0))


func mod(id: String) -> int:
	return int(run.mods.get(id, 0)) if run else 0


## 4.0: реликвия забега
func relic(id: String) -> bool:
	return bool(run and run.relics.get(id, false))


## 4.2: подсказка при первой встрече с механикой — одна за всю игру
func hintOnce(id: String, title: String, text: String) -> void:
	var h: Dictionary = M.s.get_or_add("hints", {})
	if h.get(id): return
	h[id] = 1
	M.soon()
	Bus.emit("toast", {"ico": "info", "title": title, "text": text, "info": true, "hint": true, "dur": 6500})


## 4.3.2: первая встреча с аномалией, событием волны или эволюцией — пауза и окно «как работает / как
## использовать» (тексты — D.TIPS). true — окно будет (тогда обычную плашку не показываем)
func tipOnce(key: String, tip: Dictionary) -> bool:
	var seen: Dictionary = M.s.get_or_add("tips", {})
	if not run or seen.get(key) or not D.TIPS.has(key): return false
	var q: Array = run.tipQ
	for x in q:
		if x.key == key: return true
	var t2 := tip.duplicate()
	t2.key = key; t2.how = D.TIPS[key].how; t2.use = D.TIPS[key].use
	q.append(t2)
	return true


func closeTip() -> void:
	if state != "tip": return
	state = "play"
	player.inv = maxf(player.inv, 0.6)
	Bus.emit("tip", null)


## 4.2: аномалия сектора: без id — какая действует (или null), с id — действует ли эта
func anomaly(id := "") -> Variant:
	var a = run.get("anomaly") if run else null
	if id != "": return a == id
	return a


## нет бонусов: испытание «Без бонусов» или аномалия «Радиотишина»
func noDrops() -> bool:
	return bool(run and (run.noDrops or run.anomaly == "silence"))


## сектор и босс по номеру в забеге (с учётом перемешанного порядка)
func sectorIdx(k: int) -> int:
	var o = run.get("sectorOrder") if run else null
	return o[k % o.size()] if o else k % D.SECTORS.size()


func sectorDef(k: int) -> Dictionary:
	return D.SECTORS[sectorIdx(k)]


func bossDef(num: int) -> Dictionary:
	var o = run.get("bossOrder") if run else null
	var i: int = (num - 1) % D.BOSSES.size()
	return D.BOSSES[o[i] if o else i]


func computeStats() -> Dictionary:
	var s: Dictionary = M.s
	var ship: Dictionary = D.SHIPS[s.ship.model].stats
	var pres: Dictionary = M.prestigeBonus()
	var S := G.S
	var md := func(id): return mod(id)
	var pk := func(id): return perk(id)
	var sk := func(id): return skillLv(id)
	var pl := func(id): return 1.0 if run and run.pilot == id else 0.0
	var rl := func(id): return 1.0 if relic(id) else 0.0
	var sg := func(k: String) -> float: return float(ship.get(k, 0.0))
	# 4.2: пока действует аномалия сектора, кредитов и опыта больше
	var an = anomaly()
	var anK: float = 1.0 + D.ANOMALIES[an].bonus if an else 1.0
	var shieldRegen: float = 20.0 if md.call("shieldcore") else (30.0 if sk.call("sk_capacitor") else 0.0)
	if pk.call("shieldgen"):
		var v: float = [30.0, 22.0, 15.0][pk.call("shieldgen") - 1]
		shieldRegen = minf(shieldRegen, v) if shieldRegen else v
	if sg.call("shieldRegen"): shieldRegen = minf(shieldRegen, sg.call("shieldRegen")) if shieldRegen else sg.call("shieldRegen")
	return {
		# бонусы урона складываются в один общий процент, а не перемножаются; прокачка «Мощности» оружия — в dmgMul(wid)
		"dmg": 1 + md.call("power") * 0.2 + pl.call("vega") * 0.1 + sg.call("dmg") + (pres.dmg - 1) + pk.call("dmg") * 0.15 + sk.call("sk_caliber") * 0.05 + rl.call("r_lens") * 0.12 + rl.call("r_glassblade") * 0.4 + (0.5 if pk.call("glass") else 0.0) - (0.2 if pk.call("ricochet") else 0.0) + (0.3 if noDrops() else 0.0) + pk.call("heavy") * 0.4,
		"rate": (1 + md.call("cooling") * 0.15) * (1 + sg.call("rate")) * (1 + pk.call("rate") * 0.12) * (1 + sk.call("sk_rapid") * 0.05) * (1 + rl.call("r_coolant") * 0.12) * (1 - pk.call("heavy") * 0.2),
		"crit": 0.03 + md.call("targeting") * 0.12 + pk.call("crit") * 0.08 + sg.call("crit") + pl.call("vega") * 0.05 + sk.call("sk_precision") * 0.04 + rl.call("r_scope") * 0.06,
		"critMul": 2 + sg.call("critMul") + pk.call("critdmg") * 0.5 + md.call("targeting") * 0.5 + rl.call("r_scope") * 0.5,
		"pierce": pk.call("pierce"),
		"multi": pk.call("multi") + int(sg.call("multi")) + int(rl.call("r_twins")),
		"wings": sg.call("wings") if sg.call("wings") else md.call("wings"),
		"magnet": 9999.0 if sk.call("sk_magnet") >= 2 else 120 * S * (1.5 if md.call("salvage") else 1.0) * (1 + pk.call("magnet") * 0.5) * (1 + sg.call("magnet")) * (1.5 if sk.call("sk_magnet") else 1.0) * (1 + rl.call("r_gravlov")),
		# кредитов за врага меньше там, где врагов больше: доход за волну равен множителю сложности
		"coins": diff.coins / diff.count * (1 + md.call("salvage") * 0.4) * (1.2 if pl.call("lira") else 1.0) * (1 + pk.call("greed") * 0.3) * pres.coins * (1 + sk.call("sk_greed") * 0.1) * (1 + rl.call("r_purse") * 0.25) * (1 + rl.call("r_cursedcoin")) * Comp.coinMul() * coinK * D.ECON.coins * anK,
		"luck": (1 + pk.call("luck") * 0.4) * (1 + sk.call("sk_lucky") * 0.25) * (1 + rl.call("r_dice") * 0.5),
		"speed": (1 + sg.call("speed")) * (1 + md.call("gyro") * 0.15) * (1 + pk.call("speed") * 0.15) * (1 + rl.call("r_afterburner") * 0.12),
		"dodge": minf(0.45, sk.call("sk_ghost") * 0.07 + rl.call("r_afterburner") * 0.05 + pk.call("speed") * 0.05 + sg.call("dodge") + md.call("gyro") * 0.1 + pl.call("nox") * 0.12 + pk.call("nimble") * 0.08),
		"cdMul": (1 - pk.call("cooldown") * 0.15) * (0.7 if md.call("chrono") else 1.0) * (1 - sk.call("sk_chrono") * 0.15) * (1 - rl.call("r_hourglass") * 0.25),
		"bomb": 1 + md.call("bombbay") * 0.6 + sg.call("bombdmg") + pl.call("rex") * 0.5 + rl.call("r_arsenal") * 0.4,
		"bombCd": 0.5 if pl.call("rex") else 1.0,
		"invMul": (2.0 if pl.call("nox") else 1.0) * (2.0 if sk.call("sk_secondwind") else 1.0),
		"bossDmg": 1 + pk.call("titan") * 0.25 + md.call("hunter") * 0.35 + rl.call("r_trophy") * 0.3,
		"eliteDmg": 1 + md.call("hunter") * 0.35 + rl.call("r_hunteye") * 0.3,
		"xp": (1 + md.call("scanner") * 0.35) * (1.2 if pl.call("kai") else 1.0) * (1 + rl.call("r_neuro") * 0.25) * anK,
		"shieldRegen": shieldRegen,
		"cryo": pk.call("cryo") * 0.12 + rl.call("r_frost") * 0.1,
		"nova": pk.call("nova"),
	}


func refreshStats() -> void:
	st = computeStats()
	syncDrones()
	hudDirty = true


## уровни прокачки оружия
func wl(wid: String, up: String) -> int:
	return M.weaponLevel(wid, up)


# ════════════════════════════════════════════════════════════
# ВВОД
# ════════════════════════════════════════════════════════════
## забег идёт (бой или кат-сцена)
func inRun() -> bool:
	return state == "play" or state == "cutscene"


func onPointerDown(id: int, pos: Vector2) -> void:
	var pt := pointer
	if state != "play" and state != "cutscene": return
	if pt.id != -1 and pt.id != id: return
	pt.id = id; pt.x = pos.x; pt.y = pos.y
	pt.downT = Time.get_ticks_msec(); pt.downX = pos.x; pt.downY = pos.y; pt.moved = 0.0


func onPointerMove(id: int, pos: Vector2) -> void:
	var pt := pointer
	if pt.id != id: return
	# палец следим и без управления, чтобы после сцены корабль не прыгнул на накопленный сдвиг
	if state != "play":
		pt.moved += absf(pos.x - pt.x) + absf(pos.y - pt.y)
		pt.x = pos.x; pt.y = pos.y
		return
	var sens: float = M.s.settings.get("sens", 1.25)
	var dx: float = (pos.x - pt.x) * sens
	var dy: float = (pos.y - pt.y) * sens
	pt.x = pos.x; pt.y = pos.y
	pt.moved += absf(dx) + absf(dy)
	var p := player
	if p and p.alive:
		p.x += dx; p.y += dy
		clampPlayer()
		p.vxs += dx


func onPointerUp(id: int, pos: Vector2) -> void:
	var pt := pointer
	if pt.id != id: return
	pt.id = -1
	var now := Time.get_ticks_msec()
	var quick: bool = now - pt.downT < 230 and pt.moved < 18
	# короткое касание пропускает кат-сцену (ведение пальцем — нет)
	if state == "cutscene":
		if quick: skipScene()
		return
	if state != "play": return
	# двойной тап — бомба (можно выключить в настройках)
	if quick and M.s.settings.get("dblBomb", true):
		if now - pt.lastTap < 320 and Vector2(pos.x - pt.lastTapX, pos.y - pt.lastTapY).length() < 60:
			useBomb()
			pt.lastTap = 0.0
		else:
			pt.lastTap = now; pt.lastTapX = pos.x; pt.lastTapY = pos.y


func onKey(code: String, down: bool) -> void:
	keys[code] = down
	if down and state == "cutscene" and (code == "Space" or code == "Enter"):
		skipScene()
		return
	if not down or state != "play": return
	if code == "KeyB" or code == "Space": useBomb()
	if code == "KeyQ": useSkill(0)
	if code == "KeyE": useSkill(1)
	if code.begins_with("Digit"):
		var i := int(code.substr(5)) - 1
		if i >= 0 and i < player.weapons.size(): setWeapon(player.weapons[i])


func clampPlayer() -> void:
	var p := player
	var m := p.w * 0.42
	var bottom: float = G.H - Ui.bottomInset() - p.w * 0.45
	p.x = U.clamp(p.x, m, G.FW - m)
	p.y = U.clamp(p.y, G.H * 0.14, maxf(G.H * 0.5, bottom))


func setWeapon(wid: String) -> void:
	var p := player
	if not p or not wid in p.weapons or p.weapon == wid: return
	p.weapon = wid
	A.play("click")
	Haptic.select()
	hudDirty = true


# ════════════════════════════════════════════════════════════
# ГЛАВНЫЙ ЦИКЛ
# ════════════════════════════════════════════════════════════
func frame(rdt: float) -> void:
	if state == "play" and run.tipQ.size() and player.alive:
		var tip: Dictionary = run.tipQ.pop_front()
		# «показано» отмечаем, только когда окно открылось (забег мог кончиться раньше)
		M.s.get_or_add("tips", {})[tip.key] = 1
		M.soon()
		state = "tip"
		pointer.id = -1
		Haptic.medium()
		Bus.emit("tip", tip)
		return
	if state == "play" or state == "dying" or state == "cutscene":
		updateCam(rdt)
		darkK = move_toward(darkK, 1.0 if anomaly("eclipse") and state == "play" else 0.0, rdt * 0.5)
		# хитстоп: мир замирает на пару кадров (кадр при этом рисуется)
		if stopT > 0:
			stopT -= rdt
			return
		if slowT > 0:
			slowT -= rdt
			timeScale = lerpf(timeScale, 0.3, 0.2)
		else:
			timeScale = lerpf(timeScale, 1.0, minf(1.0, rdt * 6))
		var dt := minf(rdt, 1.0 / 30) * timeScale
		update(dt, rdt)
	elif state == "idle":
		attract.t += rdt
		Bg.update(rdt, 0.6)
		FX.update(rdt)
	else:
		# пауза / выбор улучшения / экран итогов — фон слегка живёт
		Bg.update(rdt, 0.4 if state == "over" else 0.05)


## Godot: аномалия «Затмение» — тьма поверх фона и врагов (assets/shaders/dark.gdshader); свет дают корабль,
## взрывы, свежие выстрелы и вражеские снаряды. Пули, корабль и вспышки рисуются уже поверх тьмы
func drawDark(ctx: Ctx) -> void:
	if _dark_mat == null:
		_dark_mat = ShaderMaterial.new()
		_dark_mat.shader = load("res://assets/shaders/dark.gdshader")
		_dark_l.resize(20)
	var S := G.S
	# прямоугольник с запасом на тряску и наезд камеры; огни — в его координатах
	var rx := -G.FX - 40.0
	var ry := -40.0
	var rw := G.W + 80.0
	var rh := G.H + 80.0
	var L: Array[Vector4] = []
	var p := player
	if p.alive: L.append(Vector4(p.x, p.y, 175 * S, 1.0))
	var k := 0
	for i in range(FX.expl.size() - 1, -1, -1):
		var ex: Dictionary = FX.expl[i]
		if k >= 8: break
		L.append(Vector4(ex.x, ex.y, ex.w * 1.7, 1.0 - ex.life / ex.dur)); k += 1
	k = 0
	for i in range(bullets.size() - 1, -1, -1):   # свежие выстрелы — в конце списка
		if k >= 6: break
		L.append(Vector4(bullets[i].x, bullets[i].y, 52 * S, 0.6)); k += 1
	k = 0
	for i in range(ebullets.size() - 1, -1, -1):
		if k >= 5: break
		L.append(Vector4(ebullets[i].x, ebullets[i].y, 40 * S, 0.45)); k += 1
	for i in L.size(): _dark_l[i] = Vector4(L[i].x - rx, L[i].y - ry, L[i].z, L[i].w)
	_dark_mat.set_shader_parameter("lights", _dark_l)
	_dark_mat.set_shader_parameter("light_n", L.size())
	_dark_mat.set_shader_parameter("size", Vector2(rw, rh))
	_dark_mat.set_shader_parameter("dark", 0.92 * darkK)
	ctx.alpha = 1.0
	ctx.additive = false
	ctx.shader_rect(_dark_mat, rx, ry, rw, rh)


## наезд камеры на точку поля (x, y — координаты поля): увеличение z, держится hold секунд, потом плавно назад.
## Выключается вместе с тряской экрана (настройка «Тряска»)
func camFocus(x: float, y: float, z: float, hold: float) -> void:
	if not FX.shake_on: return
	cam.x = x; cam.y = y; cam.tz = z; cam.hold = hold


## точка поля → точка экрана: сдвиг поля, тряска и наезд камеры — как в draw (для Post и частиц Vfx)
func toScreen(x: float, y: float) -> Vector2:
	var z: float = cam.z
	return Vector2(cam.x + (x - cam.x) * z + G.FX + FX.shake_x, cam.y + (y - cam.y) * z + FX.shake_y)


func updateCam(rdt: float) -> void:
	if cam.hold > 0: cam.hold -= rdt
	else: cam.tz = 1.0
	# наезд быстрый, отъезд мягкий
	cam.z = U.damp(cam.z, cam.tz, 7.0 if cam.tz > cam.z else 2.5, rdt)


## 4.2.2: короткий стоп-кадр — убийство элиты, смена фазы босса; не копится, берётся самый длинный
func hitstop(sec: float) -> void:
	stopT = maxf(stopT, sec)


func update(dt: float, rdt: float) -> void:
	var p := player
	t += dt
	run.time += dt
	Scenes.tick(dt)
	var slow := enemySlow()
	var edt := dt * slow
	# ── управление с клавиатуры ──
	if p.alive and state == "play":
		var kx := 0.0
		var ky := 0.0
		if keys.get("ArrowLeft") or keys.get("KeyA"): kx -= 1
		if keys.get("ArrowRight") or keys.get("KeyD"): kx += 1
		if keys.get("ArrowUp") or keys.get("KeyW"): ky -= 1
		if keys.get("ArrowDown") or keys.get("KeyS"): ky += 1
		if kx != 0.0 or ky != 0.0:
			var sp: float = 400 * G.S * st.speed * dt
			var n := sqrt(kx * kx + ky * ky)
			p.x += kx / n * sp; p.y += ky / n * sp; p.vxs += kx / n * sp
			clampPlayer()
		# 4.3.2: отброс от астероида (bumpAsteroid) гаснет за ~0,3 с
		if p.bumpT > 0:
			p.bumpT -= dt
			p.x += p.kbx * dt; p.y += p.kby * dt; p.vxs += p.kbx * dt
			p.kbx = U.damp(p.kbx, 0, 9, dt); p.kby = U.damp(p.kby, 0, 9, dt)
			clampPlayer()
	# крен корабля по горизонтальной скорости
	p.tilt = U.damp(p.tilt, U.clamp(p.vxs * 0.035, -0.32, 0.32), 10, rdt)
	p.vxs = U.damp(p.vxs, 0, 14, rdt)
	updateTimers(dt)
	runTimers(dt)
	if run.get("shieldFxT", 0.0) > 0: run.shieldFxT = maxf(0.0, run.shieldFxT - rdt * 1.6)
	# заряд серпа копится от движения корабля (только в бою), без движения стекает
	if "arc" in p.weapons:
		var ab: Dictionary = D.WEAPONS.arc.base
		var mv := sqrt((p.x - p.lx) * (p.x - p.lx) + (p.y - p.ly) * (p.y - p.ly)) if state == "play" and not is_nan(p.lx) else 0.0
		run.arc = U.clamp(run.arc + mv / (G.FW * ab.charge) - dt * ab.drain, 0, 1)
	# скорость корабля (сглаженная) — по ней враги берут упреждение (aimAt)
	if not is_nan(p.lx) and dt > 0:
		p.vxm = U.damp(p.vxm, (p.x - p.lx) / dt, 6, dt)
		p.vym = U.damp(p.vym, (p.y - p.ly) / dt, 6, dt)
	p.lx = p.x; p.ly = p.y
	if run.focus.t > 0: run.focus.t -= dt
	var nb := bullets.size()
	if p.alive and state == "play": fireWeapons(dt)
	Skills.echo(nb)
	updateDrones(dt)
	Comp.update(dt)
	RunMap.updateEscort(dt)
	updateBullets(dt)
	E.updateAll(edt, dt)
	updateBurn(dt)
	updateFire(dt)
	Foes.update(edt)
	Skills.update(dt)
	updateEBullets(edt)
	collide()
	processBlasts()
	flushDmgNums()
	updatePickups(dt)
	updateWaves(dt)
	if scene != null: updateScene(dt)
	Events.update(dt)
	updateOverlays(dt)
	cleanup()
	FX.update(dt)
	Bg.update(dt, 1.4 if boss else 1.0)
	# комбо
	if run.combo > 0:
		run.comboT -= dt
		if run.comboT <= 0:
			run.combo = 0
			setFever(false)
			hudDirty = true
	# уровень забега → выбор улучшения
	if run.pendingPerks > 0 and state == "play" and p.alive: offerPerk()
	# достижения по времени
	if p.lives == 1 and p.alive:
		run.oneHpT += dt
		if run.oneHpT >= 60: M.unlock("survive_1hp")
	else:
		run.oneHpT = 0.0
	if run.time - run.lastAchCheck > 1.5:
		run.lastAchCheck = run.time
		M.checkAchievements()


func enemySlow() -> float:
	var s := 1.0
	if run.skillFx.get("sk_timewarp", 0.0) > 0: s *= 0.33
	if buffs.get("freeze", 0.0) > 0: s *= 0.25
	return s


func updateTimers(dt: float) -> void:
	var p := player
	if p.inv > 0: p.inv -= dt
	if p.bombCd > 0: p.bombCd -= dt
	if p.lockT > 0: p.lockT -= dt
	if buffs.get("freeze", 0.0) > 0 and FX.quality > 0 and U.random() < dt * 45: FX.frost(U.random() * G.FW, U.random() * G.H * 0.85)
	if p.lockHot > 0: p.lockHot -= dt
	for k in buffs.keys():
		if buffs[k] > 0:
			buffs[k] -= dt
			if buffs[k] <= 0:
				buffs.erase(k)
				hudDirty = true
	for k in run.skillCd: if run.skillCd[k] > 0: run.skillCd[k] = maxf(0, run.skillCd[k] - dt)
	for k in run.skillFx: if run.skillFx[k] > 0: run.skillFx[k] = maxf(0, run.skillFx[k] - dt)
	if run.overload > 0: run.overload -= dt
	# восстановление щита
	if st.shieldRegen and not p.shield and p.alive:
		run.shieldRegenT += dt
		if run.shieldRegenT >= st.shieldRegen:
			run.shieldRegenT = 0.0
			p.shield = true
			shieldFx()
			A.play("powerup", {"vol": 0.5})
			hudDirty = true
	if mod("repair") and p.alive and p.lives < p.maxLives:
		run.repairT += dt
		if run.repairT >= 60:
			run.repairT = 0.0
			heal(1, "🔧 РЕМОНТ")
	if mod("emergency") and p.alive and p.lives == 1 and not p.shield:
		run.emergT += dt
		if run.emergT >= 12:
			run.emergT = 0.0; p.shield = true; shieldFx(); hudDirty = true
	else:
		run.emergT = 0.0
	# реликвия «Око бури»: каждые 8 с молния в самого крепкого врага на экране
	if relic("r_stormeye") and p.alive and state == "play":
		run.stormT += dt
		if run.stormT >= 8:
			var best: En = null
			for e in enemies:
				if e.alive and e.hittable and e.y > 0 and e.y < G.H * 0.9 and not Foes.hidden(e) and (best == null or e.hp > best.hp): best = e
			if best:
				run.stormT = 0.0
				var wn: float = wave.n if wave else 1.0
				FX.lightning(best.x + U.rand(-30, 30) * G.S, -10, best.x, best.y, "#fff36b", 3 * G.S, 0.3)
				FX.sprite("fx_bolt", best.x, best.y, {"w0": 30 * G.S, "w1": 52 * G.S, "dur": 0.25, "hold": 0.3, "hue": 52})
				FX.flash("#fff6c0", 0.12)
				A.play("zap", {"rate": 0.7})
				# не меньше заметной доли прочности: у обычных врагов — четверть, у боссов — 3%
				var dmg := maxf(120 * dmgMul() * (1 + wn * 0.06), best.maxHp * (0.03 if best.boss else 0.25))
				damageEnemy(best, dmg, {"src": "lightning", "heavy": true})
	if relic("r_nano") and p.alive and p.lives < p.maxLives:
		run.nanoT += dt
		if run.nanoT >= 50:
			run.nanoT = 0.0
			heal(1, "🦠 НАНОРОБОТЫ")
	if skill("sk_regen") and p.alive and p.lives < p.maxLives:
		run.regenT += dt
		var rt := 35.0 if skillLv("sk_regen") >= 2 else 45.0
		if run.regenT >= (rt / 2 if p.lives == 1 else rt):
			run.regenT = 0.0
			heal(1, "💚 РЕГЕНЕРАЦИЯ")


# ════════════════════════════════════════════════════════════
# ОРУЖИЕ
# ════════════════════════════════════════════════════════════
func rateMul() -> float:
	var r: float = st.rate
	if buffs.get("rapid", 0.0) > 0: r *= 1.6
	if run.skillFx.get("sk_overclock", 0.0) > 0: r *= 2.5
	if run.overload > 0: r *= 2
	if perk("overclock") and run.combo >= 10: r *= 1 + perk("overclock") * 0.2
	return r


## wid — оружие: его прокачка урона входит в общую сумму бонусов; временные состояния — множители
func dmgMul(wid := "") -> float:
	var d: float = st.dmg + (wl(wid, "dmg") * 0.12 if wid != "" else 0.0)
	if perk("investor"): d += minf(0.4, run.coins / 5000.0)
	if relic("r_crown"): d += run.bosses * 0.1
	if buffs.get("power", 0.0) > 0: d *= 1.6
	if wave and wave.danger and skill("sk_daredevil"): d *= 1.25
	# хладнокровие: +10% урона за каждые 4 с без попаданий, до +30%
	if skill("sk_coolhead"): d *= 1 + minf(3, floorf((run.time - run.hitAt) / 4)) * 0.1
	if relic("r_redstar") and player.lives <= 1: d *= 1.5
	if skill("sk_berserker"):
		var p := player
		var lost := float(p.maxLives - p.lives) / (p.maxLives - 1) if p.maxLives > 1 else 0.0
		d *= 1 + 0.6 * U.clamp(1.0 if p.lives <= 1 else lost, 0, 1)
	return d


## магазин (ракеты, дробовик): серия выстрелов, потом перезарядка
func magSize(wid: String) -> int:
	return int(D.WEAPONS[wid].base.mag) + (wl(wid, "salvo") if wid == "rocket" else 0)


func mag(wid: String) -> Variant:
	if not D.WEAPONS.has(wid) or not D.WEAPONS[wid].base.mag: return null
	if not player.mag.has(wid): player.mag[wid] = {"n": magSize(wid), "t": 0.0}
	return player.mag[wid]


## ресурс оружия для HUD: k 0..1 и вид — магазин, перезарядка, энергия, заряд, фокус (null — ресурса нет)
func weaponRes(wid: String) -> Variant:
	if not run or not D.WEAPONS.has(wid): return null
	var b: Dictionary = D.WEAPONS[wid].base
	if b.mag:
		var m: Dictionary = mag(wid)
		var size := magSize(wid)
		return {"kind": "mag", "k": float(m.n) / size, "n": m.n, "max": size} if m.n > 0 else {"kind": "reload", "k": U.clamp(1 - m.t / b.reload, 0, 1)}
	if wid == "lightning": return {"kind": "energy", "k": run.energy}
	if wid == "arc": return {"kind": "charge", "k": run.arc} if run.arc > 0.04 else null
	if wid == "laser" and run.focus.t > 0 and run.focus.n > 1: return {"kind": "focus", "k": float(run.focus.n) / b.focusMax}
	return null


func updateMags(dt: float) -> void:
	var p := player
	for wid in p.weapons:
		var m = mag(wid)
		if m == null or m.n > 0: continue
		m.t -= dt * rateMul() * (1 + wl(wid, "rate") * 0.08)
		if m.t <= 0:
			m.n = magSize(wid)
			if wid == p.weapon: A.play("click", {"rate": 1.6, "vol": 0.5})
			hudDirty = true


func fireWeapons(dt: float) -> void:
	var p := player
	var wid := p.weapon
	if not D.WEAPONS.has(wid): return
	var def: Dictionary = D.WEAPONS[wid]
	updateMags(dt)
	var m = mag(wid)
	var cd: float = def.base.cd / (1 + wl(wid, "rate") * 0.08)
	p.wcd[wid] = p.wcd.get(wid, 0.0) - dt * rateMul()
	var guard := 0
	# тёмная материя: новая сфера — только когда прошлая схлопнулась
	var sphere := false
	if wid == "darkmatter":
		for b in bullets:
			if not b.dead and b.kind == "dark":
				sphere = true
				break
	while p.wcd[wid] <= 0 and guard < 3:
		guard += 1
		# магазин пуст — ждём перезарядку, первый выстрел после неё сразу
		if (m != null and m.n <= 0) or sphere:
			p.wcd[wid] = 0.0
			break
		fire(wid)
		if m != null:
			m.n -= 1
			if m.n <= 0:
				m.t = def.base.reload
				hudDirty = true
		p.wcd[wid] += cd
	if p.wcd[wid] < -cd: p.wcd[wid] = 0.0
	# бортовые пушки стреляют независимо от выбранного оружия
	if st.wings:
		p.wingCd -= dt * rateMul()
		if p.wingCd <= 0:
			p.wingCd = 0.26
			var S := G.S
			var dmg := 4.5 * dmgMul()
			for sd in [-1.0, 1.0]:
				shot({"x": p.x + sd * p.w * 0.4, "y": p.y - p.w * 0.05, "vx": sd * 30 * S, "vy": -980 * S, "dmg": dmg, "r": 4 * S, "kind": "laser", "sprite": "pb_bolt_s", "w": 10 * S, "pierce": st.pierce, "wid": "wings", "life": 1.4})


func shot(o: Dictionary) -> Bl:
	var b := Bl.new()
	b.x = o.x; b.y = o.y; b.px = o.x; b.py = o.y; b.vx = o.vx; b.vy = o.vy
	b.dmg = o.dmg; b.r = o.r; b.kind = o.kind; b.sprite = o.get("sprite", ""); b.cv = o.get("cv"); b.w = o.w
	b.pierce = int(o.get("pierce", 0)); b.life = o.get("life", 2.4); b.life0 = b.life; b.w1 = o.get("w1", 0.0); b.ch = o.get("ch", 0.0)
	b.homing = o.get("homing", 0.0); b.aoe = o.get("aoe", 0.0); b.aoeR = o.get("aoeR", 0.0); b.acc = o.get("acc", 0.0); b.maxSpd = o.get("maxSpd", 0.0)
	b.tickT = o.get("tickT", 0.0); b.pull = o.get("pull", 0.0); b.burst = o.get("burst", 0.0); b.burstR = o.get("burstR", 0.0)
	b.wid = o.get("wid", "")
	bullets.append(b)
	return b


func spawnShot(o: Dictionary) -> Bl:
	return shot(o)


func skillCast(id: String, sk: Dictionary) -> void:
	Skills.cast(id, sk)


func fire(wid: String) -> void:
	var p := player
	var S := G.S
	var base: Dictionary = D.WEAPONS[wid].base
	var dmgMul_ := dmgMul(wid)
	var multi: int = st.multi + (2 if buffs.get("multi", 0.0) > 0 else 0)
	# дополнительные снаряды бьют слабее основного
	var mk := (1 + multi * 0.6) / (1 + multi)
	var spread: bool = buffs.get("spread", 0.0) > 0
	var nose := p.y - p.w * 0.42
	run.shots += 1
	# реликвия «Счётчик залпов»: каждый 10-й выстрел — ещё и самонаводящаяся ракета
	if relic("r_salvo") and run.shots % 10 == 0:
		var rb: Dictionary = D.WEAPONS.rocket.base
		shot({"x": p.x, "y": nose, "vx": 0.0, "vy": -260 * S, "dmg": rb.dmg * dmgMul_ * 0.6, "aoe": rb.aoe * dmgMul_ * 0.6, "aoeR": rb.radius * S, "r": 7 * S, "kind": "rocket", "sprite": "fx_rocket", "w": 13 * S, "homing": 6.5, "acc": 900 * S, "maxSpd": rb.speed * S, "wid": "salvo", "life": 2.4})
	match wid:
		"laser":
			var lvl := wl(wid, "dmg")
			var beam := evo("laser")
			var sprite := "fx_charge" if (beam or lvl >= 8) and G.has("fx_charge") else ("pb_laser" if lvl >= 6 else ("pb_bolt_m" if lvl >= 3 else "pb_bolt_s"))
			var sw: float = (22.0 if beam else 18.0) if sprite == "fx_charge" else (13.0 if sprite == "pb_laser" else (15.0 if sprite == "pb_bolt_m" else 13.0))
			sw *= S
			var n := 1 + multi
			var gap := 10 * S
			var pierce: int = 99 if beam else wl(wid, "pierce") + st.pierce
			var dm2 := dmgMul_ * 1.25 if beam else dmgMul_
			var spd: float = base.speed * S
			for i in n:
				var ox := (i - (n - 1) / 2.0) * gap
				shot({"x": p.x + ox, "y": nose, "vx": 0.0, "vy": -spd, "dmg": base.dmg * dm2 * mk, "r": 5 * S, "kind": "laser", "sprite": sprite, "w": sw, "pierce": pierce, "wid": wid, "life": 1.6})
			if spread:
				for a in [-0.22, 0.22]:
					shot({"x": p.x, "y": nose, "vx": sin(a) * spd, "vy": -cos(a) * spd, "dmg": base.dmg * dmgMul_ * 0.8, "r": 5 * S, "kind": "laser", "sprite": sprite, "w": sw, "pierce": pierce, "wid": wid, "life": 1.6})
			A.play("laser")
		"shotgun":
			var n: int = int(base.pellets) + wl(wid, "pellets") + multi * 2
			var arc := 0.78 + (0.35 if spread else 0.0) + multi * 0.06
			var cv := G.tinted("pb_orb", {"hue": 44})
			for i in n:
				var a := (0.0 if n == 1 else (float(i) / (n - 1) - 0.5) * arc) + U.rand(-0.03, 0.03)
				var spd: float = base.speed * S * U.rand(0.9, 1.08)
				shot({"x": p.x, "y": nose, "vx": sin(a) * spd, "vy": -cos(a) * spd, "dmg": base.dmg * dmgMul_, "r": 6 * S, "kind": "pellet", "cv": cv, "w": 14 * S, "pierce": st.pierce, "wid": wid, "life": base.life})
			FX.glow_puff(p.x, nose, "#ffd23d", 40 * S, 0.1)
			A.play("shotgun")
		"rocket":
			# одна ракета из залпа (+ ракеты от «Мультивыстрела»); размер залпа — магазин
			var n := 1 + multi
			var radius: float = base.radius * S * (1 + wl(wid, "aoe") * 0.15)
			var rs := "fx_rocket2" if wl(wid, "dmg") >= 4 else "fx_rocket"
			var rw := (14.0 if rs == "fx_rocket2" else 13.0) * S
			for i in n:
				p.side = -p.side
				var out := p.side * (0.55 + i * 0.12) + (p.side * 0.3 if spread else 0.0)
				shot({"x": p.x + p.side * p.w * 0.3, "y": p.y - p.w * 0.05, "vx": sin(out) * 260 * S, "vy": -cos(out) * 260 * S,
					"dmg": base.dmg * dmgMul_ * mk, "aoe": base.aoe * dmgMul_ * mk, "aoeR": radius, "r": 7 * S, "kind": "rocket", "sprite": rs, "w": rw,
					"homing": 6.5, "acc": 900 * S, "maxSpd": base.speed * S, "wid": wid, "life": 2.4})
			A.play("rocket")
		"plasma":
			var radius: float = base.radius * S * (1 + wl(wid, "aoe") * 0.15)
			var orb := G.has("fx_plasma2")
			var cv := G.tinted("fx_plasma2" if orb else "eb_fire", {"hue": 305})
			var pw := (1.35 if orb else 1.0) * S
			var n := 1 + multi
			for i in n:
				var a := (i - (n - 1) / 2.0) * 0.16
				shot({"x": p.x, "y": nose, "vx": sin(a) * base.speed * S, "vy": -cos(a) * base.speed * S, "dmg": base.dmg * dmgMul_ * mk, "aoe": base.aoe * dmgMul_ * mk, "aoeR": radius,
					"r": 12 * S, "kind": "plasma", "cv": cv, "w": 40 * pw, "wid": wid, "life": 2.6})
			if spread:
				for a in [-0.35, 0.35]:
					shot({"x": p.x, "y": nose, "vx": sin(a) * base.speed * S, "vy": -cos(a) * base.speed * S, "dmg": base.dmg * dmgMul_ * 0.6, "aoe": base.aoe * dmgMul_ * 0.6, "aoeR": radius * 0.8, "r": 10 * S, "kind": "plasma", "cv": cv, "w": 30 * pw, "wid": wid, "life": 2.6})
			A.play("plasma")
		"lightning":
			# полный разряд тратит энергию (только если нашёл цель); без энергии — слабая искра в одну цель
			var full: bool = run.energy > 0
			var jumps: int = (int(base.chain) + wl(wid, "chain") + (2 if skill("sk_conductor") else 0) + multi) if full else 0
			var range_: float = base.range * S * (1 + wl(wid, "range") * 0.15)
			var ldmg: float = base.dmg * dmgMul_ * (1 + multi * 0.15) * (1.0 if full else base.spark)
			if chainLightning(p.x, nose, ldmg, jumps, range_, 360 * S, false, not full) and full:
				run.energy = maxf(0, run.energy - base.cost)
				hudDirty = true
			if spread and full: chainLightning(p.x, nose, ldmg * 0.6, int(ceil(jumps / 2.0)), range_, 360 * S, true)
			# двойник бьёт своей молнией (энергию не тратит)
			var cl = Skills.clone
			if cl: chainLightning(cl.x, cl.y - p.w * 0.4, ldmg * 0.6, jumps, range_, 360 * S, true, not full)
			A.play("zap", {} if full else {"vol": 0.4, "rate": 1.6})
		"arc":
			# серп: волна-полумесяц летит вперёд, расширяется и прошивает всех на пути; заряд от движения — шире и сильнее
			var ch: float = run.arc
			var k: float = base.min + (base.max - base.min) * ch
			var span := 1 + wl(wid, "range") * 0.08
			var wk := span * (0.85 + 0.3 * ch) * (1 + multi * 0.08)
			var wave_ := func(a: float, dmg: float, wmul: float):
				shot({"x": p.x, "y": nose, "vx": sin(a) * base.speed * S, "vy": -cos(a) * base.speed * S, "dmg": dmg, "r": base.thick * S,
					"kind": "wave", "w": base.w0 * S * wk * wmul, "w1": base.w1 * S * wk * wmul, "wid": wid, "life": base.life * sqrt(span), "ch": ch})
			wave_.call(0.0, base.dmg * dmgMul_ * k * (1 + multi * 0.12), 1.0)
			if spread:
				for a in [-0.4, 0.4]: wave_.call(a, base.dmg * dmgMul_ * k * 0.5, 0.6)
			A.play("arc")
		"darkmatter":
			var radius: float = base.radius * S * (1 + wl(wid, "aoe") * 0.15)
			var pull: float = base.pull * S * (1 + wl(wid, "pull") * 0.2)
			var n := 1 + multi + (2 if spread else 0)
			for i in n:
				var a := (i - (n - 1) / 2.0) * 0.42
				shot({"x": p.x, "y": nose, "vx": sin(a) * base.speed * S, "vy": -cos(a) * base.speed * S, "dmg": base.dmg * dmgMul_ * mk, "r": radius, "kind": "dark",
					"w": radius * 1.1, "tickT": base.tick, "pull": pull, "burst": base.burst * dmgMul_ * mk * (2.0 if evo("darkmatter") else 1.0), "burstR": radius * 1.25, "wid": wid, "life": base.life})
			A.play("dark")


## цепная молния: ищет ближайшую цель выше корабля, затем прыгает; weak — искра без энергии
func chainLightning(x: float, y: float, dmg: float, jumps: int, range_: float, firstRange: float, alt := false, weak := false) -> int:
	var hit: Array[En] = []
	var cx := x
	var cy := y
	var cur: En = null
	for j in jumps + 1:
		var best: En = null
		var bd := INF
		var R := firstRange if j == 0 else range_
		for e in enemies:
			if not e.alive or not e.hittable or e.def.cloak or e.fog or e in hit: continue
			var d := sqrt((e.x - cx) * (e.x - cx) + (e.y - cy) * (e.y - cy))
			if j == 0 and e.y > cy + 20: d *= 2.2  # предпочитаем цели впереди
			if alt and j == 0 and cur == null and U.random() < 0.5: d *= 1.4
			if d < R + e.r and d < bd:
				bd = d
				best = e
		if best == null: break
		hit.append(best)
		var icy := evo("lightning")
		FX.lightning(cx, cy, best.x, best.y, "#9be8ff" if icy else ("#e9e6c0" if weak else "#fff36b"), (1.2 if weak else 2.6) * G.S, 0.14)
		if icy and not best.boss: best.frozen = 2.0
		if not weak: FX.sprite("fx_bolt", best.x, best.y, {"w0": 22 * G.S, "w1": 34 * G.S, "dur": 0.18, "hold": 0.3, "rot": U.rand(-0.6, 0.6), "hue": 52, "minor": true})
		damageEnemy(best, dmg * pow(D.WEAPONS.lightning.base.falloff, j), {"crit": true, "src": "lightning"})
		cx = best.x; cy = best.y; cur = best
	if hit.is_empty():
		# разряд «в пустоту» — просто визуал
		FX.lightning(x, y, x + U.rand(-30, 30) * G.S, y - 120 * G.S, "#fff36b", 2 * G.S, 0.1)
	else:
		run.hits += 1
	return hit.size()


## серп: волна — дуга окружности радиуса R, выгнутая по курсу; полуширина растёт за время жизни
func waveGeom(b: Bl) -> Dictionary:
	var half := (b.w + (b.w1 - b.w) * minf(1.0, b.age / b.life0)) / 2
	var R := half * 1.6
	var ang := atan2(b.vy, b.vx)
	return {"R": R, "ang": ang, "cx": b.x - cos(ang) * R, "cy": b.y - sin(ang) * R, "span": asin(minf(1.0, half / R))}


func waveHits(b: Bl) -> void:
	var w := waveGeom(b)
	# луч Связки гасит волну
	if Foes.cutsWave(b, w):
		b.dead = true
		return
	for e in enemies:
		if not e.alive or not e.hittable or e.uid in b.hit: continue
		var er := maxf(e.rx, e.ry) * 0.8 if e.rx != 0.0 else e.r
		if absf(sqrt((e.x - w.cx) * (e.x - w.cx) + (e.y - w.cy) * (e.y - w.cy)) - w.R) > b.r + er: continue
		if absf(U.angle_diff(w.ang, atan2(e.y - w.cy, e.x - w.cx))) > w.span + er / w.R: continue
		b.hit.append(e.uid)
		run.hits += 1
		damageEnemy(e, b.dmg, {"crit": true, "src": "arc"})
		FX.hit(e.x, e.y, "#bff9ff")
		# каждый пробитый враг ослабляет волну; совсем слабая — гаснет
		var ab: Dictionary = D.WEAPONS.arc.base
		b.dmg *= 1 - ab.pierceLoss
		if b.hit.size() >= log(ab.minLeft) / log(1 - ab.pierceLoss):
			b.dead = true
			return


# ── дроны-напарники (улучшение забега) ──
func syncDrones() -> void:
	var n := perk("drone") + (1 if relic("r_buddy") else 0)
	while drones.size() < n: drones.append({"x": player.x, "y": player.y, "cd": 0.3 * drones.size()})
	drones.resize(n)


func updateDrones(dt: float) -> void:
	var p := player
	var S := G.S
	# у каждого дрона своё место; место слева занимает дрон из Ангара, Страж кружит по обоим ближним
	var skip := (2 if Comp.d.id == "guard" else 1) if Comp.d else 0
	for i in drones.size():
		var d: Dictionary = drones[i]
		var j := i + skip
		var side := 1.0 if j % 2 else -1.0
		var row := j >> 1
		var tx := U.clamp(p.x + side * p.w * (0.95 + row * 0.55), 12 * S, G.FW - 12 * S)
		var ty := p.y + p.w * (0.25 + row * 0.5) + sin(t * 3 + i) * 6 * S
		d.x = U.damp(d.x, tx, 9, dt); d.y = U.damp(d.y, ty, 9, dt)
		d.cd -= dt * rateMul()
		# в кат-сценах дроны молчат, как и сам корабль
		if d.cd <= 0 and p.alive and state == "play":
			d.cd = 0.38
			var tgt: En = null
			var bd := 420 * S
			for e in enemies:
				if not e.alive or not e.hittable or e.y > d.y or Foes.hidden(e): continue
				var dd: float = sqrt((e.x - d.x) * (e.x - d.x) + (e.y - d.y) * (e.y - d.y))
				if dd < bd:
					bd = dd
					tgt = e
			var a: float = atan2(tgt.y - d.y, tgt.x - d.x) if tgt else -PI / 2
			shot({"x": d.x, "y": d.y, "vx": cos(a) * 900 * S, "vy": sin(a) * 900 * S, "dmg": 7 * dmgMul(), "r": 4 * S, "kind": "drone", "sprite": "pb_bolt_s", "w": 10 * S, "wid": "drone", "life": 1.2})


# ════════════════════════════════════════════════════════════
# СНАРЯДЫ ИГРОКА
# ════════════════════════════════════════════════════════════
func updateBullets(dt: float) -> void:
	var FW := G.FW
	var H := G.H
	var S := G.S
	var ric := skill("sk_ricochet") or perk("ricochet") > 0 or relic("r_reflector")
	for b in bullets:
		if b.dead: continue
		b.age += dt; b.life -= dt
		b.px = b.x; b.py = b.y
		if b.kind == "rocket":
			# Гравитон разворачивает ракету в игрока
			if Foes.bendRocket(b):
				b.dead = true
				continue
			# самонаведение с ограниченной скоростью поворота
			if b.target == null or not b.target.alive: b.target = nearestEnemy(b.x, b.y, true)
			var sp := minf(b.maxSpd, sqrt(b.vx * b.vx + b.vy * b.vy) + b.acc * dt)
			var ang := atan2(b.vy, b.vx)
			if b.target and b.age > 0.12:
				var want := atan2(b.target.y - b.y, b.target.x - b.x)
				ang += U.clamp(U.angle_diff(ang, want), -b.homing * dt, b.homing * dt)
			elif b.age > 0.12:
				ang += U.clamp(U.angle_diff(ang, -PI / 2), -3 * dt, 3 * dt)
			b.vx = cos(ang) * sp; b.vy = sin(ang) * sp
			if U.random() < (0.3 if G.has("fx_tr_rocket") else 0.7): FX.glow_puff(b.x - b.vx * 0.02, b.y - b.vy * 0.02, "#ff9f3d", 14 * S, 0.18)
			if FX.quality > 0 and U.random() < 0.35: FX.smoke(b.x - b.vx * 0.03, b.y - b.vy * 0.03, 1, 7 * S)
		elif b.kind == "dark":
			b.vx *= exp(-0.85 * dt); b.vy *= exp(-0.85 * dt)
			b.rot += dt * 5
			b.tick -= dt
			if b.tick <= 0:
				b.tick = b.tickT
				for e in enemies:
					if not e.alive or not e.hittable: continue
					var d := sqrt((e.x - b.x) * (e.x - b.x) + (e.y - b.y) * (e.y - b.y))
					if (E.hitTest(e, b.x, b.y, b.r) if e.rx != 0.0 else d < b.r + e.r): damageEnemy(e, b.dmg, {"src": "dark", "noText": true})
			# притяжение (боссы не двигаются)
			for e in enemies:
				if not e.alive or e.boss or e.mini or e.def.gravity: continue
				var dx := b.x - e.x
				var dy := b.y - e.y
				var d := sqrt(dx * dx + dy * dy)
				if d > 1 and d < b.r * 2.2:
					var f := b.pull * (1 - d / (b.r * 2.2)) * dt
					e.x += dx / d * f; e.y += dy / d * f
			if FX.quality > 0 and U.random() < 0.5:
				var a := U.random() * TAU
				FX.embers(b.x + cos(a) * b.r, b.y + sin(a) * b.r, "#b06bff", 1, 40)
			# эволюция «Горизонт событий»: вражеские пули рядом со сферой исчезают
			if evo("darkmatter"):
				var rr := b.r * b.r * 2.6
				for eb in ebullets:
					if eb.dead: continue
					var dx := eb.x - b.x
					var dy := eb.y - b.y
					if dx * dx + dy * dy < rr:
						eb.dead = true
						if U.random() < 0.3: FX.glow_puff(eb.x, eb.y, "#b06bff", 14 * S, 0.25)
			if b.life <= 0:
				darkBurst(b)
				b.dead = true
				continue
		b.x += b.vx * dt; b.y += b.vy * dt
		# эволюция «Солнечная плазма»: шар оставляет горящий след (ov.fire, updateFire)
		if b.kind == "plasma" and evo("plasma"):
			b.tick -= dt
			if b.tick <= 0 and ov.fire.size() < 120:
				b.tick = 0.07
				ov.fire.append({"x": b.x, "y": b.y, "t": 0.0, "tick": 0.0, "burn": b.dmg * 0.06})
				FX.glow_puff(b.x, b.y, "#ff8a3d", 34 * S, FIRE_DUR)
		# купол Проектора: плазма лопается о его край
		if b.kind == "plasma" and Foes.inDome(b.x, b.y, b.r):
			Foes.domeHit(b.x, b.y)
			plasmaBlast(b, null)
			b.dead = true
			continue
		if ric and not b.bounced and (b.kind == "laser" or b.kind == "pellet" or b.kind == "drone"):
			if b.x < 0 or b.x > FW:
				b.vx = -b.vx; b.x = U.clamp(b.x, 0, FW); b.bounced = true; FX.hit(b.x, b.y, "#7fe7ff")
			elif b.y < 0:
				# от верха — под случайным углом, медленнее и недалеко: обратные снаряды тают в верхней части поля
				var sp := sqrt(b.vx * b.vx + b.vy * b.vy) * 0.7
				var a := atan2(-b.vy, b.vx) + U.rand(-0.45, 0.45)
				b.vx = cos(a) * sp; b.vy = sin(a) * sp; b.y = 0.0; b.bounced = true
				b.life = minf(b.life, 0.45)
				b.fade = b.life
				if U.random() < 0.5: FX.hit(b.x, 2, "#7fe7ff")
		if b.life <= 0 or b.y < -60 or b.y > H + 60 or b.x < -60 or b.x > FW + 60:
			if b.kind == "rocket" and b.life <= 0: rocketBlast(b, null)
			if b.kind == "plasma" and b.life <= 0: plasmaBlast(b, null)
			b.dead = true


func nearestEnemy(x: float, y: float, preferAhead := false) -> En:
	var best: En = null
	var bd := INF
	for e in enemies:
		if not e.alive or not e.hittable or e.y < -20 or Foes.hidden(e): continue
		var d := sqrt((e.x - x) * (e.x - x) + (e.y - y) * (e.y - y))
		if preferAhead and e.y > y: d *= 1.8
		if e.boss: d *= 0.8
		if d < bd:
			bd = d
			best = e
	return best


## попадает ли взрыв радиуса R в точке (x, y) по врагу (у крупных — эллиптический корпус)
func inBlast(e: En, x: float, y: float, R: float) -> bool:
	return E.hitTest(e, x, y, R, 0.6) if e.rx != 0.0 else sqrt((e.x - x) * (e.x - x) + (e.y - y) * (e.y - y)) < R + e.r * 0.5


func rocketBlast(b: Bl, direct: En) -> void:
	FX.explode(b.x, b.y, 0.8, "#ff9f3d")
	if evo("rocket"):
		var R := b.aoeR * 1.1
		for i in 4:
			var a := i * PI / 2 + PI / 4
			var x := b.x + cos(a) * R
			var y := b.y + sin(a) * R
			var r2 := b.aoeR * 0.55
			var d2 := b.aoe * 0.45
			after(0.1 + i * 0.05, func(): blast(x, y, r2, d2, "#ffb03d", "rocket"))
	A.play("explodeS", {"vol": 0.7})
	for e in enemies:
		if not e.alive or not e.hittable or e == direct: continue
		if inBlast(e, b.x, b.y, b.aoeR): damageEnemy(e, b.aoe, {"src": "rocket", "heavy": true})


## рост плазмы: доля пути до полной силы 0..1 и множитель урона base.min..base.max
func plasmaGrow(b: Bl) -> float:
	var pb: Dictionary = D.WEAPONS.plasma.base
	return U.clamp(b.age * sqrt(b.vx * b.vx + b.vy * b.vy) / (G.H * pb.grow), 0, 1)


func plasmaK(b: Bl) -> float:
	var pb: Dictionary = D.WEAPONS.plasma.base
	return pb.min + (pb.max - pb.min) * plasmaGrow(b) if b.wid == "plasma" else 1.0


func plasmaBlast(b: Bl, _direct: En) -> void:
	var gr := plasmaGrow(b) if b.wid == "plasma" else 1.0
	var k := plasmaK(b)
	var R := b.aoeR * (0.8 + 0.3 * gr)
	FX.explode(b.x, b.y, 0.9 + 0.6 * gr, "#ff5cf0", {"kind": "plasma", "hue": 315})
	FX.ring(b.x, b.y, 8, R, "#ff8af5", 0.35, 4)
	FX.shake(0.06 + 0.1 * gr)
	A.play("explodeM", {"vol": 0.6})
	for e in enemies:
		if not e.alive or not e.hittable: continue
		var d := sqrt((e.x - b.x) * (e.x - b.x) + (e.y - b.y) * (e.y - b.y))
		if inBlast(e, b.x, b.y, R): damageEnemy(e, b.aoe * k * (1 - minf(1.0, d / R) * 0.45), {"src": "plasma", "heavy": true})


func darkBurst(b: Bl) -> void:
	FX.explode(b.x, b.y, 1.2, "#b06bff", {"kind": "plasma"})
	FX.ring(b.x, b.y, b.burstR, 4, "#d9b8ff", 0.3, 4)
	A.play("explodeM", {"vol": 0.55, "rate": 0.7})
	for e in enemies:
		if not e.alive or not e.hittable: continue
		if inBlast(e, b.x, b.y, b.burstR): damageEnemy(e, b.burst, {"src": "dark", "heavy": true})


# ════════════════════════════════════════════════════════════
# СТОЛКНОВЕНИЯ
# ════════════════════════════════════════════════════════════
func collide() -> void:
	for b in bullets:
		if b.dead or b.kind == "dark": continue
		if b.kind == "wave":
			waveHits(b)
			continue
		for e in enemies:
			if not e.alive or not e.hittable: continue
			if b.hit.size() and e.uid in b.hit: continue
			var rr := (maxf(e.rx, e.ry) if e.rx != 0.0 else e.r) + b.r
			if absf(e.x - b.x) > rr + 40 or absf(e.y - b.y) > rr + 60: continue
			if e.rx != 0.0:
				if not E.hitTest(e, b.x, b.y, b.r) and not E.hitTest(e, (b.x + b.px) / 2, (b.y + b.py) / 2, b.r): continue
			elif U.seg_dist2(e.x, e.y, b.px, b.py, b.x, b.y) > rr * rr:
				continue
			run.hits += 1
			if b.kind == "rocket":
				damageEnemy(e, b.dmg, {"crit": true, "src": "rocket", "heavy": true})
				rocketBlast(b, e)
				b.dead = true
				break
			if b.kind == "plasma":
				damageEnemy(e, b.dmg * plasmaK(b), {"crit": true, "src": "plasma", "heavy": true})
				plasmaBlast(b, e)
				b.dead = true
				break
			# Кристальный пояс: кристалл преломляет выстрел веером из трёх
			if e.def.prism and not b.prism and (b.kind == "laser" or b.kind == "pellet" or b.kind == "drone"):
				var sp := sqrt(b.vx * b.vx + b.vy * b.vy)
				var a0 := atan2(b.vy, b.vx)
				for da in [-0.38, 0.38]:
					var nb := shot({"x": b.x, "y": b.y, "vx": cos(a0 + da) * sp, "vy": sin(a0 + da) * sp, "dmg": b.dmg * 0.7, "r": b.r, "kind": b.kind, "sprite": b.sprite, "cv": b.cv, "w": b.w, "wid": b.wid, "life": 1.2})
					nb.prism = true
					nb.hit.append(e.uid)
				FX.hit(b.x, b.y, "#bfffee")
			# Зеркало отражает лазер в игрока
			if e.def.reflect and e.def.reflect == b.wid:
				Foes.reflect(b, e)
				b.dead = true
				break
			# дробь в упор бьёт сильнее; лазер — «фокус» по одной цели
			var mul := 1.0
			var hitCol := "#ffd23d" if b.kind == "pellet" else "#7fe7ff"
			var sgb: Dictionary = D.WEAPONS.shotgun.base
			if b.kind == "pellet" and b.age < sgb.closeT: mul = sgb.closeMul
			if b.wid == "laser": mul = laserFocus(e)
			# эволюция «Каратель»: дробь в упор добивает ослабленных (кроме боссов и мини-боссов)
			if b.kind == "pellet" and b.age < sgb.closeT and evo("shotgun") and not e.boss and not e.mini and e.hp < e.maxHp * 0.2:
				FX.sparks(e.x, e.y, "#ffd23d", 14, 320)
				damageEnemy(e, e.hp + e.maxHp, {"src": "shotgun", "heavy": true})
				b.dead = true
				break
			if mul >= 1.3: hitCol = "#ffffff"
			damageEnemy(e, b.dmg * mul, {"crit": true, "src": b.wid, "cryo": true, "conductor": true})
			FX.hit(b.x, b.y, hitCol)
			if b.pierce > 0:
				b.pierce -= 1
				b.hit.append(e.uid)
			else:
				b.dead = true
				break
	# таран: враг врезался в корабль (в кат-сценах корабль ведёт сцена — тарана нет)
	var p := player
	if p.alive and state == "play":
		for e in enemies:
			if not e.alive or not e.hittable or (e.boss and e.entering): continue
			var rr := e.r * 0.8 + p.r * 1.6
			if (E.hitTest(e, p.x, p.y, p.r * 1.6, 0.8) if e.rx != 0.0 else U.dist2(e.x, e.y, p.x, p.y) < rr * rr):
				# обычный астероид Пояса — не таран, а толчок: жизнь цела (лавовый горячий — бьёт как враг)
				if e.type == "asteroid":
					bumpAsteroid(e)
					continue
				if not e.boss and not e.mini: damageEnemy(e, 999999, {"src": "ram", "noText": true})
				hitPlayer(e.x, e.y, "Столкновение: " + (e.bdef.name if e.boss else (e.def.name if e.def.name != "" else "враг")))


## 4.3.2: корабль задел астероид Пояса — его отбрасывает, жизнь цела
func bumpAsteroid(e: En) -> void:
	var p := player
	var S := G.S
	if p.bumpT > 0: return
	var nx := p.x - e.x
	var ny := p.y - e.y
	var d := sqrt(nx * nx + ny * ny)
	if d == 0.0: d = 1.0
	nx /= d; ny /= d
	var push := 520 * S
	p.kbx = nx * push; p.kby = ny * push; p.bumpT = 0.35
	var cx := e.x + nx * e.w * 0.4
	var cy := e.y + ny * e.w * 0.4
	FX.sparks(cx, cy, "#d8b48a", 14, 280)
	FX.ring(cx, cy, 6 * S, 34 * S, "#ffe2b8", 0.25, 3)
	FX.shake(0.25)
	A.play("hitArmor", {"rate": 0.6})
	Haptic.medium()
	if e.w < D.ENEMIES.asteroid.w * S:
		damageEnemy(e, 999999, {"src": "ram", "noText": true})
		return
	damageEnemy(e, e.maxHp * 0.5, {"src": "ram", "noText": true})
	e.vx -= nx * 70 * S


## фокус лазера: попадания подряд по одной цели (без пауз дольше focusT) усиливают урон
func laserFocus(e: En) -> float:
	var lb: Dictionary = D.WEAPONS.laser.base
	var f: Dictionary = run.focus
	if f.uid != e.uid or f.t <= 0:
		f.uid = e.uid
		f.n = 0
	f.t = lb.focusT
	var mul: float = 1 + lb.focus * f.n
	if f.n < lb.focusMax: f.n += 1
	return mul


# ════════════════════════════════════════════════════════════
# УРОН ПО ВРАГАМ
# ════════════════════════════════════════════════════════════
## o: { crit, src, heavy, noText, cryo, conductor }
func damageEnemy(e: En, dmg: float, o := {}) -> float:
	if not e.alive or dmg <= 0: return 0.0
	var src: String = o.get("src", "")
	# босс неуязвим, пока входит и пока перестраивается между фазами
	if e.boss and (e.entering or e.trans > 0): return 0.0
	# энергобарьер Редута поглощает обычный урон; бомба, нова и рельса его снимают
	if e.barrier > 0:
		if src == "bomb" or src == "nova" or src == "rail":
			e.barrier = 0.0
			e.cyc = 2.6
		else:
			e.shieldHitT = 0.12
			if U.random() < 0.2: A.play("hitArmor", {"vol": 0.5, "x": e.x})
			return 0.0
	# 3.1: защита от оружия, купол Проектора, привыкание Мимика (foes.gd)
	var rk: float = Foes.resist(e, src, dmg)
	if rk <= 0: return 0.0
	dmg *= rk
	var crit := false
	if o.get("crit", false) and (U.random() < st.crit or run.nextCrit):
		dmg *= st.critMul
		crit = true
		run.nextCrit = false
		# реликвия «Искровой разрядник»: крит бьёт молнией в соседа
		if relic("r_sparker") and U.random() < 0.5:
			var other := nearestOther(e, 150 * G.S)
			if other:
				FX.lightning(e.x, e.y, other.x, other.y, "#fff36b", 2 * G.S, 0.14)
				var d2 := dmg * 0.4
				after(0, func(): damageEnemy(other, d2, {"src": "lightning"}))
		if perk("vamp"):
			run.critsForVamp += 1
			if run.critsForVamp >= 30:
				run.critsForVamp = 0
				heal(1, "🩸 +1 ЖИЗНЬ")
		if absf(t - critFxT) > 0.08:
			critFxT = t
			FX.sprite("fx_flare", e.x + U.rand(-0.25, 0.25) * (e.rx if e.rx != 0.0 else e.r), e.y + U.rand(-0.2, 0.2) * (e.ry if e.ry != 0.0 else e.r),
				{"w0": 26 * G.S, "w1": 40 * G.S, "dur": 0.22, "hold": 0.3, "hue": 45, "rot": U.rand(-0.3, 0.3), "minor": true})
	if e.boss or e.mini: dmg *= st.bossDmg
	elif e.elite: dmg *= st.eliteDmg
	if e.vuln > 0: dmg *= 1.5
	if skill("sk_executioner") and e.hp < e.maxHp * 0.25: dmg *= 2
	if perk("finisher") and e.hp < e.maxHp * 0.35: dmg *= 1 + perk("finisher") * 0.25
	# снайпер: попадания оружием тем сильнее, чем дальше враг от корабля
	if o.get("crit", false) and perk("sniper"):
		dmg *= 1 + perk("sniper") * 0.2 * U.clamp(sqrt((e.x - player.x) * (e.x - player.x) + (e.y - player.y) * (e.y - player.y)) / (G.H * 0.8), 0, 1)
	if e.frozen > 0: dmg *= 1.15
	if e.emp > 0: dmg *= 1.3
	# Godot: попадание по замаскированной Невидимке — маскировка сбоит, корабль проявляется
	if e.def.cloak and e.alpha < 0.6 and e.revealT <= 0:
		e.revealT = 0.9
		FX.sparks(e.x, e.y, "#9fc8ff", 10, 220)
		A.play("teleport", {"vol": 0.3, "rate": 2.2, "x": e.x})
	# щит щитоносца / дредноута
	if e.shield > 0:
		var mul := 3.0 if o.get("heavy", false) or src == "rail" or src == "bomb" else 1.0
		if src == "rail": e.shield = 0.0
		var absorbed := minf(e.shield, dmg * mul)
		e.shield -= absorbed
		e.shieldHitT = 0.15
		e.shieldRegenWait = 12.0 if e.boss else 4.0
		dmg -= absorbed / mul
		if e.shield <= 0:
			e.shield = 0.0
			FX.ring(e.x, e.y, e.r, e.r * 2, "#7fd8ff", 0.4, 4)
			FX.sparks(e.x, e.y, "#7fd8ff", 16, 300)
			A.play("shieldHit")
			if e.boss:
				Bus.emit("toast", {"ico": "🛡️", "title": "ЩИТ", "text": "Щит дредноута сломан!", "info": true})
				FX.shake(0.3)
		elif U.random() < 0.3:
			A.play("hitArmor", {"x": e.x})
		if dmg <= 0.01: return 0.0
	if e.boss:
		dmg = B.bossCap(e, dmg)
		if dmg <= 0: return 0.0
	e.hp -= dmg
	e.flash = 0.07
	if e.boss:
		run.bossDamage += dmg
		# с молнией в слотах босс роняет энергоблоки по мере урона — иначе против него молния без энергии
		if "lightning" in player.weapons:
			var step: float = e.maxHp * D.WEAPONS.lightning.base.bossStep
			e.enAcc += dmg
			while e.enAcc >= step:
				e.enAcc -= step
				dropEnergy(e.x + U.rand(-0.3, 0.3) * e.w, e.y + e.h * 0.3, 1, "boss")
	if o.get("cryo", false) and st.cryo > 0 and not e.boss and U.random() < st.cryo: e.frozen = 2.0
	if o.get("crit", false) and perk("burn"): ignite(e, dmg * 0.15 * perk("burn"))
	if o.get("conductor", false) and skill("sk_conductor") and U.random() < 0.08:
		var other := nearestOther(e, 140 * G.S)
		if other:
			FX.lightning(e.x, e.y, other.x, other.y, "#fff36b", 2 * G.S, 0.12)
			damageEnemy(other, dmg * 0.5, {"src": "lightning"})
	# 3.1: цифры урона копятся и всплывают одной суммой раз в DMG_NUM_T с
	if M.s.settings.get("dmgNums", true) and not o.get("noText", false) and FX.quality > 0:
		if e.dmgSum == 0.0: e.dmgT0 = t
		e.dmgSum += maxf(0, dmg + e.hp) if e.hp < 0 else dmg
		if crit: e.dmgCrit = true
	e.hitT = t
	if not e.boss and U.random() < 0.25: A.play("hit", {"x": e.x})
	if e.hp <= 0: E.kill(e, src)
	return dmg


## 4.3: поджог — урон горения копится (e.burn) и уходит за BURN_T с, наносится порциями раз в 0,25 с
func ignite(e: En, amount: float) -> void:
	if not e.alive or amount <= 0: return
	e.burn += amount
	e.burnT = BURN_T


func updateBurn(dt: float) -> void:
	for e in enemies:
		if not e.alive or not (e.burnT > 0): continue
		var part := e.burn * minf(1.0, dt / e.burnT)
		e.burn -= part
		e.burnT -= dt
		e.burnDps += part
		if FX.quality > 0 and U.random() < dt * 10:
			FX.embers(e.x + U.rand(-0.4, 0.4) * (e.rx if e.rx != 0.0 else e.r), e.y + U.rand(-0.3, 0.3) * (e.ry if e.ry != 0.0 else e.r), "#ff8a3d" if U.random() < 0.5 else "#ffd23d", 1, 45)
		if t - e.g("burnTick", 0.0) >= 0.25 or e.burnT <= 0:
			e.s("burnTick", t)
			var d := e.burnDps
			e.burnDps = 0.0
			if d > 0: damageEnemy(e, d, {"src": "burn"})
		if e.burnT <= 0: e.burn = 0.0


## горящий след «Солнечной плазмы»: каждые 0,25 с поджигает врагов в радиусе
func updateFire(dt: float) -> void:
	var f: Array = ov.fire
	if f.is_empty(): return
	var R := 26 * G.S
	for i in range(f.size() - 1, -1, -1):
		var p: Dictionary = f[i]
		p.t += dt
		if p.t >= FIRE_DUR:
			f[i] = f[f.size() - 1]
			f.pop_back()
			continue
		p.tick -= dt
		if p.tick > 0: continue
		p.tick = 0.25
		for e in enemies:
			if e.alive and e.hittable and inBlast(e, p.x, p.y, R): ignite(e, p.burn)


func flushDmgNums() -> void:
	for e in enemies:
		if e.dmgSum == 0.0 or (e.alive and t - e.dmgT0 < DMG_NUM_T): continue
		var n := int(round(e.dmgSum))
		var crit := e.dmgCrit
		e.dmgSum = 0.0
		e.dmgCrit = false
		if n > 0: FX.dmg_num(e.x + U.rand(-8, 8) * G.S, e.y - (e.ry if e.ry != 0.0 else e.r) * 0.5, n, crit)


func nearestOther(e: En, range_: float) -> En:
	var best: En = null
	var bd := range_
	for o in enemies:
		if o == e or not o.alive or not o.hittable: continue
		var d := sqrt((o.x - e.x) * (o.x - e.x) + (o.y - e.y) * (o.y - e.y))
		if d < bd:
			bd = d
			best = o
	return best


## отложенные взрывы (детонация и т.п.) — без глубокой рекурсии
func blast(x: float, y: float, r: float, dmg: float, color := "#ff9f3d", src := "blast") -> void:
	blasts.append({"x": x, "y": y, "r": r, "dmg": dmg, "color": color, "src": src})


func processBlasts() -> void:
	var guard := 0
	while blasts.size() and guard < 40:
		guard += 1
		var b: Dictionary = blasts.pop_front()
		FX.explode(b.x, b.y, 1, b.color)
		FX.ring(b.x, b.y, 6, b.r, b.color, 0.3, 3)
		for e in enemies:
			if not e.alive or not e.hittable: continue
			if inBlast(e, b.x, b.y, b.r): damageEnemy(e, b.dmg, {"src": b.src, "noText": true})


## вызывается из E.kill — награды за уничтожение
func onEnemyKilled(e: En, _src: String) -> void:
	var S := G.S
	if e.boss: return
	run.kills += 1
	M.onKill()
	run.combo += 1
	run.comboT = 5.2 if relic("r_combo") else 2.6
	if run.combo > run.maxCombo: run.maxCombo = run.combo
	if run.combo % 10 == 0: M.onCombo(run.combo)
	if perk("demo") and run.combo % 30 == 0 and player.bombs < 9:
		player.bombs += 1
		FX.text(player.x, player.y - player.w * 0.7, "🧨 +1 БОМБА", "#ff8a3d", 14, 1.0, -50)
		hudDirty = true
	if run.combo >= 50 and not run.fever: setFever(true)
	if run.combo == 10 or run.combo == 25:
		var big: bool = run.combo == 25
		var col := "#ffc83d" if big else "#3de0ff"
		FX.text(G.FW / 2, G.H * 0.38, "КОМБО %d!" % run.combo, col, 20 if big else 17, 1.1, -30)
		FX.ring(player.x, player.y, player.w * 0.5, player.w * (2.2 if big else 1.6), col, 0.45, 4)
		addScore(round((1500 if big else 500) * wave.n * diff.score))
		A.play("powerup", {"rate": 1.5 if big else 1.3, "vol": 0.6})
	var comboMul_ := 1 + minf(run.combo, 100) * 0.02
	var waveMul: float = 1 + (wave.n - 1) * 0.08
	var pts := roundf(e.score * waveMul * diff.score * comboMul_ * (2.0 if e.elite else 1.0))
	addScore(pts)
	# кредиты и кристаллы
	var coins: float = e.coins * (2.0 if e.elite and relic("r_hunteye") else 1.0) * st.coins * (1 + wave.n * D.ECON.waveGrowth) * (1.5 if run.fever else 1.0) \
		* (3.0 if e.elite else 1.0) * (diff.count if e.mini else 1.0) * ((3.0 if skill("sk_daredevil") else D.DANGER.coins) if wave.danger else 1.0)
	var ci := int(floorf(coins)) + (1 if U.random() < fmod(coins, 1.0) else 0)
	dropCoins(e.x, e.y, ci)
	dropXp(e.x, e.y, e.xp * (2.0 if e.elite else 1.0))
	# энергоблоки для молнии — только если она в слотах; Ионный отдаёт двойной блок
	if "lightning" in player.weapons and not e.def.prop:
		dropEnergy(e.x, e.y, 1 if e.mini or e.type == "ion" or U.random() < D.WEAPONS.lightning.base.drop else 0, "big" if e.type == "ion" else "std")
	# бонусы
	var luck: float = st.luck * (100.0 if e.mini else 1.0)
	var chance: float = (0.028 + (e.def.coins if e.def.coins else 1.0) * 0.006) * luck * (1.5 if diffId == "zen" else 1.0) * (diff.drops if diff.drops else 1.0)
	if U.random() < chance or e.mini: dropPowerup(e.x, e.y)
	if e.mini: dropPowerup(e.x + 20 * S, e.y)
	# навыки и улучшения
	if (e.elite or e.mini) and skill("sk_jackpot"): dropCrate(e.x, e.y)
	if e.elite: hitstop(0.04)
	# реликвии: кровавый камень лечит, нестабильный реактор взрывает убитых
	if relic("r_bloodstone"):
		run.bloodKills += 1
		if run.bloodKills >= 20:
			run.bloodKills = 0
			heal(1, "🩸 КАМЕНЬ")
	if relic("r_volatile") and not e.def.prop: blast(e.x, e.y, 70 * S, e.maxHp * 0.25 + 10, "#ff6a2a", "volatile")
	if skill("sk_vamp"):
		run.killsForVamp += 1
		if run.killsForVamp >= 25:
			run.killsForVamp = 0
			heal(1, "🧛 ВАМПИР")
	if skill("sk_detonator"):
		run.detCount += 1
		if run.detCount % 5 == 0: blast(e.x, e.y, 80 * S, 40 * dmgMul(), "#ff9f3d", "det")
	if st.nova > 0: blast(e.x, e.y, (46 + st.nova * 14) * S, 12 * st.nova * dmgMul(), "#ffb03d", "nova")
	if e.def.split and not e.isChild: E.split(e)
	if e.type == "debris" or e.type == "asteroid": M.trackMission("debris", 1)
	Haptic.light()
	hudDirty = true


func setFever(on: bool) -> void:
	if run.fever == on: return
	run.fever = on
	if on:
		FX.text(G.FW / 2, G.H * 0.42, "ФИВЕР! КРЕДИТЫ ×1.5", "#ff6bd6", 18, 1.4, -30)
		A.play("powerup", {"rate": 1.3})
	Bus.emit("intensity")


func addScore(n: float) -> void:
	run.score += int(maxf(0, round(n)))
	hudDirty = true


# ════════════════════════════════════════════════════════════
# УРОН ПО ИГРОКУ
# ════════════════════════════════════════════════════════════
func hitPlayer(sx: float, sy: float, cause := "") -> bool:
	var p := player
	if not p.alive or p.inv > 0 or state != "play": return false
	if run.skillFx.get("sk_barrier", 0.0) > 0: return false
	if st.dodge > 0 and U.random() < st.dodge:
		p.inv = 0.35
		FX.text(p.x, p.y - p.w * 0.6, "УКЛОНЕНИЕ", "#7fe7ff", 13, 0.7)
		if perk("nimble"): run.nextCrit = true
		FX.glow_puff(p.x, p.y, "#7fe7ff", 60 * G.S, 0.25)
		FX.sprite("fx_dash", 0, 0, {"follow": p, "w0": p.w * 0.9, "w1": p.w * 1.3, "dur": 0.35, "hold": 0.3, "hue": 190})
		Haptic.light()
		return false
	if p.shield:
		p.shield = false
		p.inv = 1.0 * st.invMul
		run.shieldRegenT = 0.0
		FX.ring(p.x, p.y, p.w * 0.6, p.w * 1.4, "#7fe7ff", 0.4, 4)
		FX.sprite("fx_sh_break", p.x, p.y, {"w0": p.w * 1.3, "w1": p.w * 2.3, "dur": 0.45, "hold": 0.3, "rot": U.rand(-0.4, 0.4)})
		if relic("r_shieldburst"): blast(p.x, p.y, 120 * G.S, 60 * dmgMul() * (1 + wave.n * 0.05), "#7fe7ff", "shieldburst")
		FX.sparks(p.x, p.y, "#7fe7ff", 18, 320)
		FX.dmg_arc(p.x, p.y, sx, sy, "#7fe7ff")
		Post.hurt(0.5)
		A.play("shieldHit")
		Haptic.medium()
		clearBulletsAround(p.x, p.y, 90 * G.S)
		hudDirty = true
		return true
	p.lives -= 1
	run.hitAt = run.time
	run.lastHit = cause if cause != "" else "Вражеский огонь"
	run.waveDamage += 1
	run.bossDamaged = true
	p.inv = 1.8 * st.invMul
	# второе дыхание: пули вокруг гаснут в большом радиусе
	clearBulletsAround(p.x, p.y, (260.0 if skill("sk_secondwind") else 130.0) * G.S)
	if skill("sk_secondwind"): FX.ring(p.x, p.y, p.w * 0.5, 260 * G.S, "#bff4ff", 0.5, 4)
	FX.explode(p.x, p.y, 1.2, "#ff5c7a")
	FX.vignette("#ff2a48", 0.6, 0.85)
	FX.dmg_arc(p.x, p.y, sx, sy)
	FX.shake(0.55)
	Post.hurt(1.0)
	A.play("playerHit")
	Haptic.heavy()
	# реликвия «Хронометр»: на последней жизни враги замедляются на 3 с (раз в волну)
	if p.lives == 1 and relic("r_chrono") and wave and not wave.get("chrono", false):
		wave.chrono = true
		run.skillFx.sk_timewarp = maxf(run.skillFx.get("sk_timewarp", 0.0), 3)
		FX.flash("#3d6bff", 0.25)
		FX.text(p.x, p.y - p.w * 0.9, "🕰️ ХРОНОМЕТР", "#9fc8ff", 14, 1.2)
		A.play("teleport", {"rate": 0.5})
	Bus.emit("playerHit", p.lives)
	hudDirty = true
	if p.lives <= 0: playerDown()
	return true


func hitCause(b: Eb, bs: En) -> String:
	var what: String = SHOT_NAMES.get(b.type, "вражеский снаряд")
	return bs.bdef.name + ", " + what if bs and bs.alive else what.substr(0, 1).to_upper() + what.substr(1)


func clearBulletsAround(x: float, y: float, r: float) -> void:
	for b in ebullets:
		if b.dead: continue
		if sqrt((b.x - x) * (b.x - x) + (b.y - y) * (b.y - y)) < r:
			b.dead = true
			FX.glow_puff(b.x, b.y, b.color, 18 * G.S, 0.2)


func heal(n: int, label := "") -> void:
	var p := player
	if not p.alive: return
	var before := p.lives
	p.lives = mini(p.maxLives, p.lives + n)
	if p.lives > before:
		FX.text(p.x, p.y - p.w * 0.7, label if label != "" else "+1 ЖИЗНЬ", "#ff6b8a", 13, 0.9)
		FX.glow_puff(p.x, p.y, "#ff6b8a", 70 * G.S, 0.35)
		FX.sprite("fx_regen", p.x, p.y - p.w * 0.35, {"w0": p.w * 0.45, "w1": p.w * 0.6, "dur": 0.9, "hold": 0.55, "fadeIn": 0.12, "vy": -45 * G.S})
		A.play("powerup", {"vol": 0.7})
		hudDirty = true


## кольца щита сходятся к кораблю — щит появился
func shieldFx() -> void:
	var p := player
	FX.sprite("fx_sh_restore", 0, 0, {"follow": p, "w0": p.w * 2.2, "w1": p.w * 1.2, "dur": 0.5, "hold": 0.4})
	run.shieldFxT = 1.0   # рябь по пузырю щита (Post.bubble)


func playerDown() -> void:
	var p := player
	# реликвия «Перо феникса»: воскрешение с 1 жизнью (раньше навыка — навык останется на потом)
	if relic("r_feather") and not run.featherUsed:
		run.featherUsed = true
		p.lives = 1; p.inv = 3.0
		clearBulletsAround(p.x, p.y, 9999)
		FX.flash("#ffd9a0", 0.5)
		FX.text(p.x, p.y - p.w, "ПЕРО ФЕНИКСА!", "#ffc83d", 18, 1.3)
		A.play("revive")
		hudDirty = true
		return
	# навык «Феникс»
	if skill("sk_phoenix") and not run.phoenixUsed:
		run.phoenixUsed = true
		p.lives = mini(2, p.maxLives)
		p.inv = 3.5
		novaWave(false)
		FX.flash("#ffb03d", 0.6)
		FX.explode(p.x, p.y, 2, "#ffb03d", {"kind": "crit"})
		FX.sprite("fx_beam", 0, 0, {"follow": p, "oy": -p.w * 0.95, "w0": p.w * 1.25, "w1": p.w * 1.4, "dur": 1.1, "hold": 0.5, "fadeIn": 0.1, "hue": 30})
		FX.text(p.x, p.y - p.w, "ФЕНИКС!", "#ffb03d", 20, 1.3)
		A.play("revive")
		Bus.emit("toast", {"ico": "🔥", "title": "НАВЫК", "text": "Феникс возродил корабль!", "info": true})
		hudDirty = true
		return
	p.alive = false
	state = "dying"
	slowT = 1.2
	FX.explode(p.x, p.y, 2.6, "#7fe7ff", {"kind": "super"})
	FX.flash("#ffffff", 0.5)
	A.play("explodeL")
	Haptic.error()
	after(1.3 * 0.45, afterDeath)


func afterDeath() -> void:
	if state != "dying": return
	var cost := D.revive_cost(wave.n)
	if not run.reviveUsed and M.s.coins >= cost:
		state = "revive"
		Bus.emit("reviveOffer", cost)
	else:
		gameOver()


func revive() -> bool:
	var cost := D.revive_cost(wave.n)
	if state != "revive" or not M.spend(cost): return false
	var p := player
	run.reviveUsed = true
	p.alive = true
	p.lives = mini(p.maxLives, maxi(2, ceili(p.maxLives / 2.0)))
	p.inv = 3.0
	p.x = G.FW / 2; p.y = G.H * 0.8
	state = "play"
	for b in ebullets: b.dead = true
	novaWave(false)
	FX.flash("#7fe7ff", 0.5)
	FX.sprite("fx_beam", 0, 0, {"follow": p, "oy": -p.w * 0.95, "w0": p.w * 1.25, "w1": p.w * 1.4, "dur": 1.1, "hold": 0.5, "fadeIn": 0.1, "hue": 190})
	A.play("revive")
	hudDirty = true
	Bus.emit("revived")
	return true


func gameOver() -> void:
	if state == "over": return
	state = "over"
	var wn: int = wave.n if wave else 0
	var result: Dictionary = M.finishRun({"score": run.score, "wave": wn, "kills": run.kills, "bosses": run.bosses, "maxCombo": run.maxCombo,
		"time": run.time, "diff": diffId, "perks": run.perkCount, "shots": run.shots, "hits": run.hits, "challenge": run.challenge != null, "mode": mode})
	var summary := result.duplicate()
	summary.merge({"mode": mode, "score": run.score, "wave": wn, "sector": run.sector, "kills": run.kills, "bosses": run.bosses, "maxCombo": run.maxCombo,
		"time": run.time, "coins": run.coins, "accuracy": int(round(minf(1.0, float(run.hits) / run.shots) * 100)) if run.shots else 0,
		"diff": diffId, "level": run.level, "cause": run.lastHit, "chests": run.chests.duplicate()}, true)
	Bus.emit("runEnd", summary)


# ════════════════════════════════════════════════════════════
# БОМБА И АКТИВНЫЕ НАВЫКИ
# ════════════════════════════════════════════════════════════
func useBomb() -> void:
	var p := player
	if state != "play" or not p.alive: return
	if p.bombs <= 0:
		A.play("error")
		return
	if p.bombCd > 0: return
	p.bombs -= 1
	p.bombCd = 1.2 * st.cdMul * st.bombCd
	p.inv = maxf(p.inv, 1.2)
	var S := G.S
	FX.ring(p.x, p.y, 10, maxf(G.FW, G.H) * 1.1, "#ffb36b", 0.7, 10)
	FX.ring(p.x, p.y, 10, maxf(G.FW, G.H) * 0.8, "#ffffff", 0.5, 4)
	FX.sprite("fx_ex_kill", p.x, p.y, {"w0": 90 * S, "w1": 290 * S, "dur": 0.6, "hold": 0.25, "rot": U.random() * TAU})
	FX.sprite("fx_shock", p.x, p.y, {"w0": 60 * S, "w1": 250 * S, "dur": 0.55, "hold": 0.25, "hue": 28})
	FX.flash("#ffd9a0", 0.55)
	FX.shake(0.8)
	A.play("bomb")
	Haptic.heavy()
	for b in ebullets:
		if not b.dead:
			b.dead = true
			FX.glow_puff(b.x, b.y, b.color, 16 * S, 0.3)
	var dmg: float = 320 * st.bomb * (1 + wave.n * 0.1) * dmgMul()
	var killed := 0
	for e in enemies:
		if not e.alive or not e.hittable: continue
		if e.boss:
			damageEnemy(e, e.maxHp * 0.06 * st.bomb, {"src": "bomb", "noText": false})
			continue
		var before := e.alive
		damageEnemy(e, dmg, {"src": "bomb", "noText": true})
		if before and not e.alive: killed += 1
	if killed >= 10: M.unlock("bomb_chain")
	# реликвия «Ядро сингулярности»: после бомбы — чёрная дыра на 4 с
	if relic("r_singularity"):
		ov.hole = {"x": G.FW / 2, "y": G.H * 0.32, "t": 0.0, "dur": 4.0, "tick": 0.0}
		A.play("dark", {"rate": 0.6})
	hudDirty = true


func activeSkills() -> Array:
	var out: Array = []
	for id in M.s.skills:
		if M.s.skills[id] and D.SKILLS.has(id) and D.SKILLS[id].type == "active":
			out.append(id)
			if out.size() >= D.MAX_ACTIVE: break
	return out


func useSkill(slot: int) -> void:
	if state != "play" or not player.alive: return
	var ids := activeSkills()
	if slot >= ids.size(): return
	var id: String = ids[slot]
	var sk: Dictionary = D.SKILLS[id]
	if run.skillCd.get(id, 0.0) > 0:
		A.play("error")
		return
	run.skillCd[id] = sk.cd * st.cdMul
	if sk.dur: run.skillFx[id] = sk.dur
	if skill("sk_overload"): run.overload = 4.0
	A.play("skill")
	Haptic.medium()
	# 3.1: у каждого активного навыка — своя анимация запуска
	skillCast(id, sk)
	M.trackMission("skills", 1)
	hudDirty = true


## шевроны «ускорения» поднимаются сквозь корабль
func speedFx(hue: float) -> void:
	var p := player
	FX.sprite("fx_speed", 0, 0, {"follow": p, "oy": p.w * 0.7, "vy": -95 * G.S, "w0": p.w * 0.6, "w1": p.w * 0.74, "dur": 0.75, "hold": 0.5, "fadeIn": 0.15, "hue": hue})


func novaWave(withDamage: bool) -> void:
	var p := player
	var S := G.S
	FX.ring(p.x, p.y, 10, maxf(G.FW, G.H), "#bfe6ff", 0.6, 8)
	FX.sprite("fx_shock", p.x, p.y, {"w0": 40 * S, "w1": 240 * S, "dur": 0.5, "hold": 0.25, "alpha": 0.9})
	FX.sprite("fx_flare", p.x, p.y, {"w0": 60 * S, "w1": 150 * S, "dur": 0.45, "hold": 0.25})
	FX.flash("#cfeaff", 0.35)
	FX.shake(0.5)
	A.play("explodeM")
	for b in ebullets:
		if not b.dead:
			b.dead = true
			FX.glow_puff(b.x, b.y, b.color, 14 * S, 0.25)
	if not withDamage: return
	for e in enemies:
		if not e.alive or not e.hittable: continue
		if e.boss: damageEnemy(e, e.maxHp * 0.1, {"src": "nova"})
		elif e.mini: damageEnemy(e, e.maxHp * 0.5, {"src": "nova"})
		else: damageEnemy(e, 999999, {"src": "nova", "noText": true})


func updateOverlays(dt: float) -> void:
	var p := player
	var S := G.S
	# рельса
	if ov.rail:
		var r: Dictionary = ov.rail
		r.t += dt
		if r.t >= r.charge:
			if not r.get("fired", false):
				r.fired = true
				A.play("rail"); FX.shake(0.4); FX.flash("#99ffff", 0.2)
			r.tick -= dt
			if r.tick <= 0:
				r.tick = 0.08
				var half := 20 * S
				for e in enemies:
					if not e.alive or not e.hittable or e.y > p.y: continue
					if absf(e.x - p.x) < half + (e.rx * 0.85 if e.rx != 0.0 else e.r * 0.8):
						damageEnemy(e, (22.0 if e.boss else 48.0) * dmgMul() * (1 + wave.n * 0.05), {"src": "rail", "noText": U.random() < 0.6})
						if U.random() < 0.4: FX.sparks(e.x, e.y, "#7ffff0", 3, 220)
				for b in ebullets:
					if not b.dead and absf(b.x - p.x) < half and b.y < p.y: b.dead = true
		if r.t >= r.charge + r.dur: ov.rail = null
	# чёрная дыра
	if ov.hole:
		var h: Dictionary = ov.hole
		h.t += dt
		var R := 210 * S
		h.tick -= dt
		for e in enemies:
			if not e.alive or e.boss: continue
			var dx: float = h.x - e.x
			var dy: float = h.y - e.y
			var d := sqrt(dx * dx + dy * dy)
			if d < R * 1.8 and d > 4:
				var f := (60.0 if e.mini else 260.0) * S * dt
				e.x += dx / d * f; e.y += dy / d * f
		for b in ebullets:
			if b.dead: continue
			var dx: float = h.x - b.x
			var dy: float = h.y - b.y
			var d := sqrt(dx * dx + dy * dy)
			if d < 24 * S:
				b.dead = true
				continue
			if d < R * 2:
				b.vx += dx / d * 600 * S * dt; b.vy += dy / d * 600 * S * dt
		if h.tick <= 0:
			h.tick = 0.15
			for e in enemies:
				if e.alive and e.hittable and sqrt((e.x - h.x) * (e.x - h.x) + (e.y - h.y) * (e.y - h.y)) < R * 0.6: damageEnemy(e, 18 * dmgMul(), {"src": "hole", "noText": true})
		if FX.quality > 0:
			var a := U.random() * TAU
			FX.embers(h.x + cos(a) * R * 0.9, h.y + sin(a) * R * 0.9, "#b06bff", 1, 10)
		if h.t >= h.dur:
			FX.explode(h.x, h.y, 3, "#b06bff", {"hue": 275})
			FX.ring(h.x, h.y, 10, R * 1.5, "#e0c8ff", 0.5, 8)
			FX.flash("#d9b8ff", 0.35)
			FX.shake(0.6)
			A.play("explodeL", {"vol": 0.8})
			for e in enemies:
				if not e.alive or not e.hittable: continue
				if sqrt((e.x - h.x) * (e.x - h.x) + (e.y - h.y) * (e.y - h.y)) < R + e.r: damageEnemy(e, e.maxHp * 0.08 if e.boss else 500 * dmgMul(), {"src": "hole"})
			ov.hole = null
	var beams: Array = ov.beams
	for i in range(beams.size() - 1, -1, -1):
		var bm: Dictionary = beams[i]
		bm.t += dt
		# луч гаснет, если стрелок погиб до выстрела, и после окончания
		var owner = bm.owner
		if (owner != null and not owner.alive and bm.t < bm.warn) or bm.t >= bm.warn + bm.dur: beams.remove_at(i)
	# вертикальные лучи (дредноут, ионный, инквизитор) ранят один раз
	for bm in beams:
		if bm.t >= bm.warn and not bm.hitDone and p.alive and absf(p.x - bm.x) < bm.w * 0.75 + p.r and p.y > bm.y0:
			bm.hitDone = true
			hitPlayer(bm.x, bm.y0, boss.bdef.name + ", луч" if boss else "Луч")
		# столпы света Цитадели бьют и по врагам
		if bm.get("foes", false) and bm.t >= bm.warn and not bm.get("foesDone", false):
			bm.foesDone = true
			for e in enemies:
				if e.alive and e.hittable and not e.def.prop and absf(e.x - bm.x) < bm.w * 0.75 + e.r and e.y > bm.y0:
					damageEnemy(e, e.maxHp * 0.02 if e.boss or e.mini else e.maxHp * 0.5 + 30, {"src": "pillar"})
	# поворотные лазеры: прикреплены к владельцу, могут следить за игроком
	var edt := dt * enemySlow()
	var lasers: Array = ov.lasers
	for i in range(lasers.size() - 1, -1, -1):
		var L: Dictionary = lasers[i]
		var owner = L.owner
		if owner != null and not owner.alive:
			lasers.remove_at(i)
			continue
		L.t += edt
		if L.t >= L.warn + L.dur:
			lasers.remove_at(i)
			continue
		var o := laserOrigin(L)
		if L.track and p.alive:
			var want := atan2(p.y - o.y, p.x - o.x)
			var rate: float = L.track * 1.6 if L.t < L.warn else L.track
			L.ang += U.clamp(U.angle_diff(L.ang, want), -rate * edt, rate * edt)
		if L.t >= L.warn: L.ang += L.spin * edt
		if L.t >= L.warn + 0.05 and p.alive and p.inv <= 0:
			var dx := cos(L.ang)
			var dy := sin(L.ang)
			var tt := U.clamp((p.x - o.x) * dx + (p.y - o.y) * dy, 0, L.len)
			var qx := o.x + dx * tt
			var qy := o.y + dy * tt
			if sqrt((p.x - qx) * (p.x - qx) + (p.y - qy) * (p.y - qy)) < L.w * 0.45 + p.r:
				hitPlayer(o.x, o.y, (owner.bdef.name + ", " if owner != null and owner.boss else "") + "лазер")


## L: { owner, ox, oy — доли размера владельца, ang, spin, track, warn, dur, w, len, color }
func laser(o: Dictionary) -> Dictionary:
	var L := {"t": 0.0, "ox": 0.0, "oy": 0.0, "spin": 0.0, "track": 0.0, "warn": 0.8, "dur": 1.2, "w": 16 * G.S, "len": 1800 * G.S, "color": "#ff3d5a", "owner": null, "ang": 0.0, "x": 0.0, "y": 0.0}
	L.merge(o, true)
	ov.lasers.append(L)
	return L


func laserOrigin(L: Dictionary) -> Vector2:
	var w = L.owner
	return Vector2(w.x + L.ox * w.w, w.y + L.oy * w.h) if w != null else Vector2(L.x, L.y)


# ════════════════════════════════════════════════════════════
# ВРАЖЕСКИЕ СНАРЯДЫ
# ════════════════════════════════════════════════════════════
## o: { sprite, w, r, life, accel, homing, fuse, maxSpd, redir, redirSpd, burst, bounce, sine, escort }
func ebullet(x: float, y: float, vx: float, vy: float, type: String, o := {}) -> Eb:
	if ebullets.size() > 420: return null
	var def: Dictionary = EB.get(type, EB.orb)
	var S := G.S
	var b := Eb.new()
	b.x = x; b.y = y; b.px = x; b.py = y; b.vx = vx; b.vy = vy; b.type = type
	b.sprite = o.get("sprite", def.sprite)
	if def.has("tint"): b.cv = G.tinted(def.sprite, {"hue": def.tint})
	elif def.has("proc") and not G.has(def.sprite): b.cv = G.proc(def.proc)
	b.w = o.get("w", def.w) * S; b.r = o.get("r", def.r) * S; b.color = def.color; b.rotate = def.get("rotate", false)
	b.life = o.get("life", 9.0)
	b.accel = o.get("accel", 0.0); b.homing = o.get("homing", 0.0); b.fuse = o.get("fuse", 0.0)
	b.maxSpd = o.get("maxSpd", 0.0)
	b.redirT = o.get("redir", 0.0); b.redirSpd = o.get("redirSpd", 0.0)
	b.burst = o.get("burst"); b.bounce = int(o.get("bounce", 0))
	b.sine = o.get("sine")
	b.escort = o.get("escort", false)   # 4.2: летит в Торговца (эскорт)
	ebullets.append(b)
	return b


## скорость вражеских снарядов растёт со сложностью и волной
func bspd(v: float) -> float:
	return v * G.S * diff.bspd * (1 + minf(threatWave(), 40) * 0.012)


## «волна угрозы»: номер волны со сдвигом сложности — по нему состав волн, темп огня, упреждение и новые атаки
func threatWave() -> float:
	return (wave.n if wave else 1.0) + diff.waveOffset


## упреждение: часть выстрелов летит туда, где корабль окажется
func leadK() -> float:
	return U.clamp((threatWave() - 3) / 17.0, 0, 1) * diff.lead


func aimAt(x: float, y: float, spd: float, type: String, spreadA := 0.0, o := {}) -> Eb:
	var p := player
	var s := bspd(spd)
	var tx := p.x
	var ty := p.y
	if U.random() < leadK():
		var tt := minf(1.2, sqrt((p.x - x) * (p.x - x) + (p.y - y) * (p.y - y)) / maxf(s, 1))
		tx = U.clamp(p.x + p.vxm * tt, 0, G.FW)
		ty = p.y + p.vym * tt * 0.5
	var a := atan2(ty - y, tx - x) + spreadA
	return ebullet(x, y, cos(a) * s, sin(a) * s, type, o)


func updateEBullets(dt: float) -> void:
	var p := player
	var FW := G.FW
	var H := G.H
	var S := G.S
	var pr := p.r
	# астероиды сектора закрывают от вражеских снарядов
	_cover.clear()
	for e in enemies: if e.alive and e.def.cover: _cover.append(e)
	var barrier: bool = run.skillFx.get("sk_barrier", 0.0) > 0
	for b in ebullets:
		if b.dead: continue
		b.age += dt; b.life -= dt
		b.px = b.x; b.py = b.y
		if b.accel != 0.0:
			var sp := sqrt(b.vx * b.vx + b.vy * b.vy)
			var ns := minf(b.maxSpd if b.maxSpd else 9999.0, sp + b.accel * dt)
			if sp > 0:
				b.vx *= ns / sp; b.vy *= ns / sp
		if b.homing != 0.0 and p.alive and b.age < 2.2:
			var ang := atan2(b.vy, b.vx)
			var want := atan2(p.y - b.y, p.x - b.x)
			ang += U.clamp(U.angle_diff(ang, want), -b.homing * dt, b.homing * dt)
			var sp := sqrt(b.vx * b.vx + b.vy * b.vy)
			b.vx = cos(ang) * sp; b.vy = sin(ang) * sp
		# «перо»: тормозит, замирает и бросается в игрока
		if b.redirT > 0 and not b.redone:
			b.vx *= exp(-4 * dt); b.vy *= exp(-4 * dt)
			if b.age >= b.redirT:
				b.redone = true
				var a := atan2(p.y - b.y, p.x - b.x)
				var sp := b.redirSpd if b.redirSpd else 220 * S
				b.vx = cos(a) * sp; b.vy = sin(a) * sp
		b.x += b.vx * dt; b.y += b.vy * dt
		# «волна»: снаряд виляет поперёк курса
		if b.sine:
			var sp := sqrt(b.vx * b.vx + b.vy * b.vy)
			if sp == 0.0: sp = 1.0
			var k: float = b.sine.amp * b.sine.f * cos(b.age * b.sine.f + b.sine.ph) * dt
			b.x -= b.vy / sp * k; b.y += b.vx / sp * k
		if b.bounce > 0 and (b.x < 4 or b.x > FW - 4):
			b.vx = -b.vx; b.x = U.clamp(b.x, 4, FW - 4); b.bounce -= 1
		# кладка/клякса: разрывается кольцом по таймеру
		if b.burst and b.type != "mine":
			b.fuse -= dt
			if b.fuse <= 0:
				b.dead = true
				var bu: Dictionary = b.burst
				var sp := bspd(bu.spd)
				var off := U.random() * TAU
				var bn := int(bu.n)
				for i in bn:
					var a := off + float(i) / bn * TAU
					ebullet(b.x, b.y, cos(a) * sp, sin(a) * sp, bu.type)
				FX.glow_puff(b.x, b.y, b.color, 40 * S, 0.25)
				continue
		if b.type == "mine":
			b.vx *= exp(-1.5 * dt); b.vy = U.damp(b.vy, 45 * S, 2, dt)
			b.fuse -= dt
			if b.fuse <= 0 or (p.alive and sqrt((p.x - b.x) * (p.x - b.x) + (p.y - b.y) * (p.y - b.y)) < 70 * S):
				b.dead = true
				FX.explode(b.x, b.y, 0.7, "#ff5c5c")
				A.play("explodeS", {"vol": 0.5})
				for i in 8:
					var a := i * PI / 4
					ebullet(b.x, b.y, cos(a) * bspd(150), sin(a) * bspd(150), "orb")
				continue
		if b.life <= 0 or b.y > H + 40 or b.y < -80 or b.x < -50 or b.x > FW + 50:
			b.dead = true
			continue
		if _cover.size() and hitsCover(b):
			b.dead = true
			FX.hit(b.x, b.y, "#d8c3a5")
			continue
		# барьер (навык) отражает пули обратно во врагов, дрон-Страж их ловит
		if barrier and Skills.reflect(b):
			b.dead = true
			continue
		if Comp.block(b):
			b.dead = true
			continue
		if RunMap.escortHit(b):
			b.dead = true
			continue
		# попадание в игрока (стреловидная проверка — снаряд не «проскакивает»)
		if p.alive and p.inv <= 0:
			var rr := pr + b.r * 0.75
			if absf(b.x - p.x) < rr + 30 and absf(b.y - p.y) < rr + 40 and U.seg_dist2(p.x, p.y, b.px, b.py, b.x, b.y) < rr * rr:
				b.dead = true
				# источник — точка на секунду назад по траектории: дуга урона со стороны выстрела
				hitPlayer(b.x - b.vx, b.y - b.vy, hitCause(b, boss))


func hitsCover(b: Eb) -> bool:
	for e in _cover:
		var rr := e.r + b.r * 0.5
		if U.dist2(e.x, e.y, b.x, b.y) < rr * rr: return true
	return false


# ════════════════════════════════════════════════════════════
# ПОДБИРАЕМЫЕ ПРЕДМЕТЫ
# ════════════════════════════════════════════════════════════
func pick(kind: String, x: float, y: float, val: float) -> Pk:
	var it := Pk.new()
	var a := U.random() * TAU
	var s := U.rand(60, 170) * G.S
	it.kind = kind; it.x = x; it.y = y; it.vx = cos(a) * s; it.vy = sin(a) * s - 40 * G.S; it.val = val
	it.spin = U.random() * 6
	pickups.append(it)
	return it


func dropCoins(x: float, y: float, n: int) -> void:
	if n <= 0: return
	var left := n
	var guard := 0
	while left > 0 and guard < 10:
		guard += 1
		var v := 25 if left >= 25 and guard < 9 else (5 if left >= 5 and guard < 9 else left)
		var take := left if guard >= 9 else v
		pick("coin", x, y, take)
		left -= take


func dropXp(x: float, y: float, n: float) -> void:
	var left := int(round(n))
	var guard := 0
	while left > 0 and guard < 6:
		guard += 1
		var v := 5 if left >= 5 and guard < 6 else (left if guard >= 6 else 1)
		pick("xp", x, y, v)
		left -= v


## не больше, чем не хватает до полной энергии с учётом уже лежащих блоков, и не больше maxOnScreen на экране
## kind: 'boss' — синий блок с босса, 'big' — зелёный двойной (из Ионного)
func dropEnergy(x: float, y: float, n: int, kind := "std") -> void:
	var lb: Dictionary = D.WEAPONS.lightning.base
	var lying := 0
	for it in pickups: if not it.dead and it.kind == "en": lying += 1
	var need := int(ceil((1 - run.energy) / lb.block - 0.01)) - lying
	n = mini(n, mini(need, int(lb.maxOnScreen) - lying))
	for i in n:
		var it := pick("en", x, y, 2 if kind == "big" else 1)
		it.vx *= 0.5
		it.en = kind


## ящик Конвоя (3.1): цена растёт с волной
func dropCrate(x: float, y: float, val := 0.0) -> Pk:
	var it := pick("crate", x, y, val if val else round((8 + wave.n * 1.2) * st.coins))
	it.vx *= 0.3
	it.vy = -50 * G.S
	return it


func dropPowerup(x: float, y: float, type := "") -> Pk:
	if type == "" and noDrops(): return null
	if type == "":
		var p := player
		var ks: Array = []
		for k in D.POWERUPS:
			if not (k == "heal" and p.lives >= p.maxLives) and not (k == "shield" and p.shield): ks.append(k)
		type = U.pick_weighted(ks, func(k): return D.POWERUPS[k].weight)
	var it := pick("pu", x, y, 0)
	it.pu = type
	it.vx *= 0.3
	it.vy = -60 * G.S
	return it


func updatePickups(dt: float) -> void:
	var p := player
	var S := G.S
	var magnetAll: bool = buffs.get("magnet", 0.0) > 0 or st.magnet >= 9999
	var H := G.H
	for it in pickups:
		if it.dead: continue
		it.age += dt
		it.spin += dt * 6
		var dx := p.x - it.x
		var dy := p.y - it.y
		var d := sqrt(dx * dx + dy * dy)
		# бонус и ящик Конвоя сами к кораблю не летят — их нужно подобрать
		var big := it.kind == "pu" or it.kind == "crate"
		var mr: float = st.magnet * 0.6 if big else st.magnet
		# кредиты и кристаллы сами летят к кораблю через 2.5 с; энергоблоки молнии нужно собрать самому (или магнитом)
		if p.alive and (it.pull or (it.age > 0.35 and (magnetAll or d < mr or Comp.pulls(it))) or (not big and it.kind != "en" and it.age > 2.5)):
			it.pull = true
			var sp := (380 + it.age * 120) * S
			var dd := d if d != 0.0 else 1.0
			it.vx = U.damp(it.vx, dx / dd * sp, 9, dt)
			it.vy = U.damp(it.vy, dy / dd * sp, 9, dt)
		else:
			it.vx *= exp(-2.6 * dt)
			it.vy = U.damp(it.vy, (55.0 if big else 70.0) * S, 1.8, dt)
		it.x += it.vx * dt; it.y += it.vy * dt
		if p.alive and d < p.pickR + (10 * S if big else 0.0):
			collect(it)
			continue
		if it.y > H + 30 or it.age > (14.0 if big else 10.0): it.dead = true


func collect(it: Pk) -> void:
	it.dead = true
	var p := player
	match it.kind:
		"coin":
			run.coins += int(it.val)
			M.addCoins(int(it.val))
			M.trackMission("coins", int(it.val))
			A.play("coin")
			Bus.emit("coinPicked")
		"xp":
			run.xp += it.val * st.xp
			A.play("xp")
			while run.xp >= D.perk_xp_need(run.level):
				run.xp -= D.perk_xp_need(run.level)
				run.level += 1
				run.pendingPerks += 1
		"en":
			run.energy = minf(1.0, run.energy + D.WEAPONS.lightning.base.block * (it.val if it.val else 1.0))
			A.play("zap", {"vol": 0.35, "rate": 2})
		"crate":
			# ящик Конвоя: кредиты и случайный бонус
			run.coins += int(it.val)
			M.addCoins(int(it.val))
			M.trackMission("coins", int(it.val))
			FX.text(p.x, p.y - p.w * 0.7, "ЯЩИК  +%d" % int(it.val), "#ffc83d", 15, 1.0, -60)
			FX.ring(p.x, p.y, p.w * 0.4, p.w * 1.4, "#ffc83d", 0.4, 3)
			A.play("coin", {"rate": 0.8})
			A.play("powerup", {"vol": 0.6})
			var ks: Array = []
			for k in D.POWERUPS:
				if not (k == "heal" and p.lives >= p.maxLives) and not (k == "shield" and p.shield): ks.append(k)
			applyPowerup(U.pick_weighted(ks, func(k): return D.POWERUPS[k].weight))
			run.pickups += 1
			Bus.emit("coinPicked")
		_:
			applyPowerup(it.pu)
			run.pickups += 1
			M.trackMission("pickups", 1)
	hudDirty = true


func applyPowerup(type: String) -> void:
	var p := player
	var def: Dictionary = D.POWERUPS[type]
	var S := G.S
	A.play("powerup")
	Haptic.medium()
	FX.glow_puff(p.x, p.y, def.color, 90 * S, 0.35)
	FX.sprite("fx_pickup", 0, 0, {"follow": p, "w0": p.w * 0.8, "w1": p.w * 1.9, "dur": 0.45, "hold": 0.35, "hue": G.hue_of(def.color)})
	FX.text(p.x, p.y - p.w * 0.7, def.name, def.color, 13, 1.0, -50)
	if type == "rapid": speedFx(G.hue_of(def.color))
	elif type == "star": FX.sprite("fx_flare", 0, 0, {"follow": p, "w0": p.w * 0.8, "w1": p.w * 2.2, "dur": 0.5, "hold": 0.3, "hue": 45})
	elif type == "freeze":
		FX.ring(p.x, p.y, p.w * 0.5, maxf(G.FW, G.H) * 0.9, "#bff4ff", 0.8, 5)
		for i in 6:
			var a := i / 6.0 * TAU
			FX.sprite("fx_flare", p.x + cos(a) * p.w * 1.1, p.y + sin(a) * p.w * 1.1, {"w0": 18 * S, "w1": 34 * S, "dur": 0.5 + i * 0.04, "hold": 0.3, "hue": 190, "rot": a})
		for e in enemies:
			if e.alive and not e.boss: FX.sprite("fx_flare", e.x, e.y, {"w0": 16 * S, "w1": 28 * S, "dur": 0.45, "hold": 0.3, "hue": 190, "minor": true})
	match type:
		"heal": heal(1)
		"shield":
			p.shield = true
			run.shieldRegenT = 0.0
			shieldFx()
			M.unlock("shield")
		"bomb": p.bombs = mini(p.bombs + 1, 9)
		"star":
			var pts := roundf(1000 * wave.n * diff.score)
			addScore(pts)
			FX.text(p.x, p.y - p.w, "+" + U.fmt(pts), "#ffd23d", 15, 1.1, -60)
			dropCoins(p.x, p.y - 40 * S, int(round(8 * st.coins)))
		_:
			if def.dur: buffs[type] = def.dur
			if type == "freeze": FX.flash("#9be8ff", 0.25)
	hudDirty = true


# ════════════════════════════════════════════════════════════
# УЛУЧШЕНИЯ ЗАБЕГА (выбор 1 из 3)
# ════════════════════════════════════════════════════════════
func perkChoices() -> Array:
	var p := player
	var avail: Array = []
	for pk in D.PERKS:
		var lv := perk(pk.id)
		if lv >= pk.max or pk.filler: continue
		if pk.id == "shieldgen" and st.shieldRegen and st.shieldRegen <= 15: continue
		if (pk.id == "maxhp" or pk.id == "shieldgen") and perk("glass"): continue
		if pk.id == "glass" and p.lives < 1: continue
		if pk.id == "ricochet" and skill("sk_ricochet"): continue
		avail.append(pk)
	var picks: Array = []
	var pool := avail.duplicate()
	while picks.size() < 3 and pool.size():
		var pk = U.pick_weighted(pool, func(x): return D.RARITY[x.rar].w * (1.8 if evoStep(x.id) else 1.0))
		picks.append(pk)
		pool.erase(pk)
	# утешительные карты: когда основное взято; на последней жизни «Ремонт» подменяет одну карту
	var healCard = null
	var ammo = null
	for x in D.PERKS:
		if x.id == "heal": healCard = x
		if x.id == "bomb": ammo = x
	var canHeal := p.lives < p.maxLives
	if canHeal and p.lives <= 1 and picks.size() == 3 and U.random() < 0.6: picks[2] = healCard
	for f in [healCard if canHeal else null, ammo]:
		if f != null and picks.size() < 3 and not f in picks: picks.append(f)
	return picks


## эволюции оружия
func evo(wid: String) -> bool:
	return bool(run and run.evo.get(wid, false))


## эволюция, к которой ведёт перк (оружие в бою, эволюция ещё не получена)
func evoStep(perkId: String) -> Variant:
	for ev in D.EVOLUTIONS:
		if ev.perk == perkId and ev.weapon in player.weapons and not evo(ev.weapon): return ev
	return null


func checkEvolutions() -> void:
	var p := player
	for ev in D.EVOLUTIONS:
		if run.evo.get(ev.weapon, false) or not ev.weapon in p.weapons or perk(ev.perk) < ev.lvl: continue
		run.evo[ev.weapon] = true
		M.onEvolution(ev.weapon)
		FX.text(G.FW / 2, G.H * 0.4, "ЭВОЛЮЦИЯ: " + ev.name, "#ff9ff3", 18, 1.8, -25)
		FX.sprite("fx_beam", 0, 0, {"follow": p, "oy": -p.w * 0.95, "w0": p.w * 1.3, "w1": p.w * 1.5, "dur": 1.2, "hold": 0.5, "fadeIn": 0.1, "hue": 300})
		FX.flash("#ff9ff3", 0.3)
		A.play("levelup", {"rate": 1.2})
		var wdef: Dictionary = D.WEAPONS[ev.weapon]
		if not tipOnce("evo_" + ev.weapon, {"kind": "ЭВОЛЮЦИЯ ОРУЖИЯ", "ico": "🧬", "title": ev.name, "color": wdef.color, "note": "Оружие: " + wdef.name + ". Действует до конца забега."}):
			Bus.emit("toast", {"ico": "🧬", "title": "ЭВОЛЮЦИЯ ОРУЖИЯ", "text": ev.name + ": " + ev.desc, "info": true, "dur": 3200})
		if p.weapon != ev.weapon: setWeapon(ev.weapon)


func offerPerk() -> void:
	state = "perk"
	offerKind = "perk"
	pointer.id = -1
	A.play("levelup")
	Haptic.success()
	Bus.emit("perkOffer", U.with_rng(run.perkRng, perkChoices))


# ── модули корабля: старт забега и станция после босса (kind: 'start' | 'station') ──
func moduleChoices() -> Array:
	var pool: Array = []
	for m in D.MODULES:
		if mod(m.id) < m.max and not (m.id == "plating" and perk("glass")): pool.append(m)
	var n: int = int(D.MODULE_CHOICES) + (1 if run.pilot == "lira" else 0) + (1 if skill("sk_scavenger") else 0)
	var picks: Array = []
	while picks.size() < n and pool.size():
		var m = U.pick_weighted(pool, func(x): return D.RARITY[x.rar].w)
		picks.append(m)
		pool.erase(m)
	return picks


func offerModules(kind: String) -> void:
	var choices: Array = U.with_rng(run.perkRng, moduleChoices)
	if state != "play" or not player.alive or choices.is_empty():
		if kind == "station": jumpScene()
		return
	# Борк чинит корабль на каждой станции
	if kind == "station" and run.pilot == "bork" and player.lives < player.maxLives: heal(1, "🔧 БОРК ЧИНИТ")
	state = "perk"
	offerKind = kind
	pointer.id = -1
	A.play("levelup", {"rate": 0.8})
	Haptic.success()
	Bus.emit("moduleOffer", choices, kind)


func chooseModule(id: String) -> void:
	if state != "perk": return
	var p := player
	var kind := offerKind
	run.mods[id] = run.mods.get(id, 0) + 1
	run.parts = shipParts(run.mods)
	if id == "plating":
		p.maxLives += 2; p.lives += 2
	if id == "shieldcore" and not p.shield:
		p.shield = true
		shieldFx()
	if id == "bombbay": p.bombs = mini(9, p.bombs + 2)
	refreshStats()
	A.play("perk")
	FX.glow_puff(p.x, p.y, "#ffc83d", 120 * G.S, 0.5)
	FX.ring(p.x, p.y, p.w * 0.4, p.w * 1.7, "#ffc83d", 0.5, 4)
	p.inv = maxf(p.inv, 0.8)
	offerKind = ""
	state = "play"
	hudDirty = true
	if kind == "station": after(0.4, jumpScene)
	if kind == "start" and mode == "rush" and wave and wave.n == 0: after(0.4, nextWave)


func rerollCost() -> int:
	return 40 + run.rerolls * 40


func rerollPerks() -> Variant:
	if state != "perk": return null
	if not M.spend(rerollCost()):
		A.play("error")
		return null
	run.rerolls += 1
	A.play("click")
	return U.with_rng(run.perkRng, perkChoices)


## действие перка; free — подарен правилами (не считается выбором и не идёт в задания)
func grantPerk(id: String, free := false) -> void:
	var p := player
	run.perks[id] = run.perks.get(id, 0) + 1
	if not free:
		run.perkCount += 1
		run.pendingPerks = maxi(0, run.pendingPerks - 1)
		M.trackMission("perks", 1)
		if run.level >= 15: M.unlock("perk15")
	if id == "heal": p.lives = mini(p.maxLives, p.lives + 1)
	if id == "maxhp":
		p.maxLives += 1; p.lives += 1
	if id == "bomb": p.bombs = mini(9, p.bombs + 1)
	if id == "shieldgen" and not p.shield:
		p.shield = true
		if not free: shieldFx()
	if id == "glass":
		p.maxLives = 1; p.lives = 1
	refreshStats()
	checkEvolutions()


func choosePerk(id: String) -> void:
	if state != "perk": return
	var p := player
	grantPerk(id)
	A.play("perk")
	FX.glow_puff(p.x, p.y, "#3dffa2", 110 * G.S, 0.45)
	FX.sprite("fx_beam", 0, 0, {"follow": p, "oy": -p.w * 0.95, "w0": p.w * 1.2, "w1": p.w * 1.35, "dur": 0.85, "hold": 0.45, "fadeIn": 0.1})
	FX.ring(p.x, p.y, p.w * 0.4, p.w * 1.5, "#3dffa2", 0.45, 4)
	p.inv = maxf(p.inv, 0.8)
	state = "play"
	offerKind = ""
	hudDirty = true


# ════════════════════════════════════════════════════════════
# ВОЛНЫ
# ════════════════════════════════════════════════════════════
## 4.2: аномалия сектора — бросаем на первой волне сектора (со второго), на волне босса она гаснет
func rollAnomaly(n: int, isBoss: bool) -> void:
	var was = run.anomaly
	var A0: Dictionary = D.ANOMALY
	if isBoss:
		run.anomaly = null
	elif (n - 1) % 5 == 0:
		run.anomaly = null
		var sector := (n - 1) / 5
		if mode != "rush" and run.challenge == null and sector >= A0.from and U.random() < minf(A0.max, A0.chance + (sector - A0.from) * A0.step):
			var ids: Array = []
			for id in D.ANOMALIES: if id != run.lastAnomaly: ids.append(id)
			run.anomaly = ids[int(U.random() * ids.size())]
			run.lastAnomaly = run.anomaly
			run.anomalies += 1
			var aid: String = run.anomaly
			var def: Dictionary = D.ANOMALIES[aid]
			var r0 := run
			# после баннера волны, чтобы не налезать на него
			after(wave.intro + 0.6, func():
				if run != r0 or run.anomaly != aid: return
				A.play("skill", {"rate": 0.7})
				var pct := int(round(def.bonus * 100))
				if tipOnce(aid, {"kind": "АНОМАЛИЯ СЕКТОРА", "icon": "an_" + aid, "ico": def.ico, "title": def.name, "color": def.color,
					"note": "Действует до босса сектора. Кредитов и опыта +%d%%." % pct}): return
				Bus.emit("toast", {"ico": def.ico, "icon": "an_" + aid, "title": "АНОМАЛИЯ: " + def.name, "text": def.desc + " · награды +%d%%" % pct, "dur": 3800})
				hintOnce("anomaly", "ПОДСКАЗКА", "Аномалия меняет правила сектора до босса: сложнее, зато кредитов и опыта больше. Подробности — на паузе"))
	if run.anomaly != was: refreshStats()


func nextWave() -> void:
	# босс-раш: волны 5, 10, 15… — только боссы; выживание: боссов нет, волны идут без пауз
	var rush := mode == "rush"
	var surv := mode == "survival"
	var n: int = int(wave.n) + (5 if rush else 1) if wave else 1
	# 4.0: перед обычной волной — выбор узла на карте сектора (map.gd); после выбора снова сюда
	if mode == "normal" and RunMap.need(n):
		RunMap.offer(n)
		return
	var isBoss := n % 5 == 0 and not surv
	# 4.1: в выживании сундук за каждые 10 волн
	if surv and n > 1 and (n - 1) % 10 == 0 and player.alive: RunMap.giveChest("silver" if n > 25 else "bronze")
	var sector := (n - 1) / 5
	var tn: float = n + diff.waveOffset
	var budget: float = 0.0 if isBoss else (9 + tn * 4.4 + pow(tn, 1.28)) * diff.count
	wave = {"n": n, "boss": isBoss, "budget": budget, "spent": 0.0, "spawnT": 0.8, "intro": 1.2 if n == 1 else (0.0 if surv else 1.6),
		"done": false, "cleared": false, "clearT": 0.0, "miniDone": not (n % 5 == 3 and n >= 8), "startT": t, "danger": false, "chrono": false}
	run.waveDamage = 0
	# после прыжка (jumpScene) сектор уже сменён
	if sector != run.sector:
		run.sector = sector
		Bg.setSector(sectorIdx(sector))
		Bg.warp = 1.0
	rollAnomaly(n, isBoss)
	if anomaly("swarm"): wave.budget *= 1.3
	# баннер сектора — только если его карточку не показали в прыжке
	var newSector: bool = n > 1 and (n - 1) % 5 == 0 and run.get("cardSector", -1) != sector
	# Развилка: опасный путь — больше врагов и элиты, кредиты ×2
	if run.get("nextDanger", false):
		run.nextDanger = false
		wave.danger = true
		wave.budget *= D.DANGER.count
	RunMap.apply(wave)
	if relic("r_shieldgen") and player.alive and not player.shield:
		player.shield = true
		shieldFx()
	Bus.emit("waveStart", {"n": n, "boss": isBoss, "sector": sector, "sectorName": sectorDef(sector).name, "newSector": newSector, "danger": wave.danger})
	Events.roll(wave)
	Foes.onWave(wave)
	if run.challenge != null: M.challengeWave(run.challenge, n)
	if isBoss and state == "play":
		bossScene(n)
	elif isBoss:
		# игрок как раз погибает — без кат-сцены
		wave.intro = 3.2
		after(2.6, func(): B.spawnBoss(n))
		Bus.emit("bossWarning", bossDef(n / 5))
		FX.vignette("#ff2a48", 2.4, 0.75, true)
		A.play("warning")
	hudDirty = true


func updateWaves(dt: float) -> void:
	var w = wave
	if not w: return
	if w.intro > 0:
		w.intro -= dt
		return
	var alive := 0
	# астероиды сектора (def.prop) — часть обстановки, зачистку волны не задерживают
	for e in enemies: if e.alive and not e.leaving and not e.def.prop: alive += 1
	# волна босса завершается его уничтожением (onBossDefeated)
	if w.boss: return
	if not w.done:
		w.spawnT -= dt
		var tn := threatWave()
		# 3.1: на экране не больше ~16 врагов (на высоких сложностях чуть больше)
		var ck := sqrt(maxf(1.0, diff.count))
		var cap := minf(16 * ck, (6 + tn * 0.45) * ck)
		if w.spawnT <= 0 and alive < cap:
			U.with_rng(run.waveRng, func():
				var cost := E.spawnGroup(tn, w.budget - w.spent)
				w.spent += cost
				w.spawnT = maxf(0.42, 1.3 - tn * 0.035) * U.rand(0.75, 1.25) / pow(diff.count, 0.4)
				if not w.miniDone and w.spent > w.budget * 0.4:
					w.miniDone = true
					E.spawnMini(w.n)
				if w.spent >= w.budget: w.done = true)
		# выживание: следующая волна сразу, без зачистки и наград
		if w.done and mode == "survival":
			w.cleared = true
			nextWave()
			return
	elif alive == 0:
		w.clearT += dt
		if w.clearT > 0.9: waveCleared()


func waveCleared() -> void:
	var w: Dictionary = wave
	if w.cleared: return
	w.cleared = true
	var perfect: bool = run.waveDamage == 0
	var bonus := roundf(250 * w.n * diff.score * (2.0 if perfect else 1.0))
	addScore(bonus)
	if perfect and w.n >= 5: M.unlock("no_hit_level")
	if w.n >= 10 and perk("glass"): M.unlock("glass10")
	Events.finish()
	# собираем оставшиеся кредиты и кристаллы
	for it in pickups: if it.kind != "pu" and it.kind != "crate": it.pull = true
	Bus.emit("waveClear", {"n": w.n, "bonus": bonus, "perfect": perfect})
	# 4.1: после босса — трофейный сундук (откроется после забега), потом станция; после обычной волны — награда узла карты
	if w.boss:
		after(0.8, func(): if is_same(wave, w): RunMap.chestScene(RunMap.bossChest(), "ТРОФЕЙ БОССА", func(): offerModules("station")))
	else:
		after(1.2, func(): if is_same(wave, w) and not RunMap.reward(w): nextWave())


## события между волнами: Развилка и Торговец. true — событие показано, волна начнётся после выбора
var offer = null

func waveEvent(w: Dictionary) -> bool:
	var WE: Dictionary = D.WAVE_EVENTS
	if state != "play" or not player.alive or w.n < WE.from or w.n - run.get("lastWaveEvent", 0) < 2: return false
	var r: float = U.with_rng(run.waveRng, U.random)
	if r > WE.chance: return false
	# перед боссом развилки нет — только торговец
	var kind := "merchant" if (int(w.n) + 1) % 5 == 0 or r > WE.chance * WE.forkShare else "fork"
	run.lastWaveEvent = w.n
	offer = U.with_rng(run.waveRng, forkOffer if kind == "fork" else merchantOffer)
	state = "perk"
	offerKind = "event"
	pointer.id = -1
	A.play("skill", {"rate": 1.2})
	Bus.emit("eventOffer", offer)
	return true


func forkOffer() -> Dictionary:
	var d: Dictionary = D.DANGER
	return {"title": "РАЗВИЛКА", "sub": "Куда ведём следующую волну?", "cards": [
		{"id": "safe", "ico": "🛰️", "name": "ОБЫЧНЫЙ ПУТЬ", "desc": "Следующая волна как обычно", "rar": "common"},
		{"id": "danger", "ico": "☠️", "name": "ОПАСНЫЙ ПУТЬ", "desc": "Врагов +%d%%, элита чаще — но кредиты ×%s" % [int(round((d.count - 1) * 100)), str(d.coins)], "rar": "epic"},
	]}


func merchantOffer() -> Dictionary:
	# 4.2: скидка за эскорт — на одну лавку
	var disc: float = run.get("shopCut", 0.0) if run.get("shopCut", 0.0) else 1.0
	run.shopCut = 0.0
	var n: int = wave.n
	var p := player
	var cards: Array = []
	var cut := (0.7 if skill("sk_scavenger") else 1.0) * (0.75 if relic("r_chart") else 1.0) * disc
	var mods := moduleChoices()
	if mods.size():
		var m: Dictionary = mods[0]
		cards.append({"id": "mod:" + m.id, "icon": "md_" + m.id, "ico": m.ico, "name": m.name, "desc": "Модуль корабля: " + m.desc, "rar": m.rar, "price": roundf((250 + n * 20) * cut / 10) * 10})
	var perks: Array = []
	for x in D.PERKS:
		if not x.filler and x.rar != "common" and perk(x.id) < x.max and x.id != "glass": perks.append(x)
	var pk = U.pick(perks) if perks.size() else null
	if pk: cards.append({"id": "perk:" + pk.id, "icon": "pk_" + pk.id, "ico": pk.ico, "name": pk.name, "desc": "Улучшение: " + pk.desc, "rar": pk.rar, "price": roundf((150 + n * 12) * cut / 10) * 10})
	var epic: Array = []
	for x in D.PERKS:
		if x.rar == "epic" and perk(x.id) < x.max and x.id != "glass" and x.id != "maxhp" and (pk == null or x.id != pk.id): epic.append(x)
	var ep = U.pick(epic) if epic.size() and p.lives >= 2 else null
	if ep: cards.append({"id": "deal:" + ep.id, "ico": "🩸", "name": "СДЕЛКА: " + ep.name, "desc": "−1 жизнь, взамен: " + ep.desc, "rar": "legendary"})
	cards.append({"id": "pass", "ico": "👋", "name": "ПРОЙТИ МИМО", "desc": "Сберечь кредиты", "rar": "common"})
	return {"title": "ТОРГОВЕЦ", "art": "p_merchant", "sub": ("Скидка за эскорт −%d%% · кредиты из кошелька" % int(round((1 - disc) * 100))) if disc < 1 else "Цены в кредитах — кредиты уходят из кошелька", "cards": cards, "cut": cut}


func pickOffer(id: String) -> bool:
	if state != "perk" or offerKind != "event": return false
	var of: Dictionary = offer
	var card = null
	for c in of.cards:
		if c.id == id: card = c
	if card == null: return false
	if card.get("price", 0) and not M.spend(int(card.price)):
		A.play("error")
		return false
	var parts := id.split(":")
	var k := parts[0]
	var v := parts[1] if parts.size() > 1 else ""
	if k == "danger": run.nextDanger = true
	if k == "mod":
		offerKind = "module-buy"
		state = "perk"
		chooseModule(v)
	if k == "perk":
		grantPerk(v, true)
		A.play("perk")
	if k == "chest": RunMap.giveChest(v)
	if k == "ev": RunMap.resolve(v, parts[2] if parts.size() > 2 else "")
	if k == "deal":
		var p := player
		p.lives = maxi(1, p.lives - 1)
		grantPerk(v, true)
		FX.flash("#ff3d5a", 0.35)
		A.play("playerHit", {"vol": 0.6})
		Bus.emit("playerHit")
	if card.get("price", 0): hudDirty = true
	offer = null
	offerKind = ""
	state = "play"
	player.inv = maxf(player.inv, 0.8)
	# 4.1: торговец прощается и улетает, пока начинается волна
	if of.get("art", "") == "p_merchant": Scenes.leave("merchant", bool(card.get("price", 0)) or k == "deal")
	var wait := 1.5 if of.get("art", "") == "p_merchant" else 0.4
	if of.get("after", "") == "station": after(wait, func(): offerModules("station"))
	else: after(wait, nextWave)
	return true


## уничтожение босса (из bosses.gd)
func onBossDefeated(bs: En) -> void:
	var S := G.S
	run.bosses += 1
	run.bossIds.append(bs.bdef.id)
	M.onBoss(bs.bdef.id)
	if not run.bossDamaged: M.unlock("no_damage_boss")
	var pts := roundf(6000 * (wave.n / 5.0) * diff.score)
	addScore(pts)
	dropCoins(bs.x, bs.y, int(round((60 + wave.n * 8) * st.coins * diff.count * D.ECON.boss)))
	dropXp(bs.x, bs.y, 18 + wave.n)
	dropPowerup(bs.x - 30 * S, bs.y, "heal")
	dropPowerup(bs.x + 30 * S, bs.y)
	# реликвия «Сердце звезды»: +1 к максимуму жизней и +1 жизнь (со «Стеклянной пушкой» — только лечение)
	if relic("r_starheart") and player.alive:
		if not perk("glass"): player.maxLives += 1
		heal(1, "🌟 СЕРДЦЕ ЗВЕЗДЫ")
	# Godot: замедление и наезд камеры на гибнущего босса
	slowT = 1.5
	camFocus(bs.x, bs.y, 1.22, 1.1)
	for b in ebullets: b.dead = true
	Bus.emit("bossDefeated", {"def": bs.bdef, "pts": pts})
	after(2.2, func():
		for it in pickups: it.pull = true
		waveCleared())


# ════════════════════════════════════════════════════════════
# КАТ-СЦЕНЫ: выход босса и прыжок в следующий сектор
#  Затемнение и полосы кино поверх боя, карточка с крупным именем.
#  Корабль ведёт сцена: игрок им не управляет, он неуязвим и не стреляет; касание — пропуск.
# ════════════════════════════════════════════════════════════
func ease3(q: float) -> float:
	return 1.0 - pow(1.0 - U.clamp(q, 0, 1), 3)


## выход босса: полная сцена — при первой встрече, дальше короткая
func bossScene(n: int) -> void:
	var def := bossDef(n / 5)
	var seen: Array = M.s.get_or_add("bossSeen", [])
	var full: bool = not def.id in seen
	if full:
		seen.append(def.id)
		M.soon()
	var sc := {"spawnT": 0.9, "cardT": 2.4, "end": 4.4} if full else {"spawnT": 0.1, "cardT": 0.5, "end": 1.8}
	sc.merge({"kind": "boss", "n": n, "def": def, "full": full, "color": def.color, "spawned": false})
	startScene(sc)
	A.play("warning")


## прыжок после босса: звёзды из заставки, вспышка, новый фон и карточка сектора
func jumpScene() -> void:
	if state != "play":
		nextWave()
		return
	var sector: int = int(wave.n) / 5
	var sec := sectorDef(sector)
	startScene({"kind": "jump", "sector": sector, "sec": sec, "color": sec.neb[0], "flashT": 1.45, "cardT": 1.75, "end": 3.4, "warp": 0.0, "flashed": false, "stars": Intro.warpStars(150)})
	A.play("skill", {"rate": 0.6})


## срежиссированный момент: снаряды в полёте гаснут, корабль ведёт сцена (updateScene)
func startScene(sc: Dictionary) -> void:
	sc.merge({"t": 0.0, "out": -1.0, "card": null}, true)
	scene = sc
	state = "cutscene"
	for b in ebullets: b.dead = true
	for b in bullets: b.dead = true
	# астероиды сектора не лезут в кадр: тают за полсекунды (updateScene), без добычи
	for e in enemies:
		if e.alive and e.def.prop:
			e.hittable = false
			e.s("fading", true)
	A.muffle(true)
	Bus.emit("cinema", true)


func updateScene(dt: float) -> void:
	var sc: Dictionary = scene
	for e in enemies:
		if e.g("fading", false) and e.alive:
			e.alpha -= dt * 2.5
			if e.alpha <= 0: e.alive = false
	# сцена закончилась — полосы ещё уезжают
	if sc.out >= 0:
		sc.out += dt
		if sc.out > 0.45: scene = null
		return
	sc.t += dt
	# корабль выходит в центр; в прыжке на разгоне подаётся вперёд, после вспышки возвращается
	var p := player
	var ox := p.x
	p.x = U.damp(p.x, G.FW / 2, 2.6, dt)
	p.y = U.damp(p.y, G.H * (0.72 - 0.1 * sc.warp if sc.kind == "jump" else 0.76), 2.6, dt)
	p.vxs += p.x - ox
	if sc.kind == "boss":
		if not sc.spawned and sc.t >= sc.spawnT:
			sc.spawned = true
			B.spawnBoss(sc.n)
		if sc.card == null and sc.t >= sc.cardT: bossCard()
	elif sc.kind == "visit":
		RunMap.updateVisit(sc)
	else:
		# разгон до вспышки, после неё торможение
		sc.warp = ease3((sc.t - 0.25) / (sc.flashT - 0.25)) if sc.t < sc.flashT else maxf(0, 1 - (sc.t - sc.flashT) * 0.9)
		Intro.warpStep(sc.stars, dt, sc.warp)
		if not sc.flashed and sc.t >= sc.flashT: jumpFlash()
		if sc.card == null and sc.t >= sc.cardT: sectorCard()
	if sc.t >= sc.end: endScene()


func bossCard() -> void:
	var sc: Dictionary = scene
	var def: Dictionary = sc.def
	sc.card = {"cap": "НОВЫЙ БОСС" if sc.full else "БОСС", "name": def.name, "sub": def.title, "at": sc.t, "y": 0.6}
	A.play("bossRoar")
	FX.shake(0.6 if sc.full else 0.4)
	Haptic.warning()


## на пике прыжка: под вспышкой меняется сектор, всё от прошлого (астероиды) остаётся позади
func jumpFlash() -> void:
	var sc: Dictionary = scene
	sc.flashed = true
	run.sector = sc.sector
	Bg.setSector(sectorIdx(sc.sector), true)
	Bg.warp = 0.7
	for e in enemies: if not e.boss: e.alive = false
	FX.flash("#dcecff", 0.7)
	A.play("teleport")


func sectorCard() -> void:
	var sc: Dictionary = scene
	sc.card = {"cap": "СЕКТОР %d" % (sc.sector + 1), "name": sc.sec.name, "sub": sc.sec.desc, "at": sc.t, "y": 0.42}
	# карточку видели — баннер сектора на старте волны не нужен (nextWave)
	run.cardSector = sc.sector


func endScene() -> void:
	var sc = scene
	if sc == null or state != "cutscene": return
	sc.out = 0.0
	state = "play"
	player.inv = maxf(player.inv, 0.5)
	A.muffle(false)
	Bus.emit("cinema", false)
	hudDirty = true
	if sc.kind == "jump": nextWave()
	# сцена узла карты: дальше — окно награды или следующая волна
	if sc.kind == "visit" and sc.get("onEnd"):
		var f: Callable = sc.onEnd
		sc.onEnd = null
		f.call()


func skipScene() -> void:
	var sc = scene
	if sc == null or state != "cutscene": return
	if sc.kind == "boss":
		if not sc.spawned:
			sc.spawned = true
			B.spawnBoss(sc.n)
		# имя ещё не показали — покажем обычным предупреждением поверх боя
		if sc.card == null:
			A.play("bossRoar")
			Bus.emit("bossWarning", sc.def)
		# босс сразу встаёт на место, дальше обычный выход (bosses.gd)
		if boss and boss.entering: boss.y = boss.baseY
	elif sc.kind == "jump":
		if not sc.flashed: jumpFlash()
		sc.warp = 0.0
	endScene()


## 0..1: полосы выезжают за 0,45 с и уезжают за 0,45 с после конца
func sceneK(sc: Dictionary) -> float:
	return 1.0 - ease3(sc.out / 0.45) if sc.out >= 0 else ease3(sc.t / 0.45)


## затемнение фона под боем; в прыжке гуще, и поверх него летят звёзды
func drawSceneDim(ctx: Ctx) -> void:
	var sc: Dictionary = scene
	var k := sceneK(sc) * (0.7 if sc.kind == "visit" else 1.0)
	if k <= 0: return
	var warp: float = sc.warp if sc.kind == "jump" else 0.0
	ctx.alpha = minf(0.92, 0.5 * k + 0.42 * warp)
	ctx.fill = Color.BLACK
	ctx.fill_rect(0, 0, G.W, G.H)
	ctx.alpha = 1.0
	if warp > 0.01: Intro.warpDraw(ctx, sc.stars, warp, G.FX + G.FW / 2, G.H * 0.42, maxf(G.W, G.H) * 0.7, minf(1.0, warp * 1.6))


## полосы кино и карточка
func drawScene(ctx: Ctx) -> void:
	var sc: Dictionary = scene
	var k := sceneK(sc)
	if k <= 0: return
	var W := G.W
	var H := G.H
	var S := G.S
	var bh := roundf(H * 0.11 * k)
	ctx.fill = Color.BLACK
	ctx.fill_rect(0, 0, W, bh)
	ctx.fill_rect(0, H - bh, W, bh)
	ctx.fill = U.col(sc.color, 0.55 * k)
	ctx.fill_rect(0, bh, W, 1)
	ctx.fill_rect(0, H - bh - 1, W, 1)
	var cd = sc.card
	if cd == null: return
	var lt: float = sc.t - cd.at
	var a := minf(1.0, lt / 0.25) * k
	if a <= 0: return
	var cx := G.FX + G.FW / 2
	var cy: float = H * cd.y
	var name: String = cd.name
	var size := roundf(minf(32 * S, G.FW * 0.92 / (name.length() * 0.82)))
	var grow := 1 + 0.12 * (1 - minf(1.0, lt / 0.35))
	# линия под именем раскрывается от центра
	var lw := G.FW * 0.36 * minf(1.0, lt / 0.4)
	ctx.alpha = a
	ctx.fill = U.col(sc.color)
	ctx.fill_text(cd.cap, cx, cy - size * 0.95 + 5 * S, int(round(11 * S)), 1)
	ctx.fill_rect(cx - lw, cy + size * 0.62, lw * 2, maxf(1, 2 * S))
	ctx.additive = true
	ctx.alpha = a * 0.5
	ctx.draw_tex(G.soft(sc.color, 64), cx - G.FW * 0.4, cy - size, G.FW * 0.8, size * 1.6)
	ctx.additive = false
	ctx.alpha = a
	ctx.fill = Color.WHITE
	ctx.fill_text(name, cx, cy + size * grow * 0.35, int(round(size * grow)), 1, 6, Color(0, 0, 0, 0.6))
	if cd.sub != "":
		ctx.fill = Color(1, 1, 1, 0.78)
		ctx.fill_text(cd.sub, cx, cy + size * 0.62 + 23 * S, int(round(15 * S)), 1)
	ctx.alpha = 1.0


# ════════════════════════════════════════════════════════════
# УБОРКА
# ════════════════════════════════════════════════════════════
func cleanup() -> void:
	bullets = bullets.filter(func(b): return not b.dead)
	ebullets = ebullets.filter(func(b): return not b.dead)
	pickups = pickups.filter(func(it): return not it.dead)
	enemies = enemies.filter(func(e): return e.alive)


# ════════════════════════════════════════════════════════════
# КОРАБЛЬ ИГРОКА: облик, пламя, детали модулей
# ════════════════════════════════════════════════════════════
var _flameCache := {}
var _looks: Array = []


## пламя сопла: капля с градиентом от белого к цвету следа
func flameSprite(colors: Array) -> Texture2D:
	var key := ",".join(colors)
	if _flameCache.has(key): return _flameCache[key]
	var w := 24
	var h := 72
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var c0 := U.col(colors[0])
	var c1 := U.col(colors[1])
	var c2 := U.col(colors[2])
	for y in h:
		var k := float(y) / h
		var col := c0.lerp(c1, k / 0.18) if k < 0.18 else (c1.lerp(U.col(colors[2], 0.7), (k - 0.18) / 0.37) if k < 0.55 else U.col(colors[2], 0.7).lerp(U.col(colors[2], 0.0), (k - 0.55) / 0.45))
		# ширина капли: у сопла почти полная, к хвосту сходится в точку
		var half := (0.38 * (1.0 - pow(k, 1.6)) + 0.02) * w
		for x in w:
			var dx := absf(x + 0.5 - w / 2.0)
			if dx <= half:
				var edge := clampf((half - dx) / 2.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * edge))
	var tex := ImageTexture.create_from_image(img)
	_flameCache[key] = tex
	return tex


func trailColors(id: String) -> Array:
	var tr: Dictionary = D.TRAILS[0]
	for x in D.TRAILS: if x.id == id: tr = x
	if not tr.colors is String: return tr.colors
	var h := int(Time.get_ticks_msec() / 120.0) % 12 * 30
	return ["#ffffff", "#" + Color.from_hsv(h / 360.0, 0.6, 1.0).to_html(false), "#" + Color.from_hsv(fmod(h + 40, 360) / 360.0, 1.0, 1.0).to_html(false)]


## спрайт корабля игрока с учётом раскраски
func shipCanvas(model: String, skinId: String) -> Texture2D:
	var sk: Dictionary = D.SKINS[0]
	for k in D.SKINS: if k.id == skinId: sk = k
	var sprite: String = D.SHIPS[model].sprite
	if sk.get("hue") is String and sk.hue == "rainbow":
		return G.tinted(sprite, {"hue": int(Time.get_ticks_msec() / 150.0) % 12 * 30})
	return G.tinted(sprite, sk)


## облик корабля: нарисованный цветной вариант или перекраска
func shipLook(model: String, skinId: String, preview := false) -> Dictionary:
	var variant: String = D.SHIP_VARIANTS.get(model, {}).get(skinId, "")
	if variant != "": return {"sprite": variant, "cv": null}
	var sprite: String = D.SHIPS[model].sprite
	var sk: Dictionary = D.SKINS[0]
	for k in D.SKINS: if k.id == skinId: sk = k
	if preview and sk.get("hue") is String and sk.hue == "rainbow": return {"sprite": sprite, "cv": G.tinted(sprite, {"hue": 300})}
	return {"sprite": sprite, "cv": shipCanvas(model, skinId)}


func drawLook(model: String, skin: String, trail: String) -> Dictionary:
	var now := Time.get_ticks_msec()
	var sk = null
	for k in D.SKINS: if k.id == skin: sk = k
	var tr = null
	for k in D.TRAILS: if k.id == trail: tr = k
	var ss := int(now / 150.0) % 12 if sk and sk.get("hue") is String and sk.hue == "rainbow" else 0
	var ts := int(now / 120.0) % 12 if tr and tr.colors is String else 0
	for L in _looks:
		if L.model == model and L.skin == skin and L.trail == trail and L.ss == ss and L.ts == ts: return L
	var variant: String = D.SHIP_VARIANTS.get(model, {}).get(skin, "")
	var sprite: String = variant if variant != "" else D.SHIPS[model].sprite
	var cols := trailColors(trail)
	var L := {"model": model, "skin": skin, "trail": trail, "ss": ss, "ts": ts, "sprite": sprite, "f": G.frame(sprite),
		"cv": null if variant != "" else shipCanvas(model, skin), "flame": flameSprite(cols), "glowCol": cols[1],
		"noz": G.nozzles.get(sprite, [[0.5, 1, 1]]), "tfx": tr.fx if tr and tr.get("fx", "") != "" else "", "spin": tr != null and tr.get("spin", false)}
	# шлейф рисуем только из главных сопел, чтобы у кораблей с 3–4 соплами не было каши
	if L.tfx != "":
		var big := 0.0
		for n in L.noz: big = maxf(big, n[2])
		L.tnoz = L.noz.filter(func(n): return n[2] >= big * 0.75)
	if L.f.is_empty(): return L
	_looks.append(L)
	if _looks.size() > 8: _looks.pop_front()
	return L


## детали модулей на корабле: [спрайт, x, y (доли ширины/высоты), ширина (доля), слой: 0 — под корпусом, 1 — поверх]
func shipParts(mods: Dictionary) -> Array:
	var out: Array = []
	var m := func(id): return int(mods.get(id, 0))
	var pair := func(l: String, r: String, x: float, y: float, w: float, layer: int):
		out.append([l, -x, y, w, layer])
		out.append([r, x, y, w, layer])
	# крылья — одни на корабль: с пушками, тяжёлые (бронеплиты ×2) или лёгкие (гироскоп)
	var wing := "gun" if m.call("wings") else ("heavy" if m.call("plating") >= 2 else ("light" if m.call("gyro") else ""))
	if wing != "": pair.call("sp_wing_" + wing + "_l", "sp_wing_" + wing + "_r", 0.4, 0.18, 0.42, 0)
	if m.call("gyro"): pair.call("sp_eng", "sp_eng", 0.22, 0.44, 0.13, 0)
	if m.call("chrono"): out.append(["sp_warp", 0, 0.46, 0.2, 0])
	if m.call("hunter"): out.append(["sp_gun_plasma", 0, -0.44, 0.12, 0])
	if m.call("salvage"): out.append(["sp_hook", 0, 0.58, 0.1, 0])
	if m.call("power"):
		var g := "sp_gun_minigun" if m.call("power") >= 2 else "sp_gun_lancer"
		pair.call(g, g, 0.24, -0.14, 0.1, 1)
	if m.call("bombbay"): pair.call("sp_gun_rockets", "sp_gun_rockets", 0.32, 0.12, 0.1, 1)
	if m.call("cooling"): pair.call("sp_heatsink", "sp_heatsink", 0.13, 0.3, 0.1, 1)
	if m.call("plating"): out.append(["sp_arm_nose", 0, -0.28, 0.16, 1])
	if m.call("plating") >= 2: pair.call("sp_arm_plate_l", "sp_arm_plate_r", 0.16, 0.05, 0.13, 1)
	if m.call("targeting"): out.append(["sp_arm_sensor", 0, -0.06, 0.14, 1])
	if m.call("shieldcore"): out.append(["sp_arm_core", 0, 0.14, 0.17, 1])
	if m.call("scanner"): out.append(["sp_radar", 0.2, 0.3, 0.11, 1])
	if m.call("emergency"): out.append(["sp_arm_emblem", 0, 0.32, 0.13, 1])
	return out


func drawParts(ctx: Ctx, parts: Array, layer: int, w: float, h: float) -> void:
	for p in parts:
		if p[4] != layer: continue
		var f := G.frame(p[0])
		if f.is_empty(): continue
		var pw: float = w * p[3]
		var ph: float = pw * f[3] / f[2]
		ctx.save()
		ctx.translate(p[1] * w, p[2] * h)
		if p[1] > 0 and not String(p[0]).ends_with("_r"): ctx.scale(-1, 1)
		ctx.draw_image(G.src(f), f[0], f[1], f[2], f[3], -pw / 2, -ph / 2, pw, ph)
		ctx.restore()


## корабль с пламенем: (x, y) — центр, w — ширина; parts — детали модулей (только в забеге)
func drawShip(ctx: Ctx, model: String, skin: String, trail: String, x: float, y: float, w: float, tilt: float, tt: float, boost := 1.0, parts = null) -> void:
	var L := drawLook(model, skin, trail)
	var f: Array = L.f
	if f.is_empty(): return
	var h: float = w * f[3] / f[2]
	var flame: Texture2D = L.flame
	ctx.save()
	ctx.translate(x, y)
	if tilt != 0.0: ctx.rotate(tilt)
	# пламя
	ctx.additive = true
	for n in L.noz:
		var nx: float = (n[0] - 0.5) * w
		var ny: float = (n[1] - 0.5) * h
		var fl: float = (0.75 + 0.25 * sin(tt * 38 + n[0] * 9) + U.random() * 0.12) * boost
		var fw: float = w * 0.2 * n[2]
		var fh: float = w * 0.62 * n[2] * fl
		ctx.alpha = 0.95
		ctx.draw_tex(flame, nx - fw / 2, ny - fh * 0.06, fw, fh)
		ctx.alpha = 0.5
		var gs := fw * 2.6
		ctx.draw_tex(G.glow(L.glowCol, 64), nx - gs / 2, ny - gs * 0.35, gs, gs)
	if L.tfx != "":
		var tf := G.frame(L.tfx)
		for n in L.tnoz:
			var nx: float = (n[0] - 0.5) * w
			var ny: float = (n[1] - 0.5) * h
			var k: float = n[2] * boost
			if L.spin:
				# спираль крутится прямо за соплом
				var sz := w * 0.5 * k
				ctx.save(); ctx.translate(nx, ny + sz * 0.42); ctx.rotate(tt * 5); ctx.scale(1, 0.72)
				ctx.alpha = 0.85
				ctx.draw_image(G.src(tf), tf[0], tf[1], tf[2], tf[3], -sz / 2, -sz / 2 * tf[3] / tf[2], sz, sz * tf[3] / tf[2])
				ctx.restore()
			else:
				var tw := w * 0.36 * k
				var th: float = tw * tf[3] / tf[2] * (0.9 + 0.1 * sin(tt * 30 + n[0] * 7))
				ctx.alpha = 0.9
				ctx.draw_image(G.src(tf), tf[0], tf[1], tf[2], tf[3], nx - tw / 2, ny - th * 0.04, tw, th)
	ctx.alpha = 1.0
	ctx.additive = false
	if parts: drawParts(ctx, parts, 0, w, h)
	if L.cv: ctx.draw_tex(L.cv, -w / 2, -h / 2, w, h)
	else: ctx.draw_image(G.src(f), f[0], f[1], f[2], f[3], -w / 2, -h / 2, w, h)
	if parts: drawParts(ctx, parts, 1, w, h)
	ctx.restore()


# ════════════════════════════════════════════════════════════
# ОТРИСОВКА МИРА
# ════════════════════════════════════════════════════════════
var _beamCache := {}


func draw(ctx: Ctx) -> void:
	var W := G.W
	var H := G.H
	Bg.draw(ctx, Main.quality)
	if state == "idle":
		drawAttract(ctx)
		FX.draw_front(ctx)
		return
	if player == null: return
	if scene != null: drawSceneDim(ctx)
	ctx.save()
	ctx.translate(G.FX + FX.shake_x, FX.shake_y)
	if cam.z > 1.001:
		# наезд: точка фокуса стоит на месте, всё вокруг раздвигается (фон не увеличивается — даёт глубину)
		ctx.translate(cam.x, cam.y); ctx.scale(cam.z, cam.z); ctx.translate(-cam.x, -cam.y)
	FX.draw_back(ctx)
	drawPickups(ctx)
	Events.drawBack(ctx)
	Foes.drawBack(ctx)
	Skills.drawBack(ctx)
	RunMap.drawEscort(ctx)
	E.drawAll(ctx)
	Foes.drawFront(ctx)
	Events.drawMid(ctx)
	if darkK > 0.01: drawDark(ctx)
	drawBullets(ctx)
	drawPlayer(ctx)
	Skills.drawFront(ctx)
	drawEBullets(ctx)
	if scene != null and scene.kind == "visit": RunMap.drawVisit(ctx, scene)
	Scenes.drawActors(ctx)
	Events.draw(ctx)
	drawOverlays(ctx)
	FX.draw_front(ctx)
	Vfx.draw(ctx)
	FX.draw_texts(ctx)
	ctx.restore()
	# эффекты экрана
	if run.skillFx.get("sk_timewarp", 0.0) > 0 or buffs.get("freeze", 0.0) > 0:
		var frz: bool = buffs.get("freeze", 0.0) > 0
		ctx.fill = Color(0.47, 0.86, 1.0, 0.05) if frz else Color(0.24, 0.43, 1.0, 0.06)
		ctx.fill_rect(0, 0, W, H)
		ctx.additive = true
		ctx.alpha = (0.9 if frz else 0.7) + 0.1 * sin(t * 2.5)
		ctx.draw_tex(FX._vignette_tex("#8fe9ff" if frz else "#3d6bff"), 0, 0, W, H)
		ctx.alpha = 1.0
		ctx.additive = false
	if player.alive and player.lives == 1:
		# последняя жизнь: виньетка по краям бьётся как сердце — два толчка и пауза
		var ph := fmod(t * 1.1, 1.0)
		var beat := exp(-ph * 10) + (0.65 * exp(-(ph - 0.24) * 10) if ph > 0.24 else 0.0)
		ctx.additive = true
		ctx.alpha = minf(0.85, 0.25 + 0.55 * beat)
		ctx.draw_tex(FX._vignette_tex("#ff2a48"), 0, 0, W, H)
		ctx.alpha = 1.0
		ctx.additive = false
	FX.draw_screen(ctx, W, H)
	FX.draw_arcs(ctx, G.FX, G.FW, H)
	FX.draw_flash(ctx, W, H)
	# края поля на широких экранах
	if G.FX > 1:
		ctx.fill = Color(0.008, 0.012, 0.04, 0.55)
		ctx.fill_rect(0, 0, G.FX, H)
		ctx.fill_rect(G.FX + G.FW, 0, W - G.FX - G.FW, H)
		ctx.fill = Color(0.24, 0.88, 1.0, 0.18)
		ctx.fill_rect(G.FX - 1, 0, 1, H)
		ctx.fill_rect(G.FX + G.FW, 0, 1, H)
	if scene != null: drawScene(ctx)
	if scene != null and scene.kind == "jump":
		Post.warp = scene.warp
		Post.warp_at = Vector2(G.FW / 2, G.H * 0.42)


## меню: корабль игрока парит над логотипом
func drawAttract(ctx: Ctx) -> void:
	var s: Dictionary = M.s
	var S := G.S
	var at: float = attract.t
	var slot = attract.get("slot")
	if slot and slot.h < 44: return
	var sh: Dictionary = D.SHIPS.get(s.ship.model, D.SHIPS.ship1)
	var fr := G.frame(sh.sprite)
	var size: float = (U.clamp(slot.h * 0.66, 38, 92) if slot else 70 * minf(1.3, S * 1.1)) * (sh.scale if sh.scale else 1.0)
	if slot and fr.size(): size = minf(size, (slot.h / 2 + 10) / (float(fr[3]) / fr[2] / 2 + 0.5))
	var x := G.W / 2 + sin(at * 0.7) * 26 * S
	var y: float = (slot.y if slot else G.H * 0.36) + sin(at * 1.3) * 6 * S
	ctx.alpha = 0.95
	drawShip(ctx, s.ship.model, s.ship.skin, s.ship.trail, x, y, size, cos(at * 0.7) * 0.12, at, 1.1)
	ctx.alpha = 1.0


func drawPickups(ctx: Ctx) -> void:
	var S := G.S
	var coin := G.proc("coin")
	var xp := G.proc("xp")
	var xpBig := G.proc("xpBig")
	for it in pickups:
		if it.dead: continue
		match it.kind:
			"crate":
				var s := 40 * S * (1 + sin(it.age * 5) * 0.05)
				ctx.additive = true
				ctx.alpha = 0.45 + sin(it.age * 6) * 0.15
				ctx.draw_tex(G.glow("#ffc83d", 64), it.x - s, it.y - s, s * 2, s * 2)
				ctx.additive = false
				ctx.alpha = 0.5 + 0.5 * sin(it.age * 20) if it.age > 11 else 1.0
				if G.has("p_crate"): G.draw(ctx, "p_crate", it.x, it.y, s, sin(it.age * 2) * 0.12)
				else: ctx.draw_tex(coin, it.x - s / 3, it.y - s / 3, s / 1.5, s / 1.5)
			"coin":
				var s := (22.0 if it.val >= 25 else (17.0 if it.val >= 5 else 13.0)) * S
				var sx := absf(cos(it.spin)) * 0.8 + 0.2
				ctx.draw_tex(coin, it.x - s * sx / 2, it.y - s / 2, s * sx, s)
			"xp":
				var big := it.val >= 5
				var s := (18.0 if big else 12.0) * S
				ctx.additive = true
				ctx.alpha = 0.5
				ctx.draw_tex(G.glow("#5cc8ff" if big else "#3dffa2", 64), it.x - s, it.y - s, s * 2, s * 2)
				ctx.alpha = 1.0
				ctx.additive = false
				ctx.draw_tex(xpBig if big else xp, it.x - s / 2, it.y - s / 2, s, s)
			"en":
				# энергоблок: пульсирует, перед исчезновением мигает; цвет — обычный, с босса, двойной
				var s := 20 * S * (1 + sin(it.age * 7) * 0.08)
				var spr: String = EN_SPR.get(it.en, EN_SPR.std)
				var col: String = EN_COL.get(it.en, EN_COL.std)
				ctx.additive = true
				ctx.alpha = 0.5
				ctx.draw_tex(G.glow(col, 64), it.x - s * 1.1, it.y - s * 1.1, s * 2.2, s * 2.2)
				ctx.additive = false
				ctx.alpha = 0.5 + 0.5 * sin(it.age * 20) if it.age > 8 else 1.0
				if G.has(spr): G.draw(ctx, spr, it.x, it.y, s * (1.45 if it.val > 1 else 1.25))
				else: ctx.draw_tex(G.proc("energy"), it.x - s * 0.39, it.y - s / 2, s * 0.78, s)
			_:
				var def: Dictionary = D.POWERUPS[it.pu]
				var s := 34 * S * (1 + sin(it.age * 5) * 0.05)
				ctx.additive = true
				ctx.alpha = 0.55 + sin(it.age * 6) * 0.2
				ctx.draw_tex(G.glow(def.color, 64), it.x - s, it.y - s, s * 2, s * 2)
				ctx.alpha = 0.5 + 0.5 * sin(it.age * 20) if it.age > 11 else 1.0
				ctx.additive = false
				if def.get("sprite"): G.draw(ctx, def.sprite, it.x, it.y, s)
				else: Hud.drawBadge(ctx, def, it.x, it.y, s)
		ctx.alpha = 1.0


## полумесяц серпа по геометрии волны: внешняя дуга и внутренняя кривая, сходящиеся на концах
func crescent(ctx: Ctx, w: Dictionary, th: float) -> void:
	var a0: float = w.ang - w.span
	var a1: float = w.ang + w.span
	var Ro: float = w.R + th * 0.35
	var ax: float = w.cx + cos(a0) * Ro
	var ay: float = w.cy + sin(a0) * Ro
	var bx: float = w.cx + cos(a1) * Ro
	var by: float = w.cy + sin(a1) * Ro
	var mx: float = w.cx + cos(w.ang) * (w.R - th * 0.65)
	var my: float = w.cy + sin(w.ang) * (w.R - th * 0.65)
	ctx.begin_path()
	ctx.arc(w.cx, w.cy, Ro, a0, a1)
	ctx.quadratic_curve_to(2 * mx - (ax + bx) / 2, 2 * my - (ay + by) / 2, ax, ay)
	ctx.fill_path()


func drawBullets(ctx: Ctx) -> void:
	ctx.additive = true
	var trail: bool = G.has("fx_tr_rocket") and Main.quality > 0
	var vortex := G.has("fx_vortex")
	for b in bullets:
		if b.dead: continue
		var ang := atan2(b.vy, b.vx) + PI / 2
		if b.kind == "rocket":
			var f := G.frame(b.sprite)
			var h: float = b.w * f[3] / f[2] if f.size() else b.w * 2.3
			if f.size() and trail:
				# след: голова у сопла, хвост из искр уходит назад по курсу
				var va := ang - PI / 2
				var tw := b.w * 0.9
				var back := h * 0.35 + tw * 1.2
				ctx.alpha = 0.75
				G.draw(ctx, "fx_tr_rocket", b.x - cos(va) * back, b.y - sin(va) * back, tw, va + 1.262)
				ctx.alpha = 1.0
			ctx.additive = false
			G.draw(ctx, b.sprite, b.x, b.y, b.w, ang)
			ctx.additive = true
			var gs := b.w * 1.7
			ctx.alpha = 0.75
			ctx.draw_tex(G.glow("#ff9f3d", 64), b.x - sin(ang) * h * 0.5 - gs / 2, b.y + cos(ang) * h * 0.5 - gs / 2, gs, gs)
			ctx.alpha = 1.0
		elif b.kind == "dark":
			var s := b.r * 0.42 * (1 + sin(b.age * 12) * 0.06)
			if vortex:
				G.draw(ctx, "fx_vortex", b.x, b.y, s * 2.7, b.rot)
				ctx.additive = false
				ctx.draw_tex(G.proc("voidcore"), b.x - s * 0.5, b.y - s * 0.5, s, s)
				ctx.additive = true
				Post.lens(b.x, b.y, s * 0.9, 0.5)
			ctx.alpha = 0.16
			ctx.draw_tex(G.soft("#7a3dff", 64), b.x - b.r, b.y - b.r, b.r * 2, b.r * 2)
			ctx.alpha = 0.28
			ctx.stroke = U.col("#c9a0ff"); ctx.line_width = 1.5
			ctx.begin_path(); ctx.arc(b.x, b.y, b.r, b.rot * 0.3, b.rot * 0.3 + TAU * 0.75); ctx.stroke_path()
			ctx.alpha = 1.0
		elif b.kind == "wave":
			# серп: мягкий ореол, неоновое тело, белая кромка; заряженная волна белее, к концу полёта гаснет
			var w := waveGeom(b)
			var fade := minf(1.0, b.life / 0.15)
			for pass_ in [["#3dc8ff", 0.16 + 0.08 * b.ch, 3.2], ["#7ff6ff", 0.55, 1.5], ["#ffffff" if b.ch > 0.66 else "#e8ffff", 0.95, 0.6]]:
				ctx.alpha = pass_[1] * fade
				ctx.fill = U.col(pass_[0])
				crescent(ctx, w, b.r * pass_[2])
			ctx.alpha = 1.0
		elif b.cv or b.sprite != "":
			# отскочившие от верха снаряды тают
			if b.fade != 0.0: ctx.alpha = U.clamp(b.life / b.fade, 0, 1) * 0.85
			if b.cv: G.draw_canvas(ctx, b.cv, b.x, b.y, b.w * (0.7 + 0.5 * plasmaGrow(b)) if b.wid == "plasma" else b.w, b.age * 4 if b.kind == "plasma" else 0.0)
			else: G.draw(ctx, b.sprite, b.x, b.y, b.w, ang)
			ctx.alpha = 1.0
	ctx.additive = false


## шкала ресурса: магазин — деления по числу выстрелов, остальное — заполнение снизу вверх
func drawWeaponRes(ctx: Ctx, p: Pl, res: Dictionary) -> void:
	var S := G.S
	var w := 3.5 * S
	var h := p.w * 0.6
	var x := p.x - p.w * 0.66 - w / 2
	var y := p.y - h * 0.4
	var col: String = D.WEAPONS[p.weapon].color
	var empty: bool = res.kind == "energy" and res.k <= 0
	if res.kind == "charge":
		# заряд серпа — кольцо вокруг корабля: длина и яркость по заряду
		var R := p.w * 0.66
		var a0 := -PI / 2
		ctx.additive = true
		ctx.alpha = 0.25 + 0.55 * res.k
		ctx.stroke = U.col("#e8ffff" if res.k > 0.66 else col)
		ctx.line_width = (1.5 + 1.5 * res.k) * S
		ctx.begin_path(); ctx.arc(p.x, p.y, R, a0 - PI * res.k, a0 + PI * res.k); ctx.stroke_path()
		ctx.alpha = 1.0
		ctx.additive = false
		return
	ctx.fill = Color(0, 0, 0, 0.55)
	ctx.fill_rect(x - 1, y - 1, w + 2, h + 2)
	if res.kind == "mag":
		var gap := 2 * S
		var sh: float = (h - gap * (res.max - 1)) / res.max
		ctx.fill = U.col(col)
		for i in int(res.n): ctx.fill_rect(x, y + h - (i + 1) * sh - i * gap, w, sh)
	elif empty:
		# энергия кончилась — мигающая красная рамка
		ctx.alpha = 0.5 + 0.5 * sin(t * 12)
		ctx.stroke = U.col("#ff4d5e"); ctx.line_width = 1.5 * S
		ctx.begin_path(); ctx.rect(x, y, w, h); ctx.stroke_path()
		ctx.alpha = 1.0
	else:
		ctx.alpha = 0.5 if res.kind == "reload" else 1.0
		ctx.fill = Color.WHITE if res.kind == "focus" else U.col(col)
		ctx.fill_rect(x, y + h * (1 - res.k), w, h * res.k)
		ctx.alpha = 1.0


func drawPlayer(ctx: Ctx) -> void:
	var p := player
	var s: Dictionary = M.s
	var S := G.S
	# дроны
	Comp.draw(ctx)
	for i in drones.size():
		var d: Dictionary = drones[i]
		var name := "c_gold" if i else "c_white"
		var f := G.frame(name)
		if f.is_empty(): continue
		var w := 24 * S
		var h: float = w * f[3] / f[2]
		ctx.additive = true
		ctx.alpha = 0.7 + U.random() * 0.3
		# пламя развёрнуто вниз: основание у сопла, язык уходит назад
		var fw := 9 * S
		var fy: float = d.y + h * 0.5 + fw * 0.9
		if i: G.draw_canvas(ctx, G.tinted("fx_tr_engine", {"hue": 45}), d.x, fy, fw, PI)
		else: G.draw(ctx, "fx_tr_engine", d.x, fy, fw, PI)
		ctx.alpha = 1.0
		ctx.additive = false
		ctx.draw_image(G.src(f), f[0], f[1], f[2], f[3], d.x - w / 2, d.y - h / 2, w, h)
	if not p.alive: return
	var blink: bool = p.inv > 0 and state == "play" and int(floor(p.inv * 14)) % 2 == 0
	ctx.alpha = 0.35 if blink else 1.0
	# в прыжке между секторами двигатели на форсаже
	var boost: float = (1.3 if buffs.get("rapid", 0.0) > 0 or run.skillFx.get("sk_overclock", 0.0) > 0 else 1.0) + (scene.warp * 1.5 if scene != null and scene.kind == "jump" else 0.0)
	# след двигателя на частицах Godot — под кораблём, остаётся в пространстве
	Vfx.wake(ctx, p.x, p.y + p.w * 0.42, p.w, drawLook(s.ship.model, s.ship.skin, s.ship.trail).glowCol, boost)
	drawShip(ctx, s.ship.model, s.ship.skin, s.ship.trail, p.x, p.y, p.w, p.tilt, t, boost, run.get("parts"))
	ctx.alpha = 1.0
	# ресурс текущего оружия — вертикальная шкала слева от корабля
	var res = weaponRes(p.weapon) if state == "play" and p.alive else null
	if res: drawWeaponRes(ctx, p, res)
	# щит
	var barrier: bool = run.skillFx.get("sk_barrier", 0.0) > 0
	if p.shield or barrier:
		var col := "#ffd23d" if barrier else "#7fe7ff"
		var r := p.w * 0.78
		ctx.additive = true
		ctx.alpha = 0.18 + sin(t * 6) * 0.05
		ctx.draw_tex(G.soft(col, 64), p.x - r * 1.2, p.y - r * 1.2, r * 2.4, r * 2.4)
		var bw := r * 2.25 * (1 + sin(t * 4) * 0.025)
		# Godot: стеклянный пузырь — преломление и светящаяся кромка (постобработка)
		Post.bubble(p.x, p.y, r * 1.1, 1.0, U.col(col), run.get("shieldFxT", 0.0))
		ctx.alpha = 0.4 + sin(t * 6) * 0.08
		if barrier: G.draw_canvas(ctx, G.tinted("fx_sh_bubble", {"hue": 46}), p.x, p.y, bw)
		else: G.draw(ctx, "fx_sh_bubble", p.x, p.y, bw)
		# полное тонкое кольцо и бегущий по нему блик
		ctx.stroke = U.col(col); ctx.line_width = 1.5 * S
		ctx.alpha = 0.45
		ctx.begin_path(); ctx.arc(p.x, p.y, r, 0, TAU); ctx.stroke_path()
		ctx.alpha = 0.9; ctx.line_width = 2.2 * S
		ctx.begin_path(); ctx.arc(p.x, p.y, r, t * 2.5, t * 2.5 + TAU * 0.22); ctx.stroke_path()
		ctx.alpha = 1.0
		ctx.additive = false
	# прицел снайпера на корабле: держится пару секунд после наводки, перед выстрелом сжимается и мигает
	if p.lockT > 0:
		var hot := p.lockHot > 0
		var fade := minf(1.0, p.lockT / 0.4)
		ctx.additive = true
		ctx.alpha = fade * ((0.85 + 0.15 * sin(t * 40)) if hot else (0.75 + 0.2 * sin(t * 6)))
		G.draw(ctx, "fx_lock", p.x, p.y, p.w * (1.05 if hot else 1.35 + 0.05 * sin(t * 4)), t * (4.0 if hot else 1.2))
		if hot: G.draw(ctx, "fx_lock", p.x, p.y, p.w * 1.05, t * 4)
		ctx.alpha = 1.0
		ctx.additive = false
	# точка хитбокса (видна при опасности — помогает уклоняться)
	if ebullets.size() > 6 or p.lives == 1 or pointer.id != -1:
		ctx.additive = true
		ctx.alpha = 0.85
		ctx.draw_tex(G.glow("#ff5c7a", 32), p.x - 7 * S, p.y - 7 * S, 14 * S, 14 * S)
		ctx.alpha = 1.0
		ctx.additive = false


func drawEBullets(ctx: Ctx) -> void:
	ctx.additive = true
	for b in ebullets:
		if b.dead: continue
		if b.type == "mine":
			ctx.additive = false
			var s := b.w
			if b.sprite != "" and G.has(b.sprite):
				ctx.draw_tex(G.proc("voidcore"), b.x - s * 0.36, b.y - s * 0.36, s * 0.72, s * 0.72)
				G.draw(ctx, b.sprite, b.x, b.y, s, b.age * 1.6)
			elif b.cv:
				G.draw_canvas(ctx, b.cv, b.x, b.y, s, b.age * 3)
			ctx.additive = true
			if sin(b.age * 18) > 0: ctx.draw_tex(G.glow("#ff3d5a", 32), b.x - s * 0.6, b.y - s * 0.6, s * 1.2, s * 1.2)
			continue
		# ореол, спрайт и белое ядро (чтобы пуля читалась на любом фоне)
		var gs := b.w * 2
		ctx.alpha = 0.5
		ctx.draw_tex(G.glow(b.color, 32), b.x - gs / 2, b.y - gs / 2, gs, gs)
		ctx.alpha = 1.0
		var rot := atan2(b.vy, b.vx) + PI / 2 if b.rotate else 0.0
		if b.cv: G.draw_canvas(ctx, b.cv, b.x, b.y, b.w, rot)
		else: G.draw(ctx, b.sprite, b.x, b.y, b.w, rot)
		var r := b.r * 0.45
		ctx.fill = Color.WHITE
		ctx.fill_rect(b.x - r, b.y - r, r * 2, r * 2)
	ctx.additive = false


## профиль поперёк луча: прозрачные края → цвет → белое ядро (кэш по цвету)
func beamProfile(color: String) -> Texture2D:
	if _beamCache.has(color): return _beamCache[color]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.18, 0.36, 0.45, 0.55, 0.64, 0.82, 1.0])
	g.colors = PackedColorArray([U.col(color, 0), U.col(color, 0.18), U.col(color, 0.75), Color.WHITE, Color.WHITE, U.col(color, 0.75), U.col(color, 0.18), U.col(color, 0)])
	var tex := GradientTexture1D.new()
	tex.gradient = g
	tex.width = 64
	_beamCache[color] = tex
	return tex


## вертикальный луч между y0 и y1 полушириной w; dir — куда бегут импульсы (−1 вверх, 1 вниз); src — яркий исток
func drawBeamV(ctx: Ctx, x: float, y0: float, y1: float, w: float, color: String, alpha: float, dir := -1.0, src := NAN) -> void:
	var len := y1 - y0
	var S := G.S
	if len <= 0 or alpha <= 0: return
	var ww := w * (1 + 0.07 * sin(t * 47) + 0.04 * sin(t * 83))
	var prev := ctx.additive
	ctx.additive = true
	ctx.alpha = alpha
	ctx.draw_tex(beamProfile(color), x - ww * 1.6, y0, ww * 3.2, len)
	# импульсы бегут вдоль луча
	var step := 64 * S
	var off := fmod(t * 520 * S, step) * dir
	ctx.alpha = alpha * 0.55
	var gl := G.glow(color, 64)
	var gs := ww * 2.2
	var y := (y0 if dir > 0 else y1) + off
	while (y < y1) if dir > 0 else (y > y0):
		ctx.draw_tex(gl, x - gs / 2, y - gs * 0.9, gs, gs * 1.8)
		y += step if dir > 0 else -step
	# яркий исток
	if not is_nan(src):
		var ss := ww * 5
		ctx.alpha = alpha
		ctx.draw_tex(gl, x - ss / 2, src - ss / 2, ss, ss)
		ctx.draw_tex(G.glow("#ffffff", 32), x - ss / 5, src - ss / 5, ss / 2.5, ss / 2.5)
	ctx.alpha = 1.0
	ctx.additive = prev


func drawOverlays(ctx: Ctx) -> void:
	var p := player
	var S := G.S
	ctx.additive = true
	# рельса
	if ov.rail and p.alive:
		var r: Dictionary = ov.rail
		if r.t < r.charge:
			var k: float = r.t / r.charge
			ctx.alpha = 0.4 + k * 0.5
			ctx.draw_tex(G.glow("#7ffff0", 64), p.x - 40 * S * k, p.y - p.w * 0.6 - 40 * S * k, 80 * S * k, 80 * S * k)
			var sw := 46 * S * (0.4 + k * 0.6)
			ctx.alpha = 0.5 + k * 0.5
			G.draw(ctx, "fx_super", p.x, p.y - p.w * 0.45 - sw * 0.6, sw)
			# прицельная нить: тонкий мягкий луч
			drawBeamV(ctx, p.x, 0, p.y - p.w * 0.5, (1.5 + 2.5 * k) * S, "#7ffff0", 0.25 + 0.35 * k)
		else:
			# разгорается за 0,12 с, гаснет за 0,25 с
			var fade := minf(1.0, minf((r.t - r.charge) * 8, (r.charge + r.dur - r.t) * 4))
			drawBeamV(ctx, p.x, 0, p.y - p.w * 0.45, 24 * S * (0.6 + 0.4 * fade), "#3de0ff", fade, -1, p.y - p.w * 0.55)
			ctx.alpha = fade * (0.8 + U.random() * 0.2)
			G.draw(ctx, "fx_charge", p.x, p.y - p.w * 0.55 - 26 * S, 34 * S)
		ctx.alpha = 1.0
	# чёрная дыра
	if ov.hole:
		var h: Dictionary = ov.hole
		var k := minf(1.0, h.t * 3)
		var R := 210 * S
		ctx.alpha = 0.35 * k
		ctx.draw_tex(G.soft("#7a3dff", 64), h.x - R, h.y - R, R * 2, R * 2)
		var s := R * 0.55 * k * (1 + sin(h.t * 10) * 0.05)
		ctx.alpha = k
		G.draw(ctx, "fx_vortex", h.x, h.y, s * 2.6, h.t * 4)
		ctx.alpha = 0.55 * k
		G.draw(ctx, "fx_vortex", h.x, h.y, s * 1.7, -h.t * 6)
		ctx.alpha = 1.0
		ctx.additive = false
		ctx.draw_tex(G.proc("voidcore"), h.x - s * 0.45, h.y - s * 0.45, s * 0.9, s * 0.9)
		ctx.additive = true
		Post.lens(h.x, h.y, s * 0.9, 0.9 * k)
	# предупреждения о лучах и сами лучи
	for bm in ov.beams:
		if bm.t < bm.warn:
			# предупреждение: мерцающая красная полоса сужается к моменту выстрела, по краям — пунктир
			var k: float = bm.t / bm.warn
			var pulse := 0.5 + 0.5 * absf(sin(bm.t * 16))
			drawBeamV(ctx, bm.x, bm.y0, G.H, bm.w * (1.1 - 0.7 * k), "#ff3d5a", (0.12 + 0.18 * k) * pulse, 1)
			ctx.alpha = 0.35 + 0.4 * k * pulse
			ctx.stroke = U.col("#ff6b7d"); ctx.line_width = 1.5 * S
			ctx.dash = PackedFloat32Array([8 * S, 7 * S])
			for sd in [-1.0, 1.0]:
				ctx.begin_path(); ctx.move_to(bm.x + sd * bm.w * 0.9, bm.y0); ctx.line_to(bm.x + sd * bm.w * 0.9, G.H); ctx.stroke_path()
			ctx.dash = PackedFloat32Array()
		else:
			var k: float = 1 - (bm.t - bm.warn) / bm.dur
			drawBeamV(ctx, bm.x, bm.y0, G.H, bm.w * (0.7 + 0.3 * k), bm.color, minf(1.0, k * 1.6), 1, bm.y0)
	# поворотные лазеры
	for L in ov.lasers:
		var o := laserOrigin(L)
		var ex: float = o.x + cos(L.ang) * L.len
		var ey: float = o.y + sin(L.ang) * L.len
		if L.t < L.warn:
			ctx.alpha = 0.25 + 0.4 * absf(sin(L.t * 16))
			ctx.stroke = U.col(L.color); ctx.line_width = 2 * S
			ctx.stroke_line(o.x, o.y, ex, ey)
			var gs: float = (14 + 30 * L.t / L.warn) * S
			ctx.alpha = 0.6
			ctx.draw_tex(G.glow(L.color, 64), o.x - gs, o.y - gs, gs * 2, gs * 2)
			ctx.alpha = 0.85
			G.draw_canvas(ctx, G.tinted("fx_storm", {"hue": G.hue_of(L.color)}), o.x, o.y, gs * 2.2, L.ang - PI / 2)
		else:
			var k := minf(1.0, minf((L.t - L.warn) * 8, (L.warn + L.dur - L.t) * 5))
			ctx.alpha = 0.3 * k; ctx.stroke = U.col(L.color); ctx.line_width = L.w * 2.4; ctx.stroke_line(o.x, o.y, ex, ey)
			ctx.alpha = 0.8 * k; ctx.line_width = L.w; ctx.stroke_line(o.x, o.y, ex, ey)
			ctx.alpha = k; ctx.stroke = Color.WHITE; ctx.line_width = L.w * 0.32; ctx.stroke_line(o.x, o.y, ex, ey)
			var gs: float = L.w * 2.6
			ctx.draw_tex(G.glow(L.color, 64), o.x - gs, o.y - gs, gs * 2, gs * 2)
	ctx.alpha = 1.0
	ctx.additive = false


# ── данные для HUD ──
func powerProgress() -> float:
	return run.xp / D.perk_xp_need(run.level) if run else 0.0


func comboMul() -> float:
	return 1 + minf(run.combo, 100) * 0.02 if run else 1.0
