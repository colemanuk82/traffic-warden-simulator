"""Generates every voice line for Traffic Warden Sim with Kokoro, an offline neural text-to-speech model.

Replaces the old espeak-ng voices. The line tables still live in gen_audio.py and gen_audio_extra.py;
this script gives each line a cast member (British men and women, kids, Santa, an announcer) and writes
the same file names into audio/voice, so the game picks them up with no code changes.

Takes 0 and 1 of every heckle and driver line are men, takes 2 and 3 are women (driver.gd and car.gd
pick a take that matches the character on screen).

Run:  python3 tools/gen_voices.py   (needs numpy, scipy, ffmpeg, kokoro-onnx, soundfile)
Model: kokoro-v1.0.onnx and voices-v1.0.bin from
       https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0
       in tools/kokoro/ (or set KOKORO_DIR).
"""
import os
import sys

import numpy as np
from scipy import signal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_audio as ga  # noqa: E402
import gen_audio_extra as gx  # noqa: E402
from gen_audio import SR, highpass, bandpass, write_ogg, mono_to_stereo  # noqa: E402

MODEL_DIR = os.environ.get("KOKORO_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "kokoro"))
VOICE_DIR = os.path.join(ga.ROOT, "voice")

_kokoro = None


def kokoro():
    global _kokoro
    if _kokoro is None:
        from kokoro_onnx import Kokoro
        _kokoro = Kokoro(os.path.join(MODEL_DIR, "kokoro-v1.0.onnx"), os.path.join(MODEL_DIR, "voices-v1.0.bin"))
    return _kokoro


# ------------------------------------------------------------------ the cast
# (voice or [(voice, weight), ...], speed, semitones, lang, style)
# style: "shout" (a bit of grit), "talk", "radio" (tannoy announcer), "kid"

MEN = [
    ("bm_george", 1.08, 0, "en-gb", "shout"),
    ("bm_lewis", 1.12, -1, "en-gb", "shout"),
    ("bm_daniel", 1.1, 1, "en-gb", "shout"),
    ("bm_fable", 1.08, 0, "en-gb", "shout"),
    ([("bm_george", 0.5), ("bm_lewis", 0.5)], 1.1, -2, "en-gb", "shout"),
    ([("bm_daniel", 0.6), ("bm_fable", 0.4)], 1.15, 2, "en-gb", "shout"),
]
WOMEN = [
    ("bf_emma", 1.08, 0, "en-gb", "shout"),
    ("bf_isabella", 1.1, 0, "en-gb", "shout"),
    ("bf_alice", 1.1, 1, "en-gb", "shout"),
    ("bf_lily", 1.08, 0, "en-gb", "shout"),
    ([("bf_emma", 0.5), ("bf_alice", 0.5)], 1.12, -1, "en-gb", "shout"),
    ([("bf_isabella", 0.5), ("bf_lily", 0.5)], 1.15, 1, "en-gb", "shout"),
]
KIDS = [
    ("bf_lily", 1.0, 5, "en-gb", "kid"),
    ("af_sky", 1.0, 4, "en-us", "kid"),
    ("bf_alice", 1.0, 6, "en-gb", "kid"),
    ("bm_fable", 1.0, 7, "en-gb", "kid"),
]
ANNOUNCER = ("bm_george", 0.95, -2, "en-gb", "radio")
WARDEN = ("bm_fable", 1.0, 0, "en-gb", "talk")
WARDEN_RADIO = ("bm_fable", 1.0, 0, "en-gb", "radio")
SANTA = ("am_santa", 0.9, -1, "en-us", "talk")
MAYOR = ("bm_daniel", 0.92, -1, "en-gb", "shout")
VANMAN = ([("bm_lewis", 0.7), ("bm_george", 0.3)], 1.15, -2, "en-gb", "shout")
GETAWAY = ("am_fenrir", 1.15, 0, "en-us", "shout")
DRUNK = ("bm_lewis", 0.82, -1, "en-gb", "talk")
GEEZER = ([("bm_lewis", 0.6), ("bm_daniel", 0.4)], 1.2, 0, "en-gb", "talk")
STAG = ("am_puck", 1.15, 0, "en-us", "shout")
CAROLLER = ("bf_isabella", 0.95, 1, "en-gb", "talk")
ELF = ("am_puck", 1.1, 6, "en-us", "kid")

# A few lines read better with a nudge to the pronunciation or delivery
SAY = {
    "Hi vis, low I Q!": "Hi-vis, low I.Q.!",
    "Boo! Boooo!": "Boo! Boo-ooo!",
    "Ooof!": "Oof!",
    "#@%&!": "",
    "Ho ho no!": "Ho, ho... NO!",
    "Wahey!": "Wa-hey!",
    "Lads lads lads!": "Lads! Lads! Lads!",
    "Bwok bwok! Chicken man!": "Bwok, bwok, bwok! Chicken man!",
    "Robocop on a budget!": "Robo-cop, on a budget!",
    "Fa la la la la!": "Fa la la la laaa!",
}


def _style(voice):
    k = kokoro()
    if isinstance(voice, str):
        return voice
    mix = None
    for name, w in voice:
        s = k.get_voice_style(name) * w
        mix = s if mix is None else mix + s
    return mix


def _trim(x, thresh=0.02):
    idx = np.where(np.abs(x) > thresh * np.max(np.abs(x)))[0]
    if len(idx) == 0:
        return x
    a = max(idx[0] - int(0.01 * SR), 0)
    b = min(idx[-1] + int(0.06 * SR), len(x))
    return x[a:b]


def _echo(x, taps=((0.045, 0.25), (0.09, 0.15), (0.16, 0.08))):
    out = np.concatenate([x, np.zeros(int(0.2 * SR))])
    for d, g in taps:
        n = int(d * SR)
        out[n:n + len(x)] += x * g
    return out


def speak(text, who):
    voice, speed, semis, lang, style = who
    text = SAY.get(text, text)
    ratio = 2 ** (semis / 12.0)
    # A pitch shift by resampling also speeds the line up, so ask the model to talk slower to match
    samples, sr = kokoro().create(text, voice=_style(voice), speed=speed / ratio, lang=lang)
    x = np.asarray(samples, dtype=np.float64)
    up, down = SR, int(round(sr * ratio))
    g = np.gcd(up, down)
    x = signal.resample_poly(x, up // g, down // g)
    x = _trim(x)
    x = highpass(x, 90)
    if style == "shout":
        x = x / (np.max(np.abs(x)) + 1e-9)
        x = np.tanh(x * 1.8) / np.tanh(1.8)
    elif style == "radio":
        x = bandpass(x, 300, 4200)
        x = x / (np.max(np.abs(x)) + 1e-9)
        x = _echo(np.tanh(x * 2.2) / np.tanh(2.2))
    elif style == "kid":
        x = highpass(x, 180)
    fade = int(0.008 * SR)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    return ga.norm(x, 0.9)


def say(name, text, who):
    if not text:
        return
    write_ogg(os.path.join(VOICE_DIR, name + ".ogg"), mono_to_stereo(speak(text, who)))
    print(name, "-", text)


def four_takes(prefix, text, i):
    """Two men and two women read the line; each line gets a different pair from the cast."""
    say(prefix + "_0", text, MEN[(i * 2) % len(MEN)])
    say(prefix + "_1", text, MEN[(i * 2 + 3) % len(MEN)])
    say(prefix + "_2", text, WOMEN[i % len(WOMEN)])
    say(prefix + "_3", text, WOMEN[(i + 3) % len(WOMEN)])


def main():
    only = sys.argv[1:]

    def want(group):
        return not only or group in only

    if want("heckles"):
        for i, line in enumerate(ga.HECKLES + ga.MORE_HECKLES):
            four_takes("heckle_%d" % i, line, i)
        for i, line in enumerate(gx.FAMILY_HECKLES):
            four_takes("heckle_ff_%d" % i, line, i + 2)
        for prefix, lines in (("hheckle", ga.HALLOWEEN_HECKLES), ("xheckle", ga.CHRISTMAS_HECKLES)):
            for i, line in enumerate(lines):
                four_takes("%s_%d" % (prefix, i), line, i + 1)
        for j, line in enumerate(ga.GROUP_LINES["heckle_splash"][0]):
            say("heckle_splash_%d" % j, line, MEN[j * 2] if j < 2 else WOMEN[j])
    if want("drivers"):
        lines = dict(ga.DRIVER_LINES)
        lines.update(gx.NEW_DRIVER_LINES)
        for g in ("driver_hween", "driver_ghoul", "driver_xmas", "driver_grinch"):
            lines[g[len("driver_"):]] = ga.SEASONAL_GROUPS[g][0][0]
        for i, (key, line) in enumerate(lines.items()):
            four_takes("driver_" + key, line, i)
        for key, line in ga.PUNCHED_LINES.items():
            say("punched_" + key, line, MEN[len(key) % len(MEN)])
            say("punched_%s_2" % key, line, WOMEN[len(key) % len(WOMEN)])
    if want("excuses"):
        for i, (key, line) in enumerate(gx.EXCUSE_LINES.items()):
            four_takes("driver_x_" + key, line, i + 1)
    if want("insults"):
        for i, (key, line) in enumerate(gx.INSULT_LINES.items()):
            four_takes("driver_i_" + key, line, i + 2)
    if want("warden"):
        for key, line in ga.WARDEN_LINES.items():
            say("warden_" + key, line, WARDEN)
        for key, line in ga.ANNOUNCER.items():
            say("announce_" + key, line, ANNOUNCER)
        for key, (line, who) in ga.EXTRA_LINES.items():
            say(key, line, ANNOUNCER if who == "announcer" else WARDEN_RADIO)
    if want("characters"):
        cast = {"boss_mayor": MAYOR, "boss_vanman": VANMAN, "boss_getaway": GETAWAY, "ped_drunk": DRUNK,
                "ped_geezer": GEEZER, "ped_stag": STAG}
        for group, who in cast.items():
            for j, line in enumerate(ga.GROUP_LINES[group][0]):
                say("%s_%d" % (group, j), line, who)
        seasonal = {"santa_hohoho": SANTA, "santa_naughty": SANTA, "ped_caroller": CAROLLER, "ped_elf": ELF}
        for group, who in seasonal.items():
            for j, line in enumerate(ga.SEASONAL_GROUPS[group][0]):
                say("%s_%d" % (group, j), line, who)
        for group in ("kid_tot", "kid_thanks", "kid_trick"):
            for j, line in enumerate(ga.SEASONAL_GROUPS[group][0]):
                say("%s_%d" % (group, j), line, KIDS[j % len(KIDS)])
    print("voices done")


if __name__ == "__main__":
    main()
