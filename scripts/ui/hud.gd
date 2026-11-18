class_name Hud
extends CanvasLayer
## In-cockpit HUD: crosshair, part integrity, boost fuel, ammo, prompts, messages.

var mech: Mech
var aim: Node3D            # gun direction reference (PlayerController.aim); null = use the camera
var targeting: Targeting
var _reticle: Reticle
var _crosshair: Label


## Screen overlay: aim ring (where the pilot is steering the aim), gun cross (where the guns point
## now, shown when it isn't the screen centre: third person / free-look), and the target bracket.
class Reticle extends Control:
    var aligned := 0.0
    var ring := Vector2.ZERO
    var ring_on := false
    var gun := Vector2.ZERO
    var gun_on := false
    var target_rect := Rect2()
    var target_on := false
    var target_text := ""
    var target_color := Color.WHITE

    func _draw() -> void:
        var col := Color(1.0, 0.75, 0.3, 0.55 + 0.4 * aligned)
        if ring_on:
            draw_arc(ring, 16.0, 0.0, TAU, 32, col, 2.0, true)
            for k in 4:
                var d := Vector2.from_angle(k * PI / 2.0 + PI / 4.0)
                draw_line(ring + d * 10.0, ring + d * 22.0, col, 2.0, true)
        if gun_on:
            var c := Color(0.4, 0.95, 1.0)
            for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
                draw_line(gun + d * 5.0, gun + d * 14.0, c, 2.0, true)
            if ring_on and gun.distance_to(ring) > 6.0:
                draw_dashed_line(gun, ring, Color(col, 0.35), 1.5, 6.0)
        if target_on:
            var r := target_rect
            var L := minf(r.size.x, r.size.y) * 0.28
            for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
                var sx := 1.0 if corner.x == r.position.x else -1.0
                var sy := 1.0 if corner.y == r.position.y else -1.0
                draw_line(corner, corner + Vector2(L * sx, 0), target_color, 2.5)
                draw_line(corner, corner + Vector2(0, L * sy), target_color, 2.5)
            draw_string(ThemeDB.fallback_font, Vector2(r.position.x, r.position.y - 8), target_text,
                HORIZONTAL_ALIGNMENT_LEFT, -1, 16, target_color)
var _status: Label
var _prompt: Label
var _message: Label
var _message_token := 0


func _ready() -> void:
    _crosshair = _label(0, 0, 1, 1, 28, HORIZONTAL_ALIGNMENT_CENTER)
    _crosshair.text = "+"
    _status = _label(0, 0, 0.4, 0.5, 18, HORIZONTAL_ALIGNMENT_LEFT)
    _status.vertical_alignment = VERTICAL_ALIGNMENT_TOP
    _status.offset_left = 20
    _status.offset_top = 20
    _prompt = _label(0, 0.72, 1, 0.78, 24, HORIZONTAL_ALIGNMENT_CENTER)
    _message = _label(0, 0.25, 1, 0.32, 36, HORIZONTAL_ALIGNMENT_CENTER)
    _reticle = Reticle.new()
    _reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_reticle)


func _process(_delta: float) -> void:
    if mech == null or not is_instance_valid(mech):
        return
    var holo_active := mech.has_meta("holo_hud")   # the cockpit hologram draws aim + targeting instead
    if holo_active:
        _crosshair.visible = false
        _reticle.visible = false
    else:
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
    _reticle.visible = true
    var ring_point := cam.global_position + mech.target_aim_direction() * 300.0
    _reticle.ring_on = not cam.is_position_behind(ring_point)
    if _reticle.ring_on:
        _reticle.ring = cam.unproject_position(ring_point)
    var err := absf(mech.target_twist - mech.torso_twist) + absf(mech.target_pitch - mech.aim_pitch)
    _reticle.aligned = clampf(1.0 - err / 0.05, 0.0, 1.0)
    # guns: centre "+" only when the camera looks exactly down the barrels (first person, no free-look)
    var gun_centred := aim == null or (cam.global_position.distance_to(aim.global_position) < 0.05
        and (-cam.global_basis.z).angle_to(-aim.global_basis.z) < 0.01)
    _crosshair.visible = gun_centred
    _reticle.gun_on = false
    if not gun_centred:
        var gp := aim.global_position - aim.global_basis.z * 300.0
        _reticle.gun_on = not cam.is_position_behind(gp)
        if _reticle.gun_on:
            _reticle.gun = cam.unproject_position(gp)
    _reticle.target_on = false
    if targeting and targeting.target and is_instance_valid(targeting.target):
        var t := targeting.target
        var top := t.global_position + Vector3(0, 4.8, 0)
        var bottom := t.global_position
        if not cam.is_position_behind(top) and not cam.is_position_behind(bottom):
            var a := cam.unproject_position(top)
            var b := cam.unproject_position(bottom)
            var h := maxf(40.0, absf(b.y - a.y))
            _reticle.target_rect = Rect2((a + b) / 2.0 - Vector2(h * 0.4, h / 2.0), Vector2(h * 0.8, h))
            _reticle.target_on = true
            var dist := int(aim.global_position.distance_to(t.global_position)) if aim else 0
            _reticle.target_color = Color(1, 0.32, 0.25) if targeting.locked else (Color(1, 0.75, 0.3) if targeting.lock > 0.0 else Color(0.4, 0.95, 1.0))
            _reticle.target_text = "%d m  %s" % [dist, "LOCKED" if targeting.locked else ("LOCKING %d%%" % int(targeting.lock * 100) if targeting.lock > 0.0 else "")]
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
