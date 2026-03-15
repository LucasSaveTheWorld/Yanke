# Yanke (燕歌) — Project Context

## What is Yanke
iOS app that extracts the main melody (主旋律) from Chinese songs by isolating the vocal stem and transcribing pitch to a piano roll, so the user can learn to play it on piano.

## Architecture (MVP)
- **iOS app**: SwiftUI, Swift 6, iOS 18+ — imports audio file, POSTs to local Python backend, displays piano roll
- **Python backend**: FastAPI on `localhost:8000` — Demucs (vocal stem separation) → CREPE tiny (pitch tracking) → note quantizer

## Processing Pipeline
```
Song (MP3/M4A) → [Demucs] vocal stem → [CREPE tiny] f0 contour → [Quantizer] notes JSON → Piano Roll UI
```

## Tech Stack
- **Language**: Swift 6.0
- **UI**: SwiftUI
- **Platform**: iOS 18+ / iPhone only
- **Xcode**: 26.3
- **Project generation**: XcodeGen (`project.yml`)
- **Backend**: Python 3.11 + FastAPI + Demucs + CREPE (local dev server)

## Project Structure
```
Yanke/
├── backend/           → Python FastAPI server
│   ├── main.py        → FastAPI routes
│   ├── processor.py   → Demucs + CREPE + quantizer pipeline
│   └── requirements.txt
├── Yanke/             → iOS source
│   ├── App/           → YankeApp.swift (entry point)
│   ├── Views/         → ContentView, ProcessingView, PianoRollView
│   ├── Models/        → Note.swift
│   └── Services/      → APIService.swift
├── project.yml        → XcodeGen spec (source of truth)
└── CLAUDE.md          → this file
```

## Development Workflow

### Start backend (required before running iOS app)
```bash
cd ~/Developer/Yanke/backend
source venv/bin/activate
uvicorn main:app --reload
```

### Regenerate Xcode project
```bash
cd ~/Developer/Yanke && xcodegen generate
```

### First-time backend setup
```bash
cd ~/Developer/Yanke/backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```
Note: First `uvicorn` run downloads htdemucs model (~130 MB) and CREPE tiny (~6 MB) automatically.

## Key Decisions
- **MVP uses local Python server** (not Core ML) to validate pipeline accuracy before investing in model conversion
- **Simulator-first**: AVAudioFile-based file processing works in simulator; mic input is a later concern
- **Swift 6 concurrency**: async/await throughout, no legacy GCD
- **XcodeGen**: never manually edit `.xcodeproj` — always `xcodegen generate`

## Next Steps (post-MVP)
- [ ] Convert Demucs + CREPE tiny to Core ML for fully on-device processing
- [ ] Add sheet music notation view (treble clef) in addition to piano roll
- [ ] BPM detection for better rhythm quantization
- [ ] Export to MIDI / MusicXML
