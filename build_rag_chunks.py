from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Dict, Iterable, List


PROJECT_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SOURCE_PATH = PROJECT_ROOT / "data" / "lg_solution_all.json"
DEFAULT_OUTPUT_PATH = PROJECT_ROOT / "data" / "lg_solution_chunks.jsonl"


def normalize_whitespace(text: str) -> str:
    """Clean repeated whitespace while preserving sentence readability."""
    return re.sub(r"\s+", " ", str(text or "")).strip()


def split_into_paragraphs(text: str) -> List[str]:
    """Split long support content into retrieval-friendly paragraph blocks."""
    raw_parts = re.split(r"\n{2,}|(?<=다\.)\s+|(?<=요\.)\s+|(?<=니다\.)\s+", str(text or ""))
    return [normalize_whitespace(part) for part in raw_parts if normalize_whitespace(part)]


def chunk_paragraphs(paragraphs: Iterable[str], chunk_size: int = 900, overlap: int = 150) -> List[str]:
    """Build overlapping text chunks so retrieval remains stable on long articles."""
    chunks: List[str] = []
    current = ""

    for paragraph in paragraphs:
        if not current:
            current = paragraph
            continue

        candidate = f"{current}\n{paragraph}"
        if len(candidate) <= chunk_size:
            current = candidate
            continue

        chunks.append(current)

        if overlap > 0:
            tail = current[-overlap:]
            current = f"{tail}\n{paragraph}"
        else:
            current = paragraph

        current = normalize_whitespace(current)

    if current:
        chunks.append(current)

    return chunks


def build_chunk_record(document: Dict[str, object], chunk_text: str, chunk_index: int) -> Dict[str, object]:
    """Serialize one retrieval chunk with useful metadata for search and debugging."""
    title = normalize_whitespace(str(document.get("title", "")))
    device = normalize_whitespace(str(document.get("device", "")))
    category_ko = normalize_whitespace(str(document.get("category_ko", "")))
    url = normalize_whitespace(str(document.get("url", "")))
    doc_id = normalize_whitespace(str(document.get("url", ""))) or f"{title}-{chunk_index}"

    retrieval_text = "\n".join(
        part
        for part in [
            f"Title: {title}" if title else "",
            f"Device: {device}" if device else "",
            f"Category: {category_ko}" if category_ko else "",
            f"Content: {chunk_text}" if chunk_text else "",
        ]
        if part
    )

    return {
        "chunk_id": f"{doc_id}::chunk_{chunk_index}",
        "source_id": doc_id,
        "title": title,
        "device": device,
        "category_ko": category_ko,
        "url": url,
        "content_chunk": chunk_text,
        "retrieval_text": retrieval_text,
    }


def build_chunks(documents: List[Dict[str, object]]) -> List[Dict[str, object]]:
    """Expand full documents into smaller retrieval chunks."""
    records: List[Dict[str, object]] = []

    for document in documents:
        paragraphs = split_into_paragraphs(str(document.get("content", "")))
        chunks = chunk_paragraphs(paragraphs)

        if not chunks:
            chunks = [normalize_whitespace(str(document.get("content", "")))]

        for index, chunk_text in enumerate(chunks):
            records.append(build_chunk_record(document, chunk_text, index))

    return records


def main() -> None:
    parser = argparse.ArgumentParser(description="Build chunked RAG data from LG support JSON.")
    parser.add_argument("--source", default=str(DEFAULT_SOURCE_PATH), help="Path to lg_solution_all.json")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT_PATH), help="Path to output JSONL file")
    args = parser.parse_args()

    source_path = Path(args.source)
    output_path = Path(args.output)

    if not source_path.exists():
        raise FileNotFoundError(f"Source JSON not found: {source_path}")

    documents = json.loads(source_path.read_text(encoding="utf-8"))
    chunks = build_chunks(documents)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as file:
        for record in chunks:
            file.write(json.dumps(record, ensure_ascii=False) + "\n")

    print(f"Saved: {output_path}")
    print(f"Documents: {len(documents)}")
    print(f"Chunks: {len(chunks)}")


if __name__ == "__main__":
    main()
