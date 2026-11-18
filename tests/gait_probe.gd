extends Node
## Prints gait numbers (foot fore/aft vs hip, foot height, knee angle, pelvis height) while walking.
func _ready() -> void:
    var tree := get_tree()
    tree.root.remove_child.call_deferred(self)
    tree.root.add_child.call_deferred(self)
    _run.call_deferred()

func _run() -> void:
    get_tree().change_scene_to_file("res://scenes/testing_grounds/testing_grounds.tscn")
    await get_tree().create_timer(1.0).timeout
    var tg = get_tree().current_scene
    tg.player_ctrl.queue_free()
    var m: Mech = tg.player
    var g: MechGait = m.gait
    for ph in [["stand", 0.0, 0.0, 0.6], ["walk", 1.0, 0.0, 3.0], ["turn", 0.0, 1.0, 1.5], ["stop", 0.0, 0.0, 1.5]]:
        m.throttle = ph[1]
        m.turn = ph[2]
        var t := 0.0
        var nxt := 0.0
        while t < ph[3]:
            await get_tree().physics_frame
            t += 1.0 / 60.0
            if t >= nxt:
                nxt += 0.1
                var line := "%s t=%.1f spd=%.1f phase=%.2f pelvisY=%.2f |" % [ph[0], t, Vector2(m.velocity.x, m.velocity.z).length(), g.phase, g.pelvis.global_position.y - m.global_position.y]
                for leg in g.legs:
                    var a: Node3D = leg["ankle"]
                    var lp := m.to_local(a.global_position)
                    line += " %s fwd=%+.2f up=%.2f knee=%+.0f sw=%s" % [leg["side"], lp.z, lp.y, rad_to_deg(leg["knee"].rotation.x), "S" if leg["swinging"] else "-"]
                print("GAIT ", line)
    get_tree().quit()
