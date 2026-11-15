extends Node3D
## Workshop hub between matches: repair damage, equip / buy / sell parts,
## then deploy to the arena or the salvage yard.
## Uses the Blender environment when it exists, otherwise a blockout.

const ENV_PATH := "res://assets/models/environments/workshop.glb"

var display_mech: Mech
var camera: Camera3D
var _orbit := 0.6
var _ui: VBoxContainer


func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    LevelUtils.add_lighting(self, Color(0.25, 0.28, 0.33), Color(0.15, 0.15, 0.15), 0.8)
    if ResourceLoader.exists(ENV_PATH):
        LevelUtils.instance_environment(ENV_PATH, self)
    else:
        _build_blockout()
    camera = Camera3D.new()
    camera.fov = 55.0
    add_child(camera)
    camera.current = true
    _build_ui()
    _rebuild_mech()
    GameState.loadout_changed.connect(_on_state_changed)
    GameState.money_changed.connect(_on_state_changed.unbind(1))
    GameState.scrap_changed.connect(_on_state_changed.unbind(1))


func _process(delta: float) -> void:
    _orbit += delta * 0.12
    camera.position = Vector3(sin(_orbit) * 11.0, 5.0, cos(_orbit) * 11.0)
    camera.look_at(Vector3(0, 2.6, 0))


func _on_state_changed() -> void:
    _rebuild_mech()
    _refresh_ui()


func _rebuild_mech() -> void:
    if display_mech:
        display_mech.queue_free()
    display_mech = Mech.new()
    add_child(display_mech)
    display_mech.position = Vector3(0, 0.2, 0)
    display_mech.build(GameState.loadout, GameState.damage)


func _build_blockout() -> void:
    LevelUtils.add_box(self, Vector3(26, 0.4, 20), Vector3(0, -0.2, 0), Color(0.45, 0.44, 0.42))
    LevelUtils.add_box(self, Vector3(26, 10, 0.4), Vector3(0, 5, -10), Color(0.34, 0.4, 0.48))
    LevelUtils.add_box(self, Vector3(0.4, 10, 20), Vector3(-13, 5, 0), Color(0.34, 0.4, 0.48))
    LevelUtils.add_box(self, Vector3(0.4, 10, 20), Vector3(13, 5, 0), Color(0.34, 0.4, 0.48))
    LevelUtils.add_box(self, Vector3(9, 0.05, 9), Vector3(0, 0.02, 0), Color(0.95, 0.76, 0.19), 0.0, false)
    for x in [-4.2, 4.2]:
        for z in [-4.2, 4.2]:
            LevelUtils.add_box(self, Vector3(0.5, 8, 0.5), Vector3(x, 4, z), Color(0.23, 0.25, 0.28))
    var lamp := OmniLight3D.new()
    lamp.position = Vector3(0, 8, 2)
    lamp.omni_range = 20.0
    lamp.light_energy = 2.0
    add_child(lamp)


# ------------------------------------------------------------- UI
func _build_ui() -> void:
    var layer := CanvasLayer.new()
    add_child(layer)
    var panel := PanelContainer.new()
    panel.anchor_bottom = 1.0
    panel.offset_left = 16
    panel.offset_top = 16
    panel.offset_bottom = -16
    panel.custom_minimum_size = Vector2(520, 0)
    layer.add_child(panel)
    var scroll := ScrollContainer.new()
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    panel.add_child(scroll)
    _ui = VBoxContainer.new()
    _ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _ui.add_theme_constant_override("separation", 6)
    scroll.add_child(_ui)
    _refresh_ui()


func _refresh_ui() -> void:
    for c in _ui.get_children():
        c.queue_free()
    _text("MECH WORKSHOP", 30)
    _text("Money $%d    Scrap %d kg    Record %d-%d" % [GameState.money, GameState.scrap_kg,
        GameState.matches_won, GameState.matches_played - GameState.matches_won], 16)

    _header("Repairs")
    for slot in GameState.SLOTS:
        if str(GameState.loadout.get(slot, "")) == "":
            continue
        var row := _row()
        _cell(row, "%-9s %4d / %d" % [slot, GameState.current_hp(slot), GameState.max_hp(slot)])
        var cost := GameState.repair_cost(slot)
        if cost > 0:
            row.add_child(_button("Repair $%d" % cost, GameState.repair.bind(slot), cost > GameState.money))
    var total := GameState.repair_cost()
    if total > 0:
        _ui.add_child(_button("Repair everything  $%d" % total, GameState.repair.bind(""), total > GameState.money))

    _header("Loadout")
    for slot in GameState.SLOTS:
        var row := _row()
        var l := Label.new()
        l.text = slot
        l.custom_minimum_size.x = 90
        row.add_child(l)
        var opt := OptionButton.new()
        opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var current := str(GameState.loadout.get(slot, ""))
        opt.add_item(PartDB.display_name(current) if current != "" else "(empty)")
        opt.set_item_metadata(0, current)
        for id in GameState.inventory:
            if PartDB.fits(id, slot):
                opt.add_item("Equip: " + PartDB.display_name(id))
                opt.set_item_metadata(opt.item_count - 1, id)
        opt.item_selected.connect(_on_equip_selected.bind(opt, slot))
        row.add_child(opt)

    _header("Parts shop")
    for id in PartDB.sorted_ids():
        var price := int(PartDB.stat(id, "price", 0))
        var row := _row()
        _cell(row, "%s\n  %s" % [PartDB.display_name(id), PartDB.summary(id)])
        row.add_child(_button("Buy $%d" % price, GameState.buy_part.bind(id), price > GameState.money))

    _header("Inventory")
    if GameState.inventory.is_empty():
        _text("(empty - buy parts or find them in the salvage yard)", 14)
    for id in GameState.inventory:
        var row := _row()
        _cell(row, PartDB.display_name(id))
        var value := int(int(PartDB.stat(id, "price", 0)) * GameState.SELL_RATIO)
        row.add_child(_button("Sell $%d" % value, GameState.sell_part.bind(id)))

    _header("Deploy")
    _ui.add_child(_button("Enter the Arena", GameState.go_to.bind("arena")))
    _ui.add_child(_button("Drive to the Salvage Yard", GameState.go_to.bind("salvage_yard")))
    _ui.add_child(_button("New game (wipe save)", _on_new_game))


func _on_equip_selected(index: int, opt: OptionButton, slot: String) -> void:
    var id := str(opt.get_item_metadata(index))
    if id != str(GameState.loadout.get(slot, "")):
        GameState.equip(id, slot)


func _on_new_game() -> void:
    GameState.new_game()
    GameState.save_game()
    _on_state_changed()


func _text(t: String, size: int) -> void:
    var l := Label.new()
    l.text = t
    l.add_theme_font_size_override("font_size", size)
    _ui.add_child(l)


func _header(t: String) -> void:
    _ui.add_child(HSeparator.new())
    _text(t.to_upper(), 20)


func _row() -> HBoxContainer:
    var row := HBoxContainer.new()
    _ui.add_child(row)
    return row


func _cell(row: HBoxContainer, t: String) -> void:
    var l := Label.new()
    l.text = t
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(l)


func _button(t: String, action: Callable, disabled: bool = false) -> Button:
    var b := Button.new()
    b.text = t
    b.disabled = disabled
    b.pressed.connect(action)
    return b
