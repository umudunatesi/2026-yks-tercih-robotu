import sqlite3
from pathlib import Path
from urllib.parse import unquote


def sqlite_database_path(database_url: str, working_directory: Path) -> Path | None:
    prefix = "sqlite:///"
    if not database_url.startswith(prefix):
        return None
    value = unquote(database_url[len(prefix):])
    path = Path(value)
    if not path.is_absolute():
        path = working_directory / path
    return path.resolve()


def merge_program_catalog(
    database_path: Path, catalog_path: Path
) -> dict[str, int]:
    if not catalog_path.exists():
        return {"added": 0, "updated": 0, "removed": 0}
    database = sqlite3.connect(database_path)
    try:
        database.execute("PRAGMA foreign_keys = ON")
        database.execute("ATTACH DATABASE ? AS catalog", (str(catalog_path),))
        program_columns = [
            row[1] for row in database.execute("PRAGMA main.table_info(programs)")
            if row[1] != "id"
        ]
        if not program_columns:
            raise RuntimeError("Ana veritabanında programs tablosu bulunamadı")
        catalog_columns = {
            row[1] for row in database.execute(
                "PRAGMA catalog.table_info(programs)"
            )
        }
        missing = set(program_columns) - catalog_columns
        if missing:
            raise RuntimeError(
                f"Program kataloğu sütunları eksik: {sorted(missing)}"
            )

        before_codes = {
            row[0] for row in database.execute(
                "SELECT program_code FROM main.programs WHERE data_year = 2026"
            )
        }
        catalog_codes = {
            row[0] for row in database.execute(
                "SELECT program_code FROM catalog.programs WHERE data_year = 2026"
            )
        }
        quoted = ", ".join(f'"{column}"' for column in program_columns)
        assignments = ", ".join(
            f'"{column}" = excluded."{column}"'
            for column in program_columns
            if column not in {"data_year", "program_code"}
        )
        database.execute("BEGIN IMMEDIATE")
        database.execute(
            f"""
            INSERT INTO main.programs ({quoted})
            SELECT {quoted} FROM catalog.programs WHERE data_year = 2026
            ON CONFLICT(data_year, program_code) DO UPDATE SET {assignments}
            """
        )
        database.execute(
            """
            DELETE FROM main.program_rank_history
            WHERE program_id IN (
                SELECT main_program.id
                FROM main.programs AS main_program
                JOIN catalog.programs AS catalog_program
                  ON catalog_program.data_year = main_program.data_year
                 AND catalog_program.program_code = main_program.program_code
                WHERE main_program.data_year = 2026
            )
            """
        )
        database.execute(
            """
            INSERT INTO main.program_rank_history
                (program_id, year, rank, status)
            SELECT main_program.id, history.year, history.rank, history.status
            FROM catalog.program_rank_history AS history
            JOIN catalog.programs AS catalog_program
              ON catalog_program.id = history.program_id
            JOIN main.programs AS main_program
              ON main_program.data_year = catalog_program.data_year
             AND main_program.program_code = catalog_program.program_code
            WHERE catalog_program.data_year = 2026
            """
        )
        stale_ids = [
            row[0] for row in database.execute(
                """
                SELECT program.id
                FROM main.programs AS program
                WHERE program.data_year = 2026
                  AND NOT EXISTS (
                      SELECT 1 FROM catalog.programs AS current
                      WHERE current.data_year = program.data_year
                        AND current.program_code = program.program_code
                  )
                  AND NOT EXISTS (
                      SELECT 1 FROM main.preference_items AS item
                      WHERE item.program_id = program.id
                  )
                """
            )
        ]
        if stale_ids:
            placeholders = ",".join("?" for _ in stale_ids)
            database.execute(
                f"DELETE FROM main.program_rank_history "
                f"WHERE program_id IN ({placeholders})",
                stale_ids,
            )
            database.execute(
                f"DELETE FROM main.programs WHERE id IN ({placeholders})",
                stale_ids,
            )
        database.commit()
        return {
            "added": len(catalog_codes - before_codes),
            "updated": len(catalog_codes & before_codes),
            "removed": len(stale_ids),
        }
    except Exception:
        database.rollback()
        raise
    finally:
        database.close()


def apply_packaged_catalog(database_url: str, working_directory: Path) -> dict:
    database_path = sqlite_database_path(database_url, working_directory)
    catalog_path = working_directory / "catalog-update.db"
    if database_path is None or not catalog_path.exists():
        return {"added": 0, "updated": 0, "removed": 0}
    result = merge_program_catalog(database_path, catalog_path)
    catalog_path.unlink(missing_ok=True)
    return result
