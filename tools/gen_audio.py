"""Generates every music track, sound effect and voice line for Traffic Warden Sim.

Everything is synthesised from scratch (numpy + scipy), and the voices come from
espeak-ng, so there are no third-party audio files to license.
Run:  python3 tools/gen_audio.py   (needs numpy, scipy, ffmpeg, espeak-ng)
Writes .ogg files into audio/music, audio/sfx and audio/voice.
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
rng = np.random.default_rng(7)

NOTE_INDEX = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    n = NOTE_INDEX[name[0]]
    i = 1
    while i < len(name) and name[i] in "#b":
        n += 1 if name[i] == "#" else -1
        i += 1
    return n + 12 * (int(name[i:]) + 1)


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def tvec(dur):
    return np.arange(int(dur * SR)) / SR


def lowpass(x, cutoff, order=2):
    cutoff = min(cutoff, SR * 0.45)
    b, a = signal.butter(order, cutoff / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def highpass(x, cutoff, order=2):
    b, a = signal.butter(order, cutoff / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi, SR * 0.45) / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def adsr(n, a=0.005, d=0.1, s=0.7, r=0.08, hold=None):
    """Envelope of n samples; the release starts at `hold` seconds (default: n - r)."""
    t = np.arange(n) / SR
    total = n / SR
    hold = total - r if hold is None else hold
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    rel = np.clip((t - hold) / max(r, 1e-6), 0, 1)
    return e * (1 - rel)


def saw(f, t, detune=0.0):
    return 2.0 * ((t * f * (1 + detune)) % 1.0) - 1.0


def pulse(f, t, width=0.5):
    return np.where((t * f) % 1.0 < width, 1.0, -1.0)


def vibrato(t, rate=5.5, depth=0.004, delay=0.15):
    ramp = np.clip((t - delay) / 0.2, 0, 1)
    return 1 + depth * ramp * np.sin(2 * np.pi * rate * t)


def phase(f, t, vib=None):
    inst = f * (vib if vib is not None else 1.0)
    return 2 * np.pi * np.cumsum(inst) / SR


# ------------------------------------------------------------------ instruments

def kick(v=1.0):
    t = tvec(0.35)
    f = 45 + 110 * np.exp(-t * 28)
    x = np.sin(phase(f, t)) * np.exp(-t * 9)
    x += 0.3 * np.exp(-t * 300) * rng.standard_normal(len(t))
    return x * v


def snare(v=1.0):
    t = tvec(0.22)
    noise = bandpass(rng.standard_normal(len(t)), 1200, 7000) * np.exp(-t * 18)
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 30)
    return (noise * 0.9 + tone * 0.6) * v


def clap(v=1.0):
    t = tvec(0.25)
    n = bandpass(rng.standard_normal(len(t)), 900, 5000)
    e = np.zeros(len(t))
    for off in (0.0, 0.011, 0.022):
        e += np.where(t >= off, np.exp(-(t - off) * 60), 0)
    e += 0.5 * np.exp(-t * 12)
    return n * e * 0.7 * v


def hat(v=1.0, open_=False):
    t = tvec(0.3 if open_ else 0.06)
    x = highpass(rng.standard_normal(len(t)), 7000) * np.exp(-t * (12 if open_ else 70))
    return x * 0.5 * v


def shaker(v=1.0):
    t = tvec(0.08)
    x = bandpass(rng.standard_normal(len(t)), 4000, 12000) * np.sin(np.pi * np.clip(t / 0.08, 0, 1)) ** 2
    return x * 0.35 * v


def conga(f, v=1.0):
    t = tvec(0.25)
    ff = f * (1 + 0.3 * np.exp(-t * 40))
    return np.sin(phase(ff, t)) * np.exp(-t * 16) * 0.6 * v


def sleigh(v=1.0):
    t = tvec(0.18)
    x = highpass(rng.standard_normal(len(t)), 6000) * (0.6 + 0.4 * np.sin(2 * np.pi * 38 * t)) * np.exp(-t * 20)
    return x * 0.4 * v


def bass_round(f, dur, v=1.0):
    t = tvec(dur + 0.05)
    x = np.sin(phase(f, t)) + 0.35 * np.sin(phase(2 * f, t)) + 0.12 * np.sin(phase(3 * f, t))
    return x * adsr(len(t), 0.004, 0.25, 0.6, 0.05) * 0.8 * v


def bass_saw(f, dur, v=1.0):
    t = tvec(dur + 0.05)
    x = saw(f, t) + saw(f, t, 0.004)
    bright = lowpass(x, 1400)
    dark = lowpass(x, 350)
    e = np.exp(-t * 10)
    return (bright * e + dark * (1 - e)) * adsr(len(t), 0.003, 0.2, 0.8, 0.04) * 0.45 * v


def pluck_bass(f, dur, v=1.0):
    t = tvec(max(dur, 0.25) + 0.05)
    x = lowpass(saw(f, t), 900) * np.exp(-t * 6)
    return (x + 0.6 * np.sin(phase(f, t)) * np.exp(-t * 4)) * 0.6 * v


def organ(f, dur, v=1.0):
    t = tvec(dur + 0.06)
    x = np.zeros(len(t))
    for mult, amp in ((1, 1.0), (2, 0.6), (3, 0.35), (4, 0.25), (6, 0.12), (8, 0.08)):
        x += amp * np.sin(phase(f * mult, t))
    x *= 1 + 0.15 * np.sin(2 * np.pi * 6.3 * t)
    return x * adsr(len(t), 0.004, 0.05, 0.85, 0.05) * 0.22 * v


def epiano(f, dur, v=1.0):
    t = tvec(dur + 0.4)
    mod = 1.6 * np.exp(-t * 6) * np.sin(2 * np.pi * f * t)
    x = np.sin(2 * np.pi * f * t + mod) + 0.25 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 3)
    return x * adsr(len(t), 0.002, 0.6, 0.45, 0.25, hold=dur) * 0.35 * v


def harpsichord(f, dur, v=1.0):
    t = tvec(dur + 0.5)
    x = pulse(f, t, 0.3) * 0.5 + saw(f, t) * 0.5
    x = lowpass(x, min(f * 8, 9000)) * np.exp(-t * 3.5)
    return x * adsr(len(t), 0.001, 0.3, 0.6, 0.15, hold=dur + 0.3) * 0.3 * v


def strings(f, dur, v=1.0):
    t = tvec(dur + 0.3)
    vib = vibrato(t, 5.0, 0.003, 0.1)
    x = sum(saw(f, t, d) for d in (-0.003, 0.0, 0.004))
    x = lowpass(x * vib, 2500)
    return x * adsr(len(t), 0.12, 0.3, 0.8, 0.25, hold=dur) * 0.12 * v


def brass(f, dur, v=1.0):
    t = tvec(dur + 0.08)
    vib = vibrato(t, 5.5, 0.006, 0.18)
    ph = phase(f, t, vib)
    x = 2.0 * ((ph / (2 * np.pi)) % 1.0) - 1.0
    x += 0.5 * (2.0 * ((ph * 1.003 / (2 * np.pi)) % 1.0) - 1.0)
    bright = lowpass(x, 4000)
    dark = lowpass(x, 900)
    swell = np.clip(t / 0.05, 0, 1) * (0.6 + 0.4 * np.exp(-t * 4))
    y = dark * (1 - swell) + bright * swell
    return y * adsr(len(t), 0.02, 0.15, 0.8, 0.06) * 0.22 * v


def whistle_lead(f, dur, v=1.0):
    t = tvec(dur + 0.06)
    vib = vibrato(t, 6.0, 0.008, 0.12)
    x = np.sin(phase(f, t, vib)) + 0.08 * rng.standard_normal(len(t)) * np.exp(-t * 20)
    return x * adsr(len(t), 0.02, 0.1, 0.85, 0.05) * 0.3 * v


def steel(f, dur, v=1.0):
    t = tvec(max(dur, 0.3) + 0.3)
    ff = f * (1 + 0.02 * np.exp(-t * 50))
    x = np.sin(phase(ff, t)) + 0.5 * np.sin(phase(ff * 2.0, t)) * np.exp(-t * 6) \
        + 0.3 * np.sin(phase(ff * 3.01, t)) * np.exp(-t * 9)
    return x * np.exp(-t * 3.2) * adsr(len(t), 0.002, 1, 1, 0.1) * 0.32 * v


def glock(f, dur, v=1.0):
    t = tvec(max(dur, 0.6) + 0.4)
    x = np.sin(2 * np.pi * f * t) * np.exp(-t * 3) + 0.4 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t * 9) \
        + 0.2 * np.sin(2 * np.pi * f * 5.4 * t) * np.exp(-t * 16)
    return x * 0.3 * v


def square_lead(f, dur, v=1.0):
    t = tvec(dur + 0.1)
    vib = vibrato(t, 5.8, 0.005, 0.2)
    ph = phase(f, t, vib) / (2 * np.pi)
    width = 0.35 + 0.15 * np.sin(2 * np.pi * 0.7 * t)
    x = np.where(ph % 1.0 < width, 1.0, -1.0) + 0.6 * (2.0 * ((ph * 1.005) % 1.0) - 1.0)
    x = lowpass(x, 3200)
    return x * adsr(len(t), 0.005, 0.2, 0.7, 0.08) * 0.14 * v


def pad(f, dur, v=1.0):
    t = tvec(dur + 0.4)
    x = sum(saw(f, t, d) for d in (-0.006, -0.002, 0.003, 0.007))
    x = lowpass(x, 1600)
    return x * adsr(len(t), 0.25, 0.5, 0.8, 0.35, hold=dur) * 0.07 * v


def arp_synth(f, dur, v=1.0):
    t = tvec(dur + 0.05)
    x = lowpass(saw(f, t) + pulse(f * 2, t, 0.25) * 0.3, 2800) * np.exp(-t * 8)
    return x * adsr(len(t), 0.002, 0.1, 0.6, 0.03) * 0.18 * v


# ------------------------------------------------------------------ effects

def _feedback_delay(x, d, g):
    """y[n] = x[n] + g * y[n - d], processed in blocks of d samples."""
    y = np.array(x, dtype=np.float64)
    for start in range(d, len(y), d):
        end = min(start + d, len(y))
        y[start:end] += g * y[start - d:end - d]
    return y


def reverb(x, mix=0.2, size=1.0):
    out = np.zeros(len(x))
    for d, g in ((1557, 0.82), (1617, 0.8), (1491, 0.81), (1422, 0.79)):
        out += _feedback_delay(x, int(d * size), g)
    out /= 4
    for d, g in ((225, 0.5), (556, 0.5)):
        delayed = np.concatenate([np.zeros(d), out[:-d]])
        fb = _feedback_delay(out, d, g)
        out = -g * out + delayed + g * np.concatenate([np.zeros(d), fb[:-d]])
    out = lowpass(out, 5000)
    return x * (1 - mix) + out * mix


def echo(x, time, fb=0.35, mix=0.3):
    d = int(time * SR)
    wet = _feedback_delay(np.concatenate([np.zeros(d), x[:-d]]), d, fb)
    return x + wet * mix


# ------------------------------------------------------------------ song engine

CHORDS = {
    "": (0, 4, 7), "m": (0, 3, 7), "7": (0, 4, 7, 10), "m7": (0, 3, 7, 10), "maj7": (0, 4, 7, 11),
}


def chord_notes(sym, octave=4):
    root = sym[0]
    rest = sym[1:]
    if rest[:1] in ("#", "b"):
        root += rest[0]
        rest = rest[1:]
    base = midi(root + str(octave))
    return base, [base + i for i in CHORDS[rest]]


class Song:
    def __init__(self, bpm, bars, swing=0.0):
        self.spb = 60.0 / bpm
        self.bars = bars
        self.swing = swing
        self.length = bars * 4 * self.spb
        n = int(self.length * SR) + SR * 4
        self.buses = {}
        self.n = n

    def bus(self, name):
        if name not in self.buses:
            self.buses[name] = [np.zeros(self.n), np.zeros(self.n)]
        return self.buses[name]

    def time(self, beat):
        frac = beat % 1.0
        if self.swing and abs(frac - 0.5) < 1e-6:
            beat += self.swing * 0.5
        return beat * self.spb

    def add(self, sig, beat, bus="main", pan=0.0, gain=1.0):
        start = int(self.time(beat) * SR)
        if start >= self.n:
            return
        end = min(start + len(sig), self.n)
        left, right = self.bus(bus)
        lg = gain * np.sqrt(0.5 * (1 - pan))
        rg = gain * np.sqrt(0.5 * (1 + pan))
        left[start:end] += sig[:end - start] * lg
        right[start:end] += sig[:end - start] * rg

    def drums(self, bars, pattern, start_bar=0, gain=1.0):
        """pattern: dict of instrument -> 16-step string ('x' hit, 'o' soft hit, '.' rest)."""
        for bar in range(start_bar, start_bar + bars):
            for inst, steps in pattern.items():
                n = len(steps)
                for i, ch in enumerate(steps):
                    if ch == ".":
                        continue
                    v = 1.0 if ch == "x" else 0.55
                    beat = bar * 4 + i * 4.0 / n
                    if inst == "kick":
                        self.add(kick(v), beat, "drums", 0, 0.9 * gain)
                    elif inst == "snare":
                        self.add(snare(v), beat, "drums", 0.05, 0.55 * gain)
                    elif inst == "clap":
                        self.add(clap(v), beat, "drums", 0.0, 0.6 * gain)
                    elif inst == "hat":
                        self.add(hat(v, open_=ch == "O"), beat, "drums", 0.3, 0.5 * gain)
                    elif inst == "shaker":
                        self.add(shaker(v), beat, "drums", -0.3, 0.6 * gain)
                    elif inst == "sleigh":
                        self.add(sleigh(v), beat, "drums", -0.25, 0.6 * gain)
                    elif inst == "conga":
                        self.add(conga(220 if i % 3 else 330, v), beat, "drums", 0.4, 0.7 * gain)

    def melody(self, text, inst, start_bar=0, bus="lead", pan=0.0, gain=1.0, transpose=0):
        beat = start_bar * 4.0
        for tok in text.split():
            name, dur = tok.split(":")
            dur = float(dur)
            if name != "r":
                f = hz(midi(name) + transpose)
                self.add(inst(f, dur * self.spb * 0.95), beat, bus, pan, gain)
            beat += dur

    def mixdown(self, bus_fx, master=0.9):
        left = np.zeros(self.n)
        right = np.zeros(self.n)
        for name, (l, r) in self.buses.items():
            fx = bus_fx.get(name)
            if fx:
                l, r = fx(l), fx(r)
            left += l
            right += r
        # Wrap the tail round to the start so the loop is seamless
        loop = int(self.length * SR)
        for ch in (left, right):
            tail = ch[loop:]
            ch[:len(tail)] += tail
        out = np.stack([left[:loop], right[:loop]], axis=1)
        out = np.tanh(out * 1.2) / np.tanh(1.2)
        peak = np.max(np.abs(out)) + 1e-9
        return out / peak * master


def comp_pattern(song, prog, inst, offsets, octave=4, bus="comp", pan=0.0, gain=1.0, length=0.4, start_bar=0):
    """Plays the chord of each bar on the given beat offsets."""
    for i, sym in enumerate(prog):
        _, notes = chord_notes(sym, octave)
        for off in offsets:
            for j, m in enumerate(notes):
                song.add(inst(hz(m), length * song.spb), (start_bar + i) * 4 + off, bus,
                         pan + (j - 1) * 0.1, gain)


def bass_line(song, prog, inst, style, octave=2, gain=1.0, start_bar=0):
    for i, sym in enumerate(prog):
        root, notes = chord_notes(sym, octave)
        fifth = root + 7
        third = notes[1]
        nxt = chord_notes(prog[(i + 1) % len(prog)], octave)[0]
        bar = (start_bar + i) * 4
        if style == "walk":
            approach = nxt - 1 if nxt > root else nxt + 1
            for b, m in enumerate((root, third, fifth, approach)):
                song.add(inst(hz(m), 0.9 * song.spb), bar + b, "bass", 0, gain)
        elif style == "ska":
            for b, m in enumerate((root, root, fifth, root + 12, root, fifth, third, fifth)):
                song.add(inst(hz(m), 0.45 * song.spb), bar + b * 0.5, "bass", 0, gain)
        elif style == "calypso":
            for b, m in ((0, root), (1.5, fifth), (2, root + 12), (3, fifth), (3.5, third)):
                song.add(inst(hz(m), 0.45 * song.spb), bar + b, "bass", 0, gain)
        elif style == "octaves":
            for b in range(8):
                m = root + (12 if b % 2 else 0)
                song.add(inst(hz(m), 0.42 * song.spb), bar + b * 0.5, "bass", 0, gain)
        elif style == "pizz":
            for b, m in ((0, root), (1, fifth), (2, root + 12), (3, fifth)):
                song.add(inst(hz(m), 0.4 * song.spb), bar + b, "bass", 0, gain)


def arpeggio(song, prog, inst, octave=4, gain=1.0, start_bar=0):
    for i, sym in enumerate(prog):
        _, notes = chord_notes(sym, octave)
        seq = notes[:3] + [notes[0] + 12]
        for s in range(16):
            m = seq[s % 4] + (12 if s // 8 else 0)
            song.add(inst(hz(m), 0.22 * song.spb), (start_bar + i) * 4 + s * 0.25, "arp", 0.35 * (1 if s % 2 else -1), gain)


def write_ogg(path, data, quality=5):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav = tmp.name
    pcm = (np.clip(data, -1, 1) * 32767).astype(np.int16)
    wavfile.write(wav, SR, pcm)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", str(quality), path],
                   check=True)
    os.remove(wav)


def fx_reverb(mix, size=1.0):
    return lambda x: reverb(x, mix, size)


# ------------------------------------------------------------------ tracks

MENU_PROG = ["F", "Dm", "Gm", "C7", "F", "Dm", "Bb", "C7", "Bb", "C", "Am", "Dm", "Gm", "C7", "F", "C7"]
MENU_TUNE = """
A4:1 C5:.5 A4:.5 F4:1 G4:1
A4:1.5 F4:.5 D4:2
Bb4:1 D5:.5 Bb4:.5 G4:1 A4:1
Bb4:1.5 A4:.5 G4:2
A4:1 C5:.5 A4:.5 F5:1 E5:1
D5:1.5 C5:.5 A4:2
Bb4:1 D5:1 F5:1 D5:1
C5:3 r:1
D5:1 D5:.5 C5:.5 Bb4:1 D5:1
C5:1 C5:.5 Bb4:.5 A4:1 C5:1
E5:1.5 D5:.5 C5:1 A4:1
D5:2 F5:2
G5:1 F5:.5 E5:.5 D5:1 Bb4:1
C5:1 E5:1 G5:1 Bb5:1
A5:1.5 G5:.5 F5:1 C5:1
E5:.5 F5:.5 G5:1 C5:1 r:1
"""


def track_menu(posh=False):
    s = Song(104 if posh else 108, 32, swing=0.0 if posh else 0.33)
    prog = MENU_PROG * 2
    swing_kit = {"kick": "x.......x.......", "snare": "....o.......o...", "hat": "x.o.x.o.x.o.x.o."}
    s.drums(32, swing_kit, gain=0.5 if posh else 0.8)
    if posh:
        bass_line(s, prog, pluck_bass, "pizz", gain=0.8)
        comp_pattern(s, prog, harpsichord, (0, 1, 2, 3), octave=4, gain=0.6, length=0.5)
        comp_pattern(s, prog, strings, (0,), octave=3, gain=0.8, length=3.9, bus="pad")
        s.melody(MENU_TUNE, strings, 0, gain=1.8, transpose=12)
        s.melody(MENU_TUNE, harpsichord, 16, gain=1.1, transpose=12)
        s.melody(MENU_TUNE, strings, 16, gain=1.0)
    else:
        bass_line(s, prog, bass_round, "walk", gain=0.9)
        comp_pattern(s, prog, epiano, (1, 3), octave=4, gain=0.7, length=0.6)
        s.melody(MENU_TUNE, whistle_lead, 0, gain=1.0, transpose=12)
        s.melody(MENU_TUNE, glock, 16, gain=0.9, transpose=12)
        s.melody(MENU_TUNE, epiano, 16, gain=0.6)
    return s.mixdown({"lead": fx_reverb(0.25), "comp": fx_reverb(0.2), "pad": fx_reverb(0.3)})


SKA_A = ["Bb", "Eb", "F", "Bb", "Bb", "Eb", "F", "F"]
SKA_B = ["Gm", "Eb", "Bb", "F", "Gm", "Eb", "C", "F"]
SKA_TUNE_A = """
D5:.5 F5:.5 r:.5 F5:.5 G5:.5 F5:.5 D5:1
Eb5:.5 G5:.5 r:.5 G5:.5 Bb5:1 G5:1
F5:.5 A5:.5 r:.5 A5:.5 C6:.5 A5:.5 F5:1
D5:1.5 C5:.5 Bb4:2
D5:.5 F5:.5 r:.5 F5:.5 G5:.5 F5:.5 D5:1
Eb5:.5 G5:.5 Bb5:.5 G5:.5 Eb5:1 C5:1
C5:.5 D5:.5 Eb5:.5 F5:.5 G5:.5 A5:.5 Bb5:1
A5:2 r:2
"""
SKA_TUNE_B = """
G5:1 Bb5:1 D6:1.5 C6:.5
Bb5:1 G5:1 Eb5:2
F5:1 D5:1 F5:.5 G5:.5 F5:1
C5:3 r:1
G5:.5 G5:.5 Bb5:.5 G5:.5 D6:1 C6:1
Bb5:.5 Bb5:.5 G5:.5 Bb5:.5 Eb6:2
E5:1 G5:1 C6:1 E6:1
F6:1 C6:.5 A5:.5 F5:1 r:1
"""


def track_street():
    s = Song(150, 32)
    prog = SKA_A + SKA_A + SKA_B + SKA_A
    kit = {"kick": "x.......x.......", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."}
    s.drums(32, kit)
    s.drums(1, {"snare": "....x...x.x.xxxx"}, start_bar=15, gain=0.7)
    bass_line(s, prog, bass_saw, "ska", gain=1.1)
    comp_pattern(s, prog, organ, (0.5, 1.5, 2.5, 3.5), octave=4, gain=0.8, length=0.25)
    s.melody(SKA_TUNE_A, brass, 0, gain=1.0, transpose=-12)
    s.melody(SKA_TUNE_A, brass, 8, gain=0.9, transpose=-12)
    s.melody(SKA_TUNE_A, brass, 8, gain=0.55, transpose=-15, pan=0.3)
    s.melody(SKA_TUNE_B, brass, 16, gain=1.0, transpose=-12)
    s.melody(SKA_TUNE_B, glock, 16, gain=0.5)
    s.melody(SKA_TUNE_A, brass, 24, gain=1.0, transpose=-12)
    s.melody(SKA_TUNE_A, brass, 24, gain=0.5, transpose=0, pan=-0.3)
    return s.mixdown({"lead": fx_reverb(0.18), "comp": fx_reverb(0.15)})


SEA_A = ["C", "F", "G", "C", "C", "F", "G7", "C"]
SEA_B = ["Am", "F", "C", "G", "Am", "D7", "G", "G7"]
SEA_TUNE_A = """
E5:.75 G5:.75 C6:.5 G5:.5 E5:.5 G5:1
F5:.75 A5:.75 C6:.5 A5:1 F5:1
D5:.75 G5:.75 B5:.5 A5:.5 G5:.5 F5:1
E5:2 C5:2
E5:.75 G5:.75 C6:.5 D6:.5 C6:.5 G5:1
A5:.75 C6:.75 F6:.5 E6:.5 D6:.5 C6:1
B5:.5 D6:.5 F6:.5 D6:.5 B5:1 G5:1
C6:3 r:1
"""
SEA_TUNE_B = """
A5:1 C6:.5 E6:.5 r:.5 E6:.5 D6:1
C6:1 A5:.5 F5:.5 r:.5 A5:.5 C6:1
G5:1 E5:.5 C5:.5 r:.5 E5:.5 G5:1
D6:2 B5:2
A5:.5 B5:.5 C6:.5 E6:.5 A6:1 G6:1
F#6:1 E6:.5 D6:.5 C6:1 A5:1
B5:1 D6:1 G6:1 F6:1
D6:.5 B5:.5 G5:1 F5:1 D5:1
"""


def track_seaside():
    s = Song(124, 32)
    prog = SEA_A + SEA_B + SEA_A + SEA_B
    kit = {"kick": "x.....x...x.....", "snare": "....x.......x...", "shaker": "xoxoxoxoxoxoxoxo", "conga": "..x..x....x..x.x"}
    s.drums(32, kit, gain=0.8)
    bass_line(s, prog, bass_round, "calypso", gain=1.0)
    comp_pattern(s, prog, epiano, (0.5, 1.5, 2, 3.5), octave=4, gain=0.55, length=0.3)
    s.melody(SEA_TUNE_A, steel, 0, gain=1.1, transpose=-12)
    s.melody(SEA_TUNE_B, steel, 8, gain=1.1, transpose=-12)
    s.melody(SEA_TUNE_A, steel, 16, gain=1.0, transpose=-12)
    s.melody(SEA_TUNE_A, whistle_lead, 16, gain=0.6, transpose=-12)
    s.melody(SEA_TUNE_B, steel, 24, gain=1.1, transpose=-12)
    s.melody(SEA_TUNE_B, glock, 24, gain=0.5, transpose=-12)
    return s.mixdown({"lead": fx_reverb(0.22), "comp": fx_reverb(0.2)})


SNOW_PROG = ["G", "C", "D", "G", "Em", "C", "A7", "D", "G", "C", "D", "Em", "C", "D", "G", "D7"]
SNOW_TUNE = """
B4:1 D5:1 G5:1.5 F#5:.5
E5:1 G5:1 E5:2
F#5:1 A5:1 D5:1.5 E5:.5
D5:2 B4:2
B4:.5 C5:.5 D5:.5 E5:.5 G5:1 E5:1
G5:1 E5:.5 C5:.5 E5:1 G5:1
A5:1 G5:.5 E5:.5 C#5:1 A4:1
D5:3 r:1
G5:1 B5:1 A5:.5 G5:.5 F#5:1
E5:1 G5:1 C6:2
A5:1 F#5:.5 E5:.5 D5:1 F#5:1
G5:1.5 E5:.5 B4:2
C5:1 E5:1 G5:1 C6:1
B5:1 A5:1 F#5:1 D5:1
G5:1 D5:.5 B4:.5 G4:1 B4:1
A4:1 C5:1 D5:1 F#5:1
"""


def track_snow():
    s = Song(128, 32)
    prog = SNOW_PROG * 2
    kit = {"kick": "x.......x.......", "snare": "....o.......o...", "sleigh": "x.x.x.x.x.x.x.x."}
    s.drums(32, kit, gain=0.8)
    bass_line(s, prog, pluck_bass, "pizz", gain=0.9)
    comp_pattern(s, prog, strings, (0,), octave=3, gain=0.9, length=3.9, bus="pad")
    comp_pattern(s, prog, glock, (1, 3), octave=5, gain=0.25, length=0.4)
    s.melody(SNOW_TUNE, glock, 0, gain=1.1)
    s.melody(SNOW_TUNE, whistle_lead, 0, gain=0.4)
    s.melody(SNOW_TUNE, brass, 16, gain=0.9, transpose=-12)
    s.melody(SNOW_TUNE, glock, 16, gain=0.7, transpose=12)
    return s.mixdown({"lead": fx_reverb(0.3, 1.2), "comp": fx_reverb(0.3), "pad": fx_reverb(0.35)})


NIGHT_PROG = ["Am", "F", "C", "G", "Am", "F", "C", "G", "F", "G", "Em", "Am", "F", "G", "E", "E"]
NIGHT_TUNE = """
A4:1.5 C5:1.5 E5:1
F5:1.5 E5:1.5 C5:1
G5:1.5 E5:1.5 C5:1
D5:2 B4:2
A4:1.5 C5:1.5 E5:1
A5:1.5 G5:1.5 F5:1
E5:1.5 G5:1.5 C6:1
B5:3 r:1
C6:1 A5:1 F5:1 A5:1
B5:1 G5:1 D5:1 G5:1
E5:.5 G5:.5 B5:1 E6:1 D6:1
C6:2 A5:2
A5:.5 C6:.5 F6:1 E6:1 C6:1
D6:.5 B5:.5 G5:1 B5:1 D6:1
G#5:1 B5:1 E6:1 D6:1
B5:2 G#5:1 E5:1
"""


def track_night():
    s = Song(112, 32)
    prog = NIGHT_PROG * 2
    kit = {"kick": "x...x...x...x...", "clap": "....x.......x...", "hat": "..x...x...x...x."}
    s.drums(32, kit, gain=0.9)
    bass_line(s, prog, bass_saw, "octaves", octave=2, gain=1.0)
    comp_pattern(s, prog, pad, (0,), octave=4, gain=1.0, length=3.9, bus="pad")
    arpeggio(s, prog, arp_synth, octave=4, gain=0.8)
    s.melody(NIGHT_TUNE, square_lead, 16, gain=1.2)
    s.melody(NIGHT_TUNE, square_lead, 16, gain=0.5, transpose=-12, pan=0.2)
    return s.mixdown({"lead": lambda x: reverb(echo(x, s.spb * 0.75, 0.35, 0.35), 0.25),
                      "pad": fx_reverb(0.4), "arp": lambda x: echo(x, s.spb * 0.5, 0.3, 0.25)})


def stinger(kind):
    s = Song(140, 2)
    if kind == "win":
        for i, n in enumerate(("F4", "Bb4", "D5")):
            s.add(brass(hz(midi(n)), 0.18), i * 0.333, "lead")
        for n in ("Bb4", "D5", "F5", "Bb5"):
            s.add(brass(hz(midi(n)), 1.6), 1.0, "lead", gain=0.7)
        s.add(glock(hz(midi("Bb5")), 1.0), 1.0, "lead")
        s.add(kick(), 1.0, "drums")
        s.add(hat(1, True), 1.0, "drums")
    elif kind == "lose":
        for i, n in enumerate(("Bb3", "A3", "Ab3")):
            s.add(brass(hz(midi(n)), 0.45), i * 0.8, "lead")
        t = tvec(1.6)
        f = hz(midi("G3")) * (1 + 0.03 * np.sin(2 * np.pi * 7 * t))
        x = lowpass(saw(f, t), 1200) * adsr(len(t), 0.02, 0.3, 0.8, 0.4) * 0.3
        s.add(x, 2.4, "lead")
    elif kind == "unlock":
        for i, n in enumerate(("C6", "E6", "G6", "C7", "E7")):
            s.add(glock(hz(midi(n)), 0.5), i * 0.25, "lead", gain=0.9)
        s.add(hat(1, True), 1.25, "drums")
    elif kind == "quota":
        for n in ("F4", "A4", "C5", "F5"):
            s.add(brass(hz(midi(n)), 0.5), 0.0, "lead", gain=0.6)
            s.add(brass(hz(midi(n)), 0.8), 0.75, "lead", gain=0.7)
        s.add(kick(), 0.0, "drums")
        s.add(kick(), 0.75, "drums")
    out = s.mixdown({"lead": fx_reverb(0.25)}, master=0.85)
    # Stingers do not loop, so cut the wrap-around and fade out
    return out


def render_stinger(kind, seconds):
    s_out = stinger(kind)
    n = int(seconds * SR)
    out = np.zeros((n, 2))
    m = min(n, len(s_out))
    out[:m] = s_out[:m]
    fade = np.linspace(1, 0, int(0.2 * SR))
    out[-len(fade):] *= fade[:, None]
    return out


# ------------------------------------------------------------------ sound effects

def norm(x, peak=0.9):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def sfx_whistle():
    t = tvec(0.7)
    trill = 1 + 0.06 * np.sign(np.sin(2 * np.pi * 28 * t))
    f = 2900 * trill * (1 + 0.02 * np.sin(2 * np.pi * 3 * t))
    x = np.sin(phase(f, t)) + 0.15 * bandpass(rng.standard_normal(len(t)), 2000, 6000)
    return norm(x * adsr(len(t), 0.01, 0.2, 0.9, 0.12)) * 0.7


def sfx_whistle_long():
    t = tvec(1.2)
    trill = 1 + 0.06 * np.sign(np.sin(2 * np.pi * 26 * t))
    x = np.sin(phase(2800 * trill, t)) + 0.15 * bandpass(rng.standard_normal(len(t)), 2000, 6000)
    return norm(x * adsr(len(t), 0.02, 0.3, 0.9, 0.2)) * 0.7


def sfx_stamp():
    t = tvec(0.35)
    thump = np.sin(phase(90 + 120 * np.exp(-t * 40), t)) * np.exp(-t * 18)
    click = highpass(rng.standard_normal(len(t)), 2500) * np.exp(-t * 90)
    return norm(thump + 0.7 * click)


def sfx_punch_swing():
    t = tvec(0.22)
    x = bandpass(rng.standard_normal(len(t)), 700, 3200)
    return norm(x * np.sin(np.pi * t / 0.22) ** 2) * 0.5


def sfx_punch_hit():
    t = tvec(0.4)
    thump = np.sin(phase(70 + 160 * np.exp(-t * 30), t)) * np.exp(-t * 12)
    crack = lowpass(rng.standard_normal(len(t)), 3500) * np.exp(-t * 35)
    slap = highpass(rng.standard_normal(len(t)), 3000) * np.exp(-t * 120)
    return norm(np.tanh(2.5 * (thump + 0.8 * crack + 0.5 * slap)))


def sfx_boing():
    t = tvec(0.6)
    f = 180 + 260 * np.abs(np.sin(2 * np.pi * 5 * t)) * np.exp(-t * 3)
    return norm(np.sin(phase(f, t)) * np.exp(-t * 4)) * 0.7


def sfx_honk(pitch=1.0):
    t = tvec(0.45)
    x = np.tanh(3 * (np.sin(phase(370 * pitch, t)) + np.sin(phase(466 * pitch, t))))
    x = lowpass(x, 3000)
    return norm(x * adsr(len(t), 0.01, 0.1, 0.9, 0.06)) * 0.6


def sfx_ui(kind):
    if kind == "move":
        t = tvec(0.06)
        return norm(np.sin(2 * np.pi * 880 * t) * np.exp(-t * 50)) * 0.4
    if kind == "select":
        out = np.zeros(int(0.22 * SR))
        for i, f in enumerate((660, 990)):
            t = tvec(0.12)
            s = int(i * 0.07 * SR)
            out[s:s + len(t)] += pulse(f, t, 0.25) * np.exp(-t * 25) * 0.5
        return norm(lowpass(out, 5000)) * 0.45
    if kind == "back":
        out = np.zeros(int(0.22 * SR))
        for i, f in enumerate((660, 440)):
            t = tvec(0.12)
            s = int(i * 0.07 * SR)
            out[s:s + len(t)] += pulse(f, t, 0.25) * np.exp(-t * 25) * 0.5
        return norm(lowpass(out, 4000)) * 0.4
    if kind == "tick":
        t = tvec(0.04)
        return norm(highpass(rng.standard_normal(len(t)), 3000) * np.exp(-t * 120)) * 0.35


def sfx_ding():
    t = tvec(0.9)
    x = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, a, d in ((1568, 1, 4), (2349, 0.5, 6), (3136, 0.3, 9)))
    return norm(x) * 0.6


def sfx_combo():
    out = np.zeros(int(0.35 * SR))
    for i, m in enumerate((72, 76, 79, 84)):
        t = tvec(0.15)
        s = int(i * 0.05 * SR)
        out[s:s + len(t)] += glock(hz(m), 0.1)[:len(t)]
    return norm(out) * 0.6


def sfx_wrong():
    t = tvec(0.5)
    x = lowpass(pulse(110, t, 0.5) + pulse(116, t, 0.5), 2000)
    return norm(x * adsr(len(t), 0.005, 0.2, 0.8, 0.05)) * 0.5


def sfx_scribble():
    t = tvec(0.8)
    n = bandpass(rng.standard_normal(len(t)), 2000, 8000)
    mod = 0.5 + 0.5 * np.sin(2 * np.pi * 9 * t + 2 * np.sin(2 * np.pi * 3 * t))
    return norm(n * mod * adsr(len(t), 0.02, 0.2, 0.8, 0.1)) * 0.3


def sfx_whoosh():
    t = tvec(0.35)
    x = lowpass(rng.standard_normal(len(t)), 1800) * np.sin(np.pi * t / 0.35) ** 2
    return norm(x) * 0.5


def sfx_thud():
    t = tvec(0.3)
    x = np.sin(phase(60 + 60 * np.exp(-t * 30), t)) * np.exp(-t * 14) + 0.3 * lowpass(rng.standard_normal(len(t)), 600) * np.exp(-t * 20)
    return norm(x) * 0.7


def sfx_countdown(high=False):
    t = tvec(0.25 if not high else 0.6)
    f = 1320 if high else 880
    return norm(pulse(f, t, 0.5) * 0.5 * adsr(len(t), 0.005, 0.1, 0.8, 0.05)) * 0.4


def sfx_star():
    t = tvec(0.7)
    x = glock(hz(84), 0.6)[:len(t)] + 0.5 * glock(hz(91), 0.6)[:len(t)]
    return norm(x) * 0.6


def sfx_brakes():
    t = tvec(0.5)
    f = 2200 + 300 * np.sin(2 * np.pi * 13 * t)
    x = np.sin(phase(f, t)) * np.exp(-t * 4) * np.clip(t / 0.03, 0, 1)
    return norm(x) * 0.15


def sfx_engine_pass():
    t = tvec(1.6)
    dist = (t - 0.8) / 0.5
    loud = 1 / (1 + dist ** 2)
    f = 55 * (1 + 0.08 * -np.tanh(dist))
    x = lowpass(saw(f, t) + 0.5 * saw(f * 2, t), 600) + 0.3 * lowpass(rng.standard_normal(len(t)), 900)
    x *= loud * np.clip(t / 0.1, 0, 1) * np.clip((1.6 - t) / 0.1, 0, 1)
    return norm(x) * 0.45


def sfx_thunder():
    t = tvec(3.5)
    crack = highpass(rng.standard_normal(len(t)), 1500) * np.exp(-t * 25) * 0.6
    rumble = lowpass(rng.standard_normal(len(t)), 180, 4) * (np.exp(-t * 0.9) * (0.7 + 0.3 * np.sin(2 * np.pi * 1.7 * t)))
    return norm(crack + rumble * 6) * 0.9


def ambience(kind, seconds=20.0):
    t = tvec(seconds)
    n = len(t)
    if kind == "birds":
        x = lowpass(rng.standard_normal(n), 400) * 0.08
        for _ in range(26):
            start = rng.uniform(0, seconds - 1)
            f0 = rng.uniform(2500, 4500)
            for k in range(rng.integers(2, 6)):
                tt = tvec(0.08)
                chirp = np.sin(phase(f0 * (1 + 0.4 * np.sin(np.pi * tt / 0.08)), tt)) * np.sin(np.pi * tt / 0.08)
                s = int((start + k * 0.11) * SR) % (n - len(tt))
                x[s:s + len(tt)] += chirp * 0.2
    elif kind == "waves":
        swell = 0.55 + 0.45 * np.sin(2 * np.pi * t / 6.6) ** 2
        x = lowpass(rng.standard_normal(n), 900) * swell * 0.5
        for _ in range(6):
            start = rng.uniform(0, seconds - 1)
            tt = tvec(0.5)
            gull = np.sin(phase(1400 * (1 - 0.3 * tt / 0.5), tt)) * np.sin(np.pi * tt / 0.5) * 0.1
            s = int(start * SR) % (n - len(tt))
            x[s:s + len(tt)] += gull
    elif kind == "city":
        x = lowpass(rng.standard_normal(n), 250) * 0.5 + 0.05 * np.sin(2 * np.pi * 60 * t)
        for _ in range(5):
            start = rng.uniform(0, seconds - 1)
            hk = sfx_honk(rng.uniform(0.7, 1.2)) * 0.12
            s = int(start * SR) % (n - len(hk))
            x[s:s + len(hk)] += lowpass(hk, 1500)
    elif kind == "rain":
        x = bandpass(rng.standard_normal(n), 800, 9000) * 0.35
        for _ in range(400):
            tt = tvec(0.03)
            drop = highpass(rng.standard_normal(len(tt)), 3000) * np.exp(-tt * 200) * rng.uniform(0.1, 0.4)
            st = int(rng.uniform(0, seconds - 0.1) * SR)
            x[st:st + len(tt)] += drop
    elif kind == "wind":
        gust = 0.5 + 0.5 * np.sin(2 * np.pi * t / 5.0 + np.sin(2 * np.pi * t / 3.0))
        x = bandpass(rng.standard_normal(n), 300, 1500) * gust * 0.4
    # Crossfade the ends so the loop is seamless
    fade = int(SR * 1.0)
    x[:fade] = x[:fade] * np.linspace(0, 1, fade) + x[-fade:] * np.linspace(1, 0, fade)
    x = x[:-fade]
    return norm(x) * 0.5


# ------------------------------------------------------------------ voices

HECKLES = [
    "Get a proper job!", "Oi! Get a proper job!", "Get a proper job, mate!", "Get a real job!",
    "Jobsworth!", "Nobody likes you!", "Get a proper job, you muppet!", "Get a proper job, sunshine!",
]
DRIVER_LINES = {
    "oi": "Oi! That's my car!", "what": "You what?!", "minutes": "I was only two minutes!",
    "comehere": "Come here!", "minute": "I was only here for a minute!",
    "where": "Where else am I meant to park?!", "tosser": "You're a tosser!", "jobsworth": "Jobsworth!", "takethat": "Ha! Take that!", "hmph": "Hmph!",
}
PUNCHED_LINES = {"ow": "Ow!", "nose": "My nose!", "oof": "Ooof!", "mum": "I'm telling my mum!"}
WARDEN_LINES = {"oof": "Oof!", "hiyah": "Hi-yah!", "niceday": "Have a nice day!", "gotcha": "Gotcha!",
                "rules": "Rules is rules!"}
ANNOUNCER = {"shift_start": "Shift start!", "quota": "Quota met!", "shift_over": "Shift over!",
             "go": "Go!"}

VOICES = [("en-gb+m3", 45, 175), ("en-gb-x-gbcwmd+m1", 35, 170), ("en-gb-scotland+m2", 50, 180),
          ("en-gb+f3", 70, 175), ("en-gb-x-gbclan+m4", 30, 165), ("en-gb+f4", 65, 185)]


def speak(text, voice, pitch, speed, shout=True, radio=False):
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav = tmp.name
    subprocess.run(["espeak-ng", "-v", voice, "-p", str(pitch), "-s", str(speed), "-a", "180", "-w", wav, text],
                   check=True)
    sr, data = wavfile.read(wav)
    os.remove(wav)
    x = data.astype(np.float64) / 32768.0
    if sr != SR:
        x = signal.resample_poly(x, SR, sr)
    if shout:
        x = np.tanh(x * 4.0)
    if radio:
        x = bandpass(x, 400, 3500)
    x = highpass(x, 120)
    return norm(x, 0.9)


def mono_to_stereo(x):
    return np.stack([x, x], axis=1)


def main():
    music = os.path.join(ROOT, "music")
    sfx = os.path.join(ROOT, "sfx")
    voice = os.path.join(ROOT, "voice")
    tracks = {
        "menu": lambda: track_menu(False), "posh": lambda: track_menu(True), "street": track_street,
        "seaside": track_seaside, "snow": track_snow, "night": track_night,
    }
    for name, fn in tracks.items():
        print("music", name)
        write_ogg(os.path.join(music, name + ".ogg"), fn(), quality=4)
    for kind, secs in (("win", 3.5), ("lose", 4.5), ("unlock", 1.8), ("quota", 1.8)):
        write_ogg(os.path.join(music, "sting_" + kind + ".ogg"), render_stinger(kind, secs))

    effects = {
        "whistle": sfx_whistle(), "whistle_long": sfx_whistle_long(), "stamp": sfx_stamp(),
        "punch_swing": sfx_punch_swing(), "punch_hit": sfx_punch_hit(), "boing": sfx_boing(),
        "honk": sfx_honk(), "ui_move": sfx_ui("move"), "ui_select": sfx_ui("select"), "ui_back": sfx_ui("back"),
        "tick": sfx_ui("tick"), "ding": sfx_ding(), "combo": sfx_combo(), "wrong": sfx_wrong(),
        "scribble": sfx_scribble(), "whoosh": sfx_whoosh(), "thud": sfx_thud(), "beep": sfx_countdown(),
        "beep_go": sfx_countdown(True), "star": sfx_star(), "brakes": sfx_brakes(), "engine_pass": sfx_engine_pass(),
        "thunder": sfx_thunder(),
    }
    for name, data in effects.items():
        write_ogg(os.path.join(sfx, name + ".ogg"), mono_to_stereo(data))
    for kind in ("birds", "waves", "city", "wind", "rain"):
        print("ambience", kind)
        write_ogg(os.path.join(sfx, "amb_" + kind + ".ogg"), mono_to_stereo(ambience(kind)), quality=2)

    for i, line in enumerate(HECKLES):
        for j in range(2):
            v, p, s = VOICES[(i * 2 + j) % len(VOICES)]
            write_ogg(os.path.join(voice, "heckle_%d_%d.ogg" % (i, j)), mono_to_stereo(speak(line, v, p, s)))
    for key, line in DRIVER_LINES.items():
        for j in range(2):
            v, p, s = VOICES[(sum(map(ord, key)) + j * 3) % len(VOICES)]
            write_ogg(os.path.join(voice, "driver_%s_%d.ogg" % (key, j)), mono_to_stereo(speak(line, v, p, s)))
    for key, line in PUNCHED_LINES.items():
        v, p, s = VOICES[len(key) % len(VOICES)]
        write_ogg(os.path.join(voice, "punched_%s.ogg" % key), mono_to_stereo(speak(line, v, p + 10, s + 20)))
    for key, line in WARDEN_LINES.items():
        write_ogg(os.path.join(voice, "warden_%s.ogg" % key), mono_to_stereo(speak(line, "en-gb-x-rp+m1", 40, 165, False)))
    for key, line in ANNOUNCER.items():
        write_ogg(os.path.join(voice, "announce_%s.ogg" % key),
                  mono_to_stereo(speak(line, "en-gb+m7", 35, 150, False, radio=True)))
    print("done")


# ------------------------------------------------------------------ new tracks (career update)

BOSS_PROG = ["Dm", "Dm", "Bb", "A7", "Dm", "Dm", "Gm", "A7", "Bb", "C", "Dm", "Dm", "Gm", "A7", "Dm", "A7"]
BOSS_TUNE = """
D5:.5 D5:.5 F5:.5 D5:.5 A5:1 G5:1
F5:.5 E5:.5 D5:.5 E5:.5 F5:2
D5:.5 D5:.5 F5:.5 D5:.5 Bb5:1 A5:1
G5:.5 F5:.5 E5:.5 F5:.5 E5:1 C#5:1
D5:.5 F5:.5 A5:.5 D6:.5 C6:1 A5:1
Bb5:.5 A5:.5 G5:.5 F5:.5 E5:2
F5:.5 G5:.5 A5:.5 Bb5:.5 A5:1 G5:1
E5:1 C#5:1 A4:2
"""


def track_boss():
    s = Song(164, 16)
    prog = BOSS_PROG
    kit = {"kick": "x...x...x...x.x.", "snare": "....x.......x..x", "hat": "x.x.x.x.x.x.x.x."}
    s.drums(16, kit)
    s.drums(1, {"snare": "x.x.x.x.xxxxxxxx"}, start_bar=7, gain=0.6)
    bass_line(s, prog, bass_saw, "octaves", octave=2, gain=1.2)
    comp_pattern(s, prog, brass, (0, 1.5, 3), octave=3, gain=0.6, length=0.3)
    comp_pattern(s, prog, strings, (0,), octave=4, gain=0.5, length=3.9, bus="pad")
    s.melody(BOSS_TUNE, brass, 0, gain=0.9)
    s.melody(BOSS_TUNE, square_lead, 8, gain=0.8)
    s.melody(BOSS_TUNE, brass, 8, gain=0.6, transpose=-12)
    return s.mixdown({"lead": fx_reverb(0.15), "pad": fx_reverb(0.3)})


ENDLESS_PROG = ["Em", "C", "G", "D", "Em", "C", "Am", "B7"]
ENDLESS_TUNE = """
E5:.5 G5:.5 B5:1 A5:.5 G5:.5 E5:1
C5:.5 E5:.5 G5:1 F#5:.5 E5:.5 C5:1
D5:.5 G5:.5 B5:1 D6:1 B5:1
A5:.5 F#5:.5 D5:1 F#5:2
E5:.5 G5:.5 B5:1 E6:1 D6:1
C6:.5 B5:.5 G5:1 E5:2
A5:.5 C6:.5 E6:1 D6:.5 C6:.5 A5:1
B5:1 D#6:1 F#6:2
"""


def track_endless():
    s = Song(140, 32)
    prog = ENDLESS_PROG * 4
    kit = {"kick": "x...x...x...x...", "clap": "....x.......x...", "hat": "..x...x...x...x."}
    s.drums(8, {"kick": "x...x...x...x...", "hat": "..x...x...x...x."}, gain=0.9)
    s.drums(24, kit, start_bar=8)
    bass_line(s, prog, bass_saw, "octaves", octave=2, gain=1.0)
    arpeggio(s, prog, arp_synth, octave=4, gain=0.8)
    comp_pattern(s, prog, pad, (0,), octave=4, gain=0.8, length=3.9, bus="pad")
    s.melody(ENDLESS_TUNE, square_lead, 8, gain=1.0)
    s.melody(ENDLESS_TUNE, square_lead, 16, gain=1.0, transpose=12)
    s.melody(ENDLESS_TUNE, glock, 24, gain=0.8, transpose=12)
    s.melody(ENDLESS_TUNE, square_lead, 24, gain=0.6)
    return s.mixdown({"lead": lambda x: reverb(echo(x, s.spb * 0.75, 0.3, 0.3), 0.2),
                      "pad": fx_reverb(0.4), "arp": lambda x: echo(x, s.spb * 0.5, 0.3, 0.2)})


VERSUS_PROG = ["C", "C", "F", "G", "Am", "F", "D7", "G7"]
VERSUS_TUNE = """
G4:.5 C5:.5 E5:.5 G5:.5 r:.5 E5:.5 G5:1
A5:.5 G5:.5 E5:.5 C5:.5 D5:2
F5:.5 F5:.5 A5:.5 F5:.5 G5:1 E5:1
D5:.5 E5:.5 F5:.5 D5:.5 G5:2
A5:.5 A5:.5 C6:.5 A5:.5 G5:1 E5:1
F5:.5 A5:.5 C6:.5 A5:.5 F5:2
F#5:.5 A5:.5 D6:.5 C6:.5 A5:1 F#5:1
G5:1 B5:1 D6:1 r:1
"""


def track_versus():
    s = Song(132, 32, swing=0.2)
    prog = VERSUS_PROG * 4
    kit = {"kick": "x..x..x...x..x..", "snare": "....x.......x...", "hat": "xoxoxoxoxoxoxoxo"}
    s.drums(32, kit, gain=0.9)
    bass_line(s, prog, bass_round, "calypso", gain=1.0)
    comp_pattern(s, prog, organ, (0.5, 1.5, 2.5, 3.5), octave=4, gain=0.6, length=0.25)
    s.melody(VERSUS_TUNE, brass, 0, gain=0.9, transpose=-12)
    s.melody(VERSUS_TUNE, whistle_lead, 8, gain=0.9)
    s.melody(VERSUS_TUNE, brass, 16, gain=0.9, transpose=-12)
    s.melody(VERSUS_TUNE, glock, 16, gain=0.6)
    s.melody(VERSUS_TUNE, square_lead, 24, gain=0.8)
    return s.mixdown({"lead": fx_reverb(0.2), "comp": fx_reverb(0.15)})


# Wagner's Bridal Chorus (1850, public domain), played as a jaunty church organ romp
WEDDING_PROG = ["F", "F", "C7", "F", "F", "Bb", "C7", "F"] * 2
WEDDING_TUNE = """
C5:1 F5:.75 F5:.25 F5:2
C5:1 G5:.75 E5:.25 F5:2
C5:1 F5:.75 Bb5:.25 Bb5:1 A5:.75 G5:.25
F5:.75 E5:.25 F5:.75 G5:.25 F5:2
C5:1 F5:.75 F5:.25 F5:2
C5:1 G5:.75 E5:.25 F5:2
C5:1 F5:.75 A5:.25 C6:1 A5:.75 F5:.25
D5:1 F5:.75 G5:.25 F5:2
"""


def bell(f, dur, v=1.0):
    t = tvec(max(dur, 1.2))
    x = sum(a * np.sin(2 * np.pi * f * m * t) * np.exp(-t * d) for m, a, d in ((1, 1, 2.5), (2.76, 0.4, 4), (5.4, 0.25, 7)))
    return x * 0.25 * v


def track_wedding():
    s = Song(110, 16)
    prog = WEDDING_PROG
    kit = {"kick": "x.......x.......", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.x."}
    s.drums(8, kit, start_bar=8, gain=0.7)
    bass_line(s, prog, pluck_bass, "pizz", gain=0.9)
    comp_pattern(s, prog, organ, (0, 2), octave=3, gain=0.7, length=1.8, bus="pad")
    s.melody(WEDDING_TUNE, organ, 0, gain=1.2)
    s.melody(WEDDING_TUNE, bell, 8, gain=1.0, transpose=12)
    s.melody(WEDDING_TUNE, brass, 8, gain=0.7, transpose=-12)
    for bar in range(16):
        s.add(bell(hz(midi("F6")), 1.0), bar * 4, "lead", 0.4, 0.4)
    return s.mixdown({"lead": fx_reverb(0.35, 1.3), "pad": fx_reverb(0.4, 1.3)})


MATCH_PROG = ["G", "G", "C", "D", "G", "Em", "C", "D"]
MATCH_TUNE = """
D5:1 D5:.5 D5:.5 B4:1 G4:1
C5:1 C5:.5 C5:.5 E5:1 C5:1
D5:1 D5:.5 D5:.5 G5:1 D5:1
E5:.5 D5:.5 C5:.5 B4:.5 A4:2
D5:1 D5:.5 D5:.5 B4:1 G4:1
E5:1 E5:.5 E5:.5 G5:1 E5:1
C5:.5 D5:.5 E5:.5 F#5:.5 G5:1 E5:1
D5:2 A4:1 r:1
"""


def crowd(seconds):
    t = tvec(seconds)
    x = bandpass(rng.standard_normal(len(t)), 300, 2500) * (0.7 + 0.3 * np.sin(2 * np.pi * t / 4.0))
    return x * 0.35


def track_matchday():
    s = Song(124, 16)
    prog = MATCH_PROG * 2
    kit = {"kick": "x.x.x.x.x.x.x.x.", "clap": "x...x...x...x...", "snare": "......x.......x."}
    s.drums(16, kit, gain=0.8)
    bass_line(s, prog, bass_round, "pizz", gain=1.0)
    comp_pattern(s, prog, brass, (0, 2), octave=3, gain=0.5, length=1.6, bus="pad")
    s.melody(MATCH_TUNE, brass, 0, gain=1.0)
    s.melody(MATCH_TUNE, brass, 0, gain=0.5, transpose=-12, pan=0.3)
    s.melody(MATCH_TUNE, brass, 8, gain=1.0)
    s.melody(MATCH_TUNE, whistle_lead, 8, gain=0.5, transpose=12)
    s.add(crowd(s.length), 0, "crowd", 0, 1.0)
    return s.mixdown({"lead": fx_reverb(0.35, 1.4), "pad": fx_reverb(0.3), "crowd": fx_reverb(0.2)})


# Jingle Bells (1857, public domain)
XMAS_PROG = ["C", "C", "C", "C", "F", "C", "D7", "G7", "C", "C", "C", "C", "F", "C", "G7", "C"]
XMAS_TUNE = """
E5:1 E5:1 E5:2
E5:1 E5:1 E5:2
E5:1 G5:1 C5:1.5 D5:.5
E5:4
F5:1 F5:1 F5:1.5 F5:.5
F5:1 E5:1 E5:1 E5:.5 E5:.5
E5:1 D5:1 D5:1 E5:1
D5:2 G5:2
E5:1 E5:1 E5:2
E5:1 E5:1 E5:2
E5:1 G5:1 C5:1.5 D5:.5
E5:4
F5:1 F5:1 F5:1.5 F5:.5
F5:1 E5:1 E5:1 E5:.5 E5:.5
G5:1 G5:1 F5:1 D5:1
C5:4
"""


def track_xmas():
    s = Song(168, 32, swing=0.25)
    prog = XMAS_PROG * 2
    kit = {"kick": "x.......x.......", "snare": "....x.......x...", "sleigh": "xoxoxoxoxoxoxoxo"}
    s.drums(32, kit, gain=0.8)
    bass_line(s, prog, bass_round, "walk", gain=0.9)
    comp_pattern(s, prog, epiano, (1, 3), octave=4, gain=0.6, length=0.5)
    s.melody(XMAS_TUNE, glock, 0, gain=1.1)
    s.melody(XMAS_TUNE, whistle_lead, 0, gain=0.4)
    s.melody(XMAS_TUNE, brass, 16, gain=0.9, transpose=-12)
    s.melody(XMAS_TUNE, bell, 16, gain=0.8, transpose=12)
    return s.mixdown({"lead": fx_reverb(0.3, 1.2), "comp": fx_reverb(0.25)})


def extra_stinger(kind):
    s = Song(140, 3)
    if kind == "boss":
        for i, n in enumerate(("D4", "C#4", "C4", "B3")):
            s.add(brass(hz(midi(n)), 0.3), i * 0.5, "lead", gain=0.8)
            s.add(brass(hz(midi(n) - 12), 0.3), i * 0.5, "lead", gain=0.6)
        for n in ("D3", "F3", "Ab3", "B3"):
            s.add(strings(hz(midi(n)), 2.0), 2.0, "lead", gain=0.9)
        s.add(kick(), 2.0, "drums")
        s.add(snare(), 2.0, "drums")
    elif kind == "rankup":
        for i, n in enumerate(("C4", "E4", "G4", "C5", "E5")):
            s.add(brass(hz(midi(n)), 0.2), i * 0.25, "lead", gain=0.8)
        for n in ("C5", "E5", "G5", "C6"):
            s.add(brass(hz(midi(n)), 2.0), 1.5, "lead", gain=0.6)
        for i, n in enumerate(("C6", "E6", "G6", "C7")):
            s.add(glock(hz(midi(n)), 0.6), 1.5 + i * 0.25, "lead", gain=0.7)
        s.add(kick(), 1.5, "drums")
        s.add(hat(1, True), 1.5, "drums")
    return s.mixdown({"lead": fx_reverb(0.3)}, master=0.85)


def render_extra_stinger(kind, seconds):
    s_out = extra_stinger(kind)
    n = int(seconds * SR)
    out = np.zeros((n, 2))
    m = min(n, len(s_out))
    out[:m] = s_out[:m]
    fade = np.linspace(1, 0, int(0.25 * SR))
    out[-len(fade):] *= fade[:, None]
    return out


# ------------------------------------------------------------------ new sound effects (career update)

def _place(out, sig, at):
    s = int(at * SR)
    e = min(len(out), s + len(sig))
    out[s:e] += sig[:e - s]


def sfx_clamp():
    out = np.zeros(int(0.8 * SR))
    for i in range(5):
        t = tvec(0.05)
        _place(out, highpass(rng.standard_normal(len(t)), 2500) * np.exp(-t * 90) * 0.5, 0.05 + i * 0.07)
    t = tvec(0.5)
    clank = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, d in ((420, 9), (1130, 12), (2210, 18)))
    _place(out, clank, 0.42)
    return norm(out) * 0.7


def sfx_tow():
    t = tvec(1.8)
    f = 45 + 35 * np.clip(t / 0.6, 0, 1)
    eng = lowpass(saw(f, t) + 0.6 * saw(f * 2.02, t), 900) * adsr(len(t), 0.05, 0.3, 0.8, 0.4)
    out = eng * 0.6
    for i in range(10):
        tt = tvec(0.04)
        _place(out, highpass(rng.standard_normal(len(tt)), 3000) * np.exp(-tt * 100) * 0.4, 0.2 + i * 0.09)
    return norm(out) * 0.7


def sfx_camera():
    out = np.zeros(int(0.45 * SR))
    for at in (0.0, 0.09):
        t = tvec(0.04)
        _place(out, highpass(rng.standard_normal(len(t)), 1500) * np.exp(-t * 140), at)
    t = tvec(0.3)
    _place(out, np.sin(phase(1500 + 2500 * t / 0.3, t)) * np.exp(-t * 8) * 0.15, 0.12)
    return norm(out) * 0.6


def sfx_cash():
    out = np.zeros(int(1.0 * SR))
    t = tvec(0.08)
    _place(out, highpass(rng.standard_normal(len(t)), 2000) * np.exp(-t * 60) * 0.6, 0.0)
    t = tvec(0.9)
    ring = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, a, d in ((2637, 1, 4), (3520, 0.6, 5), (5274, 0.3, 7)))
    _place(out, ring, 0.1)
    return norm(out) * 0.6


def sfx_chimes():
    tune = ("G5", "C6", "C6", "D6", "E6", "G6", "E6", "C6")
    out = np.zeros(int(2.6 * SR))
    for i, n in enumerate(tune):
        f = hz(midi(n)) * (1 + 0.01 * np.sin(i))
        t = tvec(0.5)
        x = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 3.01 * t)) * np.exp(-t * 6)
        _place(out, x, i * 0.28)
    return norm(out) * 0.5


def sfx_coo():
    out = np.zeros(int(0.9 * SR))
    for at, f0 in ((0.0, 420), (0.32, 380)):
        t = tvec(0.28)
        f = f0 * (1 + 0.25 * np.sin(np.pi * t / 0.28))
        x = np.sin(phase(f, t)) * np.sin(np.pi * t / 0.28) ** 1.5
        x = lowpass(np.tanh(2 * x) + 0.2 * rng.standard_normal(len(t)) * np.sin(np.pi * t / 0.28), 1200)
        _place(out, x, at)
    return norm(out) * 0.5


def sfx_flap():
    out = np.zeros(int(0.8 * SR))
    for i in range(9):
        t = tvec(0.06)
        _place(out, bandpass(rng.standard_normal(len(t)), 400, 2500) * np.sin(np.pi * t / 0.06), i * 0.075)
    return norm(out) * 0.6


def sfx_rattle():
    t = tvec(1.2)
    x = highpass(rng.standard_normal(len(t)), 1800) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 22 * t)))
    x += 0.4 * np.sin(phase(1900 + 300 * np.sin(2 * np.pi * 7 * t), t)) * (rng.random(len(t)) < 0.3)
    return norm(x * adsr(len(t), 0.02, 0.2, 0.9, 0.2)) * 0.45


def sfx_slurp():
    t = tvec(0.7)
    f = 300 + 500 * t / 0.7
    gurgle = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 18 * t))
    x = bandpass(rng.standard_normal(len(t)), 500, 3000) * gurgle * 0.5 + 0.4 * np.sin(phase(f, t)) * gurgle
    out = np.zeros(int(1.0 * SR))
    _place(out, x * adsr(len(t), 0.02, 0.1, 0.9, 0.1), 0.0)
    t = tvec(0.2)
    _place(out, np.sin(phase(600 - 300 * t / 0.2, t)) * np.exp(-t * 15), 0.75)
    return norm(out) * 0.55


def sfx_splash():
    t = tvec(1.0)
    x = bandpass(rng.standard_normal(len(t)), 300, 6000) * np.exp(-t * 4) * np.clip(t / 0.02, 0, 1)
    for _ in range(25):
        tt = tvec(0.05)
        drop = np.sin(phase(rng.uniform(800, 2500) * (1 + tt * 10), tt)) * np.exp(-tt * 60) * 0.3
        _place(x, drop, rng.uniform(0.1, 0.8))
    return norm(x) * 0.7


def sfx_zap():
    t = tvec(0.9)
    buzz = np.sign(np.sin(2 * np.pi * 110 * t)) * 0.4 + highpass(rng.standard_normal(len(t)), 2000) * (rng.random(len(t)) < 0.15)
    crack = highpass(rng.standard_normal(len(t)), 1000) * np.exp(-t * 30)
    return norm(np.tanh(2 * (buzz * np.exp(-t * 3) + crack))) * 0.6


def sfx_slap():
    t = tvec(0.35)
    wet = bandpass(rng.standard_normal(len(t)), 600, 5000) * np.exp(-t * 30)
    thump = np.sin(phase(140 * np.exp(-t * 5), t)) * np.exp(-t * 20)
    squish = np.sin(phase(400 + 300 * np.sin(2 * np.pi * 9 * t), t)) * np.exp(-t * 10) * 0.2
    return norm(wet + thump + squish) * 0.75


# ------------------------------------------------------------------ new voices (career update)

MORE_HECKLES = [
    "Got nothing better to do?", "My nan parks worse than that!", "Vulture!", "Who hurt you?",
    "I pay your wages!", "Got a quota, have ya?", "Hi vis, low I Q!", "Go catch real criminals!",
    "Nice hat, Napoleon!", "Go and do something useful!", "Typical!", "Boo! Boooo!",
]
EXTRA_LINES = {
    "announce_wave": ("Next wave!", "announcer"), "announce_boss": ("Boss incoming!", "announcer"),
    "announce_p1wins": ("Player one wins!", "announcer"), "announce_p2wins": ("Player two wins!", "announcer"),
    "announce_promoted": ("Promoted!", "announcer"), "warden_backup": ("Backup requested!", "warden"),
}
GROUP_LINES = {
    "boss_mayor": (["Do you know who I am?!", "I'll have your badge for this!", "Guards! Guards!"], ("en-gb-x-rp+m3", 30, 150, True)),
    "boss_vanman": (["Leave it out, mate!", "I'm only dropping off a parcel!", "Ten minutes, tops!"], ("en-gb-x-gbclan+m4", 35, 175, True)),
    "boss_getaway": (["You'll never catch me!", "Floor it!", "So long, sucker!"], ("en-us+m2", 45, 190, True)),
    "heckle_splash": (["Ha! Soaked!", "Enjoy your bath, jobsworth!", "Splish splash!"], None),
    "ped_drunk": (["I love you, mate!", "Ticket me! Go on!", "Where's me car?", "You're me best mate, you!"], ("en-gb+m3", 25, 115, False)),
    "ped_geezer": (["Wanna buy a watch?", "Genuine Rolex, a tenner!", "Fell off the back of a lorry!", "Jobsworth!"], ("en-gb-x-gbclan+m1", 40, 185, False)),
    "ped_stag": (["Wahey!", "Lads lads lads!", "It's my stag do!", "Dance with me, warden!"], ("en-gb-scotland+m4", 55, 180, True)),
}


def extras():
    music = os.path.join(ROOT, "music")
    sfx = os.path.join(ROOT, "sfx")
    voice = os.path.join(ROOT, "voice")
    tracks = {"boss": track_boss, "endless": track_endless, "versus": track_versus,
              "wedding": track_wedding, "matchday": track_matchday, "xmas": track_xmas}
    for name, fn in tracks.items():
        print("music", name)
        write_ogg(os.path.join(music, name + ".ogg"), fn(), quality=4)
    for kind, secs in (("boss", 4.0), ("rankup", 3.8)):
        write_ogg(os.path.join(music, "sting_" + kind + ".ogg"), render_extra_stinger(kind, secs))
    effects = {
        "clamp": sfx_clamp(), "tow": sfx_tow(), "camera": sfx_camera(), "cash": sfx_cash(), "chimes": sfx_chimes(),
        "coo": sfx_coo(), "flap": sfx_flap(), "rattle": sfx_rattle(), "slurp": sfx_slurp(), "splash": sfx_splash(),
        "zap": sfx_zap(), "slap": sfx_slap(),
    }
    for name, data in effects.items():
        write_ogg(os.path.join(sfx, name + ".ogg"), mono_to_stereo(data))
    base = len(HECKLES)
    for i, line in enumerate(MORE_HECKLES):
        for j in range(2):
            v, p, sp = VOICES[(i * 2 + j + 1) % len(VOICES)]
            write_ogg(os.path.join(voice, "heckle_%d_%d.ogg" % (base + i, j)), mono_to_stereo(speak(line, v, p, sp)))
    for key, (line, who) in EXTRA_LINES.items():
        if who == "announcer":
            data = speak(line, "en-gb+m7", 35, 150, False, radio=True)
        else:
            data = speak(line, "en-gb-x-rp+m1", 40, 165, False, radio=True)
        write_ogg(os.path.join(voice, key + ".ogg"), mono_to_stereo(data))
    for group, (lines, vs) in GROUP_LINES.items():
        for j, line in enumerate(lines):
            v, p, sp, shout = vs if vs else VOICES[j % len(VOICES)] + (True,)
            write_ogg(os.path.join(voice, "%s_%d.ogg" % (group, j)), mono_to_stereo(speak(line, v, p, sp, shout)))
    print("extras done")


if __name__ == "__main__":
    import sys
    if "--extras" in sys.argv:
        extras()
    else:
        main()
        extras()
