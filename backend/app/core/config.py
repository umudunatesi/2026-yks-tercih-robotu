from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    app_name: str = "2026 YKS Tercih Robotu"
    database_url: str = "sqlite:///./yks.db"
    secret_key: str = "development-only-change-me"
    access_token_minutes: int = 480
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

settings = Settings()
