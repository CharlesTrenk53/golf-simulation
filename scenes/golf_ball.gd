extends MeshInstance3D

@export var speed: float = 10.0
@export var lateral_error: float = 4.0
@export var distance_error: float = 4.0

@onready var target: MeshInstance3D = $"../Target"

var shot_destination: Vector3


func _ready() -> void:
	randomize()

	var x_error = randf_range(-lateral_error, lateral_error)
	var z_error = randf_range(-distance_error, distance_error)

	shot_destination = target.global_position + Vector3(
		x_error,
		0.0,
		z_error
	)


func _process(delta: float) -> void:
	global_position = global_position.move_toward(
		shot_destination,
		speed * delta
	)
