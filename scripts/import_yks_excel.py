import argparse, os, sys
from pathlib import Path
ROOT = Path(__file__).parents[1]
ORIGINAL_CWD = Path.cwd()
os.chdir(ROOT / "backend")
sys.path.insert(0, str(ROOT / "backend"))
from app.core.database import Base, SessionLocal, engine
from app.importers.yks_excel import analyze, iter_programs
from app.models.entities import (
    DataImport, PreferenceItem, Program, ProgramRankHistory,
)
from sqlalchemy import func, insert, select

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("file"); parser.add_argument("--year", type=int, default=2026)
    parser.add_argument("--analyze-only", action="store_true")
    args = parser.parse_args()
    source_file = Path(args.file)
    source_file = (ORIGINAL_CWD / source_file).resolve() if not source_file.is_absolute() else source_file.resolve()
    report = analyze(source_file); print(report)
    if args.analyze_only: return
    if not report["matches_expected"] or report["duplicate_codes"]:
        raise SystemExit("Doğrulama başarısız; veri tabanında değişiklik yapılmadı.")
    Base.metadata.create_all(engine)
    with SessionLocal.begin() as db:
        db.query(DataImport).update({DataImport.is_active: False})
        imported = db.query(DataImport).filter_by(file_hash=report["sha256"]).one_or_none()
        if imported is None:
            imported = DataImport(data_year=args.year, file_name=Path(args.file).name,
                                  file_hash=report["sha256"], record_count=report["total"],
                                  is_active=True, report=report)
            db.add(imported)
        else:
            imported.data_year = args.year
            imported.file_name = Path(args.file).name
            imported.record_count = report["total"]
            imported.is_active = True
            imported.report = report
        existing_count = db.scalar(
            select(func.count(Program.id)).where(Program.data_year == args.year)
        ) or 0
        if existing_count == 0:
            program_rows = []
            history_by_code = {}
            for data in iter_programs(source_file):
                history_by_code[data["program_code"]] = data.pop("history")
                program_rows.append(data)
            inserted = db.execute(
                insert(Program).returning(Program.id, Program.program_code),
                program_rows,
            )
            ids_by_code = {
                row.program_code: row.id for row in inserted
            }
            history_rows = [
                {
                    "program_id": ids_by_code[program_code],
                    **history,
                }
                for program_code, histories in history_by_code.items()
                for history in histories
            ]
            if history_rows:
                db.execute(insert(ProgramRankHistory), history_rows)
            print(
                f"{report['total']} kayıt toplu olarak içe aktarıldı; "
                "0 eski kayıt kaldırıldı, 0 kullanılan kayıt korundu."
            )
            return
        imported_codes = set()
        for data in iter_programs(source_file):
            history = data.pop("history")
            imported_codes.add(data["program_code"])
            program = db.scalar(db.query(Program).filter_by(data_year=args.year, program_code=data["program_code"]).statement)
            if program is None:
                program = Program(**data); db.add(program); db.flush()
            else:
                for key, value in data.items(): setattr(program, key, value)
                db.query(ProgramRankHistory).filter_by(program_id=program.id).delete()
            db.add_all(ProgramRankHistory(program_id=program.id, **item) for item in history)
        removed = retained = 0
        stale_programs = db.query(Program).filter(
            Program.data_year == args.year,
            Program.program_code.notin_(imported_codes),
        ).all()
        for program in stale_programs:
            is_used = db.query(PreferenceItem.id).filter_by(
                program_id=program.id
            ).first()
            if is_used:
                retained += 1
                continue
            db.query(ProgramRankHistory).filter_by(
                program_id=program.id
            ).delete()
            db.delete(program)
            removed += 1
    print(
        f"{report['total']} kayıt başarıyla içe aktarıldı; "
        f"{removed} eski kayıt kaldırıldı, {retained} kullanılan kayıt korundu."
    )
if __name__ == "__main__": main()
