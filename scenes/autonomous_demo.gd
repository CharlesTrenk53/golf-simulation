extends Node3D

const AutonomousHole = preload("res://simulation/autonomous_hole.gd")

@export var shot_duration: float = 1.4
@export var decision_pause: float = 0.9
@export var arc_height: float = 5.0
@export var seed_value: int = 42

@onready var ball: MeshInstance3D = $GolfBall
@onready var hole: MeshInstance3D = $Hole
@onready var water_hazard: MeshInstance3D = $WaterHazard
@onready var golfer: Node = $Golfer
@onready var status_label: Label = $UI/Panel/VBox/Status
@onready var detail_label: Label = $UI/Panel/VBox/Detail

var simulation = AutonomousHole.new()
var state
var hazards: Array = []


func _ready() -> void:
	hazards = [
		{
			"name": "Water",
			"position": water_hazard.global_position,
			"radius": 10.0,
			"risk": 90.0
		}
	]

	state = simulation.create_state(
		ball.global_position,
		hole.global_position,
		4,
		seed_value
	)

	_update_status("Ready", "Autonomous play begins...")
	await get_tree().create_timer(0.8).timeout
	await _play_autonomous_hole()


func _play_autonomous_hole() -> void:
	while state.can_continue():
		var before_distance = state.remaining_distance()
		var result = simulation.play_step(golfer, state, hazards)

		if result.is_empty():
			_update_status("Stopped", "No valid shot options were available.")
			return

		var selected = result["selected_option"]
		var title = "Stroke %d: %s" % [
			result["shot_number"],
			selected["name"]
		]
		var detail = "Remaining %.1f  |  Risk %.1f  |  Expected success %.1f%%" % [
			before_distance,
			selected["risk"],
			selected["model_success_chance"]
		]
		_update_status(title, detail)

		await _animate_ball(
			result["start_position"],
			result["landing_position"]
		)

		var outcome_text = "%s  |  Now %.1f from hole  |  Score: %d" % [
			result["outcome"],
			state.remaining_distance(),
			state.strokes
		]
		_update_status(title, outcome_text)

		await get_tree().create_timer(decision_pause).timeout

	if state.finished:
		_update_status(
			"HOLE COMPLETE",
			"%s finished in %d strokes on a par %d." % [
				golfer.golfer_name,
				state.strokes,
				state.par
			]
		)
	else:
		_update_status(
			"STROKE LIMIT REACHED",
			"%.1f remains after %d strokes." % [
				state.remaining_distance(),
				state.strokes
			]
		)


func _animate_ball(start: Vector3, finish: Vector3) -> void:
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(
		_set_ball_progress.bind(start, finish),
		0.0,
		1.0,
		shot_duration
	)
	await tween.finished


func _set_ball_progress(
	progress: float,
	start: Vector3,
	finish: Vector3
) -> void:
	var position = start.lerp(finish, progress)
	position.y += 4.0 * arc_height * progress * (1.0 - progress)
	ball.global_position = position


func _update_status(title: String, detail: String) -> void:
	status_label.text = title
	detail_label.text = detail
