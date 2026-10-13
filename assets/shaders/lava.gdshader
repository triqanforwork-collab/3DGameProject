shader_type spatial;
// Dung nham: vỏ đá nguội trôi chậm, khe nứt + vũng nóng phát sáng theo nhịp.
// Dùng cho biển dung nham (pool_level cao) và đá núi lửa (pool_level thấp, chỉ còn khe nứt).

#include "res://assets/shaders/world_noise.gdshaderinc"

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 crust_color : source_color = vec3(0.1, 0.045, 0.035);
uniform vec3 hot_color : source_color = vec3(1.0, 0.36, 0.06);
uniform vec3 core_color : source_color = vec3(1.0, 0.82, 0.35);
uniform float scale = 0.03;
uniform float flow_speed = 0.006;
// Noise thấp hơn mức này thành vũng dung nham (0 = không có vũng).
uniform float pool_level : hint_range(0.0, 1.0) = 0.42;
uniform float crack_width : hint_range(0.0, 0.2) = 0.035;
uniform float glow = 3.0;
// Sóng lăn tăn trên mặt (m); 0 = phẳng (dùng cho đá).
uniform float wave_height = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (wave_height > 0.0) {
		float w = sin(world_pos.x * 0.13 + TIME * 0.5) * cos(world_pos.z * 0.11 + TIME * 0.37);
		VERTEX.y += w * wave_height;
	}
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 drift = vec3(1.0, 0.0, 0.6) * TIME * flow_speed;
	vec3 p = world_pos * scale;
	float n1 = triplanar(noise_tex, p + drift, world_normal);
	float n2 = triplanar(noise_tex, p * 2.3 - drift * 1.7, world_normal);
	float n = n1 * 0.65 + n2 * 0.35;

	float pool = 1.0 - smoothstep(pool_level - 0.05, pool_level + 0.05, n);
	float crack = 1.0 - smoothstep(0.0, crack_width, abs(n2 - 0.5));
	float heat = max(pool, crack * 0.85);
	float pulse = 0.8 + 0.2 * sin(TIME * 1.8 + n1 * 12.0);

	ALBEDO = mix(crust_color, hot_color * 0.4, heat);
	ROUGHNESS = mix(0.95, 0.5, heat);
	EMISSION = mix(hot_color, core_color, heat * heat) * heat * glow * pulse;
}
