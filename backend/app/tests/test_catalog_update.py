import sqlite3

from app.services.catalog_update import merge_program_catalog


SCHEMA = """
CREATE TABLE programs (
    id INTEGER PRIMARY KEY,
    data_year INTEGER NOT NULL,
    program_code TEXT NOT NULL,
    program TEXT NOT NULL,
    UNIQUE(data_year, program_code)
);
CREATE TABLE program_rank_history (
    id INTEGER PRIMARY KEY,
    program_id INTEGER NOT NULL,
    year INTEGER NOT NULL,
    rank INTEGER,
    status TEXT
);
CREATE TABLE preference_items (
    id INTEGER PRIMARY KEY,
    program_id INTEGER NOT NULL
);
CREATE TABLE students (id INTEGER PRIMARY KEY, first_name TEXT);
"""


def create_database(path, catalog=False):
    database = sqlite3.connect(path)
    database.executescript(SCHEMA)
    if catalog:
        database.execute(
            "INSERT INTO programs VALUES (1, 2026, '100', 'Güncel Program')"
        )
        database.execute(
            "INSERT INTO programs VALUES (2, 2026, '200', 'Yeni Program')"
        )
        database.execute(
            "INSERT INTO program_rank_history VALUES (1, 1, 2025, 12345, NULL)"
        )
    else:
        database.execute(
            "INSERT INTO programs VALUES (10, 2026, '100', 'Eski Program')"
        )
        database.execute(
            "INSERT INTO programs VALUES (11, 2026, '300', 'Kaldırılacak')"
        )
        database.execute(
            "INSERT INTO programs VALUES (12, 2026, '400', 'Tercihte Kullanılan')"
        )
        database.execute("INSERT INTO preference_items VALUES (1, 12)")
        database.execute("INSERT INTO students VALUES (1, 'Ada')")
    database.commit()
    database.close()


def test_catalog_merge_preserves_personal_data_and_program_ids(tmp_path):
    main = tmp_path / "main.db"
    catalog = tmp_path / "catalog.db"
    create_database(main)
    create_database(catalog, catalog=True)

    result = merge_program_catalog(main, catalog)

    database = sqlite3.connect(main)
    programs = database.execute(
        "SELECT id, program_code, program FROM programs ORDER BY program_code"
    ).fetchall()
    students = database.execute("SELECT first_name FROM students").fetchall()
    preferences = database.execute(
        "SELECT program_id FROM preference_items"
    ).fetchall()
    history = database.execute(
        "SELECT program_id, year, rank FROM program_rank_history"
    ).fetchall()
    database.close()

    assert result == {"added": 1, "updated": 1, "removed": 1}
    assert programs == [
        (10, "100", "Güncel Program"),
        (13, "200", "Yeni Program"),
        (12, "400", "Tercihte Kullanılan"),
    ]
    assert students == [("Ada",)]
    assert preferences == [(12,)]
    assert history == [(10, 2025, 12345)]
