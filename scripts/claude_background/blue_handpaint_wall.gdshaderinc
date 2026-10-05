vec3 hp_wall(vec3 original, vec3 pos, vec3 normal) {
	vec3 an = abs(normal);
	vec2 uv = an.y >= max(an.x, an.z) ? pos.xz / 2.0 :
		(an.x > an.z ? vec2(pos.z, -pos.y) : vec2(pos.x, -pos.y)) / 2.0;
	vec3 brush = clamp(hp_sample(uv) / max(paint_mean, vec3(0.001)), vec3(0.58), vec3(1.55));
	float l = dot(original, vec3(0.2126, 0.7152, 0.0722));
	// Retain actual atlas inset/fastener/bevel shading, without replacing UV islands.
	float plate = smoothstep(0.13, 0.23, l);
	float top = smoothstep(0.35, 0.80, normal.y);
	vec3 base = mix(vec3(0.065, 0.073, 0.145), vec3(0.245, 0.275, 0.385), plate);
	base = mix(base, vec3(0.31, 0.34, 0.46), top * 0.70);
	float structure = clamp(l / mix(0.092, 0.25, plate), 0.30, 1.65);
	structure = mix(1.0, structure, 0.72);
	vec3 col = base * brush * structure;
	float chip = smoothstep(0.025, 0.075, original.r - original.g) *
		smoothstep(-0.055, 0.015, original.r - original.b);
	return mix(col, vec3(0.23, 0.17, 0.20) * brush, chip * 0.55);
}
