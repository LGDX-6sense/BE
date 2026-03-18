from __future__ import annotations

import os
from typing import Any, Dict, Generator, Optional

from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session, declarative_base, sessionmaker


def build_database_url() -> Optional[str]:
    """Build a MySQL connection URL from environment variables."""
    direct_url = os.getenv("DATABASE_URL", "").strip()
    if direct_url:
        return direct_url

    user = os.getenv("DB_USER", "dx_app")
    password = os.getenv("DB_PASSWORD", "").strip()
    host = os.getenv("DB_HOST", "127.0.0.1")
    port = os.getenv("DB_PORT", "3306")
    name = os.getenv("DB_NAME", "dx_chat")
    charset = os.getenv("DB_CHARSET", "utf8mb4")
    if not password:
        return None
    return f"mysql+pymysql://{user}:{password}@{host}:{port}/{name}?charset={charset}"


DATABASE_URL = build_database_url()
Base = declarative_base()
_engine = None
_SessionLocal = None


def get_engine():
    """Create the SQLAlchemy engine lazily once configuration is available."""
    global _engine, _SessionLocal
    if not DATABASE_URL:
        raise RuntimeError(
            "Database is not configured. Set DATABASE_URL or DB_PASSWORD before starting the server."
        )
    if _engine is None:
        _engine = create_engine(
            DATABASE_URL,
            pool_pre_ping=True,
            future=True,
        )
        _SessionLocal = sessionmaker(
            bind=_engine,
            autoflush=False,
            autocommit=False,
            future=True,
        )
    return _engine


def get_session_factory():
    """Return the configured SQLAlchemy session factory."""
    get_engine()
    return _SessionLocal


def get_db() -> Generator[Session, None, None]:
    """Yield a SQLAlchemy session for request-scoped database work."""
    db = get_session_factory()()
    try:
        yield db
    finally:
        db.close()


def test_database_connection() -> None:
    """Raise an exception if the database is not reachable."""
    with get_engine().connect() as connection:
        connection.execute(text("SELECT 1"))


def get_database_status() -> Dict[str, Any]:
    """Return a lightweight database health payload."""
    try:
        test_database_connection()
        return {
            "configured": True,
            "database_url": get_engine().url.render_as_string(hide_password=True),
            "connected": True,
        }
    except Exception as error:
        return {
            "configured": bool(DATABASE_URL),
            "database_url": get_engine().url.render_as_string(hide_password=True)
            if DATABASE_URL
            else None,
            "connected": False,
            "error": str(error),
        }
