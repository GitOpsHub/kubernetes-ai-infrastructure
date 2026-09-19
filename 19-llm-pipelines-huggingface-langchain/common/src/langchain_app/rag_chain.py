"""Shared LangChain building blocks for rag_api.py and batch_infer.py.

Both scripts `import rag_chain`. `uv run /opt/app/<script>.py` puts the script's own directory
first on sys.path, and the ConfigMap `ch19-langchain-app` mounts all three files flat in /opt/app,
so the import works in the pod and on a laptop. This module has no PEP 723 header of its own: it
runs inside the environment of whichever script imported it, so its imports must stay a subset of
the dependencies BOTH scripts declare.

The pieces:
  - Settings            every env var, read once, with in-cluster defaults
  - TEIEmbeddings       LangChain Embeddings backed by a Text Embeddings Inference (TEI) server
  - build_vector_store  DOCS_DIR/*.md -> chunks -> embeddings -> InMemoryVectorStore
  - build_rag_chain     LCEL: {"question"} -> retrieve -> prompt -> LLM -> {"answer", "docs"}
  - build_chat_chain    LCEL: {"question"} -> prompt -> LLM -> str (no retrieval)
"""

from __future__ import annotations

import logging
import os
import re
import time
from dataclasses import dataclass
from operator import itemgetter
from pathlib import Path

from huggingface_hub import InferenceClient
from langchain_core.documents import Document
from langchain_core.embeddings import Embeddings
from langchain_core.language_models import BaseChatModel
from langchain_core.output_parsers import StrOutputParser
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.retrievers import BaseRetriever
from langchain_core.runnables import (
    Runnable,
    RunnableLambda,
    RunnableParallel,
    RunnablePassthrough,
)
from langchain_core.vectorstores import InMemoryVectorStore
from langchain_openai import ChatOpenAI
from langchain_text_splitters import Language, RecursiveCharacterTextSplitter

log = logging.getLogger("rag_chain")


def env_bool(name: str, default: str) -> bool:
    return os.environ.get(name, default).strip().lower() in ("1", "true", "yes", "on")


@dataclass(frozen=True)
class Settings:
    openai_base_url: str
    openai_api_key: str
    chat_model: str
    embeddings_url: str
    docs_dir: Path
    disable_thinking: bool
    top_k: int
    max_tokens: int
    # Not in the chapter's params: tuning knobs with sane defaults, overridable if you need them.
    request_timeout: float
    embeddings_wait_seconds: float
    reasoning_effort: str

    @classmethod
    def from_env(cls) -> Settings:
        return cls(
            openai_base_url=os.environ.get(
                "OPENAI_BASE_URL",
                "http://vllm.ch19-pipelines.svc.cluster.local:8000/v1",
            ),
            # vLLM/Ollama ignore the key, but the OpenAI client refuses to start without one.
            openai_api_key=os.environ.get("OPENAI_API_KEY", "not-needed"),
            chat_model=os.environ.get("CHAT_MODEL", "ch19-model"),
            embeddings_url=os.environ.get(
                "EMBEDDINGS_URL", "http://tei.ch19-pipelines.svc.cluster.local:8080"
            ),
            docs_dir=Path(os.environ.get("DOCS_DIR", "/opt/app/docs")),
            disable_thinking=env_bool("DISABLE_THINKING", "true"),
            top_k=int(os.environ.get("TOP_K", "4")),
            max_tokens=int(os.environ.get("MAX_TOKENS", "512")),
            request_timeout=float(os.environ.get("REQUEST_TIMEOUT", "120")),
            embeddings_wait_seconds=float(
                os.environ.get("EMBEDDINGS_WAIT_SECONDS", "600")
            ),
            reasoning_effort=os.environ.get("REASONING_EFFORT", "").strip(),
        )


# ---------------------------------------------------------------------------------------------
# Embeddings: TEI over HTTP
# ---------------------------------------------------------------------------------------------
# Why not langchain_huggingface.HuggingFaceEndpointEmbeddings(model=EMBEDDINGS_URL)?
# In langchain-huggingface 1.2.2 its `validate_environment` validator raises
# "`model` must be a HuggingFace repo ID, not a URL." for any http(s):// value, so it can no
# longer point at a self-hosted TEI Service. Under the hood it only wrapped
# huggingface_hub.InferenceClient.feature_extraction anyway, which we call directly here.
# Re-evaluate if a later langchain-huggingface release accepts endpoint URLs again.
#
# What goes over the wire (huggingface_hub 1.32.0, TEI 1.9.4 -- both verified from source):
# InferenceClient(model=<URL>) routes to the "hf-inference" provider, which POSTs to the URL
# itself, i.e. `POST http://tei...:8080/` with body {"inputs": [...], "truncate": true}.
# For an embedding model TEI's router maps `POST /` to the same handler as `POST /embed` and
# answers with [[float, ...], ...] (L2-normalized by default).
# TEI's --max-client-batch-size default; larger requests get HTTP 413.
TEI_MAX_CLIENT_BATCH = 32


class TEIEmbeddings(Embeddings):
    """LangChain Embeddings that call a TEI server through huggingface_hub's InferenceClient."""

    def __init__(
        self, url: str, batch_size: int = TEI_MAX_CLIENT_BATCH, timeout: float = 60
    ):
        self.url = url.rstrip("/")
        self.batch_size = batch_size
        self.client = InferenceClient(model=self.url, timeout=timeout)

    def embed_documents(self, texts: list[str]) -> list[list[float]]:
        vectors: list[list[float]] = []
        for start in range(0, len(texts), self.batch_size):
            batch = texts[start : start + self.batch_size]
            # truncate=True: bge-small has a 512-token window. TEI 1.9 already auto-truncates by
            # default, but being explicit keeps a server started with --auto-truncate=false
            # from rejecting a long chunk with HTTP 413.
            arr = self.client.feature_extraction(batch, truncate=True)
            # feature_extraction returns a float32 ndarray of shape (len(batch), dim) for a list
            # input. Check the shape so a server misconfiguration (e.g. a token-level model that
            # returns (batch, tokens, dim)) fails loudly here instead of breaking retrieval quietly.
            if arr.ndim != 2 or arr.shape[0] != len(batch):
                raise ValueError(
                    f"TEI at {self.url} returned shape {arr.shape}, expected ({len(batch)}, dim)"
                )
            vectors.extend(arr.tolist())
        return vectors

    def embed_query(self, text: str) -> list[float]:
        return self.embed_documents([text])[0]


def wait_for_embeddings(embeddings: TEIEmbeddings, max_wait_seconds: float) -> None:
    """Block until TEI answers a real embedding request, with capped exponential backoff.

    The TEI pod downloads bge-small and warms up on start, so right after `kubectl apply` (or a
    spot reclaim that moved both pods) the Service exists but connections are refused or answered
    with 503 for a while. Retrying here instead of crashing avoids a CrashLoopBackOff whose own
    back-off (up to 5 min) would delay readiness far longer than TEI actually needs.
    """
    deadline = time.monotonic() + max_wait_seconds
    delay, attempt = 2.0, 0
    while True:
        attempt += 1
        try:
            dim = len(embeddings.embed_query("readiness probe"))
            log.info(
                "TEI at %s is up (attempt %d, embedding dim %d)",
                embeddings.url,
                attempt,
                dim,
            )
            return
        # Connection refused, 503 while loading, DNS not ready yet, ...
        except Exception as exc:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError(
                    f"TEI at {embeddings.url} not reachable after {max_wait_seconds:.0f}s: {exc}"
                ) from exc
            log.warning(
                "TEI at %s not ready (attempt %d): %s: %s -- retrying in %.0fs",
                embeddings.url,
                attempt,
                type(exc).__name__,
                str(exc)[:200],
                min(delay, remaining),
            )
            time.sleep(min(delay, remaining))
            delay = min(delay * 2, 30.0)


# ---------------------------------------------------------------------------------------------
# Corpus -> vector store
# ---------------------------------------------------------------------------------------------
def load_documents(docs_dir: Path) -> list[Document]:
    # A ConfigMap volume holds the real files under a hidden `..<timestamp>/` dir with top-level
    # symlinks to them. The top-level glob only sees the symlinks, so each doc is read once.
    paths = sorted(p for p in docs_dir.glob("*.md") if p.is_file())
    if not paths:
        raise FileNotFoundError(f"no *.md files in DOCS_DIR={docs_dir}")
    return [
        Document(
            page_content=p.read_text(encoding="utf-8"), metadata={"source": p.name}
        )
        for p in paths
    ]


def build_vector_store(settings: Settings) -> InMemoryVectorStore:
    """Load, chunk and embed DOCS_DIR into an in-process vector store (rebuilt on every start).

    In-memory is deliberate for a lab-sized corpus: no extra database to run, and the index is
    rebuilt in a second or two from the ConfigMap. The trade-off: every replica embeds the corpus
    on startup, and nothing persists. A real corpus belongs in pgvector/Qdrant/OpenSearch.
    """
    docs = load_documents(settings.docs_dir)
    # Markdown-aware separators split on headings first, then paragraphs. ~800 characters
    # (~200 tokens) per chunk sits well inside bge-small's 512-token window.
    splitter = RecursiveCharacterTextSplitter.from_language(
        Language.MARKDOWN, chunk_size=800, chunk_overlap=100
    )
    chunks = splitter.split_documents(docs)
    log.info(
        "loaded %d docs from %s -> %d chunks", len(docs), settings.docs_dir, len(chunks)
    )

    embeddings = TEIEmbeddings(
        settings.embeddings_url, timeout=settings.request_timeout
    )
    wait_for_embeddings(embeddings, settings.embeddings_wait_seconds)

    store = InMemoryVectorStore(embedding=embeddings)
    store.add_documents(chunks)
    log.info("indexed %d chunks into InMemoryVectorStore", len(chunks))
    return store


# ---------------------------------------------------------------------------------------------
# LLM + chains
# ---------------------------------------------------------------------------------------------
def build_llm(settings: Settings) -> ChatOpenAI:
    """An OpenAI-compatible chat client aimed at vLLM (GPU) or Ollama (cpu-lab)."""
    extra_body: dict = {
        # langchain-openai 1.6 sends the limit as `max_completion_tokens`. vLLM honours that, but
        # Ollama's OpenAI endpoint reads only `max_tokens`, so repeat it for portability.
        "max_tokens": settings.max_tokens,
    }
    if settings.disable_thinking:
        # Qwen3 "thinks" (<think>...</think>) before answering by default, which burns the token
        # budget and latency. vLLM forwards chat_template_kwargs to the chat template, where
        # enable_thinking=False switches it off. Servers that don't know the field ignore it.
        extra_body["chat_template_kwargs"] = {"enable_thinking": False}
    if settings.reasoning_effort:
        # Opt-in, for Ollama (cpu-lab sets REASONING_EFFORT=none). Ollama's OpenAI endpoint
        # drops chat_template_kwargs and turns thinking ON by default for qwen3. Its only
        # off-switch on /v1 is `reasoning_effort: "none"` (mapped to Think=false). Without
        # it, qwen3:0.6b can spend all of MAX_TOKENS reasoning and return an empty answer.
        # Leave it unset for vLLM: its ChatCompletionRequest validates reasoning_effort.
        # VERIFY: whether vLLM v0.29 accepts "none" (believed to allow only low|medium|high).
        extra_body["reasoning_effort"] = settings.reasoning_effort
    return ChatOpenAI(
        model=settings.chat_model,
        base_url=settings.openai_base_url,
        api_key=settings.openai_api_key,
        max_tokens=settings.max_tokens,
        temperature=0.2,  # grounded Q&A: little creativity wanted
        timeout=settings.request_timeout,
        max_retries=2,  # the OpenAI SDK's own backoff on connection errors / 429 / 5xx
        extra_body=extra_body,
    )


_THINK_BLOCK = re.compile(r"<think>.*?</think>", re.DOTALL)


def strip_think(text: str) -> str:
    """Remove Qwen3 reasoning from an answer, even if enable_thinking was not honoured.

    Cases handled: a complete <think>...</think> block (server ignored chat_template_kwargs, e.g.
    Ollama); a dangling </think> whose opening tag the chat template already emitted in the
    prompt; and an unterminated <think> (the model ran out of max_tokens mid-thought).
    """
    text = _THINK_BLOCK.sub("", text)
    if "</think>" in text:
        text = text.rsplit("</think>", 1)[1]
    if "<think>" in text:
        text = text.split("<think>", 1)[0]
    return text.strip()


RAG_PROMPT = ChatPromptTemplate.from_messages(
    [
        (
            "system",
            (
                "You are a support assistant for a Kubernetes AI platform course. Answer the "
                "question using ONLY the context below. If the context does not contain the "
                "answer, say you don't know. Be concise and mention the relevant Kubernetes "
                "objects or flags.\n\nContext:\n{context}"
            ),
        ),
        ("human", "{question}"),
    ]
)

CHAT_PROMPT = ChatPromptTemplate.from_messages(
    [
        ("system", "You are a concise, helpful assistant for platform engineers."),
        ("human", "{question}"),
    ]
)


def format_docs(docs: list[Document]) -> str:
    return "\n\n".join(
        f"[{d.metadata.get('source', '?')}]\n{d.page_content}" for d in docs
    )


def build_rag_chain(retriever: BaseRetriever, llm: BaseChatModel) -> Runnable:
    """{"question": str} -> {"question": str, "docs": [Document], "answer": str}.

    The retrieved docs are kept in the output (instead of being hidden inside the prompt) so
    callers can return them as sources, which is how you debug a bad RAG answer.
    """
    answer = (
        RunnablePassthrough.assign(context=lambda x: format_docs(x["docs"]))
        | RAG_PROMPT
        | llm
        | StrOutputParser()
        | RunnableLambda(strip_think)
    )
    return RunnableParallel(
        docs=itemgetter("question") | retriever,
        question=itemgetter("question"),
    ).assign(answer=answer)


def build_chat_chain(llm: BaseChatModel) -> Runnable:
    """{"question": str} -> str. Same LLM, no retrieval: the baseline to compare RAG against."""
    return CHAT_PROMPT | llm | StrOutputParser() | RunnableLambda(strip_think)


def sources_of(docs: list[Document]) -> list[str]:
    """Unique source file names, in retrieval-rank order."""
    return list(dict.fromkeys(d.metadata.get("source", "?") for d in docs))


def configure_logging() -> None:
    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    # httpx (huggingface_hub) and httpx2 (openai SDK 3.x) log every request at INFO: one line per
    # embedding batch / LLM call would drown the useful lines.
    for noisy in ("httpx", "httpx2"):
        logging.getLogger(noisy).setLevel(logging.WARNING)
