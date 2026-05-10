extends Control
## Fills the RingMeter “hole” with a solid disc matching `RingMeter` geometry (use for black base and semi-transparent charge overlay).

@export var pie_width_pixels: float = 8.0
@export var outline_width: float = 3.2
@export var fill_color: Color = Color.BLACK


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r_outer: float = minf(size.x, size.y) * 0.5 - outline_width * 0.5
	if r_outer < 2.0:
		return
	var r_inner: float = maxf(r_outer - pie_width_pixels, r_outer * 0.55)
	draw_circle(c, r_inner, fill_color)
