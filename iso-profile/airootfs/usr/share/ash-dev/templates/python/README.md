# {{project_name}}

Python project scaffolded by `ash-new`.

## Stack
- **Framework:** FastAPI
- **Validation:** Pydantic
- **ORM:** SQLAlchemy 2.0 + asyncpg
- **Testing:** pytest + httpx
- **Linting:** ruff
- **Formatting:** ruff format

## Quick Start
```bash
make setup    # Create venv + install deps
make test     # Run tests
make run      # Start dev server
make lint     # Lint with ruff
```

## Project Structure
```
src/
  {{project_name}}/
    __init__.py
    main.py         # FastAPI app
    models.py       # SQLAlchemy models
    schemas.py      # Pydantic schemas
    api/
      __init__.py
      routes.py
    core/
      __init__.py
      config.py
      database.py
tests/
  __init__.py
  conftest.py
  test_api.py
```

## AI Agent Instructions
When working on this project:
1. Run `make setup` first to install dependencies
2. Use `ruff` for linting — no flake8/black
3. Tests go in `tests/` matching `src/` structure
4. Type hints required for all functions
