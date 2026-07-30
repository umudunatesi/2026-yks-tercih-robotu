import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
os.chdir(BACKEND)
sys.path.insert(0, str(BACKEND))

from sqlalchemy import func, select

from app.core.database import Base, SessionLocal, engine
from app.core.security import hash_password
from app.models.entities import Program, User


def seed_catalog() -> None:
    with SessionLocal() as database:
        program_count = database.scalar(select(func.count(Program.id))) or 0
    if program_count:
        print(f"Program kataloğu hazır: {program_count} kayıt")
        return
    files = sorted((ROOT / "data").glob("*.xlsx"))
    if not files:
        raise SystemExit("Başlangıç program kataloğu bulunamadı.")
    subprocess.run(
        [
            sys.executable,
            str(ROOT / "scripts" / "import_yks_excel.py"),
            str(files[-1]),
            "--year",
            "2026",
        ],
        cwd=ROOT,
        check=True,
    )


def bootstrap_admin() -> None:
    email = os.getenv("ADMIN_EMAIL", "").strip().casefold()
    password = os.getenv("ADMIN_PASSWORD", "")
    full_name = os.getenv("ADMIN_NAME", "Sistem Yöneticisi").strip()
    with SessionLocal.begin() as database:
        user_count = database.scalar(select(func.count(User.id))) or 0
        if not email or not password:
            if user_count == 0:
                raise SystemExit(
                    "İlk kurulum için ADMIN_EMAIL ve ADMIN_PASSWORD gereklidir."
                )
            return
        if "@" not in email or len(password) < 10 or not full_name:
            raise SystemExit("Bulut yönetici bilgileri geçersiz.")
        user = database.scalar(select(User).where(User.email == email))
        if user is None:
            database.add(
                User(
                    email=email,
                    full_name=full_name,
                    password_hash=hash_password(password),
                    role="admin",
                    is_active=True,
                )
            )
        else:
            user.full_name = full_name
            user.password_hash = hash_password(password)
            user.role = "admin"
            user.is_active = True


def main() -> None:
    Base.metadata.create_all(engine)
    seed_catalog()
    bootstrap_admin()
    print("Bulut başlangıç işlemleri tamamlandı.")


if __name__ == "__main__":
    main()
