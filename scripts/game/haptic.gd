extends Node
## Вибрация (автозагрузка Haptic) — SS.tg.haptic из tg.js. В Telegram были «удары» HapticFeedback, здесь —
## Input.vibrate_handheld (Android, iOS, мобильный браузер) с той же силой, что navigator.vibrate в JS.
## Haptic.light() / medium() / heavy() / select() / success() / warning() / error(); выключается в настройках.

const MS := {"light": 8, "select": 6, "soft": 10, "medium": 18, "rigid": 22, "heavy": 35}
## уведомления — двойной импульс: [импульс, пауза, импульс]
const PAT := {"success": [12, 40, 12], "warning": [20, 60, 20], "error": [40, 50, 40]}

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
		Input.vibrate_handheld(p[0])
		get_tree().create_timer((p[0] + p[1]) / 1000.0).timeout.connect(func(): Input.vibrate_handheld(p[2]))
	else:
		Input.vibrate_handheld(MS.get(kind, 10))


func light() -> void: vibrate("light")
func select() -> void: vibrate("select")
func medium() -> void: vibrate("medium")
func heavy() -> void: vibrate("heavy")
func success() -> void: vibrate("success")
func warning() -> void: vibrate("warning")
func error() -> void: vibrate("error")
