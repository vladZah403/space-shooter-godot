// Небо и туманность сектора: вертикальный градиент неба + два слоя облаков (шум fbm), которые плывут вниз
// с разной скоростью, и тёмные пылевые прожилки. Замена холстов makeSky/makeNebula из JS-версии.
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

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(sky_top, sky_bot, smoothstep(0.0, 0.55, uv.y));
	// слой 1: крупные мягкие облака двух цветов
	vec2 p1 = vec2(uv.x * aspect, uv.y - scroll1) * 1.6 + vec2(seed * 3.7, seed * 1.3);
	float n1 = fbm(p1);
	float m1 = fbm(p1 * 0.6 + vec2(4.2, 1.7));
	float c1 = smoothstep(0.42, 0.85, n1);
	vec3 neb = mix(neb0, neb1, smoothstep(0.35, 0.7, m1)) * c1 * 0.34;
	// слой 2: мельче, быстрее, третий цвет
	if (layers > 1.5) {
		vec2 p2 = vec2(uv.x * aspect, uv.y - scroll2) * 3.1 + vec2(seed * 5.1 + 11.0, seed * 2.9);
		float n2 = fbm(p2);
		neb += neb2 * smoothstep(0.5, 0.9, n2) * 0.22;
	}
	// тёмные пылевые прожилки
	float dust = fbm(vec2(uv.x * aspect, uv.y - scroll1) * 2.4 + vec2(seed + 31.0, 7.0));
	neb *= 1.0 - 0.6 * smoothstep(0.5, 0.75, dust);
	COLOR = vec4(col + neb * glow, COLOR.a);
}
