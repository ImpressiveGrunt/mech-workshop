class_name Hud
extends CanvasLayer
## In-cockpit HUD: crosshair, part integrity, boost fuel, ammo, prompts, messages.

var mech: Mech
var _reticle: Reticle


## Ring drawn where the pilot is aiming; the centre "+" shows where the guns point right now.
class Reticle extends Control:
    var aligned := 0.0   # 1 when the guns have caught up

    func _draw() -> void:
        var col := Color(1.0, 0.75, 0.3, 0.55 + 0.4 * aligned)
        draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, col, 2.0, true)
        for k in 4:
            var d := Vector2.from_angle(k * PI / 2.0 + PI / 4.0)
            draw_line(d * 10.0, d * 22.0, col, 2.0, true)
var _status: Label
var _prompt: Label
var _message: Label
var _message_token := 0


func _ready() -> void:
    var crosshair := _label(0, 0, 1, 1, 28, HORIZONTAL_ALIGNMENT_CENTER)
    crosshair.text = "+"
    _status = _label(0, 0, 0.4, 0.5, 18, HORIZONTAL_ALIGNMENT_LEFT)
    _status.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    _status.offset_left = 20
    _status.offset_top = 20
    _prompt = _label(0, 0.72, 1, 0.78, 24, HORIZONTAL_ALIGNMENT_CENTER)
    _message = _label(0, 0.25, 1, 0.32, 36, HORIZONTAL_ALIGNMENT_CENTER)
    _reticle = Reticle.new()
    _reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_reticle)


func _process(_delta: float) -> void:
    if mech == null or not is_instance_valid(mech):
        return
    _update_reticle()
    if mech.has_meta("diegetic_hud"):
        _status.text = ""   # the cockpit screens show this instead
        return
    var lines: Array[String] = []
    for slot in GameState.SLOTS:
        if mech.part_max_hp.has(slot):
            var hp: float = mech.part_hp[slot]
            lines.append("%-9s %s %4d" % [slot.to_upper(), _bar(hp / mech.part_max_hp[slot]), int(hp)])
    if mech.max_fuel > 0.0:
        lines.append("BOOST     %s" % _bar(mech.fuel / mech.max_fuel))
    for wslot in mech.weapons:
        var w: Weapon = mech.weapons[wslot]
        lines.append("%s  %s" % [PartDB.display_name(w.part_id), "inf" if w.ammo < 0 else str(w.ammo)])
    _status.text = "\n".join(lines)


func _update_reticle() -> void:
    var cam := get_viewport().get_camera_3d()
    if cam == null or mech.is_destroyed:
        _reticle.visible = false
        return
    var point := cam.global_position + mech.target_aim_direction() * 300.0
    _reticle.visible = not cam.is_position_behind(point)
    if _reticle.visible:
        _reticle.position = cam.unproject_position(point)
        var err := absf(mech.target_twist - mech.torso_twist) + absf(mech.target_pitch - mech.aim_pitch)
        _reticle.aligned = clampf(1.0 - err / 0.05, 0.0, 1.0)
        _reticle.queue_redraw()


func set_prompt(text: String) -> void:
    _prompt.text = text


func show_message(text: String, seconds: float = 3.0) -> void:
    _message_token += 1
    var token := _message_token
    _message.text = text
    await get_tree().create_timer(seconds).timeout
    if token == _message_token:
        _message.text = ""


func _bar(fraction: float) -> String:
    var n := int(round(clampf(fraction, 0.0, 1.0) * 10.0))
    return "[" + "#".repeat(n) + ".".repeat(10 - n) + "]"


func _label(l: float, t: float, r: float, b: float, size: int, align: HorizontalAlignment) -> Label:
    var lab := Label.new()
    lab.anchor_left = l
    lab.anchor_top = t
    lab.anchor_right = r
    lab.anchor_bottom = b
    lab.horizontal_alignment = align
    lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    lab.add_theme_font_size_override("font_size", size)
    lab.add_theme_color_override("font_outline_color", Color.BLACK)
    lab.add_theme_constant_override("outline_size", 6)
    lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(lab)
    return lab
