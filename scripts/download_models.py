#!/usr/bin/env python3
"""
Download Qwen-Image-Edit-Rapid-AIO checkpoints into ComfyUI's checkpoints folder.

Every build is ~28.4 GB, so this script is deliberately careful:
  * skips a file that is already present at the right size (idempotent restarts)
  * refuses to start if the volume does not have room
  * resumes interrupted transfers
  * verifies the final size against the Hub's metadata

Usage:  download_models.py <dest_dir> <variant> [variant ...]
        download_models.py --list
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

# variant key -> path inside the Hugging Face repo
VARIANTS: dict[str, str] = {
    "v23-sfw": "v23/Qwen-Rapid-AIO-SFW-v23.safetensors",
    "v23-nsfw": "v23/Qwen-Rapid-AIO-NSFW-v23.safetensors",
    "v22-sfw": "v22/Qwen-Rapid-AIO-SFW-v22.safetensors",
    "v22-nsfw": "v22/Qwen-Rapid-AIO-NSFW-v22.safetensors",
    "v21-sfw": "v21/Qwen-Rapid-AIO-SFW-v21.safetensors",
    "v21-nsfw": "v21/Qwen-Rapid-AIO-NSFW-v21.safetensors",
    "v20-sfw": "v20/Qwen-Rapid-AIO-SFW-v20.safetensors",
    "v20-nsfw": "v20/Qwen-Rapid-AIO-NSFW-v20.safetensors",
    "v19-sfw": "v19/Qwen-Rapid-AIO-SFW-v19.safetensors",
    "v19-nsfw": "v19/Qwen-Rapid-AIO-NSFW-v19.safetensors",
}

NOTES = {
    "v23-sfw": "best prompt adherence — recommended default",
    "v19-sfw": "best edit consistency (subjects keep their identity)",
}

REPO_ID = os.environ.get("HF_REPO", "Phr00t/Qwen-Image-Edit-Rapid-AIO")


def human(n: float) -> str:
    # Decimal units, to match how Hugging Face reports file sizes.
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1000 or unit == "TB":
            return f"{n:.1f} {unit}"
        n /= 1000
    return f"{n:.1f} TB"


def log(msg: str) -> None:
    print(f"\033[1;34m[qwen]\033[0m {msg}", flush=True)


def warn(msg: str) -> None:
    print(f"\033[1;33m[qwen] WARN\033[0m {msg}", file=sys.stderr, flush=True)


def die(msg: str) -> None:
    print(f"\033[1;31m[qwen] ERROR\033[0m {msg}", file=sys.stderr, flush=True)
    raise SystemExit(1)


def list_variants() -> None:
    print("Available checkpoints (each ~28.4 GB):\n")
    for key, rel in VARIANTS.items():
        note = NOTES.get(key, "")
        print(f"  {key:<10} {rel:<44} {note}")
    print("\nSet MODELS to a comma-separated list, e.g.  MODELS=v23-sfw,v19-sfw")


def remote_size(api_url_filename: str) -> int | None:
    from huggingface_hub import get_hf_file_metadata, hf_hub_url

    try:
        meta = get_hf_file_metadata(
            hf_hub_url(REPO_ID, api_url_filename), token=os.environ.get("HF_TOKEN") or None
        )
        return meta.size
    except Exception as exc:  # network hiccup shouldn't be fatal
        warn(f"could not read remote size for {api_url_filename}: {exc}")
        return None


def download_one(dest_dir: Path, key: str) -> Path:
    from huggingface_hub import hf_hub_download

    rel = VARIANTS[key]
    flat_name = Path(rel).name
    final = dest_dir / flat_name

    expected = remote_size(rel)

    if final.exists():
        actual = final.stat().st_size
        if expected is None or actual == expected:
            log(f"{flat_name} already present ({human(actual)}) — skipping")
            return final
        warn(
            f"{flat_name} is {human(actual)} but the Hub says {human(expected)}; "
            "re-downloading (previous attempt was probably interrupted)"
        )
        final.unlink()

    if expected:
        free = shutil.disk_usage(dest_dir).free
        # Staging copy + final move can transiently need ~2x on some filesystems.
        if free < expected * 1.15:
            die(
                f"only {human(free)} free on {dest_dir}, need ~{human(expected * 1.15)} "
                f"for {flat_name}. Grow the RunPod network volume (100 GB recommended)."
            )

    stage = dest_dir / ".hf-staging"
    stage.mkdir(parents=True, exist_ok=True)

    log(f"downloading {rel} ({human(expected) if expected else 'unknown size'}) …")
    path = hf_hub_download(
        repo_id=REPO_ID,
        filename=rel,
        local_dir=str(stage),
        token=os.environ.get("HF_TOKEN") or None,
    )

    shutil.move(path, final)
    shutil.rmtree(stage / ".cache", ignore_errors=True)
    for leftover in sorted(stage.glob("*"), reverse=True):
        if leftover.is_dir() and not any(leftover.iterdir()):
            leftover.rmdir()
    if stage.exists() and not any(stage.iterdir()):
        stage.rmdir()

    actual = final.stat().st_size
    if expected and actual != expected:
        die(f"{flat_name} finished at {human(actual)} but should be {human(expected)}")
    log(f"{flat_name} ready ({human(actual)})")
    return final


def main(argv: list[str]) -> int:
    if not argv or argv[0] in ("--list", "-l"):
        list_variants()
        return 0

    dest_dir = Path(argv[0])
    keys = argv[1:]
    if not keys:
        die("no checkpoint variants requested")

    unknown = [k for k in keys if k not in VARIANTS]
    if unknown:
        warn(f"unknown variant(s): {', '.join(unknown)}")
        list_variants()
        return 1

    dest_dir.mkdir(parents=True, exist_ok=True)

    # hf_transfer gives a large speedup on RunPod's fat pipes; harmless if absent.
    os.environ.setdefault("HF_HUB_ENABLE_HF_TRANSFER", "1")
    try:
        import hf_transfer  # noqa: F401
    except ImportError:
        os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "0"

    if not os.environ.get("HF_TOKEN"):
        # The repo is public, so this works — but authenticated requests get
        # higher rate limits and Xet-accelerated transfer, which is worth having
        # on a 28 GB file.
        print(
            "\033[2m       no HF_TOKEN set — works fine (public repo), but a token "
            "makes this download noticeably faster\033[0m",
            flush=True,
        )

    for key in keys:
        download_one(dest_dir, key)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
