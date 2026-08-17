extends RefCounted

# POC-29C/D: Player Activity Launcher
# -----------------------------------
# Consumes an already-validated PlayerActivityContract selection and delegates
# mutation to the existing persistent-session activity authority. ROUND launch is
# only an adapter to enter_round(); PRACTICE launch is only an adapter to
# enter_practice(). Neither path invents outcomes or bypasses world authority.

const PlayerActivityContract = preload("res://simulation/player_activity_contract.gd")

const REASON_SELECTION_NOT_ACCEPTED := "SELECTION_NOT_ACCEPTED"
const REASON_ACTIVITY_NOT_IMPLEMENTED := "ACTIVITY_NOT_IMPLEMENTED"


func launch(session, selection: Dictionary) -> Dictionary:
	if not bool(selection.get("accepted", false)):
		return {
			"launched": false,
			"activity_type": str(selection.get("activity_type", "")),
			"reason": REASON_SELECTION_NOT_ACCEPTED
		}

	var activity_type: String = str(selection.get("activity_type", "")).strip_edges().to_upper()
	match activity_type:
		PlayerActivityContract.ACTIVITY_ROUND:
			return _launch_round(session, selection.get("options", {}))
		PlayerActivityContract.ACTIVITY_PRACTICE:
			return _launch_practice(session, selection.get("options", {}))
		_:
			return {
				"launched": false,
				"activity_type": activity_type,
				"reason": REASON_ACTIVITY_NOT_IMPLEMENTED
			}


func _launch_round(session, options_value) -> Dictionary:
	if session == null:
		return {
			"launched": false,
			"activity_type": PlayerActivityContract.ACTIVITY_ROUND,
			"reason": PlayerActivityContract.REASON_SESSION_NOT_CONFIGURED
		}
	if typeof(options_value) != TYPE_DICTIONARY:
		return {
			"launched": false,
			"activity_type": PlayerActivityContract.ACTIVITY_ROUND,
			"reason": "INVALID_ACTIVITY_OPTIONS"
		}

	var options: Dictionary = options_value
	var other_golfers_value = options.get("other_golfers", [])
	if typeof(other_golfers_value) != TYPE_ARRAY:
		return {
			"launched": false,
			"activity_type": PlayerActivityContract.ACTIVITY_ROUND,
			"reason": "INVALID_OTHER_GOLFERS"
		}
	var other_golfers: Array = other_golfers_value
	var group_id: String = str(options.get("group_id", ""))
	var tee_id: String = str(options.get("tee_id", "default"))
	var player_member_index: int = int(options.get("player_member_index", 0))
	var seed_base: int = int(options.get("seed_base", 1))

	var entered: Dictionary = session.enter_round(
		group_id,
		other_golfers,
		tee_id,
		player_member_index,
		seed_base
	)
	if not bool(entered.get("entered", false)):
		return {
			"launched": false,
			"activity_type": PlayerActivityContract.ACTIVITY_ROUND,
			"reason": str(entered.get("reason", "ROUND_ENTRY_REJECTED")),
			"entry": entered.duplicate(true)
		}

	return {
		"launched": true,
		"activity_type": PlayerActivityContract.ACTIVITY_ROUND,
		"reason": "",
		"entry": entered.duplicate(true)
	}


func _launch_practice(session, options_value) -> Dictionary:
	if session == null:
		return {
			"launched": false,
			"activity_type": PlayerActivityContract.ACTIVITY_PRACTICE,
			"reason": PlayerActivityContract.REASON_SESSION_NOT_CONFIGURED
		}
	if typeof(options_value) != TYPE_DICTIONARY:
		return {
			"launched": false,
			"activity_type": PlayerActivityContract.ACTIVITY_PRACTICE,
			"reason": "INVALID_ACTIVITY_OPTIONS"
		}

	var options: Dictionary = options_value
	var focus_value = options.get("focus", {})
	if typeof(focus_value) != TYPE_DICTIONARY:
		return {
			"launched": false,
			"activity_type": PlayerActivityContract.ACTIVITY_PRACTICE,
			"reason": "INVALID_PRACTICE_FOCUS"
		}
	var total_repetitions: int = int(options.get("total_repetitions", 0))
	var quality: float = float(options.get("quality", 1.0))
	var duration_seconds: float = float(options.get("duration_seconds", 1800.0))
	var entered: Dictionary = session.enter_practice(
		total_repetitions,
		focus_value,
		quality,
		duration_seconds
	)
	if not bool(entered.get("entered", false)):
		return {
			"launched": false,
			"activity_type": PlayerActivityContract.ACTIVITY_PRACTICE,
			"reason": str(entered.get("reason", "PRACTICE_ENTRY_REJECTED")),
			"entry": entered.duplicate(true)
		}
	return {
		"launched": true,
		"activity_type": PlayerActivityContract.ACTIVITY_PRACTICE,
		"reason": "",
		"entry": entered.duplicate(true)
	}
