extends Node3D

@export var expand_to: float = 2.2
@export var expand_time: float = 0.08
@export var contract_to: float = 0.3
@export var contract_time: float = 0.12

func _ready() -> void:
	scale = Vector3.ONE * contract_to
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * expand_to, expand_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE * contract_to, contract_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)

