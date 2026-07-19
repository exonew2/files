# {{project_name}}

Go API project scaffolded by `ash-new`.

## Stack
- **Router:** chi or gin
- **Database:** sqlx
- **Logging:** zap
- **Testing:** testify

## Quick Start
```bash
make setup    # Download dependencies
make test     # Run tests
make run      # Start API server
```

## Project Structure
```
cmd/
  server/
    main.go
internal/
  api/
    router.go
    handlers.go
  db/
    db.go
  models/
    models.go
  config/
    config.go
```

## AI Agent Instructions
- Run `go fmt` before commits
- Use `net/http` middleware patterns
- sqlx for all database queries
- Structured logging with zap
