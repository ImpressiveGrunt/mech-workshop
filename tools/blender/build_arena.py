"""Arena: a night-time industrial colosseum sized for 15 ft (4.6 m) mechs.

116 m floor (radius 58 m): long sightlines, flanking lanes, raised decks reachable
by ramp or jump thruster, and cover spread across three rings.

Layout is point-symmetric around the centre so spawn A and spawn B are fair.
Exports assets/models/environments/arena.glb with:
  markers   spawn_A, spawn_B (mech faces the centre), arena_center
  collision extras {"collision": "box" | "convex" | "mesh"} on solid geometry
  props     extras {"destructible": true, "hp": n, "explosive": bool} on crates / barrels
  colliders wreck "*_collider" boxes (hidden in game, used as static collision)
  lights    extras {godot_energy, godot_range}

    blender -b --factory-startup --python tools/blender/build_arena.py
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import *
import mech_parts as mp
import props as pr

random.seed(11)
reset()

R = 58.0                 # playable floor radius (116 m across: room to boost, flank and kite)
S = R / 38.0             # spread factor for the original cover layout
SPAWN_R = R - 8.0
WALL_H = 8.0             # blast wall height (mechs are 4.6 m)
GATE_HALF = math.asin(6.2 / (R + 1.0))   # ~12 m gate opening at any radius
GATES = {"A": -PI / 2, "B": PI / 2}   # south / north
M = dict(
    floor=mat("arena_floor", "#7C7A75", 0, .85),
    floor_dark=mat("arena_floor_dark", "#5A5853", 0, .9),
    line_w=mat("paint_white", "#D8D8D0", 0, .7),
    line_y=mat("hazard_yellow", "#F2C230", 0, .5),
    black=mat("hazard_black", "#1B1C1E", 0, .6),
    scorch=mat("scorch", "#1E1C1A", 0, 1.0),
    wall=mat("wall_steel_blue", "#2E3A46", .5, .5),
    wall_dark=mat("wall_dark", "#1E252C", .5, .55),
    impact=mat("impact_panel", "#C8372D", .2, .6),
    concrete=mat("concrete", "#8C8A84", 0, .85),
    concrete_dark=mat("concrete_dark", "#62605B", 0, .9),
    steel=mat("steel", "#3A3F47", .8, .4),
    glass=mat("blast_glass", "#9FD8FF", .1, .05, alpha=.18),
    lamp=mat("flood_lamp", "#FFF4E0", 0, .3, emit=20),
    glow_blue=mat("glow_blue", "#3CE6FF", 0, .2, emit=6),
    glow_red=mat("glow_red", "#FF3B2E", 0, .2, emit=8),
    glow_green=mat("glow_green", "#2EE66B", 0, .2, emit=8),
    screen=mat("jumbotron_screen", "#123A66", 0, .3, emit=2.5),
    screen_text=mat("jumbotron_text", "#FFFFFF", 0, .3, emit=6),
    orange=mat("accent_orange", "#E8772E", .2, .45),
    banner_red=mat("banner_red", "#A8262B", 0, .8),
    banner_blue=mat("banner_blue", "#244C8A", 0, .8),
    seat_a=mat("seat_blue", "#2F5D8C", .1, .6),
    seat_b=mat("seat_orange", "#D96A2B", .1, .6),
    seat_c=mat("seat_grey", "#6E747A", .1, .6),
)
SOLID, CONVEX, MESHCOL = {"collision": "box"}, {"collision": "convex"}, {"collision": "mesh"}


def polar(r, a, z=0.0):
    return (r * math.cos(a), r * math.sin(a), z)


def in_gate(a, pad=0.0):
    for g in GATES.values():
        d = (a - g + PI) % (2 * PI) - PI
        if abs(d) < GATE_HALF + pad:
            return True
    return False


def light(name, loc, energy, color, godot_energy, godot_range, target=None, angle=0.8):
    ob = spot_light(name, loc, target, energy, angle, color) if target else point_light(name, loc, energy, color)
    ob["godot_energy"] = godot_energy
    ob["godot_range"] = godot_range
    return ob


def mirror(fn, name, loc, *args, scale=True, **kw):
    """Place something and its point-mirrored twin (x, y) -> (-x, -y).
    scale=True spreads the original 38 m layout out to the current radius."""
    if scale:
        loc = (loc[0] * S, loc[1] * S, loc[2])
    fn(name, loc, *args, **kw, _twin=False)
    fn(name, loc, *args, **kw, _twin=True)


def lw(origin, rotz, lx, ly, lz=0.0):
    c, s = math.cos(rotz), math.sin(rotz)
    return (origin[0] + lx * c - ly * s, origin[1] + lx * s + ly * c, origin[2] + lz)


# ================================================================== floor
use_collection("floor")
cyl("floor", R + 1.0, .5, (0, 0, -.25), M["floor"], segs=64, props=SOLID)
# expansion-joint grid
lines = []
for k in range(-int(R / 4) - 1, int(R / 4) + 2):
    v = k * 4.0
    half = math.sqrt(max(0.0, R * R - v * v))
    if half > 1:
        lines.append(((2 * half, .06, .02), (0, v, .005)))
        lines.append(((.06, 2 * half, .02), (v, 0, .005)))
multi_box("floor_joints", lines, M["floor_dark"])
# a few darker replacement slabs
multi_box("floor_patches", [((4, 4, .02), (4 * random.randint(-11, 11) + 2, 4 * random.randint(-11, 11) + 2, .008))
                            for _ in range(50)], M["floor_dark"])
# painted rings (segment strips) + sector lines


def ring_strip(name, r, width, m, n=96, z=.012, skip_gates=False):
    parts = []
    for i in range(n):
        a = 2 * PI * (i + .5) / n
        if skip_gates and in_gate(a, .02):
            continue
        parts.append(((2 * PI * r / n * 1.02, width, .02), polar(r, a, z), (0, 0, a + PI / 2)))
    multi_box(name, parts, m)


ring_strip("ring_outer_yellow", R - 1.6, .35, M["line_y"], skip_gates=True)
ring_strip("ring_outer_white", R - 2.3, .15, M["line_w"], skip_gates=True)
ring_strip("ring_mid", 24.0, .25, M["line_w"], n=96)
for k in range(8):
    a = k * PI / 4 + PI / 8
    c, r, L = seg_xf(polar(25, a, .012), polar(R - 2.6, a, .012))
    box(f"sector_line_{k}", (.18, .02, L), c, M["line_w"], rot=r, bevel=0)
# scorch marks + drains
multi_cyl("scorch_marks", [(random.uniform(.8, 2.6), .01, polar(random.uniform(8, R - 4), random.uniform(0, 2 * PI), .015))
                           for _ in range(40)], M["scorch"], segs=10)
for k in range(12):
    a = k * PI / 6 + PI / 12
    if in_gate(a, .1):
        continue
    p = polar(R - .9, a, .02)
    box(f"drain_{k}", (1.6, .6, .03), p, M["black"], rot=(0, 0, a + PI / 2), bevel=0)
    multi_box(f"drain_slats_{k}", [((.05, .55, .04), lw(p, a + PI / 2, dx, 0, .005)) for dx in (-.6, -.3, 0, .3, .6)],
              M["steel"])

# spawn pads
for g, a in GATES.items():
    p = polar(SPAWN_R, a)
    cyl(f"spawn_pad_glow_{g}", 3.3, .03, (p[0], p[1], .02), M["glow_blue"] if g == "A" else M["glow_red"], segs=40)
    cyl(f"spawn_pad_{g}", 3.0, .05, (p[0], p[1], .03), M["floor_dark"], segs=40)
    text(f"spawn_letter_{g}", g, 2.4, (p[0], p[1], .06), rot=(0, 0, a - PI / 2 if g == "B" else a + PI / 2),
         m=M["line_w"], extrude=.01)

# ================================================================== walls, blast glass, banners
use_collection("walls")
N = int(60 * S)
seg_w = 2 * PI * (R + 1.0) / N
walls, impacts, buttress, caps, bands_y, bands_k, glass = [], [], [], [], [], [], []
lamps = []
for i in range(N):
    a = 2 * PI * (i + .5) / N
    if in_gate(a):
        continue
    rot = (0, 0, a + PI / 2)
    walls.append(((seg_w + .05, 1.2, WALL_H), polar(R + 1.6, a, WALL_H / 2), rot))
    impacts.append(((seg_w * .82, .25, 4.2), polar(R + .9, a, 3.4), rot))
    (bands_y if i % 2 == 0 else bands_k).append(((seg_w, .3, .7), polar(R + .9, a, .35), rot))
    caps.append(((seg_w + .05, 2.0, .45), polar(R + 1.6, a, WALL_H + .22), rot))
    glass.append(((seg_w, .12, 3.2), polar(R + 1.0, a, WALL_H + 2.05), rot))
    ab = a + PI / N
    if not in_gate(ab, .03):
        buttress.append(((.9, 1.0, WALL_H + .3), polar(R + .7, ab, (WALL_H + .3) / 2), (0, 0, ab + PI / 2)))
        buttress.append(((.18, .18, 3.4), polar(R + .95, ab, WALL_H + 2.0), (0, 0, ab + PI / 2)))
        if i % 3 == 0:
            lamps.append(((.6, .3, .25), polar(R + .15, ab, WALL_H - .6), (0, 0, ab + PI / 2)))
multi_box("wall_panels", walls, M["wall"], props=MESHCOL)
multi_box("wall_impact_panels", impacts, M["impact"])
multi_box("wall_base_band_yellow", bands_y, M["line_y"])
multi_box("wall_base_band_black", bands_k, M["black"])
multi_box("wall_buttresses", buttress, M["wall_dark"])
multi_box("wall_caps", caps, M["steel"])
multi_box("blast_glass", glass, M["glass"], props=MESHCOL)
multi_box("wall_lamps", lamps, M["lamp"])
# hanging banners with a white hex emblem
for k in range(14):
    a = 2 * PI * (k + .25) / 14
    if in_gate(a, .12):
        continue
    m = M["banner_red"] if k % 2 else M["banner_blue"]
    box(f"banner_{k}", (2.2, .06, 3.6), polar(R + .72, a, 5.6), m, rot=(0, 0, a + PI / 2), bevel=0)
    cyl(f"banner_emblem_{k}", .6, .03, polar(R + .68, a, 5.9), M["line_w"], rot=(PI / 2, 0, a + PI / 2), segs=6)
# sponsor boards along the wall top (fictional)
for k, name in enumerate(["SCRAP & SONS", "VOLTWORKS", "HAMMER CO", "IRONLINE", "RUSTBUCKET", "GEARHEAD"]):
    a = k * PI / 3 + PI / 6
    p = polar(R + .78, a, 7.3)
    box(f"sponsor_board_{k}", (7.0, .1, 1.0), p, M["wall_dark"], rot=(0, 0, a + PI / 2), bevel=0)
    tp = polar(R + .7, a, 7.3)
    text(f"sponsor_text_{k}", name, .55, tp, rot=(PI / 2, 0, a + PI / 2 + PI), m=M["screen_text"], extrude=.01)

# ================================================================== gates + tunnels
use_collection("gates")
for g, a in GATES.items():
    rot = (0, 0, a + PI / 2)
    inward = a + PI
    for side in (-1, 1):
        ga = a + side * (GATE_HALF + .012)
        box(f"gate_{g}_pillar_{side:+d}", (2.2, 2.6, WALL_H + 3.5), polar(R + 1.6, ga, (WALL_H + 3.5) / 2), M["wall_dark"],
            rot=rot, props=SOLID)
        multi_box(f"gate_{g}_pillar_stripes_{side:+d}",
                  [((2.25, 2.65, .35), polar(R + 1.6, ga, z)) for z in (1.0, 2.0, 3.0)], M["line_y"], )
        cyl(f"gate_{g}_light_{side:+d}", .35, .3, polar(R + .2, ga, WALL_H + 1.2), M["glow_green" if g == "A" else "glow_red"],
            rot=(PI / 2, 0, a + PI / 2), segs=12)
    box(f"gate_{g}_header", (12.8, 2.6, 3.0), polar(R + 1.6, a, WALL_H + 2.0), M["wall_dark"], rot=rot, props=SOLID)
    text(f"gate_{g}_letter", g, 2.4, polar(R + .25, a, WALL_H + 2.0), rot=(PI / 2, 0, a - PI / 2),
         m=M["glow_blue"] if g == "A" else M["glow_red"], extrude=.1)
    for side in (-1, 1):  # blast doors (closed), chevrons, pistons
        dc = lw(polar(R + 1.9, a), a + PI / 2, side * 3.0, 0, 4.0)
        box(f"gate_{g}_door_{side:+d}", (5.9, .7, 8.0), dc, M["orange"], rot=rot, bevel=.05, props=SOLID)
        chev = []
        for k in range(3):
            z = 2.2 + k * 1.9
            chev.append(((.5, .75, 2.2), lw(polar(R + 1.85, a), a + PI / 2, side * 3.0 - side * .7, 0, z), (0, 0, 0)))
        for c in chev:
            box(f"gate_{g}_chevron_{side:+d}_{c[1][2]:.0f}", (2.6, .74, .45), c[1], M["black"],
                rot=(0, side * .7, a + PI / 2), bevel=0)
        piston_a = lw(polar(R + 1.5, a), a + PI / 2, side * 5.6, 0, 6.6)
        piston_b = lw(polar(R + 1.5, a), a + PI / 2, side * 1.6, 0, 7.4)
        c, r, L = seg_xf(piston_a, piston_b)
        cyl(f"gate_{g}_piston_{side:+d}", .14, L, c, M["steel"], rot=r, segs=10)
    # tunnel behind the gate, under the stands
    tc = polar(R + 10, a, 0)
    box(f"tunnel_{g}_floor", (13, 16, .3), (tc[0], tc[1], -.1), M["concrete_dark"], rot=rot, bevel=0)
    for side in (-1, 1):
        box(f"tunnel_{g}_wall_{side:+d}", (1.0, 16, 9.5), lw(tc, a + PI / 2, side * 6.8, 0, 4.75), M["concrete_dark"],
            rot=rot, bevel=0, props=SOLID)
        multi_box(f"tunnel_{g}_lights_{side:+d}", [((.2, 1.2, .2), lw(tc, a + PI / 2, side * 6.2, y, 6.5))
                                                   for y in (-5, 0, 5)], M["lamp"], )
    box(f"tunnel_{g}_ceiling", (14.6, 16, 1.0), (tc[0], tc[1], 9.8), M["concrete_dark"], rot=rot, bevel=0)
    box(f"gatehouse_{g}", (18, 14, 8.0), polar(R + 10, a, 14.3), M["concrete"], rot=rot, bevel=.1)
    text(f"gatehouse_{g}_letter", f"GATE {g}", 2.0, polar(R + 2.9, a, 14.8), rot=(PI / 2, 0, a - PI / 2),
         m=M["screen_text"], extrude=.05)

# ================================================================== stands + crowd
use_collection("stands")
TIERS, T0_R, T0_Z, T_DEPTH, T_RISE = 9, R + 3.2, 8.6, 1.4, 1.0
N2 = int(96 * S)
crowd_shirts = ["#C8372D", "#2F5D8C", "#F2C230", "#E8772E", "#3E7A4E", "#D8D8D0", "#6B4E9B"]
crowd = {c: [] for c in crowd_shirts}
heads = {k: [] for k in range(4)}
seats = {"a": [], "b": [], "c": []}
for t in range(TIERS):
    r = T0_R + t * T_DEPTH
    z = T0_Z + t * T_RISE
    tiers = []
    for i in range(N2):
        a = 2 * PI * (i + .5) / N2
        if in_gate(a, .1):
            continue
        tiers.append(((2 * PI * r / N2 * 1.03, T_DEPTH + .05, z), polar(r, a, z / 2), (0, 0, a + PI / 2)))
    multi_box(f"stand_tier_{t}", tiers, M["concrete"] if t % 2 == 0 else M["concrete_dark"])
    n_seats = int(2 * PI * r / .62)
    for i in range(n_seats):
        a = 2 * PI * (i + .5) / n_seats
        if in_gate(a, .1):
            continue
        sector = int((a % (2 * PI)) / (PI / 6))
        key = "abc"[sector % 3]
        seats[key].append(((.5, .45, .12), polar(r - .25, a, z + .25), (0, 0, a + PI / 2)))
        if random.random() < .68:
            shirt = random.choice(crowd_shirts)
            bob = random.uniform(-.05, .12)                       # some stand, some sit
            crowd[shirt].append(((.42, .3, .62), polar(r - .2, a, z + .62 + bob), (0, 0, a + PI / 2)))
            heads[random.randrange(4)].append(((.22, .22, .24), polar(r - .2, a, z + 1.08 + bob), (0, 0, a + PI / 2)))
for key, parts in seats.items():
    multi_box(f"seats_{key}", parts, M["seat_" + key])
for c, parts in crowd.items():
    multi_box(f"crowd_{c[1:]}", parts, mat("crowd_" + c, c, 0, .8))
for k, parts in heads.items():
    multi_box(f"crowd_heads_{k}", parts, mat(f"skin_{k}", pr.SKIN[k], 0, .6))
# railings at the front of the stands + back wall
ring_strip("stand_front_rail", T0_R - .75, .08, M["line_y"], n=N2, z=T0_Z + 1.0)
back_r = T0_R + TIERS * T_DEPTH
outer = []
for i in range(N2):
    a = 2 * PI * (i + .5) / N2
    outer.append(((2 * PI * back_r / N2 * 1.03, 1.0, T0_Z + TIERS * T_RISE + 3), polar(back_r + .4, a, (T0_Z + TIERS * T_RISE + 3) / 2),
                  (0, 0, a + PI / 2)))
multi_box("stand_back_wall", outer, M["wall"])
# announcer booth (east)
bp = polar(back_r - 1.5, 0, T0_Z + TIERS * T_RISE + 1.6)
box("booth", (4.0, 9.0, 3.2), bp, M["wall_dark"], bevel=.06)
box("booth_glass", (.1, 8.4, 1.8), (bp[0] - 2.05, bp[1], bp[2] + .3), M["glass"], bevel=0)
box("booth_glow", (.05, 8.2, 1.6), (bp[0] - 1.8, bp[1], bp[2] + .3), M["glow_blue"], bevel=0)
text("booth_sign", "LIVE", .8, (bp[0] - 2.1, bp[1], bp[2] + 1.9), rot=(PI / 2, 0, -PI / 2), m=M["glow_red"], extrude=.05)

# ================================================================== light towers + jumbotron
use_collection("lights")
TOWER_R, TOWER_H = R + 24, 40.0
heads_pos = []
for k in range(4):
    a = PI / 4 + k * PI / 2
    base = polar(TOWER_R, a)
    posts, braces = [], []
    for dx in (-1.2, 1.2):
        for dy in (-1.2, 1.2):
            posts.append(((.35, .35, TOWER_H), (base[0] + dx, base[1] + dy, TOWER_H / 2)))
    for z0 in range(0, int(TOWER_H) - 3, 4):
        for (ax, ay), (bx, by) in [((-1.2, -1.2), (1.2, -1.2)), ((1.2, -1.2), (1.2, 1.2)), ((1.2, 1.2), (-1.2, 1.2)),
                                   ((-1.2, 1.2), (-1.2, -1.2))]:
            c, r, L = seg_xf((base[0] + ax, base[1] + ay, z0), (base[0] + bx, base[1] + by, z0 + 4))
            braces.append(((.12, .12, L), c, r))
    multi_box(f"light_tower_{k}_posts", posts, M["steel"], props=SOLID)
    multi_box(f"light_tower_{k}_braces", braces, M["steel"])
    face = a + PI
    hp = polar(TOWER_R - 1.5, a, TOWER_H + 2.5)
    box(f"light_tower_{k}_frame", (9.0, .8, 5.0), hp, M["wall_dark"], rot=(-.45, 0, face - PI / 2 + PI), bevel=.05)
    lamps = []
    for ix in range(4):
        for iz in range(3):
            lamps.append(((1.6, .2, 1.1), lw(polar(TOWER_R - 2.0, a, TOWER_H + 2.5), face + PI / 2, (ix - 1.5) * 2.0, 0,
                                             (iz - 1) * 1.4), (-.45, 0, face - PI / 2 + PI)))
    multi_box(f"light_tower_{k}_lamps", lamps, M["lamp"])
    light(f"floodlight_{k}", polar(TOWER_R - 3.0, a, TOWER_H + 2.0), 600000, "#FFF4E0", 20.0, 160,
          target=polar(16, a + PI, 0), angle=1.35)  # aimed past centre: wide cones cover the far side
    heads_pos.append(polar(TOWER_R - 1.5, a, TOWER_H + 4.5))
# jumbotron hanging over the centre on cables
JZ = 30.0
box("jumbotron_core", (7.4, 7.4, 4.4), (0, 0, JZ), M["wall_dark"], bevel=.1)
for k in range(4):
    a = k * PI / 2
    box(f"jumbotron_screen_{k}", (6.6, .1, 3.6), polar(3.75, a, JZ), M["screen"], rot=(0, 0, a + PI / 2), bevel=0)
    text(f"jumbotron_text_{k}", "ARENA", 1.15, polar(3.82, a, JZ + .5), rot=(PI / 2, 0, a + PI / 2), m=M["screen_text"],
         extrude=.02)
    text(f"jumbotron_vs_{k}", "A  VS  B", .7, polar(3.82, a, JZ - .9), rot=(PI / 2, 0, a + PI / 2), m=M["glow_blue"],
         extrude=.02)
multi_box("jumbotron_trim", [((7.8, 7.8, .3), (0, 0, JZ + 2.35)), ((7.8, 7.8, .3), (0, 0, JZ - 2.35))], M["steel"])
cyl("jumbotron_ring_light", 3.2, .2, (0, 0, JZ - 2.6), M["glow_blue"], segs=24)
for k, hp in enumerate(heads_pos):
    c, r, L = seg_xf((hp[0] * .1, hp[1] * .1, JZ + 2.5), hp)
    cyl(f"jumbotron_cable_{k}", .06, L, c, M["steel"], rot=r, segs=6)
light("jumbotron_glow", (0, 0, JZ - 3.5), 6000, "#3CE6FF", 2.5, 40)

# ================================================================== cover (point-symmetric)
use_collection("cover")
# central hex platform with ramps (blocks the direct spawn-to-spawn line of fire)
cyl("platform", 6.5, 1.4, (0, 0, .7), M["concrete"], segs=6, props=CONVEX)
cyl("platform_top", 6.3, .1, (0, 0, 1.45), M["steel"], segs=6)
cyl("platform_emblem", 3.6, .02, (0, 0, 1.51), M["orange"], segs=6)
cyl("platform_emblem_core", 2.4, .03, (0, 0, 1.52), M["black"], segs=6)
text("platform_number", "07", 1.6, (0, 0, 1.54), rot=(0, 0, 0), m=M["line_w"], extrude=.01)
for s in (-1, 1):
    box(f"ramp_{s:+d}", (5.0, 4.0, .5), (s * 8.4, 0, .55), M["concrete_dark"], rot=(0, s * .3, 0), props=CONVEX)
    hazard_strip(f"ramp_edge_{s:+d}", (s * 6.2, -2, 0), (s * 6.2, 2, 0), .3, z=1.52)
multi_box("platform_bollards", [((.5, .5, 1.0), polar(5.9, k * PI / 3 + PI / 6, 1.95)) for k in range(6) if k % 3 != 0],
          M["line_y"])


def container(name, loc, rotz, color, _twin=False):
    if _twin:
        loc, rotz, name = (-loc[0], -loc[1], loc[2]), rotz + PI, name + "_b"
    m = mat("container_" + color, color, .3, .6)
    dark = mat("container_dark_" + color, color, .3, .7)
    o = (loc[0], loc[1], loc[2])
    body = box(name, (6.1, 2.44, 2.6), lw(o, rotz, 0, 0, 1.3), m, rot=(0, 0, rotz), bevel=.03, props=SOLID)
    ribs = []
    for k in range(15):
        lx = -2.8 + k * .4
        for ly in (-1.24, 1.24):
            ribs.append(((.12, .06, 2.4), lw(o, rotz, lx, ly, 1.3), (0, 0, rotz)))
    multi_box(name + "_ribs", ribs, dark, body)
    box(name + "_doors", (.06, 2.3, 2.45), lw(o, rotz, 3.06, 0, 1.3), dark, body, rot=(0, 0, rotz), bevel=0)
    multi_box(name + "_door_bars", [((.08, .06, 2.4), lw(o, rotz, 3.1, ly, 1.3), (0, 0, rotz)) for ly in (-.85, -.35, .35, .85)],
              M["steel"], body)
    multi_box(name + "_corners", [((.2, .2, .2), lw(o, rotz, lx, ly, z), (0, 0, rotz)) for lx in (-2.95, 2.95)
                                  for ly in (-1.12, 1.12) for z in (.1, 2.5)], M["black"], body)


def blast_wall(name, loc, rotz, _twin=False):
    if _twin:
        loc, rotz, name = (-loc[0], -loc[1], loc[2]), rotz + PI, name + "_b"
    o = (loc[0], loc[1], 0)
    w = box(name, (6.0, 1.6, 3.4), lw(o, rotz, 0, 0, 1.7), M["concrete"], rot=(0, 0, rotz), bevel=.06, taper=(1, .4),
            props=CONVEX)
    box(name + "_foot", (6.1, 2.4, .5), lw(o, rotz, 0, 0, .25), M["concrete_dark"], w, rot=(0, 0, rotz), bevel=.04)
    multi_box(name + "_band", [((1.0, 1.0, .3), lw(o, rotz, lx, 0, 2.9), (0, 0, rotz)) for lx in (-2.5, -.5, 1.5)],
              M["line_y"], w)
    multi_cyl(name + "_loops", [(.12, .25, lw(o, rotz, lx, 0, 3.5), (PI / 2, 0, rotz)) for lx in (-1.8, 1.8)],
              M["steel"], w, segs=8)
    for i in range(random.randint(1, 3)):  # battle damage chips
        box(f"{name}_chip_{i}", (random.uniform(.4, .9), .3, random.uniform(.3, .6)),
            lw(o, rotz, random.uniform(-2.4, 2.4), -.45, random.uniform(1.0, 2.6)), M["concrete_dark"], w,
            rot=(random.uniform(-.3, .3), 0, rotz), bevel=0)


def pillar(name, loc, _twin=False):
    if _twin:
        loc, name = (-loc[0], -loc[1], 0), name + "_b"
    x, y, _ = loc
    p = cyl(name, 1.6, 10.0, (x, y, 5.0), M["concrete"], segs=12, props=CONVEX)
    multi_cyl(name + "_bands", [(1.65, .5, (x, y, z)) for z in (1.0, 2.0)], M["line_y"], p, segs=12)
    multi_cyl(name + "_bands_k", [(1.65, .5, (x, y, z)) for z in (1.5, 2.5)], M["black"], p, segs=12)
    cyl(name + "_cap", 1.9, .5, (x, y, 10.25), M["steel"], p, segs=12)
    cyl(name + "_lamp", .5, .3, (x, y, 10.6), M["glow_red"], p, segs=10)


def tank_trap(name, loc, rotz, _twin=False):
    if _twin:
        loc, rotz, name = (-loc[0], -loc[1], 0), rotz + PI, name + "_b"
    x, y, _ = loc
    parts = [((3.0, .35, .35), (x, y, 1.0), (0, .62, rotz + b)) for b in (0, 2 * PI / 3, 4 * PI / 3)]
    multi_box(name, parts, M["steel"], props=CONVEX)


def crate_stack(name, loc, _twin=False):
    if _twin:
        loc, name = (-loc[0], -loc[1], 0), name + "_b"
    x, y, _ = loc
    props = {"collision": "box", "destructible": True, "hp": 120}
    for i, (dx, dy, z, s) in enumerate([(0, 0, 0, 1.6), (1.7, .2, 0, 1.6), (.8, 0, 1.6, 1.5), (.3, 1.7, 0, 1.4)]):
        crate(f"{name}_{i}", (x + dx, y + dy, z), s, random.uniform(-.2, .2), props=dict(props))


def barrels(name, loc, _twin=False):
    if _twin:
        loc, name = (-loc[0], -loc[1], 0), name + "_b"
    x, y, _ = loc
    for i, (dx, dy) in enumerate([(0, 0), (.7, .1), (.3, .65)]):
        drum(f"{name}_{i}", (x + dx, y + dy, 0), "#B33A2E",
             props={"collision": "box", "destructible": True, "hp": 30, "explosive": True})
    box(f"{name}_sign", (.05, .6, .6), (x - .45, y, 1.4), M["line_y"], rot=(0, 0, PI / 4), bevel=0)


def wreck(name, loc, rotz, _twin=False):
    """Burnt-out mech from an earlier bout, used as cover."""
    if _twin:
        loc, rotz, name = (-loc[0], -loc[1], 0), rotz + PI, name + "_b"
    pal = mp.palette("wreck")
    t = mp.torso(pal)
    t.matrix_basis = Matrix.LocRotScale(Vector((loc[0], loc[1], .9)), Euler((-1.35, .2, rotz)), None)
    l = mp.legs_biped(pal)
    l.matrix_basis = Matrix.LocRotScale(Vector(lw((loc[0], loc[1], 0), rotz, 2.6, -1.0, -.25)), Euler((0, 1.45, rotz + .5)),
                                        None)
    a = mp.arm(pal, "L")
    a.matrix_basis = Matrix.LocRotScale(Vector(lw((loc[0], loc[1], 0), rotz, -2.2, 1.6, 1.2)), Euler((.3, -.8, rotz + 2.0)),
                                        None)
    for root in (t, l, a):
        root.name = f"{name}_{root.name}"
        root["wreck"] = True
        for o in hierarchy(root):
            if o.name.endswith("_collider") or ".0" in o.name and "_collider" in o.name:
                o["collision"] = "box"
    multi_cyl(name + "_scorch", [(3.5, .01, (loc[0], loc[1], .018))], M["scorch"], segs=12)


GX, GY = 13.0 * (S - 1), -10.3 * (S - 1)  # stacked group moves as a unit
mirror(container, "container_1", (13.0 + GX, -9.0 + GY, 0), .35, "#2F5D8C", scale=False)
mirror(container, "container_2", (13.3 + GX, -11.6 + GY, 0), .35, "#B33A2E", scale=False)
mirror(container, "container_3", (13.1 + GX, -10.3 + GY, 2.6), .38, "#3E7A4E", scale=False)
mirror(container, "container_4", (-20.0, -14.0, 0), -.9, "#C88A2E")
mirror(blast_wall, "blast_wall_1", (22.0, 4.0, 0), PI / 2 - .2)
mirror(blast_wall, "blast_wall_2", (7.0, -17.5, 0), .15)
mirror(blast_wall, "blast_wall_3", (-9.0, -20.0, 0), -.25)
mirror(blast_wall, "blast_wall_4", (-25.0, 3.0, 0), PI / 2 + .3)
mirror(pillar, "pillar_1", (24.0, 18.0, 0))
mirror(pillar, "pillar_2", (-24.0, 18.0, 0))
mirror(tank_trap, "tank_trap_1", (4.0, -24.0, 0), .2)
mirror(tank_trap, "tank_trap_2", (-4.5, -26.0, 0), .9)
mirror(tank_trap, "tank_trap_3", (30.0, -4.0, 0), .5)
mirror(tank_trap, "tank_trap_4", (-30.0, -6.0, 0), 1.2)
mirror(crate_stack, "crates_1", (18.0, -22.0, 0))
mirror(crate_stack, "crates_2", (-14.0, -4.0, 0))
mirror(barrels, "barrels_1", (10.5, -6.5, 0))
mirror(barrels, "barrels_2", (-18.0, -10.0, 0))
mirror(wreck, "wreck_1", (-14.0, 14.0, 0), .7)


def raised_deck(name, loc, rotz, _twin=False):
    """Elevated firing deck: ramp up from the centre side, jump-thruster up the back."""
    if _twin:
        loc, rotz, name = (-loc[0], -loc[1], 0), rotz + PI, name + "_b"
    o = (loc[0], loc[1], 0)
    d = box(name, (11.0, 8.0, 2.6), lw(o, rotz, 0, 0, 1.3), M["concrete"], rot=(0, 0, rotz), bevel=.08, props=CONVEX)
    box(name + "_top", (10.6, 7.6, .12), lw(o, rotz, 0, 0, 2.66), M["steel"], d, rot=(0, 0, rotz), bevel=0)
    box(name + "_ramp", (7.5, 4.6, .5), lw(o, rotz, -8.6, 0, 1.25), M["concrete_dark"], rot=(0, -.33, rotz),
        props=CONVEX)
    multi_box(name + "_bollards", [((.6, .6, 1.2), lw(o, rotz, lx, ly, 3.3)) for lx in (-3.5, 0, 3.5, 5.0)
                                   for ly in (-3.5, 3.5) if not (lx == -3.5)], M["line_y"], d)
    multi_box(name + "_edge", [((11.0, .3, .06), lw(o, rotz, 0, ly, 2.75), (0, 0, rotz)) for ly in (-3.85, 3.85)],
              M["black"], d)
    box(name + "_parapet", (.8, 8.0, 1.3), lw(o, rotz, 5.1, 0, 3.3), M["concrete_dark"], d, rot=(0, 0, rotz),
        props=CONVEX)
    multi_box(name + "_lights", [((.1, .5, .2), lw(o, rotz, lx, -4.05, 2.0), (0, 0, rotz)) for lx in (-4, 0, 4)],
              M["glow_blue"], d)


# outer ring: the extra space gets flanking routes, high ground and spawn cover
mirror(raised_deck, "deck_1", (36.0, 8.0, 0), 0.22, scale=False)
mirror(raised_deck, "deck_2", (-30.0, 30.0, 0), 2.4, scale=False)
mirror(container, "container_5", (34.0, -30.0, 0), 1.1, "#2F5D8C", scale=False)
mirror(container, "container_6", (31.5, -32.5, 0), 1.1, "#C88A2E", scale=False)
mirror(container, "container_7", (-44.0, -10.0, 0), 1.4, "#3E7A4E", scale=False)
mirror(blast_wall, "blast_wall_5", (42.0, -18.0, 0), 1.2, scale=False)
mirror(blast_wall, "blast_wall_6", (16.0, -40.0, 0), .35, scale=False)
mirror(blast_wall, "blast_wall_7", (-8.0, -41.0, 0), -.2, scale=False)      # spawn A cover
mirror(blast_wall, "blast_wall_8", (-38.0, -28.0, 0), .9, scale=False)
mirror(blast_wall, "blast_wall_9", (48.0, 10.0, 0), PI / 2 + .1, scale=False)
mirror(pillar, "pillar_3", (44.0, -32.0, 0), scale=False)
mirror(tank_trap, "tank_trap_5", (24.0, -44.0, 0), .4, scale=False)
mirror(tank_trap, "tank_trap_6", (-22.0, -45.0, 0), 1.0, scale=False)
mirror(tank_trap, "tank_trap_7", (50.0, -2.0, 0), .2, scale=False)
mirror(tank_trap, "tank_trap_8", (-50.0, 14.0, 0), .7, scale=False)
mirror(crate_stack, "crates_3", (38.0, -40.0, 0), scale=False)
mirror(crate_stack, "crates_4", (-46.0, 4.0, 0), scale=False)
mirror(barrels, "barrels_3", (28.0, -16.0, 0), scale=False)
mirror(barrels, "barrels_4", (-28.0, -36.0, 0), scale=False)
mirror(wreck, "wreck_2", (40.0, 26.0, 0), 2.2, scale=False)

# ================================================================== markers
use_collection("markers")
empty("arena_center", (0, 0, 0), props={"marker": "arena_center"})
empty("spawn_A", polar(SPAWN_R, GATES["A"]), rot=(0, 0, PI), props={"marker": "spawn", "team": "A"})   # faces +Y
empty("spawn_B", polar(SPAWN_R, GATES["B"]), rot=(0, 0, 0), props={"marker": "spawn", "team": "B"})    # faces -Y

export_glb(os.path.join(MODELS, "environments", "arena.glb"))

# ================================================================== previews (mechs added after export)
use_collection("_preview_mechs")
mp.assemble(mp.palette("mk1"), loc=polar(SPAWN_R, GATES["A"]), rotz=PI, name="preview_mech_A")
mp.assemble(mp.palette("scrap"), loc=polar(SPAWN_R, GATES["B"]), weapon_L="missile_pod", name="preview_mech_B")
render_preview("arena_overview", (38.0, -78.0, 60.0), (0, -2, 0), lens=19, sun=.15, sun_color="#9FB4FF",
               sun_rot=(.9, 0, .8), world="#0E1626", world_strength=.35, samples=96)
render_preview("arena_ground", (4.5, -SPAWN_R - 6.0, 6.4), (0, 0, 3.0), lens=22, sun=0, world="#0E1626", world_strength=.35,
               samples=96)
save_blend(os.path.join(SOURCE, "environments", "arena.blend"))
