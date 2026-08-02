from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session

from app.core.database import Base
from app.core.text_search import normalize_search
from app.main import programs
from app.models.entities import Program


def test_education_type_aliases_match_excel_codes():
    engine = create_engine("sqlite://")

    @event.listens_for(engine, "connect")
    def register_search_function(connection, _):
        connection.create_function(
            "tr_fold", 1, normalize_search, deterministic=True
        )

    Base.metadata.create_all(engine)
    with Session(engine) as session:
        session.add_all([
            Program(
                level="lisans",
                program_code="1001",
                university="Örnek Üniversitesi",
                program="Açık Program",
                education_type="AÖ",
            ),
            Program(
                level="lisans",
                program_code="1002",
                university="Örnek Üniversitesi",
                program="Uzaktan Program",
                education_type="UÖ",
            ),
            Program(
                level="lisans",
                program_code="1003",
                university="Örnek Üniversitesi",
                program="Örgün Program",
                education_type=None,
            ),
        ])
        session.commit()

        open_programs = programs(
            education_type="Açıköğretim", page=1, page_size=50, db=session
        )
        open_programs_from_search = programs(
            q="Açıköğretim", page=1, page_size=50, db=session
        )
        remote_programs = programs(
            education_type="Uzaktan", page=1, page_size=50, db=session
        )
        combined = programs(
            education_type="Açıköğretim,Uzaktan",
            page=1,
            page_size=50,
            db=session,
        )
        formal = programs(
            education_type="Örgün", page=1, page_size=50, db=session
        )

    assert [item["program_code"] for item in open_programs["items"]] == ["1001"]
    assert [
        item["program_code"] for item in open_programs_from_search["items"]
    ] == ["1001"]
    assert [item["program_code"] for item in remote_programs["items"]] == ["1002"]
    assert {item["program_code"] for item in combined["items"]} == {"1001", "1002"}
    assert [item["program_code"] for item in formal["items"]] == ["1003"]


def test_free_fee_filter_matches_empty_and_explicit_values():
    engine = create_engine("sqlite://")

    @event.listens_for(engine, "connect")
    def register_search_function(connection, _):
        connection.create_function(
            "tr_fold", 1, normalize_search, deterministic=True
        )

    Base.metadata.create_all(engine)
    with Session(engine) as session:
        session.add_all([
            Program(
                level="lisans", program_code="2001", university="Devlet Ü.",
                program="Ücretsiz Program", fee_status=None,
            ),
            Program(
                level="lisans", program_code="2002", university="Devlet Ü.",
                program="Açıkça Ücretsiz Program", fee_status="Ücretsiz",
            ),
            Program(
                level="lisans", program_code="2003", university="Vakıf Ü.",
                program="Burslu Program", fee_status="Burslu",
            ),
        ])
        session.commit()

        free_programs = programs(
            fee_status="Ücretsiz", page=1, page_size=50, db=session
        )
        combined = programs(
            fee_status="Ücretsiz,Burslu", page=1, page_size=50, db=session
        )

    assert {item["program_code"] for item in free_programs["items"]} == {
        "2001", "2002"
    }
    assert {item["program_code"] for item in combined["items"]} == {
        "2001", "2002", "2003"
    }


def test_multiple_universities_and_program_names_can_be_combined():
    engine = create_engine("sqlite://")

    @event.listens_for(engine, "connect")
    def register_search_function(connection, _):
        connection.create_function(
            "tr_fold", 1, normalize_search, deterministic=True
        )

    Base.metadata.create_all(engine)
    with Session(engine) as session:
        session.add_all([
            Program(
                level="lisans", program_code="3001",
                university="Ankara Üniversitesi", program="Tıp",
            ),
            Program(
                level="lisans", program_code="3002",
                university="Hacettepe Üniversitesi", program="Tıp",
            ),
            Program(
                level="lisans", program_code="3003",
                university="Hacettepe Üniversitesi", program="Diş Hekimliği",
            ),
            Program(
                level="lisans", program_code="3004",
                university="Ege Üniversitesi", program="Tıp",
            ),
        ])
        session.commit()

        result = programs(
            university="Ankara Üniversitesi,Hacettepe Üniversitesi",
            program_name="Tıp,Diş Hekimliği",
            page=1,
            page_size=50,
            db=session,
        )

    assert {item["program_code"] for item in result["items"]} == {
        "3001", "3002", "3003"
    }
