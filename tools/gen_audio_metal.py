"""Generates the rock and metal update for Traffic Warden Sim: death metal (the new default soundtrack),
plus thrash, doom, groove, black, metalcore, nu-metal, hardcore punk, grunge, stoner and glam rock.

The death metal tracks have growled vocals with family-friendly lyrics ("TICKET OF DOOM!"). The growls are
read by the Kokoro neural voice (see gen_voices.py), pitched down, layered and put through distortion.

Builds on the synths in gen_audio.py and the guitars in gen_audio_extra.py. Everything is synthesised.
Run:  python3 tools/gen_audio_metal.py [track names...]   (needs numpy, scipy, ffmpeg, kokoro-onnx)
"""
import os
import sys

import numpy as np
from scipy import signal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_audio as ga  # noqa: E402
import gen_audio_extra as gx  # noqa: E402
from gen_audio import SR, Song, hz, midi, tvec, lowpass, highpass, bandpass, write_ogg  # noqa: E402

rng = np.random.default_rng(666)


# ------------------------------------------------------------------ drums

def metal_kick(v=1.0):
    """Tight, clicky kick that cuts through fast double bass."""
    t = tvec(0.16)
    f = 55 + 160 * np.exp(-t * 45)
    x = np.sin(ga.phase(f, t)) * np.exp(-t * 22)
    click = highpass(rng.standard_normal(len(t)), 2500) * np.exp(-t * 400) * 0.8
    return (x + click) * v


def metal_snare(v=1.0):
    t = tvec(0.2)
    noise = bandpass(rng.standard_normal(len(t)), 1500, 8000) * np.exp(-t * 20)
    tone = np.sin(2 * np.pi * 210 * t) * np.exp(-t * 25)
    return np.tanh((noise + tone * 0.8) * 1.6) * v


def ride(v=1.0):
    t = tvec(0.5)
    x = highpass(rng.standard_normal(len(t)), 6000) * np.exp(-t * 7)
    x += 0.3 * np.sin(2 * np.pi * 3200 * t) * np.exp(-t * 6)
    return x * 0.3 * v


def china(v=1.0):
    t = tvec(0.9)
    x = bandpass(rng.standard_normal(len(t)), 3000, 11000) * np.exp(-t * 5)
    return np.tanh(x * 2.0) * 0.3 * v


KIT = {
    "kick": (metal_kick, 0.0, 0.85), "snare": (metal_snare, 0.05, 0.6), "hat": (lambda v: ga.hat(v), 0.3, 0.5),
    "ride": (ride, 0.35, 0.6), "crash": (gx.crash, -0.3, 0.75), "china": (china, 0.4, 0.7),
    "tom": (None, 0.2, 0.8),
}


def drums(s, bars, pattern, start_bar=0, gain=1.0):
    """pattern: lane -> steps ('x' hit, 'o' soft, '.' rest), any number of steps per bar."""
    for bar in range(start_bar, start_bar + bars):
        for lane, steps in pattern.items():
            fn, pan, g = KIT[lane]
            n = len(steps)
            for i, ch in enumerate(steps):
                if ch == ".":
                    continue
                v = 1.0 if ch == "x" else 0.55
                beat = bar * 4 + i * 4.0 / n
                sig = gx.tom(160 - (i % 4) * 25, v) if lane == "tom" else fn(v)
                s.add(sig, beat, "drums", pan, g * gain)


def fill(s, bar, gain=1.0):
    drums(s, 1, {"tom": "....xxxxxxxxxxxx", "snare": "xxxx............", "kick": "x.x.x.x.x.x.x.x."}, bar, gain)


def crash_on(s, bars, gain=1.0):
    for b in bars:
        drums(s, 1, {"crash": "x..............."}, b, gain)


# ------------------------------------------------------------------ guitars

def guitar(s, notes, start_bar, bars, step=0.25, gain=1.0, palm=False, drive=18.0, transpose=0, bass=True):
    """Tremolo-picks a line: notes is 'C2:1 D#2:1 ...' (beats held), each held note picked every `step` beats."""
    tokens = [tok.split(":") for tok in notes.split()]
    beat = start_bar * 4.0
    end = (start_bar + bars) * 4.0
    while beat < end - 1e-6:
        for name, dur in tokens:
            d = float(dur.rstrip("p"))
            pm = palm or dur.endswith("p")
            if name != "r":
                f = hz(midi(name) + transpose)
                k = 0.0
                while k < d - 1e-6 and beat + k < end - 1e-6:
                    st = min(step, d - k)
                    sig = gx.power_chord(f, st * s.spb * 0.92, 1.0, pm, drive)
                    s.add(sig, beat + k, "gtr", -0.3, gain)
                    s.add(sig, beat + k + 0.008, "gtr", 0.3, gain * 0.9)
                    k += st
                if bass:
                    s.add(ga.bass_saw(f / 2, d * s.spb * 0.95), beat, "bass", 0, gain)
            beat += d
            if beat >= end - 1e-6:
                break


def chords(s, notes, start_bar, bars, gain=1.0, drive=22.0, transpose=0):
    """Big ringing chords, held for each note's length (doom, stoner, grunge)."""
    guitar(s, notes, start_bar, bars, step=64, gain=gain, drive=drive, transpose=transpose)


def fuzz_lead(f, dur, v=1.0):
    n = int(max(dur, 0.05) * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.008 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.2) * 3, 0, 1)
    ph = 2 * np.pi * f * np.cumsum(vib) / SR
    x = np.sign(np.sin(ph)) * 0.6 + 0.4 * (2 * ((ph / (2 * np.pi)) % 1.0) - 1)
    x = np.tanh(lowpass(x, 2800) * 6.0)
    return bandpass(x, 180, 4500) * ga.adsr(n, a=0.01, d=0.1, s=0.9, r=0.1) * 0.28 * v


def whammy_lead(f, dur, v=1.0):
    """Squealing lead with a dive at the end of long notes."""
    n = int(max(dur, 0.05) * SR)
    t = np.arange(n) / SR
    bend = np.where(t > dur * 0.7, 1 - 0.25 * ((t - dur * 0.7) / max(dur * 0.3, 1e-3)) ** 2, 1.0) if dur > 0.4 else 1.0
    vib = (1 + 0.01 * np.sin(2 * np.pi * 7 * t)) * bend
    ph = 2 * np.pi * f * np.cumsum(vib) / SR
    x = 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    x = np.tanh(lowpass(x, 4200) * 7.0)
    return bandpass(x, 250, 6000) * ga.adsr(n, a=0.005, d=0.08, s=0.9, r=0.06) * 0.27 * v


# ------------------------------------------------------------------ growled vocals

_growls = {}


def growl(text, semis=-7, seed=0):
    """A family-friendly death growl: Kokoro reads the line, then it's dropped, doubled and distorted."""
    key = (text, semis, seed)
    if key in _growls:
        return _growls[key]
    import gen_voices as gv
    r = np.random.default_rng(seed)
    takes = []
    for voice, shift in (("bm_lewis", semis), ("bm_george", semis - 5)):
        ratio = 2 ** (shift / 12.0)
        samples, sr = gv.kokoro().create(text, voice=voice, speed=0.95 / ratio * 0.9, lang="en-gb")
        x = np.asarray(samples, dtype=np.float64)
        up, down = SR, int(round(sr * ratio))
        g = np.gcd(up, down)
        takes.append(gv._trim(signal.resample_poly(x, up // g, down // g)))
    n = max(len(a) for a in takes)
    x = sum(np.pad(a, (0, n - len(a))) for a in takes)
    env = lowpass(np.abs(x), 30)
    env /= np.max(env) + 1e-9
    t = np.arange(n) / SR
    # Throat rasp: noise shaped by the voice's own envelope, plus a sub-harmonic buzz
    rasp = bandpass(r.standard_normal(n), 400, 3000) * env * 0.5
    sub = x * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 48 * t)))
    x = x + sub * 0.6 + rasp
    x = x / (np.max(np.abs(x)) + 1e-9)
    x = np.tanh(x * 6.0)
    x = bandpass(x, 110, 3800)
    x = ga.reverb(np.concatenate([x, np.zeros(int(0.4 * SR))]), 0.18)
    fade = int(0.01 * SR)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    x = ga.norm(x, 0.9)
    _growls[key] = x
    return x


def sing(s, lines, start_bar, every=2, gain=0.9, semis=-7):
    """Drops growled lines in, one every `every` bars."""
    for i, line in enumerate(lines):
        s.add(growl(line, semis, i), (start_bar + i * every) * 4.0, "vox", 0.0, gain)


def master(s, extra=None, gtr=0.06):
    fx = {"gtr": lambda x: ga.reverb(x, gtr, 0.8), "lead": lambda x: ga.reverb(ga.echo(x, s.spb * 0.75, 0.25, 0.2), 0.22),
          "pad": ga.fx_reverb(0.45), "vox": lambda x: x}
    fx.update(extra or {})
    return s.mixdown(fx)


# ------------------------------------------------------------------ death metal

BLAST = {"kick": "xxxxxxxxxxxxxxxx", "snare": "x.x.x.x.x.x.x.x.", "ride": "xxxxxxxx"}
DBEAT_DEATH = {"kick": "x.xxx.xxx.xxx.xx", "snare": "....x.......x...", "china": "x...x...x...x..."}
SLAM = {"kick": "x..x..x...x..x..", "snare": "........x.......", "china": "x.......x......."}


def track_death():
    """Double Yellow Death: the default soundtrack. Blast beats, tremolo riffs and a growled chorus."""
    s = Song(196, 48)
    trem = "C2:1 C#2:1 C2:1 F#2:1 G2:1 F#2:1 C2:2"
    chug = "C2:.5p C2:.25p C2:.25p D#2:.5 C2:.5p C2:.25p C2:.25p F#2:.5 F2:.5 D#2:.5"
    drums(s, 1, {"china": "x.......x.......", "tom": "........xxxxxxxx"})
    guitar(s, "C2:4", 0, 1, step=0.5, palm=True)
    drums(s, 15, BLAST, 1)
    guitar(s, trem, 1, 15)
    crash_on(s, range(1, 16, 4))
    sing(s, ["DOUBLE YELLOW!", "NO PARKING!", "TICKET OF DOOM!", "YOU HAVE BEEN FINED!"], 5, every=2)
    drums(s, 15, DBEAT_DEATH, 16)
    guitar(s, chug, 16, 15)
    sing(s, ["PAY AND DISPLAY!", "OR PAY THE PRICE!"], 20, every=4)
    fill(s, 31)
    drums(s, 16, BLAST, 32)
    crash_on(s, range(32, 48, 4))
    guitar(s, trem, 32, 16, transpose=5)
    lead = """
C5:.5 D#5:.5 F#5:.5 G5:.5 F#5:1 D#5:1
C5:.5 D5:.5 D#5:.5 F5:.5 D#5:2
G5:.5 F#5:.5 D#5:.5 C5:.5 C#5:1 C5:1
G4:.5 C5:.5 D#5:.5 F#5:.5 G5:2
"""
    s.melody(lead, whammy_lead, 36, gain=0.85)
    s.melody(lead, whammy_lead, 40, gain=0.6, transpose=3, pan=0.35)
    sing(s, ["DOUBLE YELLOW!", "DOUBLE YELLOW DEATH!"], 44, every=2)
    return master(s)


def track_death2():
    """Clamped in Darkness: mid-tempo slam, filthy chugs and a breakdown."""
    s = Song(132, 40)
    slam = "B1:.75p B1:.25p r:.5 C2:.5 B1:.75p B1:.25p r:.5 F2:.5"
    groove = "B1:.25p B1:.25p B1:.5 D2:.5 B1:.25p B1:.25p F2:.5 E2:.5 D2:.5 C2:.5"
    drums(s, 8, SLAM)
    guitar(s, slam, 0, 8, step=4)
    crash_on(s, (0, 4))
    drums(s, 16, {"kick": "xxxxxxxxxxxxxxxx", "snare": "....x.......x...", "china": "x.x.x.x.x.x.x.x."}, 8)
    guitar(s, groove, 8, 16)
    crash_on(s, range(8, 24, 4))
    sing(s, ["CLAMPED!", "IN THE DARKNESS!", "TOWED AWAY!", "NEVER TO RETURN!"], 10, every=3)
    fill(s, 23)
    drums(s, 8, {"kick": "x...x..x...x....", "snare": "........x.......", "china": "x...x...x...x..."}, 24)
    guitar(s, "B1:1.5p B1:.5p r:1 A#1:1", 24, 8, step=4)
    sing(s, ["CLAMPED!", "CLAMPED!"], 26, every=2, semis=-9)
    drums(s, 8, BLAST, 32)
    guitar(s, "B1:1 C2:1 B1:1 F2:1", 32, 8)
    crash_on(s, range(32, 40, 2))
    sing(s, ["IN THE DARKNESS!"], 36)
    return master(s)


def track_death3():
    """Pay and Display of Doom: melodic death metal with harmonised twin leads."""
    s = Song(176, 48)
    riff = "E2:.5 E2:.25p E2:.25p G2:.5 E2:.25p E2:.25p A2:.5 G2:.5 F#2:.5 D2:.5"
    drums(s, 48, DBEAT_DEATH)
    crash_on(s, range(0, 48, 8))
    guitar(s, riff, 0, 48)
    tune = """
B4:1 E5:.5 F#5:.5 G5:1 F#5:.5 E5:.5
D5:1 E5:.5 D5:.5 B4:2
C5:1 D5:.5 E5:.5 F#5:1 G5:.5 A5:.5
B5:1.5 A5:.5 G5:1 F#5:1
"""
    for start in (4, 12, 28, 36):
        s.melody(tune, gx.lead_guitar, start, gain=0.85, pan=-0.25)
        s.melody(tune, gx.lead_guitar, start, gain=0.7, pan=0.25, transpose=3 if start % 8 == 4 else 4)
    sing(s, ["PAY AND DISPLAY!", "PAY AND DISPLAY OF DOOM!"], 20, every=4)
    drums(s, 8, BLAST, 40)
    sing(s, ["RULES ARE RULES!"], 44)
    return master(s)


def track_death_menu():
    """Clocking On (Death Mix): the menu theme, heavy but steady so the menus aren't stressful."""
    s = Song(112, 32)
    drums(s, 4, {"ride": "x.x.x.x.", "kick": "x.......x......."})
    chords(s, "C2:4 G#1:4 A#1:4 G1:4", 0, 4)
    drums(s, 28, {"kick": "x.xx..x.x.xx..x.", "snare": "....x.......x...", "ride": "x.x.x.x."}, 4)
    guitar(s, "C2:.5p C2:.5p C2:.5 D#2:.5 C2:.5p C2:.5p G2:.5 F#2:.5", 4, 28)
    crash_on(s, range(4, 32, 8))
    tune = """
G4:1 C5:1 D#5:1.5 D5:.5
C5:1 G4:1 G#4:2
G4:1 C5:1 D#5:1 F5:1
D5:2 G4:2
"""
    s.melody(tune, whammy_lead, 12, gain=0.7)
    s.melody(tune, ga.strings, 12, bus="pad", gain=0.45, transpose=-12)
    s.melody(tune, whammy_lead, 20, gain=0.75, transpose=12)
    sing(s, ["CLOCKING ON!"], 8)
    sing(s, ["CLOCKING ON!"], 28)
    return master(s)


# ------------------------------------------------------------------ other metal and rock styles

def track_thrash():
    """Speed Camera: fast thrash with a gang chant."""
    s = Song(212, 48)
    riff = "E2:.25p E2:.25p E2:.25p E2:.25p F2:.5 E2:.25p E2:.25p G2:.5 E2:.25p E2:.25p A#2:.5 A2:.5"
    drums(s, 48, {"kick": "x.x.x.x.x.x.x.x.", "snare": "..x...x...x...x.", "hat": "xxxxxxxx"})
    crash_on(s, range(0, 48, 4))
    guitar(s, riff, 0, 16)
    guitar(s, "E2:.5p E2:.5p G2:1 E2:.5p E2:.5p A2:.5 A#2:.5", 16, 16)
    guitar(s, riff, 32, 16)
    solo = """
E5:.25 G5:.25 A5:.25 B5:.25 A5:.25 G5:.25 E5:.5 D5:.25 E5:.25 G5:.25 E5:.25 D5:.5 B4:.5
E5:.25 G5:.25 A5:.25 B5:.25 D6:.5 B5:.5 A5:.5 G5:.5 E5:1
"""
    for b in range(32, 48, 2):
        s.melody(solo, whammy_lead, b, gain=0.8, transpose=0 if b % 4 == 0 else 5)
    return master(s)


def track_doom():
    """Yellow Line Doom: slow, crushing and very serious about parking."""
    s = Song(64, 20)
    drums(s, 20, {"kick": "x.......x.x.....", "snare": "........x.......", "ride": "x.x.x.x."}, gain=1.1)
    crash_on(s, range(0, 20, 2))
    chords(s, "D2:2 F2:1 D#2:1 D2:2 A#1:1 A1:1", 0, 20, drive=26.0)
    s.melody("D5:2 F5:1 E5:1 D5:4 A5:2 G5:1 F5:1 E5:4", fuzz_lead, 8, gain=0.8)
    s.melody("D5:2 F5:1 E5:1 D5:4 A5:2 G5:1 F5:1 E5:4", fuzz_lead, 12, gain=0.8, transpose=12)
    ga.comp_pattern(s, ["Dm", "Dm", "Bb", "A"] * 5, ga.organ, (0,), octave=3, gain=0.35, length=3.9, bus="pad")
    return master(s, gtr=0.15)


def track_groove():
    """Wheel Clamp Groove: swaggering groove metal, all pinch harmonics and attitude."""
    s = Song(116, 32)
    riff = "E2:.75 E2:.25p G2:.5 E2:.5p A#2:.25 A2:.25 G2:.5 E2:.5p D2:.5"
    drums(s, 32, {"kick": "x..xx..x..x.x...", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."})
    crash_on(s, range(0, 32, 4))
    guitar(s, riff, 0, 32, step=8)
    s.melody("E6:.25 r:3.75 r:4 G6:.25 r:3.75 r:4", whammy_lead, 4, gain=0.6)
    s.melody("B4:1 D5:.5 E5:1.5 G5:1 E5:1 D5:.5 B4:1.5 A4:1", whammy_lead, 16, gain=0.8)
    s.melody("B4:1 D5:.5 E5:1.5 G5:1 E5:1 D5:.5 B4:1.5 A4:1", whammy_lead, 24, gain=0.8, transpose=12)
    return master(s)


def track_black():
    """Frostbitten Parking Meter: icy symphonic black metal with strings and a choir pad."""
    s = Song(184, 40)
    drums(s, 40, BLAST)
    crash_on(s, range(0, 40, 8))
    guitar(s, "D3:2 C#3:2 A#2:2 A2:2", 0, 40, step=0.25, drive=12.0)
    prog = ["Dm", "Dm", "Bb", "A"] * 10
    ga.comp_pattern(s, prog, ga.strings, (0,), octave=4, gain=0.55, length=3.9, bus="pad")
    ga.comp_pattern(s, prog, ga.pad, (0,), octave=5, gain=0.35, length=3.9, bus="pad")
    tune = "A5:2 F5:1 E5:1 D5:4 F5:2 G5:1 A5:1 E5:4"
    s.melody(tune, ga.strings, 8, bus="pad", gain=0.6)
    s.melody(tune, ga.strings, 24, bus="pad", gain=0.6, transpose=12)
    return master(s, {"gtr": lambda x: ga.reverb(highpass(x, 160), 0.3, 1.2)})


def track_metalcore():
    """Breakdown Lane: metalcore with a melodic chorus and a big breakdown."""
    s = Song(150, 40)
    verse = "D2:.25p D2:.25p D2:.25p D2:.25p F2:.5 D2:.25p D2:.25p G#2:.5 G2:.5 F2:.5 D#2:.5"
    drums(s, 16, {"kick": "x.xxx.xxx.xxx.xx", "snare": "....x.......x...", "china": "x.x.x.x.x.x.x.x."})
    guitar(s, verse, 0, 16)
    drums(s, 8, {"kick": "x...x...x...x...", "snare": "....x.......x...", "ride": "xxxxxxxx"}, 16)
    crash_on(s, range(16, 24, 2))
    chords(s, "A#2:4 F2:4 C3:4 G2:4", 16, 8, drive=16.0)
    s.melody("D5:1 F5:1 G5:2 A#5:1 A5:1 G5:2 F5:1 G5:1 A5:2 D5:4", gx.lead_guitar, 16, gain=0.8)
    drums(s, 8, {"kick": "x..x...x.x..x...", "snare": "........x.......", "china": "x.......x......."}, 24)
    guitar(s, "D1:.75p D1:.75p r:.5 D1:.5p r:.5 D1:.5p D#1:.5", 24, 8, step=4)
    sing(s, ["BREAKDOWN LANE!"], 24, semis=-5)
    drums(s, 8, {"kick": "x.xxx.xxx.xxx.xx", "snare": "....x.......x...", "china": "x.x.x.x.x.x.x.x."}, 32)
    guitar(s, verse, 32, 8)
    crash_on(s, (0, 8, 16, 24, 32))
    return master(s)


def track_numetal():
    """Bounce Bay: bouncy nu-metal with a scratchy turntable and a big detuned riff."""
    s = Song(100, 32, swing=0.12)
    drums(s, 32, {"kick": "x..x..x...x.....", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."})
    crash_on(s, range(0, 32, 8))
    guitar(s, "A1:.75p A1:.75p r:.5 A1:.5p C2:.5 A1:.5p D#2:.5", 0, 32, step=4)
    for b in range(4, 32, 4):
        t = tvec(0.25)
        scratch = bandpass(rng.standard_normal(len(t)), 600, 3000) * np.abs(np.sin(2 * np.pi * 9 * t))
        s.add(scratch * 0.6, b * 4 + 3, "lead", 0.4, 0.8)
        s.add(scratch[::-1] * 0.6, b * 4 + 3.5, "lead", -0.4, 0.8)
    s.melody("E5:1 r:1 E5:.5 G5:.5 E5:1 D5:2 C5:1 B4:1", ga.square_lead, 8, gain=0.4)
    s.melody("E5:1 r:1 E5:.5 G5:.5 E5:1 D5:2 C5:1 B4:1", ga.square_lead, 20, gain=0.4)
    return master(s)


def track_hardcore():
    """Hi-Vis Hardcore: d-beat punk, ninety seconds of shouting at a parking meter."""
    s = Song(186, 32)
    drums(s, 32, {"kick": "x..x..x.x..x..x.", "snare": "....x.......x...", "crash": "x.x.x.x.x.x.x.x."}, gain=0.85)
    guitar(s, "G2:1 G2:.5 A#2:.5 C3:1 A#2:.5 F2:.5", 0, 32, step=0.5)
    s.melody("G4:.5 G4:.5 A#4:1 C5:.5 C5:.5 A#4:1 G4:2 F4:2", ga.square_lead, 8, gain=0.6)
    s.melody("G4:.5 G4:.5 A#4:1 C5:.5 C5:.5 A#4:1 G4:2 F4:2", ga.square_lead, 24, gain=0.6, transpose=12)
    return master(s)


def track_grunge():
    """Rain on the Windscreen: quiet verse, loud chorus, very 1991."""
    s = Song(118, 32)
    drums(s, 8, {"kick": "x.....x.x.......", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."}, gain=0.7)
    for b in range(8):
        for i, n in enumerate(("F3", "A#3", "C4", "A#3")):
            s.add(gx.lead_guitar(hz(midi(n)), s.spb * 0.9, 0.5), b * 4 + i, "lead", -0.2, 0.6)
    drums(s, 8, {"kick": "x.....x.x.x.....", "snare": "....x.......x...", "crash": "x.x.x.x."}, 8)
    chords(s, "F2:1.5 A#2:1.5 G#2:.5 C#3:.5", 8, 8, drive=30.0)
    crash_on(s, (8, 16, 24))
    drums(s, 8, {"kick": "x.....x.x.......", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."}, 16, gain=0.7)
    for b in range(16, 24):
        for i, n in enumerate(("F3", "A#3", "C4", "A#3")):
            s.add(gx.lead_guitar(hz(midi(n)), s.spb * 0.9, 0.5), b * 4 + i, "lead", -0.2, 0.6)
    drums(s, 8, {"kick": "x.....x.x.x.....", "snare": "....x.......x...", "crash": "x.x.x.x."}, 24)
    chords(s, "F2:1.5 A#2:1.5 G#2:.5 C#3:.5", 24, 8, drive=30.0)
    s.melody("C5:1 A#4:1 G#4:1 F4:1 G#4:2 F4:2", fuzz_lead, 26, gain=0.7)
    return master(s, gtr=0.12)


def track_stoner():
    """Desert Car Park: fuzzy stoner rock with a cowbell, heat haze optional."""
    s = Song(96, 32, swing=0.18)
    drums(s, 32, {"kick": "x.....x.x.......", "snare": "....x.......x...", "ride": "x.x.x.x."})
    crash_on(s, range(0, 32, 8))
    chords(s, "C2:1 C2:.5 D#2:.5 F2:.5 F#2:.25 F2:.25 D#2:.5 C2:.5 A#1:1", 0, 32, drive=34.0)
    for b in range(0, 32):
        t = tvec(0.12)
        bell = (np.sign(np.sin(2 * np.pi * 560 * t)) + np.sign(np.sin(2 * np.pi * 845 * t))) * np.exp(-t * 30) * 0.08
        for k in range(4):
            s.add(bandpass(bell, 400, 4000), b * 4 + k, "drums", -0.4, 0.8)
    s.melody("G4:1 A#4:.5 C5:1.5 D#5:1 C5:2 A#4:1 G4:1", fuzz_lead, 12, gain=0.8)
    s.melody("G4:1 A#4:.5 C5:1.5 D#5:1 C5:2 A#4:1 G4:1", fuzz_lead, 20, gain=0.8, transpose=12)
    return master(s, gtr=0.15)


def track_glam():
    """Hazard Lights: glam hard rock, big hair and bigger choruses."""
    s = Song(128, 32)
    drums(s, 32, {"kick": "x.......x.x.....", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."})
    crash_on(s, range(0, 32, 4))
    guitar(s, "A2:.5 A2:.5 G2:.5 A2:1 C3:.5 D3:.5 A2:.5", 0, 16, step=0.5)
    chords(s, "D3:2 A2:2 G2:2 A2:2", 16, 16, drive=14.0)
    hook = "A4:.5 C#5:.5 E5:1 F#5:.5 E5:1.5 D5:.5 C#5:.5 B4:1 A4:2"
    s.melody(hook, whammy_lead, 8, gain=0.8)
    s.melody(hook, ga.brass, 16, bus="pad", gain=0.35)
    s.melody(hook, whammy_lead, 24, gain=0.8, transpose=12)
    return master(s)


TRACKS = {
    "death": track_death, "death2": track_death2, "death3": track_death3, "death_menu": track_death_menu,
    "thrash": track_thrash, "doom": track_doom, "groove": track_groove, "black": track_black,
    "metalcore": track_metalcore, "numetal": track_numetal, "hardcore": track_hardcore, "grunge": track_grunge,
    "stoner": track_stoner, "glam": track_glam,
}


def main():
    only = sys.argv[1:]
    music = os.path.join(ga.ROOT, "music")
    for name, fn in TRACKS.items():
        if only and name not in only:
            continue
        print("music", name, flush=True)
        write_ogg(os.path.join(music, name + ".ogg"), fn(), quality=4)
    if not only or "radio" in only:
        # A death metal car stereo for the loud-music cars
        x = track_death()
        start = int(16 * 4 * 60.0 / 196 * SR)
        loop = gx.in_car(x[start:], 8 * 4 * 60.0 / 196)
        write_ogg(os.path.join(ga.ROOT, "sfx", "radio_death.ogg"), ga.mono_to_stereo(loop), quality=3)
    print("metal done")


if __name__ == "__main__":
    main()
