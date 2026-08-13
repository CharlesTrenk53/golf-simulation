extends SceneTree
const C=preload("res://simulation/course_definition.gd")
const P=preload("res://simulation/group_pace_model.gd")
func _init()->void:
 var course=C.load_json("res://data/courses/poc12_proving_course.json");assert(course!=null)
 var hole=course.hole_by_number(1);var pace=P.new()
 var two:Dictionary=pace.estimate_hole_duration(_group([_m(4,4),_m(4,4)]),hole)
 var four:Dictionary=pace.estimate_hole_duration(_group([_m(4,4),_m(4,4),_m(4,4),_m(4,4)]),hole)
 var slow:Dictionary=pace.estimate_hole_duration(_group([_m(6,6),_m(6,6)]),hole)
 var penalty:Dictionary=pace.estimate_hole_duration(_group([_m(5,4,1),_m(4,4)]),hole)
 assert(int(two.get("actual_shots",0))==8 and int(two.get("group_size",0))==2)
 assert(float(four.get("total_seconds",0.0))>float(two.get("total_seconds",0.0)))
 assert(float(slow.get("total_seconds",0.0))>float(two.get("total_seconds",0.0)))
 assert(int(penalty.get("penalty_strokes",0))==1 and float(penalty.get("penalty_recovery_seconds",0.0))==pace.penalty_recovery_seconds)
 assert(float(penalty.get("total_seconds",0.0))>float(two.get("total_seconds",0.0)))
 var parts:float=float(two.get("travel_seconds",0.0))+float(two.get("shot_routine_seconds",0.0))+float(two.get("penalty_recovery_seconds",0.0))
 assert(abs(parts-float(two.get("total_seconds",0.0)))<0.001)
 print("POC24_PACE_SUMMARY two=%.1f four=%.1f slow=%.1f penalty=%.1f"%[two.total_seconds,four.total_seconds,slow.total_seconds,penalty.total_seconds])
 print("POC-24C EMERGENT GROUP PACE DURATION PASSED");quit(0)
func _group(members:Array)->Dictionary:return {"member_results":members}
func _m(strokes:int,shots:int,penalties:int=0)->Dictionary:
 var h:Array=[]
 for i in range(shots):h.append({"penalty_strokes":penalties if i==0 else 0})
 return {"strokes":strokes,"history":h}
