extends RefCounted

# POC-24F / POC-25D: Same-Hole Release Scheduler
# -----------------------------------------------
# Converts the spacing model's relative safe-tee milestone into an absolute
# simulated traffic event. POC-25D also carries the ordered-shot milestone that
# produced the clearance so spectator playback and traffic can agree exactly.
#
# POC-25 spectator start policy adds a second authoritative gate: the following
# group cannot be released before every lead-group golfer is on the green (or
# holed out). The final release is the later of the reach-safety milestone and
# the all-lead-golfers-on-green milestone.

const SameHoleSpacingModel = preload("res://simulation/same_hole_spacing_model.gd")

var spacing_model = SameHoleSpacingModel.new()
var pending_by_group: Dictionary = {}

func schedule_release(lead_group_id: String, following_group_id: String, lead_group_result: Dictionary, hole_definition, following_golfers: Array, lead_start_time_seconds: float, tee_id: String = "default") -> Dictionary:
	var lead_id := lead_group_id.strip_edges()
	var follower_id := following_group_id.strip_edges()
	if lead_id.is_empty() or follower_id.is_empty() or lead_id == follower_id:
		return {}
	if hole_definition == null or lead_start_time_seconds < 0.0:
		return {}
	if pending_by_group.has(follower_id):
		return pending_by_group[follower_id].duplicate(true)

	var spacing: Dictionary = spacing_model.earliest_safe_tee_time(lead_group_result, hole_definition, following_golfers, tee_id)
	if not bool(spacing.get("safe", false)):
		return {
			"scheduled": false,
			"lead_group_id": lead_id,
			"following_group_id": follower_id,
			"hole_number": int(hole_definition.hole_number),
			"status": str(spacing.get("status", "WAIT_FOR_HOLE_CLEAR")),
			"credible_reach_yards": float(spacing.get("credible_reach_yards", 0.0))
		}

	var green_gate: Dictionary = spacing_model.earliest_all_members_green_time(lead_group_result, hole_definition, tee_id)
	if not bool(green_gate.get("reached", false)):
		return {
			"scheduled": false,
			"lead_group_id": lead_id,
			"following_group_id": follower_id,
			"hole_number": int(hole_definition.hole_number),
			"status": str(green_gate.get("status", "WAIT_FOR_LEAD_GROUP_GREEN")),
			"credible_reach_yards": float(spacing.get("credible_reach_yards", 0.0)),
			"range_safe_time_seconds": float(spacing.get("safe_time_seconds", 0.0))
		}

	var range_safe_time: float = float(spacing.get("safe_time_seconds", 0.0))
	var green_time: float = float(green_gate.get("green_time_seconds", 0.0))
	var relative_time: float = max(range_safe_time, green_time)
	var release_milestone: Dictionary = spacing if range_safe_time >= green_time else green_gate
	var event := {
		"scheduled": true,
		"status": "SCHEDULED_SAFE_TEE_RELEASE",
		"release_rule": "RANGE_SAFE_AND_ALL_LEAD_GOLFERS_ON_GREEN",
		"lead_group_id": lead_id,
		"following_group_id": follower_id,
		"hole_number": int(hole_definition.hole_number),
		"lead_start_time_seconds": lead_start_time_seconds,
		"relative_safe_time_seconds": relative_time,
		"release_time_seconds": lead_start_time_seconds + relative_time,
		"range_safe_time_seconds": range_safe_time,
		"lead_group_green_time_seconds": green_time,
		"credible_reach_yards": float(spacing.get("credible_reach_yards", 0.0)),
		"safe_clearance_yards": float(release_milestone.get("safe_clearance_yards", 0.0)),
		"shot_wave": int(release_milestone.get("shot_wave", 0)),
		"sequence_index": int(release_milestone.get("sequence_index", -1)),
		"member_index": int(release_milestone.get("member_index", -1))
	}
	pending_by_group[follower_id] = event
	return event.duplicate(true)

func due_releases(current_time_seconds: float) -> Array:
	if current_time_seconds < 0.0:
		return []
	var due: Array = []
	for follower_id in pending_by_group.keys():
		var event: Dictionary = pending_by_group[follower_id]
		if float(event.get("release_time_seconds", INF)) <= current_time_seconds:
			due.append(event.duplicate(true))
	due.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_time: float = float(a.get("release_time_seconds", 0.0))
		var b_time: float = float(b.get("release_time_seconds", 0.0))
		if is_equal_approx(a_time, b_time):
			return str(a.get("following_group_id", "")) < str(b.get("following_group_id", ""))
		return a_time < b_time
	)
	for event in due:
		pending_by_group.erase(str(event.get("following_group_id", "")))
	return due

func pending_release(following_group_id: String) -> Dictionary:
	return pending_by_group.get(following_group_id.strip_edges(), {}).duplicate(true)

func cancel_release(following_group_id: String) -> bool:
	var follower_id := following_group_id.strip_edges()
	if not pending_by_group.has(follower_id):
		return false
	pending_by_group.erase(follower_id)
	return true

func snapshot() -> Dictionary:
	var pending: Array = []
	for event in pending_by_group.values():
		pending.append(event.duplicate(true))
	pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("release_time_seconds", 0.0)) < float(b.get("release_time_seconds", 0.0))
	)
	return {"pending_count": pending.size(), "pending_releases": pending}
