class_name PlayerController
extends Node
## First-person mech controls. Add as a child of a built Mech.
##   W/S throttle, A/D turn legs, mouse twists the torso and pitches the arms,
##   LMB right-arm weapon, RMB left-arm weapon, Space boost, C centre torso.
## The cockpit sells the 15 ft scale: a slow heavy stride bob, a thud on every
## footfall, a jolt on landing, and shake when hit.

const STEP_LENGTH := 2.6   # metres per footfall for a 4.6 m tall walker
const BOB_HEIGHT := 0.09
const SWAY_ROLL := 0.015

@export var mouse_sensitivity := 0.0025

var mech: Mech
var camera: Camera3D
var enabled := true  # false = movement/weapons locked (e.g. match intro); looking around still works
var _base_pos := Vector3.ZERO
var _step_phase := 0.0
var _last_step_sign := 1.0
var _shake := 0.0
var _air_time := 0.0


func _ready() -> void:
    mech = get_parent() as Mech
    camera = Camera3D.new()
    camera.fov = 80.0
    camera.near = 0.05
    camera.far = 2000.0
    var anchor: Node3D = mech.cockpit_anchor if mech.cockpit_anchor else mech
    anchor.add_child(camera)
    if anchor == mech:
        camera.position = Vector3(0, 3.6, 0)
    _base_pos = camera.position
    camera.current = true
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    mech.hit_taken.connect(_on_hit)


func _on_hit(_m: Mech, _slot: String, amount: float) -> void:
    add_shake(amount * 0.004)


func add_shake(amount: float) -> void:
    _shake = minf(_shake + amount, 0.35)


func _process(delta: float) -> void:
    var speed := Vector2(mech.velocity.x, mech.velocity.z).length()
    if mech.is_on_floor():
        if _air_time > 0.35:
            _shake = maxf(_shake, 0.3)  # landing jolt after a thruster jump
        _air_time = 0.0
        if speed > 0.3:
            _step_phase += speed / STEP_LENGTH * PI * delta
            var side := signf(sin(_step_phase))
            if side != _last_step_sign:
                _last_step_sign = side
                _shake = maxf(_shake, 0.07)  # footfall thud
        else:
            _step_phase = lerpf(_step_phase, round(_step_phase / PI) * PI, delta * 4.0)
    else:
        _air_time += delta
    _shake = move_toward(_shake, 0.0, delta * 0.6)
    var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.15
    var bob := -absf(sin(_step_phase)) * BOB_HEIGHT
    camera.position = _base_pos + Vector3(jitter.x, bob + jitter.y, 0)
    # Godot cameras look down -Z; mech models face +Z, hence the PI yaw.
    camera.rotation = Vector3(mech.aim_pitch + jitter.y * 0.3, PI, sin(_step_phase) * SWAY_ROLL + jitter.x * 0.3)


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
