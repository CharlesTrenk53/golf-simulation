extends Node3D

const AutonomousHole = preload("res://simulation/autonomous_hole.gd")

@export var shot_duration: float = 0.9
@export var decision_pause: float = 0.45
@export var golfer_pause: float = 1.2
@export var arc_height: float = 5.0
@export var seed_value: int = 42

@onready var ball: MeshInstance3D = $GolfBall
@onready var hole: MeshInstance3D = $Hole
@onready var water_hazard: MeshInstance3D = $WaterHazard
@onready var golfer: Node = $Golfer
@onready var status_label: Label = $UI/Panel/VBox/Status
@onready var detail_label: Label = $UI/Panel/VBox/Detail
@onready var comparison_label: Label = $UI/ComparisonPanel/Comparison

var simulation = AutonomousHole.new()
var state
var hazards: Array = []
var start_position: Vector3
var results: Array = []

var profiles: Array = [
	{"profile": 0, "label": "Wild Bill"},
	{"profile": 1, "label": "Reckless Rick"},
	{"profile": 2, "label": "Careful Carl"}
]


func _ready() -> void:
	start_position = ball.global_position
	hazards = [
		{
			"name": "Water",
			"position": water_hazard.global_position,
			"radius": 10.0,
			"risk": 90.0
		}
	]

	_update_status("Ready", "Three golfers will play the same hole.")
	_update_comparison()
	await get_tree().create_timer(0.8).timeout
	await _run_comparison()


func _run_comparison() -> void:
	for profile_data in profiles:
		_reset_golfer(profile_data["profile"])
		ball.global_position = start_position
		state = simulation.create_state(
			start_position,
			hole.global_position,
			4,
			seed_value
		)

		_update_status(
			"NOW PLAYING: %s" % golfer.golfer_name,
			"Same hole, same hazard, same random seed."
		)
		await get_tree().create_timer(golfer_pause).timeout

		var result = await _play_current_golfer()
		results.append(result)
		_update_comparison()
		await get_tree().create_timer(golfer_pause).timeout

	_update_status(
		"COMPARISON COMPLETE",
		"All three golfers played the same situation autonomously."
	)


func _reset_golfer(profile_value: int) -> void:
	golfer.profile = profile_value
	golfer.apply_profile()
	golfer.shots_attempted = 0
	golfer.successful_shots = 0
	golfer.water_balls = 0
	golfer.aggressive_attempts = 0
	golfer.aggressive_successes = 0
	golfer.aggressive_failures = 0


func _play_current_golfer() -> Dictionary:
	var shot_sequence: Array[String] = []
	var water_count: int = 0

	while state.can_continue():
		var before_distance = state.remaining_distance()
		var result = simulation.play_step(golfer, state, hazards)

		if result.is_empty():
			_update_status("Stopped", "No valid shot options were available.")
			break

		var selected = result["selected_option"]
		shot_sequence.append(selected["name"])
		if result["outcome"] == "WATER":
			water_count += 1

		var title = "%s — Stroke %d: %s" % [
			golfer.golfer_name,
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

		_update_status(
			title,
			"%s  |  Now %.1f from hole  |  Score: %d" % [
				result["outcome"],
				state.remaining_distance(),
				state.strokes
			]
		)
		await get_tree().create_timer(decision_pause).timeout

	var finish_text = "Finished" if state.finished else "Stroke limit"
	_update_status(
		"%s: %s" % [golfer.golfer_name, finish_text],
		"Score %d  |  Water %d  |  %s" % [
			state.strokes,
			water_count,
			" → ".join(shot_sequence)
		]
	)

	return {
		"name": golfer.golfer_name,
		"finished": state.finished,
		"strokes": state.strokes,
		"water": water_count,
		"shots": shot_sequence.duplicate()
	}


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


func _update_comparison() -> void:
	var lines: Array[String] = ["POC-05E — SAME HOLE COMPARISON"]

	if results.is_empty():
		lines.append("Waiting for results...")
	else:
		for result in results:
			var status = "FINISHED" if result["finished"] else "LIMIT"
			lines.append(
				"%s | %s | %d strokes | %d water" % [
					result["name"],
					status,
					result["strokes"],
					result["water"]
				]
			)
			lines.append("  " + " → ".join(result["shots"]))

	comparison_label.text = "\n".join(lines)
