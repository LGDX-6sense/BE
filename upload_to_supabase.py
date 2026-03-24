from __future__ import annotations

import argparse
import hashlib
import mimetypes
import os
import re
import unicodedata
from pathlib import Path

from pipeline import PROJECT_ROOT

try:
    from supabase import create_client
except ImportError:
    raise ImportError("Missing required package: supabase. Install it with `pip install supabase`.")


DEFAULT_IMAGES_DIR = PROJECT_ROOT / "images"
DEFAULT_BUCKET = os.getenv("SUPABASE_IMAGES_BUCKET", "support-images")


def ensure_supabase_client():
    supabase_url = str(os.getenv("SUPABASE_URL", "")).strip()
    service_role_key = str(os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")).strip()
    if not supabase_url or not service_role_key:
        raise EnvironmentError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set.")
    return create_client(supabase_url, service_role_key)


def _sanitize_storage_key(path: str) -> str:
    """Convert a path to an ASCII-safe Supabase storage key."""
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


def _extract_public_url(result) -> str:
    if isinstance(result, str):
        return result
    if isinstance(result, dict):
        for key in ("publicUrl", "publicURL", "signedURL", "signedUrl"):
            value = result.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
    return ""


def upload_images(images_dir: Path = DEFAULT_IMAGES_DIR, bucket: str = DEFAULT_BUCKET) -> dict:
    if not images_dir.exists():
        raise FileNotFoundError(f"Images directory not found: {images_dir}")

    client = ensure_supabase_client()
    uploaded = 0
    failed = 0
    url_map: dict[str, str] = {}

    all_files = [p for p in images_dir.rglob("*") if p.is_file()]
    total = len(all_files)
    print(f"총 {total}개 파일 업로드 시작... (버킷: {bucket})")

    for i, path in enumerate(all_files, 1):
        relative_path = _sanitize_storage_key(path.relative_to(images_dir).as_posix())
        mime_type, _ = mimetypes.guess_type(str(path))
        mime_type = mime_type or "application/octet-stream"

        try:
            with path.open("rb") as file_handle:
                client.storage.from_(bucket).upload(
                    path=relative_path,
                    file=file_handle,
                    file_options={"content-type": mime_type, "upsert": "true"},
                )

            public_url = _extract_public_url(client.storage.from_(bucket).get_public_url(relative_path))
            url_map[relative_path] = public_url
            uploaded += 1

            if i % 100 == 0 or i == total:
                print(f"[{i}/{total}] 완료: {uploaded}개 성공, {failed}개 실패")

        except Exception as e:
            failed += 1
            print(f"[{i}/{total}] 실패: {relative_path} — {e}")

    return {"uploaded": uploaded, "failed": failed, "bucket": bucket, "url_map": url_map}


def main() -> None:
    parser = argparse.ArgumentParser(description="Upload images directory to Supabase Storage.")
    parser.add_argument("--images-dir", default=str(DEFAULT_IMAGES_DIR), help="Path to images directory")
    parser.add_argument("--bucket", default=DEFAULT_BUCKET, help="Supabase storage bucket name")
    args = parser.parse_args()

    result = upload_images(Path(args.images_dir), args.bucket)
    print(
        f"\n완료! 성공: {result['uploaded']}개, 실패: {result['failed']}개, 버킷: `{result['bucket']}`"
    )


if __name__ == "__main__":
    main()
