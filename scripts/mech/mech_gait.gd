class_name MechGait
extends Node
## Procedural walking for a mech's legs.
##
## * Feet plant in the world and stay put during stance (no foot sliding);
##   in swing they arc to a landing point predicted from the body's velocity.
## * Each leg is solved with 2-bone IK on the Blender joints
##   (joint_hip_* -> joint_knee_* -> joint_ankle_*); feet stay flat, toes lift
##   in swing. The piston sleeves/rods ride those joints, so they telescope.
## * The body (pelvis, which carries the torso and cockpit) crouches, bobs
##   (lowest at each footfall), sways over the stance leg, leans into
##   acceleration and turns, and recoils from hits.
## * Turning or drifting in place triggers small re-steps; idle feet settle.
## Emits footstep(side, world_pos, strength) on every footfall.

signal footstep(side: String, world_pos: Vector3, strength: float)

const DUTY := 0.6            # fraction of the cycle a foot is planted
const LIFT := 0.38           # swing foot clearance (m)
const CROUCH_IDLE := 0.12
const CROUCH_MOVE := 0.24
const BOB := 0.16
const SWAY := 0.05
const ROLL := 0.035
const SETTLE_DIST := 0.28    # re-step when a foot is this far from home while moving
const IDLE_DELAY := 0.35     # after this long standing still, square the stance up again
const IDLE_SETTLE := 0.04    # ...stepping any foot further than this back under its hip, facing forward

var mech: Mech
var pelvis: Node3D
var legs: Array = []
var phase := 0.0
var frozen := false
var _pelvis_rest: Transform3D
var _speed_f := 0.0
var _lean := 0.0
var _roll := 0.0
var _kick := Vector2.ZERO
var _last_fwd := 0.0
var _idle_time := 0.0


func setup(owner_mech: Mech, legs_root: Node3D) -> bool:
    mech = owner_mech
    pelvis = legs_root.find_child("pelvis", true, false) as Node3D
    if pelvis == null:
        return false
    _pelvis_rest = pelvis.transform
    for side in ["L", "R"]:
        var hip := pelvis.find_child("joint_hip_" + side, true, false) as Node3D
        var knee := pelvis.find_child("joint_knee_" + side, true, false) as Node3D
        var ankle := pelvis.find_child("joint_ankle_" + side, true, false) as Node3D
        if hip == null or knee == null or ankle == null:
            return false
        var home_local := mech.to_local(ankle.global_position)
        legs.append({
            "side": side, "hip": hip, "knee": knee, "ankle": ankle,
            "l1": knee.position.length(), "l2": ankle.position.length(),
            "thigh_rest": atan2(knee.position.z, -knee.position.y),
            "shin_rest": atan2(ankle.position.z, -ankle.position.y),
            "offset": 0.0 if side == "L" else 0.5,
            "home": home_local, "ankle_h": home_local.y,
            "planted": ankle.global_position, "from": ankle.global_position,
            "swinging": false, "t": 0.0,
        })
    return true


## Pose once with feet at home and stop (e.g. the workshop dock).
func freeze() -> void:
    frozen = true
    _apply_body(0.0)
    for leg in legs:
        leg["planted"] = mech.to_global(leg["home"])
        _solve(leg, leg["planted"], 0.0)


func kick(push_world: Vector3) -> void:
    var p := mech.global_basis.inverse() * push_world
    _kick += Vector2(clampf(p.z * 0.03, -0.12, 0.12), clampf(-p.x * 0.03, -0.12, 0.12))


func _physics_process(delta: float) -> void:
    if frozen or mech == null or mech.is_destroyed:
        return
    var vel := mech.velocity
    vel.y = 0.0
    var speed := vel.length()
    _speed_f = move_toward(_speed_f, clampf(speed / 6.0, 0.0, 1.0), delta * 2.5)
    var cycle := clampf(1.6 + speed * 0.36, 1.6, 4.0)   # metres travelled per full two-step cycle
    _idle_time = _idle_time + delta if speed < 0.2 and absf(mech.yaw_velocity) < 0.1 else 0.0

    # advance the gait: walking, turning on the spot, or settling stray feet
    var drive := maxf(speed, absf(mech.yaw_velocity) * 1.8)
    var need_step := _needs_step()
    if drive > 0.25 or need_step or not _both_planted():
        phase = fposmod(phase + maxf(drive, 1.2) * delta / cycle, 1.0)

    _apply_body(delta)
    var ahead := vel.normalized() * cycle * DUTY * 0.5 if speed > 0.2 else Vector3.ZERO
    for leg in legs:
        var lp := fposmod(phase + leg["offset"], 1.0)
        var target := _ground(mech.to_global(leg["home"]) + ahead, leg["ankle_h"])
        var foot: Vector3
        var toe := 0.0
        var squared: bool = _idle_time > IDLE_DELAY and _home_offset(leg) < IDLE_SETTLE and not leg["swinging"]
        if lp >= DUTY and not squared:
            if not leg["swinging"]:
                leg["swinging"] = true
                leg["from"] = leg["planted"]
            var t := (lp - DUTY) / (1.0 - DUTY)
            foot = (leg["from"] as Vector3).lerp(target, smoothstep(0.0, 1.0, t))
            foot.y += sin(PI * t) * LIFT * (0.35 + 0.65 * _speed_f)
            toe = -0.3 * sin(PI * t)
        else:
            if leg["swinging"]:
                leg["swinging"] = false
                leg["planted"] = target
                footstep.emit(leg["side"], target, 0.4 + 0.6 * _speed_f)
            foot = leg["planted"]
        _solve(leg, foot, toe)


func _apply_body(delta: float) -> void:
    var fwd_axis := mech.global_basis.z
    var fwd_speed := mech.velocity.dot(fwd_axis)
    if delta > 0.0:
        var accel := (fwd_speed - _last_fwd) / delta
        _lean = lerpf(_lean, clampf(accel * 0.015, -0.12, 0.12), delta * 4.0)
        _roll = lerpf(_roll, clampf(-mech.yaw_velocity * fwd_speed * 0.006, -0.08, 0.08), delta * 3.0)
        _kick = _kick.move_toward(Vector2.ZERO, delta * 0.5)
    _last_fwd = fwd_speed
    var crouch := lerpf(CROUCH_IDLE, CROUCH_MOVE, _speed_f)
    var bob := -(1.0 - absf(sin(TAU * phase))) * BOB * _speed_f       # lowest as each foot lands
    var sway := cos(TAU * (phase - DUTY * 0.5))                        # +1 over the left stance leg
    pelvis.transform = _pelvis_rest
    pelvis.position += Vector3(sway * SWAY * _speed_f, -crouch + bob, 0)
    pelvis.rotation = Vector3(_lean + _kick.x, 0, _roll + sway * ROLL * _speed_f + _kick.y)


## 2-bone IK in the leg's sagittal plane; knees bend forward, foot kept flat.
func _solve(leg: Dictionary, foot_world: Vector3, toe: float) -> void:
    var hip: Node3D = leg["hip"]
    var knee: Node3D = leg["knee"]
    var ankle: Node3D = leg["ankle"]
    var l1: float = leg["l1"]
    var l2: float = leg["l2"]
    var local := pelvis.global_transform.affine_inverse() * foot_world - hip.position
    var dist := clampf(Vector2(local.y, local.z).length(), (l1 + l2) * 0.35, (l1 + l2) * 0.999)
    var phi := atan2(local.z, -local.y)
    var a1 := acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
    var a2 := acos(clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0))
    var thigh := phi + a1
    var shin := thigh - (PI - a2)
    hip.rotation.x = -(thigh - leg["thigh_rest"])
    knee.rotation.x = -((shin - thigh) - (leg["shin_rest"] - leg["thigh_rest"]))
    ankle.rotation.x = -(pelvis.rotation.x + hip.rotation.x + knee.rotation.x) + toe


func _ground(p: Vector3, ankle_h: float) -> Vector3:
    var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 2.5, p + Vector3.DOWN * 3.0, Mech.LAYER_WORLD)
    q.exclude = [mech.get_rid()]
    var hit := mech.get_world_3d().direct_space_state.intersect_ray(q)
    if hit.is_empty():
        return Vector3(p.x, mech.global_position.y + ankle_h, p.z)
    return hit["position"] + Vector3.UP * ankle_h


func _home_offset(leg: Dictionary) -> float:
    var d: Vector3 = leg["planted"] - mech.to_global(leg["home"])
    d.y = 0.0
    return d.length()


## Moving: re-step only stray feet. Idle: keep stepping until both feet are back under the hips.
func _needs_step() -> bool:
    var limit := IDLE_SETTLE if _idle_time > IDLE_DELAY else SETTLE_DIST
    for leg in legs:
        if _home_offset(leg) > limit:
            return true
    return false


func _both_planted() -> bool:
    for leg in legs:
        if leg["swinging"]:
            return false
    return true
