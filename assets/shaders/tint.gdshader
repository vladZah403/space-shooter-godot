shader_type canvas_item;
// Перекраска кадра атласа на видеокарте (G.tinted / G.white в scripts/core/gfx.gd): один раз рисуется
// в свой SubViewport, дальше это обычная текстура. Формулы — те же, что в JS (режимы смешивания
// Canvas 'hue' / 'saturation' / 'multiply' / 'screen'), раньше считались на процессоре по пикселям.
// blend_disabled — пишем цвет и прозрачность как есть, без домножения на альфу при наложении.
render_mode blend_disabled, unshaded;

uniform bool hue_on = false;
uniform vec3 hc = vec3(1.0);
uniform float sat = 0.0;
uniform float dark = 0.0;
uniform vec3 dk = vec3(1.0);
uniform float bright = 0.0;
uniform bool add = false;
uniform bool keep_a = false;
uniform bool white = false;

float lum(vec3 c) {
	return 0.3 * c.r + 0.59 * c.g + 0.11 * c.b;
}

vec3 clip_col(vec3 c) {
	float l = lum(c);
	float n = min(c.r, min(c.g, c.b));
	float x = max(c.r, max(c.g, c.b));
	vec3 r = c;
	if (n < 0.0) {
		r = vec3(l) + (c - vec3(l)) * l / (l - n);
	}
	if (x > 1.0) {
		r = vec3(l) + (r - vec3(l)) * (1.0 - l) / (x - l);
	}
	return r;
}

vec3 set_lum(vec3 c, float l) {
	return clip_col(c + vec3(l - lum(c)));
}

vec3 set_sat(vec3 c, float s) {
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	if (mx - mn <= 0.0) {
		return vec3(0.0);
	}
	return (c - vec3(mn)) * (s / (mx - mn));
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float a = c.a;
	if (white) {
		COLOR = vec4(1.0, 1.0, 1.0, a);
	} else {
		bool opaque = add && !keep_a;
		vec3 rgb = opaque ? c.rgb * a : c.rgb;
		if (hue_on) {
			float mx = max(rgb.r, max(rgb.g, rgb.b));
			float mn = min(rgb.r, min(rgb.g, rgb.b));
			rgb = set_lum(set_sat(hc, mx - mn), lum(rgb));
		}
		if (sat != 0.0) {
			rgb = set_lum(set_sat(rgb, sat), lum(rgb));
		}
		if (dark > 0.0) {
			rgb *= dk;
		}
		if (bright > 0.0) {
			rgb = vec3(1.0) - (vec3(1.0) - rgb) * (1.0 - bright);
		}
		COLOR = vec4(rgb, opaque ? 1.0 : a);
	}
}
