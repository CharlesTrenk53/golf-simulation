extends Node3D

# POC-26 Participate shot-dispersion preview
# ------------------------------------------
# Presentation-only landing envelope for the currently selected human shot.
# The preview never samples a result and never mutates simulation authority. It
# reconstructs the same bounded execution error scales used by ShotExecutionModel
# from the authority-issued predicted flight plus this golfer's proficiency.
#
# Putting intentionally remains unpreviewed for now: the public decision summary
# does not expose the break-adjusted putting read/aim point, and drawing a straight
# approximation would communicate false precision.

const GolfBag = preload("res://simulation/golf_bag.gd")
const ShotmakingProficiencyModel = preload("res://simulation/shotmaking_proficiency_model.gd")

@export var envelope_sigma: float = 2.5
@export var vertical_offset: float = 0.22
@export var ring_segments: int = 72

var bag = GolfBag.new()
var proficiency_model = ShotmakingProficiencyModel.new()
var ring_mesh_instance: MeshInstance3D = null
var ring_mesh: ImmediateMesh = null
var ring_material: StandardMaterial3D = null
var preview_data: Dictionary = {}
var _last_preview_key: String = ""


func _ready() -> void:
	_ensure_visuals()
	set_process(true)


func _process(_delta: float) -> void:
	refresh_from_demo()


func refresh_from_demo() -> Dictionary:
	_ensure_visuals()
	var demo = get_parent()
	if demo == null or not bool(demo.get("initialized")):
		_hide_preview()
		return {}
	var focus = demo.get("focus_controller")
	var course_world = demo.get("course_world")
	if focus == null or course_world == null or not demo.has_method("selected_candidate_index"):
		_hide_preview()
		return {}

	var presentation: Dictionary = focus.presentation_snapshot()
	var decision_id: String = str(presentation.get("decision_id", ""))
	var selected_index: int = int(demo.selected_candidate_index())
	if decision_id.is_empty() or selected_index < 0 or str(presentation.get("group_id", "")) != "group_1":
		_hide_preview()
		return {}

	var choice: Dictionary = _choice_for_index(presentation.get("choices", []), selected_index)
	if choice.is_empty() or str(choice.get("mode", "")) != "COURSE_STRATEGY":
		_hide_preview()
		return {}

	var golfers: Array = demo.get("golfer_nodes")
	if golfers.is_empty() or golfers[0] == null:
		_hide_preview()
		return {}
	var situation: Dictionary = presentation.get("situation", {})
	var preview: Dictionary = build_preview(choice, situation, golfers[0])
	if preview.is_empty():
		_hide_preview()
		return {}

	var key: String = "%s|%d|%.4f|%.4f" % [
		decision_id,
		selected_index,
		float(preview.get("forward_radius_yards", 0.0)),
		float(preview.get("lateral_radius_yards", 0.0))
	]
	if key != _last_preview_key:
		var hole_number: int = int(situation.get("hole_number", presentation.get("hole_number", 0)))
		_apply_preview(preview, hole_number, course_world)
		_last_preview_key = key
	preview_data = preview.duplicate(true)
	preview_data["decision_id"] = decision_id
	preview_data["candidate_index"] = selected_index
	return preview_data.duplicate(true)


func build_preview(choice: Dictionary, situation: Dictionary, golfer: Node) -> Dictionary:
	if golfer == null or str(choice.get("mode", "")) != "COURSE_STRATEGY":
		return {}
	var predicted: Dictionary = choice.get("predicted_flight", {})
	var intent: Dictionary = choice.get("intent", {})
	var club_id: String = str(choice.get("club_id", ""))
	if predicted.is_empty() or intent.is_empty() or club_id.is_empty():
		return {}
	var club: Dictionary = bag.get_club(club_id)
	if club.is_empty():
		return {}
	var start_value = situation.get("ball_position", null)
	var target_value = choice.get("target_position", null)
	if typeof(start_value) != TYPE_VECTOR3 or typeof(target_value) != TYPE_VECTOR3:
		return {}
	var start: Vector3 = start_value
	var target: Vector3 = target_value
	var direction: Vector3 = target - start
	direction.y = 0.0
	if direction.length() <= 0.001:
		return {}
	direction = direction.normalized()
	var lateral: Vector3 = Vector3(-direction.z, 0.0, direction.x)

	var proficiency: Dictionary = proficiency_model.assess(golfer, club, intent, predicted)
	var reliability: float = clampf(float(proficiency.get("execution_reliability", 0.70)), 0.05, 0.99)
	var dispersion_multiplier: float = maxf(0.1, float(proficiency.get("expected_dispersion_multiplier", 1.0)))
	var planned_carry: float = maxf(0.0, float(predicted.get("carry_yards", 0.0)))
	var planned_rollout: float = maxf(0.0, float(predicted.get("rollout_yards", 0.0)))
	var planned_total: float = planned_carry + planned_rollout
	var planned_curve: float = float(predicted.get("curve_yards", 0.0))
	var planned_dispersion: float = maxf(0.1, float(predicted.get("dispersion_yards", 1.0)))
	if planned_carry <= 0.01 or planned_total <= 0.01:
		return {}

	# These formulas intentionally mirror ShotExecutionModel.realize(). Execution
	# clamps each Gaussian-like error at +/-2.5 sigma, so the displayed radii show
	# the model's bounded outer error scale rather than predicting the sampled shot.
	var error_scale: float = lerpf(1.0, 0.18, reliability)
	var lateral_sigma: float = planned_dispersion * dispersion_multiplier * error_scale
	var distance_sigma: float = planned_carry * lerpf(0.10, 0.025, reliability)
	var curve_sigma: float = maxf(1.0, absf(planned_curve) * 0.28 + planned_dispersion * 0.20) * error_scale
	var bound: float = maxf(0.1, envelope_sigma)
	var carry_bound: float = distance_sigma * bound
	var low_carry: float = maxf(0.0, planned_carry - carry_bound)
	var high_carry: float = planned_carry + carry_bound
	var low_total: float = _total_for_carry(low_carry, planned_carry, planned_rollout)
	var high_total: float = _total_for_carry(high_carry, planned_carry, planned_rollout)
	var forward_radius: float = maxf(absf(planned_total - low_total), absf(high_total - planned_total))
	var lateral_radius: float = bound * (lateral_sigma + curve_sigma)
	forward_radius = maxf(forward_radius, 0.75)
	lateral_radius = maxf(lateral_radius, 0.75)

	var center: Vector3 = start + direction * planned_total + lateral * planned_curve
	center.y = start.y
	return {
		"available": true,
		"kind": "BOUNDED_EXECUTION_ENVELOPE",
		"center_position": center,
		"start_position": start,
		"target_position": target,
		"forward_axis": direction,
		"lateral_axis": lateral,
		"forward_radius_yards": forward_radius,
		"lateral_radius_yards": lateral_radius,
		"planned_total_yards": planned_total,
		"planned_curve_yards": planned_curve,
		"execution_reliability": reliability,
		"lateral_sigma_yards": lateral_sigma,
		"distance_sigma_yards": distance_sigma,
		"curve_sigma_yards": curve_sigma,
		"envelope_sigma": bound,
		"club_id": club_id,
		"intent_signature": str(predicted.get("intent_signature", ""))
	}


func snapshot() -> Dictionary:
	return {
		"visible": ring_mesh_instance.visible if ring_mesh_instance != null else false,
		"preview": preview_data.duplicate(true),
		"preview_key": _last_preview_key
	}


func _choice_for_index(choices: Array, candidate_index: int) -> Dictionary:
	for choice_value in choices:
		if typeof(choice_value) == TYPE_DICTIONARY:
			var choice: Dictionary = choice_value
			if int(choice.get("index", -1)) == candidate_index:
				return choice
	return {}


func _total_for_carry(actual_carry: float, planned_carry: float, planned_rollout: float) -> float:
	var carry_ratio: float = actual_carry / planned_carry if planned_carry > 0.01 else 1.0
	var actual_rollout: float = planned_rollout * clampf(carry_ratio, 0.65, 1.25)
	return actual_carry + maxf(0.0, actual_rollout)


func _ensure_visuals() -> void:
	if ring_mesh_instance != null:
		return
	ring_mesh_instance = MeshInstance3D.new()
	ring_mesh_instance.name = "PossibleLandingZone"
	ring_mesh = ImmediateMesh.new()
	ring_mesh_instance.mesh = ring_mesh
	ring_material = StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(1.0, 0.78, 0.08, 1.0)
	ring_material.no_depth_test = true
	ring_mesh_instance.visible = false
	add_child(ring_mesh_instance)


func _apply_preview(preview: Dictionary, hole_number: int, course_world) -> void:
	if ring_mesh == null or ring_mesh_instance == null or hole_number <= 0:
		_hide_preview()
		return
	var center_course: Vector3 = preview.get("center_position", Vector3.ZERO)
	var center_world: Vector3 = course_world.world_position(hole_number, center_course)
	var forward: Vector3 = preview.get("forward_axis", Vector3.FORWARD)
	var lateral: Vector3 = preview.get("lateral_axis", Vector3.RIGHT)
	var forward_radius: float = float(preview.get("forward_radius_yards", 0.0))
	var lateral_radius: float = float(preview.get("lateral_radius_yards", 0.0))
	if forward_radius <= 0.0 or lateral_radius <= 0.0:
		_hide_preview()
		return

	ring_mesh.clear_surfaces()
	ring_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, ring_material)
	var segments: int = maxi(24, ring_segments)
	for index in range(segments + 1):
		var angle: float = TAU * float(index) / float(segments)
		var point: Vector3 = (
			forward * (cos(angle) * forward_radius)
			+ lateral * (sin(angle) * lateral_radius)
		)
		point.y += vertical_offset
		ring_mesh.surface_add_vertex(point)
	ring_mesh.surface_end()

	# Small center cross makes the theoretical landing center readable without
	# implying that the ball is expected to finish exactly there.
	var cross_size: float = clampf(minf(forward_radius, lateral_radius) * 0.22, 0.6, 2.5)
	ring_mesh.surface_begin(Mesh.PRIMITIVE_LINES, ring_material)
	ring_mesh.surface_add_vertex(forward * -cross_size + Vector3.UP * vertical_offset)
	ring_mesh.surface_add_vertex(forward * cross_size + Vector3.UP * vertical_offset)
	ring_mesh.surface_add_vertex(lateral * -cross_size + Vector3.UP * vertical_offset)
	ring_mesh.surface_add_vertex(lateral * cross_size + Vector3.UP * vertical_offset)
	ring_mesh.surface_end()
	ring_mesh_instance.position = center_world
	ring_mesh_instance.visible = true


func _hide_preview() -> void:
	preview_data.clear()
	_last_preview_key = ""
	if ring_mesh_instance != null:
		ring_mesh_instance.visible = false
