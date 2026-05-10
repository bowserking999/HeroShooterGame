shader_type spatial;
/* Vertex COLOR is filled in heal_beam.gd (works reliably on gl_compatibility where uniforms + albedo often read wrong).
 * If the beam still looks white: open the Godot Output / debugger for shader compile errors, or try project rendering_method forward_plus briefly to compare. */
render_mode blend_mix, cull_disabled, unshaded, shadows_disabled;

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = COLOR.a;
}
