extends Node
## Звук (автозагрузка A) — перенос audio.js.
##  Эффекты и музыка синтезированы тем же кодом JS-версии и записаны в WAV (tools/render_audio.mjs):
##  assets/audio/sfx/<имя>.wav, assets/audio/music/<стиль>_<0|1|2>.wav — петли по 4 такта для интенсивности
##  0 (меню), 1 (бой), 2 (босс/фивер). Все три слоя стиля играют синхронно, интенсивность — плавная смена громкости.
##  Шины: Master (компрессор, как DynamicsCompressor в JS) ← Music (фильтр «приглушить» на паузе) и SFX.
##  A.play("explodeM", {"vol": 0.8, "rate": 1.2}); A.music_play("synthwave", 1); A.muffle(true)

const DIR := "res://assets/audio/"
## минимальный интервал (с) и громкость по умолчанию — чтобы частые звуки не «долбили»
const LIMIT := {
	"laser": [0.06, 0.32], "shotgun": [0.08, 0.55], "rocket": [0.08, 0.4], "plasma": [0.1, 0.55], "zap": [0.07, 0.45], "arc": [0.08, 0.45], "dark": [0.12, 0.5],
	"hit": [0.035, 0.32], "hitArmor": [0.05, 0.4], "explodeS": [0.04, 0.55], "explodeM": [0.08, 0.7], "explodeL": [0.3, 1.0], "enemyShot": [0.07, 0.25],
	"coin": [0.04, 0.4], "xp": [0.03, 0.3], "mine": [0.1, 0.35],
}
const VOICES := 24
const STYLE_IDS := ["synthwave", "chiptune", "ambient", "dnb", "cyber"]

var meta: Dictionary = {}
var sfx: Dictionary = {}          # имя → AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _last := {}
var _bus_music := 0
var _bus_sfx := 0
var _lowpass: AudioEffectLowPassFilter
var _muffle := 20000.0
var _muffle_to := 20000.0

# музыка
var style := ""
var intensity := 0
var _layers: Array[AudioStreamPlayer] = []
var _layer_vol: Array[float] = [0.0, 0.0, 0.0]
var _fade := 0.0                 # общая громкость стиля 0..1 (появление и уход)
var _fade_to := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	var f := FileAccess.open(DIR + "audio.json", FileAccess.READ)
	if f: meta = JSON.parse_string(f.get_as_text())
	for name in meta.get("sfx", {}):
		var s = load(DIR + "sfx/" + name + ".wav")
		if s: sfx[name] = s
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for lv in 3:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80
		add_child(p)
		_layers.append(p)
	applyVolumes()


func _setup_buses() -> void:
	# Master: компрессор, как в JS (порог −14 дБ, 6:1, атака 3 мс, отпускание 200 мс)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -14; comp.ratio = 6; comp.attack_us = 3000; comp.release_ms = 200
	AudioServer.add_bus_effect(0, comp)
	_bus_music = _add_bus("Music")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000
	AudioServer.add_bus_effect(_bus_music, _lowpass)
	_bus_sfx = _add_bus("SFX")


func _add_bus(name: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i >= 0: return i
	AudioServer.add_bus()
	i = AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, "Master")
	return i


## громкость из настроек (0..100), квадратичная кривая, как в JS
func applyVolumes() -> void:
	var st = M.s.get("settings") if M.s else null
	var mv: float = (st.music if st else 70) / 100.0
	var sv: float = (st.sfx if st else 80) / 100.0
	AudioServer.set_bus_volume_db(_bus_music, linear_to_db(maxf(0.0001, mv * mv * 0.9)))
	AudioServer.set_bus_volume_db(_bus_sfx, linear_to_db(maxf(0.0001, sv * sv * 0.95)))


## o: vol, rate
func play(name: String, o := {}) -> void:
	var s = sfx.get(name)
	if s == null: return
	var lim = LIMIT.get(name)
	var now := Time.get_ticks_msec() / 1000.0
	if lim and now - _last.get(name, -10.0) < lim[0]: return
	var p: AudioStreamPlayer = null
	for q in _pool:
		if not q.playing:
			p = q
			break
	if p == null: return
	_last[name] = now
	p.stream = s
	p.pitch_scale = o.get("rate", U.rand(0.94, 1.06) if lim else 1.0)
	var vol: float = o.get("vol", 1.0) * (lim[1] if lim else 0.8) * meta.sfx[name].get("gain", 1.0) * 0.9
	p.volume_db = linear_to_db(maxf(0.0001, vol))
	p.play()


## приглушение музыки на паузе
func muffle(on: bool) -> void:
	_muffle_to = 700.0 if on else 20000.0


## на телефоне при сворачивании звук замирает сам; на всякий случай — пауза всех плееров
func suspend() -> void:
	for p in _layers: p.stream_paused = true


func resume() -> void:
	for p in _layers: p.stream_paused = false


# ════════════════════════════════════════════════════════════
# МУЗЫКА
# ════════════════════════════════════════════════════════════
## intensity: 0 — меню, 1 — бой, 2 — босс/фивер
func music_play(style_id: String, lv: int) -> void:
	if not style_id in STYLE_IDS: style_id = "synthwave"
	intensity = clampi(lv, 0, 2)
	if style_id == style and _fade_to > 0: return
	style = style_id
	for i in 3:
		var s = load(DIR + "music/%s_%d.wav" % [style_id, i])
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_begin = 0
			s.loop_end = int(round(meta.music["%s_%d" % [style_id, i]].dur * s.mix_rate))
		_layers[i].stream = s
		_layer_vol[i] = 1.0 if i == intensity else 0.0
		_layers[i].volume_db = -80
	# все три слоя стартуют вместе — дальше идут в такт и только меняют громкость
	for p in _layers: p.play()
	_fade = 0.0
	_fade_to = 1.0


func music_stop(fast := false) -> void:
	_fade_to = 0.0
	_stop_fast = fast


func setIntensity(lv: int) -> void:
	intensity = clampi(lv, 0, 2)


var _stop_fast := false


func _process(dt: float) -> void:
	# фильтр «приглушить»: как setTargetAtTime с постоянной 0,15 с
	_muffle = lerpf(_muffle, _muffle_to, 1 - exp(-dt / 0.15))
	_lowpass.cutoff_hz = _muffle
	if style == "": return
	var fade_k := (1.0 / (0.4 if _stop_fast else 1.2)) if _fade_to < _fade else (1.0 / 1.2)
	_fade = move_toward(_fade, _fade_to, dt * fade_k)
	for i in 3:
		_layer_vol[i] = move_toward(_layer_vol[i], 1.0 if i == intensity else 0.0, dt * 2.5)
		var v: float = _layer_vol[i] * _fade * meta.music["%s_%d" % [style, i]].get("gain", 1.0)
		_layers[i].volume_db = linear_to_db(maxf(0.00001, v))
	if _fade <= 0.0 and _fade_to <= 0.0:
		for p in _layers: p.stop()
		style = ""
