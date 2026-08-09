extends RefCounted

# POC-08 next assessment block.
# These values describe the golfer right now and the competitive situation.
# They are intentionally separate from stable ability and personality.

var fatigue: float = 0.0
var injury: float = 0.0
var soreness: float = 0.0
var energy: float = 100.0
var balance: float = 100.0
var hydration: float = 100.0
var heat_cold_stress: float = 0.0
var holes_played: int = 0

var calm: float = 70.0
var nervous: float = 0.0
var frustration: float = 0.0
var anger: float = 0.0
var excitement: float = 30.0
var focus: float = 80.0
var distraction: float = 0.0
var pressure: float = 0.0

var hole_number: int = 1
var par: int = 4
var current_score_to_par: int = 0
var score_differential_to_target: int = 0
var holes_remaining: int = 17
var protecting_lead: bool = false
var chasing: bool = false
var match_play: bool = false
var opponent_advantage: int = 0

func set_physical_condition(values: Dictionary) -> void:
	fatigue = clamp(float(values.get("fatigue", fatigue)), 0.0, 100.0)
	injury = clamp(float(values.get("injury", injury)), 0.0, 100.0)
	soreness = clamp(float(values.get("soreness", soreness)), 0.0, 100.0)
	energy = clamp(float(values.get("energy", energy)), 0.0, 100.0)
	balance = clamp(float(values.get("balance", balance)), 0.0, 100.0)
	hydration = clamp(float(values.get("hydration", hydration)), 0.0, 100.0)
	heat_cold_stress = clamp(float(values.get("heat_cold_stress", heat_cold_stress)), 0.0, 100.0)
	holes_played = max(int(values.get("holes_played", holes_played)), 0)

func set_mental_state(values: Dictionary) -> void:
	calm = clamp(float(values.get("calm", calm)), 0.0, 100.0)
	nervous = clamp(float(values.get("nervous", nervous)), 0.0, 100.0)
	frustration = clamp(float(values.get("frustration", frustration)), 0.0, 100.0)
	anger = clamp(float(values.get("anger", anger)), 0.0, 100.0)
	excitement = clamp(float(values.get("excitement", excitement)), 0.0, 100.0)
	focus = clamp(float(values.get("focus", focus)), 0.0, 100.0)
	distraction = clamp(float(values.get("distraction", distraction)), 0.0, 100.0)
	pressure = clamp(float(values.get("pressure", pressure)), 0.0, 100.0)

func set_strategic_context(values: Dictionary) -> void:
	hole_number = max(int(values.get("hole_number", hole_number)), 1)
	par = max(int(values.get("par", par)), 3)
	current_score_to_par = int(values.get("current_score_to_par", current_score_to_par))
	score_differential_to_target = int(values.get("score_differential_to_target", score_differential_to_target))
	holes_remaining = max(int(values.get("holes_remaining", holes_remaining)), 0)
	protecting_lead = bool(values.get("protecting_lead", protecting_lead))
	chasing = bool(values.get("chasing", chasing))
	match_play = bool(values.get("match_play", match_play))
	opponent_advantage = int(values.get("opponent_advantage", opponent_advantage))

func physical_readiness() -> float:
	var penalty = fatigue * 0.22 + injury * 0.30 + soreness * 0.12 + heat_cold_stress * 0.10
	var support = energy * 0.10 + balance * 0.10 + hydration * 0.06
	return clamp(64.0 + support - penalty, 0.0, 100.0)

func mental_execution_readiness() -> float:
	var positive = calm * 0.18 + focus * 0.32 + excitement * 0.04
	var negative = nervous * 0.14 + frustration * 0.12 + anger * 0.10 + distraction * 0.22 + pressure * 0.08
	return clamp(50.0 + positive - negative, 0.0, 100.0)

func aggression_pressure() -> float:
	# Positive values make attacking strategically more valuable; negative values
	# favor protecting position. This is strategy, not personality.
	var modifier = 0.0
	if chasing:
		modifier += 18.0
	if protecting_lead:
		modifier -= 18.0
	if holes_remaining <= 3:
		modifier *= 1.35
	if score_differential_to_target < 0:
		modifier += min(abs(score_differential_to_target) * 4.0, 20.0)
	elif score_differential_to_target > 0:
		modifier -= min(score_differential_to_target * 3.0, 15.0)
	if match_play:
		modifier += clamp(float(opponent_advantage) * 5.0, -15.0, 15.0)
	return clamp(modifier, -35.0, 35.0)

func snapshot() -> Dictionary:
	return {
		"physical_readiness": physical_readiness(),
		"mental_execution_readiness": mental_execution_readiness(),
		"aggression_pressure": aggression_pressure(),
		"fatigue": fatigue,
		"injury": injury,
		"energy": energy,
		"focus": focus,
		"frustration": frustration,
		"anger": anger,
		"pressure": pressure,
		"hole_number": hole_number,
		"holes_remaining": holes_remaining,
		"protecting_lead": protecting_lead,
		"chasing": chasing
	}
