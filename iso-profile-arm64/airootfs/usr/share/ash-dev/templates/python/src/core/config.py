from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "{{project_name}}"
    debug: bool = False
    database_url: str = "sqlite+aiosqlite:///./{{project_name}}.db"

    model_config = {"env_prefix": "{{PROJECT_NAME}}_"}
