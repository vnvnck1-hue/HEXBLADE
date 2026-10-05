shader_type canvas_item;
render_mode unshaded;
uniform sampler2D panel_mask : filter_linear, repeat_disable;
void fragment() {
	// CanvasItem fragment COLOR already contains TEXTURE and node modulate.
	COLOR.a *= texture(panel_mask, UV).a;
}
