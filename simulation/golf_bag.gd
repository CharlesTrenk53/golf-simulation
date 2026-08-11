extends RefCounted

# POC-08: club catalog + default 14-club bag.
# Legacy distances remain in the original compact POC simulation units.
# POC-11 adds an opt-in literal-yardage profile for data-defined courses so
# full-length holes can use realistic golf distances without disturbing legacy tests.

var clubs: Array[Dictionary] = []
var club_catalog: Array[Dictionary] = []
var literal_yardages_enabled: bool = false

const DEFAULT_BAG_IDS := [
	"DRIVER", "3_WOOD", "5_WOOD", "4_HYBRID",
	"5_IRON", "6_IRON", "7_IRON", "8_IRON", "9_IRON",
	"PITCHING_WEDGE", "GAP_WEDGE", "SAND_WEDGE", "LOB_WEDGE", "PUTTER"
]

# Provisional POC-11 average-golfer yardages. These are intentionally treated as
# one practical distance number for now; carry-versus-total separation belongs in
# later shot-physics work. Interpolated clubs fill gaps in the reference chart.
const AVERAGE_YARDAGE_BASELINES := {
	"DRIVER": 220.0,
	"3_WOOD": 210.0,
	"5_WOOD": 195.0,
	"7_WOOD": 185.0,
	"2_HYBRID": 190.0,
	"3_HYBRID": 185.0,
	"4_HYBRID": 180.0,
	"2_IRON": 180.0,
	"3_IRON": 170.0,
	"4_IRON": 160.0,
	"5_IRON": 155.0,
	"6_IRON": 145.0,
	"7_IRON": 140.0,
	"8_IRON": 130.0,
	"9_IRON": 115.0,
	"PITCHING_WEDGE": 100.0,
	"GAP_WEDGE": 90.0,
	"SAND_WEDGE": 80.0,
	"LOB_WEDGE": 60.0,
	"PUTTER": 8.0
}


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


func use_literal_yardages(enabled: bool = true) -> void:
	literal_yardages_enabled = enabled


func is_using_literal_yardages() -> bool:
	return literal_yardages_enabled


func baseline_distance(club: Dictionary) -> float:
	if literal_yardages_enabled:
		var club_id := str(club.get("id", ""))
		if AVERAGE_YARDAGE_BASELINES.has(club_id):
			return float(AVERAGE_YARDAGE_BASELINES[club_id])
	return float(club.get("carry_distance", 0.0))


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


# Some clubs remain physically possible from a surface while becoming substantially
# harder to execute. Driver from a clean fairway is the important first example:
# it is not forbidden, but the missing tee makes center-face launch far less reliable.
# This is deliberately a feasibility/skill penalty rather than an arbitrary strategy
# penalty so an exceptional golfer can still choose the shot when the geometry warrants it.
func surface_execution_penalty(club: Dictionary, surface: String, lie_quality: float = 1.0) -> float:
	var club_id: String = str(club.get("id", ""))
	var family: String = str(club.get("family", ""))
	var normalized_surface: String = surface.to_upper()
	var penalty: float = 0.0

	if club_id == "DRIVER" and normalized_surface != "TEE":
		penalty += 0.35
	elif family == "WOOD" and normalized_surface == "FAIRWAY":
		penalty += 0.05

	# Poorer lies amplify clubs that are already difficult from the surface.
	penalty += max(0.0, 1.0 - lie_quality) * 0.25
	return clamp(penalty, 0.0, 1.0)


func effective_carry(club: Dictionary, golfer: Node, surface: String, lie_quality: float = 1.0) -> float:
	var base_carry: float = baseline_distance(club)
	var shot_type: int = int(club["shot_type"])
	var ability: float = golfer.get_shot_ability(shot_type)
	var strike_factor: float = lerp(0.94, 1.04, ability / 100.0)
	var raw_physical_factor: float = golfer.physical_distance_factor(shot_type) if golfer.has_method("physical_distance_factor") else 1.0
	var physical_sensitivity: float = float(club.get("physical_sensitivity", 1.0))
	var physical_factor: float = 1.0 + ((raw_physical_factor - 1.0) * physical_sensitivity)
	var lie_factor: float = clamp(lie_quality, 0.45, 1.0)

	if surface == "ROUGH":
		lie_factor *= 0.90
	elif surface == "BUNKER":
		lie_factor *= 0.78

	return base_carry * strike_factor * physical_factor * lie_factor


func effective_dispersion(club: Dictionary, golfer: Node, surface: String, lie_quality: float = 1.0) -> float:
	var base_dispersion: float = float(club["dispersion"])
	var ability: float = golfer.get_shot_ability(int(club["shot_type"]))
	var ability_factor: float = lerp(1.45, 0.65, ability / 100.0)
	var lie_penalty: float = 1.0 + (1.0 - lie_quality)
	if surface == "ROUGH":
		lie_penalty *= 1.15
	elif surface == "BUNKER":
		lie_penalty *= 1.30
	var execution_penalty: float = surface_execution_penalty(club, surface, lie_quality)
	var surface_dispersion_factor: float = 1.0 + execution_penalty * 1.10
	return base_dispersion * ability_factor * lie_penalty * surface_dispersion_factor


func best_distance_match(golfer: Node, surface: String, lie_quality: float, desired_distance: float) -> Dictionary:
	var available: Array[Dictionary] = clubs_for_surface(surface)
	if available.is_empty():
		return {}
	var best: Dictionary = available[0]
	var best_gap: float = INF
	for club in available:
		var carry: float = effective_carry(club, golfer, surface, lie_quality)
		var gap: float = abs(carry - desired_distance)
		if gap < best_gap:
			best_gap = gap
			best = club
	return best.duplicate(true)
