extends Node
## Вибрация (автозагрузка Haptic) — SS.tg.haptic из tg.js. В Telegram были «удары» HapticFeedback, здесь —
## Input.vibrate_handheld (Android, iOS, мобильный браузер) с той же силой, что navigator.vibrate в JS.
## Haptic.light() / medium() / heavy() / select() / success() / warning() / error(); выключается в настройках.

const MS := {"light": 8, "select": 6, "soft": 10, "medium": 18, "rigid": 22, "heavy": 35}
## сила импульса 0..1 (Android 8+; в браузере и на iOS игнорируется) — лёгкие касания мягче, удары жёстче
const AMP := {"light": 0.3, "select": 0.25, "soft": 0.35, "medium": 0.6, "rigid": 0.75, "heavy": 1.0}
## уведомления и удары — серии: [импульс, пауза, импульс, …], сила по импульсам
const PAT := {"success": [12, 40, 12], "warning": [20, 60, 20], "error": [40, 50, 40], "boom": [70, 50, 110, 60, 160]}
const PAT_AMP := {"success": [0.5, 0.7], "warning": [0.7, 0.7], "error": [0.9, 0.9], "boom": [1.0, 0.75, 0.45]}

var _last := -1000


func vibrate(kind: String) -> void:
	var st = M.s.get("settings") if M.s else null
	if st and not st.get("vibro", true): return
	var now := Time.get_ticks_msec()
	if kind == "light" and now - _last < 60: return
	_last = now
	if not (OS.has_feature("mobile") or OS.has_feature("web")): return
	if PAT.has(kind):
		var p: Array = PAT[kind]
		var amp: Array = PAT_AMP.get(kind, [])
		var at := 0
		for i in range(0, p.size(), 2):
			var ms: int = p[i]
			var a: float = amp[i >> 1] if (i >> 1) < amp.size() else -1.0
			if at == 0: Input.vibrate_handheld(ms, a)
			else: get_tree().create_timer(at / 1000.0).timeout.connect(func(): Input.vibrate_handheld(ms, a))
			at += ms + (p[i + 1] if i + 1 < p.size() else 0)
	else:
		Input.vibrate_handheld(MS.get(kind, 10), AMP.get(kind, -1.0))


func light() -> void: vibrate("light")
func select() -> void: vibrate("select")
func medium() -> void: vibrate("medium")
func heavy() -> void: vibrate("heavy")
func success() -> void: vibrate("success")
func warning() -> void: vibrate("warning")
func error() -> void: vibrate("error")
func boom() -> void: vibrate("boom")
