extends MeshInstance3D

@export var shot_duration: float = 2.0
@export var arc_height: float = 6.0

@export var max_lateral_error: float = 8.0
@export var max_distance_error: float = 8.0

@export var aggressive_target: MeshInstance3D
@export var bailout_target: MeshInstance3D
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

	await get_tree().process_frame

	hit_shot()


func _process(delta: float) -> void:

	if (
		Input.is_key_pressed(KEY_SPACE)
		and shot_complete
	):
		hit_shot()

	if shot_complete:
		return

	elapsed_time += delta

	var t = (
		elapsed_time
		/ shot_duration
	)

	t = clamp(
		t,
		0.0,
		1.0
	)

	var position_on_line = start_position.lerp(
		shot_destination,
		t
	)

	var arc = (
		4.0
		* arc_height
		* t
		* (1.0 - t)
	)

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

	var calculated_hazard_risk = (
		water_hazard.calculate_hazard_risk(
			golfer
		)
	)

	var model_success_chance = (
		shot_simulator.calculate_carry_success_chance(
			golfer,
			water_hazard.required_carry
		)
	)

	var shot_options = [
		{
			"name": "LAYUP",
			"shot_type": golfer.ShotType.APPROACH,
			"target": layup_target,
			"reward": 45.0,
			"risk": 10.0,
			"is_aggressive": false,
			"model_success_chance": 100.0
		},
		{
			"name": "BAILOUT",
			"shot_type": golfer.ShotType.APPROACH,
			"target": bailout_target,
			"reward": 55.0,
			"risk": 30.0,
			"is_aggressive": false,
			"model_success_chance": 100.0
		},
		{
			"name": "ATTACK",
			"shot_type": golfer.ShotType.DRIVE,
			"target": aggressive_target,
			"reward": 65.0,
			"risk": calculated_hazard_risk,
			"is_aggressive": true,
			"model_success_chance": model_success_chance
		}
	]

	var chosen_option = golfer.choose_best_option(
		shot_options
	)

	var chosen_target: MeshInstance3D = (
		chosen_option["target"]
	)

	var chosen_shot_type: int = (
		chosen_option["shot_type"]
	)

	print("====================")
	print("COURSE DECISION")
	print("Golfer: ", golfer.golfer_name)
	print(
		"Selected option: ",
		chosen_option["name"]
	)
	print(
		"Target selected: ",
		chosen_target.name
	)
	print(
		"Shot type: ",
		golfer.ShotType.keys()[
			chosen_shot_type
		]
	)

	var required_carry: float = 0.0

	if chosen_option["is_aggressive"]:
		required_carry = (
			water_hazard.required_carry
		)

	shot_destination = (
		shot_simulator.simulate_shot(
			golfer,
			chosen_shot_type,
			chosen_target.global_position,
			max_lateral_error,
			max_distance_error,
			required_carry,
			water_hazard.global_position
		)
	)
