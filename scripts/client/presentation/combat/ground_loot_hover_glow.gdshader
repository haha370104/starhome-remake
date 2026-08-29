shader_type canvas_item;
render_mode unshaded;

uniform vec4 glow_color : source_color = vec4(0.2, 1.0, 0.0, 1.0);
uniform float glow_radius : hint_range(1.0, 8.0, 1.0) = 4.0;
uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;

const float TAU_VALUE = 6.28318530718;


void vertex() {
	VERTEX += (UV * 2.0 - vec2(1.0)) * glow_radius;
}


void fragment() {
	vec2 source_size = vec2(1.0) / TEXTURE_PIXEL_SIZE;
	vec2 source_pixel = UV * (source_size + vec2(glow_radius * 2.0)) - vec2(glow_radius);
	vec2 source_uv = source_pixel * TEXTURE_PIXEL_SIZE;
	float source_inside = (
		step(0.0, source_uv.x)
		* step(source_uv.x, 1.0)
		* step(0.0, source_uv.y)
		* step(source_uv.y, 1.0)
	);
	vec4 base_color = texture(TEXTURE, clamp(source_uv, vec2(0.0), vec2(1.0))) * source_inside;
	float blurred_alpha = 0.0;
	for (int ring = 1; ring <= 4; ring++) {
		float radius = float(ring);
		float radial_weight = 1.0 - radius / (glow_radius + 1.0);
		for (int direction = 0; direction < 16; direction++) {
			float angle = TAU_VALUE * float(direction) / 16.0;
			vec2 sample_uv = source_uv + vec2(cos(angle), sin(angle)) * radius * TEXTURE_PIXEL_SIZE;
			float sample_inside = (
				step(0.0, sample_uv.x)
				* step(sample_uv.x, 1.0)
				* step(0.0, sample_uv.y)
				* step(sample_uv.y, 1.0)
			);
			float sample_alpha = texture(
				TEXTURE,
				clamp(sample_uv, vec2(0.0), vec2(1.0))
			).a * sample_inside;
			blurred_alpha = max(blurred_alpha, sample_alpha * radial_weight);
		}
	}
	float halo_alpha = max(blurred_alpha - base_color.a, 0.0) * hover_amount;
	float body_light = base_color.a * hover_amount * 0.16;
	vec3 rendered_rgb = base_color.rgb + glow_color.rgb * (halo_alpha + body_light);
	float rendered_alpha = max(base_color.a, halo_alpha * glow_color.a);
	COLOR = vec4(rendered_rgb, rendered_alpha) * COLOR;
}
