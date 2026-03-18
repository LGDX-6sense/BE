from __future__ import annotations

from datetime import datetime
import re
from typing import Any, Dict, List, Optional, Sequence

from sqlalchemy import DateTime, Enum, ForeignKey, String, Text, func, select
from sqlalchemy.dialects.mysql import BIGINT, JSON
from sqlalchemy.orm import Mapped, Session, mapped_column

from db import Base


class ChatSession(Base):
    __tablename__ = "chat_sessions"

    id: Mapped[int] = mapped_column(BIGINT(unsigned=True), primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(BIGINT(unsigned=True), nullable=False, index=True)
    product_id: Mapped[Optional[int]] = mapped_column(BIGINT(unsigned=True), nullable=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    summary: Mapped[str] = mapped_column(String(500), nullable=False)
    status: Mapped[str] = mapped_column(
        Enum("active", "resolved", "archived", name="chat_session_status"),
        nullable=False,
        default="active",
    )
    started_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, default=datetime.utcnow)
    last_message_at: Mapped[datetime] = mapped_column(
        DateTime,
        nullable=False,
        default=datetime.utcnow,
    )
    archived_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        nullable=False,
        default=datetime.utcnow,
        server_default=func.current_timestamp(),
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        nullable=False,
        default=datetime.utcnow,
        onupdate=datetime.utcnow,
        server_default=func.current_timestamp(),
    )


class ChatMessage(Base):
    __tablename__ = "chat_messages"

    id: Mapped[int] = mapped_column(BIGINT(unsigned=True), primary_key=True, autoincrement=True)
    session_id: Mapped[int] = mapped_column(
        BIGINT(unsigned=True),
        ForeignKey("chat_sessions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    role: Mapped[str] = mapped_column(
        Enum("user", "assistant", "system", name="chat_message_role"),
        nullable=False,
    )
    message_type: Mapped[str] = mapped_column(
        Enum("text", "image", "audio", "mixed", name="chat_message_type"),
        nullable=False,
        default="text",
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    attachments: Mapped[Optional[Dict[str, Any]]] = mapped_column(JSON, nullable=True)
    ai_meta: Mapped[Optional[Dict[str, Any]]] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        nullable=False,
        default=datetime.utcnow,
        server_default=func.current_timestamp(),
    )


def _normalize_text(text: str) -> str:
    return re.sub(r"\s+", " ", str(text or "")).strip()


def _truncate(text: str, length: int) -> str:
    cleaned = _normalize_text(text)
    if len(cleaned) <= length:
        return cleaned
    return f"{cleaned[: max(0, length - 1)].rstrip()}…"


def _strip_attachment_lines(text: str) -> str:
    lines: List[str] = []
    for line in str(text or "").splitlines():
        candidate = line.strip()
        if not candidate:
            continue
        if candidate.startswith("[") and candidate.endswith("]"):
            continue
        lines.append(candidate)
    return _normalize_text(" ".join(lines))


def _clean_assistant_text(text: str) -> str:
    cleaned = _normalize_text(str(text or "").replace("**", " "))
    cleaned = re.sub(r"^[^.!?]*문제를 진단해봤어요!\s*", "", cleaned)
    cleaned = cleaned.replace("현재 증상은 ", "")
    return _normalize_text(cleaned)


def _extract_latest_user_text(history: Sequence[Dict[str, str]]) -> str:
    for turn in reversed(history):
        candidate = _strip_attachment_lines(turn.get("user", ""))
        if candidate:
            return candidate
    return ""


def _extract_latest_assistant_text(history: Sequence[Dict[str, str]]) -> str:
    for turn in reversed(history):
        candidate = _clean_assistant_text(turn.get("assistant", ""))
        if candidate:
            return candidate
    return ""


def _extract_latest_user_attachment_name(history: Sequence[Dict[str, str]]) -> str:
    pattern = re.compile(r"\[(?:이미지|오디오|음성 메시지) 첨부: ([^\]]+)\]")
    for turn in reversed(history):
        match = pattern.search(turn.get("user", ""))
        if match:
            return _normalize_text(match.group(1))
    return ""


def _extract_first_sentence(text: str) -> str:
    cleaned = _clean_assistant_text(text)
    if not cleaned:
        return ""
    parts = re.split(r"(?<=[.!?。])\s+", cleaned)
    return _normalize_text(parts[0] if parts else cleaned)


def _extract_error_code(text: str) -> str:
    normalized = _normalize_text(text.upper())
    patterns = [
        r"'([A-Z]{1,3}\s?[A-Z0-9]{1,3})'",
        r'"([A-Z]{1,3}\s?[A-Z0-9]{1,3})"',
        r"\b([A-Z]{1,3}\s?[A-Z0-9]{1,3})\b(?=\s*(?:에러|오류|코드))",
    ]
    for pattern in patterns:
        match = re.search(pattern, normalized)
        if match:
            return _normalize_text(match.group(1))
    return ""


def _infer_device_label(text: str) -> str:
    normalized = _normalize_text(text)
    if any(keyword in normalized for keyword in ("냉장고", "냉동", "냉장")):
        return "냉장고"
    if any(keyword in normalized for keyword in ("세탁기", "탈수", "배수")):
        return "세탁기"
    if any(keyword in normalized for keyword in ("에어컨", "냉방", "실외기", "실내기")):
        return "에어컨"
    return ""


def _extract_solution_line(text: str) -> str:
    cleaned = _clean_assistant_text(text)
    if not cleaned:
        return ""

    numbered_lines = re.findall(r"(?:^|\s)(?:\d+\.|\d+\))\s*([^0-9]+?)(?=(?:\s+\d+\.|\s+\d+\)|$))", cleaned)
    if numbered_lines:
        return _normalize_text(numbered_lines[0])

    fallback_patterns = [
        r"다음과 같이 대처해보세요\.?\s*(.+)",
        r"대처해보세요\.?\s*(.+)",
    ]
    for pattern in fallback_patterns:
        match = re.search(pattern, cleaned)
        if match:
            return _normalize_text(match.group(1))
    return ""


def _build_archive_title(latest_user: str, latest_assistant: str, attachment_name: str) -> str:
    combined = _normalize_text(f"{latest_user} {latest_assistant} {attachment_name}")
    error_code = _extract_error_code(combined)
    device = _infer_device_label(combined)

    if device and error_code:
        return f"{device} {error_code} 에러 문의"
    if error_code:
        return f"{error_code} 에러 문의"
    if latest_user:
        if device and device not in latest_user:
            return _truncate(f"{device} {latest_user}", 36)
        return _truncate(latest_user, 36)
    if device and attachment_name:
        return f"{device} 이미지 진단"
    if attachment_name:
        return _truncate(f"{attachment_name} 진단", 36)
    if latest_assistant:
        return _truncate(_extract_first_sentence(latest_assistant), 36)
    return "새 채팅"


def _build_archive_summary(latest_user: str, latest_assistant: str) -> str:
    symptom = _extract_first_sentence(latest_assistant)
    solution = _extract_solution_line(latest_assistant)

    if symptom and solution:
        return _truncate(f"{symptom} {solution} 안내함.", 120)
    if solution:
        return _truncate(f"{solution} 안내함.", 120)
    if symptom:
        return _truncate(symptom, 120)
    if latest_user:
        return _truncate(latest_user, 120)
    return "대화가 시작되었습니다."


def build_title_and_summary(
    history: Sequence[Dict[str, str]],
    *,
    routing_intent: str = "normal_chat",
    routing_required: bool = False,
) -> tuple[str, str]:
    """Build a short archive title and one-line summary from the conversation."""
    latest_user = _extract_latest_user_text(history)
    latest_assistant = _extract_latest_assistant_text(history)
    attachment_name = _extract_latest_user_attachment_name(history)

    if routing_required and routing_intent == "connect_agent":
        return (
            "상담사 연결 요청",
            "상담사 연결이 필요하다고 판단해 상담 연결 선택 단계로 안내함.",
        )

    if routing_required and routing_intent == "book_visit":
        return (
            "출장서비스 예약 요청",
            "출장서비스 예약이 필요하다고 판단해 방문 예약 선택 단계로 안내함.",
        )

    return (
        _build_archive_title(latest_user, latest_assistant, attachment_name),
        _build_archive_summary(latest_user, latest_assistant),
    )


def _build_user_attachments(
    *,
    image_filename: Optional[str],
    audio_filename: Optional[str],
    voice_filename: Optional[str],
) -> Optional[Dict[str, Any]]:
    items: List[Dict[str, str]] = []
    if image_filename:
        items.append({"type": "image", "file_name": image_filename})
    if audio_filename:
        items.append({"type": "audio", "file_name": audio_filename})
    if voice_filename:
        items.append({"type": "voice", "file_name": voice_filename})
    return {"items": items} if items else None


def _infer_message_type(attachments: Optional[Dict[str, Any]]) -> str:
    if not attachments or not attachments.get("items"):
        return "text"
    item_types = {item.get("type") for item in attachments.get("items", [])}
    if len(item_types) > 1:
        return "mixed"
    only_type = next(iter(item_types))
    if only_type == "image":
        return "image"
    if only_type in {"audio", "voice"}:
        return "audio"
    return "mixed"


def get_or_create_session(
    db: Session,
    *,
    session_id: Optional[int],
    user_id: int,
    product_id: Optional[int],
) -> ChatSession:
    """Fetch an existing session or create a new one."""
    if session_id is not None:
        existing = db.get(ChatSession, session_id)
        if existing is not None:
            return existing

    session = ChatSession(
        user_id=user_id,
        product_id=product_id,
        title="새 채팅",
        summary="대화가 시작되었습니다.",
        status="active",
    )
    db.add(session)
    db.flush()
    return session


def save_chat_exchange(
    db: Session,
    *,
    session_id: Optional[int],
    user_id: int,
    product_id: Optional[int],
    user_message: str,
    assistant_message: str,
    history: Sequence[Dict[str, str]],
    routing_intent: str,
    routing_required: bool,
    image_filename: Optional[str] = None,
    audio_filename: Optional[str] = None,
    voice_filename: Optional[str] = None,
    ai_meta: Optional[Dict[str, Any]] = None,
) -> ChatSession:
    """Persist the latest user and assistant messages into MySQL."""
    session = get_or_create_session(
        db,
        session_id=session_id,
        user_id=user_id,
        product_id=product_id,
    )

    user_attachments = _build_user_attachments(
        image_filename=image_filename,
        audio_filename=audio_filename,
        voice_filename=voice_filename,
    )
    db.add(
        ChatMessage(
            session_id=session.id,
            role="user",
            message_type=_infer_message_type(user_attachments),
            content=user_message or "",
            attachments=user_attachments,
            ai_meta=None,
        )
    )

    if assistant_message.strip():
        db.add(
            ChatMessage(
                session_id=session.id,
                role="assistant",
                message_type="text",
                content=assistant_message,
                attachments=None,
                ai_meta=ai_meta,
            )
        )

    title, summary = build_title_and_summary(
        history,
        routing_intent=routing_intent,
        routing_required=routing_required,
    )
    session.title = title
    session.summary = summary
    session.last_message_at = datetime.utcnow()

    db.commit()
    db.refresh(session)
    return session


def list_sessions(db: Session, *, user_id: int, limit: int = 50) -> List[ChatSession]:
    """Return recent archive sessions for one user."""
    stmt = (
        select(ChatSession)
        .where(ChatSession.user_id == user_id)
        .order_by(ChatSession.last_message_at.desc(), ChatSession.id.desc())
        .limit(limit)
    )
    return list(db.scalars(stmt))


def list_messages(db: Session, *, session_id: int) -> List[ChatMessage]:
    """Return messages for a session in chronological order."""
    stmt = (
        select(ChatMessage)
        .where(ChatMessage.session_id == session_id)
        .order_by(ChatMessage.created_at.asc(), ChatMessage.id.asc())
    )
    return list(db.scalars(stmt))


def serialize_session(session: ChatSession) -> Dict[str, Any]:
    return {
        "id": session.id,
        "user_id": session.user_id,
        "product_id": session.product_id,
        "title": session.title,
        "summary": session.summary,
        "status": session.status,
        "started_at": session.started_at.isoformat() if session.started_at else None,
        "last_message_at": session.last_message_at.isoformat() if session.last_message_at else None,
        "archived_at": session.archived_at.isoformat() if session.archived_at else None,
    }


def serialize_message(message: ChatMessage) -> Dict[str, Any]:
    return {
        "id": message.id,
        "session_id": message.session_id,
        "role": message.role,
        "message_type": message.message_type,
        "content": message.content,
        "attachments": message.attachments,
        "ai_meta": message.ai_meta,
        "created_at": message.created_at.isoformat() if message.created_at else None,
    }
