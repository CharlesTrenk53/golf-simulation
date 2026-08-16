extends SceneTree

const PlayerWorldSession = preload("res://simulation/player_world_session.gd")
const PlayerWorldHub = preload("res://simulation/player_world_hub.gd")
const PlayerActivityContract = preload("res://simulation/player_activity_contract.gd")
const POC27Course = preload("res://simulation/poc27_eighteen_hole_course.gd")
const QuietGolfer = preload("res://tests/quiet_golfer.gd")
const Golfer = preload("res://scenes/golfer.gd")

var created_nodes: Array = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("POC-29F DIAGNOSTIC: practice-to-round transition")
	var course = POC27Course.build()
	var player = _new_golfer(Golfer.GolferProfile.CAREFUL_CARL)
	var persistent = PlayerWorldSession.new()
	get_root().add_child(persistent)
	created_nodes.append(persistent)
	print("TRACE 01 configure begin")
	print("TRACE 02 configure=", persistent.configure(player, course, 50, 28800.0))
	var hub = PlayerWorldHub.new()
	print("TRACE 03 hub configure=", hub.configure(persistent))

	var practice_selection: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_PRACTICE, {
		"total_repetitions": 30,
		"focus": {3: 1.0},
		"quality": 0.8,
		"duration_seconds": 600.0
	})
	print("TRACE 04 practice selected=", practice_selection)
	print("TRACE 05 practice launched=", hub.launch_selected_activity(practice_selection))
	print("TRACE 06 practice return begin")
	var practice_return: Dictionary = hub.return_to_world("AUTO", {
		"observations": {3: {"execution_score": 76.0, "lateral_error": 0.0, "distance_error": 0.6}}
	})
	print("TRACE 07 practice return=", practice_return.get("returned", false), " time=", persistent.world_time_seconds, " putting=", player.putting)

	var partner = _new_golfer(Golfer.GolferProfile.WILD_BILL)
	var round_selection: Dictionary = hub.select_activity(PlayerActivityContract.ACTIVITY_ROUND, {
		"group_id": "poc29_diag_round",
		"other_golfers": [partner],
		"tee_id": "default",
		"player_member_index": 0,
		"seed_base": 29501
	})
	print("TRACE 08 round selected=", round_selection.get("accepted", false))
	var round_launch: Dictionary = hub.launch_selected_activity(round_selection)
	print("TRACE 09 round launched=", round_launch.get("launched", false), " entry=", round_launch.get("entry", {}))
	var release: Dictionary = persistent.release_next_group()
	print("TRACE 10 release=", release)
	print("TRACE 11 active_round=", persistent.active_round)
	print("TRACE 12 before pending decision")
	var decision: Dictionary = persistent.pending_player_decision()
	print("TRACE 13 pending decision size=", decision.size(), " kind=", decision.get("decision_kind", ""))
	print("TRACE 14 before first advance")
	var events: Array = persistent.advance_world_time(60.0)
	print("TRACE 15 after first advance events=", events.size(), " time=", persistent.world_time_seconds)
	print("TRACE 16 before second pending decision")
	decision = persistent.pending_player_decision()
	print("TRACE 17 second pending size=", decision.size(), " kind=", decision.get("decision_kind", ""))
	if not decision.is_empty():
		var choices: Array = decision.get("choices", [])
		print("TRACE 18 choices=", choices.size())
		var candidate_index := -1
		for i in range(choices.size()):
			if typeof(choices[i]) == TYPE_DICTIONARY and bool(choices[i].get("human_selectable", false)):
				candidate_index = int(choices[i].get("index", i))
				break
		print("TRACE 19 candidate=", candidate_index)
		if candidate_index >= 0:
			print("TRACE 20 before submit")
			var committed: Dictionary = persistent.submit_player_choice(candidate_index)
			print("TRACE 21 after submit=", committed.get("played", false), " reason=", committed.get("reason", ""))
	print("POC-29F DIAGNOSTIC COMPLETE")
	_cleanup()
	quit(0)

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
