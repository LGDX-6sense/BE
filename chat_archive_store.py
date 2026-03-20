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


def _all_history_text(history: Sequence[Dict[str, str]]) -> str:
    parts: List[str] = []
    for turn in history:
        user_text = _strip_attachment_lines(turn.get("user", ""))
        assistant_text = _clean_assistant_text(turn.get("assistant", ""))
        if user_text:
            parts.append(user_text)
        if assistant_text:
            parts.append(assistant_text)
    return _normalize_text(" ".join(parts))


def _contains_any(text: str, keywords: Sequence[str]) -> bool:
    normalized = _normalize_text(text)
    return any(keyword in normalized for keyword in keywords)


def _extract_issue_phrase(
    latest_user: str,
    latest_assistant: str,
    history_text: str,
) -> str:
    combined = _normalize_text(f"{latest_user} {latest_assistant} {history_text}")
    device = _infer_device_label(combined)
    error_code = _extract_error_code(combined)

    if device and error_code:
        return f"{device} {error_code} 에러코드"
    if error_code:
        return f"{error_code} 에러코드"

    symptom_patterns = [
        (("온풍", "나오지"), "온풍이 나오지 않는 증상"),
        (("시원하지",), "시원하지 않은 증상"),
        (("안 시원",), "시원하지 않은 증상"),
        (("차갑지",), "차갑지 않은 증상"),
        (("배수",), "배수가 되지 않는 증상"),
        (("물이 안 빠",), "배수가 되지 않는 증상"),
        (("누수",), "누수 증상"),
        (("물 새",), "누수 증상"),
        (("소음",), "이상 소음 증상"),
        (("소리",), "이상 소음 증상"),
        (("진동",), "진동 증상"),
        (("냄새",), "냄새 문제"),
        (("전원이 안",), "전원 문제"),
        (("안 켜",), "전원 문제"),
        (("냉기가 약",), "냉기가 약한 증상"),
    ]
    for keywords, label in symptom_patterns:
        if all(keyword in combined for keyword in keywords):
            if device and device not in label:
                return f"{device} {label}"
            return label

    if latest_user:
        compact = re.sub(
            r"(이에요|예요|해요|나요|떠요|있어요|인가요|일까요|싶어요|해주세요|해줘)$",
            "",
            _normalize_text(latest_user),
        )
        if device and device not in compact:
            compact = f"{device} {compact}"
        return _truncate(compact, 40)

    return _truncate(_extract_first_sentence(latest_assistant), 40)


def _extract_action_phrase(text: str) -> str:
    solution = _extract_solution_line(text)
    combined = _normalize_text(text)
    source = _normalize_text(f"{solution} {combined}")

    mapped_actions = [
        (("호스", "물", "빼"), "호스 안의 물을 빼는 자가진단"),
        (("호스", "연결"), "호스 연결 상태를 확인하는 자가진단"),
        (("필터", "청소"), "필터 청소 자가진단"),
        (("문", "닫"), "문 닫힘 상태를 확인하는 자가점검"),
        (("전원", "다시"), "전원을 다시 켜보는 자가점검"),
        (("전원", "꺼"), "전원을 다시 켜보는 자가점검"),
        (("실외기", "점검"), "실외기 상태를 확인하는 자가점검"),
        (("리모컨", "건전지"), "리모컨 건전지를 확인하는 자가점검"),
        (("배수", "점검"), "배수 상태를 확인하는 자가점검"),
        (("자가진단",), "자가진단"),
        (("자가점검",), "자가점검"),
    ]
    for keywords, label in mapped_actions:
        if all(keyword in source for keyword in keywords):
            return label

    if solution:
        cleaned = _normalize_text(solution).rstrip(". ")
        cleaned = re.sub(r"(먼저|우선)\s+", "", cleaned)
        cleaned = re.sub(r"(해보세요|보세요|해주세요|해 주세요|하세요)$", "", cleaned)
        if cleaned:
            return _truncate(f"{cleaned} 자가점검", 46)

    return ""


def _detect_resolved(history_text: str) -> bool:
    return _contains_any(
        history_text,
        (
            "해결됐",
            "해결되었",
            "해결됐어요",
            "정상으로 돌아",
            "정상 작동",
            "괜찮아졌",
            "사라졌",
            "없어졌",
            "문제가 해결",
        ),
    )


def _detect_service_request(history_text: str, routing_intent: str, routing_required: bool) -> bool:
    if routing_required and routing_intent in {"connect_agent", "book_visit"}:
        return True
    return _contains_any(
        history_text.lower(),
        (
            "as",
            "a/s",
            "상담사",
            "상담 연결",
            "예약",
            "출장",
            "방문",
            "기사",
            "서비스 신청",
            "as 신청",
        ),
    )


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


def _build_archive_summary(
    history: Sequence[Dict[str, str]],
    latest_user: str,
    latest_assistant: str,
    *,
    routing_intent: str,
    routing_required: bool,
) -> str:
    history_text = _all_history_text(history)
    issue = _extract_issue_phrase(latest_user, latest_assistant, history_text)
    action = _extract_action_phrase(history_text)
    resolved = _detect_resolved(history_text)
    service_requested = _detect_service_request(history_text, routing_intent, routing_required)

    if routing_required and routing_intent == "connect_agent":
        return "상담사 연결이 필요해 상담 연결 단계로 안내드렸어요."

    if routing_required and routing_intent == "book_visit":
        return "출장 서비스가 필요해 방문 예약 단계로 안내드렸어요."

    if issue and resolved and action:
        return _truncate(
            f"{issue} 발생으로 {action}을 추천드렸으며, 점검 후 증상이 해결됐습니다.",
            120,
        )

    if issue and service_requested and action:
        return _truncate(
            f"{issue}에 관해 진단을 받으시고 {action} 후 AS를 신청하셨어요.",
            120,
        )

    if issue and service_requested:
        return _truncate(f"{issue} 문제로 AS 예약을 도와드렸어요.", 120)

    if issue and action:
        return _truncate(f"{issue} 증상으로 {action}을 안내드렸어요.", 120)

    symptom = _extract_first_sentence(latest_assistant)
    if symptom:
        return _truncate(f"{symptom} 관련 내용을 안내드렸어요.", 120)
    if latest_user:
        return _truncate(f"{latest_user} 관련 상담을 진행했어요.", 120)
    return "대화를 진행했어요."


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
        return ("상담사 연결 요청", "상담사 연결이 필요해 상담 연결 단계로 안내드렸어요.")

    if routing_required and routing_intent == "book_visit":
        return ("출장서비스 예약 요청", "출장 서비스가 필요해 방문 예약 단계로 안내드렸어요.")

    return (
        _build_archive_title(latest_user, latest_assistant, attachment_name),
        _build_archive_summary(
            history,
            latest_user,
            latest_assistant,
            routing_intent=routing_intent,
            routing_required=routing_required,
        ),
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
