extends RefCounted
## Общая подготовка дымовых тестов: состояние забега как после Game.start (тот же набор полей run, st —
## без бонусов), бессмертный корабль. Пока store.gd (M) не перенесён, M.s — минимальное сохранение.

static func setup(wave_n := 5) -> void:
	M.s = {"skills": {}, "ship": {"model": D.SHIPS.keys()[0], "skin": "", "trail": ""}, "settings": {"dmgNums": true}, "foeSeen": [], "hints": {}, "tips": {},
		"comp": {"sel": "", "owned": [], "lv": {}}, "weapons": {"loadout": ["laser"]}}
	Game.state = "play"
	Game.mode = "normal"
	Game.diff = D.DIFFS.normal
	Game.t = 0.0
	Game.run = {
		"score": 0, "coins": 0, "kills": 0, "bosses": 0, "bossIds": [], "combo": 0, "comboT": 0.0, "maxCombo": 0,
		"level": 1, "xp": 0.0, "pendingPerks": 0, "perks": {}, "perkCount": 0, "rerolls": 0, "relics": {}, "chests": [], "map": null, "mapNode": null, "mapStep": 0,
		"time": 0.0, "shots": 0, "hits": 0, "pickups": 0, "reviveUsed": false, "phoenixUsed": false, "featherUsed": false,
		"waveDamage": 0, "bossDamage": 0.0, "bossDamaged": false, "oneHpT": 0.0, "killsForVamp": 0, "critsForVamp": 0, "detCount": 0, "bloodKills": 0, "evo": {}, "lastHit": "", "hitAt": 0.0,
		"skillCd": {}, "skillFx": {}, "overload": 0.0, "regenT": 0.0, "shieldRegenT": 0.0, "repairT": 0.0, "emergT": 0.0, "stormT": 0.0, "nanoT": 0.0, "fever": false, "nextCrit": false,
		"lastAchCheck": 0.0, "sector": 0, "lastEvent": 0, "lastEventId": "", "energy": 1.0, "arc": 0.0, "focus": {"uid": 0, "n": 0, "t": 0.0},
		"mods": {}, "pilot": "kai", "challenge": null, "noDrops": false,
		"anomaly": null, "lastAnomaly": "", "anomalies": 0, "tipQ": [], "waveRng": null, "perkRng": null,
		"bossDps": 0.0, "bossK": 1.0, "sectorOrder": range(D.SECTORS.size()), "bossOrder": range(D.BOSSES.size()),
	}
	Game.st = {"dmg": 1.0, "rate": 1.0, "crit": 0.03, "critMul": 2.0, "pierce": 0, "multi": 0, "wings": 0.0, "magnet": 120 * G.S, "coins": 1.0, "luck": 1.0,
		"speed": 1.0, "dodge": 0.0, "cdMul": 1.0, "bomb": 1.0, "bombCd": 1.0, "invMul": 1.0, "bossDmg": 1.0, "eliteDmg": 1.0, "xp": 1.0, "shieldRegen": 0.0, "cryo": 0.0, "nova": 0}
	Game.wave = {"n": wave_n, "boss": false, "budget": 0.0, "spent": 0.0, "spawnT": 0.0, "intro": 999.0, "done": true, "cleared": true, "clearT": 0.0, "miniDone": true, "startT": 0.0, "danger": false}
	Game.buffs = {}
	Game.clearWorld()
	var p := Pl.new()
	p.x = G.FW / 2; p.y = G.H * 0.8; p.w = 56 * G.S; p.r = 6 * G.S; p.pickR = 28 * G.S
	p.inv = 1e9; p.alive = true; p.lives = 3; p.maxLives = 3; p.weapons = ["laser"]; p.weapon = "laser"
	Game.player = p


## один кадр мира без ввода и стрельбы игрока: враги, их пули, отложенные действия
static func step(dt: float) -> void:
	Game.t += dt
	Game.run.time += dt
	E.updateAll(dt, dt)
	Foes.update(dt)
	Game.runTimers(dt)
