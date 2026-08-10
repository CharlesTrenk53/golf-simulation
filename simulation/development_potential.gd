extends RefCounted

# Latent Development Potential
# ----------------------------
# Potential is a soft source of resistance to acquiring new above-baseline skill.
# It is not a hard cap: sustained high-quality development can move a golfer
# beyond latent potential, but each additional point becomes increasingly costly.
#
# A potential of 100 is deliberately neutral. TechniqueSkillDevelopment uses 100
# for golfers that do not yet carry an explicit potential profile, so legacy
# golfers retain exactly the pre-POC-09 acquisition path rather than receiving
# subtle resistance merely because their current skill approaches 100.

const DEFAULT_POTENTIAL := 85.0
const NEUTRAL_POTENTIAL := 100.0
const AT_POTENTIAL_RESISTANCE := 0.35
const MIN_RESISTANCE := 0.08
const APPROACH_WINDOW := 20.0
const OVERSHOOT_SCALE := 10.0
const OVERSHOOT_POWER := 1.25

var potential_by_shot: Dictionary = {}

func initialize(default_potential: float = DEFAULT_POTENTIAL) -> void:
	potential_by_shot.clear()
	var resolved = clamp(default_potential, 0.0, 100.0)
	for shot_type in [0, 1, 2, 3]:
		potential_by_shot[shot_type] = resolved

func set_potential(shot_type: int, potential: float) -> void:
	potential_by_shot[shot_type] = clamp(potential, 0.0, 100.0)

func potential_for(shot_type: int) -> float:
	return float(potential_by_shot.get(shot_type, DEFAULT_POTENTIAL))

func resistance_for(shot_type: int, current_skill: float) -> float:
	var potential = potential_for(shot_type)

	# Maximum potential is the explicit backward-compatibility sentinel. There is
	# no developmental ceiling below the model's own 100-point skill boundary, so
	# POC-09 must not alter acquisition for golfers with no configured potential.
	if is_equal_approx(potential, NEUTRAL_POTENTIAL):
		return 1.0

	var skill = clamp(current_skill, 0.0, 100.0)
	var gap = potential - skill

	if gap >= 0.0:
		# Far below potential, the latent ceiling should barely matter. As the golfer
		# approaches potential, resistance rises smoothly toward the configured
		# at-potential value rather than switching on at an arbitrary threshold.
		var normalized_gap = clamp(gap / APPROACH_WINDOW, 0.0, 1.0)
		return lerp(AT_POTENTIAL_RESISTANCE, 1.0, sqrt(normalized_gap))

	# Potential remains deliberately soft. Above it, acquisition never becomes
	# impossible; the modifier asymptotically approaches a small positive floor.
	var overshoot = abs(gap) / OVERSHOOT_SCALE
	return max(MIN_RESISTANCE, AT_POTENTIAL_RESISTANCE / pow(1.0 + overshoot, OVERSHOOT_POWER))

func state_for(shot_type: int, current_skill: float) -> Dictionary:
	var potential = potential_for(shot_type)
	return {
		"potential": potential,
		"current_skill": clamp(current_skill, 0.0, 100.0),
		"distance_to_potential": potential - current_skill,
		"potential_resistance": resistance_for(shot_type, current_skill)
	}
