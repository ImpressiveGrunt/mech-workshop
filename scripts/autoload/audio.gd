extends Node
## Sound playback for every scene. Sounds are synthesized by tools/audio/build_sounds.py into
## assets/audio/*.wav; data/sounds.json (generated) lists each one's bus, base volume, loop flag
## and 3D audible range.
##
##   Audio.play("autocannon", muzzle_pos)        one-shot in 3D (picks _1/_2/_3 variants, varies pitch)
##   Audio.play_2d("ui_click")                   one-shot, non-positional
##   var p = Audio.loop("servo_loop", node)      looping 3D player attached to a node (caller sets volume/pitch)
##   var p = Audio.loop_2d("crowd_loop")         looping non-positional player

const DIR := "res://assets/audio/"
const MANIFEST := "res://data/sounds.json"
const BUSES := ["SFX", "UI", "Ambience"]

var info: Dictionary = {}       # name -> manifest entry
var streams: Dictionary = {}    # name -> AudioStream
var variants: Dictionary = {}   # base name -> [names]
var played: Dictionary = {}     # name -> count (tests / debugging)


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    _setup_buses()
    var data = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
    if not (data is Dictionary):
        push_warning("Audio: no sound manifest - run tools/audio/build_sounds.py")
        return
    info = data.get("sounds", {})
    for key in info:
        var sound_name := String(key)
        var path: String = DIR + sound_name + ".wav"
        if not ResourceLoader.exists(path):
            continue
        var s: AudioStream = load(path)
        if bool(info[sound_name].get("loop", false)) and s is AudioStreamWAV:
            var w := s as AudioStreamWAV
            w.loop_mode = AudioStreamWAV.LOOP_FORWARD
            w.loop_begin = 0
            w.loop_end = int(w.get_length() * w.mix_rate)
        streams[sound_name] = s
        var base: String = sound_name
        var tail: String = sound_name.get_slice("_", sound_name.get_slice_count("_") - 1)
        if tail.is_valid_int():
            base = sound_name.trim_suffix("_" + tail)
        if not variants.has(base):
            variants[base] = []
        variants[base].append(sound_name)


func _setup_buses() -> void:
    for b in BUSES:
        if AudioServer.get_bus_index(b) == -1:
            AudioServer.add_bus()
            var i := AudioServer.bus_count - 1
            AudioServer.set_bus_name(i, b)
            AudioServer.set_bus_send(i, "Master")
    if AudioServer.get_bus_effect_count(0) == 0:
        var limiter: AudioEffect
        if ClassDB.class_exists("AudioEffectHardLimiter"):
            limiter = ClassDB.instantiate("AudioEffectHardLimiter")
        else:
            limiter = AudioEffectLimiter.new()
        AudioServer.add_bus_effect(0, limiter)
    var amb := AudioServer.get_bus_index("Ambience")
    AudioServer.set_bus_volume_db(amb, -2.0)


func has_sound(sound_name: String) -> bool:
    return streams.has(sound_name) or variants.has(sound_name)


func _resolve(sound_name: String) -> String:
    if streams.has(sound_name):
        return sound_name
    var v: Array = variants.get(sound_name, [])
    return v.pick_random() if not v.is_empty() else ""


func _count(n: String) -> void:
    var base := n
    for b in variants:
        if variants[b].has(n):
            base = b
    played[base] = int(played.get(base, 0)) + 1


## One-shot positional sound. volume_db is added to the sound's base volume.
func play(sound_name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer3D:
    var n := _resolve(sound_name)
    var tree := get_tree()
    if n == "" or tree == null or tree.current_scene == null:
        return null
    var e: Dictionary = info[n]
    var p := AudioStreamPlayer3D.new()
    p.stream = streams[n]
    p.bus = str(e.get("bus", "SFX"))
    p.volume_db = float(e.get("volume_db", 0.0)) + volume_db
    p.pitch_scale = pitch * randf_range(0.95, 1.05)
    var r := float(e.get("range", 80.0))
    p.max_distance = r
    p.unit_size = r * 0.12
    p.attenuation_filter_cutoff_hz = 6000.0
    p.attenuation_filter_db = -12.0
    tree.current_scene.add_child(p)
    p.global_position = pos
    p.finished.connect(p.queue_free)
    p.play()
    _count(n)
    return p


## One-shot non-positional sound (UI, announcer, cockpit tones).
func play_2d(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> AudioStreamPlayer:
    var n := _resolve(sound_name)
    if n == "":
        return null
    var e: Dictionary = info[n]
    var p := AudioStreamPlayer.new()
    p.stream = streams[n]
    p.bus = str(e.get("bus", "UI"))
    p.volume_db = float(e.get("volume_db", 0.0)) + volume_db
    p.pitch_scale = pitch
    add_child(p)                 # survives scene changes until finished
    p.finished.connect(p.queue_free)
    p.play()
    _count(n)
    return p


## Looping positional sound attached to a node; starts silent-ish at the base volume + volume_db.
func loop(sound_name: String, parent: Node3D, volume_db: float = 0.0) -> AudioStreamPlayer3D:
    var n := _resolve(sound_name)
    if n == "" or parent == null:
        return null
    var e: Dictionary = info[n]
    var p := AudioStreamPlayer3D.new()
    p.stream = streams[n]
    p.bus = str(e.get("bus", "SFX"))
    p.volume_db = float(e.get("volume_db", 0.0)) + volume_db
    var r := float(e.get("range", 60.0))
    p.max_distance = r
    p.unit_size = r * 0.12
    p.set_meta("base_db", float(e.get("volume_db", 0.0)))
    parent.add_child(p)
    p.play()
    _count(n)
    return p


func loop_2d(sound_name: String, volume_db: float = 0.0, parent: Node = null) -> AudioStreamPlayer:
    var n := _resolve(sound_name)
    if n == "":
        return null
    var e: Dictionary = info[n]
    var p := AudioStreamPlayer.new()
    p.stream = streams[n]
    p.bus = str(e.get("bus", "Ambience"))
    p.volume_db = float(e.get("volume_db", 0.0)) + volume_db
    p.set_meta("base_db", float(e.get("volume_db", 0.0)))
    (parent if parent else get_tree().current_scene).add_child(p)
    p.play()
    _count(n)
    return p


## Set a loop's loudness as a 0..1 level on top of its base volume (0 = silent).
static func set_level(p: Node, level: float, extra_db: float = 0.0) -> void:
    if p == null or not is_instance_valid(p):
        return
    var base := float(p.get_meta("base_db", 0.0))
    p.set("volume_db", base + extra_db + linear_to_db(maxf(level, 0.0001)))
