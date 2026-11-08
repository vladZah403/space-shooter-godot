extends Node
## Сохранение и мета-прогрессия (автозагрузка M) — перенос store.js: SS.store (хранение) и SS.meta
## (покупки, опыт корабля, навыки, сундуки и реликвии, достижения, задания, испытание дня, награда за вход).
## Хранение: user://save.json (на вебе — IndexedDB браузера). Пишем через временный файл и переименование —
## сбой посреди записи не портит профиль. Облака Telegram и переноса со старой версии 1.x здесь нет.

const PATH := "user://save.json"
const TMP := "user://save.tmp"
const PATCH := 43

var s: Dictionary = {}
var DEV := false             # SS.DEV: всё открыто и бесплатно (запуск с --dev)
var _pending := false        # отложенное сохранение уже назначено


func _ready() -> void:
	DEV = "--dev" in OS.get_cmdline_user_args()
	load_save()


## сворачивание на телефоне, закрытие окна — сохраняем сразу, а не через 0,6 с
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if _pending or what != NOTIFICATION_APPLICATION_FOCUS_OUT: save()


static func now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func defaults() -> Dictionary:
	var diff := {}
	for k in D.DIFF_ORDER: diff[k] = {"best": 0, "wave": 0}
	return {
		"v": 2, "created": now_ms(), "updated": 0,
		"coins": 0,
		"shipXP": 0, "shipLvl": 1, "spBonus": 0, "skills": {},
		"comp": {"owned": ["gunner"], "sel": "gunner", "lv": {"gunner": 1}},
		"prestige": 0,
		"weapons": {"owned": ["laser"], "loadout": ["laser"], "ups": {}},
		"general": {},
		"ship": {"model": "ship1", "models": ["ship1"], "skin": "default", "skins": ["default"], "trail": "ice", "trails": ["ice", "fire"]},
		"stats": {"games": 0, "kills": 0, "bosses": 0, "bossTypes": [], "bestScore": 0, "bestWave": 0, "maxCombo": 0, "playTime": 0.0,
			"coinsEarned": 0, "perks": 0, "deaths": 0, "shots": 0, "diff": diff, "events": 0, "challenges": 0, "evos": []},
		"achievements": {},
		"daily": {"date": "", "missions": [], "bonus": false, "loginDate": "", "streak": 0, "seen": "", "ch": {"date": "", "best": 0, "wave": 0, "done": false}},
		"settings": {"music": 70, "sfx": 80, "musicStyle": "synthwave", "quality": "auto", "vibro": true, "sens": 1.25,
			"dmgNums": true, "shake": true, "fps": false, "diff": "normal", "intro": true, "dblBomb": true, "post": true},
		"lb": [],
		"seenIntro": false,
		"pilot": "kai",
		"bossSeen": [],   # боссы, чью полную кат-сцену уже показали
		"notes": [],
		# 4.1: коллекция реликвий { id: 1 }, взятые в забег, и закрытые сундуки ["bronze", ...] — открываются после забега
		"relics": {}, "relicLoadout": [], "chests": [],
		"tips": {},       # 4.3.2: какие окна-подсказки уже показаны (Game.tipOnce)
		"patch": 42,
	}


## аккуратное слияние: новые поля из defaults дополняют старое сохранение. Идём по ключам сохранения,
## а не defaults: поля, которых нет в defaults (comp.lv.guard, stats.modes, settings.mode, daily.ch.tiers, foeSeen…),
## иначе терялись бы при каждой загрузке
func merge(base: Dictionary, data) -> Dictionary:
	if not data is Dictionary: return base
	for k in data:
		var bv = base.get(k)
		var dv = data[k]
		if bv is Dictionary and dv is Dictionary: base[k] = merge(bv, dv)
		elif dv != null: base[k] = dv
	# словари с произвольными ключами копируем целиком
	for k in ["skills", "achievements", "general", "relics"]:
		if data.get(k) is Dictionary: base[k] = data[k].duplicate()
	if data.get("weapons") is Dictionary and data.weapons.get("ups") is Dictionary: base.weapons.ups = data.weapons.ups.duplicate(true)
	return base


# ════════════════════════════════════════════════════════════
# ХРАНЕНИЕ
# ════════════════════════════════════════════════════════════
func load_save() -> Dictionary:
	var data = null
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f: data = JSON.parse_string(f.get_as_text())
		if not data is Dictionary:
			push_warning("[store] повреждённое сохранение, начинаем заново")
			data = null
	s = defaults()
	if data != null:
		s = merge(s, data)
		patchNotes(data)
	sanitize()
	return s


## исправляет несовместимые значения (удалённые id, выход за пределы); числа из JSON — в целые
func sanitize() -> void:
	var w: Dictionary = s.weapons
	w.owned = w.owned.filter(func(x): return D.WEAPONS.has(x))
	if not "laser" in w.owned: w.owned.push_front("laser")
	var lo: Array = []
	for x in w.loadout:
		if x in w.owned and not x in lo: lo.append(x)
	w.loadout = lo.slice(0, 3)
	if w.loadout.is_empty(): w.loadout = ["laser"]
	for wid in w.ups:
		for u in w.ups[wid]: w.ups[wid][u] = int(w.ups[wid][u])
	for id in s.skills.keys():
		if not D.SKILLS.has(id): s.skills.erase(id)
	fixSkillSlots()
	var sh: Dictionary = s.ship
	if not D.SHIPS.has(sh.model) or not sh.model in sh.models: sh.model = "ship1"
	if not "ship1" in sh.models: sh.models.push_front("ship1")
	if not D.SKINS.any(func(k): return k.id == sh.skin): sh.skin = "default"
	if not "default" in sh.skins: sh.skins.push_front("default")
	if not sh.skin in sh.skins: sh.skin = "default"
	if not D.TRAILS.any(func(t): return t.id == sh.trail): sh.trail = "ice"
	for t in D.TRAILS:
		if t.price == 0 and not t.id in sh.trails: sh.trails.append(t.id)
	if not sh.trail in sh.trails: sh.trail = "ice"
	if not D.DIFFS.has(s.settings.diff): s.settings.diff = "normal"
	for id in s.relics.keys():
		if not D.RELICS.has(id): s.relics.erase(id)
	s.chests = (s.chests if s.chests is Array else []).filter(func(t): return D.CHESTS.has(t))
	var rl: Array = []
	for id in (s.relicLoadout if s.relicLoadout is Array else []):
		if s.relics.get(id) and not id in rl: rl.append(id)
	s.relicLoadout = rl
	s.coins = maxi(0, int(floor(float(s.coins))))
	s.shipLvl = clampi(int(s.shipLvl), 1, 999)
	for k in ["shipXP", "spBonus", "prestige"]: s[k] = int(s[k])
	s.daily.streak = int(s.daily.streak)
	for k in s.comp.lv: s.comp.lv[k] = int(s.comp.lv[k])
	for k in ["games", "kills", "bosses", "bestScore", "bestWave", "maxCombo", "coinsEarned", "perks", "deaths", "shots", "events", "challenges"]:
		s.stats[k] = int(s.stats.get(k, 0))


func save() -> void:
	_pending = false
	s.updated = now_ms()
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	if f == null:
		push_warning("[store] не удалось сохранить: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(s))
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(TMP), ProjectSettings.globalize_path(PATH))
	if err != OK:
		# на некоторых платформах переименование поверх файла не проходит — пишем напрямую
		var f2 := FileAccess.open(PATH, FileAccess.WRITE)
		if f2: f2.store_string(JSON.stringify(s))


## отложенное сохранение — не пишем на диск на каждое действие
func soon(ms := 600) -> void:
	if _pending: return
	_pending = true
	get_tree().create_timer(ms / 1000.0, true).timeout.connect(func(): if _pending: save())


## заметки об обновлениях для тех, кто играл в прошлые версии (окна «что нового»)
func patchNotes(data: Dictionary) -> void:
	var patch: float = data.get("patch", 0)
	var played: bool = data.get("stats") is Dictionary and data.stats.get("games", 0) > 0
	var has_note := func(type: String) -> bool: return s.notes.any(func(n): return n.type == type)
	if patch < 21 and played:
		if not has_note.call("v21") and not has_note.call("v2"): s.notes.append({"type": "v21"})
	elif patch >= 21 and patch < 24 and played:
		if not has_note.call("v24"): s.notes.append({"type": "v24"})
	elif patch >= 24 and patch < 25 and played:
		if not has_note.call("v25"): s.notes.append({"type": "v25"})
	# 3.0: прокачка корабля переехала в забег — кредиты за неё возвращаем
	if patch < 30:
		var refund := 0
		for g in D.GENERAL:
			var l := mini(int(s.general.get(g.id, 0)), g.costs.size())
			for i in l: refund += int(g.costs[i])
		s.general = {}
		if refund > 0: s.coins += refund
		if played and not has_note.call("v30"): s.notes.append({"type": "v30", "coins": refund})
	if patch >= 30 and patch < 31 and played and not has_note.call("v31"): s.notes.append({"type": "v31"})
	if patch >= 30 and patch < 40 and played and not has_note.call("v40"): s.notes.append({"type": "v40"})
	# 4.1: реликвии — коллекция из сундуков; тем, кто уже играл, — серебряный сундук в подарок
	if patch < 41 and played and not has_note.call("v41"):
		s.notes.append({"type": "v41"})
		s.chests.append("silver")
	if patch >= 41 and patch < 42 and played and not has_note.call("v42"): s.notes.append({"type": "v42"})
	if patch < 43 and played and not has_note.call("v43"): s.notes.append({"type": "v43"})
	s.patch = PATCH


func reset() -> void:
	var keep: Dictionary = s.settings
	s = defaults()
	s.settings = keep
	s.seenIntro = true
	save()


## старые сохранения: ранги в пределах, навыки без пути к ним по древу (3.1) и лишние активные снимаются —
## очки возвращаются сами (считаются от изученного)
func fixSkillSlots() -> void:
	for id in s.skills:
		var mx: int = int(D.SKILLS[id].max) if D.SKILLS[id].max else 1
		s.skills[id] = mini(mx, maxi(1, int(s.skills[id]) if s.skills[id] else 1))
	_dropOrphans()
	var byType := {"passive": [], "active": []}
	for id in s.skills: byType[D.SKILLS[id].type].append(id)
	var limit := {"passive": D.MAX_PASSIVE, "active": D.MAX_ACTIVE}
	for t in ["passive", "active"]:
		while byType[t].size() > limit[t]: s.skills.erase(byType[t].pop_back())


## снять навыки, к которым больше нет пути по древу; → снятые
func _dropOrphans() -> Array:
	var removed: Array = []
	var changed := true
	while changed:
		changed = false
		for id in s.skills.keys():
			var req: Array = D.SKILLS[id].req
			if not req.is_empty() and not req.any(func(r): return s.skills.get(r)):
				s.skills.erase(id); removed.append(id); changed = true
	return removed


# ════════════════════════════════════════════════════════════
# КРЕДИТЫ
# ════════════════════════════════════════════════════════════
func addCoins(n: float, earned := true) -> void:
	var k := int(floor(n))
	if k <= 0: return
	s.coins += k
	if earned: s.stats.coinsEarned += k
	Bus.emit("coins", s.coins)
	soon()


func spend(n: float) -> bool:
	if DEV: return true
	if s.coins < n: return false
	s.coins -= int(n)
	Bus.emit("coins", s.coins)
	save()
	return true


# ════════════════════════════════════════════════════════════
# ОРУЖИЕ
# ════════════════════════════════════════════════════════════
func _up(wid: String, upId: String):
	for u in D.WEAPONS[wid].ups:
		if u.id == upId: return u
	return null


func weaponLevel(wid: String, upId: String) -> int:
	var u = s.weapons.ups.get(wid)
	return int(u.get(upId, 0)) if u else 0


func upCost(wid: String, upId: String) -> int:
	var up = _up(wid, upId)
	var lvl := weaponLevel(wid, upId)
	return 0 if lvl >= up.max else int(up.costs[lvl])


func buyWeaponUp(wid: String, upId: String) -> bool:
	var up = _up(wid, upId)
	var lvl := weaponLevel(wid, upId)
	if up == null or lvl >= up.max or not wid in s.weapons.owned: return false
	if not spend(up.costs[lvl]): return false
	var u: Dictionary = s.weapons.ups.get_or_add(wid, {})
	u[upId] = lvl + 1
	if u[upId] >= up.max: unlock("max_one_upgrade")
	save()
	return true


func buyWeapon(wid: String) -> bool:
	var w = D.WEAPONS.get(wid)
	if w == null or wid in s.weapons.owned: return false
	if not spend(w.price): return false
	s.weapons.owned.append(wid)
	if s.weapons.loadout.size() < 3: s.weapons.loadout.append(wid)
	save()
	checkAchievements()
	return true


func toggleLoadout(wid: String) -> bool:
	var lo: Array = s.weapons.loadout
	var i := lo.find(wid)
	if i >= 0:
		if lo.size() > 1: lo.remove_at(i)
		else: return false
	else:
		if not wid in s.weapons.owned: return false
		if lo.size() >= 3: lo.pop_front()
		lo.append(wid)
	save()
	return true


# ════════════════════════════════════════════════════════════
# ПИЛОТЫ (3.0), КОРАБЛИ, РАСКРАСКИ, СЛЕДЫ
# ════════════════════════════════════════════════════════════
func pilotUnlocked(id: String) -> bool:
	var p = D.PILOTS.get(id)
	return p != null and (DEV or s.shipLvl >= p.lvl)


func setPilot(id: String) -> bool:
	if not pilotUnlocked(id): return false
	s.pilot = id
	save()
	return true


func buyShip(id: String) -> bool:
	var sh = D.SHIPS.get(id)
	if sh == null or id in s.ship.models: return false
	if s.shipLvl < sh.lvl and not DEV: return false
	if not spend(sh.price): return false
	s.ship.models.append(id)
	s.ship.model = id
	if id == "ship3": unlock("ship3")
	if id == "ship6": unlock("ship6")
	save()
	return true


func _trail(id: String):
	for t in D.TRAILS:
		if t.id == id: return t
	return null


func buyTrail(id: String) -> bool:
	var t = _trail(id)
	if t == null or id in s.ship.trails: return false
	if not spend(t.price): return false
	s.ship.trails.append(id)
	s.ship.trail = id
	if t.fx: unlock("trail_fx")
	save()
	return true


## условие раскраски (в data.js — функция cond у каждой записи SKINS; в JSON функции не переносятся)
func skinCond(id: String, sv: Dictionary) -> bool:
	var st: Dictionary = sv.stats
	match id:
		"default": return true
		"fire": return st.kills >= 50
		"ice": return sv.shipLvl >= 5
		"ghost": return st.bosses >= 3
		"alien": return st.bosses >= 5
		"gold": return st.coinsEarned >= 5000
		"dragon": return st.maxCombo >= 40
		"neon": return st.bestScore >= 50000
		"toxic": return st.kills >= 1000
		"void": return st.diff.get("nightmare", {}).get("wave", 0) >= 10 or st.diff.get("god", {}).get("wave", 0) >= 10
		"storm": return st.bestWave >= 30
		"phoenix2": return st.bosses >= 25
		"crystal": return sv.shipLvl >= 20
		"rainbow": return sv.achievements.size() >= 25
		"darkmatter": return st.bestScore >= 250000
	return false


## проверяет условия раскрасок, возвращает только что открытые
func refreshUnlocks() -> Array:
	var fresh: Array = []
	for sk in D.SKINS:
		if sk.id in s.ship.skins: continue
		if skinCond(sk.id, s):
			s.ship.skins.append(sk.id); fresh.append(sk)
	if not fresh.is_empty():
		soon()
		for sk in fresh: Bus.emit("skinUnlocked", sk)
	return fresh


# ════════════════════════════════════════════════════════════
# 4.0: ДРОНЫ-НАПАРНИКИ
# ════════════════════════════════════════════════════════════
func compBuy(id: String) -> bool:
	var d = D.COMPANIONS.get(id)
	var c: Dictionary = s.comp
	if d == null or id in c.owned or (s.shipLvl < d.lvl and not DEV) or not spend(d.price): return false
	c.owned.append(id); c.lv[id] = 1; c.sel = id
	save()
	return true


func compUp(id: String) -> bool:
	var d = D.COMPANIONS.get(id)
	var c: Dictionary = s.comp
	var lv: int = int(c.lv.get(id, 1))
	if d == null or not id in c.owned or lv >= 5 or not spend(d.costs[lv - 1]): return false
	c.lv[id] = lv + 1
	save()
	return true


# ════════════════════════════════════════════════════════════
# НАВЫКИ
# ════════════════════════════════════════════════════════════
func skillPointsTotal() -> int:
	return maxi(0, s.shipLvl - 1) + int(s.spBonus)


func skillPointsSpent() -> int:
	var n := 0
	for id in s.skills:
		if D.SKILLS.has(id): n += int(D.SKILLS[id].cost) * int(s.skills[id])
	return n


func skillPoints() -> int:
	return maxi(0, skillPointsTotal() - skillPointsSpent())


func skillCount(type: String) -> int:
	var n := 0
	for id in s.skills:
		if D.SKILLS.has(id) and D.SKILLS[id].type == type: n += 1
	return n


## 3.1: у навыка бывает несколько рангов; req — нужен хотя бы один из списка
func skillState(id: String) -> Dictionary:
	var sk: Dictionary = D.SKILLS[id]
	var rank := int(s.skills.get(id, 0))
	var mx: int = int(sk.max) if sk.max else 1
	var learned := rank > 0
	var maxed := rank >= mx
	var req: Array = sk.req
	var locked := not req.is_empty() and not req.any(func(r): return s.skills.get(r))
	var slotsFull: bool = not learned and skillCount(sk.type) >= (D.MAX_ACTIVE if sk.type == "active" else D.MAX_PASSIVE)
	var afford: bool = skillPoints() >= sk.cost
	return {"rank": rank, "max": mx, "learned": learned, "maxed": maxed, "locked": locked, "slotsFull": slotsFull, "afford": afford,
		"canLearn": not maxed and not locked and not slotsFull and afford}


func learnSkill(id: String) -> bool:
	var st := skillState(id)
	if not st.canLearn and not (DEV and not st.maxed and not st.locked and not st.slotsFull): return false
	if DEV and not st.afford: s.spBonus += int(D.SKILLS[id].cost)
	s.skills[id] = st.rank + 1
	save()
	checkAchievements()
	return true


## снять все навыки — бесплатно: навыки это выбор стиля, а не вложение
func resetSkills() -> int:
	var n: int = s.skills.size()
	s.skills = {}
	save()
	return n


## снимает навык и все зависящие от него
func forgetSkill(id: String) -> Array:
	if not s.skills.get(id): return []
	s.skills.erase(id)
	var removed: Array = [id] + _dropOrphans()
	save()
	return removed


# ════════════════════════════════════════════════════════════
# ОПЫТ КОРАБЛЯ
# ════════════════════════════════════════════════════════════
func addShipXP(n: float) -> Dictionary:
	var res := {"levels": 0, "coins": 0}
	s.shipXP += maxi(0, int(floor(n)))
	var need := D.ship_xp_need(s.shipLvl)
	while s.shipXP >= need and s.shipLvl < 999:
		s.shipXP -= need
		s.shipLvl += 1
		res.levels += 1
		var bonus: int = 50 + s.shipLvl * 10
		res.coins += bonus
		addCoins(bonus, false)
		need = D.ship_xp_need(s.shipLvl)
	if res.levels: Bus.emit("shipLevel", s.shipLvl, res)
	soon()
	return res


# ════════════════════════════════════════════════════════════
# 4.1: СУНДУКИ И КОЛЛЕКЦИЯ РЕЛИКВИЙ
# ════════════════════════════════════════════════════════════
func relicSlots() -> int:
	var n := 0
	var slots: Array = D.RELIC_SLOTS
	for i in slots.size():
		if DEV or s.shipLvl >= slots[i] or s.prestige >= i: n += 1
	return n


func relicCount() -> int:
	return s.relics.size()


## сундук получен в забеге — сразу в сохранение (закрытым): забег может оборваться
func addChest(tier: String) -> void:
	if not D.CHESTS.has(tier): return
	s.chests.append(tier)
	soon()


## какая реликвия выпадет: вес — по редкости сундука, у уже собранных вдвое меньше
func rollRelic(tier: String) -> String:
	var w: Dictionary = D.CHESTS[tier].w
	var ids: Array = D.RELICS.keys().filter(func(id): return w.get(D.RELICS[id].rar, 0) > 0)
	return U.pick_weighted(ids, func(id): return w[D.RELICS[id].rar] * (0.5 if s.relics.get(id) else 1.0))


## открыть первый закрытый сундук → { tier, id, dupe, coins }
func openChest():
	if s.chests.is_empty(): return null
	var tier: String = s.chests.pop_front()
	var id := rollRelic(tier)
	var dupe: bool = s.relics.has(id)
	var coins := 0
	if dupe:
		coins = int(D.RELIC_DUPE.get(D.RELICS[id].rar, 50))
		addCoins(coins)
	else:
		s.relics[id] = 1
		# свободный слот — сразу в забег
		if s.relicLoadout.size() < relicSlots(): s.relicLoadout.append(id)
	save()
	return {"tier": tier, "id": id, "dupe": dupe, "coins": coins}


## → "off" | "on" | "full" | false
func toggleRelic(id: String) -> Variant:
	var i: int = s.relicLoadout.find(id)
	if i >= 0:
		s.relicLoadout.remove_at(i); save()
		return "off"
	if not s.relics.get(id): return false
	if s.relicLoadout.size() >= relicSlots(): return "full"
	s.relicLoadout.append(id)
	save()
	return "on"


## реликвии, которые полетят в забег (лишние сверх открытых слотов — нет)
func relicLoadout() -> Array:
	return s.relicLoadout.filter(func(id): return s.relics.get(id)).slice(0, relicSlots())


# ════════════════════════════════════════════════════════════
# ПРЕСТИЖ
# ════════════════════════════════════════════════════════════
func canPrestige() -> bool:
	return s.shipLvl >= D.PRESTIGE_LVL


func prestigeBonus() -> Dictionary:
	var p: int = s.prestige
	return {"coins": 1 + p * 0.08, "dmg": 1 + p * 0.04}


func doPrestige() -> bool:
	if not canPrestige(): return false
	s.prestige += 1
	# прокачка оружия и корабля сохраняется — сбрасываются только уровень и навыки
	s.shipLvl = 1; s.shipXP = 0; s.skills = {}
	unlock("prestige1")
	save()
	return true


# ════════════════════════════════════════════════════════════
# ДОСТИЖЕНИЯ
# ════════════════════════════════════════════════════════════
func statValue(stat: String) -> float:
	var st: Dictionary = s.stats
	match stat:
		"bossTypes": return st.bossTypes.size()
		"weaponsOwned": return s.weapons.owned.size()
		"skillsLearned": return s.skills.size()
		"shipsOwned": return s.ship.models.filter(func(m): return D.SHIPS.has(m)).size()
		"shipLvl": return s.shipLvl
		"evoTypes": return st.get("evos", []).size()
	var v = st.get(stat, 0)
	return float(v) if (v is float or v is int) else 0.0


## медаль достижения (лист Влада, кадры ach_<группа>) и номер ступени в группе — рисуется плашкой поверх
const ACH_MEDAL := {
	"first_kill": ["kills", 1], "kill200_total": ["kills", 2], "kill1000_total": ["kills", 3], "kill5000": ["kills", 4],
	"boss1": ["boss", 1], "boss10": ["boss", 2], "boss_all": ["boss", 3], "overlord": ["boss", 4], "no_damage_boss": ["boss", 5],
	"combo5": ["combo", 1], "combo10": ["combo", 2], "combo30": ["combo", 3],
	"score1000": ["score", 1], "score5000": ["score", 2], "score250k": ["score", 3], "score1m": ["score", 4],
	"survive5": ["wave", 1], "wave20": ["wave", 2], "wave40": ["wave", 3], "wave65": ["wave", 4],
	"nightmare10": ["hard", 1], "god_mode_clear": ["hard", 2], "glass10": ["hard", 3],
	"shield": ["survive", 1], "no_hit_level": ["survive", 2], "survive_1hp": ["survive", 3], "survive_10min": ["survive", 4],
	"bomb_chain": ["aim", 1], "accuracy80": ["aim", 2],
	"perk15": ["evo", 1], "evo1": ["evo", 2], "evo_all": ["evo", 3],
	"weapon_all": ["arsenal", 1], "max_one_upgrade": ["arsenal", 2], "skill_tree_full": ["arsenal", 3],
	"ship_lvl20": ["fleet", 1], "ship3": ["fleet", 2], "ship6": ["fleet", 3], "ships_all": ["fleet", 4], "prestige1": ["fleet", 5],
	"coins10k": ["pilot", 1], "games50": ["pilot", 2], "daily3": ["pilot", 3], "daily_7": ["pilot", 4],
	"events10": ["pilot", 5], "challenge1": ["pilot", 6], "challenge7": ["pilot", 7], "trail_fx": ["pilot", 8],
}


func _ach(id: String):
	for a in D.ACHIEVEMENTS:
		if a.id == id: return a
	return null


func unlock(id: String) -> bool:
	if s.achievements.get(id): return false
	var a = _ach(id)
	if a == null: return false
	s.achievements[id] = now_ms()
	addCoins(a.reward, false)
	soon()
	Bus.emit("achievement", a)
	return true


func checkAchievements() -> void:
	for a in D.ACHIEVEMENTS:
		if a.stat == "" or s.achievements.get(a.id): continue
		if statValue(a.stat) >= a.goal: unlock(a.id)
	refreshUnlocks()


# ════════════════════════════════════════════════════════════
# ЕЖЕДНЕВНЫЕ ЗАДАНИЯ
# ════════════════════════════════════════════════════════════
func missions() -> Array:
	var d: Dictionary = s.daily
	var today := U.today()
	if d.date != today:
		var rnd := U.seeded(U.hash_str(today + ":0"))
		var pool: Array = D.MISSIONS.duplicate()
		var picked: Array = []
		while picked.size() < 3 and not pool.is_empty():
			picked.append(pool.pop_at(int(floor(rnd.call() * pool.size()))))
		d.date = today
		d.bonus = false
		var bw: int = s.stats.bestWave
		var maxTier := 2 if bw >= 15 else (1 if bw >= 8 else 0)
		d.missions = picked.map(func(m):
			var tier := int(floor(rnd.call() * (maxTier + 1)))
			return {"id": m.id, "goal": m.goals[tier], "reward": m.rewards[tier], "progress": 0.0, "done": false})
		soon()
	return d.missions


func _mission(id: String):
	for x in D.MISSIONS:
		if x.id == id: return x
	return null


func missionText(m: Dictionary) -> String:
	var def = _mission(m.id)
	return def.text.replace("{n}", U.fmt(m.goal)) if def else m.id


## прибавить значение или (def.max) зафиксировать максимум
func trackMission(id: String, value: float) -> void:
	var list := missions()
	for m in list:
		if m.id != id or m.done: continue
		var def = _mission(id)
		m.progress = maxf(m.progress, value) if def.max else m.progress + value
		if m.progress >= m.goal:
			m.progress = m.goal; m.done = true
			addCoins(m.reward, false)
			Bus.emit("mission", m)
	var d: Dictionary = s.daily
	if not d.bonus and not list.is_empty() and list.all(func(m): return m.done):
		d.bonus = true
		addCoins(D.DAILY_BONUS, false)
		unlock("daily3")
		Bus.emit("missionBonus", D.DAILY_BONUS)
	soon()


# ════════════════════════════════════════════════════════════
# ЭВОЛЮЦИИ, УРОН ОРУЖИЯ, БОЕВАЯ МОЩЬ
# ════════════════════════════════════════════════════════════
func onEvolution(wid: String) -> void:
	var st: Dictionary = s.stats
	if not wid in st.evos: st.evos.append(wid)
	unlock("evo1")
	checkAchievements()


## урон оружия в секунду ПО ОДНОЙ ЦЕЛИ (примерно, сверено со стендом урона).
## full — с бонусами корабля и престижа (для Боевой мощи); иначе — прокачка оружия и «Корабль» в арсенале
func weaponDps(wid: String, full := false) -> float:
	var b: Dictionary = D.WEAPONS[wid].base
	var ship: Dictionary = D.SHIPS[s.ship.model].stats
	var pres := prestigeBonus()
	var dm: float = 1 + weaponLevel(wid, "dmg") * 0.12 + ((ship.get("dmg", 0.0) + pres.dmg - 1) if full else 0.0)
	var rate: float = 1 + ship.get("rate", 0.0) if full else 1.0
	var up := 1 + weaponLevel(wid, "rate") * 0.08
	var cd: float = b.cd / up
	var mag: float = (b.mag + (weaponLevel(wid, "salvo") if wid == "rocket" else 0)) if b.mag else 0.0
	var perSec: float = mag / ((mag - 1) * cd + b.reload / up) if mag else 1 / cd
	var dps := 0.0
	match wid:
		"laser": dps = b.dmg * dm / cd * (1 + b.focus * b.focusMax * 0.9)
		"arc": dps = b.dmg * dm / cd * (b.min + b.max) / 2
		"shotgun": dps = b.dmg * dm * (b.pellets + weaponLevel(wid, "pellets")) * 0.65 * perSec
		"rocket": dps = b.dmg * dm * perSec
		"plasma": dps = (b.dmg + b.aoe) * dm / cd * (b.min + b.max) / 2
		"lightning": dps = b.dmg * dm / cd
		"darkmatter": dps = (b.dmg * (b.life / b.tick) * 0.6 + b.burst) * dm / maxf(cd, b.life)
		# Godot: клинок режет дважды за рейс; рейсов в секунду — сколько клинков в воздухе
		"boomerang": dps = b.dmg * dm * 2 * (b.air + weaponLevel(wid, "air")) / (b.out * 2.2)
		"gravgun": dps = b.dmg * dm / cd * (1 + b.impact * 0.5)
		"flail": dps = b.dmg * dm / b.tick * 0.8
	return dps * rate


## Боевая мощь (3.0): урон лучшего оружия × живучесть × навыки. Новичок ≈ 120, всё на максимуме ≈ 850
func power() -> int:
	var ship: Dictionary = D.SHIPS[s.ship.model].stats
	var dps := 0.0
	for wid in s.weapons.owned:
		if D.WEAPONS.has(wid): dps = maxf(dps, weaponDps(wid, true))
	var lives: float = D.BASE_LIVES + ship.get("lives", 0)
	var skills := 0
	for k in s.skills:
		if s.skills[k]: skills += 1
	return int(round(dps * sqrt(lives / D.BASE_LIVES) * (1 + skills * 0.03) * 1.4))


## сложность открыта: первые три сразу; дальше — волна D.DIFF_UNLOCK_WAVE на предыдущей.
## Где уже есть рекорд (играли до 3.0) — остаётся открытой
func diffUnlocked(id: String) -> bool:
	var d = D.DIFFS.get(id)
	var st: Dictionary = s.stats.diff
	if d == null: return false
	if d.unlock == "" or DEV or st.get(id, {}).get("wave", 0) > 0: return true
	return st.get(d.unlock, {}).get("wave", 0) >= D.DIFF_UNLOCK_WAVE


## страховка: если мощь в 3+ раза выше рекомендуемой, кредиты плавно снижаются до ×0,5 (к 6 разам)
func overpowerK(id: String, pw := -1.0) -> float:
	var rec: float = D.DIFFS[id].power if D.DIFFS.has(id) else 0.0
	if not rec: return 1.0
	var r := (float(power()) if pw < 0 else pw) / rec
	return 1.0 if r <= 3 else maxf(0.5, 1 - (r - 3) / 6)


# ════════════════════════════════════════════════════════════
# ИСПЫТАНИЕ ДНЯ: правила одинаковы у всех в этот день (зерно — только дата)
# ════════════════════════════════════════════════════════════
func challenge() -> Dictionary:
	var today := U.today_utc()
	var rnd := U.seeded(U.hash_str("challenge:" + today))
	var pool: Array = D.CHALLENGE_MODS.map(func(m): return m.id)
	var mods: Array = []
	while mods.size() < 2:
		var id: String = pool.pop_at(int(floor(rnd.call() * pool.size())))
		# стеклянная пушка без бонусов и форы — слишком жёстко для награды раз в день
		if (id == "nodrops" and "glass" in mods) or (id == "glass" and "nodrops" in mods): continue
		mods.append(id)
	var ws: Array = D.WEAPON_ORDER.filter(func(w): return w != "laser")
	return {"date": today, "mods": mods, "weapon": ws[int(floor(rnd.call() * ws.size()))]}


## tiers — сколько ступеней наград уже получено сегодня (done — старое поле: первая ступень)
func challengeState() -> Dictionary:
	var d: Dictionary = s.daily
	var today := U.today_utc()
	if not d.get("ch") is Dictionary or d.ch.date != today: d.ch = {"date": today, "best": 0, "wave": 0, "done": false, "tiers": 0}
	if not d.ch.has("tiers"): d.ch.tiers = 1 if d.ch.done else 0
	d.ch.tiers = int(d.ch.tiers)
	return d.ch


func modText(id: String, ch: Dictionary) -> String:
	for m in D.CHALLENGE_MODS:
		if m.id == id: return m.desc.replace("{w}", D.WEAPONS[ch.weapon].name)
	return id


## волна испытания: дошли до ступени — её награда (каждая ступень раз в день)
func challengeWave(ch: Dictionary, wave: int) -> bool:
	var c := challengeState()
	if ch.date != c.date: return false
	var got := false
	var tiers: Array = D.CHALLENGE_TIERS
	while c.tiers < tiers.size() and wave >= tiers[c.tiers].wave:
		var t: Dictionary = tiers[c.tiers]
		c.tiers += 1
		c.done = true
		if c.tiers == 1:
			s.stats.challenges += 1; unlock("challenge1")
		addCoins(t.coins, false)
		Bus.emit("toast", {"ico": "🎲", "title": "ИСПЫТАНИЕ: СТУПЕНЬ %d / %d" % [c.tiers, tiers.size()], "text": "Волна %d — +%d кредитов" % [t.wave, t.coins], "dur": 3200})
		got = true
	if got:
		checkAchievements(); save()
	return got


# ════════════════════════════════════════════════════════════
# НАГРАДА ЗА ВХОД
# ════════════════════════════════════════════════════════════
func loginStatus() -> Dictionary:
	var d: Dictionary = s.daily
	var today := U.today()
	if d.loginDate == today: return {"available": false, "day": (d.streak - 1) % 7, "streak": d.streak}
	var gap := U.days_between(d.loginDate, today) if d.loginDate != "" else 99
	var streak: int = d.streak + 1 if gap == 1 else 1
	return {"available": true, "day": (streak - 1) % 7, "streak": streak}


func claimLogin():
	var st := loginStatus()
	if not st.available: return null
	var r: Dictionary = D.LOGIN[st.day]
	var d: Dictionary = s.daily
	d.loginDate = U.today()
	d.streak = st.streak
	addCoins(r.coins, false)
	if r.get("sp", 0): s.spBonus += int(r.sp)
	if d.streak >= 7: unlock("daily_7")
	save()
	return r


# ════════════════════════════════════════════════════════════
# СОБЫТИЯ ЗАБЕГА: пишем в статистику сразу, чтобы прогресс не терялся при закрытии
# ════════════════════════════════════════════════════════════
func onKill() -> void:
	s.stats.kills += 1
	trackMission("kills", 1)


func onBoss(id: String) -> void:
	var st: Dictionary = s.stats
	st.bosses += 1
	if not id in st.bossTypes: st.bossTypes.append(id)
	trackMission("bosses", 1)
	checkAchievements()


func onCombo(c: int) -> void:
	if c > s.stats.maxCombo: s.stats.maxCombo = c
	trackMission("combo", c)


## итоги забега. run: { score, wave, kills, bosses, maxCombo, time, diff, perks, shots, hits, mode, challenge }
func finishRun(run: Dictionary) -> Dictionary:
	var st: Dictionary = s.stats
	st.games += 1
	st.playTime += run.time
	st.perks += int(run.perks)
	st.shots += int(run.shots)
	st.deaths += 1
	# 4.0: режимы (босс-раш, выживание) — свои рекорды; в рекорды сложностей и рейтинг не идут, опыт корабля дают
	var isRecord := false
	var mode: String = run.get("mode", "normal")
	if mode != "normal" and mode != "":
		var md: Dictionary = st.get_or_add("modes", {}).get_or_add(mode, {"best": 0, "wave": 0, "time": 0.0})
		isRecord = run.score > md.best
		md.best = max(md.best, run.score); md.wave = max(md.wave, run.wave); md.time = maxf(md.time, run.time)
	else:
		isRecord = run.score > st.bestScore
		st.bestScore = max(st.bestScore, run.score)
		st.bestWave = max(st.bestWave, run.wave)
		var dd: Dictionary = st.diff.get_or_add(run.diff, {"best": 0, "wave": 0})
		dd.best = max(dd.best, run.score)
		dd.wave = max(dd.wave, run.wave)
		if run.diff == "nightmare" and run.wave >= 10: unlock("nightmare10")
		if run.diff == "god" and run.wave >= 15: unlock("god_mode_clear")
		if run.get("challenge"):
			var c := challengeState()
			c.best = max(c.best, run.score); c.wave = max(c.wave, run.wave)
		# 3.0: рекорды по сложностям — по 10 лучших забегов на каждой (очки разных сложностей не сравниваются)
		s.lb.append({"score": run.score, "wave": run.wave, "diff": run.diff, "date": now_ms()})
		s.lb.sort_custom(func(a, b): return a.score > b.score)
		var per := {}
		var lb: Array = []
		for r in s.lb:
			per[r.diff] = per.get(r.diff, 0) + 1
			if per[r.diff] <= 10: lb.append(r)
		s.lb = lb
	if run.shots >= 150 and float(run.hits) / run.shots >= 0.8: unlock("accuracy80")
	if run.time >= 600: unlock("survive_10min")
	# опыт корабля: за врагов, волны и боссов; за врагов и очки нормирован на число врагов и множитель очков,
	# затем умножен на опыт сложности
	var dk: Dictionary = D.DIFFS.get(run.diff, D.DIFFS.normal)
	var xp := int(round((run.kills / dk.count + run.wave * 12 + run.bosses * 120 + run.score / (400 * dk.score * dk.count)) * dk.xp * D.ECON.xp))
	var lvlBefore: int = s.shipLvl
	var xpBefore: int = s.shipXP
	var res := addShipXP(xp)
	trackMission("games", 1)
	trackMission("score", run.score)
	trackMission("wave", run.wave)
	trackMission("minutes", run.time / 60.0)
	checkAchievements()
	save()
	return {"xp": xp, "isRecord": isRecord, "lvlBefore": lvlBefore, "xpBefore": xpBefore, "levels": res.levels, "lvlCoins": res.coins}
