from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import json
import os
import re
from typing import Any, Dict, List, Optional, Sequence

from sqlalchemy import BigInteger, DateTime, ForeignKey, JSON, String, Text, func, select, text
from sqlalchemy.orm import Mapped, Session, mapped_column

from db import Base

try:
    from openai import OpenAI
except ImportError:
    OpenAI = None


class ChatSession(Base):
    __tablename__ = "chat_sessions"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(BigInteger, nullable=False, index=True)
    product_id: Mapped[Optional[int]] = mapped_column(BigInteger, nullable=True)
    title: Mapped[str] = mapped_column(String(255), nullable=False)
    summary: Mapped[str] = mapped_column(String(500), nullable=False)
    status: Mapped[str] = mapped_column(
        String(20),
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

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    session_id: Mapped[int] = mapped_column(
        BigInteger,
        ForeignKey("chat_sessions.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    role: Mapped[str] = mapped_column(String(20), nullable=False)
    message_type: Mapped[str] = mapped_column(String(20), nullable=False, default="text")
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


def _truncate_multiline(text: str, length: int, *, max_lines: int = 2) -> str:
    lines = [_normalize_text(line) for line in str(text or "").splitlines() if _normalize_text(line)]
    if not lines:
        return ""
    lines = lines[:max_lines]
    compact = "\n".join(lines)
    if len(compact) <= length:
        return compact

    remaining = length
    output: List[str] = []
    for index, line in enumerate(lines):
        reserve = 1 if index < len(lines) - 1 else 0
        allowance = max(0, remaining - reserve)
        if allowance <= 0:
            break
        if len(line) <= allowance:
            output.append(line)
            remaining -= len(line) + reserve
            continue
        output.append(f"{line[: max(0, allowance - 1)].rstrip()}…")
        break
    return "\n".join(output)


ARCHIVE_SUMMARY_MODEL = os.getenv(
    "OPENAI_ARCHIVE_SUMMARY_MODEL",
    os.getenv("OPENAI_AGENT_MODEL", os.getenv("OPENAI_MODEL", "gpt-4.1-mini")),
)
_OPENAI_MODEL_ALIASES = {
    "gpt-4-mini": "gpt-4.1-mini",
}


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
    # 줄바꿈 기준으로 먼저 정리 (normalize 전에 줄별 처리)
    raw = str(text or "").replace("**", " ")
    # 인트로 문구 제거: "지영님의 문제를 진단해봤어요!" 같은 줄
    raw = re.sub(r"^[^\n]*문제를 진단해봤어요![^\n]*", "", raw, flags=re.MULTILINE)
    # 이모지 심각도 줄 제거: "🟢 자가 해결 가능", "🟡 확인 필요", "🔵 진단 신뢰도" 등
    raw = re.sub(r"^[^\n]*[🔵🟢🟡🟠🔴⚪🟣][^\n]*", "", raw, flags=re.MULTILINE)
    # 번호 섹션 헤더 줄 제거: "1. 증상 분류", "2. 원인 분석" 등
    raw = re.sub(
        r"^\s*\d+\s*[.)]\s*(?:증상\s*분류|원인\s*분석|심각도|추천\s*조치|자가점검|판단)[^\n]*",
        "",
        raw,
        flags=re.MULTILINE,
    )
    cleaned = _normalize_text(raw)
    for marker in ("__AS_ROUTING__", "__SELF_CHECK__", "__SERVICE_CONSULT__", "__VISIT_SERVICE__"):
        cleaned = cleaned.replace(marker, " ")
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
    """대화 전체를 하나의 텍스트로 합칩니다."""
    parts: List[str] = []
    for turn in history:
        u = _strip_attachment_lines(turn.get("user", ""))
        a = _clean_assistant_text(turn.get("assistant", ""))
        if u:
            parts.append(u)
        if a:
            parts.append(a)
    return _normalize_text(" ".join(parts))


def _trim_phrase(text: str) -> str:
    return _normalize_text(str(text or "").rstrip(" .,!?:;"))


def _ensure_sentence(text: str) -> str:
    cleaned = _trim_phrase(text)
    if not cleaned:
        return ""
    if cleaned.endswith((".", "!", "?")):
        return cleaned
    return f"{cleaned}."


def _to_reported_clause(text: str) -> str:
    cleaned = _trim_phrase(text)
    if not cleaned:
        return ""

    special_endings = {
        "필요합니다": "필요하다고",
        "필요해요": "필요하다고",
        "높습니다": "높다고",
        "높아요": "높다고",
        "부족합니다": "부족하다고",
        "보입니다": "보인다고",
        "보여요": "보인다고",
        "의심됩니다": "의심된다고",
        "추정됩니다": "추정된다고",
    }
    for ending, replacement in special_endings.items():
        if cleaned.endswith(ending):
            return f"{cleaned[: -len(ending)]}{replacement}"

    if cleaned.endswith("입니다"):
        return f"{cleaned[:-3]}이라고"
    if cleaned.endswith("됩니다"):
        return f"{cleaned[:-3]}된다고"
    if cleaned.endswith("한다"):
        return f"{cleaned[:-2]}한다고"
    if cleaned.endswith("하다"):
        return f"{cleaned[:-2]}한다고"
    if cleaned.endswith("다"):
        return f"{cleaned[:-1]}다고"
    return f"{cleaned}라고"


def _contains_ignoring_spaces(text: str, needle: str) -> bool:
    normalized_text = _normalize_text(text).replace(" ", "")
    normalized_needle = _normalize_text(needle).replace(" ", "")
    return bool(normalized_text and normalized_needle and normalized_needle in normalized_text)


def _extract_issue_tag(text: str) -> str:
    normalized = _normalize_text(text)
    if any(keyword in normalized for keyword in ("소음", "소리", "진동", "흔들")):
        return "소음"
    if any(keyword in normalized for keyword in ("배수", "탈수")):
        return "배수 이상"
    if any(keyword in normalized for keyword in ("누수", "물이 새", "물 샘", "물샘", "물이 고", "물이 나")):
        return "누수"
    if any(keyword in normalized for keyword in ("냄새", "악취")):
        return "냄새"
    if any(keyword in normalized for keyword in ("에러", "오류", "코드")):
        return "오류"
    if any(keyword in normalized for keyword in ("전원", "안 켜", "안켜", "꺼져", "꺼짐", "먹통")):
        return "전원 이상"
    if any(keyword in normalized for keyword in ("냉방", "찬바람", "시원하지", "냉기")):
        return "냉방 이상"
    if any(keyword in normalized for keyword in ("가열", "건조", "온도")):
        return "온도 이상"
    return ""


_INTERNAL_SUMMARY_HEADING_PATTERN = re.compile(
    r"^(?:\d+\s*단계\s*[:：-]\s*)?"
    r"(?:증상\s*분류|원인\s*분석|심각도\s*판단(?:\s*(?:\+|및)\s*행동\s*패턴\s*결정)?|"
    r"판단\s*(?:\+|및)\s*행동\s*패턴\s*결정|행동\s*패턴\s*결정|추천\s*조치|자가점검\s*가이드)"
    r"\s*[:：-]\s*",
)


def _strip_internal_summary_heading(text: str) -> str:
    cleaned = _normalize_text(text)
    if not cleaned:
        return ""

    previous = None
    while cleaned and cleaned != previous:
        previous = cleaned
        cleaned = _INTERNAL_SUMMARY_HEADING_PATTERN.sub("", cleaned).strip()
    return cleaned


def _resolve_openai_model(model_name: str, fallback: str = "gpt-4.1-mini") -> str:
    normalized = str(model_name or "").strip()
    if not normalized:
        return fallback
    return _OPENAI_MODEL_ALIASES.get(normalized, normalized)


def _extract_openai_response_text(response: Any) -> str:
    direct_text = getattr(response, "output_text", "")
    if isinstance(direct_text, str) and direct_text.strip():
        return direct_text.strip()

    parts: List[str] = []
    for item in getattr(response, "output", []) or []:
        for content in getattr(item, "content", []) or []:
            text_value = getattr(content, "text", None)
            refusal_value = getattr(content, "refusal", None)
            if isinstance(text_value, str) and text_value.strip():
                parts.append(text_value.strip())
            elif isinstance(refusal_value, str) and refusal_value.strip():
                parts.append(refusal_value.strip())
    return "\n".join(parts).strip()


def _try_parse_json_object(text: str) -> Dict[str, Any]:
    raw = str(text or "").strip()
    if not raw:
        return {}
    candidates = [raw]
    fenced_match = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", raw, flags=re.DOTALL)
    if fenced_match:
        candidates.insert(0, fenced_match.group(1))
    brace_match = re.search(r"(\{.*\})", raw, flags=re.DOTALL)
    if brace_match:
        candidates.append(brace_match.group(1))
    for candidate in candidates:
        try:
            parsed = json.loads(candidate)
        except Exception:
            continue
        if isinstance(parsed, dict):
            return parsed
    return {}


def _build_issue_subject(issue: str, device: str) -> str:
    cleaned_issue = _trim_phrase(issue)
    issue_tag = _extract_issue_tag(cleaned_issue)
    if device and issue_tag:
        return f"{device} {issue_tag}"
    if cleaned_issue:
        if device and device not in cleaned_issue:
            return _truncate(f"{device} {cleaned_issue}", 28)
        return _truncate(cleaned_issue, 28)
    return device


def _looks_like_service_only_request(text: str) -> bool:
    normalized = _normalize_text(text)
    service_keywords = (
        "상담사 연결",
        "상담 연결",
        "고객센터 연결",
        "전화 상담",
        "상담 서비스",
        "상담 서비스 예약",
        "AS 신청",
        "AS 접수",
        "A/S 신청",
        "A/S 접수",
        "서비스 접수",
        "방문 예약",
        "출장 예약",
        "출장 서비스",
        "출장 서비스 예약",
        "기사 방문",
        "기사 파견",
    )
    return any(keyword in normalized for keyword in service_keywords)


def _extract_issue_phrase(
    history: Sequence[Dict[str, str]],
) -> str:
    """사용자 메시지 전체에서 핵심 증상 구문을 추출합니다."""
    # 전체 사용자 메시지 수집
    user_msgs: List[str] = []
    for turn in history:
        u = _strip_attachment_lines(turn.get("user", ""))
        if u:
            user_msgs.append(u)
    combined_user = " ".join(user_msgs)

    product_symptom_patterns = [
        r"((?:냉장고|세탁기|에어컨|건조기|식기세척기|TV|티비|청소기|전자레인지)[이가]?\s*[^.!?\n]{2,25}(?:소음|소리|안\s*돼|안\s*됩|못|불|이상|고장|에러|오류|멈춤|냄새|물|진동|흔들))",
        r"((?:소음|소리|진동|냄새|누수|에러|오류|고장|이상|멈춤)\s*[^.!?\n]{0,15}(?:냉장고|세탁기|에어컨|건조기|식기세척기))",
        r"([가-힣]{2,6}(?:이|가)\s+(?:안\s*(?:돼|됩|켜|열|작동)|고장|이상|멈춤|소음|냄새|누수)[^.!?]{0,20})",
        r"([가-힣]+에서\s+[^.!?]{4,30}(?:소음|소리|냄새|물|이상|오류)[^.!?]{0,10})",
    ]
    for pat in product_symptom_patterns:
        m = re.search(pat, combined_user)
        if m:
            return _truncate(m.group(1), 40)

    # 첫 사용자 메시지의 첫 의미 있는 문장
    if user_msgs:
        for part in re.split(r"[.!?\n]", user_msgs[0]):
            cleaned = _normalize_text(part)
            if len(cleaned) >= 6:
                return _truncate(cleaned, 40)

    return ""


def _extract_diagnosis_from_history(history: Sequence[Dict[str, str]]) -> str:
    """어시스턴트 응답에서 핵심 진단 결론 문장을 추출합니다."""
    diagnosis_patterns = [
        r"([^.!?\n]{4,50}(?:원인으로\s*보입|문제로\s*보입|가능성이\s*높|것으로\s*판단|로\s*인한)[^.!?]{0,30}[.!?]?)",
        r"(원인[은는이가]?\s*[^.!?\n]{5,50}[.!?])",
        r"([^.!?\n]{4,50}(?:가능성이\s*있|의심됩|추정됩|추정돼|보여요|보입니다)[^.!?]{0,20}[.!?]?)",
        r"([^.!?\n]{4,50}(?:확인\s*필요|점검이\s*필요|교체가\s*필요|청소가\s*필요)[^.!?]{0,20}[.!?]?)",
        r"([^.!?\n]{4,50}(?:고장|이상|불량|막힘|부족|과부하)[^.!?\n]{0,30}[.!?])",
    ]
    for turn in reversed(history):
        a = _clean_assistant_text(turn.get("assistant", ""))
        if not a:
            continue
        for pat in diagnosis_patterns:
            m = re.search(pat, a)
            if m:
                result = _strip_internal_summary_heading(
                    _normalize_text(m.group(1).rstrip(".!?"))
                )
                if len(result) >= 8:
                    return _truncate(result, 60)
    return ""


def _extract_action_phrase_from_history(history: Sequence[Dict[str, str]]) -> str:
    """어시스턴트가 권장한 조치/해결책을 추출합니다."""
    action_keywords = [
        (r"배수\s*필터\s*청소", "배수 필터 청소"),
        (r"필터\s*청소", "필터 청소"),
        (r"전원\s*(?:재시작|리셋|껐다)", "전원 재시작"),
        (r"온도\s*설정\s*확인", "온도 설정 확인"),
        (r"컴프레서\s*점검", "컴프레서 점검"),
        (r"냉매\s*(?:점검|충전|보충)", "냉매 점검"),
        (r"세탁조\s*청소", "세탁조 청소"),
        (r"전문\s*기사\s*(?:점검|방문)|기사\s*방문", "전문 기사 점검"),
        (r"자가\s*점검|자가점검", "자가 점검"),
        (r"AS\s*(?:신청|접수)|서비스\s*접수", "AS 신청"),
        (r"재부팅|리셋", "재부팅"),
    ]
    for turn in reversed(history):
        a = turn.get("assistant", "")
        for pattern, label in action_keywords:
            if re.search(pattern, a):
                return label
    # 번호 목록 첫 항목 fallback
    for turn in reversed(history):
        a = _clean_assistant_text(turn.get("assistant", ""))
        m = re.search(r"(?:^|\s)1[.)]\s*(.{5,30})", a)
        if m:
            return _truncate(m.group(1), 25)
    return ""


def _detect_resolved(history: Sequence[Dict[str, str]]) -> bool:
    """사용자 발화에서만 문제 해결 여부를 감지합니다."""
    user_texts = " ".join(turn.get("user", "") for turn in history)
    return _has_resolved_keyword(user_texts)


def _has_resolved_keyword(text: str) -> bool:
    normalized = _normalize_text(text)
    resolved_keywords = [
        "괜찮아졌", "정상 작동", "잘 됩니다", "잘 돼요",
        "고쳐졌", "작동합니다", "작동돼요", "작동되고 있", "됩니다 감사",
        "해결됐", "해결되었",
    ]
    return any(kw in normalized for kw in resolved_keywords)


def _detect_service_request(
    history_text: str,
    routing_intent: str,
    routing_required: bool,
) -> bool:
    """AS 접수·출장 요청 여부를 감지합니다."""
    if routing_required and routing_intent in ("as_request", "book_visit", "connect_agent"):
        return True
    service_keywords = [
        "AS 신청", "as 접수", "서비스 접수", "출장 신청", "방문 예약",
        "기사 파견", "수리 요청", "서비스 예약", "상담 서비스 예약",
        "출장 서비스 예약",
    ]
    return any(kw in history_text.lower() for kw in service_keywords)


def _detect_service_status(
    history_text: str,
    routing_intent: str,
    routing_required: bool,
) -> str:
    normalized = _normalize_text(history_text)
    lowered = normalized.lower()

    if routing_required and routing_intent == "connect_agent":
        return "상담사 연결 안내"
    if routing_required and routing_intent == "book_visit":
        return "방문 예약 안내"
    if routing_required and routing_intent == "as_request":
        return "AS 접수 안내"

    if any(
        keyword in normalized
        for keyword in (
            "상담사 연결",
            "상담 연결",
            "고객센터 연결",
            "전화 상담",
            "상담 서비스",
            "상담 서비스 예약",
        )
    ):
        return "상담사 연결 안내"

    if any(keyword in normalized for keyword in ("방문 예약 완료", "출장 예약 완료")):
        return "방문 예약 완료"
    if any(
        keyword in normalized
        for keyword in (
            "방문 예약",
            "출장 예약",
            "기사 방문",
            "기사 파견",
            "출장 서비스",
            "출장 서비스 예약",
        )
    ):
        return "방문 예약 안내"

    if any(keyword in normalized for keyword in ("A/S 신청", "A/S 접수", "서비스 접수", "수리 요청", "서비스 예약")):
        return "AS 접수 안내"
    if "as 신청" in lowered or "as 접수" in lowered:
        return "AS 접수 안내"

    return ""


@dataclass
class _ArchiveSignals:
    issue: str
    diagnosis: str
    action: str
    resolved: bool
    service_status: str
    device: str
    error_code: str


def _collect_archive_signals(
    history: Sequence[Dict[str, str]],
    latest_user: str,
    latest_assistant: str,
    attachment_name: str,
    *,
    routing_intent: str,
    routing_required: bool,
) -> _ArchiveSignals:
    history_text = _all_history_text(history)
    combined = _normalize_text(f"{history_text} {latest_user} {latest_assistant} {attachment_name}")
    issue = _extract_issue_phrase(history)
    diagnosis = _extract_diagnosis_from_history(history)
    action = _extract_action_phrase_from_history(history)
    service_status = _detect_service_status(history_text, routing_intent, routing_required)
    if issue and service_status and not _infer_device_label(issue) and not _extract_issue_tag(issue):
        if _looks_like_service_only_request(issue):
            issue = ""
    if diagnosis and (
        _has_resolved_keyword(diagnosis)
        or _looks_like_service_only_request(diagnosis)
    ):
        diagnosis = ""
    if diagnosis and action and _contains_ignoring_spaces(diagnosis, action):
        diagnosis = ""
    return _ArchiveSignals(
        issue=issue,
        diagnosis=diagnosis,
        action=action,
        resolved=_detect_resolved(history),
        service_status=service_status,
        device=_infer_device_label(combined),
        error_code=_extract_error_code(combined),
    )


def _serialize_recent_history_for_summary(history: Sequence[Dict[str, str]], max_turns: int = 6) -> str:
    selected_turns = list(history[-max_turns:])
    lines: List[str] = []
    for index, turn in enumerate(selected_turns, start=1):
        user_text = _strip_attachment_lines(turn.get("user", ""))
        assistant_text = _clean_assistant_text(turn.get("assistant", ""))
        if user_text:
            lines.append(f"[사용자 {index}] {user_text}")
        if assistant_text:
            lines.append(f"[상담 {index}] {assistant_text}")
    return "\n".join(lines).strip()


def _normalize_archive_summary_output(summary: str) -> str:
    cleaned = _normalize_text(
        str(summary or "")
        .replace("```json", " ")
        .replace("```", " ")
        .strip()
        .strip('"')
        .strip("'")
    )
    if not cleaned:
        return ""
    return _truncate(cleaned, 140)


def _split_archive_summary_lines(summary: str) -> tuple[str, str]:
    normalized = _normalize_archive_summary_output(summary)
    if not normalized:
        return "", ""

    cause_line = ""
    action_line = ""
    for line in normalized.splitlines():
        if not cause_line and re.match(r"^(원인|증상):", line):
            cause_line = line
        elif not action_line and line.startswith("조치:"):
            action_line = line
    return cause_line, action_line


def _build_archive_summary_prompt(
    history: Sequence[Dict[str, str]],
    latest_user: str,
    latest_assistant: str,
    signals: _ArchiveSignals,
    *,
    routing_intent: str,
    routing_required: bool,
    ai_meta: Optional[Dict[str, Any]],
) -> str:
    judgment_steps = {}
    if isinstance(ai_meta, dict):
        raw_steps = ai_meta.get("judgment_steps")
        if isinstance(raw_steps, dict):
            judgment_steps = raw_steps

    preferred_cause = signals.diagnosis or _normalize_text(judgment_steps.get("step2", ""))
    preferred_action = signals.action or signals.service_status

    signal_lines = [
        f"- 제품: {signals.device or '미상'}",
        f"- 핵심 증상: {signals.issue or '미상'}",
        f"- 추정 원인: {preferred_cause or '미상'}",
        f"- 권장 조치: {signals.action or '미상'}",
        f"- 서비스 상태: {signals.service_status or '없음'}",
        f"- 해결 여부: {'해결됨' if signals.resolved else '미해결 또는 불명'}",
        f"- 라우팅 intent: {routing_intent or 'normal_chat'}",
        f"- 라우팅 필요 여부: {'예' if routing_required else '아니오'}",
    ]

    if latest_user:
        signal_lines.append(f"- 최신 사용자 메시지: {latest_user}")
    if latest_assistant:
        signal_lines.append(f"- 최신 상담 응답: {latest_assistant}")
    if isinstance(ai_meta, dict):
        severity_level = ai_meta.get("severity_level")
        action_pattern = ai_meta.get("action_pattern")
        if severity_level not in (None, ""):
            signal_lines.append(f"- severity_level: {severity_level}")
        if action_pattern:
            signal_lines.append(f"- action_pattern: {action_pattern}")
        for key in ("step1", "step2", "step3"):
            value = _normalize_text(judgment_steps.get(key, ""))
            if value:
                signal_lines.append(f"- {key}: {value}")

    recent_history = _serialize_recent_history_for_summary(history)
    return (
        "보관함 카드에 표시할 한국어 요약을 만드세요.\n"
        "반드시 2문장 구조로 쓰세요.\n"
        "첫 번째 문장 형식: '[제품명] [에러코드(있으면)] [구체적 증상/원인]으로 문의주셨어요.'\n"
        "  - 에러코드가 있으면 반드시 포함 (예: 'UE 에러코드', 'E1 오류')\n"
        "  - 제품명 + 증상을 구체적으로 (예: '세탁기 편심 탈수', '냉장고 컴프레서 소음', '에어컨 냉방 불량')\n"
        "  - 원인이 있으면: '[원인] 원인으로 문의주셨어요.'\n"
        "  - 원인 없으면 증상: '[제품] [증상]으로 문의주셨어요.'\n"
        "두 번째 문장 규칙:\n"
        "  - AS 신청 → 'AS 신청이 완료되었어요.'\n"
        "  - 출장 서비스 예약 → '출장 서비스 예약을 완료했어요.'\n"
        "  - 상담사 연결 → '상담사 연결을 완료했어요.'\n"
        "  - 자가해결 안내 → '자가해결 방안을 안내드렸어요.'\n"
        "라벨형 표현, 마크다운, 따옴표 사용 금지.\n"
        f"추정 원인: {preferred_cause or '미상'}\n"
        f"핵심 조치: {preferred_action or '미상'}\n"
        "반드시 JSON만 출력하세요. 형식: {\"summary\":\"요약\"}\n\n"
        "예시 1:\n"
        "{\"summary\":\"세탁기 UE 에러코드 편심 탈수 원인으로 문의주셨어요. 자가해결 방안을 안내드렸어요.\"}\n"
        "예시 2:\n"
        "{\"summary\":\"냉장고 컴프레서 소음으로 문의주셨어요. 출장 서비스 예약을 완료했어요.\"}\n"
        "예시 3:\n"
        "{\"summary\":\"에어컨 E1 에러코드 냉매 부족 원인으로 문의주셨어요. AS 신청이 완료되었어요.\"}\n\n"
        "구조화 단서:\n"
        f"{chr(10).join(signal_lines)}\n\n"
        "최근 대화:\n"
        f"{recent_history or '없음'}"
    )


def _generate_archive_summary_via_ai(
    history: Sequence[Dict[str, str]],
    latest_user: str,
    latest_assistant: str,
    signals: _ArchiveSignals,
    *,
    routing_intent: str,
    routing_required: bool,
    ai_meta: Optional[Dict[str, Any]],
) -> str:
    if OpenAI is None or not os.getenv("OPENAI_API_KEY"):
        return ""

    prompt = _build_archive_summary_prompt(
        history,
        latest_user,
        latest_assistant,
        signals,
        routing_intent=routing_intent,
        routing_required=routing_required,
        ai_meta=ai_meta,
    )

    try:
        response = OpenAI().responses.create(
            model=_resolve_openai_model(ARCHIVE_SUMMARY_MODEL),
            input=prompt,
            max_output_tokens=180,
        )
    except Exception:
        return ""

    raw_output = _extract_openai_response_text(response)
    parsed = _try_parse_json_object(raw_output)
    summary = parsed.get("summary", "") if isinstance(parsed, dict) else ""
    if isinstance(summary, str) and summary.strip():
        return _normalize_archive_summary_output(summary)
    return _normalize_archive_summary_output(raw_output)


def _dedupe_phrases(phrases: Sequence[str]) -> List[str]:
    items: List[str] = []
    seen = set()
    for phrase in phrases:
        cleaned = _normalize_text(phrase)
        if not cleaned:
            continue
        key = cleaned.replace(" ", "")
        if key in seen:
            continue
        seen.add(key)
        items.append(cleaned)
    return items


def _build_archive_cause_line(
    signals: _ArchiveSignals,
    issue_subject: str,
    latest_user: str,
) -> str:
    diagnosis_text = _trim_phrase(signals.diagnosis)
    if diagnosis_text and (
        _has_resolved_keyword(diagnosis_text)
        or _looks_like_service_only_request(diagnosis_text)
    ):
        diagnosis_text = ""
    if diagnosis_text:
        return _ensure_sentence(f"원인: {diagnosis_text}")
    if signals.resolved and _has_resolved_keyword(latest_user):
        return ""
    if latest_user and _looks_like_service_only_request(latest_user):
        return ""
    if issue_subject:
        return _ensure_sentence(f"증상: {issue_subject}")
    if latest_user:
        return _ensure_sentence(f"증상: {_truncate(_trim_phrase(latest_user), 42)}")
    return ""


def _build_archive_action_line(signals: _ArchiveSignals) -> str:
    action_text = _trim_phrase(signals.action)

    if signals.resolved:
        if action_text and action_text != "AS 신청":
            return _ensure_sentence(f"조치: {action_text} 안내 후 해결")
        return "조치: 안내 후 해결."

    action_parts: List[str] = []
    if action_text and action_text != "AS 신청":
        action_parts.append(f"{action_text} 안내")

    service_action = {
        "AS 접수 안내": "AS 접수 안내",
        "방문 예약 안내": "방문 예약 안내",
        "방문 예약 완료": "방문 예약 완료",
        "상담사 연결 안내": "상담사 연결 안내",
    }.get(signals.service_status, "")
    if service_action:
        action_parts.append(service_action)

    deduped = _dedupe_phrases(action_parts)
    if deduped:
        return _ensure_sentence(f"조치: {', '.join(deduped)}")

    if signals.diagnosis:
        return "조치: 추가 점검 필요."
    return ""



def _extract_cause_phrase(diagnosis_text: str) -> str:
    """진단 텍스트에서 핵심 원인 구절을 추출합니다."""
    cleaned = _trim_phrase(_strip_internal_summary_heading(diagnosis_text))
    if not cleaned:
        return ""
    cleaned = re.sub(r"^원인[은는이가]?\s*", "", cleaned)
    explicit_reason_patterns = (
        r"^(.+?)[이가]\s*원인으로\s*보입니다[.]?$",
        r"^(.+?)[이가]\s*원인으로\s*보여요[.]?$",
        r"^(.+?)[이가]\s*원인으로\s*추정됩니다[.]?$",
        r"^(.+?)[이가]\s*원인으로\s*의심됩니다[.]?$",
    )
    for pattern in explicit_reason_patterns:
        match = re.match(pattern, cleaned)
        if match:
            return _trim_phrase(match.group(1))
    # 이미 완성 문장이면 그대로 반환
    completed_endings = ("요.", "요", "어요.", "어요", "이에요.", "이에요", "있어요.", "있어요", "았어요.", "았어요", "니다.", "니다")
    for ending in completed_endings:
        if cleaned.endswith(ending):
            return ""
    return _trim_phrase(cleaned)


def _build_archive_lead_sentence(
    signals: _ArchiveSignals,
    issue_subject: str,
    latest_user: str,
) -> str:
    # 에러코드 + 제품 접두어 조합
    prefix_parts = []
    if signals.device:
        prefix_parts.append(signals.device)
    if signals.error_code:
        prefix_parts.append(f"{signals.error_code} 에러코드")
    prefix = " ".join(prefix_parts)

    # 진단(원인)이 있으면 "[제품] [에러코드] [원인] 원인으로 문의주셨어요."
    cause = _extract_cause_phrase(signals.diagnosis) if signals.diagnosis else ""
    if cause:
        subject = f"{prefix} {cause}".strip() if prefix else cause
        return f"{subject} 원인으로 문의주셨어요."

    if issue_subject and not _looks_like_service_only_request(issue_subject):
        subject = issue_subject
        if signals.error_code and signals.error_code not in issue_subject:
            subject = f"{signals.error_code} 에러코드 {issue_subject}".strip()
        return f"{subject}으로 문의주셨어요."

    if signals.service_status == "AS 접수 안내":
        return f"{prefix} AS 관련 문의를 주셨어요.".strip()
    if signals.service_status in ("방문 예약 안내", "방문 예약 완료"):
        return f"{prefix} 방문 예약 관련 문의를 주셨어요.".strip()
    if signals.service_status == "상담사 연결 안내":
        return "상담사 연결 관련 문의를 주셨어요."

    if latest_user:
        user_text = _truncate(_trim_phrase(latest_user), 36)
        subject = f"{prefix} {user_text}".strip() if prefix else user_text
        return f"{subject}으로 문의주셨어요."
    return ""


def _build_archive_result_sentence(signals: _ArchiveSignals) -> str:
    if signals.service_status == "AS 접수 안내":
        return "AS를 신청했다면 신청완료되었어요."
    if signals.service_status in ("방문 예약 안내", "방문 예약 완료"):
        return "출장 서비스 예약을 완료했어요."
    if signals.service_status == "상담사 연결 안내":
        return "상담사 연결을 완료했어요."

    return "자가해결 방안 안내드렸어요."


def _build_archive_narrative_summary(
    signals: _ArchiveSignals,
    issue_subject: str,
    latest_user: str,
    latest_assistant: str,
) -> str:
    lead_sentence = _build_archive_lead_sentence(signals, issue_subject, latest_user)
    result_sentence = _build_archive_result_sentence(signals)

    compact_summary = " ".join(part for part in (lead_sentence, result_sentence) if part)
    if compact_summary:
        # "as" 소문자를 "AS"로 정정 (AS 신청, AS 접수 등)
        compact_summary = re.sub(r"\bas\b", "AS", compact_summary, flags=re.IGNORECASE)
        return _truncate(compact_summary, 180)

    symptom = _extract_first_sentence(latest_assistant)
    if symptom:
        return _truncate(f"{_trim_phrase(symptom)} 관련 안내를 드렸어요.", 140)
    if latest_user:
        return _truncate(f"{_trim_phrase(latest_user)} 관련 안내를 드렸어요.", 140)
    return ""


def _generate_archive_title_via_ai(
    history: Sequence[Dict[str, str]],
    latest_user: str,
    latest_assistant: str,
    signals: _ArchiveSignals,
) -> str:
    """전체 대화 맥락을 보고 자연스러운 채팅 제목을 AI로 생성합니다."""
    if OpenAI is None or not os.getenv("OPENAI_API_KEY"):
        return ""

    recent_history = _serialize_recent_history_for_summary(history)
    prompt = (
        "아래 대화를 읽고 채팅 보관함에 표시할 제목을 한 줄로 만들어주세요.\n"
        "조건:\n"
        "- 15자 이내의 짧고 명확한 제목\n"
        "- 제품명 + 핵심 증상 또는 조치를 담을 것 (예: '냉장고 이상소음', '세탁기 누수 AS 신청')\n"
        "- AS 신청이면 '~AS 신청', 방문예약이면 '~방문예약', 상담사 연결이면 '~상담 연결'로 끝낼 것\n"
        "- 말줄임표, 마크다운, 따옴표 사용 금지\n"
        f"- 처리 결과: {signals.service_status or '일반 상담'}\n"
        "반드시 JSON만 출력. 형식: {\"title\":\"제목\"}\n\n"
        "예시:\n"
        "{\"title\":\"냉장고 이상소음 진단\"}\n"
        "{\"title\":\"세탁기 진동 AS 신청\"}\n"
        "{\"title\":\"에어컨 냉방불량\"}\n"
        "{\"title\":\"냉장고 냉각불량 방문예약\"}\n\n"
        f"최근 대화:\n{recent_history or '없음'}"
    )

    try:
        response = OpenAI().responses.create(
            model=_resolve_openai_model(ARCHIVE_SUMMARY_MODEL),
            input=prompt,
            max_output_tokens=60,
        )
    except Exception:
        return ""

    raw_output = _extract_openai_response_text(response)
    parsed = _try_parse_json_object(raw_output)
    title = parsed.get("title", "") if isinstance(parsed, dict) else ""
    if isinstance(title, str) and title.strip():
        return _truncate(title.strip(), 36)
    return ""


def _build_archive_title(
    history: Sequence[Dict[str, str]],
    latest_user: str,
    latest_assistant: str,
    attachment_name: str,
    *,
    routing_intent: str,
    routing_required: bool,
) -> str:
    signals = _collect_archive_signals(
        history,
        latest_user,
        latest_assistant,
        attachment_name,
        routing_intent=routing_intent,
        routing_required=routing_required,
    )

    # AI로 전체 맥락 기반 제목 생성 (우선)
    ai_title = _generate_archive_title_via_ai(history, latest_user, latest_assistant, signals)
    if ai_title:
        return ai_title

    # 폴백: 키워드 기반
    issue_subject = _build_issue_subject(signals.issue, signals.device)
    if signals.device and signals.error_code:
        return f"{signals.device} {signals.error_code} 오류 상담"
    if signals.error_code:
        return f"{signals.error_code} 오류 상담"
    if issue_subject:
        if "방문 예약" in signals.service_status:
            return _truncate(f"{issue_subject} 방문예약", 36)
        if "상담사 연결" in signals.service_status:
            return _truncate(f"{issue_subject} 상담 연결", 36)
        if "AS 접수" in signals.service_status:
            return _truncate(f"{issue_subject} AS 신청", 36)
        if signals.resolved:
            return _truncate(f"{issue_subject} 해결", 36)
        return _truncate(f"{issue_subject} 상담", 36)
    if "방문 예약" in signals.service_status:
        return "방문예약 요청"
    if "상담사 연결" in signals.service_status:
        return "상담사 연결 요청"
    if "AS 접수" in signals.service_status:
        return "AS 신청"
    if latest_user:
        return _truncate(latest_user, 36)
    if attachment_name:
        return _truncate(f"{attachment_name} 진단", 36)
    return "새 채팅"


def _build_archive_summary(
    history: Sequence[Dict[str, str]],
    latest_user: str,
    latest_assistant: str,
    *,
    routing_intent: str,
    routing_required: bool,
    ai_meta: Optional[Dict[str, Any]],
) -> str:
    """보관함 카드에 노출할 자연스러운 문장형 요약을 생성합니다."""
    signals = _collect_archive_signals(
        history,
        latest_user,
        latest_assistant,
        "",
        routing_intent=routing_intent,
        routing_required=routing_required,
    )

    issue_subject = _build_issue_subject(signals.issue, signals.device)
    narrative_summary = _build_archive_narrative_summary(
        signals,
        issue_subject,
        latest_user,
        latest_assistant,
    )
    if narrative_summary:
        return narrative_summary

    ai_summary = _generate_archive_summary_via_ai(
        history,
        latest_user,
        latest_assistant,
        signals,
        routing_intent=routing_intent,
        routing_required=routing_required,
        ai_meta=ai_meta,
    )
    if ai_summary:
        return ai_summary

    symptom = _extract_first_sentence(latest_assistant)
    if symptom:
        return _truncate(f"{_trim_phrase(symptom)} 관련 안내를 드렸어요.", 140)
    if latest_user:
        return _truncate(f"{_trim_phrase(latest_user)} 관련 안내를 드렸어요.", 140)
    return "안내를 도와드렸어요."


def build_title_and_summary(
    history: Sequence[Dict[str, str]],
    *,
    routing_intent: str = "normal_chat",
    routing_required: bool = False,
    ai_meta: Optional[Dict[str, Any]] = None,
) -> tuple[str, str]:
    """Build a short archive title and one-line summary from the conversation."""
    latest_user = _extract_latest_user_text(history)
    latest_assistant = _extract_latest_assistant_text(history)
    attachment_name = _extract_latest_user_attachment_name(history)

    return (
        _build_archive_title(
            history,
            latest_user,
            latest_assistant,
            attachment_name,
            routing_intent=routing_intent,
            routing_required=routing_required,
        ),
        _build_archive_summary(
            history,
            latest_user,
            latest_assistant,
            routing_intent=routing_intent,
            routing_required=routing_required,
            ai_meta=ai_meta,
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
        ai_meta=ai_meta,
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
