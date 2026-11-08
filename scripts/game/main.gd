extends Node
## Запуск, качество графики, музыка по режиму (автозагрузка Main) — перенос main.js.
## Сам игровой цикл и ввод — в сцене мира (scripts/world.gd), сюда — то, что нужно и игре, и интерфейсу.

var quality := 2          # 0 — низкое, 1 — среднее, 2 — высокое
var autoQ := true
var musicMode := "menu"
var fps := 60.0
var _fpsAcc := 0.0
var _fpsN := 0
var _slow := 0
var _fast := 0
var _downs := 0
var _upgraded := false
## Godot (браузер): потолок плотности пикселей холста по качеству. На айфоне devicePixelRatio = 3 — холст в 9 раз
## больше точек вёрстки; ×2 на глаз почти не отличить, а видеокарте вдвое с лишним меньше работы.
## Сам потолок — в index.html (export_presets.cfg, html/head_include: window.ssDprCap)
const DPR_CAP := [1.5, 2.0, 2.0]
const DPR_HIGH := 3.0     # «Высокое», выбранное вручную, — без потолка (на айфоне ×3)
var _dpr_force := -1.0   # проверки: -- --dpr=N (0 — без потолка)


func _ready() -> void:
	Bus.on("intensity", func(): if musicMode == "game": setMusic("game"))
	applyQuality()


func applyQuality() -> void:
	var q: String = M.s.settings.get("quality", "auto")
	# проверки: -- --quality=high|medium|low (без автоподбора)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="): q = a.substr(10)
		elif a.begins_with("--dpr="): _dpr_force = float(a.substr(6))
	autoQ = q == "auto"
	match q:
		"high": quality = 2
		"medium": quality = 1
		"low": quality = 0
		_: quality = 1 if OS.get_processor_count() <= 2 else 2
	_setQ(quality)
	FX.shake_on = M.s.settings.get("shake", true)


## музыка по режиму: меню — тихий слой, бой — с барабанами, босс и фивер — с соло
func setMusic(mode: String, force := false) -> void:
	musicMode = mode
	var style: String = M.s.settings.get("musicStyle", "synthwave")
	var lv := 0 if mode == "menu" else (2 if Game.boss != null or (Game.run and Game.run.get("fever", false)) else 1)
	if force: A.music_stop(true)
	A.music_play(style, lv)


## счётчик FPS и автоподбор качества: понижаем быстро, повышаем осторожно и не больше одного раза
func measure(dt: float) -> void:
	_fpsAcc += dt; _fpsN += 1
	if _fpsAcc < 0.5: return
	fps = _fpsN / _fpsAcc
	_fpsAcc = 0.0; _fpsN = 0
	if not autoQ or Game.state != "play": return
	if fps < 45:
		_slow += 1; _fast = 0
	elif fps > 57:
		_fast += 1; _slow = 0
	else:
		_slow = 0; _fast = 0
	if _slow >= 4 and quality > 0:
		_slow = 0; _downs += 1; _setQ(quality - 1)
	if _fast >= 60 and quality < 2 and _downs < 2 and not _upgraded:
		_fast = 0; _upgraded = true; _setQ(quality + 1)


## телефон или планшет (приложение или браузер). Safari на iPad называет себя «macOS» — узнаём его по сенсорному экрану
func is_mobile() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"): return true
	return OS.has_feature("web_macos") and DisplayServer.is_touchscreen_available()


## свечение (bloom) — самая дорогая часть постобработки: на телефоне только если «Высокое» выбрано вручную
func bloom_ok() -> bool:
	return not is_mobile() or M.s.settings.get("quality", "auto") == "high"


func _setQ(q: int) -> void:
	if q != quality: print("[quality] Q%d → Q%d (%.0f FPS)" % [quality, q, fps])
	quality = q
	FX.set_quality(q)
	if OS.has_feature("web"):
		var cap: float = DPR_CAP[clampi(q, 0, 2)]
		if q >= 2 and M.s.settings.get("quality", "auto") == "high": cap = DPR_HIGH
		if _dpr_force >= 0: cap = _dpr_force if _dpr_force > 0 else 99.0
		JavaScriptBridge.eval("window.ssDprCap = %s" % cap)
