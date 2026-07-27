import argparse
import sqlite3
from pathlib import Path


PERSONAL_TABLES = (
    "preference_items",
    "preference_lists",
    "student_exam_results",
    "counseling_notes",
    "students",
    "audit_logs",
    "users",
)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Kişisel veri içermeyen dağıtım veritabanı hazırlar."
    )
    parser.add_argument("source")
    parser.add_argument("destination")
    args = parser.parse_args()

    source = Path(args.source).resolve()
    destination = Path(args.destination).resolve()
    if not source.is_file():
        raise SystemExit(f"Kaynak veritabanı bulunamadı: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.unlink(missing_ok=True)

    with sqlite3.connect(source) as source_db, sqlite3.connect(destination) as target_db:
        source_db.backup(target_db)

    with sqlite3.connect(destination) as database:
        database.execute("PRAGMA foreign_keys=OFF")
        for table in PERSONAL_TABLES:
            database.execute(f'DELETE FROM "{table}"')
        has_sequence = database.execute(
            "SELECT 1 FROM sqlite_master "
            "WHERE type='table' AND name='sqlite_sequence'"
        ).fetchone()
        if has_sequence:
            database.execute(
                "DELETE FROM sqlite_sequence WHERE name IN "
                f"({','.join('?' for _ in PERSONAL_TABLES)})",
                PERSONAL_TABLES,
            )
        database.commit()
        database.execute("VACUUM")
        integrity = database.execute("PRAGMA integrity_check").fetchone()[0]
        programs = database.execute("SELECT COUNT(*) FROM programs").fetchone()[0]
        users = database.execute("SELECT COUNT(*) FROM users").fetchone()[0]
        students = database.execute("SELECT COUNT(*) FROM students").fetchone()[0]

    if integrity != "ok" or programs < 21482 or users != 0 or students != 0:
        destination.unlink(missing_ok=True)
        raise SystemExit(
            "Dağıtım veritabanı doğrulanamadı: "
            f"{integrity=}, {programs=}, {users=}, {students=}"
        )
    print(
        f"Temiz dağıtım veritabanı hazır: {destination} "
        f"({programs} program, kişisel veri yok)"
    )


if __name__ == "__main__":
    main()
