class_name RingMeter
extends Control
## Fills a radial slice (pie) for ultimate / capture ring. 0 = empty, 1 = full turn.

@export var fill_ratio: float = 0.0:
	set(v):
		fill_ratio = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var fill_color: Color = Color(0.82, 0.72, 0.18, 0.95)
@export var track_color: Color = Color(0.12, 0.12, 0.14, 0.85)
@export var outline_color: Color = Color(0.35, 0.36, 0.4, 0.9)
@export var outline_width: float = 2.5
@export var pie_width_pixels: float = 6.0
## If false, the pie wedge grows counter-clockwise from the top (enemy capture read from local POV).
@export var fill_clockwise: bool = true:
	set(v):
		fill_clockwise = v
		queue_redraw()
## Objective ring: blue arc (ally) + orange arc (enemy) fill the whole donut — orange grows as enemies cap.
@export var dual_tone_capture: bool = false:
	set(v):
		dual_tone_capture = v
		queue_redraw()
## Fraction of the ring drawn as ally_arc_color from the top, clockwise; remainder is enemy_arc_color.
@export var ally_arc_fraction: float = 1.0:
	set(v):
		ally_arc_fraction = clampf(v, 0.0, 1.0)
		queue_redraw()
@export var ally_arc_color: Color = Color(0.160784, 0.705882, 1.0, 0.95)
@export var enemy_arc_color: Color = Color(0.96, 0.55, 0.18, 0.95)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r_outer: float = minf(size.x, size.y) * 0.5 - outline_width * 0.5
	if r_outer < 2.0:
		return
	var r_inner: float = maxf(r_outer - pie_width_pixels, r_outer * 0.55)

	draw_arc(c, (r_inner + r_outer) * 0.5, 0.0, TAU, 72, track_color, pie_width_pixels, true)

	if dual_tone_capture:
		var arc0: float = -PI * 0.5
		var ally_end: float = arc0 + TAU * ally_arc_fraction
		_draw_donut_arc(c, r_inner, r_outer, arc0, ally_end, ally_arc_color)
		_draw_donut_arc(c, r_inner, r_outer, ally_end, arc0 + TAU, enemy_arc_color)
	else:
		if fill_ratio > 0.001:
			var arc_start: float = -PI * 0.5
			var arc_end: float = arc_start + (TAU * fill_ratio if fill_clockwise else -TAU * fill_ratio)
			var steps: int = maxi(3, int(48.0 * fill_ratio))
			for i in range(steps):
				var t0: float = lerpf(arc_start, arc_end, float(i) / float(steps))
				var t1: float = lerpf(arc_start, arc_end, float(i + 1) / float(steps))
				var p0i: Vector2 = c + Vector2(cos(t0), sin(t0)) * r_inner
				var p0o: Vector2 = c + Vector2(cos(t0), sin(t0)) * r_outer
				var p1o: Vector2 = c + Vector2(cos(t1), sin(t1)) * r_outer
				var p1i: Vector2 = c + Vector2(cos(t1), sin(t1)) * r_inner
				draw_colored_polygon(PackedVector2Array([p0i, p0o, p1o, p1i]), fill_color)

	draw_arc(c, r_outer, 0.0, TAU, 72, outline_color, outline_width, false)


func _draw_donut_arc(
	c: Vector2,
	r_inner: float,
	r_outer: float,
	from_angle: float,
	to_angle: float,
	col: Color,
) -> void:
	var span: float = to_angle - from_angle
	if span <= 0.0001:
		return
	var frac: float = clampf(span / TAU, 0.0, 1.0)
	var steps: int = maxi(3, int(48.0 * frac))
	for i in range(steps):
		var t0: float = lerpf(from_angle, to_angle, float(i) / float(steps))
		var t1: float = lerpf(from_angle, to_angle, float(i + 1) / float(steps))
		var p0i: Vector2 = c + Vector2(cos(t0), sin(t0)) * r_inner
		var p0o: Vector2 = c + Vector2(cos(t0), sin(t0)) * r_outer
		var p1o: Vector2 = c + Vector2(cos(t1), sin(t1)) * r_outer
		var p1i: Vector2 = c + Vector2(cos(t1), sin(t1)) * r_inner
		draw_colored_polygon(PackedVector2Array([p0i, p0o, p1o, p1i]), col)
