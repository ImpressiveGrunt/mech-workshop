extends Node3D
## Arena match: player vs one AI mech. Destroy the enemy torso to win.
## Damage you take is carried back to the workshop for repair.
## The Blender arena: night colosseum with crowd, floodlights, symmetric cover,
## destructible crates and explosive barrels.

const ENV_PATH := "res://assets/models/environments/arena.glb"
const WIN_REWARD := 400
const LOSS_REWARD := 75
const GATE_TIME := 2.2         # seconds for the blast doors to slide
const WALK_TIMEOUT := 14.0     # safety net for the walk-out

## Match intro: both mechs start inside their gate tunnels, the blast doors
## slide open, the mechs walk out to their spawn marks (you watch from your own
## cockpit and can look around), the gates slam shut behind them, 3-2-1, FIGHT.

var player: Mech
var enemy: Mech
var hud: Hud
var player_ctrl: PlayerController
var enemy_ai: AIController
var _over := false
var _doors: Array = []          # [{node, closed, open}]


func _ready() -> void:
    var root: Node3D
    if ResourceLoader.exists(ENV_PATH):
        # Night bout under floodlights (the Blender arena brings its own lights).
        LevelUtils.add_lighting(self, Color(0.05, 0.08, 0.15), Color(0.04, 0.04, 0.05), 0.25)
        root = LevelUtils.instance_environment(ENV_PATH, self)
    else:
        LevelUtils.add_lighting(self, Color(0.3, 0.42, 0.65), Color(0.25, 0.23, 0.2), 1.2)
        root = _build_blockout()
    var spawn_a := LevelUtils.find_marker(root, "spawn_A")
    var spawn_b := LevelUtils.find_marker(root, "spawn_B")
    var start_a := LevelUtils.find_marker(root, "gate_A_start")
    var start_b := LevelUtils.find_marker(root, "gate_B_start")
    _collect_doors(root)
    var intro := start_a != null and start_b != null and not _doors.is_empty()

    player = _spawn_mech(GameState.loadout, GameState.damage, start_a if intro else spawn_a, GameState.paint)
    player_ctrl = PlayerController.new()
    player.add_child(player_ctrl)
    enemy = _spawn_mech(_enemy_loadout(), {}, start_b if intro else spawn_b, GameState.PAINT_PRESETS.values().pick_random())
    enemy_ai = AIController.new()
    enemy_ai.target = player
    enemy.add_child(enemy_ai)
    player.destroyed.connect(_on_mech_destroyed)
    enemy.destroyed.connect(_on_mech_destroyed)

    hud = Hud.new()
    add_child(hud)
    hud.mech = player
    if intro:
        _run_intro({player: spawn_a.global_position, enemy: spawn_b.global_position})
    else:
        _start_fight()


# ------------------------------------------------------------- match intro
func _run_intro(walk_to: Dictionary) -> void:
    player_ctrl.enabled = false
    enemy_ai.enabled = false
    hud.show_message("GATES OPENING", GATE_TIME + 0.5)
    player_ctrl.add_shake(0.12)
    await _move_gates(true)

    hud.show_message("ENTER THE ARENA", 3.0)
    var t := 0.0
    var walking := true
    while walking and t < WALK_TIMEOUT:
        await get_tree().physics_frame
        t += get_physics_process_delta_time()
        walking = false
        for m in walk_to:
            if is_instance_valid(m) and _walk_toward(m, walk_to[m]):
                walking = true
    for m in walk_to:
        if is_instance_valid(m):
            m.throttle = 0.0
            m.turn = 0.0

    hud.show_message("GATES SEALED", GATE_TIME)
    await _move_gates(false)
    player_ctrl.add_shake(0.3)  # the doors slam shut behind you
    for n in ["3", "2", "1"]:
        hud.show_message(n, 0.9)
        await get_tree().create_timer(0.8).timeout
    _start_fight()


func _start_fight() -> void:
    player_ctrl.enabled = true
    enemy_ai.enabled = true
    hud.show_message("FIGHT!", 2.0)


## Autopilot step: steer and throttle towards a point; false once arrived.
func _walk_toward(m: Mech, target: Vector3) -> bool:
    var to := target - m.global_position
    to.y = 0.0
    if to.length() < 1.2:
        m.throttle = 0.0
        m.turn = 0.0
        return false
    var fwd := m.global_basis.z
    fwd.y = 0.0
    m.turn = clampf(fwd.signed_angle_to(to, Vector3.UP) * 2.0, -1.0, 1.0)
    m.throttle = clampf(to.length() / 4.0, 0.3, 1.0)
    return true


## Blender tags each blast door with extras {gate, side, slide}; doors slide along local X.
func _collect_doors(root: Node) -> void:
    for n in Mech._descendants(root):
        var e := LevelUtils.extras_of(n)
        if e.has("gate") and n is Node3D:
            var closed: Transform3D = n.transform
            var offset := Vector3(float(e.get("side", 1)) * float(e.get("slide", 5.9)), 0, 0)
            _doors.append({"node": n, "closed": closed, "open": closed.translated_local(offset)})


func _move_gates(open: bool) -> void:
    if _doors.is_empty():
        return
    var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    for d in _doors:
        tw.tween_property(d["node"], "transform", d["open"] if open else d["closed"], GATE_TIME)
    await tw.finished


func _spawn_mech(loadout: Dictionary, damage: Dictionary, marker: Node3D, paint: Dictionary) -> Mech:
    var m := Mech.new()
    add_child(m)
    m.global_transform = marker.global_transform
    m.position.y += 0.3
    m.build(loadout, damage, paint)
    return m


func _enemy_loadout() -> Dictionary:
    var l: Dictionary = GameState.STARTING_LOADOUT.duplicate()
    for slot in ["weapon_L", "weapon_R"]:
        var options := []
        for id in PartDB.sorted_ids():
            if PartDB.fits(id, slot):
                options.append(id)
        if not options.is_empty():
            l[slot] = options.pick_random()
    return l


func _on_mech_destroyed(m: Mech) -> void:
    if _over:
        return
    _over = true
    var won := m == enemy
    var reward := WIN_REWARD if won else LOSS_REWARD
    GameState.finish_match(won, player.damage_report(), reward)
    if won:
        var scrap := randi_range(40, 90)
        GameState.add_scrap(scrap)
        hud.show_message("VICTORY   +$%d   +%d kg scrap" % [reward, scrap], 5.0)
    else:
        hud.show_message("DESTROYED   +$%d" % reward, 5.0)
    await get_tree().create_timer(5.0).timeout
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    GameState.go_to("workshop")


func _build_blockout() -> Node3D:
    var root := Node3D.new()
    root.name = "ArenaBlockout"
    add_child(root)
    LevelUtils.add_box(root, Vector3(110, 1, 110), Vector3(0, -0.5, 0), Color(0.5, 0.49, 0.46))
    var segments := 36
    for i in segments:
        var a := TAU * i / segments
        var color := Color(0.25, 0.27, 0.3) if i % 2 == 0 else Color(0.91, 0.47, 0.18)
        LevelUtils.add_box(root, Vector3(7.6, 7, 1.2), Vector3(sin(a) * 42.0, 3.5, cos(a) * 42.0), color, a)
    for p in [Vector3(14, 0, 14), Vector3(-14, 0, -14), Vector3(-14, 0, 14), Vector3(14, 0, -14)]:
        LevelUtils.add_box(root, Vector3(3, 8, 3), p + Vector3(0, 4, 0), Color(0.42, 0.42, 0.4))
    for p in [Vector3(8, 0, -6), Vector3(-8, 0, 6), Vector3(-20, 0, -4), Vector3(20, 0, 4)]:
        LevelUtils.add_box(root, Vector3(5, 1.6, 1), p + Vector3(0, 0.8, 0), Color(0.62, 0.6, 0.55), 0.4)
    LevelUtils.add_marker(root, "spawn_A", Vector3(0, 0, -32), 0.0)  # faces +Z
    LevelUtils.add_marker(root, "spawn_B", Vector3(0, 0, 32), PI)
    return root
