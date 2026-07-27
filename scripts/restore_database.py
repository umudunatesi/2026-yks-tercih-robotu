import argparse
import os
import sqlite3
import subprocess
from contextlib import closing
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).parents[1]


def sqlite_path(database_url: str) -> Path:
    raw = database_url.removeprefix("sqlite:///")
    return (ROOT / raw).resolve() if not Path(raw).is_absolute() else Path(raw).resolve()


def integrity_check(path: Path) -> None:
    with closing(sqlite3.connect(path)) as database:
        result = database.execute("PRAGMA integrity_check").fetchone()[0]
    if result != "ok":
        raise SystemExit(f"SQLite bütünlük kontrolü başarısız: {result}")


def main():
    parser = argparse.ArgumentParser(description="YKS veritabanı geri yükleme")
    parser.add_argument("backup")
    parser.add_argument(
        "--database-url",
        default=os.getenv("DATABASE_URL", "sqlite:///./backend/yks.db"),
    )
    parser.add_argument("--yes", action="store_true", help="Geri yüklemeyi onayla")
    args = parser.parse_args()
    if not args.yes:
        raise SystemExit("Bu işlem mevcut veriyi değiştirir. Onay için --yes kullanın.")

    backup = Path(args.backup).resolve()
    if not backup.is_file():
        raise SystemExit(f"Yedek bulunamadı: {backup}")

    if args.database_url.startswith("sqlite:///"):
        integrity_check(backup)
        target = sqlite_path(args.database_url)
        target.parent.mkdir(parents=True, exist_ok=True)
        safety_backup = target.with_name(
            f"{target.stem}-geri-yukleme-oncesi-"
            f"{datetime.now():%Y%m%d-%H%M%S}{target.suffix}"
        )
        if target.exists():
            with closing(sqlite3.connect(target)) as source, closing(
                sqlite3.connect(safety_backup)
            ) as dest:
                source.backup(dest)
        temporary = target.with_suffix(target.suffix + ".restore")
        temporary.unlink(missing_ok=True)
        with closing(sqlite3.connect(backup)) as source, closing(
            sqlite3.connect(temporary)
        ) as dest:
            source.backup(dest)
        integrity_check(temporary)
        os.replace(temporary, target)
        print(f"Geri yükleme tamamlandı: {target}")
        if safety_backup.exists():
            print(f"Önceki veritabanı güvenlik yedeği: {safety_backup}")
    elif args.database_url.startswith(("postgresql://", "postgresql+psycopg://")):
        url = args.database_url.replace("postgresql+psycopg://", "postgresql://", 1)
        subprocess.run(
            ["pg_restore", "--clean", "--if-exists", "--no-owner",
             "--dbname", url, str(backup)],
            check=True,
        )
        print(f"Geri yükleme tamamlandı: {args.database_url}")
    else:
        raise SystemExit("Desteklenmeyen DATABASE_URL")


if __name__ == "__main__":
    main()
