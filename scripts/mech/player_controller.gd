class_name PlayerController
extends Node
## Mech controls. Add as a child of a built Mech.
##   W/S throttle, A/D strafe; the mouse aims the torso and arms, and the legs turn to follow the aim
##   (so they always face forward). LMB left-arm weapon, RMB right-arm weapon, Space boost,
##   V first / third person, hold Left Alt to free-look (camera only, aim stays put), MMB next target.
## You sit inside a Blender-built cockpit (mounted on cockpit_camera) and look
## out through its armoured glass. Dashboard screens show live status, radar
## and weapons; the glass cracks as the torso takes damage. The camera rides the
## procedural gait (real body bob), with a thud on each footfall, a jolt on
## landing and shake when hit.

const SCREEN_HZ := 10.0
# Render layer for your own torso exterior: the cockpit camera doesn't draw it (shadows still do),
# so no piece of the hull can intrude into the cabin.
const HULL_LAYER := 1 << 19

@export var mouse_sensitivity := 0.0025

var mech: Mech
var camera: Camera3D            # first-person eye (cockpit)
var aim: Node3D                 # where the guns point: same place as the eye, ignores free-look
var tp_camera: Camera3D         # third-person chase camera
var third_person := false
var look := Vector2.ZERO        # free-look offset (yaw, pitch), rad
var _tp_pos := Vector3.ZERO
const LOOK_YAW_MAX := deg_to_rad(150.0)
const LOOK_PITCH_MAX := deg_to_rad(60.0)
const TP_DISTANCE := 12.0
const TP_HEIGHT := 3.2
var enabled := true  # false = movement/weapons locked (e.g. match intro); looking around still works
var cockpit: Node3D
var targeting: Targeting
var holo: HoloHud
var _base_pos := Vector3.ZERO
var _shake := 0.0
var _air_time := 0.0
var _screens: Dictionary = {}   # "status" / "radar" / "weapons" -> Label3D
var _cracks: Array = []
var _screen_timer := 0.0
var _snd_lock: AudioStreamPlayer
var _lock_tick_t := 0.0
var _warn_t := 0.0
var _stick_drive: Node3D        # left joystick: tilts with W/S (pitch) and A/D (roll)
var _stick_aim: Node3D          # right joystick: tilts with torso twist / aim pitch rate (mouse)
var _arms: Array = []           # [{shoulder, elbow}]: upper arms re-aimed at the elbows each frame
var _aim_rate := Vector2.ZERO   # smoothed twist / pitch rate, rad/s
var _last_aim := Vector2.ZERO


func _ready() -> void:
    mech = get_parent() as Mech
    camera = Camera3D.new()
    camera.fov = 86.0   # wide view for the wraparound glass
    camera.near = 0.02
    camera.far = 2000.0
    var anchor: Node3D = mech.cockpit_anchor if mech.cockpit_anchor else mech
    anchor.add_child(camera)
    if anchor == mech:
        camera.position = Vector3(0, 3.6, 0)
    _base_pos = camera.position
    aim = Node3D.new()
    anchor.add_child(aim)
    aim.position = _base_pos
    tp_camera = Camera3D.new()
    tp_camera.fov = 70.0
    tp_camera.far = 2000.0
    add_child(tp_camera)            # under a plain Node: positioned in world space each frame
    _tp_pos = mech.global_position + Vector3(0, 6, -10)
    targeting = Targeting.new()
    targeting.mech = mech
    targeting.camera = aim
    targeting.target_changed.connect(func(t): if t != null: Audio.play_2d("target_switch"))
    _snd_lock = Audio.loop_2d("lock_tone_loop", 0.0, self)
    Audio.set_level(_snd_lock, 0.0)
    add_child(targeting)
    camera.current = true
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    mech.hit_taken.connect(_on_hit)
    mech.footstep.connect(_on_footstep)
    _setup_cockpit()


func _setup_cockpit() -> void:
    var path := str(PartDB.stat(str(mech.loadout.get("torso", "")), "cockpit_interior", ""))
    if path == "" or not ResourceLoader.exists(path) or mech.cockpit_anchor == null:
        return
    cockpit = LevelUtils.instance_scene(path) as Node3D
    mech.cockpit_anchor.add_child(cockpit)
    var torso: Node = mech.part_nodes.get("torso")
    if torso:
        _hide_hull(torso)
    camera.cull_mask &= ~HULL_LAYER
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
    _stick_drive = cockpit.find_child("stick_pivot_L", true, false) as Node3D
    _stick_aim = cockpit.find_child("stick_pivot_R", true, false) as Node3D
    _last_aim = Vector2(mech.torso_twist, mech.aim_pitch)
    for sd in ["L", "R"]:
        var shoulder := cockpit.find_child("arm_shoulder_" + sd, true, false) as Node3D
        var elbow := cockpit.find_child("arm_elbow_" + sd, true, false) as Node3D
        if shoulder and elbow:
            _arms.append({"shoulder": shoulder, "elbow": elbow})
    for k in [1, 2, 3]:
        var c := cockpit.find_child("glass_crack_%d" % k, true, false) as Node3D
        if c:
            c.visible = false
            _cracks.append(c)
    _setup_holo()
    mech.apply_paint(mech.current_paint)   # paint the cockpit trim to match
    mech.set_meta("diegetic_hud", true)


## Holographic HUD: render HoloHud into a SubViewport and show it on the Blender holo plane.
func _setup_holo() -> void:
    var frame := cockpit.find_child("holo_frame", true, false) as Node3D
    var surface := cockpit.find_child("holo_hud", true, false) as MeshInstance3D
    if frame == null or surface == null:
        return
    var e := LevelUtils.extras_of(frame)
    var size_m := Vector2(float(e.get("w", 1.1)), float(e.get("h", 0.4)))
    var vp := SubViewport.new()
    vp.size = Vector2i(int(size_m.x * 1000.0), int(size_m.y * 1000.0))   # 1 px = 1 mm on the glass
    vp.transparent_bg = true
    vp.disable_3d = true
    vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(vp)
    holo = HoloHud.new()
    holo.mech = mech
    holo.camera = camera
    holo.aim = aim
    holo.targeting = targeting
    holo.frame = frame
    holo.size_m = size_m
    holo.size = Vector2(vp.size)
    vp.add_child(holo)
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
    m.cull_mode = BaseMaterial3D.CULL_DISABLED
    m.albedo_texture = vp.get_texture()
    surface.material_override = m
    surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    mech.set_meta("holo_hud", true)


## Put the torso's own meshes on HULL_LAYER, stopping at sockets (arms, backpack) and the cockpit mount.
func _hide_hull(n: Node) -> void:
    for c in n.get_children():
        var nm := String(c.name)
        if nm.begins_with("socket_") or nm == "cockpit_camera":
            continue
        if c is VisualInstance3D:
            (c as VisualInstance3D).layers = HULL_LAYER
        _hide_hull(c)


func _make_screen_label(marker: Node3D, big: bool) -> Label3D:
    var l := Label3D.new()
    l.font_size = 34 if big else 30
    l.pixel_size = 0.00042 if big else 0.00036   # sized in-engine so the longest lines fit the overhead screens
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
    l.position = Vector3(-w * 0.45, h * 0.36, 0.002)   # top-left corner of the screen (inset)
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
    aim.rotation = Vector3(mech.aim_pitch, PI, 0)
    if not Input.is_action_pressed("freelook"):
        look = look.lerp(Vector2.ZERO, minf(1.0, delta * 8.0))   # swing back to the aim on release
    var fp_look := look if not third_person else Vector2.ZERO
    camera.rotation = Vector3(mech.aim_pitch + fp_look.y + jitter.y * 0.3, PI + fp_look.x, jitter.x * 0.3)
    if third_person:
        _update_third_person(delta, jitter)
    _animate_sticks(delta)
    _cockpit_tones(delta)
    _screen_timer -= delta
    if cockpit and _screen_timer <= 0.0:
        _screen_timer = 1.0 / SCREEN_HZ
        _update_screens()


## The pilot's hands ride the sticks (they are parented to the pivots in Blender).
## Godot pivot space: +X = mech left, +Z = forward; tilting the stick top forward is +rotation.x,
## toward the left is -rotation.z.
## Chase camera behind and above the mech, looking where you aim (free-look orbits it).
func _update_third_person(delta: float, jitter: Vector2) -> void:
    var fwd := -aim.global_basis.z
    var yaw := atan2(fwd.x, fwd.z) + look.x
    var pitch := clampf(asin(clampf(fwd.y, -1.0, 1.0)) * 0.6 - look.y, -0.5, 0.9)
    var pivot := mech.global_position + Vector3(0, mech.cockpit_anchor.global_position.y - mech.global_position.y + 0.6, 0) \
        if mech.cockpit_anchor else mech.global_position + Vector3(0, 4.0, 0)
    var back := -Vector3(sin(yaw), 0, cos(yaw)) * cos(pitch) + Vector3.UP * sin(pitch + 0.25)
    var want := pivot + back.normalized() * TP_DISTANCE
    var q := PhysicsRayQueryParameters3D.create(pivot, want, Mech.LAYER_WORLD)
    q.exclude = [mech.get_rid()]
    var hit := mech.get_world_3d().direct_space_state.intersect_ray(q)
    if not hit.is_empty():
        want = hit["position"] + (pivot - want).normalized() * 0.5   # don't clip into walls
    _tp_pos = _tp_pos.lerp(want, minf(1.0, delta * 10.0))
    tp_camera.global_position = _tp_pos + Vector3(jitter.x, jitter.y, 0) * 2.0
    var look_target := pivot + Vector3(sin(yaw), 0, cos(yaw)) * 8.0
    if tp_camera.global_position.distance_to(look_target) > 0.1:
        tp_camera.look_at(look_target, Vector3.UP)


## Lock-on ticks speed up as the lock builds; a steady tone while locked; torso damage warning.
func _cockpit_tones(delta: float) -> void:
    var locking := targeting != null and targeting.target != null and targeting.lock > 0.0 and not targeting.locked
    if locking:
        _lock_tick_t -= delta
        if _lock_tick_t <= 0.0:
            _lock_tick_t = lerpf(0.3, 0.07, targeting.lock)
            Audio.play_2d("lock_tick")
    Audio.set_level(_snd_lock, 1.0 if targeting != null and targeting.locked and not mech.is_destroyed else 0.0)
    var torso_f: float = mech.part_hp.get("torso", 1.0) / maxf(1.0, mech.part_max_hp.get("torso", 1.0))
    _warn_t -= delta
    if torso_f < 0.3 and not mech.is_destroyed and _warn_t <= 0.0:
        _warn_t = 1.4
        Audio.play_2d("warning_beep")


func apply_freelook(relative: Vector2) -> void:
    look.x = clampf(look.x - relative.x * mouse_sensitivity, -LOOK_YAW_MAX, LOOK_YAW_MAX)
    look.y = clampf(look.y - relative.y * mouse_sensitivity, -LOOK_PITCH_MAX, LOOK_PITCH_MAX)


func set_third_person(on: bool) -> void:
    third_person = on
    if on:
        _tp_pos = mech.global_position + Vector3(0, 6, 0) - (-aim.global_basis.z) * TP_DISTANCE
    tp_camera.current = on
    camera.current = not on
    if cockpit:
        cockpit.visible = not on
    if on:
        mech.remove_meta("holo_hud")
        mech.remove_meta("diegetic_hud")
    elif cockpit:
        mech.set_meta("diegetic_hud", true)
        if holo:
            mech.set_meta("holo_hud", true)


func _animate_sticks(delta: float) -> void:
    const MAX_TILT := 0.32
    var aim := Vector2(mech.torso_twist, mech.aim_pitch)
    if delta > 0.0:
        _aim_rate = _aim_rate.lerp((aim - _last_aim) / delta, minf(1.0, delta * 12.0))
    _last_aim = aim
    if _stick_drive:
        var target := Vector3(mech.throttle * MAX_TILT, 0.0, -(mech.turn + mech.strafe) * MAX_TILT)
        _stick_drive.rotation = _stick_drive.rotation.lerp(target, minf(1.0, delta * 10.0))
    if _stick_aim:
        var target := Vector3(clampf(-_aim_rate.y * 0.12, -MAX_TILT, MAX_TILT), 0.0,
            clampf(-_aim_rate.x * 0.12, -MAX_TILT, MAX_TILT))
        _stick_aim.rotation = _stick_aim.rotation.lerp(target, minf(1.0, delta * 14.0))
    # forearms ride the sticks; swing each upper arm from its shoulder so it stays joined at the elbow
    for arm in _arms:
        var shoulder: Node3D = arm["shoulder"]
        var elbow: Node3D = arm["elbow"]
        var up := cockpit.global_basis.y
        if shoulder.global_position.distance_to(elbow.global_position) > 0.01:
            shoulder.look_at(elbow.global_position, up)   # Blender modelled the upper arm along local +Y (= Godot -Z)


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
        var fwd := -aim.global_basis.z
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
    elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("freelook"):
        apply_freelook((event as InputEventMouseMotion).relative)   # free-look: move only the camera
    elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not mech.is_destroyed:
        var motion := event as InputEventMouseMotion
        # the mouse moves the aim point; the heavy torso/arms swing after it (Mech._slew_aim)
        mech.target_twist = clampf(mech.target_twist - motion.relative.x * mouse_sensitivity,
                                   -Mech.TWIST_LIMIT, Mech.TWIST_LIMIT)
        mech.target_pitch = clampf(mech.target_pitch - motion.relative.y * mouse_sensitivity,
                                   -Mech.PITCH_LIMIT, Mech.PITCH_LIMIT)


func _physics_process(_delta: float) -> void:
    if Input.is_action_just_pressed("toggle_view"):
        set_third_person(not third_person)
    if mech.is_destroyed:
        mech.throttle = 0.0
        mech.turn = 0.0
        mech.strafe = 0.0
        mech.boosting = false
        return
    mech.legs_follow_aim = enabled
    if not enabled:
        return  # someone else (the intro autopilot) is driving
    mech.throttle = Input.get_axis("move_back", "move_forward")
    mech.strafe = Input.get_axis("strafe_right", "strafe_left")
    mech.turn = 0.0
    mech.boosting = Input.is_action_pressed("boost")
    if Input.is_action_just_pressed("center_torso"):
        mech.target_twist = 0.0
    if Input.is_action_just_pressed("target_cycle") and targeting:
        targeting.cycle()
    if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
        return
    if Input.is_action_pressed("fire_left"):
        _fire("weapon_L")
    if Input.is_action_pressed("fire_right"):
        _fire("weapon_R")


func _fire(slot: String) -> void:
    var w: Weapon = mech.weapons.get(slot)
    if w == null:
        return
    if w.weapon_type == "explosive" and targeting and targeting.locked and targeting.target:
        w.fire(Targeting.aim_point_of(targeting.target))   # locked missiles home in on centre mass
    else:
        w.fire(aim_point())


func aim_point() -> Vector3:
    var from := aim.global_position
    var to := from - aim.global_basis.z * 500.0
    var q := PhysicsRayQueryParameters3D.create(from, to, Mech.LAYER_WORLD | Mech.LAYER_HITBOX | Mech.LAYER_DEBRIS)
    q.collide_with_areas = true
    var ex: Array[RID] = [mech.get_rid()]
    ex.append_array(mech.hitbox_rids)
    q.exclude = ex
    var hit := aim.get_world_3d().direct_space_state.intersect_ray(q)
    return hit["position"] if not hit.is_empty() else to
