extends RefCounted

# POC-29B-F: Player Activity Selection Contract
# ---------------------------------------------
# Pure validation/catalog contract between the persistent world hub and activity
# launchers. Selecting an activity is intentionally NOT the same thing as launching
# it: this layer validates player intent without mutating golfer, world, controller,
# clock, population, or per-activity authority.
#
# Availability checks deliberately inspect only configuration/activity state. They
# must not deep-snapshot the entire accumulated world just to decide whether the
# player can choose an activity.

const ACTIVITY_ROUND := "ROUND"
const ACTIVITY_PRACTICE := "PRACTICE"

const REASON_SESSION_NOT_CONFIGURED := "SESSION_NOT_CONFIGURED"
const REASON_ACTIVITY_ALREADY_ACTIVE := "PLAYER_ACTIVITY_ALREADY_ACTIVE"
const REASON_UNKNOWN_ACTIVITY := "UNKNOWN_ACTIVITY"

const DEFINITIONS := {
	ACTIVITY_ROUND: {
		"activity_type": ACTIVITY_ROUND,
		"label": "Play a Round",
		"description": "Enter an ordinary group in the living golf world and play a scored round."
	},
	ACTIVITY_PRACTICE: {
		"activity_type": ACTIVITY_PRACTICE,
		"label": "Practice",
		"description": "Practice golf while preserving the same golfer, world clock, activity history, and development state."
	}
}


func catalog(session) -> Array:
	var result: Array = []
	for activity_type in [ACTIVITY_ROUND, ACTIVITY_PRACTICE]:
		var definition: Dictionary = DEFINITIONS.get(activity_type, {}).duplicate(true)
		var availability: Dictionary = availability_for(session, activity_type)
		definition["available"] = bool(availability.get("available", false))
		definition["reason"] = str(availability.get("reason", ""))
		result.append(definition)
	return result


func availability_for(session, activity_type: String) -> Dictionary:
	var normalized: String = activity_type.strip_edges().to_upper()
	if not DEFINITIONS.has(normalized):
		return {"available": false, "reason": REASON_UNKNOWN_ACTIVITY, "activity_type": normalized}
	if not _session_configured(session):
		return {"available": false, "reason": REASON_SESSION_NOT_CONFIGURED, "activity_type": normalized}
	if not session.active_round.is_empty() or not session.active_practice.is_empty():
		return {"available": false, "reason": REASON_ACTIVITY_ALREADY_ACTIVE, "activity_type": normalized}
	return {"available": true, "reason": "", "activity_type": normalized}


func select(session, activity_type: String, options: Dictionary = {}) -> Dictionary:
	var normalized: String = activity_type.strip_edges().to_upper()
	var availability: Dictionary = availability_for(session, normalized)
	if not bool(availability.get("available", false)):
		return {
			"accepted": false,
			"activity_type": normalized,
			"reason": str(availability.get("reason", REASON_UNKNOWN_ACTIVITY)),
			"options": {}
		}

	return {
		"accepted": true,
		"activity_type": normalized,
		"reason": "",
		"options": options.duplicate(true)
	}


func _session_configured(session) -> bool:
	return (
		session != null
		and session.player_golfer != null
		and session.controller != null
		and session.course != null
	)
