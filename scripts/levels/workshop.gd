extends Node3D
## Workshop: the mech stands in its dock, seen from the front in third person.
## Clickable options: UPGRADES, REPAIRS, PAINT. You can also click a part of
## the mech itself to jump to its upgrades. The camera glides to a shot per
## option (markers cam_* placed in Blender).

const ENV_PATH := "res://assets/models/environments/workshop.glb"
const TABS := {"upgrades": "UPGRADES", "repairs": "REPAIRS", "paint": "PAINT"}
const SHOTS := {"": "cam_overview", "upgrades": "cam_upgrade", "repairs": "cam_repair", "paint": "cam_paint"}
const ROTATE_SPEED := deg_to_rad(60.0)  # turntable speed while a rotate button is held
const TURNTABLE_NODES := ["turntable", "turntable_grooves"]

var display_mech: Mech
var camera: Camera3D
var dock: Node3D
var shots: Dictionary = {}  # marker name -> Transform3D

var _tab := ""
var _slot := "weapon_R"
var _hover_slot := ""
var _cam_tween: Tween
var _content: VBoxContainer
var _status_label: Label
var _tooltip: Label
var _tab_buttons: Dictionary = {}
var _dock_yaw := 0.0
var _spin := 0.0                       # -1 / 0 / +1 while a rotate control is held
var _turntable: Dictionary = {}        # node -> rest transform


func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    LevelUtils.add_lighting(self, Color(0.1, 0.12, 0.15), Color(0.08, 0.08, 0.08), 0.0)
    var root: Node3D
    if ResourceLoader.exists(ENV_PATH):
        root = LevelUtils.instance_environment(ENV_PATH, self)
    else:
        root = _build_blockout()
    dock = LevelUtils.find_marker(root, "mech_dock")
    for node_name in TURNTABLE_NODES:
        var n := LevelUtils.find_marker(root, node_name)
        if n:
            _turntable[n] = n.transform
    for marker_name in SHOTS.values():
        var m := LevelUtils.find_marker(root, marker_name)
        if m:
            shots[marker_name] = m.global_transform
    camera = Camera3D.new()
    camera.fov = 50.0
    add_child(camera)
    camera.current = true
    camera.global_transform = shots.get("cam_overview", Transform3D(Basis(), Vector3(2.4, 1.7, 11.0)))

    _build_ui()
    _rebuild_mech()
    _show_tab("")
    GameState.loadout_changed.connect(_on_state_changed)
    GameState.money_changed.connect(_on_state_changed.unbind(1))
    GameState.scrap_changed.connect(_on_state_changed.unbind(1))
    GameState.paint_changed.connect(_on_paint_changed)


# ------------------------------------------------------------- 3D
func _rebuild_mech() -> void:
    if display_mech:
        display_mech.queue_free()
    display_mech = Mech.new()
    add_child(display_mech)
    _apply_dock_yaw()
    display_mech.build(GameState.loadout, GameState.damage, GameState.paint)
    display_mech.set_physics_process(false)  # parked in the dock
    _hover_slot = ""
    if _tab == "upgrades":
        display_mech.set_highlight(_slot, true)


func _move_camera(marker_name: String) -> void:
    if not shots.has(marker_name):
        return
    if _cam_tween:
        _cam_tween.kill()
    _cam_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
    _cam_tween.tween_property(camera, "global_transform", shots[marker_name], 0.9)


func _process(delta: float) -> void:
    if _spin != 0.0:
        _dock_yaw = wrapf(_dock_yaw + _spin * ROTATE_SPEED * delta, -PI, PI)
        _apply_dock_yaw()


## Spin the docked mech (and the turntable under it) around the dock marker.
func _apply_dock_yaw() -> void:
    var rest := dock.global_transform if dock else Transform3D()
    if display_mech:
        display_mech.global_transform = Transform3D(rest.basis.rotated(Vector3.UP, _dock_yaw), rest.origin)
    for n in _turntable:
        var t: Transform3D = _turntable[n]
        n.transform = Transform3D(t.basis.rotated(Vector3.UP, _dock_yaw), t.origin)


func _set_spin(direction: float) -> void:
    _spin = direction


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and not event.echo:
        var key := (event as InputEventKey).physical_keycode
        if key == KEY_Q or key == KEY_E:
            _spin = (1.0 if key == KEY_Q else -1.0) if event.pressed else 0.0
            return
    if event is InputEventMouseMotion:
        _update_hover((event as InputEventMouseMotion).position)
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if _hover_slot != "":
            _slot = _hover_slot
            _show_tab("upgrades")


func _update_hover(mouse: Vector2) -> void:
    var from := camera.project_ray_origin(mouse)
    var q := PhysicsRayQueryParameters3D.create(from, from + camera.project_ray_normal(mouse) * 100.0, Mech.LAYER_HITBOX)
    q.collide_with_areas = true
    q.collide_with_bodies = false
    var hit := get_world_3d().direct_space_state.intersect_ray(q)
    var slot := ""
    if not hit.is_empty() and hit["collider"].has_meta("slot"):
        slot = str(hit["collider"].get_meta("slot"))
    if slot != _hover_slot:
        if _hover_slot != "" and not (_tab == "upgrades" and _hover_slot == _slot):
            display_mech.set_highlight(_hover_slot, false)
        _hover_slot = slot
        if slot != "":
            display_mech.set_highlight(slot, true)
    _tooltip.visible = slot != ""
    if slot != "":
        var id := str(GameState.loadout.get(slot, ""))
        _tooltip.text = "%s: %s\nClick to upgrade" % [GameState.SLOT_NAMES[slot], PartDB.display_name(id)]
        _tooltip.position = mouse + Vector2(18, 14)


# ------------------------------------------------------------- state
func _on_state_changed() -> void:
    _rebuild_mech()
    _refresh()


func _on_paint_changed() -> void:
    display_mech.apply_paint(GameState.paint)


# ------------------------------------------------------------- UI shell
func _build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var ui := Control.new()
    ui.set_anchors_preset(Control.PRESET_FULL_RECT)
    ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui.theme = UITheme.make()
    layer.add_child(ui)

    # top-left: title + wallet
    var header := PanelContainer.new()
    header.position = Vector2(20, 20)
    ui.add_child(header)
    var hv := VBoxContainer.new()
    header.add_child(hv)
    var title := Label.new()
    title.text = "MECH WORKSHOP  ·  BAY 01"
    title.add_theme_font_size_override("font_size", 24)
    title.add_theme_color_override("font_color", UITheme.ACCENT)
    hv.add_child(title)
    _status_label = Label.new()
    hv.add_child(_status_label)

    # rotate-in-dock controls, centred under the mech (hold to spin the turntable)
    var rotate_bar := HBoxContainer.new()
    rotate_bar.anchor_left = 0.36
    rotate_bar.anchor_right = 0.36
    rotate_bar.anchor_top = 1.0
    rotate_bar.anchor_bottom = 1.0
    rotate_bar.offset_left = -150
    rotate_bar.offset_right = 150
    rotate_bar.offset_top = -110
    rotate_bar.offset_bottom = -56
    rotate_bar.alignment = BoxContainer.ALIGNMENT_CENTER
    rotate_bar.add_theme_constant_override("separation", 16)
    ui.add_child(rotate_bar)
    for pair in [["<   ROTATE", 1.0, "Hold to turn the mech left (Q)"], ["ROTATE   >", -1.0, "Hold to turn the mech right (E)"]]:
        var b := Button.new()
        b.text = pair[0]
        b.tooltip_text = pair[2]
        b.custom_minimum_size = Vector2(140, 52)
        b.add_theme_font_size_override("font_size", 18)
        b.button_down.connect(_set_spin.bind(pair[1]))
        b.button_up.connect(_set_spin.bind(0.0))
        rotate_bar.add_child(b)

    # bottom-left hint
    var hint := Label.new()
    hint.text = "Tip: click any part of your mech to upgrade it  ·  Q / E rotates it in the dock"
    hint.add_theme_color_override("font_color", UITheme.MUTED)
    hint.anchor_top = 1.0
    hint.anchor_bottom = 1.0
    hint.offset_left = 24
    hint.offset_top = -40
    hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui.add_child(hint)

    # right: option tabs, content, deploy
    var panel := PanelContainer.new()
    panel.anchor_left = 1.0
    panel.anchor_right = 1.0
    panel.anchor_bottom = 1.0
    panel.offset_left = -500
    panel.offset_right = -20
    panel.offset_top = 20
    panel.offset_bottom = -20
    ui.add_child(panel)
    var pv := VBoxContainer.new()
    pv.add_theme_constant_override("separation", 10)
    panel.add_child(pv)
    var tabs := HBoxContainer.new()
    pv.add_child(tabs)
    for key in TABS:
        var b := Button.new()
        b.text = TABS[key]
        b.toggle_mode = true
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.custom_minimum_size.y = 46
        b.add_theme_font_size_override("font_size", 18)
        b.pressed.connect(_on_tab_pressed.bind(key))
        tabs.add_child(b)
        _tab_buttons[key] = b
    pv.add_child(HSeparator.new())
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    pv.add_child(scroll)
    _content = VBoxContainer.new()
    _content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _content.add_theme_constant_override("separation", 8)
    scroll.add_child(_content)
    pv.add_child(HSeparator.new())
    var deploy := HBoxContainer.new()
    pv.add_child(deploy)
    for pair in [["ENTER ARENA", "arena"], ["SALVAGE YARD", "salvage_yard"]]:
        var b := _button(pair[0], GameState.go_to.bind(pair[1]))
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.custom_minimum_size.y = 52
        b.add_theme_font_size_override("font_size", 18)
        deploy.add_child(b)

    _tooltip = Label.new()
    _tooltip.add_theme_color_override("font_outline_color", Color.BLACK)
    _tooltip.add_theme_constant_override("outline_size", 6)
    _tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _tooltip.visible = false
    ui.add_child(_tooltip)


func _on_tab_pressed(key: String) -> void:
    _show_tab("" if _tab == key else key)  # clicking the open tab returns to overview


func _show_tab(key: String) -> void:
    if display_mech and _tab == "upgrades":
        display_mech.set_highlight(_slot, false)
    _tab = key
    for k in _tab_buttons:
        _tab_buttons[k].set_pressed_no_signal(k == key)
    if display_mech and key == "upgrades":
        display_mech.set_highlight(_slot, true)
    _move_camera(SHOTS[key])
    _refresh()


func _refresh() -> void:
    _status_label.text = "$%d    ·    %d kg scrap    ·    record %d-%d" % [GameState.money, GameState.scrap_kg,
        GameState.matches_won, GameState.matches_played - GameState.matches_won]
    for c in _content.get_children():
        c.queue_free()
    match _tab:
        "upgrades": _build_upgrades()
        "repairs": _build_repairs()
        "paint": _build_paint()
        _: _build_overview()


# ------------------------------------------------------------- overview
func _build_overview() -> void:
    _heading("YOUR MECH")
    var hp := 0
    var max_hp := 0
    for slot in GameState.SLOTS:
        hp += GameState.current_hp(slot)
        max_hp += GameState.max_hp(slot)
    _line("Condition", "%d%%" % int(100.0 * hp / maxf(1.0, max_hp)))
    if display_mech:
        _line("Mass", "%.1f t" % (display_mech.mass_kg / 1000.0))
        _line("Top speed", "%d km/h" % int(display_mech.top_speed * 3.6))
    for slot in ["weapon_L", "weapon_R"]:
        _line(GameState.SLOT_NAMES[slot], PartDB.display_name(str(GameState.loadout.get(slot, ""))))
    _content.add_child(HSeparator.new())
    _option_card("UPGRADES", "Swap, buy and equip parts and weapons.", "upgrades")
    var cost := GameState.repair_cost()
    _option_card("REPAIRS", "All systems nominal." if cost == 0 else "Damage on board: full repair costs $%d." % cost, "repairs")
    _option_card("PAINT", "Change your mech's colours.", "paint")


func _option_card(title: String, body: String, tab: String) -> void:
    var b := _button("%s\n%s" % [title, body], _show_tab.bind(tab))
    b.alignment = HORIZONTAL_ALIGNMENT_LEFT
    b.custom_minimum_size.y = 70
    b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _content.add_child(b)


# ------------------------------------------------------------- upgrades
func _build_upgrades() -> void:
    _heading("SELECT PART")
    var grid := GridContainer.new()
    grid.columns = 2
    _content.add_child(grid)
    for slot in GameState.SLOTS:
        var b := _button(GameState.SLOT_NAMES[slot], _select_slot.bind(slot))
        b.toggle_mode = true
        b.set_pressed_no_signal(slot == _slot)
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        grid.add_child(b)

    var current := str(GameState.loadout.get(_slot, ""))
    _heading("EQUIPPED: " + GameState.SLOT_NAMES[_slot].to_upper())
    _part_card(current, "")

    var owned := GameState.inventory.filter(func(id): return PartDB.fits(id, _slot))
    if not owned.is_empty():
        _heading("IN STORAGE")
        for id in owned:
            _part_card(id, "equip")
    _heading("SHOP")
    var any := false
    for id in PartDB.sorted_ids():
        if PartDB.fits(id, _slot) and id != current:
            _part_card(id, "buy")
            any = true
    if not any:
        _note("Nothing else for this slot yet. Check the salvage yard.")


func _select_slot(slot: String) -> void:
    display_mech.set_highlight(_slot, false)
    _slot = slot
    display_mech.set_highlight(_slot, true)
    _refresh()


func _part_card(id: String, action: String) -> void:
    var card := PanelContainer.new()
    card.add_theme_stylebox_override("panel", UITheme.box(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.06), 1, 4))
    _content.add_child(card)
    var row := HBoxContainer.new()
    card.add_child(row)
    var info := Label.new()
    info.text = "%s\n%s" % [PartDB.display_name(id), PartDB.summary(id)] if id != "" else "(empty)"
    info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    row.add_child(info)
    match action:
        "equip":
            row.add_child(_button("EQUIP", _equip.bind(id)))
        "buy":
            var price := int(PartDB.stat(id, "price", 0))
            row.add_child(_button("BUY $%d" % price, _buy_and_equip.bind(id), price > GameState.money))


func _equip(id: String) -> void:
    GameState.equip(id, _slot)


func _buy_and_equip(id: String) -> void:
    if GameState.buy_part(id):
        GameState.equip(id, _slot)


# ------------------------------------------------------------- repairs
func _build_repairs() -> void:
    _heading("DAMAGE REPORT")
    for slot in GameState.SLOTS:
        if str(GameState.loadout.get(slot, "")) == "":
            continue
        var hp := GameState.current_hp(slot)
        var max_hp := maxi(1, GameState.max_hp(slot))
        var row := HBoxContainer.new()
        _content.add_child(row)
        var l := Label.new()
        l.text = GameState.SLOT_NAMES[slot]
        l.custom_minimum_size.x = 120
        row.add_child(l)
        var bar := ProgressBar.new()
        bar.max_value = max_hp
        bar.value = hp
        bar.show_percentage = false
        bar.custom_minimum_size = Vector2(0, 18)
        bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        if hp < max_hp * 0.5:
            bar.add_theme_stylebox_override("fill", UITheme.box(UITheme.BAD, Color(0, 0, 0, 0), 0, 3, 0))
        row.add_child(bar)
        var cost := GameState.repair_cost(slot)
        if cost > 0:
            row.add_child(_button("$%d" % cost, GameState.repair.bind(slot), cost > GameState.money))
        else:
            var ok := Label.new()
            ok.text = "  OK  "
            ok.add_theme_color_override("font_color", UITheme.GOOD)
            row.add_child(ok)
    var total := GameState.repair_cost()
    _content.add_child(HSeparator.new())
    if total == 0:
        _note("All systems nominal.")
    else:
        var b := _button("REPAIR EVERYTHING  ·  $%d" % total, GameState.repair.bind(""), total > GameState.money)
        b.custom_minimum_size.y = 46
        _content.add_child(b)
        _note("Repairs cost $%d per HP. Missing armour plates are refitted." % GameState.REPAIR_COST_PER_HP)


# ------------------------------------------------------------- paint
func _build_paint() -> void:
    _heading("COLOURS")
    for channel in GameState.PAINT_CHANNELS:
        var row := HBoxContainer.new()
        _content.add_child(row)
        var l := Label.new()
        l.text = GameState.PAINT_CHANNELS[channel]
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(l)
        var picker := ColorPickerButton.new()
        picker.color = Color(str(GameState.paint.get(channel, "#ffffff")))
        picker.edit_alpha = false
        picker.custom_minimum_size = Vector2(150, 34)
        picker.color_changed.connect(_on_color_dragged.bind(channel))
        picker.popup_closed.connect(GameState.save_game)
        row.add_child(picker)
    _heading("PRESETS")
    var grid := GridContainer.new()
    grid.columns = 2
    _content.add_child(grid)
    for preset in GameState.PAINT_PRESETS:
        var colors: Dictionary = GameState.PAINT_PRESETS[preset]
        var b := _button(preset, _apply_preset.bind(preset))
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.custom_minimum_size.y = 44
        var primary := Color(str(colors["primary"]))
        b.add_theme_stylebox_override("normal", UITheme.box(primary.darkened(0.35), Color(str(colors["accent"])), 2, 4))
        b.add_theme_stylebox_override("hover", UITheme.box(primary.darkened(0.15), Color.WHITE, 2, 4))
        grid.add_child(b)
    _note("Paint is free. It's your mech, make it yours.")


func _on_color_dragged(color: Color, channel: String) -> void:
    GameState.set_paint_color(channel, color, false)  # saved when the picker closes


func _apply_preset(preset: String) -> void:
    GameState.apply_paint_preset(preset)
    _refresh()


# ------------------------------------------------------------- widgets
func _heading(t: String) -> void:
    var l := Label.new()
    l.text = t
    l.add_theme_font_size_override("font_size", 14)
    l.add_theme_color_override("font_color", UITheme.ACCENT)
    _content.add_child(l)


func _line(key: String, value: String) -> void:
    var row := HBoxContainer.new()
    _content.add_child(row)
    var k := Label.new()
    k.text = key
    k.add_theme_color_override("font_color", UITheme.MUTED)
    k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(k)
    var v := Label.new()
    v.text = value
    row.add_child(v)


func _note(t: String) -> void:
    var l := Label.new()
    l.text = t
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.add_theme_color_override("font_color", UITheme.MUTED)
    _content.add_child(l)


func _button(t: String, action: Callable, disabled: bool = false) -> Button:
    var b := Button.new()
    b.text = t
    b.disabled = disabled
    b.pressed.connect(action)
    return b


# ------------------------------------------------------------- fallback
func _build_blockout() -> Node3D:
    var root := Node3D.new()
    root.name = "WorkshopBlockout"
    add_child(root)
    LevelUtils.add_box(root, Vector3(28, 0.3, 24), Vector3(0, -0.15, 2), Color(0.45, 0.44, 0.42))
    LevelUtils.add_box(root, Vector3(28, 8.5, 0.3), Vector3(0, 4.25, -10), Color(0.25, 0.3, 0.36))
    for x in [-4.7, 4.7]:
        LevelUtils.add_box(root, Vector3(1.9, 6.4, 3), Vector3(x, 3.2, -0.5), Color(0.88, 0.65, 0.15))
    var lamp := OmniLight3D.new()
    lamp.position = Vector3(0, 7, 5)
    lamp.omni_range = 18.0
    lamp.light_energy = 2.5
    root.add_child(lamp)
    LevelUtils.add_marker(root, "mech_dock", Vector3(0, 0.18, 0))
    var cams := {"cam_overview": [Vector3(2.4, 1.7, 11.0), Vector3(2.2, 2.9, 0)],
                 "cam_upgrade": [Vector3(1.9, 1.7, 6.8), Vector3(1.6, 3.3, 0)],
                 "cam_repair": [Vector3(4.6, 1.2, 6.6), Vector3(1.3, 2.6, 0)],
                 "cam_paint": [Vector3(2.8, 1.6, 8.8), Vector3(2.4, 2.9, 0)]}
    for marker_name in cams:
        var m := LevelUtils.add_marker(root, marker_name, cams[marker_name][0])
        m.look_at(cams[marker_name][1])
    return root
