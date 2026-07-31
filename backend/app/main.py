from pathlib import Path
from tempfile import NamedTemporaryFile
from datetime import datetime
import json
import logging
from logging.handlers import RotatingFileHandler
import os
import shutil
import subprocess
import tempfile
from urllib.parse import urlparse
from urllib.request import Request as UrlRequest, urlopen
from uuid import uuid4
from fastapi import Depends, FastAPI, File, HTTPException, Query, Request, Response, UploadFile
from fastapi.responses import FileResponse, JSONResponse
from fastapi.security import OAuth2PasswordRequestForm
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy import and_, func, literal, or_, select
from sqlalchemy.orm import Session
from app.core.database import Base, engine, get_db
from app.core.config import settings
from app.core.regions import cities_for_regions
from app.core.text_search import normalize_search
from app.core.security import create_access_token, current_user, hash_password, require_roles, verify_password
from app.importers.yks_excel import analyze as analyze_excel, iter_programs
from app.models.entities import ApplicationSetting, AuditLog, CounselingNote, DataImport, Program, ProgramRankHistory, Student, StudentExamResult, User, PreferenceList, PreferenceItem
from app.services.exports import preference_csv, preference_pdf, preference_xlsx
from app.services.catalog_update import apply_packaged_catalog
from app.services.recommendation import classify
from app.services.special_conditions import condition_details
from app.services.special_talent import (
    filter_special_talent_programs,
    special_talent_data,
    special_talent_filter_options,
)

Base.metadata.create_all(engine)
catalog_update_result = apply_packaged_catalog(
    settings.database_url, Path.cwd()
)
APP_VERSION = "1.3.8"
OFFICIAL_UPDATE_MANIFEST_URL = (
    "https://github.com/umudunatesi/2026-yks-tercih-robotu/"
    "releases/latest/download/latest.json"
)
app = FastAPI(title="2026 YKS Tercih Robotu API", version=APP_VERSION)


@app.get("/api/health", include_in_schema=False)
def health():
    return {"status": "ok", "version": APP_VERSION}

runtime_dir = Path(__file__).resolve().parents[2] / "runtime"
runtime_dir.mkdir(parents=True, exist_ok=True)
error_handler = RotatingFileHandler(
    runtime_dir / "application-error.log",
    maxBytes=2_000_000,
    backupCount=5,
    encoding="utf-8",
)
error_handler.setFormatter(logging.Formatter(
    "%(asctime)s | %(levelname)s | %(name)s | %(message)s"
))
app_logger = logging.getLogger("yks.application")
app_logger.setLevel(logging.INFO)
if not app_logger.handlers:
    app_logger.addHandler(error_handler)
app_logger.propagate = False

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        origin.strip()
        for origin in settings.cors_origins.split(",")
        if origin.strip()
    ],
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.middleware("http")
async def recover_from_unexpected_errors(request: Request, call_next):
    try:
        return await call_next(request)
    except Exception:
        error_id = uuid4().hex[:10].upper()
        app_logger.exception(
            "Takip kodu=%s method=%s path=%s",
            error_id,
            request.method,
            request.url.path,
        )
        return JSONResponse(
            status_code=500,
            content={
                "detail": (
                    "Beklenmeyen bir hata oluştu. İşlemi tekrar deneyin. "
                    f"Takip kodu: {error_id}"
                )
            },
        )

class StudentIn(BaseModel):
    first_name: str; last_name: str; school: str | None = None
    graduation_status: str | None = None; phone: str | None = None; email: str | None = None
    consent_given: bool = False

class UserIn(BaseModel):
    email: str; full_name: str; password: str; role: str = "viewer"

class UserUpdate(BaseModel):
    full_name: str | None = None; role: str | None = None
    is_active: bool | None = None; password: str | None = None

class CounselingNoteIn(BaseModel):
    note: str

class PreferenceItemIn(BaseModel):
    program_id: int; position: int; category: str | None = None
    explanation: str | None = None; note: str | None = None

class PreferenceIn(BaseModel):
    student_id: int; name: str = "Tercih Listesi"; score_type: str | None = None
    items: list[PreferenceItemIn] = []

class PreferenceUpdate(BaseModel):
    name: str | None = None
    status: str | None = None
    items: list[PreferenceItemIn] | None = None

class ThresholdSettings(BaseModel):
    high_target: float = -0.20
    target: float = -0.05
    balanced: float = 0.15

class UpdateSettings(BaseModel):
    manifest_url: str = ""
    automatic_check: bool = True

def get_update_settings(db: Session) -> dict:
    setting = db.get(ApplicationSetting, "update_settings")
    return setting.value if setting else {
        "manifest_url": os.getenv(
            "UPDATE_MANIFEST_URL", OFFICIAL_UPDATE_MANIFEST_URL
        ),
        "automatic_check": True,
    }

def version_tuple(value: str) -> tuple[int, ...]:
    try:
        return tuple(int(part) for part in value.strip().lstrip("v").split("."))
    except ValueError:
        raise HTTPException(502, "Güncelleme sunucusu geçersiz sürüm döndürdü")

def fetch_update_manifest(url: str) -> dict:
    parsed = urlparse(url)
    if parsed.scheme not in {"https", "http"} or not parsed.netloc:
        raise HTTPException(422, "Geçerli bir HTTP/HTTPS manifest adresi girin")
    try:
        request = UrlRequest(url, headers={"User-Agent": f"YKS-Tercih-Robotu/{APP_VERSION}"})
        with urlopen(request, timeout=12) as response:
            manifest = json.loads(response.read(1_000_000).decode("utf-8"))
    except Exception as error:
        raise HTTPException(502, f"Güncelleme bilgisi alınamadı: {error}")
    required = {"version", "download_url", "sha256"}
    if not isinstance(manifest, dict) or not required.issubset(manifest):
        raise HTTPException(502, "Güncelleme manifesti eksik veya geçersiz")
    download = urlparse(str(manifest["download_url"]))
    if download.scheme not in {"https", "http"} or not download.netloc:
        raise HTTPException(502, "Güncelleme paket adresi geçersiz")
    sha256 = str(manifest["sha256"]).strip().upper()
    if len(sha256) != 64 or any(char not in "0123456789ABCDEF" for char in sha256):
        raise HTTPException(502, "Güncelleme SHA-256 değeri geçersiz")
    manifest["sha256"] = sha256
    manifest["available"] = version_tuple(str(manifest["version"])) > version_tuple(APP_VERSION)
    manifest["current_version"] = APP_VERSION
    return manifest

def get_thresholds(db: Session) -> dict:
    setting = db.get(ApplicationSetting, "recommendation_thresholds")
    return setting.value if setting else {
        "high_target": -0.20, "target": -0.05, "balanced": 0.15
    }

class ExamResultIn(BaseModel):
    year: int = 2026; score_type: str; score: float | None = None; rank: int | None = None

class StudentWithResultsIn(StudentIn):
    exam_results: list[ExamResultIn] = Field(default_factory=list)

def validate_exam_results(results: list[ExamResultIn]) -> None:
    allowed_types = {"TYT", "SAY", "EA", "SÖZ", "DİL"}
    score_types = [result.score_type for result in results]
    if len(score_types) != len(set(score_types)):
        raise HTTPException(422, "Aynı puan türü birden fazla kez girilemez")
    for result in results:
        if result.year != 2026:
            raise HTTPException(422, "Bu formda yalnızca 2026 sonuçları girilebilir")
        if result.score_type not in allowed_types:
            raise HTTPException(422, f"Geçersiz puan türü: {result.score_type}")
        if result.rank is not None and result.rank <= 0:
            raise HTTPException(422, "Başarı sırası pozitif olmalıdır")
        if result.score is not None and not 0 < result.score <= 600:
            raise HTTPException(422, "Puan 0 ile 600 arasında olmalıdır")

@app.get("/health")
def health(): return {"status": "ok"}

@app.post("/api/auth/login")
def login(form: OAuth2PasswordRequestForm = Depends(), db: Session = Depends(get_db)):
    email = form.username.strip().casefold()
    user = db.scalar(select(User).where(User.email == email))
    if not user or not user.is_active or not verify_password(form.password, user.password_hash):
        raise HTTPException(401, "E-posta veya şifre hatalı")
    return {"access_token": create_access_token(user), "token_type": "bearer",
            "user": {"id": user.id, "email": user.email, "full_name": user.full_name, "role": user.role}}

@app.get("/api/auth/me")
def me(user: User = Depends(current_user)):
    return {"id": user.id, "email": user.email, "full_name": user.full_name, "role": user.role}

@app.get("/api/settings/recommendation-thresholds")
def recommendation_thresholds(db: Session = Depends(get_db),
                              _: User = Depends(current_user)):
    return get_thresholds(db)

@app.put("/api/settings/recommendation-thresholds")
def update_recommendation_thresholds(data: ThresholdSettings,
                                     db: Session = Depends(get_db),
                                     actor: User = Depends(require_roles("admin"))):
    if not (-1 < data.high_target < data.target < data.balanced < 2):
        raise HTTPException(422, "Eşikler küçükten büyüğe sıralı olmalıdır")
    setting = db.get(ApplicationSetting, "recommendation_thresholds")
    if setting:
        setting.value = data.model_dump()
    else:
        setting = ApplicationSetting(key="recommendation_thresholds",
                                     value=data.model_dump())
        db.add(setting)
    db.add(AuditLog(user_id=actor.id, action="settings.update",
                    entity_type="application_setting",
                    entity_id=setting.key, details=data.model_dump()))
    db.commit(); return setting.value

@app.get("/api/update/check")
def check_update(db: Session = Depends(get_db),
                 _: User = Depends(current_user)):
    settings = get_update_settings(db)
    if not settings.get("manifest_url"):
        return {
            "configured": False,
            "available": False,
            "current_version": APP_VERSION,
            "automatic_check": settings.get("automatic_check", True),
        }
    manifest = fetch_update_manifest(settings["manifest_url"])
    manifest["configured"] = True
    manifest["automatic_check"] = settings.get("automatic_check", True)
    return manifest

@app.get("/api/settings/update")
def read_update_settings(db: Session = Depends(get_db),
                         _: User = Depends(require_roles("admin"))):
    return {**get_update_settings(db), "current_version": APP_VERSION}

@app.put("/api/settings/update")
def save_update_settings(data: UpdateSettings,
                         db: Session = Depends(get_db),
                         actor: User = Depends(require_roles("admin"))):
    manifest_url = data.manifest_url.strip()
    if manifest_url:
        parsed = urlparse(manifest_url)
        if parsed.scheme not in {"https", "http"} or not parsed.netloc:
            raise HTTPException(422, "Geçerli bir HTTP/HTTPS manifest adresi girin")
    value = {"manifest_url": manifest_url,
             "automatic_check": data.automatic_check}
    setting = db.get(ApplicationSetting, "update_settings")
    if setting:
        setting.value = value
    else:
        setting = ApplicationSetting(key="update_settings", value=value)
        db.add(setting)
    db.add(AuditLog(user_id=actor.id, action="settings.update",
                    entity_type="application_setting",
                    entity_id="update_settings", details=value))
    db.commit()
    return {**value, "current_version": APP_VERSION}

@app.post("/api/update/install")
def install_update(db: Session = Depends(get_db),
                   actor: User = Depends(require_roles("admin"))):
    settings = get_update_settings(db)
    manifest_url = settings.get("manifest_url", "")
    if not manifest_url:
        raise HTTPException(422, "Önce güncelleme manifest adresini kaydedin")
    manifest = fetch_update_manifest(manifest_url)
    if not manifest["available"]:
        raise HTTPException(409, "Uygulama zaten güncel")
    project_root = Path(__file__).resolve().parents[2]
    updater_source = project_root / "scripts" / "update_windows.ps1"
    if not updater_source.exists():
        raise HTTPException(500, "Windows güncelleme yardımcısı bulunamadı")
    updater_copy = Path(tempfile.gettempdir()) / f"yks-updater-{uuid4().hex}.ps1"
    shutil.copy2(updater_source, updater_copy)
    creation_flags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0)
    creation_flags |= getattr(subprocess, "DETACHED_PROCESS", 0)
    subprocess.Popen(
        [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-File", str(updater_copy),
            "-InstallRoot", str(project_root),
            "-ManifestUrl", manifest_url,
            "-ExpectedVersion", str(manifest["version"]),
        ],
        cwd=str(project_root),
        creationflags=creation_flags,
        close_fds=True,
    )
    db.add(AuditLog(user_id=actor.id, action="update.start",
                    entity_type="application", entity_id=str(manifest["version"]),
                    details={"manifest_url": manifest_url}))
    db.commit()
    return {"started": True, "version": manifest["version"],
            "message": "Güncelleme başlatıldı; uygulama kısa süre içinde kapanıp yeniden açılacak."}

@app.post("/api/users", status_code=201)
def create_user(data: UserIn, db: Session = Depends(get_db), actor: User = Depends(require_roles("admin"))):
    if data.role not in {"admin", "counselor", "teacher", "viewer"}:
        raise HTTPException(422, "Geçersiz rol")
    if len(data.password) < 10: raise HTTPException(422, "Şifre en az 10 karakter olmalıdır")
    email = data.email.strip().casefold()
    full_name = data.full_name.strip()
    if not email or not full_name:
        raise HTTPException(422, "E-posta ve ad soyad boş bırakılamaz")
    if "@" not in email or email.startswith("@") or email.endswith("@"):
        raise HTTPException(422, "Geçerli bir e-posta adresi girin")
    if db.scalar(select(User.id).where(User.email == email)) is not None:
        raise HTTPException(409, "Bu e-posta adresiyle kayıtlı bir kullanıcı zaten var")
    obj = User(email=email, full_name=full_name, role=data.role, password_hash=hash_password(data.password))
    db.add(obj); db.flush(); db.add(AuditLog(user_id=actor.id, action="user.create", entity_type="user", entity_id=str(obj.id)))
    db.commit(); db.refresh(obj); return {"id": obj.id, "email": obj.email, "role": obj.role}

@app.get("/api/users")
def users(db: Session = Depends(get_db), _: User = Depends(require_roles("admin"))):
    rows = db.scalars(select(User).order_by(User.full_name)).all()
    return [{"id": x.id, "email": x.email, "full_name": x.full_name,
             "role": x.role, "is_active": x.is_active,
             "created_at": x.created_at} for x in rows]

@app.patch("/api/users/{user_id}")
def update_user(user_id: int, data: UserUpdate, db: Session = Depends(get_db),
                actor: User = Depends(require_roles("admin"))):
    user = db.get(User, user_id)
    if not user: raise HTTPException(404, "Kullanıcı bulunamadı")
    future_role = data.role if data.role is not None else user.role
    future_active = data.is_active if data.is_active is not None else user.is_active
    if user.role == "admin" and user.is_active and (
        future_role != "admin" or not future_active
    ):
        active_admins = db.scalar(
            select(func.count(User.id)).where(
                User.role == "admin", User.is_active.is_(True)
            )
        )
        if (active_admins or 0) <= 1:
            raise HTTPException(422, "Son aktif yönetici hesabı değiştirilemez")
    if data.role is not None:
        if data.role not in {"admin", "counselor", "teacher", "viewer"}:
            raise HTTPException(422, "Geçersiz rol")
        user.role = data.role
    if data.full_name is not None:
        full_name = data.full_name.strip()
        if not full_name: raise HTTPException(422, "Ad soyad boş bırakılamaz")
        user.full_name = full_name
    if data.is_active is not None:
        if user.id == actor.id and data.is_active is False:
            raise HTTPException(422, "Kendi hesabınızı pasifleştiremezsiniz")
        user.is_active = data.is_active
    if data.password is not None:
        if len(data.password) < 10: raise HTTPException(422, "Şifre en az 10 karakter olmalıdır")
        user.password_hash = hash_password(data.password)
    db.add(AuditLog(user_id=actor.id, action="user.update", entity_type="user",
                    entity_id=str(user.id), details={"role": user.role, "is_active": user.is_active}))
    db.commit(); return {"id": user.id, "role": user.role, "is_active": user.is_active}

@app.get("/api/special-talent-programs")
def special_talent_programs(
    q: str | None = None,
    institution_type: str | None = None,
    university: str | None = None,
    accreditation: str | None = None,
    condition_code: str | None = None,
    min_quota: int | None = None,
    max_quota: int | None = None,
    kktc_national_only: bool | None = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
):
    rows = filter_special_talent_programs(
        query=q,
        institution_type=institution_type,
        university=university,
        accreditation=accreditation,
        condition_code=condition_code,
        min_quota=min_quota,
        max_quota=max_quota,
        kktc_national_only=kktc_national_only,
    )
    start = (page - 1) * page_size
    return {
        "total": len(rows),
        "page": page,
        "items": rows[start:start + page_size],
        "filters": special_talent_filter_options(),
        "source": special_talent_data()["source"],
    }


@app.get("/api/programs")
def programs(q: str | None = None, level: str | None = None, city: str | None = None,
             university: str | None = None, regions: str | None = None,
             score_type: str | None = None, university_type: str | None = None,
             language: str | None = None, education_type: str | None = None,
             fee_status: str | None = None, accreditation: bool | None = None,
             school_top_quota: bool | None = None,
             martyr_veteran_quota: bool | None = None,
             women_34_quota: bool | None = None,
             status: str | None = None, min_quota: int | None = None, max_quota: int | None = None,
             min_rank: int | None = None, max_rank: int | None = None,
             page: int = Query(1, ge=1), page_size: int = Query(50, ge=1, le=200), db: Session = Depends(get_db)):
    stmt = select(Program)
    if q:
        normalized_query = normalize_search(q)
        # Match from the beginning of a word while allowing the user to type
        # a stem: "muhendis" finds "muhendislik", but "tip" does not match
        # the middle of "katip".
        needle = f"% {normalized_query}%"
        normalized_program = (
            literal(" ") + func.tr_fold(Program.program) + literal(" ")
        )
        normalized_code = (
            literal(" ") + func.tr_fold(Program.program_code) + literal(" ")
        )
        query_filters = [
            normalized_program.like(needle),
            normalized_code.like(needle),
        ]
        if normalized_query in {"acik", "acikogretim", "acik ogretim"}:
            query_filters.append(
                func.upper(func.trim(Program.education_type)) == "AÖ"
            )
        if normalized_query in {"uzaktan", "uzaktan ogretim"}:
            query_filters.append(
                func.upper(func.trim(Program.education_type)) == "UÖ"
            )
        stmt = stmt.where(or_(*query_filters))
    if level: stmt = stmt.where(Program.level == level)
    if city:
        stmt = stmt.where(func.tr_fold(Program.city) == normalize_search(city))
    if university:
        stmt = stmt.where(
            func.tr_fold(Program.university).like(
                f"%{normalize_search(university)}%"
            )
        )
    if regions:
        region_values = [x.strip() for x in regions.split(",") if x.strip()]
        if region_values:
            inferred_cities = cities_for_regions(region_values)
            region_filters = [Program.region.in_(region_values)]
            if inferred_cities:
                region_filters.append(
                    (Program.region.is_(None)) & (Program.city.in_(inferred_cities))
                )
            stmt = stmt.where(or_(*region_filters))
    if score_type:
        score_type_values = [
            value.strip() for value in score_type.split(",") if value.strip()
        ]
        if score_type_values:
            stmt = stmt.where(Program.score_type.in_(score_type_values))
    if university_type:
        university_type_values = [
            normalize_search(value)
            for value in university_type.split(",")
            if value.strip()
        ]
        if university_type_values:
            stmt = stmt.where(or_(*[
                func.tr_fold(Program.university_type).like(f"%{value}%")
                for value in university_type_values
            ]))
    if language:
        language_values = [
            normalize_search(value)
            for value in language.split(",")
            if value.strip()
        ]
        if language_values:
            stmt = stmt.where(or_(*[
                func.tr_fold(Program.language).like(f"%{value}%")
                for value in language_values
            ]))
    if education_type:
        education_type_values = [
            normalize_search(value)
            for value in education_type.split(",")
            if value.strip()
        ]
        if education_type_values:
            folded_education_type = func.tr_fold(Program.education_type)
            education_type_filters = []
            for value in education_type_values:
                if value in {"acikogretim", "ao"}:
                    education_type_filters.append(
                        folded_education_type.in_(["ao", "acikogretim"])
                    )
                elif value in {"uzaktan", "uzaktan ogretim", "uo"}:
                    education_type_filters.append(
                        folded_education_type.in_(["uo", "uzaktan", "uzaktan ogretim"])
                    )
                elif value == "orgun":
                    education_type_filters.append(or_(
                        Program.education_type.is_(None),
                        Program.education_type == "",
                        folded_education_type == "orgun",
                    ))
                elif value == "ikinci ogretim":
                    education_type_filters.append(
                        folded_education_type.like("%ikinci%")
                    )
                else:
                    education_type_filters.append(
                        folded_education_type.like(f"%{value}%")
                    )
            stmt = stmt.where(or_(*education_type_filters))
    if fee_status:
        fee_status_values = [
            normalize_search(value)
            for value in fee_status.split(",")
            if value.strip()
        ]
        if fee_status_values:
            stmt = stmt.where(or_(*[
                func.tr_fold(Program.fee_status).like(f"%{value}%")
                for value in fee_status_values
            ]))
    if accreditation is True: stmt = stmt.where(Program.accreditation.is_not(None), Program.accreditation != "")
    if school_top_quota is True: stmt = stmt.where(Program.school_top_quota > 0)
    if martyr_veteran_quota is True: stmt = stmt.where(Program.martyr_veteran_quota > 0)
    if women_34_quota is True: stmt = stmt.where(Program.women_34_quota > 0)
    if status:
        status_values = [value.strip() for value in status.split(",") if value.strip()]
        if status_values:
            stmt = stmt.where(Program.rank_status_2025.in_(status_values))
    if min_quota is not None: stmt = stmt.where(Program.quota_2026 >= min_quota)
    if max_quota is not None: stmt = stmt.where(Program.quota_2026 <= max_quota)
    if min_rank is not None or max_rank is not None:
        numeric_rank_filters = []
        if min_rank is not None:
            numeric_rank_filters.append(Program.min_rank_2025 >= min_rank)
        if max_rank is not None:
            numeric_rank_filters.append(Program.min_rank_2025 <= max_rank)
        # Başarı sırası bulunmayan Dolmadı/Yer.Olmadı/Yeni programlar sayısal
        # aralıkla karşılaştırılamaz. "Tümü" veya bir durum filtresi seçiliyken
        # diğer filtrelere uyuyorlarsa sonuç kapsamından çıkarılmamalıdır.
        stmt = stmt.where(or_(
            and_(*numeric_rank_filters),
            Program.rank_status_2025.in_(["Dolmadı", "Yer.Olmadı", "Yeni"]),
        ))
    total = db.scalar(select(func.count()).select_from(stmt.subquery()))
    # Program arama sonuçları en iyi 2025 başarı sırasından başlar.
    # Sayısal sırası olmayan Dolmadı/Yeni/Yer.Olmadı kayıtları "Tümü"
    # kapsamındadır ve ilgili durum filtresiyle doğrudan listelenebilir.
    order_by = (
        Program.min_rank_2025.asc().nullslast(),
        Program.university.asc(),
        Program.program.asc(),
    )
    rows = db.scalars(
        stmt.order_by(*order_by)
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).all()
    program_ids = [program.id for program in rows]
    histories = db.scalars(select(ProgramRankHistory).where(
        ProgramRankHistory.program_id.in_(program_ids),
        ProgramRankHistory.year.in_([2025, 2024, 2023]),
    )).all() if program_ids else []
    history_by_program: dict[int, list[ProgramRankHistory]] = {}
    for history in histories:
        history_by_program.setdefault(history.program_id, []).append(history)
    return {
        "total": total,
        "page": page,
        "items": [
            program_payload(program, history_by_program.get(program.id, []))
            for program in rows
        ],
    }


def program_payload(
    program: Program,
    histories: list[ProgramRankHistory],
) -> dict:
    data = {
        column.name: getattr(program, column.name)
        for column in Program.__table__.columns
    }
    history_by_year = {history.year: history for history in histories}
    data["rank_history"] = [
        {"year": history.year, "rank": history.rank, "status": history.status}
        for history in sorted(histories, key=lambda item: item.year)
    ]
    extra = program.extra or {}
    data["kktc_national_only"] = bool(
        extra.get("kktc_national_only")
        or (program.university_type or "").strip().upper() == "KKTC U."
    )
    data["special_condition_details"] = condition_details(
        program.special_conditions
    )
    for year in (2025, 2024, 2023):
        history = history_by_year.get(year)
        data[f"rank_{year}"] = (
            history.rank if history and history.rank is not None
            else (history.status if history and history.status else None)
        )
    return data

def threshold_for_program(program: Program) -> int | None:
    if program.threshold_rank:
        return program.threshold_rank
    name = program.program.casefold()
    rules = [
        ("tıp", 50_000), ("diş hekimliği", 80_000),
        ("hukuk", 100_000), ("eczacılık", 100_000),
        ("mimarlık", 250_000), ("mühendisliği", 300_000),
        ("öğretmenliği", 300_000),
    ]
    return next((limit for keyword, limit in rules if keyword in name), None)

def validate_program_threshold(program: Program, student_id: int, db: Session) -> None:
    limit = threshold_for_program(program)
    if not limit:
        return
    score_type = program.score_type
    result = db.scalar(select(StudentExamResult).where(
        StudentExamResult.student_id == student_id,
        StudentExamResult.year == 2026,
        StudentExamResult.score_type == score_type))
    if not result or not result.rank:
        raise HTTPException(
            422, f"{program.program} için {score_type} başarı sırası girilmelidir "
                 f"(baraj: ilk {limit:,}).".replace(",", "."))
    if result.rank > limit:
        raise HTTPException(
            422, f"{program.program} programı için başarı sırası barajı ilk "
                 f"{limit:,}; öğrencinin {score_type} sırası "
                 f"{result.rank:,}.".replace(",", "."))

@app.get("/api/programs/{program_id}")
def program_detail(program_id: int, db: Session = Depends(get_db)):
    obj = db.get(Program, program_id)
    if not obj: raise HTTPException(404, "Program bulunamadı")
    history = db.scalars(select(ProgramRankHistory).where(
        ProgramRankHistory.program_id == program_id).order_by(ProgramRankHistory.year)).all()
    return program_payload(obj, history)

@app.post("/api/recommend")
def recommend(student_rank: int, program_id: int, db: Session = Depends(get_db)):
    p = db.get(Program, program_id)
    if not p: raise HTTPException(404, "Program bulunamadı")
    return classify(student_rank, p.min_rank_2025, p.rank_status_2025,
                    thresholds=get_thresholds(db))

@app.post("/api/recommend/batch")
def recommend_batch(student_id: int, score_type: str, program_ids: list[int],
                    db: Session = Depends(get_db), _: User = Depends(current_user)):
    result = db.scalar(select(StudentExamResult).where(
        StudentExamResult.student_id == student_id,
        StudentExamResult.year == 2026,
        StudentExamResult.score_type == score_type))
    if not result or not result.rank:
        raise HTTPException(422, "Öğrencinin seçilen puan türü için başarı sırası bulunamadı")
    programs = db.scalars(select(Program).where(Program.id.in_(program_ids))).all()
    output = []
    for program in programs:
        if program.score_type != score_type:
            continue
        history = db.scalars(select(ProgramRankHistory.rank).where(
            ProgramRankHistory.program_id == program.id,
            ProgramRankHistory.rank.is_not(None)).order_by(ProgramRankHistory.year.desc()).limit(5)).all()
        limit = threshold_for_program(program)
        if limit and result.rank > limit:
            decision = {
                "category": "Baraj dışı",
                "explanation": (
                    f"{program.program} için yasal başarı sırası şartı ilk "
                    f"{limit:,}; öğrencinin {score_type} sırası "
                    f"{result.rank:,}."
                ).replace(",", "."),
            }
        else:
            decision = classify(
                result.rank, program.min_rank_2025, program.rank_status_2025,
                history, get_thresholds(db))
        output.append({
            "program_id": program.id,
            "score_type": program.score_type,
            "threshold_rank": limit,
            **decision,
        })
    return {"student_rank": result.rank, "score_type": score_type, "items": output}

@app.get("/api/students")
def students(
    q: str | None = None,
    db: Session = Depends(get_db),
    actor: User = Depends(current_user),
):
    stmt = select(Student).where(Student.archived_at.is_(None))
    if actor.role == "counselor": stmt = stmt.where(Student.counselor_id == actor.id)
    if q and q.strip():
        needle = f"%{normalize_search(q)}%"
        stmt = stmt.where(or_(
            func.tr_fold(Student.first_name).like(needle),
            func.tr_fold(Student.last_name).like(needle),
            func.tr_fold(Student.first_name + " " + Student.last_name).like(needle),
            func.tr_fold(Student.school).like(needle),
            func.tr_fold(Student.phone).like(needle),
            func.tr_fold(Student.email).like(needle),
        ))
    rows = db.scalars(
        stmt.order_by(
            func.tr_fold(Student.first_name),
            func.tr_fold(Student.last_name),
            Student.id,
        )
    ).all()
    student_ids = [student.id for student in rows]
    history_by_student: dict[int, list[dict]] = {}
    if student_ids:
        preferences = db.scalars(
            select(PreferenceList)
            .where(PreferenceList.student_id.in_(student_ids))
            .order_by(PreferenceList.created_at.desc(), PreferenceList.id.desc())
        ).all()
        for preference in preferences:
            history_by_student.setdefault(preference.student_id, []).append({
                "id": preference.id,
                "name": preference.name,
                "version": preference.version,
                "status": preference.status,
                "created_at": preference.created_at,
            })
    return [
        {
            **{
                column.name: getattr(student, column.name)
                for column in Student.__table__.columns
            },
            "preference_count": len(history_by_student.get(student.id, [])),
            "preference_history": history_by_student.get(student.id, []),
        }
        for student in rows
    ]

@app.get("/api/students/archived")
def archived_students(db: Session = Depends(get_db),
                      actor: User = Depends(require_roles("admin", "counselor"))):
    stmt = select(Student).where(Student.archived_at.is_not(None))
    if actor.role == "counselor":
        stmt = stmt.where(Student.counselor_id == actor.id)
    return db.scalars(stmt.order_by(Student.archived_at.desc())).all()

@app.post("/api/students", status_code=201)
def create_student(data: StudentIn, db: Session = Depends(get_db), actor: User = Depends(require_roles("admin", "counselor", "teacher"))):
    obj = Student(**data.model_dump(), counselor_id=actor.id if actor.role == "counselor" else None)
    db.add(obj); db.flush(); db.add(AuditLog(user_id=actor.id, action="student.create", entity_type="student", entity_id=str(obj.id)))
    db.commit(); db.refresh(obj); return obj

@app.post("/api/students-with-results", status_code=201)
def create_student_with_results(
    data: StudentWithResultsIn,
    db: Session = Depends(get_db),
    actor: User = Depends(require_roles("admin", "counselor", "teacher")),
):
    validate_exam_results(data.exam_results)
    student_data = data.model_dump(exclude={"exam_results"})
    obj = Student(
        **student_data,
        counselor_id=actor.id if actor.role == "counselor" else None,
    )
    db.add(obj)
    db.flush()
    for result in data.exam_results:
        db.add(StudentExamResult(student_id=obj.id, **result.model_dump()))
    db.add(AuditLog(
        user_id=actor.id,
        action="student.create_with_results",
        entity_type="student",
        entity_id=str(obj.id),
        details={"score_types": [x.score_type for x in data.exam_results]},
    ))
    db.commit()
    db.refresh(obj)
    return obj

@app.put("/api/students/{student_id}")
def update_student(student_id: int, data: StudentIn, db: Session = Depends(get_db), actor: User = Depends(require_roles("admin", "counselor", "teacher"))):
    obj = db.get(Student, student_id)
    if not obj: raise HTTPException(404, "Öğrenci bulunamadı")
    if actor.role == "counselor" and obj.counselor_id != actor.id:
        raise HTTPException(403, "Bu öğrenci için yetkiniz yok")
    for k, v in data.model_dump().items(): setattr(obj, k, v)
    db.add(AuditLog(user_id=actor.id, action="student.update", entity_type="student", entity_id=str(obj.id)))
    db.commit(); db.refresh(obj); return obj

@app.put("/api/students/{student_id}/with-results")
def update_student_with_results(
    student_id: int,
    data: StudentWithResultsIn,
    db: Session = Depends(get_db),
    actor: User = Depends(require_roles("admin", "counselor", "teacher")),
):
    validate_exam_results(data.exam_results)
    obj = db.get(Student, student_id)
    if not obj:
        raise HTTPException(404, "Öğrenci bulunamadı")
    if actor.role == "counselor" and obj.counselor_id != actor.id:
        raise HTTPException(403, "Bu öğrenci için yetkiniz yok")
    for key, value in data.model_dump(exclude={"exam_results"}).items():
        setattr(obj, key, value)
    db.query(StudentExamResult).filter(
        StudentExamResult.student_id == student_id,
        StudentExamResult.year == 2026,
    ).delete()
    for result in data.exam_results:
        db.add(StudentExamResult(student_id=student_id, **result.model_dump()))
    db.add(AuditLog(
        user_id=actor.id,
        action="student.update_with_results",
        entity_type="student",
        entity_id=str(student_id),
        details={"score_types": [x.score_type for x in data.exam_results]},
    ))
    db.commit()
    db.refresh(obj)
    return obj

@app.delete("/api/students/{student_id}", status_code=204)
def archive_student(student_id: int, db: Session = Depends(get_db),
                    actor: User = Depends(require_roles("admin", "counselor"))):
    student = db.get(Student, student_id)
    if not student: raise HTTPException(404, "Öğrenci bulunamadı")
    if actor.role == "counselor" and student.counselor_id != actor.id:
        raise HTTPException(403, "Bu öğrenci için yetkiniz yok")
    student.archived_at = datetime.utcnow()
    db.add(AuditLog(user_id=actor.id, action="student.archive",
                    entity_type="student", entity_id=str(student.id)))
    db.commit()

@app.post("/api/students/{student_id}/restore")
def restore_student(student_id: int, db: Session = Depends(get_db),
                    actor: User = Depends(require_roles("admin", "counselor"))):
    student = db.get(Student, student_id)
    if not student: raise HTTPException(404, "Öğrenci bulunamadı")
    if actor.role == "counselor" and student.counselor_id != actor.id:
        raise HTTPException(403, "Bu öğrenci için yetkiniz yok")
    student.archived_at = None
    db.add(AuditLog(user_id=actor.id, action="student.restore",
                    entity_type="student", entity_id=str(student.id)))
    db.commit()
    return student

@app.get("/api/students/{student_id}/notes")
def counseling_notes(student_id: int, db: Session = Depends(get_db),
                     actor: User = Depends(current_user)):
    student = db.get(Student, student_id)
    if not student: raise HTTPException(404, "Öğrenci bulunamadı")
    if actor.role == "counselor" and student.counselor_id != actor.id:
        raise HTTPException(403, "Bu öğrenci için yetkiniz yok")
    rows = db.scalars(select(CounselingNote).where(
        CounselingNote.student_id == student_id).order_by(CounselingNote.created_at.desc())).all()
    authors = {x.id: x.full_name for x in db.scalars(select(User)).all()}
    return [{"id": x.id, "note": x.note, "author_id": x.author_id,
             "author": authors.get(x.author_id, "Bilinmeyen"),
             "created_at": x.created_at} for x in rows]

@app.post("/api/students/{student_id}/notes", status_code=201)
def add_counseling_note(student_id: int, data: CounselingNoteIn,
                        db: Session = Depends(get_db),
                        actor: User = Depends(require_roles("admin", "counselor", "teacher"))):
    student = db.get(Student, student_id)
    if not student: raise HTTPException(404, "Öğrenci bulunamadı")
    if actor.role == "counselor" and student.counselor_id != actor.id:
        raise HTTPException(403, "Bu öğrenci için yetkiniz yok")
    note_text = data.note.strip()
    if not note_text: raise HTTPException(422, "Not boş olamaz")
    note = CounselingNote(student_id=student_id, author_id=actor.id, note=note_text)
    db.add(note); db.flush()
    db.add(AuditLog(user_id=actor.id, action="counseling_note.create",
                    entity_type="student", entity_id=str(student_id),
                    details={"note_id": note.id}))
    db.commit(); db.refresh(note); return note

@app.get("/api/audit-logs")
def audit_logs(action: str | None = None, user_id: int | None = None,
               page: int = Query(1, ge=1), page_size: int = Query(50, ge=1, le=200),
               db: Session = Depends(get_db), _: User = Depends(require_roles("admin"))):
    stmt = select(AuditLog)
    if action: stmt = stmt.where(AuditLog.action == action)
    if user_id: stmt = stmt.where(AuditLog.user_id == user_id)
    total = db.scalar(select(func.count()).select_from(stmt.subquery()))
    rows = db.scalars(stmt.order_by(AuditLog.created_at.desc())
                      .offset((page - 1) * page_size).limit(page_size)).all()
    users_by_id = {x.id: x.full_name for x in db.scalars(select(User)).all()}
    return {"total": total, "items": [
        {"id": x.id, "user_id": x.user_id, "user": users_by_id.get(x.user_id, "Sistem"),
         "action": x.action, "entity_type": x.entity_type, "entity_id": x.entity_id,
         "details": x.details, "created_at": x.created_at} for x in rows]}

@app.get("/api/students/{student_id}/exam-results")
def exam_results(student_id: int, db: Session = Depends(get_db), _: User = Depends(current_user)):
    if not db.get(Student, student_id): raise HTTPException(404, "Öğrenci bulunamadı")
    return db.scalars(select(StudentExamResult).where(StudentExamResult.student_id == student_id).order_by(StudentExamResult.year.desc(), StudentExamResult.score_type)).all()

@app.post("/api/students/{student_id}/exam-results")
def save_exam_result(student_id: int, data: ExamResultIn, db: Session = Depends(get_db), actor: User = Depends(require_roles("admin", "counselor", "teacher"))):
    if data.rank is not None and data.rank <= 0: raise HTTPException(422, "Başarı sırası pozitif olmalıdır")
    if not db.get(Student, student_id): raise HTTPException(404, "Öğrenci bulunamadı")
    result = db.scalar(select(StudentExamResult).where(StudentExamResult.student_id == student_id, StudentExamResult.year == data.year, StudentExamResult.score_type == data.score_type))
    if result:
        result.score = data.score; result.rank = data.rank
    else:
        result = StudentExamResult(student_id=student_id, **data.model_dump()); db.add(result)
    db.flush(); db.add(AuditLog(user_id=actor.id, action="exam_result.upsert", entity_type="student_exam_result", entity_id=str(result.id)))
    db.commit(); db.refresh(result); return result

@app.delete("/api/students/{student_id}/exam-results/{result_id}", status_code=204)
def delete_exam_result(student_id: int, result_id: int,
                       db: Session = Depends(get_db),
                       actor: User = Depends(require_roles("admin", "counselor", "teacher"))):
    result = db.get(StudentExamResult, result_id)
    if not result or result.student_id != student_id:
        raise HTTPException(404, "Sınav sonucu bulunamadı")
    db.delete(result)
    db.add(AuditLog(user_id=actor.id, action="exam_result.delete",
                    entity_type="student_exam_result", entity_id=str(result_id)))
    db.commit()

@app.post("/api/preference-lists", status_code=201)
def create_preference(data: PreferenceIn, db: Session = Depends(get_db), actor: User = Depends(require_roles("admin", "counselor", "teacher"))):
    if not db.get(Student, data.student_id): raise HTTPException(404, "Öğrenci bulunamadı")
    program_ids = [x.program_id for x in data.items]
    if len(program_ids) != len(set(program_ids)): raise HTTPException(422, "Aynı program iki kez eklenemez")
    if len({x.position for x in data.items}) != len(data.items): raise HTTPException(422, "Tercih sıraları benzersiz olmalıdır")
    pref = PreferenceList(student_id=data.student_id, name=data.name, score_type=data.score_type, created_by=actor.id)
    db.add(pref); db.flush()
    exam = db.scalar(select(StudentExamResult).where(
        StudentExamResult.student_id == data.student_id,
        StudentExamResult.year == 2026,
        StudentExamResult.score_type == data.score_type))
    for item in data.items:
        program = db.get(Program, item.program_id)
        if not program: raise HTTPException(404, f"Program bulunamadı: {item.program_id}")
        values = item.model_dump()
        calculated_categories = {"Yüksek hedef", "Hedef aralığı", "Dengeli", "Daha güvenli",
                                 "Verisi yetersiz", "Yeni program", "Geçen yıl dolmadı"}
        if exam and exam.rank and item.category not in calculated_categories:
            history = db.scalars(select(ProgramRankHistory.rank).where(
                ProgramRankHistory.program_id == program.id,
                ProgramRankHistory.rank.is_not(None)).order_by(ProgramRankHistory.year.desc()).limit(5)).all()
            decision = classify(exam.rank, program.min_rank_2025,
                                program.rank_status_2025, history,
                                get_thresholds(db))
            values["category"] = decision["category"]
            values["explanation"] = decision["explanation"]
        db.add(PreferenceItem(preference_list_id=pref.id, **values))
    db.add(AuditLog(user_id=actor.id, action="preference.create", entity_type="preference_list", entity_id=str(pref.id)))
    db.commit(); db.refresh(pref); return {"id": pref.id, "version": pref.version, "status": pref.status}

@app.get("/api/preference-lists")
def list_preferences(student_id: int | None = None, db: Session = Depends(get_db), _: User = Depends(current_user)):
    stmt = select(PreferenceList)
    if student_id is not None: stmt = stmt.where(PreferenceList.student_id == student_id)
    rows = db.scalars(stmt.order_by(PreferenceList.created_at.desc())).all()
    return [{"id": x.id, "student_id": x.student_id, "name": x.name, "version": x.version,
             "status": x.status, "score_type": x.score_type, "created_at": x.created_at} for x in rows]

@app.get("/api/preference-lists/{list_id}")
def get_preference(list_id: int, db: Session = Depends(get_db), _: User = Depends(current_user)):
    pref = db.get(PreferenceList, list_id)
    if not pref: raise HTTPException(404, "Tercih listesi bulunamadı")
    items = db.scalars(select(PreferenceItem).where(PreferenceItem.preference_list_id == list_id).order_by(PreferenceItem.position)).all()
    program_ids = [item.program_id for item in items]
    histories = db.scalars(select(ProgramRankHistory).where(
        ProgramRankHistory.program_id.in_(program_ids),
        ProgramRankHistory.year.in_([2025, 2024, 2023]),
    )).all() if program_ids else []
    history_by_program: dict[int, list[ProgramRankHistory]] = {}
    for history in histories:
        history_by_program.setdefault(history.program_id, []).append(history)
    return {"id": pref.id, "student_id": pref.student_id, "name": pref.name, "version": pref.version, "status": pref.status,
            "items": [{"id": x.id, "program_id": x.program_id, "position": x.position, "category": x.category,
                       "explanation": x.explanation, "note": x.note,
                       "program": x.program.program, "university": x.program.university,
                       "score_type": x.program.score_type, "city": x.program.city,
                       "program_data": program_payload(
                           x.program, history_by_program.get(x.program_id, [])
                       )}
                      for x in items]}

@app.put("/api/preference-lists/{list_id}")
def update_preference(list_id: int, data: PreferenceUpdate,
                      db: Session = Depends(get_db),
                      actor: User = Depends(require_roles("admin", "counselor", "teacher"))):
    pref = db.get(PreferenceList, list_id)
    if not pref: raise HTTPException(404, "Tercih listesi bulunamadı")
    if data.name is not None:
        name = data.name.strip()
        if not name: raise HTTPException(422, "Liste adı boş olamaz")
        pref.name = name
    if data.status is not None:
        if data.status not in {"draft", "completed", "archived"}:
            raise HTTPException(422, "Geçersiz liste durumu")
        pref.status = data.status
    if data.items is not None:
        ids = [x.program_id for x in data.items]
        positions = [x.position for x in data.items]
        if len(ids) != len(set(ids)) or len(positions) != len(set(positions)):
            raise HTTPException(422, "Programlar ve sıra numaraları benzersiz olmalıdır")
        db.query(PreferenceItem).filter_by(preference_list_id=list_id).delete()
        for item in data.items:
            program = db.get(Program, item.program_id)
            if not program:
                raise HTTPException(404, f"Program bulunamadı: {item.program_id}")
            db.add(PreferenceItem(preference_list_id=list_id, **item.model_dump()))
    db.add(AuditLog(user_id=actor.id, action="preference.update",
                    entity_type="preference_list", entity_id=str(list_id),
                    details={"status": pref.status,
                             "item_count": len(data.items) if data.items is not None else None}))
    db.commit()
    return {"id": pref.id, "status": pref.status, "version": pref.version}

@app.delete("/api/preference-lists/{list_id}", status_code=204)
def delete_preference(list_id: int, db: Session = Depends(get_db),
                      actor: User = Depends(require_roles("admin", "counselor", "teacher"))):
    pref = db.get(PreferenceList, list_id)
    if not pref: raise HTTPException(404, "Tercih listesi bulunamadı")
    db.query(PreferenceItem).filter_by(preference_list_id=list_id).delete()
    db.delete(pref)
    db.add(AuditLog(user_id=actor.id, action="preference.delete",
                    entity_type="preference_list", entity_id=str(list_id)))
    db.commit()

@app.post("/api/preference-lists/{list_id}/versions", status_code=201)
def new_version(list_id: int, db: Session = Depends(get_db), actor: User = Depends(require_roles("admin", "counselor", "teacher"))):
    source = db.get(PreferenceList, list_id)
    if not source: raise HTTPException(404, "Tercih listesi bulunamadı")
    version = (db.scalar(select(func.max(PreferenceList.version)).where(PreferenceList.student_id == source.student_id, PreferenceList.name == source.name)) or 0) + 1
    target = PreferenceList(student_id=source.student_id, name=source.name, version=version, status="draft", score_type=source.score_type, created_by=actor.id)
    db.add(target); db.flush()
    items = db.scalars(select(PreferenceItem).where(PreferenceItem.preference_list_id == source.id)).all()
    db.add_all(PreferenceItem(preference_list_id=target.id, program_id=x.program_id, position=x.position, category=x.category, explanation=x.explanation, note=x.note) for x in items)
    db.commit(); return {"id": target.id, "version": target.version}

def _export_data(list_id: int, db: Session):
    pref = db.get(PreferenceList, list_id)
    if not pref: raise HTTPException(404, "Tercih listesi bulunamadı")
    student = db.get(Student, pref.student_id)
    if not student:
        raise HTTPException(409, "Tercih listesinin öğrenci kaydı bulunamadı")
    items = db.scalars(select(PreferenceItem).where(PreferenceItem.preference_list_id == list_id).order_by(PreferenceItem.position)).all()
    if not items:
        raise HTTPException(409, "Tercih listesi boş. PDF oluşturmadan önce programa tercih ekleyin.")
    if any(item.program is None for item in items):
        raise HTTPException(409, "Tercih listesindeki bir program kaydı artık bulunamıyor")
    return pref, student, items

@app.get("/api/preference-lists/{list_id}/export.csv")
def export_csv(list_id: int, db: Session = Depends(get_db), _: User = Depends(current_user)):
    _, _, items = _export_data(list_id, db)
    return Response(preference_csv(items), media_type="text/csv; charset=utf-8", headers={"Content-Disposition": f'attachment; filename="tercih-{list_id}.csv"'})

@app.get("/api/preference-lists/{list_id}/export.xlsx")
def export_xlsx(list_id: int, db: Session = Depends(get_db), _: User = Depends(current_user)):
    _, _, items = _export_data(list_id, db)
    return Response(preference_xlsx(items), media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", headers={"Content-Disposition": f'attachment; filename="tercih-{list_id}.xlsx"'})

@app.get("/api/preference-lists/{list_id}/export.pdf")
def export_pdf(list_id: int, db: Session = Depends(get_db), _: User = Depends(current_user)):
    pref, student, items = _export_data(list_id, db)
    exam_results = db.scalars(select(StudentExamResult).where(
        StudentExamResult.student_id == student.id,
        StudentExamResult.year == 2026).order_by(StudentExamResult.score_type)).all()
    program_ids = [item.program_id for item in items]
    histories = db.scalars(select(ProgramRankHistory).where(
        ProgramRankHistory.program_id.in_(program_ids),
        ProgramRankHistory.year.in_([2025, 2024]))).all() if program_ids else []
    history_by_program = {}
    for history in histories:
        history_by_program.setdefault(history.program_id, {})[history.year] = history
    return Response(
        preference_pdf(pref, student, items, exam_results, history_by_program),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="tercih-{list_id}.pdf"'})

@app.get("/api/dashboard")
def dashboard(db: Session = Depends(get_db), _: User = Depends(current_user)):
    return {"programs": db.scalar(select(func.count(Program.id))), "students": db.scalar(select(func.count(Student.id))),
            "preference_lists": db.scalar(select(func.count(PreferenceList.id)))}

@app.get("/api/reports/summary")
def report_summary(db: Session = Depends(get_db), _: User = Depends(require_roles("admin", "counselor", "teacher", "viewer"))):
    top_universities = db.execute(
        select(Program.university, func.count(PreferenceItem.id).label("count"))
        .join(PreferenceItem, PreferenceItem.program_id == Program.id)
        .group_by(Program.university).order_by(func.count(PreferenceItem.id).desc()).limit(10)
    ).all()
    top_programs = db.execute(
        select(Program.program, func.count(PreferenceItem.id).label("count"))
        .join(PreferenceItem, PreferenceItem.program_id == Program.id)
        .group_by(Program.program).order_by(func.count(PreferenceItem.id).desc()).limit(10)
    ).all()
    score_types = db.execute(
        select(Program.score_type, func.count(PreferenceItem.id).label("count"))
        .join(PreferenceItem, PreferenceItem.program_id == Program.id)
        .group_by(Program.score_type).order_by(func.count(PreferenceItem.id).desc())
    ).all()
    categories = db.execute(
        select(PreferenceItem.category, func.count(PreferenceItem.id).label("count"))
        .group_by(PreferenceItem.category).order_by(func.count(PreferenceItem.id).desc())
    ).all()
    return {
        "students": db.scalar(select(func.count(Student.id)).where(Student.archived_at.is_(None))),
        "students_with_lists": db.scalar(select(func.count(func.distinct(PreferenceList.student_id)))),
        "preference_lists": db.scalar(select(func.count(PreferenceList.id))),
        "preference_items": db.scalar(select(func.count(PreferenceItem.id))),
        "top_universities": [{"name": name, "count": count} for name, count in top_universities],
        "top_programs": [{"name": name, "count": count} for name, count in top_programs],
        "score_types": [{"name": name or "Belirsiz", "count": count} for name, count in score_types],
        "categories": [{"name": name or "Belirsiz", "count": count} for name, count in categories],
    }

@app.get("/api/imports")
def imports(db: Session = Depends(get_db), _: User = Depends(require_roles("admin"))):
    rows = db.scalars(select(DataImport).order_by(DataImport.imported_at.desc())).all()
    return [{"id": x.id, "data_year": x.data_year, "file_name": x.file_name,
             "file_hash": x.file_hash, "record_count": x.record_count,
             "is_active": x.is_active, "imported_at": x.imported_at,
             "report": x.report} for x in rows]

@app.post("/api/imports/preview")
async def preview_import(file: UploadFile = File(...), _: User = Depends(require_roles("admin"))):
    if not file.filename or not file.filename.lower().endswith(".xlsx"):
        raise HTTPException(422, "Yalnızca .xlsx dosyaları kabul edilir")
    content = await file.read()
    if len(content) > 50 * 1024 * 1024:
        raise HTTPException(413, "Dosya 50 MB sınırını aşıyor")
    temporary_path = None
    try:
        with NamedTemporaryFile(delete=False, suffix=".xlsx") as temporary:
            temporary.write(content)
            temporary_path = temporary.name
        report = analyze_excel(temporary_path)
        return {"file_name": file.filename, "size": len(content), **report,
                "can_import": report["matches_expected"] and not report["duplicate_codes"]}
    except (KeyError, ValueError) as exc:
        raise HTTPException(422, f"Excel yapısı doğrulanamadı: {exc}")
    finally:
        if temporary_path:
            Path(temporary_path).unlink(missing_ok=True)


web_dist_value = os.getenv("WEB_DIST", "").strip()
web_dist = Path(web_dist_value).resolve() if web_dist_value else None
if web_dist is not None and web_dist.is_dir():
    def web_file_response(path: Path) -> FileResponse:
        # Flutter's entry files must never outlive a deployment. Otherwise an
        # old bootstrap/main bundle can be mixed with new assets and leave the
        # user on a blank grey screen immediately after login.
        no_cache_files = {
            "index.html",
            "flutter_bootstrap.js",
            "flutter_service_worker.js",
            "main.dart.js",
            "version.json",
        }
        headers = (
            {"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"}
            if path.name in no_cache_files
            else {"Cache-Control": "public, max-age=86400"}
        )
        return FileResponse(path, headers=headers)

    @app.get("/{full_path:path}", include_in_schema=False)
    def flutter_web(full_path: str):
        requested = (web_dist / full_path).resolve()
        if web_dist == requested or web_dist in requested.parents:
            if requested.is_file():
                return web_file_response(requested)
        return web_file_response(web_dist / "index.html")

@app.post("/api/imports/commit")
async def commit_import(data_year: int, file: UploadFile = File(...),
                        db: Session = Depends(get_db), actor: User = Depends(require_roles("admin"))):
    if data_year < 2026 or data_year > 2100:
        raise HTTPException(422, "Veri yılı 2026–2100 arasında olmalıdır")
    if not file.filename or not file.filename.lower().endswith(".xlsx"):
        raise HTTPException(422, "Yalnızca .xlsx dosyaları kabul edilir")
    content = await file.read()
    if len(content) > 50 * 1024 * 1024:
        raise HTTPException(413, "Dosya 50 MB sınırını aşıyor")
    temporary_path = None
    try:
        with NamedTemporaryFile(delete=False, suffix=".xlsx") as temporary:
            temporary.write(content); temporary_path = temporary.name
        report = analyze_excel(temporary_path)
        if not report["matches_expected"] or report["duplicate_codes"]:
            raise HTTPException(422, "Doğrulama başarısız; veritabanında değişiklik yapılmadı")
        if db.scalar(select(DataImport).where(DataImport.file_hash == report["sha256"])):
            raise HTTPException(409, "Bu dosya daha önce içe aktarılmış")
        db.query(DataImport).update({DataImport.is_active: False})
        imported = DataImport(data_year=data_year, file_name=file.filename,
                              file_hash=report["sha256"], uploaded_by=actor.id,
                              record_count=report["total"], is_active=True, report=report)
        db.add(imported); db.flush()
        added = updated = 0
        imported_codes = set()
        for values in iter_programs(temporary_path):
            history = values.pop("history")
            values["data_year"] = data_year
            imported_codes.add(values["program_code"])
            program = db.scalar(select(Program).where(
                Program.data_year == data_year,
                Program.program_code == values["program_code"]))
            if program is None:
                program = Program(**values); db.add(program); db.flush(); added += 1
            else:
                for key, value in values.items(): setattr(program, key, value)
                db.query(ProgramRankHistory).filter_by(program_id=program.id).delete()
                updated += 1
            db.add_all(ProgramRankHistory(program_id=program.id, **item) for item in history)
        removed = retained = 0
        stale_programs = db.scalars(select(Program).where(
            Program.data_year == data_year,
            Program.program_code.notin_(imported_codes))).all()
        for program in stale_programs:
            is_used = db.scalar(select(PreferenceItem.id).where(
                PreferenceItem.program_id == program.id).limit(1))
            if is_used:
                retained += 1
                continue
            db.query(ProgramRankHistory).filter_by(
                program_id=program.id).delete()
            db.delete(program)
            removed += 1
        db.add(AuditLog(user_id=actor.id, action="data_import.commit",
                        entity_type="data_import", entity_id=str(imported.id),
                        details={"year": data_year, "added": added, "updated": updated,
                                 "removed": removed, "retained": retained,
                                 "sha256": report["sha256"]}))
        db.commit()
        return {"id": imported.id, "data_year": data_year, "record_count": report["total"],
                "added": added, "updated": updated, "removed": removed,
                "retained": retained, "sha256": report["sha256"]}
    except HTTPException:
        db.rollback(); raise
    except Exception:
        db.rollback(); raise
    finally:
        if temporary_path:
            Path(temporary_path).unlink(missing_ok=True)
