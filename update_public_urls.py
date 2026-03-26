"""
support_document_images.public_url 컬럼을 relative_path 기반으로 정확하게 업데이트.

문제: 기존 스크립트는 파일명만으로 URL을 조립해서 서브폴더가 누락됨.
      실제 Storage에는 '한글카테고리 → MD5해시폴더/파일명' 형태로 저장돼 있음.
해결: relative_path에 upload_to_supabase.py와 동일한 sanitize 로직을 적용해 올바른 URL 생성.
"""
from __future__ import annotations

import hashlib
import os
import re
import time
import unicodedata
from pathlib import Path

try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent / "openaiapi.env", override=False)
except ImportError:
    pass

from supabase import create_client

SUPABASE_URL = os.getenv("SUPABASE_URL", "").strip()
SUPABASE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
BUCKET = "support-images"


def _sanitize_storage_key(path: str) -> str:
    """upload_to_supabase.py와 동일한 로직 — 경로를 ASCII-safe Storage 키로 변환."""
    parts = path.split("/")
    sanitized = []
    for part in parts:
        original = part
        part = unicodedata.normalize("NFKD", part).encode("ascii", "ignore").decode("ascii")
        part = re.sub(r"[^\w.\-]", "_", part)
        part = re.sub(r"_+", "_", part).strip("_")
        if not part:
            part = hashlib.md5(original.encode()).hexdigest()[:8]
        sanitized.append(part)
    return "/".join(sanitized)


def make_correct_url(relative_path: str) -> str:
    """relative_path → 올바른 Storage public URL."""
    storage_key = _sanitize_storage_key(relative_path)
    return f"{SUPABASE_URL}/storage/v1/object/public/{BUCKET}/{storage_key}"


def main():
    print("support_document_images.public_url 업데이트 시작 (relative_path 기반)...")

    offset = 0
    batch = 500
    updated = 0
    skipped = 0
    errors = 0

    while True:
        # 매 배치마다 새 클라이언트 생성 (연결 재사용 문제 방지)
        client = create_client(SUPABASE_URL, SUPABASE_KEY)

        result = (
            client.table("support_document_images")
            .select("id, filename, relative_path, public_url")
            .range(offset, offset + batch - 1)
            .execute()
        )
        rows = result.data or []
        if not rows:
            break

        for row in rows:
            relative_path = (row.get("relative_path") or "").strip()
            filename = (row.get("filename") or "").strip()

            if not relative_path and not filename:
                skipped += 1
                continue

            # relative_path 우선, 없으면 filename만으로 조립
            if relative_path:
                new_url = make_correct_url(relative_path)
            else:
                new_url = make_correct_url(filename)

            current_url = (row.get("public_url") or "").strip()
            if current_url == new_url:
                skipped += 1
                continue

            try:
                client.table("support_document_images").update(
                    {"public_url": new_url}
                ).eq("id", row["id"]).execute()
                updated += 1
            except Exception as e:
                errors += 1
                print(f"  [오류] id={row['id']}: {e}")

        print(f"  처리: {offset + len(rows)}개 (업데이트: {updated}, 스킵: {skipped}, 오류: {errors})")
        offset += batch

        # 배치 사이 잠깐 대기 (연결 과부하 방지)
        time.sleep(0.3)

    print(f"\n완료! 총 {updated}개 URL 업데이트됨. (스킵: {skipped}, 오류: {errors})")


if __name__ == "__main__":
    main()
