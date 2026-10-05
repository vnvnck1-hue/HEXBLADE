uniform bool handpaint = false;
uniform sampler2D paint_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 paint_mean = vec3(0.2);

// Overlapping half-size samples agree in value and slope at each repeat boundary.
// Explicit gradients avoid incorrect mip selection where fract() wraps.
vec3 hp_sample(vec2 uv) {
	vec2 p = fract(uv);
	vec2 w = smoothstep(vec2(0.0), vec2(1.0), p);
	vec2 dx = dFdx(uv) * 0.5;
	vec2 dy = dFdy(uv) * 0.5;
	vec2 a = p * 0.5 + vec2(0.25);
	vec3 tl = textureGrad(paint_tex, a, dx, dy).rgb;
	vec3 tr = textureGrad(paint_tex, a - vec2(0.5, 0.0), dx, dy).rgb;
	vec3 bl = textureGrad(paint_tex, a - vec2(0.0, 0.5), dx, dy).rgb;
	vec3 br = textureGrad(paint_tex, a - vec2(0.5), dx, dy).rgb;
	return mix(mix(tl, tr, w.x), mix(bl, br, w.x), w.y);
}
