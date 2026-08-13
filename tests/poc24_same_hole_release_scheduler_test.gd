extends SceneTree
const C=preload("res://simulation/course_definition.gd")
const R=preload("res://simulation/same_hole_release_scheduler.gd")
const G=preload("res://scenes/golfer.gd")
func _init()->void:
 var h=C.load_json("res://data/courses/poc12_proving_course.json").hole_by_number(1);var s=R.new()
 var c=G.new();c.profile=G.GolferProfile.CAREFUL_CARL;c.apply_profile()
 var b=G.new();b.profile=G.GolferProfile.WILD_BILL;b.apply_profile()
 var t:Vector3=h.tee_position();var d:Vector3=(h.pin_position-t).normalized();var a=t+d*220.0;var x=t+d*225.0;var y=t+d*340.0;var z=t+d*350.0
 var r={"member_results":[{"history":[{"landing_position":a,"relief_position":a},{"landing_position":y,"relief_position":y}]},{"history":[{"landing_position":x,"relief_position":x},{"landing_position":z,"relief_position":z}]}]}
 var ce:Dictionary=s.schedule_release("lead","carl_group",r,h,[c],100.0);var be:Dictionary=s.schedule_release("lead","bill_group",r,h,[b],100.0)
 assert(bool(ce.get("scheduled",false)) and bool(be.get("scheduled",false)));assert(int(ce.get("shot_wave",0))==1 and int(be.get("shot_wave",0))==2);assert(float(ce.get("release_time_seconds",0.0))<float(be.get("release_time_seconds",0.0)))
 assert(s.due_releases(float(ce.get("release_time_seconds",0.0))-0.01).is_empty());var first:Array=s.due_releases(float(ce.get("release_time_seconds",0.0))+0.01);assert(first.size()==1 and str(first[0].get("following_group_id",""))=="carl_group")
 assert(not s.pending_release("bill_group").is_empty());var second:Array=s.due_releases(float(be.get("release_time_seconds",0.0))+0.01);assert(second.size()==1 and str(second[0].get("following_group_id",""))=="bill_group")
 print("POC24_RELEASE_SUMMARY carl=%.1f bill=%.1f"%[float(ce.get("release_time_seconds",0.0)),float(be.get("release_time_seconds",0.0))]);print("POC-24F SPACING-AWARE TEE RELEASE SCHEDULING PASSED");c.free();b.free();quit(0)
