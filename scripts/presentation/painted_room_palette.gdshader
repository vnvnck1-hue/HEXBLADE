shader_type spatial;
render_mode diffuse_burley, specular_disabled;

uniform sampler2D artwork : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float saturation : hint_range(0.0, 1.0) = 0.18;
uniform float brightness : hint_range(0.0, 1.0) = 0.22;

void fragment() {
	vec3 paint = texture(artwork, UV).rgb;
	float value = dot(paint, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = mix(vec3(value), paint, saturation) * brightness;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
