class_name MechGait
extends Node
## Procedural walking for a mech's legs (heavy, reach-limited, planted feet).
##
## * Stride length is capped by what the legs can actually reach at the current crouch, so a
##   planted foot never gets dragged out of reach and knees never hyperextend. Speed comes from
##   cadence: slow heavy steps when walking, quicker but still weighty at full speed.
## * Feet plant in the world and keep their world position *and* heading during stance (no
##   sliding, no twisting on the ground). In swing the foot peels off heel-first, lifts early,
##   reaches forward and lands heel-first on a point predicted from the body's velocity.
## * Each leg is solved with 2-bone IK on the Blender joints (joint_hip_* -> joint_knee_* ->
##   joint_ankle_*); the piston sleeves/rods ride those joints, so they telescope.
## * The body crouches with speed, takes a weight dip on every footfall (spring), bobs, sways
##   over the stance leg, leans into acceleration and turns, and staggers from hits.
## * Turning on the spot re-steps; after stopping, the feet square up under the hips.
## * Heavily damaged legs limp: uneven timing, shorter lift, more sway.
## * Airborne (thruster jump, falling): no stepping; the legs hang under the hips, knees slightly
##   bent and feet trailing the motion. On landing both feet plant together with a heavy dip.
## Emits footstep(side, world_pos, strength) on every footfall.

signal footstep(side: String, world_pos: Vector3, strength: float)

const DUTY_SLOW := 0.64        # fraction of the cycle each foot is planted when walking (long double support)
const DUTY_FAST := 0.5         # ...at full speed (brief double support, longer swing)
const LIFT := 0.42             # swing clearance at full stride (m)
const MAX_HALF_STRIDE := 1.05  # foot travels at most this far ahead of / behind the hip (m)
const REACH := 0.96            # never straighten the leg past this fraction of its length
const CYCLE_SLOW := 1.5        # seconds per two-step cycle when barely moving
const CYCLE_FAST := 0.8        # ...at full speed (if the reach cap allows)
const CROUCH_IDLE := 0.1
const CROUCH_MOVE := 0.38      # deeper crouch at speed = longer reach
const BOB := 0.1
const IMPACT := 0.09           # weight dip on each footfall (m)
const SWAY := 0.07
const ROLL := 0.04
const HIP_ROLL_MAX := 0.35     # how far a leg can swing out sideways (rad): limits strafe stride
const FOOT_YAW_MAX := 0.6      # how far a planted foot may stay twisted relative to the body (rad)
const SETTLE_DIST := 0.3       # re-step when a foot strays this far from home while moving / turning
const IDLE_DELAY := 0.35       # after this long standing still, square the stance up again
const IDLE_SETTLE := 0.04
const AIR_DELAY := 0.12        # off the floor this long = airborne (ignores tiny bumps)
const AIR_HANG := 0.35         # feet hang this far below their standing height (knees relax)

var mech: Mech
var pelvis: Node3D
var legs: Array = []
var phase := 0.0
var frozen := false
var _pelvis_rest: Transform3D
var _speed_f := 0.0
var _cycle := CYCLE_SLOW
var _duty := DUTY_SLOW
var _lean := 0.0
var _roll := 0.0
var _impact := 0.0
var _impact_vel := 0.0
var _kick := Vector2.ZERO
var _last_fwd := 0.0
var _idle_time := 0.0
var _grounded_once := false
var _air_time := 0.0
var airborne := false


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
            "yaw": mech.global_rotation.y, "from_yaw": mech.global_rotation.y,
            "swinging": false,
        })
    return true


## Pose once with feet square under the hips and stop (e.g. the workshop dock).
func freeze() -> void:
    frozen = true
    _apply_body(0.0)
    for leg in legs:
        leg["planted"] = mech.to_global(leg["home"])
        leg["yaw"] = mech.global_rotation.y
        _solve(leg, leg["planted"], 0.0, 0.0)


func kick(push_world: Vector3) -> void:
    var p := mech.global_basis.inverse() * push_world
    _kick += Vector2(clampf(p.z * 0.03, -0.12, 0.12), clampf(-p.x * 0.03, -0.12, 0.12))


func _physics_process(delta: float) -> void:
    if frozen or mech == null or mech.is_destroyed:
        return
    if not _grounded_once and mech.is_on_floor():
        _grounded_once = true          # spawned in the air: put both feet on the real ground
        for leg in legs:
            leg["planted"] = _ground(mech.to_global(leg["home"]), leg["ankle_h"])
            leg["yaw"] = mech.global_rotation.y
    if _update_airborne(delta):
        return
    var vel := mech.velocity
    vel.y = 0.0
    var speed := vel.length()
    _speed_f = move_toward(_speed_f, clampf(speed / 5.0, 0.0, 1.0), delta * 2.0)
    var turning := absf(mech.yaw_velocity) > 0.1
    _idle_time = _idle_time + delta if speed < 0.2 and not turning else 0.0

    # cadence: heavy and slow when walking, quicker at speed, but never a stride the legs can't reach
    var limp := _limp()
    var half := minf(MAX_HALF_STRIDE, _reach_half() * 0.92)
    if speed > 0.2:   # sideways steps are shorter than forward ones (hip roll limit)
        var lateral := absf(mech.global_basis.x.dot(vel / speed))
        half = lerpf(half, minf(half, _lateral_half()), lateral)
    _duty = lerpf(DUTY_SLOW, DUTY_FAST, _speed_f)
    var want := lerpf(CYCLE_SLOW, CYCLE_FAST, _speed_f)
    if speed > 0.05:
        want = minf(want, 2.0 * half / (speed * _duty))  # stance travel = speed * cycle * duty <= 2 * half
    # shorten instantly (never outrun the legs), lengthen smoothly
    _cycle = want if want < _cycle else lerpf(_cycle, want, minf(1.0, delta * 3.0))
    var stepping := speed > 0.2 or turning or _needs_step() or not _both_planted()
    if stepping:
        var rate := 1.0 / maxf(_cycle * (1.15 if speed < 0.2 else 1.0), 0.3)
        if _overreached(half):
            rate *= 2.0                                    # a planted foot is being dragged: step now
        phase = fposmod(phase + delta * rate, 1.0)

    _apply_body(delta)
    var travel := speed * _cycle * _duty                  # how far the body moves during one stance
    var ahead := vel.normalized() * travel * 0.5 if speed > 0.2 else Vector3.ZERO
    var body_yaw := mech.global_rotation.y
    for leg in legs:
        var offset: float = leg["offset"] if limp == 0.0 else (0.0 if leg["side"] == "L" else 0.5 - 0.12 * limp)
        var lp := fposmod(phase + offset, 1.0)
        var target := _ground(mech.to_global(leg["home"]) + ahead, leg["ankle_h"])
        var squared: bool = _idle_time > IDLE_DELAY and _home_offset(leg) < IDLE_SETTLE and not leg["swinging"]
        var foot: Vector3
        var pitch := 0.0
        var yaw_off := 0.0
        if lp >= _duty and not squared:
            if not leg["swinging"]:
                leg["swinging"] = true
                leg["from"] = leg["planted"]
                leg["from_yaw"] = leg["yaw"]
            var t := (lp - _duty) / (1.0 - _duty)
            var reach_t := smoothstep(0.08, 0.92, t)                 # pause at toe-off, ease in to the landing
            foot = (leg["from"] as Vector3).lerp(target, reach_t)
            var lift_curve := sin(PI * pow(t, 0.75))                  # lifts early, sets down gently
            foot.y += lift_curve * LIFT * (0.3 + 0.7 * _speed_f) * (1.0 - 0.5 * limp)
            pitch = lerpf(0.25, -0.25, t) * (0.4 + 0.6 * _speed_f)    # heel-off at start, toes up for heel-strike
            yaw_off = lerpf(_wrap(leg["from_yaw"] - body_yaw), 0.0, reach_t)
        else:
            if leg["swinging"]:
                leg["swinging"] = false
                leg["planted"] = target
                leg["yaw"] = body_yaw
                var strength := 0.4 + 0.6 * _speed_f
                _impact_vel -= IMPACT * 10.0 * strength
                footstep.emit(leg["side"], target, strength)
            foot = leg["planted"]
            yaw_off = clampf(_wrap(leg["yaw"] - body_yaw), -FOOT_YAW_MAX, FOOT_YAW_MAX)
            if absf(_wrap(leg["yaw"] - body_yaw)) > FOOT_YAW_MAX:
                leg["yaw"] = body_yaw + signf(_wrap(leg["yaw"] - body_yaw)) * FOOT_YAW_MAX
            var stance_t := lp / _duty
            if stance_t > 0.8 and stepping and not squared:
                pitch = (stance_t - 0.8) / 0.2 * 0.25 * (0.4 + 0.6 * _speed_f)   # heel lifts before toe-off
        _solve(leg, foot, pitch, yaw_off)


## Returns true while airborne (legs posed here, no stepping).
func _update_airborne(delta: float) -> bool:
    if mech.is_on_floor():
        _air_time = 0.0
        if airborne:
            _land()
        return false
    _air_time += delta
    if _air_time < AIR_DELAY or not _grounded_once:
        return false
    airborne = true
    _idle_time = 0.0
    _apply_body(delta)
    var drift := mech.velocity
    drift.y = 0.0
    var trail := mech.global_basis.inverse() * (-drift * 0.06)       # feet lag behind the motion
    trail = Vector3(clampf(trail.x, -0.3, 0.3), 0.0, clampf(trail.z, -0.4, 0.4))
    for leg in legs:
        leg["swinging"] = false
        var hang: Vector3 = leg["home"] + trail + Vector3(0, -AIR_HANG, 0.12)
        var foot := mech.to_global(hang)
        leg["planted"] = foot
        leg["yaw"] = mech.global_rotation.y
        _solve(leg, foot, -0.15, 0.0)
    return true


func _land() -> void:
    airborne = false
    var fall := clampf(-mech.velocity.y / 12.0, 0.4, 1.6)
    _impact_vel -= IMPACT * 14.0 * fall                               # heavy two-footed landing
    for leg in legs:
        leg["planted"] = _ground(mech.to_global(leg["home"]), leg["ankle_h"])
        leg["yaw"] = mech.global_rotation.y
        leg["swinging"] = false
        footstep.emit(leg["side"], leg["planted"], fall)
    phase = 0.0


func _apply_body(delta: float) -> void:
    var fwd_axis := mech.global_basis.z
    var fwd_speed := mech.velocity.dot(fwd_axis)
    var limp := _limp()
    if delta > 0.0:
        var accel := (fwd_speed - _last_fwd) / delta
        _lean = lerpf(_lean, clampf(accel * 0.015, -0.12, 0.12), delta * 4.0)
        _roll = lerpf(_roll, clampf(-mech.yaw_velocity * fwd_speed * 0.006, -0.08, 0.08), delta * 3.0)
        _kick = _kick.move_toward(Vector2.ZERO, delta * 0.5)
        # footfall weight dip: critically damped spring back to 0
        _impact_vel += (-_impact * 160.0 - _impact_vel * 2.0 * sqrt(160.0)) * delta
        _impact = clampf(_impact + _impact_vel * delta, -0.2, 0.05)
    _last_fwd = fwd_speed
    var crouch := lerpf(CROUCH_IDLE, CROUCH_MOVE, _speed_f)
    var bob := -(1.0 - absf(sin(TAU * phase))) * BOB * _speed_f
    var sway := cos(TAU * (phase - _duty * 0.5)) * (1.0 + 0.6 * limp)
    pelvis.transform = _pelvis_rest
    pelvis.position += Vector3(sway * SWAY * _speed_f, -crouch + bob + _impact, 0)
    pelvis.rotation = Vector3(_lean + _kick.x, 0, _roll + sway * ROLL * _speed_f + _kick.y)


## 2-bone IK in the leg's sagittal plane; knees bend forward; foot pitch/yaw applied at the ankle.
func _solve(leg: Dictionary, foot_world: Vector3, pitch: float, yaw_off: float) -> void:
    var hip: Node3D = leg["hip"]
    var knee: Node3D = leg["knee"]
    var ankle: Node3D = leg["ankle"]
    var l1: float = leg["l1"]
    var l2: float = leg["l2"]
    var local := pelvis.global_transform.affine_inverse() * foot_world - hip.position
    # hip roll swings the leg plane out sideways toward the foot; then solve in that plane
    var roll := clampf(atan2(local.x, -local.y), -HIP_ROLL_MAX, HIP_ROLL_MAX)
    var down := Vector2(local.x, local.y).length()
    var dist := clampf(Vector2(down, local.z).length(), (l1 + l2) * 0.35, (l1 + l2) * REACH)
    var phi := atan2(local.z, down)
    var a1 := acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
    var a2 := acos(clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0))
    var thigh := phi + a1
    var shin := thigh - (PI - a2)
    hip.basis = Basis(Vector3(0, 0, 1), roll) * Basis(Vector3(1, 0, 0), -(thigh - leg["thigh_rest"]))
    knee.rotation = Vector3(-((shin - thigh) - (leg["shin_rest"] - leg["thigh_rest"])), 0, 0)
    # foot stays flat on the ground in the mech's frame, with heel/toe pitch and planted yaw
    ankle.global_basis = mech.global_basis * Basis(Vector3.UP, yaw_off) * Basis(Vector3.RIGHT, pitch)


## Horizontal reach of the legs at the current crouch (how far a foot can be ahead/behind the hip).
func _reach_half() -> float:
    var leg: Dictionary = legs[0]
    var hip_h: float = (_pelvis_rest.origin.y - lerpf(CROUCH_IDLE, CROUCH_MOVE, _speed_f)) + leg["hip"].position.y - leg["ankle_h"]
    var L: float = (leg["l1"] + leg["l2"]) * REACH
    return sqrt(maxf(0.01, L * L - hip_h * hip_h))


func _overreached(half: float) -> bool:
    for leg in legs:
        if leg["swinging"]:
            continue
        var d: Vector3 = mech.to_local(leg["planted"]) - leg["home"]
        if absf(d.z) > half * 1.08 or absf(d.x) > _lateral_half() * 1.15:
            return true
    return false


func _lateral_half() -> float:
    var leg: Dictionary = legs[0]
    var hip_h: float = (_pelvis_rest.origin.y - lerpf(CROUCH_IDLE, CROUCH_MOVE, _speed_f)) + leg["hip"].position.y - leg["ankle_h"]
    return tan(HIP_ROLL_MAX) * hip_h * 0.9


func _limp() -> float:
    if mech == null or not mech.part_max_hp.has("legs"):
        return 0.0
    var f: float = mech.part_hp["legs"] / maxf(1.0, mech.part_max_hp["legs"])
    return clampf((0.35 - f) / 0.35, 0.0, 1.0)


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


## Moving / turning: re-step stray feet. Idle: keep stepping until both feet are back under the hips.
func _needs_step() -> bool:
    var limit := IDLE_SETTLE if _idle_time > IDLE_DELAY else SETTLE_DIST
    for leg in legs:
        if _home_offset(leg) > limit or absf(_wrap(leg["yaw"] - mech.global_rotation.y)) > FOOT_YAW_MAX * 0.8:
            return true
    return false


func _both_planted() -> bool:
    for leg in legs:
        if leg["swinging"]:
            return false
    return true


static func _wrap(a: float) -> float:
    return wrapf(a, -PI, PI)
