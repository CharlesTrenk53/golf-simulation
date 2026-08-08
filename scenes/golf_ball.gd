extends MeshInstance3D

@export var speed: float = 10.0

@onready var target: MeshInstance3D = $"../Target"


func _process(delta: float) -> void:
	global_position = global_position.move_toward(
		target.global_position,
		speed * delta
	)
