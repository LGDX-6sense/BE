from __future__ import annotations

import argparse
import base64
import json
import math
import mimetypes
import os
import re
from dataclasses import asdict, dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

from pipeline import PROJECT_ROOT, detect_device, first_existing_path, predict_noise

try:
    from openai import OpenAI
except ImportError:
    OpenAI = None


DEFAULT_AGENT_MODEL = os.getenv("OPENAI_AGENT_MODEL", os.getenv("OPENAI_MODEL", "gpt-4-mini"))
DEFAULT_VISION_MODEL = os.getenv("OPENAI_VISION_MODEL", "gpt-4.1-mini")
DEFAULT_RESPONSE_MODE_EMBEDDING_MODEL = os.getenv(
    "OPENAI_RESPONSE_MODE_EMBEDDING_MODEL",
    "text-embedding-3-small",
)
DEFAULT_CHUNK_PATH = first_existing_path(
    PROJECT_ROOT / "data" / "lg_solution_chunks.jsonl",
    PROJECT_ROOT / "lg_solution_chunks.jsonl",
)
DEFAULT_FULL_DOC_PATH = first_existing_path(
    PROJECT_ROOT / "data" / "lg_solution_all.json",
    PROJECT_ROOT / "lg_solution_all.json",
)
DEFAULT_TOP_K = 5

MODEL_ALIASES = {
    "gpt-4-mini": "gpt-4.1-mini",
}

DEVICE_KEYWORDS = {
    "refrigerator": ["냉장고", "김치", "냉동", "와인셀러"],
    "washing_machine": ["세탁기", "드럼세탁기", "통돌이", "워시타워"],
    "air_conditioner": ["에어컨", "시스템에어컨", "냉난방", "2in1"],
}

RETRIEVAL_STOPWORDS = {
    "lg",
    "thinq",
    "wifi",
    "app",
    "앱",
    "제품",
    "설정",
    "방법",
    "설치",
    "가입",
    "업데이트",
    "사용",
    "서비스",
    "고객",
    "지원",
    "냉장고",
    "세탁기",
    "에어컨",
    "소리",
    "나요",
}

RESPONSE_MODE_EXAMPLES = {
    "diagnosis": (
        "냉장고가 시원하지 않아요",
        "세탁기에서 이상한 소리가 나요",
        "에어컨이 작동을 안 해요",
        "에러 코드가 떠요",
        "전원이 안 켜져요",
        "물이 안 빠져요",
        "고장 난 것 같아요",
        "원인이 뭔가요",
        "수리를 받아야 하나요",
        "냄새가 나는 이유가 뭔가요",
    ),
    "conversation": (
        "고마워요",
        "감사합니다",
        "해결됐어요",
        "고쳐졌어요",
        "됐어요 감사해요",
        "문제 없어졌어요",
        "괜찮아졌어요",
        "다시 설명해줘",
        "쉽게 설명해줘",
        "요약해줘",
        "이게 무슨 뜻이야",
        "무슨 의미야",
        "정리해줘",
        "다른 방법도 알려줘",
        "사용법 알려줘",
        "기능이 뭐야",
    ),
    "diagnosis_followup": (
        "그럼 어떻게 해야 해요",
        "왜 그런 거예요",
        "그래도 안 되면 어떻게 해요",
        "다음에는 뭘 확인해야 해요",
        "이 상태면 수리 받아야 해요",
        "이후에는 뭘 하면 돼요",
        "계속 이러면 어떡해요",
        "왜 이렇게 되는 거예요",
    ),
}


@dataclass
class AudioEvidence:
    product_label: str
    status_label: str
    detail_label: str
    detail_confidence: float
    device: str
    chunk_count: int


@dataclass
class ImageEvidence:
    summary: str
    visible_issue: str
    device_hint: str
    error_codes: List[str] = field(default_factory=list)
    visible_components: List[str] = field(default_factory=list)
    confidence: str = "unknown"


@dataclass
class RetrievedContext:
    title: str
    device: str
    category_ko: str
    url: str
    content: str
    score: float


@dataclass
class AgentEvidenceBundle:
    user_text: str
    device_hint: str
    user_name: str = ""
    audio: Optional[AudioEvidence] = None
    image: Optional[ImageEvidence] = None
    warnings: List[str] = field(default_factory=list)
    retrieved_contexts: List[RetrievedContext] = field(default_factory=list)


def tokenize(text: str) -> List[str]:
    """Tokenize English and Korean terms for lightweight local retrieval."""
    return re.findall(r"[0-9A-Za-z가-힣]+", str(text or "").lower())


def normalize_whitespace(text: str) -> str:
    """Collapse repeated whitespace for more stable prompts and search."""
    return re.sub(r"\s+", " ", str(text or "")).strip()


def cosine_similarity(left: Sequence[float], right: Sequence[float]) -> float:
    """Compute cosine similarity between two embedding vectors."""
    if not left or not right or len(left) != len(right):
        return 0.0

    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    if left_norm == 0 or right_norm == 0:
        return 0.0

    dot_product = sum(left_value * right_value for left_value, right_value in zip(left, right))
    return dot_product / (left_norm * right_norm)


def average_vectors(vectors: Sequence[Sequence[float]]) -> List[float]:
    """Average a group of embeddings into one centroid vector."""
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
            totals[index] += float(value)

    if valid_count == 0:
        return []
    return [value / valid_count for value in totals]


def resolve_openai_model(model_name: str, fallback: str) -> str:
    """Normalize legacy or invalid model aliases into supported names."""
    normalized = str(model_name or "").strip()
    if not normalized:
        return fallback
    return MODEL_ALIASES.get(normalized, normalized)


def supports_temperature(model_name: str) -> bool:
    """Return whether the selected model should receive a temperature parameter."""
    normalized = resolve_openai_model(model_name, "")
    return not normalized.startswith("gpt-5")


def extract_response_text(response: Any) -> str:
    """Read text from Responses API output_text or nested message content."""
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


def normalize_record_device(record: Dict[str, Any]) -> str:
    """Re-infer device from category and title to avoid weak upstream mapping."""
    category_ko = str(record.get("category_ko", ""))
    title = str(record.get("title", ""))
    combined = f"{category_ko} {title}"

    for canonical, keywords in DEVICE_KEYWORDS.items():
        if any(keyword in combined for keyword in keywords):
            return canonical

    stored = str(record.get("device", "unknown")).strip()
    return stored or "unknown"


def ensure_openai() -> None:
    """Validate that the OpenAI SDK and API key are available."""
    if OpenAI is None:
        raise ImportError("Missing required package: openai. Install it with `pip install openai`.")
    if not os.getenv("OPENAI_API_KEY"):
        raise EnvironmentError("OPENAI_API_KEY is not set.")


@lru_cache(maxsize=1)
def load_response_mode_centroids(
    model_name: str = DEFAULT_RESPONSE_MODE_EMBEDDING_MODEL,
) -> Dict[str, List[float]]:
    """Embed response-mode example phrases once and cache their centroids."""
    ensure_openai()
    client = OpenAI()

    labels: List[str] = []
    example_texts: List[str] = []
    for label, samples in RESPONSE_MODE_EXAMPLES.items():
        for sample in samples:
            labels.append(label)
            example_texts.append(sample)

    response = client.embeddings.create(model=model_name, input=example_texts)
    grouped_vectors: Dict[str, List[List[float]]] = {label: [] for label in RESPONSE_MODE_EXAMPLES}
    for label, data in zip(labels, response.data):
        grouped_vectors[label].append(list(data.embedding))

    return {
        label: average_vectors(vectors)
        for label, vectors in grouped_vectors.items()
        if vectors
    }


@lru_cache(maxsize=1)
def load_chunk_records(chunk_path: str = str(DEFAULT_CHUNK_PATH)) -> List[Dict[str, Any]]:
    """Load pre-chunked LG support records for local retrieval."""
    path = Path(chunk_path)
    if not path.exists():
        full_doc_path = Path(DEFAULT_FULL_DOC_PATH)
        if not full_doc_path.exists():
            raise FileNotFoundError(
                f"Chunk file not found: {path}. Full document fallback also missing: {full_doc_path}"
            )

        from build_rag_chunks import build_chunks

        documents = json.loads(full_doc_path.read_text(encoding="utf-8"))
        if not isinstance(documents, list):
            raise ValueError(f"Expected a JSON array in {full_doc_path}")
        return build_chunks(documents)

    records: List[Dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as file:
        for line in file:
            line = line.strip()
            if not line:
                continue
            records.append(json.loads(line))
    return records


def encode_image_to_data_url(image_path: str | Path) -> str:
    """Convert a local image into a data URL for the Responses API."""
    path = Path(image_path)
    if not path.exists():
        raise FileNotFoundError(f"Image file not found: {path}")

    mime_type, _ = mimetypes.guess_type(str(path))
    if not mime_type:
        mime_type = "image/png"

    encoded = base64.b64encode(path.read_bytes()).decode("utf-8")
    return f"data:{mime_type};base64,{encoded}"


def extract_json_object(text: str) -> Dict[str, Any]:
    """Best-effort JSON extraction from model output."""
    content = normalize_whitespace(text)
    if not content:
        return {}

    try:
        parsed = json.loads(content)
        return parsed if isinstance(parsed, dict) else {}
    except json.JSONDecodeError:
        pass

    match = re.search(r"\{.*\}", content)
    if not match:
        return {}

    try:
        parsed = json.loads(match.group(0))
        return parsed if isinstance(parsed, dict) else {}
    except json.JSONDecodeError:
        return {}


def analyze_image(image_path: str | Path, user_text: str = "") -> ImageEvidence:
    """Use OpenAI vision input to summarize visible appliance clues."""
    ensure_openai()
    client = OpenAI()
    data_url = encode_image_to_data_url(image_path)

    model_name = resolve_openai_model(DEFAULT_VISION_MODEL, "gpt-4.1-mini")
    request_kwargs = {
        "model": model_name,
        "max_output_tokens": 400,
        "instructions": (
            "You analyze appliance support images. "
            "Return JSON only with keys: device_hint, visible_issue, visible_components, "
            "error_codes, confidence, summary. "
            "Use short strings or arrays. If uncertain, say unknown."
        ),
        "input": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": user_text or "Analyze this appliance image for visible problems or clues.",
                    },
                    {
                        "type": "input_image",
                        "image_url": data_url,
                    },
                ],
            }
        ],
    }
    if supports_temperature(model_name):
        request_kwargs["temperature"] = 0

    response = client.responses.create(**request_kwargs)

    parsed = extract_json_object(extract_response_text(response))
    return ImageEvidence(
        summary=normalize_whitespace(str(parsed.get("summary", "unknown"))),
        visible_issue=normalize_whitespace(str(parsed.get("visible_issue", "unknown"))),
        device_hint=normalize_whitespace(str(parsed.get("device_hint", "unknown"))),
        error_codes=[normalize_whitespace(item) for item in parsed.get("error_codes", []) if normalize_whitespace(item)],
        visible_components=[
            normalize_whitespace(item) for item in parsed.get("visible_components", []) if normalize_whitespace(item)
        ],
        confidence=normalize_whitespace(str(parsed.get("confidence", "unknown"))),
    )


def build_audio_evidence(audio_path: str | Path) -> AudioEvidence:
    """Run the local audio model and convert output into a compact evidence object."""
    prediction = predict_noise(audio_path)
    device = detect_device(prediction["product_label"])
    if device == "unknown":
        device = detect_device(prediction["label"])

    return AudioEvidence(
        product_label=prediction["product_label"],
        status_label=prediction["status_label"],
        detail_label=prediction["label"],
        detail_confidence=float(prediction["confidence"]),
        device=device,
        chunk_count=int(prediction.get("chunk_count", 0)),
    )


def infer_device_hint(user_text: str, audio: Optional[AudioEvidence], image: Optional[ImageEvidence]) -> str:
    """Merge lightweight device hints from user text, audio, and image."""
    candidates = []

    if audio and audio.device != "unknown":
        candidates.append(audio.device)

    if image and image.device_hint:
        candidates.append(detect_device(image.device_hint))

    text_device = detect_device(user_text)
    if text_device != "unknown":
        candidates.append(text_device)

    for candidate in candidates:
        if candidate != "unknown":
            return candidate

    return "unknown"


def build_search_query(bundle: AgentEvidenceBundle) -> str:
    """Combine signals into one retrieval query."""
    parts = [bundle.user_text]

    if bundle.audio:
        parts.append(bundle.audio.product_label)
        parts.append(bundle.audio.status_label)
        parts.append(bundle.audio.detail_label)

    if bundle.image:
        parts.append(bundle.image.summary)
        parts.append(bundle.image.visible_issue)
        parts.extend(bundle.image.error_codes)
        parts.extend(bundle.image.visible_components)

    if bundle.device_hint != "unknown":
        parts.append(bundle.device_hint)

    return normalize_whitespace(" ".join(part for part in parts if part))


def extract_priority_tokens(bundle: AgentEvidenceBundle) -> List[str]:
    """Focus retrieval on symptom-bearing tokens rather than generic appliance words."""
    priority_tokens = []
    for token in tokenize(build_search_query(bundle)):
        if token in RETRIEVAL_STOPWORDS:
            continue
        if len(token) <= 1:
            continue
        priority_tokens.append(token)
    return priority_tokens


def score_local_chunk(
    record: Dict[str, Any],
    query_tokens: Sequence[str],
    priority_tokens: Sequence[str],
    device_hint: str,
) -> float:
    """Simple lexical scoring for local retrieval."""
    record_device = normalize_record_device(record)
    searchable = " ".join(
        [
            str(record.get("title", "")),
            record_device,
            str(record.get("category_ko", "")),
            str(record.get("content_chunk", "")),
        ]
    ).lower()

    score = 0.0
    if device_hint != "unknown" and record_device == device_hint:
        score += 12.0

    priority_matches = 0
    title = str(record.get("title", "")).lower()
    for token in priority_tokens:
        if token in searchable:
            score += 2.5
            priority_matches += 1
        if token in title:
            score += 2.0

    for token in query_tokens:
        if len(token) <= 1:
            continue
        if token in searchable:
            score += 0.6
        if token in title:
            score += 0.6

    if priority_tokens and priority_matches == 0:
        return 0.0

    return score


def local_retrieve(bundle: AgentEvidenceBundle, top_k: int = DEFAULT_TOP_K) -> List[RetrievedContext]:
    """Retrieve top support chunks from the local chunk store."""
    records = load_chunk_records()
    query = build_search_query(bundle)
    query_tokens = tokenize(query)
    priority_tokens = extract_priority_tokens(bundle)

    scored: List[tuple[float, Dict[str, Any]]] = []
    for record in records:
        score = score_local_chunk(record, query_tokens, priority_tokens, bundle.device_hint)
        if score > 0:
            scored.append((score, record))

    scored.sort(key=lambda item: item[0], reverse=True)

    seen_sources = set()
    contexts: List[RetrievedContext] = []
    for score, record in scored:
        source_id = record.get("source_id")
        if source_id in seen_sources:
            continue
        seen_sources.add(source_id)
        contexts.append(
            RetrievedContext(
                title=str(record.get("title", "")),
                device=normalize_record_device(record),
                category_ko=str(record.get("category_ko", "")),
                url=str(record.get("url", "")),
                content=str(record.get("content_chunk", "")),
                score=score,
            )
        )
        if len(contexts) >= top_k:
            break

    return contexts


def vector_store_retrieve(bundle: AgentEvidenceBundle, vector_store_id: str, top_k: int = DEFAULT_TOP_K) -> List[RetrievedContext]:
    """Retrieve support context from an OpenAI vector store when configured."""
    ensure_openai()
    client = OpenAI()
    query = build_search_query(bundle)
    results = client.vector_stores.search(
        vector_store_id=vector_store_id,
        query=query,
        max_num_results=top_k,
        rewrite_query=True,
    )

    contexts: List[RetrievedContext] = []
    for item in getattr(results, "data", []):
        title = ""
        device = ""
        category_ko = ""
        url = ""
        content = ""

        attributes = getattr(item, "attributes", None) or {}
        if isinstance(attributes, dict):
            title = str(attributes.get("title", ""))
            device = str(attributes.get("device", ""))
            category_ko = str(attributes.get("category_ko", ""))
            url = str(attributes.get("url", ""))

        for part in getattr(item, "content", []) or []:
            text_value = getattr(part, "text", None)
            if isinstance(text_value, str) and text_value.strip():
                content = text_value
                break

        contexts.append(
            RetrievedContext(
                title=title,
                device=normalize_record_device({"title": title, "category_ko": category_ko, "device": device}),
                category_ko=category_ko,
                url=url,
                content=content,
                score=float(getattr(item, "score", 0.0) or 0.0),
            )
        )

    return contexts


def build_context_block(contexts: Sequence[RetrievedContext]) -> str:
    """Format retrieved support context for the final diagnosis prompt."""
    if not contexts:
        return "No LG support context was retrieved."

    blocks = []
    for index, context in enumerate(contexts, start=1):
        blocks.append(
            "\n".join(
                [
                    f"[Context {index}]",
                    f"Title: {context.title}",
                    f"Device: {context.device}",
                    f"Category: {context.category_ko}",
                    f"Content: {context.content}",
                    f"URL: {context.url}",
                ]
            )
        )
    return "\n\n".join(blocks)


def build_evidence_payload(bundle: AgentEvidenceBundle) -> Dict[str, Any]:
    """Convert internal evidence into prompt-friendly JSON."""
    return {
        "user_name": bundle.user_name,
        "user_text": bundle.user_text,
        "device_hint": bundle.device_hint,
        "audio": asdict(bundle.audio) if bundle.audio else None,
        "image": asdict(bundle.image) if bundle.image else None,
        "warnings": bundle.warnings,
        "retrieved_contexts": [asdict(context) for context in bundle.retrieved_contexts],
    }


def format_display_name(user_name: str) -> str:
    """Normalize a user display name for friendly Korean output."""
    normalized = normalize_whitespace(user_name)
    if not normalized:
        return "고객"
    if normalized.endswith("님"):
        return normalized[:-1].strip() or "고객"
    return normalized


def summarize_empty_response(response: Any) -> str:
    """Capture the most useful metadata when the Responses API returns no text."""
    response_status = getattr(response, "status", "unknown")
    response_error = getattr(response, "error", None)
    incomplete_details = getattr(response, "incomplete_details", None)
    incomplete_reason = getattr(incomplete_details, "reason", None) if incomplete_details else None
    return f"status={response_status}, incomplete_reason={incomplete_reason}, error={response_error}"


def build_agent_request_kwargs(
    model_name: str,
    instructions: str,
    user_prompt: str,
    *,
    max_output_tokens: int,
) -> Dict[str, Any]:
    """Assemble model-specific Responses API arguments."""
    request_kwargs: Dict[str, Any] = {
        "model": model_name,
        "max_output_tokens": max_output_tokens,
        "instructions": instructions,
        "input": user_prompt,
    }
    if model_name.startswith("gpt-5"):
        request_kwargs["reasoning"] = {"effort": "minimal"}
        request_kwargs["text"] = {"verbosity": "low"}
    else:
        request_kwargs["temperature"] = 0.2
    return request_kwargs


def build_response_instructions(opening_line: str) -> str:
    """Build conditional response instructions for diagnosis and general chat."""
    return (
        "You are an appliance support agent. "
        "Combine the user's text, recent conversation context, local audio classifier output, image analysis, and LG support context. "
        "Write the final answer in very easy Korean for a non-technical user. "
        "Only say things that are supported by the evidence. "
        "If something is uncertain, do not present it as fact. "
        "Instead say clearly that it is hard to be certain and describe it as a possibility. "
        "Do not use English section headings. "
        "Do not use markdown except when you are explicitly told to start with one bold sentence. "
        "The input includes recent conversation history and the latest user message. "
        "First decide whether the latest user message is mainly about appliance diagnosis, symptoms, troubleshooting, error codes, noise, repair, or a fault-related follow-up. "
        "If it is diagnosis-related, use this structure. "
        f"Start with this exact sentence: {opening_line} "
        "In the next sentence, explain the current symptom in this style: '현재 증상은 ... 상황이에요.' "
        "After that, explain why this symptom may be happening in this style: '이 증상은 보통 ... 문제 때문에 생길 수 있어요.' "
        "If the cause is not certain, say '정확한 원인은 확실하지 않지만 ... 문제일 가능성도 있어요.' "
        "Then write this sentence exactly: '이러한 상황에서는 다음과 같이 대처해보세요.' "
        "After that, provide 2 to 5 numbered steps in order. "
        "Each step should be short, concrete, and easy to follow. "
        "If service is recommended, mention it in the last numbered step or a short final sentence. "
        "If the latest user message is not diagnosis-related, do not use the diagnosis template and do not start with the diagnosis sentence. "
        "Instead answer naturally as a continuing conversation in easy Korean. "
        "In that case, answer the user's actual question first, keep the wording connected to the recent conversation, and only mention diagnosis or symptoms if they are directly relevant. "
        "For non-diagnosis questions, use a natural conversational reply in 2 to 5 short sentences, and ask at most one short follow-up question only when it is really needed. "
        "Do not mention ThinQ app, this app, or '앱을 통해' style wording unless the user explicitly asks about the app itself. "
        "If warnings indicate a missing modality result, briefly mention that limitation in simple Korean."
    )


def build_response_user_prompt(evidence_json: str, context_block: str) -> str:
    """Build the user prompt for either diagnosis or general follow-up replies."""
    return (
        "Multimodal evidence:\n"
        f"{evidence_json}\n\n"
        "Relevant LG support context:\n"
        f"{context_block}\n\n"
        "Write a concise support response for an end user. "
        "Use plain, everyday Korean and avoid technical jargon when a simpler explanation is possible. "
        "If the latest user message is diagnosis-related, clearly include what the current symptom is and why it may be happening. "
        "If the latest user message is not diagnosis-related, answer it naturally so the conversation flows correctly from the recent turns. "
        "If the evidence is not enough for a confident diagnosis, say that clearly and ask for only the single most useful next input."
    )


def extract_latest_user_message(conversation_text: str) -> str:
    """Extract the latest user message from the compact conversation context."""
    lines = [line.strip() for line in str(conversation_text or "").splitlines() if line.strip()]
    for line in reversed(lines):
        if line.startswith("Current user message:"):
            return normalize_whitespace(line.split(":", 1)[1])
        if line.startswith("User:"):
            return normalize_whitespace(line.split(":", 1)[1])
    return normalize_whitespace(conversation_text)


def classify_response_mode(bundle: AgentEvidenceBundle) -> str:
    """Choose between diagnosis mode and general conversation mode."""
    latest_message = normalize_whitespace(extract_latest_user_message(bundle.user_text)).lower()
    conversation_text = normalize_whitespace(bundle.user_text).lower()
    has_prior_diagnosis_context = (
        "현재 증상은" in conversation_text
        or "진단해봤어요" in conversation_text
    )

    if bundle.audio or bundle.image:
        return "diagnosis"

    diagnosis_keywords = (
        "증상",
        "에러",
        "오류",
        "코드",
        "소리",
        "소음",
        "고장",
        "수리",
        "원인",
        "진단",
        "진동",
        "냄새",
        "누수",
        "작동",
        "멈춤",
        "고쳐",
        "고쳐줘",
        "차갑지",
        "안 시원",
        "시원하지",
        "배수",
        "결빙",
        "팬",
        "전원",
        "문이 안",
        "물이 안",
        "안돼",
        "안되",
        "안 돼",
    )
    # Expressions that clearly signal the issue is resolved or the user is closing the conversation.
    # These must be checked BEFORE followup_keywords to avoid "해결됐어" being misrouted.
    resolution_keywords = (
        "해결됐어",
        "해결됐어요",
        "해결됐습니다",
        "고쳐졌어",
        "고쳐졌어요",
        "됐어요",
        "됐습니다",
        "해결했어",
        "해결했어요",
        "문제없어",
        "문제없어요",
        "괜찮아졌어",
        "괜찮아졌어요",
    )
    general_chat_keywords = (
        "고마워",
        "고마워요",
        "감사",
        "안녕",
        "반가워",
        "이름",
        "누구",
        "뭐 할 수",
        "무슨 기능",
        "사용법",
        "설명해",
        "다시 말해",
        "쉽게 말해",
        "정리해",
        "요약해",
        "요약해줘",
        "번역해",
        "추천해",
        "비교해",
        "무슨 뜻",
        "이게 무슨 뜻",
        "뜻이야",
        "다시 설명",
        "다시 설명해줘",
        "쉽게 설명",
    )
    followup_keywords = (
        "그럼",
        "그러면",
        "왜",
        "왜 그래",
        "왜 그런",
        "어떻게",
        "어떡해",
        "그 다음",
        "다음엔",
        "해결",
        "조치",
        "확인",
        "맞아",
        "계속",
        "그래도",
    )

    keyword_scores = {
        "diagnosis": 0.0,
        "conversation": 0.0,
        "diagnosis_followup": 0.0,
    }
    for keyword in diagnosis_keywords:
        if keyword in latest_message:
            keyword_scores["diagnosis"] += 0.12 if " " in keyword else 0.08
    for keyword in general_chat_keywords:
        if keyword in latest_message:
            keyword_scores["conversation"] += 0.12 if " " in keyword else 0.08
    for keyword in followup_keywords:
        if keyword in latest_message:
            keyword_scores["diagnosis_followup"] += 0.12 if " " in keyword else 0.08

    # Resolution/closing expressions override followup keyword matches (e.g. "해결됐어" contains "해결").
    if any(kw in latest_message for kw in resolution_keywords):
        return "conversation"

    if keyword_scores["diagnosis"] >= 0.16:
        return "diagnosis"
    if has_prior_diagnosis_context and keyword_scores["diagnosis_followup"] >= 0.08:
        return "diagnosis"
    if keyword_scores["conversation"] >= 0.16:
        return "conversation"

    vector_scores = {
        "diagnosis": 0.0,
        "conversation": 0.0,
        "diagnosis_followup": 0.0,
    }
    try:
        centroids = load_response_mode_centroids()
        response = OpenAI().embeddings.create(
            model=DEFAULT_RESPONSE_MODE_EMBEDDING_MODEL,
            input=[latest_message],
        )
        input_vector = list(response.data[0].embedding)
        for label, centroid in centroids.items():
            vector_scores[label] = cosine_similarity(input_vector, centroid)
    except Exception:
        vector_scores = vector_scores

    diagnosis_score = keyword_scores["diagnosis"] + vector_scores["diagnosis"]
    conversation_score = keyword_scores["conversation"] + vector_scores["conversation"]
    followup_score = keyword_scores["diagnosis_followup"] + vector_scores["diagnosis_followup"]

    if has_prior_diagnosis_context and followup_score >= 0.34:
        return "diagnosis"
    if diagnosis_score >= 0.34 and diagnosis_score > conversation_score + 0.02:
        return "diagnosis"
    if has_prior_diagnosis_context and diagnosis_score >= 0.28 and followup_score >= 0.28:
        return "diagnosis"
    if conversation_score >= 0.30:
        return "conversation"

    return "conversation"


def build_mode_specific_instructions(mode: str, opening_line: str) -> str:
    """Build a prompt that matches the detected response mode."""
    common_prefix = (
        "You are an appliance support agent. "
        "Combine the user's text, recent conversation context, local audio classifier output, image analysis, and LG support context. "
        "Write the final answer in very easy Korean for a non-technical user. "
        "Only say things that are supported by the evidence. "
        "If something is uncertain, do not present it as fact. "
        "Instead say clearly that it is hard to be certain and describe it as a possibility. "
        "Do not use English section headings. "
        "Do not mention ThinQ app, this app, or '앱을 통해' style wording unless the user explicitly asks about the app itself. "
        "If warnings indicate a missing modality result, briefly mention that limitation in simple Korean. "
    )
    if mode == "diagnosis":
        return (
            common_prefix
            + "Do not use markdown except for the first bold sentence. "
            + f"Start the answer with this exact sentence: {opening_line} "
            + "In the next sentence, explain the current symptom in this style: '현재 증상은 ... 상황이에요.' "
            + "After that, explain why this symptom may be happening in this style: '이 증상은 보통 ... 문제 때문에 생길 수 있어요.' "
            + "If the cause is not certain, say '정확한 원인은 확실하지 않지만 ... 문제일 가능성도 있어요.' "
            + "Then write this sentence exactly: '이러한 상황에서는 다음과 같이 대처해보세요.' "
            + "After that, provide 2 to 5 numbered steps in order. "
            + "Each step should be short, concrete, and easy to follow. "
            + "If service is recommended, mention it in the last numbered step or a short final sentence."
        )
    return (
        common_prefix
        + "Do not use markdown. "
        + "The latest user message is not a direct symptom diagnosis request. "
        + "Answer naturally as a continuing conversation in easy Korean. "
        + "Answer the user's actual question first. "
        + "Keep the wording connected to the recent conversation so the flow feels natural. "
        + "Only mention diagnosis or symptoms if they are directly relevant to the latest question. "
        + "Never use these diagnosis-template phrases in conversation mode: '진단해봤어요', '현재 증상은', '이러한 상황에서는 다음과 같이 대처해보세요.' "
        + "Use 2 to 5 short sentences. "
        + "Ask at most one short follow-up question only when it is really needed."
    )


def build_mode_specific_user_prompt(
    mode: str,
    evidence_json: str,
    context_block: str,
    latest_user_message: str,
) -> str:
    """Build a prompt payload tailored to the detected mode."""
    return (
        f"Detected response mode: {mode}\n"
        f"Latest user message: {latest_user_message}\n\n"
        "Multimodal evidence:\n"
        f"{evidence_json}\n\n"
        "Relevant LG support context:\n"
        f"{context_block}\n\n"
        "Write a concise support response for an end user. "
        "Use plain, everyday Korean and avoid technical jargon when a simpler explanation is possible. "
        "If this is diagnosis mode, clearly include what the current symptom is and why it may be happening. "
        "If this is conversation mode, answer the latest user message naturally so the conversation flows correctly from the recent turns. "
        "If the evidence is not enough for a confident diagnosis, say that clearly and ask for only the single most useful next input."
    )


def generate_agent_response(bundle: AgentEvidenceBundle) -> str:
    """Generate the final multimodal support response."""
    ensure_openai()
    client = OpenAI()
    evidence_json = json.dumps(build_evidence_payload(bundle), ensure_ascii=False, indent=2)
    display_name = format_display_name(bundle.user_name)
    opening_line = f"**{display_name}님의 문제를 진단해봤어요!**"

    instructions = (
        "You are an appliance diagnosis agent. "
        "Combine the user's text, local audio classifier output, image analysis, and LG support context. "
        "Write the final answer in very easy Korean for a non-technical user. "
        "Only say things that are supported by the evidence. "
        "If something is uncertain, do not present it as fact. "
        "Instead say clearly that it is hard to be certain and describe it as a possibility. "
        "Do not use English section headings. "
        "Do not use markdown except for the first bold sentence. "
        f"Start the answer with this exact sentence: {opening_line} "
        "In the next sentence, explain the current symptom in this style: '현재 증상은 ... 상황이에요.' "
        "After that, explain why this symptom may be happening in this style: '이 증상은 보통 ... 때문에 나타날 수 있어요.' "
        "If the cause is not certain, say '정확한 원인은 확실하지 않지만 ... 때문에 나타날 가능성이 있어요.' "
        "Then write this sentence exactly: '이러한 상황에서는 다음과 같이 대처해보세요.' "
        "After that, provide 2 to 5 numbered steps in order. "
        "Each step should be short, concrete, and easy to follow. "
        "If service is recommended, mention it in the last numbered step or a short final sentence. "
        "Do not mention ThinQ app, this app, or '앱을 통해' style wording unless the user explicitly asks about the app itself. "
        "If warnings indicate a missing modality result, briefly mention that limitation in simple Korean."
    )

    user_prompt = (
        "Multimodal evidence:\n"
        f"{evidence_json}\n\n"
        "Relevant LG support context:\n"
        f"{build_context_block(bundle.retrieved_contexts)}\n\n"
        "Write a concise support response for an end user. "
        "Use plain, everyday Korean and avoid technical jargon when a simpler explanation is possible. "
        "The answer must clearly include what the current symptom is and why it may be happening. "
        "If the evidence is not enough for a confident diagnosis, say that clearly and ask for only the single most useful next input."
    )

    latest_user_message = extract_latest_user_message(bundle.user_text)
    response_mode = classify_response_mode(bundle)
    context_block = build_context_block(bundle.retrieved_contexts)
    instructions = build_mode_specific_instructions(response_mode, opening_line)
    user_prompt = build_mode_specific_user_prompt(
        response_mode,
        evidence_json,
        context_block,
        latest_user_message,
    )

    primary_model = resolve_openai_model(DEFAULT_AGENT_MODEL, "gpt-5-mini")
    attempt_configs = [
        (primary_model, 1200),
        (primary_model, 1800),
    ]
    if primary_model != "gpt-4.1-mini":
        attempt_configs.append(("gpt-4.1-mini", 900))

    failures: List[str] = []
    for attempt_index, (model_name, max_output_tokens) in enumerate(attempt_configs, start=1):
        response = client.responses.create(
            **build_agent_request_kwargs(
                model_name,
                instructions,
                user_prompt,
                max_output_tokens=max_output_tokens,
            )
        )

        output_text = extract_response_text(response)
        if output_text:
            return output_text

        failures.append(f"attempt={attempt_index}, model={model_name}, {summarize_empty_response(response)}")

    raise RuntimeError(
        "The OpenAI agent response was empty after retries. " + " | ".join(failures)
    )


def run_agent(
    user_text: str = "",
    image_path: Optional[str] = None,
    audio_path: Optional[str] = None,
    top_k: int = DEFAULT_TOP_K,
    vector_store_id: Optional[str] = None,
    user_name: str = "",
) -> Dict[str, Any]:
    """Run the full multimodal agent pipeline and return structured output."""
    warnings: List[str] = []
    audio_evidence = None
    image_evidence = None

    if audio_path:
        try:
            audio_evidence = build_audio_evidence(audio_path)
        except Exception as error:
            warnings.append(f"Audio analysis unavailable: {error}")

    if image_path:
        try:
            image_evidence = analyze_image(image_path, user_text=user_text)
        except Exception as error:
            warnings.append(f"Image analysis unavailable: {error}")

    device_hint = infer_device_hint(user_text, audio_evidence, image_evidence)

    bundle = AgentEvidenceBundle(
        user_text=normalize_whitespace(user_text),
        device_hint=device_hint,
        user_name=normalize_whitespace(user_name),
        audio=audio_evidence,
        image=image_evidence,
        warnings=warnings,
    )

    vector_store_id = vector_store_id or os.getenv("OPENAI_VECTOR_STORE_ID")
    if vector_store_id:
        try:
            bundle.retrieved_contexts = vector_store_retrieve(bundle, vector_store_id=vector_store_id, top_k=top_k)
        except Exception:
            bundle.retrieved_contexts = local_retrieve(bundle, top_k=top_k)
    else:
        bundle.retrieved_contexts = local_retrieve(bundle, top_k=top_k)

    response_text = generate_agent_response(bundle)

    return {
        "evidence": build_evidence_payload(bundle),
        "response": response_text,
    }


def main() -> None:
    """CLI entrypoint for local testing."""
    parser = argparse.ArgumentParser(description="Multimodal appliance diagnosis agent.")
    parser.add_argument("--text", default="", help="User symptom text")
    parser.add_argument("--image", default="", help="Optional image path")
    parser.add_argument("--audio", default="", help="Optional audio path")
    parser.add_argument("--top-k", type=int, default=DEFAULT_TOP_K, help="Number of support contexts to retrieve")
    parser.add_argument("--vector-store-id", default="", help="Optional OpenAI vector store id")
    args = parser.parse_args()

    result = run_agent(
        user_text=args.text,
        image_path=args.image or None,
        audio_path=args.audio or None,
        top_k=args.top_k,
        vector_store_id=args.vector_store_id or None,
    )

    print("=== Multimodal Agent Response ===")
    print(result["response"])


if __name__ == "__main__":
    main()
