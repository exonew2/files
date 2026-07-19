import ollama


class LLMClient:
    def __init__(self, model: str = "llama3.2"):
        self.model = model

    def generate(self, prompt: str, system: str | None = None) -> str:
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})

        resp = ollama.chat(model=self.model, messages=messages)
        return resp["message"]["content"]

    async def generate_async(self, prompt: str, system: str | None = None) -> str:
        messages = []
        if system:
            messages.append({"role": "system", "content": system})
        messages.append({"role": "user", "content": prompt})

        resp = await ollama.AsyncClient().chat(model=self.model, messages=messages)
        return resp["message"]["content"]
