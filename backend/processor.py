"""
Yanke audio processor: Demucs vocal separation → CREPE pitch tracking → note quantizer.
"""

import subprocess
import tempfile
import os
import numpy as np
from pathlib import Path

import crepe
import soundfile as sf
import librosa


# ── Helpers ──────────────────────────────────────────────────────────────────

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

def midi_to_note_name(midi: int) -> str:
    octave = (midi // 12) - 1
    return f"{NOTE_NAMES[midi % 12]}{octave}"

def freq_to_midi(freq: float) -> int | None:
    """Convert Hz to MIDI note number (piano range 21–108). Returns None if out of range."""
    if freq <= 0:
        return None
    midi = round(12 * np.log2(freq / 440.0) + 69)
    return midi if 21 <= midi <= 108 else None


# ── Stage 1: Vocal separation ─────────────────────────────────────────────────

def separate_vocals(input_path: str, work_dir: str) -> str:
    """
    Run Demucs htdemucs_2stems to extract vocals.
    Returns path to vocals.wav.
    """
    print("[1/3] Separating vocals with Demucs (this takes 1–3 min on CPU)...")
    subprocess.run(
        [
            "python", "-m", "demucs",
            "--two-stems", "vocals",
            "--out", work_dir,
            input_path,
        ],
        check=True,
    )

    # Demucs writes to: <work_dir>/<model_name>/<song_stem>/vocals.wav
    for vocals_path in Path(work_dir).rglob("vocals.wav"):
        print(f"  → vocals: {vocals_path}")
        return str(vocals_path)

    raise FileNotFoundError(f"Demucs output vocals.wav not found in {work_dir}")


# ── Stage 2: Pitch tracking ───────────────────────────────────────────────────

def track_pitch(vocals_path: str):
    """
    Run CREPE tiny on the vocal stem.
    Returns (time_array, frequency_array, confidence_array).
    """
    print("[2/3] Tracking pitch with CREPE tiny...")

    audio, sr = sf.read(vocals_path)
    if audio.ndim == 2:
        audio = audio.mean(axis=1)          # stereo → mono

    # CREPE was trained at 16 kHz
    if sr != 16000:
        audio = librosa.resample(audio, orig_sr=sr, target_sr=16000)
        sr = 16000

    audio = audio.astype(np.float32)

    time, frequency, confidence, _ = crepe.predict(
        audio, sr,
        model="tiny",
        viterbi=True,     # smoother pitch contour
        step_size=10,     # 10 ms frames
    )
    return time, frequency, confidence


# ── Stage 3: Quantize to note events ─────────────────────────────────────────

def quantize_to_notes(
    time: np.ndarray,
    frequency: np.ndarray,
    confidence: np.ndarray,
    conf_threshold: float = 0.5,
    min_duration: float = 0.08,   # seconds — drop notes shorter than 80 ms
) -> list[dict]:
    """
    Convert f0 contour to discrete note events.
    Groups consecutive frames with the same MIDI pitch into a single note.
    """
    print("[3/3] Quantizing pitch contour to notes...")

    notes = []
    current_midi: int | None = None
    current_start: float | None = None

    for t, f, c in zip(time, frequency, confidence):
        midi = freq_to_midi(f) if c >= conf_threshold else None

        if midi != current_midi:
            # Close current note
            if current_midi is not None and current_start is not None:
                duration = float(t) - current_start
                if duration >= min_duration:
                    notes.append({
                        "midiPitch": int(current_midi),
                        "startTime": round(current_start, 3),
                        "duration":  round(duration, 3),
                        "noteName":  midi_to_note_name(current_midi),
                    })
            # Open new note
            current_midi = midi
            current_start = float(t) if midi is not None else None

    # Close final note
    if current_midi is not None and current_start is not None:
        duration = float(time[-1]) - current_start
        if duration >= min_duration:
            notes.append({
                "midiPitch": int(current_midi),
                "startTime": round(current_start, 3),
                "duration":  round(duration, 3),
                "noteName":  midi_to_note_name(current_midi),
            })

    print(f"  → {len(notes)} notes detected")
    return notes


# ── Main entry point ──────────────────────────────────────────────────────────

def process_audio(input_path: str) -> list[dict]:
    """Full pipeline: audio file → list of note dicts."""
    with tempfile.TemporaryDirectory() as work_dir:
        vocals_path = separate_vocals(input_path, work_dir)
        time, frequency, confidence = track_pitch(vocals_path)
        notes = quantize_to_notes(time, frequency, confidence)
    return notes
