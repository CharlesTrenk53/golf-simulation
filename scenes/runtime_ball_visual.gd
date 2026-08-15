extends Node3D

# POC-21B: Runtime Ball Representation
# -------------------------------------
# Visual-only representation of an already-resolved simulation shot. The
# simulation remains authoritative for start, target, landing, penalties, and
# relief. This node never calculates a golf outcome or modifies simulation state.
#
# POC-27 kickoff: putting results retain their authoritative rolled landing point
# but are presented as a ground roll instead of inheriting the generic airborne
# parabola used by full shots.

signal flight_finished

const PUTT_SHOT_TYPE := 3

@export var flight_duration: float = 1.25
@export var default_arc_height: float = 8.0
@export var ball_radius: float = 0.35

var course_position: Vector3 = Vector3.ZERO
var shot_start: Vector3 = Vector3.ZERO
var shot_target: Vector3 = Vector3.ZERO
var shot_landing: Vector3 = Vector3.ZERO
var relief_position: Vector3 = Vector3.ZERO
var has_relief: bool = false
var flight_progress: float = 1.0
var is_flying: bool = false
var _elapsed: float = 0.0
var _arc_height: float = 0.0
var _ground_roll: bool = false


func _ready() -> void:
	_ensure_ball_mesh()
	_apply_course_position(course_position)


func place_at(position: Vector3) -> void:
	course_position = position
	shot_start = position
	shot_target = position
	shot_landing = position
	relief_position = position
	has_relief = false
	flight_progress = 1.0
	is_flying = false
	_elapsed = 0.0
	_ground_roll = false
	set_meta("trajectory_kind", "STATIONARY")
	_apply_course_position(position)


func present_shot(result: Dictionary, animate: bool = true) -> bool:
	if not result.has("start_position") or not result.has("landing_position"):
		return false

	shot_start = result.get("start_position", Vector3.ZERO)
	shot_target = result.get("target_position", result.get("landing_position", shot_start))
	shot_landing = result.get("landing_position", shot_start)
	relief_position = result.get("relief_position", shot_landing)
	has_relief = relief_position.distance_to(shot_landing) > 0.001
	course_position = shot_start
	_elapsed = 0.0
	_ground_roll = _is_putt(result)
	_arc_height = 0.0 if _ground_roll else _resolved_arc_height(result)
	set_meta("trajectory_kind", "GROUND_ROLL" if _ground_roll else "AIRBORNE")
	flight_progress = 0.0 if animate else 1.0
	is_flying = animate

	if animate:
		_apply_flight_progress(0.0)
	else:
		_finish_at_landing()
	return true


func set_flight_progress(value: float) -> void:
	flight_progress = clamp(value, 0.0, 1.0)
	_apply_flight_progress(flight_progress)
	if flight_progress >= 1.0:
		_finish_at_landing()


func apply_simulation_relief() -> void:
	if not has_relief:
		return
	course_position = relief_position
	_apply_course_position(relief_position)


func _process(delta: float) -> void:
	if not is_flying:
		return
	var duration: float = max(0.001, flight_duration)
	_elapsed += delta
	set_flight_progress(_elapsed / duration)


func _apply_flight_progress(value: float) -> void:
	var t: float = clamp(value, 0.0, 1.0)
	var horizontal: Vector3 = shot_start.lerp(shot_landing, t)
	var arc: float = 0.0 if _ground_roll else 4.0 * _arc_height * t * (1.0 - t)
	course_position = horizontal
	position = Vector3(horizontal.x, horizontal.y + ball_radius + arc, horizontal.z)
	set_meta("course_position", course_position)


func _finish_at_landing() -> void:
	var was_flying: bool = is_flying
	is_flying = false
	flight_progress = 1.0
	course_position = shot_landing
	_apply_course_position(shot_landing)
	if was_flying:
		flight_finished.emit()


func _apply_course_position(value: Vector3) -> void:
	position = Vector3(value.x, value.y + ball_radius, value.z)
	set_meta("course_position", value)


func _is_putt(result: Dictionary) -> bool:
	if int(result.get("shot_type", -1)) == PUTT_SHOT_TYPE:
		return true
	if str(result.get("club_id", "")).to_upper() == "PUTTER":
		return true
	var putting = result.get("putting", {})
	return typeof(putting) == TYPE_DICTIONARY and not putting.is_empty()


func _resolved_arc_height(result: Dictionary) -> float:
	var shot_execution: Dictionary = result.get("shot_execution", {})
	var apex: float = float(shot_execution.get("apex_height_yards", default_arc_height))
	if apex <= 0.0:
		return default_arc_height
	return apex


func _ensure_ball_mesh() -> void:
	if get_node_or_null("BallMesh") != null:
		return
	var visual := MeshInstance3D.new()
	visual.name = "BallMesh"
	var sphere := SphereMesh.new()
	sphere.radius = ball_radius
	sphere.height = ball_radius * 2.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.98, 0.98, 0.98)
	material.roughness = 0.8
	sphere.material = material
	visual.mesh = sphere
	add_child(visual)
