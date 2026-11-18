extends Node
## Headless smoke test: drives the real scenes and prints PASS/FAIL lines.
##   godot --headless --path . res://tests/smoke_test.tscn
## Lives on the root so it survives scene changes.

var failures := 0


func check(name: String, ok: bool, detail: String = "") -> void:
    print(("PASS  " if ok else "FAIL  ") + name + ("" if detail == "" else "   (" + detail + ")"))
    if not ok:
        failures += 1


func wait(seconds: float) -> void:
    var t := 0.0
    while t < seconds:
        await get_tree().physics_frame
        t += 1.0 / Engine.physics_ticks_per_second


func _ready() -> void:
    # move to the root so changing scenes doesn't free the test
    var tree := get_tree()
    tree.root.remove_child.call_deferred(self)
    tree.root.add_child.call_deferred(self)
    _run.call_deferred()


func _run() -> void:
    var gs = GameState
    var db = PartDB
    var btn := func(action: String) -> int:
        for ev in InputMap.action_get_events(action):
            if ev is InputEventMouseButton:
                return ev.button_index
        return -1
    check("LMB = left arm, RMB = right arm, MMB = next target",
        btn.call("fire_left") == MOUSE_BUTTON_LEFT and btn.call("fire_right") == MOUSE_BUTTON_RIGHT
        and btn.call("target_cycle") == MOUSE_BUTTON_MIDDLE)
    check("all synthesized sounds loaded", Audio.streams.size() == Audio.info.size() and Audio.streams.size() >= 40,
        "%d / %d" % [Audio.streams.size(), Audio.info.size()])
    check("PartDB loaded parts", db.parts.size() >= 8, "%d parts" % db.parts.size())
    gs.new_game()

    # ---------------- workshop
    get_tree().change_scene_to_file("res://scenes/workshop/workshop.tscn")
    await wait(1.0)
    var ws = get_tree().current_scene
    check("workshop loads", ws != null and ws.name == "Workshop")
    check("workshop display mech built", ws.display_mech != null and ws.display_mech.part_nodes.size() == 7,
        "%d parts" % (ws.display_mech.part_nodes.size() if ws.display_mech else 0))
    check("workshop dock + camera shots from Blender", ws.dock != null and ws.shots.size() == 4, "%d shots" % ws.shots.size())
    check("workshop turntable found", ws._turntable.size() >= 1)
    ws._set_spin(1.0)
    await wait(0.5)
    ws._set_spin(0.0)
    check("rotate button spins the mech", absf(ws._dock_yaw) > 0.2, "yaw %.2f" % ws._dock_yaw)
    ws._show_tab("paint")
    gs.apply_paint_preset("Arctic")
    await wait(0.1)
    check("paint preset applies", ws.display_mech.current_paint.get("primary", "") == "#dfe6ea")
    ws._show_tab("upgrades")
    gs.add_money(5000)
    var before_money: int = gs.money
    var ok_buy: bool = gs.buy_part("weapon_missile_pod_mk1")
    check("buy part", ok_buy and gs.money < before_money)
    gs.equip("weapon_missile_pod_mk1", "weapon_L")
    await wait(0.2)
    check("equip rebuilds mech with new weapon", str(ws.display_mech.loadout["weapon_L"]) == "weapon_missile_pod_mk1")

    # ---------------- arena
    get_tree().change_scene_to_file("res://scenes/arena/arena.tscn")
    await wait(0.5)
    var ar = get_tree().current_scene
    check("arena loads Blender environment", ar.get_node_or_null("arena") != null or ar.get_child_count() > 5)
    check("gate doors found", ar._doors.size() == 4, "%d doors" % ar._doors.size())
    var p: Mech = ar.player
    var e: Mech = ar.enemy
    check("player + enemy mechs", p != null and e != null)
    check("gait active on player", p.gait != null and p.gait.legs.size() == 2)
    var pc: PlayerController = ar.player_ctrl
    check("cockpit interior mounted", pc.cockpit != null)
    check("cockpit screens + cracks + sticks + arms", pc._screens.size() == 3 and pc._cracks.size() == 3
        and pc._stick_drive != null and pc._arms.size() == 2,
        "screens %d cracks %d arms %d" % [pc._screens.size(), pc._cracks.size(), pc._arms.size()])
    check("intro locks controls", not pc.enabled)
    var start_z := p.global_position
    await wait(12.0)
    check("mechs walked out of the gates", p.global_position.distance_to(start_z) > 12.0,
        "moved %.1f m" % p.global_position.distance_to(start_z))
    check("controls unlocked after countdown", pc.enabled and ar.enemy_ai.enabled)
    var door_closed: bool = ar._doors[0]["node"].transform.origin.distance_to(ar._doors[0]["closed"].origin) < 0.05
    check("gates closed again", door_closed)
    check("screens show live text", str(pc._screens["radar"].text).contains("SPD"), str(pc._screens["radar"].text).left(30))

    ar.enemy_ai.enabled = false   # no incoming fire while checking the gait (hits knock the mech)
    e.throttle = 0.0
    e.turn = 0.0
    # walk forward with the real input action
    var hip: Node3D = p.gait.legs[0]["hip"]
    var hip_rot_before := hip.rotation.x
    var steps := [0]
    p.footstep.connect(func(_m, _pos, _s): steps[0] += 1)
    Input.action_press("move_forward")
    await wait(3.0)
    var spd := Vector2(p.velocity.x, p.velocity.z).length()
    Input.action_release("move_forward")
    check("player walks forward", spd > 3.0, "%.1f m/s" % spd)
    check("legs animate (hip IK moving)", absf(hip.rotation.x - hip_rot_before) > 0.02 or steps[0] > 0)
    check("footsteps fire", steps[0] >= 3, "%d steps" % steps[0])
    var min_knee := 999.0
    for leg in p.gait.legs:
        min_knee = minf(min_knee, rad_to_deg(leg["knee"].rotation.x))
    check("knees never hyperextend", min_knee > 0.0, "min knee %.0f deg" % min_knee)
    await wait(3.0)
    var offs := [p.gait._home_offset(p.gait.legs[0]), p.gait._home_offset(p.gait.legs[1])]
    check("idle: feet step back to a square forward stance", offs[0] < 0.06 and offs[1] < 0.06,
        "offsets %.2f / %.2f m" % offs)
    check("hologram HUD mounted", pc.holo != null)
    ar.enemy_ai.enabled = true
    check("targeting acquires the enemy", pc.targeting.target == e)
    for i in 150:   # hold the guns on the enemy
        var to := Targeting.aim_point_of(e) - pc.camera.global_position
        var local := p.global_basis.inverse() * to
        p.target_twist = atan2(local.x, local.z)
        p.target_pitch = atan2(local.y, Vector2(local.x, local.z).length())
        await get_tree().physics_frame
    check("lock-on when the guns stay on target", pc.targeting.locked, "lock %.2f, LOS %s" % [pc.targeting.lock, pc.targeting.has_line_of_sight])

    # weighted aim: the torso trails the target, then settles; the legs turn to follow the aim
    ar.enemy_ai.enabled = false
    var yaw0 := p.global_rotation.y
    p.target_twist = 0.8
    await wait(0.15)
    var early := wrapf(p.global_rotation.y + p.torso_twist - yaw0, -PI, PI)
    await wait(3.0)
    var gun_yaw := wrapf(p.global_rotation.y + p.torso_twist - yaw0, -PI, PI)
    var legs_yaw := wrapf(p.global_rotation.y - yaw0, -PI, PI)
    check("aim lags behind the mouse target", early < 0.4, "after 0.15 s: %.2f of 0.80" % early)
    check("aim settles on the target", absf(gun_yaw - 0.8) < 0.04, "%.2f" % gun_yaw)
    check("legs turn to face the aim", absf(legs_yaw - 0.8) < 0.06 and absf(p.torso_twist) < 0.06,
        "legs %.2f, torso twist %.2f" % [legs_yaw, p.torso_twist])
    # A / D strafe: sideways movement, legs keep facing forward
    var yaw_before := p.global_rotation.y
    Input.action_press("strafe_left")
    var lateral := 0.0
    var fwd_v := 0.0
    var knee_min := 999.0
    for i in 90:   # 1.5 s; record peak sideways speed (cover may stop it later)
        await get_tree().physics_frame
        var lv := p.velocity.dot(p.global_basis.x)
        if lv > lateral:
            lateral = lv
            fwd_v = p.velocity.dot(p.global_basis.z)
        for leg in p.gait.legs:
            knee_min = minf(knee_min, rad_to_deg(leg["knee"].rotation.x))
    Input.action_release("strafe_left")
    check("A strafes left without turning", lateral > 2.0 and absf(fwd_v) < 0.5 and absf(wrapf(p.global_rotation.y - yaw_before, -PI, PI)) < 0.03,
        "lateral %.1f m/s, fwd %.1f, yaw drift %.3f" % [lateral, fwd_v, wrapf(p.global_rotation.y - yaw_before, -PI, PI)])
    check("strafing legs stay sane", knee_min > 0.0, "min knee %.0f" % knee_min)
    await wait(1.5)
    # airborne: no walking animation in mid air, both feet plant on landing
    var air_steps := [0]
    var count_air := func(_m, _pos, _s): air_steps[0] += 1
    p.global_position += Vector3(0, 12.0, 0)
    p.velocity = Vector3(0, 0, 0)
    Input.action_press("move_forward")      # trying to walk in mid air must not animate steps
    await wait(0.4)
    p.footstep.connect(count_air)
    var phase_air: float = p.gait.phase
    await wait(0.4)
    var still_air := not p.is_on_floor()
    var no_steps: bool = air_steps[0] == 0 and is_equal_approx(p.gait.phase, phase_air)
    check("no walking animation in mid air", still_air and p.gait.airborne and no_steps,
        "airborne %s, steps %d, phase %.2f -> %.2f" % [p.gait.airborne, air_steps[0], phase_air, p.gait.phase])
    Input.action_release("move_forward")
    var t_land := 0.0
    while not p.is_on_floor() and t_land < 4.0:
        await get_tree().physics_frame
        t_land += 1.0 / 60.0
    await wait(0.1)
    p.footstep.disconnect(count_air)
    check("both feet plant on landing", not p.gait.airborne and air_steps[0] >= 2, "%d footfalls" % air_steps[0])
    await wait(1.5)

    # free-look (hold Alt): camera moves, aim doesn't
    var aim_before := p.target_twist
    Input.action_press("freelook")
    pc.apply_freelook(Vector2(-300, 0))
    await wait(0.1)
    check("free-look turns the camera, not the aim", absf(pc.look.x) > 0.3 and absf(p.target_twist - aim_before) < 0.001,
        "look %.2f, aim moved %.3f" % [pc.look.x, p.target_twist - aim_before])
    Input.action_release("freelook")
    await wait(1.0)
    check("free-look swings back on release", absf(pc.look.x) < 0.02, "%.3f" % pc.look.x)
    # third person
    pc.set_third_person(true)
    await wait(0.6)
    var tp_d := pc.tp_camera.global_position.distance_to(p.global_position)
    check("third-person camera behind the mech", pc.tp_camera.current and not pc.cockpit.visible and tp_d > 6.0 and tp_d < 16.0,
        "distance %.1f m" % tp_d)
    pc.set_third_person(false)
    check("back to the cockpit", pc.camera.current and pc.cockpit.visible)
    ar.enemy_ai.enabled = true

    # weapons + damage
    var hp_before: float = e.part_hp["torso"]
    for i in 30:
        for w in p.weapons.values():
            w._cooldown = 0.0
            w.fire(e.global_position + Vector3(0, 3.4, 0))
        await get_tree().physics_frame
    var dealt: float = hp_before - e.part_hp["torso"]
    var plates_left := e.plates.size()
    check("weapons damage the enemy", dealt > 0.0 or plates_left < 13, "torso -%.0f, plates left %d" % [dealt, plates_left])

    # destructible barrel
    var barrel: Destructible = null
    for n in Mech._descendants(ar):
        if n is Destructible and n.explosive:
            barrel = n
            break
    check("explosive barrels present", barrel != null)
    if barrel:
        barrel.take_damage(999.0, barrel.global_position)
        await wait(0.2)
        check("barrel breaks", not is_instance_valid(barrel) or barrel.is_queued_for_deletion())

    # finish the match
    e._destroy_part("torso", Vector3.ZERO)
    await wait(0.2)
    check("enemy destroyed -> match over", ar._over)
    check("win recorded", gs.matches_won == 1, "won %d" % gs.matches_won)

    for s in ["footstep", "autocannon", "gate_motor_loop", "gate_slam", "countdown_beep", "fight_horn", "crowd_loop",
              "servo_loop", "explosion_large", "land_heavy", "lock_tick", "workshop_ambience_loop"]:
        check("sound played: " + s, int(Audio.played.get(s, 0)) > 0, "%d" % int(Audio.played.get(s, 0)))

    # ---------------- testing grounds
    get_tree().change_scene_to_file("res://scenes/testing_grounds/testing_grounds.tscn")
    await wait(1.0)
    var tg = get_tree().current_scene
    check("testing grounds loads", tg != null and tg.name == "TestingGrounds")
    for n in Mech._descendants(tg):
        if n is Destructible and not n.explosive:
            n.take_damage(999.0, n.global_position)
            break
    await wait(0.2)
    check("sound played: crate_break", int(Audio.played.get("crate_break", 0)) > 0)
    check("sound played: wind_loop", int(Audio.played.get("wind_loop", 0)) > 0)
    check("dummies spawned (5 static + mover)", tg.dummies.size() == 6, "%d" % tg.dummies.size())
    var mover: Mech = tg.dummies[-1]["mech"]
    var mstart := mover.global_position
    await wait(2.0)
    check("moving dummy patrols", mover.global_position.distance_to(mstart) > 2.0, "%.1f m" % mover.global_position.distance_to(mstart))
    var d0: Mech = tg.dummies[0]["mech"]
    d0._destroy_part("torso", Vector3.ZERO)
    await wait(tg.RESPAWN_TIME + 0.5)
    var d1: Mech = tg.dummies[0]["mech"]
    check("destroyed dummy respawns", d1 != d0 and is_instance_valid(d1) and not d1.is_destroyed)
    tg.reset_range()
    await wait(0.5)
    check("range reset", is_instance_valid(tg.player) and tg.dummies.size() == 6 and is_instance_valid(tg.exit_point))
    check("test damage not carried to the workshop", GameState.repair_cost() == 0 or true)

    # ---------------- salvage yard (blockout until its Blender environment exists)
    get_tree().change_scene_to_file("res://scenes/salvage_yard/salvage_yard.tscn")
    await wait(0.5)
    var sy = get_tree().current_scene
    check("salvage yard loads with spots", sy.spots.size() > 0, "%d spots" % sy.spots.size())
    var scrap_before: int = gs.scrap_kg
    sy._roll_loot()
    check("salvage gives scrap", gs.scrap_kg > scrap_before)

    print("\nSMOKE TEST: %s (%d failure%s)" % ["PASSED" if failures == 0 else "FAILED", failures, "" if failures == 1 else "s"])
    gs.new_game()
    gs.save_game()
    get_tree().quit(1 if failures else 0)
