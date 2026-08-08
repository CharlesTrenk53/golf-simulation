extends MeshInstance3D

@export var shot_duration: float = 2.0
@export var arc_height: float = 6.0

@export var max_lateral_error: float = 8.0
@export var max_distance_error: float = 8.0

@onready var target: MeshInstance3D = $"../Target"
@onready var golfer: Node = $"../Golfer"
@onready var shot_simulator: Node = $"../ShotSimulator"

var start_position: Vector3
var shot_destination: Vector3
var elapsed_time: float = 0.0
var shot_complete: bool = false


func _ready() -> void:
	randomize()
	start_position = global_position
	hit_shot()


func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_SPACE) and shot_complete:
		hit_shot()

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


func hit_shot() -> void:
	global_position = start_position
	elapsed_time = 0.0
	shot_complete = false

	var distance_to_target = start_position.distance_to(
		target.global_position
	)

	var chosen_shot_type = golfer.choose_shot(
		distance_to_target
	)

	print("====================")
	print("DECISION")
	print("Distance to target: ", distance_to_target)
	print(
		"Golfer chose: ",
		golfer.ShotType.keys()[chosen_shot_type]
	)

	shot_destination = shot_simulator.simulate_shot(
		golfer,
		chosen_shot_type,
		target.global_position,
		max_lateral_error,
		max_distance_error
	)
