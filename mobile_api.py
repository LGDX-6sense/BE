from __future__ import annotations

import argparse
import json
import math
import os
import tempfile
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware

from multimodal_agent import (
    DEFAULT_CHUNK_PATH,
    DEFAULT_FULL_DOC_PATH,
    DEFAULT_TOP_K,
    normalize_whitespace,
    run_agent,
)
from pipeline import PROJECT_ROOT

try:
    from openai import OpenAI
except ImportError:
    OpenAI = None


DEFAULT_TRANSCRIPTION_MODEL = os.getenv(
    "OPENAI_TRANSCRIPTION_MODEL",
    "gpt-4o-mini-transcribe",
)
DEFAULT_INTENT_EMBEDDING_MODEL = os.getenv(
    "OPENAI_INTENT_EMBEDDING_MODEL",
    "text-embedding-3-small",
)

INTENT_EXAMPLES: Dict[str, List[str]] = {
    "normal_chat": [
        "냉장고가 시원하지 않아요",
        "세탁기에서 물이 새요",
        "에어컨 바람이 약해요",
        "제품 사진을 보고 문제를 진단해줘",
        "이 소리가 어떤 고장인지 알려줘",
        "자가 해결 방법을 알려줘",
        "현재 증상이 왜 생기는지 쉽게 설명해줘",
    ],
    "connect_agent": [
        "상담하고 싶어요",
        "상담사 연결해 주세요",
        "상담원과 이야기하고 싶어요",
        "고객센터 연결해줘",
        "전화 상담 받고 싶어요",
        "사람 상담원과 통화하고 싶어요",
        "직원 연결을 원해요",
    ],
    "book_visit": [
        "출장 서비스 예약하고 싶어요",
        "기사 방문 예약해 주세요",
        "수리 기사님 보내주세요",
        "방문 점검 접수하고 싶어요",
        "출장 수리를 신청할게요",
        "엔지니어 방문을 예약하고 싶어요",
        "집으로 기사님 불러주세요",
    ],
}

INTENT_KEYWORD_HINTS: Dict[str, List[str]] = {
    "connect_agent": [
        "상담",
        "상담원",
        "고객센터",
        "전화",
        "통화",
        "사람이랑",
        "직원",
        "연결",
    ],
    "book_visit": [
        "출장",
        "방문",
        "기사",
        "기사님",
        "수리 예약",
        "방문 예약",
        "출장 예약",
        "출장 서비스",
        "접수",
    ],
}


app = FastAPI(
    title="LG 가전 모바일 API",
    description="모바일 앱에서 쓰는 멀티모달 진단 API입니다.",
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
        raise HTTPException(
            status_code=400,
            detail=f"history_json 형식이 올바르지 않습니다: {error}",
        ) from error

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


def ensure_openai_client() -> None:
    """Validate that the OpenAI SDK and API key are available."""
    if OpenAI is None:
        raise RuntimeError("Missing required package: openai. Install it with `pip install openai`.")
    if not os.getenv("OPENAI_API_KEY"):
        raise RuntimeError("OPENAI_API_KEY is not set.")


def cosine_similarity(left: List[float], right: List[float]) -> float:
    """Compute cosine similarity for two embedding vectors."""
    if not left or not right or len(left) != len(right):
        return 0.0

    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    if left_norm == 0 or right_norm == 0:
        return 0.0

    dot_product = sum(left_value * right_value for left_value, right_value in zip(left, right))
    return dot_product / (left_norm * right_norm)


def average_vectors(vectors: List[List[float]]) -> List[float]:
    """Average a list of embeddings into a single centroid."""
    if not vectors:
        return []

    width = len(vectors[0])
    if width == 0:
        return []

    totals = [0.0] * width
    valid_count = 0
    for vector in vectors:
        if len(vector) != width:
            continue
        valid_count += 1
        for index, value in enumerate(vector):
            totals[index] += value

    if valid_count == 0:
        return []
    return [value / valid_count for value in totals]


@lru_cache(maxsize=1)
def load_intent_centroids(
    model_name: str = DEFAULT_INTENT_EMBEDDING_MODEL,
) -> Dict[str, List[float]]:
    """Embed intent example sentences once and cache their centroids."""
    ensure_openai_client()
    client = OpenAI()

    example_texts: List[str] = []
    labels: List[str] = []
    for label, samples in INTENT_EXAMPLES.items():
        for sample in samples:
            labels.append(label)
            example_texts.append(sample)

    response = client.embeddings.create(model=model_name, input=example_texts)
    grouped_vectors: Dict[str, List[List[float]]] = {label: [] for label in INTENT_EXAMPLES}
    for label, data in zip(labels, response.data):
        grouped_vectors[label].append(list(data.embedding))

    return {
        label: average_vectors(vectors)
        for label, vectors in grouped_vectors.items()
        if vectors
    }


def classify_service_intent(message: str) -> Dict[str, Any]:
    """Classify whether the user is asking for human support or a visit."""
    normalized_message = normalize_whitespace(message).lower()
    base_result: Dict[str, Any] = {
        "intent": "normal_chat",
        "routing_required": False,
        "action_hint": None,
        "confidence": 0.0,
        "matched_by": "none",
    }

    if not normalized_message:
        return base_result

    keyword_scores = {
        "normal_chat": 0.0,
        "connect_agent": 0.0,
        "book_visit": 0.0,
    }
    for label, keywords in INTENT_KEYWORD_HINTS.items():
        for keyword in keywords:
            if keyword in normalized_message:
                keyword_scores[label] += 0.12 if " " in keyword else 0.08

    vector_scores = {
        "normal_chat": 0.0,
        "connect_agent": 0.0,
        "book_visit": 0.0,
    }
    used_vector = False
    try:
        centroids = load_intent_centroids()
        client = OpenAI()
        response = client.embeddings.create(
            model=DEFAULT_INTENT_EMBEDDING_MODEL,
            input=[normalized_message],
        )
        input_vector = list(response.data[0].embedding)
        for label, centroid in centroids.items():
            vector_scores[label] = cosine_similarity(input_vector, centroid)
        used_vector = True
    except Exception:
        used_vector = False

    combined_scores = {
        label: vector_scores.get(label, 0.0) + keyword_scores.get(label, 0.0)
        for label in ("normal_chat", "connect_agent", "book_visit")
    }
    service_labels = ("connect_agent", "book_visit")
    best_service_label = max(service_labels, key=lambda label: combined_scores[label])
    best_service_score = combined_scores[best_service_label]
    normal_score = combined_scores["normal_chat"]
    keyword_hit_strength = max(keyword_scores[label] for label in service_labels)

    routing_required = False
    matched_by = "none"
    if keyword_hit_strength >= 0.16:
        routing_required = True
        matched_by = "keyword"
    elif best_service_score >= 0.34 and best_service_score > normal_score + 0.01:
        routing_required = True
        matched_by = "vector" if used_vector else "keyword"

    if not routing_required:
        return {
            **base_result,
            "confidence": round(min(1.0, max(normal_score, 0.0)), 3),
            "matched_by": "vector" if used_vector else "none",
        }

    return {
        "intent": best_service_label,
        "routing_required": True,
        "action_hint": best_service_label,
        "confidence": round(min(1.0, max(best_service_score, 0.0)), 3),
        "matched_by": matched_by,
    }


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
    ensure_openai_client()
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
    user_name: str = Form(""),
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
        raise HTTPException(
            status_code=400,
            detail="메시지, 이미지, 오디오, 음성 중 하나 이상을 보내 주세요.",
        )

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
        voice_transcription_warning = ""
        if voice_audio_path is not None:
            try:
                voice_transcript = transcribe_voice_message(voice_audio_path)
            except Exception as error:
                voice_transcription_warning = f"음성 전사에 실패했습니다: {error}"

        effective_message = merge_user_message_text(message, voice_transcript)
        if not effective_message.strip() and image is None and audio is None:
            raise HTTPException(
                status_code=400,
                detail="음성 전사 결과가 비어 있습니다. 다시 말해 주세요.",
            )

        user_message = build_user_message(
            message=message,
            image_filename=image.filename if image else None,
            audio_filename=audio.filename if audio else None,
            voice_transcript=voice_transcript,
            voice_filename=voice_audio.filename if voice_audio else None,
        )
        intent_result = classify_service_intent(effective_message)
        if intent_result["routing_required"]:
            updated_history = history + [{"user": user_message, "assistant": ""}]
            return {
                "assistant_message": "",
                "evidence": {},
                "history": updated_history,
                "voice_transcript": voice_transcript,
                "voice_transcription_warning": voice_transcription_warning,
                "routing_required": True,
                "routing_intent": intent_result["intent"],
                "routing_action_hint": intent_result["action_hint"],
                "routing_confidence": intent_result["confidence"],
                "routing_matched_by": intent_result["matched_by"],
            }

        conversation_text = build_conversation_context(history, effective_message)
        result = run_agent(
            user_text=conversation_text,
            image_path=str(image_path) if image_path else None,
            audio_path=str(audio_path) if audio_path else None,
            top_k=top_k,
            user_name=user_name,
        )
        updated_history = history + [{"user": user_message, "assistant": result["response"]}]

        return {
            "assistant_message": result["response"],
            "evidence": result.get("evidence", {}),
            "history": updated_history,
            "voice_transcript": voice_transcript,
            "voice_transcription_warning": voice_transcription_warning,
            "routing_required": False,
            "routing_intent": "normal_chat",
            "routing_action_hint": None,
            "routing_confidence": intent_result["confidence"],
            "routing_matched_by": intent_result["matched_by"],
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
