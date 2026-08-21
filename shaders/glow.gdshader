shader_type canvas_item;
render_mode blend_add;

uniform vec2 rect_size = vec2(0.26, 0.10);
uniform float bness : hint_range(0.0, 5.0) = 1.3;
uniform float fall_off_scale : hint_range(0.1, 10.0) = 1.8;
uniform float b_offset : hint_range(0.0, 2.0) = 0.42;

// Vibrant Riot Red Gradient
uniform vec4 glow_color : source_color = vec4(1.0, 0.04, 0.14, 1.0);
uniform vec4 glow_color_secondary : source_color = vec4(0.85, 0.0, 0.28, 1.0);

uniform float pulse_speed : hint_range(0.0, 10.0) = 2.0;
uniform float pulse_amount : hint_range(0.0, 0.5) = 0.08;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	
	// Closest point in core card box
	vec2 closest_point = uv;
	closest_point.x = clamp(uv.x, -rect_size.x, rect_size.x);
	closest_point.y = clamp(uv.y, -rect_size.y, rect_size.y);
	
	vec2 diff = uv - closest_point;
	float d = length(diff);
	
	// Smooth photographic logarithmic diffusion
	float intensity = -log(clamp(d * fall_off_scale + b_offset, 0.001, 1.0)) * bness;
	intensity = max(intensity, 0.0);
	
	// Subtle breathing pulse
	float pulse = 1.0 + sin(TIME * pulse_speed) * pulse_amount;
	
	// Smooth vibrant red gradient
	float grad_t = clamp(UV.x + sin(TIME * 1.2 + UV.y * 1.5) * 0.15, 0.0, 1.0);
	vec4 col = mix(glow_color, glow_color_secondary, grad_t);
	
	COLOR = vec4(col.rgb, intensity * pulse * col.a);
}
