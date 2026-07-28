import argparse
import json
import os
import secrets
from pathlib import Path


def bootstrap_admin(database: Path, input_file: Path) -> None:
    database_url = f"sqlite:///{database.resolve().as_posix()}"
    os.environ["DATABASE_URL"] = database_url
    env_file = database.resolve().parent / ".env"
    if not env_file.exists():
        env_file.write_text(
            f"DATABASE_URL={database_url}\n"
            f"SECRET_KEY={secrets.token_hex(32)}\n"
            "ACCESS_TOKEN_MINUTES=10080\n"
            "UPDATE_MANIFEST_URL=https://github.com/umudunatesi/"
            "2026-yks-tercih-robotu/releases/latest/download/latest.json\n",
            encoding="utf-8",
        )
    from sqlalchemy import select

    from app.core.database import Base, SessionLocal, engine
    from app.core.security import hash_password
    from app.models.entities import User

    try:
        payload = json.loads(input_file.read_text(encoding="utf-8-sig"))
        email = str(payload["email"]).strip().casefold()
        full_name = str(payload["full_name"]).strip()
        password = str(payload["password"])
        if "@" not in email or len(password) < 10 or not full_name:
            raise ValueError("Yönetici bilgileri geçersiz.")
        Base.metadata.create_all(engine)
        with SessionLocal.begin() as db:
            user = db.scalar(select(User).where(User.email == email))
            if user:
                user.full_name = full_name
                user.password_hash = hash_password(password)
                user.role = "admin"
                user.is_active = True
            else:
                db.add(User(
                    email=email,
                    full_name=full_name,
                    password_hash=hash_password(password),
                    role="admin",
                    is_active=True,
                ))
    finally:
        input_file.unlink(missing_ok=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bootstrap-admin-file", type=Path)
    parser.add_argument("--database", type=Path)
    args = parser.parse_args()
    if args.bootstrap_admin_file:
        if not args.database:
            parser.error("--database zorunludur")
        bootstrap_admin(args.database, args.bootstrap_admin_file)
        return

    import uvicorn
    from app.main import app

    uvicorn.run(app, host="127.0.0.1", port=8000, log_level="info")


if __name__ == "__main__":
    main()
