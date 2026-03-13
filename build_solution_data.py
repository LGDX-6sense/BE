from __future__ import annotations

import csv
import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Sequence
from urllib.parse import urlsplit, urlunsplit


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "data"


@dataclass
class Document:
    title: str
    content: str
    url: str
    category_ko: str
    device: str
    image_urls: List[str] = field(default_factory=list)
    source_files: List[str] = field(default_factory=list)
    category_aliases: List[str] = field(default_factory=list)


SUPPORTED_DEVICES = {"refrigerator", "washing_machine", "air_conditioner"}


DEVICE_RULES = {
    "refrigerator": [
        "냉장고",
        "김치",
        "냉동고",
        "정수기형냉장고",
        "양문형 냉장고",
        "일반형냉장고",
        "상냉장하냉동",
    ],
    "washing_machine": [
        "세탁기",
        "드럼세탁기",
        "통돌이",
        "일반세탁기",
    ],
    "air_conditioner": [
        "에어컨",
        "시스템에어컨",
        "냉난방",
    ],
}


def normalize_whitespace(text: str) -> str:
    """Collapse repeated whitespace for cleaner storage and better retrieval."""
    return re.sub(r"\s+", " ", str(text or "")).strip()


def normalize_url(url: str) -> str:
    """Strip tracking-like query noise so duplicates can be merged more reliably."""
    raw_url = normalize_whitespace(url)
    if not raw_url:
        return ""

    parsed = urlsplit(raw_url)
    query = parsed.query
    if query:
        keep_parts = []
        for part in query.split("&"):
            if part.startswith(("category=", "subCategory=", "categoryNm=", "subCategoryNm=", "seq=")):
                keep_parts.append(part)
        query = "&".join(keep_parts)

    return urlunsplit((parsed.scheme, parsed.netloc, parsed.path, query, ""))


def parse_image_urls(value: str) -> List[str]:
    """Convert the CSV image column into a list."""
    text = normalize_whitespace(value)
    if not text:
        return []

    if text.startswith("[") and text.endswith("]"):
        try:
            parsed = json.loads(text)
            if isinstance(parsed, list):
                return [normalize_whitespace(item) for item in parsed if normalize_whitespace(item)]
        except json.JSONDecodeError:
            pass

    parts = re.split(r"[\n|,]", text)
    return [normalize_whitespace(part) for part in parts if normalize_whitespace(part)]


def map_device(category_ko: str, title: str, content: str) -> str:
    """Map Korean categories into chatbot-friendly device groups."""
    primary_text = " ".join([category_ko, title])
    fallback_text = " ".join([category_ko, title, content])

    for device, keywords in DEVICE_RULES.items():
        if any(keyword in primary_text for keyword in keywords):
            return device

    for device, keywords in DEVICE_RULES.items():
        if any(keyword in fallback_text for keyword in keywords):
            return device

    return "other"


def read_csv_rows(csv_path: Path) -> List[Dict[str, str]]:
    """Read a CSV file with UTF-8 BOM support."""
    with csv_path.open("r", encoding="utf-8-sig", newline="") as file:
        return list(csv.DictReader(file))


def build_documents(csv_paths: Sequence[Path]) -> List[Document]:
    """Merge solution rows from multiple CSV files and deduplicate them."""
    merged: Dict[str, Document] = {}

    for csv_path in csv_paths:
        for row in read_csv_rows(csv_path):
            category_ko = normalize_whitespace(row.get("카테고리", ""))
            title = normalize_whitespace(row.get("제목", ""))
            content = normalize_whitespace(row.get("본문", ""))
            raw_url = normalize_whitespace(row.get("URL", ""))
            url = normalize_url(raw_url)
            image_urls = parse_image_urls(row.get("이미지목록", ""))
            device = map_device(category_ko, title, content)

            if not title or not content or not url:
                continue

            key = url or f"{category_ko}|{title}"
            source_name = csv_path.name

            if key not in merged:
                merged[key] = Document(
                    title=title,
                    content=content,
                    url=url,
                    category_ko=category_ko,
                    device=device,
                    image_urls=image_urls,
                    source_files=[source_name],
                    category_aliases=[category_ko] if category_ko else [],
                )
                continue

            existing = merged[key]

            if len(content) > len(existing.content):
                existing.content = content
            if len(title) > len(existing.title):
                existing.title = title
            if category_ko and category_ko not in existing.category_aliases:
                existing.category_aliases.append(category_ko)
            if source_name not in existing.source_files:
                existing.source_files.append(source_name)

            for image_url in image_urls:
                if image_url not in existing.image_urls:
                    existing.image_urls.append(image_url)

            if existing.device == "other" and device != "other":
                existing.device = device

    documents = list(merged.values())
    documents.sort(key=lambda item: (item.device, item.category_ko, item.title))
    return documents


def to_record(document: Document) -> Dict[str, object]:
    """Serialize a document for JSON output."""
    return {
        "title": document.title,
        "device": document.device,
        "category_ko": document.category_ko,
        "content": document.content,
        "url": document.url,
        "image_urls": document.image_urls,
        "category_aliases": document.category_aliases,
        "source_files": document.source_files,
    }


def main() -> None:
    csv_paths = [
        Path(r"C:\Users\4111\Documents\카카오톡 받은 파일\lg_multicat_results_20260304_182144.csv"),
        Path(r"C:\Users\4111\Documents\카카오톡 받은 파일\lg_total_crawl2\lg_multicat_results_20260304_184650.csv"),
    ]

    for csv_path in csv_paths:
        if not csv_path.exists():
            raise FileNotFoundError(f"CSV file not found: {csv_path}")

    DEFAULT_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    all_documents = build_documents(csv_paths)
    supported_documents = [doc for doc in all_documents if doc.device in SUPPORTED_DEVICES]

    all_output_path = DEFAULT_OUTPUT_DIR / "lg_solution_all.json"
    supported_output_path = DEFAULT_OUTPUT_DIR / "lg_solution.json"
    metadata_output_path = DEFAULT_OUTPUT_DIR / "lg_solution_stats.json"

    all_output_path.write_text(
        json.dumps([to_record(doc) for doc in all_documents], ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    supported_output_path.write_text(
        json.dumps([to_record(doc) for doc in supported_documents], ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    stats: Dict[str, object] = {
        "total_documents": len(all_documents),
        "supported_documents": len(supported_documents),
        "device_counts": {},
    }

    device_counts: Dict[str, int] = {}
    for document in all_documents:
        device_counts[document.device] = device_counts.get(document.device, 0) + 1
    stats["device_counts"] = device_counts

    metadata_output_path.write_text(
        json.dumps(stats, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"Saved: {all_output_path}")
    print(f"Saved: {supported_output_path}")
    print(f"Saved: {metadata_output_path}")
    print(f"Total documents: {len(all_documents)}")
    print(f"Supported documents: {len(supported_documents)}")


if __name__ == "__main__":
    main()
