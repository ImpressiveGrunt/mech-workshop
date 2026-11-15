"""Modular mech part library (built in Blender).

Each part is a hierarchy under one root empty whose origin is its mount point.
Parts connect through sockets:
    legs  -> socket_torso
    torso -> socket_arm_L / socket_arm_R / socket_back, plus cockpit_camera
    arm   -> socket_hand (weapons mount here, pointing -Y)
Damage model hooks:
    armor_*      detachable plates  extras {armor_plate, detachable, hp}
    weak_point   reactor core       extras {weak_point, damage_multiplier}
    *_collider   physics boxes      extras {collider: "box"}
Root extras hold the gameplay stats (slot, hp, mass, price, ...).

Detail layer: hydraulic pistons (sleeve on the parent joint, rod on the child
joint so they telescope when the game bends a joint), cable runs, bolts,
grilles, layered armour, running lights and unit markings.
Paint channels follow material suffixes: _paint, _trim, _hazard, _glow.
"""
from common import *

TIER_MULT = {"mk1": (1.0, 1.0), "scrap": (0.7, 0.35), "wreck": (0.4, 0.2)}
UNIT_NUMBER = "07"
X_AXIS, Y_AXIS = (0, PI / 2, 0), (PI / 2, 0, 0)


def palette(tier="mk1"):
    P = {
        "mk1":   dict(paint=("#E8772E", .2, .45), trim=("#2B2F36", .5, .4), frame=("#4A5059", .7, .45),
                      joint=("#1E2125", .6, .5), hazard=("#F2C230", 0, .5), glow="#FFB347", glass="#78D8FF"),
        "scrap": dict(paint=("#8A4B2A", .3, .85), trim=("#5E7F8C", .2, .75), frame=("#5B5B55", .6, .7),
                      joint=("#2A2826", .5, .75), hazard=("#B8962E", 0, .8), glow="#7CFF6B", glass="#6E9C8C"),
        "wreck": dict(paint=("#5E3A26", .3, .95), trim=("#4A4E50", .3, .9), frame=("#3E3C38", .5, .85),
                      joint=("#1E1C1A", .4, .9), hazard=("#7E6A30", 0, .9), glow="#2A2A2A", glass="#2B3536"),
    }[tier]
    pal = {k: mat(f"{tier}_{k}", *P[k]) for k in ("paint", "trim", "frame", "joint", "hazard")}
    live = tier != "wreck"
    pal["glow"] = mat(f"{tier}_glow", P["glow"], 0, .3, emit=6 if live else 0)
    pal["glass"] = mat(f"{tier}_glass", P["glass"], 0, .1, emit=.5 if live else 0, alpha=.55 if live else 1)
    pal["chrome"] = mat(f"{tier}_chrome", "#C9CED4" if live else "#6A6560", 1.0, .2 if live else .7)
    pal["rubber"] = mat(f"{tier}_rubber", "#141414", 0, .9)
    pal["decal"] = mat(f"{tier}_decal", "#EDEDE6" if live else "#7A746A", 0, .6)
    pal["tier"] = tier
    return pal


def meta(pid, slot, tier, mass, hp, price, **stats):
    h, p = TIER_MULT[tier]
    d = {"part_id": pid, "slot": slot, "tier": tier, "mass_kg": mass, "hp": round(hp * h), "price": round(price * p)}
    d.update(stats)
    return d


def armor(hp, tier):
    return {"armor_plate": True, "detachable": True, "hp": round(hp * TIER_MULT[tier][0])}


# ------------------------------------------------------------------ detail helpers
def _seg_collider(name, a, b, w, d, parent):
    c, r, L = seg_xf(a, b)
    collider(name, (w, d, L), c, parent, r)


def piston(name, a, b, pal, parent_a, parent_b=None, r=.07):
    """Hydraulic ram: sleeve rides parent_a, chrome rod rides parent_b (telescopes)."""
    a, b = Vector(a), Vector(b)
    c, rot, L = seg_xf(a, a.lerp(b, .58))
    cyl(name + "_sleeve", r, L, c, pal["frame"], parent_a, rot=rot, segs=8)
    c, rot, L = seg_xf(a.lerp(b, .35), b)
    cyl(name + "_rod", r * .55, L, c, pal["chrome"], parent_b or parent_a, rot=rot, segs=8)
    cyl(name + "_mount_a", r * 1.4, r * 2.2, tuple(a), pal["joint"], parent_a, rot=X_AXIS, segs=8)
    cyl(name + "_mount_b", r * 1.4, r * 2.2, tuple(b), pal["joint"], parent_b or parent_a, rot=X_AXIS, segs=8)


def bolts(name, pts, pal, parent, axis=Y_AXIS, r=.035):
    multi_cyl(name, [(r, .04, p, axis) for p in pts], pal["joint"], parent, segs=6)


def cable(name, pts, pal, parent, r=.03, m=None):
    parts = []
    for a, b in zip(pts, pts[1:]):
        c, rot, L = seg_xf(a, b)
        parts.append((r, L + r, c, rot))
    multi_cyl(name, parts, m or pal["rubber"], parent, segs=6)


def grille(name, center, w, h, pal, parent, normal="y", n=5, sign=-1):
    """Vent slats on a face pointing along +/- normal axis."""
    cx, cy, cz = center
    parts = []
    for i in range(n):
        z = cz - h / 2 + (i + .5) * h / n
        if normal == "y":
            parts.append(((w, .05, h / n * .45), (cx, cy + .02 * sign, z)))
        else:
            parts.append(((.05, w, h / n * .45), (cx + .02 * sign, cy, z)))
    size = (w + .06, .04, h + .06) if normal == "y" else (.04, w + .06, h + .06)
    box(name + "_frame", size, center, pal["joint"], parent, bevel=0)
    multi_box(name, parts, pal["frame"], parent)


def lamp(name, loc, pal, parent, rot=Y_AXIS, r=.07):
    cyl(name + "_housing", r * 1.4, .08, loc, pal["joint"], parent, rot=rot, segs=10)
    v = Vector((0, 0, .045)); v.rotate(Euler(rot))
    cyl(name, r, .03, tuple(Vector(loc) + v * (-1 if rot == Y_AXIS else 1)), pal["glow"], parent, rot=rot, segs=10)


def stripes(name, center, size, pal, parent, n=4, rot=(0, 0, 0)):
    """Diagonal-feel hazard band: alternating hazard / joint blocks along X."""
    cx, cy, cz = center
    w = size[0] / n
    yel, blk = [], []
    for i in range(n):
        (yel if i % 2 == 0 else blk).append(((w, size[1], size[2]), (cx - size[0] / 2 + (i + .5) * w, cy, cz), rot))
    multi_box(name + "_y", yel, pal["hazard"], parent)
    multi_box(name + "_k", blk, pal["joint"], parent)


# ------------------------------------------------------------------ legs
def legs_biped(pal):
    t = pal["tier"]
    root = empty(f"legs_biped_{t}", props=meta("legs_biped", "legs", t, 9000, 420, 1200,
                                                 speed=8.0, turn_rate=90, jump=0.0, load_capacity=22000))
    pelvis = box("pelvis", (1.3, .9, .5), (0, 0, 2.25), pal["frame"], root, bevel=.06)
    box("armor_pelvis", (1.1, .14, .42), (0, -.5, 2.25), pal["paint"], pelvis, props=armor(60, t))
    box("pelvis_stripe", (1.12, .05, .08), (0, -.58, 2.36), pal["hazard"], pelvis, bevel=0)
    box("armor_crotch", (.5, .35, .45), (0, -.32, 1.92), pal["trim"], pelvis, taper=(1.25, 1.1), props=armor(40, t))
    box("pelvis_rear", (.9, .25, .4), (0, .5, 2.2), pal["trim"], pelvis)
    grille("pelvis_vent", (0, .63, 2.2), .7, .28, pal, pelvis, sign=1, n=4)
    cyl("waist_bearing", .5, .14, (0, 0, 2.47), pal["joint"], pelvis, segs=16)
    bolts("pelvis_bolts", [(x, -.58, z) for x in (-.48, .48) for z in (2.1, 2.4)], pal, pelvis)
    collider("pelvis_collider", (1.3, 1.0, .5), (0, 0, 2.25), pelvis)
    empty("socket_torso", (0, 0, 2.5), pelvis)
    for s, side in ((1, "L"), (-1, "R")):
        x = .62 * s
        hipP, kneeP, ankP = (x, 0, 2.15), (x, -.12, 1.18), (x, .04, .34)
        hip = empty(f"joint_hip_{side}", hipP, pelvis, props={"joint": "hip"})
        cyl(f"hip_cap_{side}", .3, .36, (x + .1 * s, 0, 2.15), pal["joint"], hip, rot=X_AXIS, segs=12)
        cyl(f"hip_servo_{side}", .36, .12, (x + .3 * s, 0, 2.15), pal["trim"], hip, rot=X_AXIS, segs=12)
        bolts(f"hip_bolts_{side}", [(x + .37 * s, .25 * math.cos(a), 2.15 + .25 * math.sin(a))
                                    for a in [k * PI / 3 for k in range(6)]], pal, hip, axis=X_AXIS)
        box(f"armor_skirt_{side}", (.12, .8, .6), (.8 * s, -.05, 2.12), pal["paint"], pelvis,
            rot=(0, -.12 * s, 0), props=armor(40, t))
        # thigh
        seg(f"thigh_{side}", hipP, kneeP, .46, .56, pal["frame"], hip, taper=(.85, .85))
        seg(f"armor_thigh_{side}", (x, -.34, 2.0), (x, -.44, 1.35), .54, .14, pal["paint"], hip, props=armor(80, t))
        bolts(f"thigh_bolts_{side}", [(x + dx, -.43 + dz * .05, z) for dx in (-.2, .2) for z, dz in ((1.95, 0), (1.42, -1))],
              pal, hip)
        grille(f"thigh_vent_{side}", (x + .25 * s, -.05, 1.68), .3, .4, pal, hip, normal="x", sign=s, n=4)
        cable(f"thigh_cable_{side}", [(x + .27 * s, .18, 2.05), (x + .3 * s, .14, 1.75), (x + .27 * s, .1, 1.3)], pal, hip)
        _seg_collider(f"thigh_{side}_collider", hipP, kneeP, .55, .7, hip)
        knee = empty(f"joint_knee_{side}", kneeP, hip, props={"joint": "knee"})
        piston(f"thigh_piston_{side}", (x, .32, 1.95), (x, .38, .98), pal, hip, knee, r=.075)
        # knee
        cyl(f"knee_cap_{side}", .27, .5, kneeP, pal["joint"], knee, rot=X_AXIS, segs=12)
        multi_cyl(f"knee_rings_{side}", [(.2, .06, (x + d, -.12, 1.18), X_AXIS) for d in (-.27, .27)], pal["chrome"],
                  knee, segs=12)
        box(f"armor_kneepad_{side}", (.46, .22, .42), (x, -.42, 1.2), pal["trim"], knee, props=armor(50, t))
        box(f"kneepad_top_{side}", (.36, .16, .14), (x, -.46, 1.44), pal["paint"], knee, rot=(.4, 0, 0))
        # shin
        seg(f"shin_{side}", kneeP, ankP, .52, .62, pal["paint"], knee, taper=(.8, .8))
        seg(f"armor_shin_{side}", (x, -.42, 1.0), (x, -.32, .52), .48, .12, pal["trim"], knee, props=armor(70, t))
        box(f"shin_stripe_{side}", (.53, .63, .07), (x, -.05, .9), pal["hazard"], knee, rot=(-.15, 0, 0), bevel=0)
        box(f"armor_calf_{side}", (.42, .16, .55), (x, .37, .78), pal["trim"], knee, rot=(.1, 0, 0), props=armor(40, t))
        multi_box(f"shin_lights_{side}", [((.12, .03, .04), (x + dx, -.49, .95)) for dx in (-.12, .12)], pal["glow"], knee)
        cable(f"shin_cable_{side}", [(x - .27 * s, .1, 1.15), (x - .3 * s, .1, .8), (x - .26 * s, .12, .45)], pal, knee)
        _seg_collider(f"shin_{side}_collider", kneeP, ankP, .55, .7, knee)
        # ankle + foot
        ank = empty(f"joint_ankle_{side}", ankP, knee, props={"joint": "ankle"})
        piston(f"ankle_piston_{side}", (x, .3, .78), (x, .46, .3), pal, knee, ank, r=.05)
        cyl(f"ankle_cap_{side}", .2, .46, ankP, pal["frame"], ank, rot=X_AXIS, segs=12)
        box(f"foot_{side}", (.7, 1.0, .26), (x, -.05, .13), pal["frame"], ank, bevel=.06, taper=(.9, .85))
        box(f"foot_top_{side}", (.5, .6, .14), (x, -.05, .32), pal["trim"], ank, taper=(.8, .7))
        for k, dx in enumerate((-.19, .19)):
            box(f"toe_{side}_{k}", (.3, .42, .2), (x + dx, -.72, .11), pal["trim"], ank, taper=(.9, .7))
            box(f"toe_cap_{side}_{k}", (.28, .12, .12), (x + dx, -.95, .08), pal["hazard"], ank)
        cyl(f"toe_hinge_{side}", .09, .66, (x, -.52, .16), pal["chrome"], ank, rot=X_AXIS, segs=8)
        box(f"heel_{side}", (.5, .32, .22), (x, .55, .13), pal["joint"], ank, taper=(.8, 1))
        box(f"heel_claw_{side}", (.18, .3, .14), (x, .78, .08), pal["trim"], ank, taper=(.6, .5))
        box(f"sole_{side}", (.72, 1.7, .05), (x, -.12, .025), pal["rubber"], ank, bevel=0)
        collider(f"foot_{side}_collider", (.75, 1.8, .35), (x, -.12, .17), ank)
    return root


# ------------------------------------------------------------------ torso
def torso(pal):
    t = pal["tier"]
    root = empty(f"torso_{t}", props=meta("torso_mk", "torso", t, 7000, 600, 1500,
                                            power=100, cooling=12, cockpit_height=1.12))
    box("waist", (.9, .8, .3), (0, 0, .15), pal["joint"], root)
    multi_box("waist_teeth", [((.1, .12, .2), (.47 * math.cos(a), .42 * math.sin(a), .15), (0, 0, a))
                              for a in [k * PI / 8 for k in range(16)]], pal["frame"], root)
    core = box("core", (1.7, 1.3, 1.1), (0, 0, .85), pal["frame"], root, bevel=.07, taper=(1.12, 1.08))
    # cockpit nose
    box("cockpit", (1.0, .55, .7), (0, -.8, 1.0), pal["paint"], core, bevel=.08, taper=(.85, .9))
    box("canopy", (.78, .1, .36), (0, -1.08, 1.12), pal["glass"], core, rot=(.3, 0, 0), bevel=.02)
    multi_box("canopy_frame", [((.04, .13, .4), (x, -1.09, 1.12), (.3, 0, 0)) for x in (-.4, -.13, .13, .4)]
              + [((.82, .13, .04), (0, -1.09, z), (.3, 0, 0)) for z in (.95, 1.3)], pal["joint"], core)
    box("canopy_brow", (.9, .25, .1), (0, -1.02, 1.36), pal["trim"], core)
    box("chin", (.7, .25, .2), (0, -1.0, .72), pal["trim"], core, taper=(1.15, 1))
    grille("chin_vent", (0, -1.13, .72), .5, .14, pal, core, n=3)
    text("unit_number", UNIT_NUMBER, .2, (0, -1.1, .86), m=pal["decal"], parent=core, extrude=.01)
    for s, side in ((1, "L"), (-1, "R")):
        lamp(f"headlight_{side}", (.42 * s, -1.08, .82), pal, core)
        grille(f"cockpit_intake_{side}", (.5 * s, -.82, 1.0), .35, .35, pal, core, normal="x", sign=s, n=4)
        box(f"armor_chest_{side}", (.5, .22, .85), (.68 * s, -.75, .85), pal["paint"], core,
            rot=(0, 0, -.25 * s), props=armor(90, t))
        box(f"chest_stripe_{side}", (.51, .23, .08), (.68 * s, -.75, 1.12), pal["hazard"], core,
            rot=(0, 0, -.25 * s), bevel=0)
        bolts(f"chest_bolts_{side}", [(.68 * s + .17 * dx, -.87 - .04 * dx * s, z) for dx in (-1, 1) for z in (.52, .98)],
              pal, core)
        box(f"shoulder_block_{side}", (.45, .75, .65), (.98 * s, 0, 1.1), pal["trim"], core)
        stripes(f"shoulder_stripe_{side}", (.98 * s, -.38, 1.1), (.4, .04, .55), pal, core, n=4)
        empty(f"socket_arm_{side}", (1.22 * s, 0, 1.1), core)
        grille(f"side_intake_{side}", (.93 * s, .05, .6), .6, .35, pal, core, normal="x", sign=s, n=5)
        box(f"vent_{side}", (.35, .06, .12), (.45 * s, .66, 1.0), pal["glow"], core, bevel=0)
        cyl(f"exhaust_{side}", .11, .55, (.52 * s, .55, 1.6), pal["trim"], core, segs=10)
        cyl(f"exhaust_cap_{side}", .13, .06, (.52 * s, .55, 1.88), pal["joint"], core, segs=10)
        cyl(f"exhaust_glow_{side}", .08, .02, (.52 * s, .55, 1.915), pal["glow"], core, segs=10)
        cable(f"back_cable_{side}", [(.25 * s, .68, 1.3), (.45 * s, .72, 1.05), (.75 * s, .6, .9), (.92 * s, .35, 1.0)],
              pal, core, r=.035)
    # sensor head
    box("sensor_head", (.5, .45, .3), (0, -.3, 1.55), pal["paint"], core, taper=(.85, .9))
    box("sensor_eye", (.34, .05, .07), (0, -.53, 1.58), pal["glow"], core, bevel=0)
    box("sensor_visor", (.42, .1, .05), (0, -.54, 1.66), pal["trim"], core)
    grille("sensor_vent_L", (.24, -.28, 1.55), .25, .16, pal, core, normal="x", sign=1, n=3)
    grille("sensor_vent_R", (-.24, -.28, 1.55), .25, .16, pal, core, normal="x", sign=-1, n=3)
    cyl("antenna", .025, .7, (.32, .15, 1.75), pal["joint"], core, segs=6)
    cyl("antenna_short", .02, .4, (.42, .2, 1.6), pal["joint"], core, segs=6)
    cyl("antenna_tip", .04, .04, (.32, .15, 2.11), pal["glow"], core, segs=6)
    cyl("sensor_dish", .16, .04, (-.3, .1, 1.62), pal["chrome"], core, rot=(.6, 0, .4), segs=14)
    cyl("sensor_dish_mount", .03, .2, (-.3, .1, 1.53), pal["joint"], core, segs=6)
    # back: reactor (weak point, kept below the backpack so it stays exposed) + ladder
    cyl("reactor_housing", .33, .3, (0, .68, .48), pal["joint"], core, rot=Y_AXIS, segs=16)
    multi_box("reactor_fins", [((.05, .14, .14), (.42 * math.sin(a), .7, .48 + .42 * math.cos(a)), (0, a, 0))
                               for a in [k * PI / 6 for k in range(12)]], pal["frame"], core)
    cyl("weak_point_reactor", .23, .14, (0, .85, .48), pal["glow"], core, rot=Y_AXIS, segs=16,
        props={"weak_point": True, "damage_multiplier": 2.5, "hp": round(80 * TIER_MULT[t][0])})
    multi_box("reactor_grate", [((.5 - abs(z) * 1.2, .03, .025), (0, .93, .48 + z)) for z in (-.12, 0, .12)], pal["joint"], core)
    multi_cyl("ladder_rungs", [(.025, .32, (-.62, .7, z), X_AXIS) for z in (.35, .55, .75, .95, 1.15)], pal["chrome"],
              core, segs=6)
    multi_box("ladder_rails", [((.04, .04, 1.0), (x, .7, .75)) for x in (-.78, -.46)], pal["chrome"], core)
    bolts("core_bolts", [(x, -.66, .32) for x in (-.6, -.3, 0, .3, .6)], pal, core)
    empty("socket_back", (0, .7, 1.2), core)
    empty("cockpit_camera", (0, -.9, 1.12), core, props={"camera": "first_person"})  # view = mech forward
    collider("core_collider", (1.9, 1.4, 1.3), (0, 0, .85), core)
    collider("cockpit_collider", (1.0, .6, .75), (0, -.85, 1.05), core)
    return root


# ------------------------------------------------------------------ arms
def arm(pal, side="L"):
    t = pal["tier"]; s = 1 if side == "L" else -1
    root = empty(f"arm_{side}_{t}", props=meta(f"arm_{side}", f"arm_{side}", t, 2600, 260, 700,
                                                 aim_speed=120, recoil_control=0.6))
    sh = empty(f"joint_shoulder_{side}", (0, 0, 0), root, props={"joint": "shoulder"})
    x = .45 * s
    cyl(f"shoulder_cap_{side}", .32, .5, (.2 * s, 0, 0), pal["joint"], sh, rot=X_AXIS, segs=12)
    cyl(f"shoulder_servo_{side}", .26, .1, (-.02 * s, 0, 0), pal["chrome"], sh, rot=X_AXIS, segs=12)
    # layered pauldron
    box(f"armor_pauldron_{side}", (.85, 1.0, .55), (x, 0, .25), pal["paint"], sh, bevel=.07,
        taper=(.8, .85), props=armor(90, t))
    box(f"armor_pauldron_top_{side}", (.6, .8, .2), (x + .03 * s, .02, .6), pal["paint"], sh, bevel=.05,
        taper=(.8, .8), props=armor(40, t))
    box(f"pauldron_stripe_{side}", (.87, .2, .4), (x, -.32, .25), pal["hazard"], sh, bevel=.02, taper=(.8, 1))
    box(f"pauldron_rim_{side}", (.9, 1.05, .08), (x, 0, .0), pal["trim"], sh)
    lamp(f"pauldron_light_{side}", (x + .25 * s, -.5, .2), pal, sh, r=.05)
    text(f"pauldron_number_{side}", UNIT_NUMBER, .26, (x + .435 * s, .08, .25),
         rot=(PI / 2, 0, PI / 2 * s), m=pal["decal"], parent=sh, extrude=.01)
    bolts(f"pauldron_bolts_{side}", [(x + dx, -.51, z) for dx in (-.25, .25) for z in (.08, .42)], pal, sh)
    # upper arm
    seg(f"upper_arm_{side}", (x, 0, 0), (x, 0, -.95), .42, .48, pal["frame"], sh)
    box(f"armor_bicep_{side}", (.12, .5, .6), (x + .26 * s, 0, -.5), pal["trim"], sh, props=armor(40, t))
    cable(f"bicep_cable_{side}", [(x - .25 * s, .15, -.1), (x - .27 * s, .2, -.5), (x - .24 * s, .15, -.9)], pal, sh)
    _seg_collider(f"upper_arm_{side}_collider", (x, 0, .3), (x, 0, -.95), .7, .9, sh)
    el = empty(f"joint_elbow_{side}", (x, 0, -1.0), sh, props={"joint": "elbow"})
    piston(f"bicep_piston_{side}", (x, -.3, -.15), (x, -.32, -.85), pal, sh, el, r=.06)
    # elbow + forearm
    cyl(f"elbow_cap_{side}", .26, .5, (x, 0, -1.0), pal["joint"], el, rot=X_AXIS, segs=12)
    multi_cyl(f"elbow_rings_{side}", [(.19, .05, (x + d, 0, -1.0), X_AXIS) for d in (-.26, .26)], pal["chrome"], el,
              segs=12)
    seg(f"forearm_{side}", (x, .1, -1.0), (x, -1.0, -1.0), .55, .5, pal["trim"], el, taper=(.9, .9))
    box(f"armor_forearm_{side}", (.6, .85, .14), (x, -.5, -.7), pal["paint"], el, props=armor(60, t))
    box(f"forearm_stripe_{side}", (.61, .1, .15), (x, -.12, -.7), pal["hazard"], el, bevel=0)
    bolts(f"forearm_bolts_{side}", [(x + dx, y, -.62) for dx in (-.22, .22) for y in (-.2, -.8)], pal, el, axis=(0, 0, 0))
    grille(f"forearm_vent_{side}", (x + .29 * s, -.55, -1.0), .5, .3, pal, el, normal="x", sign=s, n=4)
    multi_box(f"forearm_glow_{side}", [((.03, .4, .03), (x + .31 * s, -.55, z)) for z in (-1.18,)], pal["glow"], el)
    cyl(f"forearm_piston_{side}_sleeve", .05, .6, (x, -.3, -1.3), pal["frame"], el, rot=Y_AXIS, segs=8)
    cyl(f"forearm_piston_{side}_rod", .03, .5, (x, -.75, -1.3), pal["chrome"], el, rot=Y_AXIS, segs=8)
    cable(f"forearm_cable_{side}", [(x - .3 * s, .05, -.95), (x - .32 * s, -.5, -1.05), (x - .26 * s, -1.0, -1.0)], pal, el)
    cyl(f"wrist_{side}", .22, .16, (x, -1.05, -1.0), pal["joint"], el, rot=Y_AXIS, segs=12)
    cyl(f"wrist_ring_{side}", .25, .05, (x, -1.13, -1.0), pal["chrome"], el, rot=Y_AXIS, segs=12)
    bolts(f"wrist_bolts_{side}", [(x + .2 * math.cos(a), -1.16, -1.0 + .2 * math.sin(a))
                                  for a in [k * PI / 4 for k in range(8)]], pal, el, r=.025)
    empty(f"socket_hand", (x, -1.12, -1.0), el)
    _seg_collider(f"forearm_{side}_collider", (x, .1, -1.0), (x, -1.1, -1.0), .6, .6, el)
    return root


# ------------------------------------------------------------------ weapons
def weapon_autocannon(pal):
    t = pal["tier"]
    root = empty(f"weapon_autocannon_{t}", props=meta("weapon_autocannon", "weapon", t, 1800, 150, 900,
                                                        damage=35, fire_rate=6.0, range=120, ammo=120,
                                                        weapon_type="ballistic"))
    box("ac_body", (.5, 1.0, .55), (0, -.4, 0), pal["frame"], root, bevel=.05)
    box("ac_rail", (.3, .9, .12), (0, -.4, .32), pal["paint"], root)
    stripes("ac_stripe", (0, -.75, .39), (.3, .12, .03), pal, root, n=4)
    grille("ac_vent_L", (.26, -.45, 0), .5, .3, pal, root, normal="x", sign=1, n=4)
    grille("ac_vent_R", (-.26, -.45, 0), .5, .3, pal, root, normal="x", sign=-1, n=4)
    # optic
    box("ac_optic", (.16, .34, .14), (0, -.25, .46), pal["trim"], root)
    cyl("ac_optic_lens", .055, .02, (0, -.43, .46), pal["glass"], root, rot=Y_AXIS, segs=10)
    # rotary barrel cluster with cooling rings and clamps
    cyl("ac_shroud", .19, .6, (0, -1.15, .05), pal["trim"], root, rot=Y_AXIS, segs=8)
    multi_cyl("ac_cooling_rings", [(.21, .04, (0, y, .05), Y_AXIS) for y in (-.95, -1.05, -1.15, -1.25, -1.35)],
              pal["frame"], root, segs=8)
    multi_cyl("ac_barrels", [(.045, 1.45, (.085 * math.cos(a), -1.62, .05 + .085 * math.sin(a)), Y_AXIS)
                             for a in [k * 2 * PI / 3 + PI / 2 for k in range(3)]], pal["joint"], root, segs=8)
    cyl("ac_spindle", .03, 1.5, (0, -1.6, .05), pal["chrome"], root, rot=Y_AXIS, segs=6)
    multi_cyl("ac_clamps", [(.16, .06, (0, y, .05), Y_AXIS) for y in (-1.75, -2.1)], pal["frame"], root, segs=8)
    cyl("ac_muzzle", .17, .28, (0, -2.33, .05), pal["frame"], root, rot=Y_AXIS, segs=6)
    multi_box("ac_muzzle_slots", [((.36, .06, .05), (0, y, .05)) for y in (-2.28, -2.38)], pal["joint"], root)
    # ammo drum + feed chute
    cyl("ac_drum", .3, .32, (.42, -.3, -.05), pal["paint"], root, rot=X_AXIS, segs=14)
    multi_cyl("ac_drum_bands", [(.31, .04, (x, -.3, -.05), X_AXIS) for x in (.3, .54)], pal["joint"], root, segs=14)
    cyl("ac_drum_cap", .14, .06, (.6, -.3, -.05), pal["chrome"], root, rot=X_AXIS, segs=10)
    chute = []
    for i in range(5):
        a = i / 4 * PI / 2
        chute.append(((.14, .12, .14), (.42 - .14 * math.sin(a), -.3 - .25 * math.sin(a), .25 + .05 * math.cos(a)),
                      (0, 0, 0)))
    multi_box("ac_feed_chute", chute, pal["joint"], root)
    bolts("ac_bolts", [(x, -.91, z) for x in (-.18, .18) for z in (-.18, .18)], pal, root, r=.03)
    empty("socket_muzzle", (0, -2.48, .05), root)
    collider("ac_collider", (.9, 2.4, .6), (0, -1.1, 0), root)
    return root


def weapon_ram_fist(pal):
    t = pal["tier"]
    root = empty(f"weapon_ram_fist_{t}", props=meta("weapon_ram_fist", "weapon", t, 2200, 260, 750,
                                                      damage=80, fire_rate=1.0, range=4, weapon_type="melee"))
    box("ram_housing", (.62, .62, .58), (0, -.3, 0), pal["frame"], root, bevel=.06)
    multi_box("ram_housing_ribs", [((.66, .06, .62), (0, y, 0)) for y in (-.12, -.3, -.48)], pal["trim"], root)
    lamp("ram_warning", (0, -.3, .32), pal, root, rot=(0, 0, 0), r=.06)
    cyl("ram_piston", .15, .55, (0, -.78, 0), pal["chrome"], root, rot=Y_AXIS, segs=12)
    cyl("ram_piston_collar", .2, .1, (0, -.62, 0), pal["joint"], root, rot=Y_AXIS, segs=12)
    for s in (-1, 1):
        cyl(f"ram_side_piston_{s:+d}_sleeve", .06, .45, (.27 * s, -.75, -.18), pal["frame"], root, rot=Y_AXIS, segs=8)
        cyl(f"ram_side_piston_{s:+d}_rod", .035, .35, (.27 * s, -.98, -.18), pal["chrome"], root, rot=Y_AXIS, segs=8)
    box("ram_fist", (.8, .5, .8), (0, -1.15, 0), pal["paint"], root, bevel=.08, rot=Y_AXIS)
    box("ram_stripe", (.82, .12, .82), (0, -1.0, 0), pal["hazard"], root, bevel=0)
    multi_box("ram_knuckles", [((.17, .14, .62), (x, -1.44, 0)) for x in (-.29, -.1, .1, .29)], pal["trim"], root)
    multi_cyl("ram_spikes", [(.06, .2, (x, -1.58, z), (PI / 2, 0, 0), .0) for x in (-.29, -.1, .1, .29) for z in (-.15, .15)],
              pal["chrome"], root, segs=6)
    bolts("ram_bolts", [(x, -.88, z) for x in (-.3, .3) for z in (-.3, .3)], pal, root, r=.03)
    empty("socket_muzzle", (0, -1.6, 0), root)
    collider("ram_collider", (.85, 1.7, .85), (0, -.8, 0), root)
    return root


def weapon_missile_pod(pal):
    t = pal["tier"]
    root = empty(f"weapon_missile_pod_{t}", props=meta("weapon_missile_pod", "weapon", t, 2000, 140, 1400,
                                                         damage=60, fire_rate=1.5, range=200, ammo=18,
                                                         weapon_type="explosive"))
    box("pod_body", (.85, 1.0, .7), (0, -.45, 0), pal["paint"], root, bevel=.06)
    box("pod_face", (.8, .06, .62), (0, -.96, 0), pal["trim"], root)
    tubes = [(x, z) for x in (-.24, 0, .24) for z in (-.15, .15)]
    multi_cyl("pod_tubes", [(.1, .14, (x, -.99, z), Y_AXIS) for x, z in tubes], pal["joint"], root, segs=10)
    multi_cyl("pod_missiles", [(.075, .22, (x, -1.06, z), (-PI / 2, 0, 0), .015) for x, z in tubes],
              pal["hazard"], root, segs=10)
    multi_cyl("pod_tips", [(.03, .03, (x, -1.17, z), Y_AXIS) for x, z in tubes], pal["glow"], root, segs=8)
    box("armor_pod_cover", (.8, .55, .06), (0, -.62, .44), pal["paint"], root, rot=(-.35, 0, 0), props=armor(30, t))
    cyl("pod_cover_hinge", .04, .8, (0, -.36, .38), pal["chrome"], root, rot=X_AXIS, segs=8)
    box("pod_stripe", (.87, .15, .72), (0, -.1, 0), pal["hazard"], root, bevel=0)
    box("pod_sensor", (.16, .28, .18), (.5, -.6, .18), pal["trim"], root)
    cyl("pod_sensor_lens", .05, .02, (.5, -.75, .18), pal["glass"], root, rot=Y_AXIS, segs=10)
    grille("pod_vent", (-.44, -.45, 0), .6, .4, pal, root, normal="x", sign=-1, n=5)
    multi_box("pod_rails", [((.06, 1.0, .06), (x, -.45, -.38)) for x in (-.3, .3)], pal["frame"], root)
    multi_cyl("pod_exhaust", [(.07, .05, (x, .07, z), Y_AXIS) for x, z in tubes], pal["joint"], root, segs=8)
    bolts("pod_bolts", [(x, -.98, z) for x in (-.37, .37) for z in (-.27, .27)], pal, root, r=.025)
    empty("socket_muzzle", (0, -1.2, 0), root)
    collider("pod_collider", (1.0, 1.2, .8), (0, -.55, 0), root)
    return root


def back_thruster(pal):
    t = pal["tier"]
    root = empty(f"back_thruster_{t}", props=meta("back_thruster", "back", t, 1500, 180, 1000,
                                                    boost_force=900000, fuel=100, recharge=15))
    box("pack_body", (1.2, .6, 1.0), (0, .35, 0), pal["frame"], root, bevel=.06)
    box("armor_pack_cover", (1.0, .12, .8), (0, .7, .05), pal["paint"], root, props=armor(50, t))
    stripes("pack_stripe", (0, .77, .38), (.9, .03, .08), pal, root, n=6)
    multi_box("pack_fins", [((.04, .1, .5), (x, .78, -.05)) for x in (-.36, -.24, -.12, 0, .12, .24, .36)],
              pal["trim"], root)
    lamp("pack_warning", (0, .4, .53), pal, root, rot=(0, 0, 0), r=.05)
    for s, side in ((1, "L"), (-1, "R")):
        # fuel tank
        cyl(f"fuel_tank_{side}", .17, .9, (.72 * s, .4, .1), pal["chrome"], root, segs=12)
        multi_cyl(f"fuel_tank_bands_{side}", [(.18, .04, (.72 * s, .4, z)) for z in (-.2, .1, .4)], pal["joint"], root,
                  segs=12)
        cyl(f"fuel_tank_cap_{side}", .1, .08, (.72 * s, .4, .59), pal["hazard"], root, segs=10)
        cable(f"fuel_line_{side}", [(.72 * s, .4, -.35), (.6 * s, .45, -.45), (.38 * s, .45, -.38)], pal, root, r=.035)
        # gimballed nozzle
        cyl(f"nozzle_mount_{side}", .2, .14, (.38 * s, .45, -.45), pal["joint"], root, segs=12)
        cyl(f"nozzle_gimbal_{side}", .22, .05, (.38 * s, .45, -.53), pal["chrome"], root, segs=12)
        cyl(f"nozzle_{side}", .24, .5, (.38 * s, .45, -.8), pal["frame"], root, segs=14, r2=.15)
        multi_cyl(f"nozzle_ribs_{side}", [(.17 + .07 * k, .03, (.38 * s, .45, -.62 - .14 * k)) for k in range(3)],
                  pal["joint"], root, segs=14)
        cyl(f"nozzle_glow_{side}", .19, .04, (.38 * s, .45, -1.03), pal["glow"], root, segs=14)
        cyl(f"nozzle_core_{side}", .08, .2, (.38 * s, .45, -.95), pal["glow"], root, segs=10, r2=.02)
        empty(f"socket_thrust_{side}", (.38 * s, .45, -1.06), root, rot=(PI, 0, 0))
        box(f"fin_{side}", (.08, .5, .7), (.95 * s, .5, .1), pal["paint"], root, taper=(1, .6))
    collider("pack_collider", (1.8, .8, 1.7), (0, .4, -.25), root)
    return root


# ------------------------------------------------------------------ assembly
LEGS = {"biped": legs_biped}
WEAPONS = {"autocannon": weapon_autocannon, "ram_fist": weapon_ram_fist, "missile_pod": weapon_missile_pod}


def find(root, name):
    for c in root.children_recursive:
        if c.name == name or c.name.startswith(name + "."):
            return c
    raise KeyError(name)


def attach(child, socket):
    child.parent = socket
    child.matrix_parent_inverse = Matrix.Identity(4)
    child.matrix_basis = Matrix.Identity(4)


def assemble(pal, legs="biped", weapon_L="ram_fist", weapon_R="autocannon", back=True, name=None,
             loc=(0, 0, 0), rotz=0.0):
    t = pal["tier"]
    top = empty(name or f"mech_{t}", loc, rot=(0, 0, rotz), props={"mech": True, "tier": t})
    L = LEGS[legs](pal); attach(L, top)
    T = torso(pal); attach(T, find(L, "socket_torso"))
    for side, w in (("L", weapon_L), ("R", weapon_R)):
        a = arm(pal, side); attach(a, find(T, f"socket_arm_{side}"))
        if w:
            attach(WEAPONS[w](pal), find(a, "socket_hand"))
    if back:
        attach(back_thruster(pal), find(T, "socket_back"))
    return top
