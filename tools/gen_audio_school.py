"""Generates the School Patrol and Rampage update (1.3.0) for Traffic Warden Sim.

- music/rampage.ogg: "Batter Up!", galloping heavy metal with twin harmony guitars and a shouted
  "RAMPAGE!" chant, played while the warden has the baseball bat.
- sfx: bat_hit (a wooden TOK), bat_swing (a big whoosh), smash (cartoon glass and tin crunch), explode,
  car_alarm (a short wee-woo) and school_bell.
- voices: the school-run heckles, parents' shouts, kids saying goodbye, the lollipop ladies and the
  rampage callouts, read by Kokoro (see gen_voices.py).

Run:  python3 tools/gen_audio_school.py [music] [sfx] [voices]   (needs numpy, scipy, ffmpeg, kokoro-onnx)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_audio as ga  # noqa: E402
import gen_audio_extra as gx  # noqa: E402
import gen_audio_metal as gm  # noqa: E402
from gen_audio import SR, Song, lowpass, highpass, bandpass, write_ogg, mono_to_stereo  # noqa: E402

rng = np.random.default_rng(1303)

# Lines shown on screen in levels.gd use the same order, so line i plays sheckle_<i>_<take>.ogg
SCHOOL_HECKLES = [
    "I'm only dropping the kids off!", "It's the school run, mate!", "I'm late for work!",
    "Two minutes, that's all!", "Detention for you!", "Everyone parks here!",
    "The kids are watching, jobsworth!", "Go back to school!",
]
SCHOOL_DRIVER_LINES = {
    "dropoff": "I'm only dropping off!",
    "late": "We're late for school!",
    "betterdo": "Haven't you got anything better to do?!",
    "behave": "Glad you're here, they behave when you are!",
}
KID_BYE = ["Bye Mum!", "Bye Dad!", "See you later!", "Love you!", "Bye!", "See you at home time!"]
LOLLIPOP_LINES = ["Stop! Children crossing!", "Wait there, please!", "Slow down, driver!", "Mind the little ones!",
                  "Thank you, driver!"]
LOLLIPOP_WHISTLED = ["Oi! That's my job!", "Cheeky!"]


# ------------------------------------------------------------------ music

GALLOP = {"kick": "x.xxx.xxx.xxx.xx", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."}
DRIVE = {"kick": "x.x.x.x.x.x.x.x.", "snare": "....x.......x...", "ride": "xxxxxxxx"}


def track_rampage():
    """Batter Up!: galloping heavy metal, twin harmony leads and a big gang shout of RAMPAGE!"""
    s = Song(178, 32)
    gallop = "E2:.5p E2:.25p E2:.25p E2:.5p E2:.25p E2:.25p G2:.5 E2:.25p E2:.25p A2:.5 G2:.5"
    climb = "C3:.5 C3:.25 C3:.25 D3:.5 D3:.25 D3:.25 E3:.5 E3:.25 E3:.25 G3:.5 F#3:.5"
    # Intro: a dive bomb and a drum roll into the riff
    gm.drums(s, 1, {"tom": "........xxxxxxxx", "crash": "x..............."})
    s.add(gm.whammy_lead(ga.hz(ga.midi("E5")), 2.6 * s.spb, 1.0), 0, "lead", 0.0, 0.9)
    gm.guitar(s, "E2:4p", 0, 1, step=0.25, palm=True, drive=24.0)
    gm.drums(s, 15, GALLOP, 1)
    gm.crash_on(s, range(1, 32, 4))
    gm.guitar(s, gallop, 1, 15, step=0.25, drive=24.0)
    gm.sing(s, ["RAMPAGE!", "RAMPAGE!"], 5, every=4, gain=0.85, semis=-4)
    # Twin harmony lead over the gallop, a third apart like the old greats
    twin = """
E5:.5 F#5:.5 G5:.5 A5:.5 B5:1 A5:.5 G5:.5
F#5:.5 G5:.5 A5:.5 F#5:.5 E5:2
G5:.5 A5:.5 B5:.5 C6:.5 D6:1 C6:.5 B5:.5
A5:.5 B5:.5 G5:.5 A5:.5 B5:2
"""
    s.melody(twin, gm.whammy_lead, 9, gain=0.8, pan=-0.3)
    s.melody(twin, gm.whammy_lead, 9, gain=0.6, pan=0.3, transpose=4)
    gm.fill(s, 15)
    # Chorus: driving eighths, the climb and the chant
    gm.drums(s, 8, DRIVE, 16)
    gm.guitar(s, climb, 16, 8, step=0.25, drive=24.0)
    gm.sing(s, ["RAMPAGE!", "BATTER UP!", "RAMPAGE!", "SMASH IT UP!"], 16, every=2, gain=0.9, semis=-4)
    # Shred solo to round off the loop
    gm.drums(s, 8, GALLOP, 24)
    gm.guitar(s, gallop, 24, 8, step=0.25, drive=24.0)
    shred = """
E5:.25 G5:.25 B5:.25 E6:.25 B5:.25 G5:.25 E5:.25 G5:.25 A5:.25 C6:.25 E6:.25 C6:.25 A5:.25 E5:.25 A5:.25 C6:.25
B5:.25 D6:.25 F#6:.25 D6:.25 B5:.25 F#5:.25 B5:.25 D6:.25 E6:1 D6:.5 B5:.5
"""
    for b in range(24, 32, 2):
        s.melody(shred, gm.whammy_lead, b, gain=0.75, transpose=0 if b % 4 == 0 else 2)
    gm.fill(s, 31)
    return gm.master(s)


# ------------------------------------------------------------------ effects

def _n(dur):
    return int(dur * SR)


def bat_hit():
    """A wooden TOK with a thump behind it."""
    n = _n(0.35)
    t = np.arange(n) / SR
    tok = np.sin(2 * np.pi * 820 * t) * np.exp(-t * 55) + 0.6 * np.sin(2 * np.pi * 1340 * t) * np.exp(-t * 70)
    thump = np.sin(2 * np.pi * 110 * t * (1 - 0.4 * t)) * np.exp(-t * 18)
    click = bandpass(rng.standard_normal(n), 1500, 6000) * np.exp(-t * 160) * 0.6
    return ga.norm(tok * 0.7 + thump + click, 0.9)


def bat_swing():
    """A big, low whoosh."""
    n = _n(0.4)
    t = np.arange(n) / SR
    env = np.sin(np.pi * np.clip(t / 0.4, 0, 1)) ** 2
    x = rng.standard_normal(n)
    lo = lowpass(x, 900)
    hi = bandpass(x, 900, 2600) * np.clip(t / 0.4, 0, 1)
    return ga.norm((lo + hi * 0.5) * env, 0.7)


def smash():
    """Cartoon car smash: a tinny crunch, then glass tinkling down."""
    n = _n(1.1)
    t = np.arange(n) / SR
    crunch = bandpass(rng.standard_normal(n), 200, 3000) * np.exp(-t * 14)
    crunch += 0.8 * np.sin(2 * np.pi * 70 * t) * np.exp(-t * 20)
    clang = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, d in ((523, 9), (790, 11), (1187, 13))) * 0.25
    glass = np.zeros(n)
    for _ in range(36):
        start = int(rng.uniform(0.03, 0.8) * SR)
        f = rng.uniform(2800, 7000)
        m = min(int(0.09 * SR), n - start)
        tt = np.arange(m) / SR
        glass[start:start + m] += np.sin(2 * np.pi * f * tt) * np.exp(-tt * 60) * rng.uniform(0.2, 0.6)
    glass += highpass(rng.standard_normal(n), 5000) * np.exp(-t * 6) * 0.25
    return ga.norm(crunch + clang + glass * 0.8, 0.9)


def explode():
    """A big cartoon KABOOM: a low boom, a crackling blast and debris rattling down."""
    n = _n(2.2)
    t = np.arange(n) / SR
    boom = np.sin(2 * np.pi * 48 * t * (1 - 0.25 * t)) * np.exp(-t * 3.0)
    blast = lowpass(rng.standard_normal(n), 1800) * np.exp(-t * 4.5) * 1.3
    crackle = highpass(rng.standard_normal(n) * (rng.random(n) < 0.02), 2000) * np.exp(-t * 2.0) * 2.0
    x = np.tanh((boom * 1.6 + blast + crackle) * 1.8)
    return ga.norm(x, 0.95)


def car_alarm():
    """Two rounds of a cartoon wee-woo."""
    n = _n(1.2)
    t = np.arange(n) / SR
    f = np.where((t * 2.5) % 1.0 < 0.5, 980, 740)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sign(np.sin(ph)) * 0.5 + np.sin(ph) * 0.5
    x = lowpass(x, 3500) * ga.adsr(n, a=0.01, d=0.05, s=1.0, r=0.1)
    return ga.norm(x, 0.6)


def school_bell():
    """An old electric school bell."""
    n = _n(1.6)
    t = np.arange(n) / SR
    strike = (np.sin(2 * np.pi * 26 * t) > 0).astype(float)
    tone = sum(np.sin(2 * np.pi * f * t) for f in (1250, 2710, 3980)) / 3
    env = np.clip((1.3 - t) * 4, 0, 1)
    x = tone * (0.55 + 0.45 * strike) * env
    return ga.norm(highpass(x, 400), 0.6)


# ------------------------------------------------------------------ voices

def voices():
    import gen_voices as gv
    lollipop_lady = ("bf_emma", 0.95, -1, "en-gb", "talk")
    for i, line in enumerate(SCHOOL_HECKLES):
        gv.four_takes("sheckle_%d" % i, line, i + 3)
    for i, (key, line) in enumerate(SCHOOL_DRIVER_LINES.items()):
        gv.four_takes("driver_" + key, line, i + 5)
    for j, line in enumerate(KID_BYE):
        gv.say("kid_bye_%d_0" % j, line, gv.KIDS[j % len(gv.KIDS)])
    for j, line in enumerate(LOLLIPOP_LINES):
        gv.say("lollipop_%d_0" % j, line, lollipop_lady)
    for j, line in enumerate(LOLLIPOP_WHISTLED):
        gv.say("lollipop_whistled_%d" % j, line, lollipop_lady)
    gv.say("announce_rampage_0", "RAMPAGE!", gv.ANNOUNCER)
    gv.say("announce_rampage_1", "Rampage mode!", gv.ANNOUNCER)
    gv.say("warden_batter_0", "Batter up!", gv.WARDEN)
    gv.say("warden_batter_1", "Who wants some?", gv.WARDEN)
    gv.say("warden_homerun_0", "Home run!", gv.WARDEN)
    gv.say("warden_homerun_1", "Out of the park!", gv.WARDEN)


def main():
    only = sys.argv[1:]
    if not only or "music" in only:
        print("music rampage", flush=True)
        write_ogg(os.path.join(ga.ROOT, "music", "rampage.ogg"), track_rampage(), quality=4)
    if not only or "sfx" in only:
        for name, fn in (("bat_hit", bat_hit), ("bat_swing", bat_swing), ("smash", smash),
                         ("car_alarm", car_alarm), ("school_bell", school_bell), ("explode", explode)):
            write_ogg(os.path.join(ga.ROOT, "sfx", name + ".ogg"), mono_to_stereo(fn()))
            print("sfx", name)
    if not only or "voices" in only:
        voices()
    print("school done")


if __name__ == "__main__":
    main()
