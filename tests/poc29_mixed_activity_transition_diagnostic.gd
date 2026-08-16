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
	print("POC-29F DIAGNOSTIC: full mixed activity progression")
	var course = POC27Course.build()
	var player = _new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var persistent = PlayerWorldSession.new()
	get_root().add_child(persistent)
	created_nodes.append(persistent)
	print("TRACE 01 configure=", persistent.configure(player, course, 50, 28800.0))
	var hub = PlayerWorldHub.new()
	print("TRACE 02 hub configure=", hub.configure(persistent))
	var player_id: int = player.get_instance_id()
	var controller_id: int = persistent.controller.get_instance_id()

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

		var decision: Dictionary = persistent.pending_player_decision()
		if not decision.is_empty():
			var candidate_index: int = _preferred_human_candidate(decision)
			if candidate_index < 0:
				print("TRACE ERROR no selectable candidate iteration=", iterations)
				break
			var committed: Dictionary = persistent.submit_player_choice(candidate_index)
			if not bool(committed.get("played", false)):
				print("TRACE ERROR submit rejected iteration=", iterations, " result=", committed)
				break
		else:
			persistent.advance_world_time(STEP_SECONDS)
		iterations += 1

	print("TRACE 09 round loop end iterations=", iterations, " time=", persistent.world_time_seconds)
	var final_state = persistent.player_round_state()
	print("TRACE 10 state object valid=", final_state != null)
	print("TRACE 11 state_complete=", bool(final_state.complete) if final_state != null else false)
	print("TRACE 12 holes=", int(final_state.holes_completed()) if final_state != null else -1)
	print("TRACE 13 memory shots=", int(player.shots_attempted))
	print("TRACE 14 before hub round return")
	var round_return: Dictionary = hub.return_to_world()
	print("TRACE 15 after hub round return returned=", round_return.get("returned", false), " completed=", round_return.get("completed", false), " reason=", round_return.get("reason", ""))
	print("TRACE 16 completed_rounds=", persistent.completed_rounds.size(), " career_rounds=", persistent.golf_activity.career_rounds_played)
	print("TRACE 17 active_round_empty=", persistent.active_round.is_empty(), " population=", persistent.controller.living_course.population.group_count())
	print("TRACE 18 identity golfer=", player.get_instance_id() == player_id, " controller=", persistent.controller.get_instance_id() == controller_id)
	print("TRACE 19 hub_state=", hub.context().get("state", ""), " active=", hub.context().get("active_activity_type", ""))
	print("TRACE 20 latest round begin")
	var round_archive: Dictionary = persistent.latest_completed_round()
	print("TRACE 21 latest round shots=", round_archive.get("statistics", {}).get("total_shots", -1), " strokes=", round_archive.get("total_strokes", -1))
	print("TRACE 22 development snapshot begin")
	var development_after_round: Dictionary = persistent.development_snapshot()
	print("TRACE 23 development snapshot skills=", development_after_round.size())

	print("TRACE 24 second practice select begin")
	var practice_2_selection: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_PRACTICE, {
		"total_repetitions": 20,
		"focus": {1: 1.0},
		"quality": 0.5,
		"duration_seconds": 300.0
	})
	print("TRACE 25 second practice selected=", practice_2_selection.get("accepted", false), " reason=", practice_2_selection.get("reason", ""))
	print("TRACE 26 second practice launch begin")
	var practice_2_launch: Dictionary = hub.launch_selected_activity(practice_2_selection)
	print("TRACE 27 second practice launched=", practice_2_launch.get("launched", false), " reason=", practice_2_launch.get("reason", ""))
	print("TRACE 28 second practice return begin")
	var practice_2_return: Dictionary = hub.return_to_world("COMPLETE", {
		"observations": {1: {"execution_score": 72.0, "lateral_error": 2.0, "distance_error": 3.0}}
	})
	print("TRACE 29 second practice returned=", practice_2_return.get("returned", false), " completed=", practice_2_return.get("completed", false), " reason=", practice_2_return.get("reason", ""))
	print("TRACE 30 final practices=", persistent.completed_practices.size(), " rounds=", persistent.completed_rounds.size(), " reps=", persistent.golf_activity.total_practice_repetitions())
	print("TRACE 31 final identity golfer=", player.get_instance_id() == player_id, " controller=", persistent.controller.get_instance_id() == controller_id)
	print("POC-29F FULL MIXED DIAGNOSTIC COMPLETE")
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
