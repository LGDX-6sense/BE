from __future__ import annotations

import argparse
import io
import json
import os
import re
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence

import numpy as np

try:
    import librosa
    import librosa.display
except ImportError:
    librosa = None

try:
    import tensorflow as tf
except ImportError:
    tf = None

try:
    import matplotlib
    matplotlib.use('Agg')  # non-interactive backend (no GUI/tkinter)
    import matplotlib.pyplot as plt
except ImportError:
    plt = None

try:
    from openai import OpenAI
except ImportError:
    OpenAI = None


def first_existing_path(*candidates: Path) -> Path:
    """Return the first existing path, or the primary candidate if none exist yet."""
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    return candidates[0]


def get_project_root() -> Path:
    """Return the project root in both local and Colab environments."""
    if "__file__" in globals():
        return Path(__file__).resolve().parent
    return Path.cwd()


PROJECT_ROOT = get_project_root()
DEFAULT_MODEL_PATH = first_existing_path(PROJECT_ROOT / "smart_care_multi_model_v2.h5")
DEFAULT_AUDIO_DIR = first_existing_path(PROJECT_ROOT / "audio")
DEFAULT_SOLUTION_PATH = first_existing_path(
    PROJECT_ROOT / "data" / "lg_solution.json",
    PROJECT_ROOT / "lg_solution.json",
)
DEFAULT_PRODUCT_CLASSES_PATH = first_existing_path(PROJECT_ROOT / "classes_product.npy")
DEFAULT_STATUS_CLASSES_PATH = first_existing_path(PROJECT_ROOT / "classes_status.npy")
DEFAULT_DETAIL_CLASSES_PATH = first_existing_path(PROJECT_ROOT / "classes_detail.npy")
DEFAULT_OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-4-mini")

TARGET_SAMPLE_RATE = 22050
TARGET_MELS = 128
TARGET_IMAGE_SIZE = 128
TARGET_FMAX = 8000
TARGET_CHUNK_SECONDS = 0.5


DEVICE_NAME_MAP = {
    "refrigerator": {"refrigerator", "fridge", "냉장고"},
    "washing_machine": {"washing_machine", "washer", "washing machine", "세탁기", "드럼세탁기", "일반세탁기"},
    "air_conditioner": {"air_conditioner", "air conditioner", "ac", "에어컨"},
}


DETAIL_DEVICE_HINTS = {
    "refrigerator": ["냉장", "컴프레서", "3way", "수축팽창", "사출팽창"],
    "washing_machine": ["세탁", "탈수", "배수", "급수", "세탁통", "드럼", "도어잠금", "베어링"],
    "air_conditioner": ["실내기", "실외기", "냉매", "토출구", "팬", "드레인호스", "앵글"],
}


NOISE_HINTS = {
    "팬": ["팬", "fan", "송풍"],
    "컴프레서": ["컴프레서", "compressor", "압축기"],
    "냉매": ["냉매", "gas", "flow"],
    "배수": ["배수", "펌프", "pump"],
    "탈수": ["탈수", "spin"],
    "진동": ["진동", "떨림", "vibration"],
    "덜컹": ["덜컹", "달그락", "딸그락", "rattle"],
}

MODEL_ALIASES = {
    "gpt-4-mini": "gpt-4.1-mini",
}


def load_local_env() -> None:
    """Load simple KEY=VALUE pairs from local env files if present."""
    candidate_paths = [
        PROJECT_ROOT / ".env",
        PROJECT_ROOT / "openaiapi.env",
    ]

    for target_path in candidate_paths:
        if not target_path.exists():
            continue

        for raw_line in target_path.read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue

            key, value = line.split("=", 1)
            key = key.strip()
            value = value.strip().strip('"').strip("'")

            if key and key not in os.environ:
                os.environ[key] = value


load_local_env()


def ensure_dependencies(require_openai: bool = False) -> None:
    """Raise a readable error when required packages are missing."""
    missing: List[str] = []

    if librosa is None:
        missing.append("librosa")
    if tf is None:
        missing.append("tensorflow")
    if plt is None:
        missing.append("matplotlib")
    if require_openai and OpenAI is None:
        missing.append("openai")

    if missing:
        raise ImportError(
            f"Missing required package(s): {', '.join(missing)}. "
            f"Install them with `pip install {' '.join(missing)}`."
        )


def resolve_openai_model(model_name: str, fallback: str = "gpt-5-mini") -> str:
    """Normalize legacy or invalid model aliases into supported names."""
    normalized = str(model_name or "").strip()
    if not normalized:
        return fallback
    return MODEL_ALIASES.get(normalized, normalized)


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


def resolve_input_path(path_value: str | Path, default_parent: Optional[Path] = None) -> Path:
    """Resolve a path in local VS Code and Colab-style working directories."""
    raw_path = Path(path_value)
    candidates = [raw_path]

    if not raw_path.is_absolute():
        candidates.append(PROJECT_ROOT / raw_path)
        candidates.append(Path.cwd() / raw_path)
        if default_parent is not None:
            candidates.append(default_parent / raw_path)
            candidates.append(default_parent / raw_path.name)

    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()

    if not raw_path.is_absolute() and default_parent is not None and default_parent.exists():
        recursive_candidates = list(default_parent.rglob(raw_path.name))
        if recursive_candidates:
            return recursive_candidates[0].resolve()

        if raw_path.suffix:
            same_stem_candidates = []
            for extension in (".wav", ".mp3", ".m4a", ".flac"):
                same_stem_candidates.extend(default_parent.rglob(f"{raw_path.stem}{extension}"))
            if same_stem_candidates:
                return same_stem_candidates[0].resolve()

    if default_parent is not None and not raw_path.is_absolute():
        return (default_parent / raw_path.name).resolve()
    return raw_path.resolve()


def _safe_load_npy(path: Path) -> List[str]:
    """Load a class-name npy file if it exists."""
    if not path.exists():
        return []
    values = np.load(path, allow_pickle=True)
    return [str(item) for item in values.tolist()]


def load_audio_waveform(audio_path: str | Path) -> tuple[Path, np.ndarray, int]:
    """Load an audio file once so full and chunk inference can share it."""
    ensure_dependencies()

    resolved_audio_path = resolve_input_path(audio_path, DEFAULT_AUDIO_DIR)
    if not resolved_audio_path.exists():
        raise FileNotFoundError(f"Audio file not found: {resolved_audio_path}")

    waveform, sample_rate = librosa.load(
        str(resolved_audio_path),
        sr=TARGET_SAMPLE_RATE,
        mono=True,
    )
    if waveform.size == 0:
        raise ValueError(f"Loaded audio is empty: {resolved_audio_path}")

    return resolved_audio_path, waveform, sample_rate


@lru_cache(maxsize=1)
def load_class_maps() -> Dict[str, List[str]]:
    """Load product, status, and detail labels."""
    return {
        "product": _safe_load_npy(resolve_input_path(DEFAULT_PRODUCT_CLASSES_PATH)),
        "status": _safe_load_npy(resolve_input_path(DEFAULT_STATUS_CLASSES_PATH)),
        "detail": _safe_load_npy(resolve_input_path(DEFAULT_DETAIL_CLASSES_PATH)),
    }


def _render_mel_image(waveform: np.ndarray, sample_rate: int) -> np.ndarray:
    """Render a mel spectrogram image using the same style as the training set."""
    if waveform.size == 0:
        raise ValueError("Waveform is empty.")

    mel = librosa.feature.melspectrogram(
        y=waveform,
        sr=sample_rate,
        n_mels=TARGET_MELS,
        fmax=TARGET_FMAX,
    )
    mel_db = librosa.power_to_db(mel, ref=np.max)

    # Match the training image generation script as closely as possible:
    # save mel spectrogram PNG first, then resize to 128x128 for inference.
    figure = plt.figure(figsize=(10, 4))
    buffer = io.BytesIO()

    try:
        librosa.display.specshow(mel_db, sr=sample_rate, fmax=TARGET_FMAX)
        plt.axis("off")
        plt.savefig(buffer, bbox_inches="tight", pad_inches=0, format="png")
    finally:
        plt.close(figure)

    image_bytes = buffer.getvalue()
    image = tf.io.decode_png(image_bytes, channels=3)
    image = tf.image.resize(image, [TARGET_IMAGE_SIZE, TARGET_IMAGE_SIZE])
    image = tf.cast(image, tf.float32) / 255.0

    return image.numpy().astype(np.float32)


def split_waveform_into_chunks(waveform: np.ndarray, sample_rate: int) -> List[np.ndarray]:
    """Split audio into fixed 0.5-second chunks, matching the chunked training data."""
    chunk_seconds = float(os.getenv("AUDIO_CHUNK_SECONDS", str(TARGET_CHUNK_SECONDS)))
    chunk_length = max(1, int(sample_rate * chunk_seconds))

    chunks = [
        waveform[index : index + chunk_length]
        for index in range(0, len(waveform), chunk_length)
        if len(waveform[index : index + chunk_length]) == chunk_length
    ]

    return chunks


def extract_features(audio_path: str | Path) -> np.ndarray:
    """
    Convert an audio file into a 128x128x3 mel-spectrogram image.

    The current classifier is a Keras MobileNetV2 model whose input shape is
    [batch, 128, 128, 3]. This follows the notebook pipeline: audio -> mel
    spectrogram -> matplotlib PNG render -> TensorFlow PNG decode/resize.
    """
    ensure_dependencies()

    _, waveform, sample_rate = load_audio_waveform(audio_path)
    return _render_mel_image(waveform, sample_rate)


@lru_cache(maxsize=1)
def load_classifier(model_path: str = str(DEFAULT_MODEL_PATH)) -> Any:
    """Load the multi-output Keras classifier."""
    ensure_dependencies()

    resolved_model_path = resolve_input_path(model_path)
    if not resolved_model_path.exists():
        raise FileNotFoundError(
            f"Model file not found: {resolved_model_path}. "
            "Place the trained Keras model at smart_care_multi_model_v2.h5."
        )

    return tf.keras.models.load_model(str(resolved_model_path), compile=False)


def _normalize_outputs(model: Any, predictions: Any) -> Dict[str, np.ndarray]:
    """Map model outputs into a predictable dictionary."""
    if isinstance(predictions, dict):
        return {str(key): np.asarray(value) for key, value in predictions.items()}

    if isinstance(predictions, list):
        output_names = list(getattr(model, "output_names", []))
        if len(output_names) == len(predictions):
            return {name: np.asarray(value) for name, value in zip(output_names, predictions)}
        if len(predictions) == 3:
            return {
                "product_out": np.asarray(predictions[0]),
                "status_out": np.asarray(predictions[1]),
                "detail_out": np.asarray(predictions[2]),
            }

    if isinstance(predictions, np.ndarray):
        return {"detail_out": predictions}

    raise TypeError("Unsupported model output format.")


def _pick_label(probabilities: np.ndarray, class_names: Sequence[str], fallback_prefix: str) -> Dict[str, Any]:
    """Return the top label, confidence, and top-3 predictions."""
    if probabilities.ndim == 2:
        probabilities = probabilities[0]

    predicted_index = int(np.argmax(probabilities))
    predicted_label = class_names[predicted_index] if predicted_index < len(class_names) else f"{fallback_prefix}_{predicted_index}"

    top_k = min(3, len(probabilities))
    top_indices = np.argsort(probabilities)[::-1][:top_k]
    top_predictions = [
        {
            "label": class_names[index] if index < len(class_names) else f"{fallback_prefix}_{index}",
            "confidence": float(probabilities[index]),
        }
        for index in top_indices
    ]

    return {
        "label": predicted_label,
        "confidence": float(probabilities[predicted_index]),
        "top_predictions": top_predictions,
    }


def _aggregate_probabilities(probability_list: Sequence[np.ndarray]) -> np.ndarray:
    """Average multiple probability vectors into a single ensemble prediction."""
    if len(probability_list) == 0:
        raise ValueError("No probability vectors were provided for aggregation.")

    stacked = np.stack([np.asarray(probabilities, dtype=np.float32) for probabilities in probability_list], axis=0)
    return np.mean(stacked, axis=0)


def predict_noise(audio_path: str | Path) -> Dict[str, Any]:
    """Predict product, status, and detail using both full-audio and chunk-based inference."""
    resolved_audio_path, waveform, sample_rate = load_audio_waveform(audio_path)
    model = load_classifier()
    class_maps = load_class_maps()
    chunk_waveforms = split_waveform_into_chunks(waveform, sample_rate)

    feature_batch = [_render_mel_image(waveform, sample_rate)]
    source_labels = ["full"]
    for index, chunk_waveform in enumerate(chunk_waveforms):
        feature_batch.append(_render_mel_image(chunk_waveform, sample_rate))
        source_labels.append(f"chunk_{index}")

    batch = np.stack(feature_batch, axis=0)
    predictions = model.predict(batch, verbose=0)
    outputs = _normalize_outputs(model, predictions)

    aggregated_outputs = {
        "product_out": _aggregate_probabilities(outputs["product_out"]),
        "status_out": _aggregate_probabilities(outputs["status_out"]),
        "detail_out": _aggregate_probabilities(outputs["detail_out"]),
    }

    product_result = _pick_label(aggregated_outputs["product_out"], class_maps["product"], "product")
    status_result = _pick_label(aggregated_outputs["status_out"], class_maps["status"], "status")
    detail_result = _pick_label(aggregated_outputs["detail_out"], class_maps["detail"], "detail")

    full_product_result = _pick_label(outputs["product_out"][0], class_maps["product"], "product")
    full_status_result = _pick_label(outputs["status_out"][0], class_maps["status"], "status")
    full_detail_result = _pick_label(outputs["detail_out"][0], class_maps["detail"], "detail")

    return {
        "label": detail_result["label"],
        "confidence": detail_result["confidence"],
        "top_predictions": detail_result["top_predictions"],
        "product_label": product_result["label"],
        "product_confidence": product_result["confidence"],
        "status_label": status_result["label"],
        "status_confidence": status_result["confidence"],
        "audio_path": str(resolved_audio_path),
        "inference_sources": source_labels,
        "chunk_count": len(chunk_waveforms),
        "full_audio_prediction": {
            "product_label": full_product_result["label"],
            "status_label": full_status_result["label"],
            "detail_label": full_detail_result["label"],
            "detail_confidence": full_detail_result["confidence"],
        },
    }


def detect_device(label: str) -> str:
    """Infer the appliance type from a product label or a detailed noise label."""
    normalized = str(label or "").strip().lower()

    for canonical, aliases in DEVICE_NAME_MAP.items():
        if normalized in {alias.lower() for alias in aliases}:
            return canonical

    if "냉장" in label or "컴프레서" in label:
        return "refrigerator"
    if "세탁" in label or "탈수" in label or "배수" in label or "급수" in label:
        return "washing_machine"
    if "에어컨" in label or "실내기" in label or "실외기" in label or "냉매" in label:
        return "air_conditioner"

    for device_name, hints in DETAIL_DEVICE_HINTS.items():
        if any(hint in label for hint in hints):
            return device_name

    return "unknown"


@lru_cache(maxsize=1)
def load_solutions(solution_path: str = str(DEFAULT_SOLUTION_PATH)) -> List[Dict[str, Any]]:
    """Load LG troubleshooting documents from JSON."""
    resolved_solution_path = resolve_input_path(solution_path)
    if not resolved_solution_path.exists():
        raise FileNotFoundError(
            f"Solution data not found: {resolved_solution_path}. "
            "Place the crawled LG support data at data/lg_solution.json."
        )

    with resolved_solution_path.open("r", encoding="utf-8") as file:
        data = json.load(file)

    if not isinstance(data, list):
        raise ValueError("lg_solution.json must contain a JSON array.")

    return data


def normalize_device(device_name: str) -> str:
    """Normalize different device spellings to a canonical name."""
    normalized = str(device_name or "").strip().lower().replace("-", "_")

    for canonical, aliases in DEVICE_NAME_MAP.items():
        alias_set = {alias.lower().replace("-", "_") for alias in aliases}
        if normalized in alias_set:
            return canonical

    if "refrigerator" in normalized or "fridge" in normalized or "냉장" in device_name:
        return "refrigerator"
    if "washer" in normalized or "washing" in normalized or "세탁" in device_name:
        return "washing_machine"
    if "air" in normalized or normalized == "ac" or "에어컨" in device_name:
        return "air_conditioner"
    return "unknown"


def _extract_keywords(noise_label: str) -> List[str]:
    """Build keyword candidates from Korean detail labels."""
    keywords = set()
    tokens = [token for token in re.split(r"[\s_/(),-]+", str(noise_label)) if token]

    for token in tokens:
        keywords.add(token)
        for source_keyword, variants in NOISE_HINTS.items():
            if token == source_keyword or token in variants:
                keywords.update(variants)

    return sorted(keywords)


def search_solution(device: str, noise_label: str) -> List[Dict[str, Any]]:
    """Search the LG solution dataset for relevant troubleshooting pages."""
    solutions = load_solutions()
    normalized_device = normalize_device(device)
    keywords = _extract_keywords(noise_label)

    ranked_results: List[Dict[str, Any]] = []
    for item in solutions:
        item_device = normalize_device(str(item.get("device", "")))
        title = str(item.get("title", ""))
        content = str(item.get("content", ""))
        combined_text = f"{title}\n{content}".lower()

        score = 0
        if normalized_device != "unknown" and item_device == normalized_device:
            score += 10
        elif normalized_device != "unknown":
            continue

        if str(noise_label).lower() in combined_text:
            score += 8

        for keyword in keywords:
            if keyword.lower() in combined_text:
                score += 2

        if score > 0:
            ranked_results.append(
                {
                    "title": title,
                    "content": content,
                    "device": item.get("device", ""),
                    "url": item.get("url", ""),
                    "score": score,
                }
            )

    ranked_results.sort(key=lambda item: item["score"], reverse=True)
    return ranked_results[:3]


def _truncate_text(text: str, max_chars: int = 700) -> str:
    """Trim long solution text before sending it to the API."""
    compact = " ".join(str(text or "").split())
    if len(compact) <= max_chars:
        return compact
    return compact[: max_chars - 3] + "..."


def _build_solution_context(solutions: Sequence[Dict[str, Any]]) -> str:
    """Convert solution records into a compact prompt context."""
    if not solutions:
        return "No matching LG support documents were found."

    blocks = []
    for index, solution in enumerate(solutions, start=1):
        blocks.append(
            "\n".join(
                [
                    f"[Document {index}]",
                    f"Title: {_truncate_text(solution.get('title', ''))}",
                    f"Device: {solution.get('device', '')}",
                    f"Content: {_truncate_text(solution.get('content', ''))}",
                    f"URL: {solution.get('url', '')}",
                ]
            )
        )
    return "\n\n".join(blocks)


def _fallback_diagnosis(device: str, noise_label: str, solutions: Sequence[Dict[str, Any]], error: str) -> str:
    """Return a readable diagnosis if the OpenAI request cannot be completed."""
    matched_titles = ", ".join(solution.get("title", "") for solution in solutions if solution.get("title"))
    if not matched_titles:
        matched_titles = "관련 LG 문서를 찾지 못했습니다."

    return (
        "Explanation\n"
        f"- 예측 기기: {device}\n"
        f"- 예측 소음 라벨: {noise_label}\n"
        f"- OpenAI 진단 생성 실패 사유: {error}\n\n"
        "Possible causes\n"
        f"- `{noise_label}`에 해당하는 부품 또는 동작 단계에서 소음이 발생했을 가능성이 있습니다.\n"
        f"- 참고 가능한 LG 문서: {matched_titles}\n\n"
        "Self troubleshooting steps\n"
        "- 제품이 수평으로 설치되어 있는지 확인하세요.\n"
        "- 소음이 발생하는 시점과 패턴을 다시 확인하세요.\n"
        "- 매칭된 LG 문서의 안내사항을 먼저 점검하세요.\n\n"
        "Whether repair service is recommended\n"
        "- 소음이 점점 커지거나 제품 성능 저하가 함께 나타나면 서비스 점검을 권장합니다."
    )


def generate_ai_diagnosis(device: str, noise_label: str, solutions: Sequence[Dict[str, Any]]) -> str:
    """Use OpenAI to generate a user-friendly diagnosis in Korean."""
    if OpenAI is None:
        raise ImportError("Missing required package: openai. Install it with `pip install openai`.")
    if not os.getenv("OPENAI_API_KEY"):
        raise EnvironmentError("OPENAI_API_KEY is not set.")

    client = OpenAI()
    solution_context = _build_solution_context(solutions)

    instructions = (
        "You are an appliance diagnosis assistant. "
        "Write the answer in Korean, but keep the section headings exactly as: "
        "Explanation, Possible causes, Self troubleshooting steps, Whether repair service is recommended. "
        "Base the answer on the predicted device, predicted noise label, and LG support documents. "
        "Do not invent facts that are not supported by the evidence. "
        "If confidence is limited, say so clearly."
    )

    user_prompt = (
        f"Predicted device: {device}\n"
        f"Predicted noise label: {noise_label}\n\n"
        "Relevant LG support documents:\n"
        f"{solution_context}\n\n"
        "Generate a concise, practical diagnosis for an end user."
    )

    response = client.responses.create(
        model=resolve_openai_model(DEFAULT_OPENAI_MODEL),
        instructions=instructions,
        input=user_prompt,
    )

    output_text = extract_response_text(response)
    if not output_text:
        response_status = getattr(response, "status", "unknown")
        response_error = getattr(response, "error", None)
        raise RuntimeError(f"The OpenAI response was empty. status={response_status}, error={response_error}")
    return output_text


def main() -> None:
    """Run the full diagnosis pipeline."""
    parser = argparse.ArgumentParser(description="AI appliance diagnosis based on sound.")
    parser.add_argument(
        "--audio",
        default="sample.wav",
        help="Audio file name or path. Example: fridge_test.wav or audio/fridge_test.wav",
    )
    args = parser.parse_args()

    audio_path = resolve_input_path(args.audio, DEFAULT_AUDIO_DIR)

    try:
        prediction = predict_noise(audio_path)

        device = detect_device(prediction["product_label"])
        if device == "unknown":
            device = detect_device(prediction["label"])

        try:
            solutions = search_solution(device, prediction["label"])
        except FileNotFoundError as error:
            print(f"[WARNING] {error}")
            solutions = []

        diagnosis_label = (
            f"{prediction['label']} | 제품: {prediction['product_label']} | 상태: {prediction['status_label']}"
        )

        try:
            diagnosis = generate_ai_diagnosis(device, diagnosis_label, solutions)
        except Exception as error:
            diagnosis = _fallback_diagnosis(device, diagnosis_label, solutions, str(error))

        print("=== Appliance Diagnosis Result ===")
        print(f"Audio file: {audio_path}")
        print(f"Predicted device: {device}")
        print(f"Predicted product: {prediction['product_label']} ({prediction['product_confidence']:.4f})")
        print(f"Predicted status: {prediction['status_label']} ({prediction['status_confidence']:.4f})")
        print(f"Predicted noise label: {prediction['label']} ({prediction['confidence']:.4f})")
        print(f"Inference mode: full + {prediction['chunk_count']} chunk(s)")
        print(
            "Full-only prediction: "
            f"{prediction['full_audio_prediction']['product_label']} / "
            f"{prediction['full_audio_prediction']['status_label']} / "
            f"{prediction['full_audio_prediction']['detail_label']} "
            f"({prediction['full_audio_prediction']['detail_confidence']:.4f})"
        )
        print("\nTop detail predictions:")
        for item in prediction["top_predictions"]:
            print(f"- {item['label']}: {item['confidence']:.4f}")
        print("\nDiagnosis:")
        print(diagnosis)

    except FileNotFoundError as error:
        print(f"[ERROR] {error}")
    except Exception as error:
        print(f"[ERROR] Pipeline failed: {error}")


if __name__ == "__main__":
    main()
