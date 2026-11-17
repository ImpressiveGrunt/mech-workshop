class_name HoloHud
extends Control
## Holographic HUD drawn into a SubViewport that the game maps onto the cockpit's holo plane
## (Blender: holo_hud mesh + holo_frame marker just inside the armoured glass). World points are
## projected from the pilot's eye onto that plane, so brackets sit on the targets seen through the
## glass and the whole display sways with the cockpit.

const CYAN := Color(0.35, 0.95, 1.0)
const AMBER := Color(1.0, 0.75, 0.3)
const RED := Color(1.0, 0.32, 0.25)

var mech: Mech
var camera: Camera3D
var targeting: Targeting
var frame: Node3D
var size_m := Vector2(1.12, 0.41)
var _font: Font
var _flicker := 0.0
var _time := 0.0


func _ready() -> void:
    _font = ThemeDB.fallback_font
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    if mech:
        mech.hit_taken.connect(func(_m, _s, amount): _flicker = minf(1.0, _flicker + amount * 0.02))


func _process(delta: float) -> void:
    _time += delta
    _flicker = move_toward(_flicker, 0.0, delta * 1.5)
    queue_redraw()


## Pilot's-eye projection of a world point onto the holo plane, in canvas pixels (null if behind).
func project(world: Vector3) -> Variant:
    var inv := frame.global_transform.affine_inverse()
    var e := inv * camera.global_position
    var d := inv * world - e
    if d.z >= -0.0001:
        return null
    var hit := e + d * (-e.z / d.z)
    return Vector2((hit.x / size_m.x + 0.5) * size.x, (0.5 - hit.y / size_m.y) * size.y)


func _col(c: Color, a: float = 1.0) -> Color:
    var flick := 1.0 - _flicker * randf() * 0.7
    return Color(c.r, c.g, c.b, c.a * a * flick)


func _draw() -> void:
    if mech == null or camera == null or frame == null or mech.is_destroyed:
        return
    if _flicker > 0.05:
        draw_set_transform(Vector2(randf_range(-6, 6) * _flicker, 0))
    _draw_frame()
    _draw_compass()
    _draw_aim()
    _draw_target()
    _draw_side_bars()
    _draw_twist_indicator()


func _text(pos: Vector2, s: String, size_px: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
    draw_string(_font, pos, s, align, width, size_px, _col(c))


func _draw_frame() -> void:
    for y in range(0, int(size.y), 6):
        draw_line(Vector2(0, y), Vector2(size.x, y), _col(CYAN, 0.035), 1.0)
    var L := 40.0
    for corner in [Vector2(8, 8), Vector2(size.x - 8, 8), Vector2(8, size.y - 8), Vector2(size.x - 8, size.y - 8)]:
        var sx := 1.0 if corner.x < size.x / 2 else -1.0
        var sy := 1.0 if corner.y < size.y / 2 else -1.0
        draw_line(corner, corner + Vector2(L * sx, 0), _col(CYAN, 0.6), 2.0)
        draw_line(corner, corner + Vector2(0, L * sy), _col(CYAN, 0.6), 2.0)


func _draw_compass() -> void:
    var fwd := -camera.global_basis.z
    var heading := fposmod(rad_to_deg(atan2(fwd.x, fwd.z)), 360.0)
    var cx := size.x / 2
    var y := 34.0
    var span := 90.0           # degrees across the tape
    var width := 460.0
    draw_line(Vector2(cx - width / 2, y), Vector2(cx + width / 2, y), _col(CYAN, 0.5), 1.5)
    for k in range(-50, 51, 5):
        var deg := floorf(heading / 5.0) * 5.0 + k
        var off := (deg - heading) / span * width
        if absf(off) > width / 2:
            continue
        var d := int(fposmod(deg, 360.0))
        var big := d % 30 == 0
        draw_line(Vector2(cx + off, y), Vector2(cx + off, y - (12.0 if big else 6.0)), _col(CYAN, 0.8), 1.5)
        if big:
            var label: String = str({0: "N", 90: "E", 180: "S", 270: "W"}.get(d, "%03d" % d))
            _text(Vector2(cx + off - 30, y - 16), label, 15, CYAN, HORIZONTAL_ALIGNMENT_CENTER, 60)
    draw_colored_polygon(PackedVector2Array([Vector2(cx, y + 2), Vector2(cx - 7, y + 12), Vector2(cx + 7, y + 12)]), _col(AMBER))
    _text(Vector2(cx - 40, y + 30), "%03d" % int(heading), 16, AMBER, HORIZONTAL_ALIGNMENT_CENTER, 80)


func _draw_aim() -> void:
    # gun pipper: where the guns point right now
    var pip = project(camera.global_position - camera.global_basis.z * 300.0)
    if pip != null:
        for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
            draw_line(pip + d * 6.0, pip + d * 16.0, _col(CYAN), 2.0)
        draw_circle(pip, 2.0, _col(CYAN))
    # aim ring: where the pilot is steering the heavy torso/arms to
    var aim = project(camera.global_position + mech.target_aim_direction() * 300.0)
    if aim != null:
        var err := absf(mech.target_twist - mech.torso_twist) + absf(mech.target_pitch - mech.aim_pitch)
        var settled := clampf(1.0 - err / 0.05, 0.0, 1.0)
        draw_arc(aim, 22.0, 0.0, TAU, 40, _col(AMBER, 0.5 + 0.5 * settled), 2.0, true)
        if pip != null and err > 0.02:
            draw_dashed_line(pip, aim, _col(AMBER, 0.35), 1.5, 6.0)


func _draw_target() -> void:
    if targeting == null or targeting.target == null:
        _text(Vector2(size.x / 2 - 100, size.y - 22), "NO TARGET", 16, CYAN, HORIZONTAL_ALIGNMENT_CENTER, 200)
        return
    var t := targeting.target
    var dist := camera.global_position.distance_to(Targeting.aim_point_of(t))
    var c := RED if targeting.locked else (AMBER if targeting.lock > 0.0 else CYAN)
    var top = project(t.global_position + Vector3(0, 4.8, 0))
    var bottom = project(t.global_position)
    var inside: bool = top != null and bottom != null and Rect2(Vector2.ZERO, size).grow(-10).has_point((top + bottom) / 2.0)
    if inside:
        var h: float = maxf(70.0, (bottom - top).length())   # readable even across the arena
        var w := h * 0.8
        var r := Rect2((top + bottom) / 2.0 - Vector2(w, h) / 2.0, Vector2(w, h))
        var L := minf(w, h) * 0.28
        for corner in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
            var sx := 1.0 if corner.x == r.position.x else -1.0
            var sy := 1.0 if corner.y == r.position.y else -1.0
            draw_line(corner, corner + Vector2(L * sx, 0), _col(c), 2.5)
            draw_line(corner, corner + Vector2(0, L * sy), _col(c), 2.5)
        if targeting.lock > 0.0 and not targeting.locked:
            draw_arc(r.get_center(), maxf(w, h) * 0.62, -PI / 2, -PI / 2 + TAU * targeting.lock, 48, _col(AMBER), 3.0, true)
        if targeting.locked:
            var blink := 0.6 + 0.4 * sin(_time * 12.0)
            draw_arc(r.get_center(), maxf(w, h) * 0.62, 0.0, TAU, 48, _col(RED, blink), 3.0, true)
        _text(Vector2(r.get_center().x - 90, r.position.y - 22), "%s  %d m" % [_target_name(t), int(dist)], 16, c,
            HORIZONTAL_ALIGNMENT_CENTER, 180)
        var torso_f: float = t.part_hp.get("torso", 0.0) / maxf(1.0, t.part_max_hp.get("torso", 1.0))
        draw_rect(Rect2(r.position + Vector2(0, -14), Vector2(w, 5)), _col(c, 0.25))
        draw_rect(Rect2(r.position + Vector2(0, -14), Vector2(w * torso_f, 5)), _col(c))
        var status := "LOCKED" if targeting.locked else ("LOCKING %d%%" % int(targeting.lock * 100) if targeting.lock > 0.0 else "")
        if status != "":
            _text(Vector2(r.get_center().x - 90, r.end.y + 20), status, 16, c, HORIZONTAL_ALIGNMENT_CENTER, 180)
        _draw_weak_point(t)
        if not targeting.has_line_of_sight:
            _text(Vector2(r.get_center().x - 80, r.end.y + 38), "NO LINE OF SIGHT", 13, CYAN, HORIZONTAL_ALIGNMENT_CENTER, 160)
    else:
        _draw_offscreen_arrow(t, c, dist)
    # target readout strip along the bottom of the hologram
    var parts: Array[String] = []
    for slot in ["arm_L", "torso", "arm_R", "legs"]:
        if t.part_max_hp.has(slot):
            parts.append("%s %d%%" % [slot.replace("_", " ").to_upper(), int(t.part_hp[slot] / t.part_max_hp[slot] * 100)])
    var strip := "TGT  " + "   ".join(parts)
    if targeting.locked and _has_missiles():
        strip += "     MISSILES HOMING"
    _text(Vector2(size.x / 2 - 300, size.y - 22), strip, 14, c, HORIZONTAL_ALIGNMENT_CENTER, 600)
    _text(Vector2(size.x / 2 - 80, size.y - 6), "[T] NEXT TARGET", 11, CYAN, HORIZONTAL_ALIGNMENT_CENTER, 160)


func _draw_weak_point(t: Mech) -> void:
    for wp in t.weak_points:
        if not is_instance_valid(wp):
            continue
        var to_eye: Vector3 = (camera.global_position - wp.global_position).normalized()
        if to_eye.dot(-t.global_basis.z) < 0.25:   # reactor is on the back
            return
        var p = project(wp.global_position)
        if p == null:
            return
        var s := 10.0 + 3.0 * sin(_time * 8.0)
        draw_polyline(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0), p + Vector2(0, -s)]), _col(RED), 2.0)
        _text(p + Vector2(14, 5), "WEAK POINT", 13, RED)
        return


func _draw_offscreen_arrow(t: Mech, c: Color, dist: float) -> void:
    var local := camera.global_transform.affine_inverse() * Targeting.aim_point_of(t)
    var dir := Vector2(local.x, -local.y)
    if dir.length() < 0.001:
        dir = Vector2(0, 1)
    dir = dir.normalized()
    var centre := size / 2.0
    var edge := centre + Vector2(dir.x * (size.x / 2 - 40), dir.y * (size.y / 2 - 40))
    var ang := dir.angle()
    var pts := PackedVector2Array([edge + Vector2.from_angle(ang) * 18, edge + Vector2.from_angle(ang + 2.5) * 14, edge + Vector2.from_angle(ang - 2.5) * 14])
    draw_colored_polygon(pts, _col(c))
    _text(edge - dir * 34 + Vector2(-40, 5), "%d m" % int(dist), 14, c, HORIZONTAL_ALIGNMENT_CENTER, 80)


func _draw_side_bars() -> void:
    var h := size.y * 0.45
    var y0 := size.y * 0.3
    var speed := Vector2(mech.velocity.x, mech.velocity.z).length()
    var f := clampf(speed / maxf(1.0, mech.top_speed), 0.0, 1.0)
    draw_rect(Rect2(28, y0, 10, h), _col(CYAN, 0.2))
    draw_rect(Rect2(28, y0 + h * (1.0 - f), 10, h * f), _col(CYAN, 0.8))
    _text(Vector2(46, y0 + 12), "%d km/h" % int(speed * 3.6), 15, CYAN)
    _text(Vector2(46, y0 + 30), "THR %+d%%" % int(mech.throttle * 100), 13, CYAN)
    if mech.max_fuel > 0.0:
        var b := mech.fuel / mech.max_fuel
        draw_rect(Rect2(size.x - 38, y0, 10, h), _col(CYAN, 0.2))
        draw_rect(Rect2(size.x - 38, y0 + h * (1.0 - b), 10, h * b), _col(AMBER if b < 0.3 else CYAN, 0.8))
        _text(Vector2(size.x - 130, y0 + 12), "BOOST", 15, CYAN, HORIZONTAL_ALIGNMENT_RIGHT, 84)
    var yy := y0 + h + 22
    for wslot in ["weapon_L", "weapon_R"]:
        var w: Weapon = mech.weapons.get(wslot)
        var x := 28.0 if wslot == "weapon_L" else size.x - 228.0
        var align := HORIZONTAL_ALIGNMENT_LEFT if wslot == "weapon_L" else HORIZONTAL_ALIGNMENT_RIGHT
        if w:
            var in_range := targeting != null and targeting.target != null and \
                camera.global_position.distance_to(Targeting.aim_point_of(targeting.target)) <= w.weapon_range
            var label := "%s %s" % [PartDB.display_name(w.part_id).split(" ")[0].to_upper(), "IN RANGE" if in_range else ""]
            _text(Vector2(x, yy), label, 14, CYAN if w.ready_fraction() >= 1.0 else AMBER, align, 200)
        else:
            _text(Vector2(x, yy), "OFFLINE", 14, RED, align, 200)


func _draw_twist_indicator() -> void:
    # torso vs legs: the arc shows how far the torso is twisted from the direction the legs walk
    var c := Vector2(size.x / 2 + 230, size.y - 30)
    draw_arc(c, 26.0, PI + 0.4, TAU - 0.4, 24, _col(CYAN, 0.4), 1.5, true)
    var legs_dir := Vector2.from_angle(-PI / 2 - mech.torso_twist)
    draw_line(c, c + legs_dir * 26.0, _col(AMBER), 2.0)
    draw_line(c, c + Vector2(0, -30), _col(CYAN), 2.0)


func _target_name(t: Mech) -> String:
    var legs := str(t.loadout.get("legs", "MECH"))
    return legs.split("_")[-1].to_upper()


func _has_missiles() -> bool:
    for w in mech.weapons.values():
        if w.weapon_type == "explosive":
            return true
    return false
