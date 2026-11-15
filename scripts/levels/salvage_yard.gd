extends Node3D
## Salvage yard: drive around, search glowing scrap piles for scrap + parts,
## sell scrap at the scale, then head back to the workshop.

const ENV_PATH := "res://assets/models/environments/salvage_yard.glb"
const INTERACT_RANGE := 6.0
const PART_CHANCE := 0.25

var player: Mech
var hud: Hud
var spots: Array = []
var sell_point: Node3D
var exit_point: Node3D
var _busy := false


func _ready() -> void:
    LevelUtils.add_lighting(self, Color(0.62, 0.55, 0.47), Color(0.36, 0.29, 0.21), 1.3)
    var root: Node3D
    if ResourceLoader.exists(ENV_PATH):
        root = LevelUtils.instance_environment(ENV_PATH, self)
    else:
        root = _build_blockout()
    for n in LevelUtils.find_markers(root, "salvage_spot"):
        spots.append(n)
        _add_beacon(n)
    sell_point = LevelUtils.find_marker(root, "sell_point")
    exit_point = LevelUtils.find_marker(root, "exit_to_workshop")
    var spawn := LevelUtils.find_marker(root, "mech_spawn")

    player = Mech.new()
    add_child(player)
    player.global_transform = spawn.global_transform
    player.position.y += 0.3
    player.build(GameState.loadout, GameState.damage, GameState.paint)
    player.add_child(PlayerController.new())
    hud = Hud.new()
    add_child(hud)
    hud.mech = player
    hud.show_message("SALVAGE YARD: search the glowing piles", 4.0)


func _physics_process(_delta: float) -> void:
    if _busy or player == null:
        return
    var it := _nearest_interactable()
    hud.set_prompt(str(it.get("prompt", "")))
    if not it.is_empty() and Input.is_action_just_pressed("interact"):
        _interact(it)


func _nearest_interactable() -> Dictionary:
    var best := {}
    var best_d := INTERACT_RANGE
    var pos := player.global_position
    for s in spots:
        var d: float = pos.distance_to(s.global_position)
        if d < best_d:
            best_d = d
            best = {"kind": "search", "node": s, "prompt": "[E] Search for salvage"}
    if sell_point and pos.distance_to(sell_point.global_position) < best_d:
        best_d = pos.distance_to(sell_point.global_position)
        var value := GameState.scrap_kg * GameState.SCRAP_PRICE_PER_KG
        best = {"kind": "sell", "prompt": "[E] Sell %d kg scrap for $%d" % [GameState.scrap_kg, value]}
    if exit_point and pos.distance_to(exit_point.global_position) < best_d:
        best = {"kind": "exit", "prompt": "[E] Return to the workshop"}
    return best


func _interact(it: Dictionary) -> void:
    match it["kind"]:
        "search":
            _busy = true
            hud.set_prompt("Searching...")
            await get_tree().create_timer(1.5).timeout
            var spot: Node3D = it["node"]
            spots.erase(spot)
            spot.queue_free()
            hud.show_message(_roll_loot(), 4.0)
            _busy = false
        "sell":
            if GameState.scrap_kg == 0:
                hud.show_message("Nothing to sell", 2.0)
            else:
                hud.show_message("Sold scrap for $%d" % GameState.sell_scrap(), 3.0)
        "exit":
            Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
            GameState.go_to("workshop")


func _roll_loot() -> String:
    var kg := randi_range(15, 60)
    GameState.add_scrap(kg)
    var msg := "+%d kg scrap" % kg
    if randf() < PART_CHANCE and not PartDB.parts.is_empty():
        var id: String = PartDB.sorted_ids().pick_random()
        GameState.add_part(id)
        msg += "   FOUND PART: %s" % PartDB.display_name(id)
    return msg


func _add_beacon(marker: Node3D) -> void:
    var mesh := CylinderMesh.new()
    mesh.top_radius = 0.6
    mesh.bottom_radius = 0.6
    mesh.height = 8.0
    var m := StandardMaterial3D.new()
    m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    m.albedo_color = Color(0.5, 1.0, 0.6, 0.25)
    mesh.material = m
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    mi.position = Vector3(0, 4, 0)
    marker.add_child(mi)


func _build_blockout() -> Node3D:
    var root := Node3D.new()
    root.name = "SalvageBlockout"
    add_child(root)
    LevelUtils.add_box(root, Vector3(180, 1, 180), Vector3(0, -0.5, 0), Color(0.47, 0.38, 0.28))
    var rng := RandomNumberGenerator.new()
    rng.seed = 42
    var rust := [Color(0.54, 0.29, 0.16), Color(0.42, 0.43, 0.45), Color(0.65, 0.37, 0.18), Color(0.3, 0.32, 0.34)]
    for i in 10:
        var a := TAU * i / 10.0 + rng.randf_range(-0.2, 0.2)
        var center := Vector3(sin(a), 0, cos(a)) * rng.randf_range(20, 45)
        for j in 14:
            var off := Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))
            var size := Vector3(rng.randf_range(1, 3), rng.randf_range(0.5, 2.5), rng.randf_range(1, 3))
            var h := (1.0 - off.length() / 6.0) * 3.0
            LevelUtils.add_box(root, size, center + off + Vector3(0, maxf(size.y / 2, h), 0),
                rust[rng.randi() % rust.size()], rng.randf() * TAU)
        LevelUtils.add_marker(root, "salvage_spot_%02d" % i, center + center.normalized() * -7.0)
    LevelUtils.add_box(root, Vector3(7, 0.15, 4), Vector3(12, 0.07, -60), Color(0.95, 0.76, 0.19), 0.0, false)
    LevelUtils.add_box(root, Vector3(5, 3.5, 4), Vector3(12, 1.75, -65), Color(0.36, 0.5, 0.55))
    LevelUtils.add_marker(root, "sell_point", Vector3(12, 0, -60))
    LevelUtils.add_box(root, Vector3(0.6, 6, 0.6), Vector3(-6, 3, -78), Color(0.3, 0.3, 0.3))
    LevelUtils.add_box(root, Vector3(0.6, 6, 0.6), Vector3(6, 3, -78), Color(0.3, 0.3, 0.3))
    LevelUtils.add_marker(root, "exit_to_workshop", Vector3(0, 0, -76))
    LevelUtils.add_marker(root, "mech_spawn", Vector3(0, 0, -68), 0.0)
    return root
