from __future__ import annotations

import argparse
import base64
import json
import mimetypes
import os
import re
from dataclasses import asdict, dataclass, field
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

from pipeline import PROJECT_ROOT, detect_device, predict_noise

try:
    from openai import OpenAI
except ImportError:
    OpenAI = None


DEFAULT_AGENT_MODEL = os.getenv("OPENAI_AGENT_MODEL", os.getenv("OPENAI_MODEL", "gpt-5-mini"))
DEFAULT_VISION_MODEL = os.getenv("OPENAI_VISION_MODEL", "gpt-4.1-mini")
DEFAULT_CHUNK_PATH = PROJECT_ROOT / "data" / "lg_solution_chunks.jsonl"
DEFAULT_FULL_DOC_PATH = PROJECT_ROOT / "data" / "lg_solution_all.json"
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
    audio: Optional[AudioEvidence] = None
    image: Optional[ImageEvidence] = None
    retrieved_contexts: List[RetrievedContext] = field(default_factory=list)


def tokenize(text: str) -> List[str]:
    """Tokenize English and Korean terms for lightweight local retrieval."""
    return re.findall(r"[0-9A-Za-z가-힣]+", str(text or "").lower())


def normalize_whitespace(text: str) -> str:
    """Collapse repeated whitespace for more stable prompts and search."""
    return re.sub(r"\s+", " ", str(text or "")).strip()


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
def load_chunk_records(chunk_path: str = str(DEFAULT_CHUNK_PATH)) -> List[Dict[str, Any]]:
    """Load pre-chunked LG support records for local retrieval."""
    path = Path(chunk_path)
    if not path.exists():
        raise FileNotFoundError(
            f"Chunk file not found: {path}. Run `python src/build_rag_chunks.py` first."
        )

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
        "user_text": bundle.user_text,
        "device_hint": bundle.device_hint,
        "audio": asdict(bundle.audio) if bundle.audio else None,
        "image": asdict(bundle.image) if bundle.image else None,
        "retrieved_contexts": [asdict(context) for context in bundle.retrieved_contexts],
    }


def generate_agent_response(bundle: AgentEvidenceBundle) -> str:
    """Generate the final multimodal support response."""
    ensure_openai()
    client = OpenAI()
    evidence_json = json.dumps(build_evidence_payload(bundle), ensure_ascii=False, indent=2)

    instructions = (
        "You are an appliance diagnosis agent. "
        "Combine the user's text, local audio classifier output, image analysis, and LG support context. "
        "Do not overstate certainty. If evidence is weak or conflicting, say so. "
        "Write the final answer in Korean. "
        "Use these exact section headings: Summary, Evidence, Likely causes, Self-check steps, Service recommendation, Follow-up question."
    )

    user_prompt = (
        "Multimodal evidence:\n"
        f"{evidence_json}\n\n"
        "Relevant LG support context:\n"
        f"{build_context_block(bundle.retrieved_contexts)}\n\n"
        "Write a concise support response for an end user. "
        "If an extra image, audio clip, or symptom detail would improve confidence, ask for the single best next input."
    )

    model_name = resolve_openai_model(DEFAULT_AGENT_MODEL, "gpt-5-mini")
    request_kwargs = {
        "model": model_name,
        "max_output_tokens": 900,
        "instructions": instructions,
        "input": user_prompt,
    }
    if supports_temperature(model_name):
        request_kwargs["temperature"] = 0.2

    response = client.responses.create(**request_kwargs)

    output_text = extract_response_text(response)
    if not output_text:
        response_status = getattr(response, "status", "unknown")
        response_error = getattr(response, "error", None)
        raise RuntimeError(f"The OpenAI agent response was empty. status={response_status}, error={response_error}")
    return output_text


def run_agent(
    user_text: str = "",
    image_path: Optional[str] = None,
    audio_path: Optional[str] = None,
    top_k: int = DEFAULT_TOP_K,
    vector_store_id: Optional[str] = None,
) -> Dict[str, Any]:
    """Run the full multimodal agent pipeline and return structured output."""
    audio_evidence = build_audio_evidence(audio_path) if audio_path else None
    image_evidence = analyze_image(image_path, user_text=user_text) if image_path else None
    device_hint = infer_device_hint(user_text, audio_evidence, image_evidence)

    bundle = AgentEvidenceBundle(
        user_text=normalize_whitespace(user_text),
        device_hint=device_hint,
        audio=audio_evidence,
        image=image_evidence,
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
