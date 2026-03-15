"""
Yanke backend — FastAPI server.
Run: uvicorn main:app --reload
"""

import os
import tempfile
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from processor import process_audio

app = FastAPI(title="Yanke API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

SUPPORTED_EXTENSIONS = {".mp3", ".wav", ".m4a", ".aac", ".flac"}


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/process")
async def process(file: UploadFile = File(...)):
    """
    Accept an audio file, run the full Demucs → CREPE → quantizer pipeline,
    and return a JSON array of note objects.
    """
    ext = Path(file.filename or "").suffix.lower()
    if ext not in SUPPORTED_EXTENSIONS:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported format '{ext}'. Use: {', '.join(SUPPORTED_EXTENSIONS)}",
        )

    # Write upload to a temp file (demucs needs a real path)
    with tempfile.NamedTemporaryFile(suffix=ext, delete=False) as tmp:
        tmp.write(await file.read())
        tmp_path = tmp.name

    try:
        notes = process_audio(tmp_path)
        return notes
    except FileNotFoundError as e:
        raise HTTPException(status_code=500, detail=f"Demucs output missing: {e}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        os.unlink(tmp_path)
