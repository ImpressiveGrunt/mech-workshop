class_name Mech
extends CharacterBody3D
## A modular mech assembled at runtime from the Blender-made part scenes.
##
## Parts snap together through sockets (socket_torso, socket_arm_L/R,
## socket_hand, socket_back). Damage model:
##   * "*_collider" meshes become per-part hitboxes (Area3D, layer "hitbox").
##   * "armor_*" plates soak hits near them, then break off as physics debris.
##   * "weak_point*" nodes (reactor) multiply damage.
##   * A part at 0 HP is destroyed: arms/weapons/backpack fall off, legs get
##     crippled, and losing the torso destroys the mech.
## Controllers (player or AI) drive it by setting throttle / turn / twist / pitch.

signal destroyed(mech: Mech)
signal part_destroyed(mech: Mech, slot: String)
signal hit_taken(mech: Mech, slot: String, amount: float)
signal footstep(mech: Mech, world_pos: Vector3, strength: float)

const GRAVITY := 24.0
const LAYER_WORLD := 1
const LAYER_MECH := 2
const LAYER_HITBOX := 4
const LAYER_DEBRIS := 8
const TWIST_LIMIT := deg_to_rad(110.0)
const PITCH_LIMIT := deg_to_rad(35.0)
const WEAK_POINT_RADIUS := 0.7
const PLATE_RADIUS := 1.5
# Weighted aim: the torso and arms are heavy. They chase target_twist / target_pitch with a
# critically damped spring and a top slew speed, so the view and guns trail behind the mouse.
const AIM_STIFFNESS := 26.0
const AIM_MAX_TWIST_SPEED := deg_to_rad(85.0)
const AIM_MAX_PITCH_SPEED := deg_to_rad(55.0)
const PAINT_SUFFIXES := {"_paint": "primary", "_trim": "secondary", "_hazard": "accent", "_glow": "glow"}

var loadout: Dictionary = {}
var part_nodes: Dictionary = {}   # slot -> Node3D
var part_hp: Dictionary = {}      # slot -> float
var part_max_hp: Dictionary = {}  # slot -> float
var plates: Array = []            # [{node, slot, hp}]
var weak_points: Array = []
var weapons: Dictionary = {}      # "weapon_L"/"weapon_R" -> Weapon
var hitbox_rids: Array[RID] = []
var torso_pivot: Node3D
var cockpit_anchor: Node3D
var shoulders: Array = []
var slot_meshes: Dictionary = {}  # slot -> visible meshes of that part (for highlighting)
var _paint_cache: Dictionary = {}
var _highlight_mat: StandardMaterial3D
var gait: MechGait
var current_paint: Dictionary = {}
var yaw_velocity := 0.0   # rad/s, eased so heavy mechs wind up and wind down their turns
var is_destroyed := false

# Inputs written by a controller.
var throttle := 0.0  # -1 back .. 1 forward
var turn := 0.0      # -1 right .. 1 left (explicit leg turning: AI, autopilot)
var strafe := 0.0    # -1 right .. 1 left (sidestep relative to the legs)
var legs_follow_aim := false   # player mode: legs turn to face where the torso aims
const STRAFE_FACTOR := 0.65    # sidestepping is slower than walking forward
var boosting := false
var torso_twist := 0.0   # actual (lags behind the target)
var aim_pitch := 0.0
var target_twist := 0.0  # where the pilot / AI wants to aim
var target_pitch := 0.0
var aim_agility := 1.0   # from the arms' aim_speed stat
var _twist_vel := 0.0
var _pitch_vel := 0.0

# Derived from parts.
var mass_kg := 1000.0
var top_speed := 6.0
var turn_rate := deg_to_rad(80.0)
var boost_force := 0.0
var fuel := 0.0
var max_fuel := 0.0
var fuel_recharge := 0.0
var _impulse := Vector3.ZERO


func build(new_loadout: Dictionary, carried_damage: Dictionary = {}, paint: Dictionary = {}) -> void:
    loadout = new_loadout.duplicate()
    add_to_group("mechs")
    floor_snap_length = 0.6
    floor_max_angle = deg_to_rad(40.0)
    collision_layer = LAYER_MECH
    collision_mask = LAYER_WORLD | LAYER_MECH
    var body_shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 1.4
    capsule.height = 4.6
    body_shape.shape = capsule
    body_shape.position = Vector3(0, 2.3, 0)
    add_child(body_shape)

    var legs := _spawn("legs", self)
    if legs == null:
        return
    torso_pivot = _find(legs, "socket_torso")
    gait = MechGait.new()
    add_child(gait)
    if gait.setup(self, legs):
        gait.footstep.connect(_on_gait_footstep)
    else:
        gait.queue_free()
        gait = null
    var torso := _spawn("torso", torso_pivot)
    if torso:
        cockpit_anchor = _find(torso, "cockpit_camera")
        for side in ["L", "R"]:
            var arm := _spawn("arm_" + side, _find(torso, "socket_arm_" + side))
            if arm == null:
                continue
            var shoulder := _find(arm, "joint_shoulder_" + side)
            if shoulder:
                shoulders.append(shoulder)
            var wslot: String = "weapon_" + side
            var model := _spawn(wslot, _find(arm, "socket_hand"))
            if model:
                var w := Weapon.new()
                w.setup(self, wslot, str(loadout[wslot]), model)
                model.add_child(w)
                weapons[wslot] = w
        _spawn("back", _find(torso, "socket_back"))
    _compute_stats()
    for slot in carried_damage:
        if part_hp.has(slot):
            part_hp[slot] = maxf(1.0, part_hp[slot] - float(carried_damage[slot]))
    _strip_damaged_armor()
    if not paint.is_empty():
        apply_paint(paint)


## Carried damage shows: a part at 60% HP is missing ~40% of its armor plates.
func _strip_damaged_armor() -> void:
    for slot in part_max_hp:
        var lost: float = 1.0 - part_hp[slot] / part_max_hp[slot]
        var slot_plates := plates.filter(func(p): return p["slot"] == slot)
        for k in int(round(lost * slot_plates.size())):
            var p: Dictionary = slot_plates[k]
            p["node"].visible = false
            plates.erase(p)


## Recolour the mech. paint: {"primary", "secondary", "accent", "glow"} -> "#rrggbb".
func apply_paint(paint: Dictionary) -> void:
    current_paint = paint.duplicate()
    _paint_cache.clear()
    for n in _descendants(self):
        if not (n is MeshInstance3D) or n.mesh == null:
            continue
        var mi := n as MeshInstance3D
        for i in mi.mesh.get_surface_count():
            var base := mi.mesh.surface_get_material(i) as BaseMaterial3D
            if base == null:
                continue
            var channel := ""
            for suffix in PAINT_SUFFIXES:
                if base.resource_name.ends_with(suffix):
                    channel = PAINT_SUFFIXES[suffix]
            if channel == "" or not paint.has(channel):
                mi.set_surface_override_material(i, null)
                continue
            if not _paint_cache.has(base):
                var m := base.duplicate() as BaseMaterial3D
                var c := Color(str(paint[channel]))
                m.albedo_color = c
                if channel == "glow":
                    m.emission_enabled = true
                    m.emission = c
                _paint_cache[base] = m
            mi.set_surface_override_material(i, _paint_cache[base])


func set_highlight(slot: String, on: bool) -> void:
    if _highlight_mat == null:
        _highlight_mat = StandardMaterial3D.new()
        _highlight_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        _highlight_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        _highlight_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
        _highlight_mat.albedo_color = Color(1.0, 0.55, 0.2, 0.35)
    for mi in slot_meshes.get(slot, []):
        if is_instance_valid(mi):
            mi.material_overlay = _highlight_mat if on else null


func damage_report() -> Dictionary:
    var out := {}
    for slot in part_max_hp:
        out[slot] = part_max_hp[slot] - part_hp[slot]
    return out


func is_part_alive(slot: String) -> bool:
    return part_hp.get(slot, 0.0) > 0.0


# ------------------------------------------------------------- movement
func _physics_process(delta: float) -> void:
    var legs_ok := is_part_alive("legs")
    var steer := turn
    if legs_follow_aim and absf(turn) < 0.01:
        steer = clampf(target_twist * 2.5, -1.0, 1.0)   # legs swing round under the torso's aim
    var target_yaw := 0.0 if is_destroyed else steer * turn_rate * (1.0 if legs_ok else 0.4)
    yaw_velocity = move_toward(yaw_velocity, target_yaw, turn_rate * 2.5 * delta)
    var dyaw := yaw_velocity * delta
    rotate_y(dyaw)
    if legs_follow_aim:
        # keep the aim fixed in the world while the legs turn underneath it
        torso_twist -= dyaw
        target_twist -= dyaw
    var forward := global_basis.z  # models face +Z (Blender -Y)
    var left := global_basis.x     # pilot's left is +X
    var speed := top_speed * (1.0 if legs_ok else 0.25)
    var wish := forward * throttle + left * strafe * STRAFE_FACTOR
    if wish.length() > 1.0:
        wish = wish.normalized()
    var target := wish * speed if not is_destroyed else Vector3.ZERO
    var accel := clampf(180000.0 / mass_kg, 2.5, 14.0)   # ~6.7 m/s^2 for the 27 t starter mech
    var horizontal := Vector3(velocity.x, 0, velocity.z).move_toward(target, accel * delta)
    velocity.x = horizontal.x
    velocity.z = horizontal.z
    velocity.y -= GRAVITY * delta
    if boosting and fuel > 0.0 and boost_force > 0.0 and not is_destroyed:
        velocity += (Vector3.UP * 0.85 + forward * 0.35) * (boost_force / mass_kg) * delta
        fuel = maxf(0.0, fuel - 35.0 * delta)
    elif is_on_floor():
        fuel = minf(max_fuel, fuel + fuel_recharge * delta)
    velocity += _impulse
    _impulse = Vector3.ZERO
    move_and_slide()
    if not is_destroyed:
        _slew_aim(delta)
    if torso_pivot:
        torso_pivot.rotation.y = torso_twist
    for s in shoulders:
        if is_instance_valid(s):
            s.rotation.x = -aim_pitch


# ------------------------------------------------------------- damage
func take_hit(slot: String, amount: float, at: Vector3, push: Vector3 = Vector3.ZERO) -> void:
    if is_destroyed or not is_part_alive(slot):
        return
    var dmg := amount
    for wp in weak_points:
        if is_instance_valid(wp) and wp.global_position.distance_to(at) < WEAK_POINT_RADIUS:
            dmg *= 2.5
            break
    var plate := _nearest_plate(slot, at)
    if not plate.is_empty():
        plate["hp"] -= dmg
        if plate["hp"] > 0.0:
            dmg = 0.0
        else:
            dmg = -plate["hp"] * 0.5
            plates.erase(plate)
            _detach(plate["node"], push)
    if dmg > 0.0:
        part_hp[slot] = maxf(0.0, part_hp[slot] - dmg)
        if part_hp[slot] <= 0.0:
            _destroy_part(slot, push)
    _impulse += push * (8000.0 / mass_kg)
    if gait:
        gait.kick(push)
    hit_taken.emit(self, slot, amount)


func _slew_aim(delta: float) -> void:
    target_twist = clampf(target_twist, -TWIST_LIMIT, TWIST_LIMIT)
    target_pitch = clampf(target_pitch, -PITCH_LIMIT, PITCH_LIMIT)
    var k := AIM_STIFFNESS * aim_agility
    var c := 2.0 * sqrt(k)
    _twist_vel += ((target_twist - torso_twist) * k - _twist_vel * c) * delta
    _pitch_vel += ((target_pitch - aim_pitch) * k - _pitch_vel * c) * delta
    _twist_vel = clampf(_twist_vel, -AIM_MAX_TWIST_SPEED * aim_agility, AIM_MAX_TWIST_SPEED * aim_agility)
    _pitch_vel = clampf(_pitch_vel, -AIM_MAX_PITCH_SPEED * aim_agility, AIM_MAX_PITCH_SPEED * aim_agility)
    torso_twist = clampf(torso_twist + _twist_vel * delta, -TWIST_LIMIT, TWIST_LIMIT)
    aim_pitch = clampf(aim_pitch + _pitch_vel * delta, -PITCH_LIMIT, PITCH_LIMIT)


## World direction the pilot is aiming at (the target, not where the guns point yet).
func target_aim_direction() -> Vector3:
    var local := Basis(Vector3.UP, target_twist) * (Basis(Vector3.RIGHT, -target_pitch) * Vector3(0, 0, 1))
    return (global_basis * local).normalized()


func _on_gait_footstep(_side: String, world_pos: Vector3, strength: float) -> void:
    footstep.emit(self, world_pos, strength * clampf(mass_kg / 25000.0, 0.5, 2.0))


func _nearest_plate(slot: String, at: Vector3) -> Dictionary:
    var best := {}
    var best_d := PLATE_RADIUS
    for p in plates:
        if p["slot"] != slot or not is_instance_valid(p["node"]):
            continue
        var d: float = p["node"].global_position.distance_to(at)
        if d < best_d:
            best_d = d
            best = p
    return best


func _destroy_part(slot: String, push: Vector3) -> void:
    part_destroyed.emit(self, slot)
    match slot:
        "torso":
            _explode(push)
        "arm_L", "arm_R":
            var wslot := "weapon_" + slot.right(1)
            weapons.erase(wslot)
            part_hp[wslot] = 0.0
            _detach(part_nodes.get(slot), push)
        "weapon_L", "weapon_R":
            weapons.erase(slot)
            _detach(part_nodes.get(slot), push)
        "back":
            boost_force = 0.0
            _detach(part_nodes.get(slot), push)
        "legs":
            pass  # crippled: movement drops to 25% in _physics_process


func _explode(push: Vector3) -> void:
    is_destroyed = true
    weapons.clear()
    for slot in ["weapon_L", "weapon_R", "arm_L", "arm_R", "back"]:
        if is_part_alive(slot):
            part_hp[slot] = 0.0
            _detach(part_nodes.get(slot), push + Vector3(randf_range(-1, 1), 1, randf_range(-1, 1)))
    destroyed.emit(self)


func _detach(node: Node3D, push: Vector3) -> void:
    if node == null or not is_instance_valid(node) or not node.is_inside_tree():
        return
    for n in _descendants(node):
        if n is Area3D:
            hitbox_rids.erase((n as Area3D).get_rid())
            n.queue_free()
    var aabb := _subtree_aabb(node)
    var body := RigidBody3D.new()
    body.collision_layer = LAYER_DEBRIS
    body.collision_mask = LAYER_WORLD | LAYER_DEBRIS
    body.mass = maxf(50.0, aabb.get_volume() * 400.0)
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = aabb.size.max(Vector3.ONE * 0.2)
    shape.shape = box
    shape.position = aabb.get_center()
    body.add_child(shape)
    get_tree().current_scene.add_child(body)
    body.global_transform = node.global_transform
    node.reparent(body, true)
    var dir := push.normalized() + Vector3.UP * 0.6
    body.apply_central_impulse(dir * body.mass * randf_range(3.0, 7.0))
    body.apply_torque_impulse(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * body.mass * 4.0)
    get_tree().create_timer(45.0).timeout.connect(body.queue_free)


# ------------------------------------------------------------- assembly helpers
func _spawn(slot: String, parent: Node3D) -> Node3D:
    var id := str(loadout.get(slot, ""))
    if id == "" or parent == null:
        return null
    var node := PartDB.instantiate(id)
    if node == null:
        return null
    parent.add_child(node)
    part_nodes[slot] = node
    var hp := float(PartDB.stat(id, "hp", 100))
    part_hp[slot] = hp
    part_max_hp[slot] = hp
    _prepare_part(node, slot)
    return node


func _prepare_part(root: Node, slot: String) -> void:
    slot_meshes[slot] = []
    for n in _descendants(root):
        var nm := String(n.name)
        if n is MeshInstance3D and not nm.ends_with("_collider"):
            slot_meshes[slot].append(n)
        if n is MeshInstance3D and nm.ends_with("_collider"):
            _make_hitbox(n as MeshInstance3D, slot)
        elif n is MeshInstance3D and nm.begins_with("armor_"):
            var extras = n.get_meta("extras", {})
            var hp := 40.0
            if extras is Dictionary:
                hp = float(extras.get("hp", hp))
            plates.append({"node": n, "slot": slot, "hp": hp})
        elif nm.begins_with("weak_point"):
            weak_points.append(n)


func _make_hitbox(mi: MeshInstance3D, slot: String) -> void:
    mi.visible = false
    var aabb := mi.get_aabb()
    var area := Area3D.new()
    area.collision_layer = LAYER_HITBOX
    area.collision_mask = 0
    area.monitoring = false
    area.set_meta("mech", self)
    area.set_meta("slot", slot)
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = aabb.size
    shape.shape = box
    shape.position = aabb.get_center()
    area.add_child(shape)
    mi.add_child(area)
    hitbox_rids.append(area.get_rid())


func _compute_stats() -> void:
    mass_kg = 0.0
    for slot in loadout:
        mass_kg += float(PartDB.stat(str(loadout[slot]), "mass_kg", 0))
    mass_kg = maxf(mass_kg, 1000.0)
    var legs_id := str(loadout.get("legs", ""))
    var overload := maxf(1.0, mass_kg / float(PartDB.stat(legs_id, "load_capacity", 20000)))
    top_speed = float(PartDB.stat(legs_id, "speed", 6)) / overload
    turn_rate = deg_to_rad(float(PartDB.stat(legs_id, "turn_rate", 80)))
    var aim_speeds := []
    for side in ["arm_L", "arm_R"]:
        if loadout.get(side, "") != "":
            aim_speeds.append(float(PartDB.stat(str(loadout[side]), "aim_speed", 120)))
    if not aim_speeds.is_empty():
        aim_agility = clampf((aim_speeds[0] + aim_speeds[-1]) * 0.5 / 120.0, 0.5, 1.5)
    var back_id := str(loadout.get("back", ""))
    if part_nodes.has("back"):
        boost_force = float(PartDB.stat(back_id, "boost_force", 0))
        max_fuel = float(PartDB.stat(back_id, "fuel", 0))
        fuel_recharge = float(PartDB.stat(back_id, "recharge", 0))
    fuel = max_fuel


func _subtree_aabb(root: Node3D) -> AABB:
    var inv := root.global_transform.affine_inverse()
    var out := AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
    var first := true
    for n in [root] + _descendants(root):
        if n is MeshInstance3D and (n as MeshInstance3D).visible:
            var mi := n as MeshInstance3D
            var b := (inv * mi.global_transform) * mi.get_aabb()
            out = b if first else out.merge(b)
            first = false
    return out


static func _find(root: Node, node_name: String) -> Node3D:
    if root == null:
        return null
    return root.find_child(node_name, true, false) as Node3D


static func _descendants(n: Node) -> Array:
    var out := []
    for c in n.get_children():
        out.append(c)
        out.append_array(_descendants(c))
    return out
