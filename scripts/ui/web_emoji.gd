class_name WebEmoji
## Цветные эмодзи в браузере. Godot в вебе не видит системных шрифтов, поэтому значки-эмодзи рисует сам
## браузер — на айфоне это Apple Color Emoji, на Android — Noto Color Emoji, в Windows — Segoe UI Emoji,
## то есть ровно те же картинки, что были в JS-версии. Рисуем их на скрытом холсте, забираем пиксели и
## собираем растровый шрифт (FontFile без файла, глиф = код символа). Kit.font ставит его первым запасным
## после Exo 2; дальше — контурный Noto Emoji для всего остального.
## Символы, которые браузер рисует цветом текста (●, ★, ←, ✓), пропускаем: их, как и раньше, рисует
## Noto Emoji цветом надписи. Список значков — data/emoji.json (собирает tools/emoji_list.py).

const LIST := "res://data/emoji.json"
const UPEM := 2048   # единиц на кегль в собранном шрифте

## JS: рисует значки, проверяет «цветной ли» (красной и синей заливкой — у эмодзи картинка не меняется),
## складывает цветные в атлас; пиксели атласа оставляет в window.__ssEmoji, метрики возвращает строкой JSON
const JS := """
(function (list, px) {
	const font = px + 'px "Apple Color Emoji","Segoe UI Emoji","Noto Color Emoji","Twemoji Mozilla",sans-serif';
	const pad = Math.ceil(px * 0.12), by = Math.ceil(px * 1.05), ch = Math.ceil(px * 1.45);
	const probe = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
	probe.canvas.width = px * 2 + pad * 2; probe.canvas.height = ch;
	probe.font = font; probe.textBaseline = 'alphabetic';
	const ink = (s, col) => {
		probe.clearRect(0, 0, probe.canvas.width, ch);
		probe.fillStyle = col; probe.fillText(s, pad, by);
		return probe.getImageData(0, 0, probe.canvas.width, ch).data;
	};
	const ok = [], skip = [];
	let cw = 0;
	for (const s of list) {
		const a = ink(s, '#ff0000'), b = ink(s, '#0000ff');
		let n = 0, diff = 0;
		for (let i = 0; i < a.length; i += 4) {
			if (a[i + 3] < 8) continue;
			n++;
			if (Math.abs(a[i] - b[i]) > 48 || Math.abs(a[i + 2] - b[i + 2]) > 48) diff++;
		}
		if (n < px || diff > n * 0.25) { skip.push(s); continue; }   // пусто или рисуется цветом текста
		const w = probe.measureText(s).width;
		ok.push([s, w]);
		cw = Math.max(cw, Math.ceil(w));
	}
	cw += pad * 2;
	const cols = Math.max(1, Math.min(ok.length, Math.floor(2048 / cw)));
	const rows = Math.ceil(ok.length / cols);
	const cv = document.createElement('canvas');
	cv.width = Math.max(1, cols * cw); cv.height = Math.max(1, rows * ch);
	const cx = cv.getContext('2d', { willReadFrequently: true });
	cx.font = font; cx.textBaseline = 'alphabetic'; cx.fillStyle = '#ffffff';
	const glyphs = ok.map(([s, w], i) => {
		const x = (i % cols) * cw, y = Math.floor(i / cols) * ch;
		cx.fillText(s, x + pad, y + by);
		return { cp: s.codePointAt(0), adv: w, x, y };
	});
	window.__ssEmoji = new Uint8Array(cx.getImageData(0, 0, cv.width, cv.height).data.buffer);
	return JSON.stringify({ w: cv.width, h: cv.height, cw, ch, pad, by, glyphs, skipped: skip.join(' ') });
})(__LIST__, __PX__)
"""


## растровый шрифт из эмодзи браузера; null — не в браузере или что-то пошло не так (тогда останется Noto Emoji)
static func build() -> FontFile:
	if not OS.has_feature("web"): return null
	var f := FileAccess.open(LIST, FileAccess.READ)
	if f == null: return null
	var list = JSON.parse_string(f.get_as_text())
	if not (list is Array) or list.is_empty(): return null
	# размер глифа — под настоящий размер на экране: на айфоне интерфейс увеличен почти втрое
	var win := DisplayServer.window_get_size()
	var k := minf(win.x / 390.0, win.y / 844.0)
	var px := clampi(int(26 * k), 32, 72)
	var t0 := Time.get_ticks_msec()
	var raw = JavaScriptBridge.eval(JS.replace("__LIST__", JSON.stringify(list)).replace("__PX__", str(px)), true)
	if not (raw is String): return null
	var meta = JSON.parse_string(raw)
	if not (meta is Dictionary) or meta.glyphs.is_empty(): return null
	var bytes = JavaScriptBridge.eval("window.__ssEmoji", true)
	if not (bytes is PackedByteArray):
		# запасной путь, если браузер не отдал массив байтов напрямую — base64 кусками
		var b64 = JavaScriptBridge.eval("(function(u){let s='';for(let i=0;i<u.length;i+=32768)s+=String.fromCharCode.apply(null,u.subarray(i,i+32768));return btoa(s);})(window.__ssEmoji)", true)
		if b64 is String: bytes = Marshalls.base64_to_raw(b64)
	JavaScriptBridge.eval("delete window.__ssEmoji", true)
	var w := int(meta.w)
	var h := int(meta.h)
	if not (bytes is PackedByteArray) or bytes.size() != w * h * 4: return null
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)
	var font := make_font(img, meta.glyphs, px, int(meta.cw), int(meta.ch), int(meta.pad), int(meta.by))
	print("[emoji] цветных значков из браузера: %d, %d px, атлас %d×%d, %d мс; цветом текста: %s" % [
		meta.glyphs.size(), px, w, h, Time.get_ticks_msec() - t0, meta.skipped])
	return font


## Шрифт из картинок: настоящий файл OpenType с цветными растровыми глифами (таблицы CBDT/CBLC, PNG — так
## устроен Noto Color Emoji). Собранный вручную FontFile без файла не годится: Godot умножает цветной глиф на
## цвет надписи, если у шрифта нет FreeType-«лица» (на синей кнопке эмодзи становились тёмными).
## atlas — картинки в ячейках cw×ch; glyphs — [{cp, adv, x, y}]; pad — отступ рисунка слева в ячейке,
## by — где в ячейке базовая линия; px — размер шрифта, под который нарисованы картинки
static func make_font(atlas: Image, glyphs: Array, px: int, cw: int, ch: int, pad: int, by: int) -> FontFile:
	var list := glyphs.duplicate()
	list.sort_custom(func(a, b): return int(a.cp) < int(b.cp))
	var n := list.size()
	var asc := roundi(px * 0.86)
	var desc := roundi(px * 0.24)
	var u := func(v: float) -> int: return roundi(v * UPEM / px)
	# CBDT: формат 17 — короткие метрики + PNG; картинку обрезаем по рисунку
	var cbdt := _be()
	cbdt.put_u16(3); cbdt.put_u16(0)
	var offs: Array[int] = []
	var advs: Array[int] = []
	var max_adv := 0
	for g in list:
		offs.append(cbdt.get_position() - 4)
		var cell := atlas.get_region(Rect2i(int(g.x), int(g.y), cw, ch))
		var r := cell.get_used_rect()
		if r.size.x <= 0 or r.size.y <= 0: r = Rect2i(0, 0, 1, 1)
		var png := cell.get_region(r).save_png_to_buffer()
		var adv := clampi(roundi(float(g.adv)), 1, 255)
		advs.append(adv)
		max_adv = maxi(max_adv, adv)
		cbdt.put_u8(r.size.y); cbdt.put_u8(r.size.x)
		cbdt.put_8(r.position.x - pad); cbdt.put_8(by - r.position.y)
		cbdt.put_u8(adv)
		cbdt.put_u32(png.size()); cbdt.put_data(png)
	offs.append(cbdt.get_position() - 4)
	# CBLC: один размер (px), глифы 1..n, индекс формата 1 (смещения в CBDT)
	var cblc := _be()
	cblc.put_u16(3); cblc.put_u16(0); cblc.put_u32(1)
	cblc.put_u32(8 + 48); cblc.put_u32(8 + 8 + 4 * (n + 1)); cblc.put_u32(1); cblc.put_u32(0)
	for i in 2:   # линии строки: по горизонтали и по вертикали (одинаковые)
		cblc.put_8(asc); cblc.put_8(-desc); cblc.put_u8(mini(max_adv, 255)); cblc.put_8(1); cblc.put_8(0); cblc.put_8(0)
		cblc.put_8(0); cblc.put_8(0); cblc.put_8(asc); cblc.put_8(-desc); cblc.put_8(0); cblc.put_8(0)
	cblc.put_u16(1); cblc.put_u16(n); cblc.put_u8(px); cblc.put_u8(px); cblc.put_u8(32); cblc.put_8(1)
	cblc.put_u16(1); cblc.put_u16(n); cblc.put_u32(8)
	cblc.put_u16(1); cblc.put_u16(17); cblc.put_u32(4)
	for o in offs: cblc.put_u32(o)
	# cmap: Юникод (3, 10), формат 12 — по группе на символ
	var cmap := _be()
	cmap.put_u16(0); cmap.put_u16(1); cmap.put_u16(3); cmap.put_u16(10); cmap.put_u32(12)
	cmap.put_u16(12); cmap.put_u16(0); cmap.put_u32(16 + 12 * n); cmap.put_u32(0); cmap.put_u32(n)
	for i in n:
		var cp := int(list[i].cp)
		cmap.put_u32(cp); cmap.put_u32(cp); cmap.put_u32(i + 1)
	var head := _be()
	head.put_u32(0x00010000); head.put_u32(0x00010000); head.put_u32(0); head.put_u32(0x5F0F3CF5)
	head.put_u16(0x000B); head.put_u16(UPEM); head.put_64(0); head.put_64(0)
	head.put_16(0); head.put_16(-u.call(desc)); head.put_16(u.call(max_adv)); head.put_16(u.call(asc))
	head.put_u16(0); head.put_u16(8); head.put_16(2); head.put_16(0); head.put_16(0)
	var hhea := _be()
	hhea.put_u32(0x00010000); hhea.put_16(u.call(asc)); hhea.put_16(-u.call(desc)); hhea.put_16(0)
	hhea.put_u16(u.call(max_adv)); hhea.put_16(0); hhea.put_16(0); hhea.put_16(u.call(max_adv))
	hhea.put_16(1); hhea.put_16(0); hhea.put_16(0)
	for i in 4: hhea.put_16(0)
	hhea.put_16(0); hhea.put_u16(n + 1)
	var hmtx := _be()
	hmtx.put_u16(u.call(px)); hmtx.put_16(0)   # .notdef
	for a in advs: hmtx.put_u16(u.call(a)); hmtx.put_16(0)
	var maxp := _be()
	maxp.put_u32(0x00005000); maxp.put_u16(n + 1)
	var nm := _be()
	var names := [[1, "SS Emoji"], [2, "Regular"], [4, "SS Emoji"]]
	nm.put_u16(0); nm.put_u16(names.size()); nm.put_u16(6 + 12 * names.size())
	var str_off := 0
	for it in names:
		nm.put_u16(3); nm.put_u16(1); nm.put_u16(0x409); nm.put_u16(it[0])
		nm.put_u16(it[1].length() * 2); nm.put_u16(str_off)
		str_off += it[1].length() * 2
	for it in names:
		for c in it[1]: nm.put_u16(c.unicode_at(0))
	var post := _be()
	post.put_u32(0x00030000); post.put_u32(0); post.put_16(-u.call(desc) / 2); post.put_16(u.call(1))
	for i in 5: post.put_u32(0)
	# каталог таблиц (теги по алфавиту, каждая таблица выровнена на 4 байта)
	var tables := [["CBDT", cbdt], ["CBLC", cblc], ["cmap", cmap], ["head", head], ["hhea", hhea],
		["hmtx", hmtx], ["maxp", maxp], ["name", nm], ["post", post]]
	var nt := tables.size()
	var sr := 16
	var es := 0
	while sr * 2 <= nt * 16: sr *= 2; es += 1
	var out := _be()
	out.put_u32(0x00010000); out.put_u16(nt); out.put_u16(sr); out.put_u16(es); out.put_u16(nt * 16 - sr)
	var pos := 12 + 16 * nt
	var blobs: Array[PackedByteArray] = []
	for t in tables:
		var data: PackedByteArray = (t[1] as StreamPeerBuffer).data_array
		var padded := data.duplicate()
		while padded.size() % 4 != 0: padded.append(0)
		out.put_data(t[0].to_ascii_buffer()); out.put_u32(_checksum(padded)); out.put_u32(pos); out.put_u32(data.size())
		pos += padded.size()
		blobs.append(padded)
	for b in blobs: out.put_data(b)
	var font := FontFile.new()
	font.data = out.data_array
	font.fixed_size = px
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	font.allow_system_fallback = false
	font.generate_mipmaps = true   # в интерфейсе значки обычно мельче, чем нарисованы
	# в шрифте нет таблиц, по которым Godot узнаёт письменности; без этого строку из одного эмодзи
	# (письменность Zsye) он отдаёт контурному Noto Emoji
	for scr in ["Zsye", "Zsym", "Zyyy", "Zinh"]: font.set_script_support_override(scr, true)
	return font


static func _be() -> StreamPeerBuffer:
	var b := StreamPeerBuffer.new()
	b.big_endian = true
	return b


static func _checksum(d: PackedByteArray) -> int:
	var s := 0
	for i in range(0, d.size(), 4):
		s = (s + (d[i] << 24 | d[i + 1] << 16 | d[i + 2] << 8 | d[i + 3])) & 0xFFFFFFFF
	return s
