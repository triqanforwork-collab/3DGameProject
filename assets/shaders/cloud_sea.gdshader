shader_type spatial;
// Biển mây: mặt phẳng được đẩy phồng theo noise (trôi chậm), đỉnh mây trắng, chỗ trũng xanh xám.
// Pháp tuyến tính lại từ noise để ánh nắng đổ lên từng cụm mây.

uniform sampler2D noise_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 top_color : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 shade_color : source_color = vec3(0.66, 0.72, 0.86);
uniform float scale = 0.012;
uniform float speed = 0.004;
uniform float puff_height = 4.0;

varying vec2 cloud_uv;

float height_at(vec2 uv) {
	return textureLod(noise_tex, uv, 0.0).r * 0.7 + textureLod(noise_tex, uv * 2.7 + 0.31, 0.0).r * 0.3;
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	cloud_uv = wp.xz * scale + vec2(TIME * speed, TIME * speed * 0.4);
	VERTEX.y += height_at(cloud_uv) * puff_height;
}

void fragment() {
	float e = 0.004;
	float h = height_at(cloud_uv);
	float hx = height_at(cloud_uv + vec2(e, 0.0));
	float hz = height_at(cloud_uv + vec2(0.0, e));
	// Độ dốc theo mét: (chênh cao * puff_height) / (e / scale).
	float k = puff_height * scale / e;
	vec3 n_world = normalize(vec3((h - hx) * k, 1.0, (h - hz) * k));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	ALBEDO = mix(shade_color, top_color, smoothstep(0.3, 0.75, h));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
