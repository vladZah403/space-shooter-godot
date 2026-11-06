shader_type canvas_item;
// Постобработка поля боя (слой между миром и интерфейсом, scripts/game/post.gd):
// ударные волны от взрывов, линзы-воронки чёрных дыр, хроматическая аберрация при попадании,
// радиальный «форсаж» при прыжке в сектор и мягкое свечение ярких мест (bloom по мип-уровням экрана).
// Все расстояния — в долях высоты экрана (по x домножаем на aspect = W/H, чтобы круги были круглыми).

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float aspect = 0.46;
uniform vec4 waves[6];      // x, y (UV), радиус, сила
uniform int wave_n = 0;
uniform vec4 lenses[6];     // x, y (UV), радиус, сила (закрутка + вытягивание)
uniform int lens_n = 0;
uniform float aberr = 0.0;
uniform float bloom = 0.0;
uniform float bloom_thr = 0.3;
uniform float warp = 0.0;
uniform vec2 warp_c = vec2(0.5, 0.42);

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 asp = vec2(aspect, 1.0);
	vec2 off = vec2(0.0);
	float ca = aberr;
	// ударные волны: кольцо-линза расходится от центра, на фронте картинка «выпучивается» и слегка двоится по цвету
	for (int i = 0; i < wave_n; i++) {
		vec4 w = waves[i];
		vec2 d = (uv - w.xy) * asp;
		float dist = length(d);
		float band = 0.045 + w.z * 0.14;
		float x = (dist - w.z) / band;
		if (abs(x) < 1.0 && dist > 0.0001) {
			float p = 1.0 - x * x;
			p *= p;
			off -= (d / dist) / asp * p * w.w * sign(x + 0.35);
			ca += p * w.w * 0.4;
		}
	}
	// воронки: кольцо искажения вокруг центра (сам центр не трогаем — там спрайт ядра), закрутка + втягивание
	for (int i = 0; i < lens_n; i++) {
		vec4 l = lenses[i];
		vec2 d = (uv - l.xy) * asp;
		float dist = length(d);
		float p = smoothstep(l.z * 0.4, l.z, dist) * (1.0 - smoothstep(l.z, l.z * 2.4, dist));
		if (p > 0.0) {
			vec2 nd = rot(d, l.w * p * 2.2);
			nd *= 1.0 - l.w * p * 0.35;
			off += (nd - d) / asp;
		}
	}
	vec2 suv = clamp(uv + off, vec2(0.0), vec2(1.0));
	vec3 col;
	if (ca > 0.0004) {
		vec2 cd = (suv - vec2(0.5)) * ca * 2.0;
		col.r = textureLod(screen_tex, suv + cd, 0.0).r;
		col.g = textureLod(screen_tex, suv, 0.0).g;
		col.b = textureLod(screen_tex, suv - cd, 0.0).b;
	} else {
		col = textureLod(screen_tex, suv, 0.0).rgb;
	}
	// форсаж: размытие по лучам к точке прыжка
	if (warp > 0.005) {
		// шаги со случайным сдвигом на пиксель — вместо «лесенки» копий получается гладкий шлейф
		float j = fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
		vec2 wd = (warp_c - suv) * warp * 0.03;
		vec3 acc = col;
		for (int k = 1; k <= 8; k++) {
			acc += textureLod(screen_tex, suv + wd * (float(k) - j), 0.0).rgb;
		}
		col = acc / 9.0;
	}
	// свечение: размытые мип-уровни, только яркое (мягкий порог)
	if (bloom > 0.0) {
		vec3 b = textureLod(screen_tex, suv, 1.2).rgb * 0.4
			+ textureLod(screen_tex, suv, 2.5).rgb * 0.4
			+ textureLod(screen_tex, suv, 4.0).rgb * 0.3
			+ textureLod(screen_tex, suv, 5.5).rgb * 0.2;
		b = max(b - vec3(bloom_thr), vec3(0.0));
		col += b * b * bloom * 3.0;
	}
	COLOR = vec4(col, 1.0);
}
