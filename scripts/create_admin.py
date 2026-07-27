import argparse
import getpass
import os
import sys
from pathlib import Path

ROOT = Path(__file__).parents[1]
os.chdir(ROOT / "backend")
sys.path.insert(0, str(ROOT / "backend"))

from sqlalchemy import func, select

from app.core.database import Base, SessionLocal, engine
from app.core.security import hash_password
from app.models.entities import User


def admin_exists() -> bool:
    Base.metadata.create_all(engine)
    with SessionLocal() as db:
        return bool(
            db.scalar(
                select(func.count(User.id)).where(
                    User.role == "admin", User.is_active.is_(True)
                )
            )
        )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check", action="store_true", help="Etkin yönetici varsa başarılı çık."
    )
    args = parser.parse_args()
    if args.check:
        raise SystemExit(0 if admin_exists() else 1)

    email = input("E-posta [admin@example.local]: ").strip() or "admin@example.local"
    name = input("Ad soyad [Sistem Yöneticisi]: ").strip() or "Sistem Yöneticisi"
    password = getpass.getpass(
        "Şifre (en az 10 karakter; yazarken ekranda görünmez): "
    )
    if len(password) < 10:
        raise SystemExit("Şifre çok kısa.")
    confirm = getpass.getpass("Şifre tekrar: ")
    if password != confirm:
        raise SystemExit("Şifreler eşleşmiyor.")

    Base.metadata.create_all(engine)
    with SessionLocal.begin() as db:
        user = db.scalar(select(User).where(User.email == email.casefold()))
        if user:
            user.full_name = name
            user.password_hash = hash_password(password)
            user.role = "admin"
            user.is_active = True
        else:
            db.add(
                User(
                    email=email.casefold(),
                    full_name=name,
                    password_hash=hash_password(password),
                    role="admin",
                )
            )
    print("Yönetici hesabı hazır.")


if __name__ == "__main__":
    main()
