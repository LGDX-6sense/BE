"""
AI Agent Loop — ReAct 패턴 (생각 → 행동 → 관찰 → 생각)

도구 목록:
  1. analyze_image          — 이미지에서 증상/에러코드/부품 상태 분석
  2. analyze_audio          — 소음 녹음에서 이상음 유형 분석
  3. search_knowledge_base  — Pinecone 벡터 검색 (폴백: Supabase 렉시컬)
  4. ask_user_question      — 진단에 필요한 추가 정보 요청
  5. initiate_as_booking    — AS 예약 트리거
  6. connect_human_agent    — 상담사 연결 트리거
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import re
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

try:
    from openai import OpenAI, AsyncOpenAI
except ImportError:
    OpenAI = None
    AsyncOpenAI = None


# ── 도구 정의 ────────────────────────────────────────────────────────────────

TOOL_DEFINITIONS: List[Dict[str, Any]] = [
    {
        "type": "function",
        "function": {
            "name": "analyze_image",
            "description": (
                "사용자가 업로드한 가전제품 이미지를 분석합니다. "
                "눈에 보이는 문제, 에러코드, 부품 상태를 파악합니다. "
                "이미지가 첨부된 경우 진단 초반에 반드시 호출하세요."
            ),
            "parameters": {
                "type": "object",
                "properties": {},
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "analyze_audio",
            "description": (
                "사용자가 녹음한 가전제품 소음/작동음을 분석합니다. "
                "이상 소음의 유형과 제품, 상태를 파악합니다. "
                "소음 녹음이 첨부된 경우 진단 초반에 반드시 호출하세요."
            ),
            "parameters": {
                "type": "object",
                "properties": {},
                "required": [],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "search_knowledge_base",
            "description": (
                "LG 가전 지원 데이터베이스에서 관련 정보를 검색합니다. "
                "증상, 에러코드, 제품 관련 정보가 필요할 때 호출하세요. "
                "검색 결과를 바탕으로 사용자에게 답변을 생성합니다."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "검색할 증상, 에러코드 또는 키워드 (한국어)",
                    },
                    "device_hint": {
                        "type": "string",
                        "enum": ["refrigerator", "washing_machine", "air_conditioner", "unknown"],
                        "description": "제품 종류 힌트",
                    },
                },
                "required": ["query"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "ask_user_question",
            "description": (
                "진단에 필요한 정보가 부족할 때 사용자에게 한 가지 추가 질문을 합니다. "
                "모델명, 에러코드, 증상 상세 정보 등이 필요할 때 사용하세요. "
                "반드시 한 가지 질문만 하세요."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "question": {
                        "type": "string",
                        "description": "사용자에게 물어볼 질문 (한국어, 1문장)",
                    },
                },
                "required": ["question"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "initiate_as_booking",
            "description": (
                "내부 부품 손상, 전기 계통, 냉매 문제 등 전문가 수리가 필요한 경우 "
                "AS 방문 서비스 예약을 시작합니다. "
                "자가점검 없이도 명확히 전문가가 필요한 상황이면 즉시 호출하세요."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "reason": {
                        "type": "string",
                        "description": (
                            "발견된 증상, 예상 원인, AS가 필요한 이유를 포함한 전체 진단 내용 (한국어)"
                        ),
                    },
                },
                "required": ["reason"],
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "connect_human_agent",
            "description": (
                "사용자가 상담사 연결을 원하거나 AI가 해결하기 어려운 복잡한 문제일 때 사용합니다."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "reason": {
                        "type": "string",
                        "description": "상담사 연결 이유",
                    },
                },
                "required": ["reason"],
            },
        },
    },
]

# 호출 시 루프를 즉시 종료하는 도구들
_TERMINAL_TOOLS = {"ask_user_question", "initiate_as_booking", "connect_human_agent"}


# ── 결과 데이터 클래스 ────────────────────────────────────────────────────────

@dataclass
class AgentStep:
    iteration: int
    action: str          # 도구 이름 또는 "final_response"
    detail: str = ""     # 검색 쿼리, 질문 내용 등


@dataclass
class AgentLoopResult:
    final_response: str
    triggered_action: Optional[str] = None   # "initiate_as_booking" | "connect_human_agent" | None
    triggered_reason: str = ""
    steps: List[AgentStep] = field(default_factory=list)
    image_paths: List[str] = field(default_factory=list)
    severity_level: Optional[int] = None     # 1(자가해결) 2(재확인) 3(전문가) 4(긴급)
    action_pattern: Optional[str] = None     # "A" | "B" | "C" | "D"
    confidence: Optional[str] = None         # "high" | "medium" | "low"
    judgment_steps: Dict[str, str] = field(default_factory=dict)  # step1/2/3 요약


# ── 메타 블록 파싱 ───────────────────────────────────────────────────────────

import re as _re

def _parse_agent_meta(text: str) -> tuple[str, dict]:
    """[[AGENT_META]]...[[/AGENT_META]] 블록을 파싱하고 제거된 텍스트를 반환."""
    pattern = r'\[\[AGENT_META\]\](.*?)\[\[/AGENT_META\]\]'
    match = _re.search(pattern, text, _re.DOTALL)
    if not match:
        return text, {}
    meta_json = match.group(1).strip()
    cleaned = (text[:match.start()].rstrip() + text[match.end():]).strip()
    try:
        meta = json.loads(meta_json)
    except json.JSONDecodeError:
        meta = {}
    return cleaned, meta


# ── 도구 실행 ────────────────────────────────────────────────────────────────

def _execute_analyze_image(image_path: str, user_text: str = "") -> str:
    """analyze_image 도구 실행 — 이미지에서 증상/에러코드/부품 상태 추출."""
    if not image_path:
        return "이미지가 제공되지 않았습니다."
    try:
        from multimodal_agent import analyze_image
        ev = analyze_image(image_path, user_text=user_text)
        return (
            f"이미지 분석 결과:\n"
            f"- 기기: {ev.device_hint}\n"
            f"- 눈에 보이는 문제: {ev.visible_issue}\n"
            f"- 에러코드: {', '.join(ev.error_codes) or '없음'}\n"
            f"- 확인된 부품: {', '.join(ev.visible_components) or '없음'}\n"
            f"- 요약: {ev.summary}\n"
            f"- 신뢰도: {ev.confidence}"
        )
    except Exception as e:
        return f"이미지 분석 오류: {e}"


def _execute_analyze_audio(audio_path: str) -> str:
    """analyze_audio 도구 실행 — 소음 유형/제품/상태 분류."""
    if not audio_path:
        return "소음 녹음이 제공되지 않았습니다."
    try:
        from multimodal_agent import build_audio_evidence
        ev = build_audio_evidence(audio_path)
        return (
            f"소음 분석 결과:\n"
            f"- 제품: {ev.product_label}\n"
            f"- 상태: {ev.status_label}\n"
            f"- 소리 유형: {ev.detail_label}\n"
            f"- 신뢰도: {ev.detail_confidence:.1%}\n"
            f"- 기기: {ev.device}"
        )
    except Exception as e:
        return f"소음 분석 오류: {e}"


def _execute_search(query: str, device_hint: str = "unknown") -> tuple[str, List[str]]:
    """search_knowledge_base 도구 실행 — Pinecone 벡터 검색 우선, Supabase 폴백."""

    # ── 1차: Pinecone 벡터 검색 ──────────────────────────────────────────────
    pinecone_api_key = os.getenv("PINECONE_API_KEY", "")
    pinecone_index   = os.getenv("PINECONE_INDEX_NAME", "lg-support")
    supabase_url     = os.getenv("SUPABASE_URL", "").rstrip("/")
    bucket           = "support-images"

    if pinecone_api_key and OpenAI is not None:
        try:
            from pinecone import Pinecone as _PC
            oai   = OpenAI()
            emb   = oai.embeddings.create(model="text-embedding-3-small", input=[query]).data[0].embedding
            pc    = _PC(api_key=pinecone_api_key)
            index = pc.Index(pinecone_index)

            search_filter = {"device": {"$eq": device_hint}} if device_hint and device_hint != "unknown" else None
            matches = index.query(
                vector=emb,
                top_k=3,
                include_metadata=True,
                **({"filter": search_filter} if search_filter else {}),
            ).get("matches", [])
            if not matches and search_filter:
                matches = index.query(vector=emb, top_k=3, include_metadata=True).get("matches", [])

            if matches:
                texts: List[str] = []
                image_paths: List[str] = []
                for m in matches:
                    meta    = m.get("metadata", {})
                    content = str(meta.get("content_chunk", ""))
                    if content:
                        texts.append(content[:800])

                    if len(image_paths) < 8:
                        meta_device = meta.get("device", "")
                        if (
                            device_hint
                            and device_hint != "unknown"
                            and meta_device
                            and meta_device != device_hint
                        ):
                            continue
                        raw = meta.get("image_urls", "")
                        filenames: List[str] = json.loads(raw) if raw else []
                        need = 8 - len(image_paths)
                        if filenames:
                            try:
                                from supabase import create_client as _sc
                                _sb = _sc(supabase_url, os.getenv("SUPABASE_SERVICE_ROLE_KEY", ""))
                                _res = _sb.table("support_document_images").select("filename, public_url").in_("filename", filenames[:need]).execute()
                                _url_map = {r["filename"]: r["public_url"] for r in (_res.data or []) if r.get("public_url")}
                                for fname in filenames[:need]:
                                    url = _url_map.get(fname)
                                    if url and url not in image_paths:
                                        image_paths.append(url)
                            except Exception as _e:
                                logger.warning("DB 이미지 URL 조회 실패: %s", _e)
                        # fallback: http URL이면 그대로 사용
                        for fname in filenames[:need]:
                            if fname.startswith("http") and fname not in image_paths:
                                image_paths.append(fname)

                return "\n\n---\n\n".join(texts), image_paths
        except Exception as _e:
            logger.warning("Pinecone 검색 실패, Supabase 폴백: %s", _e)

    # ── 2차: Supabase 렉시컬 검색 (폴백) ────────────────────────────────────
    try:
        from supabase_store import retrieve_chunks_from_supabase
        tokens = [t for t in query.split() if len(t) > 1]
        rows = retrieve_chunks_from_supabase(
            query_tokens=tokens,
            device_hint=device_hint,
            top_k=3,
        )
        if not rows:
            return "관련 정보를 찾지 못했습니다.", []

        texts = []
        image_paths = []
        for row in rows:
            content = str(row.get("content_chunk") or row.get("retrieval_text") or "")
            if content:
                texts.append(content[:800])
            for url in row.get("_image_public_urls", []):
                if url and url not in image_paths and len(image_paths) < 8:
                    image_paths.append(url)

        return "\n\n---\n\n".join(texts), image_paths
    except Exception as e:
        return f"검색 오류: {e}", []


# ── Vision 이미지 디바이스 검증 ───────────────────────────────────────────────

_DEVICE_KO = {
    "refrigerator": "냉장고",
    "washing_machine": "세탁기",
    "air_conditioner": "에어컨",
}


async def _validate_images_by_device(
    image_urls: List[str],
    device_hint: str,
    client: "AsyncOpenAI",
) -> List[str]:
    """GPT-4o-mini vision으로 device_hint와 맞지 않는 이미지를 제거한다."""
    if not image_urls or device_hint == "unknown":
        return image_urls

    device_ko = _DEVICE_KO.get(device_hint, device_hint)
    vision_model = os.getenv("OPENAI_VISION_MODEL", "gpt-4o-mini")

    content: List[Any] = [
        {
            "type": "text",
            "text": (
                f"아래 이미지 중 '{device_ko}' 가 포함된 이미지의 번호를 JSON 배열로만 답하세요. "
                f"예: [1, 3]. 해당 없으면 []."
            ),
        }
    ]
    for index, url in enumerate(image_urls, 1):
        content.append({"type": "text", "text": f"이미지{index}:"})
        content.append({"type": "image_url", "image_url": {"url": url, "detail": "low"}})

    try:
        response = await client.chat.completions.create(
            model=vision_model,
            messages=[{"role": "user", "content": content}],
            max_tokens=60,
        )
        raw = (response.choices[0].message.content or "").strip()
        match = re.search(r"\[.*?\]", raw, re.DOTALL)
        if match:
            indices = json.loads(match.group())
            filtered = [
                image_urls[index - 1]
                for index in indices
                if isinstance(index, int) and 1 <= index <= len(image_urls)
            ]
            if filtered:
                return filtered
    except Exception as error:
        logger.warning("이미지 디바이스 검증 실패, 원본 반환: %s", error)

    return image_urls


# ── 이미지 ↔ 텍스트 매핑 (GPT-4o vision) ────────────────────────────────────

def _match_images_to_text(text: str, image_urls: List[str], client) -> str:
    """GPT-4o-mini vision으로 이미지를 텍스트 단계에 맞게 [이미지N] 마커로 삽입.

    번호 단계가 없거나 이미지가 없으면 원본 텍스트를 그대로 반환.
    vision API 실패 시에도 원본 텍스트 반환(안전 폴백).
    """
    if not image_urls or not text:
        return text
    # 단일 짧은 문장이면 vision 매핑 불필요 (번호 단계 또는 줄바꿈 없음)
    has_numbered = re.search(r'\d+[.)]\s|\d+단계', text)
    has_paragraphs = text.count('\n') >= 2
    if not has_numbered and not has_paragraphs:
        return text

    vision_model = os.getenv("OPENAI_VISION_MODEL", "gpt-4o-mini")

    content: List[Any] = [
        {
            "type": "text",
            "text": (
                "아래 텍스트의 각 단계에 이미지를 배치해주세요.\n\n"
                "규칙:\n"
                "- 가능한 한 많은 이미지를 활용해 각 단계 바로 뒤에 [이미지N] 형식으로 삽입\n"
                "- N은 1부터 시작하는 이미지 번호 (이미지1, 이미지2 ... 순서 유지)\n"
                "- 하나의 단계에 여러 이미지가 관련되면 모두 삽입 가능\n"
                "- 텍스트 단계가 없는 이미지는 텍스트 맨 끝에 배치\n"
                "- 텍스트 내용·표현은 절대 수정하지 말 것, 마커만 삽입\n\n"
                f"텍스트:\n{text}"
            ),
        }
    ]

    for i, url in enumerate(image_urls[:8], 1):
        content.append({"type": "text", "text": f"\n이미지{i}:"})
        content.append({"type": "image_url", "image_url": {"url": url, "detail": "low"}})

    try:
        resp = client.chat.completions.create(
            model=vision_model,
            messages=[{"role": "user", "content": content}],
            max_tokens=2000,
        )
        result = (resp.choices[0].message.content or "").strip()
        # 원본 텍스트 길이의 50% 미만이면 손상된 것으로 판단 → 원본 반환
        if len(result) < len(text) * 0.5:
            return text
        return result
    except Exception as _e:
        logger.warning("vision 이미지 매핑 실패, 원본 텍스트 반환: %s", _e)
        return text


# ── 메인 에이전트 루프 ────────────────────────────────────────────────────────

async def run_agent_loop(
    user_text: str,
    user_name: str = "",
    device_hint: str = "unknown",
    image_path: str = "",
    audio_path: str = "",
    image_summary: str = "",   # 하위 호환성 유지
    audio_summary: str = "",   # 하위 호환성 유지
    max_iterations: int = 6,
    user_profile_context: str = "",
) -> AgentLoopResult:
    """
    ReAct 루프: 생각 → 행동(도구) → 관찰 → 생각 → ... → 최종 답변

    Returns AgentLoopResult with final_response and metadata.
    """
    if AsyncOpenAI is None:
        return AgentLoopResult(final_response="OpenAI 패키지가 설치되지 않았습니다.")

    client = AsyncOpenAI()
    display_name = user_name.strip() or "고객"
    model = os.getenv("OPENAI_AGENT_MODEL", "gpt-4.1-mini")

    _has_image = bool(image_path)
    _has_audio = bool(audio_path)

    system_prompt = f"""당신은 LG전자 가전제품 AS 전문 AI 에이전트입니다. 이름: 레보(Rebo). 고객 이름: {display_name}.

## 필수 3단계 판단 프로세스

모든 진단 응답은 아래 3단계를 반드시 순서대로 거쳐야 합니다.

### 1단계: 증상 분류
- 이미지가 첨부된 경우 → **analyze_image를 먼저 호출**하여 증상을 파악하세요.
- 소음 녹음이 첨부된 경우 → **analyze_audio를 먼저 호출**하여 소음 유형을 파악하세요.
- 그 다음 search_knowledge_base로 증상/에러코드를 검색하세요.
- 제품군(냉장고/세탁기/에어컨)과 증상 유형을 파악하세요.
  (유형: 작동불가/성능저하/이상소음/이상진동/누수누출/오류코드/외관손상/냄새위생/동결)
- 정보가 부족하면 ask_user_question으로 아래 우선순위에 따라 가장 중요한 한 가지만 질문하세요:
  1순위) 언제부터 발생했나요? (갑자기/서서히, 며칠 전/몇 주 전)
  2순위) 항상 발생하나요, 아니면 특정 상황에서만 발생하나요?
  3순위) 특정 기능 사용 중/후에만 발생하나요? (예: 세탁 중, 냉동실 열 때)

### 2단계: 원인 분석
- 검색 결과를 바탕으로 가장 가능성 높은 원인 1-2가지를 추론하세요.
- 원인의 복잡성과 위험도를 평가하세요.

### 3단계: 심각도 판단 + 행동 패턴 결정

심각도 레벨 기준:
- 레벨 1 🟢 (자가해결): 필터 청소, 재시작, 설정 조정 등 사용자가 안전하게 직접 처리 가능
- 레벨 2 🟡 (확인 필요): 자가점검 후 개선 여부 확인 필요, 미해결 시 전문가 권장
- 레벨 3 🔴 (전문가 필요): 내부 부품 손상, 전기 계통, 냉매 누출 등 전문 수리 필요
- 레벨 4 🚨 (긴급): 화재 위험, 감전 위험, 가스 누출 등 즉각 사용 중단 필요

행동 패턴:
- A패턴 (레벨 1): 단계별 자가 해결 가이드 제공 (최대 5단계)
- B패턴 (레벨 2): 자가점검 가이드 제공 후 반드시 마지막 문장에 "이 방법을 시도해보신 후 결과를 알려주세요. 해결되지 않으면 전문가 수리가 필요할 수 있어요." 로 마무리하세요.
- C패턴 (레벨 3): 간략한 원인 설명 후 initiate_as_booking 반드시 호출
- D패턴 (레벨 4): 즉시 사용 중단 + 안전 조치 안내 후 connect_human_agent 반드시 호출

## 응답 규칙
1. 최종 답변은 쉬운 한국어로, 번호 단계를 포함해 작성하세요.
2. URL, 링크, 마크다운(볼드 제외)은 사용하지 마세요.
3. 답변 첫 문장은 반드시 '**{display_name}님의 문제를 진단해봤어요!**'로 시작하세요.
4. 레벨 1-2 답변: 첫 줄에 심각도 표시를 포함하세요. (예: 🟢 자가 해결 가능 / 🟡 확인 필요)
5. 레벨 3: initiate_as_booking을 반드시 호출하세요.
6. 레벨 4: connect_human_agent를 반드시 호출하세요. 답변에 ⚠️ 안전 경고를 포함하세요.
7. 레벨 1-2 답변 마지막에 진단 신뢰도를 한 줄로 표시하세요:
   - 충분한 정보(이미지/오디오/에러코드/모델명)가 있을 때 → 🔵 진단 신뢰도: 높음
   - 증상 설명만 있고 추가 정보가 없을 때 → 🟡 진단 신뢰도: 보통 (모델명/사진 제공 시 더 정확해요)
   - 정보가 매우 부족하거나 증상이 모호할 때 → ⚪ 진단 신뢰도: 낮음 (추가 정보가 필요해요)
8. 모든 최종 답변(finish_reason=stop) 끝에 반드시 아래 메타 블록을 추가하세요 (사용자에게 표시되지 않음):

[[AGENT_META]]
{{"severity_level": <1|2|3|4>, "action_pattern": "<A|B|C|D>", "confidence": "<high|medium|low>", "step1": "<증상 분류 요약>", "step2": "<원인 분석 요약>", "step3": "<심각도 판단 근거>"}}
[[/AGENT_META]]
"""

    system_prompt += """

## 대화 연속성 규칙
- 최근 대화에 이미 진단 내용이나 증상 설명이 있고, 최신 메시지가 더 자세한 설명, 쉬운 설명, 반복 설명, 이전 답변의 의미를 묻는 경우 → 같은 문제의 연속으로 처리하세요.
- 그 경우 새로운 접수 흐름을 시작하지 말고 이전 답변을 이어서 진행하세요.
- 최근 대화나 고객 프로필에 이미 있는 제품, 증상, 모델 정보는 재활용하세요.
- 모델명이나 제품 정보가 진짜 없고 반드시 필요할 때만 다시 물어보세요.

## B패턴 후속 처리 규칙
- 이전 응답이 B패턴(레벨 2)이었고 고객이 자가점검 결과를 알려온 경우:
  - "해결됐어요" / "됐어요" / "괜찮아졌어요" 등 → 🟢 해결 축하 메시지 + 추가 이상 시 재문의 안내
  - "안 됐어요" / "그대로예요" / "여전해요" 등 → 레벨 3으로 상향, initiate_as_booking 호출
"""

    # 유저 프로필 정보가 있으면 system prompt에 추가
    if user_profile_context:
        system_prompt += f"\n\n## 고객 정보 (DB 등록 정보)\n{user_profile_context}\n"
        system_prompt += (
            "search_knowledge_base 호출 시 등록된 제품의 모델번호(model_no)를 쿼리에 반드시 포함하세요. "
            "예: '냉장고 드드득 소리 F873SS55E'. 모델번호가 있으면 일반 검색보다 훨씬 정확한 결과를 얻을 수 있습니다.\n"
            "AS 예약 시 위 주소/연락처를 활용하세요.\n"
        )

    # 사용자 메시지 구성
    user_content = user_text
    if _has_image:
        user_content += "\n[이미지가 첨부되었습니다. analyze_image 도구로 분석하세요.]"
    elif image_summary:
        user_content += f"\n[이미지 분석: {image_summary}]"
    if _has_audio:
        user_content += "\n[소음 녹음이 첨부되었습니다. analyze_audio 도구로 분석하세요.]"
    elif audio_summary:
        user_content += f"\n[음성 분석: {audio_summary}]"

    messages: List[Dict[str, Any]] = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_content},
    ]

    steps: List[AgentStep] = []
    collected_images: List[str] = []

    for iteration in range(1, max_iterations + 1):
        try:
            response = await client.chat.completions.create(
                model=model,
                messages=messages,
                tools=TOOL_DEFINITIONS,
                tool_choice="auto",
                max_tokens=900,
            )
        except Exception as e:
            return AgentLoopResult(
                final_response=f"AI 응답 생성 중 오류가 발생했습니다: {e}",
                steps=steps,
            )

        choice = response.choices[0]
        finish_reason = choice.finish_reason

        # ── 최종 텍스트 응답 ──────────────────────────────────────────────────
        if finish_reason == "stop":
            raw_text = choice.message.content or ""
            final_text, meta = _parse_agent_meta(raw_text)
            steps.append(AgentStep(iteration=iteration, action="final_response"))

            final_images = collected_images
            if collected_images and device_hint and device_hint != "unknown":
                try:
                    final_images = await _validate_images_by_device(
                        collected_images,
                        device_hint,
                        client,
                    )
                except Exception as error:
                    logger.warning("이미지 검증 실패, 원본 이미지 사용: %s", error)

            return AgentLoopResult(
                final_response=final_text,
                steps=steps,
                image_paths=final_images,
                severity_level=meta.get("severity_level"),
                action_pattern=meta.get("action_pattern"),
                confidence=meta.get("confidence"),
                judgment_steps={
                    "step1": str(meta.get("step1", "")),
                    "step2": str(meta.get("step2", "")),
                    "step3": str(meta.get("step3", "")),
                },
            )

        # ── 도구 호출 ─────────────────────────────────────────────────────────
        if finish_reason == "tool_calls":
            tool_calls = choice.message.tool_calls or []
            messages.append(choice.message)  # assistant 메시지 추가

            for tool_call in tool_calls:
                name = tool_call.function.name
                try:
                    args = json.loads(tool_call.function.arguments or "{}")
                except json.JSONDecodeError:
                    args = {}

                steps.append(AgentStep(iteration=iteration, action=name, detail=str(args)))

                # ── 종료 도구: 즉시 루프 탈출 ────────────────────────────────
                if name == "ask_user_question":
                    question = args.get("question", "추가 정보를 알려주시겠어요?")
                    return AgentLoopResult(
                        final_response=question,
                        triggered_action="ask_user_question",
                        steps=steps,
                        image_paths=collected_images,
                    )

                if name == "initiate_as_booking":
                    reason = args.get("reason", "전문가 점검이 필요합니다.")
                    return AgentLoopResult(
                        final_response=reason,
                        triggered_action="initiate_as_booking",
                        triggered_reason=reason,
                        steps=steps,
                        image_paths=collected_images,
                        severity_level=3,
                        action_pattern="C",
                    )

                if name == "connect_human_agent":
                    reason = args.get("reason", "상담사 연결을 요청합니다.")
                    _emergency_keywords = ("가스", "불꽃", "화재", "감전", "연기", "폭발", "긴급")
                    _is_emergency = any(kw in reason for kw in _emergency_keywords)
                    return AgentLoopResult(
                        final_response=reason,
                        triggered_action="connect_human_agent",
                        triggered_reason=reason,
                        steps=steps,
                        image_paths=collected_images,
                        severity_level=4 if _is_emergency else 3,
                        action_pattern="D" if _is_emergency else "C",
                    )

                # ── analyze_image 실행 ───────────────────────────────────────
                if name == "analyze_image":
                    tool_result = await asyncio.to_thread(
                        _execute_analyze_image,
                        image_path,
                        user_text,
                    )

                # ── analyze_audio 실행 ───────────────────────────────────────
                elif name == "analyze_audio":
                    tool_result = await asyncio.to_thread(
                        _execute_analyze_audio,
                        audio_path,
                    )

                # ── search_knowledge_base 실행 ────────────────────────────────
                elif name == "search_knowledge_base":
                    query = args.get("query", user_text)
                    hint = args.get("device_hint", device_hint)
                    result_text, images = await asyncio.to_thread(
                        _execute_search,
                        query,
                        hint,
                    )
                    if images:
                        for img in images:
                            if img not in collected_images:
                                collected_images.append(img)
                    tool_result = result_text
                else:
                    tool_result = f"알 수 없는 도구: {name}"

                messages.append({
                    "role": "tool",
                    "tool_call_id": tool_call.id,
                    "content": tool_result[:2000],  # 컨텍스트 크기 제한
                })

        else:
            # 예상치 못한 finish_reason
            break

    # 최대 루프 초과 시 강제 답변 생성
    try:
        fallback = await client.chat.completions.create(
            model=model,
            messages=messages + [
                {"role": "user", "content": "지금까지 수집한 정보를 바탕으로 최종 답변을 한국어로 작성해주세요."}
            ],
            max_tokens=800,
        )
        final_text = fallback.choices[0].message.content or "죄송합니다. 답변 생성에 실패했습니다."
    except Exception as _e:
        logger.error("fallback 응답 생성 실패: %s", _e)
        final_text = "죄송합니다. 일시적인 오류가 발생했습니다. 다시 시도해주세요."

    return AgentLoopResult(
        final_response=final_text,
        steps=steps,
        image_paths=collected_images,
    )
