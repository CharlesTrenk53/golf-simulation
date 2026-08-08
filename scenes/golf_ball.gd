extends MeshInstance3D

enum ShotType {
	DRIVE,
	APPROACH,
	SHORT_GAME,
	PUTT
}

@export var shot_type: ShotType = ShotType.APPROACH

@export var shot_duration: float = 2.0
@export var arc_height: float = 6.0

@export var max_lateral_error: float = 8.0
@export var max_distance_error: float = 8.0

@onready var target: MeshInstance3D = $"../Target"
@onready var golfer: Node = $"../Golfer"

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

	var ability = get_shot_ability()

	var accuracy_factor = 1.0 - (ability / 100.0)

	var lateral_error_range = max_lateral_error * accuracy_factor
	var distance_error_range = max_distance_error * accuracy_factor

	var x_error = randf_range(
		-lateral_error_range,
		lateral_error_range
	)

	var z_error = randf_range(
		-distance_error_range,
		distance_error_range
	)

	shot_destination = target.global_position + Vector3(
		x_error,
		0.0,
		z_error
	)

	print("--------------------")
	print("Golfer: ", golfer.golfer_name)
	print("Shot type: ", ShotType.keys()[shot_type])
	print("Ability used: ", ability)
	print("Lateral error: ", x_error)
	print("Distance error: ", z_error)
	print("Shot destination: ", shot_destination)


func get_shot_ability() -> float:
	match shot_type:
		ShotType.DRIVE:
			return golfer.driving

		ShotType.APPROACH:
			return golfer.approach

		ShotType.SHORT_GAME:
			return golfer.short_game

		ShotType.PUTT:
			return golfer.putting

	return golfer.approach
