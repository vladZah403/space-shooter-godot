// Постобработка поля боя (слой между миром и интерфейсом, scripts/game/post.gd):
// ударные волны от взрывов, линзы-воронки чёрных дыр, хроматическая аберрация при попадании,
// пузыри щитов (преломление у кромки, светящийся край, рябь от удара), радиальный «форсаж» при прыжке в сектор, мягкое свечение ярких мест (bloom по мип-уровням экрана),
// размытие игры под окнами (пауза, выбор, итоги) и цветокоррекция (последняя жизнь, заморозка, замедление).
// Все расстояния — в долях высоты экрана (по x домножаем на aspect = W/H, чтобы круги были круглыми).

// Godot: копия экрана с мип-уровнями нужна только свечению и размытию — их строит видеокарта каждый кадр, это дорого.
// post.gdshader (POST_MIPS) — полный вариант, post_lite.gdshader — без мип-уровней: волны, воронки, аберрация, щиты
// post_tex.gdshader (POST_TEX) — шейдер на картинке мира (world.gd: wview): читает её TEXTURE, без копии экрана
#ifdef POST_TEX
#define SRC TEXTURE
#define SUV UV
#else
#define SRC screen_tex
#define SUV SCREEN_UV
#ifdef POST_MIPS
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
#else
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
#endif
#endif
uniform float aspect = 0.46;
uniform vec4 waves[6];      // x, y (UV), радиус, сила
uniform int wave_n = 0;
uniform vec4 lenses[6];     // x, y (UV), радиус, сила (закрутка + вытягивание)
uniform int lens_n = 0;
uniform vec4 bubbles[4];    // x, y (UV), радиус, сила преломления
uniform vec4 bubble_col[4]; // цвет кромки, удар 0…1
uniform int bubble_n = 0;
uniform float aberr = 0.0;
uniform float bloom = 0.0;
uniform float bloom_thr = 0.3;
uniform float warp = 0.0;
uniform vec2 warp_c = vec2(0.5, 0.42);
uniform float blur = 0.0;
uniform float sat = 1.0;
uniform vec3 grade = vec3(1.0);

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

void fragment() {
	vec2 uv = SUV;
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
	// пузыри щитов: у кромки картинка стягивается к центру (выпуклое стекло), по краю бежит рябь от удара
	vec3 rim_glow = vec3(0.0);
	for (int i = 0; i < bubble_n; i++) {
		vec4 b = bubbles[i];
		vec4 bc = bubble_col[i];
		vec2 d = (uv - b.xy) * asp;
		float dist = length(d);
		float x = dist / b.z;
		if (b.w < 0.0) {
			// марево маскировки (Невидимка): картинка дрожит внутри силуэта, без кромки и свечения
			float m = 1.0 - smoothstep(0.4, 1.0, x);
			vec2 wv = vec2(sin(d.y * 150.0 + TIME * 11.0), cos(d.x * 150.0 + TIME * 9.0));
			off += wv / asp * m * (-b.w) * 0.0035;
			ca += m * (-b.w) * 0.002;
			continue;
		}
		if (x < 1.15 && dist > 0.0001) {
			float rim = smoothstep(0.55, 1.0, x) * (1.0 - smoothstep(1.0, 1.15, x));
			float wob = sin(x * 26.0 - TIME * 24.0 + atan(d.y, d.x) * 3.0) * bc.a * smoothstep(0.2, 1.0, x);
			off -= (d / dist) / asp * b.z * b.w * (rim * 0.16 + wob * 0.05);
			ca += rim * b.w * 0.003;
			float edge = pow(smoothstep(0.82, 1.0, x), 3.0) * (1.0 - smoothstep(1.0, 1.06, x));
			rim_glow += bc.rgb * (edge * (0.22 + bc.a * 0.6) + rim * bc.a * 0.15) * min(b.w, 1.0);
		}
	}
	vec2 suv = clamp(uv + off, vec2(0.0), vec2(1.0));
	vec3 col;
	if (ca > 0.0004) {
		vec2 cd = (suv - vec2(0.5)) * ca * 2.0;
		col.r = textureLod(SRC, suv + cd, 0.0).r;
		col.g = textureLod(SRC, suv, 0.0).g;
		col.b = textureLod(SRC, suv - cd, 0.0).b;
	} else {
		col = textureLod(SRC, suv, 0.0).rgb;
	}
	col += rim_glow;
	// форсаж: размытие по лучам к точке прыжка
	if (warp > 0.005) {
		// шаги со случайным сдвигом на пиксель — вместо «лесенки» копий получается гладкий шлейф
		float j = fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
		vec2 wd = (warp_c - suv) * warp * 0.03;
		vec3 acc = col;
		for (int k = 1; k <= 8; k++) {
			acc += textureLod(SRC, suv + wd * (float(k) - j), 0.0).rgb;
		}
		col = acc / 9.0;
	}
#ifdef POST_MIPS
	// свечение: размытые мип-уровни, только яркое (мягкий порог)
	if (bloom > 0.0) {
		vec3 b = textureLod(SRC, suv, 1.2).rgb * 0.4
			+ textureLod(SRC, suv, 2.5).rgb * 0.4
			+ textureLod(SRC, suv, 4.0).rgb * 0.3
			+ textureLod(SRC, suv, 5.5).rgb * 0.2;
		b = max(b - vec3(bloom_thr), vec3(0.0));
		col += b * b * bloom * 3.0;
	}
	if (blur > 0.0) {
		vec3 bl = textureLod(SRC, suv, 2.5).rgb * 0.6 + textureLod(SRC, suv, 3.5).rgb * 0.4;
		col = mix(col, bl, blur);
	}
#endif
	if (sat < 0.999 || grade != vec3(1.0)) {
		float l = dot(col, vec3(0.3, 0.59, 0.11));
		col = mix(vec3(l), col, sat) * grade;
	}
	COLOR = vec4(col, 1.0);
}
