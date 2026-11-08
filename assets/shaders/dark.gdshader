shader_type canvas_item;
// Аномалия «Затмение» (Godot): тьма поверх фона и врагов — светлые круги только там, где есть свет:
// корабль, выстрелы, вражеские снаряды, взрывы (Game.drawDark). Пули и сам корабль рисуются поверх тьмы.
// Координаты огней — в пикселях прямоугольника тьмы (size).

uniform vec4 lights[20];    // x, y, радиус, сила
uniform int light_n = 0;
uniform vec2 size = vec2(390.0, 844.0);
uniform float dark = 0.0;

void fragment() {
	vec2 p = UV * size;
	float l = 0.0;
	for (int i = 0; i < light_n; i++) {
		vec4 L = lights[i];
		float d = length(p - L.xy) / L.z;
		if (d < 1.0) {
			float f = 1.0 - d * d;
			l += L.w * f * f;
		}
	}
	l = clamp(l, 0.0, 1.0);
	// у границы света — лёгкая синева, в глубине тьмы — почти чёрный
	COLOR = vec4(0.0, 0.012, 0.05, dark * (1.0 - l));
}
