"""Generates the cat and garden bird sounds for Traffic Warden Sim (meow, hiss, purr, chirp, caw, gull).

Everything is synthesised with numpy/scipy, like the rest of the game's effects.
Run:  python3 tools/gen_animals.py   (needs numpy, scipy, ffmpeg)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_audio as ga  # noqa: E402
from gen_audio import SR, tvec, lowpass, highpass, bandpass, phase, norm, write_ogg, mono_to_stereo  # noqa: E402

rng = np.random.default_rng(11)


def formant(x, freqs, q=6.0):
    """Very rough vocal tract: sum of band-passes around each formant."""
    out = np.zeros_like(x)
    for f, g in freqs:
        out += g * bandpass(x, f / (1 + 1 / q), f * (1 + 1 / q))
    return out


def meow(dur=0.75, f0=520.0, up=1.5):
    t = tvec(dur)
    # Pitch rises then falls; the mouth opens ("mi-") then closes ("-aow")
    shape = np.sin(np.pi * t / dur) ** 0.7
    f = f0 * (1 + (up - 1) * np.sin(np.pi * np.clip(t / (dur * 0.8), 0, 1)))
    src = np.sign(np.sin(phase(f, t))) * 0.5 + np.sin(phase(f, t))
    open_ = np.clip(np.sin(np.pi * t / dur) * 1.4, 0, 1)
    vowel = formant(src, [(900 + 900 * open_.mean(), 1.0), (1700, 0.6), (3200, 0.25)])
    vowel = vowel * (0.3 + 0.7 * open_)
    return norm(lowpass(vowel * shape, 5000)) * 0.8


def hiss():
    t = tvec(0.7)
    x = highpass(rng.standard_normal(len(t)), 2500)
    env = np.minimum(t / 0.05, 1) * np.exp(-t * 2.5)
    return norm(x * env) * 0.6


def purr():
    t = tvec(1.6)
    rate = 26.0
    pulses = (0.5 + 0.5 * np.sin(2 * np.pi * rate * t)) ** 4
    x = lowpass(rng.standard_normal(len(t)), 300) * pulses
    breath = 0.6 + 0.4 * np.sin(2 * np.pi * t / 1.6 - np.pi / 2)
    fade = np.minimum(np.minimum(t / 0.1, 1), np.minimum((1.6 - t) / 0.2, 1))
    return norm(x * breath * fade) * 0.7


def chirp():
    out = np.zeros(int(0.9 * SR))
    at = 0.0
    for i in range(rng.integers(3, 6)):
        d = rng.uniform(0.05, 0.11)
        t = tvec(d)
        f0 = rng.uniform(3200, 5200)
        f = f0 * (1 + rng.uniform(-0.35, 0.35) * t / d)
        x = np.sin(phase(f, t)) * np.sin(np.pi * t / d) ** 2
        ga._place(out, x, at)
        at += d + rng.uniform(0.03, 0.09)
    return norm(out) * 0.45


def caw():
    out = np.zeros(int(1.0 * SR))
    for k in range(2):
        t = tvec(0.32)
        f = 520 * (1 - 0.15 * t / 0.32)
        src = np.sign(np.sin(phase(f, t))) + 0.4 * rng.standard_normal(len(t))
        x = formant(src, [(1100, 1.0), (1900, 0.7), (2900, 0.3)], 4.0) * np.sin(np.pi * t / 0.32) ** 0.5
        ga._place(out, np.tanh(x * 2), k * 0.42)
    return norm(out) * 0.6


def gull():
    out = np.zeros(int(1.3 * SR))
    for k in range(3):
        d = 0.3 if k else 0.45
        t = tvec(d)
        f = 1300 * (1 + 0.5 * np.sin(np.pi * t / d)) * (0.85 if k else 1.0)
        src = np.sin(phase(f, t)) + 0.3 * np.sign(np.sin(phase(f, t)))
        x = formant(src, [(1500, 1.0), (2800, 0.6)], 5.0) * np.sin(np.pi * t / d)
        ga._place(out, x, [0.0, 0.5, 0.85][k])
    return norm(out) * 0.55


def main():
    sfx = os.path.join(ga.ROOT, "sfx")
    sounds = {
        "meow": meow(), "meow2": meow(0.55, 640, 1.3), "meow3": meow(0.95, 430, 1.6),
        "hiss": hiss(), "purr": purr(), "chirp": chirp(), "chirp2": chirp(), "caw": caw(), "gull": gull(),
    }
    for name, x in sounds.items():
        write_ogg(os.path.join(sfx, name + ".ogg"), mono_to_stereo(x))
        print(name)


if __name__ == "__main__":
    main()
