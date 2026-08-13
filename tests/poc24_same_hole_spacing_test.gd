extends SceneTree
const C=preload("res://simulation/course_definition.gd")
const S=preload("res://simulation/same_hole_spacing_model.gd")
const G=preload("res://scenes/golfer.gd")
func _init()->void:
 var h=C.load_json("res://data/courses/poc12_proving_course.json").hole_by_number(1);var m=S.new()
 var c=G.new();c.profile=G.GolferProfile.CAREFUL_CARL;c.apply_profile()
 var b=G.new();b.profile=G.GolferProfile.WILD_BILL;b.apply_profile()
 var t:Vector3=h.tee_position();var d:Vector3=(h.pin_position-t).normalized()
 var a:Vector3=t+d*220.0;var x:Vector3=t+d*225.0;var y:Vector3=t+d*340.0;var z:Vector3=t+d*350.0
 var r={"member_results":[{"history":[{"landing_position":a,"relief_position":a},{"landing_position":y,"relief_position":y}]},{"history":[{"landing_position":x,"relief_position":x},{"landing_position":z,"relief_position":z}]}]}
 var cr:float=m.maximum_tee_reach([c]);var br:float=m.maximum_tee_reach([b]);assert(cr<220.0);assert(br>220.0 and br<340.0)
 var cs:Dictionary=m.earliest_safe_tee_time(r,h,[c]);var bs:Dictionary=m.earliest_safe_tee_time(r,h,[b])
 assert(bool(cs.get("safe",false)) and bool(bs.get("safe",false)));assert(int(cs.get("shot_wave",0))==1);assert(int(bs.get("shot_wave",0))==2)
 print("POC24_SPACING_SUMMARY carl=%.1f bill=%.1f carl_wave=%d bill_wave=%d"%[cr,br,int(cs.get("shot_wave",0)),int(bs.get("shot_wave",0))]);print("POC-24E SAME-HOLE PLAYER-DEPENDENT SPACING PASSED");c.free();b.free();quit(0)
