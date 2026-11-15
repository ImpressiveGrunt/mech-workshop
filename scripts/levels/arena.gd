extends Node3D
## Arena match: player vs one AI mech. Destroy the enemy torso to win.
## Damage you take is carried back to the workshop for repair.
## The Blender arena: night colosseum with crowd, floodlights, symmetric cover,
## destructible crates and explosive barrels.

const ENV_PATH := "res://assets/models/environments/arena.glb"
const WIN_REWARD := 400
const LOSS_REWARD := 75

var player: Mech
var enemy: Mech
var hud: Hud
var _over := false


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

    player = _spawn_mech(GameState.loadout, GameState.damage, spawn_a, GameState.paint)
    player.add_child(PlayerController.new())
    enemy = _spawn_mech(_enemy_loadout(), {}, spawn_b, GameState.PAINT_PRESETS.values().pick_random())
    var ai := AIController.new()
    ai.target = player
    enemy.add_child(ai)
    player.destroyed.connect(_on_mech_destroyed)
    enemy.destroyed.connect(_on_mech_destroyed)

    hud = Hud.new()
    add_child(hud)
    hud.mech = player
    hud.show_message("FIGHT!", 2.0)


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
