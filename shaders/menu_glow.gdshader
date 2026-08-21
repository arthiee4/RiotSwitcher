shader_type canvas_item;
render_mode blend_add;

uniform vec2 rect_size = vec2(0.02, 0.10);
uniform float bness : hint_range(0.0, 5.0) = 1.5;
uniform float fall_off_scale : hint_range(0.1, 10.0) = 1.6;
uniform float b_offset : hint_range(0.0, 2.0) = 0.35;
uniform vec4 glow_color : source_color = vec4(1.0, 0.04, 0.14, 1.0);

void fragment() {
	vec2 uv = UV - vec2(0.5);
	vec2 closest_point = uv;
	closest_point.x = clamp(uv.x, -rect_size.x, rect_size.x);
	closest_point.y = clamp(uv.y, -rect_size.y, rect_size.y);
	
	vec2 diff = uv - closest_point;
	float d = length(diff);
	
	float intensity = -log(clamp(d * fall_off_scale + b_offset, 0.001, 1.0)) * bness;
	intensity = max(intensity, 0.0);
	
	COLOR = vec4(glow_color.rgb, intensity * glow_color.a);
}
