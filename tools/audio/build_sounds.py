"""Procedural sound design for Mech Workshop.

Every sound effect is synthesized here from scratch (oscillators, filtered noise, inharmonic metal
partials, distortion and convolution reverb), so the audio is original and reproducible like the
Blender-built models. Writes 16-bit mono WAVs to assets/audio/ and data/sounds.json (the manifest
the game's Audio autoload reads: bus, base volume, loop flag, 3D range).

    python3 tools/audio/build_sounds.py          (needs numpy + scipy)
"""
import json, os, wave
import numpy as np
from scipy import signal

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio")
MANIFEST = {}
rng = np.random.default_rng(1337)


# ------------------------------------------------------------------ building blocks
def t_(d):
    return np.arange(int(d * SR)) / SR


def silence(d):
    return np.zeros(int(d * SR))


def noise(d):
    return rng.standard_normal(int(d * SR))


def pink(d):
    w = noise(d)
    b, a = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400]
    return signal.lfilter(b, a, w) * 4


def brown(d):
    x = np.cumsum(noise(d))
    x = signal.sosfilt(signal.butter(1, 20, "highpass", fs=SR, output="sos"), x)
    return x / (np.abs(x).max() + 1e-9)


def lp(x, fc, order=4):
    return signal.sosfilt(signal.butter(order, min(fc, SR * 0.45), "lowpass", fs=SR, output="sos"), x)


def hp(x, fc, order=4):
    return signal.sosfilt(signal.butter(order, fc, "highpass", fs=SR, output="sos"), x)


def bp(x, lo, hi, order=3):
    return signal.sosfilt(signal.butter(order, [lo, min(hi, SR * 0.45)], "bandpass", fs=SR, output="sos"), x)


def decay(d, tau, attack=0.002):
    """Exponential decay that is guaranteed to reach zero before the buffer ends (no end clicks)."""
    t = t_(d)
    e = np.exp(-t / tau)
    a = int(attack * SR)
    if a > 0:
        e[:a] *= np.linspace(0, 1, a)
    n = max(1, int(len(e) * 0.15))
    e[-n:] *= np.linspace(1, 0, n) ** 2
    return e


def sweep(d, f0, f1, shape="exp"):
    t = t_(d)
    f = f0 * (f1 / f0) ** (t / d) if shape == "exp" else np.linspace(f0, f1, len(t))
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def tone(d, f, harmonics=(1.0,)):
    t = t_(d)
    return sum(a * np.sin(2 * np.pi * f * (k + 1) * t) for k, a in enumerate(harmonics))


def metal(d, base, ratios=(1, 2.76, 5.4, 8.93, 13.34), taus=(0.5, 0.3, 0.18, 0.1, 0.06), amps=(1, .7, .5, .35, .2)):
    """Struck metal: inharmonic partials with their own decays plus a strike click."""
    t = t_(d)
    out = np.zeros_like(t)
    for r, tau, a in zip(ratios, taus, amps):
        f = base * r * (1 + rng.uniform(-0.01, 0.01))
        out += a * np.sin(2 * np.pi * f * t + rng.uniform(0, 6.28)) * np.exp(-t / tau)
    click = hp(noise(d), 2500) * decay(d, 0.004) * 0.6
    n = max(1, int(len(out) * 0.2))
    out[-n:] *= np.linspace(1, 0, n) ** 2            # ringing partials fade out instead of being cut
    return out + click


def at(x, offset, length):
    """Place x starting at offset seconds inside a buffer of length seconds (fades if truncated)."""
    out = silence(length)
    i = int(offset * SR)
    n = min(len(x), len(out) - i)
    seg = x[:n].copy()
    if n < len(x):
        k = min(n, int(0.05 * SR))
        seg[-k:] *= np.linspace(1, 0, k)
    out[i:i + n] += seg
    return out


def pad(x, d):
    return np.concatenate([x, silence(max(0.0, d - len(x) / SR))])[:int(d * SR)] if len(x) < int(d * SR) else x[:int(d * SR)]


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def drive(x, amount):
    return np.tanh(x * amount) / np.tanh(amount)


def reverb(x, size=1.2, wet=0.3, damp=4000, predelay=0.01):
    """Convolution with a synthetic decaying-noise impulse response."""
    n = int(size * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / (size * SR / 6.9))
    ir = lp(ir, damp, 2)
    ir = np.concatenate([np.zeros(int(predelay * SR)), ir])
    ir /= np.sqrt(np.sum(ir ** 2))
    w = signal.fftconvolve(x, ir)[:len(x) + n]
    dry = np.concatenate([x, np.zeros(len(w) - len(x))])
    return dry * (1 - wet) + w * wet


def fade_out(x, d=0.05):
    n = min(len(x), int(d * SR))
    x = x.copy()
    x[-n:] *= np.linspace(1, 0, n)
    return x


def trim_tail(x, thresh=1e-4):
    idx = np.where(np.abs(x) > thresh * np.abs(x).max())[0]
    return fade_out(x[:idx[-1] + int(0.02 * SR)] if len(idx) else x)


def seamless(x, xfade=0.25):
    """Make a loop: crossfade the tail into the head."""
    n = int(xfade * SR)
    head, body, tail = x[:n], x[n:-n], x[-n:]
    f = np.linspace(0, 1, n)
    return np.concatenate([body, tail * (1 - f) + head * f])


def am(x, rate, depth, smooth=True):
    """Random amplitude modulation (crowd swells, gear chatter)."""
    k = max(2, int(len(x) / SR * rate) + 2)
    ctrl = rng.uniform(1 - depth, 1, k)
    env = np.interp(np.linspace(0, k - 1, len(x)), np.arange(k), ctrl)
    if smooth:
        env = lp(env, rate * 2, 2)
    return x * env


def crackle(d, rate, decay_s=0.004, hp_fc=2000):
    out = silence(d)
    n = int(d * rate)
    for _ in range(n):
        i = rng.integers(0, len(out) - 400)
        L = int(decay_s * SR * 4)
        burst = rng.standard_normal(L) * np.exp(-np.arange(L) / (decay_s * SR)) * rng.uniform(0.2, 1)
        out[i:i + L] += burst[:len(out) - i]
    return hp(out, hp_fc)


def save(name, x, bus="SFX", volume=0.0, loop=False, range_m=80.0, peak_db=-1.0):
    x = np.asarray(x, dtype=np.float64)
    if not loop:
        x = trim_tail(x)
    x = x - np.mean(x) if loop else x
    x = x / (np.abs(x).max() + 1e-9) * 10 ** (peak_db / 20)
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    MANIFEST[name] = {"bus": bus, "volume_db": volume, "loop": loop, "range": range_m,
                      "length": round(len(x) / SR, 3)}
    print(f"  {name:22s} {len(x) / SR:5.2f}s  {bus:9s} {'loop' if loop else ''}")


# ------------------------------------------------------------------ mech
def footstep(k):
    d = 1.2
    thud = sweep(.5, 75 + k * 4, 32) * decay(.5, .13) * 1.0
    body = lp(noise(.3), 220) * decay(.3, .05) * 1.4
    clank = metal(.6, 170 + k * 35, taus=(.25, .15, .1, .06, .04), amps=(.5, .4, .3, .2, .1)) * .35
    hiss = hp(noise(.35), 2500) * decay(.35, .09, attack=.03) * .12
    gravel = crackle(.25, 90, .002, 1500) * .25
    x = mix(at(thud, 0, d), at(body, 0, d), at(clank, .008, d), at(hiss, .05, d), at(gravel, 0, d))
    return reverb(drive(x, 1.6), 0.9, .18, 3000)


def land():
    d = 2.0
    thud = sweep(.9, 60, 22) * decay(.9, .28) * 1.2
    body = lp(noise(.5), 180) * decay(.5, .1) * 1.6
    clanks = mix(*[at(metal(.8, f, taus=(.4, .25, .15, .08, .05)) * a, o, 1.2)
                   for f, a, o in ((140, .5, 0), (210, .35, .03), (95, .4, .06))])
    rattle = crackle(.7, 60, .003, 1200) * decay(.7, .25) * .5
    hiss = hp(noise(.8), 2000) * decay(.8, .25, .05) * .18
    x = mix(at(thud, 0, d), at(body, 0, d), at(clanks, 0, d), at(rattle, .05, d), at(hiss, .1, d))
    return reverb(drive(x, 2.2), 1.6, .25, 2500)


def servo_loop():
    d = 2.0
    t = t_(d)
    vib = 1 + .004 * np.sin(2 * np.pi * 3 * t)
    whine = sum(a * np.sin(2 * np.pi * f * np.cumsum(vib) / SR) for f, a in ((220, 1), (440, .45), (660, .25), (1320, .12)))
    grind = bp(noise(d + .5), 900, 2600)[:len(t)] * .25
    motor = am(tone(d, 55, (1, .5)), 30, .4) * .4
    return seamless(mix(whine * .5, grind, motor), .3)


def thruster_loop():
    d = 3.0
    roar = lp(brown(d + .5), 700)[:int(d * SR)] * 1.0
    hiss = bp(pink(d + .5), 1500, 7000)[:int(d * SR)] * .5
    rumble = lp(noise(d + .5), 80)[:int(d * SR)] * 2.5
    crack = crackle(d, 40, .003, 3000) * .3
    return seamless(drive(mix(roar, hiss, rumble, crack), 1.8), .4)


def thruster_start():
    d = 1.0
    t = t_(d)
    whoosh = noise(d)
    cut = 300 + 3000 * (t / d) ** .6
    out = np.zeros_like(t)
    for i in range(0, len(t), 2048):     # sweeping band
        seg = whoosh[i:i + 2048]
        out[i:i + len(seg)] = bp(seg, cut[i] * .6, cut[i] * 1.6, 2)
    env = np.minimum(1, t / .15) * np.exp(-np.maximum(0, t - .3) / .35)
    pop = sweep(.25, 120, 40) * decay(.25, .07)
    return reverb(drive(mix(out * env * 1.2, at(pop, 0, d)), 2.0), .8, .2)


def reactor_hum_loop():
    d = 4.0
    hum = tone(d, 55, (1, .6, .3, .15)) + .5 * tone(d, 55.5, (1, .4))
    fan = lp(pink(d + .5), 500)[:int(d * SR)] * .5
    return seamless(mix(hum * .6, fan), .5)


# ------------------------------------------------------------------ weapons + impacts
def autocannon(k):
    d = 1.2
    crack = hp(noise(.12), 1200) * decay(.12, .018) * 1.2
    boom = sweep(.4, 140 + 10 * k, 38) * decay(.4, .11) * 1.1
    body = bp(noise(.3), 150, 900) * decay(.3, .05) * .8
    clack = metal(.2, 950 + 60 * k, taus=(.05, .03, .02, .015, .01)) * .35
    shell = metal(.5, 2300 + 200 * k, taus=(.12, .08, .05, .03, .02), amps=(.4, .3, .2, .1, .05)) * .12
    x = mix(at(crack, 0, d), at(boom, 0, d), at(body, 0, d), at(clack, .055, d), at(shell, .25, d))
    return reverb(drive(x, 3.0), 1.2, .22, 3500)


def missile_launch():
    d = 2.0
    t = t_(1.4)
    w = noise(1.4)
    out = np.zeros_like(t)
    for i in range(0, len(t), 2048):
        seg = w[i:i + 2048]
        c = 500 + 2200 * min(1, t[i] / .4)
        out[i:i + len(seg)] = bp(seg, c * .5, c * 1.8, 2)
    env = np.minimum(1, t / .05) * np.exp(-t / .5)
    pop = sweep(.3, 180, 50) * decay(.3, .06) * 1.2
    hiss = hp(noise(1.2), 4000) * decay(1.2, .5) * .25
    x = mix(at(pop, 0, d), at(out * env, 0, d), at(hiss, .05, d))
    return reverb(drive(x, 2.0), 1.4, .3, 4000)


def explosion(size):
    d = 2.5 + 2 * size
    boom = sweep(1.2 + size, 70 - 10 * size, 18) * decay(1.2 + size, .35 + .3 * size) * 1.4
    blast = lp(noise(d), 900 + 600 * size) * decay(d, .3 + .45 * size, .004) * 1.6
    crack = hp(noise(.2), 1500) * decay(.2, .03) * .8
    debris = crackle(d * .7, 70 + 40 * size, .004, 900) * decay(d * .7, .5 + .3 * size) * .6
    rumble = lp(noise(d), 60) * decay(d, .9 + size) * 3.0
    x = mix(at(boom, 0, d), at(blast, 0, d), at(crack, 0, d), at(debris, .1, d), at(rumble, 0, d))
    return reverb(drive(x, 3.5 + size), 2.2 + size, .35, 2200)


def ram_fist():
    d = 1.4
    hiss = hp(noise(.12), 2000) * decay(.12, .05, .02) * .4
    slam = metal(1.0, 110, taus=(.5, .3, .2, .1, .06)) * 1.0
    thud = sweep(.4, 90, 35) * decay(.4, .12) * 1.2
    x = mix(at(hiss, 0, d), at(thud, .07, d), at(slam, .07, d))
    return reverb(drive(x, 2.2), 1.0, .2)


def impact_metal(k):
    d = 1.0
    clang = metal(.9, (320, 410, 520)[k] , taus=(.35, .2, .12, .07, .04))
    hit = bp(noise(.08), 800, 5000) * decay(.08, .01) * .9
    return reverb(drive(mix(clang * .7, hit), 1.8), .7, .15)


def impact_ground():
    d = .9
    thud = sweep(.3, 110, 45) * decay(.3, .08)
    crunch = bp(noise(.4), 300, 2500) * decay(.4, .06) * .8
    grit = crackle(.4, 120, .002, 2500) * decay(.4, .12) * .4
    return reverb(mix(thud, crunch, at(grit, .01, .45)), .8, .15)


def armor_break():
    d = 1.6
    t = t_(.5)
    tear = bp(noise(.5), 600, 4000) * (0.5 + 0.5 * signal.square(2 * np.pi * 38 * t)) * decay(.5, .2) * .7
    clang = metal(1.1, 260, taus=(.4, .25, .15, .08, .05)) * .8
    rattle = crackle(.8, 50, .003, 1500) * decay(.8, .3) * .5
    x = mix(at(tear, 0, d), at(clang, .05, d), at(rattle, .2, d))
    return reverb(drive(x, 2.0), 1.0, .2)


def crate_break():
    d = 1.1
    snaps = mix(*[at(bp(noise(.06), 400, 3000) * decay(.06, .008) * rng.uniform(.5, 1), o, .6)
                  for o in rng.uniform(0, .18, 7)])
    thump = sweep(.25, 120, 50) * decay(.25, .06) * .8
    bits = crackle(.5, 80, .003, 1800) * decay(.5, .15) * .4
    return reverb(mix(at(snaps, 0, d), at(thump, 0, d), at(bits, .08, d)), .7, .12)


# ------------------------------------------------------------------ arena
def gate_motor_loop():
    d = 3.0
    hum = tone(d, 45, (1, .7, .35)) * .5
    gears = am(bp(noise(d + .5), 200, 1200)[:int(d * SR)], 14, .8) * .6
    hyd = hp(pink(d + .5), 1800)[:int(d * SR)] * .15
    return seamless(drive(mix(hum, gears, hyd), 1.5), .4)


def gate_slam():
    d = 3.5
    thud = sweep(1.0, 55, 20) * decay(1.0, .35) * 1.4
    clang = mix(metal(2.0, 62, taus=(1.2, .8, .5, .3, .2)), metal(2.0, 97, taus=(.9, .6, .4, .2, .1)) * .6) * .8
    body = lp(noise(.6), 300) * decay(.6, .12) * 1.4
    x = mix(at(thud, 0, d), at(clang, 0, d), at(body, 0, d))
    return reverb(drive(x, 2.5), 3.0, .4, 1800)


def crowd_loop():
    d = 8.0
    n = int((d + .6) * SR)
    voices = np.zeros(n)
    for lo, hi, rate in ((250, 700, 1.3), (600, 1400, 1.9), (1200, 2800, 2.7), (2500, 4500, 3.5)):
        voices += am(bp(pink(n / SR), lo, hi), rate, .75)
    chatter = am(bp(noise(n / SR), 700, 2200), 9, .9) * .3
    return seamless(mix(voices, chatter)[:n], .6)


def crowd_cheer():
    d = 4.0
    t = t_(d)
    env = np.minimum(1, t / .35) * np.exp(-np.maximum(0, t - .6) / 1.3)
    roar = mix(*[am(bp(pink(d), lo, hi), r, .5) * a for lo, hi, r, a in
                 ((300, 900, 3, 1), (800, 2000, 4, .9), (1800, 4200, 6, .6))])
    whistles = sum(np.sin(2 * np.pi * np.cumsum(np.full(len(t), f) + 60 * np.sin(2 * np.pi * .7 * t + p)) / SR)
                   * (np.abs(np.sin(np.pi * t / d * k)) ** 8) for f, p, k in ((2400, 0, 3), (2900, 1, 5))) * .08
    return reverb(roar * env + whistles * env, 2.0, .35)


def beep(f, d=.16):
    t = t_(d)
    env = np.minimum(1, t / .005) * np.minimum(1, (d - t) / .03)
    return tone(d, f, (1, .2, .05)) * env


def fight_horn():
    d = 1.8
    t = t_(d)
    vib = 1 + .006 * np.sin(2 * np.pi * 5.5 * t)
    saw = lambda f: signal.sawtooth(2 * np.pi * f * np.cumsum(vib) / SR)
    chord = (saw(220) + saw(277.2) * .8 + saw(329.6) * .7 + saw(110) * .6)
    env = np.minimum(1, t / .06) * np.minimum(1, np.maximum(0, d - t) / .35)
    return reverb(drive(lp(chord, 2200) * env, 1.5), 2.0, .35)


# ------------------------------------------------------------------ cockpit + ui
def lock_tick():
    return beep(1500, .045)


def lock_tone_loop():
    d = .4
    t = t_(d)
    gate = (np.sin(2 * np.pi * 10 * t) > 0).astype(float)
    gate = lp(gate, 200, 2)
    return tone(d, 1600, (1, .15)) * gate


def target_switch():
    return mix(beep(900, .06), at(beep(1350, .07), .06, .14))


def warning_beep():
    return mix(beep(620, .12), at(beep(620, .12), .18, .32)) * 1.0


def ui_click():
    d = .05
    return tone(d, 2100) * decay(d, .006) + hp(noise(d), 3000) * decay(d, .002) * .4


def ui_hover():
    return tone(.03, 3200) * decay(.03, .004) * .5


def ui_confirm():
    return mix(beep(660, .1), at(beep(990, .16), .08, .26))


def ui_error():
    d = .26
    t = t_(d)
    return signal.square(2 * np.pi * 140 * t) * np.minimum(1, (d - t) / .04) * .5 * (1 - .4 * (t > .12))


def ui_purchase():
    d = .9
    bell = metal(d, 1250, ratios=(1, 2.0, 2.76, 4.1, 5.4), taus=(.5, .35, .25, .15, .1), amps=(1, .5, .4, .25, .15))
    bell2 = metal(d, 1660, ratios=(1, 2.0, 2.76, 4.1, 5.4), taus=(.5, .35, .25, .15, .1), amps=(1, .5, .4, .25, .15))
    return reverb(mix(bell * .6, at(bell2 * .6, .09, d)), 1.0, .25, 6000)


# ------------------------------------------------------------------ ambience
def workshop_ambience_loop():
    d = 10.0
    n = int((d + .8) * SR)
    hum = tone(n / SR, 60, (1, .5, .25)) * .25
    vent = lp(pink(n / SR), 700) * .6
    clanks = np.zeros(n)
    for _ in range(9):
        c = reverb(metal(1.0, rng.uniform(250, 900), taus=(.3, .2, .1, .06, .04)) * rng.uniform(.1, .3), 1.5, .6, 2500)
        i = rng.integers(0, n - len(c))
        clanks[i:i + len(c)] += c
    return seamless(mix(hum, vent, clanks)[:n], .8)


def weld_loop():
    d = 3.0
    n = int((d + .4) * SR)
    sizzle = am(hp(noise(n / SR), 3000), 20, .8) * .5
    crack = crackle(n / SR, 220, .0015, 2500) * 1.2
    buzz = am(tone(n / SR, 100, (1, .5, .3)) * .1, 6, .7)
    return seamless(mix(sizzle, crack, buzz)[:n], .4)


def wind_loop():
    d = 8.0
    n = int((d + .8) * SR)
    w = am(lp(pink(n / SR), 600), .5, .7) + am(bp(noise(n / SR), 800, 1800), .8, .9) * .15
    return seamless(w[:n], .8)


def salvage_search():
    d = 1.8
    clinks = mix(*[at(metal(.4, rng.uniform(500, 1600), taus=(.12, .08, .05, .03, .02)) * rng.uniform(.2, .6), o, d)
                   for o in np.sort(rng.uniform(0, 1.3, 9))])
    scrape = am(bp(noise(1.4), 400, 2500), 6, .8) * .4
    return reverb(mix(clinks, at(scrape, .1, d)), .8, .15)


def main():
    print("Synthesizing sounds ->", os.path.relpath(OUT, ROOT))
    for k in range(3):
        save(f"footstep_{k + 1}", footstep(k), volume=-2, range_m=110)
    save("land_heavy", land(), volume=0, range_m=140)
    save("servo_loop", servo_loop(), volume=-10, loop=True, range_m=40)
    save("thruster_loop", thruster_loop(), volume=-3, loop=True, range_m=150)
    save("thruster_start", thruster_start(), volume=-2, range_m=150)
    save("reactor_hum_loop", reactor_hum_loop(), volume=-16, loop=True, range_m=25)
    for k in range(3):
        save(f"autocannon_{k + 1}", autocannon(k), volume=-2, range_m=220)
    save("missile_launch", missile_launch(), volume=-2, range_m=200)
    save("ram_fist", ram_fist(), volume=-1, range_m=120)
    save("explosion_small", explosion(0), volume=0, range_m=250)
    save("explosion_large", explosion(1), volume=0, range_m=320)
    for k in range(3):
        save(f"impact_metal_{k + 1}", impact_metal(k), volume=-4, range_m=120)
    save("impact_ground", impact_ground(), volume=-6, range_m=90)
    save("armor_break", armor_break(), volume=-2, range_m=140)
    save("crate_break", crate_break(), volume=-3, range_m=100)
    save("gate_motor_loop", gate_motor_loop(), volume=-4, loop=True, range_m=120)
    save("gate_slam", gate_slam(), volume=0, range_m=260)
    save("crowd_loop", crowd_loop(), bus="Ambience", volume=-14, loop=True)
    save("crowd_cheer", crowd_cheer(), bus="Ambience", volume=-6)
    save("countdown_beep", beep(880), bus="UI", volume=-6)
    save("fight_horn", fight_horn(), bus="UI", volume=-3)
    save("lock_tick", lock_tick(), bus="UI", volume=-12)
    save("lock_tone_loop", lock_tone_loop(), bus="UI", volume=-14, loop=True)
    save("target_switch", target_switch(), bus="UI", volume=-10)
    save("warning_beep", warning_beep(), bus="UI", volume=-10)
    save("ui_click", ui_click(), bus="UI", volume=-8)
    save("ui_hover", ui_hover(), bus="UI", volume=-18)
    save("ui_confirm", ui_confirm(), bus="UI", volume=-8)
    save("ui_error", ui_error(), bus="UI", volume=-12)
    save("ui_purchase", ui_purchase(), bus="UI", volume=-6)
    save("workshop_ambience_loop", workshop_ambience_loop(), bus="Ambience", volume=-12, loop=True)
    save("weld_loop", weld_loop(), volume=-14, loop=True, range_m=30)
    save("wind_loop", wind_loop(), bus="Ambience", volume=-16, loop=True)
    save("salvage_search", salvage_search(), volume=-4, range_m=50)
    os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
    with open(os.path.join(ROOT, "data", "sounds.json"), "w") as f:
        json.dump({"generated_by": "tools/audio/build_sounds.py", "sounds": MANIFEST}, f, indent=1, sort_keys=True)
    print(f"WROTE data/sounds.json ({len(MANIFEST)} sounds)")


if __name__ == "__main__":
    main()
