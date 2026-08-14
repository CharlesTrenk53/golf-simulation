extends SceneTree

const ParticipateDemo = preload("res://scenes/participate_demo.gd")

var failures: int = 0
var demo = null


func _init() -> void:
	print("POC-26E: compact participate choice browser")
	demo = ParticipateDemo.new()
	demo.auto_advance = false
	get_root().add_child(demo)
	_assert_true(demo.initialize_demo(), "launchable participate demo initializes headlessly")
	_assert_true(demo.initialized, "participate demo reports initialized")
	if not demo.initialized:
		_finish()
		return

	var decision: Dictionary = demo.session.pending_human_decision("group_1")
	var iterations: int = 0
	while decision.is_empty() and iterations < 180:
		demo.session.advance_time(30.0, false)
		decision = demo.session.pending_human_decision("group_1")
		iterations += 1
	_assert_true(iterations < 180, "player decision becomes presentation-ready in bounded course time")
	_assert_true(not decision.is_empty(), "authority exposes a real human decision to launchable demo")
	if decision.is_empty():
		_finish()
		return

	demo.select_group("group_1")
	demo._refresh_presentation(0.0, true)
	_assert_true(demo.decision_panel != null and demo.decision_panel.visible, "decision panel appears only when player turn is ready")
	_assert_equal(demo.current_decision_id, str(decision.get("decision_id", "")), "launchable HUD binds exact authority decision identity")

	var human_choices: Array = []
	for choice_value in decision.get("choices", []):
		if typeof(choice_value) == TYPE_DICTIONARY and bool(choice_value.get("human_selectable", false)):
			human_choices.append(choice_value)
	_assert_true(not human_choices.is_empty(), "real authority decision contains human-selectable candidates")
	_assert_equal(demo.choice_browser.candidate_count(), human_choices.size(), "compact browser preserves every human-selectable candidate")

	var unresolved: int = 0
	for choice_value in human_choices:
		var choice: Dictionary = choice_value
		var candidate_index: int = int(choice.get("index", -1))
		var path: Dictionary = demo.choice_browser.path_for_candidate(candidate_index)
		if path.is_empty():
			unresolved += 1
			continue
		var resolved: int = demo.choice_browser.resolve_candidate(
			str(path.get("club_key", "")),
			str(path.get("aim_key", "")),
			str(path.get("shot_key", ""))
		)
		if resolved != candidate_index:
			unresolved += 1
	_assert_equal(unresolved, 0, "every authority-issued candidate round-trips through Club-Aim-Shot browser")

	var browser_snapshot: Dictionary = demo.choice_browser.snapshot()
	_assert_true(int(browser_snapshot.get("club_count", 0)) > 0, "browser exposes at least one club bucket")
	_assert_true(int(browser_snapshot.get("aim_count", 0)) > 0, "browser exposes aim buckets")
	_assert_true(int(browser_snapshot.get("max_shots_in_leaf", 0)) < human_choices.size(), "no UI leaf exposes the original flat candidate explosion")
	_assert_true(demo.club_select.item_count < human_choices.size(), "club selector is materially smaller than flat authority list")
	_assert_true(demo.aim_select.item_count < human_choices.size(), "aim selector is materially smaller than flat authority list")
	_assert_true(demo.shot_select.item_count < human_choices.size(), "shot selector is materially smaller than flat authority list")

	var selected_candidate: int = demo.selected_candidate_index()
	_assert_true(selected_candidate >= 0, "launchable UI resolves its selected path to a valid authority candidate index")
	var selected_path: Dictionary = demo.choice_browser.path_for_candidate(selected_candidate)
	_assert_true(not selected_path.is_empty(), "selected candidate is traceable back through compact browser")

	# Browsing is presentation-only. Merely populating/changing selectors cannot
	# play golf or mutate the pending authoritative decision.
	var before_shots: int = demo.controller.group_live_shot_count("group_1")
	var before_decision_id: String = str(demo.session.pending_human_decision("group_1").get("decision_id", ""))
	if demo.club_select.item_count > 1:
		demo.club_select.select(1)
		demo._on_club_selected(1)
	if demo.aim_select.item_count > 1:
		demo.aim_select.select(1)
		demo._on_aim_selected(1)
	_assert_equal(demo.controller.group_live_shot_count("group_1"), before_shots, "browsing choices cannot execute a golf shot")
	_assert_equal(str(demo.session.pending_human_decision("group_1").get("decision_id", "")), before_decision_id, "browsing choices cannot replace authoritative pending decision")

	print("POC26E_CHOICE_BROWSER_SUMMARY candidates=%d clubs=%d aims=%d max_leaf=%d selected=%d" % [
		human_choices.size(),
		int(browser_snapshot.get("club_count", 0)),
		int(browser_snapshot.get("aim_count", 0)),
		int(browser_snapshot.get("max_shots_in_leaf", 0)),
		selected_candidate
	])
	_finish()


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


func _finish() -> void:
	if demo != null and is_instance_valid(demo):
		demo.queue_free()
	if failures == 0:
		print("POC-26E COMPACT PARTICIPATE CHOICE BROWSER PASSED")
		quit(0)
	else:
		push_error("POC-26E COMPACT PARTICIPATE CHOICE BROWSER FAILED: %d" % failures)
		quit(1)
