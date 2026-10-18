shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(0.2, 1.0, 0.0, 1.0);
uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
uniform float glow_radius : hint_range(1.0, 4.0) = 4.0;
// 图集裁切后的有效帧；相邻帧和已排除的留白不得参与高亮采样。
uniform vec4 source_region = vec4(0.0, 0.0, 1.0, 1.0);

varying vec4 canvas_modulate;

void vertex() {
	canvas_modulate = COLOR;
}

vec3 frame_sample_point(vec2 point, vec2 pixel_size) {
	vec2 minimum = source_region.xy;
	vec2 maximum = minimum + source_region.zw;
	float inside = step(minimum.x, point.x) * step(point.x, maximum.x)
		* step(minimum.y, point.y) * step(point.y, maximum.y);
	return vec3(clamp(point, minimum + pixel_size * 0.5,
		maximum - pixel_size * 0.5), inside);
}

void fragment() {
	vec3 center = frame_sample_point(UV, TEXTURE_PIXEL_SIZE);
	vec4 base = texture(TEXTURE, center.xy) * center.z;
	vec2 pixel = TEXTURE_PIXEL_SIZE * glow_radius;
	float nearby_alpha = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec3 neighbor = frame_sample_point(UV + vec2(float(x), float(y)) * pixel, TEXTURE_PIXEL_SIZE);
			nearby_alpha = max(nearby_alpha, texture(TEXTURE, neighbor.xy).a * neighbor.z);
		}
	}

	float halo = max(0.0, nearby_alpha - base.a) * hover_amount;
	float body_light = base.a * hover_amount * 0.22;
	vec3 highlighted = base.rgb + glow_color.rgb * (halo + body_light);
	float highlighted_alpha = max(base.a, halo * 0.85);
	COLOR = vec4(highlighted, highlighted_alpha) * canvas_modulate;
}
