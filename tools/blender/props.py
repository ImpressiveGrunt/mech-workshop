"""Human-scale props: they make a 15 ft (4.6 m) mech read as huge.

Everything is built at the origin under a root empty, then moved with place().
People are stylized 1.8 m workers facing -Y.
"""
from common import *

SKIN = ["#E0B08A", "#B57D55", "#7A4E33", "#F0CBA8"]


def place(root, loc, rotz=0.0):
    root.matrix_basis = Matrix.LocRotScale(Vector(loc), Euler((0, 0, rotz)), None)
    return root


def human(name, loc, rotz=0.0, pose="stand", vest="#F2C230", hat="#F2C230", skin=0):
    """pose: stand | tablet | point | wave"""
    root = empty(name, props={"prop": "worker", "height_m": 1.8})
    pants = mat("worker_pants", "#2E3A4E", 0, .8)
    shirt = mat("worker_shirt", "#4A5563", 0, .8)
    boots = mat("worker_boots", "#2A1F18", 0, .7)
    skin_m = mat(f"skin_{skin}", SKIN[skin % len(SKIN)], 0, .6)
    vest_m = mat("vest_" + vest, vest, 0, .55)
    hat_m = mat("hardhat_" + hat, hat, 0, .35)
    stripe = mat("reflective", "#E8E8E8", .3, .3, emit=.3)
    for s in (-1, 1):
        box(f"{name}_boot_{s:+d}", (.15, .3, .12), (.11 * s, -.04, .06), boots, root, bevel=.02)
        seg(f"{name}_leg_{s:+d}", (.11 * s, 0, .95), (.11 * s, 0, .12), .17, .19, pants, root, bevel=.02, taper=(.9, .9))
    box(f"{name}_hips", (.38, .21, .18), (0, 0, .97), pants, root, bevel=.02)
    box(f"{name}_torso", (.4, .23, .52), (0, 0, 1.3), shirt, root, bevel=.03, taper=(1.12, 1.0))
    box(f"{name}_vest", (.43, .26, .4), (0, 0, 1.27), vest_m, root, bevel=.03, taper=(1.1, 1.0))
    multi_box(f"{name}_vest_stripes", [((.44, .27, .035), (0, 0, z)) for z in (1.18, 1.32)], stripe, root)
    cyl(f"{name}_neck", .05, .08, (0, 0, 1.58), skin_m, root, segs=8)
    box(f"{name}_head", (.19, .21, .23), (0, 0, 1.71), skin_m, root, bevel=.04)
    cyl(f"{name}_hat", .13, .1, (0, 0, 1.86), hat_m, root, segs=12, r2=.11)
    cyl(f"{name}_hat_brim", .16, .02, (0, -.02, 1.81), hat_m, root, segs=12)
    arms = {
        "stand": [((.27, 0, 1.5), (.29, .02, 1.2), (.3, 0, .93)), ((-.27, 0, 1.5), (-.29, .02, 1.2), (-.3, 0, .93))],
        "tablet": [((.27, 0, 1.5), (.28, -.03, 1.22), (.12, -.3, 1.2)), ((-.27, 0, 1.5), (-.28, -.03, 1.22), (-.12, -.3, 1.2))],
        "point": [((.27, 0, 1.5), (.33, -.2, 1.68), (.38, -.5, 1.88)), ((-.27, 0, 1.5), (-.29, .02, 1.2), (-.3, 0, .93))],
        "wave": [((.27, 0, 1.5), (.45, 0, 1.75), (.5, -.05, 2.05)), ((-.27, 0, 1.5), (-.29, .02, 1.2), (-.3, 0, .93))],
    }[pose]
    for k, (sh, el, hand) in enumerate(arms):
        seg(f"{name}_upperarm_{k}", sh, el, .11, .12, shirt, root, bevel=.015)
        seg(f"{name}_forearm_{k}", el, hand, .1, .11, vest_m if False else shirt, root, bevel=.015)
        cyl(f"{name}_hand_{k}", .05, .08, hand, skin_m, root, segs=8)
    if pose == "tablet":
        box(f"{name}_tablet", (.3, .2, .02), (0, -.33, 1.22), mat("tablet_case", "#1B1C1E", .3, .5), root, rot=(.5, 0, 0), bevel=0)
        box(f"{name}_tablet_screen", (.26, .16, .005), (0, -.335, 1.233), mat("tablet_screen", "#3CE6FF", 0, .2, emit=3),
            root, rot=(.5, 0, 0), bevel=0)
    return place(root, loc, rotz)


def forklift(name, loc, rotz=0.0):
    root = empty(name, props={"prop": "forklift", "collision": "box"})
    body = mat("forklift_yellow", "#E8B32A", .2, .5)
    dark = mat("forklift_dark", "#25282C", .5, .5)
    tire = mat("tire", "#151515", 0, .9)
    box(f"{name}_body", (1.1, 1.8, .9), (0, .25, .75), body, root, bevel=.08, props={"collision": "box"})
    box(f"{name}_counterweight", (1.1, .45, .7), (0, 1.15, .65), dark, root, bevel=.06)
    box(f"{name}_seat", (.5, .45, .12), (0, .45, 1.3), dark, root)
    box(f"{name}_seat_back", (.5, .1, .5), (0, .68, 1.55), dark, root)
    multi_box(f"{name}_cage", [((.07, .07, 1.2), (x, y, 1.8)) for x in (-.5, .5) for y in (-.3, .85)]
              + [((1.07, 1.22, .07), (0, .28, 2.4))], dark, root)
    multi_box(f"{name}_mast", [((.1, .12, 2.6), (x, -.75, 1.3)) for x in (-.35, .35)], dark, root)
    multi_box(f"{name}_forks", [((.12, 1.1, .05), (x, -1.35, .12)) for x in (-.25, .25)]
              + [((.8, .08, .5), (0, -.82, .35))], dark, root)
    multi_cyl(f"{name}_wheels", [(.3, .22, (x, y, .3), (0, PI / 2, 0)) for x in (-.5, .5) for y in (-.35, .9)], tire,
              root, segs=12)
    cyl(f"{name}_beacon", .07, .1, (0, .3, 2.48), mat("beacon", "#FF9A2E", 0, .3, emit=8), root, segs=8)
    return place(root, loc, rotz)


def cone(name, loc):
    root = empty(name, props={"prop": "cone"})
    box(f"{name}_base", (.36, .36, .04), (0, 0, .02), mat("cone_orange", "#FF6A1A", 0, .5), root, bevel=.01)
    cyl(f"{name}_body", .14, .66, (0, 0, .37), mat("cone_orange", "#FF6A1A", 0, .5), root, segs=12, r2=.03)
    cyl(f"{name}_band", .105, .1, (0, 0, .4), mat("reflective", "#E8E8E8", .3, .3, emit=.3), root, segs=12, r2=.085)
    return place(root, loc)
