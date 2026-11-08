// Небо и туманность сектора: вертикальный градиент неба + два слоя облаков (шум fbm), которые плывут вниз
// с разной скоростью, и тёмные пылевые прожилки. Замена холстов makeSky/makeNebula из JS-версии.
// Godot: у каждого сектора своя живая деталь фона (style, по механике сектора — Bg.STYLES):
//  1 полярное сияние (Орбита Земли)   2 пылевые потоки (Пояс астероидов)   3 светящиеся облака и столпы (Орион)
//  4 ледяные искры и туман (Луны)      5 жар и протуберанцы (Красный гигант) 6 споры (Изумрудные поля)
//  7 вихрь-линза (Горизонт событий)    8 спиральные рукава (Сердце галактики) 9 радужные каустики (Кристальный пояс)
//  10 соты (Улей)                      11 огненные трещины (Пустошь хаоса)   12 лучи сверху (Цитадель)
//  13 глаз в небе (Трон Оверлорда)
shader_type canvas_item;

uniform vec3 sky_top : source_color = vec3(0.02, 0.06, 0.23);
uniform vec3 sky_bot : source_color = vec3(0.01, 0.02, 0.05);
uniform vec3 neb0 : source_color = vec3(0.12, 0.3, 1.0);
uniform vec3 neb1 : source_color = vec3(0.24, 0.88, 1.0);
uniform vec3 neb2 : source_color = vec3(0.48, 0.24, 1.0);
uniform float scroll1 = 0.0;   // смещение слоя 1 в долях высоты экрана
uniform float scroll2 = 0.0;
uniform float aspect = 0.46;   // ширина / высота экрана
uniform float seed = 0.0;
uniform float layers = 2.0;    // 1 — только крупный слой (низкое качество)
uniform float glow = 1.0;      // яркость туманности
uniform int style = 0;         // живая деталь сектора (см. выше); 0 — без неё

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return v;
}

// мерцающие точки на сетке: искры, споры, пыль
float sparks(vec2 p, float cell, float t, float density) {
	vec2 g = floor(p / cell);
	vec2 f = fract(p / cell) - 0.5;
	float h = hash(g + seed);
	if (h > density) return 0.0;
	vec2 o = vec2(hash(g + 3.1), hash(g + 7.7)) - 0.5;
	float d = length(f - o * 0.6);
	float tw = 0.5 + 0.5 * sin(t * (2.0 + h * 5.0) + h * 40.0);
	return smoothstep(0.12, 0.0, d) * tw;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	vec2 sp = vec2(uv.x * aspect, uv.y);   // экранные координаты с правильными пропорциями
	// вихрь у горизонта событий: картинка закручивается вокруг точки над полем
	if (style == 7) {
		vec2 c = vec2(0.5 * aspect, 0.22);
		vec2 d = sp - c;
		float r = length(d);
		float a = 0.9 / (r * 6.0 + 0.4) + t * 0.12;
		float cs = cos(a);
		float sn = sin(a);
		sp = c + vec2(d.x * cs - d.y * sn, d.x * sn + d.y * cs);
		uv = vec2(sp.x / aspect, sp.y);
	}
	vec3 col = mix(sky_top, sky_bot, smoothstep(0.0, 0.55, uv.y));
	// слой 1: крупные мягкие облака двух цветов
	vec2 p1 = vec2(uv.x * aspect, uv.y - scroll1) * 1.6 + vec2(seed * 3.7, seed * 1.3);
	if (style == 3) p1 += vec2(sin(t * 0.07), cos(t * 0.05)) * 0.3;   // облака Ориона медленно клубятся
	float n1 = fbm(p1);
	float m1 = fbm(p1 * 0.6 + vec2(4.2, 1.7));
	float c1 = smoothstep(0.42, 0.85, n1);
	vec3 neb = mix(neb0, neb1, smoothstep(0.35, 0.7, m1)) * c1 * (style == 3 ? 0.5 : 0.34);
	// слой 2: мельче, быстрее, третий цвет
	if (layers > 1.5) {
		vec2 p2 = vec2(uv.x * aspect, uv.y - scroll2) * 3.1 + vec2(seed * 5.1 + 11.0, seed * 2.9);
		float n2 = fbm(p2);
		neb += neb2 * smoothstep(0.5, 0.9, n2) * 0.22;
	}
	// тёмные пылевые прожилки
	float dust = fbm(vec2(uv.x * aspect, uv.y - scroll1) * 2.4 + vec2(seed + 31.0, 7.0));
	neb *= 1.0 - 0.6 * smoothstep(0.5, 0.75, dust);
	vec3 add = vec3(0.0);
	float yl = uv.y - scroll1;   // координата, плывущая вместе с облаками
	if (style == 1) {
		// полярное сияние: колышущиеся занавесы у верха экрана
		float w = sin(sp.x * 9.0 + fbm(vec2(sp.x * 2.0, t * 0.15)) * 6.0 + t * 0.4);
		float curtain = pow(0.5 + 0.5 * w, 6.0) * smoothstep(0.55, 0.05, uv.y) * smoothstep(0.0, 0.12, uv.y);
		add += mix(neb1, vec3(0.3, 1.0, 0.6), 0.5) * curtain * 0.35;
	} else if (style == 2) {
		// пылевые потоки: косые полосы и летящая крошка
		vec2 q = vec2(sp.x * 0.8 + yl * 0.5, yl * 3.0);
		float lane = smoothstep(0.55, 0.8, fbm(vec2(q.x * 1.5, q.y * 0.4) + seed));
		add += neb0 * lane * 0.18;
		add += vec3(1.0, 0.8, 0.6) * sparks(vec2(sp.x - t * 0.02, yl) * 900.0, 14.0, t, 0.25) * 0.45;
	} else if (style == 3) {
		// тёмные столпы пыли снизу (как «Столпы творения»)
		float pil = fbm(vec2(sp.x * 5.0, uv.y * 1.2) + seed * 2.0);
		float shape = smoothstep(0.62, 0.48, pil + (1.0 - uv.y) * 0.55);
		col = mix(col, col * 0.25, shape * 0.85);
		neb *= 1.0 - shape * 0.7;
	} else if (style == 4) {
		// ледяные искры и холодный туман внизу
		add += vec3(0.75, 0.95, 1.0) * sparks(vec2(sp.x, yl) * 900.0, 18.0, t, 0.35) * 0.7;
		add += neb1 * smoothstep(0.55, 1.0, uv.y) * fbm(vec2(sp.x * 3.0 + t * 0.03, uv.y * 2.0)) * 0.18;
	} else if (style == 5) {
		// жар снизу и протуберанцы
		float heat = smoothstep(0.45, 1.0, uv.y) * (0.6 + 0.4 * fbm(vec2(sp.x * 4.0, uv.y * 3.0 - t * 0.4)));
		add += vec3(1.0, 0.35, 0.1) * heat * 0.28;
		float fl = pow(fbm(vec2(atan(uv.y + 0.2, uv.x - 0.15) * 4.0, t * 0.1)), 4.0) * smoothstep(0.7, 0.0, length(sp - vec2(0.12, -0.1)));
		add += vec3(1.0, 0.55, 0.2) * fl * 0.6;
	} else if (style == 6) {
		// светящиеся споры плывут вверх
		add += vec3(0.4, 1.0, 0.6) * sparks(vec2(sp.x + sin(uv.y * 8.0 + t) * 0.01, uv.y + t * 0.03) * 700.0, 22.0, t, 0.3) * 0.6;
		add += neb0 * smoothstep(0.6, 0.9, fbm(sp * 2.5 + vec2(0.0, -t * 0.04))) * 0.1;
	} else if (style == 7) {
		// яркое кольцо вокруг вихря
		float r = length(vec2(UV.x * aspect, UV.y) - vec2(0.5 * aspect, 0.22));
		add += mix(neb1, vec3(1.0, 0.8, 0.5), 0.4) * smoothstep(0.05, 0.0, abs(r - 0.075)) * 0.45;
		col *= smoothstep(0.03, 0.07, r);
	} else if (style == 8) {
		// спиральные рукава галактики, медленно вращаются
		vec2 c = vec2(0.5 * aspect, 0.18);
		vec2 d = sp - c;
		float r = length(d);
		float a = atan(d.y, d.x);
		float arm = 0.5 + 0.5 * cos(2.0 * a - log(r + 0.02) * 5.0 - t * 0.15);
		add += mix(neb0, vec3(1.0, 0.9, 0.7), 0.4) * pow(arm, 4.0) * smoothstep(0.6, 0.05, r) * 0.35;
		add += vec3(1.0, 0.9, 0.7) * smoothstep(0.08, 0.0, r) * 0.6;
	} else if (style == 9) {
		// радужные каустики, как свет сквозь кристалл
		float cau = abs(sin(sp.x * 22.0 + fbm(sp * 3.0 + t * 0.1) * 8.0)) * abs(sin(yl * 18.0 + fbm(sp * 2.5 - t * 0.08) * 7.0));
		vec3 rb = 0.5 + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + sp.x * 1.5 + t * 0.05));
		add += rb * pow(1.0 - cau, 16.0) * 0.12;
	} else if (style == 10) {
		// соты Улья: тонкие стенки и бегущая по ним волна
		vec2 h = vec2(sp.x, yl) * 18.0;
		vec2 r2 = vec2(1.0, 1.732);
		vec2 a = mod(h, r2) - r2 * 0.5;
		vec2 b = mod(h - r2 * 0.5, r2) - r2 * 0.5;
		vec2 g = dot(a, a) < dot(b, b) ? a : b;
		float edge = smoothstep(0.42, 0.5, max(abs(g.x) * 0.866 + abs(g.y) * 0.5, abs(g.y)));
		float pulse = 0.5 + 0.5 * sin(length(sp - vec2(0.5 * aspect, 0.4)) * 20.0 - t * 2.0);
		add += neb0 * edge * (0.015 + 0.07 * pow(pulse, 3.0));
	} else if (style == 11) {
		// огненные трещины Хаоса — мерцают
		float cr = abs(fbm(vec2(sp.x * 3.0, yl * 3.0) + seed) - 0.5);
		float line = smoothstep(0.025, 0.0, cr);
		add += vec3(1.0, 0.45, 0.1) * line * (0.4 + 0.6 * noise(vec2(t * 3.0, sp.x * 10.0))) * 0.5;
	} else if (style == 12) {
		// лучи света сверху
		vec2 o = vec2(0.5 * aspect, -0.15);
		vec2 d = sp - o;
		float a = atan(d.x, d.y);
		float ray = pow(fbm(vec2(a * 9.0, t * 0.08)), 3.0) * 2.0;
		add += mix(neb2, vec3(1.0, 0.95, 0.8), 0.6) * ray * smoothstep(1.0, 0.1, uv.y) * 0.3;
	} else if (style == 13) {
		// глаз в небе: радужка пульсирует и поворачивается
		vec2 c = vec2(0.5 * aspect, 0.16);
		vec2 d = (sp - c) * vec2(1.0, 1.8);
		float r = length(d);
		float a = atan(d.y, d.x);
		float iris = smoothstep(0.17, 0.15, r) * (0.6 + 0.4 * sin(a * 24.0 + t * 0.6));
		float pupil = smoothstep(0.045 + 0.01 * sin(t * 1.3), 0.035, r);
		add += mix(neb0, neb1, 0.5) * iris * 0.22;
		col *= 1.0 - pupil * 0.9;
		add += neb1 * smoothstep(0.012, 0.0, abs(r - 0.17)) * 0.4;
	}
	COLOR = vec4(col + (neb + add) * glow, COLOR.a);
}
