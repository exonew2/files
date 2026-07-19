# {{project_name}}

Rust CLI project scaffolded by `ash-new`.

## Stack
- **CLI:** clap v4
- **Async:** tokio
- **Serialization:** serde
- **Logging:** tracing
- **Linting:** clippy

## Quick Start
```bash
make setup    # Build project
make test     # Run tests
make run      # Run CLI
```

## Project Structure
```
src/
  main.rs       # Entry point
  cli.rs        # CLI argument parsing
  commands/
    mod.rs
  lib.rs        # Library root
tests/
  integration_tests.rs
```

## AI Agent Instructions
- Use `cargo clippy` for linting
- All public APIs must be documented
- Use `anyhow` for error handling
- Async where IO is involved
