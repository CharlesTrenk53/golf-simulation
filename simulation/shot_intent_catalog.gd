extends RefCounted

const ShotIntent = preload("res://simulation/shot_intent.gd")

# POC-14A deliberately separates feasibility from later strategy scoring.
# This catalog answers only: "What kinds of shots can reasonably be attempted
# with this club from this lie?" It does not decide which one is best.


func intents_for(club: Dictionary, surface: String) -> Array[Dictionary]:
	var intents: Array[Dictionary] = []
	var family: String = str(club.get("family", "")).to_upper()
	var club_id: String = str(club.get("id", ""))
	var lie: String = surface.to_upper()

	if family == "PUTTER":
		# Putting gets its own pace/line/strike intent model later in POC-14.
		return intents

	_add_unique(intents, ShotIntent.make())

	if family in ["DRIVER", "WOOD", "HYBRID", "IRON"]:
		_add_unique(intents, ShotIntent.make(ShotIntent.Trajectory.NORMAL, ShotIntent.Shape.DRAW))
		_add_unique(intents, ShotIntent.make(ShotIntent.Trajectory.NORMAL, ShotIntent.Shape.FADE))
		_add_unique(intents, ShotIntent.make(ShotIntent.Trajectory.LOW, ShotIntent.Shape.STRAIGHT))
		_add_unique(intents, ShotIntent.make(ShotIntent.Trajectory.HIGH, ShotIntent.Shape.STRAIGHT))

	if family in ["DRIVER", "WOOD", "HYBRID", "IRON"] and lie in ["TEE", "FAIRWAY"]:
		_add_unique(intents, ShotIntent.make(
			ShotIntent.Trajectory.LOW,
			ShotIntent.Shape.STRAIGHT,
			ShotIntent.SwingLength.FULL,
			ShotIntent.Technique.STINGER
		))

	if family in ["HYBRID", "IRON", "WEDGE"] and lie != "BUNKER":
		_add_unique(intents, ShotIntent.make(
			ShotIntent.Trajectory.LOW,
			ShotIntent.Shape.STRAIGHT,
			ShotIntent.SwingLength.THREE_QUARTER,
			ShotIntent.Technique.PUNCH
		))

	if family == "WEDGE":
		if lie == "BUNKER":
			_add_unique(intents, ShotIntent.make(
				ShotIntent.Trajectory.HIGH,
				ShotIntent.Shape.STRAIGHT,
				ShotIntent.SwingLength.TOUCH,
				ShotIntent.Technique.BUNKER
			))
		else:
			_add_unique(intents, ShotIntent.make(
				ShotIntent.Trajectory.NORMAL,
				ShotIntent.Shape.STRAIGHT,
				ShotIntent.SwingLength.THREE_QUARTER,
				ShotIntent.Technique.PITCH
			))
			_add_unique(intents, ShotIntent.make(
				ShotIntent.Trajectory.NORMAL,
				ShotIntent.Shape.STRAIGHT,
				ShotIntent.SwingLength.HALF,
				ShotIntent.Technique.PITCH
			))
			_add_unique(intents, ShotIntent.make(
				ShotIntent.Trajectory.LOW,
				ShotIntent.Shape.STRAIGHT,
				ShotIntent.SwingLength.TOUCH,
				ShotIntent.Technique.BUMP_AND_RUN
			))
			if club_id in ["SAND_WEDGE", "LOB_WEDGE"] and lie in ["FAIRWAY", "ROUGH"]:
				_add_unique(intents, ShotIntent.make(
					ShotIntent.Trajectory.HIGH,
					ShotIntent.Shape.STRAIGHT,
					ShotIntent.SwingLength.TOUCH,
					ShotIntent.Technique.FLOP
				))

	return intents


func _add_unique(intents: Array[Dictionary], intent: Dictionary) -> void:
	var intent_signature: String = str(intent.get("signature", ""))
	for existing in intents:
		if str(existing.get("signature", "")) == intent_signature:
			return
	intents.append(intent)
