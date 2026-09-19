# /// script
# requires-python = ">=3.12,<3.13"
# dependencies = [
#     "langchain-core==1.6.3",
#     "langchain-openai==1.6.2",
#     "langchain-text-splitters==1.1.2",
#     "huggingface-hub==1.32.0",
#     "numpy==2.5.3",
#     "fastapi==0.141.1",
#     "uvicorn==0.53.0",
# ]
# ///
"""RAG question-answering API over this course's docs.

Run with `uv run /opt/app/rag_api.py`: uv reads the inline metadata above, builds a cached venv
(in UV_CACHE_DIR) and starts the app. There's no image build step, so the ConfigMap is the
deployment artifact.

Endpoints (port 8080, or $PORT):
  GET  /healthz  200 while the process is alive (liveness). 503 only if the index build
                 failed for good, so the kubelet restarts the container.
  GET  /readyz   200 once the vector index is built, 503 before (readiness: no traffic until then)
  POST /ask      {"question": str} -> {"answer": str, "sources": [str]}   (RAG)
  POST /chat     {"message": str}  -> {"answer": str}                     (plain LLM, no RAG)

The index is built in a background thread, so uvicorn serves /healthz right away while TEI is
still loading. Building it inside the lifespan would keep the port closed and make the startup
probe fail for the wrong reason. /readyz does NOT check the LLM: vLLM restarting shouldn't pull
this pod out of the Service. /ask returns 502 instead, and the client sees why.
"""

from __future__ import annotations

import logging
import os
import threading
from contextlib import asynccontextmanager

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

import rag_chain  # sibling module in the same dir (uv run puts the script dir on sys.path)

log = logging.getLogger("rag_api")
settings = rag_chain.Settings.from_env()


class AskRequest(BaseModel):
    question: str = Field(min_length=1, max_length=4000)


class AskResponse(BaseModel):
    answer: str
    sources: list[str]


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)


class ChatResponse(BaseModel):
    answer: str


class State:
    rag = None  # Runnable, set once the index is built
    chat = None  # Runnable, available immediately (needs no index)
    failed: str | None = None  # permanent startup failure -> /healthz 503


state = State()


def _build_index() -> None:
    """Runs in a worker thread: blocking HTTP to TEI must not stall the event loop."""
    try:
        store = rag_chain.build_vector_store(settings)
        retriever = store.as_retriever(search_kwargs={"k": settings.top_k})
        state.rag = rag_chain.build_rag_chain(retriever, rag_chain.build_llm(settings))
        log.info("RAG index ready -- /readyz now returns 200")
    except Exception as exc:
        state.failed = f"{type(exc).__name__}: {exc}"
        log.exception("index build failed permanently, /healthz now returns 503")


@asynccontextmanager
async def lifespan(app: FastAPI):
    log.info(
        "starting: llm=%s model=%s embeddings=%s docs=%s top_k=%d disable_thinking=%s",
        settings.openai_base_url,
        settings.chat_model,
        settings.embeddings_url,
        settings.docs_dir,
        settings.top_k,
        settings.disable_thinking,
    )
    state.chat = rag_chain.build_chat_chain(rag_chain.build_llm(settings))
    # A daemon thread, not asyncio.to_thread: executor threads are joined at interpreter exit,
    # so a SIGTERM during the TEI retry loop would hang shutdown until the loop gave up.
    threading.Thread(target=_build_index, name="build-index", daemon=True).start()
    yield


app = FastAPI(title="ch19 RAG API", lifespan=lifespan)


@app.get("/healthz")
async def healthz():
    if state.failed:
        return JSONResponse(
            {"status": "failed", "error": state.failed}, status_code=503
        )
    return {"status": "ok"}


@app.get("/readyz")
async def readyz():
    if state.rag is None:
        return JSONResponse({"status": "building index"}, status_code=503)
    return {"status": "ready"}


@app.post("/ask", response_model=AskResponse)
async def ask(req: AskRequest) -> AskResponse:
    if state.rag is None:
        raise HTTPException(status_code=503, detail="index not built yet")
    try:
        out = await state.rag.ainvoke({"question": req.question})
    # LLM or TEI unreachable/erroring: a bad gateway, not a bug in this service.
    except Exception as exc:
        log.warning("/ask failed: %s: %s", type(exc).__name__, exc)
        raise HTTPException(
            status_code=502, detail=f"{type(exc).__name__}: {exc}"
        ) from exc
    sources = rag_chain.sources_of(out["docs"])
    log.info(
        "/ask q=%r sources=%s answer_chars=%d",
        req.question[:80],
        sources,
        len(out["answer"]),
    )
    return AskResponse(answer=out["answer"], sources=sources)


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest) -> ChatResponse:
    try:
        answer = await state.chat.ainvoke({"question": req.message})
    except Exception as exc:
        log.warning("/chat failed: %s: %s", type(exc).__name__, exc)
        raise HTTPException(
            status_code=502, detail=f"{type(exc).__name__}: {exc}"
        ) from exc
    return ChatResponse(answer=answer)


if __name__ == "__main__":
    rag_chain.configure_logging()
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.environ.get("PORT", "8080")),
        log_config=None,  # keep our logging format instead of uvicorn's own
        # Probes hit every few seconds; don't log each one. Our own handlers log what matters.
        access_log=False,
    )
