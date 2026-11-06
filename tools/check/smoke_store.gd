extends Node2D
## Дымовой тест сохранения и мета-прогрессии (store.gd): запись и чтение, слияние со старым сохранением,
## починка битых данных, покупки, навыки, опыт корабля, сундуки, достижения, задания, испытание, вход, итоги забега.

var fails := 0


func check(name_: String, ok: bool, info := "") -> void:
	if not ok: fails += 1
	print(("ok   " if ok else "FAIL ") + name_ + ("  " + info if info != "" else ""))


func _ready() -> void:
	# новый профиль → сохранить → прочитать
	M.s = M.defaults()
	M.s.coins = 123
	M.s.foeSeen = ["scout"]          # поля, которых нет в defaults, не теряются
	M.save()
	M.s = {}
	M.load_save()
	check("сохранение читается", M.s.coins == 123 and M.s.foeSeen == ["scout"], "coins=%s" % M.s.coins)
	check("числа из JSON — целые", M.s.coins is int and M.s.shipLvl is int)
	# битое старое сохранение: несуществующее оружие, корабль, навык, сундук; сломанная раскладка
	var f := FileAccess.open("user://save.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"v": 2, "coins": -5, "shipLvl": 0, "weapons": {"owned": ["laser", "nope"], "loadout": ["nope", "laser", "laser"], "ups": {"laser": {"dmg": 2.0}}},
		"ship": {"model": "ship99", "models": []}, "skills": {"sk_nope": 1}, "chests": ["bronze", "fake"], "patch": 40, "stats": {"games": 3}}))
	f.close()
	M.load_save()
	check("починка: монеты и уровень", M.s.coins >= 0 and M.s.shipLvl == 1, "coins=%s lvl=%s" % [M.s.coins, M.s.shipLvl])
	check("починка: оружие", M.s.weapons.owned == ["laser"] and M.s.weapons.loadout == ["laser"], str(M.s.weapons))
	check("починка: корабль", M.s.ship.model == "ship1" and "ship1" in M.s.ship.models)
	check("починка: навыки и сундуки", M.s.skills.is_empty() and "bronze" in M.s.chests and not "fake" in M.s.chests, str(M.s.chests))
	check("заметки обновления 4.1–4.3", M.s.notes.any(func(n): return n.type == "v41") and "silver" in M.s.chests and M.s.patch == 43, str(M.s.notes))
	check("уровень прокачки — int", M.weaponLevel("laser", "dmg") == 2)
	# покупки
	M.s = M.defaults()
	M.s.coins = 100000
	var wid: String = D.WEAPON_ORDER[1]
	check("купить оружие " + wid, M.buyWeapon(wid) and wid in M.s.weapons.owned and wid in M.s.weapons.loadout)
	var up: String = D.WEAPONS[wid].ups[0].id
	var c0: int = M.s.coins
	check("улучшение оружия", M.buyWeaponUp(wid, up) and M.weaponLevel(wid, up) == 1 and M.s.coins < c0)
	check("раскладка", M.toggleLoadout(wid) and not wid in M.s.weapons.loadout and not M.toggleLoadout("laser"))
	# опыт корабля и навыки
	var r := M.addShipXP(20000)
	check("опыт корабля → уровни", r.levels > 0 and M.s.shipLvl > 1, "lvl=%d +%d монет" % [M.s.shipLvl, r.coins])
	var sk := ""
	for id in D.SKILLS:
		if D.SKILLS[id].req.is_empty() and M.skillState(id).canLearn: sk = id; break
	check("изучить навык " + sk, sk != "" and M.learnSkill(sk) and M.s.skills[sk] == 1, "очков %d" % M.skillPoints())
	check("снять навык", M.forgetSkill(sk) == [sk] and M.s.skills.is_empty())
	# сундуки
	M.s.chests = ["bronze", "silver", "gold"]
	var got := []
	for i in 3: got.append(M.openChest())
	check("сундуки → реликвии", got.all(func(g): return g != null and D.RELICS.has(g.id)) and M.s.chests.is_empty(), str(got.map(func(g): return g.id)))
	check("реликвии в забег", M.relicLoadout().size() <= M.relicSlots(), "слотов %d" % M.relicSlots())
	# дроны
	M.s.shipLvl = 50
	check("дрон: купить и улучшить", M.compBuy("guard") and M.compUp("guard") and M.s.comp.lv.guard == 2)
	# достижения, раскраски, задания, испытание, вход
	M.s.stats.kills = 2000; M.s.stats.bosses = 30
	M.checkAchievements()
	check("достижения и раскраски", M.s.achievements.size() > 0 and "fire" in M.s.ship.skins and "phoenix2" in M.s.ship.skins, "достижений %d" % M.s.achievements.size())
	var ms := M.missions()
	check("задания дня", ms.size() == 3, ", ".join(ms.map(func(m): return M.missionText(m))))
	var ch := M.challenge()
	check("испытание дня", ch.mods.size() == 2 and D.WEAPONS.has(ch.weapon), str(ch))
	var c1: int = M.s.coins
	check("ступени испытания", M.challengeWave(ch, 30) and M.s.coins > c1 and M.challengeState().tiers > 0)
	var lr = M.claimLogin()
	check("награда за вход", lr != null and M.s.daily.streak == 1 and M.claimLogin() == null)
	check("боевая мощь", M.power() > 0 and M.overpowerK("normal") <= 1.0, "мощь %d" % M.power())
	# итоги забега
	var res := M.finishRun({"score": 54321, "wave": 12, "kills": 300, "bosses": 2, "maxCombo": 40, "time": 700.0, "diff": "normal", "perks": 6, "shots": 2000, "hits": 1700, "mode": "normal", "challenge": null})
	check("итоги забега", res.xp > 0 and M.s.stats.bestScore == 54321 and M.s.lb.size() == 1 and M.s.achievements.has("survive_10min"), str(res))
	var res2 := M.finishRun({"score": 999, "wave": 5, "kills": 30, "bosses": 1, "maxCombo": 4, "time": 100.0, "diff": "normal", "perks": 1, "shots": 10, "hits": 1, "mode": "rush", "challenge": null})
	check("рекорд режима отдельно", M.s.stats.modes.rush.best == 999 and M.s.stats.bestScore == 54321 and res2.isRecord)
	# отложенное сохранение срабатывает
	M.s.coins = 777
	M.soon(50)
	await get_tree().create_timer(0.2).timeout
	M.s = {}
	M.load_save()
	check("отложенное сохранение", M.s.coins == 777)
	print("FAILS %d" % fails)
	print("SMOKE DONE")
	get_tree().quit()
