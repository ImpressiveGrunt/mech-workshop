class_name Weapon
extends Node3D
## Runtime behaviour for a weapon part: hitscan (ballistic), short-range
## melee, or explosive with splash. Stats come from PartDB.

var mech: Mech
var slot := ""
var part_id := ""
var weapon_type := "ballistic"
var damage := 10.0
var fire_rate := 1.0
var weapon_range := 50.0
var ammo := -1  # -1 = unlimited
var muzzle: Node3D
var _cooldown := 0.0


func setup(owner_mech: Mech, weapon_slot: String, id: String, model: Node3D) -> void:
    mech = owner_mech
    slot = weapon_slot
    part_id = id
    var p := PartDB.get_part(id)
    weapon_type = str(p.get("weapon_type", "ballistic"))
    damage = float(p.get("damage", 10))
    fire_rate = maxf(0.1, float(p.get("fire_rate", 1)))
    weapon_range = float(p.get("range", 50))
    ammo = int(p.get("ammo", -1))
    muzzle = model.find_child("socket_muzzle", true, false) as Node3D


func _process(delta: float) -> void:
    _cooldown = maxf(0.0, _cooldown - delta)


func ready_fraction() -> float:
    return clampf(1.0 - _cooldown * fire_rate, 0.0, 1.0)


func can_fire() -> bool:
    return _cooldown <= 0.0 and ammo != 0 and not mech.is_destroyed


func fire(aim_point: Vector3) -> void:
    if not can_fire():
        return
    _cooldown = 1.0 / fire_rate
    if ammo > 0:
        ammo -= 1
    var from := muzzle.global_position if muzzle else global_position
    Audio.play({"ballistic": "autocannon", "explosive": "missile_launch", "melee": "ram_fist"}.get(weapon_type, "autocannon"), from)
    var dir := (aim_point - from).normalized()
    var end := from + dir * weapon_range
    var hit := _ray(from, end)
    if not hit.is_empty():
        end = hit["position"]
        _apply_hit(hit["collider"], end, dir, damage)
        if weapon_type != "explosive":
            var c = hit["collider"]
            var metal: bool = (c is Area3D and c.has_meta("mech")) or c is RigidBody3D
            Audio.play("impact_metal" if metal else "impact_ground", end, 0.0 if weapon_type == "ballistic" else 4.0)
    if weapon_type == "explosive":
        Audio.play("explosion_small", end, -2.0)
        _splash(end)
    _tracer(from, end)


func _ray(a: Vector3, b: Vector3) -> Dictionary:
    var q := PhysicsRayQueryParameters3D.create(a, b, Mech.LAYER_WORLD | Mech.LAYER_HITBOX | Mech.LAYER_DEBRIS)
    q.collide_with_areas = true
    var ex: Array[RID] = [mech.get_rid()]
    ex.append_array(mech.hitbox_rids)
    q.exclude = ex
    return get_world_3d().direct_space_state.intersect_ray(q)


func _apply_hit(collider: Object, pos: Vector3, dir: Vector3, amount: float) -> void:
    if collider is Area3D and collider.has_meta("mech"):
        var target = collider.get_meta("mech")
        if is_instance_valid(target):
            target.take_hit(str(collider.get_meta("slot")), amount, pos, dir * amount * 0.05)
    elif collider is RigidBody3D:
        var rb := collider as RigidBody3D
        rb.apply_impulse(dir * amount * 20.0, pos - rb.global_position)
    elif collider != null and collider.has_method("take_damage"):
        collider.take_damage(amount, pos)


func _splash(center: Vector3, radius: float = 3.0) -> void:
    var sphere := SphereShape3D.new()
    sphere.radius = radius
    var q := PhysicsShapeQueryParameters3D.new()
    q.shape = sphere
    q.transform = Transform3D(Basis(), center)
    q.collide_with_areas = true
    q.collide_with_bodies = false
    q.collision_mask = Mech.LAYER_HITBOX
    q.exclude = mech.hitbox_rids
    var seen := {}
    for r in get_world_3d().direct_space_state.intersect_shape(q, 32):
        var area = r["collider"]
        if not (area is Area3D and area.has_meta("mech")):
            continue
        var key := "%d:%s" % [area.get_meta("mech").get_instance_id(), area.get_meta("slot")]
        if seen.has(key):
            continue
        seen[key] = true
        var falloff := clampf(1.0 - area.global_position.distance_to(center) / radius, 0.2, 1.0)
        var away: Vector3 = (area.global_position - center).normalized()
        _apply_hit(area, area.global_position, away, damage * 0.5 * falloff)


func _tracer(a: Vector3, b: Vector3) -> void:
    var length := a.distance_to(b)
    if weapon_type == "melee" or length < 0.1:
        return
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.07, 0.07, length)
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = Color(1.0, 0.75, 0.3) if weapon_type == "ballistic" else Color(1.0, 0.4, 0.2)
    mesh.material = m
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    get_tree().current_scene.add_child(mi)
    mi.global_position = (a + b) * 0.5
    var dir := (b - a) / length
    mi.look_at(b, Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP)
    var tw := mi.create_tween()
    tw.tween_property(mi, "scale", Vector3(0.1, 0.1, 1.0), 0.08)
    tw.tween_callback(mi.queue_free)
