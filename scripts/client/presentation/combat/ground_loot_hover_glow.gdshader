shader_type canvas_item;
render_mode unshaded;

uniform vec4 glow_color : source_color = vec4(0.2, 1.0, 0.0, 1.0);
uniform float glow_radius : hint_range(1.0, 8.0, 1.0) = 4.0;
uniform float hover_amount : hint_range(0.0, 1.0) = 0.0;
// 图集内当前 ALE 帧的归一化区域，普通独立图片使用完整区域。
uniform vec4 source_region = vec4(0.0, 0.0, 1.0, 1.0);
varying vec4 vertex_tint;

const float TAU_VALUE = 6.28318530718;


void vertex() {
	vertex_tint = COLOR;
	vec2 frame_uv = (UV - source_region.xy) / source_region.zw;
	VERTEX += (frame_uv * 2.0 - vec2(1.0)) * glow_radius;
}


void fragment() {
	vec2 source_size = source_region.zw / TEXTURE_PIXEL_SIZE;
	vec2 frame_uv = (UV - source_region.xy) / source_region.zw;
	vec2 source_pixel = frame_uv * (source_size + vec2(glow_radius * 2.0)) - vec2(glow_radius);
	vec2 source_uv = source_pixel / source_size;
	vec2 sample_min = source_region.xy + TEXTURE_PIXEL_SIZE * 0.5;
	vec2 sample_max = source_region.xy + source_region.zw - TEXTURE_PIXEL_SIZE * 0.5;
	float source_inside = (
		step(0.0, source_uv.x)
		* step(source_uv.x, 1.0)
		* step(0.0, source_uv.y)
		* step(source_uv.y, 1.0)
	);
	vec4 base_color = texture(TEXTURE, clamp(source_region.xy + source_uv * source_region.zw, sample_min, sample_max)) * source_inside;
	float blurred_alpha = 0.0;
	for (int ring = 1; ring <= 4; ring++) {
		float radius = float(ring);
		float radial_weight = 1.0 - radius / (glow_radius + 1.0);
		for (int direction = 0; direction < 16; direction++) {
			float angle = TAU_VALUE * float(direction) / 16.0;
			vec2 sample_uv = source_uv + vec2(cos(angle), sin(angle)) * radius / source_size;
			float sample_inside = (
				step(0.0, sample_uv.x)
				* step(sample_uv.x, 1.0)
				* step(0.0, sample_uv.y)
				* step(sample_uv.y, 1.0)
			);
			float sample_alpha = texture(
				TEXTURE,
				clamp(source_region.xy + sample_uv * source_region.zw, sample_min, sample_max)
			).a * sample_inside;
			blurred_alpha = max(blurred_alpha, sample_alpha * radial_weight);
		}
	}
	float halo_alpha = max(blurred_alpha - base_color.a, 0.0) * hover_amount;
	float body_light = base_color.a * hover_amount * 0.16;
	vec3 rendered_rgb = base_color.rgb + glow_color.rgb * (halo_alpha + body_light);
	float rendered_alpha = max(base_color.a, halo_alpha * glow_color.a);
	// fragment 的 COLOR 已含一次贴图采样，不能再次相乘，否则 RGB/alpha 都会被平方。
	COLOR = vec4(rendered_rgb, rendered_alpha) * vertex_tint;
}
