from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import BigInteger, DateTime, JSON, String, func, select
from sqlalchemy.orm import Mapped, Session, mapped_column

from db import Base


class UserProfile(Base):
    __tablename__ = "user_profiles"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(50), nullable=False)
    phone: Mapped[str] = mapped_column(String(20), nullable=False)
    address: Mapped[str] = mapped_column(String(200), nullable=False)
    birth_year: Mapped[Optional[int]] = mapped_column(nullable=True)
    devices: Mapped[Optional[List[Dict[str, Any]]]] = mapped_column(JSON, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        nullable=False,
        default=datetime.utcnow,
        server_default=func.current_timestamp(),
    )


def get_user_profile(db: Session, user_id: int) -> Optional[UserProfile]:
    return db.get(UserProfile, user_id)


def get_user_context_string(profile: UserProfile) -> str:
    """agent system prompt에 주입할 유저 정보 문자열 반환."""
    lines = [
        f"고객 이름: {profile.name}",
        f"연락처: {profile.phone}",
        f"주소: {profile.address}",
    ]
    devices = profile.devices or []
    if devices:
        lines.append("등록 제품:")
        for d in devices:
            model = d.get("model_name", "")
            model_no = d.get("model_no", "")
            purchased = d.get("purchased", "")
            warranty = d.get("warranty_until", "")
            line = f"  - {model} ({model_no})"
            if purchased:
                line += f"  구매: {purchased}"
            if warranty:
                line += f"  보증만료: {warranty}"
            lines.append(line)
    return "\n".join(lines)


def list_users(db: Session) -> List[UserProfile]:
    return list(db.scalars(select(UserProfile).order_by(UserProfile.id)))


def serialize_user(profile: UserProfile) -> Dict[str, Any]:
    return {
        "id": profile.id,
        "name": profile.name,
        "phone": profile.phone,
        "address": profile.address,
        "birth_year": profile.birth_year,
        "devices": profile.devices or [],
    }
