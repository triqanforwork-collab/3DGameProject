shader_type spatial;
// Băng: lớp sâu xanh đậm / mặt băng sáng theo noise, vân nứt trắng, viền sáng theo góc nhìn (fresnel).

#include "res://assets/shaders/world_noise.gdshaderinc"

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.22, 0.45, 0.74);
uniform vec3 surface_color : source_color = vec3(0.78, 0.89, 1.0);
uniform vec3 rim_color : source_color = vec3(0.88, 0.96, 1.0);
uniform float scale = 0.05;
uniform float crack_width : hint_range(0.0, 0.2) = 0.03;
uniform float rim_power = 3.0;
uniform float rim_strength = 0.6;
// Phát sáng nền nhẹ để băng trông như có ánh sáng xuyên qua.
uniform float inner_glow = 0.12;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 p = world_pos * scale;
	float n = triplanar(noise_tex, p, world_normal);
	float n2 = triplanar(noise_tex, p * 3.1 + 0.37, world_normal);

	vec3 col = mix(deep_color, surface_color, smoothstep(0.35, 0.68, n));
	float crack = 1.0 - smoothstep(0.0, crack_width, abs(n2 - 0.5));
	col = mix(col, rim_color, crack * 0.85);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = col;
	ROUGHNESS = mix(0.12, 0.6, crack);
	SPECULAR = 0.7;
	EMISSION = rim_color * fres * rim_strength + col * inner_glow;
}
