from fastapi import FastAPI

app = FastAPI(title="ARGOS Lab API", version="0.1.0")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/scope")
def scope() -> dict[str, list[str]]:
    return {
        "allowed_targets": ["*.lab.local", "10.0.0.0/24"],
        "blocked_targets": ["0.0.0.0/0", "*.prod.*"],
    }
