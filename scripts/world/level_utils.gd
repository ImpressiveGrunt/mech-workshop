class_name LevelUtils
extends Object
## Helpers shared by the level scripts: lighting, blockout geometry, and loading
## Blender-built environments (which tag collision + markers via glTF extras).


static func add_lighting(parent: Node, sky_top: Color, ground: Color, sun_energy: float = 1.2) -> void:
    var mat := ProceduralSkyMaterial.new()
    mat.sky_top_color = sky_top
    mat.sky_horizon_color = sky_top.lerp(Color.WHITE, 0.4)
    mat.ground_bottom_color = ground
    mat.ground_horizon_color = ground.lerp(Color.WHITE, 0.3)
    var sky := Sky.new()
    sky.sky_material = mat
    var env := Environment.new()
    env.background_mode = Environment.BG_SKY
    env.sky = sky
    env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
    env.ssao_enabled = true
    env.glow_enabled = true
    var world := WorldEnvironment.new()
    world.environment = env
    parent.add_child(world)
    var sun := DirectionalLight3D.new()
    sun.light_energy = sun_energy
    sun.shadow_enabled = true
    sun.rotation_degrees = Vector3(-50, 35, 0)
    parent.add_child(sun)


static func add_box(parent: Node, size: Vector3, pos: Vector3, color: Color, rot_y: float = 0.0,
        solid: bool = true) -> Node3D:
    var mesh := BoxMesh.new()
    mesh.size = size
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.85
    mesh.material = m
    var mi := MeshInstance3D.new()
    mi.mesh = mesh
    var root: Node3D = mi
    if solid:
        var body := StaticBody3D.new()
        body.collision_layer = Mech.LAYER_WORLD
        body.collision_mask = 0
        var shape := CollisionShape3D.new()
        var box := BoxShape3D.new()
        box.size = size
        shape.shape = box
        body.add_child(shape)
        body.add_child(mi)
        root = body
    root.position = pos
    root.rotation.y = rot_y
    parent.add_child(root)
    return root


static func add_marker(parent: Node, marker_name: String, pos: Vector3, rot_y: float = 0.0) -> Node3D:
    var n := Node3D.new()
    n.name = marker_name
    n.position = pos
    n.rotation.y = rot_y
    parent.add_child(n)
    return n


static var _extras_cache: Dictionary = {}


## Blender writes <scene>.glb.extras.json next to every export ({object name: custom properties})
## because Godot 4.3's glTF importer drops node extras. Re-attach them as meta "extras".
static func apply_extras(root: Node, scene_path: String) -> void:
    if not _extras_cache.has(scene_path):
        var table := {}
        var text := FileAccess.get_file_as_string(scene_path + ".extras.json")
        var data = JSON.parse_string(text) if text != "" else null
        if data is Dictionary:
            for key in data:
                table[String(key).validate_node_name()] = data[key]
        _extras_cache[scene_path] = table
    var extras: Dictionary = _extras_cache[scene_path]
    if extras.is_empty():
        return
    for n in [root] + Mech._descendants(root):
        var key := String(n.name)
        if extras.has(key) and not n.has_meta("extras"):
            n.set_meta("extras", extras[key])


static func instance_scene(path: String) -> Node:
    var packed: PackedScene = load(path)
    var node := packed.instantiate()
    apply_extras(node, path)
    return node


static func instance_environment(path: String, parent: Node) -> Node3D:
    var root := instance_scene(path) as Node3D
    parent.add_child(root)
    for n in Mech._descendants(root):
        if n is Light3D:
            tune_light(n as Light3D)
            continue
        if not (n is MeshInstance3D):
            continue
        var mi := n as MeshInstance3D
        var extras := extras_of(mi)
        if String(mi.name).contains("_collider"):
            mi.visible = false  # physics proxy (e.g. wrecks built from mech parts)
        if extras.get("destructible", false):
            Destructible.wrap(mi, extras)
            continue
        match str(extras.get("collision", "")):
            "mesh":
                mi.create_trimesh_collision()
            "convex":
                mi.create_convex_collision()
            "box":
                var aabb := mi.get_aabb()
                var body := StaticBody3D.new()
                var shape := CollisionShape3D.new()
                var box := BoxShape3D.new()
                box.size = aabb.size
                shape.shape = box
                shape.position = aabb.get_center()
                body.add_child(shape)
                mi.add_child(body)
    return root


static func extras_of(n: Node) -> Dictionary:
    var e = n.get_meta("extras", {})
    return e if e is Dictionary else {}


## Blender lights carry engine-friendly values in extras {godot_energy, godot_range}.
static func tune_light(light: Light3D) -> void:
    var e := extras_of(light)
    light.light_energy = float(e.get("godot_energy", 1.0))
    if light is OmniLight3D:
        (light as OmniLight3D).omni_range = float(e.get("godot_range", 10.0))
    elif light is SpotLight3D:
        (light as SpotLight3D).spot_range = float(e.get("godot_range", 25.0))
        light.shadow_enabled = true


static func find_marker(root: Node, marker_name: String) -> Node3D:
    return root.find_child(marker_name, true, false) as Node3D


static func find_markers(root: Node, prefix: String) -> Array:
    var out := []
    for n in Mech._descendants(root):
        if n is Node3D and String(n.name).begins_with(prefix):
            out.append(n)
    return out
