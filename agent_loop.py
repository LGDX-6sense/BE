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

import json
import os
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

try:
    from openai import OpenAI
except ImportError:
    OpenAI = None


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
                "자가점검 후에도 문제가 해결되지 않거나 전문가 수리가 필요한 경우 "
                "AS 방문 서비스 예약을 시작합니다."
            ),
            "parameters": {
                "type": "object",
                "properties": {
                    "reason": {
                        "type": "string",
                        "description": "AS 예약을 권장하는 이유 (한국어 1-2문장)",
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
            matches = index.query(vector=emb, top_k=3, include_metadata=True).get("matches", [])

            if matches:
                texts: List[str] = []
                image_paths: List[str] = []
                for m in matches:
                    meta    = m.get("metadata", {})
                    content = str(meta.get("content_chunk", ""))
                    if content:
                        texts.append(content[:800])
                    # 이미지: DB에서 올바른 public_url 조회 (서브폴더 포함)
                    if not image_paths:
                        raw = meta.get("image_urls", "")
                        filenames: List[str] = json.loads(raw) if raw else []
                        if filenames:
                            try:
                                from supabase import create_client as _sc
                                _sb = _sc(supabase_url, os.getenv("SUPABASE_SERVICE_ROLE_KEY", ""))
                                _res = _sb.table("support_document_images").select("filename, public_url").in_("filename", filenames[:5]).execute()
                                _url_map = {r["filename"]: r["public_url"] for r in (_res.data or []) if r.get("public_url")}
                                for fname in filenames[:2]:
                                    url = _url_map.get(fname)
                                    if url:
                                        image_paths.append(url)
                            except Exception:
                                pass
                        # fallback: http URL이면 그대로 사용
                        if not image_paths:
                            for fname in filenames[:2]:
                                if fname.startswith("http"):
                                    image_paths.append(fname)

                return "\n\n---\n\n".join(texts), image_paths
        except Exception:
            pass  # Pinecone 실패 시 Supabase 폴백

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
            if not image_paths:
                image_paths = row.get("_image_public_urls", [])[:2]

        return "\n\n---\n\n".join(texts), image_paths
    except Exception as e:
        return f"검색 오류: {e}", []


# ── 메인 에이전트 루프 ────────────────────────────────────────────────────────

def run_agent_loop(
    user_text: str,
    user_name: str = "",
    device_hint: str = "unknown",
    image_path: str = "",
    audio_path: str = "",
    image_summary: str = "",   # 하위 호환성 유지
    audio_summary: str = "",   # 하위 호환성 유지
    max_iterations: int = 6,
) -> AgentLoopResult:
    """
    ReAct 루프: 생각 → 행동(도구) → 관찰 → 생각 → ... → 최종 답변

    Returns AgentLoopResult with final_response and metadata.
    """
    if OpenAI is None:
        return AgentLoopResult(final_response="OpenAI 패키지가 설치되지 않았습니다.")

    client = OpenAI()
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
- 정보가 부족하면 ask_user_question으로 한 가지만 질문하세요.

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
- B패턴 (레벨 2): 자가점검 가이드 제공 후 결과 재확인 안내
- C패턴 (레벨 3): 간략한 원인 설명 후 initiate_as_booking 반드시 호출
- D패턴 (레벨 4): 즉시 사용 중단 + 안전 조치 안내 후 connect_human_agent 반드시 호출

## 응답 규칙
1. 최종 답변은 쉬운 한국어로, 번호 단계를 포함해 작성하세요.
2. URL, 링크, 마크다운(볼드 제외)은 사용하지 마세요.
3. 답변 첫 문장은 반드시 '**{display_name}님의 문제를 진단해봤어요!**'로 시작하세요.
4. 레벨 1-2 답변: 첫 줄에 심각도 표시를 포함하세요. (예: 🟢 자가 해결 가능 / 🟡 확인 필요)
5. 레벨 3: initiate_as_booking을 반드시 호출하세요.
6. 레벨 4: connect_human_agent를 반드시 호출하세요. 답변에 ⚠️ 안전 경고를 포함하세요.
7. 모든 최종 답변(finish_reason=stop) 끝에 반드시 아래 메타 블록을 추가하세요 (사용자에게 표시되지 않음):

[[AGENT_META]]
{{"severity_level": <1|2|3|4>, "action_pattern": "<A|B|C|D>", "step1": "<증상 분류 요약>", "step2": "<원인 분석 요약>", "step3": "<심각도 판단 근거>"}}
[[/AGENT_META]]
"""

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
            response = client.chat.completions.create(
                model=model,
                messages=messages,
                tools=TOOL_DEFINITIONS,
                tool_choice="auto",
                max_tokens=1500,
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
            return AgentLoopResult(
                final_response=final_text,
                steps=steps,
                image_paths=collected_images,
                severity_level=meta.get("severity_level"),
                action_pattern=meta.get("action_pattern"),
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
                    tool_result = _execute_analyze_image(image_path, user_text)

                # ── analyze_audio 실행 ───────────────────────────────────────
                elif name == "analyze_audio":
                    tool_result = _execute_analyze_audio(audio_path)

                # ── search_knowledge_base 실행 ────────────────────────────────
                elif name == "search_knowledge_base":
                    query = args.get("query", user_text)
                    hint = args.get("device_hint", device_hint)
                    result_text, images = _execute_search(query, hint)
                    if images and not collected_images:
                        collected_images = images
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
        fallback = client.chat.completions.create(
            model=model,
            messages=messages + [
                {"role": "user", "content": "지금까지 수집한 정보를 바탕으로 최종 답변을 한국어로 작성해주세요."}
            ],
            max_tokens=800,
        )
        final_text = fallback.choices[0].message.content or "죄송합니다. 답변 생성에 실패했습니다."
    except Exception:
        final_text = "죄송합니다. 일시적인 오류가 발생했습니다. 다시 시도해주세요."

    return AgentLoopResult(
        final_response=final_text,
        steps=steps,
        image_paths=collected_images,
    )
