"""Build the starter mech (Mk1): every part as its own .glb plus an assembled mech.

    blender -b --factory-startup --python tools/blender/build_mech.py
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
import mech_parts as mp
import props as pr

TIERS = ["mk1"]
PARTS = [
    ("legs_biped", mp.legs_biped, {}),
    ("torso", mp.torso, {}),
    ("arm_L", mp.arm, {"side": "L"}),
    ("arm_R", mp.arm, {"side": "R"}),
    ("weapon_autocannon", mp.weapon_autocannon, {}),
    ("weapon_ram_fist", mp.weapon_ram_fist, {}),
    ("weapon_missile_pod", mp.weapon_missile_pod, {}),
    ("back_thruster", mp.back_thruster, {}),
]
OUT = os.path.join(MODELS, "mech")
# exterior torso pieces the game hides on the player's own mech when the cockpit interior is shown
COCKPIT_HIDE = {"cockpit", "canopy", "canopy_frame", "canopy_brow", "chin", "chin_vent", "chin_vent_frame", "unit_number",
                "headlight_L", "headlight_L_housing", "headlight_R", "headlight_R_housing", "cockpit_intake_L",
                "cockpit_intake_L_frame", "cockpit_intake_R", "cockpit_intake_R_frame"}
NAMES = {"legs_biped": "Strider Legs", "torso": "Bulwark Torso", "arm_L": "Left Arm", "arm_R": "Right Arm",
         "weapon_autocannon": "Autocannon", "weapon_ram_fist": "Ram Fist", "weapon_missile_pod": "Missile Pod",
         "back_thruster": "Jump Thruster"}
DB = {}

for tier in TIERS:
    for pid, fn, kw in PARTS:
        reset()
        root = fn(mp.palette(tier), **kw)
        stats = {k: root[k] for k in root.keys()}
        stats.update(name=f"{NAMES[pid]} {tier.upper()}", scene=f"res://assets/models/mech/parts/{pid}_{tier}.glb")
        DB[f"{pid}_{tier}"] = stats
        export_glb(os.path.join(OUT, "parts", f"{pid}_{tier}.glb"), hierarchy(root))

    reset()
    mech = mp.assemble(mp.palette(tier))
    export_glb(os.path.join(OUT, f"mech_{tier}_assembled.glb"), hierarchy(mech))
    pr.human("scale_ref", (2.5, .3, 0), -.5, pose="stand")  # preview only: 1.8 m person for scale
    render_preview(f"mech_{tier}_front", (6.0, -9.5, 1.7), (.6, 0, 2.4), lens=35, ground="#6F7378",
                   sun_rot=(0.85, 0.15, -0.5))
    render_preview(f"mech_{tier}_back", (-6.0, 7.5, 5.2), (0, 0, 2.9), lens=40, sun=0)
    render_preview(f"mech_{tier}_closeup", (-3.2, -5.2, 3.6), (-1.0, -1.5, 2.9), lens=40, sun=0)
    # cockpit view: mount the interior on the eye, hide the exterior nose (as the game does), add scenery
    bpy.context.view_layer.update()
    eye = mp.find(mech, "cockpit_camera").matrix_world.translation.copy()
    cockpit = mp.cockpit_interior(mp.palette(tier))
    cockpit.matrix_basis = Matrix.Translation(eye)
    for o in hierarchy(mech):
        # Godot culls back faces so the torso shell around the eye vanishes from inside; Cycles needs it hidden
        if o.name.split(".")[0] in COCKPIT_HIDE or o.name.split(".")[0] == "core":
            o.hide_render = True
    for o in hierarchy(cockpit):
        if o.name.startswith("glass_crack_"):
            o.hide_render = True   # cracks only appear in game as the torso takes damage
    # preview only: sample readouts on the dashboard screens (the game draws live Label3D text there)
    bpy.context.view_layer.update()
    readouts = {"screen_status": ("SYSTEMS\nTORSO [######] 100%\nLEGS  [#####-]  84%\nARM L [######] 100%\nARM R [####--]  71%", .0105),
                "screen_radar": ("SPD  21 km/h   HDG 004\n\nTARGET  26 m   [ ]  +2", .013),
                "screen_weapons": ("WEAPONS\nR AUTOCANNON 112\n   READY\nL RAM        INF\nBOOST [######]", .0105)}
    for o in hierarchy(cockpit):
        key = o.name.split(".")[0]
        if key in readouts:
            body, size = readouts[key]
            tob = text("preview_" + key, body, size, (0, 0, 0), rot=(0, 0, 0), m=mat("screen_text_preview", "#73FFBF", 0, .3, emit=4),
                       extrude=0)
            tob.data.materials.clear(); tob.data.materials.append(mat("screen_text_preview", "#73FFBF", 0, .3, emit=4))
            tob.matrix_world = o.matrix_world @ Matrix.Translation((0, -.002, 0)) @ Euler((PI / 2, 0, 0)).to_matrix().to_4x4()
    enemy = mp.assemble(mp.palette("scrap"), weapon_L="missile_pod", loc=(-3.0, -26.0, 0), rotz=PI + .25, name="preview_enemy")
    for i, (x, y, r) in enumerate([(7, -18, .3), (-9, -34, -.5), (4, -40, .1)]):
        box(f"preview_block_{i}", (6.0, 2.4, 2.6), (x, y, 1.3), mat(f"preview_block_{i}", ["#2F5D8C", "#B33A2E", "#3E7A4E"][i], .3, .6),
            rot=(0, 0, r))
    render_preview(f"mech_{tier}_cockpit_view", tuple(eye), tuple(eye + Vector((0, -10, -.9))),
                   lens=20.25 / (2 * math.tan(math.radians(37.5))), sun=0)   # = Godot fov 75 (vertical)
    render_preview(f"mech_{tier}_cockpit_detail", tuple(eye + Vector((.08, .1, .02))), tuple(eye + Vector((-.15, -1, -.35))),
                   lens=16, sun=0)

    save_blend(os.path.join(SOURCE, "mech", f"mech_{tier}.blend"))
    reset()
    root = mp.cockpit_interior(mp.palette(tier))
    export_glb(os.path.join(OUT, f"cockpit_interior_{tier}.glb"), hierarchy(root))

# Part stats for the game (single source of truth: the Blender part builders).
os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
with open(os.path.join(ROOT, "data", "parts.json"), "w") as f:
    json.dump({"generated_by": "tools/blender/build_mech.py", "parts": DB}, f, indent=2, sort_keys=True)
print("WROTE data/parts.json")
