"""Testing grounds: a simple daytime proving range for trying parts and weapons.

Layout (Blender, mech faces -Y from the spawn at the south end):
  * firing lanes north of the spawn with distance markers at 25 / 50 / 75 / 100 / 150 m
    and dummy pads (markers dummy_1..5); a patrol lane for a moving dummy (mover_a -> mover_b)
  * mobility course to the east: ramps, jump platforms (2 / 4 / 6 m), slalom pillars
  * destructible crate and barrel cluster to the west; container cover
  * concrete perimeter with fencing, control tower, floodlights, signage
Markers: mech_spawn, exit_to_workshop, dummy_*, mover_a / mover_b.

    blender -b --factory-startup --python tools/blender/build_testing_grounds.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
import mech_parts as mp
import props as pr

random.seed(5)
reset()
M = dict(
    ground=mat("tg_ground", "#9A968C", 0, .9),
    pad=mat("tg_pad", "#7F7C75", 0, .85),
    line=mat("paint_white", "#D8D8D0", 0, .7),
    yellow=mat("hazard_yellow", "#F2C230", 0, .5),
    black=mat("hazard_black", "#1B1C1E", 0, .6),
    concrete=mat("concrete", "#8C8A84", 0, .85),
    concrete_dark=mat("concrete_dark", "#62605B", 0, .9),
    steel=mat("steel", "#3A3F47", .8, .4),
    orange=mat("accent_orange", "#E8772E", .2, .45),
    blue=mat("tg_blue", "#2F5D8C", .2, .5),
    fence=mat("fence", "#5A5E62", .6, .5, alpha=.55),
    glass=mat("tower_glass", "#9FD8FF", .1, .1, emit=.4),
    lamp=mat("flood_lamp", "#FFF4E0", 0, .3, emit=10),
    sign=mat("sign_board", "#1E252C", .3, .6),
    grass=mat("tg_grass", "#6F8A4E", 0, 1.0),
)
SOLID, CONVEX = {"collision": "box"}, {"collision": "convex"}
W, D = 160.0, 220.0           # ground size (x, y)
SPAWN = (0.0, 80.0)           # south end; mech faces -Y (north) down the range

# ---------------------------------------------------------------- ground
use_collection("ground")
box("ground", (W, D, .4), (0, 0, -.2), M["ground"], bevel=0, props=SOLID)
box("grass_surround", (W + 120, D + 120, .2), (0, 0, -.25), M["grass"], bevel=0)
lines = []
for x in range(-70, 71, 10):
    lines.append(((.08, D - 4, .02), (x, 0, .005)))
for y in range(-100, 101, 10):
    lines.append(((W - 4, .08, .02), (0, y, .005)))
multi_box("grid_lines", lines, M["concrete_dark"])
box("spawn_pad", (14, 14, .05), (SPAWN[0], SPAWN[1], .03), M["pad"], bevel=0)
hazard_strip("spawn_edge_n", (-7, SPAWN[1] - 7, 0), (7, SPAWN[1] - 7, 0), .35, z=.06)
hazard_strip("spawn_edge_s", (-7, SPAWN[1] + 7, 0), (7, SPAWN[1] + 7, 0), .35, z=.06)
text("spawn_text", "TEST GROUNDS", 1.6, (0, SPAWN[1] + 4.5, .06), rot=(0, 0, PI), m=M["line"], extrude=.01)

# ---------------------------------------------------------------- firing lanes (north of spawn)
use_collection("range")
lane_x = [-24, -12, 0, 12, 24]
for x in lane_x[:-1]:
    box(f"lane_divider_{x}", (.3, 160, .03), (x + 6, SPAWN[1] - 85, .015), M["yellow"], bevel=0)
for r in (25, 50, 75, 100, 150):
    y = SPAWN[1] - r
    box(f"range_line_{r}", (60, .4, .03), (0, y, .02), M["line"], bevel=0)
    for s in (-1, 1):
        x = 32 * s
        box(f"range_post_{r}_{s:+d}", (.5, .5, 3.0), (x, y, 1.5), M["orange"], bevel=.05, props=SOLID)
        box(f"range_sign_{r}_{s:+d}", (2.6, .15, 1.4), (x, y, 3.6), M["sign"], bevel=.03)
        text(f"range_text_{r}_{s:+d}", f"{r} m", .8, (x, y + .1, 3.6), rot=(PI / 2, 0, PI), m=M["yellow"], extrude=.02)
# dummy pads + markers (dummies face the spawn = +Y)
DUMMIES = [(-24, 25), (-12, 50), (0, 75), (12, 100), (24, 150)]
for i, (x, r) in enumerate(DUMMIES, start=1):
    y = SPAWN[1] - r
    cyl(f"dummy_pad_{i}", 3.2, .06, (x, y, .03), M["pad"], segs=24)
    ring = []
    for k in range(24):
        a = k * 2 * PI / 24
        ring.append(((.9, .3, .02), (x + 3.1 * math.cos(a), y + 3.1 * math.sin(a), .07), (0, 0, a + PI / 2)))
    multi_box(f"dummy_ring_{i}", ring, M["orange"])
    text(f"dummy_label_{i}", str(i), 1.2, (x, y + 4.2, .07), rot=(0, 0, PI), m=M["line"], extrude=.01)
    empty(f"dummy_{i}", (x, y, .06), rot=(0, 0, PI), props={"marker": "dummy", "range_m": r})
# berm behind the range
box("backstop_berm", (80, 8, 9), (0, SPAWN[1] - 175, 4.5), M["concrete_dark"], bevel=.3, taper=(.9, .4), props=CONVEX)
# moving-target patrol lane at 60 m
y_mv = SPAWN[1] - 60
box("mover_lane", (56, 3, .03), (0, y_mv, .02), M["blue"], bevel=0)
hazard_strip("mover_lane_n", (-28, y_mv - 1.6, 0), (28, y_mv - 1.6, 0), .25, z=.04)
hazard_strip("mover_lane_s", (-28, y_mv + 1.6, 0), (28, y_mv + 1.6, 0), .25, z=.04)
empty("mover_a", (-26, y_mv, .05), props={"marker": "mover"})
empty("mover_b", (26, y_mv, .05), props={"marker": "mover"})

# ---------------------------------------------------------------- mobility course (east)
use_collection("mobility")
CX = 55.0
for i, (y, h) in enumerate([(30, 1.5), (0, 3.0)]):
    L = h / math.tan(math.radians(16))
    box(f"ramp_{i}", (8, L, .5), (CX, y + L / 2, h / 2), M["concrete"], rot=(-math.atan2(h, L), 0, 0), bevel=.05, props=CONVEX)
    box(f"ramp_deck_{i}", (8, 8, h), (CX, y - 4, h / 2), M["concrete"], bevel=.06, props=SOLID)
    hazard_strip(f"ramp_edge_{i}", (CX - 4, y - 8, 0), (CX + 4, y - 8, 0), .3, z=h + .02)
for i, (y, h) in enumerate([(-30, 2.0), (-44, 4.0), (-58, 6.0)]):
    box(f"jump_block_{i}", (9, 9, h), (CX, y, h / 2), M["concrete"] if i % 2 == 0 else M["concrete_dark"], bevel=.08, props=SOLID)
    box(f"jump_block_top_{i}", (8.6, 8.6, .06), (CX, y, h + .03), M["steel"], bevel=0)
    text(f"jump_label_{i}", f"{int(h)} m", 1.4, (CX - 4.6, y, h * .55), rot=(PI / 2, 0, -PI / 2), m=M["yellow"], extrude=.02)
for k in range(7):
    x = CX - 20 + (k % 2) * 6
    y = 40 - k * 14
    p = cyl(f"slalom_pillar_{k}", .8, 6.0, (x - 8, y, 3.0), M["orange"] if k % 2 else M["blue"], segs=12, props=CONVEX)
    multi_cyl(f"slalom_band_{k}", [(.85, .4, (x - 8, y, z)) for z in (1.0, 2.0)], M["black"], p, segs=12)

# ---------------------------------------------------------------- destructibles + cover (west)
use_collection("destructibles")
WX = -52.0
for i in range(10):
    x = WX + random.uniform(-8, 8)
    y = random.uniform(-20, 30)
    crate(f"test_crate_{i}", (x, y, 0), random.choice([1.4, 1.6, 1.8]), random.uniform(0, PI),
          props={"collision": "box", "destructible": True, "hp": 120})
for i in range(8):
    drum(f"test_barrel_{i}", (WX + 6 + random.uniform(-4, 4), -32 + random.uniform(-5, 5), 0), "#B33A2E",
         props={"collision": "box", "destructible": True, "hp": 30, "explosive": True})
for i, (x, y, r, c) in enumerate([(WX - 10, 45, .2, "#2F5D8C"), (WX - 9, 52, .2, "#C88A2E"), (WX + 12, -50, 1.3, "#3E7A4E")]):
    o = box(f"container_{i}", (6.1, 2.44, 2.6), (x, y, 1.3), mat("container_" + c, c, .3, .6), rot=(0, 0, r), bevel=.03,
            props=SOLID)
for i, (x, y, r) in enumerate([(-20, 20, .3), (20, 5, -.4), (-8, -25, .1)]):
    box(f"cover_wall_{i}", (6, 1.6, 3.2), (x, y, 1.6), M["concrete"], rot=(0, 0, r), bevel=.06, taper=(1, .45), props=CONVEX)

# ---------------------------------------------------------------- perimeter, tower, lights
use_collection("perimeter")
posts, panels, barriers = [], [], []
for side, (a, b) in {"n": ((-W / 2, -D / 2), (W / 2, -D / 2)), "s": ((-W / 2, D / 2), (W / 2, D / 2)),
                     "w": ((-W / 2, -D / 2), (-W / 2, D / 2)), "e": ((W / 2, -D / 2), (W / 2, D / 2))}.items():
    a, b = Vector((*a, 0)), Vector((*b, 0))
    n = int((b - a).length / 6)
    ang = math.atan2(b.y - a.y, b.x - a.x)
    for k in range(n + 1):
        p = a.lerp(b, k / n)
        posts.append(((.15, .15, 3.4), (p.x, p.y, 1.7)))
        if k < n:
            q = a.lerp(b, (k + .5) / n)
            panels.append(((6.0, .04, 2.6), (q.x, q.y, 2.1), (0, 0, ang)))
            barriers.append(((6.0, .9, .8), (q.x, q.y, .4), (0, 0, ang)))
multi_box("fence_posts", posts, M["steel"])
multi_box("fence_panels", panels, M["fence"], props={"collision": "mesh"})
multi_box("perimeter_barriers", barriers, M["concrete"], props={"collision": "mesh"})
# control tower behind the spawn
TX, TY = -30.0, SPAWN[1] + 18
box("tower_base", (6, 6, 9), (TX, TY, 4.5), M["concrete"], bevel=.1, props=SOLID)
box("tower_cab", (8, 8, 3.2), (TX, TY, 10.6), M["steel"], bevel=.08)
multi_box("tower_windows", [((7.6, .1, 1.6), (TX, TY - 4.0, 10.8)), ((.1, 7.6, 1.6), (TX + 4.0, TY, 10.8))], M["glass"])
box("tower_roof", (9, 9, .4), (TX, TY, 12.4), M["orange"], bevel=.05)
cyl("tower_antenna", .08, 4.0, (TX + 3, TY + 3, 14.4), M["steel"], segs=6)
pr.human("tower_crew", (TX + 1.5, TY - 3.5, 9.0), PI, pose="tablet")
box("sign_board", (14, .4, 3.2), (0, SPAWN[1] + 14, 4.0), M["sign"], bevel=.05, props=SOLID)
multi_box("sign_legs", [((.4, .4, 2.4), (x, SPAWN[1] + 14, 1.2)) for x in (-5, 5)], M["steel"])
text("sign_text", "TEST GROUNDS", 1.6, (0, SPAWN[1] + 13.75, 4.1), rot=(PI / 2, 0, 0), m=M["yellow"], extrude=.05)
# exit pad back to the workshop (beside the spawn)
EX = (14.0, SPAWN[1] + 2)
cyl("exit_pad", 3.0, .06, (EX[0], EX[1], .03), M["blue"], segs=24)
text("exit_text", "EXIT", 1.2, (EX[0], EX[1], .08), rot=(0, 0, PI), m=M["line"], extrude=.01)
empty("exit_to_workshop", (EX[0], EX[1], .06), props={"marker": "exit"})
for i, (x, y) in enumerate([(-40, 60), (40, 60), (-40, -60), (40, -60)]):
    cyl(f"flood_pole_{i}", .25, 14, (x, y, 7), M["steel"], segs=8)
    box(f"flood_head_{i}", (2.0, .6, 1.0), (x, y, 14.2), M["lamp"], bevel=.05)

use_collection("markers")
empty("mech_spawn", (SPAWN[0], SPAWN[1], .06), rot=(0, 0, 0), props={"marker": "spawn"})   # faces -Y (north, down range)

export_glb(os.path.join(MODELS, "environments", "testing_grounds.glb"))

use_collection("_preview_mechs")
mp.assemble(mp.palette("mk1"), loc=(SPAWN[0], SPAWN[1], .06), name="preview_player")
for i, (x, r) in enumerate(DUMMIES[:3], start=1):
    mp.assemble(mp.palette("scrap"), loc=(x, SPAWN[1] - r, .06), rotz=PI, name=f"preview_dummy_{i}")
render_preview("testing_grounds_overview", (70.0, 150.0, 55.0), (0, 10, 0), lens=24, sun=3.2, sun_rot=(.85, .1, .7),
               world="#A9C2DA", world_strength=.9, samples=64)
render_preview("testing_grounds_range", (6.0, SPAWN[1] + 12.0, 6.0), (0, SPAWN[1] - 60, 2.0), lens=24, sun=0, samples=64)
save_blend(os.path.join(SOURCE, "environments", "testing_grounds.blend"))
