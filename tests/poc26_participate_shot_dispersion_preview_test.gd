extends SceneTree

const ParticipateDemoScene = preload("res://scenes/participate_demo.tscn")
const GolfBag = preload("res://simulation/golf_bag.gd")
const ShotmakingProficiencyModel = preload("res://simulation/shotmaking_proficiency_model.gd")

var failures: int = 0
var demo = null
var bag = GolfBag.new()
var proficiency_model = ShotmakingProficiencyModel.new()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-26E: model-derived Participate shot dispersion preview")
	demo = ParticipateDemoScene.instantiate()
	demo.auto_advance = false
	get_root().add_child(demo)
	_assert_true(demo.initialized, "launchable Participate scene initializes with preview child")
	if not demo.initialized:
		_finish()
		return

	var preview = demo.get_node_or_null("ShotDispersionPreview")
	_assert_true(preview != null, "Participate scene owns shot dispersion preview")
	if preview == null:
		_finish()
		return

	var decision: Dictionary = demo.session.pending_human_decision("group_1")
	var iterations: int = 0
	while decision.is_empty() and iterations < 180:
		demo.session.advance_time(30.0, false)
		decision = demo.session.pending_human_decision("group_1")
		iterations += 1
	_assert_true(not decision.is_empty(), "player reaches authoritative full-shot decision")
	if decision.is_empty():
		_finish()
		return

	demo.select_group("group_1")
	demo._refresh_presentation(0.0, true)
	var selected_index: int = demo.selected_candidate_index()
	_assert_true(selected_index >= 0, "compact browser selects authority-issued candidate")
	var choice: Dictionary = _choice_for_index(decision.get("choices", []), selected_index)
	_assert_equal(str(choice.get("mode", "")), "COURSE_STRATEGY", "opening selection is a course-strategy shot")
	_assert_true(not choice.get("predicted_flight", {}).is_empty(), "authority choice exposes theoretical flight without outcome")
	_assert_true(not choice.get("intent", {}).is_empty(), "authority choice exposes selected shot intent")

	var before_shots: int = demo.controller.group_live_shot_count("group_1")
	var before_decision_id: String = str(decision.get("decision_id", ""))
	var refreshed: Dictionary = preview.refresh_from_demo()
	var snap: Dictionary = preview.snapshot()
	_assert_true(bool(snap.get("visible", false)), "selected full shot displays possible landing ring")
	_assert_equal(int(refreshed.get("candidate_index", -1)), selected_index, "preview follows exact browser candidate index")
	_assert_equal(str(refreshed.get("decision_id", "")), before_decision_id, "preview remains attached to exact authoritative decision")
	_assert_equal(str(refreshed.get("kind", "")), "BOUNDED_EXECUTION_ENVELOPE", "preview identifies bounded execution envelope")
	_assert_true(float(refreshed.get("forward_radius_yards", 0.0)) > 0.0, "preview has positive distance uncertainty")
	_assert_true(float(refreshed.get("lateral_radius_yards", 0.0)) > 0.0, "preview has positive lateral uncertainty")

	var situation: Dictionary = decision.get("situation", {})
	var expected: Dictionary = _expected_envelope(choice, situation, demo.golfer_nodes[0], preview.envelope_sigma)
	_assert_true(not expected.is_empty(), "test independently reconstructs execution-model envelope")
	if not expected.is_empty():
		_assert_vector_near(refreshed.get("center_position", Vector3.ZERO), expected.get("center_position", Vector3.ONE), 0.0001, "ring center matches theoretical authoritative flight endpoint")
		_assert_near(float(refreshed.get("forward_radius_yards", -1.0)), float(expected.get("forward_radius_yards", -2.0)), 0.0001, "ring forward radius matches bounded distance execution error")
		_assert_near(float(refreshed.get("lateral_radius_yards", -1.0)), float(expected.get("lateral_radius_yards", -2.0)), 0.0001, "ring lateral radius matches bounded curve-plus-dispersion error")

	# Changing the selected HOW choice should update the informational envelope but
	# must remain pure presentation: no shot and no replacement authority decision.
	var changed_selection: bool = false
	var first_preview: Dictionary = refreshed.duplicate(true)
	if demo.shot_select.item_count > 1:
		var next_ui_index: int = 1 if demo.shot_select.selected != 1 else 0
		demo.shot_select.select(next_ui_index)
		changed_selection = demo.selected_candidate_index() != selected_index
	elif demo.aim_select.item_count > 1:
		var next_aim: int = 1 if demo.aim_select.selected != 1 else 0
		demo.aim_select.select(next_aim)
		demo._on_aim_selected(next_aim)
		changed_selection = demo.selected_candidate_index() != selected_index
	_assert_true(changed_selection, "test can browse to a different authority-issued shot")
	var second_preview: Dictionary = preview.refresh_from_demo()
	if changed_selection:
		_assert_true(int(second_preview.get("candidate_index", -1)) != selected_index, "preview follows newly browsed shot")
		var visual_changed: bool = (
			second_preview.get("center_position", Vector3.ZERO) != first_preview.get("center_position", Vector3.ZERO)
			or absf(float(second_preview.get("forward_radius_yards", 0.0)) - float(first_preview.get("forward_radius_yards", 0.0))) > 0.0001
			or absf(float(second_preview.get("lateral_radius_yards", 0.0)) - float(first_preview.get("lateral_radius_yards", 0.0))) > 0.0001
		)
		_assert_true(visual_changed, "different shot selection changes landing preview geometry")
	_assert_equal(demo.controller.group_live_shot_count("group_1"), before_shots, "browsing dispersion preview cannot execute a shot")
	_assert_equal(str(demo.session.pending_human_decision("group_1").get("decision_id", "")), before_decision_id, "browsing dispersion preview cannot mutate pending authority")

	print("POC26E_DISPERSION_PREVIEW_SUMMARY candidate=%d forward=%.2f lateral=%.2f changed=%s" % [
		selected_index,
		float(first_preview.get("forward_radius_yards", 0.0)),
		float(first_preview.get("lateral_radius_yards", 0.0)),
		str(changed_selection)
	])
	_finish()


func _expected_envelope(choice: Dictionary, situation: Dictionary, golfer: Node, bound: float) -> Dictionary:
	var predicted: Dictionary = choice.get("predicted_flight", {})
	var intent: Dictionary = choice.get("intent", {})
	var club: Dictionary = bag.get_club(str(choice.get("club_id", "")))
	if predicted.is_empty() or intent.is_empty() or club.is_empty() or golfer == null:
		return {}
	var start = situation.get("ball_position", null)
	var target = choice.get("target_position", null)
	if typeof(start) != TYPE_VECTOR3 or typeof(target) != TYPE_VECTOR3:
		return {}
	var direction: Vector3 = target - start
	direction.y = 0.0
	if direction.length() <= 0.001:
		return {}
	direction = direction.normalized()
	var lateral := Vector3(-direction.z, 0.0, direction.x)
	var proficiency: Dictionary = proficiency_model.assess(golfer, club, intent, predicted)
	var reliability: float = clampf(float(proficiency.get("execution_reliability", 0.70)), 0.05, 0.99)
	var dispersion_multiplier: float = maxf(0.1, float(proficiency.get("expected_dispersion_multiplier", 1.0)))
	var planned_carry: float = maxf(0.0, float(predicted.get("carry_yards", 0.0)))
	var planned_rollout: float = maxf(0.0, float(predicted.get("rollout_yards", 0.0)))
	var planned_total: float = planned_carry + planned_rollout
	var planned_curve: float = float(predicted.get("curve_yards", 0.0))
	var planned_dispersion: float = maxf(0.1, float(predicted.get("dispersion_yards", 1.0)))
	if planned_carry <= 0.01:
		return {}
	var error_scale: float = lerpf(1.0, 0.18, reliability)
	var lateral_sigma: float = planned_dispersion * dispersion_multiplier * error_scale
	var distance_sigma: float = planned_carry * lerpf(0.10, 0.025, reliability)
	var curve_sigma: float = maxf(1.0, absf(planned_curve) * 0.28 + planned_dispersion * 0.20) * error_scale
	var carry_bound: float = distance_sigma * bound
	var low_carry: float = maxf(0.0, planned_carry - carry_bound)
	var high_carry: float = planned_carry + carry_bound
	var low_total: float = _total_for_carry(low_carry, planned_carry, planned_rollout)
	var high_total: float = _total_for_carry(high_carry, planned_carry, planned_rollout)
	return {
		"center_position": start + direction * planned_total + lateral * planned_curve,
		"forward_radius_yards": maxf(maxf(absf(planned_total - low_total), absf(high_total - planned_total)), 0.75),
		"lateral_radius_yards": maxf(bound * (lateral_sigma + curve_sigma), 0.75)
	}


func _total_for_carry(actual_carry: float, planned_carry: float, planned_rollout: float) -> float:
	var ratio: float = actual_carry / planned_carry if planned_carry > 0.01 else 1.0
	return actual_carry + planned_rollout * clampf(ratio, 0.65, 1.25)


func _choice_for_index(choices: Array, candidate_index: int) -> Dictionary:
	for choice_value in choices:
		if typeof(choice_value) == TYPE_DICTIONARY and int(choice_value.get("index", -1)) == candidate_index:
			return choice_value
	return {}


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal(actual, expected, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])


func _assert_vector_near(actual: Vector3, expected: Vector3, tolerance: float, label: String) -> void:
	if actual.distance_to(expected) <= tolerance:
		print("PASS: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, str(actual), str(expected)])


func _finish() -> void:
	if demo != null and is_instance_valid(demo):
		demo.queue_free()
	if failures == 0:
		print("POC-26E MODEL-DERIVED SHOT DISPERSION PREVIEW PASSED")
		quit(0)
	else:
		push_error("POC-26E SHOT DISPERSION PREVIEW FAILED: %d" % failures)
		quit(1)
