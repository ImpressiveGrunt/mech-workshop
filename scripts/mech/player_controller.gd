class_name PlayerController
extends Node
## First-person mech controls. Add as a child of a built Mech.
##   W/S throttle, A/D turn legs, mouse twists the torso and pitches the arms,
##   LMB right-arm weapon, RMB left-arm weapon, Space boost, C centre torso.
## You sit inside a Blender-built cockpit (mounted on cockpit_camera) and look
## out through its armoured glass. Dashboard screens show live status, radar
## and weapons; the glass cracks as the torso takes damage. The camera rides the
## procedural gait (real body bob), with a thud on each footfall, a jolt on
## landing and shake when hit.

const SCREEN_HZ := 10.0
# Exterior torso pieces hidden on your own mech so they don't intrude on the cockpit.
const EXTERIOR_HIDE := ["cockpit", "canopy", "canopy_frame", "canopy_brow", "chin", "chin_vent", "chin_vent_frame",
    "unit_number", "headlight_L", "headlight_L_housing", "headlight_R", "headlight_R_housing", "cockpit_intake_L",
    "cockpit_intake_L_frame", "cockpit_intake_R", "cockpit_intake_R_frame"]

@export var mouse_sensitivity := 0.0025

var mech: Mech
var camera: Camera3D
var enabled := true  # false = movement/weapons locked (e.g. match intro); looking around still works
var cockpit: Node3D
var _base_pos := Vector3.ZERO
var _shake := 0.0
var _air_time := 0.0
var _screens: Dictionary = {}   # "status" / "radar" / "weapons" -> Label3D
var _cracks: Array = []
var _screen_timer := 0.0


func _ready() -> void:
    mech = get_parent() as Mech
    camera = Camera3D.new()
    camera.fov = 75.0
    camera.near = 0.02
    camera.far = 2000.0
    var anchor: Node3D = mech.cockpit_anchor if mech.cockpit_anchor else mech
    anchor.add_child(camera)
    if anchor == mech:
        camera.position = Vector3(0, 3.6, 0)
    _base_pos = camera.position
    camera.current = true
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    mech.hit_taken.connect(_on_hit)
    mech.footstep.connect(_on_footstep)
    _setup_cockpit()


func _setup_cockpit() -> void:
    var path := str(PartDB.stat(str(mech.loadout.get("torso", "")), "cockpit_interior", ""))
    if path == "" or not ResourceLoader.exists(path) or mech.cockpit_anchor == null:
        return
    cockpit = (load(path) as PackedScene).instantiate() as Node3D
    mech.cockpit_anchor.add_child(cockpit)
    var torso: Node = mech.part_nodes.get("torso")
    for node_name in EXTERIOR_HIDE:
        var n: Node3D = (torso.find_child(node_name, true, false) as Node3D) if torso else null
        if n:
            n.visible = false
    for n in Mech._descendants(cockpit):
        if n is Light3D:
            LevelUtils.tune_light(n)
            (n as Light3D).shadow_enabled = false
        elif n is MeshInstance3D and (String(n.name).contains("glass") or String(n.name).contains("crack")):
            (n as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    for key in ["status", "radar", "weapons"]:
        var marker := cockpit.find_child("screen_" + key, true, false) as Node3D
        if marker:
            _screens[key] = _make_screen_label(marker, key == "radar")
    for k in [1, 2, 3]:
        var c := cockpit.find_child("glass_crack_%d" % k, true, false) as Node3D
        if c:
            c.visible = false
            _cracks.append(c)
    mech.apply_paint(mech.current_paint)   # paint the cockpit trim to match
    mech.set_meta("diegetic_hud", true)


func _make_screen_label(marker: Node3D, big: bool) -> Label3D:
    var l := Label3D.new()
    l.font_size = 34 if big else 30
    l.pixel_size = 0.00065 if big else 0.0006   # sized so the longest lines fit the screen glass
    l.modulate = Color(0.45, 1.0, 0.75)
    l.outline_size = 0
    l.shaded = false
    l.double_sided = false
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    l.width = 280.0 if big else 230.0
    l.autowrap_mode = TextServer.AUTOWRAP_OFF
    var w := float(LevelUtils.extras_of(marker).get("w", 0.2))
    var h := float(LevelUtils.extras_of(marker).get("h", 0.14))
    l.position = Vector3(-w * 0.45, h * 0.42, 0.002)   # top-left corner of the screen
    marker.add_child(l)
    return l


func _on_footstep(_m: Mech, _pos: Vector3, strength: float) -> void:
    add_shake(0.05 * strength)   # each footfall thuds through the cockpit


func _on_hit(_m: Mech, _slot: String, amount: float) -> void:
    add_shake(amount * 0.004)


func add_shake(amount: float) -> void:
    _shake = minf(_shake + amount, 0.35)


func _process(delta: float) -> void:
    if mech.is_on_floor():
        if _air_time > 0.35:
            _shake = maxf(_shake, 0.3)  # landing jolt after a thruster jump
        _air_time = 0.0
    else:
        _air_time += delta
    _shake = move_toward(_shake, 0.0, delta * 0.6)
    var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.08
    camera.position = _base_pos + Vector3(jitter.x, jitter.y, 0)   # the gait moves the cockpit itself
    # Godot cameras look down -Z; mech models face +Z, hence the PI yaw.
    camera.rotation = Vector3(mech.aim_pitch + jitter.y * 0.3, PI, jitter.x * 0.3)
    _screen_timer -= delta
    if cockpit and _screen_timer <= 0.0:
        _screen_timer = 1.0 / SCREEN_HZ
        _update_screens()


func _update_screens() -> void:
    if _screens.has("status"):
        var lines: Array[String] = ["SYSTEMS"]
        for slot in ["torso", "legs", "arm_L", "arm_R", "back"]:
            if mech.part_max_hp.has(slot):
                var f: float = mech.part_hp[slot] / mech.part_max_hp[slot]
                lines.append("%-6s %s %3d%%" % [slot.replace("_", " ").to_upper().left(6), _bar(f, 6), int(f * 100)])
        _screens["status"].text = "\n".join(lines)
        _screens["status"].modulate = Color(1.0, 0.45, 0.35) if mech.part_hp.get("torso", 1.0) < mech.part_max_hp.get("torso", 1.0) * 0.35 else Color(0.45, 1.0, 0.75)
    if _screens.has("radar"):
        var speed := Vector2(mech.velocity.x, mech.velocity.z).length() * 3.6
        var fwd := -camera.global_basis.z
        var heading := fposmod(rad_to_deg(atan2(fwd.x, fwd.z)), 360.0)
        var text := "SPD %3d km/h   HDG %03d\nTWIST %+4d   PITCH %+3d" % [int(speed), int(heading),
            int(rad_to_deg(mech.torso_twist)), int(rad_to_deg(mech.aim_pitch))]
        var target := _nearest_enemy()
        if target:
            var to := target.global_position - mech.global_position
            var bearing := rad_to_deg(Vector2(fwd.x, fwd.z).angle_to(Vector2(to.x, to.z)))
            var arrow := "<<" if bearing < -8.0 else (">>" if bearing > 8.0 else "[ ]")
            text += "\n\nTARGET  %3d m   %s %+4d" % [int(to.length()), arrow, int(bearing)]
        else:
            text += "\n\nNO TARGET"
        _screens["radar"].text = text
    if _screens.has("weapons"):
        var lines: Array[String] = ["WEAPONS"]
        for wslot in ["weapon_R", "weapon_L"]:
            var w: Weapon = mech.weapons.get(wslot)
            if w:
                var wname := PartDB.display_name(w.part_id).split(" ")[0].to_upper()
                lines.append("%s %-10s %s" % ["R" if wslot == "weapon_R" else "L", wname.left(10),
                    "INF" if w.ammo < 0 else "%3d" % w.ammo])
                lines.append("   %s" % ("READY" if w.ready_fraction() >= 1.0 else _bar(w.ready_fraction(), 6)))
            else:
                lines.append("%s --OFFLINE--" % ("R" if wslot == "weapon_R" else "L"))
        if mech.max_fuel > 0.0:
            lines.append("BOOST %s" % _bar(mech.fuel / mech.max_fuel, 6))
        _screens["weapons"].text = "\n".join(lines)
    var torso_f: float = mech.part_hp.get("torso", 1.0) / maxf(1.0, mech.part_max_hp.get("torso", 1.0))
    for k in _cracks.size():
        _cracks[k].visible = torso_f < 1.0 - 0.25 * (k + 1)   # cracks at 75 / 50 / 25 % torso


func _nearest_enemy() -> Mech:
    var best: Mech = null
    var best_d := INF
    for m in get_tree().get_nodes_in_group("mechs"):
        if m == mech or m.is_destroyed:
            continue
        var d: float = m.global_position.distance_to(mech.global_position)
        if d < best_d:
            best_d = d
            best = m
    return best


static func _bar(fraction: float, width: int) -> String:
    var n := int(round(clampf(fraction, 0.0, 1.0) * width))
    return "[" + "#".repeat(n) + "-".repeat(width - n) + "]"


func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("pause"):
        var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
    elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not mech.is_destroyed:
        var motion := event as InputEventMouseMotion
        mech.torso_twist = clampf(mech.torso_twist - motion.relative.x * mouse_sensitivity,
                                  -Mech.TWIST_LIMIT, Mech.TWIST_LIMIT)
        mech.aim_pitch = clampf(mech.aim_pitch - motion.relative.y * mouse_sensitivity,
                                -Mech.PITCH_LIMIT, Mech.PITCH_LIMIT)


func _physics_process(_delta: float) -> void:
    if mech.is_destroyed:
        mech.throttle = 0.0
        mech.turn = 0.0
        mech.boosting = false
        return
    if not enabled:
        return  # someone else (the intro autopilot) is driving
    mech.throttle = Input.get_axis("move_back", "move_forward")
    mech.turn = Input.get_axis("turn_right", "turn_left")
    mech.boosting = Input.is_action_pressed("boost")
    if Input.is_action_just_pressed("center_torso"):
        mech.torso_twist = 0.0
    if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
        return
    if Input.is_action_pressed("fire_primary"):
        _fire("weapon_R")
    if Input.is_action_pressed("fire_secondary"):
        _fire("weapon_L")


func _fire(slot: String) -> void:
    var w: Weapon = mech.weapons.get(slot)
    if w:
        w.fire(aim_point())


func aim_point() -> Vector3:
    var from := camera.global_position
    var to := from - camera.global_basis.z * 500.0
    var q := PhysicsRayQueryParameters3D.create(from, to, Mech.LAYER_WORLD | Mech.LAYER_HITBOX | Mech.LAYER_DEBRIS)
    q.collide_with_areas = true
    var ex: Array[RID] = [mech.get_rid()]
    ex.append_array(mech.hitbox_rids)
    q.exclude = ex
    var hit := camera.get_world_3d().direct_space_state.intersect_ray(q)
    return hit["position"] if not hit.is_empty() else to
