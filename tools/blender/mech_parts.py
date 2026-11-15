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
"""
from common import *

TIER_MULT = {"mk1": (1.0, 1.0), "scrap": (0.7, 0.35), "wreck": (0.4, 0.2)}


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
    pal["tier"] = tier
    return pal


def meta(pid, slot, tier, mass, hp, price, **stats):
    h, p = TIER_MULT[tier]
    d = {"part_id": pid, "slot": slot, "tier": tier, "mass_kg": mass, "hp": round(hp * h), "price": round(price * p)}
    d.update(stats)
    return d


def armor(hp, tier):
    return {"armor_plate": True, "detachable": True, "hp": round(hp * TIER_MULT[tier][0])}


def _seg_collider(name, a, b, w, d, parent):
    c, r, L = seg_xf(a, b)
    collider(name, (w, d, L), c, parent, r)


# ------------------------------------------------------------------ legs
def legs_biped(pal):
    t = pal["tier"]
    root = empty(f"legs_biped_{t}", props=meta("legs_biped", "legs", t, 9000, 420, 1200,
                                                 speed=8.0, turn_rate=90, jump=0.0, load_capacity=22000))
    pelvis = box("pelvis", (1.3, .9, .5), (0, 0, 2.25), pal["frame"], root, bevel=.06)
    box("armor_pelvis", (1.1, .14, .42), (0, -.5, 2.25), pal["paint"], pelvis, props=armor(60, t))
    box("pelvis_stripe", (1.12, .05, .08), (0, -.58, 2.36), pal["hazard"], pelvis, bevel=0)
    collider("pelvis_collider", (1.3, 1.0, .5), (0, 0, 2.25), pelvis)
    empty("socket_torso", (0, 0, 2.5), pelvis)
    for s, side in ((1, "L"), (-1, "R")):
        x = .62 * s
        hipP, kneeP, ankP = (x, 0, 2.15), (x, -.12, 1.18), (x, .04, .34)
        hip = empty(f"joint_hip_{side}", hipP, pelvis, props={"joint": "hip"})
        cyl(f"hip_cap_{side}", .3, .36, (x + .1 * s, 0, 2.15), pal["joint"], hip, rot=(0, PI / 2, 0), segs=10)
        seg(f"thigh_{side}", hipP, kneeP, .46, .56, pal["frame"], hip, taper=(.85, .85))
        seg(f"armor_thigh_{side}", (x, -.34, 2.0), (x, -.44, 1.35), .54, .14, pal["paint"], hip, props=armor(80, t))
        _seg_collider(f"thigh_{side}_collider", hipP, kneeP, .55, .7, hip)
        knee = empty(f"joint_knee_{side}", kneeP, hip, props={"joint": "knee"})
        cyl(f"knee_cap_{side}", .27, .5, kneeP, pal["joint"], knee, rot=(0, PI / 2, 0), segs=10)
        box(f"armor_kneepad_{side}", (.46, .22, .42), (x, -.42, 1.2), pal["trim"], knee, props=armor(50, t))
        seg(f"shin_{side}", kneeP, ankP, .52, .62, pal["paint"], knee, taper=(.8, .8))
        seg(f"armor_shin_{side}", (x, -.42, 1.0), (x, -.32, .52), .48, .12, pal["trim"], knee, props=armor(70, t))
        box(f"shin_stripe_{side}", (.53, .63, .07), (x, -.05, .9), pal["hazard"], knee, rot=(-.15, 0, 0), bevel=0)
        _seg_collider(f"shin_{side}_collider", kneeP, ankP, .55, .7, knee)
        ank = empty(f"joint_ankle_{side}", ankP, knee, props={"joint": "ankle"})
        cyl(f"ankle_cap_{side}", .2, .46, ankP, pal["frame"], ank, rot=(0, PI / 2, 0), segs=10)
        box(f"foot_{side}", (.7, 1.25, .28), (x, -.15, .14), pal["frame"], ank, bevel=.06, taper=(.9, .85))
        box(f"toe_{side}", (.72, .35, .2), (x, -.72, .12), pal["trim"], ank)
        box(f"heel_{side}", (.5, .3, .22), (x, .5, .14), pal["joint"], ank)
        collider(f"foot_{side}_collider", (.75, 1.6, .3), (x, -.15, .15), ank)
    return root


# ------------------------------------------------------------------ torso
def torso(pal):
    t = pal["tier"]
    root = empty(f"torso_{t}", props=meta("torso_mk", "torso", t, 7000, 600, 1500,
                                            power=100, cooling=12, cockpit_height=1.12))
    box("waist", (.9, .8, .3), (0, 0, .15), pal["joint"], root)
    core = box("core", (1.7, 1.3, 1.1), (0, 0, .85), pal["frame"], root, bevel=.07, taper=(1.12, 1.08))
    box("cockpit", (1.0, .55, .7), (0, -.8, 1.0), pal["paint"], core, bevel=.08, taper=(.85, .9))
    box("canopy", (.78, .1, .36), (0, -1.08, 1.12), pal["glass"], core, rot=(.3, 0, 0), bevel=.02)
    box("canopy_brow", (.9, .25, .1), (0, -1.02, 1.36), pal["trim"], core)
    for s, side in ((1, "L"), (-1, "R")):
        box(f"armor_chest_{side}", (.5, .22, .85), (.68 * s, -.75, .85), pal["paint"], core,
            rot=(0, 0, -.25 * s), props=armor(90, t))
        box(f"chest_stripe_{side}", (.51, .23, .08), (.68 * s, -.75, 1.12), pal["hazard"], core,
            rot=(0, 0, -.25 * s), bevel=0)
        box(f"shoulder_block_{side}", (.45, .75, .65), (.98 * s, 0, 1.1), pal["trim"], core)
        empty(f"socket_arm_{side}", (1.22 * s, 0, 1.1), core)
        box(f"vent_{side}", (.35, .06, .12), (.45 * s, .66, 1.0), pal["glow"], core, bevel=0)
    box("sensor_head", (.5, .45, .3), (0, -.3, 1.55), pal["paint"], core, taper=(.85, .9))
    box("sensor_eye", (.34, .05, .07), (0, -.53, 1.58), pal["glow"], core, bevel=0)
    cyl("antenna", .025, .7, (.32, .15, 1.75), pal["joint"], core, segs=6)
    cyl("reactor_housing", .42, .3, (0, .68, .75), pal["joint"], core, rot=(PI / 2, 0, 0), segs=12)
    cyl("weak_point_reactor", .28, .14, (0, .85, .75), pal["glow"], core, rot=(PI / 2, 0, 0), segs=12,
        props={"weak_point": True, "damage_multiplier": 2.5, "hp": round(80 * TIER_MULT[t][0])})
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
    cyl(f"shoulder_cap_{side}", .32, .5, (.2 * s, 0, 0), pal["joint"], sh, rot=(0, PI / 2, 0), segs=10)
    box(f"armor_pauldron_{side}", (.85, 1.0, .55), (x, 0, .25), pal["paint"], sh, bevel=.07,
        taper=(.8, .85), props=armor(90, t))
    box(f"pauldron_stripe_{side}", (.87, .2, .4), (x, -.32, .25), pal["hazard"], sh, bevel=.02, taper=(.8, 1))
    seg(f"upper_arm_{side}", (x, 0, 0), (x, 0, -.95), .42, .48, pal["frame"], sh)
    _seg_collider(f"upper_arm_{side}_collider", (x, 0, .3), (x, 0, -.95), .7, .9, sh)
    el = empty(f"joint_elbow_{side}", (x, 0, -1.0), sh, props={"joint": "elbow"})
    cyl(f"elbow_cap_{side}", .26, .5, (x, 0, -1.0), pal["joint"], el, rot=(0, PI / 2, 0), segs=10)
    seg(f"forearm_{side}", (x, .1, -1.0), (x, -1.0, -1.0), .55, .5, pal["trim"], el, taper=(.9, .9))
    box(f"armor_forearm_{side}", (.6, .85, .14), (x, -.5, -.7), pal["paint"], el, props=armor(60, t))
    cyl(f"wrist_{side}", .22, .16, (x, -1.05, -1.0), pal["joint"], el, rot=(PI / 2, 0, 0), segs=10)
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
    cyl("ac_shroud", .17, .6, (0, -1.15, .05), pal["trim"], root, rot=(PI / 2, 0, 0), segs=8)
    cyl("ac_barrel", .09, 1.4, (0, -1.6, .05), pal["joint"], root, rot=(PI / 2, 0, 0), segs=10)
    cyl("ac_muzzle", .15, .25, (0, -2.3, .05), pal["frame"], root, rot=(PI / 2, 0, 0), segs=6)
    cyl("ac_drum", .3, .32, (.42, -.3, -.05), pal["paint"], root, rot=(0, PI / 2, 0), segs=12)
    empty("socket_muzzle", (0, -2.45, .05), root)
    collider("ac_collider", (.9, 2.4, .6), (0, -1.1, 0), root)
    return root


def weapon_ram_fist(pal):
    t = pal["tier"]
    root = empty(f"weapon_ram_fist_{t}", props=meta("weapon_ram_fist", "weapon", t, 2200, 260, 750,
                                                      damage=80, fire_rate=1.0, range=4, weapon_type="melee"))
    box("ram_housing", (.6, .6, .55), (0, -.3, 0), pal["frame"], root, bevel=.06)
    cyl("ram_piston", .14, .5, (0, -.75, 0), pal["joint"], root, rot=(PI / 2, 0, 0), segs=10)
    box("ram_fist", (.8, .5, .8), (0, -1.15, 0), pal["paint"], root, bevel=.08, rot=(PI / 2, 0, 0))
    multi_box("ram_knuckles", [((.17, .14, .62), (x, -1.44, 0)) for x in (-.29, -.1, .1, .29)], pal["trim"], root)
    box("ram_stripe", (.82, .12, .82), (0, -1.0, 0), pal["hazard"], root, bevel=0)
    empty("socket_muzzle", (0, -1.5, 0), root)
    collider("ram_collider", (.85, 1.6, .85), (0, -.75, 0), root)
    return root


def weapon_missile_pod(pal):
    t = pal["tier"]
    root = empty(f"weapon_missile_pod_{t}", props=meta("weapon_missile_pod", "weapon", t, 2000, 140, 1400,
                                                         damage=60, fire_rate=1.5, range=200, ammo=18,
                                                         weapon_type="explosive"))
    box("pod_body", (.85, 1.0, .7), (0, -.45, 0), pal["paint"], root, bevel=.06)
    tubes = [(x, z) for x in (-.24, 0, .24) for z in (-.15, .15)]
    multi_cyl("pod_tubes", [(.1, .14, (x, -.98, z), (PI / 2, 0, 0)) for x, z in tubes], pal["joint"], root, segs=10)
    multi_cyl("pod_tips", [(.06, .1, (x, -.99, z), (PI / 2, 0, 0)) for x, z in tubes], pal["glow"], root, segs=8)
    box("pod_stripe", (.87, .15, .72), (0, -.1, 0), pal["hazard"], root, bevel=0)
    empty("socket_muzzle", (0, -1.05, 0), root)
    collider("pod_collider", (.9, 1.1, .75), (0, -.5, 0), root)
    return root


def back_thruster(pal):
    t = pal["tier"]
    root = empty(f"back_thruster_{t}", props=meta("back_thruster", "back", t, 1500, 180, 1000,
                                                    boost_force=900000, fuel=100, recharge=15))
    box("pack_body", (1.2, .6, 1.0), (0, .35, 0), pal["frame"], root, bevel=.06)
    box("pack_cover", (1.0, .12, .8), (0, .7, .05), pal["paint"], root, props=armor(50, t))
    for s, side in ((1, "L"), (-1, "R")):
        cyl(f"nozzle_{side}", .2, .5, (.38 * s, .45, -.65), pal["joint"], root, segs=10, r2=.14)
        cyl(f"nozzle_glow_{side}", .15, .05, (.38 * s, .45, -.9), pal["glow"], root, segs=10)
        empty(f"socket_thrust_{side}", (.38 * s, .45, -.92), root, rot=(PI, 0, 0))
        box(f"fin_{side}", (.08, .5, .7), (.62 * s, .5, .1), pal["paint"], root, taper=(1, .6))
    collider("pack_collider", (1.3, .8, 1.6), (0, .4, -.2), root)
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
