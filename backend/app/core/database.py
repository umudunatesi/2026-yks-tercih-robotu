from sqlalchemy import create_engine, event, text
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from .config import settings
from .text_search import normalize_search

class Base(DeclarativeBase):
    pass

database_url = settings.database_url
if database_url.startswith("postgresql://"):
    database_url = database_url.replace(
        "postgresql://", "postgresql+psycopg://", 1
    )
connect_args = {"check_same_thread": False} if database_url.startswith("sqlite") else {}
engine = create_engine(database_url, connect_args=connect_args, pool_pre_ping=True)

if database_url.startswith("sqlite"):
    @event.listens_for(engine, "connect")
    def register_sqlite_functions(dbapi_connection, _):
        dbapi_connection.create_function(
            "tr_fold", 1, normalize_search, deterministic=True
        )
elif database_url.startswith("postgresql"):
    with engine.begin() as connection:
        connection.execute(text("""
            CREATE OR REPLACE FUNCTION tr_fold(input text)
            RETURNS text
            LANGUAGE sql
            IMMUTABLE
            PARALLEL SAFE
            AS $$
              SELECT trim(regexp_replace(
                lower(translate(coalesce(input, ''),
                  'ÇĞİIÖŞÜçğıöşü', 'CGIIOSUcgiosu')),
                '[^a-z0-9]+', ' ', 'g'
              ))
            $$
        """))

SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
