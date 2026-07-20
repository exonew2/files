# Contributing

## Pull Requests

1. Fork the repository at https://github.com/exonew2/files
2. Create a feature branch: `git checkout -b my-feature`
3. Make your changes
4. Run validation:
   - Shell scripts: `bash -n script.sh`
   - Python scripts: `python -m py_compile script.py`
5. Commit with a descriptive message
6. Push and open a PR against `main`

## Coding Standards

- **Shell scripts**: POSIX sh or Bash; use `set -euo pipefail`; no linters required beyond `bash -n`
- **Python**: Syntax-clean; no style enforcement beyond `python -m py_compile`
- **Documentation**: Markdown files in `docs/` and `landing-page/src/content/docs/`
- **Landing page**: Astro content files with frontmatter (title, description, order)

## Areas for Contribution

- Improving the `ultimate-fix-v2.sh` deployment script
- Adding VMware-specific optimizations (VMX settings, guest tools)
- Extending the LSFS pure-bash launcher with new semantic commands
- Documentation improvements and corrections

## License

By contributing, you agree your contributions are licensed under the same license as the project.
