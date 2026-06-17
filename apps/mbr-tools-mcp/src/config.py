from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    STORAGE_ACCOUNT_URL: str = ""
    AZURE_CLIENT_ID: str = ""
    APPLICATIONINSIGHTS_CONNECTION_STRING: str = ""

    class Config:
        env_file = ".env"
        extra = "ignore"


settings = Settings()
