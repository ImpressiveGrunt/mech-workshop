class_name AIController
extends Node
## Simple arena opponent: turns to face the target, keeps a fighting distance,
## twists its torso to aim, and fires when lined up. Add as a child of a Mech.

@export var preferred_distance := 28.0  # the 116 m arena leaves room to keep range
@export var spread := 0.035  # aim error per metre of distance

var mech: Mech
var target: Mech
var _strafe := 1.0
var _strafe_timer := 0.0


func _ready() -> void:
    mech = get_parent() as Mech


func _physics_process(delta: float) -> void:
    if mech.is_destroyed or target == null or not is_instance_valid(target) or target.is_destroyed:
        mech.throttle = 0.0
        mech.turn = 0.0
        return
    var to := target.global_position - mech.global_position
    to.y = 0.0
    var dist := to.length()
    var fwd := mech.global_basis.z
    fwd.y = 0.0
    var angle := fwd.signed_angle_to(to, Vector3.UP)
    mech.turn = clampf(angle * 2.0, -1.0, 1.0)
    _strafe_timer -= delta
    if _strafe_timer <= 0.0:
        _strafe = -_strafe
        _strafe_timer = randf_range(2.0, 4.0)
    if dist > preferred_distance + 8.0:
        mech.throttle = 1.0
    elif dist < preferred_distance - 8.0:
        mech.throttle = -0.6
    else:
        mech.throttle = 0.35 * _strafe
    mech.torso_twist = clampf(angle, -Mech.TWIST_LIMIT, Mech.TWIST_LIMIT)
    var aim := target.global_position + Vector3(0, 3.0, 0)
    mech.aim_pitch = clampf(atan2(aim.y - (mech.global_position.y + 3.6), dist), -Mech.PITCH_LIMIT, Mech.PITCH_LIMIT)
    if absf(angle - mech.torso_twist) > 0.15:
        return
    var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spread * dist
    for w in mech.weapons.values():
        if w.weapon_type == "melee" and dist > w.weapon_range + 3.0:
            continue
        if dist <= w.weapon_range:
            w.fire(aim + jitter)
