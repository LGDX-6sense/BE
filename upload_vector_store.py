from __future__ import annotations

import argparse
import os
from pathlib import Path

from pipeline import PROJECT_ROOT, first_existing_path

try:
    from openai import OpenAI
except ImportError:
    OpenAI = None


DEFAULT_CHUNK_PATH = first_existing_path(
    PROJECT_ROOT / "data" / "lg_solution_chunks.jsonl",
    PROJECT_ROOT / "lg_solution_chunks.jsonl",
)


def ensure_openai() -> None:
    """Validate SDK install and API key presence."""
    if OpenAI is None:
        raise ImportError("Missing required package: openai. Install it with `pip install openai`.")
    if not os.getenv("OPENAI_API_KEY"):
        raise EnvironmentError("OPENAI_API_KEY is not set.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Upload LG support chunks to an OpenAI vector store.")
    parser.add_argument("--file", default=str(DEFAULT_CHUNK_PATH), help="Path to chunked JSONL file")
    parser.add_argument("--name", default="lg-support-multimodal", help="Vector store name")
    parser.add_argument("--vector-store-id", default="", help="Existing vector store id to reuse")
    args = parser.parse_args()

    ensure_openai()
    chunk_path = Path(args.file)
    if not chunk_path.exists():
        raise FileNotFoundError(f"Chunk file not found: {chunk_path}. Run `python src/build_rag_chunks.py` first.")

    client = OpenAI()

    if args.vector_store_id:
        vector_store_id = args.vector_store_id
    else:
        vector_store = client.vector_stores.create(name=args.name)
        vector_store_id = vector_store.id

    with chunk_path.open("rb") as file_handle:
        uploaded = client.vector_stores.files.upload_and_poll(
            vector_store_id=vector_store_id,
            file=file_handle,
        )

    print(f"Vector store id: {vector_store_id}")
    print(f"Uploaded file id: {uploaded.id}")
    print("Set OPENAI_VECTOR_STORE_ID to this value for multimodal_agent.py")


if __name__ == "__main__":
    main()
