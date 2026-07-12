#!/usr/bin/env python3
"""Procedural SFX/ambience generator for Hòn Gió.

Generates every WAV the game uses into assets/audio/.
Deterministic (fixed seed), no external audio assets, no copyright issues.

Usage:  python3 tools/generate_audio.py
"""
import math
import os
import wave

import numpy as np

SR = 22050
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "audio")
rng = np.random.default_rng(20260711)


# --- helpers -----------------------------------------------------------------

def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return rng.standard_normal(int(dur * SR))


def band(x, lo, hi):
    """Brick-wall band-pass via FFT (offline, quality > speed)."""
    spec = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1.0 / SR)
    mask = (freqs >= lo) & (freqs <= hi)
    return np.fft.irfft(spec * mask, len(x))


def env_ad(n, attack, decay, curve=3.0):
    """Attack-decay envelope."""
    na = max(int(attack * SR), 1)
    e = np.ones(n)
    e[:na] = np.linspace(0.0, 1.0, na)
    nd = n - na
    if nd > 0:
        e[na:] = np.exp(-curve * np.linspace(0.0, 1.0, nd) * (1.0 / max(decay, 1e-3)))
    return e


def sine(freq, dur, phase=0.0):
    return np.sin(2 * math.pi * freq * t_axis(dur) + phase)


def sweep(f0, f1, dur):
    t = t_axis(dur)
    freqs = np.linspace(f0, f1, len(t))
    return np.sin(2 * math.pi * np.cumsum(freqs) / SR)


def loopify(x, fade=0.3):
    """Crossfade tail into head so the sample loops seamlessly."""
    nf = int(fade * SR)
    n = len(x)
    y = x[: n - nf].copy()
    r = np.linspace(0.0, 1.0, nf)
    y[:nf] = x[:nf] * r + x[n - nf:] * (1.0 - r)
    return y


def write(name, x, gain=0.9):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = x / peak * gain
    data = (x * 32767).astype(np.int16)
    path = os.path.join(OUT_DIR, name + ".wav")
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(data.tobytes())
    print(f"  {name}.wav  ({len(x)/SR:.2f}s, {os.path.getsize(path)//1024} KB)")


# --- footsteps -----------------------------------------------------------------

def gen_steps():
    n = int(0.16 * SR)
    x = band(noise(0.16), 300, 5500) * env_ad(n, 0.004, 0.16)
    x += band(noise(0.16), 80, 300) * env_ad(n, 0.002, 0.06) * 0.8
    write("step_grass", x, 0.55)

    n = int(0.13 * SR)
    x = band(noise(0.13), 120, 2000) * env_ad(n, 0.002, 0.05)
    x += sine(95, 0.13) * env_ad(n, 0.001, 0.04) * 0.5
    write("step_road", x, 0.5)

    n = int(0.22 * SR)
    x = band(noise(0.22), 700, 7500) * env_ad(n, 0.015, 0.22, 2.0)
    write("step_sand", x, 0.45)

    n = int(0.15 * SR)
    x = sine(180, 0.15) * env_ad(n, 0.001, 0.05)
    x += band(noise(0.15), 150, 1200) * env_ad(n, 0.002, 0.05) * 0.7
    write("step_wood", x, 0.55)


# --- water ---------------------------------------------------------------------

def gen_water():
    n = int(0.7 * SR)
    x = band(noise(0.7), 400, 7000) * env_ad(n, 0.01, 0.35, 2.5)
    bubbles = np.zeros(n)
    for _ in range(8):
        p = rng.integers(int(0.05 * SR), int(0.5 * SR))
        f = rng.uniform(300, 900)
        d = 0.08
        seg = sweep(f, f * 0.5, d) * env_ad(int(d * SR), 0.003, 0.06)
        bubbles[p:p + len(seg)] += seg * 0.5
    write("splash", x + bubbles, 0.7)

    n = int(0.5 * SR)
    x = band(noise(0.5), 500, 5000) * env_ad(n, 0.05, 0.3, 2.0)
    write("swim_stroke", x, 0.4)

    n = int(0.25 * SR)
    x = sweep(500, 180, 0.25) * env_ad(n, 0.003, 0.15)
    x += band(noise(0.25), 500, 3000) * env_ad(n, 0.003, 0.08) * 0.4
    write("bobber_plop", x, 0.55)


# --- tools / combat --------------------------------------------------------------

def gen_tools():
    n = int(0.25 * SR)
    x = sine(170, 0.25) * env_ad(n, 0.001, 0.04)
    x += band(noise(0.25), 900, 4500) * env_ad(n, 0.001, 0.05) * 0.9
    write("chop", x, 0.75)

    dur = 1.5
    n = int(dur * SR)
    creak = sweep(140, 55, dur) * env_ad(n, 0.02, 0.9, 1.5)
    creak *= 1.0 + 0.4 * band(noise(dur), 4, 30)
    cracks = np.zeros(n)
    for i in range(7):
        p = int((0.1 + i * 0.12) * SR)
        d = 0.05
        seg = band(noise(d), 800, 5000) * env_ad(int(d * SR), 0.001, 0.02)
        cracks[p:p + len(seg)] += seg * (0.4 + i * 0.1)
    thump_at = int(1.05 * SR)
    thump_n = n - thump_at
    thump = np.zeros(n)
    thump[thump_at:] = sine(60, thump_n / SR) * env_ad(thump_n, 0.002, 0.2)
    thump[thump_at:] += band(noise(thump_n / SR), 100, 700) * env_ad(thump_n, 0.002, 0.15) * 0.8
    write("tree_fall", creak * 0.6 + cracks + thump, 0.85)

    n = int(0.3 * SR)
    x = sine(2400, 0.3) * env_ad(n, 0.001, 0.05) * 0.5
    x += sine(3610, 0.3) * env_ad(n, 0.001, 0.035) * 0.35
    x += sine(130, 0.3) * env_ad(n, 0.001, 0.05) * 0.8
    x += band(noise(0.3), 1500, 6000) * env_ad(n, 0.001, 0.02) * 0.6
    write("pickaxe", x, 0.7)

    dur = 0.8
    n = int(dur * SR)
    x = band(noise(dur), 90, 900) * env_ad(n, 0.005, 0.4, 2.0)
    for _ in range(10):
        p = rng.integers(0, int(0.5 * SR))
        d = 0.04
        seg = band(noise(d), 400, 3000) * env_ad(int(d * SR), 0.001, 0.02)
        x[p:p + len(seg)] += seg * 0.7
    write("rock_break", x, 0.8)

    n = int(0.18 * SR)
    x = sine(85, 0.18) * env_ad(n, 0.001, 0.05)
    x += band(noise(0.18), 250, 1100) * env_ad(n, 0.001, 0.04) * 0.7
    write("punch", x, 0.8)

    n = int(0.3 * SR)
    e = np.sin(np.linspace(0, math.pi, n)) ** 2
    x = band(noise(0.3), 600, 2600) * e
    write("whoosh", x, 0.5)


# --- vehicle ---------------------------------------------------------------------

def gen_vehicle():
    dur = 1.1
    n = int(dur * SR)
    t = t_axis(dur)
    crank_f = 9.0
    crank = np.sign(np.sin(2 * math.pi * crank_f * t)) * band(noise(dur), 60, 400)
    crank *= np.clip(1.4 - t, 0.0, 1.0)
    rev = sweep(40, 85, dur) * np.clip((t - 0.5) * 2.5, 0.0, 1.0)
    write("car_start", crank * 0.7 + rev, 0.75)

    # Seamless 2 s idle loop: all modulators use whole cycles.
    dur = 2.0
    n = int(dur * SR)
    t = t_axis(dur)
    base_f = 55.0
    x = np.zeros(n)
    for h, a in [(1, 1.0), (2, 0.55), (3, 0.35), (4, 0.22), (6, 0.12)]:
        x += a * np.sin(2 * math.pi * base_f * h * t)
    wob = 1.0 + 0.18 * np.sin(2 * math.pi * 4.0 * t) + 0.09 * np.sin(2 * math.pi * 13.0 * t)
    x = x * wob + band(noise(dur), 40, 220) * 0.35
    write("car_engine", loopify(x, 0.15), 0.6)

    n = int(0.8 * SR)
    tone = np.sign(np.sin(2 * math.pi * 405 * t_axis(0.8))) * 0.5
    tone += np.sign(np.sin(2 * math.pi * 512 * t_axis(0.8))) * 0.5
    e = env_ad(n, 0.02, 3.0)
    e[int(0.65 * SR):] *= np.linspace(1.0, 0.0, n - int(0.65 * SR))
    write("car_horn", band(tone, 200, 3000) * e, 0.55)

    n = int(0.3 * SR)
    x = sine(120, 0.3) * env_ad(n, 0.001, 0.05)
    x += band(noise(0.3), 600, 2500) * env_ad(n, 0.001, 0.02) * 0.6
    write("car_door_open", x, 0.6)

    n = int(0.22 * SR)
    x = sine(85, 0.22) * env_ad(n, 0.001, 0.06)
    x += band(noise(0.22), 300, 1800) * env_ad(n, 0.001, 0.03) * 0.8
    write("car_door_close", x, 0.8)

    dur = 0.9
    n = int(dur * SR)
    wob = 1.0 + 0.5 * np.sin(2 * math.pi * 11 * t_axis(dur))
    x = band(noise(dur), 800, 2400) * wob * env_ad(n, 0.05, 0.8, 1.2)
    write("car_skid", x, 0.6)


# --- doors / UI / feedback ---------------------------------------------------------

def gen_ui():
    dur = 0.7
    n = int(dur * SR)
    creak = sweep(280, 460, dur) * (1.0 + 0.5 * band(noise(dur), 6, 40))
    creak *= env_ad(n, 0.05, 0.6, 1.5) * 0.5
    click = np.zeros(n)
    seg = band(noise(0.04), 1200, 5000) * env_ad(int(0.04 * SR), 0.001, 0.015)
    click[:len(seg)] += seg
    write("door_open", creak + click, 0.5)

    n = int(0.35 * SR)
    x = sine(110, 0.35) * env_ad(n, 0.001, 0.07)
    x += band(noise(0.35), 400, 2500) * env_ad(n, 0.001, 0.025) * 0.7
    write("door_close", x, 0.7)

    n = int(0.15 * SR)
    write("pickup", sweep(620, 930, 0.15) * env_ad(n, 0.004, 0.09), 0.5)

    dur = 0.45
    n = int(dur * SR)
    x = np.zeros(n)
    for i, f in enumerate([1900, 2450]):
        p = int(i * 0.09 * SR)
        d = 0.3
        seg = (sine(f, d) + 0.5 * sine(f * 2.01, d)) * env_ad(int(d * SR), 0.001, 0.12)
        x[p:p + len(seg)] += seg
    write("cash", x, 0.45)

    n = int(0.3 * SR)
    buzz = np.sign(np.sin(2 * math.pi * 105 * t_axis(0.3)))
    gate = (np.sin(2 * math.pi * 8 * t_axis(0.3)) > 0).astype(float)
    write("denied", band(buzz * gate, 60, 900) * env_ad(n, 0.005, 0.4), 0.4)

    n = int(0.05 * SR)
    write("click", band(noise(0.05), 1500, 5500) * env_ad(n, 0.001, 0.02), 0.35)

    dur = 0.8
    n = int(dur * SR)
    x = np.zeros(n)
    for i, f in enumerate([523.25, 659.25, 783.99]):
        p = int(i * 0.14 * SR)
        d = 0.5
        seg = (sine(f, d) + 0.4 * sine(f * 2, d)) * env_ad(int(d * SR), 0.005, 0.25)
        x[p:p + len(seg)] += seg
    write("save", x, 0.4)

    n = int(0.2 * SR)
    write("bite", sweep(330, 140, 0.2) * env_ad(n, 0.003, 0.12), 0.55)

    dur = 0.9
    n = int(dur * SR)
    x = np.zeros(n)
    for i, f in enumerate([659.25, 783.99, 1046.5]):
        p = int(i * 0.12 * SR)
        d = 0.55
        seg = (sine(f, d) + 0.35 * sine(f * 2, d)) * env_ad(int(d * SR), 0.004, 0.3)
        x[p:p + len(seg)] += seg
    write("catch_jingle", x, 0.45)

    n = int(0.12 * SR)
    write("npc_talk", sweep(440, 640, 0.12) * env_ad(n, 0.01, 0.1), 0.3)

    n = int(0.4 * SR)
    e = np.sin(np.linspace(0, math.pi, n)) ** 1.5
    write("fishing_cast", band(noise(0.4), 900, 4000) * e, 0.45)

    dur = 0.5
    n = int(dur * SR)
    x = np.zeros(n)
    clicks_per_sec = 22
    for i in range(int(dur * clicks_per_sec)):
        p = int(i / clicks_per_sec * SR)
        d = 0.012
        seg = band(noise(d), 2000, 7000) * env_ad(int(d * SR), 0.0005, 0.01)
        x[p:p + len(seg)] += seg
    write("fishing_reel", loopify(x, 0.05), 0.35)


# --- ambience ----------------------------------------------------------------------

def gen_ambience():
    dur = 8.0
    n = int(dur * SR)
    t = t_axis(dur)
    x = band(noise(dur), 90, 900)
    lfo = 0.6 + 0.25 * np.sin(2 * math.pi * 2 / dur * t) + 0.15 * np.sin(2 * math.pi * 5 / dur * t + 1.3)
    write("ambient_wind", loopify(x * lfo, 0.6), 0.5)

    dur = 10.0
    n = int(dur * SR)
    t = t_axis(dur)
    bed = band(noise(dur), 150, 1200) * 0.35
    swell = np.zeros(n)
    for k in range(2):
        phase = 2 * math.pi * (t / dur * 2 - k * 0.5)
        e = np.clip(np.sin(phase), 0, 1) ** 2
        swell += band(noise(dur), 250, 2600) * e
    foam = band(noise(dur), 2500, 7500) * np.clip(np.sin(2 * math.pi * (t / dur * 2 + 0.12)), 0, 1) ** 3 * 0.6
    write("ambient_waves", loopify(bed + swell + foam, 0.8), 0.55)

    dur = 12.0
    n = int(dur * SR)
    x = band(noise(dur), 2000, 6000) * 0.02
    chirp_times = [0.7, 1.6, 3.1, 4.4, 6.2, 7.5, 9.0, 10.4]
    for i, ct in enumerate(chirp_times):
        f0 = [2600, 3100, 2200, 3500][i % 4]
        nnotes = 2 + i % 3
        for j in range(nnotes):
            p = int((ct + j * 0.13) * SR)
            d = 0.09
            vib = sine(f0 + rng.uniform(-200, 300), d) * (1 + 0.6 * sine(40, d))
            seg = vib * env_ad(int(d * SR), 0.01, 0.05)
            if p + len(seg) < n:
                x[p:p + len(seg)] += seg * 0.5
    write("ambient_birds", loopify(x, 0.4), 0.5)

    dur = 6.0
    n = int(dur * SR)
    t = t_axis(dur)
    carrier = sine(4300, dur) + 0.4 * sine(4700, dur)
    am = (np.sin(2 * math.pi * 24 * t) > 0.2).astype(float)
    bursts = (np.sin(2 * math.pi * 3 / dur * t) > -0.3).astype(float)
    write("ambient_crickets", loopify(carrier * am * bursts * 0.5, 0.3), 0.35)

    dur = 7.0
    n = int(dur * SR)
    x = band(noise(dur), 400, 9000)
    x *= 0.8 + 0.2 * band(noise(dur), 1, 8)
    drops = np.zeros(n)
    for _ in range(60):
        p = rng.integers(0, n - int(0.03 * SR))
        d = 0.02
        seg = band(noise(d), 3000, 9000) * env_ad(int(d * SR), 0.0005, 0.01)
        drops[p:p + len(seg)] += seg * rng.uniform(0.3, 1.0)
    write("ambient_rain", loopify(x * 0.6 + drops, 0.5), 0.5)


def _pad_chord(freqs, dur, brightness=1.0):
    n = int(dur * SR)
    x = np.zeros(n)
    for f in freqs:
        for h, a in [(1, 1.0), (2, 0.35 * brightness), (3, 0.15 * brightness)]:
            x += a * sine(f * h, dur, rng.uniform(0, 6.28)) * rng.uniform(0.8, 1.0)
    e = np.ones(n)
    nf = int(0.9 * SR)
    e[:nf] = np.linspace(0, 1, nf) ** 1.5
    e[-nf:] *= np.linspace(1, 0, nf) ** 1.5
    return x * e / len(freqs)


def gen_music():
    def make_pad(chords, name, brightness):
        parts = []
        for freqs in chords:
            parts.append(_pad_chord(freqs, 4.5, brightness))
        total = int(16.0 * SR)
        x = np.zeros(total)
        for i, p in enumerate(parts):
            start = int(i * 4.0 * SR)
            end = min(start + len(p), total)
            x[start:end] += p[: end - start]
        write(name, loopify(x, 1.0), 0.4)

    c = lambda *fs: list(fs)
    make_pad([
        c(261.63, 329.63, 392.0, 523.25),   # C
        c(220.0, 261.63, 329.63, 440.0),    # Am
        c(174.61, 220.0, 261.63, 349.23),   # F
        c(196.0, 246.94, 293.66, 392.0),    # G
    ], "music_day", 1.0)
    make_pad([
        c(220.0, 261.63, 329.63),           # Am
        c(174.61, 220.0, 261.63),           # F
        c(146.83, 174.61, 220.0),           # Dm
        c(164.81, 207.65, 246.94),          # E
    ], "music_night", 0.5)


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    print("Generating audio ->", os.path.abspath(OUT_DIR))
    gen_steps()
    gen_water()
    gen_tools()
    gen_vehicle()
    gen_ui()
    gen_ambience()
    gen_music()
    print("Done.")
