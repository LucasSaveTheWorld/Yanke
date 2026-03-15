"""
Yanke audio processor:
  1. Demucs Python API — vocal stem separation (bypasses torchaudio.load)
  2. pyin              — probabilistic YIN pitch tracker (librosa)
  3. Quantizer         — f0 contour → discrete note events
"""

import numpy as np
from pathlib import Path

import soundfile as sf
import librosa
import torch
from demucs.pretrained import get_model
from demucs.apply import apply_model


# ── Constants ─────────────────────────────────────────────────────────────────

NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
PYIN_SR    = 22050
HOP_LENGTH = 256


# ── Helpers ───────────────────────────────────────────────────────────────────

def midi_to_note_name(midi: int) -> str:
    return f"{NOTE_NAMES[midi % 12]}{(midi // 12) - 1}"


def freq_to_midi(freq: float) -> int | None:
    if not np.isfinite(freq) or freq <= 0:
        return None
    midi = round(12 * np.log2(freq / 440.0) + 69)
    return midi if 21 <= midi <= 108 else None


def load_audio(path: str) -> tuple[np.ndarray, int]:
    """
    Load audio via soundfile (handles WAV/FLAC/AIFF natively).
    Falls back to librosa/audioread for MP3/M4A.
    Returns (audio_float32, sample_rate). Audio is always 2D: (channels, samples).
    """
    try:
        audio, sr = sf.read(path, always_2d=True)   # (samples, channels)
        audio = audio.T.astype(np.float32)           # → (channels, samples)
    except Exception:
        # Fallback for M4A/MP3 via audioread
        audio, sr = librosa.load(path, sr=None, mono=False)
        if audio.ndim == 1:
            audio = audio[np.newaxis, :]
        audio = audio.astype(np.float32)
    return audio, sr


# ── Stage 1: Vocal separation ─────────────────────────────────────────────────

_model_cache = None

def get_demucs_model():
    global _model_cache
    if _model_cache is None:
        print("  → Loading htdemucs model (first run: downloads ~130 MB)…")
        _model_cache = get_model("htdemucs")
        _model_cache.eval()
    return _model_cache


def separate_vocals(input_path: str) -> tuple[np.ndarray, int]:
    """
    Use Demucs Python API to extract the vocal stem.
    Loads audio via soundfile — bypasses torchaudio.load entirely.
    Returns (vocals_mono_float32, sample_rate).
    """
    print("[1/3] Separating vocals with Demucs…")
    model = get_demucs_model()
    model_sr = model.samplerate  # 44100 for htdemucs

    audio, sr = load_audio(input_path)

    # Resample to model's expected rate
    if sr != model_sr:
        audio = np.stack([
            librosa.resample(ch, orig_sr=sr, target_sr=model_sr)
            for ch in audio
        ])

    # Ensure stereo (model expects 2 channels)
    if audio.shape[0] == 1:
        audio = np.vstack([audio, audio])
    elif audio.shape[0] > 2:
        audio = audio[:2]

    wav = torch.from_numpy(audio).unsqueeze(0)  # (1, 2, samples)

    with torch.no_grad():
        sources = apply_model(model, wav, device="cpu", progress=True)
    # sources shape: (1, n_sources, 2, samples)
    # htdemucs source order: drums=0, bass=1, other=2, vocals=3
    vocals_idx = model.sources.index("vocals")
    vocals = sources[0, vocals_idx]              # (2, samples)
    vocals_mono = vocals.mean(dim=0).numpy()     # (samples,)

    print(f"  → Vocals extracted ({len(vocals_mono)/model_sr:.1f}s)")
    return vocals_mono, model_sr


# ── Stage 2: Pitch tracking ───────────────────────────────────────────────────

def track_pitch(vocals_mono: np.ndarray, sr: int):
    """pyin on the vocal stem → (times, f0s, voiced_flags)."""
    print("[2/3] Tracking pitch with pyin…")

    if sr != PYIN_SR:
        vocals_mono = librosa.resample(vocals_mono, orig_sr=sr, target_sr=PYIN_SR)

    f0, voiced_flag, _ = librosa.pyin(
        vocals_mono.astype(np.float32),
        fmin=librosa.note_to_hz("C2"),
        fmax=librosa.note_to_hz("C7"),
        sr=PYIN_SR,
        hop_length=HOP_LENGTH,
    )
    times = librosa.times_like(f0, sr=PYIN_SR, hop_length=HOP_LENGTH)
    return times, f0, voiced_flag


# ── Stage 3: Quantise to note events ─────────────────────────────────────────

def quantize_to_notes(
    times: np.ndarray,
    f0s: np.ndarray,
    voiced: np.ndarray,
    min_duration: float = 0.08,
) -> list[dict]:
    print("[3/3] Quantising pitch contour to notes…")
    notes: list[dict] = []
    current_midi: int | None = None
    current_start: float | None = None

    for t, f, v in zip(times, f0s, voiced):
        midi = freq_to_midi(f) if v else None
        if midi != current_midi:
            if current_midi is not None and current_start is not None:
                dur = float(t) - current_start
                if dur >= min_duration:
                    notes.append({
                        "midiPitch": int(current_midi),
                        "startTime": round(current_start, 3),
                        "duration":  round(dur, 3),
                        "noteName":  midi_to_note_name(current_midi),
                    })
            current_midi = midi
            current_start = float(t) if midi is not None else None

    if current_midi is not None and current_start is not None:
        dur = float(times[-1]) - current_start
        if dur >= min_duration:
            notes.append({
                "midiPitch": int(current_midi),
                "startTime": round(current_start, 3),
                "duration":  round(dur, 3),
                "noteName":  midi_to_note_name(current_midi),
            })

    print(f"  → {len(notes)} notes detected")
    return notes


# ── Entry point ───────────────────────────────────────────────────────────────

def process_audio(input_path: str) -> list[dict]:
    vocals_mono, sr = separate_vocals(input_path)
    times, f0s, voiced = track_pitch(vocals_mono, sr)
    return quantize_to_notes(times, f0s, voiced)
