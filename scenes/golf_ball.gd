extends MeshInstance3D

@export var shot_duration: float = 2.0
@export var lateral_error: float = 4.0
@export var distance_error: float = 4.0
@export var arc_height: float = 6.0

@onready var target: MeshInstance3D = $"../Target"

var start_position: Vector3
var shot_destination: Vector3
var elapsed_time: float = 0.0
var shot_complete: bool = false


func _ready() -> void:
	randomize()

	start_position = global_position

	var x_error = randf_range(-lateral_error, lateral_error)
	var z_error = randf_range(-distance_error, distance_error)

	shot_destination = target.global_position + Vector3(
		x_error,
		0.0,
		z_error
	)


func _process(delta: float) -> void:
	if shot_complete:
		return

	elapsed_time += delta

	var t = elapsed_time / shot_duration
	t = clamp(t, 0.0, 1.0)

	var position_on_line = start_position.lerp(
		shot_destination,
		t
	)

	var arc = 4.0 * arc_height * t * (1.0 - t)

	global_position = Vector3(
		position_on_line.x,
		position_on_line.y + arc,
		position_on_line.z
	)

	if t >= 1.0:
		global_position = shot_destination
		shot_complete = true
