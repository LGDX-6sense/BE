from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from multimodal_agent import DEFAULT_CHUNK_PATH, DEFAULT_FULL_DOC_PATH, DEFAULT_TOP_K, run_agent
from pipeline import PROJECT_ROOT

try:
    from openai import OpenAI
except ImportError:
    OpenAI = None


DEFAULT_TRANSCRIPTION_MODEL = os.getenv("OPENAI_TRANSCRIPTION_MODEL", "gpt-4o-mini-transcribe")


app = FastAPI(
    title="LG 가전 모바일 API",
    description="모바일 앱에서 쓰기 위한 멀티모달 진단 API 래퍼입니다.",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def parse_history(history_json: str) -> List[Dict[str, str]]:
    """Parse a lightweight chat history payload from the mobile client."""
    if not str(history_json or "").strip():
        return []

    try:
        parsed = json.loads(history_json)
    except json.JSONDecodeError as error:
        raise HTTPException(status_code=400, detail=f"history_json 형식이 올바르지 않습니다: {error}") from error

    if not isinstance(parsed, list):
        raise HTTPException(status_code=400, detail="history_json은 JSON 배열이어야 합니다.")

    history: List[Dict[str, str]] = []
    for item in parsed:
        if not isinstance(item, dict):
            continue
        history.append(
            {
                "user": str(item.get("user", "")).strip(),
                "assistant": str(item.get("assistant", "")).strip(),
            }
        )
    return history


def build_conversation_context(history: List[Dict[str, str]], current_text: str) -> str:
    """Compress recent turns into a prompt-friendly context string."""
    recent_turns = history[-4:]
    lines: List[str] = []
    for turn in recent_turns:
        user_text = turn.get("user", "").strip()
        assistant_text = turn.get("assistant", "").strip()
        if user_text:
            lines.append(f"User: {user_text}")
        if assistant_text:
            lines.append(f"Assistant: {assistant_text}")
    if current_text.strip():
        lines.append(f"Current user message: {current_text.strip()}")
    return "\n".join(lines)


def build_user_message(
    message: str,
    image_filename: Optional[str],
    audio_filename: Optional[str],
    *,
    voice_transcript: str = "",
    voice_filename: Optional[str] = None,
) -> str:
    """Format a readable history entry for the client UI."""
    parts: List[str] = []
    if message.strip():
        parts.append(message.strip())
    if voice_transcript.strip():
        parts.append(f"음성 입력: {voice_transcript.strip()}")
    if image_filename:
        parts.append(f"[이미지 첨부: {image_filename}]")
    if audio_filename:
        parts.append(f"[오디오 첨부: {audio_filename}]")
    if voice_filename:
        parts.append(f"[음성 메시지: {voice_filename}]")
    return "\n".join(parts) if parts else "[입력 없음]"


def merge_user_message_text(message: str, voice_transcript: str) -> str:
    """Combine typed text and spoken transcript into one prompt-friendly message."""
    parts = [message.strip(), voice_transcript.strip()]
    return "\n".join(part for part in parts if part)


async def save_upload(upload: Optional[UploadFile]) -> Optional[Path]:
    """Persist an upload to a temp file so the existing agent can read it from disk."""
    if upload is None or not upload.filename:
        return None

    suffix = Path(upload.filename).suffix or ".bin"
    data = await upload.read()
    if not data:
        return None

    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
        temp_file.write(data)
        return Path(temp_file.name)


def cleanup_temp_files(paths: List[Path]) -> None:
    """Delete temporary upload files after the request finishes."""
    for path in paths:
        try:
            path.unlink(missing_ok=True)
        except OSError:
            continue


def ensure_openai_for_transcription() -> None:
    """Validate that the OpenAI SDK and API key are ready for speech-to-text."""
    if OpenAI is None:
        raise RuntimeError("Missing required package: openai. Install it with `pip install openai`.")
    if not os.getenv("OPENAI_API_KEY"):
        raise RuntimeError("OPENAI_API_KEY is not set.")


def extract_transcript_text(transcript: Any) -> str:
    """Normalize SDK transcription output into a plain string."""
    if isinstance(transcript, str):
        return transcript.strip()

    text = getattr(transcript, "text", None)
    if isinstance(text, str):
        return text.strip()

    if isinstance(transcript, dict):
        value = transcript.get("text")
        if isinstance(value, str):
            return value.strip()

    return ""


def transcribe_voice_message(audio_path: Path) -> str:
    """Turn a recorded speech message into Korean text via OpenAI STT."""
    ensure_openai_for_transcription()
    client = OpenAI()

    with audio_path.open("rb") as audio_file:
        transcript = client.audio.transcriptions.create(
            file=audio_file,
            model=DEFAULT_TRANSCRIPTION_MODEL,
            language="ko",
            prompt="The speaker is a Korean customer describing an appliance issue.",
            response_format="text",
        )

    transcript_text = extract_transcript_text(transcript)
    if transcript_text:
        return transcript_text

    raise RuntimeError("The speech transcription response was empty.")


@app.get("/health")
def health() -> Dict[str, Any]:
    """Basic readiness check for emulators, simulators, and local devices."""
    chunk_path = Path(DEFAULT_CHUNK_PATH)
    full_doc_path = Path(DEFAULT_FULL_DOC_PATH)
    return {
        "status": "ok",
        "project_root": str(PROJECT_ROOT),
        "chunk_path": str(chunk_path),
        "chunk_available": chunk_path.exists(),
        "full_doc_path": str(full_doc_path),
        "full_doc_available": full_doc_path.exists(),
        "openai_api_key_configured": bool(os.getenv("OPENAI_API_KEY")),
    }


@app.post("/api/chat")
async def chat(
    message: str = Form(""),
    history_json: str = Form("[]"),
    top_k: int = Form(DEFAULT_TOP_K),
    image: Optional[UploadFile] = File(default=None),
    audio: Optional[UploadFile] = File(default=None),
    voice_audio: Optional[UploadFile] = File(default=None),
) -> Dict[str, Any]:
    """Run a mobile chat turn with optional image and audio attachments."""
    history = parse_history(history_json)
    temp_paths: List[Path] = []

    if not message.strip() and image is None and audio is None and voice_audio is None:
        raise HTTPException(status_code=400, detail="메시지, 이미지, 오디오, 음성 중 하나 이상을 보내 주세요.")

    try:
        image_path = await save_upload(image)
        audio_path = await save_upload(audio)
        voice_audio_path = await save_upload(voice_audio)

        if image_path is not None:
            temp_paths.append(image_path)
        if audio_path is not None:
            temp_paths.append(audio_path)
        if voice_audio_path is not None:
            temp_paths.append(voice_audio_path)

        voice_transcript = ""
        if voice_audio_path is not None:
            try:
                voice_transcript = transcribe_voice_message(voice_audio_path)
            except Exception as error:
                raise HTTPException(status_code=502, detail=f"음성 전사에 실패했습니다: {error}") from error

        effective_message = merge_user_message_text(message, voice_transcript)
        if not effective_message.strip() and image is None and audio is None:
            raise HTTPException(status_code=400, detail="음성 전사 결과가 비어 있습니다. 다시 말씀해 주세요.")

        conversation_text = build_conversation_context(history, effective_message)
        result = run_agent(
            user_text=conversation_text,
            image_path=str(image_path) if image_path else None,
            audio_path=str(audio_path) if audio_path else None,
            top_k=top_k,
        )

        user_message = build_user_message(
            message=message,
            image_filename=image.filename if image else None,
            audio_filename=audio.filename if audio else None,
            voice_transcript=voice_transcript,
            voice_filename=voice_audio.filename if voice_audio else None,
        )
        updated_history = history + [{"user": user_message, "assistant": result["response"]}]

        return {
            "assistant_message": result["response"],
            "evidence": result.get("evidence", {}),
            "history": updated_history,
            "voice_transcript": voice_transcript,
        }
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error
    finally:
        cleanup_temp_files(temp_paths)


def main() -> None:
    """CLI entrypoint for local mobile testing."""
    parser = argparse.ArgumentParser(description="Run the FastAPI server for the mobile Flutter client.")
    parser.add_argument("--host", default="0.0.0.0", help="Host for the FastAPI server")
    parser.add_argument("--port", type=int, default=8000, help="Port for the FastAPI server")
    args = parser.parse_args()

    import uvicorn

    uvicorn.run(app, host=args.host, port=args.port)


if __name__ == "__main__":
    main()
