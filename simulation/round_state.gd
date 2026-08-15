extends RefCounted

# POC-12B: Round State
# --------------------
# Tracks progression and scoring across an arbitrary CourseDefinition. This
# object deliberately does not execute golf shots; POC-12C feeds completed hole
# scores into it.
#
# POC-27B adds read-only full-round semantics for traditional 18-hole play:
# front-nine/back-nine progress, turn state, nine-level scoring, and explicit
# started/finished snapshot fields. Existing arbitrary-length course behavior and
# snapshot restoration remain unchanged.

const FRONT_NINE_LIMIT := 9

var course = null
var tee_id: String = "default"
var current_hole_index: int = 0
var hole_scores: Array[int] = []
var complete: bool = false


func _init(course_definition = null, selected_tee_id: String = "default") -> void:
	course = course_definition
	tee_id = selected_tee_id
	if course != null:
		for _index in range(course.hole_count()):
			hole_scores.append(-1)
		complete = course.hole_count() == 0
	else:
		complete = true


func current_hole():
	if complete or course == null:
		return null
	return course.hole_at(current_hole_index)


func current_hole_number() -> int:
	var hole = current_hole()
	if hole == null:
		return 0
	return int(hole.hole_number)


func holes_completed() -> int:
	return _holes_completed_in_range(0, hole_scores.size())


func record_current_hole(strokes: int) -> bool:
	if complete or course == null:
		return false
	if strokes <= 0:
		return false
	if current_hole_index < 0 or current_hole_index >= hole_scores.size():
		return false
	if hole_scores[current_hole_index] >= 0:
		return false

	hole_scores[current_hole_index] = strokes
	if current_hole_index + 1 >= course.hole_count():
		complete = true
	else:
		current_hole_index += 1
	return true


func restore_snapshot(saved: Dictionary) -> bool:
	if course == null or saved.is_empty():
		return false
	if str(saved.get("course_id", "")) != str(course.course_id):
		return false
	if str(saved.get("tee_id", tee_id)) != tee_id:
		return false

	var rows: Array = saved.get("scorecard", [])
	if rows.size() != course.hole_count():
		return false

	var restored_scores: Array[int] = []
	var completed_count: int = 0
	var encountered_incomplete: bool = false
	for index in range(rows.size()):
		var row: Dictionary = rows[index]
		var hole = course.hole_at(index)
		if hole == null or int(row.get("hole_number", 0)) != int(hole.hole_number):
			return false
		var row_completed: bool = bool(row.get("completed", false))
		if row_completed:
			if encountered_incomplete:
				return false
			var strokes: int = int(row.get("strokes", -1))
			if strokes <= 0:
				return false
			restored_scores.append(strokes)
			completed_count += 1
		else:
			encountered_incomplete = true
			restored_scores.append(-1)

	hole_scores = restored_scores
	complete = completed_count == course.hole_count()
	if complete:
		current_hole_index = maxi(0, course.hole_count() - 1)
	else:
		current_hole_index = completed_count
	return true


func score_for_hole(hole_number: int) -> int:
	if course == null:
		return -1
	var index: int = hole_number - 1
	if index < 0 or index >= hole_scores.size():
		return -1
	return hole_scores[index]


func total_strokes() -> int:
	return _strokes_in_range(0, hole_scores.size())


func par_played() -> int:
	return _par_played_in_range(0, hole_scores.size())


func score_to_par() -> int:
	return total_strokes() - par_played()


func remaining_holes() -> int:
	if course == null:
		return 0
	return max(0, course.hole_count() - holes_completed())


func front_nine_size() -> int:
	if course == null:
		return 0
	return mini(FRONT_NINE_LIMIT, course.hole_count())


func back_nine_size() -> int:
	if course == null:
		return 0
	return maxi(0, course.hole_count() - FRONT_NINE_LIMIT)


func front_nine_holes_completed() -> int:
	return _holes_completed_in_range(0, front_nine_size())


func back_nine_holes_completed() -> int:
	return _holes_completed_in_range(FRONT_NINE_LIMIT, hole_scores.size())


func front_nine_strokes() -> int:
	return _strokes_in_range(0, front_nine_size())


func back_nine_strokes() -> int:
	return _strokes_in_range(FRONT_NINE_LIMIT, hole_scores.size())


func front_nine_par_played() -> int:
	return _par_played_in_range(0, front_nine_size())


func back_nine_par_played() -> int:
	return _par_played_in_range(FRONT_NINE_LIMIT, hole_scores.size())


func front_nine_score_to_par() -> int:
	return front_nine_strokes() - front_nine_par_played()


func back_nine_score_to_par() -> int:
	return back_nine_strokes() - back_nine_par_played()


func front_nine_complete() -> bool:
	return front_nine_size() > 0 and front_nine_holes_completed() == front_nine_size()


func back_nine_complete() -> bool:
	return back_nine_size() > 0 and back_nine_holes_completed() == back_nine_size()


func turn_reached() -> bool:
	return back_nine_size() > 0 and front_nine_complete()


func round_phase() -> String:
	if course == null:
		return "NO_COURSE"
	if complete:
		return "COMPLETE"
	if holes_completed() == 0:
		return "NOT_STARTED"
	if current_hole_index < FRONT_NINE_LIMIT or back_nine_size() == 0:
		return "FRONT_NINE"
	return "BACK_NINE"


func nine_summary(start_index: int, end_index: int) -> Dictionary:
	var size: int = maxi(0, mini(end_index, hole_scores.size()) - maxi(0, start_index))
	var completed_count: int = _holes_completed_in_range(start_index, end_index)
	var strokes: int = _strokes_in_range(start_index, end_index)
	var par_total: int = _par_played_in_range(start_index, end_index)
	return {
		"holes_total": size,
		"holes_completed": completed_count,
		"strokes": strokes,
		"par_played": par_total,
		"score_to_par": strokes - par_total,
		"complete": size > 0 and completed_count == size
	}


func scorecard() -> Array:
	var rows: Array = []
	if course == null:
		return rows
	for index in range(course.hole_count()):
		var hole = course.hole_at(index)
		var strokes: int = hole_scores[index]
		rows.append({
			"hole_number": int(hole.hole_number),
			"hole_name": str(hole.hole_name),
			"par": int(hole.par),
			"yardage": float(hole.tee_yardage(tee_id)),
			"strokes": strokes,
			"score_to_par": strokes - int(hole.par) if strokes >= 0 else 0,
			"completed": strokes >= 0
		})
	return rows


func snapshot() -> Dictionary:
	return {
		"course_id": str(course.course_id) if course != null else "",
		"tee_id": tee_id,
		"current_hole_index": current_hole_index,
		"current_hole_number": current_hole_number(),
		"holes_completed": holes_completed(),
		"remaining_holes": remaining_holes(),
		"total_strokes": total_strokes(),
		"par_played": par_played(),
		"score_to_par": score_to_par(),
		"round_started": holes_completed() > 0,
		"round_finished": complete,
		"round_phase": round_phase(),
		"turn_reached": turn_reached(),
		"front_nine": nine_summary(0, FRONT_NINE_LIMIT),
		"back_nine": nine_summary(FRONT_NINE_LIMIT, hole_scores.size()),
		"complete": complete,
		"scorecard": scorecard()
	}


func _holes_completed_in_range(start_index: int, end_index: int) -> int:
	var count: int = 0
	var start: int = maxi(0, start_index)
	var finish: int = mini(end_index, hole_scores.size())
	for index in range(start, finish):
		if hole_scores[index] >= 0:
			count += 1
	return count


func _strokes_in_range(start_index: int, end_index: int) -> int:
	var total: int = 0
	var start: int = maxi(0, start_index)
	var finish: int = mini(end_index, hole_scores.size())
	for index in range(start, finish):
		if hole_scores[index] >= 0:
			total += hole_scores[index]
	return total


func _par_played_in_range(start_index: int, end_index: int) -> int:
	if course == null:
		return 0
	var total: int = 0
	var start: int = maxi(0, start_index)
	var finish: int = mini(end_index, hole_scores.size())
	for index in range(start, finish):
		if hole_scores[index] < 0:
			continue
		var hole = course.hole_at(index)
		if hole != null:
			total += int(hole.par)
	return total
