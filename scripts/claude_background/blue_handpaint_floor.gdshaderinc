// Preserve the approved four-panel PNG without brush mixing or extra damage.
uniform bool floor_direct = false;
float hp_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
vec3 hp_floor(vec2 uv, vec3 pos, vec3 normal, vec2 phase) {
	if (floor_direct) {
		return textureGrad(paint_tex, uv, dFdx(uv), dFdy(uv)).rgb;
	}
	vec3 col = hp_sample(uv);
	if (abs(normal.y) >= 0.5) {
		vec2 g = (pos.xz - phase) / 2.0;
		vec2 tile = floor(g);
		vec2 local = fract(g);
		vec2 ed = min(local, 1.0 - local) * 2.0;
		float d = min(ed.x, ed.y);
		float aa = max(fwidth(d), 0.0008);
		float seam = 1.0 - smoothstep(0.012 - aa, 0.012 + aa, d);
		float lip = (1.0 - smoothstep(0.038 - aa, 0.038 + aa, d)) - seam;
		float h = hp_hash(tile);
		col *= mix(0.94, 1.06, h);
		// Selective brushed chips; calm centers and no bright outline on every tile.
		float grain = dot(col / max(paint_mean, vec3(0.001)), vec3(0.3333));
		float wear = smoothstep(1.025, 1.16, grain + sin(dot(pos.xz, vec2(3.9, 2.7))) * 0.10);
		wear *= (1.0 - smoothstep(0.03, 0.13, d)) * (0.35 + 0.65 * h);
		col = mix(col, vec3(0.29, 0.30, 0.40), wear * 0.45);
		col *= mix(1.0, 0.55, seam) * mix(1.0, 1.18, lip);
	} else {
		col *= 0.83;
	}
	return col;
}
