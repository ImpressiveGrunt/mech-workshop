class_name Destructible
extends StaticBody3D
## Breakable environment prop (crates, barrels). Built from Blender props tagged
## extras {"destructible": true, "hp": n, "explosive": bool}. Weapons call
## take_damage(); at 0 HP the prop bursts into physics debris, and explosive
## ones damage nearby mechs and set off other props (chain reactions).

const EXPLOSION_RADIUS := 6.0
const EXPLOSION_DAMAGE := 70.0

var hp := 100.0
var explosive := false
var visual: MeshInstance3D
var _broken := false


## Replace a static mesh with a destructible body wrapping it.
static func wrap(mi: MeshInstance3D, extras: Dictionary) -> Destructible:
    var d := Destructible.new()
    d.hp = float(extras.get("hp", 100))
    d.explosive = bool(extras.get("explosive", false))
    d.collision_layer = Mech.LAYER_WORLD
    d.collision_mask = 0
    mi.get_parent().add_child(d)
    d.global_transform = mi.global_transform
    mi.reparent(d, true)
    var aabb := mi.get_aabb()
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = aabb.size
    shape.shape = box
    shape.position = mi.position + aabb.get_center()
    d.add_child(shape)
    d.visual = mi
    return d


func take_damage(amount: float, at: Vector3) -> void:
    if _broken:
        return
    hp -= amount
    if hp <= 0.0:
        _break(at)


func _break(at: Vector3) -> void:
    _broken = true
    var aabb := visual.get_aabb()
    var center := visual.global_transform * aabb.get_center()
    var material := visual.get_active_material(0)
    for i in 6:
        _spawn_chunk(center, aabb.size, material, at)
    Audio.play("crate_break" if not explosive else "explosion_large", center)
    if explosive:
        _explode(center)
    queue_free()


func _spawn_chunk(center: Vector3, size: Vector3, material: Material, at: Vector3) -> void:
    var s := size * randf_range(0.25, 0.45)
    var mesh := BoxMesh.new()
    mesh.size = s
    mesh.material = material
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    var shape := CollisionShape3D.new()
    var box := BoxShape3D.new()
    box.size = s
    shape.shape = box
    var body := RigidBody3D.new()
    body.collision_layer = Mech.LAYER_DEBRIS
    body.collision_mask = Mech.LAYER_WORLD | Mech.LAYER_DEBRIS
    body.mass = 20.0
    body.add_child(mi)
    body.add_child(shape)
    get_tree().current_scene.add_child(body)
    body.global_position = center + Vector3(randf_range(-.4, .4) * size.x, randf_range(0, .4) * size.y, randf_range(-.4, .4) * size.z)
    var away := (body.global_position - at).normalized()
    body.apply_central_impulse((away + Vector3.UP) * randf_range(60.0, 140.0) * (3.0 if explosive else 1.0))
    body.apply_torque_impulse(Vector3(randf() - .5, randf() - .5, randf() - .5) * 40.0)
    get_tree().create_timer(20.0).timeout.connect(body.queue_free)


func _explode(center: Vector3) -> void:
    var sphere := SphereShape3D.new()
    sphere.radius = EXPLOSION_RADIUS
    var q := PhysicsShapeQueryParameters3D.new()
    q.shape = sphere
    q.transform = Transform3D(Basis(), center)
    q.collide_with_areas = true
    q.collide_with_bodies = true
    q.collision_mask = Mech.LAYER_WORLD | Mech.LAYER_HITBOX
    q.exclude = [get_rid()]
    var seen := {}
    for r in get_world_3d().direct_space_state.intersect_shape(q, 64):
        var c = r["collider"]
        if c is Area3D and c.has_meta("mech"):
            var key := "%d:%s" % [c.get_meta("mech").get_instance_id(), c.get_meta("slot")]
            if seen.has(key):
                continue
            seen[key] = true
            var d: float = c.global_position.distance_to(center)
            var falloff := clampf(1.0 - d / EXPLOSION_RADIUS, 0.15, 1.0)
            var away: Vector3 = (c.global_position - center).normalized()
            c.get_meta("mech").take_hit(str(c.get_meta("slot")), EXPLOSION_DAMAGE * falloff, c.global_position, away * 4.0)
        elif c is Destructible and c != self:
            c.call_deferred("take_damage", 999.0, center)  # chain reaction
    _flash(center)


func _flash(center: Vector3) -> void:
    var scene := get_tree().current_scene
    var light := OmniLight3D.new()
    light.light_color = Color(1.0, 0.6, 0.25)
    light.light_energy = 10.0
    light.omni_range = 14.0
    scene.add_child(light)
    light.global_position = center + Vector3.UP
    var ball := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = 1.0
    mesh.height = 2.0
    var m := StandardMaterial3D.new()
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
    mesh.material = m
    ball.mesh = mesh
    scene.add_child(ball)
    ball.global_position = center + Vector3.UP
    var tw := scene.create_tween().set_parallel(true)
    tw.tween_property(ball, "scale", Vector3.ONE * EXPLOSION_RADIUS * 0.8, 0.35)
    tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
    tw.tween_property(light, "light_energy", 0.0, 0.6)
    tw.chain().tween_callback(ball.queue_free)
    tw.tween_callback(light.queue_free)
