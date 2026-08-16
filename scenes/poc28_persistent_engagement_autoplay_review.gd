extends "res://scenes/poc28_persistent_engagement_demo.gd"

# POC-28 manual-review accelerator
# --------------------------------
# Uses only the existing authoritative human decision contract, but automatically
# commits a valid human-selectable candidate and drains presentation immediately.
# This is a review/debug scene, not normal gameplay: it exists so post-round
# results and persistent-world transitions can be inspected without manually
# playing another full 18 holes.

@export var autorun_steps_per_frame: int = 256
@export var fallback_world_step_seconds: float = 60.0

var autoplay_human_shots: int = 0
var autoplay_frames: int = 0
var autoplay_stalled_frames: int = 0
var _results_announced: bool = false


func _process(delta: float) -> void:
	if not initialized:
		return

	# Once results are reached, stop completely so the reviewer can inspect the
	# real POC-28 results screen and choose when to return to the persistent world.
	if engagement_state == "RESULTS":
		if not _results_announced:
			_results_announced = true
			_print_autoplay_summary()
		return

	# The review shortcut ends at the results screen. Once the reviewer explicitly
	# returns to the world hub, resume the base scene's ordinary living-world clock
	# so autonomous groups keep existing and progressing normally.
	if engagement_state == "WORLD":
		super._process(delta)
		return

	autoplay_frames += 1
	var progressed: bool = _autorun_playing_round()
	if progressed:
		autoplay_stalled_frames = 0
	else:
		autoplay_stalled_frames += 1

	_sync_world_session_from_controller()
	if session != null:
		session.drain_visuals_immediate()
	_maybe_finalize_player_round()

	# Keep the ordinary HUD/context projection current while the authority races
	# ahead. No presentation result feeds back into the simulation.
	if engagement_state == "PLAYING":
		_refresh_presentation(0.0, true)


func _begin_next_round() -> void:
	var previous_round: int = round_number
	super._begin_next_round()
	if engagement_state == "PLAYING" and round_number > previous_round:
		autoplay_human_shots = 0
		autoplay_frames = 0
		autoplay_stalled_frames = 0
		_results_announced = false


func _autorun_playing_round() -> bool:
	if engagement_state != "PLAYING" or session == null or controller == null:
		return false

	var any_progress: bool = false
	var steps: int = maxi(1, autorun_steps_per_frame)
	for _index in range(steps):
		if engagement_state != "PLAYING" or _player_round_authority_complete():
			break

		# Immediate draining removes only visual waiting. Authority remains exactly
		# where the living-course controller says it is.
		session.drain_visuals_immediate()
		var decision: Dictionary = session.pending_human_decision(active_player_group_id)
		if not decision.is_empty():
			var candidate_index: int = _preferred_autoplay_candidate(decision)
			if candidate_index < 0:
				push_error("POC-28 autoplay review found no human-selectable candidate")
				break
			var committed: Dictionary = session.submit_human_choice(active_player_group_id, candidate_index, false)
			if not bool(committed.get("played", false)):
				push_error("POC-28 autoplay review could not commit authoritative human choice: %s" % str(committed.get("reason", "UNKNOWN")))
				break
			autoplay_human_shots += 1
			any_progress = true
			_sync_world_session_from_controller()
			continue

		var before_time: float = float(controller.current_time_seconds)
		var pacing: Dictionary = participate_pacing.idle_advance(controller, active_player_group_id)
		var advance_seconds: float = 0.0
		if str(pacing.get("mode", "")) == "FAST_FORWARD":
			advance_seconds = maxf(0.0, float(pacing.get("delta_seconds", 0.0)))
		if advance_seconds <= 0.0001:
			advance_seconds = maxf(fallback_world_step_seconds, 0.001)
		session.advance_time(advance_seconds, false)
		_sync_world_session_from_controller()
		if float(controller.current_time_seconds) > before_time + 0.0001:
			any_progress = true

	# Final visual drain allows the ordinary completion/finalization gate to see
	# that all authoritative player-group presentation has caught up.
	session.drain_visuals_immediate()
	return any_progress


func _preferred_autoplay_candidate(decision: Dictionary) -> int:
	var choices: Array = decision.get("choices", [])

	# Keep putting review behavior stable and sensible by preferring the neutral
	# strategy when the authoritative choice set offers it.
	if str(decision.get("decision_kind", "")) == "PUTTING":
		for index in range(choices.size()):
			if typeof(choices[index]) != TYPE_DICTIONARY:
				continue
			var choice: Dictionary = choices[index]
			if bool(choice.get("human_selectable", false)) and str(choice.get("putting_strategy", "")) == "NEUTRAL":
				return int(choice.get("index", index))

	# For every other shot, take the first option the normal human contract marks
	# selectable. The autorunner never constructs, evaluates, or predicts a shot.
	for index in range(choices.size()):
		if typeof(choices[index]) != TYPE_DICTIONARY:
			continue
		var choice: Dictionary = choices[index]
		if bool(choice.get("human_selectable", false)):
			return int(choice.get("index", index))
	return -1


func _print_autoplay_summary() -> void:
	var archive: Dictionary = last_completed_round
	print("POC28_AUTOPLAY_REVIEW_READY round=%d score=%d to_par=%s human_shots=%d world_time=%.1f state=%s" % [
		int(archive.get("sequence", round_number)),
		int(archive.get("total_strokes", 0)),
		_score_label(int(archive.get("score_to_par", 0))),
		autoplay_human_shots,
		float(world_session.world_time_seconds) if world_session != null else 0.0,
		engagement_state
	])
