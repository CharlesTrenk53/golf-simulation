extends "res://scenes/participate_spectator_session.gd"

# POC-28 player-facing persistence helper.
# ----------------------------------------
# The base ParticipateSpectatorSession already owns all presentation behavior.
# This thin subclass exposes one safe presentation-facing seam for a world that
# already exists: ask the authoritative controller to release the next waiting
# group and, if it succeeds, immediately feed that already-authoritative event
# into the normal presentation queue. No shot, traffic, or scoring logic lives
# here.

func attempt_release_next(animate: bool = true) -> Dictionary:
	if controller == null or not started:
		return {}
	var result: Dictionary = controller.release_next_group()
	if not bool(result.get("released", false)):
		return result
	_handle_authority_event(result, animate)
	if not animate:
		drain_visuals_immediate()
	else:
		_present_next_global(true)
	return result
