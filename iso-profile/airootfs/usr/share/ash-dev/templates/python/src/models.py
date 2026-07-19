from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


engine = create_engine("sqlite+aiosqlite:///./{{project_name}}.db", echo=True)
