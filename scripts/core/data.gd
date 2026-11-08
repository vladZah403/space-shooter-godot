extends Node
## Игровые данные (автозагрузка D) — таблицы из data.js JS-версии, выгруженные в data/game_data.json:
## D.WEAPONS, D.ENEMIES, D.PERKS, D.RELICS, D.BOSSES, D.SECTORS…  Числа в JSON — float.
## В записях однотипных таблиц (враги, перки, реликвии…) недостающие поля дополняются пустыми значениями
## (0, false, "", [], {}): в JS отсутствующее поле было undefined, а в GDScript обращение к нему — ошибка.

const PATH := "res://data/game_data.json"
## таблицы записей: { id: {...} } или [ {...}, ... ]
const RECORD_TABLES := ["ENEMIES", "BOSSES", "PERKS", "RELICS", "MODULES", "SKILLS", "SHIPS", "WEAPONS", "PILOTS",
	"COMPANIONS", "MAP_NODES", "SECTORS", "EVENTS", "ANOMALIES", "POWERUPS", "DIFFS", "ACHIEVEMENTS", "MISSIONS",
	"TRAILS", "SKINS", "MAP_EVENTS", "EVOLUTIONS", "CHALLENGE_MODS", "MODES", "CHESTS", "GENERAL", "TIPS"]

## таблица → { поле: значение, если поля нет }. null — «не задано» (проверять != null)
const OPTIONAL := {
	"ENEMIES": {"tint": null, "rot": PI},   # спрайт без своего поворота смотрит вниз (def.rot ?? Math.PI)
	"COMPANIONS": {"hue": null},
}

var data: Dictionary = {}


func _init() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_error("Нет файла данных " + PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Файл данных повреждён: " + PATH)
		return
	data = Lang.tr_data(parsed)   # Godot: английский — тексты переводятся сразу при загрузке
	# необязательные поля, где в JS «нет поля» ≠ 0 (проверка !== undefined): ставим их до дополнения,
	# иначе дополнение дало бы 0 — например, оттенок 0 (красный) всем врагам без своего tint
	for t in OPTIONAL:
		for r in data[t].values():
			for k in OPTIONAL[t]:
				if not r.has(k):
					r[k] = OPTIONAL[t][k]
	for t in RECORD_TABLES:
		if data.has(t):
			_normalize(data[t])
	# у оружия свои вложенные base — тоже дополняем по всем видам
	var bases := []
	for w in data.WEAPONS.values():
		bases.append(w.base)
	_normalize(bases)


func _get(property: StringName) -> Variant:
	return data.get(property)


## дополнить записи таблицы недостающими полями
func _normalize(table) -> void:
	var recs: Array = table.values() if table is Dictionary else table
	var proto := {}
	for r in recs:
		if not r is Dictionary:
			return
		for k in r:
			if not proto.has(k) and r[k] != null:
				proto[k] = _empty_like(r[k])
	for r in recs:
		for k in proto:
			if not r.has(k):
				r[k] = proto[k].duplicate() if proto[k] is Array or proto[k] is Dictionary else proto[k]


func _empty_like(v) -> Variant:
	match typeof(v):
		TYPE_FLOAT, TYPE_INT:
			return 0.0
		TYPE_BOOL:
			return false
		TYPE_STRING:
			return ""
		TYPE_ARRAY:
			return []
		TYPE_DICTIONARY:
			return {}
	return null


# ── функции из data.js ──
func revive_cost(wave: int) -> int:
	return int(round(150 + wave * 35 + wave * wave * 2.5))


func ship_xp_need(lvl: int) -> int:
	return int(round(150 * pow(lvl, 1.25) + 40))


func perk_xp_need(lvl: int) -> int:
	return 6 if lvl <= 1 else int(round(4 + lvl * 5 + lvl * lvl * 0.9))
