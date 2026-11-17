extends Node
## Campaign state that survives between scenes: money, scrap, owned parts,
## the equipped loadout, damage carried between matches, and scene flow.
##
## Loop: Workshop (repair / upgrade) -> Arena (fight for money)
##                                   -> Salvage Yard (find parts + scrap to sell)

signal money_changed(money: int)
signal scrap_changed(scrap_kg: int)
signal loadout_changed
signal paint_changed

const SAVE_PATH := "user://save.json"
const SCENES := {
    "workshop": "res://scenes/workshop/workshop.tscn",
    "arena": "res://scenes/arena/arena.tscn",
    "salvage_yard": "res://scenes/salvage_yard/salvage_yard.tscn",
}
const SLOTS := ["legs", "torso", "arm_L", "arm_R", "weapon_L", "weapon_R", "back"]
const STARTING_LOADOUT := {
    "legs": "legs_biped_mk1",
    "torso": "torso_mk1",
    "arm_L": "arm_L_mk1",
    "arm_R": "arm_R_mk1",
    "weapon_L": "weapon_ram_fist_mk1",
    "weapon_R": "weapon_autocannon_mk1",
    "back": "back_thruster_mk1",
}
const SLOT_NAMES := {
    "legs": "Legs", "torso": "Torso", "arm_L": "Left Arm", "arm_R": "Right Arm",
    "weapon_L": "Left Weapon", "weapon_R": "Right Weapon", "back": "Backpack",
}
# Paint channels map to Blender material suffixes: _paint, _trim, _hazard, _glow.
const PAINT_CHANNELS := {"primary": "Primary", "secondary": "Secondary", "accent": "Stripes", "glow": "Lights"}
const DEFAULT_PAINT := {"primary": "#e8772e", "secondary": "#2b2f36", "accent": "#f2c230", "glow": "#ffb347"}
const PAINT_PRESETS := {
    "Foundry": DEFAULT_PAINT,
    "Arctic": {"primary": "#dfe6ea", "secondary": "#3a4a5a", "accent": "#3ce6ff", "glow": "#3ce6ff"},
    "Jungle": {"primary": "#4f6b3a", "secondary": "#2a2e24", "accent": "#d9c45a", "glow": "#9cff6b"},
    "Crimson": {"primary": "#a8262b", "secondary": "#1e1e22", "accent": "#e6e6e6", "glow": "#ff4b3a"},
    "Hornet": {"primary": "#f2c230", "secondary": "#1b1c1e", "accent": "#1b1c1e", "glow": "#ff9a2e"},
    "Ghost": {"primary": "#2c3036", "secondary": "#14161a", "accent": "#7d8590", "glow": "#b06bff"},
}
const STARTING_MONEY := 500
const REPAIR_COST_PER_HP := 2
const SCRAP_PRICE_PER_KG := 3
const SELL_RATIO := 0.5

var money: int = STARTING_MONEY
var scrap_kg: int = 0
var inventory: Array[String] = []
var loadout: Dictionary = {}
var damage: Dictionary = {}  # slot -> hp lost, carried between matches
var paint: Dictionary = {}   # channel -> "#rrggbb"
var matches_played: int = 0
var matches_won: int = 0


func _ready() -> void:
    _setup_input()
    new_game()
    load_game()


func new_game() -> void:
    money = STARTING_MONEY
    scrap_kg = 0
    inventory.clear()
    loadout = STARTING_LOADOUT.duplicate()
    damage.clear()
    paint = DEFAULT_PAINT.duplicate()
    matches_played = 0
    matches_won = 0


# ------------------------------------------------------------- economy
func add_money(amount: int) -> void:
    money += amount
    save_game()
    money_changed.emit(money)


func spend(amount: int) -> bool:
    if amount > money:
        return false
    add_money(-amount)
    return true


func add_scrap(kg: int) -> void:
    scrap_kg += kg
    save_game()
    scrap_changed.emit(scrap_kg)


func sell_scrap() -> int:
    var earned := scrap_kg * SCRAP_PRICE_PER_KG
    scrap_kg = 0
    scrap_changed.emit(scrap_kg)
    add_money(earned)
    return earned


func add_part(id: String) -> void:
    inventory.append(id)
    save_game()
    loadout_changed.emit()


func buy_part(id: String) -> bool:
    var price := int(PartDB.stat(id, "price", 0))
    if price > money:
        return false
    inventory.append(id)
    add_money(-price)
    return true


func sell_part(id: String) -> int:
    var i := inventory.find(id)
    if i < 0:
        return 0
    inventory.remove_at(i)
    var value := int(int(PartDB.stat(id, "price", 0)) * SELL_RATIO)
    add_money(value)
    return value


func equip(id: String, slot: String) -> bool:
    var i := inventory.find(id)
    if i < 0 or not PartDB.fits(id, slot):
        return false
    inventory.remove_at(i)
    var old := str(loadout.get(slot, ""))
    if old != "":
        inventory.append(old)
    loadout[slot] = id
    damage.erase(slot)  # swapped-in parts arrive in working order
    save_game()
    loadout_changed.emit()
    return true


# ------------------------------------------------------------- paint
func set_paint_color(channel: String, color: Color, persist: bool = true) -> void:
    paint[channel] = "#" + color.to_html(false)
    if persist:
        save_game()
    paint_changed.emit()


func apply_paint_preset(preset: String) -> void:
    paint = PAINT_PRESETS[preset].duplicate()
    save_game()
    paint_changed.emit()


# ------------------------------------------------------------- damage
func max_hp(slot: String) -> int:
    return int(PartDB.stat(str(loadout.get(slot, "")), "hp", 0))


func current_hp(slot: String) -> int:
    return maxi(0, max_hp(slot) - int(damage.get(slot, 0)))


func repair_cost(slot: String = "") -> int:
    var total := 0
    for s in damage:
        if slot == "" or s == slot:
            total += int(damage[s]) * REPAIR_COST_PER_HP
    return total


func repair(slot: String = "") -> bool:
    var cost := repair_cost(slot)
    if cost == 0 or cost > money:
        return false
    if slot == "":
        damage.clear()
    else:
        damage.erase(slot)
    add_money(-cost)
    loadout_changed.emit()
    return true


func finish_match(won: bool, damage_report: Dictionary, reward: int) -> void:
    matches_played += 1
    if won:
        matches_won += 1
    damage.clear()
    for slot in damage_report:
        var lost := clampi(int(damage_report[slot]), 0, maxi(0, max_hp(slot) - 1))
        if lost > 0:
            damage[slot] = lost
    add_money(reward)


# ------------------------------------------------------------- flow
func go_to(location: String) -> void:
    get_tree().change_scene_to_file(SCENES[location])


# ------------------------------------------------------------- save
func save_game() -> void:
    var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if f == null:
        return
    f.store_string(JSON.stringify({
        "money": money, "scrap_kg": scrap_kg, "inventory": inventory, "loadout": loadout,
        "damage": damage, "paint": paint, "matches_played": matches_played, "matches_won": matches_won,
    }, "  "))


func load_game() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        return
    var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
    if not (data is Dictionary):
        return
    money = int(data.get("money", money))
    scrap_kg = int(data.get("scrap_kg", scrap_kg))
    matches_played = int(data.get("matches_played", 0))
    matches_won = int(data.get("matches_won", 0))
    inventory.clear()
    for id in data.get("inventory", []):
        if PartDB.has_part(str(id)):
            inventory.append(str(id))
    var saved: Dictionary = data.get("loadout", {})
    for slot in SLOTS:
        var id := str(saved.get(slot, loadout.get(slot, "")))
        if id == "" or PartDB.has_part(id):
            loadout[slot] = id
    damage = data.get("damage", {})
    var saved_paint: Dictionary = data.get("paint", {})
    for channel in PAINT_CHANNELS:
        if saved_paint.has(channel):
            paint[channel] = str(saved_paint[channel])


# ------------------------------------------------------------- input
func _setup_input() -> void:
    _bind_key("move_forward", KEY_W)
    _bind_key("move_back", KEY_S)
    _bind_key("turn_left", KEY_A)
    _bind_key("turn_right", KEY_D)
    _bind_key("boost", KEY_SPACE)
    _bind_key("interact", KEY_E)
    _bind_key("center_torso", KEY_C)
    _bind_key("target_cycle", KEY_T)
    _bind_key("pause", KEY_ESCAPE)
    _bind_mouse("fire_primary", MOUSE_BUTTON_LEFT)    # right-arm weapon
    _bind_mouse("fire_secondary", MOUSE_BUTTON_RIGHT)  # left-arm weapon


func _bind_key(action: String, key: Key) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev := InputEventKey.new()
    ev.physical_keycode = key
    InputMap.action_add_event(action, ev)


func _bind_mouse(action: String, button: MouseButton) -> void:
    if not InputMap.has_action(action):
        InputMap.add_action(action)
    var ev := InputEventMouseButton.new()
    ev.button_index = button
    InputMap.action_add_event(action, ev)
