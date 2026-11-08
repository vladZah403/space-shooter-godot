class_name Lang
## Язык игры. Исходный язык — русский: ключ перевода — сама русская строка, перевод лежит в data/i18n/en.json
## (собирает tools/i18n.py). Lang.t("ВОЛНА %d") % n — перевод строки; данные (D) переводятся целиком при загрузке,
## Ctx.fill_text и надписи Godot (автоперевод) переводят сами. Язык: user://lang.cfg (auto/ru/en); auto — русский
## для ru/uk/be/kk, иначе английский. Смена языка — перезапуск игры (Lang.restart).

const FILE := "user://lang.cfg"
const LANGS := ["auto", "ru", "en"]
## языки, для которых по умолчанию остаётся русский
const RU_LOCALES := ["ru", "uk", "be", "kk"]

static var code := ""          # "ru" или "en" — после первого обращения
static var en := false
static var _map: Dictionary = {}


static func _ensure() -> void:
	if code != "": return
	code = resolve(setting())
	# проверки: -- --lang=en
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lang="): code = resolve(a.substr(7))
	en = code == "en"
	if not en:
		TranslationServer.set_locale("ru")
		return
	var f := FileAccess.open("res://data/i18n/en.json", FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text()) if f else null
	if typeof(parsed) == TYPE_DICTIONARY:
		for k in parsed:
			if parsed[k] != "": _map[k] = parsed[k]
	# автоперевод надписей Godot (Label, Button) — для строк, что пришли не через Lang.t
	var tr := Translation.new()
	tr.locale = "en"
	for k in _map: tr.add_message(k, _map[k])
	TranslationServer.add_translation(tr)
	TranslationServer.set_locale("en")


## перевод строки (ключ — русский текст); нет перевода — строка как есть
static func t(s: String) -> String:
	_ensure()
	if not en: return s
	return _map.get(s, s)


static func is_en() -> bool:
	_ensure()
	return en


## перевести все русские строки в данных (словари и массивы — на месте)
static func tr_data(x: Variant) -> Variant:
	_ensure()
	if not en: return x
	if x is String: return _map.get(x, x)
	if x is Dictionary:
		for k in x: x[k] = tr_data(x[k])
	elif x is Array:
		for i in x.size(): x[i] = tr_data(x[i])
	return x


## выбранный в настройках язык: auto / ru / en
static func setting() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(FILE) != OK: return "auto"
	var v: String = cfg.get_value("lang", "code", "auto")
	return v if v in LANGS else "auto"


static func resolve(v: String) -> String:
	if v != "auto": return v
	return "ru" if OS.get_locale_language() in RU_LOCALES else "en"


## сохранить выбор; true — язык поменялся и игру нужно перезапустить
static func choose(v: String) -> bool:
	var cfg := ConfigFile.new()
	cfg.set_value("lang", "code", v)
	cfg.save(FILE)
	return resolve(v) != code


## перезапуск: в браузере — перезагрузка страницы, на компьютере — новый процесс
static func restart(tree: SceneTree) -> void:
	M.save()
	if OS.has_feature("web"):
		# сохранение в браузере дописывается в IndexedDB не мгновенно — даём ему время
		JavaScriptBridge.eval("setTimeout(function () { location.reload(); }, 800)")
		return
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	tree.quit()
