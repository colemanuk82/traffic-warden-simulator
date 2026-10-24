"""NOTE: the voice lines this script writes with espeak-ng are replaced by tools/gen_voices.py (Kokoro
neural voices); run that afterwards. The line tables here are still the script it reads from.

Generates the release-update audio for Traffic Warden Sim: heavy rock and metal tracks, more music
for the jukebox, the loud car stereos, a dog bark, and new voice lines (women's voices, family-friendly
heckles, "Hey, that's my bike!" and "chicken man").

Builds on the synths in gen_audio.py. Everything is synthesised, voices come from espeak-ng.
Run:  python3 tools/gen_audio_extra.py   (needs numpy, scipy, ffmpeg, espeak-ng)
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_audio as ga  # noqa: E402
from gen_audio import SR, Song, hz, midi, tvec, lowpass, highpass, bandpass, write_ogg, mono_to_stereo  # noqa: E402

rng = np.random.default_rng(42)


# ------------------------------------------------------------------ instruments

def power_chord(f, dur, v=1.0, palm=False, drive=14.0):
    """Distorted guitar power chord (root, fifth, octave) through a speaker cabinet."""
    n = int(max(dur, 0.05) * SR)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for mult, amp in ((1.0, 1.0), (1.4983, 0.8), (2.0, 0.6)):
        for det in (-0.004, 0.004):
            ph = 2 * np.pi * f * mult * (1 + det) * t
            x += amp * (2 * ((ph / (2 * np.pi)) % 1.0) - 1)
    x = lowpass(x, 5000)
    x = np.tanh(x * drive * 0.15)
    if palm:
        env = np.exp(-t * 18.0)
        x = lowpass(x, 900) * env * 1.4
    else:
        env = ga.adsr(n, a=0.004, d=0.2, s=0.75, r=0.05)
        x = x * env
    x = bandpass(x, 90, 4200)
    return x * 0.32 * v


def lead_guitar(f, dur, v=1.0):
    n = int(max(dur, 0.05) * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 6.0 * t) * np.clip((t - 0.15) * 4, 0, 1)
    ph = 2 * np.pi * f * np.cumsum(vib) / SR
    x = 2 * ((ph / (2 * np.pi)) % 1.0) - 1
    x = np.tanh(lowpass(x, 3500) * 5.0)
    x = bandpass(x, 200, 5000) * ga.adsr(n, a=0.01, d=0.1, s=0.85, r=0.08)
    return x * 0.3 * v


def crash(v=1.0):
    t = tvec(1.6)
    x = highpass(rng.standard_normal(len(t)), 5000) * np.exp(-t * 2.5)
    return x * 0.35 * v


def tom(f, v=1.0):
    t = tvec(0.35)
    x = np.sin(2 * np.pi * f * t * (1 - t * 0.6)) * np.exp(-t * 10)
    return x * 0.8 * v


def rock_drums(s, bars, pattern, start_bar=0, gain=1.0):
    """Like Song.drums, plus 'crash' and 'tom' lanes."""
    simple = {k: v for k, v in pattern.items() if k not in ("crash", "tom")}
    s.drums(bars, simple, start_bar, gain)
    for bar in range(start_bar, start_bar + bars):
        for inst in ("crash", "tom"):
            steps = pattern.get(inst)
            if not steps:
                continue
            for i, ch in enumerate(steps):
                if ch == ".":
                    continue
                beat = bar * 4 + i * 4.0 / len(steps)
                if inst == "crash":
                    s.add(crash(), beat, "drums", -0.2, 0.7 * gain)
                else:
                    s.add(tom(140 - (i % 4) * 20), beat, "drums", 0.2, 0.8 * gain)


def riff(s, text, start_bar, bars, gain=1.0, pan=0.0, transpose=0, bus="gtr"):
    """Plays a one- or two-bar riff written as tokens 'E2:.5', 'E2:.5p' (palm muted) or 'r:.5'."""
    tokens = text.split()
    total = sum(float(tok.split(":")[1].rstrip("p")) for tok in tokens)
    beat = start_bar * 4.0
    end = (start_bar + bars) * 4.0
    while beat < end - 1e-6:
        for tok in tokens:
            name, dur = tok.split(":")
            palm = dur.endswith("p")
            d = float(dur.rstrip("p"))
            if name != "r" and beat < end - 1e-6:
                f = hz(midi(name) + transpose)
                sig = power_chord(f, d * s.spb * (0.6 if palm else 0.95), 1.0, palm)
                s.add(sig, beat, bus, pan - 0.25, gain)
                s.add(sig, beat + 0.01, bus, pan + 0.25, gain * 0.9)  # double tracked
                s.add(ga.bass_saw(f / 2, d * s.spb * 0.9), beat, "bass", 0, gain * 0.9)
            beat += d
        if total <= 0:
            break


def cab(mix):
    return lambda x: ga.reverb(x, mix, 0.8)


# ------------------------------------------------------------------ tracks

def track_rock():
    """Heavy rock: a big E riff, a pounding chorus and a screaming solo."""
    s = Song(138, 32)
    beat = {"kick": "x.......x.x.....", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."}
    intro = "E2:.5p E2:.5p G2:.5 E2:.5p A2:.5 E2:.5p D3:.5 C#3:.5"
    chorus = "E2:1 C3:1 D3:1 B2:1"
    rock_drums(s, 1, {"crash": "x...............", "tom": "........xxxxxxxx"})
    riff(s, intro, 0, 2, gain=0.8)
    rock_drums(s, 14, beat, start_bar=2)
    riff(s, intro, 2, 14)
    rock_drums(s, 1, {"crash": "x..............."}, start_bar=16)
    rock_drums(s, 16, {"kick": "x...x...x...x...", "snare": "....x.......x...", "hat": "xxxxxxxxxxxxxxxx",
                       "crash": "x..............."}, start_bar=16)
    riff(s, chorus, 16, 16)
    solo = """
E4:.5 G4:.5 A4:.5 B4:1.5 D5:.5 B4:.5 A4:1 G4:.5 E4:1.5
E4:.5 G4:.5 A4:.5 B4:.5 E5:2 D5:.5 B4:.5 D5:1 E5:2
G5:.5 E5:.5 D5:.5 B4:.5 A4:1 B4:1 G4:.5 A4:.5 B4:1 E4:2
E5:.5 D5:.5 B4:.5 A4:.5 G4:.5 A4:.5 B4:1 E5:4
"""
    s.melody(solo, lead_guitar, 8, bus="lead", gain=0.9)
    s.melody(solo, lead_guitar, 16, bus="lead", gain=1.0, transpose=12)
    s.melody(solo, lead_guitar, 24, bus="lead", gain=0.9)
    return s.mixdown({"gtr": cab(0.08), "lead": lambda x: ga.reverb(ga.echo(x, s.spb * 0.75, 0.3, 0.25), 0.2)})


def track_rock2():
    """Hard rock boogie with a swing in its step."""
    s = Song(126, 32, swing=0.22)
    groove = {"kick": "x.....x.x.......", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."}
    rock_drums(s, 32, groove)
    for b in range(0, 32, 8):
        rock_drums(s, 1, {"crash": "x..............."}, start_bar=b)
    boogie = "A2:.5 A2:.5 A2:.5 C#3:.5 A2:.5 D3:.5 A2:.5 C#3:.5"
    riff(s, boogie, 0, 8)
    riff(s, boogie, 8, 4, transpose=5)
    riff(s, boogie, 12, 4)
    riff(s, "E3:1 D3:1 A2:2", 16, 4)
    riff(s, boogie, 20, 12)
    tune = """
A4:.5 C5:.5 A4:.5 E5:1 D5:.5 C5:1
A4:.5 G4:.5 A4:2 r:1
D5:.5 F5:.5 D5:.5 A5:1 G5:.5 F5:1
E5:.5 D5:.5 C5:2 r:1
"""
    s.melody(tune, lead_guitar, 4, bus="lead", gain=0.9)
    s.melody(tune, lead_guitar, 20, bus="lead", gain=0.9, transpose=12)
    s.melody(tune, ga.organ, 24, bus="lead", gain=0.5)
    return s.mixdown({"gtr": cab(0.1), "lead": lambda x: ga.reverb(ga.echo(x, s.spb * 0.5, 0.25, 0.2), 0.2)})


def track_metal():
    """Thrash metal: double kick, palm-muted gallops and a harmonised lead."""
    s = Song(184, 32)
    thrash = {"kick": "xxxxxxxxxxxxxxxx", "snare": "....x.......x...", "hat": "x...x...x...x..."}
    gallop = "E2:.5p E2:.25p E2:.25p E2:.5p E2:.25p E2:.25p F2:.5 E2:.5p G2:.5 F#2:.5"
    rock_drums(s, 2, {"crash": "x.......x.......", "tom": "....xxxx....xxxx"})
    riff(s, "E2:2 F2:2", 0, 2)
    rock_drums(s, 30, thrash, start_bar=2)
    for b in range(2, 32, 4):
        rock_drums(s, 1, {"crash": "x..............."}, start_bar=b)
    riff(s, gallop, 2, 14)
    riff(s, "E2:.5p E2:.5p C3:1 E2:.5p E2:.5p D3:1", 16, 8)
    riff(s, gallop, 24, 8)
    lead = """
E5:.5 F5:.5 G5:.5 B5:.5 A5:1 G5:1
F5:.5 E5:.5 D5:.5 E5:.5 B4:2
E5:.5 F5:.5 G5:.5 B5:.5 C6:1 B5:1
A5:.5 G5:.5 F5:.5 G5:.5 E5:2
"""
    s.melody(lead, lead_guitar, 16, bus="lead", gain=0.85)
    s.melody(lead, lead_guitar, 16, bus="lead", gain=0.6, transpose=3, pan=0.4)
    s.melody(lead, lead_guitar, 24, bus="lead", gain=0.85, transpose=12)
    return s.mixdown({"gtr": cab(0.05), "lead": lambda x: ga.reverb(x, 0.25)})


def track_metal2():
    """Power metal: fast, heroic and slightly ridiculous."""
    s = Song(168, 32)
    gallop = {"kick": "x.xxx.xxx.xxx.xx", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."}
    rock_drums(s, 32, gallop)
    for b in range(0, 32, 4):
        rock_drums(s, 1, {"crash": "x..............."}, start_bar=b)
    prog = ["E2", "C3", "D3", "B2", "E2", "C3", "A2", "B2"]
    for i in range(32):
        riff(s, "%s:.5 %s:.25p %s:.25p" % ((prog[i % 8],) * 3), i, 1, gain=0.8)
    hero = """
B4:1 E5:1 F#5:.5 G5:.5 A5:1
G5:1 F#5:.5 E5:.5 D5:1 E5:1
C5:1 E5:1 G5:.5 A5:.5 B5:1
A5:1 G5:.5 F#5:.5 E5:2
"""
    s.melody(hero, lead_guitar, 8, bus="lead", gain=0.9)
    s.melody(hero, ga.strings, 8, bus="pad", gain=0.5, transpose=-12)
    s.melody(hero, lead_guitar, 16, bus="lead", gain=0.9)
    s.melody(hero, lead_guitar, 16, bus="lead", gain=0.6, transpose=4, pan=0.3)
    s.melody(hero, lead_guitar, 24, bus="lead", gain=0.9, transpose=12)
    ga.comp_pattern(s, ["Em", "C", "D", "Bm", "Em", "C", "Am", "B"] * 4, ga.strings, (0,), octave=4, gain=0.35,
                    length=3.9, bus="pad")
    return s.mixdown({"gtr": cab(0.05), "lead": lambda x: ga.reverb(ga.echo(x, s.spb * 0.75, 0.25, 0.2), 0.25),
                      "pad": ga.fx_reverb(0.4)})


def track_punk():
    """Three chords and the truth, very fast."""
    s = Song(200, 32)
    kit = {"kick": "x.x.x.x.x.x.x.x.", "snare": "..x...x...x...x.", "hat": "xxxxxxxxxxxxxxxx"}
    rock_drums(s, 32, kit, gain=0.9)
    prog = ["D3", "D3", "G2", "A2"]
    for i in range(32):
        root = prog[i % 4]
        riff(s, "%s:.5 %s:.5 %s:.5 %s:.5 %s:.5 %s:.5 %s:.5 %s:.5" % ((root,) * 8), i, 1, gain=0.75)
    shout = """
D5:1 D5:.5 D5:.5 F#5:1 A5:1
G5:1 F#5:1 E5:2
D5:1 D5:.5 D5:.5 F#5:1 A5:1
B5:1 A5:1 D5:2
"""
    s.melody(shout, ga.square_lead, 8, bus="lead", gain=0.8)
    s.melody(shout, ga.square_lead, 24, bus="lead", gain=0.8, transpose=12)
    return s.mixdown({"gtr": cab(0.05), "lead": ga.fx_reverb(0.15)})


def track_synthwave():
    """Neon night drive."""
    s = Song(104, 32)
    prog = ["Am", "F", "C", "G"] * 8
    kit = {"kick": "x...x...x...x...", "snare": "....x.......x...", "hat": "..x...x...x...x."}
    s.drums(4, {"kick": "x...x...x...x..."})
    s.drums(28, kit, start_bar=4)
    ga.bass_line(s, prog, ga.bass_saw, "octaves", octave=2, gain=1.0)
    ga.arpeggio(s, prog, ga.arp_synth, octave=4, gain=0.7)
    ga.comp_pattern(s, prog, ga.pad, (0,), octave=4, gain=0.8, length=3.9, bus="pad")
    tune = """
E5:1.5 D5:.5 C5:1 A4:1
F5:1.5 E5:.5 C5:2
G5:1.5 F5:.5 E5:1 C5:1
D5:2 B4:2
"""
    s.melody(tune, ga.square_lead, 8, gain=0.8)
    s.melody(tune, ga.square_lead, 16, gain=0.8, transpose=12)
    s.melody(tune, ga.glock, 24, gain=0.6, transpose=12)
    return s.mixdown({"lead": lambda x: ga.reverb(ga.echo(x, s.spb * 0.75, 0.35, 0.3), 0.3),
                      "pad": ga.fx_reverb(0.5), "arp": lambda x: ga.echo(x, s.spb * 0.5, 0.3, 0.2)})


# ------------------------------------------------------------------ car stereos

def in_car(stereo, seconds):
    """Squash a track into a booming, muffled car-stereo loop."""
    x = stereo.mean(axis=1)[:int(seconds * SR)]
    boom = lowpass(x, 160) * 1.6
    x = lowpass(x, 2400) + boom
    x = np.tanh(x * 1.8)
    fade = int(0.05 * SR)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    return ga.norm(x, 0.95)


def radio_rave():
    s = Song(140, 8)
    s.drums(8, {"kick": "x...x...x...x...", "clap": "....x.......x...", "hat": "..x...x...x...x."})
    prog = ["Fm", "Fm", "Db", "Eb"] * 2
    ga.bass_line(s, prog, ga.bass_saw, "octaves", octave=2, gain=1.3)
    ga.arpeggio(s, prog, ga.arp_synth, octave=4, gain=0.8)
    return s.mixdown({})


def radio_bass():
    s = Song(174, 8)
    s.drums(8, {"kick": "x.........x.....", "snare": "....x.......x...", "hat": "x.x.x.xxx.x.x.x."})
    for bar in range(8):
        for b, n in ((0, "F1"), (1.5, "F1"), (2.5, "Ab1"), (3, "C2")):
            s.add(ga.bass_round(hz(midi(n)), 0.4 * s.spb, 1.6), bar * 4 + b, "bass", 0, 1.4)
    return s.mixdown({})


def bark():
    t = tvec(0.22)
    f = 520 * (1 - t * 1.5)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.5 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    noise = bandpass(rng.standard_normal(len(t)), 500, 2500) * 0.5
    x = np.tanh((tone + noise) * 3.0) * np.exp(-t * 14) * np.clip(t * 200, 0, 1)
    return ga.norm(bandpass(x, 250, 4000), 0.9)


# ------------------------------------------------------------------ voices

WOMEN = [("en-gb+f2", 70, 170), ("en-gb+f3", 75, 175), ("en-gb+f4", 65, 180), ("en-gb-scotland+f2", 70, 175),
         ("en-gb+f5", 80, 170), ("en-gb-x-rp+f3", 72, 165)]
MEN = ga.VOICES

FAMILY_HECKLES = [
    "Go and catch some real criminals!", "My nan's faster than you!", "Nice hat, Napoleon!",
    "Lovely shiny jacket!", "Haven't you got a home to go to?", "You couldn't ticket a parked bus!",
    "Is that a uniform or your pyjamas?", "Boo! Spoilsport!", "Get a hobby!", "Bet you love Mondays!",
    "Off you pop, slowcoach!", "You're a chicken man!",
]
NEW_DRIVER_LINES = {"bike": "Hey, that's my bike!", "chicken": "You're a chicken man!"}
# Excuses drivers shout when they come back to a ticketed car (voiced by tools/gen_voices.py)
EXCUSE_LINES = {
    "aminute": "I was only a minute!",
    "phone": "My phone didn't work, so I couldn't pay!",
    "space": "I couldn't find a space!",
    "wherelike": "I park where I like, mate!",
    "cashpoint": "I was only popping to the cash machine!",
    "coins": "The machine only takes coins!",
    "app": "The parking app crashed!",
    "signs": "There weren't any signs!",
    "yellow": "I didn't see any yellow lines!",
    "droppingoff": "I was only dropping something off!",
    "hazards": "My hazards were on!",
    "straightback": "I was coming straight back!",
    "everyone": "Everyone else parks here!",
    "years": "I've parked here for twenty years!",
    "loo": "I was desperate for the loo!",
    "sandwich": "I was only buying a sandwich!",
    "notmine": "It's not even my car!",
    "appeal": "I'm appealing that!",
    "birthday": "Have a heart, it's my birthday!",
    "whoami": "Do you know who I am?!",
    "roadtax": "I pay my road tax, you know!",
    "nan": "I was helping my nan with her shopping!",
    "lost": "I got lost looking for the car park!",
    "change": "I was just getting change!",
}

# Angry, cheeky insults drivers shout while they chase you (1.2.0). Rude-sounding but family-friendly:
# no swearing, no slurs, nothing about how anyone looks or who they are, just British playground name-calling.
INSULT_LINES = {
    "plonker": "You absolute plonker!",
    "muppet": "Oi! You massive muppet!",
    "numpty": "Clear off, you numpty!",
    "wally": "You big daft wally!",
    "lollipop": "You jumped-up lollipop man!",
    "nitwit": "Go on, hop it, you nitwit!",
    "goblin": "You ticket-happy goblin!",
    "pixie": "Get a life, you parking pixie!",
    "pram": "You couldn't park a pram, you wally!",
    "yellowline": "You're a walking yellow line!",
    "mumdresses": "Does your mum still dress you?!",
    "cone": "Come here, you hi-vis traffic cone!",
    "turnip": "You absolute turnip!",
    "meterbrains": "You've got the brains of a parking meter!",
    "notepad": "Ooh, big man with a notepad!",
    "robocop": "Robocop on a budget!",
    "nobodylikes": "Nobody likes you, you know!",
    "plum": "Get stuffed, you plum!",
    "melon": "You utter melon!",
    "jacket": "Waste of a good jacket, you are!",
    "lemon": "Bog off, you lemon!",
    "pudding": "You great big pudding!",
    "donut": "You complete doughnut!",
    "sausage": "Do one, you sausage!",
    "hat": "I'll knock your silly hat off!",
    "spanner": "Out the way, you spanner!",
    "sillybilly": "You great big silly billy!",
    "numbskull": "Get out of it, you numbskull!",
    "chickenagain": "Bwok bwok! Chicken man!",
}


def voices():
    voice = os.path.join(ga.ROOT, "voice")
    # Women's voices for every existing heckle and driver line: index 2 joins each group's pool
    for i, line in enumerate(ga.HECKLES + ga.MORE_HECKLES):
        v, p, sp = WOMEN[i % len(WOMEN)]
        write_ogg(os.path.join(voice, "heckle_%d_2.ogg" % i), mono_to_stereo(ga.speak(line, v, p, sp)))
    for j, (key, line) in enumerate(ga.DRIVER_LINES.items()):
        if key == "tosser":
            continue
        v, p, sp = WOMEN[j % len(WOMEN)]
        write_ogg(os.path.join(voice, "driver_%s_2.ogg" % key), mono_to_stereo(ga.speak(line, v, p, sp)))
    for key, line in NEW_DRIVER_LINES.items():
        for j in range(3):
            v, p, sp = (MEN[(len(key) + j * 2) % len(MEN)]) if j < 2 else WOMEN[len(key) % len(WOMEN)]
            write_ogg(os.path.join(voice, "driver_%s_%d.ogg" % (key, j)), mono_to_stereo(ga.speak(line, v, p, sp)))
    # Family-friendly heckles, one man's and one woman's take on each
    for i, line in enumerate(FAMILY_HECKLES):
        m = MEN[(i * 2 + 1) % len(MEN)]
        f = WOMEN[i % len(WOMEN)]
        write_ogg(os.path.join(voice, "heckle_ff_%d_0.ogg" % i), mono_to_stereo(ga.speak(line, *m)))
        write_ogg(os.path.join(voice, "heckle_ff_%d_1.ogg" % i), mono_to_stereo(ga.speak(line, *f)))


def main():
    music = os.path.join(ga.ROOT, "music")
    sfx = os.path.join(ga.ROOT, "sfx")
    only = sys.argv[1:]
    tracks = {"rock": track_rock, "rock2": track_rock2, "metal": track_metal, "metal2": track_metal2,
              "punk": track_punk, "synthwave": track_synthwave}
    rendered = {}
    for name, fn in tracks.items():
        if only and name not in only and "music" not in only:
            continue
        print("music", name)
        rendered[name] = fn()
        write_ogg(os.path.join(music, name + ".ogg"), rendered[name], quality=4)
    if not only or "radio" in only:
        print("car stereos")
        sources = {"rock": rendered.get("rock"), "metal": rendered.get("metal")}
        if sources["rock"] is None:
            sources["rock"] = track_rock()
        if sources["metal"] is None:
            sources["metal"] = track_metal()
        start_rock = int(16 * 4 * 60.0 / 138 * SR)  # the chorus
        start_metal = int(2 * 4 * 60.0 / 184 * SR)
        loops = {
            "radio_rock": in_car(sources["rock"][start_rock:], 8 * 4 * 60.0 / 138),
            "radio_metal": in_car(sources["metal"][start_metal:], 8 * 4 * 60.0 / 184),
            "radio_rave": in_car(radio_rave(), 8 * 4 * 60.0 / 140),
            "radio_bass": in_car(radio_bass(), 8 * 4 * 60.0 / 174),
        }
        for name, data in loops.items():
            write_ogg(os.path.join(sfx, name + ".ogg"), mono_to_stereo(data), quality=3)
        write_ogg(os.path.join(sfx, "bark.ogg"), mono_to_stereo(bark()))
    if not only or "voices" in only:
        print("voices")
        voices()
    print("extra done")


if __name__ == "__main__":
    main()
