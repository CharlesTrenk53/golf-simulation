extends RefCounted

# POC-14A: composable shot intent.
# A shot is not a giant named type such as "7-iron draw". It is built from
# orthogonal dimensions that can later modify launch, spin, curvature, carry,
# rollout, dispersion, and execution difficulty.

enum Trajectory {
	LOW,
	NORMAL,
	HIGH
}

enum Shape {
	DRAW,
	STRAIGHT,
	FADE
}

enum SwingLength {
	FULL,
	THREE_QUARTER,
	HALF,
	TOUCH
}

enum Technique {
	STOCK,
	PUNCH,
	STINGER,
	PITCH,
	FLOP,
	CHIP,
	BUMP_AND_RUN,
	BUNKER
}


static func make(
	trajectory: int = Trajectory.NORMAL,
	shape: int = Shape.STRAIGHT,
	swing_length: int = SwingLength.FULL,
	technique: int = Technique.STOCK
) -> Dictionary:
	return {
		"trajectory": trajectory,
		"trajectory_name": trajectory_name(trajectory),
		"shape": shape,
		"shape_name": shape_name(shape),
		"swing_length": swing_length,
		"swing_length_name": swing_length_name(swing_length),
		"technique": technique,
		"technique_name": technique_name(technique),
		"signature": signature(trajectory, shape, swing_length, technique)
	}


static func signature(trajectory: int, shape: int, swing_length: int, technique: int) -> String:
	return "%s|%s|%s|%s" % [
		trajectory_name(trajectory),
		shape_name(shape),
		swing_length_name(swing_length),
		technique_name(technique)
	]


static func trajectory_name(value: int) -> String:
	match value:
		Trajectory.LOW: return "LOW"
		Trajectory.HIGH: return "HIGH"
		_: return "NORMAL"


static func shape_name(value: int) -> String:
	match value:
		Shape.DRAW: return "DRAW"
		Shape.FADE: return "FADE"
		_: return "STRAIGHT"


static func swing_length_name(value: int) -> String:
	match value:
		SwingLength.THREE_QUARTER: return "THREE_QUARTER"
		SwingLength.HALF: return "HALF"
		SwingLength.TOUCH: return "TOUCH"
		_: return "FULL"


static func technique_name(value: int) -> String:
	match value:
		Technique.PUNCH: return "PUNCH"
		Technique.STINGER: return "STINGER"
		Technique.PITCH: return "PITCH"
		Technique.FLOP: return "FLOP"
		Technique.CHIP: return "CHIP"
		Technique.BUMP_AND_RUN: return "BUMP_AND_RUN"
		Technique.BUNKER: return "BUNKER"
		_: return "STOCK"
