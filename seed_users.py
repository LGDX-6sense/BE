"""
가상 유저 5명 DB 시드 스크립트.
실행: python seed_users.py
"""
from db import get_engine, Base
from user_store import UserProfile
from sqlalchemy.orm import Session

DEMO_USERS = [
    {
        "name": "경옥",
        "phone": "010-3821-5647",
        "address": "서울특별시 강동구 천호대로 423 래미안강동팰리스 102동 804호",
        "birth_year": 1971,
        "devices": [
            {
                "category": "냉장고",
                "model_name": "LG 디오스 오브제컬렉션 냉장고",
                "model_no": "M873GYV451S",
                "serial": "604KAWR1P991",
                "purchased": "2021-03",
                "warranty_until": "2023-03",
            },
            {
                "category": "세탁기",
                "model_name": "LG 트롬 드럼세탁기",
                "model_no": "F21VDA",
                "serial": "112TROMB8821",
                "purchased": "2020-08",
                "warranty_until": "2022-08",
            },
        ],
    },
    {
        "name": "경은",
        "phone": "010-9204-7731",
        "address": "경기도 성남시 분당구 불정로 90 네이버그린팩토리 인근 판교역로 235 힐스테이트판교역 501호",
        "birth_year": 1993,
        "devices": [
            {
                "category": "에어컨",
                "model_name": "LG 휘센 벽걸이 에어컨",
                "model_no": "FQ18VDKSA",
                "serial": "305WHIS3K441",
                "purchased": "2023-05",
                "warranty_until": "2025-05",
            },
            {
                "category": "세탁기",
                "model_name": "LG 트롬 드럼세탁기",
                "model_no": "F19VDD",
                "serial": "208TROM5D662",
                "purchased": "2022-11",
                "warranty_until": "2024-11",
            },
        ],
    },
    {
        "name": "지영",
        "phone": "010-6642-3098",
        "address": "인천광역시 부평구 부평대로 168 부평삼성래미안 7동 1203호",
        "birth_year": 1982,
        "devices": [
            {
                "category": "냉장고",
                "model_name": "LG 디오스 양문형 냉장고",
                "model_no": "F873SS55E",
                "serial": "912DIOSX7723",
                "purchased": "2019-12",
                "warranty_until": "2021-12",
            },
            {
                "category": "에어컨",
                "model_name": "LG 휘센 스탠드 에어컨",
                "model_no": "SQ18BEKWSA",
                "serial": "207STAND2K11",
                "purchased": "2022-07",
                "warranty_until": "2024-07",
            },
        ],
    },
    {
        "name": "수현",
        "phone": "010-5519-8823",
        "address": "서울특별시 마포구 와우산로 94 홍익대학교 인근 서교자이 203호",
        "birth_year": 1998,
        "devices": [
            {
                "category": "세탁기",
                "model_name": "LG 트롬 미니워시",
                "model_no": "F12WM",
                "serial": "401MINI9W334",
                "purchased": "2023-09",
                "warranty_until": "2025-09",
            },
        ],
    },
    {
        "name": "혜민",
        "phone": "010-7734-2201",
        "address": "서울특별시 송파구 올림픽로 300 롯데월드타워 인근 파크리오 15동 602호",
        "birth_year": 1990,
        "devices": [
            {
                "category": "냉장고",
                "model_name": "LG 디오스 오브제컬렉션 냉장고",
                "model_no": "M874GBB251S",
                "serial": "101OBJEC4M55",
                "purchased": "2024-01",
                "warranty_until": "2026-01",
            },
            {
                "category": "세탁기",
                "model_name": "LG 트롬 드럼세탁기 오브제컬렉션",
                "model_no": "F21VDDS",
                "serial": "102TROMOB223",
                "purchased": "2024-01",
                "warranty_until": "2026-01",
            },
            {
                "category": "에어컨",
                "model_name": "LG 휘센 타워 에어컨",
                "model_no": "FQ18VDKSA",
                "serial": "306TOWER1A77",
                "purchased": "2024-06",
                "warranty_until": "2026-06",
            },
        ],
    },
]


def seed():
    engine = get_engine()
    Base.metadata.create_all(engine)

    with Session(engine) as db:
        existing = db.query(UserProfile).count()
        if existing > 0:
            print(f"이미 {existing}명의 유저가 있습니다. 스킵합니다.")
            print("초기화하려면 DB에서 user_profiles 테이블을 비우고 재실행하세요.")
            return

        for data in DEMO_USERS:
            db.add(UserProfile(**data))
        db.commit()
        print(f"✅ 더미 유저 {len(DEMO_USERS)}명 생성 완료!")
        for u in DEMO_USERS:
            devices = u["devices"]
            device_names = ", ".join(d["category"] for d in devices)
            print(f"  - {u['name']} ({u['birth_year']}) | {u['address'][:20]}... | {device_names}")


if __name__ == "__main__":
    seed()
