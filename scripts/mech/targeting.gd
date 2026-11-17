class_name Targeting
extends Node
## Player targeting: picks a target (most central in front, T cycles), checks line of sight,
## and builds a lock while the guns are held on it. A locked target makes missiles home in.

signal target_changed(target: Mech)

const LOCK_TIME := 0.9               # seconds on target to lock
const LOCK_CONE := deg_to_rad(5.0)   # guns must point within this of the target
const LOCK_RANGE := 220.0
const ACQUIRE_CONE := deg_to_rad(75.0)

var mech: Mech
var camera: Camera3D
var target: Mech
var lock := 0.0          # 0..1 lock progress
var locked := false
var has_line_of_sight := false


static func aim_point_of(m: Mech) -> Vector3:
    return m.global_position + Vector3(0, 3.3, 0)   # centre mass (torso)


func _physics_process(delta: float) -> void:
    if mech == null or camera == null:
        return
    if target != null and (not is_instance_valid(target) or target.is_destroyed):
        _set_target(null)
    if target == null:
        _set_target(_best_target(null))
    if target == null:
        lock = 0.0
        locked = false
        return
    var to := aim_point_of(target) - camera.global_position
    has_line_of_sight = _line_of_sight(target)
    var on_target := (-camera.global_basis.z).angle_to(to) < LOCK_CONE and to.length() < LOCK_RANGE and has_line_of_sight
    if on_target:
        lock = minf(1.0, lock + delta / LOCK_TIME)
    else:
        lock = maxf(0.0, lock - delta * 1.2)
    if lock >= 1.0:
        locked = true
    elif lock < 0.6:
        locked = false


## Next target, ordered by how central it is in view.
func cycle() -> void:
    _set_target(_best_target(target))


func candidates() -> Array:
    var out := []
    for m in get_tree().get_nodes_in_group("mechs"):
        if m != mech and not m.is_destroyed:
            out.append(m)
    var fwd := -camera.global_basis.z
    out.sort_custom(func(a, b): return fwd.angle_to(a.global_position - camera.global_position) < fwd.angle_to(b.global_position - camera.global_position))
    return out


func _best_target(after: Mech) -> Mech:
    var list := candidates()
    if list.is_empty():
        return null
    if after != null and list.has(after):
        return list[(list.find(after) + 1) % list.size()]
    var fwd := -camera.global_basis.z
    for m in list:
        if fwd.angle_to(m.global_position - camera.global_position) < ACQUIRE_CONE:
            return m
    return list[0]


func _set_target(t: Mech) -> void:
    if t == target:
        return
    target = t
    lock = 0.0
    locked = false
    target_changed.emit(t)


func _line_of_sight(t: Mech) -> bool:
    var q := PhysicsRayQueryParameters3D.create(camera.global_position, aim_point_of(t), Mech.LAYER_WORLD)
    q.exclude = [mech.get_rid()]
    return camera.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
