shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(0.2, 1.0, 0.0, 1.0);
uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;

varying vec4 canvas_modulate;

void vertex() {
	canvas_modulate = COLOR;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	vec2 pixel = TEXTURE_PIXEL_SIZE * 4.0;
	float nearby_alpha = 0.0;
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(pixel.x, 0.0)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV - vec2(pixel.x, 0.0)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(0.0, pixel.y)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV - vec2(0.0, pixel.y)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + pixel).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV - pixel).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(pixel.x, -pixel.y)).a);
	nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(-pixel.x, pixel.y)).a);

	float halo = max(0.0, nearby_alpha - base.a) * hover_amount;
	float body_light = base.a * hover_amount * 0.22;
	vec3 highlighted = base.rgb + glow_color.rgb * (halo + body_light);
	float highlighted_alpha = max(base.a, halo * 0.85);
	COLOR = vec4(highlighted, highlighted_alpha) * canvas_modulate;
}
