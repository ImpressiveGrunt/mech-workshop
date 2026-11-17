extends Node
## Captures in-engine screenshots of each location into user://screens (or SCREEN_DIR env).
##   xvfb-run godot --path . res://tests/screenshots.tscn

var out_dir := ""


func _ready() -> void:
    out_dir = OS.get_environment("SCREEN_DIR")
    if out_dir == "":
        out_dir = OS.get_user_data_dir() + "/screens"
    DirAccess.make_dir_recursive_absolute(out_dir)
    var tree := get_tree()
    tree.root.remove_child.call_deferred(self)
    tree.root.add_child.call_deferred(self)
    _run.call_deferred()


func shot(name: String) -> void:
    await RenderingServer.frame_post_draw
    var img := get_viewport().get_texture().get_image()
    img.save_png(out_dir + "/" + name + ".png")
    print("SHOT ", name)


func wait(seconds: float) -> void:
    await get_tree().create_timer(seconds).timeout


func _run() -> void:
    get_window().size = Vector2i(1280, 720)
    GameState.new_game()
    get_tree().change_scene_to_file("res://scenes/workshop/workshop.tscn")
    await wait(2.5)
    await shot("01_workshop")
    get_tree().current_scene._show_tab("upgrades")
    await wait(1.5)
    await shot("02_workshop_upgrades")
    get_tree().change_scene_to_file("res://scenes/arena/arena.tscn")
    await wait(3.4)
    await shot("03_arena_gates_open")
    await wait(3.0)
    await shot("04_arena_walkout")
    await wait(6.5)
    await shot("05_arena_fight")
    var p = get_tree().current_scene.player
    p.target_pitch = -0.5
    await wait(1.5)
    await shot("06_cockpit_hands")
    get_tree().change_scene_to_file("res://scenes/salvage_yard/salvage_yard.tscn")
    await wait(2.5)
    await shot("07_salvage_yard")
    GameState.new_game()
    GameState.save_game()
    get_tree().quit()
