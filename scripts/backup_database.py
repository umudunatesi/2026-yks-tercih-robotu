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


def main():
    parser = argparse.ArgumentParser(description="YKS veritabanı yedeği")
    parser.add_argument(
        "--database-url",
        default=os.getenv("DATABASE_URL", "sqlite:///./backend/yks.db"),
    )
    parser.add_argument("--output-dir", default=str(ROOT / "backups"))
    parser.add_argument("--keep", type=int, default=10)
    args = parser.parse_args()

    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")

    if args.database_url.startswith("sqlite:///"):
        source = sqlite_path(args.database_url)
        if not source.is_file():
            raise SystemExit(f"SQLite dosyası bulunamadı: {source}")
        target = output_dir / f"yks-{stamp}.db"
        with closing(sqlite3.connect(source)) as source_db, closing(
            sqlite3.connect(target)
        ) as target_db:
            source_db.backup(target_db)
        with closing(sqlite3.connect(target)) as check_db:
            result = check_db.execute("PRAGMA integrity_check").fetchone()[0]
            if result != "ok":
                target.unlink(missing_ok=True)
                raise SystemExit(f"Yedek bütünlük kontrolü başarısız: {result}")
        backups = sorted(
            output_dir.glob("yks-*.db"),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )
        for old_backup in backups[max(args.keep, 1):]:
            old_backup.unlink()
    elif args.database_url.startswith(("postgresql://", "postgresql+psycopg://")):
        target = output_dir / f"yks-{stamp}.dump"
        url = args.database_url.replace("postgresql+psycopg://", "postgresql://", 1)
        subprocess.run(
            ["pg_dump", "--format=custom", "--file", str(target), url],
            check=True,
        )
    else:
        raise SystemExit("Desteklenmeyen DATABASE_URL")
    print(f"Yedek oluşturuldu: {target}")


if __name__ == "__main__":
    main()
