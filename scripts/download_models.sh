#!/usr/bin/env bash
# Convenience wrapper: fetch extra checkpoints onto a pod that is already set up.
#
#   ./scripts/download_models.sh --list
#   MODELS=v19-sfw,v23-nsfw ./scripts/download_models.sh
#   ./scripts/download_models.sh v19-sfw

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ "${1:-}" == "--list" || "${1:-}" == "-l" ]]; then
  vpython "$REPO_DIR/scripts/download_models.py" --list
  exit 0
fi

if [[ $# -gt 0 ]]; then
  MODEL_LIST=("$@")
else
  IFS=',' read -r -a MODEL_LIST <<< "$MODELS"
fi

vpython "$REPO_DIR/scripts/download_models.py" \
  "$COMFY_DATA/models/checkpoints" "${MODEL_LIST[@]}"

ok "restart ComfyUI (or hit Refresh twice) before the new file shows in the loader dropdown"
