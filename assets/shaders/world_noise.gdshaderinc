// Lấy mẫu noise theo toạ độ thế giới (triplanar): không cần UV, mặt đứng không bị kéo dãn.
// p: vị trí thế giới đã nhân tỉ lệ, n: pháp tuyến thế giới.
float triplanar(sampler2D tex, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= w.x + w.y + w.z;
	return texture(tex, p.zy).r * w.x + texture(tex, p.xz).r * w.y + texture(tex, p.xy).r * w.z;
}
