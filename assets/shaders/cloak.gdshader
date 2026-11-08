shader_type canvas_item;
// Маскировка Невидимки (Godot): спрятанный корабль виден только дрожащим стеклянным контуром — блестят края
// силуэта, по ним бежит отблеск. Видимость 0…1 приходит в альфе цвета вершины (Ctx: tint): 0 — один контур,
// 1 — корабль целиком (проявился, чтобы выстрелить, или его подбили).

varying float vis;

void vertex() {
	vis = COLOR.a;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 ps = TEXTURE_PIXEL_SIZE * 1.5;
	float nb = texture(TEXTURE, UV + vec2(ps.x, 0.0)).a + texture(TEXTURE, UV - vec2(ps.x, 0.0)).a
		+ texture(TEXTURE, UV + vec2(0.0, ps.y)).a + texture(TEXTURE, UV - vec2(0.0, ps.y)).a;
	float edge = clamp(c.a * 4.0 - nb, 0.0, 1.0);   // край: сам непрозрачен, а сосед — нет
	float sweep = 0.5 + 0.5 * sin(UV.y / TEXTURE_PIXEL_SIZE.y * 0.08 - TIME * 6.0);
	float ea = edge * (0.18 + 0.45 * sweep * sweep) + c.a * 0.03;
	vec3 glass = vec3(0.72, 0.86, 1.0);
	COLOR = vec4(mix(glass, c.rgb, vis), mix(ea, c.a, vis));
}
