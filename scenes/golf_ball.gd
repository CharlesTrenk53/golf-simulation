extends MeshInstance3D

@export var shot_duration: float = 2.0
@export var arc_height: float = 6.0

@export var max_lateral_error: float = 8.0
@export var max_distance_error: float = 8.0

@export var aggressive_target: MeshInstance3D
@export var layup_target: MeshInstance3D
@export var water_hazard: MeshInstance3D

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

	var distance_to_aggressive_target = start_position.distance_to(
		aggressive_target.global_position
	)

	var calculated_hazard_risk = water_hazard.calculate_hazard_risk(
	golfer
)

	var chosen_shot_type = golfer.choose_shot(
	distance_to_aggressive_target,
	calculated_hazard_risk
)

	var chosen_target: MeshInstance3D

	if chosen_shot_type == golfer.ShotType.DRIVE:
		chosen_target = aggressive_target
	else:
		chosen_target = layup_target

	print("====================")
	print("COURSE DECISION")
	print("Golfer: ", golfer.golfer_name)
	print("Risk tolerance: ", golfer.risk_tolerance)
	print(
		"Shot selected: ",
		golfer.ShotType.keys()[chosen_shot_type]
	)
	print("Target selected: ", chosen_target.name)

	shot_destination = shot_simulator.simulate_shot(
		golfer,
		chosen_shot_type,
		chosen_target.global_position,
		max_lateral_error,
		max_distance_error
	)
