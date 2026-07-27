from datetime import date, datetime
from sqlalchemy import Boolean, Date, DateTime, Float, ForeignKey, Index, Integer, JSON, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.core.database import Base

class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    full_name: Mapped[str] = mapped_column(String(160))
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(32), default="viewer", index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

class Student(Base):
    __tablename__ = "students"
    id: Mapped[int] = mapped_column(primary_key=True)
    first_name: Mapped[str] = mapped_column(String(80), index=True)
    last_name: Mapped[str] = mapped_column(String(80), index=True)
    school: Mapped[str | None] = mapped_column(String(200))
    graduation_status: Mapped[str | None] = mapped_column(String(80))
    phone: Mapped[str | None] = mapped_column(String(40))
    email: Mapped[str | None] = mapped_column(String(255))
    consent_given: Mapped[bool] = mapped_column(Boolean, default=False)
    counselor_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    archived_at: Mapped[datetime | None] = mapped_column(DateTime)

class StudentExamResult(Base):
    __tablename__ = "student_exam_results"
    id: Mapped[int] = mapped_column(primary_key=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("students.id", ondelete="CASCADE"), index=True)
    year: Mapped[int] = mapped_column(Integer, default=2026)
    score_type: Mapped[str] = mapped_column(String(16), index=True)
    score: Mapped[float | None] = mapped_column(Float)
    rank: Mapped[int | None] = mapped_column(Integer, index=True)
    __table_args__ = (UniqueConstraint("student_id", "year", "score_type"),)

class Program(Base):
    __tablename__ = "programs"
    id: Mapped[int] = mapped_column(primary_key=True)
    data_year: Mapped[int] = mapped_column(Integer, default=2026, index=True)
    level: Mapped[str] = mapped_column(String(16), index=True)
    program_code: Mapped[str] = mapped_column(String(32), index=True)
    sector: Mapped[str | None] = mapped_column(String(100))
    university_type: Mapped[str | None] = mapped_column(String(80), index=True)
    region: Mapped[str | None] = mapped_column(String(80))
    city: Mapped[str | None] = mapped_column(String(100), index=True)
    location: Mapped[str | None] = mapped_column(String(120))
    university: Mapped[str] = mapped_column(String(255), index=True)
    faculty: Mapped[str | None] = mapped_column(String(255), index=True)
    program: Mapped[str] = mapped_column(String(255), index=True)
    note: Mapped[str | None] = mapped_column(Text)
    fee_status: Mapped[str | None] = mapped_column(String(160), index=True)
    language: Mapped[str | None] = mapped_column(String(80), index=True)
    education_type: Mapped[str | None] = mapped_column(String(80))
    duration: Mapped[str | None] = mapped_column(String(20))
    score_type: Mapped[str | None] = mapped_column(String(16), index=True)
    quota_2026: Mapped[int | None] = mapped_column(Integer)
    min_score_2025: Mapped[float | None] = mapped_column(Float)
    max_score_2025: Mapped[float | None] = mapped_column(Float)
    min_rank_2025: Mapped[int | None] = mapped_column(Integer, index=True)
    rank_status_2025: Mapped[str | None] = mapped_column(String(32), index=True)
    special_conditions: Mapped[str | None] = mapped_column(Text)
    threshold_rank: Mapped[int | None] = mapped_column(Integer)
    school_top_quota: Mapped[int | None] = mapped_column(Integer)
    martyr_veteran_quota: Mapped[int | None] = mapped_column(Integer)
    women_34_quota: Mapped[int | None] = mapped_column(Integer)
    tyc: Mapped[str | None] = mapped_column(String(80))
    accreditation: Mapped[str | None] = mapped_column(String(160))
    extra: Mapped[dict] = mapped_column(JSON, default=dict)
    __table_args__ = (UniqueConstraint("data_year", "program_code"), Index("ix_program_search", "level", "score_type", "city", "min_rank_2025"),)

class ProgramRankHistory(Base):
    __tablename__ = "program_rank_history"
    id: Mapped[int] = mapped_column(primary_key=True)
    program_id: Mapped[int] = mapped_column(ForeignKey("programs.id", ondelete="CASCADE"), index=True)
    year: Mapped[int] = mapped_column(Integer)
    rank: Mapped[int | None] = mapped_column(Integer)
    status: Mapped[str | None] = mapped_column(String(32))
    __table_args__ = (UniqueConstraint("program_id", "year"),)

class PreferenceList(Base):
    __tablename__ = "preference_lists"
    id: Mapped[int] = mapped_column(primary_key=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("students.id"), index=True)
    name: Mapped[str] = mapped_column(String(160), default="Tercih Listesi")
    version: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String(24), default="draft")
    score_type: Mapped[str | None] = mapped_column(String(16))
    created_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

class PreferenceItem(Base):
    __tablename__ = "preference_items"
    id: Mapped[int] = mapped_column(primary_key=True)
    preference_list_id: Mapped[int] = mapped_column(ForeignKey("preference_lists.id", ondelete="CASCADE"), index=True)
    program_id: Mapped[int] = mapped_column(ForeignKey("programs.id"))
    position: Mapped[int] = mapped_column(Integer)
    category: Mapped[str | None] = mapped_column(String(40))
    explanation: Mapped[str | None] = mapped_column(Text)
    note: Mapped[str | None] = mapped_column(Text)
    __table_args__ = (UniqueConstraint("preference_list_id", "program_id"), UniqueConstraint("preference_list_id", "position"))

    program: Mapped["Program"] = relationship()

class CounselingNote(Base):
    __tablename__ = "counseling_notes"
    id: Mapped[int] = mapped_column(primary_key=True)
    student_id: Mapped[int] = mapped_column(ForeignKey("students.id"), index=True)
    author_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    note: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

class ApplicationSetting(Base):
    __tablename__ = "application_settings"
    key: Mapped[str] = mapped_column(String(100), primary_key=True)
    value: Mapped[dict] = mapped_column(JSON)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

class DataImport(Base):
    __tablename__ = "data_imports"
    id: Mapped[int] = mapped_column(primary_key=True)
    data_year: Mapped[int] = mapped_column(Integer)
    file_name: Mapped[str] = mapped_column(String(255))
    file_hash: Mapped[str] = mapped_column(String(64), unique=True)
    uploaded_by: Mapped[int | None] = mapped_column(ForeignKey("users.id"))
    imported_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    record_count: Mapped[int] = mapped_column(Integer)
    is_active: Mapped[bool] = mapped_column(Boolean, default=False)
    report: Mapped[dict] = mapped_column(JSON, default=dict)

class AuditLog(Base):
    __tablename__ = "audit_logs"
    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int | None] = mapped_column(ForeignKey("users.id"), index=True)
    action: Mapped[str] = mapped_column(String(80), index=True)
    entity_type: Mapped[str] = mapped_column(String(80))
    entity_id: Mapped[str | None] = mapped_column(String(80))
    details: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
