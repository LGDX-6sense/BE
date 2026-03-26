from __future__ import annotations

import json
import os
import time
from pathlib import Path
from typing import Any, Dict, List

from tqdm import tqdm

from pipeline import PROJECT_ROOT, first_existing_path

try:
    from pinecone import Pinecone, ServerlessSpec
except ImportError:
    raise ImportError("Missing required package: pinecone. Install it with `pip install pinecone`.")

try:
    from openai import OpenAI
except ImportError:
    raise ImportError("Missing required package: openai. Install it with `pip install openai`.")


DEFAULT_CHUNK_PATH = first_existing_path(
    PROJECT_ROOT / "data" / "lg_solution_chunks.jsonl",
    PROJECT_ROOT / "lg_solution_chunks.jsonl",
)

EMBEDDING_MODEL = "text-embedding-3-small"
EMBEDDING_DIM = 1536
BATCH_SIZE = 100


def get_embeddings(texts: List[str], client: OpenAI) -> List[List[float]]:
    response = client.embeddings.create(model=EMBEDDING_MODEL, input=texts)
    return [item.embedding for item in response.data]


def load_chunks(chunk_path: Path) -> List[Dict[str, Any]]:
    chunks = []
    with chunk_path.open("r", encoding="utf-8") as file:
        for line in file:
            line = line.strip()
            if line:
                chunks.append(json.loads(line))
    return chunks


def build_vector(chunk: Dict[str, Any], embedding: List[float]) -> Dict[str, Any]:
    metadata = {
        "title": chunk.get("title", ""),
        "device": chunk.get("device", ""),
        "category_ko": chunk.get("category_ko", ""),
        "url": chunk.get("url", ""),
        "content_chunk": chunk.get("content_chunk", "")[:1000],
        "image_urls": json.dumps(chunk.get("image_urls", []), ensure_ascii=False),
    }
    return {
        "id": chunk["chunk_id"],
        "values": embedding,
        "metadata": metadata,
    }


def main() -> None:
    pinecone_api_key = os.getenv("PINECONE_API_KEY", "")
    index_name = os.getenv("PINECONE_INDEX_NAME", "lg-support")
    openai_api_key = os.getenv("OPENAI_API_KEY", "")

    if not pinecone_api_key:
        raise EnvironmentError("PINECONE_API_KEY is not configured.")
    if not openai_api_key:
        raise EnvironmentError("OPENAI_API_KEY is not configured.")

    if not DEFAULT_CHUNK_PATH.exists():
        raise FileNotFoundError(
            f"Chunk file not found: {DEFAULT_CHUNK_PATH}\nRun `python build_rag_chunks.py` first."
        )

    openai_client = OpenAI(api_key=openai_api_key)
    pc = Pinecone(api_key=pinecone_api_key)

    existing_indexes = [index.name for index in pc.list_indexes()]
    if index_name not in existing_indexes:
        print(f"Creating Pinecone index '{index_name}'...")
        pc.create_index(
            name=index_name,
            dimension=EMBEDDING_DIM,
            metric="cosine",
            spec=ServerlessSpec(cloud="aws", region="us-east-1"),
        )
        time.sleep(5)
        print("Index created.")
    else:
        print(f"Using existing Pinecone index '{index_name}'.")

    index = pc.Index(index_name)
    chunks = load_chunks(DEFAULT_CHUNK_PATH)
    print(f"Total chunks: {len(chunks)}")

    for batch_start in tqdm(range(0, len(chunks), BATCH_SIZE), desc="Uploading"):
        batch = chunks[batch_start : batch_start + BATCH_SIZE]
        texts = [chunk.get("retrieval_text", chunk.get("content_chunk", "")) for chunk in batch]

        embeddings = get_embeddings(texts, openai_client)
        vectors = [build_vector(chunk, embedding) for chunk, embedding in zip(batch, embeddings)]
        index.upsert(vectors=vectors)

    stats = index.describe_index_stats()
    print(f"\nDone. Pinecone vector count: {stats.total_vector_count}")
    print(f"PINECONE_INDEX_NAME={index_name}")


if __name__ == "__main__":
    main()
