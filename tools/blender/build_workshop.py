"""Workshop: the mech dock bay players return to between matches.

The mech stands on a turntable in a docking frame (clamps, repair arms, hoses,
catwalk) and is viewed from the front in third person. Exports:
  assets/models/environments/workshop.glb
Markers (empties) the game uses:
  mech_dock                    where the mech stands (faces the camera)
  cam_overview / cam_upgrade / cam_repair / cam_paint
                               camera shots; Godot camera = marker transform
Lights carry extras {godot_energy, godot_range} for the engine.

    blender -b --factory-startup --python tools/blender/build_workshop.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
import mech_parts as mp
import props as pr

random.seed(7)
reset()

M = dict(
    concrete=mat("concrete", "#7E7C78", 0, .85),
    pad=mat("dock_pad", "#4F5A63", .2, .6),
    wall=mat("wall_panel", "#3E4B5A", .3, .6),
    rib=mat("wall_rib", "#33404D", .4, .55),
    wainscot=mat("wall_lower", "#2A323C", .3, .6),
    ceiling=mat("ceiling", "#23282E", .3, .7),
    steel=mat("steel", "#3A3F47", .8, .4),
    dock=mat("dock_yellow", "#E0A526", .3, .45),
    grate=mat("grating", "#2C3036", .7, .5),
    rubber=mat("rubber", "#1A1A1A", 0, .9),
    lamp=mat("lamp", "#FFF1D6", 0, .3, emit=10),
    screen=mat("screen", "#3CE6FF", 0, .2, emit=4),
    beacon=mat("beacon", "#FF9A2E", 0, .3, emit=8),
    weld=mat("weld_tip", "#9FE8FF", 0, .2, emit=15),
    ring=mat("dock_ring", "#3CE6FF", 0, .2, emit=6),
    accent=mat("accent_orange", "#E8772E", .2, .45),
    red=mat("tool_red", "#C0392B", .3, .45),
    wood=mat("bench_wood", "#9A7148", 0, .8),
)
SOLID = {"collision": "box"}
W, Y0, Y1, H = 28.0, -14.0, 10.0, 8.5


def light(name, loc, energy, color, godot_energy, godot_range, spot_target=None, angle=0.8):
    ob = spot_light(name, loc, spot_target, energy, angle, color) if spot_target else point_light(name, loc, energy, color)
    ob["godot_energy"] = godot_energy
    ob["godot_range"] = godot_range
    return ob


def cyl_seg(name, a, b, r, m, segs=10):
    c, rot, L = seg_xf(a, b)
    return cyl(name, r, L, c, m, rot=rot, segs=segs)


def railing(name, a, b, z, posts=6):
    a, b = Vector(a), Vector(b)
    parts = []
    for i in range(posts + 1):
        p = a + (b - a) * (i / posts)
        parts.append(((.06, .06, 1.0), (p.x, p.y, z + .5)))
    for h in (.5, 1.0):
        c, r, L = seg_xf((a.x, a.y, z + h), (b.x, b.y, z + h))
        parts.append(((.05, .05, L), c, r))
    multi_box(name, parts, M["dock"])


# ------------------------------------------------------------------ shell
use_collection("structure")
box("floor", (W, Y1 - Y0, .3), (0, (Y0 + Y1) / 2, -.15), M["concrete"], bevel=0, props=SOLID)
box("ceiling", (W, Y1 - Y0, .3), (0, (Y0 + Y1) / 2, H + .15), M["ceiling"], bevel=0)


def wall(name, length, center, rotz):
    cx, cy = center
    ob = box(name, (length, .3, H), (cx, cy, H / 2), M["wall"], rot=(0, 0, rotz), bevel=0, props=SOLID)
    ux, uy = math.cos(rotz), math.sin(rotz)          # along the wall
    nx, ny = -uy, ux                                 # inward normal (towards origin)
    if nx * -cx + ny * -cy < 0:
        nx, ny = -nx, -ny
    ribs = []
    n = int(length / .9)
    for i in range(n):
        t = -length / 2 + (i + .5) * length / n
        ribs.append(((.14, .12, H - 1.6), (cx + ux * t + nx * .2, cy + uy * t + ny * .2, H / 2 + .8), (0, 0, rotz)))
    multi_box(name + "_ribs", ribs, M["rib"])
    box(name + "_lower", (length, .2, 1.6), (cx + nx * .2, cy + ny * .2, .8), M["wainscot"], rot=(0, 0, rotz), bevel=0)
    stripes_y, stripes_k = [], []
    for i in range(int(length / .8)):
        t = -length / 2 + (i + .5) * .8
        (stripes_y if i % 2 == 0 else stripes_k).append(
            ((.8, .05, .25), (cx + ux * t + nx * .32, cy + uy * t + ny * .32, 1.45), (0, 0, rotz)))
    multi_box(name + "_stripe_y", stripes_y, mat("hazard_yellow", "#F2C230", 0, .5))
    multi_box(name + "_stripe_k", stripes_k, mat("hazard_black", "#1B1C1E", 0, .6))
    return ob


wall("wall_back", W, (0, Y1), 0)
wall("wall_front", W, (0, Y0), 0)
wall("wall_left", Y1 - Y0, (-W / 2, (Y0 + Y1) / 2), PI / 2)
wall("wall_right", Y1 - Y0, (W / 2, (Y0 + Y1) / 2), PI / 2)
text("bay_sign", "BAY 01", 1.7, (0, Y1 - .45, 6.9), m=M["accent"], extrude=.08)
box("bay_sign_plate", (8.2, .1, 2.4), (0, Y1 - .3, 6.9), M["wainscot"], bevel=.03)

# roof trusses + light panels
trusses = []
for y in range(-12, 10, 4):
    trusses.append(((W, .35, .7), (0, y, H - .4)))
    trusses.append(((W, .2, .2), (0, y, H - 1.2)))
    for x in range(-12, 13, 3):
        c, r, L = seg_xf((x, y, H - 1.2), (x + 1.5, y, H - .4))
        trusses.append(((.12, .12, L), c, r))
multi_box("roof_trusses", trusses, M["steel"])
panels = [((2.6, .7, .12), (x, y + 2, H - 1.5)) for x in (-8, 0, 8) for y in (-10, -2, 6)]
multi_box("ceiling_lamps", panels, M["lamp"])
for i, (x, y) in enumerate([(-8, -8), (0, -8), (8, -8), (-8, 0), (8, 0), (-8, 8), (0, 8), (8, 8)]):
    light(f"ceiling_light_{i}", (x, y, H - 2.0), 700, "#FFF1D6", 1.2, 14)

# ------------------------------------------------------------------ dock pad
use_collection("dock")
box("dock_pad", (10, 10, .06), (0, .5, .03), M["pad"], bevel=0, props=SOLID)
for nm, a, b in (("n", (-5, 5.5), (5, 5.5)), ("s", (-5, -4.5), (5, -4.5)),
                 ("w", (-5, -4.5), (-5, 5.5)), ("e", (5, -4.5), (5, 5.5))):
    hazard_strip(f"pad_edge_{nm}", (*a, 0), (*b, 0), .35, z=.07)
cyl("turntable_glow", 3.25, .05, (0, 0, .085), M["ring"], segs=48)
cyl("turntable", 3.1, .12, (0, 0, .12), M["steel"], segs=48, props=SOLID)
multi_box("turntable_grooves", [((6.0, .06, .02), (0, 0, .185), (0, 0, a * PI / 6)) for a in range(6)], M["grate"])
text("floor_bay_number", "01", 1.6, (0, -3.6, .07), rot=(0, 0, 0), m=mat("floor_paint_white", "#D8D8D0", 0, .7), extrude=.01)
for x in (-5.5, 5.5):
    box(f"lane_{x:+.0f}", (.25, 9, .02), (x, -9.5, .01), mat("hazard_yellow", "#F2C230", 0, .5), bevel=0)

# docking towers: sized to the 4.6 m mech (decks at cockpit height)
DECK_Z = 3.3
for s, side in ((1, "L"), (-1, "R")):
    x = 4.7 * s
    cols = [((.45, .45, 6.4), (x + dx, y, 3.2)) for dx in (-.7, .7) for y in (-.8, 1.8)]
    multi_box(f"tower_{side}_columns", cols, M["dock"], props=SOLID, bevel=.03)
    braces = []
    for z0 in (0.4, DECK_Z + .15):
        for dx in (-.7, .7):
            for a, b in (((x + dx, -.8, z0), (x + dx, 1.8, z0 + 2.75)), ((x + dx, 1.8, z0), (x + dx, -.8, z0 + 2.75))):
                c, r, L = seg_xf(a, b); braces.append(((.12, .12, L), c, r))
    multi_box(f"tower_{side}_braces", braces, M["steel"])
    box(f"tower_{side}_deck", (1.9, 4.2, .12), (x, -.1, DECK_Z), M["grate"], bevel=0, props=SOLID)
    railing(f"tower_{side}_rail_outer", (x + .95 * s, -2.2), (x + .95 * s, 2.0), DECK_Z, posts=5)
    box(f"tower_{side}_cap", (2.0, 3.1, .35), (x, .5, 6.55), M["steel"])
    cyl(f"tower_{side}_beacon", .16, .26, (x, -.8, 6.85), M["beacon"], segs=12)
    light(f"tower_{side}_beacon_light", (x, -1.1, 6.8), 40, "#FF9A2E", .6, 6)
    # eye-level status monitor (a person-sized screen next to a 15 ft machine)
    box(f"tower_{side}_monitor_frame", (.9, .1, .6), (x, -1.12, 1.55), M["steel"], rot=(-.15, 0, 0))
    box(f"tower_{side}_monitor", (.78, .05, .48), (x, -1.18, 1.55), M["screen"], rot=(-.15, 0, 0), bevel=0)
    # docking clamp over the pauldron
    box(f"clamp_{side}_beam", (2.6, .7, .6), (2.95 * s, .1, 5.05), M["dock"], bevel=.05)
    cyl(f"clamp_{side}_piston", .14, .7, (2.05 * s, .05, 4.55), M["steel"], segs=10)
    box(f"clamp_{side}_pad", (.8, .9, .16), (2.05 * s, .05, 4.22), M["rubber"])
    box(f"clamp_{side}_stripe", (2.62, .72, .15), (3.6 * s, .1, 5.05), mat("hazard_black", "#1B1C1E", 0, .6), bevel=0)
    # robotic repair arm on a floor pedestal
    base = (3.5 * s, -1.6, 0)
    cyl(f"repair_arm_{side}_base", .55, .5, (base[0], base[1], .25), M["steel"], segs=16, props=SOLID)
    cyl(f"repair_arm_{side}_turret", .38, .5, (base[0], base[1], .75), M["accent"], segs=12)
    j1, j2, tip = (base[0], base[1], 1.0), (3.2 * s, -1.9, 3.0), (2.35 * s, -2.5, 2.35)
    seg(f"repair_arm_{side}_lower", j1, j2, .34, .34, M["accent"])
    cyl(f"repair_arm_{side}_elbow", .26, .5, j2, M["steel"], rot=(0, PI / 2, 0), segs=12)
    seg(f"repair_arm_{side}_upper", j2, tip, .26, .26, M["accent"])
    cyl_seg(f"repair_arm_{side}_tool", tip, (2.15 * s, -2.65, 2.2), .1, M["steel"])
    cyl(f"repair_arm_{side}_weld", .07, .1, (2.12 * s, -2.68, 2.18), M["weld"], segs=8)
    light(f"repair_arm_{side}_spark", (2.1 * s, -2.8, 2.2), 25, "#9FE8FF", .8, 3)

# gantry across the tower tops + hoses down to the mech's back
box("gantry_beam", (10.6, .8, .7), (0, .5, 6.3), M["dock"], bevel=.05, props=SOLID)
box("gantry_hoist", (1.1, 1.1, .6), (0, .9, 5.65), M["steel"])
multi_box("gantry_stripe", [((.4, .82, .72), (x, .5, 6.3)) for x in (-4, -2.5, -1, 1, 2.5, 4)],
          mat("hazard_black", "#1B1C1E", 0, .6))
for i, (a, b, r, m) in enumerate([((-.7, 1.3, 5.95), (-.45, 1.1, 4.6), .08, M["rubber"]),
                                  ((.7, 1.3, 5.95), (.45, 1.1, 4.6), .08, M["rubber"]),
                                  ((0, 1.3, 5.4), (0, 1.25, 4.0), .1, M["dock"])]):
    cyl_seg(f"hose_{i}", a, b, r, m)

# boarding gangway from the right tower deck to the cockpit (pilot walks this)
box("gangway", (2.5, .9, .1), (-2.5, -1.65, DECK_Z), M["grate"], bevel=0, props=SOLID)
railing("gangway_rail", (-3.75, -2.1), (-1.25, -2.1), DECK_Z, posts=4)
hazard_strip("gangway_edge", (-1.3, -2.1, 0), (-1.3, -1.2, 0), .1, seg_len=.15, z=DECK_Z + .06)

# stairs up to the right tower deck
steps = []
for i in range(13):
    steps.append(((.3, 1.0, .07), (-5.8 - i * .27, .6, DECK_Z - (i + 1) * DECK_Z / 13)))
multi_box("stairs", steps, M["grate"])
for dy in (-.53, .53):
    seg(f"stair_stringer_{dy:+.1f}", (-5.65, .6 + dy, DECK_Z), (-9.4, .6 + dy, 0), .08, .25, M["dock"])
railing("stair_rail", (-5.7, 1.13), (-9.3, 1.13), 0, posts=4)

# ------------------------------------------------------------------ props
use_collection("props")
# workbench + tool cabinet (front left)
box("bench_top", (3.2, 1.2, .1), (-8.5, -6.0, 1.0), M["wood"], props=SOLID)
multi_box("bench_frame", [((.1, .1, 1.0), (-8.5 + dx, -6.0 + dy, .5)) for dx in (-1.5, 1.5) for dy in (-.5, .5)]
          + [((3.1, 1.1, .05), (-8.5, -6.0, .3))], M["steel"])
box("bench_vise", (.3, .4, .25), (-9.6, -6.3, 1.18), M["steel"])
box("toolbox", (.7, .35, .35), (-8.0, -6.1, 1.23), M["red"])
box("tool_cabinet", (1.2, .7, 1.4), (-10.9, -6.0, .7), M["red"], props=SOLID)
multi_box("tool_cabinet_drawers", [((1.0, .02, .03), (-10.9, -6.36, z)) for z in (.3, .55, .8, 1.05, 1.25)],
          M["steel"])
box("pegboard", (3.4, .06, 1.6), (-8.5, -6.65, 2.0), M["wainscot"])
multi_box("pegboard_tools", [((random.uniform(.05, .12), .05, random.uniform(.3, .7)),
                              (-9.9 + i * .3, -6.6, random.uniform(1.6, 2.3))) for i in range(10)], M["steel"])
# drums + crates (front right)
for i, (x, y, c) in enumerate([(8.2, -6.4, "#2F5D8C"), (8.9, -6.0, "#2F5D8C"), (8.5, -5.3, "#B33A2E"),
                               (9.6, -6.6, "#2F5D8C"), (11.8, -2.0, "#B33A2E")]):
    drum(f"drum_{i}", (x, y, 0), c)
for i, (x, y, z, s, r) in enumerate([(11.2, -4.5, 0, 1.4, .1), (11.3, -4.4, 1.4, 1.1, -.2), (11.5, -6.3, 0, 1.0, .4),
                                     (-11.5, 4.0, 0, 1.5, 0), (-11.4, 5.6, 0, 1.5, .1), (-11.5, 4.8, 1.5, 1.2, -.1)]):
    crate(f"crate_{i}", (x, y, z), s, r)
# upgrade terminal kiosk (right)
box("terminal_base", (1.0, .8, 1.1), (6.8, -5.2, .55), M["steel"], props=SOLID)
box("terminal_screen_frame", (1.0, .12, .7), (6.8, -5.45, 1.4), M["steel"], rot=(-.5, 0, 0))
box("terminal_screen", (.85, .05, .55), (6.8, -5.52, 1.42), M["screen"], rot=(-.5, 0, 0), bevel=0)
# shelving along the back wall with parts bins
for sx in (-1, 1):
    x0 = 9.5 * sx
    frame = []
    for dx in (-2.4, 2.4):
        for dy in (-.5, .5):
            frame.append(((.08, .08, 4.2), (x0 + dx, 9.0 + dy, 2.1)))
    for z in (.4, 1.6, 2.8, 4.0):
        frame.append(((4.9, 1.1, .06), (x0, 9.0, z)))
    multi_box(f"shelf_{sx:+d}", frame, M["steel"], props=SOLID)
    for z in (.43, 1.63, 2.83):
        for k in range(4):
            w = random.uniform(.6, 1.0)
            c = random.choice(["#2F5D8C", "#E8772E", "#5A6E5A", "#8A8F96"])
            box(f"bin_{sx:+d}_{z:.0f}_{k}", (w, .8, random.uniform(.4, .9)),
                (x0 - 1.8 + k * 1.2, 9.0, z + .03 + .3), mat("bin_" + c, c, .2, .6), bevel=.02)
# gas bottles
multi_cyl("gas_bottles", [(.14, 1.4, (12.8, y, .7)) for y in (2.0, 2.4, 2.8, 3.2)], mat("gas_green", "#3E7A4E", .3, .5), segs=12)

# human scale: crew, forklift, cones, a person-sized door
pr.human("crew_boarding", (-1.75, -1.65, DECK_Z + .06), PI / 2, pose="tablet", vest="#F2C230", skin=1)
pr.human("crew_chief", (1.3, -3.1, .18), PI, pose="point", vest="#FF6A1A", hat="#FFFFFF", skin=0)
pr.human("crew_deck", (4.6, -1.4, DECK_Z + .06), 0, pose="wave", vest="#F2C230", skin=2)
pr.human("crew_bench", (-8.6, -5.25, 0), PI, pose="stand", vest="#9FE8FF", hat="#2F5D8C", skin=3)
pr.human("crew_terminal", (6.8, -6.0, 0), PI, pose="tablet", vest="#F2C230", skin=0)
pr.forklift("forklift", (9.0, 5.2, 0), PI / 2)
for i, (x, y) in enumerate([(-5.5, -6.0), (-5.5, -8.5), (5.5, -7.2), (6.1, -2.8)]):
    pr.cone(f"cone_{i}", (x, y, 0))
box("side_door", (.08, 1.0, 2.1), (W / 2 - .2, 4.0, 1.05), mat("door_blue", "#2F5D8C", .3, .5), bevel=.01)
box("side_door_frame", (.06, 1.2, 2.25), (W / 2 - .17, 4.0, 1.12), M["steel"], bevel=0)
box("exit_sign", (.05, .5, .18), (W / 2 - .22, 4.0, 2.45), mat("exit_green", "#2EE66B", 0, .3, emit=5), bevel=0)

# ------------------------------------------------------------------ dock lighting
light("key_left", (-6.0, -8.0, 8.5), 3500, "#FFF4E0", 8.0, 30, spot_target=(0, 0, 3.0), angle=0.7)
light("key_right", (6.5, -7.0, 7.5), 2200, "#FFE6C8", 5.0, 30, spot_target=(0, 0, 2.6), angle=0.7)
light("rim_left", (-3.0, 4.5, 6.5), 900, "#5FD8FF", 2.5, 12)
light("rim_right", (3.0, 4.5, 6.5), 900, "#5FD8FF", 2.5, 12)
light("pad_fill", (0, -4.0, 1.0), 250, "#3CE6FF", 1.0, 8)

# ------------------------------------------------------------------ markers
use_collection("markers")
empty("mech_dock", (0, 0, .18), props={"marker": "mech_dock"})
SHOTS = {  # name: (camera position, look-at target); mech sits left of frame for the UI panel
    # eye level (1.7 m) looking up: you stand on the floor next to a 15 ft machine
    "cam_overview": ((2.4, -11.0, 1.7), (2.2, 0, 2.9)),
    "cam_upgrade": ((1.9, -6.8, 1.7), (1.6, 0, 3.3)),
    "cam_repair": ((4.6, -6.6, 1.2), (1.3, 0, 2.6)),
    "cam_paint": ((2.8, -8.8, 1.6), (2.4, 0, 2.9)),
}
for name, (loc, tgt) in SHOTS.items():
    q = (Vector(tgt) - Vector(loc)).to_track_quat('Y', 'Z')  # local +Y -> Godot camera -Z
    empty(name, loc, rot=tuple(q.to_euler()), props={"marker": "camera", "fov": 50})

export_glb(os.path.join(MODELS, "environments", "workshop.glb"))

# ------------------------------------------------------------------ previews (mech added after export)
use_collection("_preview_mech")
mp.assemble(mp.palette("mk1"), loc=(0, 0, .18))
lens = 20.25 / (2 * math.tan(math.radians(25)))  # matches Godot fov 50 (vertical) at 16:9
render_preview("workshop_overview", *SHOTS["cam_overview"], lens=lens, sun=0, world="#1A2028", world_strength=.3)
render_preview("workshop_upgrade", *SHOTS["cam_upgrade"], lens=lens, sun=0, samples=96)
render_preview("workshop_wide", (-10.5, -12.5, 5.8), (0, 1, 2.8), lens=16, sun=0, samples=96)
save_blend(os.path.join(SOURCE, "environments", "workshop.blend"))
