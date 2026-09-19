"""Chapter 19 - optionally publish the merged model to the Hugging Face Hub.

Runs as the last (conditional) step of the `hf-finetune-pipeline` Argo WorkflowTemplate:
    python /app/publish_hf.py

Env
  MODEL_PATH    merged model dir ($RUN_DIR/model, must carry _COMPLETE)   (required)
  HF_PUSH_REPO  e.g. your-user/ch19-qwen3-0.6b-sft; empty = do nothing
  HF_TOKEN      a WRITE token (Secret hf-token); required when HF_PUSH_REPO is set
  HF_PRIVATE    create the repo private unless set to "false" (default true);
                has no effect on a repo that already exists.

The workflow already skips this step when hf-push-repo is empty; the no-op here keeps
the script safe to run by hand too. Reading from the bucket mount is plain sequential
reads, so no scratch copy is needed on the way out.
"""

import os
import sys
from pathlib import Path

from huggingface_hub import HfApi
from store import MARKER, is_complete


def main() -> None:
    repo_id = os.environ.get("HF_PUSH_REPO", "").strip()
    if not repo_id:
        print("[publish] HF_PUSH_REPO is empty; not publishing", flush=True)
        return

    model_path = Path(os.environ["MODEL_PATH"])
    token = os.environ.get("HF_TOKEN", "").strip()
    private = os.environ.get("HF_PRIVATE", "true").strip().lower() != "false"
    if not token:
        sys.exit("HF_TOKEN (write scope) is required to publish")
    if not is_complete(model_path):
        sys.exit(f"{model_path} has no {MARKER}; refusing to publish a partial model")

    api = HfApi(token=token)
    url = api.create_repo(repo_id, repo_type="model", private=private, exist_ok=True)
    print(f"[publish] uploading {model_path} -> {url} (private={private})", flush=True)
    commit = api.upload_folder(
        repo_id=repo_id,
        repo_type="model",
        folder_path=model_path,
        ignore_patterns=[MARKER, ".cache/*"],
        commit_message=f"Upload fine-tuned model from {model_path}",
    )
    print(f"[publish] done: {commit.commit_url}", flush=True)


if __name__ == "__main__":
    main()
