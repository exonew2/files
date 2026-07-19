# {{project_name}}

AI/LLM project scaffolded by `ash-new`.

## Stack
- **LLM:** Ollama SDK
- **Vector DB:** Qdrant
- **Orchestration:** LangChain
- **Structured Output:** instructor
- **Embeddings:** sentence-transformers

## Quick Start
```bash
make setup       # Install dependencies
make run         # Start the app
make test        # Run tests
```

## Prerequisites
- Ollama running (\`ollama serve\`)
- Qdrant running on localhost:6333
- At least one model pulled (\`ollama pull llama3.2\`)

## Project Structure
```
src/
  llm.py          # LLM interface
  vector_store.py # Qdrant client
  chains.py       # LangChain chains
  models.py       # Pydantic models with instructor
  config.py       # Configuration
tests/
  test_llm.py
  test_rag.py
```

## AI Agent Instructions
- Requires Ollama + Qdrant running locally
- Use instructor for structured Pydantic output from LLMs
- LangChain for chain/agent orchestration
- All LLM calls should have timeout handling
