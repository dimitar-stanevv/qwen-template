#!/usr/bin/env bash
# One-shot setup for an EXISTING RunPod pod (any CUDA/PyTorch image).
# No Docker build, no registry — clone and run.
#
#   git clone https://github.com/dimitar-stanevv/qwen-template.git /workspace/qwen-template
#   cd /workspace/qwen-template && ./bootstrap.sh
#
# Everything lands under /workspace so it survives pod restarts.

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/dimitar-stanevv/qwen-template.git}"
CHECKOUT="${CHECKOUT:-/workspace/qwen-template}"

# Allow `curl ... | bash` by self-cloning when we are not already in a checkout.
if [[ ! -f "$(dirname "${BASH_SOURCE[0]}")/scripts/provision.sh" ]]; then
  echo "[qwen] fetching template into $CHECKOUT"
  if [[ -d "$CHECKOUT/.git" ]]; then
    git -C "$CHECKOUT" pull --ff-only
  else
    git clone "$REPO_URL" "$CHECKOUT"
  fi
  exec bash "$CHECKOUT/bootstrap.sh" "$@"
fi

cd "$(dirname "${BASH_SOURCE[0]}")"

if ! command -v git >/dev/null || ! python3 -c "import venv" >/dev/null 2>&1; then
  echo "[qwen] installing git + python3-venv"
  apt-get update -qq && apt-get install -y -qq git python3-venv >/dev/null
fi

# Load ./.env if the user made one (RunPod env vars still win).
if [[ -f .env ]]; then
  echo "[qwen] loading .env"
  set -a; source .env; set +a
fi

exec bash ./scripts/start.sh "$@"
