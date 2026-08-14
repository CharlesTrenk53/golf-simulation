extends SceneTree
const C=preload("res://simulation/course_definition.gd")
const T=preload("res://simulation/traffic_aware_living_course_controller.gd")
const G=preload("res://scenes/golfer.gd")
func _init()->void:
 var c=T.new();assert(c.configure(C.load_json("res://data/courses/poc12_proving_course.json")))
 assert(c.add_group("lead",[_g(G.GolferProfile.CAREFUL_CARL)]));assert(c.add_group("follow",[_g(G.GolferProfile.WILD_BILL)]))
 assert(bool(c.release_next_group().get("released",false)));assert(not bool(c.release_next_group().get("released",true)))
 assert(bool(c.play_group_current_hole("lead",101).get("played",false)));assert(c.traffic.occupant_for_hole(2)=="lead")
 assert(bool(c.release_next_group().get("released",false)))
 var f:Dictionary=c.play_group_current_hole("follow",211);assert(bool(f.get("played",false)));assert(str(f.get("next_traffic_entry",{}).get("status",""))=="WAITING")
 assert(not bool(c.play_group_current_hole("follow",221).get("played",true)))
 var l:Dictionary=c.play_group_current_hole("lead",301);assert(str(l.get("admitted_behind",{}).get("group_id",""))=="follow")
 assert(c.traffic.occupant_for_hole(2)=="follow" and c.traffic.occupant_for_hole(3)=="lead")
 print("POC-24B TRAFFIC-AWARE LIVING COURSE PROGRESSION PASSED");quit(0)
func _g(p:int):
 var g=G.new();g.profile=p;g.apply_profile();get_root().add_child(g);return g
