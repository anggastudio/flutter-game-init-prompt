#!/usr/bin/env python3
"""Generate the game's sound effects as WAV files.

Six short beeps do not justify a sample library or a licensing search. This
script synthesises them from oscillators and an exponential decay envelope,
which is the same thing the Web Audio API does at runtime in a browser game.

Keeping it a script rather than committing opaque binaries means the sounds
stay tweakable: change a frequency here, re-run, and the asset updates. A
committed WAV nobody can regenerate is a sound nobody ever adjusts.

Usage:

    python3 tool/generate_sfx.py

Writes 16-bit mono WAVs into assets/audio/. Standard library only.
"""

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 22050
OUTPUT_DIR = os.path.join("assets", "audio")

# Deterministic noise, so re-running does not produce a subtly different file
# and create a pointless diff.
random.seed(1729)


# ---------------------------------------------------------------------------
# Oscillators. Each takes a phase in [0, 1) and returns a sample in [-1, 1].
# ---------------------------------------------------------------------------


def sine(phase):
    return math.sin(2.0 * math.pi * phase)


def square(phase):
    return 1.0 if phase < 0.5 else -1.0


def triangle(phase):
    return 4.0 * abs(phase - 0.5) - 1.0


def sawtooth(phase):
    return 2.0 * phase - 1.0


WAVES = {
    "sine": sine,
    "square": square,
    "triangle": triangle,
    "saw": sawtooth,
}


def envelope(index, total):
    """Exponential decay with a short attack.

    The attack matters more than it looks. A tone that starts at full
    amplitude clicks, and a click on every tap is what makes cheap game audio
    sound cheap.
    """
    attack = max(1, int(0.005 * SAMPLE_RATE))
    if index < attack:
        return index / attack
    decay_position = (index - attack) / max(1, total - attack)
    return math.exp(-5.0 * decay_position)


# ---------------------------------------------------------------------------
# Layer builders. Each returns a list of float samples.
# ---------------------------------------------------------------------------


def tone(frequency, duration, wave_name="sine", start=0.0, gain=1.0):
    """A single pitched note, optionally delayed by `start` seconds."""
    osc = WAVES[wave_name]
    total = int(duration * SAMPLE_RATE)
    lead = [0.0] * int(start * SAMPLE_RATE)
    body = [
        osc((i * frequency / SAMPLE_RATE) % 1.0) * envelope(i, total) * gain
        for i in range(total)
    ]
    return lead + body


def sweep(start_hz, end_hz, duration, wave_name="sine", start=0.0, gain=1.0):
    """A glide between two pitches. Rising reads as a reward, falling as a loss."""
    osc = WAVES[wave_name]
    total = int(duration * SAMPLE_RATE)
    lead = [0.0] * int(start * SAMPLE_RATE)
    body = []
    phase = 0.0
    for i in range(total):
        frequency = start_hz + (end_hz - start_hz) * (i / total)
        phase = (phase + frequency / SAMPLE_RATE) % 1.0
        body.append(osc(phase) * envelope(i, total) * gain)
    return lead + body


def noise_burst(duration, cutoff_hz, start=0.0, gain=1.0):
    """Filtered white noise. Impacts, whooshes, anything percussive."""
    total = int(duration * SAMPLE_RATE)
    lead = [0.0] * int(start * SAMPLE_RATE)

    # One-pole low pass. Crude, but the difference between "hiss" and "thud".
    alpha = min(1.0, 2.0 * math.pi * cutoff_hz / SAMPLE_RATE)
    body = []
    previous = 0.0
    for i in range(total):
        white = random.uniform(-1.0, 1.0)
        previous += alpha * (white - previous)
        body.append(previous * envelope(i, total) * gain)
    return lead + body


def arpeggio(frequencies, note_duration, wave_name="sine", step=0.06, gain=1.0):
    """A run of notes. Ascending for a win, descending for a game over."""
    layers = [
        tone(freq, note_duration, wave_name, start=index * step, gain=gain)
        for index, freq in enumerate(frequencies)
    ]
    return mix(layers)


def mix(layers):
    """Sums layers of different lengths, then soft-clips the result."""
    length = max(len(layer) for layer in layers)
    out = [0.0] * length
    for layer in layers:
        for i, sample in enumerate(layer):
            out[i] += sample

    peak = max((abs(s) for s in out), default=0.0)
    if peak > 1.0:
        out = [s / peak for s in out]
    return out


def write_wav(name, samples):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    path = os.path.join(OUTPUT_DIR, name)

    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
    )

    with wave.open(path, "w") as handle:
        handle.setnchannels(1)  # Mono. Stereo doubles the size for a stage
        handle.setsampwidth(2)  # nobody perceives through a phone speaker.
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(frames)

    print("wrote {} ({:.1f} KB)".format(path, len(frames) / 1024))


# ---------------------------------------------------------------------------
# The catalogue. Edit frequencies here and re-run to hear the difference.
# ---------------------------------------------------------------------------


def main():
    # A short, bright click. Fires on every tap, so it has to be unobtrusive.
    write_wav("tap.wav", tone(880, 0.06, "sine", gain=0.5))

    # Collecting something. Two notes a fifth apart read as "good".
    write_wav(
        "collect.wav",
        mix([tone(660, 0.10, "sine"), tone(990, 0.12, "sine", start=0.04, gain=0.7)]),
    )

    # Power-up. A rising sweep plus a sparkle on top.
    write_wav(
        "power_up.wav",
        mix(
            [
                sweep(440, 1320, 0.28, "triangle"),
                tone(1760, 0.14, "sine", start=0.18, gain=0.4),
            ]
        ),
    )

    # Losing a life. Falling, and slightly harsh, without being punishing.
    write_wav(
        "life_lost.wav",
        mix([sweep(440, 180, 0.32, "square", gain=0.6), noise_burst(0.12, 900, gain=0.3)]),
    )

    # Game over. A descending minor arpeggio. Resigned, not cruel.
    write_wav("game_over.wav", arpeggio([523, 440, 349, 262], 0.30, "triangle", step=0.13))

    # Winning. The same shape, ascending and major.
    write_wav("win.wav", arpeggio([523, 659, 784, 1047], 0.34, "sine", step=0.10))


if __name__ == "__main__":
    main()
