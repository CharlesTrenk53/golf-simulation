extends RefCounted

const ShotIntent = preload("res://simulation/shot_intent.gd")

# POC-14B: deterministic predicted flight from club baseline + composable intent.
# This is deliberately a planning model, not yet the stochastic execution result.
# It turns intent into physically meaningful relative effects that later strategy
# and execution layers can consume without inventing separate named shot types.


func predict(club: Dictionary, intent: Dictionary, baseline_carry: float, baseline_dispersion: float) -> Dictionary:
	var family: String = str(club.get("family", "")).to_upper()
	var carry_factor: float = 1.0
	var apex_factor: float = 1.0
	var rollout_factor: float = 1.0
	var dispersion_factor: float = 1.0
	var difficulty: float = 0.0
	var curve_yards: float = 0.0

	# Swing length is the primary distance-control dimension. Technique may then
	# refine that result (e.g. a flop consumes even more forward distance).
	match int(intent.get("swing_length", ShotIntent.SwingLength.FULL)):
		ShotIntent.SwingLength.THREE_QUARTER:
			carry_factor *= 0.82
			dispersion_factor *= 0.88
			difficulty += 0.06
		ShotIntent.SwingLength.HALF:
			carry_factor *= 0.62
			dispersion_factor *= 0.82
			difficulty += 0.10
		ShotIntent.SwingLength.TOUCH:
			carry_factor *= 0.38
			dispersion_factor *= 0.78
			difficulty += 0.16

	match int(intent.get("trajectory", ShotIntent.Trajectory.NORMAL)):
		ShotIntent.Trajectory.LOW:
			carry_factor *= 0.96
			apex_factor *= 0.62
			rollout_factor *= 1.42
			dispersion_factor *= 0.94
			difficulty += 0.08
		ShotIntent.Trajectory.HIGH:
			carry_factor *= 0.97
			apex_factor *= 1.38
			rollout_factor *= 0.58
			dispersion_factor *= 1.08
			difficulty += 0.10

	var shape_strength: float = _shape_strength_for_family(family)
	match int(intent.get("shape", ShotIntent.Shape.STRAIGHT)):
		ShotIntent.Shape.DRAW:
			carry_factor *= _draw_carry_factor(family)
			rollout_factor *= 1.10
			curve_yards = -shape_strength
			dispersion_factor *= 1.08
			difficulty += 0.12
		ShotIntent.Shape.FADE:
			carry_factor *= _fade_carry_factor(family)
			rollout_factor *= 0.88
			curve_yards = shape_strength
			dispersion_factor *= 1.06
			difficulty += 0.10

	match int(intent.get("technique", ShotIntent.Technique.STOCK)):
		ShotIntent.Technique.PUNCH:
			carry_factor *= 0.92
			apex_factor *= 0.62
			rollout_factor *= 1.30
			dispersion_factor *= 0.88
			difficulty += 0.08
		ShotIntent.Technique.STINGER:
			carry_factor *= 0.90
			apex_factor *= 0.58
			rollout_factor *= 1.48
			dispersion_factor *= 0.92
			difficulty += 0.16
		ShotIntent.Technique.PITCH:
			apex_factor *= 1.08
			rollout_factor *= 0.72
			dispersion_factor *= 0.86
			difficulty += 0.08
		ShotIntent.Technique.FLOP:
			carry_factor *= 0.78
			apex_factor *= 1.65
			rollout_factor *= 0.24
			dispersion_factor *= 1.28
			difficulty += 0.34
		ShotIntent.Technique.CHIP:
			carry_factor *= 0.72
			apex_factor *= 0.48
			rollout_factor *= 1.38
			dispersion_factor *= 0.78
			difficulty += 0.05
		ShotIntent.Technique.BUMP_AND_RUN:
			carry_factor *= 0.62
			apex_factor *= 0.36
			rollout_factor *= 1.70
			dispersion_factor *= 0.76
			difficulty += 0.05
		ShotIntent.Technique.BUNKER:
			carry_factor *= 0.52
			apex_factor *= 1.42
			rollout_factor *= 0.34
			dispersion_factor *= 1.16
			difficulty += 0.24

	var carry_yards: float = max(0.0, baseline_carry * carry_factor)
	var stock_rollout_ratio: float = _stock_rollout_ratio_for_family(family)
	var rollout_yards: float = max(0.0, carry_yards * stock_rollout_ratio * rollout_factor)
	var total_yards: float = carry_yards + rollout_yards
	var dispersion_yards: float = max(0.1, baseline_dispersion * dispersion_factor)

	return {
		"intent_signature": str(intent.get("signature", "")),
		"carry_factor": carry_factor,
		"carry_yards": carry_yards,
		"apex_factor": apex_factor,
		"curve_yards": curve_yards,
		"rollout_factor": rollout_factor,
		"rollout_yards": rollout_yards,
		"total_yards": total_yards,
		"dispersion_factor": dispersion_factor,
		"dispersion_yards": dispersion_yards,
		"execution_difficulty": clamp(difficulty, 0.0, 1.0)
	}


func _shape_strength_for_family(family: String) -> float:
	match family:
		"DRIVER": return 18.0
		"WOOD": return 15.0
		"HYBRID": return 12.0
		"IRON": return 10.0
		"WEDGE": return 7.0
		_: return 8.0


func _draw_carry_factor(family: String) -> float:
	if family in ["DRIVER", "WOOD"]:
		return 1.015
	return 1.005


func _fade_carry_factor(family: String) -> float:
	if family in ["DRIVER", "WOOD"]:
		return 0.985
	return 0.992


func _stock_rollout_ratio_for_family(family: String) -> float:
	match family:
		"DRIVER": return 0.10
		"WOOD": return 0.08
		"HYBRID": return 0.06
		"IRON": return 0.045
		"WEDGE": return 0.025
		_: return 0.04
