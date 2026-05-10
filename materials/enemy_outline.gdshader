shader_type spatial;
render_mode blend_add, depth_draw_always, cull_disabled, unshaded;

uniform vec4 outline_color : source_color = vec4(1.0, 0.32, 0.28, 1.0);
uniform float rim_power : hint_range(0.5, 16.0, 0.1) = 2.35;
uniform float rim_broad_power : hint_range(0.5, 8.0, 0.1) = 1.15;
uniform float rim_intensity : hint_range(0.0, 4.0, 0.05) = 1.65;
uniform float rim_broad_mix : hint_range(0.0, 1.0, 0.05) = 0.42;
uniform float emission_boost : hint_range(0.0, 6.0, 0.05) = 3.2;

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndotv = clamp(abs(dot(n, v)), 0.0, 1.0);
	float t = 1.0 - ndotv;
	float rim_edge = pow(t, rim_power);
	float rim_wide = pow(t, rim_broad_power);
	float rim = clamp(rim_edge * rim_intensity + rim_wide * rim_broad_mix, 0.0, 1.0);
	vec3 glow = outline_color.rgb * rim * emission_boost;
	EMISSION = glow;
	ALBEDO = outline_color.rgb * rim * 0.35;
	ALPHA = rim;
}
