extends RefCounted

# POC-08: club catalog + default 14-club bag.
# Distances are simulation units matching the existing POC scale, not literal yards.
# POC-11 adds a configurable distance scale so data-defined courses can keep
# literal yard coordinates without rewriting the legacy club calibration.

var clubs: Array[Dictionary] = []
var club_catalog: Array[Dictionary] = []
var distance_scale: float = 1.0

const DEFAULT_BAG_IDS := [
	"DRIVER", "3_WOOD", "5_WOOD", "4_HYBRID",
	"5_IRON", "6_IRON", "7_IRON", "8_IRON", "9_IRON",
	"PITCHING_WEDGE", "GAP_WEDGE", "SAND_WEDGE", "LOB_WEDGE", "PUTTER"
]


func _init() -> void:
	club_catalog = [
		_club("DRIVER", "Driver", "DRIVER", 70.0, 9.0, 0, ["TEE", "FAIRWAY"], 1.00, 0.52),
		_club("3_WOOD", "3 Wood", "WOOD", 60.0, 7.0, 0, ["TEE", "FAIRWAY"], 0.95, 0.60),
		_club("5_WOOD", "5 Wood", "WOOD", 55.0, 6.5, 0, ["TEE", "FAIRWAY", "ROUGH"], 0.85, 0.68),
		_club("7_WOOD", "7 Wood", "WOOD", 50.0, 6.2, 1, ["TEE", "FAIRWAY", "ROUGH"], 0.75, 0.74),
		_club("2_HYBRID", "2 Hybrid", "HYBRID", 54.0, 6.0, 1, ["TEE", "FAIRWAY", "ROUGH"], 0.80, 0.70),
		_club("3_HYBRID", "3 Hybrid", "HYBRID", 50.0, 5.8, 1, ["TEE", "FAIRWAY", "ROUGH"], 0.75, 0.74),
		_club("4_HYBRID", "4 Hybrid", "HYBRID", 47.0, 5.5, 1, ["TEE", "FAIRWAY", "ROUGH"], 0.68, 0.78),
		_club("2_IRON", "2 Iron", "IRON", 55.0, 6.8, 1, ["TEE", "FAIRWAY"], 0.98, 0.38),
		_club("3_IRON", "3 Iron", "IRON", 52.0, 6.3, 1, ["TEE", "FAIRWAY", "ROUGH"], 0.92, 0.43),
		_club("4_IRON", "4 Iron", "IRON", 49.0, 5.9, 1, ["TEE", "FAIRWAY", "ROUGH"], 0.84, 0.49),
		_club("5_IRON", "5 Iron", "IRON", 46.0, 5.5, 1, ["TEE", "FAIRWAY", "ROUGH"], 0.74, 0.55),
		_club("6_IRON", "6 Iron", "IRON", 41.0, 5.0, 1, ["TEE", "FAIRWAY", "ROUGH"], 0.65, 0.60),
		_club("7_IRON", "7 Iron", "IRON", 36.0, 4.5, 1, ["TEE", "FAIRWAY", "ROUGH"], 0.56, 0.65),
		_club("8_IRON", "8 Iron", "IRON", 31.5, 4.0, 1, ["FAIRWAY", "ROUGH"], 0.48, 0.69),
		_club("9_IRON", "9 Iron", "IRON", 27.0, 3.5, 1, ["FAIRWAY", "ROUGH"], 0.40, 0.73),
		_club("PITCHING_WEDGE", "Pitching Wedge", "WEDGE", 20.0, 3.0, 2, ["FAIRWAY", "ROUGH", "BUNKER"], 0.30, 0.76),
		_club("GAP_WEDGE", "Gap Wedge", "WEDGE", 17.0, 3.2, 2, ["FAIRWAY", "ROUGH", "BUNKER"], 0.25, 0.78),
		_club("SAND_WEDGE", "Sand Wedge", "WEDGE", 14.0, 4.0, 2, ["FAIRWAY", "ROUGH", "BUNKER"], 0.20, 0.80),
		_club("LOB_WEDGE", "Lob Wedge", "WEDGE", 11.0, 4.5, 2, ["FAIRWAY", "ROUGH", "BUNKER"], 0.15, 0.72),
		_club("PUTTER", "Putter", "PUTTER", 8.0, 1.0, 3, ["GREEN"], 0.00, 0.90)
	]
	clubs = []
	for club_id in DEFAULT_BAG_IDS:
		var club := _find_catalog_club(club_id)
		if not club.is_empty():
			clubs.append(club)


func _club(id: String, display_name: String, family: String, carry_distance: float, dispersion: float, shot_type: int, allowed_surfaces: Array[String], physical_sensitivity: float, forgiveness: float) -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"family": family,
		"carry_distance": carry_distance,
		"dispersion": dispersion,
		"shot_type": shot_type,
		"allowed_surfaces": allowed_surfaces,
		"physical_sensitivity": physical_sensitivity,
		"forgiveness": forgiveness
	}


func _find_catalog_club(club_id: String) -> Dictionary:
	for club in club_catalog:
		if club["id"] == club_id:
			return club.duplicate(true)
	return {}


func all_clubs() -> Array[Dictionary]:
	return clubs.duplicate(true)


func all_catalog_clubs() -> Array[Dictionary]:
	return club_catalog.duplicate(true)


func get_club(club_id: String) -> Dictionary:
	return _find_catalog_club(club_id)


func clubs_for_surface(surface: String) -> Array[Dictionary]:
	var available: Array[Dictionary] = []
	for club in clubs:
		if surface in club["allowed_surfaces"]:
			available.append(club.duplicate(true))
	return available


func effective_carry(club: Dictionary, golfer: Node, surface: String, lie_quality: float = 1.0) -> float:
	var base_carry: float = club["carry_distance"]
	var shot_type = int(club["shot_type"])
	var ability: float = golfer.get_shot_ability(shot_type)
	var strike_factor = lerp(0.94, 1.04, ability / 100.0)
	var raw_physical_factor = golfer.physical_distance_factor(shot_type) if golfer.has_method("physical_distance_factor") else 1.0
	var physical_sensitivity: float = float(club.get("physical_sensitivity", 1.0))
	var physical_factor: float = 1.0 + ((raw_physical_factor - 1.0) * physical_sensitivity)
	var lie_factor = clamp(lie_quality, 0.45, 1.0)

	if surface == "ROUGH":
		lie_factor *= 0.90
	elif surface == "BUNKER":
		lie_factor *= 0.78

	return base_carry * strike_factor * physical_factor * lie_factor * distance_scale


func effective_dispersion(club: Dictionary, golfer: Node, surface: String, lie_quality: float = 1.0) -> float:
	var base_dispersion: float = club["dispersion"]
	var ability: float = golfer.get_shot_ability(int(club["shot_type"]))
	var ability_factor = lerp(1.45, 0.65, ability / 100.0)
	var lie_penalty = 1.0 + (1.0 - lie_quality)
	if surface == "ROUGH":
		lie_penalty *= 1.15
	elif surface == "BUNKER":
		lie_penalty *= 1.30
	return base_dispersion * ability_factor * lie_penalty * distance_scale


func best_distance_match(golfer: Node, surface: String, lie_quality: float, desired_distance: float) -> Dictionary:
	var available = clubs_for_surface(surface)
	if available.is_empty():
		return {}
	var best: Dictionary = available[0]
	var best_gap = INF
	for club in available:
		var carry = effective_carry(club, golfer, surface, lie_quality)
		var gap = abs(carry - desired_distance)
		if gap < best_gap:
			best_gap = gap
			best = club
	return best.duplicate(true)
