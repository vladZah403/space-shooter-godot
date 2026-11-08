shader_type canvas_item;
// Логотип: металлический вертикальный градиент по буквам и бегущий по диагонали блик (scripts/ui/logo.gd).
// Координаты — локальные точки надписи (VERTEX), поэтому градиент идёт по всей строке, а не по каждой букве.
uniform vec4 c_top : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 c_mid : source_color = vec4(0.78, 0.86, 1.0, 1.0);
uniform vec4 c_bot : source_color = vec4(0.42, 0.58, 0.95, 1.0);
uniform float y0 = 0.0;       // верх букв в точках надписи
uniform float h = 50.0;       // высота букв
uniform float w = 300.0;      // ширина строки
uniform float shine = -1.0;   // 0…1 — где сейчас блик (меньше 0 — нет)
varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float t = clamp((lp.y - y0) / h, 0.0, 1.0);
	vec3 g = t < 0.5 ? mix(c_top.rgb, c_mid.rgb, t * 2.0) : mix(c_mid.rgb, c_bot.rgb, (t - 0.5) * 2.0);
	// тонкая светлая полоса посередине — «грань» металла
	g += vec3(0.25) * smoothstep(0.06, 0.0, abs(t - 0.52));
	if (shine >= 0.0) {
		float pos = shine * (w + h * 2.0) - h;
		float d = abs((lp.x + (lp.y - y0) * 0.7) - pos);
		g += vec3(0.9) * smoothstep(h * 0.35, 0.0, d);
	}
	COLOR.rgb *= g;
}
