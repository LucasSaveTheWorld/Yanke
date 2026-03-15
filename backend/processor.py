"""
Yanke audio processor:
  1. Demucs  — separate vocal stem from full mix
  2. pyin    — probabilistic YIN pitch tracker (librosa, no separate model needed)
  3. Quantizer — f0 contour → discrete note events
"""

import subprocess
import tempfile
import os
import numpy as np
from pathlib import Path

import soundfile as sf
import librosa


# ── Constants ─────────────────────────────────────────────────────────────────

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
TARGET_SR = 22050   # pyin works well at 22 kHz
HOP_LENGTH = 256    # ~11.6 ms per frame at 22050 Hz


# ── Helpers ───────────────────────────────────────────────────────────────────

def midi_to_note_name(midi: int) -> str:
    octave = (midi // 12) - 1
    return f"{NOTE_NAMES[midi % 12]}{octave}"


def freq_to_midi(freq: float) -> int | None:
    """Hz → MIDI (piano range 21–108). Returns None if invalid."""
    if not np.isfinite(freq) or freq <= 0:
        return None
    midi = round(12 * np.log2(freq / 440.0) + 69)
    return midi if 21 <= midi <= 108 else None


# ── Stage 1: Vocal separation ─────────────────────────────────────────────────

def separate_vocals(input_path: str, work_dir: str) -> str:
    """
    Run Demucs (htdemucs, two-stems mode) to extract the vocal track.
    Returns the path to vocals.wav.
    """
    print("[1/3] Separating vocals with Demucs (1–3 min on CPU)…")
    subprocess.run(
        [
            "python", "-m", "demucs",
            "--two-stems", "vocals",
            "--out", work_dir,
            input_path,
        ],
        check=True,
    )

    for p in Path(work_dir).rglob("vocals.wav"):
        print(f"  → vocals: {p}")
        return str(p)

    raise FileNotFoundError(f"Demucs did not produce vocals.wav in {work_dir}")


# ── Stage 2: Pitch tracking ───────────────────────────────────────────────────

def track_pitch(vocals_path: str):
    """
    Use librosa.pyin (probabilistic YIN) to track fundamental frequency.
    Returns (times, f0s, voiced_flags).
    """
    print("[2/3] Tracking pitch with pyin…")

    audio, sr = sf.read(vocals_path)
    if audio.ndim == 2:
        audio = audio.mean(axis=1)              # stereo → mono

    if sr != TARGET_SR:
        audio = librosa.resample(audio, orig_sr=sr, target_sr=TARGET_SR)

    audio = audio.astype(np.float32)

    # fmin/fmax cover the typical female/male vocal range
    f0, voiced_flag, _ = librosa.pyin(
        audio,
        fmin=librosa.note_to_hz("C2"),   # ~65 Hz
        fmax=librosa.note_to_hz("C7"),   # ~2093 Hz
        sr=TARGET_SR,
        hop_length=HOP_LENGTH,
    )

    times = librosa.times_like(f0, sr=TARGET_SR, hop_length=HOP_LENGTH)
    return times, f0, voiced_flag


# ── Stage 3: Quantise to note events ─────────────────────────────────────────

def quantize_to_notes(
    times: np.ndarray,
    f0s: np.ndarray,
    voiced: np.ndarray,
    min_duration: float = 0.08,
) -> list[dict]:
    """
    Group consecutive frames with the same MIDI pitch into note events.
    Unvoiced frames (voiced=False) are treated as silence.
    """
    print("[3/3] Quantising pitch contour to notes…")

    notes: list[dict] = []
    current_midi: int | None = None
    current_start: float | None = None

    for t, f, v in zip(times, f0s, voiced):
        midi = freq_to_midi(f) if v else None

        if midi != current_midi:
            # Close the current note
            if current_midi is not None and current_start is not None:
                duration = float(t) - current_start
                if duration >= min_duration:
                    notes.append({
                        "midiPitch": int(current_midi),
                        "startTime": round(current_start, 3),
                        "duration":  round(duration, 3),
                        "noteName":  midi_to_note_name(current_midi),
                    })
            current_midi = midi
            current_start = float(t) if midi is not None else None

    # Close any trailing note
    if current_midi is not None and current_start is not None:
        duration = float(times[-1]) - current_start
        if duration >= min_duration:
            notes.append({
                "midiPitch": int(current_midi),
                "startTime": round(current_start, 3),
                "duration":  round(duration, 3),
                "noteName":  midi_to_note_name(current_midi),
            })

    print(f"  → {len(notes)} notes detected")
    return notes


# ── Entry point ───────────────────────────────────────────────────────────────

def process_audio(input_path: str) -> list[dict]:
    """Full pipeline: audio file path → list of note dicts."""
    with tempfile.TemporaryDirectory() as work_dir:
        vocals_path = separate_vocals(input_path, work_dir)
        times, f0s, voiced = track_pitch(vocals_path)
        notes = quantize_to_notes(times, f0s, voiced)
    return notes
