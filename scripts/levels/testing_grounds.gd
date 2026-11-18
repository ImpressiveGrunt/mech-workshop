extends Node3D
## Testing grounds: try parts and weapons with nothing at stake.
## Five stationary target dummies at 25-150 m and one dummy patrolling a lane at 60 m;
## destroyed dummies respawn. Mobility course (ramps, 2/4/6 m jump blocks, slalom),
## breakable crates and explosive barrels. R resets everything (repairs you, refills ammo,
## respawns dummies and props). Damage here is not carried back to the workshop.
## Stand on the EXIT pad and press E to return.

const ENV_PATH := "res://assets/models/environments/testing_grounds.glb"
const RESPAWN_TIME := 4.0
const MOVER_SPEED := 0.55

var root: Node3D
var player: Mech
var player_ctrl: PlayerController
var hud: Hud
var dummies: Array = []       # [{marker, mech, moving}]
var mover_points: Array = []
var _mover_target := 0
var exit_point: Node3D
var kills := 0


func _ready() -> void:
    LevelUtils.add_lighting(self, Color(0.42, 0.6, 0.85), Color(0.35, 0.37, 0.3), 1.3)
    if ResourceLoader.exists(ENV_PATH):
        root = LevelUtils.instance_environment(ENV_PATH, self)
    else:
        root = _build_blockout()
    exit_point = LevelUtils.find_marker(root, "exit_to_workshop")
    var spawn := LevelUtils.find_marker(root, "mech_spawn")
    player = Mech.new()
    add_child(player)
    player.global_transform = spawn.global_transform
    player.position.y += 0.3
    player.build(GameState.loadout, {}, GameState.paint)   # always arrive fully repaired
    player_ctrl = PlayerController.new()
    player.add_child(player_ctrl)
    for m in LevelUtils.find_markers(root, "dummy_"):
        if String(m.name).trim_prefix("dummy_").is_valid_int():   # dummy_1..5, not pads/rings/labels
            dummies.append({"marker": m, "mech": null, "moving": false})
    var a := LevelUtils.find_marker(root, "mover_a")
    var b := LevelUtils.find_marker(root, "mover_b")
    if a and b:
        mover_points = [a.global_position, b.global_position]
        dummies.append({"marker": a, "mech": null, "moving": true})
    for d in dummies:
        _spawn_dummy(d)
    hud = Hud.new()
    add_child(hud)
    hud.mech = player
    hud.show_message("TEST GROUNDS: [R] reset   [E] on EXIT pad to leave", 5.0)


func _spawn_dummy(d: Dictionary) -> void:
    var m := Mech.new()
    add_child(m)
    var marker: Node3D = d["marker"]
    m.global_transform = marker.global_transform
    if d["moving"]:
        m.rotation.y = -PI / 2     # walk along the lane
    m.position.y += 0.3
    m.build(GameState.STARTING_LOADOUT, {}, GameState.PAINT_PRESETS["Hornet"] if d["moving"] else GameState.PAINT_PRESETS["Ghost"])
    m.set_meta("dummy", true)
    m.destroyed.connect(_on_dummy_destroyed.bind(d))
    d["mech"] = m


func _on_dummy_destroyed(_m: Mech, d: Dictionary) -> void:
    kills += 1
    hud.show_message("DUMMY DOWN  (%d)" % kills, 1.5)
    await get_tree().create_timer(RESPAWN_TIME).timeout
    _replace_dummy(d)


func _replace_dummy(d: Dictionary) -> void:
    var old: Mech = d["mech"]
    if is_instance_valid(old):
        old.queue_free()
    _spawn_dummy(d)


func _physics_process(_delta: float) -> void:
    _drive_mover()
    if player == null:
        return
    var near_exit := exit_point != null and player.global_position.distance_to(exit_point.global_position) < 4.0
    hud.set_prompt("[E] Return to the workshop" if near_exit else "")
    if near_exit and Input.is_action_just_pressed("interact"):
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        GameState.go_to("workshop")
    if Input.is_action_just_pressed("reset_range"):
        reset_range()


## The patrol dummy walks back and forth between mover_a and mover_b.
func _drive_mover() -> void:
    if mover_points.is_empty():
        return
    for d in dummies:
        if not d["moving"]:
            continue
        var m: Mech = d["mech"]
        if m == null or not is_instance_valid(m) or m.is_destroyed:
            continue
        var target: Vector3 = mover_points[_mover_target]
        var to := target - m.global_position
        to.y = 0.0
        if to.length() < 2.0:
            _mover_target = 1 - _mover_target
            continue
        var fwd := m.global_basis.z
        fwd.y = 0.0
        m.turn = clampf(fwd.signed_angle_to(to, Vector3.UP) * 2.0, -1.0, 1.0)
        m.throttle = MOVER_SPEED


## Repair the player, refill ammo, respawn every dummy and the breakable props.
func reset_range() -> void:
    var t := player.global_transform
    player.queue_free()
    player = Mech.new()
    add_child(player)
    player.global_transform = t
    player.build(GameState.loadout, {}, GameState.paint)
    player_ctrl = PlayerController.new()
    player.add_child(player_ctrl)
    hud.mech = player
    for d in dummies:
        _replace_dummy(d)
    var env_name := root.name
    var xf := root.transform
    root.queue_free()
    root = LevelUtils.instance_environment(ENV_PATH, self) if ResourceLoader.exists(ENV_PATH) else _build_blockout()
    root.name = env_name
    root.transform = xf
    exit_point = LevelUtils.find_marker(root, "exit_to_workshop")
    for d in dummies:
        var fresh := LevelUtils.find_marker(root, String(d["marker"].name))
        if fresh:
            d["marker"] = fresh
    hud.show_message("RANGE RESET", 1.5)


func _build_blockout() -> Node3D:
    var r := Node3D.new()
    r.name = "TestingBlockout"
    add_child(r)
    LevelUtils.add_box(r, Vector3(160, 1, 220), Vector3(0, -0.5, 0), Color(0.6, 0.59, 0.55))
    LevelUtils.add_marker(r, "mech_spawn", Vector3(0, 0, -80), 0.0)
    LevelUtils.add_marker(r, "exit_to_workshop", Vector3(-14, 0, -82))
    var i := 1
    for p in [Vector2(-24, 25), Vector2(-12, 50), Vector2(0, 75), Vector2(12, 100), Vector2(24, 150)]:
        LevelUtils.add_marker(r, "dummy_%d" % i, Vector3(-p.x, 0, -80 + p.y), PI)
        i += 1
    LevelUtils.add_marker(r, "mover_a", Vector3(26, 0, -20))
    LevelUtils.add_marker(r, "mover_b", Vector3(-26, 0, -20))
    return r
