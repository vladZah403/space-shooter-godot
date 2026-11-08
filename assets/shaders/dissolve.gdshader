shader_type canvas_item;
// Распад сбитого врага (E.burns): корпус выгорает пятнами по шуму, по кромке — раскалённый ободок,
// уцелевшее темнеет, как обугленное. Прогресс 0…1 приходит в альфе цвета вершины (Ctx: tint),
// картинка — кадр атласа или перекрашенный спрайт; шум берём по пикселям картинки, чтобы пятна были
// одного размера у любого кадра.

uniform sampler2D noise : filter_linear, repeat_enable;
uniform float cell = 110.0;  // размер пятна шума, пикселей картинки (спрайты рисуются в 3–4 раза мельче)

varying float prog;

void vertex() {
	prog = COLOR.a;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	float n = texture(noise, px / cell).r * 0.85 + texture(noise, px / (cell * 0.35) + 0.37).r * 0.15;
	n = clamp((n - 0.5) * 1.9 + 0.5, 0.0, 1.0);   // шум кучкуется у 0.5 — растягиваем на весь отрезок
	float p = prog * 1.12 - 0.04;
	float d = n - p;
	if (d < 0.0 || c.a < 0.02) {
		discard;
	}
	float e = 1.0 - smoothstep(0.0, 0.1, d);
	vec3 hot = mix(vec3(1.0, 0.96, 0.75), vec3(1.0, 0.42, 0.08), smoothstep(0.0, 0.06, d));
	vec3 base = c.rgb * (1.0 - min(prog * 1.6, 0.75));
	COLOR = vec4(mix(base, hot * 1.5, e), c.a);
}
