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
    render_preview(f"mech_{tier}_cockpit_view", (0, -1.2, 3.62), (0, -8, 2.3), lens=16, sun=0)  # reuses sun + ground
    save_blend(os.path.join(SOURCE, "mech", f"mech_{tier}.blend"))

# Part stats for the game (single source of truth: the Blender part builders).
os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
with open(os.path.join(ROOT, "data", "parts.json"), "w") as f:
    json.dump({"generated_by": "tools/blender/build_mech.py", "parts": DB}, f, indent=2, sort_keys=True)
print("WROTE data/parts.json")
