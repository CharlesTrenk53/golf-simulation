extends SceneTree

const PlayerWorldSession = preload("res://simulation/player_world_session.gd")
const PlayerWorldHub = preload("res://simulation/player_world_hub.gd")
const PlayerActivityContract = preload("res://simulation/player_activity_contract.gd")
const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const Golfer = preload("res://scenes/golfer.gd")

const STEP_SECONDS := 60.0
const MAX_ITERATIONS := 1600

var created_nodes: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("POC-29F DIAGNOSTIC: full practice-to-round progression")
	var course = POC27Course.build()
	var player = _new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var persistent = PlayerWorldSession.new()
	get_root().add_child(persistent)
	created_nodes.append(persistent)
	print("TRACE 01 configure=", persistent.configure(player, course, 50, 28800.0))
	var hub = PlayerWorldHub.new()
	print("TRACE 02 hub configure=", hub.configure(persistent))

	var practice_selection: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_PRACTICE, {
		"total_repetitions": 30,
		"focus": {3: 1.0},
		"quality": 0.8,
		"duration_seconds": 600.0
	})
	print("TRACE 03 practice selected=", practice_selection.get("accepted", false))
	print("TRACE 04 practice launched=", hub.launch_selected_activity(practice_selection).get("launched", false))
	var practice_return: Dictionary = hub.return_to_world("AUTO", {
		"observations": {3: {"execution_score": 76.0, "lateral_error": 0.0, "distance_error": 0.6}}
	})
	print("TRACE 05 practice returned=", practice_return.get("returned", false), " time=", persistent.world_time_seconds)

	var partner = _new_golfer(Golfer.GolferProfile.WILD_BILL)
	var round_selection: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_ROUND, {
		"group_id": "poc29_diag_round",
		"other_golfers": [partner],
		"tee_id": "default",
		"player_member_index": 0,
		"seed_base": 29501
	})
	print("TRACE 06 round selected=", round_selection.get("accepted", false))
	var round_launch: Dictionary = hub.launch_selected_activity(round_selection)
	print("TRACE 07 round launched=", round_launch.get("launched", false))
	print("TRACE 08 release=", persistent.release_next_group())

	var last_hole := -1
	var iterations := 0
	while iterations < MAX_ITERATIONS:
		var state = persistent.player_round_state()
		var hole_number := int(state.current_hole_number()) if state != null else -1
		if hole_number != last_hole:
			print("TRACE HOLE iteration=", iterations, " hole=", hole_number, " time=", persistent.world_time_seconds, " status=", persistent.active_round.get("status", ""))
			last_hole = hole_number

		if state != null and bool(state.complete):
			var group_id: String = str(persistent.active_round.get("group_id", ""))
			var group = persistent.controller.living_course.population.group_by_id(group_id)
			print("TRACE COMPLETE state=true group_status=", str(group.status) if group != null else "NULL", " traffic_hole=", persistent.controller.traffic.group_hole(group_id))
			if group != null and str(group.status) == "FINISHED" and persistent.controller.traffic.group_hole(group_id) == 0:
				break

		if iterations % 25 == 0:
			print("TRACE LOOP iteration=", iterations, " hole=", hole_number, " time=", persistent.world_time_seconds)

		print("TRACE STEP ", iterations, " before pending")
		var decision: Dictionary = persistent.pending_player_decision()
		print("TRACE STEP ", iterations, " after pending size=", decision.size(), " kind=", decision.get("decision_kind", ""))
		if not decision.is_empty():
			var candidate_index: int = _preferred_human_candidate(decision)
			print("TRACE STEP ", iterations, " candidate=", candidate_index, " before submit")
			if candidate_index < 0:
				print("TRACE ERROR no selectable candidate")
				break
			var committed: Dictionary = persistent.submit_player_choice(candidate_index)
			print("TRACE STEP ", iterations, " after submit played=", committed.get("played", false), " reason=", committed.get("reason", ""))
			if not bool(committed.get("played", false)):
				print("TRACE ERROR submit rejected=", committed)
				break
		else:
			print("TRACE STEP ", iterations, " before advance")
			var events: Array = persistent.advance_world_time(STEP_SECONDS)
			print("TRACE STEP ", iterations, " after advance events=", events.size(), " time=", persistent.world_time_seconds)
		iterations += 1

	print("TRACE END iterations=", iterations, " time=", persistent.world_time_seconds)
	var final_state = persistent.player_round_state()
	print("TRACE END state_complete=", bool(final_state.complete) if final_state != null else false, " holes=", int(final_state.holes_completed()) if final_state != null else -1)
	print("POC-29F FULL ROUND DIAGNOSTIC COMPLETE")
	_cleanup()
	quit(0)

func _preferred_human_candidate(decision: Dictionary) -> int:
	var choices: Array = decision.get("choices", [])
	if str(decision.get("decision_kind", "")) == "PUTTING":
		for index in range(choices.size()):
			if typeof(choices[index]) != TYPE_DICTIONARY:
				continue
			var choice: Dictionary = choices[index]
			if bool(choice.get("human_selectable", false)) and str(choice.get("putting_strategy", "")) == "NEUTRAL":
				return int(choice.get("index", index))
	for index in range(choices.size()):
		if typeof(choices[index]) == TYPE_DICTIONARY and bool(choices[index].get("human_selectable", false)):
			return int(choices[index].get("index", index))
	return -1

func _new_golfer(profile_value: int):
	var golfer = QuietGolfer.new()
	golfer.profile = profile_value
	golfer.apply_profile()
	get_root().add_child(golfer)
	created_nodes.append(golfer)
	return golfer

func _cleanup() -> void:
	for node in created_nodes:
		if node != null and is_instance_valid(node):
			node.queue_free()
