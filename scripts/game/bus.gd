extends Node
## Шина событий (автозагрузка Bus) — SS.on / SS.off / SS.emit из core.js: модули общаются без жёстких связей.
## Bus.on("bossSpawn", func(b): ...) — подписка; Bus.emit("bossSpawn", b) — событие (до трёх аргументов).
## Ошибка в одном подписчике не мешает остальным (в GDScript она и так не прерывает цикл).

var _listeners := {}


func on(evt: String, fn: Callable) -> Callable:
	_listeners.get_or_add(evt, []).append(fn)
	return fn


func off(evt: String, fn: Callable) -> void:
	var l: Array = _listeners.get(evt, [])
	l.erase(fn)


func emit(evt: String, a = null, b = null, c = null) -> void:
	var l: Array = _listeners.get(evt, [])
	if l.is_empty(): return
	for fn: Callable in l.duplicate():
		if not fn.is_valid(): continue
		var n := fn.get_argument_count()
		match n:
			0: fn.call()
			1: fn.call(a)
			2: fn.call(a, b)
			_: fn.call(a, b, c)
