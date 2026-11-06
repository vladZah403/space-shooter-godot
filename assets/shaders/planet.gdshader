// Планета сектора: шар с освещением слева сверху, полосы облаков, терминатор (тень справа снизу) и атмосфера.
// Квадрат рисунка — радиус планеты R плюс поля 0,7·R (как холст makePlanet в JS). Цвет — тон hue (0..1).
shader_type canvas_item;

uniform float hue = 0.58;
uniform float seed = 0.0;
uniform float pad = 1.7;       // половина стороны квадрата в радиусах планеты

vec3 hsl(float h, float s, float l) {
	vec3 rgb = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return l + s * (rgb - 0.5) * (1.0 - abs(2.0 * l - 1.0));
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 q = (UV - 0.5) * 2.0 * pad;   // в радиусах планеты
	float r = length(q);
	vec4 outc = vec4(0.0);
	// атмосфера: кольцо свечения от 0,9 до 1,35 R
	float atm = (1.0 - smoothstep(0.9, 1.35, r)) * smoothstep(0.6, 1.0, r) * 0.35;
	outc = vec4(hsl(hue, 0.9, 0.65), atm);
	if (r < 1.0) {
		// тело: радиальный градиент из точки (−0,4; −0,4)
		float g = clamp(length(q - vec2(-0.4, -0.4)) / 1.5, 0.0, 1.0);
		vec3 c = g < 0.5 ? mix(hsl(hue, 0.55, 0.62), hsl(hue + 12.0 / 360.0, 0.5, 0.36), g * 2.0)
			: mix(hsl(hue + 12.0 / 360.0, 0.5, 0.36), hsl(hue + 20.0 / 360.0, 0.45, 0.10), (g - 0.5) * 2.0);
		// полосы облаков: 9 полос, светлые и тёмные через одну, с волнистым краем
		float y = q.y + (noise(vec2(q.x * 3.0, q.y * 2.0) + seed) - 0.5) * 0.12;
		float band = floor((y + 1.0) * 4.5);
		vec3 bandc = mod(band, 2.0) < 1.0 ? hsl(hue + 30.0 / 360.0, 0.4, 0.2) : hsl(hue - 10.0 / 360.0, 0.6, 0.75);
		c = mix(c, bandc, 0.16);
		// затемнение к краю диска, светлее всего чуть правее и ниже центра (как градиент тени в JS:
		// прозрачно у точки (0,55; 0,5), 0,25 — на 40%, 0,85 — у края)
		float t = clamp((length(q - vec2(0.42, 0.38)) - 0.2) / 1.3, 0.0, 1.0);
		float shade = t < 0.4 ? 0.25 * t / 0.4 : 0.25 + 0.6 * (t - 0.4) / 0.6;
		c *= 1.0 - shade;
		// мягкий край диска
		float edge = 1.0 - smoothstep(0.985, 1.0, r);
		outc = mix(outc, vec4(c, 1.0), edge);
	}
	COLOR = vec4(outc.rgb, outc.a * COLOR.a);
}
