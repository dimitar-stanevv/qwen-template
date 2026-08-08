#!/usr/bin/env python3
"""
Copy the bundled workflows into ComfyUI's user workflow folder so they show up
in the sidebar, and retarget them at whichever checkpoint was actually
downloaded (plus that version's recommended sampler/scheduler).

Existing files are left alone unless --force is passed, so your edits survive
a pod restart.

Usage: install_workflows.py <repo_workflows_dir> <comfy_user_workflows_dir> <primary_variant> [--force]
"""

from __future__ import annotations

import json
import shutil
import sys
from pathlib import Path

# Phr00t's per-version sampler guidance, from the model card.
SAMPLER_BY_VERSION = {
    "v19": ("er_sde", "beta"),
    "v20": ("euler_ancestral", "beta"),
    "v21": ("euler_ancestral", "beta"),
    "v22": ("euler_ancestral", "beta"),
    "v23": ("euler_ancestral", "beta"),
}

CHECKPOINT_BY_VARIANT = {
    "v23-sfw": "Qwen-Rapid-AIO-SFW-v23.safetensors",
    "v23-nsfw": "Qwen-Rapid-AIO-NSFW-v23.safetensors",
    "v22-sfw": "Qwen-Rapid-AIO-SFW-v22.safetensors",
    "v22-nsfw": "Qwen-Rapid-AIO-NSFW-v22.safetensors",
    "v21-sfw": "Qwen-Rapid-AIO-SFW-v21.safetensors",
    "v21-nsfw": "Qwen-Rapid-AIO-NSFW-v21.safetensors",
    "v20-sfw": "Qwen-Rapid-AIO-SFW-v20.safetensors",
    "v20-nsfw": "Qwen-Rapid-AIO-NSFW-v20.safetensors",
    "v19-sfw": "Qwen-Rapid-AIO-SFW-v19.safetensors",
    "v19-nsfw": "Qwen-Rapid-AIO-NSFW-v19.safetensors",
}


def log(msg: str) -> None:
    print(f"\033[1;34m[qwen]\033[0m {msg}", flush=True)


def dim(msg: str) -> None:
    print(f"\033[2m       {msg}\033[0m", flush=True)


def retarget(doc: dict, ckpt: str, sampler: str, scheduler: str) -> dict:
    for node in doc.get("nodes", []):
        ntype = node.get("type")
        widgets = node.get("widgets_values")
        if not isinstance(widgets, list) or not widgets:
            continue
        if ntype == "CheckpointLoaderSimple":
            widgets[0] = ckpt
        elif ntype == "KSampler" and len(widgets) >= 6:
            # [seed, control_after_generate, steps, cfg, sampler_name, scheduler, denoise]
            widgets[4] = sampler
            widgets[5] = scheduler
    return doc


def main(argv: list[str]) -> int:
    force = "--force" in argv
    argv = [a for a in argv if a != "--force"]
    if len(argv) < 3:
        print(__doc__)
        return 1

    src_dir, dst_dir, variant = Path(argv[0]), Path(argv[1]), argv[2]

    ckpt = CHECKPOINT_BY_VARIANT.get(variant)
    if ckpt is None:
        dim(f"unknown variant '{variant}' — leaving workflow checkpoint names as-is")
        ckpt = ""
    version = variant.split("-")[0]
    sampler, scheduler = SAMPLER_BY_VERSION.get(version, ("euler_ancestral", "beta"))

    dst_dir.mkdir(parents=True, exist_ok=True)
    installed = 0

    for src in sorted(src_dir.glob("*.json")):
        if src.name.endswith(".upstream.json"):
            continue  # reference copy, not meant for the sidebar
        dst = dst_dir / src.name
        if dst.exists() and not force:
            dim(f"{src.name} already in the sidebar — not overwriting your edits")
            continue
        doc = json.loads(src.read_text())
        if ckpt:
            doc = retarget(doc, ckpt, sampler, scheduler)
        dst.write_text(json.dumps(doc, indent=2))
        installed += 1

    # The reference workflow goes in untouched, for comparing against the model card.
    upstream = src_dir / "qwen-rapid-aio.upstream.json"
    if upstream.exists() and (force or not (dst_dir / upstream.name).exists()):
        shutil.copy2(upstream, dst_dir / upstream.name)

    if installed:
        log(f"installed {installed} workflow(s) → {dst_dir}")
        if ckpt:
            dim(f"pointed at {ckpt} with {sampler}/{scheduler}")
    else:
        dim("workflows already present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
