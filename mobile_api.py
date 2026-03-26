from __future__ import annotations

import argparse
import asyncio
import json
import math
import os
import tempfile
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional

# .env / openaiapi.env 자동 로드
try:
    from dotenv import load_dotenv
    _env_path = Path(__file__).parent / "openaiapi.env"
    if _env_path.exists():
        load_dotenv(dotenv_path=_env_path, override=False)
    else:
        load_dotenv(override=False)
except ImportError:
    pass

from fastapi import FastAPI, File, Form, HTTPException, Query, UploadFile
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse

from chat_archive_store import (
    ChatSession,
    _clean_assistant_text,
    _extract_error_code,
    _infer_device_label,
    list_messages,
    list_sessions,
    save_chat_exchange,
    serialize_message,
    serialize_session,
)
from db import create_tables_if_needed, get_database_status, get_session_factory
from user_store import UserProfile, get_user_context_string, get_user_profile, serialize_user
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
    "as_request": [
        "AS 신청하고 싶어요",
        "AS 받고 싶어요",
        "A/S 신청해주세요",
        "서비스 신청할게요",
        "수리 신청하고 싶어요",
        "고장 수리 맡기고 싶어요",
        "제품 고쳐주세요",
        "수리 받고 싶어요",
        "AS 어떻게 해요",
        "서비스 접수하고 싶어요",
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
    "as_request": [
        "as",
        "a/s",
        "as신청",
        "a/s신청",
        "as 신청",
        "a/s 신청",
        "서비스신청",
        "서비스 신청",
        "수리신청",
        "수리 신청",
        "수리 접수",
        "as접수",
        "as 접수",
    ],
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

import logging as _logging
_logger = _logging.getLogger(__name__)

SUPPORTED_TTS_VOICES = {
    "alloy",
    "echo",
    "fable",
    "onyx",
    "nova",
    "shimmer",
    "coral",
    "verse",
    "ballad",
    "ash",
    "sage",
    "marin",
    "cedar",
}
FALLBACK_TTS_VOICE = "marin"


def _normalize_tts_voice(voice: Optional[str]) -> str:
    normalized = (voice or "").strip().lower()
    if normalized in SUPPORTED_TTS_VOICES:
        return normalized
    if normalized:
        _logger.warning(
            "지원하지 않는 TTS voice '%s'가 설정되어 기본값 '%s'로 대체됩니다.",
            voice,
            FALLBACK_TTS_VOICE,
        )
    return FALLBACK_TTS_VOICE

@app.on_event("startup")
async def _log_model_config() -> None:
    agent_model = os.getenv("OPENAI_AGENT_MODEL", "gpt-4.1-mini(기본값)")
    vision_model = os.getenv("OPENAI_VISION_MODEL", "gpt-4.1-mini(기본값)")
    tts_model = os.getenv("OPENAI_TTS_MODEL", "gpt-4o-mini-tts(기본값)")
    tts_voice = _normalize_tts_voice(os.getenv("OPENAI_TTS_VOICE", FALLBACK_TTS_VOICE))
    _logger.warning("=== 모델 설정 ===")
    _logger.warning("  AGENT  : %s", agent_model)
    _logger.warning("  VISION : %s", vision_model)
    _logger.warning("  TTS    : %s  voice=%s", tts_model, tts_voice)
    _logger.warning("=================")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Supabase PostgreSQL 테이블 자동 생성 (없을 경우)
create_tables_if_needed()


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


_CONTINUATION_REQUEST_PATTERNS = (
    "더 자세히",
    "자세히 설명",
    "조금 더 자세히",
    "다시 설명",
    "다시 알려",
    "다시 말",
    "한 번 더 설명",
    "한번 더 설명",
    "쉽게 설명",
    "풀어서 설명",
    "무슨 뜻",
    "왜 그런",
    "이게 왜",
    "조금 더 알려",
    "정리해줘",
    "요약해줘",
)

_ASSISTANT_PLACEHOLDER_MESSAGES = {
    "__AS_ROUTING__",
    "__SELF_CHECK__",
    "__SERVICE_CONSULT__",
    "__VISIT_SERVICE__",
}


def _is_continuation_request(message: str) -> bool:
    normalized = normalize_whitespace(message).lower()
    if not normalized:
        return False
    return any(pattern in normalized for pattern in _CONTINUATION_REQUEST_PATTERNS)


def _get_last_real_turn(history: List[Dict[str, str]]) -> Optional[Dict[str, str]]:
    for turn in reversed(history):
        if not isinstance(turn, dict):
            continue
        assistant_text = normalize_whitespace(str(turn.get("assistant", "")))
        if assistant_text and assistant_text not in _ASSISTANT_PLACEHOLDER_MESSAGES:
            return {
                "user": normalize_whitespace(str(turn.get("user", ""))),
                "assistant": assistant_text,
            }
    return None


def build_conversation_context(history: List[Dict[str, str]], current_text: str) -> str:
    """Compress recent turns into a prompt-friendly context string."""
    recent_turns = history[-6:]
    lines: List[str] = []
    for turn in recent_turns:
        user_text = turn.get("user", "").strip()
        assistant_text = turn.get("assistant", "").strip()
        if user_text:
            lines.append(f"User: {user_text}")
        if assistant_text:
            lines.append(f"Assistant: {assistant_text}")
    if _is_continuation_request(current_text):
        last_turn = _get_last_real_turn(history)
        if last_turn:
            lines.append(
                "Continuation hint: the latest user message is asking for a deeper or repeated explanation of the immediately previous assistant answer."
            )
            if last_turn["user"]:
                lines.append(f"Original issue being discussed: {last_turn['user']}")
            lines.append(f"Assistant answer to continue from: {last_turn['assistant']}")
            lines.append(
                "Instruction: continue from that answer first. Reuse the previously discussed symptom, product, and context. Do not ask for the model name or repeat missing-info questions again unless that information is truly absent from the conversation."
            )
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


def _archive_chat(
    *,
    session_id,
    user_id,
    product_id,
    user_message: str,
    assistant_message: str,
    history,
    routing_intent: str,
    routing_required: bool,
    image=None,
    audio=None,
    voice_audio=None,
    ai_meta=None,
) -> tuple:
    """DB에 대화 저장 후 (saved_session_id, warning) 반환."""
    saved_session_id = session_id
    warning = ""
    try:
        db = get_session_factory()()
        try:
            saved = save_chat_exchange(
                db,
                session_id=session_id,
                user_id=user_id,
                product_id=product_id,
                user_message=user_message,
                assistant_message=assistant_message,
                history=history,
                routing_intent=routing_intent,
                routing_required=routing_required,
                image_filename=image.filename if image else None,
                audio_filename=audio.filename if audio else None,
                voice_filename=voice_audio.filename if voice_audio else None,
                ai_meta=ai_meta,
            )
            saved_session_id = saved.id
        finally:
            db.close()
    except Exception as _e:
        _logger.warning("대화 저장 실패: %s", _e)
        warning = str(_e)
    return saved_session_id, warning


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


_SIMPLE_CHITCHAT_PATTERNS = [
    # 인사
    "안녕", "하이", "헬로", "hello", "반가워", "반갑습니다",
    # 감사
    "고마워", "고맙습니다", "감사합니다", "감사해", "감사",
    # 날씨/잡담
    "날씨", "기온",
    # 짧은 응답
    "잘 있어", "어떻게 지내", "뭐해", "수고", "bye", "바이", "잘가",
    "ㅎㅎ", "ㅋㅋ",
    # 파일/자료 업로드 예고
    "올려줄게", "올릴게", "보낼게", "보내줄게", "첨부할게", "찍을게", "찍어줄게",
    "올려드릴게", "보내드릴게", "올려볼게",
    # 확인/동의
    "네", "응", "예", "맞아", "맞습니다", "그래", "그렇구나", "그렇군요",
    "알겠어", "알겠습니다", "이해했어", "알아",
    # 부정/취소
    "아니요", "아니", "괜찮아", "필요없어",
    # 대기
    "잠깐만", "잠시만", "기다려", "잠시 후",
    # 완료
    "됐어", "완료", "끝났어",
]

def _is_simple_chitchat(message: str) -> bool:
    """이미지/오디오 없는 단순 인사·잡담·업로드예고 여부 판별."""
    msg = message.strip().lower()
    if len(msg) > 40:
        return False
    return any(pattern in msg for pattern in _SIMPLE_CHITCHAT_PATTERNS)


def _fast_chat_response(message: str, user_name: str, history: list) -> str:
    """에이전트 루프 없이 LLM 직접 호출 — 단순 질문용."""
    ensure_openai_client()
    client = OpenAI()
    display_name = user_name.strip() or "고객"
    messages = [
        {
            "role": "system",
            "content": (
                f"당신은 LG전자 가전제품 AS 전문 AI 에이전트 리보(Rebo)입니다. "
                f"고객 이름: {display_name}. "
                "짧고 친근하게 답변하세요. 가전제품 관련 질문이 아니면 자연스럽게 대화하세요."
            ),
        }
    ]
    for turn in history[-4:]:
        if turn.get("user"):
            messages.append({"role": "user", "content": turn["user"]})
        if turn.get("assistant"):
            messages.append({"role": "assistant", "content": turn["assistant"]})
    messages.append({"role": "user", "content": message})

    resp = client.chat.completions.create(
        model="gpt-4.1-mini",
        messages=messages,
        max_tokens=200,
    )
    return (resp.choices[0].message.content or "").strip()


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
        "as_request": 0.0,
        "connect_agent": 0.0,
        "book_visit": 0.0,
    }
    for label, keywords in INTENT_KEYWORD_HINTS.items():
        for keyword in keywords:
            if keyword in normalized_message:
                if label == "as_request":
                    keyword_scores[label] += 0.20 if " " in keyword else 0.16
                else:
                    keyword_scores[label] += 0.12 if " " in keyword else 0.08

    vector_scores = {
        "normal_chat": 0.0,
        "as_request": 0.0,
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
        for label in ("normal_chat", "as_request", "connect_agent", "book_visit")
    }
    service_labels = ("as_request", "connect_agent", "book_visit")
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


def infer_agent_routing_action(
    triggered_action: Any,
    severity_level: Any,
    action_pattern: Any,
) -> Optional[str]:
    """Recover the intended UI routing action from agent metadata when tool calls are missed."""
    if triggered_action in {"initiate_as_booking", "connect_human_agent", "ask_user_question"}:
        return str(triggered_action)

    try:
        resolved_severity = int(severity_level) if severity_level is not None and str(severity_level).strip() else None
    except (TypeError, ValueError):
        resolved_severity = None

    resolved_pattern = str(action_pattern or "").strip().upper()

    if resolved_severity == 4 or resolved_pattern == "D":
        return "connect_human_agent"
    if resolved_severity == 3 or resolved_pattern == "C":
        return "initiate_as_booking"
    return None


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


DEFAULT_TTS_MODEL = os.getenv("OPENAI_TTS_MODEL", "gpt-4o-mini-tts")
DEFAULT_TTS_VOICE = _normalize_tts_voice(os.getenv("OPENAI_TTS_VOICE", FALLBACK_TTS_VOICE))


class TtsRequest(BaseModel):
    text: str

@app.post("/api/tts")
async def text_to_speech(body: TtsRequest) -> StreamingResponse:
    """Convert assistant text to speech using OpenAI TTS."""
    ensure_openai_client()
    if not body.text.strip():
        raise HTTPException(status_code=400, detail="text가 비어있습니다.")

    try:
        client = OpenAI()
        response = client.audio.speech.create(
            model=DEFAULT_TTS_MODEL,
            voice=_normalize_tts_voice(DEFAULT_TTS_VOICE),
            input=body.text.strip(),
            response_format="mp3",
            speed=1.1,
            instructions="You are a cheerful, bright Korean child around 8 years old. Speak in an energetic, cute, and friendly tone. Your voice should sound young, light, and enthusiastic.",
        )
        audio_bytes = response.content

        return StreamingResponse(
            iter([audio_bytes]),
            media_type="audio/mpeg",
            headers={"Content-Length": str(len(audio_bytes))},
        )
    except Exception as error:
        _logger.error("TTS 변환 실패: %s", error)
        raise HTTPException(status_code=500, detail=f"TTS 변환 실패: {error}") from error


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
        "database": get_database_status(),
    }


@app.post("/api/chat")
async def chat(
    message: str = Form(""),
    user_name: str = Form(""),
    user_id: int = Form(1),
    product_id: Optional[int] = Form(None),
    session_id: Optional[int] = Form(None),
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
        image_path, audio_path, voice_audio_path = await asyncio.gather(
            save_upload(image),
            save_upload(audio),
            save_upload(voice_audio),
        )
        for p in (image_path, audio_path, voice_audio_path):
            if p is not None:
                temp_paths.append(p)

        voice_transcript = ""
        voice_transcription_warning = ""
        if voice_audio_path is not None:
            try:
                voice_transcript = await asyncio.to_thread(
                    transcribe_voice_message, voice_audio_path
                )
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

        # ── 단순 인사/잡담 fast path ─────────────────────────────────────────
        if image is None and audio is None and _is_simple_chitchat(effective_message):
            fast_reply = await asyncio.to_thread(
                _fast_chat_response, effective_message, user_name, history
            )
            updated_history = history + [{"user": user_message, "assistant": fast_reply}]
            asyncio.create_task(asyncio.to_thread(
                _archive_chat,
                session_id=session_id, user_id=user_id, product_id=product_id,
                user_message=user_message, assistant_message=fast_reply,
                history=updated_history, routing_intent="normal_chat",
                routing_required=False, image=None, audio=None, voice_audio=voice_audio,
            ))
            return {
                "assistant_message": fast_reply,
                "assistant_images": [],
                "evidence": {},
                "history": updated_history,
                "session_id": session_id,
                "archive_warning": None,
                "voice_transcript": voice_transcript,
                "voice_transcription_warning": voice_transcription_warning,
                "routing_required": False,
                "routing_intent": "normal_chat",
                "routing_action_hint": None,
                "routing_confidence": 1.0,
                "routing_matched_by": "fast_path",
                "agent_steps": [],
                "severity_level": None,
                "action_pattern": None,
                "judgment_steps": {},
            }

        # intent 분류 + 유저 프로필 조회 병렬 실행
        def _fetch_profile():
            db = get_session_factory()()
            try:
                return get_user_profile(db, user_id)
            finally:
                db.close()

        intent_result, _profile_raw = await asyncio.gather(
            asyncio.to_thread(classify_service_intent, effective_message),
            asyncio.to_thread(_fetch_profile),
        )

        # 유저 프로필 처리
        user_profile_context = ""
        resolved_user_name = user_name
        resolved_device_hint = "unknown"
        try:
            profile = _profile_raw
            if profile:
                resolved_user_name = profile.name
                user_profile_context = get_user_context_string(profile)
                devices = profile.devices or []
                if devices:
                    resolved_device_hint = devices[0].get("category", "unknown")
        except Exception as _e:
            _logger.warning("유저 프로필 처리 실패: %s", _e)

        if intent_result["routing_required"]:
            updated_history = history + [{"user": user_message, "assistant": ""}]
            saved_session_id, archive_warning = await asyncio.to_thread(
                _archive_chat,
                session_id=session_id, user_id=user_id, product_id=product_id,
                user_message=user_message, assistant_message="",
                history=updated_history, routing_intent=intent_result["intent"],
                routing_required=True, image=image, audio=audio, voice_audio=voice_audio,
            )

            return {
                "assistant_message": "",
                "evidence": {},
                "history": updated_history,
                "session_id": saved_session_id,
                "archive_warning": archive_warning,
                "voice_transcript": voice_transcript,
                "voice_transcription_warning": voice_transcription_warning,
                "routing_required": True,
                "routing_intent": intent_result["intent"],
                "routing_action_hint": intent_result["action_hint"],
                "routing_confidence": intent_result["confidence"],
                "routing_matched_by": intent_result["matched_by"],
            }

        conversation_text = build_conversation_context(history, effective_message)
        result = await asyncio.to_thread(
            run_agent,
            user_text=conversation_text,
            image_path=str(image_path) if image_path else None,
            audio_path=str(audio_path) if audio_path else None,
            top_k=top_k,
            user_name=resolved_user_name,
            device_hint=resolved_device_hint,
            user_profile_context=user_profile_context,
        )

        # 이미지 수집: agent_loop에서 직접 반환한 경로 우선 (중복 제거)
        _seen_images: set = set()
        assistant_images: List[str] = []
        direct_paths = result.get("image_paths", [])
        for img_url in direct_paths[:8]:
            if img_url and img_url.strip() and img_url not in _seen_images:
                _seen_images.add(img_url)
                assistant_images.append(img_url)

        # 없으면 evidence contexts에서 시도
        if not assistant_images:
            contexts = result.get("evidence", {}).get("retrieved_contexts", [])
            for ctx in contexts:
                paths = ctx.get("image_paths", [])
                if paths:
                    for img_url in paths[:8]:
                        if img_url and img_url.strip() and img_url not in _seen_images:
                            _seen_images.add(img_url)
                            assistant_images.append(img_url)
                    if assistant_images:
                        break

        triggered_action = result.get("triggered_action")
        severity_level = result.get("severity_level")
        action_pattern = result.get("action_pattern")
        effective_triggered_action = infer_agent_routing_action(
            triggered_action=triggered_action,
            severity_level=severity_level,
            action_pattern=action_pattern,
        )
        agent_steps = result.get("agent_steps", [])

        _action_to_intent = {
            "initiate_as_booking": "as_request",
            "connect_human_agent": "connect_agent",
        }
        if effective_triggered_action in _action_to_intent:
            routing_intent = _action_to_intent[effective_triggered_action]
            matched_by = "agent_tool" if triggered_action in _action_to_intent else "agent_meta"
            if matched_by == "agent_meta":
                _logger.info(
                    "Recovered routing action from agent metadata: action=%s severity=%s pattern=%s",
                    effective_triggered_action,
                    severity_level,
                    action_pattern,
                )
            diagnosis_message = result.get("response", "")
            triggered_reason = result.get("triggered_reason", "")
            updated_history = history + [{"user": user_message, "assistant": diagnosis_message}]
            saved_session_id, archive_warning = await asyncio.to_thread(
                _archive_chat,
                session_id=session_id, user_id=user_id, product_id=product_id,
                user_message=user_message, assistant_message=diagnosis_message,
                history=updated_history, routing_intent=routing_intent,
                routing_required=True, image=image, audio=audio, voice_audio=voice_audio,
            )

            # 예약 화면 자동 입력용 prefill 구성
            _symptom_text = triggered_reason or diagnosis_message
            _booking_prefill: Dict[str, str] = {}

            # 1) 제품 (device_hint → 예약 화면 리스트 값)
            _device_to_product = {
                "refrigerator": "냉장고/김치냉장고",
                "washing_machine": "세탁기",
                "air_conditioner": "에어컨/환기",
            }
            if resolved_device_hint in _device_to_product:
                _booking_prefill["product"] = _device_to_product[resolved_device_hint]

            # 2) 증상 카테고리 (키워드로 자동 매핑)
            _symptom_keywords: List[tuple] = [
                ("에러코드/표시창", ["에러코드", "오류코드", "에러 코드", "에러", "표시창", "디스플레이", "오류"]),
                ("소음/진동",       ["소음", "소리", "진동", "떨림", "울림", "드드득", "덜컹", "딸깍", "윙윙"]),
                ("누수/결빙/성에/이슬", ["누수", "물새", "물이 새", "결빙", "성에", "이슬", "얼음"]),
                ("전원/누전",       ["전원", "누전", "안 켜", "안켜", "꺼짐", "전기"]),
                ("냉동/냉장",       ["냉동", "냉장", "온도", "시원", "차갑", "얼지"]),
                ("도어/홈바",       ["도어", "문", "홈바", "힌지", "닫히"]),
                ("냄새/이물",       ["냄새", "이물", "곰팡이", "악취"]),
                ("누수/결빙/성에/이슬", ["누수", "물", "결빙"]),
                ("기능/작동",       ["작동", "기능", "동작", "안 됨", "안됨"]),
            ]
            _txt_lower = _symptom_text.lower()
            for _cat, _kws in _symptom_keywords:
                if any(_kw in _txt_lower for _kw in _kws):
                    _booking_prefill["symptom_category"] = _cat
                    break

            # 3) 세부 증상: 챗봇 응답을 AI로 직접 요약 (예약 세부 증상란용)
            _symptom_summary = ""
            _booking_model = os.getenv("OPENAI_AGENT_MODEL", "gpt-4.1-mini")
            if OpenAI is not None and os.getenv("OPENAI_API_KEY") and diagnosis_message:
                try:
                    _summary_resp = OpenAI().chat.completions.create(
                        model=_booking_model,
                        messages=[
                            {
                                "role": "system",
                                "content": (
                                    "아래 진단 응답을 예약 세부 증상란에 넣을 1-2문장으로 요약하세요.\n"
                                    "규칙:\n"
                                    "- 에러코드가 있으면 '[제품] 화면에 \\'XX\\' 에러코드가 나타나고 있어요.' 형식으로 첫 문장에 포함\n"
                                    "- 두 번째 문장: 원인이나 증상을 자연스러운 문장으로 (예: '세탁물이 한쪽으로 쏠려 편심 탈수가 발생하고 있어요.')\n"
                                    "- 해결 방법, 안내 내용, 권장 조치는 포함하지 말 것\n"
                                    "- 번호, 마크다운, 섹션 제목 없이 plain text만\n"
                                    "- 100자 이내, 각 문장 마침표로 마무리"
                                ),
                            },
                            {"role": "user", "content": diagnosis_message[:1500]},
                        ],
                        max_tokens=120,
                    )
                    _symptom_summary = (_summary_resp.choices[0].message.content or "").strip()
                except Exception:
                    pass

            if not _symptom_summary:
                # AI 실패 시 챗봇 응답에서 핵심 증상 2문장 추출
                _cleaned = _clean_assistant_text(diagnosis_message)
                _error_code = _extract_error_code(diagnosis_message)
                _device_label = _infer_device_label(diagnosis_message) or _infer_device_label(user_message)
                # 첫 문장: 에러코드 있으면 "[제품] 화면에 'XX' 에러코드가 나타나고 있어요."
                _lines = []
                if _error_code and _device_label:
                    _lines.append(f"{_device_label} 화면에 '{_error_code}' 에러코드가 나타나고 있어요.")
                elif _error_code:
                    _lines.append(f"화면에 '{_error_code}' 에러코드가 나타나고 있어요.")
                # 두 번째 문장: 정리된 응답에서 첫 의미 있는 문장 추출
                import re as _re
                _sentences = _re.split(r'(?<=[.!?])\s+', _cleaned)
                for _s in _sentences:
                    _s = _s.strip()
                    if len(_s) >= 10 and not _re.search(r'(?:해결|안내|방법|단계|다음|참고|권장)', _s):
                        _lines.append(_s)
                        break
                _symptom_summary = " ".join(_lines) if _lines else _cleaned[:80]

            if _symptom_summary:
                _booking_prefill["detailed_symptom"] = _symptom_summary

            return {
                "assistant_message": diagnosis_message,
                "assistant_images": assistant_images,
                "evidence": result.get("evidence", {}),
                "history": updated_history,
                "session_id": saved_session_id,
                "archive_warning": archive_warning,
                "voice_transcript": voice_transcript,
                "voice_transcription_warning": voice_transcription_warning,
                "routing_required": True,
                "routing_intent": routing_intent,
                "routing_action_hint": effective_triggered_action,
                "routing_confidence": 1.0,
                "routing_matched_by": matched_by,
                "agent_steps": agent_steps,
                "severity_level": severity_level,
                "action_pattern": action_pattern,
                "judgment_steps": result.get("judgment_steps", {}),
                "booking_prefill": _booking_prefill,
            }

        updated_history = history + [{"user": user_message, "assistant": result["response"]}]
        saved_session_id, archive_warning = await asyncio.to_thread(
            _archive_chat,
            session_id=session_id, user_id=user_id, product_id=product_id,
            user_message=user_message, assistant_message=result["response"],
            history=updated_history, routing_intent="normal_chat",
            routing_required=False, image=image, audio=audio, voice_audio=voice_audio,
            ai_meta={"user_name": user_name} if user_name.strip() else None,
        )

        return {
            "assistant_message": result["response"],
            "assistant_images": assistant_images,
            "evidence": result.get("evidence", {}),
            "history": updated_history,
            "session_id": saved_session_id,
            "archive_warning": archive_warning,
            "voice_transcript": voice_transcript,
            "voice_transcription_warning": voice_transcription_warning,
            "routing_required": False,
            "routing_intent": "normal_chat",
            "routing_action_hint": None,
            "routing_confidence": intent_result["confidence"],
            "routing_matched_by": intent_result["matched_by"],
            "agent_steps": agent_steps,
            "severity_level": severity_level,
            "action_pattern": action_pattern,
            "judgment_steps": result.get("judgment_steps", {}),
        }
    except HTTPException:
        raise
    except Exception as error:
        _logger.error("chat API 오류: %s", error, exc_info=True)
        raise HTTPException(status_code=500, detail="일시적인 오류가 발생했습니다. 잠시 후 다시 시도해주세요.") from error
    finally:
        cleanup_temp_files(temp_paths)


_REBO_REDIRECT_KEYWORDS = [
    "as", "a/s", "수리", "고장", "소음", "누수", "냉각", "에러코드", "에러 코드",
    "오류", "작동안", "작동 안", "안돼", "안되", "불량", "교체", "점검",
    "출장", "방문", "예약", "상담", "접수", "신청", "증상", "진단",
]


def _is_rebo_query(message: str) -> bool:
    lower = message.lower().replace(" ", "")
    return any(kw.replace(" ", "") in lower for kw in _REBO_REDIRECT_KEYWORDS)


class ChatThinQRequest(BaseModel):
    message: str
    history: List[Dict[str, str]] = []


@app.post("/api/chatthinq/chat")
async def chatthinq_chat(req: ChatThinQRequest) -> Dict[str, Any]:
    """ChatThinQ 일반 대화 엔드포인트. AS/고장 관련 질문이면 Chat REBO로 유도."""
    if not req.message.strip():
        raise HTTPException(status_code=400, detail="message is required")

    if _is_rebo_query(req.message):
        return {
            "reply": "해당 문의는 Chat REBO에서 더 정확하게 도와드릴 수 있어요. 상단 메뉴에서 Chat REBO로 전환해 보세요.",
            "redirect_to_rebo": True,
        }

    if OpenAI is None or not os.getenv("OPENAI_API_KEY"):
        return {"reply": "AI 서비스를 사용할 수 없습니다.", "redirect_to_rebo": False}

    messages: List[Dict[str, str]] = [
        {
            "role": "system",
            "content": (
                "당신은 LG 스마트홈 어시스턴트 ChatThinQ입니다. "
                "날씨, 일상 대화, 스마트홈 기능 등 일반적인 질문에 친절하고 간결하게 한국어로 답해주세요. "
                "가전제품 고장, AS, 수리 관련 문의는 Chat REBO로 안내하세요."
            ),
        }
    ]
    for turn in req.history[-6:]:
        role = turn.get("role", "user")
        content = turn.get("content", "")
        if role in ("user", "assistant") and content:
            messages.append({"role": role, "content": content})
    messages.append({"role": "user", "content": req.message})

    try:
        client = OpenAI()
        response = client.chat.completions.create(
            model="gpt-4.1-mini",
            messages=messages,
            max_tokens=300,
        )
        reply = response.choices[0].message.content or ""
    except Exception as e:
        reply = f"응답을 가져오지 못했습니다: {e}"

    return {"reply": reply.strip(), "redirect_to_rebo": False}


@app.get("/api/archive/sessions")
def archive_sessions(
    user_id: int = Query(1),
    limit: int = Query(50, ge=1, le=200),
) -> Dict[str, Any]:
    """Return archive cards for one user."""
    try:
        db = get_session_factory()()
        try:
            sessions = list_sessions(db, user_id=user_id, limit=limit)
            return {"sessions": [serialize_session(session) for session in sessions]}
        finally:
            db.close()
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.get("/api/users/{user_id}")
def get_user(user_id: int) -> Dict[str, Any]:
    """유저 프로필 및 등록 기기 조회."""
    try:
        db = get_session_factory()()
        try:
            profile = get_user_profile(db, user_id)
            if profile is None:
                raise HTTPException(status_code=404, detail="User not found.")
            return {"user": serialize_user(profile)}
        finally:
            db.close()
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.get("/api/archive/sessions/{session_id}")
def archive_session_detail(session_id: int) -> Dict[str, Any]:
    """Return one archive session with its messages."""
    try:
        db = get_session_factory()()
        try:
            session = db.get(ChatSession, session_id)
            if session is None:
                raise HTTPException(status_code=404, detail="Archive session not found.")
            messages = list_messages(db, session_id=session_id)
            return {
                "session": serialize_session(session),
                "messages": [serialize_message(message) for message in messages],
            }
        finally:
            db.close()
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(status_code=500, detail=str(error)) from error


@app.get("/debug/supabase-images")
def debug_supabase_images(q: str = "에어컨") -> Dict[str, Any]:
    """Supabase 이미지 URL 조립 확인용 디버그 엔드포인트."""
    try:
        from supabase_store import retrieve_chunks_from_supabase, _make_storage_url
        tokens = q.split()
        rows = retrieve_chunks_from_supabase(query_tokens=tokens, device_hint="unknown", top_k=3)
        return {
            "query": q,
            "results_count": len(rows),
            "results": [
                {
                    "content_preview": r.get("content_chunk", "")[:80],
                    "image_urls_raw": r.get("image_urls"),
                    "image_urls_built": r.get("_image_public_urls", []),
                }
                for r in rows
            ],
            "sample_url": _make_storage_url("kfSzw80neUPmGLoMB88bMw.jpg"),
        }
    except Exception as e:
        return {"error": str(e)}


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
