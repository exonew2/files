# {{project_name}}

Data science project scaffolded by `ash-new`.

## Stack
- **Notebook:** Jupyter Lab
- **DataFrames:** Polars
- **Visualization:** Plotly
- **ML:** MLX (Apple Silicon)

## Quick Start
```bash
make setup    # Create venv + install deps
make lab      # Start Jupyter Lab
make test     # Run tests
```

## Project Structure
```
notebooks/
  exploratory.ipynb
  analysis.ipynb
src/
  data/
    loader.py
  features/
    builder.py
  models/
    train.py
  viz/
    plots.py
data/
  raw/
  processed/
tests/
  test_data.py
```

## AI Agent Instructions
- Use Polars (not pandas) for data manipulation
- MLX for Apple Silicon ML acceleration
- Plotly for interactive visualizations
- Notebooks for exploration only — final code in src/
