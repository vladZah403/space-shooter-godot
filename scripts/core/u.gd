class_name U
extends RefCounted
## Утилиты — перенос SS.util из JS-версии (core.js). Случайность идёт через U.random(): на время
## испытания дня её подменяет детерминированный генератор (U.with_rng), как Math.random в JS.

const TAU_ := TAU

static var _rng_stack: Array[Callable] = []


static func random() -> float:
	if _rng_stack.is_empty():
		return randf()
	return _rng_stack.back().call()


## выполнить fn с подменённым генератором (rng — Callable, возвращающий 0..1; null — обычная случайность)
static func with_rng(rng, fn: Callable) -> Variant:
	if rng == null:
		return fn.call()
	_rng_stack.push_back(rng)
	var r = fn.call()
	_rng_stack.pop_back()
	return r


static func clamp(v: float, a: float, b: float) -> float:
	return a if v < a else (b if v > b else v)


static func lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


static func inv_lerp(a: float, b: float, v: float) -> float:
	return (v - a) / (b - a)


static func rand(a := 0.0, b := 1.0) -> float:
	return a + random() * (b - a)


static func randi(a: int, b: int) -> int:
	return int(floor(a + random() * (b - a + 1)))


static func chance(p: float) -> bool:
	return random() < p


static func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[int(random() * arr.size())]


static func sign(v: float) -> float:
	return -1.0 if v < 0.0 else 1.0


static func dist(ax: float, ay: float, bx: float, by: float) -> float:
	return sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))


static func dist2(ax: float, ay: float, bx: float, by: float) -> float:
	var dx := bx - ax
	var dy := by - ay
	return dx * dx + dy * dy


static func angle(ax: float, ay: float, bx: float, by: float) -> float:
	return atan2(by - ay, bx - ax)


static func approach(v: float, target: float, step: float) -> float:
	return minf(v + step, target) if v < target else maxf(v - step, target)


## экспоненциальное сглаживание, не зависящее от частоты кадров
static func damp(v: float, target: float, k: float, dt: float) -> float:
	return target + (v - target) * exp(-k * dt)


static func ease_out_cubic(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3)


static func ease_in_cubic(t: float) -> float:
	return t * t * t


static func ease_in_out(t: float) -> float:
	return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3) / 2.0


static func ease_out_back(t: float) -> float:
	var c1 := 1.70158
	var c3 := c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3) + c1 * pow(t - 1.0, 2)


static func angle_diff(a: float, b: float) -> float:
	var d := fmod(b - a, TAU)
	if d > PI:
		d -= TAU
	if d < -PI:
		d += TAU
	return d


## взвешенный случайный выбор: w(item) -> вес
static func pick_weighted(items: Array, w: Callable) -> Variant:
	var total := 0.0
	for it in items:
		total += maxf(0.0, w.call(it))
	if total <= 0.0:
		return items[0]
	var r := random() * total
	for it in items:
		r -= maxf(0.0, w.call(it))
		if r <= 0.0:
			return it
	return items.back()


static func shuffle(arr: Array) -> Array:
	for i in range(arr.size() - 1, 0, -1):
		var j := int(random() * (i + 1))
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
	return arr


## расстояние от точки до отрезка (квадрат) — для «стреловидных» столкновений
static func seg_dist2(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var dx := bx - ax
	var dy := by - ay
	var l2 := dx * dx + dy * dy
	var t := ((px - ax) * dx + (py - ay) * dy) / l2 if l2 > 0.0 else 0.0
	t = clampf(t, 0.0, 1.0)
	var cx := ax + dx * t - px
	var cy := ay + dy * t - py
	return cx * cx + cy * cy


## 12345 → «12 345»
static func fmt(n: float) -> String:
	var v := int(floor(n))
	var s := str(absi(v))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += " "
		out += s[i]
	return ("−" + out) if v < 0 else out


## компактно: 12.3К, 4.5М
static func fmt_short(n: float) -> String:
	var v := floorf(n)
	if v >= 1e6:
		return _trim_zero(("%.0f" if v >= 1e7 else "%.1f") % (v / 1e6)) + "М"
	if v >= 1e4:
		return _trim_zero(("%.0f" if v >= 1e5 else "%.1f") % (v / 1e3)) + "К"
	return fmt(v)


static func _trim_zero(s: String) -> String:
	return s.trim_suffix(".0")


static func fmt_time(sec: float) -> String:
	var s := int(maxf(0.0, floorf(sec)))
	var m := s / 60
	if m >= 60:
		return "%dч %dм" % [m / 60, m % 60]
	return "%d:%02d" % [m, s % 60]


## склонение: plural(5, "монета", "монеты", "монет")
static func plural(n: int, one: String, few: String, many: String) -> String:
	var v := absi(n) % 100
	var v1 := v % 10
	if v > 10 and v < 20:
		return many
	if v1 > 1 and v1 < 5:
		return few
	if v1 == 1:
		return one
	return many


static func today() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


## дата по UTC — одна и та же у всех игроков (испытание дня)
static func today_utc() -> String:
	var d := Time.get_date_dict_from_system(true)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


static func days_between(a: String, b: String) -> int:
	var ta := Time.get_unix_time_from_datetime_string(a + "T00:00:00")
	var tb := Time.get_unix_time_from_datetime_string(b + "T00:00:00")
	return int(round((tb - ta) / 86400.0))


## детерминированный генератор xorshift32, как в JS: возвращает Callable -> 0..1
static func seeded(seed: int) -> Callable:
	var st := [seed & 0xFFFFFFFF]
	if st[0] == 0:
		st[0] = 1
	return func() -> float:
		var s: int = st[0]
		s ^= (s << 13) & 0xFFFFFFFF
		s ^= s >> 17
		s ^= (s << 5) & 0xFFFFFFFF
		s &= 0xFFFFFFFF
		st[0] = s
		return float(s % 100000) / 100000.0


static func hash_str(s: String) -> int:
	var h := 2166136261
	for i in s.length():
		h ^= s.unicode_at(i)
		h = (h * 16777619) & 0xFFFFFFFF
	return h


## цвет '#rrggbb' с прозрачностью
static func col(hex: String, a := 1.0) -> Color:
	var c := Color.from_string(hex, Color.WHITE)
	c.a = a
	return c
