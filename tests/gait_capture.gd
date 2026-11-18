extends Node
## Captures a side-view frame strip of a mech walking, turning and stopping (for gait tuning).
##   xvfb-run godot --path . res://tests/gait_capture.tscn     (SCREEN_DIR env = output folder)

var out_dir := ""
var cam: Camera3D
var m: Mech


func _ready() -> void:
    out_dir = OS.get_environment("SCREEN_DIR")
    var tree := get_tree()
    tree.root.remove_child.call_deferred(self)
    tree.root.add_child.call_deferred(self)
    _run.call_deferred()


func shot(name: String) -> void:
    await RenderingServer.frame_post_draw
    get_viewport().get_texture().get_image().save_png(out_dir + "/" + name + ".png")


func _run() -> void:
    get_window().size = Vector2i(640, 400)
    get_tree().change_scene_to_file("res://scenes/testing_grounds/testing_grounds.tscn")
    await get_tree().create_timer(1.5).timeout
    var tg = get_tree().current_scene
    tg.player_ctrl.queue_free()            # drive the player mech directly, view from outside
    m = tg.player
    cam = Camera3D.new()
    cam.fov = 40
    tg.add_child(cam)
    cam.current = true
    tg.hud.visible = false
    var phases := [["walk", 1.0, 0.0, 3.0], ["turn", 0.0, 1.0, 1.6], ["stop", 0.0, 0.0, 1.6]]
    var n := 0
    for ph in phases:
        m.throttle = ph[1]
        m.turn = ph[2]
        var t := 0.0
        var next := 0.0
        while t < ph[3]:
            var side: Vector3 = m.global_basis.x
            cam.global_position = m.global_position + side * 13.0 + Vector3(0, 2.6, 0)
            cam.look_at(m.global_position + Vector3(0, 2.0, 0))
            await get_tree().physics_frame
            t += 1.0 / Engine.physics_ticks_per_second
            if t >= next:
                await shot("gait_%02d_%s" % [n, ph[0]])
                n += 1
                next += 0.1
    get_tree().quit()
