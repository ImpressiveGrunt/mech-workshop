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
