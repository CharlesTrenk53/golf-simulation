extends SceneTree

const PlayerWorldSession = preload("res://simulation/player_world_session.gd")
const PlayerWorldHub = preload("res://simulation/player_world_hub.gd")
const PlayerActivityContract = preload("res://simulation/player_activity_contract.gd")
const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const Golfer = preload("res://scenes/golfer.gd")

var failures: int = 0
var created_nodes: Array = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("POC-29B: activity catalog and selection contract")

	var unconfigured_hub = PlayerWorldHub.new()
	var unconfigured_catalog: Array = unconfigured_hub.activity_catalog()
	_assert_equal_int(unconfigured_catalog.size(), 2, "catalog is explicit even before session configuration")
	for activity in unconfigured_catalog:
		_assert_true(not bool(activity.get("available", true)), "unconfigured catalog activity is unavailable")
		_assert_equal_str(str(activity.get("reason", "")), PlayerActivityContract.REASON_SESSION_NOT_CONFIGURED, "unconfigured activity gives factual rejection reason")
	var unconfigured_selection: Dictionary = unconfigured_hub.select_activity(PlayerActivityContract.ACTIVITY_ROUND)
	_assert_true(not bool(unconfigured_selection.get("accepted", true)), "unconfigured hub rejects activity selection")

	var course = POC27Course.build()
	_assert_true(course != null and course.hole_count() == 18, "18-hole living course builds")
	if course == null:
		_finish()
		return

	var player = _new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var session = PlayerWorldSession.new()
	get_root().add_child(session)
	created_nodes.append(session)
	_assert_true(session.configure(player, course, 8, 14400.0), "persistent world session configures")

	var hub = PlayerWorldHub.new()
	_assert_true(hub.configure(session), "world hub configures over persistent session")
	var player_id: int = player.get_instance_id()
	var controller_id: int = session.controller.get_instance_id()
	var initial_time: float = session.world_time_seconds
	var initial_population: int = session.controller.living_course.population.group_count()

	var catalog: Array = hub.activity_catalog()
	_assert_equal_int(catalog.size(), 2, "idle hub exposes two explicit POC-29 activities")
	_assert_equal_str(str(catalog[0].get("activity_type", "")), PlayerActivityContract.ACTIVITY_ROUND, "round appears first in stable catalog")
	_assert_equal_str(str(catalog[1].get("activity_type", "")), PlayerActivityContract.ACTIVITY_PRACTICE, "practice appears second in stable catalog")
	_assert_true(bool(catalog[0].get("available", false)), "round is selectable while world is idle")
	_assert_true(bool(catalog[1].get("available", false)), "practice is selectable while world is idle")

	var round_options := {"tee_id": "default", "player_member_index": 2, "seed_base": 29021}
	var round_selection: Dictionary = hub.select_activity(" round ", round_options)
	_assert_true(bool(round_selection.get("accepted", false)), "round selection accepts normalized activity id")
	_assert_equal_str(str(round_selection.get("activity_type", "")), PlayerActivityContract.ACTIVITY_ROUND, "round selection returns canonical activity id")
	_assert_equal_str(str(round_selection.get("options", {}).get("tee_id", "")), "default", "round selection preserves options")
	_assert_equal_int(int(round_selection.get("options", {}).get("player_member_index", -1)), 2, "round selection preserves player slot option")

	var practice_options := {"focus": "PUTTING", "duration_minutes": 45}
	var practice_selection: Dictionary = hub.select_activity("practice", practice_options)
	_assert_true(bool(practice_selection.get("accepted", false)), "practice selection uses same shared contract")
	_assert_equal_str(str(practice_selection.get("activity_type", "")), PlayerActivityContract.ACTIVITY_PRACTICE, "practice selection returns canonical activity id")
	_assert_equal_str(str(practice_selection.get("options", {}).get("focus", "")), "PUTTING", "practice selection preserves future launcher options")

	var unknown: Dictionary = hub.select_activity("TOURNAMENT")
	_assert_true(not bool(unknown.get("accepted", true)), "unknown activity is rejected")
	_assert_equal_str(str(unknown.get("reason", "")), PlayerActivityContract.REASON_UNKNOWN_ACTIVITY, "unknown activity returns explicit reason")

	# Selection is intent only. It must not mutate the persistent world.
	_assert_true(session.player_golfer == player, "selection preserves exact persistent golfer object")
	_assert_equal_int(player.get_instance_id(), player_id, "selection preserves golfer identity")
	_assert_equal_int(session.controller.get_instance_id(), controller_id, "selection preserves controller identity")
	_assert_near(session.world_time_seconds, initial_time, 0.0001, "selection does not advance world clock")
	_assert_equal_int(session.controller.living_course.population.group_count(), initial_population, "selection does not add course population")
	_assert_true(session.active_round.is_empty(), "selection does not launch a round as side effect")

	var partner = _new_golfer(Golfer.GolferProfile.WILD_BILL)
	var entered: Dictionary = session.enter_round("player_round", [partner], "default", 0, 29031)
	_assert_true(bool(entered.get("entered", false)), "existing POC-28 authority can launch round independently of selection")

	var blocked_catalog: Array = hub.activity_catalog()
	for activity in blocked_catalog:
		_assert_true(not bool(activity.get("available", true)), "catalog blocks new activity while round is active")
		_assert_equal_str(str(activity.get("reason", "")), PlayerActivityContract.REASON_ACTIVITY_ALREADY_ACTIVE, "active activity supplies shared rejection reason")
	var blocked_practice: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_PRACTICE)
	_assert_true(not bool(blocked_practice.get("accepted", true)), "shared contract rejects second activity while round is active")
	_assert_equal_str(str(blocked_practice.get("reason", "")), PlayerActivityContract.REASON_ACTIVITY_ALREADY_ACTIVE, "second activity rejection is explicit")

	var context: Dictionary = hub.context()
	_assert_equal_str(str(context.get("state", "")), PlayerWorldHub.STATE_ACTIVITY, "hub remains activity-aware after authoritative round launch")
	_assert_equal_int(context.get("activity_catalog", []).size(), 2, "hub context carries current activity catalog")
	_assert_equal_int(int(context.get("golfer_instance_id", 0)), player_id, "catalog/selection layer never replaces golfer")
	_assert_equal_int(int(context.get("controller_instance_id", 0)), controller_id, "catalog/selection layer never replaces controller")

	print("POC29B_ACTIVITY_SELECTION_SUMMARY golfer_id=%d controller_id=%d catalog=%d active=%s" % [
		player_id,
		controller_id,
		catalog.size(),
		str(context.get("active_activity_type", ""))
	])
	_finish()


func _new_golfer(profile_value: int):
	var golfer = Golfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	created_nodes.append(golfer)
	return golfer


func _assert_true(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)


func _assert_equal_int(actual: int, expected: int, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%d expected=%d)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%d expected=%d)" % [label, actual, expected])


func _assert_equal_str(actual: String, expected: String, label: String) -> void:
	if actual == expected:
		print("PASS: %s (actual=%s expected=%s)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%s expected=%s)" % [label, actual, expected])


func _assert_near(actual: float, expected: float, tolerance: float, label: String) -> void:
	if abs(actual - expected) <= tolerance:
		print("PASS: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])
	else:
		failures += 1
		push_error("FAIL: %s (actual=%.6f expected=%.6f)" % [label, actual, expected])


func _finish() -> void:
	for node in created_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
	if failures == 0:
		print("POC-29B ACTIVITY CATALOG AND SELECTION PASSED")
		quit(0)
	else:
		push_error("POC-29B ACTIVITY CATALOG AND SELECTION FAILED: %d" % failures)
		quit(1)
