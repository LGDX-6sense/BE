from __future__ import annotations

import json
import os
from typing import Any, Dict, List, Optional

try:
    from supabase import create_client
except ImportError:
    create_client = None

_client = None
_BUCKET = "support-images"


def _get_client():
    global _client
    if _client is not None:
        return _client
    if create_client is None:
        return None
    url = os.getenv("SUPABASE_URL", "").strip()
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not url or not key:
        return None
    _client = create_client(url, key)
    return _client


def _make_storage_url(filename: str) -> str:
    """파일명 또는 경로를 Supabase Storage 공개 URL로 변환."""
    if not filename or not filename.strip():
        return ""
    filename = filename.strip()
    # 이미 완전한 URL이면 그대로 반환
    if filename.startswith("http://") or filename.startswith("https://"):
        return filename
    supabase_url = os.getenv("SUPABASE_URL", "").strip().rstrip("/")
    if not supabase_url:
        return ""
    # relative_path처럼 슬래시가 포함된 경우도 처리
    return f"{supabase_url}/storage/v1/object/public/{_BUCKET}/{filename}"


def _images_from_doc_id(client, doc_id: str, limit: int = 4) -> List[str]:
    """document_id로 support_document_images에서 이미지 URL 목록 반환."""
    try:
        result = (
            client.table("support_document_images")
            .select("public_url, filename")
            .eq("document_id", doc_id)
            .limit(limit)
            .execute()
        )
        urls = []
        for row in (result.data or []):
            url = row.get("public_url", "").strip()
            if url:
                urls.append(url)
                continue
            fname = row.get("filename", "").strip()
            if fname:
                built = _make_storage_url(fname)
                if built:
                    urls.append(built)
        return urls
    except Exception:
        return []


def fetch_images_for_document(title: str = "", url: str = "") -> List[str]:
    """Return Supabase public image URLs for a support document, looked up by URL or title."""
    client = _get_client()
    if not client:
        return []

    doc_id: Optional[str] = None

    if url.strip():
        try:
            result = (
                client.table("support_documents")
                .select("id")
                .eq("source_url", url.strip())
                .limit(1)
                .execute()
            )
            if result.data:
                doc_id = result.data[0]["id"]
        except Exception:
            pass

    if not doc_id and title.strip():
        try:
            result = (
                client.table("support_documents")
                .select("id")
                .eq("title", title.strip())
                .limit(1)
                .execute()
            )
            if result.data:
                doc_id = result.data[0]["id"]
        except Exception:
            pass

    if not doc_id:
        return []

    return _images_from_doc_id(client, doc_id)


def _parse_image_urls(raw) -> List[str]:
    """support_chunks.image_urls 값(파일명 목록)을 전체 공개 URL 목록으로 변환."""
    if not raw:
        return []
    items: List[str] = []
    if isinstance(raw, list):
        items = [str(u).strip() for u in raw if u and str(u).strip()]
    elif isinstance(raw, str) and raw.strip():
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, list):
                items = [str(u).strip() for u in parsed if u and str(u).strip()]
            else:
                items = [raw.strip()]
        except Exception:
            items = [raw.strip()]

    return [_make_storage_url(u) for u in items if _make_storage_url(u)]


def retrieve_chunks_from_supabase(
    query_tokens: List[str],
    device_hint: str = "unknown",
    top_k: int = 5,
) -> List[Dict[str, Any]]:
    """Query support_chunks in Supabase DB and return matching rows with their image URLs."""
    client = _get_client()
    if not client:
        return []

    try:
        base_query = client.table("support_chunks").select(
            "chunk_id, source_id, device, category_ko, content_chunk, retrieval_text, image_urls, document_id"
        )
        if device_hint and device_hint != "unknown":
            result = base_query.eq("device", device_hint).limit(500).execute()
        else:
            result = base_query.limit(500).execute()
        rows = result.data or []
    except Exception:
        return []

    if not rows or not query_tokens:
        # 토큰 없으면 상위 결과 반환 (이미지 URL만 붙여서)
        for row in rows[:top_k]:
            row["_image_public_urls"] = _parse_image_urls(row.get("image_urls"))
        return rows[:top_k]

    # 렉시컬 스코어링
    scored = []
    for row in rows:
        searchable = " ".join([
            str(row.get("content_chunk", "")),
            str(row.get("retrieval_text", "")),
            str(row.get("category_ko", "")),
        ]).lower()
        score = sum(1 for token in query_tokens if token.lower() in searchable)
        if score > 0:
            scored.append((score, row))

    scored.sort(key=lambda x: x[0], reverse=True)

    # 중복 제거 및 이미지 URL 조립
    seen_sources: set = set()
    results = []
    for _, row in scored:
        source_id = row.get("source_id") or row.get("chunk_id")
        if source_id in seen_sources:
            continue
        seen_sources.add(source_id)

        # 1순위: support_chunks.image_urls 파일명 → 전체 URL
        image_urls = _parse_image_urls(row.get("image_urls"))

        # 2순위: document_id → support_document_images
        if not image_urls and row.get("document_id"):
            image_urls = _images_from_doc_id(client, row["document_id"])

        # 3순위: source_id → support_documents → support_document_images
        if not image_urls and row.get("source_id"):
            try:
                doc_result = (
                    client.table("support_documents")
                    .select("id")
                    .eq("source_url", str(row["source_id"]))
                    .limit(1)
                    .execute()
                )
                if doc_result.data:
                    image_urls = _images_from_doc_id(client, doc_result.data[0]["id"])
            except Exception:
                pass

        row["_image_public_urls"] = image_urls
        results.append(row)

        if len(results) >= top_k:
            break

    return results
