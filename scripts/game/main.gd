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


func _ready() -> void:
	Bus.on("intensity", func(): if musicMode == "game": setMusic("game"))
	applyQuality()


func applyQuality() -> void:
	var q: String = M.s.settings.get("quality", "auto")
	autoQ = q == "auto"
	match q:
		"high": quality = 2
		"medium": quality = 1
		"low": quality = 0
		_: quality = 1 if OS.get_processor_count() <= 2 else 2
	FX.set_quality(quality)
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
		quality -= 1; _slow = 0; _downs += 1; FX.set_quality(quality)
	if _fast >= 60 and quality < 2 and _downs < 2 and not _upgraded:
		quality += 1; _fast = 0; _upgraded = true; FX.set_quality(quality)
