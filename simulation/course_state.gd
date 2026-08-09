extends RefCounted

var ball_position: Vector3
var hole_position: Vector3
var strokes: int = 0
var par: int = 4
var max_strokes: int = 12
var finished: bool = false
var last_outcome: String = ""
var course_context = null
var current_surface: int = 1
var current_lie_quality: float = 1.0


func _init(
	start_position: Vector3 = Vector3.ZERO,
	target_position: Vector3 = Vector3.ZERO,
	hole_par: int = 4,
	context = null
) -> void:
	ball_position = start_position
	hole_position = target_position
	par = hole_par
	course_context = context
	_refresh_lie()


func remaining_distance() -> float:
	return ball_position.distance_to(hole_position)


func advance_to(
	new_position: Vector3,
	outcome: String = "SUCCESS",
	penalty_strokes: int = 0,
	hole_radius: float = 2.0
) -> void:
	ball_position = new_position
	strokes += 1 + penalty_strokes
	last_outcome = outcome
	_refresh_lie()
	finished = remaining_distance() <= hole_radius


func can_continue() -> bool:
	return not finished and strokes < max_strokes


func surface_name() -> String:
	if course_context == null:
		return "FAIRWAY"
	return course_context.surface_name(current_surface)


func _refresh_lie() -> void:
	if course_context == null:
		current_surface = 1
		current_lie_quality = 1.0
		return
	current_surface = course_context.surface_at(ball_position)
	current_lie_quality = course_context.lie_quality(current_surface)


func snapshot() -> Dictionary:
	return {
		"ball_position": ball_position,
		"hole_position": hole_position,
		"remaining_distance": remaining_distance(),
		"strokes": strokes,
		"par": par,
		"finished": finished,
		"last_outcome": last_outcome,
		"surface": surface_name(),
		"lie_quality": current_lie_quality
	}
